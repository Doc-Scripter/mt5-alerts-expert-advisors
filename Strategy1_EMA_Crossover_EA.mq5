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
#include "include/TrendDetection.mqh"
#include "include/TradeExecution.mqh"
#include "include/RiskManagement.mqh"





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
//| Update indicator values                                           |
//+------------------------------------------------------------------+
bool UpdateIndicators()
{
   // Update EMA and draw it
   if(!UpdateEMAValues(4))
      return false;
   
   // Draw EMA line - only once per bar
   static datetime lastEmaDrawTime = 0;
   datetime currentTime = TimeCurrent();
   
   if(lastEmaDrawTime != currentTime)
   {
      DrawEMALine();
      lastEmaDrawTime = currentTime;
   }
   
   if(Use_Trend_Filter)
   {
      ArraySetAsSeries(trendFastEmaValues, true);
      ArraySetAsSeries(trendMediumEmaValues, true);
      ArraySetAsSeries(trendSlowEmaValues, true);
      ArraySetAsSeries(trendAdxValues, true);
      
      if(CopyBuffer(trendFastEmaHandle, 0, 0, 5, trendFastEmaValues) < 5 ||
         CopyBuffer(trendMediumEmaHandle, 0, 0, 5, trendMediumEmaValues) < 5 ||
         CopyBuffer(trendSlowEmaHandle, 0, 0, 5, trendSlowEmaValues) < 5 ||
         CopyBuffer(trendAdxHandle, 0, 0, 5, trendAdxValues) < 5)
      {
         Print("Failed to copy trend filter values");
         return false;
      }
      
      // We're not drawing trend filter EMAs - only using them for calculations
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
      // Check for engulfing pattern on any bar after crossover
      if(g_lastEmaCrossAbove)
      {
         // Check for bullish engulfing on the current completed bar
         for(int i = 1; i <= g_crossoverBar; i++)  // Check all bars up to the crossover bar
         {
            if(IsEngulfing(i, true, Use_Trend_Filter))
            {
               // Check for no more than one swing low
               if(CountSwingPoints(5, true) <= 1)
               {
                  if(Use_Trend_Filter && GetTrendState() != TREND_BULLISH) 
                  {
                     Print("Trend filter detected non-bullish trend, but executing trade anyway");
                     // Continue with trade execution instead of returning
                  }
                  
                  double close1 = iClose(_Symbol, PERIOD_CURRENT, i);
                  // Place stop loss at the lowest point of the engulfing candle
                  double stopLoss = iLow(_Symbol, PERIOD_CURRENT, i);
                  double takeProfit = close1 + ((close1 - stopLoss) * 1.5);
                  
                  Print("Bullish engulfing found at bar ", i, " after crossover at bar ", g_crossoverBar);
                  Print("Stop loss placed at the lowest point of engulfing candle: ", stopLoss);
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
      }
      else // Bearish crossover
      {
         // Check for bearish engulfing on the current completed bar
         for(int i = 1; i <= g_crossoverBar; i++)  // Check all bars up to the crossover bar
         {
            if(IsEngulfing(i, false, Use_Trend_Filter))
            {
               // Check for no more than one swing high
               if(CountSwingPoints(5, false) <= 1)
               {
                  if(Use_Trend_Filter && GetTrendState() != TREND_BEARISH)
                  {
                     Print("Trend filter detected non-bearish trend, but executing trade anyway");
                     // Continue with trade execution instead of returning
                  }
                  
                  double close1 = iClose(_Symbol, PERIOD_CURRENT, i);
                  // Place stop loss at the highest point of the engulfing candle
                  double stopLoss = iHigh(_Symbol, PERIOD_CURRENT, i);
                  double takeProfit = close1 - ((stopLoss - close1) * 1.5);
                  
                  Print("Bearish engulfing found at bar ", i, " after crossover at bar ", g_crossoverBar);
                  Print("Stop loss placed at the highest point of engulfing candle: ", stopLoss);
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
      }
      
      // If we've reached this point, we didn't find a valid engulfing pattern on this bar
      // Increment the bar counter to track how many bars since crossover
      g_crossoverBar++;
      
      // No limit on how many bars to check after crossover
      // The crossover will remain valid until a trade is executed or the EA is stopped
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
//| Count swing points since EMA crossover                            |
//+------------------------------------------------------------------+
int CountSwingPoints(int lookback, bool isBullish)
{
   // Use the crossover bar as the starting point for swing detection
   int barsToCheck = (g_crossoverBar > 0) ? g_crossoverBar + 5 : lookback;
   
   if(barsToCheck < 3) barsToCheck = 3; // Need at least 3 bars to detect a swing
   
   // Reduced logging - only log the essential information
   Print("INFO: Checking swing points - ", (isBullish ? "Bullish" : "Bearish"), " setup");
   
   double highs[], lows[], emaValues[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);
   ArraySetAsSeries(emaValues, true);
   
   // Copy price data and EMA values
   if(CopyHigh(_Symbol, PERIOD_CURRENT, 0, barsToCheck, highs) != barsToCheck ||
      CopyLow(_Symbol, PERIOD_CURRENT, 0, barsToCheck, lows) != barsToCheck)
   {
      Print("ERROR: Failed to copy price data for swing detection");
      return 999; // Return a high number to prevent trade
   }
   
   // Make sure we have enough EMA values
   if(ArraySize(g_ema.values) < barsToCheck)
   {
      if(!UpdateEMAValues(barsToCheck))
      {
         Print("ERROR: Failed to update EMA values for swing detection");
         return 999; // Return a high number to prevent trade
      }
   }
   
   // Copy EMA values to local array for easier access
   ArrayResize(emaValues, barsToCheck);
   for(int i = 0; i < barsToCheck && i < ArraySize(g_ema.values); i++)
   {
      emaValues[i] = g_ema.values[i];
   }
   
   // Clear any existing swing point markers
   ObjectsDeleteAll(0, "SwingPoint_");
   
   // IMPORTANT FIX: Only check for swing points between current bar and crossover bar
   int startBar = 1;  // Current completed bar
   int endBar = g_crossoverBar;  // The bar where crossover occurred
   
   // First, identify all swing points
   double swingHighs[], swingLows[];
   datetime swingHighTimes[], swingLowTimes[];
   int swingHighCount = 0, swingLowCount = 0;
   
   // Find all swing lows
   for(int i = startBar; i <= endBar; i++)
   {
      // Skip if we don't have enough bars to check neighbors
      if(i <= 0 || i >= barsToCheck - 1) continue;
      
      // Check if this is a swing low (lower than both neighbors)
      if(lows[i] < lows[i-1] && lows[i] < lows[i+1])
      {
         // Add to swing lows array
         ArrayResize(swingLows, swingLowCount + 1);
         ArrayResize(swingLowTimes, swingLowCount + 1);
         swingLows[swingLowCount] = lows[i];
         swingLowTimes[swingLowCount] = iTime(_Symbol, PERIOD_CURRENT, i);
         swingLowCount++;
         
         // Mark the swing low on the chart
         string objName = "SwingPoint_Low_" + IntegerToString(i);
         datetime time = iTime(_Symbol, PERIOD_CURRENT, i);
         
         // Check if the swing low is below the EMA
         bool isBelowEMA = (lows[i] < emaValues[i]);
         
         // Use different colors based on position relative to EMA
         color swingColor = isBelowEMA ? clrRed : clrOrange;
         
         ObjectCreate(0, objName, OBJ_ARROW_DOWN, 0, time, lows[i]);
         ObjectSetInteger(0, objName, OBJPROP_COLOR, swingColor);
         ObjectSetInteger(0, objName, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
      }
   }
   
   // Find all swing highs
   for(int i = startBar; i <= endBar; i++)
   {
      // Skip if we don't have enough bars to check neighbors
      if(i <= 0 || i >= barsToCheck - 1) continue;
      
      // Check if this is a swing high (higher than both neighbors)
      if(highs[i] > highs[i-1] && highs[i] > highs[i+1])
      {
         // Add to swing highs array
         ArrayResize(swingHighs, swingHighCount + 1);
         ArrayResize(swingHighTimes, swingHighCount + 1);
         swingHighs[swingHighCount] = highs[i];
         swingHighTimes[swingHighCount] = iTime(_Symbol, PERIOD_CURRENT, i);
         swingHighCount++;
         
         // Mark the swing high on the chart
         string objName = "SwingPoint_High_" + IntegerToString(i);
         datetime time = iTime(_Symbol, PERIOD_CURRENT, i);
         
         // Check if the swing high is above the EMA
         bool isAboveEMA = (highs[i] > emaValues[i]);
         
         // Use different colors based on position relative to EMA
         color swingColor = isAboveEMA ? clrBlue : clrAqua;
         
         ObjectCreate(0, objName, OBJ_ARROW_UP, 0, time, highs[i]);
         ObjectSetInteger(0, objName, OBJPROP_COLOR, swingColor);
         ObjectSetInteger(0, objName, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
      }
   }
   
   // Now check if any swing points have been broken
   bool swingBroken = false;
   
   // CORRECTED LOGIC:
   // For bullish setup, check if any swing HIGH has been broken (price goes higher than a swing high)
   if(isBullish && swingHighCount > 0)
   {
      for(int i = 0; i < swingHighCount; i++)
      {
         // Find the bar index for this swing high
         datetime swingTime = swingHighTimes[i];
         double swingPrice = swingHighs[i];
         
         // Check all bars after this swing high
         for(int j = startBar; j < endBar; j++)
         {
            datetime barTime = iTime(_Symbol, PERIOD_CURRENT, j);
            
            // Only check bars that come after this swing high
            if(barTime <= swingTime) continue;
            
            // If any bar's high is above the swing high, the swing is broken
            if(highs[j] > swingPrice)
            {
               swingBroken = true;
               Print("INFO: Bullish swing high at ", TimeToString(swingTime), " (", swingPrice, ") broken by bar at ", 
                     TimeToString(barTime), " with high of ", highs[j]);
               
               // Mark the broken swing
               string objName = "BrokenSwing_" + IntegerToString(j);
               ObjectCreate(0, objName, OBJ_ARROW_CHECK, 0, barTime, highs[j] + 10 * _Point);
               ObjectSetInteger(0, objName, OBJPROP_COLOR, clrMagenta);
               ObjectSetInteger(0, objName, OBJPROP_WIDTH, 3);
               ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
               
               break;
            }
         }
         
         if(swingBroken) break;
      }
   }
   // For bearish setup, check if any swing LOW has been broken (price goes lower than a swing low)
   else if(!isBullish && swingLowCount > 0)
   {
      for(int i = 0; i < swingLowCount; i++)
      {
         // Find the bar index for this swing low
         datetime swingTime = swingLowTimes[i];
         double swingPrice = swingLows[i];
         
         // Check all bars after this swing low
         for(int j = startBar; j < endBar; j++)
         {
            datetime barTime = iTime(_Symbol, PERIOD_CURRENT, j);
            
            // Only check bars that come after this swing low
            if(barTime <= swingTime) continue;
            
            // If any bar's low is below the swing low, the swing is broken
            if(lows[j] < swingPrice)
            {
               swingBroken = true;
               Print("INFO: Bearish swing low at ", TimeToString(swingTime), " (", swingPrice, ") broken by bar at ", 
                     TimeToString(barTime), " with low of ", lows[j]);
               
               // Mark the broken swing
               string objName = "BrokenSwing_" + IntegerToString(j);
               ObjectCreate(0, objName, OBJ_ARROW_CHECK, 0, barTime, lows[j] - 10 * _Point);
               ObjectSetInteger(0, objName, OBJPROP_COLOR, clrMagenta);
               ObjectSetInteger(0, objName, OBJPROP_WIDTH, 3);
               ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
               
               break;
            }
         }
         
         if(swingBroken) break;
      }
   }
   
   // If any swing was broken, reset the count to 0
   if(swingBroken)
   {
      Print("INFO: Swing point broken - resetting count to 0");
      return 0;
   }
   
   // If no swings were broken, count valid swing points
   int validSwingCount = 0;
   
   // Count valid swing lows for bullish setup
   if(isBullish)
   {
      for(int i = 0; i < swingLowCount; i++)
      {
         // Find the bar index for this swing low
         datetime swingTime = swingLowTimes[i];
         int barIndex = iBarShift(_Symbol, PERIOD_CURRENT, swingTime);
         
         // Check if this swing low is below the EMA
         if(barIndex >= 0 && barIndex < ArraySize(emaValues) && swingLows[i] < emaValues[barIndex])
         {
            validSwingCount++;
         }
      }
   }
   // Count valid swing highs for bearish setup
   else
   {
      for(int i = 0; i < swingHighCount; i++)
      {
         // Find the bar index for this swing high
         datetime swingTime = swingHighTimes[i];
         int barIndex = iBarShift(_Symbol, PERIOD_CURRENT, swingTime);
         
         // Check if this swing high is above the EMA
         if(barIndex >= 0 && barIndex < ArraySize(emaValues) && swingHighs[i] > emaValues[barIndex])
         {
            validSwingCount++;
         }
      }
   }
   
   Print("INFO: Total valid swing points: ", validSwingCount);
   return validSwingCount;
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
