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
input double      Lot_Size_1 = 1;     // First entry lot size
input double      Lot_Size_2 = 2;     // Second entry lot size
input double      RR_Ratio_1 = 1.7;      // Risk:Reward ratio for first target
input double      RR_Ratio_2 = 2.0;      // Risk:Reward ratio for second target
input int         Max_Spread = 180;      // Maximum spread for logging purposes only
input bool        Use_Strategy_1 = false; // Use EMA crossing + engulfing strategy
input bool        Use_Strategy_2 = false; // Use S/R engulfing strategy
input bool        Use_Strategy_3 = false; // Use breakout + EMA engulfing strategy
input bool        Use_Strategy_4 = true; // Use simple engulfing strategy
input bool        Use_Strategy_5 = false;  // Use simple movement strategy (for testing)
input int         SL_Buffer_Pips = 5;    // Additional buffer for stop loss in pips
input int         SR_Lookback = 50;       // Number of candles to look back for S/R levels
input int         SR_Strength = 3;        // Minimum number of touches for S/R level
input double      SR_Tolerance = 0.0005;   // Tolerance for S/R level detection
input int         SR_MinBars = 3;        // Minimum bars between S/R levels
input int         Engulfing_AvgBody_Period = 12; // Period for Avg Body Size check in IsEngulfing
input bool        Engulfing_Use_Trend_Filter = false; // Use MA trend filter in IsEngulfing

// Strategy 5 Inputs
input double      S5_Lot_Size = 1;    // Lot size for Strategy 5
input int         S5_Min_Body_Pips = 1; // Minimum candle body size in pips for Strategy 5
input int         S5_TP_Pips = 10;      // Take Profit distance in pips for Strategy 5 (Increased Default)
input bool        S5_Use_Trailing_Stop = true; // Enable trailing stop for Strategy 5
input int         S5_Trail_Pips = 5;      // Trailing stop distance in pips
input int         S5_Trail_Activation_Pips = 5; // Pips in profit to activate trailing stop

// Global variables
int emaHandle;
double emaValues[];
int barCount;
ulong posTicket1 = 0;
ulong posTicket2 = 0;

