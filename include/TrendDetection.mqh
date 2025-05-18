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
   
   // Strong trend conditions
   bool isStrongTrend = (adxValue >= 25.0);
   
   // Determine trend direction based on EMA alignment
   if(isStrongTrend)
   {
      // For strong trends, require clear EMA alignment
      if(fastEMA > mediumEMA && mediumEMA > slowEMA)
      {
         Print("INFO: Strong bullish trend detected (ADX: ", adxValue, ")");
         return TREND_BULLISH;
      }
      else if(fastEMA < mediumEMA && mediumEMA < slowEMA)
      {
         Print("INFO: Strong bearish trend detected (ADX: ", adxValue, ")");
         return TREND_BEARISH;
      }
   }
   
   // If we reach here, we're in a ranging market or weak trend
   // Instead of allowing trades in ranging markets, we'll block them
   Print("INFO: Market is ranging or has weak trend (ADX: ", adxValue, ") - No trading allowed");
   return TREND_RANGING;
}