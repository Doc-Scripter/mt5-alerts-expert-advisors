//+------------------------------------------------------------------+
//|                                     Strategy1_EMA_Crossover_EA.mq5 |
//|                                                                    |
//|              EMA Crossover Strategy with Engulfing Confirmation    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023"
#property link      ""
#property version   "1.00"
#property strict

#include "include/CommonPatternDetection.mqh"

// Strategy-specific Magic Number
#define MAGIC_NUMBER 111111

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
int trendAdxHandle;
double trendFastEmaValues[];
double trendSlowEmaValues[];
double trendAdxValues[];

// Constants
#define EMA_PERIOD 20
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
   
   // Initialize trend filter indicators
   if(Use_Trend_Filter)
   {
      trendFastEmaHandle = iMA(_Symbol, PERIOD_CURRENT, 20, 0, MODE_EMA, PRICE_CLOSE);
      trendSlowEmaHandle = iMA(_Symbol, PERIOD_CURRENT, 50, 0, MODE_EMA, PRICE_CLOSE);
      trendAdxHandle = iADX(_Symbol, PERIOD_CURRENT, 14);
      
      if(trendFastEmaHandle == INVALID_HANDLE || 
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
      
   if(Use_Trend_Filter)
   {
      if(trendFastEmaHandle != INVALID_HANDLE)
         IndicatorRelease(trendFastEmaHandle);
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
//| Update indicator values                                           |
//+------------------------------------------------------------------+
bool UpdateIndicators()
{
   // Update EMA and draw it
   if(!UpdateEMAValues(4))
      return false;
   
   DrawEMALine();
   
   if(Use_Trend_Filter)
   {
      ArraySetAsSeries(trendFastEmaValues, true);
      ArraySetAsSeries(trendSlowEmaValues, true);
      ArraySetAsSeries(trendAdxValues, true);
      
      if(CopyBuffer(trendFastEmaHandle, 0, 0, 3, trendFastEmaValues) < 3 ||
         CopyBuffer(trendSlowEmaHandle, 0, 0, 3, trendSlowEmaValues) < 3 ||
         CopyBuffer(trendAdxHandle, 0, 0, 3, trendAdxValues) < 3)
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
   
   // First, check if we already have a valid EMA crossover stored
   bool havePendingCrossover = (g_crossoverBar >= 0);
   
   // If we don't have a pending crossover, check for a new one on the previous bar
   if(!havePendingCrossover)
   {
      // Get prices for crossover detection
      double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
      double close2 = iClose(_Symbol, PERIOD_CURRENT, 2);
      
      // Check for bullish crossover (price crosses above EMA)
      if(close2 < g_ema.values[2] && close1 > g_ema.values[1])
      {
         g_lastEmaCrossPrice = close1;
         g_lastEmaCrossAbove = true;
         g_crossoverBar = 1;  // Crossover occurred at bar 1
         Print("Bullish EMA crossover detected at bar 1, price: ", g_lastEmaCrossPrice);
      }
      // Check for bearish crossover (price crosses below EMA)
      else if(close2 > g_ema.values[2] && close1 < g_ema.values[1])
      {
         g_lastEmaCrossPrice = close1;
         g_lastEmaCrossAbove = false;
         g_crossoverBar = 1;  // Crossover occurred at bar 1
         Print("Bearish EMA crossover detected at bar 1, price: ", g_lastEmaCrossPrice);
      }
   }
   
   // If we have a valid crossover (either stored or new), check for engulfing pattern
   if(g_crossoverBar >= 0)
   {
      // Check for engulfing pattern on the current completed bar (bar 1)
      if(g_lastEmaCrossAbove)
      {
         // Check for bullish engulfing
         if(IsEngulfing(1, true, Use_Trend_Filter))
         {
            // Check for no more than one swing low
            if(CountSwingPoints(5, true) <= 1)
            {
               if(Use_Trend_Filter && GetTrendState() != TREND_BULLISH) 
               {
                  Print("Trend filter rejected bullish trade");
                  return;
               }
               
               double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
               // Find swing low for better stop loss placement
               double swingLow = FindSwingLowBeforeCross(g_crossoverBar, 10);
               double stopLoss = swingLow > 0 ? swingLow - (10 * _Point) : iLow(_Symbol, PERIOD_CURRENT, 1) - (10 * _Point);
               double takeProfit = close1 + ((close1 - stopLoss) * 1.5);
               
               ExecuteTrade(true, stopLoss, takeProfit);
               
               // Reset crossover after trade execution
               g_crossoverBar = -1;
               g_lastEmaCrossPrice = 0.0;
               return;
            }
            else
            {
               Print("Too many swing points for bullish trade");
            }
         }
      }
      else // Bearish crossover
      {
         // Check for bearish engulfing
         if(IsEngulfing(1, false, Use_Trend_Filter))
         {
            // Check for no more than one swing high
            if(CountSwingPoints(5, false) <= 1)
            {
               if(Use_Trend_Filter && GetTrendState() != TREND_BEARISH)
               {
                  Print("Trend filter rejected bearish trade");
                  return;
               }
               
               double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
               // Find swing high for better stop loss placement
               double swingHigh = FindSwingHighBeforeCross(g_crossoverBar, 10);
               double stopLoss = swingHigh > 0 ? swingHigh + (10 * _Point) : iHigh(_Symbol, PERIOD_CURRENT, 1) + (10 * _Point);
               double takeProfit = close1 - ((stopLoss - close1) * 1.5);
               
               ExecuteTrade(false, stopLoss, takeProfit);
               
               // Reset crossover after trade execution
               g_crossoverBar = -1;
               g_lastEmaCrossPrice = 0.0;
               return;
            }
            else
            {
               Print("Too many swing points for bearish trade");
            }
         }
      }
      
      // If we've reached this point, we didn't find a valid engulfing pattern on this bar
      // Increment the bar counter to track how many bars since crossover
      g_crossoverBar++;
      
      // If it's been too many bars since the crossover, reset it
      if(g_crossoverBar > 5) {
         g_crossoverBar = -1;
         g_lastEmaCrossPrice = 0.0;
         Print("Resetting crossover - no valid setup found within 5 bars");
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
   request.comment = "Strategy 1 " + (isBuy ? "Buy" : "Sell");
   
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
//| Count swing points in recent bars                                 |
//+------------------------------------------------------------------+
int CountSwingPoints(int lookback, bool isBullish)
{
   if(lookback < 3) lookback = 3; // Need at least 3 bars to detect a swing
   
   double highs[], lows[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);
   
   if(CopyHigh(_Symbol, PERIOD_CURRENT, 0, lookback, highs) != lookback ||
      CopyLow(_Symbol, PERIOD_CURRENT, 0, lookback, lows) != lookback)
   {
      Print("Failed to copy price data for swing detection");
      return 999; // Return a high number to prevent trade
   }
   
   int swingCount = 0;
   
   if(isBullish)
   {
      // Count swing lows (local minima)
      for(int i = 1; i < lookback - 1; i++)
      {
         if(lows[i] < lows[i-1] && lows[i] < lows[i+1])
         {
            swingCount++;
            Print("Bullish swing low detected at bar ", i);
         }
      }
   }
   else
   {
      // Count swing highs (local maxima)
      for(int i = 1; i < lookback - 1; i++)
      {
         if(highs[i] > highs[i-1] && highs[i] > highs[i+1])
         {
            swingCount++;
            Print("Bearish swing high detected at bar ", i);
         }
      }
   }
   
   Print("Total swing points detected: ", swingCount);
   return swingCount;
}

//+------------------------------------------------------------------+
//| Find the most recent swing low before the EMA cross               |
//+------------------------------------------------------------------+
double FindSwingLowBeforeCross(int crossBarIndex, int maxLookback)
{
   if(maxLookback <= 0) maxLookback = 10;
   
   double lows[];
   ArraySetAsSeries(lows, true);
   
   // We need at least 3 bars before the cross and 1 after to identify a swing
   int requiredBars = crossBarIndex + maxLookback;
   
   if(CopyLow(_Symbol, PERIOD_CURRENT, 0, requiredBars, lows) != requiredBars)
   {
      Print("Failed to copy price data for swing low detection");
      return 0;
   }
   
   // Start from the bar of the crossover and look back
   for(int i = crossBarIndex; i < crossBarIndex + maxLookback - 2; i++)
   {
      // Check if this is a swing low (lower than both neighbors)
      if(lows[i] < lows[i-1] && lows[i] < lows[i+1])
      {
         Print("Found swing low at bar ", i, " with price ", lows[i]);
         return lows[i];
      }
   }
   
   // If no clear swing low is found, find the lowest low in the lookback period
   double lowestLow = lows[crossBarIndex];
   int lowestLowIndex = crossBarIndex;
   
   for(int i = crossBarIndex + 1; i < crossBarIndex + maxLookback; i++)
   {
      if(lows[i] < lowestLow)
      {
         lowestLow = lows[i];
         lowestLowIndex = i;
      }
   }
   
   Print("No clear swing low found, using lowest low at bar ", lowestLowIndex, " with price ", lowestLow);
   return lowestLow;
}

//+------------------------------------------------------------------+
//| Find the most recent swing high before the EMA cross              |
//+------------------------------------------------------------------+
double FindSwingHighBeforeCross(int crossBarIndex, int maxLookback)
{
   if(maxLookback <= 0) maxLookback = 10;
   
   double highs[];
   ArraySetAsSeries(highs, true);
   
   // We need at least 3 bars before the cross and 1 after to identify a swing
   int requiredBars = crossBarIndex + maxLookback;
   
   if(CopyHigh(_Symbol, PERIOD_CURRENT, 0, requiredBars, highs) != requiredBars)
   {
      Print("Failed to copy price data for swing high detection");
      return 0;
   }
   
   // Start from the bar of the crossover and look back
   for(int i = crossBarIndex; i < crossBarIndex + maxLookback - 2; i++)
   {
      // Check if this is a swing high (higher than both neighbors)
      if(highs[i] > highs[i-1] && highs[i] > highs[i+1])
      {
         Print("Found swing high at bar ", i, " with price ", highs[i]);
         return highs[i];
      }
   }
   
   // If no clear swing high is found, find the highest high in the lookback period
   double highestHigh = highs[crossBarIndex];
   int highestHighIndex = crossBarIndex;
   
   for(int i = crossBarIndex + 1; i < crossBarIndex + maxLookback; i++)
   {
      if(highs[i] > highestHigh)
      {
         highestHigh = highs[i];
         highestHighIndex = i;
      }
   }
   
   Print("No clear swing high found, using highest high at bar ", highestHighIndex, " with price ", highestHigh);
   return highestHigh;
}

//+------------------------------------------------------------------+
//| Get current trend state                                          |
//+------------------------------------------------------------------+
int GetTrendState()
{
   if(!Use_Trend_Filter) return TREND_RANGING;
   
   double fastEMA = trendFastEmaValues[0];
   double slowEMA = trendSlowEmaValues[0];
   double adxValue = trendAdxValues[0];
   
   bool isStrong = (adxValue > 25.0);
   bool isBullish = (fastEMA > slowEMA);
   
   if(isStrong && isBullish) return TREND_BULLISH;
   if(isStrong && !isBullish) return TREND_BEARISH;
   return TREND_RANGING;
}

//+------------------------------------------------------------------+
//| Check for valid price structure                                   |
//+------------------------------------------------------------------+
bool IsValidPriceStructure(int startBar, int endBar, bool isBullish)
{
   double highs[], lows[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);
   
   if(CopyHigh(_Symbol, PERIOD_CURRENT, 0, startBar + 1, highs) != startBar + 1 ||
      CopyLow(_Symbol, PERIOD_CURRENT, 0, startBar + 1, lows) != startBar + 1)
      return false;
      
   if(isBullish)
   {
      bool hadLowerLows = false;
      for(int i = startBar + 1; i < ArraySize(lows) - 1; i++)
      {
         if(lows[i] < lows[i-1])
         {
            hadLowerLows = true;
            break;
         }
      }
      
      if(!hadLowerLows) return false;
      
      double lowestLow = lows[startBar];
      double highestHigh = highs[startBar];
      
      for(int i = startBar-1; i >= endBar; i--)
      {
         if(highs[i] > highestHigh || lows[i] > lowestLow)
            return false;
      }
   }
   else
   {
      bool hadHigherHighs = false;
      for(int i = startBar + 1; i < ArraySize(highs) - 1; i++)
      {
         if(highs[i] > highs[i-1])
         {
            hadHigherHighs = true;
            break;
         }
      }
      
      if(!hadHigherHighs) return false;
      
      double highestLow = lows[startBar];
      double lowestHigh = highs[startBar];
      
      for(int i = startBar-1; i >= endBar; i--)
      {
         if(lows[i] < highestLow || highs[i] < lowestHigh)
            return false;
      }
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Mark engulfing patterns on historical candles                     |
//+------------------------------------------------------------------+
void MarkHistoricalEngulfingPatterns(int candles)
{
   Print("Starting historical engulfing pattern detection for the last ", candles, " candles");
   
   // Make sure we have enough bars
   int availableBars = Bars(_Symbol, PERIOD_CURRENT);
   if(candles > availableBars)
   {
      Print("Warning: Requested ", candles, " candles but only ", availableBars, " are available");
      candles = availableBars - 10;  // Leave some margin for calculations
   }
   
   if(candles <= 0)
   {
      Print("Error: Not enough historical data available");
      return;
   }
   
   // Clear any existing pattern markers
   ObjectsDeleteAll(0, "EngulfPattern_");
   
   int bullishCount = 0;
   int bearishCount = 0;
   
   // Scan historical candles for engulfing patterns
   for(int i = 1; i <= candles; i++)
   {
      // Check for bullish engulfing
      if(IsEngulfing(i, true, false))  // No trend filter for historical marking
      {
         bullishCount++;
         // Pattern is already drawn by IsEngulfing function
      }
      
      // Check for bearish engulfing
      if(IsEngulfing(i, false, false))  // No trend filter for historical marking
      {
         bearishCount++;
         // Pattern is already drawn by IsEngulfing function
      }
   }
   
   Print("Historical pattern detection complete. Found ", bullishCount, " bullish and ", bearishCount, " bearish engulfing patterns");
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
