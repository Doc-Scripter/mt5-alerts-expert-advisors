//+------------------------------------------------------------------+
//|                                       EMA_Engulfing_EA.mqh       |
//|                                                                   |
//|                                                                   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023"
#property link      ""
#property strict

// Structure to hold support/resistance levels
struct SRLevel
{
   double price;
   bool isResistance;
   int strength;
   datetime time;
};

// Structure to hold pattern detection results
struct PatternInfo
{
   bool isEngulfing;
   bool isBullish;
   int barIndex;
   double highPrice;
   double lowPrice;
};

// Structure to hold EMA crossing information
struct EmaCrossInfo
{
   bool crossed;
   bool crossedUp;
   int crossBar;
};

// Function to calculate pip value for different symbols
double PipValue()
{
   string symbol = _Symbol;
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   
   if(digits == 3 || digits == 5)
      return 0.0001;
   if(digits == 2 || digits == 4)
      return 0.01;
   
   return 0.001; // Default value
}

// Function to normalize stop loss/take profit levels
double NormalizePrice(double price)
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   return MathRound(price / tickSize) * tickSize;
}

// Function to calculate risk-based lot size
double CalculateLotSize(double riskPercentage, double stopLossPips)
{
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   double riskAmount = accountBalance * (riskPercentage / 100);
   double lotSize = NormalizeDouble(riskAmount / (stopLossPips * tickValue), 2);
   
   // Round down to nearest lot step
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   
   // Check against min and max lot size
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   if(lotSize < minLot) lotSize = minLot;
   if(lotSize > maxLot) lotSize = maxLot;
   
   return lotSize;
}

// Function to check if bar formed a valid engulfing pattern
bool IsEngulfingPattern(int barIndex, bool &isBullish)
{
   double open1 = iOpen(_Symbol, PERIOD_CURRENT, barIndex + 1);
   double close1 = iClose(_Symbol, PERIOD_CURRENT, barIndex + 1);
   double open2 = iOpen(_Symbol, PERIOD_CURRENT, barIndex);
   double close2 = iClose(_Symbol, PERIOD_CURRENT, barIndex);
   
   // Check for bullish engulfing
   if((open1 > close1) && // Prior candle is bearish
      (open2 < close2) && // Current candle is bullish
      (open2 <= close1) && // Current open is below or equal to prior close
      (close2 > open1))    // Current close is above prior open
   {
      isBullish = true;
      return true;
   }
   
   // Check for bearish engulfing
   else if((open1 < close1) && // Prior candle is bullish
         (open2 > close2) && // Current candle is bearish
         (open2 >= close1) && // Current open is above or equal to prior close
         (close2 < open1))    // Current close is below prior open
   {
      isBullish = false;
      return true;
   }
   
   return false;
}

// Function to identify potential support/resistance levels
bool IdentifySRLevel(int barIndex, SRLevel &level, int lookback = 20, int minStrength = 2)
{
   double high = iHigh(_Symbol, PERIOD_CURRENT, barIndex);
   double low = iLow(_Symbol, PERIOD_CURRENT, barIndex);
   int strengthHigh = 0;
   int strengthLow = 0;
   
   // Check if this bar forms a local high/low
   bool isHighPoint = (iHigh(_Symbol, PERIOD_CURRENT, barIndex) > iHigh(_Symbol, PERIOD_CURRENT, barIndex + 1)) &&
                     (iHigh(_Symbol, PERIOD_CURRENT, barIndex) > iHigh(_Symbol, PERIOD_CURRENT, barIndex - 1));
                     
   bool isLowPoint = (iLow(_Symbol, PERIOD_CURRENT, barIndex) < iLow(_Symbol, PERIOD_CURRENT, barIndex + 1)) &&
                    (iLow(_Symbol, PERIOD_CURRENT, barIndex) < iLow(_Symbol, PERIOD_CURRENT, barIndex - 1));
   
   // If neither a high nor low point, return false
   if(!isHighPoint && !isLowPoint)
      return false;
   
   // Count how many bars have similar highs/lows
   for(int i = 0; i < lookback; i++)
   {
      if(i == barIndex) continue; // Skip the current bar
      
      if(MathAbs(iHigh(_Symbol, PERIOD_CURRENT, i) - high) <= 10 * _Point)
         strengthHigh++;
         
      if(MathAbs(iLow(_Symbol, PERIOD_CURRENT, i) - low) <= 10 * _Point)
         strengthLow++;
   }
   
   // Choose the stronger level (resistance or support)
   if(strengthHigh >= minStrength && strengthHigh > strengthLow)
   {
      level.price = high;
      level.isResistance = true;
      level.strength = strengthHigh;
      level.time = iTime(_Symbol, PERIOD_CURRENT, barIndex);
      return true;
   }
   else if(strengthLow >= minStrength)
   {
      level.price = low;
      level.isResistance = false;
      level.strength = strengthLow;
      level.time = iTime(_Symbol, PERIOD_CURRENT, barIndex);
      return true;
   }
   
   return false;
}

// Function to detect EMA crossover
bool DetectEmaCross(double emaArray[], int barIndex, bool &crossedUp)
{
   double close0 = iClose(_Symbol, PERIOD_CURRENT, barIndex);
   double close1 = iClose(_Symbol, PERIOD_CURRENT, barIndex + 1);
   
   if(close1 < emaArray[barIndex + 1] && close0 > emaArray[barIndex])
   {
      crossedUp = true;
      return true;
   }
   else if(close1 > emaArray[barIndex + 1] && close0 < emaArray[barIndex])
   {
      crossedUp = false;
      return true;
   }
   
   return false;
}

// Function to check if price stayed on one side of EMA for a period
bool StayedOnEmaSide(double emaArray[], int startBar, int numBars, bool aboveEma)
{
   for(int i = startBar; i < startBar + numBars && i < Bars(_Symbol, PERIOD_CURRENT); i++)
   {
      double close = iClose(_Symbol, PERIOD_CURRENT, i);
      
      if(aboveEma && close < emaArray[i])
         return false;
      
      if(!aboveEma && close > emaArray[i])
         return false;
   }
   
   return true;
}
//+------------------------------------------------------------------+