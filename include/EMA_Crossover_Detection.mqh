// EMA Crossover Detection Functions
// Used primarily by Strategy1

//+------------------------------------------------------------------+
//| Check for EMA crossover                                           |
//+------------------------------------------------------------------+
bool IsEmaCrossover(double &emaValues[], int shift, bool &crossAbove)
{
   if(ArraySize(emaValues) < shift + 2)
      return false;
      
   double currentClose = iClose(_Symbol, PERIOD_CURRENT, shift);
   double prevClose = iClose(_Symbol, PERIOD_CURRENT, shift + 1);
   
   bool currentAboveEma = currentClose > emaValues[shift];
   bool prevAboveEma = prevClose > emaValues[shift + 1];
   
   // Check for crossover
   if(currentAboveEma != prevAboveEma)
   {
      crossAbove = currentAboveEma;
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check for price crossing EMA                                      |
//+------------------------------------------------------------------+
bool IsPriceCrossingEma(double &emaValues[], int shift, bool &crossAbove)
{
   if(ArraySize(emaValues) < shift + 1)
      return false;
      
   double high = iHigh(_Symbol, PERIOD_CURRENT, shift);
   double low = iLow(_Symbol, PERIOD_CURRENT, shift);
   double close = iClose(_Symbol, PERIOD_CURRENT, shift);
   double ema = emaValues[shift];
   
   // Check for bullish crossover (low below EMA, close above EMA)
   if(low <= ema && close > ema)
   {
      crossAbove = true;
      return true;
   }
   
   // Check for bearish crossover (high above EMA, close below EMA)
   if(high >= ema && close < ema)
   {
      crossAbove = false;
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check for EMA crossover with confirmation                         |
//+------------------------------------------------------------------+
bool IsEmaCrossoverWithConfirmation(double &emaValues[], int shift, bool &crossAbove, int confirmationBars = 1)
{
   if(!IsEmaCrossover(emaValues, shift, crossAbove))
      return false;
      
   // Check for confirmation
   for(int i = 1; i <= confirmationBars; i++)
   {
      double checkClose = iClose(_Symbol, PERIOD_CURRENT, shift + i);
      bool checkAboveEma = checkClose > emaValues[shift + i];
      
      // If the previous bars don't confirm the crossover direction, return false
      if(crossAbove == checkAboveEma)
         return false;
   }
   
   return true;
}