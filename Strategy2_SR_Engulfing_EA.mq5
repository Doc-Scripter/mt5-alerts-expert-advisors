//+------------------------------------------------------------------+
//|                                    Strategy2_SR_Engulfing_EA.mq5   |
//|                                                                    |
//|                 Support/Resistance Engulfing Strategy              |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023"
#property link      ""
#property version   "1.00"
#property strict

// Strategy-specific Magic Number
#define MAGIC_NUMBER 222222

// Trend States
#define TREND_BULLISH 1
#define TREND_BEARISH -1
#define TREND_RANGING 0

// Lot Sizing Modes
enum ENUM_LOT_SIZING_MODE
{
   DYNAMIC_MARGIN_CHECK, // Try input lot, fallback to min lot if margin fails
   ALWAYS_MINIMUM_LOT    // Always use the minimum allowed lot size
};

// Input Parameters
input double      Lot_Size = 1.0;     // Entry lot size (used if LotSizing_Mode=DYNAMIC_MARGIN_CHECK)
input bool        Use_Trend_Filter = false;   // Enable/Disable the main Trend Filter
input ENUM_LOT_SIZING_MODE LotSizing_Mode = DYNAMIC_MARGIN_CHECK; // Lot sizing strategy
input int         SR_Lookback = 20;    // Number of candles to look back for S/R zones
input int         SR_Sensitivity_Pips = 3; // Min distance between S/R zone defining closes
input int         SR_Min_Touches = 2;   // Minimum touches required for a zone to be tradable
input int         BreakevenTriggerPips = 0; // Pips in profit to trigger breakeven (0=disabled)
input bool        Use_Breakeven_Logic = true; // Enable/Disable automatic breakeven adjustment

#include "include/CommonPatternDetection.mqh"
#include "include/Support_Resistance_Zones.mqh"

// Global Variables
long barCount;
double volMin, volMax, volStep;
datetime g_lastTradeTime = 0;

// Trend Filter Handles & Buffers
int trendFastEmaHandle;
int trendSlowEmaHandle;
int trendAdxHandle;
double trendFastEmaValues[];
double trendSlowEmaValues[];
double trendAdxValues[];

