//+------------------------------------------------------------------+
//|                                           TrendDetection.mqh      |
//|                                                                   |
//|                                                                   |
//+------------------------------------------------------------------+

#property copyright "Copyright 2023"
#property link      ""
#property strict

// Trend States
#define TREND_BULLISH 1
#define TREND_BEARISH -1
#define TREND_RANGING 0

// Trend Formation States
#define TREND_FORMING_BULLISH 2
#define TREND_FORMING_BEARISH -2
#define TREND_EXHAUSTING_BULLISH 3
#define TREND_EXHAUSTING_BEARISH -3

//+------------------------------------------------------------------+
//| Get ADX threshold based on volatility index                       |
//+------------------------------------------------------------------+
double GetVolatilityADXThreshold()
{
   string symbol = _Symbol;
   
   // Volatility 10 Index
   if(StringFind(symbol, "Vol10") >= 0 || StringFind(symbol, "V10") >= 0)
      return 20.0;  // Lower threshold for less volatile index
      
   // Volatility 10 (1s) Index
   if(StringFind(symbol, "Vol10_1s") >= 0 || StringFind(symbol, "V10_1s") >= 0)
      return 20.0;
      
   // Volatility 15 (1s) Index
   if(StringFind(symbol, "Vol15_1s") >= 0 || StringFind(symbol, "V15_1s") >= 0)
      return 22.0;
      
   // Volatility 25 Index
   if(StringFind(symbol, "Vol25") >= 0 || StringFind(symbol, "V25") >= 0)
      return 24.0;  // Standard threshold
      
   // Volatility 25 (1s) Index
   if(StringFind(symbol, "Vol25_1s") >= 0 || StringFind(symbol, "V25_1s") >= 0)
      return 25.0;
      
   // Volatility 30 (1s) Index
   if(StringFind(symbol, "Vol30_1s") >= 0 || StringFind(symbol, "V30_1s") >= 0)
      return 27.0;
      
   // Volatility 50 Index
   if(StringFind(symbol, "Vol50") >= 0 || StringFind(symbol, "V50") >= 0)
      return 30.0;  // Higher threshold for more volatile index
      
   // Volatility 75 Index
   if(StringFind(symbol, "Vol75") >= 0 || StringFind(symbol, "V75") >= 0)
      return 32.0;  // Even higher threshold
      
   // Volatility Jump 10 Index
   if(StringFind(symbol, "Jump10") >= 0 || StringFind(symbol, "J10") >= 0)
      return 28.0;  // Special threshold for jump index
      
   // Default threshold for other symbols
   return 25.0;
}

//+------------------------------------------------------------------+
//| Check for early trend formation                                   |
//+------------------------------------------------------------------+
bool IsEarlyTrendForming(bool isBullish)
{
   // Copy more data for trend formation analysis
   double fastEMA[], mediumEMA[], slowEMA[], adx[], plusDI[], minusDI[];
   
   ArrayResize(fastEMA, 3);
   ArrayResize(mediumEMA, 3);
   ArrayResize(slowEMA, 3);
   ArrayResize(adx, 3);
   ArrayResize(plusDI, 3);
   ArrayResize(minusDI, 3);
   
   ArraySetAsSeries(fastEMA, true);
   ArraySetAsSeries(mediumEMA, true);
   ArraySetAsSeries(slowEMA, true);
   ArraySetAsSeries(adx, true);
   ArraySetAsSeries(plusDI, true);
   ArraySetAsSeries(minusDI, true);
   
   // Copy recent values
   CopyBuffer(trendFastEmaHandle, 0, 0, 3, fastEMA);
   CopyBuffer(trendMediumEmaHandle, 0, 0, 3, mediumEMA);
   CopyBuffer(trendSlowEmaHandle, 0, 0, 3, slowEMA);
   CopyBuffer(trendAdxHandle, 0, 0, 3, adx);
   CopyBuffer(trendAdxHandle, 1, 0, 3, plusDI);  // +DI line
   CopyBuffer(trendAdxHandle, 2, 0, 3, minusDI); // -DI line
   
   // Early bullish trend formation conditions
   if(isBullish)
   {
      // Fast EMA crossing above medium EMA
      bool fastCrossingMedium = fastEMA[1] <= mediumEMA[1] && fastEMA[0] > mediumEMA[0];
      
      // ADX starting to rise from low levels
      bool adxRising = adx[0] > adx[1] && adx[1] > adx[2] && adx[0] < GetVolatilityADXThreshold();
      
      // +DI crossing above -DI
      bool diCrossing = plusDI[1] <= minusDI[1] && plusDI[0] > minusDI[0];
      
      return (fastCrossingMedium || diCrossing) && adxRising;
   }
   // Early bearish trend formation conditions
   else
   {
      // Fast EMA crossing below medium EMA
      bool fastCrossingMedium = fastEMA[1] >= mediumEMA[1] && fastEMA[0] < mediumEMA[0];
      
      // ADX starting to rise from low levels
      bool adxRising = adx[0] > adx[1] && adx[1] > adx[2] && adx[0] < GetVolatilityADXThreshold();
      
      // -DI crossing above +DI
      bool diCrossing = minusDI[1] <= plusDI[1] && minusDI[0] > plusDI[0];
      
      return (fastCrossingMedium || diCrossing) && adxRising;
   }
}

