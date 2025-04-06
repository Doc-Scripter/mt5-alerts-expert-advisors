//+------------------------------------------------------------------+
//|                                           EMA_Engulfing_EA.mq5    |
//|                                                                   |
//|                                                                   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023"
#property link      ""
#property version   "1.00"
#property strict

// Include spread check functionality
#include "include/SpreadCheck.mqh"

// Input parameters
input int         EMA_Period = 20;       // EMA period
input double      Lot_Size_1 = 0.01;     // First entry lot size
input double      Lot_Size_2 = 0.02;     // Second entry lot size
input double      RR_Ratio_1 = 1.7;      // Risk:Reward ratio for first target
input double      RR_Ratio_2 = 2.0;      // Risk:Reward ratio for second target
input int         Max_Spread = 180;      // Maximum spread for logging purposes only
input bool        Use_Strategy_1 = true; // Use EMA crossing + engulfing strategy
input bool        Use_Strategy_2 = true; // Use S/R engulfing strategy
input bool        Use_Strategy_3 = true; // Use breakout + EMA engulfing strategy
input bool        Use_Strategy_4 = true; // Use simple engulfing strategy
input int         SL_Buffer_Pips = 5;    // Additional buffer for stop loss in pips
input int         SR_Lookback = 50;       // Number of candles to look back for S/R levels
input int         SR_Strength = 3;        // Minimum number of touches for S/R level
input double      SR_Tolerance = 0.0005;   // Tolerance for S/R level detection
input int         SR_MinBars = 3;        // Minimum bars between S/R levels

