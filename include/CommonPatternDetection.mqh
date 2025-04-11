//+------------------------------------------------------------------+
//|                                     CommonPatternDetection.mqh     |
//|                                                                    |
//|            Common EMA and Engulfing Pattern Detection Logic        |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023"
#property link      ""
#property version   "1.00"

// Common Constants
#define EMA_PERIOD 20

// EMA Indicator Handle and Values
class CEMAValues
{
public:
   int handle;
   double values[];
   
   CEMAValues() : handle(INVALID_HANDLE) {}
};

CEMAValues g_ema;

// Pattern Detection Colors
color ENGULFING_BULLISH_COLOR = clrLime;
color ENGULFING_BEARISH_COLOR = clrRed;
color EMA_LINE_COLOR = clrRed;  // Changed from clrBlue to clrRed

//+------------------------------------------------------------------+
//| Initialize EMA indicator                                          |
//+------------------------------------------------------------------+
bool InitializeEMA()
{
   Print("InitializeEMA: Starting initialization...");
   
   if(g_ema.handle != INVALID_HANDLE)
   {
      Print("InitializeEMA: EMA already initialized with handle ", g_ema.handle);
      return true;
   }
   
   g_ema.handle = iMA(_Symbol, PERIOD_CURRENT, EMA_PERIOD, 0, MODE_EMA, PRICE_CLOSE);
   
   if(g_ema.handle == INVALID_HANDLE)
   {
      Print("InitializeEMA: Failed to create EMA indicator handle");
      return false;
   }
   
   Print("InitializeEMA: Successfully initialized with handle ", g_ema.handle);
   return true;
}

//+------------------------------------------------------------------+
//| Release EMA indicator                                             |
//+------------------------------------------------------------------+
void ReleaseEMA()
{
   Print("ReleaseEMA: Starting cleanup...");
   
   if(g_ema.handle != INVALID_HANDLE)
   {
      Print("ReleaseEMA: Releasing indicator handle ", g_ema.handle);
      if(!IndicatorRelease(g_ema.handle))
      {
         Print("ReleaseEMA: Failed to release indicator handle. Error: ", GetLastError());
      }
      g_ema.handle = INVALID_HANDLE;
      ArrayFree(g_ema.values);
      Print("ReleaseEMA: Cleanup completed");
   }
   else
   {
      Print("ReleaseEMA: No handle to release");
   }
}

//+------------------------------------------------------------------+
//| Update EMA values                                                 |
//+------------------------------------------------------------------+
bool UpdateEMAValues(int requiredBars)
{
   if(g_ema.handle == INVALID_HANDLE)
   {
      Print("UpdateEMAValues: Invalid EMA handle");
      return false;
   }
      
   // Use requested bars but ensure minimum of 3 for basic functionality
   int minBars = MathMax(requiredBars, 3);
   ArrayResize(g_ema.values, minBars);
   ArraySetAsSeries(g_ema.values, true);
   
   int copied = CopyBuffer(g_ema.handle, 0, 0, minBars, g_ema.values);
   if(copied < minBars)
   {
      Print("UpdateEMAValues: Failed to copy EMA values. Requested: ", minBars, ", Copied: ", copied);
      return false;
   }
   
   Print("UpdateEMAValues: Successfully copied ", copied, " bars");
   
   return true;
}

