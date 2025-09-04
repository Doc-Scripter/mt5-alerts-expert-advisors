//+------------------------------------------------------------------+
//|                                     Strategy1_EMA_Crossover_EA.mq5 |
//|                                                                    |
//|          EMA Crossover Alert System with Engulfing Confirmation   |
//|                    Sends alerts to phone/email instead of trading |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023"
#property link      ""
#property version   "1.00"
#property strict

#include "../../include/CommonPatternDetection.mqh"
#include "../../include/TrendDetection.mqh"
#include "IndicatorManagement.mqh"
#include "StrategyLogic.mqh"
#include "SwingAnalysis.mqh"
#include "PriceStructure.mqh"
#include "PatternMarking.mqh"
#include "AlertSystem.mqh"





// Lot Sizing Modes
enum ENUM_LOT_SIZING_MODE
{
   DYNAMIC_MARGIN_CHECK, // Try input lot, fallback to min lot if margin fails
   ALWAYS_MINIMUM_LOT    // Always use the minimum allowed lot size
};

// Input parameters
input bool        Use_Trend_Filter = false;   // Enable/Disable the main Trend Filter
input int         Historical_Candles = 100;  // Number of historical candles to check for engulfing patterns

// Alert Settings
input bool        Enable_Alerts = true;       // Enable/Disable alerts
input bool        Send_Push_Notifications = true; // Send push notifications to mobile
input bool        Send_Email_Alerts = false;  // Send email alerts
input bool        Play_Sound_Alert = true;    // Play sound when signal occurs
input string      Alert_Sound_File = "alert.wav"; // Sound file for alerts
input bool        Show_Chart_Alert = true;    // Show alert dialog on chart
input int         Alert_Cooldown_Minutes = 5; // Minutes between same type alerts

// Global variables
long barCount;
double g_lastEmaCrossPrice = 0.0;
bool g_lastEmaCrossAbove = false;
datetime g_lastAlertTime = 0;
int g_crossoverBar = -1;  // Bar index when crossover occurred (-1 means no crossover)

// Alert tracking variables
datetime g_lastBullishAlertTime = 0;
datetime g_lastBearishAlertTime = 0;

// Trend Filter Handles & Buffers
int trendFastEmaHandle;
int trendSlowEmaHandle;
int trendMediumEmaHandle;
int trendAdxHandle;
double trendFastEmaValues[];
double trendSlowEmaValues[];
double trendMediumEmaValues[];
double trendAdxValues[];


//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("Strategy1 Alert System - Initializing...");
   
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
   
   // Calculate how many bars we can actually process
   int maxBars = MathMin(Historical_Candles, (int)(barCount - 10));
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
   
   Print("Strategy1 Alert System - Ready to send alerts!");
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