// Symbol Volume Constraints
double volMin = 0.0;
double volMax = 0.0;
double volStep = 0.0;

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
   
   // Get symbol volume constraints
   volMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   volMax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   volStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   if(volMin <= 0 || volMax <= 0 || volStep <= 0)
   {
      Print("Failed to get valid volume constraints for ", _Symbol);
      // You might want to fail initialization or use default safe values
      return(INIT_FAILED); 
   }
   
   Print("Symbol Volume Constraints:");
   Print("  Min Volume: ", volMin);
   Print("  Max Volume: ", volMax);
   Print("  Volume Step: ", volStep);
   
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
   {  // No new bar, check for trailing stop management
      if(S5_Use_Trailing_Stop)
         ManageStrategy5Position();
      return; 
   }   
      
   barCount = currentBars;
   
   // Update indicators
   if(!UpdateIndicators())
      return;
      
   // Check for open positions (prevents opening new ones while others exist)
   // Note: This check might prevent S5 from opening if other strategy positions are open
   if(HasOpenPositions())
   {
      // Still manage S5 trailing stop even if other positions are open
      if(S5_Use_Trailing_Stop)
         ManageStrategy5Position(); 
      return;
   }
      
   // Log current spread for reference (but don't use it to limit trading)
   IsSpreadAcceptable(Max_Spread);
   
   // Reset comment
   Comment("");
      
   // Check strategy conditions (these return if they execute a trade)
   if(Use_Strategy_1 && CheckStrategy1())
      return;
      
   if(Use_Strategy_2 && CheckStrategy2())
      return;
      
   if(Use_Strategy_3 && CheckStrategy3())
      return;
      
   if(Use_Strategy_4 && CheckStrategy4())
      return;
      
   if(Use_Strategy_5 && CheckStrategy5()) 
      return;
      
   // If no trade was executed, ensure trailing stop is still managed on new bar
   if(S5_Use_Trailing_Stop)
      ManageStrategy5Position();
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
//| Check if the current bar forms an engulfing pattern (Indicator Logic) |
//+------------------------------------------------------------------+
bool IsEngulfing(int shift, bool bullish)
{
   // Use index i for current, i+1 for prior, aligning with indicator logic
   int i = shift;     // Typically 0 when called from CheckStrategyX
   int priorIdx = i + 1; // Typically 1 when called from CheckStrategyX
   
   // Basic check for sufficient bars
   if(Bars(_Symbol, PERIOD_CURRENT) < Engulfing_AvgBody_Period + 3 || priorIdx < 0)
   {
      // Print("IsEngulfing Error: Not enough bars available for calculation.");
      return false;
   }

   // Get required price data using iOpen/iClose etc. for reliability
   double open1 = iOpen(_Symbol, PERIOD_CURRENT, i);     // Current Open
   double close1 = iClose(_Symbol, PERIOD_CURRENT, i);    // Current Close
   double open2 = iOpen(_Symbol, PERIOD_CURRENT, priorIdx); // Prior Open
   double close2 = iClose(_Symbol, PERIOD_CURRENT, priorIdx);  // Prior Close
   
   // Check for valid data
   if(open1 == 0 || close1 == 0 || open2 == 0 || close2 == 0)
   {
      Print("IsEngulfing Error: Invalid price data for index ", i, " or ", priorIdx);
      return false;
   }
   
   // Calculate current body size
   double body1 = MathAbs(open1 - close1); 

   // Calculate average body size ending at the prior bar
   double avgBody = CalculateAverageBody(Engulfing_AvgBody_Period, priorIdx); 
   if(avgBody <= 0) 
   {
       Print("IsEngulfing Warning: Could not calculate valid Average Body Size. Skipping avg body check.");
   }
   
   // --- Trend Filter (Optional) --- 
   bool trendOkBull = true; 
   bool trendOkBear = true;
   if(Engulfing_Use_Trend_Filter)
   {
      // Ensure emaValues are up-to-date (should be called in OnTick)
      if(ArraySize(emaValues) < priorIdx + 1)
      {
         Print("IsEngulfing Error: EMA values not available for trend filter index ", priorIdx);
         return false; // Cannot apply filter if data is missing
      }
      double maPrior = emaValues[priorIdx]; // Use pre-calculated EMA value for prior bar
      double midOCPrior = (open2 + close2) / 2.0; // Midpoint of prior bar
      
      trendOkBull = midOCPrior < maPrior; // Trend Filter for Bullish: Prior Mid < MA
      trendOkBear = midOCPrior > maPrior; // Trend Filter for Bearish: Prior Mid > MA
   }

   Print("Analyzing candles for engulfing pattern (Indicator Logic):");
   Print("  - Current Bar (", i, "): O=", open1, " C=", close1, " Body=", body1);
   Print("  - Previous Bar (", priorIdx, "): O=", open2, " C=", close2);
   Print("  - Avg Body Size (", Engulfing_AvgBody_Period, " bars ending prior): ", avgBody);
   if(Engulfing_Use_Trend_Filter)
      Print("  - Trend Filter: Bullish OK=", trendOkBull, ", Bearish OK=", trendOkBear);

   // --- Check Engulfing Pattern --- 
   bool isEngulfing = false;
   
   if(bullish) // Bullish Engulfing Check
   {
      bool priorIsBearish = (close2 < open2);
      bool currentIsBullish = (close1 > open1);
      bool engulfsBody = (open1 < close2) && (close1 > open2);
      bool largerThanAvg = (avgBody > 0) ? (body1 > avgBody) : true; // Skip if avgBody invalid
      
      Print("Checking Bullish Engulfing Conditions (Indicator Logic):");
      Print("  - Prior is Bearish (C2<O2): ", priorIsBearish);
      Print("  - Current is Bullish (C1>O1): ", currentIsBullish);
      Print("  - Engulfs Prior Body (O1<C2 && C1>O2): ", engulfsBody);
      Print("  - Current Body > Avg Body (B1>Avg): ", largerThanAvg, " (Avg:", avgBody, ")");
      if(Engulfing_Use_Trend_Filter) Print("  - Trend Filter OK: ", trendOkBull);
      
      isEngulfing = priorIsBearish && currentIsBullish && engulfsBody && largerThanAvg && trendOkBull;
   }
   else // Bearish Engulfing Check
   {
      bool priorIsBullish = (close2 > open2);
      bool currentIsBearish = (close1 < open1);
      bool engulfsBody = (open1 > close2) && (close1 < open2);
      bool largerThanAvg = (avgBody > 0) ? (body1 > avgBody) : true; // Skip if avgBody invalid

      Print("Checking Bearish Engulfing Conditions (Indicator Logic):");
      Print("  - Prior is Bullish (C2>O2): ", priorIsBullish);
      Print("  - Current is Bearish (C1<O1): ", currentIsBearish);
      Print("  - Engulfs Prior Body (O1>C2 && C1<O2): ", engulfsBody);
      Print("  - Current Body > Avg Body (B1>Avg): ", largerThanAvg, " (Avg:", avgBody, ")");
      if(Engulfing_Use_Trend_Filter) Print("  - Trend Filter OK: ", trendOkBear);
      
      isEngulfing = priorIsBullish && currentIsBearish && engulfsBody && largerThanAvg && trendOkBear;
   }
   
   Print("  - Final Result: ", isEngulfing);
   return isEngulfing;
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
//| Strategy 4: Simple engulfing pattern (Checks last closed bar)    |
//+------------------------------------------------------------------+
bool CheckStrategy4()
{
   Print("Checking Strategy 4 conditions...");
   int shiftToCheck = 1; // Check the last completed bar
   
   // Check for bullish engulfing on the last closed bar
   if(IsEngulfing(shiftToCheck, true))
   {
      Print("Strategy 4 - Bullish engulfing detected on bar ", shiftToCheck);
      DrawEngulfingMarker(shiftToCheck, true); // Draw marker
      Print("  - Bar (", shiftToCheck, ") Close: ", iClose(_Symbol, PERIOD_CURRENT, shiftToCheck));
      Print("  - Bar (", shiftToCheck+1, ") Close: ", iClose(_Symbol, PERIOD_CURRENT, shiftToCheck+1));
      
      // Target level logic might need adjustment if based on bar 0
      double targetLevel = iClose(_Symbol, PERIOD_CURRENT, 0) + 100 * _Point; // Example target based on current price
      ExecuteTrade(true, targetLevel);
      return true;
   }
   
   // Check for bearish engulfing on the last closed bar
   if(IsEngulfing(shiftToCheck, false))
   {                             
      Print("Strategy 4 - Bearish engulfing detected on bar ", shiftToCheck);
      DrawEngulfingMarker(shiftToCheck, false); // Draw marker
      Print("  - Bar (", shiftToCheck, ") Close: ", iClose(_Symbol, PERIOD_CURRENT, shiftToCheck));
      Print("  - Bar (", shiftToCheck+1, ") Close: ", iClose(_Symbol, PERIOD_CURRENT, shiftToCheck+1));
      
      // Target level logic might need adjustment if based on bar 0
      double targetLevel = iClose(_Symbol, PERIOD_CURRENT, 0) - 100 * _Point; // Example target based on current price
      ExecuteTrade(false, targetLevel); 
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Strategy 5: Simple movement strategy (for testing)                  |
//+------------------------------------------------------------------+
bool CheckStrategy5()
{
   Print("Checking Strategy 5 conditions...");
   // Use shift = 1 to check the last completed bar
   int shift = 1;
   double open1 = iOpen(_Symbol, PERIOD_CURRENT, shift);
   double close1 = iClose(_Symbol, PERIOD_CURRENT, shift);
   
   // Check if bar data is available
   if(open1 == 0 || close1 == 0)
   {
      Print("Strategy 5 - Not enough data for bar at shift ", shift);
      return false;
   }
   
   double bodySize = MathAbs(close1 - open1);
   double bodySizePips = bodySize / _Point;
   
   Print("Strategy 5 - Previous Candle (shift=", shift, ") Body Size: ", bodySizePips, " pips");
   Print("  - Open: ", open1, ", Close: ", close1);
   
   if(bodySizePips > S5_Min_Body_Pips)
   {
      bool isBuy = (close1 > open1); // Determine direction based on the completed bar
      Print("Strategy 5 - Triggered based on previous bar. Direction: ", isBuy ? "BUY" : "SELL");
      ExecuteTradeStrategy5(isBuy);
      return true;
   }
   else
   {
      Print("Strategy 5 - Previous candle body size too small (", bodySizePips, " <= ", S5_Min_Body_Pips, ")");
      return false;
   }
}

//+------------------------------------------------------------------+
//| Execute Strategy 5 trade                                         |
//+------------------------------------------------------------------+
void ExecuteTradeStrategy5(bool isBuy)
{
   Print("Attempting to execute Strategy 5 ", isBuy ? "BUY" : "SELL", " trade...");
   
   // Log current spread at time of trade execution (for information only)
   LogCurrentSpread();
   
   // Get current prices and minimum distance
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double minStopDistPoints = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   
   // Determine entry price, SL, and TP
   double entryPrice = 0;
   double stopLoss = 0;
   double takeProfit = 0;
   
   if(isBuy)
   {
      entryPrice = ask;
      // Place SL below current Bid, respecting minimum stops level
      stopLoss = bid - minStopDistPoints;
      // Correct TP logic: TP above entry for BUY
      takeProfit = ask + S5_TP_Pips * _Point;
      // Ensure TP is at least minStopDistPoints away from Ask
      takeProfit = MathMax(takeProfit, ask + minStopDistPoints);
   }
   else // Sell
   {
      entryPrice = bid;
      // Place SL above current Ask, respecting minimum stops level
      stopLoss = ask + minStopDistPoints;
      // Correct TP logic: TP below entry for SELL
      takeProfit = bid - S5_TP_Pips * _Point;
      // Ensure TP is at least minStopDistPoints away from Bid
      takeProfit = MathMin(takeProfit, bid - minStopDistPoints);
   }
   
   // Normalize prices to the correct number of digits
   stopLoss = NormalizeDouble(stopLoss, _Digits);
   takeProfit = NormalizeDouble(takeProfit, _Digits);
   
   Print("Strategy 5 Trade Parameters (Corrected TP Logic):");
   Print("  - Direction: ", isBuy ? "BUY" : "SELL");
   Print("  - Entry Price (Approx): ", entryPrice); // Market order, actual entry may vary slightly
   Print("  - Stop Loss: ", stopLoss);
   Print("  - Take Profit: ", takeProfit);
   
   //--- Check if calculated SL/TP are logical --- 
   if(isBuy)
   {
      if(stopLoss >= entryPrice)
      {
         Print("Strategy 5 Error: Calculated SL (", stopLoss, ") is not below Ask price (", entryPrice, "). Aborting trade.");
         return;
      }
      if(takeProfit >= entryPrice)
      {
          Print("Strategy 5 Warning: Calculated TP (", takeProfit, ") is not below Ask price (", entryPrice, "). Check S5_TP_Pips and Stops Level.");
          // Adjust TP further if necessary, e.g., set it equal to SL? Or skip TP?
          // For now, we proceed but log warning. Broker might still reject.
      }
   }
   else // Sell
   {
      if(stopLoss <= entryPrice)
      {
         Print("Strategy 5 Error: Calculated SL (", stopLoss, ") is not above Bid price (", entryPrice, "). Aborting trade.");
         return;
      }
       if(takeProfit <= entryPrice)
      {
          Print("Strategy 5 Warning: Calculated TP (", takeProfit, ") is not above Bid price (", entryPrice, "). Check S5_TP_Pips and Stops Level.");
          // Adjust TP further if necessary? Or skip TP?
          // For now, we proceed but log warning. Broker might still reject.
      }
   }

   // Normalize volume
   double normalizedLotSize = NormalizeVolume(S5_Lot_Size);
   if(normalizedLotSize != S5_Lot_Size)
   {
      Print("Strategy 5: Input Lot Size (", S5_Lot_Size, ") adjusted to Symbol constraints: ", normalizedLotSize);
   }
   
   if(normalizedLotSize <= 0)
   {
      Print("Strategy 5 Error: Normalized lot size is zero or less. Cannot trade. Check input lot size and symbol constraints.");
      return;
   }

   // Place the order
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = normalizedLotSize; // Use normalized volume
   request.type = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   // For market orders, price is ignored, but fill it for clarity
   request.price = isBuy ? ask : bid; 
   request.sl = stopLoss;
   request.tp = takeProfit;
   request.deviation = 10;
   request.magic = 654321; // Use a different magic number for Strategy 5
   request.comment = "Strategy 5 " + string(isBuy ? "Buy" : "Sell");
   
   Print("Sending Strategy 5 order...");
   
   // Check return value of OrderSend
   bool orderSent = OrderSend(request, result);
   
   // Enhanced Error Logging
   if(!orderSent)
   {   
       Print("OrderSend function failed immediately. Error code: ", GetLastError());
       // Check specific potential issues based on error code if needed
       if(GetLastError() == TRADE_RETCODE_INVALID_STOPS)
          Print("Failure Reason: Invalid Stops (SL/TP too close or wrong side)");
       // Add more specific checks here
       return;
   }
   
   if(result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED) // Placed for pending orders, Done for market execution
   {
      ulong ticket = (result.order > 0) ? result.order : result.deal;
      Print("Strategy 5 order executed/placed successfully. Ticket/Deal ID: ", ticket);
      Print("  Result Code: ", result.retcode, " (", TradeRetcodeToString(result.retcode), ")");
      Print("  Result Comment: ", result.comment);
   }
   else
   {   
      Print("Strategy 5 order failed. Error code: ", GetLastError(), // This might be 0 if OrderSend returned true but execution failed
            ", Result Code: ", result.retcode, " (", TradeRetcodeToString(result.retcode), ")",
            ", Message: ", result.comment);
      // Log more details from the result structure if helpful
      Print("  Result Ask: ", result.ask, ", Bid: ", result.bid, ", Price: ", result.price, ", Volume: ", result.volume);
   }
}

//+------------------------------------------------------------------+
//| Helper to convert Trade Retcode to String (Revised & Simplified) |
//+------------------------------------------------------------------+
string TradeRetcodeToString(uint retcode)
{
    switch(retcode)
    {
        // Core MQL5 Trade Server Return Codes based on MqlTradeResult documentation
        case TRADE_RETCODE_REQUOTE:             return "Requote (10004)";
        case TRADE_RETCODE_REJECT:              return "Reject (10008)";
        case TRADE_RETCODE_CANCEL:              return "Cancel (10009)";
        case TRADE_RETCODE_PLACED:              return "Placed (10010)"; // Order placed in system
        case TRADE_RETCODE_DONE:                return "Done (10011)";   // Request completed
        case TRADE_RETCODE_DONE_PARTIAL:        return "Done Partial (10012)";
        case TRADE_RETCODE_ERROR:               return "Error (10013)";
        case TRADE_RETCODE_TIMEOUT:             return "Timeout (10014)";
        case TRADE_RETCODE_INVALID:             return "Invalid Request (10015)";
        case TRADE_RETCODE_INVALID_VOLUME:      return "Invalid Volume (10016)";
        case TRADE_RETCODE_INVALID_PRICE:       return "Invalid Price (10017)";
        case TRADE_RETCODE_INVALID_STOPS:       return "Invalid Stops (10018)";
        // case TRADE_RETCODE_INVALID_TRADE_VOLUME: return "Invalid Trade Volume (10019)"; // Often overlaps/less common
        // case TRADE_RETCODE_ORDER_FROZEN:        return "Order Frozen (10020)"; // Less common/may not be defined
        case TRADE_RETCODE_INVALID_EXPIRATION:  return "Invalid Expiration (10021)";
        case TRADE_RETCODE_CONNECTION:          return "Connection Problem (10022)";
        case TRADE_RETCODE_TOO_MANY_REQUESTS:   return "Too Many Requests (10023)";
        case TRADE_RETCODE_NO_MONEY:            return "No Money (10024)"; // Or Not Enough Money
        // case TRADE_RETCODE_NOT_ENOUGH_MONEY:    return "Not Enough Money (10025)"; // Covered by NO_MONEY
        case TRADE_RETCODE_PRICE_CHANGED:       return "Price Changed (10026)";
        case TRADE_RETCODE_TRADE_DISABLED:      return "Trade Disabled (10027)";
        case TRADE_RETCODE_MARKET_CLOSED:       return "Market Closed (10028)";
        case TRADE_RETCODE_INVALID_ORDER:       return "Invalid Order (10029)";
        case TRADE_RETCODE_INVALID_FILL:        return "Invalid Fill (10030)";
        // case TRADE_RETCODE_TRADE_NOT_ALLOWED:   return "Trade Not Allowed (10031)"; // Often covered by DISABLED
        // The following are less common or potentially platform-specific
        // case TRADE_RETCODE_AUTH_FAILED:         return "Auth Failed (10032)";
        // case TRADE_RETCODE_HEADER_INVALID:      return "Header Invalid (10033)";
        // case TRADE_RETCODE_REQUEST_INVALID:     return "Request Invalid (10034)";
        // case TRADE_RETCODE_ACCOUNT_DISABLED:    return "Account Disabled (10035)";
        // case TRADE_RETCODE_INVALID_ACCOUNT:     return "Invalid Account (10036)";
        // case TRADE_RETCODE_TRADE_TIMEOUT:       return "Trade Timeout (10037)";
        // case TRADE_RETCODE_ORDER_NOT_FOUND:     return "Order Not Found (10038)"; 
        // case TRADE_RETCODE_PRICE_OFF:           return "Price Off (10039)";
        // case TRADE_RETCODE_INVALID_STOPLOSS:    return "Invalid Stoploss (10040)";
        // case TRADE_RETCODE_INVALID_TAKEPROFIT:  return "Invalid Takeproprofit (10041)";
        // case TRADE_RETCODE_POSITION_CLOSED:     return "Position Closed (10042)";
        case TRADE_RETCODE_LIMIT_POSITIONS:     return "Limit Positions (10043)";
        case TRADE_RETCODE_LIMIT_ORDERS:        return "Limit Orders (10044)";
        // case TRADE_RETCODE_LIMIT_VOLUME:        return "Limit Volume (10045)";
        // case TRADE_RETCODE_ORDER_REJECTED:      return "Order Rejected (10046)"; // Covered by REJECT
        // case TRADE_RETCODE_UNSUPPORTED_FILL_POLICY: return "Unsupported Fill Policy (10047)";
        default:                                return "Unknown (" + (string)retcode + ")";
    }
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
   
   // Get current ask/bid for TP checks
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // Calculate take profit levels
   takeProfit1 = CalculateTakeProfit(isBuy, currentPrice, stopLoss, RR_Ratio_1);
   takeProfit2 = CalculateTakeProfit(isBuy, currentPrice, stopLoss, RR_Ratio_2);
   
   Print("Initial Take Profit 1: ", takeProfit1);
   Print("Initial Take Profit 2: ", takeProfit2);
   
   // Check if the TP is beyond the target level, adjust if necessary
   if(targetLevel != 0) // Only adjust if a valid targetLevel was provided
   {
      if(isBuy)
      {
         if(takeProfit1 > targetLevel)
         {  // Don't place TP1 beyond the resistance
            takeProfit1 = targetLevel - _Point; // Place slightly below resistance
            Print("TP1 adjusted to stay below resistance level. New TP1: ", takeProfit1);
         }
            
         if(takeProfit2 > targetLevel)
         { // Don't place TP2 beyond the resistance
            takeProfit2 = targetLevel; 
            Print("TP2 adjusted to target resistance level. New TP2: ", takeProfit2);
         }
      }
      else // Sell
      {
         if(takeProfit1 < targetLevel)
         { // Don't place TP1 beyond the support
            takeProfit1 = targetLevel + _Point; // Place slightly above support
            Print("TP1 adjusted to stay above support level. New TP1: ", takeProfit1);
         }
            
         if(takeProfit2 < targetLevel)
         { // Don't place TP2 beyond the support
            takeProfit2 = targetLevel;
            Print("TP2 adjusted to target support level. New TP2: ", takeProfit2);
         }
      }
   }
   
   // Ensure TPs respect minimum stop distance
   if(isBuy)
   {
      double minTP1 = ask + minSLDistance;
      double minTP2 = ask + minSLDistance;
      if(takeProfit1 < minTP1)
      {
         Print("TP1 adjusted *up* to minimum distance. Old TP1: ", takeProfit1, ", New TP1: ", minTP1);
         takeProfit1 = minTP1;
      }
      if(takeProfit2 < minTP2)
      {
          Print("TP2 adjusted *up* to minimum distance. Old TP2: ", takeProfit2, ", New TP2: ", minTP2);
          takeProfit2 = minTP2;
      }
   }
   else // Sell
   {
      double maxTP1 = bid - minSLDistance;
      double maxTP2 = bid - minSLDistance;
       if(takeProfit1 > maxTP1)
      {
         Print("TP1 adjusted *down* to minimum distance. Old TP1: ", takeProfit1, ", New TP1: ", maxTP1);
         takeProfit1 = maxTP1;
      }
      if(takeProfit2 > maxTP2)
      {
          Print("TP2 adjusted *down* to minimum distance. Old TP2: ", takeProfit2, ", New TP2: ", maxTP2);
          takeProfit2 = maxTP2;
      }
   }
   
   // Normalize final TP values
   takeProfit1 = NormalizeDouble(takeProfit1, _Digits);
   takeProfit2 = NormalizeDouble(takeProfit2, _Digits);

   Print("Final Trade Parameters:");
   Print("  - Direction: ", isBuy ? "BUY" : "SELL");
   Print("  - Entry Price: ", currentPrice);
   Print("  - Stop Loss: ", stopLoss);
   Print("  - Take Profit 1: ", takeProfit1);
   Print("  - Take Profit 2: ", takeProfit2);
   
   // Normalize lot sizes
   double normalizedLot1 = NormalizeVolume(Lot_Size_1);
   double normalizedLot2 = NormalizeVolume(Lot_Size_2);
   
   if(normalizedLot1 != Lot_Size_1)
      Print("Strategy 1-4: Lot Size 1 (", Lot_Size_1, ") adjusted to Symbol constraints: ", normalizedLot1);
   if(normalizedLot2 != Lot_Size_2)
      Print("Strategy 1-4: Lot Size 2 (", Lot_Size_2, ") adjusted to Symbol constraints: ", normalizedLot2);
      
   if(normalizedLot1 <= 0 || normalizedLot2 <= 0)
   {
      Print("Strategy 1-4 Error: Normalized lot size is zero or less. Cannot trade. Check input lot sizes and symbol constraints.");
      return;
   }
   
   // Place first order
   MqlTradeRequest request1 = {};
   MqlTradeResult result1 = {};
   
   request1.action = TRADE_ACTION_DEAL;
   request1.symbol = _Symbol;
   request1.volume = normalizedLot1; // Use normalized volume
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
      request2.volume = normalizedLot2; // Use normalized volume
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
//| Normalize volume according to symbol constraints                 |
//+------------------------------------------------------------------+
double NormalizeVolume(double desiredVolume)
{
   // Ensure volume is within min/max limits
   desiredVolume = MathMax(volMin, desiredVolume);
   desiredVolume = MathMin(volMax, desiredVolume);
   
   // Adjust volume to the nearest valid step
   // Calculate how many steps fit into the volume
   double steps = MathRound((desiredVolume - volMin) / volStep);
   // Calculate the normalized volume
   double normalizedVolume = volMin + steps * volStep;
   
   // Final check to ensure it doesn't slightly exceed max due to floating point math
   normalizedVolume = MathMin(volMax, normalizedVolume);
   
   // Ensure it's not below min either
   normalizedVolume = MathMax(volMin, normalizedVolume);
   
   return normalizedVolume;
}

//+------------------------------------------------------------------+
//| Manage Trailing Stop for Strategy 5 Position                     |
//+------------------------------------------------------------------+
void ManageStrategy5Position()
{
   // Iterate through open positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         // Check if position belongs to this EA and Strategy 5
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_MAGIC) == 654321)
         {
            long positionType = PositionGetInteger(POSITION_TYPE);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentSL = PositionGetDouble(POSITION_SL);
            double currentPrice = 0;
            double newSL = 0;
            bool isBuy = (positionType == POSITION_TYPE_BUY);
            
            double profitPips = 0;
            double minStopDistPoints = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
            double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            
            // Calculate current profit in pips
            if(isBuy)
            {
               currentPrice = bid; // Use Bid for Buy profit calculation
               profitPips = (currentPrice - openPrice) / _Point;
            }
            else // Sell
            {
               currentPrice = ask; // Use Ask for Sell profit calculation
               profitPips = (openPrice - currentPrice) / _Point;
            }
            
            // Check if trailing stop activation threshold is met
            if(profitPips < S5_Trail_Activation_Pips)
            {
               // Print("S5 Trail (Ticket: ", ticket, "): Activation not met (Profit: ", profitPips, " < ", S5_Trail_Activation_Pips, ")");
               continue; // Not enough profit to activate trailing
            }
            
            Print("S5 Trail (Ticket: ", ticket, "): Activation met (Profit: ", profitPips, " >= ", S5_Trail_Activation_Pips, ")");

            // Calculate potential new Stop Loss based on trail distance
            if(isBuy)
            {               
               newSL = currentPrice - S5_Trail_Pips * _Point;
               // Ensure SL is at least breakeven (open price)
               newSL = MathMax(newSL, openPrice);
               // Ensure new SL respects minimum stops distance from Bid
               newSL = MathMin(newSL, bid - minStopDistPoints);
            }
            else // Sell
            {               
               newSL = currentPrice + S5_Trail_Pips * _Point;
               // Ensure SL is at least breakeven (open price)
               newSL = MathMin(newSL, openPrice);
               // Ensure new SL respects minimum stops distance from Ask
               newSL = MathMax(newSL, ask + minStopDistPoints);
            }
            
            // Normalize the calculated new SL
            newSL = NormalizeDouble(newSL, _Digits);
            
            Print("S5 Trail (Ticket: ", ticket, "): Calculated New SL: ", newSL, " Current SL: ", currentSL);

            // Check if the new SL is better (further in profit direction) than the current SL
            bool shouldModify = false;
            if(isBuy && newSL > currentSL)
            {
               shouldModify = true;
            }
            else if(!isBuy && newSL < currentSL)
            {
               shouldModify = true;
            }
            
            if(shouldModify)
            {
               Print("S5 Trail (Ticket: ", ticket, "): Modifying SL from ", currentSL, " to ", newSL);
               // Modify the position
               MqlTradeRequest request = {};
               MqlTradeResult result = {};
               
               request.action = TRADE_ACTION_SLTP;
               request.position = ticket;
               request.sl = newSL;
               // request.tp = PositionGetDouble(POSITION_TP); // Keep original TP
               
               if(OrderSend(request, result))
               {
                  if(result.retcode == TRADE_RETCODE_DONE)
                  {
                     Print("S5 Trail (Ticket: ", ticket, "): Position SL modified successfully to ", newSL);
                  }
                  else
                  {                     
                     Print("S5 Trail (Ticket: ", ticket, "): Position modify failed. Retcode: ", result.retcode, " (", TradeRetcodeToString(result.retcode), ") Message: ", result.comment);
                  }
               }
               else
               {
                   Print("S5 Trail (Ticket: ", ticket, "): OrderSend failed for SL modification. Error: ", GetLastError());
               }
            }
            else
            {
               Print("S5 Trail (Ticket: ", ticket, "): New SL (", newSL, ") is not better than current SL (", currentSL, "). No modification needed.");
            }
            
            // Only manage one S5 position per tick to avoid overwhelming the server
            break; 
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate Average Body Size (Ending at startIndex)              |
//+------------------------------------------------------------------+
double CalculateAverageBody(int period, int startIndex)
{
   if(period <= 0)
   {
      Print("Error: Average Body Period must be positive.");
      return 0.0;
   }
   
   double sum = 0;
   int barsAvailable = Bars(_Symbol, PERIOD_CURRENT);
   // Ensure startIndex is valid and we have enough bars for the period
   if(startIndex < 0 || startIndex + period > barsAvailable)
   {
       Print("Error: Not enough bars available or invalid start index (", startIndex, ") for average body calculation of period ", period);
       return 0.0;
   }
   
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   
   // Copy 'period' bars ending at 'startIndex'
   // MQL5 CopyRates: from start_pos (most recent), count
   // To get bars ending *at* startIndex, we start copying from startIndex
   if(CopyRates(_Symbol, PERIOD_CURRENT, startIndex, period, rates) != period)
   {
       Print("Error copying rates for Average Body calculation. Error: ", GetLastError());
       return 0.0; // Return 0 or handle error appropriately
   }

   // Sum the body sizes of the copied bars
   for(int i = 0; i < period; i++)
   {
      sum += MathAbs(rates[i].open - rates[i].close);
   }
   
   // Avoid division by zero if period somehow ended up invalid
   if(period == 0) return 0.0;
   
   return sum / period;
}

//+------------------------------------------------------------------+
//| Draw an arrow marker for detected engulfing patterns             |
//+------------------------------------------------------------------+
void DrawEngulfingMarker(int barIndex, bool isBullish)
{
   datetime barTime = iTime(_Symbol, PERIOD_CURRENT, barIndex);
   string objectName = "EngulfMarker_" + (string)barTime + "_" + (string)isBullish;
   
   double priceLevel = 0;
   int arrowCode = 0;
   color arrowColor = clrNONE;
   
   if(isBullish)
   {
      priceLevel = iLow(_Symbol, PERIOD_CURRENT, barIndex) - 2 * _Point * 10; // Place below low
      arrowCode = 233; // Up arrow
      arrowColor = clrDodgerBlue;
   }
   else // Bearish
   {
      priceLevel = iHigh(_Symbol, PERIOD_CURRENT, barIndex) + 2 * _Point * 10; // Place above high
      arrowCode = 234; // Down arrow
      arrowColor = clrRed;
   }
   
   // Delete existing object with the same name first, if any (prevents duplicates)
   ObjectDelete(0, objectName);

   // Create the arrow object
   if(!ObjectCreate(0, objectName, OBJ_ARROW, 0, barTime, priceLevel))
   {
      Print("Error creating engulfing marker object '", objectName, "': ", GetLastError());
      return;
   }
   
   // Set arrow properties
   ObjectSetInteger(0, objectName, OBJPROP_ARROWCODE, arrowCode);
   ObjectSetInteger(0, objectName, OBJPROP_COLOR, arrowColor);
   ObjectSetInteger(0, objectName, OBJPROP_WIDTH, 1);
}

//+------------------------------------------------------------------+