// Constants
#define STRATEGY_COOLDOWN_MINUTES 60
#define SHIFT_TO_CHECK 1  // Candlestick shift to check for patterns

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("OnInit: Starting initialization...");
   
   // Check if automated trading is allowed
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   {
      Print("OnInit: Automated trading is not allowed. Please enable it in MetaTrader 5.");
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
   Print("OnInit: Initializing EMA indicator...");
   if(!InitializeEMA())
   {
      Print("OnInit: Failed to initialize EMA indicator");
      return(INIT_FAILED);
   }
   
   // Initialize barCount
   barCount = Bars(_Symbol, PERIOD_CURRENT);
   Print("OnInit: Initial bar count is ", barCount);
   
   // Initialize trend filter indicators
   if(Use_Trend_Filter)
   {
      Print("OnInit: Initializing trend filter indicators...");
      
      Print("OnInit: Creating Fast EMA indicator...");
      trendFastEmaHandle = iMA(_Symbol, PERIOD_CURRENT, 20, 0, MODE_EMA, PRICE_CLOSE);
      
      Print("OnInit: Creating Slow EMA indicator...");
      trendSlowEmaHandle = iMA(_Symbol, PERIOD_CURRENT, 50, 0, MODE_EMA, PRICE_CLOSE);
      
      Print("OnInit: Creating ADX indicator...");
      trendAdxHandle = iADX(_Symbol, PERIOD_CURRENT, 14);
      
      if(trendFastEmaHandle == INVALID_HANDLE || 
         trendSlowEmaHandle == INVALID_HANDLE || 
         trendAdxHandle == INVALID_HANDLE)
      {
         Print("OnInit: Failed to create trend filter indicators. Handles: Fast EMA=", trendFastEmaHandle,
               ", Slow EMA=", trendSlowEmaHandle, ", ADX=", trendAdxHandle);
         return(INIT_FAILED);
      }
      
      Print("OnInit: Successfully created trend filter indicators");
   }
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{   
   Print("OnDeinit: Starting cleanup with reason code ", reason);
   
   // Release EMA indicator
   Print("OnDeinit: Releasing EMA indicator...");
   ReleaseEMA();
   
   // Release trend indicators only if they were created
   if(Use_Trend_Filter)
   {
      Print("OnDeinit: Releasing trend filter indicators...");
      if(trendFastEmaHandle != INVALID_HANDLE)
      {
         IndicatorRelease(trendFastEmaHandle);
         trendFastEmaHandle = INVALID_HANDLE;
      }
      if(trendSlowEmaHandle != INVALID_HANDLE)
      {
         IndicatorRelease(trendSlowEmaHandle);
         trendSlowEmaHandle = INVALID_HANDLE;
      }
      if(trendAdxHandle != INVALID_HANDLE)
      {
         IndicatorRelease(trendAdxHandle);
         trendAdxHandle = INVALID_HANDLE;
      }
   }
   
   Print("OnDeinit: Cleaning up S/R zone lines...");
   DeleteAllSRZoneLines();
   
   Print("OnDeinit: Killing timer...");
   EventKillTimer();
   
   Print("OnDeinit: Cleanup complete");
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
   
   // Update S/R zones with input parameters
   UpdateAndDrawValidSRZones(SR_Lookback, SR_Sensitivity_Pips);
   
   // Check strategy conditions
   CheckStrategy();
}

//+------------------------------------------------------------------+
//| Update indicator values                                           |
//+------------------------------------------------------------------+
bool UpdateIndicators()
{
   Print("UpdateIndicators: Starting update...");
   
   // Update EMA and draw it
   int barsNeeded = SHIFT_TO_CHECK + 4;
   Print("UpdateIndicators: Requesting ", barsNeeded, " bars for EMA");
   
   if(!UpdateEMAValues(barsNeeded))
   {
      Print("UpdateIndicators: Failed to update EMA values");
      return false;
   }
   
   Print("UpdateIndicators: Drawing EMA line");
   DrawEMALine();
   
   if(Use_Trend_Filter)
   {
      Print("UpdateIndicators: Updating trend filter indicators");
      
      // Initialize trend filter arrays with proper size
      int requiredBars = SHIFT_TO_CHECK + 4;
      Print("UpdateIndicators: Resizing trend arrays for ", requiredBars, " bars");
      
      ArrayResize(trendFastEmaValues, requiredBars);
      ArrayResize(trendSlowEmaValues, requiredBars);
      ArrayResize(trendAdxValues, requiredBars);
      
      ArraySetAsSeries(trendFastEmaValues, true);
      ArraySetAsSeries(trendSlowEmaValues, true);
      ArraySetAsSeries(trendAdxValues, true);
      
      if(CopyBuffer(trendFastEmaHandle, 0, 0, requiredBars, trendFastEmaValues) < requiredBars ||
         CopyBuffer(trendSlowEmaHandle, 0, 0, requiredBars, trendSlowEmaValues) < requiredBars ||
         CopyBuffer(trendAdxHandle, 0, 0, requiredBars, trendAdxValues) < requiredBars)
      {
         Print("Failed to copy trend filter values");
         return false;
      }
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check strategy conditions                                         |
//+------------------------------------------------------------------+
void CheckStrategy()
{
   // Check cooldown
   if(IsStrategyOnCooldown()) return;
   
   // Verify we have enough data
   if(ArraySize(g_ema.values) <= SHIFT_TO_CHECK + 3)
   {
      Print("CheckStrategy: Insufficient EMA data");
      return;
   }
   
   double closePrice = iClose(_Symbol, PERIOD_CURRENT, SHIFT_TO_CHECK);
   if(closePrice == 0)
   {
      Print("CheckStrategy: Invalid close price");
      return;
   }
   
   // Check bullish engulfing at support
   bool isBullishEngulfing = IsEngulfing(SHIFT_TO_CHECK, true, Use_Trend_Filter);
   if(isBullishEngulfing && g_nearestSupportZoneIndex != -1 && 
      g_nearestSupportZoneIndex < ArraySize(g_activeSupportZones))
   {
      SRZone nearestSupport = g_activeSupportZones[g_nearestSupportZoneIndex];
      
      bool engulfingCloseInZone = (closePrice >= nearestSupport.bottomBoundary && 
                                  closePrice <= nearestSupport.topBoundary);
                                  
      bool priceBelowEMARecently = false;
      for(int i = SHIFT_TO_CHECK + 1; i <= SHIFT_TO_CHECK + 3; i++)
      {
         double close = iClose(_Symbol, PERIOD_CURRENT, i);
         if(ArraySize(g_ema.values) > i && close < g_ema.values[i])
         {
            priceBelowEMARecently = true;
            break;
         }
      }
      
      bool minTouchesMet = (nearestSupport.touchCount >= SR_Min_Touches);
      
      if(engulfingCloseInZone && priceBelowEMARecently && minTouchesMet)
      {
         if(Use_Trend_Filter && GetTrendState() != TREND_BULLISH)
            return;
            
         double stopLoss = nearestSupport.bottomBoundary;
         double takeProfit = closePrice + ((closePrice - stopLoss) * 1.5);
         
         ExecuteTrade(true, stopLoss, takeProfit);
         return;
      }
   }
   
   // Check bearish engulfing at resistance
   bool isBearishEngulfing = IsEngulfing(SHIFT_TO_CHECK, false, Use_Trend_Filter);
   if(isBearishEngulfing && g_nearestResistanceZoneIndex != -1 &&
      g_nearestResistanceZoneIndex < ArraySize(g_activeResistanceZones))
   {
      SRZone nearestResistance = g_activeResistanceZones[g_nearestResistanceZoneIndex];
      
      bool engulfingCloseInZone = (closePrice >= nearestResistance.bottomBoundary && 
                                  closePrice <= nearestResistance.topBoundary);
                                  
      bool priceAboveEMARecently = false;
      for(int i = SHIFT_TO_CHECK + 1; i <= SHIFT_TO_CHECK + 3; i++)
      {
         double close = iClose(_Symbol, PERIOD_CURRENT, i);
         if(ArraySize(g_ema.values) > i && close > g_ema.values[i])
         {
            priceAboveEMARecently = true;
            break;
         }
      }
      
      bool minTouchesMet = (nearestResistance.touchCount >= SR_Min_Touches);
      
      if(engulfingCloseInZone && priceAboveEMARecently && minTouchesMet)
      {
         if(Use_Trend_Filter && GetTrendState() != TREND_BEARISH)
            return;
            
         double stopLoss = nearestResistance.topBoundary;
         double takeProfit = closePrice - ((stopLoss - closePrice) * 1.5);
         
         ExecuteTrade(false, stopLoss, takeProfit);
      }
   }
}

//+------------------------------------------------------------------+
//| Execute trade                                                     |
//+------------------------------------------------------------------+
void ExecuteTrade(bool isBuy, double stopLoss, double takeProfit)
{
   double lotSize = GetLotSize();
   if(lotSize <= 0) return;
   
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lotSize;
   request.type = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   request.price = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   request.sl = stopLoss;
   request.tp = takeProfit;
   request.deviation = 10;
   request.magic = MAGIC_NUMBER;
   request.comment = "Strategy 2 " + (isBuy ? "Buy" : "Sell");
   
   if(!OrderSend(request, result))
   {
      Print("OrderSend failed with error: ", GetLastError());
      return;
   }
   
   if(result.retcode == TRADE_RETCODE_DONE)
   {
      g_lastTradeTime = TimeCurrent();
      Print("Trade executed successfully. Ticket: ", result.order);
   }
}

//+------------------------------------------------------------------+
//| Get appropriate lot size based on mode and margin                 |
//+------------------------------------------------------------------+
double GetLotSize()
{
   double lotSize = LotSizing_Mode == ALWAYS_MINIMUM_LOT ? volMin : Lot_Size;
   lotSize = MathMax(lotSize, volMin);
   lotSize = MathMin(lotSize, volMax);
   
   double marginRequired;
   if(!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lotSize, SymbolInfoDouble(_Symbol, SYMBOL_ASK), marginRequired))
   {
      Print("Error calculating margin. Error code: ", GetLastError());
      return 0;
   }
   
   if(marginRequired > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
   {
      if(LotSizing_Mode == DYNAMIC_MARGIN_CHECK)
      {
         lotSize = volMin;
         if(!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lotSize, SymbolInfoDouble(_Symbol, SYMBOL_ASK), marginRequired))
         {
            Print("Error calculating margin for minimum lot size. Error code: ", GetLastError());
            return 0;
         }
         
         if(marginRequired > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
         {
            Print("Insufficient margin even for minimum lot size");
            return 0;
         }
      }
      else
      {
         Print("Insufficient margin for desired lot size");
         return 0;
      }
   }
   
   return lotSize;
}

//+------------------------------------------------------------------+
//| Check if strategy is on cooldown                                  |
//+------------------------------------------------------------------+
bool IsStrategyOnCooldown()
{
   if(g_lastTradeTime == 0) return false;
   
   datetime currentTime = TimeCurrent();
   if(currentTime - g_lastTradeTime < STRATEGY_COOLDOWN_MINUTES * 60)
      return true;
      
   return false;
}

//+------------------------------------------------------------------+
//| Get current trend state                                          |
//+------------------------------------------------------------------+
int GetTrendState()
{
   Print("GetTrendState: Checking trend state...");
   
   if(!Use_Trend_Filter)
   {
      Print("GetTrendState: Trend filter disabled, returning RANGING");
      return TREND_RANGING;
   }
   
   int fastSize = ArraySize(trendFastEmaValues);
   int slowSize = ArraySize(trendSlowEmaValues);
   int adxSize = ArraySize(trendAdxValues);
   
   Print("GetTrendState: Array sizes - Fast EMA: ", fastSize,
         ", Slow EMA: ", slowSize, ", ADX: ", adxSize);
   
   if(fastSize == 0 || slowSize == 0 || adxSize == 0)
   {
      Print("GetTrendState: Missing indicator data, returning RANGING");
      return TREND_RANGING;
   }
   
   double fastEMA = trendFastEmaValues[0];
   double slowEMA = trendSlowEmaValues[0];
   double adxValue = trendAdxValues[0];
   
   bool isStrong = (adxValue > 25.0);
   bool isBullish = (fastEMA > slowEMA);
   
   Print("GetTrendState: Values - Fast EMA: ", fastEMA,
         ", Slow EMA: ", slowEMA, ", ADX: ", adxValue,
         " (Strong: ", isStrong, ", Bullish: ", isBullish, ")");
   
   if(isStrong && isBullish)
   {
      Print("GetTrendState: Strong bullish trend detected");
      return TREND_BULLISH;
   }
   if(isStrong && !isBullish)
   {
      Print("GetTrendState: Strong bearish trend detected");
      return TREND_BEARISH;
   }
   
   Print("GetTrendState: No strong trend detected, returning RANGING");
   return TREND_RANGING;
}


//+------------------------------------------------------------------+
//| Timer function for breakeven management                          |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(!Use_Breakeven_Logic || BreakevenTriggerPips <= 0) return;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
         PositionGetInteger(POSITION_MAGIC) != MAGIC_NUMBER)
         continue;
         
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      
      if(MathAbs(currentSL - openPrice) < _Point) continue;
      
      bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double currentPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      double profitPips = isBuy ? (currentPrice - openPrice) / _Point :
                                 (openPrice - currentPrice) / _Point;
                                 
      if(profitPips >= BreakevenTriggerPips)
      {
         MqlTradeRequest request = {};
         MqlTradeResult result = {};
         
         request.action = TRADE_ACTION_SLTP;
         request.position = ticket;
         request.sl = openPrice;
         request.tp = PositionGetDouble(POSITION_TP);
         
         if(!OrderSend(request, result))
            Print("Failed to modify position to breakeven. Error: ", GetLastError());
      }
   }
}
