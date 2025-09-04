//+------------------------------------------------------------------+
//|                                             SwingAnalysis.mqh     |
//|                                                                    |
//|                      Swing Analysis Functions for Strategy1       |
//+------------------------------------------------------------------+

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