//+------------------------------------------------------------------+
//|                                                  SpreadCheck.mqh |
//|                        Copyright 2024, Your Name                 |
//|                                             https://www.yoursite.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Your Name"
#property link      "https://www.yoursite.com"
#property version   "1.00"

// Enumeration for spread handling options
enum ENUM_SPREAD_ACTION {
   SPREAD_ACTION_SKIP_TRADE,    // Skip trading when spread is high
   SPREAD_ACTION_ADJUST_TP_SL,  // Adjust TP/SL when spread is high
   SPREAD_ACTION_IGNORE         // Ignore high spread and trade anyway
};

//+------------------------------------------------------------------+
//| Check if current spread is acceptable for trading                |
//+------------------------------------------------------------------+
bool IsSpreadAcceptable(int maxAllowedSpread)
{
   int currentSpread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   
   if(currentSpread > maxAllowedSpread)
   {
      string message = "Spread too high: " + IntegerToString(currentSpread);
      Print(message);
      Comment(message);
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

//+------------------------------------------------------------------+
//| Advanced spread handler with multiple options                    |
//+------------------------------------------------------------------+
bool HandleSpread(int maxAllowedSpread, ENUM_SPREAD_ACTION action, 
                 double &adjustedSL, double &adjustedTP)
{
   int currentSpread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   string spreadMsg = "Current spread: " + IntegerToString(currentSpread);
   Print(spreadMsg);
   
   // If spread is acceptable, no action needed
   if(currentSpread <= maxAllowedSpread)
      return true;
      
   // Handle based on selected action
   switch(action)
   {
      case SPREAD_ACTION_SKIP_TRADE:
      {
         Print("Spread too high: ", currentSpread, " - Skipping trade");
         Comment("Spread too high: ", currentSpread, " - Skipping trade");
         return false;
      }
         
      case SPREAD_ACTION_ADJUST_TP_SL:
      {
         int extraPoints = currentSpread - maxAllowedSpread;
         adjustedSL += extraPoints * _Point;
         adjustedTP += extraPoints * _Point;
         Print("Spread too high: ", currentSpread, " - Adjusted SL/TP");
         return true;
      }
         
      case SPREAD_ACTION_IGNORE:
      {
         Print("Trading despite high spread: ", currentSpread);
         return true;
      }
         
      default:
         return false;
   }
}

//+------------------------------------------------------------------+
//| Get historical spread statistics                                 |
//+------------------------------------------------------------------+
void AnalyzeSpreadHistory(int &avgSpread, int &maxSpread, int &minSpread, int bars=100)
{
   avgSpread = 0;
   maxSpread = 0;
   minSpread = INT_MAX;
   
   double totalSpread = 0.0;
   
   for(int i=0; i<bars; i++)
   {
      int spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      
      // Update statistics
      totalSpread += spread;
      
      if(spread > maxSpread)
         maxSpread = spread;
         
      if(spread < minSpread)
         minSpread = spread;
         
      // Small delay to get different spread measurements
      Sleep(50);
   }
   
   // Calculate average - avoid type conversion warnings
   if(bars > 0)
      avgSpread = (int)(totalSpread / bars);
      
   Print("Spread Analysis - Avg: ", avgSpread, ", Max: ", maxSpread, ", Min: ", minSpread);
}
