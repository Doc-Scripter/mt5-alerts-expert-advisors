//+------------------------------------------------------------------+
//|                                        IndicatorManagement.mqh    |
//|                                                                    |
//|                    Indicator Management Functions for Strategy1    |
//+------------------------------------------------------------------+

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