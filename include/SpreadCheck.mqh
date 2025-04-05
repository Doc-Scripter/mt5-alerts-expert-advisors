//+------------------------------------------------------------------+
//|                                                  SpreadCheck.mqh |
//|                        Copyright 2024, Your Name                 |
//|                                             https://www.yoursite.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Your Name"
#property link      "https://www.yoursite.com"
#property version   "1.00"

//+------------------------------------------------------------------+
//| Check if current spread is acceptable for trading                |
//+------------------------------------------------------------------+
bool IsSpreadAcceptable(int maxAllowedSpread)
{
   int currentSpread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   
   if(currentSpread > maxAllowedSpread)
   {
      Print("Spread too high: ", currentSpread);
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Log spread value to journal for monitoring                       |
//+------------------------------------------------------------------+
void LogCurrentSpread()
{
   int currentSpread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   Print("Current spread: ", currentSpread);
}