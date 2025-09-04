//+------------------------------------------------------------------+
//|                                            PriceStructure.mqh     |
//|                                                                    |
//|                    Price Structure Functions for Strategy1        |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Check for valid price structure                                   |
//+------------------------------------------------------------------+
bool IsValidPriceStructure(int startBar, int endBar, bool isBullish)
{
   double highs[], lows[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);
   
   if(CopyHigh(_Symbol, PERIOD_CURRENT, 0, startBar + 1, highs) != startBar + 1 ||
      CopyLow(_Symbol, PERIOD_CURRENT, 0, startBar + 1, lows) != startBar + 1)
      return false;
      
   if(isBullish)
   {
      bool hadLowerLows = false;
      for(int i = startBar + 1; i < ArraySize(lows) - 1; i++)
      {
         if(lows[i] < lows[i-1])
         {
            hadLowerLows = true;
            break;
         }
      }
      
      if(!hadLowerLows) return false;
      
      double lowestLow = lows[startBar];
      double highestHigh = highs[startBar];
      
      for(int i = startBar-1; i >= endBar; i--)
      {
         if(highs[i] > highestHigh || lows[i] > lowestLow)
            return false;
      }
   }
   else
   {
      bool hadHigherHighs = false;
      for(int i = startBar + 1; i < ArraySize(highs) - 1; i++)
      {
         if(highs[i] > highs[i-1])
         {
            hadHigherHighs = true;
            break;
         }
      }
      
      if(!hadHigherHighs) return false;
      
      double highestLow = lows[startBar];
      double lowestHigh = highs[startBar];
      
      for(int i = startBar-1; i >= endBar; i--)
      {
         if(lows[i] < highestLow || highs[i] < lowestHigh)
            return false;
      }
   }
   
   return true;
}