// Global variables
int emaHandle;
double emaValues[];
int barCount;
ulong posTicket1 = 0;
ulong posTicket2 = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
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
   
   // Initialize EMA indicator
   emaHandle = iMA(_Symbol, PERIOD_CURRENT, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   
   if(emaHandle == INVALID_HANDLE)
   {
      Print("Failed to create EMA indicator handle");
      return(INIT_FAILED);
   }
   
   // Initialize barCount to track new bars
   barCount = Bars(_Symbol, PERIOD_CURRENT);
   
   // Display information about the current symbol
   Print("Symbol: ", _Symbol, ", Digits: ", _Digits, ", Point: ", _Point);
   Print("SPREAD LIMITING REMOVED: EA will trade regardless of spread conditions");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release indicator handle
   if(emaHandle != INVALID_HANDLE)
      IndicatorRelease(emaHandle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check if we have a new bar
   int currentBars = Bars(_Symbol, PERIOD_CURRENT);
   if(currentBars == barCount)
      return;  // No new bar, exit
      
   barCount = currentBars;
   
   // Update indicators
   if(!UpdateIndicators())
      return;
      
   // Check for open positions
   if(HasOpenPositions())
      return;
      
   // Log current spread for reference (but don't use it to limit trading)
   IsSpreadAcceptable(Max_Spread);
   
   // Reset comment
   Comment("");
      
   // Check strategy conditions
   if(Use_Strategy_1 && CheckStrategy1())
      return;
      
   if(Use_Strategy_2 && CheckStrategy2())
      return;
      
   if(Use_Strategy_3 && CheckStrategy3())
      return;
      
   if(Use_Strategy_4 && CheckStrategy4())
      return;
}

//+------------------------------------------------------------------+
//| Update indicator values                                          |
//+------------------------------------------------------------------+
bool UpdateIndicators()
{
   // Get EMA values for the last 3 bars
   ArraySetAsSeries(emaValues, true);
   if(CopyBuffer(emaHandle, 0, 0, 3, emaValues) < 3)
   {
      Print("Failed to copy EMA indicator values");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check if there are open positions for this symbol                |
//+------------------------------------------------------------------+
bool HasOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionSelectByTicket(PositionGetTicket(i)))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol)
            return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check if the current bar forms an engulfing pattern              |
//+------------------------------------------------------------------+
bool IsEngulfing(int shift, bool bullish)
{
   double open1 = iOpen(_Symbol, PERIOD_CURRENT, shift + 1);
   double close1 = iClose(_Symbol, PERIOD_CURRENT, shift + 1);
   double open2 = iOpen(_Symbol, PERIOD_CURRENT, shift);
   double close2 = iClose(_Symbol, PERIOD_CURRENT, shift);
   
   // Calculate price range for tolerance
   double range = MathAbs(open1 - close1);
   double tolerance = range * 0.2; // Increased to 20% of the previous candle's range
   
   // Add minimum tolerance to handle small ranges
   double minTolerance = 5 * _Point;
   tolerance = MathMax(tolerance, minTolerance);
   
   Print("Analyzing candles for engulfing pattern:");
   Print("  - Current Bar (", shift, "): Open=", open2, " Close=", close2);
   Print("  - Previous Bar (", shift + 1, "): Open=", open1, " Close=", close1);
   Print("  - Tolerance: ", tolerance);
   
   if(bullish) // Bullish engulfing
   {
      // More lenient condition for prior candle being bearish
      bool condition1 = (close1 <= open1 + tolerance); // Prior candle is bearish or doji
      bool condition2 = (close2 >= open2 - tolerance); // Current candle is bullish or doji
      bool condition3 = (open2 <= close1 + tolerance); // Current open is below or equal to prior close
      bool condition4 = (close2 > open1 - tolerance); // Current close is above prior open
      
      Print("Checking Bullish Engulfing Conditions:");
      Print("  - Prior Candle Bearish/Doji: ", condition1, " (Close: ", close1, " <= Open: ", open1 + tolerance, ")");
      Print("  - Current Candle Bullish/Doji: ", condition2, " (Close: ", close2, " >= Open: ", open2 - tolerance, ")");
      Print("  - Current Open <= Prior Close: ", condition3, " (", open2, " <= ", close1 + tolerance, ")");
      Print("  - Current Close > Prior Open: ", condition4, " (", close2, " > ", open1 - tolerance, ")");
      
      bool isEngulfing = condition1 && condition2 && condition3 && condition4;
      Print("  - All Conditions Met: ", isEngulfing);
      
      if(!isEngulfing)
      {
         Print("  - Failed Conditions:");
         if(!condition1) Print("    * Prior candle is not bearish or doji");
         if(!condition2) Print("    * Current candle is not bullish or doji");
         if(!condition3) Print("    * Current open is not below or equal to prior close");
         if(!condition4) Print("    * Current close is not above prior open");
      }
      
      return isEngulfing;
   }
   else // Bearish engulfing
   {
      // More lenient condition for prior candle being bullish
      bool condition1 = (close1 >= open1 - tolerance); // Prior candle is bullish or doji
      bool condition2 = (close2 <= open2 + tolerance); // Current candle is bearish or doji
      bool condition3 = (open2 >= close1 - tolerance); // Current open is above or equal to prior close
      bool condition4 = (close2 < open1 + tolerance); // Current close is below prior open
      
      Print("Checking Bearish Engulfing Conditions:");
      Print("  - Prior Candle Bullish/Doji: ", condition1, " (Close: ", close1, " >= Open: ", open1 - tolerance, ")");
      Print("  - Current Candle Bearish/Doji: ", condition2, " (Close: ", close2, " <= Open: ", open2 + tolerance, ")");
      Print("  - Current Open >= Prior Close: ", condition3, " (", open2, " >= ", close1 - tolerance, ")");
      Print("  - Current Close < Prior Open: ", condition4, " (", close2, " < ", open1 + tolerance, ")");
      
      bool isEngulfing = condition1 && condition2 && condition3 && condition4;
      Print("  - All Conditions Met: ", isEngulfing);
      
      if(!isEngulfing)
      {
         Print("  - Failed Conditions:");
         if(!condition1) Print("    * Prior candle is not bullish or doji");
         if(!condition2) Print("    * Current candle is not bearish or doji");
         if(!condition3) Print("    * Current open is not above or equal to prior close");
         if(!condition4) Print("    * Current close is not below prior open");
      }
      
      return isEngulfing;
   }
}

//+------------------------------------------------------------------+
//| Check if price crossed EMA                                       |
//+------------------------------------------------------------------+
bool CrossedEMA(int shift, bool upward)
{
   double close1 = iClose(_Symbol, PERIOD_CURRENT, shift + 1);
   double close0 = iClose(_Symbol, PERIOD_CURRENT, shift);
   
   if(upward)
      return close1 < emaValues[shift + 1] && close0 > emaValues[shift];
   else
      return close1 > emaValues[shift + 1] && close0 < emaValues[shift];
}

//+------------------------------------------------------------------+
//| Check if price stayed on one side of EMA                         |
//+------------------------------------------------------------------+
bool StayedOnSideOfEMA(int startBar, int bars, bool above)
{
   for(int i = startBar; i < startBar + bars; i++)
   {
      double close = iClose(_Symbol, PERIOD_CURRENT, i);
      
      if(above && close < emaValues[i])
         return false;
      
      if(!above && close > emaValues[i])
         return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check if the bar is a resistance level                           |
//+------------------------------------------------------------------+
bool IsResistanceLevel(int barIndex, double strength)
{
   double high = iHigh(_Symbol, PERIOD_CURRENT, barIndex);
   int count = 0;
   
   // Check if the high is a local maximum (relaxed condition)
   bool isLocalMax = true;
   for(int i = 1; i <= 3; i++)
   {
      if(barIndex + i < Bars(_Symbol, PERIOD_CURRENT) && 
         barIndex - i >= 0)
      {
         if(high <= iHigh(_Symbol, PERIOD_CURRENT, barIndex + i) ||
            high <= iHigh(_Symbol, PERIOD_CURRENT, barIndex - i))
         {
            isLocalMax = false;
            break;
         }
      }
   }
   
   if(isLocalMax)
   {
      // Count how many times price approached this level using percentage tolerance
      for(int i = 0; i < SR_Lookback; i++)
      {
         if(i == barIndex) continue; // Skip the current bar
         
         double barHigh = iHigh(_Symbol, PERIOD_CURRENT, i);
         double tolerance = high * (SR_Tolerance / 100.0);
         
         if(MathAbs(barHigh - high) <= tolerance)
            count++;
      }
   }
   
   return count >= strength;
}

//+------------------------------------------------------------------+
//| Check if the bar is a support level                              |
//+------------------------------------------------------------------+
bool IsSupportLevel(int barIndex, double strength)
{
   double low = iLow(_Symbol, PERIOD_CURRENT, barIndex);
   int count = 0;
   
   // Check if the low is a local minimum (relaxed condition)
   bool isLocalMin = true;
   for(int i = 1; i <= 3; i++)
   {
      if(barIndex + i < Bars(_Symbol, PERIOD_CURRENT) && 
         barIndex - i >= 0)
      {
         if(low >= iLow(_Symbol, PERIOD_CURRENT, barIndex + i) ||
            low >= iLow(_Symbol, PERIOD_CURRENT, barIndex - i))
         {
            isLocalMin = false;
            break;
         }
      }
   }
   
   if(isLocalMin)
   {
      // Count how many times price approached this level using percentage tolerance
      for(int i = 0; i < SR_Lookback; i++)
      {
         if(i == barIndex) continue; // Skip the current bar
         
         double barLow = iLow(_Symbol, PERIOD_CURRENT, i);
         double tolerance = low * (SR_Tolerance / 100.0);
         
         if(MathAbs(barLow - low) <= tolerance)
            count++;
      }
   }
   
   return count >= strength;
}

//+------------------------------------------------------------------+
//| Find nearest support/resistance level                            |
//+------------------------------------------------------------------+
double FindNearestSR(bool findResistance)
{
   double levels[];
   int levelCount = 0;
   datetime lastLevelTime = 0;
   
   // Look for potential S/R points in the lookback period
   for(int i = 1; i < SR_Lookback - 1; i++)
   {
      // Skip if too close to the last level
      datetime currentTime = iTime(_Symbol, PERIOD_CURRENT, i);
      if(lastLevelTime > 0 && (currentTime - lastLevelTime) < SR_MinBars * PeriodSeconds(PERIOD_CURRENT))
         continue;
      
      double high = iHigh(_Symbol, PERIOD_CURRENT, i);
      double low = iLow(_Symbol, PERIOD_CURRENT, i);
      
      if(findResistance)
      {
         if(IsResistanceLevel(i, SR_Strength))
         {
            ArrayResize(levels, levelCount + 1);
            levels[levelCount] = high;
            levelCount++;
            lastLevelTime = currentTime;
         }
      }
      else
      {
         if(IsSupportLevel(i, SR_Strength))
         {
            ArrayResize(levels, levelCount + 1);
            levels[levelCount] = low;
            levelCount++;
            lastLevelTime = currentTime;
         }
      }
   }
   
   // Find the nearest level to current price
   if(levelCount > 0)
   {
      double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double nearestLevel = levels[0];
      double minDistance = MathAbs(currentPrice - nearestLevel);
      
      for(int i = 1; i < levelCount; i++)
      {
         double distance = MathAbs(currentPrice - levels[i]);
         if(distance < minDistance)
         {
            minDistance = distance;
            nearestLevel = levels[i];
         }
      }
      
      return nearestLevel;
   }
   
   return 0; // No level found
}

//+------------------------------------------------------------------+
//| Check if price broke through resistance/support                  |
//+------------------------------------------------------------------+
bool BrokeLevel(int shift, double level, bool breakUp)
{
   double close = iClose(_Symbol, PERIOD_CURRENT, shift);
   double prevClose = iClose(_Symbol, PERIOD_CURRENT, shift + 1);
   
   if(breakUp)
      return prevClose < level && close > level;
   else
      return prevClose > level && close < level;
}

//+------------------------------------------------------------------+
//| Calculate take profit based on risk-reward ratio                 |
//+------------------------------------------------------------------+
double CalculateTakeProfit(bool isBuy, double entryPrice, double stopLoss, double rrRatio)
{
   if(isBuy)
      return entryPrice + (entryPrice - stopLoss) * rrRatio;
   else
      return entryPrice - (stopLoss - entryPrice) * rrRatio;
}

//+------------------------------------------------------------------+
//| Strategy 1: EMA crossing + engulfing without closing opposite    |
//+------------------------------------------------------------------+
bool CheckStrategy1()
{
   Print("Checking Strategy 1 conditions...");
   
   // Check for bullish setup
   if(CrossedEMA(1, true) && IsEngulfing(0, true) && StayedOnSideOfEMA(0, 3, true))
   {
      Print("Strategy 1 - Bullish conditions met:");
      Print("  - EMA crossed upward: ", CrossedEMA(1, true));
      Print("  - Bullish engulfing: ", IsEngulfing(0, true));
      Print("  - Price stayed above EMA: ", StayedOnSideOfEMA(0, 3, true));
      
      double resistance = FindNearestSR(true);
      if(resistance > 0)
      {
         Print("  - Found resistance level at: ", resistance);
         ExecuteTrade(true, resistance);
         return true;
      }
      else
      {
         Print("  - No valid resistance level found");
      }
   }
   
   // Check for bearish setup
   if(CrossedEMA(1, false) && IsEngulfing(0, false) && StayedOnSideOfEMA(0, 3, false))
   {
      Print("Strategy 1 - Bearish conditions met:");
      Print("  - EMA crossed downward: ", CrossedEMA(1, false));
      Print("  - Bearish engulfing: ", IsEngulfing(0, false));
      Print("  - Price stayed below EMA: ", StayedOnSideOfEMA(0, 3, false));
      
      double support = FindNearestSR(false);
      if(support > 0)
      {
         Print("  - Found support level at: ", support);
         ExecuteTrade(false, support);
         return true;
      }
      else
      {
         Print("  - No valid support level found");
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Strategy 2: Engulfing at support/resistance                      |
//+------------------------------------------------------------------+
bool CheckStrategy2()
{
   Print("Checking Strategy 2 conditions...");
   double currentPrice = iClose(_Symbol, PERIOD_CURRENT, 0);
   
   // Find nearest support and resistance
   double resistance = FindNearestSR(true);
   double support = FindNearestSR(false);
   
   Print("Strategy 2 - Current Price: ", currentPrice);
   Print("Strategy 2 - Nearest Resistance: ", resistance);
   Print("Strategy 2 - Nearest Support: ", support);
   
   // Check for bullish engulfing near support
   if(support > 0 && MathAbs(currentPrice - support) < 20 * _Point && IsEngulfing(0, true))
   {
      Print("Strategy 2 - Bullish conditions met:");
      Print("  - Price near support: ", MathAbs(currentPrice - support), " points away");
      Print("  - Bullish engulfing: ", IsEngulfing(0, true));
      ExecuteTrade(true, resistance);
      return true;
   }
   
   // Check for bearish engulfing near resistance
   if(resistance > 0 && MathAbs(currentPrice - resistance) < 20 * _Point && IsEngulfing(0, false))
   {
      Print("Strategy 2 - Bearish conditions met:");
      Print("  - Price near resistance: ", MathAbs(currentPrice - resistance), " points away");
      Print("  - Bearish engulfing: ", IsEngulfing(0, false));
      ExecuteTrade(false, support);
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Strategy 3: Break past resistance + EMA engulfing                |
//+------------------------------------------------------------------+
bool CheckStrategy3()
{
   Print("Checking Strategy 3 conditions...");
   double currentPrice = iClose(_Symbol, PERIOD_CURRENT, 0);
   
   // Find nearest resistance and support
   double resistance = FindNearestSR(true);
   double support = FindNearestSR(false);
   
   Print("Strategy 3 - Current Price: ", currentPrice);
   Print("Strategy 3 - Nearest Resistance: ", resistance);
   Print("Strategy 3 - Nearest Support: ", support);
   
   if(resistance == 0 || support == 0)
   {
      Print("Strategy 3 - No valid support/resistance levels found");
      return false;
   }
   
   // Check for bullish engulfing pattern
   if(IsEngulfing(0, true))
   {
      Print("Strategy 3 - Bullish engulfing detected");
      // Look for recently broken resistance levels (within the last 5 bars)
      for(int i = 1; i <= 5; i++)
      {
         // Check if bar i broke through resistance
         if(BrokeLevel(i, resistance, true))
         {
            Print("Strategy 3 - Resistance broken at bar ", i);
            // Check if price stayed on the right side of EMA
            if(StayedOnSideOfEMA(0, 3, true))
            {
               Print("Strategy 3 - Price stayed above EMA");
               double newResistance = FindNearestSR(true);
               if(newResistance > 0 && newResistance > resistance)
               {
                  Print("Strategy 3 - New resistance found at: ", newResistance);
                  ExecuteTrade(true, newResistance);
                  return true;
               }
            }
         }
      }
   }
   
   // Check for bearish engulfing pattern
   if(IsEngulfing(0, false))
   {
      Print("Strategy 3 - Bearish engulfing detected");
      // Look for recently broken support levels (within the last 5 bars)
      for(int i = 1; i <= 5; i++)
      {
         // Check if bar i broke through support
         if(BrokeLevel(i, support, false))
         {
            Print("Strategy 3 - Support broken at bar ", i);
            // Check if price stayed on the right side of EMA
            if(StayedOnSideOfEMA(0, 3, false))
            {
               Print("Strategy 3 - Price stayed below EMA");
               double newSupport = FindNearestSR(false);
               if(newSupport > 0 && newSupport < support)
               {
                  Print("Strategy 3 - New support found at: ", newSupport);
                  ExecuteTrade(false, newSupport);
                  return true;
               }
            }
         }
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Strategy 4: Simple engulfing pattern                             |
//+------------------------------------------------------------------+
bool CheckStrategy4()
{
   Print("Checking Strategy 4 conditions...");
   
   // Check for bullish engulfing
   if(IsEngulfing(0, true))
   {
      Print("Strategy 4 - Bullish engulfing detected");
      Print("  - Current Price: ", iClose(_Symbol, PERIOD_CURRENT, 0));
      Print("  - Previous Close: ", iClose(_Symbol, PERIOD_CURRENT, 1));
      Print("  - Current Open: ", iOpen(_Symbol, PERIOD_CURRENT, 0));
      Print("  - Previous Open: ", iOpen(_Symbol, PERIOD_CURRENT, 1));
      
      // For testing, use a simple target level (current price + 100 points)
      double targetLevel = iClose(_Symbol, PERIOD_CURRENT, 0) + 100 * _Point;
      ExecuteTrade(true, targetLevel);
      return true;
   }
   
   // Check for bearish engulfing
   if(IsEngulfing(0, false))
   {
      Print("Strategy 4 - Bearish engulfing detected");
      Print("  - Current Price: ", iClose(_Symbol, PERIOD_CURRENT, 0));
      Print("  - Previous Close: ", iClose(_Symbol, PERIOD_CURRENT, 1));
      Print("  - Current Open: ", iOpen(_Symbol, PERIOD_CURRENT, 0));
      Print("  - Previous Open: ", iOpen(_Symbol, PERIOD_CURRENT, 1));
      
      // For testing, use a simple target level (current price - 100 points)
      double targetLevel = iClose(_Symbol, PERIOD_CURRENT, 0) - 100 * _Point;
      ExecuteTrade(false, targetLevel);
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Execute trade with proper risk management                        |
//+------------------------------------------------------------------+
void ExecuteTrade(bool isBuy, double targetLevel)
{
   Print("Attempting to execute ", isBuy ? "BUY" : "SELL", " trade...");
   Print("Target Level: ", targetLevel);
   
   // Log current spread at time of trade execution (for information only)
   LogCurrentSpread();
   
   double currentPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double stopLoss = 0;
   double takeProfit1 = 0;
   double takeProfit2 = 0;
   
   Print("Current Price: ", currentPrice);
   
   // Calculate stop loss based on the previous candle
   if(isBuy)
   {
      stopLoss = iLow(_Symbol, PERIOD_CURRENT, 1) - SL_Buffer_Pips * _Point;
   }
   else
   {
      stopLoss = iHigh(_Symbol, PERIOD_CURRENT, 1) + SL_Buffer_Pips * _Point;
   }
   
   Print("Initial Stop Loss: ", stopLoss);
   
   // Make sure the stop loss isn't too close to current price
   double minSLDistance = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   
   if(isBuy && (currentPrice - stopLoss) < minSLDistance)
   {
      stopLoss = currentPrice - minSLDistance;
      Print("Stop loss adjusted due to minimum distance requirement. New SL: ", stopLoss);
   }
   else if(!isBuy && (stopLoss - currentPrice) < minSLDistance)
   {
      stopLoss = currentPrice + minSLDistance;
      Print("Stop loss adjusted due to minimum distance requirement. New SL: ", stopLoss);
   }
   
   // Calculate take profit levels
   takeProfit1 = CalculateTakeProfit(isBuy, currentPrice, stopLoss, RR_Ratio_1);
   takeProfit2 = CalculateTakeProfit(isBuy, currentPrice, stopLoss, RR_Ratio_2);
   
   Print("Initial Take Profit 1: ", takeProfit1);
   Print("Initial Take Profit 2: ", takeProfit2);
   
   // Check if the TP is beyond the target level, adjust if necessary
   if(isBuy)
   {
      if(takeProfit1 > targetLevel)
      {
         takeProfit1 = targetLevel - 5 * _Point;
         Print("TP1 adjusted to stay below resistance level. New TP1: ", takeProfit1);
      }
         
      if(takeProfit2 > targetLevel)
      {
         takeProfit2 = targetLevel;
         Print("TP2 adjusted to target resistance level. New TP2: ", takeProfit2);
      }
   }
   else
   {
      if(takeProfit1 < targetLevel)
      {
         takeProfit1 = targetLevel + 5 * _Point;
         Print("TP1 adjusted to stay above support level. New TP1: ", takeProfit1);
      }
         
      if(takeProfit2 < targetLevel)
      {
         takeProfit2 = targetLevel;
         Print("TP2 adjusted to target support level. New TP2: ", takeProfit2);
      }
   }
   
   Print("Final Trade Parameters:");
   Print("  - Direction: ", isBuy ? "BUY" : "SELL");
   Print("  - Entry Price: ", currentPrice);
   Print("  - Stop Loss: ", stopLoss);
   Print("  - Take Profit 1: ", takeProfit1);
   Print("  - Take Profit 2: ", takeProfit2);
   
   // Place first order
   MqlTradeRequest request1 = {};
   MqlTradeResult result1 = {};
   
   request1.action = TRADE_ACTION_DEAL;
   request1.symbol = _Symbol;
   request1.volume = Lot_Size_1;
   request1.type = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   request1.price = currentPrice;
   request1.sl = stopLoss;
   request1.tp = takeProfit1;
   request1.deviation = 10;
   request1.magic = 123456;
   request1.comment = "Strategy " + string(isBuy ? "Buy" : "Sell") + " TP1";
   
   Print("Sending first order...");
   
   // Check return value of OrderSend
   bool orderSent1 = OrderSend(request1, result1);
   if(!orderSent1 || result1.retcode != TRADE_RETCODE_DONE)
   {
      Print("First order failed. Error code: ", GetLastError(), 
            ", Return code: ", result1.retcode, 
            ", Message: ", result1.comment);
      return;
   }
   
   if(result1.retcode == TRADE_RETCODE_DONE)
   {
      posTicket1 = result1.deal;
      Print("First order executed successfully. Ticket: ", posTicket1);
      
      // Place second order
      MqlTradeRequest request2 = {};
      MqlTradeResult result2 = {};
      
      request2.action = TRADE_ACTION_DEAL;
      request2.symbol = _Symbol;
      request2.volume = Lot_Size_2;
      request2.type = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      request2.price = currentPrice;
      request2.sl = stopLoss;
      request2.tp = takeProfit2;
      request2.deviation = 10;
      request2.magic = 123456;
      request2.comment = "Strategy " + string(isBuy ? "Buy" : "Sell") + " TP2";
      
      Print("Sending second order...");
      
      // Check return value of OrderSend
      bool orderSent2 = OrderSend(request2, result2);
      if(!orderSent2 || result2.retcode != TRADE_RETCODE_DONE)
      {
         Print("Second order failed. Error code: ", GetLastError(), 
               ", Return code: ", result2.retcode, 
               ", Message: ", result2.comment);
         return;
      }
      
      if(result2.retcode == TRADE_RETCODE_DONE)
      {
         posTicket2 = result2.deal;
         Print("Second order executed successfully. Ticket: ", posTicket2);
         
         string direction = isBuy ? "BUY" : "SELL";
         Print("Both trades executed successfully:");
         Print("  - Direction: ", direction);
         Print("  - First Ticket: ", posTicket1);
         Print("  - Second Ticket: ", posTicket2);
         Print("  - Stop Loss: ", stopLoss);
         Print("  - Take Profit 1: ", takeProfit1);
         Print("  - Take Profit 2: ", takeProfit2);
      }
      else
      {
         Print("Failed to execute second trade. Error: ", GetLastError());
      }
   }
   else
   {
      Print("Failed to execute first trade. Error: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
