//+------------------------------------------------------------------+
//|                                            PatternMarking.mqh     |
//|                                                                    |
//|                    Pattern Marking Functions for Strategy1        |
//+------------------------------------------------------------------+

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