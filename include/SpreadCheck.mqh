//+------------------------------------------------------------------+
//|                                                  SpreadCheck.mqh |
//|                        Copyright 2023                            |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023"
#property link      ""
#property version   "1.00"

// Define enums here to avoid errors
enum ENUM_SPREAD_ACTION {
   SPREAD_ACTION_SKIP_TRADE,    // Skip trading when spread is high (not used)
   SPREAD_ACTION_ADJUST_TP_SL,  // Adjust TP/SL when spread is high (not used)
   SPREAD_ACTION_IGNORE         // Ignore high spread and trade anyway
};

//+------------------------------------------------------------------+
//| Always returns true but logs current spread for reference        |
//+------------------------------------------------------------------+
bool IsSpreadAcceptable(int maxAllowedSpread, ENUM_SPREAD_ACTION action=SPREAD_ACTION_IGNORE)
{
   // Get current spread for logging purposes only
   int currentSpread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   
   // Log high spread but always allow trading
   if(currentSpread > maxAllowedSpread)
   {
      string message = "Note: Spread is " + IntegerToString(currentSpread) + 
                      " (above threshold of " + IntegerToString(maxAllowedSpread) + 
                      ") but trading is allowed";
      Print(message);
   }
   
   // Always return true (allow trading regardless of spread)
   return true;
}

//+------------------------------------------------------------------+
//| Log spread value without limiting trades                         |
//+------------------------------------------------------------------+
void LogCurrentSpread()
{
   int currentSpread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   Print("Current spread at order execution: ", currentSpread);
}

//+------------------------------------------------------------------+
//| For compatibility with existing code, does nothing meaningful    |
//+------------------------------------------------------------------+
void AnalyzeHistoricalSpread(int samples=20, double multiplier=1.5)
{
   int currentSpread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   Print("Current spread: ", currentSpread, " (spread limit disabled)");
}

//+------------------------------------------------------------------+
//| For compatibility with existing code, does nothing meaningful    |
//+------------------------------------------------------------------+
void AdjustLevelsForHighSpread(int currentSpread, int normalSpread, 
                              double &stopLoss, double &takeProfit, bool isBuy)
{
   // This function now does nothing since we're ignoring spread
   Print("Spread adjustment disabled, using original SL/TP levels");
}
