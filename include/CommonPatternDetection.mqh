//+------------------------------------------------------------------+
//|                                     CommonPatternDetection.mqh     |
//|                                                                    |
//|            Common EMA and Engulfing Pattern Detection Logic        |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023"
#property link      ""
#property version   "1.00"

// Include AlertSystem for sending alerts
#include "../strategies/Strategy1_EMA_Crossover_EA/AlertSystem.mqh"

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
   // Simplified logging - only log important outcomes
   if(g_ema.handle != INVALID_HANDLE)
      return true;
   
   g_ema.handle = iMA(_Symbol, PERIOD_CURRENT, EMA_PERIOD, 0, MODE_EMA, PRICE_CLOSE);
   
   if(g_ema.handle == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create EMA indicator handle");
      return false;
   }
   
   Print("INFO: EMA initialized successfully");
   return true;
}

//+------------------------------------------------------------------+
//| Release EMA indicator                                             |
//+------------------------------------------------------------------+
void ReleaseEMA()
{
   if(g_ema.handle != INVALID_HANDLE)
   {
      if(!IndicatorRelease(g_ema.handle))
         Print("ERROR: Failed to release EMA indicator handle. Error: ", GetLastError());
      
      g_ema.handle = INVALID_HANDLE;
      ArrayFree(g_ema.values);
   }
}

