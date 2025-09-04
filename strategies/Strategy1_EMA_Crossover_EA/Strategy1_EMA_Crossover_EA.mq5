//+------------------------------------------------------------------+
//|                                     Strategy1_EMA_Crossover_EA.mq5 |
//|                                                                    |
//|              EMA Crossover Strategy with Engulfing Confirmation    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023"
#property link      ""
#property version   "1.00"
#property strict

#include "../../include/CommonPatternDetection.mqh"
#include "../../include/TrendDetection.mqh"
#include "../../include/TradeExecution.mqh"
#include "../../include/RiskManagement.mqh"
#include "IndicatorManagement.mqh"
#include "StrategyLogic.mqh"
#include "SwingAnalysis.mqh"
#include "LotSizing.mqh"
#include "PriceStructure.mqh"
#include "PatternMarking.mqh"
#include "BreakevenManagement.mqh"





// Lot Sizing Modes
enum ENUM_LOT_SIZING_MODE
{
   DYNAMIC_MARGIN_CHECK, // Try input lot, fallback to min lot if margin fails
   ALWAYS_MINIMUM_LOT    // Always use the minimum allowed lot size
};

// Input parameters
input double      Lot_Size = 1.0;     // Entry lot size (used if LotSizing_Mode=DYNAMIC_MARGIN_CHECK)
input bool        Use_Trend_Filter = false;   // Enable/Disable the main Trend Filter
input ENUM_LOT_SIZING_MODE LotSizing_Mode = DYNAMIC_MARGIN_CHECK; // Lot sizing strategy
input int         BreakevenTriggerPips = 0; // Pips in profit to trigger breakeven (0=disabled)
input bool        Use_Breakeven_Logic = true; // Enable/Disable automatic breakeven adjustment
input int         Historical_Candles = 100;  // Number of historical candles to check for engulfing patterns

// Global variables
long barCount;
double volMin, volMax, volStep;
double g_lastEmaCrossPrice = 0.0;
bool g_lastEmaCrossAbove = false;
datetime g_lastTradeTime = 0;
int g_crossoverBar = -1;  // Bar index when crossover occurred (-1 means no crossover)

// Trend Filter Handles & Buffers
int trendFastEmaHandle;
int trendSlowEmaHandle;
int trendMediumEmaHandle;
int trendAdxHandle;
double trendFastEmaValues[];
double trendSlowEmaValues[];
double trendMediumEmaValues[];
double trendAdxValues[];

// Constants
#define STRATEGY_COOLDOWN_MINUTES 60

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   // Check if automated trading is allowed
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   {
      Print("Automated trading is not allowed. Please enable it in MetaTrader 5.");
      return(INIT_FAILED);
   }
   
   // Check if trading is allowed for the symbol
   if(!SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_FULL)
   {
      Print("Trading is not allowed for ", _Symbol);
      return(INIT_FAILED);
   }
   
   // Get symbol volume constraints
   volMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   volMax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   volStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   if(volMin <= 0 || volMax <= 0 || volStep <= 0)
   {
      Print("Failed to get valid volume constraints for ", _Symbol);
      return(INIT_FAILED); 
   }
   
   // Initialize EMA indicator
   if(!InitializeEMA())
      return(INIT_FAILED);
   
   // Initialize barCount and crossover tracking
   barCount = Bars(_Symbol, PERIOD_CURRENT);
   Print("Total available bars: ", barCount);
   g_crossoverBar = -1;
   
   // Clear any existing swing point markers
   ObjectsDeleteAll(0, "SwingPoint_");
   
   // Initialize trend filter indicators
   if(Use_Trend_Filter)
   {
      trendFastEmaHandle = iMA(_Symbol, PERIOD_CURRENT, 8, 0, MODE_EMA, PRICE_CLOSE);
      trendMediumEmaHandle = iMA(_Symbol, PERIOD_CURRENT, 21, 0, MODE_EMA, PRICE_CLOSE);
      trendSlowEmaHandle = iMA(_Symbol, PERIOD_CURRENT, 50, 0, MODE_EMA, PRICE_CLOSE);
      trendAdxHandle = iADX(_Symbol, PERIOD_CURRENT, 14);
      
      if(trendFastEmaHandle == INVALID_HANDLE || 
         trendMediumEmaHandle == INVALID_HANDLE ||
         trendSlowEmaHandle == INVALID_HANDLE || 
         trendAdxHandle == INVALID_HANDLE)
      {
         Print("Failed to create trend filter indicator handles");
         return(INIT_FAILED);
      }
   }
   
   // Start the timer for breakeven checks
   if(Use_Breakeven_Logic && BreakevenTriggerPips > 0)
   {
      EventSetTimer(1);
   }
   
   // Calculate how many bars we can actually process
   int maxBars = MathMin(Historical_Candles, barCount - 10);
   if(maxBars <= 0)
   {
      Print("Warning: Not enough historical data available for pattern detection");
      // Continue initialization anyway, we'll mark patterns when data becomes available
   }
   else
   {
      // Update EMA values for historical analysis - use available bars
      if(!UpdateEMAValues(maxBars + 5))  // Add a few extra bars for calculations
      {
         Print("Warning: Could not update all EMA values, will use available data");
         // Continue anyway with whatever data we have
      }
      
      // Mark engulfing patterns on historical candles
      MarkHistoricalEngulfingPatterns(maxBars);
   }
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ReleaseEMA();
   
   // Clean up any pattern markers when EA is removed
   ObjectsDeleteAll(0, "EngulfPattern_");
   ObjectsDeleteAll(0, "SwingPoint_");
      
   if(Use_Trend_Filter)
   {
      if(trendFastEmaHandle != INVALID_HANDLE)
         IndicatorRelease(trendFastEmaHandle);
      if(trendMediumEmaHandle != INVALID_HANDLE)
         IndicatorRelease(trendMediumEmaHandle);
      if(trendSlowEmaHandle != INVALID_HANDLE)
         IndicatorRelease(trendSlowEmaHandle);
      if(trendAdxHandle != INVALID_HANDLE)
         IndicatorRelease(trendAdxHandle);
   }
   
   EventKillTimer();
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for new bar
   int currentBars = Bars(_Symbol, PERIOD_CURRENT);
   if(currentBars == barCount) return;
   barCount = currentBars;
   
   // Update indicators
   if(!UpdateIndicators()) return;
   
   // Check strategy conditions
   CheckStrategy();
}

//+------------------------------------------------------------------+
//| Timer function for breakeven management                          |
//+------------------------------------------------------------------+
void OnTimer()
{
   OnTimerBreakeven();
}