//+------------------------------------------------------------------+
//| Check for engulfing pattern                                       |
//+------------------------------------------------------------------+
bool IsEngulfing(int shift, bool bullish, bool useTrendFilter = false)
{
   if(g_ema.handle == INVALID_HANDLE)
   {
      Print("IsEngulfing: Invalid EMA handle");
      return false;
   }
      
   int i = shift;
   int priorIdx = i + 1;
   int bars = ArraySize(g_ema.values);
   
   if(priorIdx >= bars)
   {
      Print("IsEngulfing: Not enough bars in array. Required: ", priorIdx + 1, ", Available: ", bars);
      return false;
   }
      
   double open1 = iOpen(_Symbol, PERIOD_CURRENT, i);
   double close1 = iClose(_Symbol, PERIOD_CURRENT, i);
   double open2 = iOpen(_Symbol, PERIOD_CURRENT, priorIdx);
   double close2 = iClose(_Symbol, PERIOD_CURRENT, priorIdx);
   
   if(open1 == 0 || close1 == 0 || open2 == 0 || close2 == 0)
   {
      Print("IsEngulfing: Invalid price data detected for shift ", shift);
      return false;
   }
      
   double tolerance = _Point;
   
   bool trendOkBull = !useTrendFilter;
   bool trendOkBear = !useTrendFilter;
   
   if(useTrendFilter)
   {
      // Use EMA value at pattern formation time
      double maPrior = g_ema.values[priorIdx];
      trendOkBull = close1 > maPrior;
      trendOkBear = close1 < maPrior;
   }
   
   if(bullish)
   {
      bool priorIsBearish = (close2 < open2 - tolerance);
      bool currentIsBullish = (close1 > open1 + tolerance);
      bool engulfsBody = (open1 < close2 - tolerance) && (close1 > open2 + tolerance);
      
   if(priorIsBearish && currentIsBullish && engulfsBody && trendOkBull)
   {
      Print("IsEngulfing: Bullish engulfing pattern detected at shift ", shift);
      DrawEngulfingPattern(i, true);
      return true;
   }
   }
   else
   {
      bool priorIsBullish = (close2 > open2 + tolerance);
      bool currentIsBearish = (close1 < open1 - tolerance);
      bool engulfsBody = (open1 > close2 + tolerance) && (open1 < open2 - tolerance);
      
   if(priorIsBullish && currentIsBearish && engulfsBody && trendOkBear)
   {
      Print("IsEngulfing: Bearish engulfing pattern detected at shift ", shift);
      DrawEngulfingPattern(i, false);
      return true;
   }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Draw engulfing pattern marker                                     |
//+------------------------------------------------------------------+
void DrawEngulfingPattern(int shift, bool bullish)
{
    string objName = "EngulfPattern_" + IntegerToString(TimeCurrent() + shift);
    datetime patternTime = iTime(_Symbol, PERIOD_CURRENT, shift);
    double patternPrice = bullish ? iLow(_Symbol, PERIOD_CURRENT, shift) - 10 * _Point 
                                : iHigh(_Symbol, PERIOD_CURRENT, shift) + 10 * _Point;
    
    // Delete existing object if it exists
    ObjectDelete(0, objName);
    
    // Create arrow object
    if(!ObjectCreate(0, objName, OBJ_ARROW, 0, patternTime, patternPrice))
    {
        Print("Failed to create engulfing pattern marker. Error: ", GetLastError());
        return;
    }
    
    // Set object properties
    ObjectSetInteger(0, objName, OBJPROP_ARROWCODE, bullish ? 233 : 234);  // Up/Down arrow
    ObjectSetInteger(0, objName, OBJPROP_COLOR, bullish ? ENGULFING_BULLISH_COLOR : ENGULFING_BEARISH_COLOR);
    ObjectSetInteger(0, objName, OBJPROP_WIDTH, 2);
    ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, objName, OBJPROP_HIDDEN, true);
    
    ChartRedraw(0);
}


//+------------------------------------------------------------------+
//| Draw EMA line                                                     |
//+------------------------------------------------------------------+
void DrawEMALine()
{
   if(g_ema.handle == INVALID_HANDLE)
   {
      Print("DrawEMALine: Invalid EMA handle");
      return;
   }
   
   int available = ArraySize(g_ema.values);
   if(available < 2)
   {
      Print("DrawEMALine: Not enough data points. Available: ", available);
      return;
   }
   
   // Delete existing EMA lines
   ObjectsDeleteAll(0, "EMA_Line");
   
   // Draw EMA line segments connecting available points
   datetime time1, time2;
   double price1, price2;
   
   for(int i = 1; i < available; i++)
   {
      string objName = "EMA_Line_" + IntegerToString(i);
      
      time1 = iTime(_Symbol, PERIOD_CURRENT, i);
      time2 = iTime(_Symbol, PERIOD_CURRENT, i-1);
      price1 = g_ema.values[i];
      price2 = g_ema.values[i-1];
      
      if(!ObjectCreate(0, objName, OBJ_TREND, 0, time1, price1, time2, price2))
      {
         Print("Failed to create EMA line segment. Error: ", GetLastError());
         continue;
      }
      
      ObjectSetInteger(0, objName, OBJPROP_COLOR, EMA_LINE_COLOR);
      ObjectSetInteger(0, objName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, objName, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, objName, OBJPROP_RAY_LEFT, false);
      ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, objName, OBJPROP_BACK, false);
   }
   
   ChartRedraw(0);
}