//+------------------------------------------------------------------+
//| Update EMA values                                                 |
//+------------------------------------------------------------------+
bool UpdateEMAValues(int requiredBars)
{
   if(g_ema.handle == INVALID_HANDLE)
   {
      Print("ERROR: Invalid EMA handle");
      return false;
   }
      
   // Use requested bars but ensure minimum of 3 for basic functionality
   int minBars = MathMax(requiredBars, 3);
   ArrayResize(g_ema.values, minBars);
   ArraySetAsSeries(g_ema.values, true);
   
   int copied = CopyBuffer(g_ema.handle, 0, 0, minBars, g_ema.values);
   if(copied < minBars)
   {
      Print("ERROR: Failed to copy EMA values. Requested: ", minBars, ", Copied: ", copied);
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check for engulfing pattern                                       |
//+------------------------------------------------------------------+
bool IsEngulfing(int shift, bool bullish, bool useTrendFilter = true, int lookbackCandles = 10)
{
    // Validate lookback parameter
    lookbackCandles = MathMax(1, lookbackCandles); // Ensure at least 1 candle is checked
    
    // Current candle data
    double open1 = iOpen(_Symbol, PERIOD_CURRENT, shift);
    double close1 = iClose(_Symbol, PERIOD_CURRENT, shift);
    double high1 = iHigh(_Symbol, PERIOD_CURRENT, shift);
    double low1 = iLow(_Symbol, PERIOD_CURRENT, shift);

    // Determine current candle direction
    bool currentIsBullish = (close1 > open1);
    bool currentIsBearish = (close1 < open1);
    
    // Use a small tolerance relative to the price to avoid false signals due to tiny differences
    double tolerance = _Point;

    // Check trend filter if required
    bool trendOkBull = !useTrendFilter; // Default to true if not using trend filter
    bool trendOkBear = !useTrendFilter;

    if (useTrendFilter)
    {
        // Check if we have enough EMA values
        if (ArraySize(g_ema.values) <= shift + 1)
        {
            // Instead of failing, we'll disable the trend filter for this check
            trendOkBull = true;
            trendOkBear = true;
        }
        else
        {
            double maValue = g_ema.values[shift];
            double maPrior = g_ema.values[shift + 1];
            
            // For bullish pattern, price should be above EMA or EMA should be rising
            trendOkBull = (close1 > maValue) || (maValue > maPrior);
            
            // For bearish pattern, price should be below EMA or EMA should be falling
            trendOkBear = (close1 < maValue) || (maValue < maPrior);
        }
    }

    // Calculate average candle sizes from previous candles
    double totalBodySize = 0;
    double totalCandleSize = 0;
    
    for (int i = 1; i <= lookbackCandles; i++)
    {
        int idx = shift + i;
        double prevOpen = iOpen(_Symbol, PERIOD_CURRENT, idx);
        double prevClose = iClose(_Symbol, PERIOD_CURRENT, idx);
        double prevHigh = iHigh(_Symbol, PERIOD_CURRENT, idx);
        double prevLow = iLow(_Symbol, PERIOD_CURRENT, idx);
        
        double bodySize = MathAbs(prevClose - prevOpen);
        double candleSize = prevHigh - prevLow;
        
        totalBodySize += bodySize;
        totalCandleSize += candleSize;
    }
    
    double avgBodySize = totalBodySize / lookbackCandles;
    double avgCandleSize = totalCandleSize / lookbackCandles;
    
    // Calculate current candle sizes
    double currentBodySize = MathAbs(close1 - open1);
    double currentCandleSize = high1 - low1;
    
    // Check if current candle is at least 30% larger than average
    bool isSizeSignificant = (currentBodySize >= avgBodySize * 1.3) || 
                             (currentCandleSize >= avgCandleSize * 1.3);
    
    if (!isSizeSignificant)
        return false;

    // Check each previous candle
    for (int i = 1; i <= lookbackCandles; i++)
    {
        int currentIdx = shift + i;
        double prevOpen = iOpen(_Symbol, PERIOD_CURRENT, currentIdx);
        double prevClose = iClose(_Symbol, PERIOD_CURRENT, currentIdx);
        double prevHigh = iHigh(_Symbol, PERIOD_CURRENT, currentIdx);
        double prevLow = iLow(_Symbol, PERIOD_CURRENT, currentIdx);
        
        bool canEngulf = false;
        
        if (bullish)
        {
            bool prevIsBearish = (prevClose < prevOpen - tolerance);
            bool currentIsBullishWithTolerance = (close1 > open1 + tolerance);
            
            // Check for body engulfing
            bool engulfsBody = (open1 <= prevClose - tolerance) && (close1 >= prevOpen + tolerance);
            
            // Check for shadow engulfing
            bool engulfsShadow = (low1 <= prevLow - tolerance) && (high1 >= prevHigh + tolerance);

            // Pattern is valid if either body OR shadow engulfs
            canEngulf = prevIsBearish && currentIsBullishWithTolerance && (engulfsBody || engulfsShadow) && trendOkBull;
        }
        else
        {
            bool prevIsBullish = (prevClose > prevOpen + tolerance);
            bool currentIsBearishWithTolerance = (close1 < open1 - tolerance);
            
            // Check for body engulfing
            bool engulfsBody = (open1 >= prevClose + tolerance) && (close1 <= prevOpen - tolerance);
            
            // Check for shadow engulfing
            bool engulfsShadow = (low1 <= prevLow - tolerance) && (high1 >= prevHigh + tolerance);

            // Pattern is valid if either body OR shadow engulfs
            canEngulf = prevIsBullish && currentIsBearishWithTolerance && (engulfsBody || engulfsShadow) && trendOkBear;
        }
        
        if (canEngulf)
        {
            Print("SIGNAL: ", (bullish ? "Bullish" : "Bearish"), " engulfing pattern detected at bar ", shift);
            DrawEngulfingPattern(shift, bullish);
            
            // Send alert for all engulfing candles
            if(shift == 1) // Only alert for the most recent completed candle - alerts always enabled
            {
                // Calculate stop loss and take profit levels for the alert
                double stopLoss = bullish ? iLow(_Symbol, PERIOD_CURRENT, shift) : iHigh(_Symbol, PERIOD_CURRENT, shift);
                double takeProfit = bullish ? close1 + ((close1 - stopLoss) * 1.5) : close1 - ((stopLoss - close1) * 1.5);
                
                // Create a simple alert message for engulfing patterns
                string direction = bullish ? "BULLISH" : "BEARISH";
                string alertMessage = StringFormat("%s ENGULFING PATTERN - %s", direction, _Symbol);
                
                // Always show chart alert
                Alert(alertMessage);
                
                // Always play sound alert
                PlaySound(Alert_Sound_File);
                
                // Send push notification to mobile
                if(Send_Push_Notifications)
                {
                    string pushMessage = StringFormat("%s Engulfing Pattern - %s", direction, _Symbol);
                    SendNotification(pushMessage);
                    Print("Push notification sent: ", pushMessage);
                }
                
                // Send email alert
                if(Send_Email_Alerts)
                {
                    string emailSubject = StringFormat("Engulfing Pattern Alert: %s %s", direction, _Symbol);
                    SendMail(emailSubject, alertMessage);
                    Print("Email alert sent: ", emailSubject);
                }
                
                // Print to experts log
                Print("=== ENGULFING PATTERN ALERT ===");
                Print(alertMessage);
                Print("====================");
            }
            
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
        Print("ERROR: Failed to create engulfing pattern marker. Error: ", GetLastError());
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
      Print("ERROR: Invalid EMA handle");
      return;
   }
   
   // We want to draw EMA for 200 candles
   const int requiredBars = 200;
   
   // Check if we have enough bars available
   int availableBars = Bars(_Symbol, PERIOD_CURRENT);
   int barsToUse = MathMin(requiredBars, availableBars);
   
   // Resize the array to hold the required values
   ArrayResize(g_ema.values, barsToUse);
   ArraySetAsSeries(g_ema.values, true);
   
   // Copy the EMA values
   int copied = CopyBuffer(g_ema.handle, 0, 0, barsToUse, g_ema.values);
   if(copied < barsToUse)
   {
      if(copied < 2)
      {
         Print("ERROR: Not enough EMA data points for drawing. Available: ", copied);
         return;
      }
   }
   
   // Delete existing EMA objects
   ObjectsDeleteAll(0, "EMA_Line");
   
   // Use a trendline to visualize EMA
   for(int i = 0; i < copied-1; i++)
   {
      string objName = "EMA_Line_" + IntegerToString(i);
      
      datetime time1 = iTime(_Symbol, PERIOD_CURRENT, i);
      datetime time2 = iTime(_Symbol, PERIOD_CURRENT, i+1);
      
      if(time1 == 0 || time2 == 0)
         continue;
      
      if(!ObjectCreate(0, objName, OBJ_TREND, 0, time1, g_ema.values[i], time2, g_ema.values[i+1]))
         continue;
      
      // Make the lines look connected
      ObjectSetInteger(0, objName, OBJPROP_COLOR, EMA_LINE_COLOR);
      ObjectSetInteger(0, objName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, objName, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, objName, OBJPROP_RAY_LEFT, false);
      ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, objName, OBJPROP_BACK, true); // Draw behind price bars
      ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, objName, OBJPROP_HIDDEN, true);
   }
   
   // Force chart redraw
   ChartRedraw(0);
}