//+------------------------------------------------------------------+
//| Check for trend exhaustion                                        |
//+------------------------------------------------------------------+
bool IsTrendExhausting(bool isBullish)
{
   // Copy more data for trend exhaustion analysis
   double fastEMA[], mediumEMA[], slowEMA[], adx[], plusDI[], minusDI[];
   
   ArrayResize(fastEMA, 5);
   ArrayResize(mediumEMA, 5);
   ArrayResize(slowEMA, 5);
   ArrayResize(adx, 5);
   ArrayResize(plusDI, 5);
   ArrayResize(minusDI, 5);
   
   ArraySetAsSeries(fastEMA, true);
   ArraySetAsSeries(mediumEMA, true);
   ArraySetAsSeries(slowEMA, true);
   ArraySetAsSeries(adx, true);
   ArraySetAsSeries(plusDI, true);
   ArraySetAsSeries(minusDI, true);
   
   // Copy recent values
   CopyBuffer(trendFastEmaHandle, 0, 0, 5, fastEMA);
   CopyBuffer(trendMediumEmaHandle, 0, 0, 5, mediumEMA);
   CopyBuffer(trendSlowEmaHandle, 0, 0, 5, slowEMA);
   CopyBuffer(trendAdxHandle, 0, 0, 5, adx);
   CopyBuffer(trendAdxHandle, 1, 0, 5, plusDI);  // +DI line
   CopyBuffer(trendAdxHandle, 2, 0, 5, minusDI); // -DI line
   
   // Bullish trend exhaustion conditions
   if(isBullish)
   {
      // ADX starting to decline after being above threshold
      bool adxDeclining = adx[0] < adx[1] && adx[1] < adx[2] && adx[2] > GetVolatilityADXThreshold();
      
      // Fast EMA flattening or starting to curve down
      bool emaFlattening = (fastEMA[0] - fastEMA[1]) < (fastEMA[1] - fastEMA[2]) * 0.5;
      
      // +DI declining
      bool diDeclining = plusDI[0] < plusDI[1] && plusDI[1] < plusDI[2];
      
      return adxDeclining && (emaFlattening || diDeclining);
   }
   // Bearish trend exhaustion conditions
   else
   {
      // ADX starting to decline after being above threshold
      bool adxDeclining = adx[0] < adx[1] && adx[1] < adx[2] && adx[2] > GetVolatilityADXThreshold();
      
      // Fast EMA flattening or starting to curve up
      bool emaFlattening = (fastEMA[1] - fastEMA[0]) < (fastEMA[2] - fastEMA[1]) * 0.5;
      
      // -DI declining
      bool diDeclining = minusDI[0] < minusDI[1] && minusDI[1] < minusDI[2];
      
      return adxDeclining && (emaFlattening || diDeclining);
   }
}

//+------------------------------------------------------------------+
//| Get current trend state                                          |
//+------------------------------------------------------------------+
int GetTrendState()
{
   if(!Use_Trend_Filter) return TREND_RANGING;
   
   double fastEMA = trendFastEmaValues[0];
   double mediumEMA = trendMediumEmaValues[0];
   double slowEMA = trendSlowEmaValues[0];
   double adxValue = trendAdxValues[0];
   
   // Check if we have enough data
   if(fastEMA <= 0 || slowEMA <= 0 || adxValue <= 0)
   {
      Print("WARNING: Trend filter has invalid indicator values");
      return TREND_RANGING; // Default to ranging if data is invalid
   }
   
   // Get volatility-adjusted ADX threshold
   double adxThreshold = GetVolatilityADXThreshold();
   
   // Strong trend conditions
   bool isStrongTrend = (adxValue >= adxThreshold);
   
   // Determine trend direction based on EMA alignment
   if(isStrongTrend)
   {
      // For strong trends, require clear EMA alignment
      if(fastEMA > mediumEMA && mediumEMA > slowEMA)
      {
         // Check for trend exhaustion
         if(IsTrendExhausting(true))
         {
            Print("INFO: Bullish trend showing exhaustion signs (ADX: ", adxValue, ")");
            return TREND_EXHAUSTING_BULLISH;
         }
         
         Print("INFO: Strong bullish trend detected (ADX: ", adxValue, ")");
         return TREND_BULLISH;
      }
      else if(fastEMA < mediumEMA && mediumEMA < slowEMA)
      {
         // Check for trend exhaustion
         if(IsTrendExhausting(false))
         {
            Print("INFO: Bearish trend showing exhaustion signs (ADX: ", adxValue, ")");
            return TREND_EXHAUSTING_BEARISH;
         }
         
         Print("INFO: Strong bearish trend detected (ADX: ", adxValue, ")");
         return TREND_BEARISH;
      }
   }
   else
   {
      // Check for early trend formation
      if(IsEarlyTrendForming(true))
      {
         Print("INFO: Early bullish trend formation detected (ADX: ", adxValue, ")");
         return TREND_FORMING_BULLISH;
      }
      else if(IsEarlyTrendForming(false))
      {
         Print("INFO: Early bearish trend formation detected (ADX: ", adxValue, ")");
         return TREND_FORMING_BEARISH;
      }
   }
   
   // If we reach here, we're in a ranging market or weak trend
   Print("INFO: Market is ranging or has weak trend (ADX: ", adxValue, ") - No trading allowed");
   return TREND_RANGING;
}