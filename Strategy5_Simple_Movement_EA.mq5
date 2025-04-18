//+------------------------------------------------------------------+
//|                                 Strategy5_Simple_Movement_EA.mq5   |
//|                                                                    |
//|                    Simple Movement Test Strategy                   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023"
#property link      ""
#property version   "1.00"
#property strict

// Strategy-specific Magic Number
#define MAGIC_NUMBER 555555

// Trend States
#define TREND_BULLISH 1
#define TREND_BEARISH -1
#define TREND_RANGING 0

// 30-Minute Timeframe Constants
#define OPTIMAL_TIMEFRAME PERIOD_M30 // The optimal timeframe for this EA

// Trend Multipliers for 30-Minute Strategy
input double With_Trend_Multiplier = 1.5;    // Lot multiplier for with-trend trades (following the trend)
input double Counter_Trend_Multiplier = 0.5; // Lot multiplier for counter-trend trades (against the trend)

// Lot Sizing Modes
enum ENUM_LOT_SIZING_MODE
{
   DYNAMIC_MARGIN_CHECK, // Try input lot, fallback to min lot if margin fails
   ALWAYS_MINIMUM_LOT    // Always use the minimum allowed lot size
};

// Input Parameters for 30-Minute Trend Trading
input double      Lot_Size = 1.0;     // Base lot size (used if LotSizing_Mode=DYNAMIC_MARGIN_CHECK)
input bool        Use_Trend_Filter = true;   // Enable/Disable the EMA trend filter
input ENUM_LOT_SIZING_MODE LotSizing_Mode = DYNAMIC_MARGIN_CHECK; // Lot sizing strategy
input bool        DisableTP = true;    // Disable take profit, only use trailing stop
input int         Trail_Activation_Pips = 10; // Pips in profit to activate trailing stop

#include "include/CommonPatternDetection.mqh"

// Global Variables
long barCount;
double volMin, volMax, volStep;

// Constants
#define MAX_MODIFY_ATTEMPTS 3       // Maximum number of attempts to modify a position
#define MODIFY_RETRY_DELAY_MS 500   // Delay between modification attempts in milliseconds

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize EMA indicator
   if(!InitializeEMA())
      return(INIT_FAILED);
      
   // Check if automated trading is allowed
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   {
      Print("Automated trading is not allowed. Please enable it in MetaTrader 5.");
      return(INIT_FAILED);
   }
   
   // Check if trading is allowed for the symbol
   if(!SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_FULL)
   {
      Print("Trading is not allowed for ", _Symbol);
      return(INIT_FAILED);
   }
   
   // Get symbol volume constraints
   volMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   volMax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   volStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   if(volMin <= 0 || volMax <= 0 || volStep <= 0)
   {
      Print("Failed to get valid volume constraints for ", _Symbol);
      return(INIT_FAILED); 
   }
   
   // Initialize barCount
   barCount = Bars(_Symbol, PERIOD_CURRENT);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ReleaseEMA();
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for new bar by comparing current bar count with previous count
   int currentBars = Bars(_Symbol, PERIOD_CURRENT);
   
   // If no new bar formed, only manage trailing stops and exit
   if(currentBars == barCount) 
   {
      ManageTrailingStop();
      return;
   }
   
   // Update bar count as we have a new bar
   barCount = currentBars;
   
   // Verify we're using the optimal timeframe for this strategy
   if(Period() != OPTIMAL_TIMEFRAME)
   {
      Print("WARNING: This EA is optimized for 30-minute timeframe. Current timeframe: ", 
            EnumToString(Period()), ". Performance may be suboptimal.");
   }
   
   // Update all technical indicators for the new bar
   if(!UpdateIndicators()) 
   {
      Print("Failed to update indicators, skipping this bar");
      return;
   }
   
   // Evaluate entry/exit conditions based on the strategy rules
   CheckStrategy();
   
   // Log successful completion of bar processing
   Print("Processed new bar at: ", TimeToString(TimeCurrent()));
}

//+------------------------------------------------------------------+
//| Update indicator values                                           |
//+------------------------------------------------------------------+
bool UpdateIndicators()
{
   // For 30-minute timeframe, we need more bars for reliable trend detection
   // Update EMA with more bars (10 bars should be sufficient for trend detection)
   if(!UpdateEMAValues(10))
   {
      Print("UpdateIndicators: Failed to update EMA values");
      return false;
   }
      
   // Draw EMA line for visual reference
   DrawEMALine();
   
   Print("UpdateIndicators: Successfully updated indicators");
   return true;
}

//+------------------------------------------------------------------+
//| Check strategy conditions                                         |
//+------------------------------------------------------------------+
void CheckStrategy()
{
   int shift = 1; // Check the last completed bar
   double open1 = iOpen(_Symbol, PERIOD_CURRENT, shift);
   double close1 = iClose(_Symbol, PERIOD_CURRENT, shift);
   
   if(open1 == 0 || close1 == 0) return;
   
   // Determine current trend
   int currentTrend = Use_Trend_Filter ? DetermineTrend() : TREND_RANGING;
   
   // Check price movement direction (up or down)
   bool isBuy = (close1 > open1);
   
   // Determine if we should execute the trade based on trend
   bool executeTrade = false;
   
   executeTrade = false;

   if(currentTrend == TREND_BULLISH && isBuy)
       executeTrade = true;
   else if(currentTrend == TREND_BEARISH && !isBuy)
       executeTrade = true;
   // Else, skip

   
   if(executeTrade)
   {
      double lotMultiplier = 1.0;
      
      // Adjust lot size based on trend direction
      if(currentTrend == TREND_BULLISH && isBuy)
      {
         lotMultiplier = With_Trend_Multiplier; // More volume for with-trend buys
      }
      else if(currentTrend == TREND_BEARISH && !isBuy)
      {
         lotMultiplier = With_Trend_Multiplier; // More volume for with-trend sells
      }
      else if((currentTrend == TREND_BULLISH && !isBuy) || (currentTrend == TREND_BEARISH && isBuy))
      {
         lotMultiplier = Counter_Trend_Multiplier; // Less volume for counter-trend trades
      }
      
      // Get current price for SL/TP calculation
      double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      // Execute trade with appropriate lot multiplier
      // SL/TP will be calculated inside ExecuteTrade using ValidateStopLevel
      if(isBuy)
      {
         ExecuteTrade(true, lotMultiplier);
      }
      else
      {
         ExecuteTrade(false, lotMultiplier);
      }
   }
}

//+------------------------------------------------------------------+
//| Get EMA value for specified shift                                 |
//+------------------------------------------------------------------+
double GetEMAValue(int shift)
{
   if(g_ema.handle == INVALID_HANDLE)
   {
      Print("GetEMAValue: Invalid EMA handle");
      return 0;
   }
   
   if(shift >= ArraySize(g_ema.values))
   {
      Print("GetEMAValue: Requested shift ", shift, " exceeds available data (", ArraySize(g_ema.values), ")");
      return 0;
   }
   
   return g_ema.values[shift];
}

//+------------------------------------------------------------------+
//| Determine current market trend                                    |
//+------------------------------------------------------------------+
int DetermineTrend()
{
   // For 30-minute timeframe, we need to check more bars for reliable trend detection
   double ema0 = GetEMAValue(0); // Current bar
   double ema1 = GetEMAValue(1); // Previous bar
   double ema2 = GetEMAValue(2); // Two bars ago
   double ema3 = GetEMAValue(3); // Three bars ago
   double ema4 = GetEMAValue(4); // Four bars ago
   
   // Get current price and recent prices
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double previousClose = iClose(_Symbol, PERIOD_CURRENT, 1);
   
   // For 30-minute timeframe, check more bars for a stronger trend confirmation
   bool risingEMA = (ema0 > ema1 && ema1 > ema2 && ema2 > ema3 && ema3 > ema4);
   bool fallingEMA = (ema0 < ema1 && ema1 < ema2 && ema2 < ema3 && ema3 < ema4);
   
   // Check price position relative to EMA
   bool priceAboveEMA = (currentPrice > ema0) && (previousClose > ema1);
   bool priceBelowEMA = (currentPrice < ema0) && (previousClose < ema1);
   
   // Determine trend based on multiple factors
   if(risingEMA && priceAboveEMA)
      return TREND_BULLISH;
   else if(fallingEMA && priceBelowEMA)
      return TREND_BEARISH;
   else
      return TREND_RANGING;
}

//+------------------------------------------------------------------+
//| Execute trade                                                     |
//+------------------------------------------------------------------+
void ExecuteTrade(bool isBuy, double lotMultiplier = 1.0)
{
   double baseLotSize = GetLotSize();
   if(baseLotSize <= 0) return;

   double lotSize = NormalizeDouble(baseLotSize * lotMultiplier, 2);
   lotSize = MathMax(lotSize, volMin);
   lotSize = MathMin(lotSize, volMax);
   lotSize = MathRound(lotSize / volStep) * volStep;

   double entryPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Pre-calculate TP only (SL will be recalculated per attempt)
   double preTP = (!DisableTP) ? ValidateStopLevel(0, isBuy, false, entryPrice) : 0;

   MqlTradeRequest request = {};
   MqlTradeResult result = {};

   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lotSize;
   request.type = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   request.price = entryPrice;
   request.sl = 0;
   request.tp = 0;
   request.deviation = 10;
   request.magic = MAGIC_NUMBER;
   request.comment = "Strategy 5 " + (isBuy ? "Buy" : "Sell") + " Trend: " + 
                     (DetermineTrend() == TREND_BULLISH ? "Bullish" : 
                      DetermineTrend() == TREND_BEARISH ? "Bearish" : "Ranging");

   if(!OrderSend(request, result))
   {
      Print("OrderSend failed. Error: ", GetLastError(), " Retcode: ", result.retcode);
      return;
   }

   if(result.retcode != TRADE_RETCODE_DONE)
   {
      Print("OrderSend retcode indicates failure: ", result.retcode, " Comment: ", result.comment);
      return;
   }

   Print("Trade executed. Ticket: ", result.order, 
         " Type: ", (isBuy ? "Buy" : "Sell"), 
         " Lot: ", lotSize, 
         " Price: ", entryPrice);

   // --- Modify SL/TP after successful order (recalculate SL each attempt) ---
   MqlTradeRequest modRequest = {};
   MqlTradeResult modResult = {};

   modRequest.action = TRADE_ACTION_SLTP;
   modRequest.position = result.order;
   modRequest.symbol = _Symbol;
   modRequest.tp = preTP;

   int modifyAttempts = 0;
   const int maxModifyAttempts = 5;
   bool modified = false;

   while(modifyAttempts < maxModifyAttempts)
   {
      double latestPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double dynamicSL = ValidateStopLevel(0, isBuy, true, latestPrice);  // dynamically refreshed

      modRequest.sl = dynamicSL;

      if(OrderSend(modRequest, modResult) && modResult.retcode == TRADE_RETCODE_DONE)
      {
         Print("SL/TP successfully applied post-order. SL: ", dynamicSL, " TP: ", preTP);
         modified = true;
         break;
      }

      Print("Failed to modify SL (attempt ", modifyAttempts+1, "). Error: ", GetLastError(), 
            " Retcode: ", modResult.retcode, " Msg: ", modResult.comment);

      if(modResult.retcode != TRADE_RETCODE_INVALID_STOPS)
         break; // Stop on any non-SL error

      Sleep(200);
      modifyAttempts++;
   }

   if(!modified)
   {
      Print("SL/TP modification failed after ", maxModifyAttempts, " attempts.");
   }
}




//+------------------------------------------------------------------+
//| Validate and set stop level at broker minimum                     |
//+------------------------------------------------------------------+
double ValidateStopLevel(double currentPrice, bool isBuy, bool isStopLoss, double marketPrice = 0)
{
   // 1) Broker min‑stop in *points*
   long stopPoints = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double point    = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double minDist  = stopPoints * point;              // in price terms
   double tick     = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   int    digits   = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   // Never allow below one tick
   if(minDist < tick) 
      minDist = tick;

   // 2) Determine the reference price for calculation
   // Use provided marketPrice if valid, otherwise use currentPrice if valid, else fetch current Ask/Bid
   double referencePrice = 0;
   if (marketPrice > 0)
   {
       referencePrice = marketPrice; // Use explicitly passed market price
   }
   else if (currentPrice > 0)
   {
       referencePrice = currentPrice; // Use price passed for trailing stop context
   }
   else
   {
       referencePrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID); // Fetch current market price
   }

   // --- Add Buffer to Minimum Distance ---
   double bufferPoints = 10; // Add a 10-point (1 pip for most pairs) buffer
   double bufferPrice = bufferPoints * point;
   double minDistWithBuffer = minDist + bufferPrice; // Add buffer directly to min distance

   // 3) Compute raw stop level using the buffered minimum distance relative to the referencePrice
   double rawStopLevel = 0;
   if(isStopLoss)
      rawStopLevel = isBuy ? (referencePrice - minDistWithBuffer)
                           : (referencePrice + minDistWithBuffer);
   else  // take‑profit
      rawStopLevel = isBuy ? (referencePrice + minDistWithBuffer)
                           : (referencePrice - minDistWithBuffer);

   // 4) Round the final level *away* from the referencePrice so we never violate min‑distance
   double finalNormalizedLevel;
   if(isStopLoss)
   {
      // for SL, round further away from entry
      finalNormalizedLevel = isBuy
                             ? MathFloor(rawStopLevel / tick) * tick
                             : MathCeil (rawStopLevel / tick) * tick;
   }
   else // Take Profit
   {
      // for TP, round further away from entry
      finalNormalizedLevel = isBuy
                             ? MathCeil (rawStopLevel / tick) * tick
                             : MathFloor(rawStopLevel / tick) * tick;
   }
   finalNormalizedLevel = NormalizeDouble(finalNormalizedLevel, digits);

   return finalNormalizedLevel; // Return the final buffered and normalized level
}



//+------------------------------------------------------------------+
//| Get appropriate lot size based on mode and margin                 |
//+------------------------------------------------------------------+
double GetLotSize()
{
   double lotSize = LotSizing_Mode == ALWAYS_MINIMUM_LOT ? volMin : Lot_Size;
   lotSize = MathMax(lotSize, volMin);
   lotSize = MathMin(lotSize, volMax);
   
   double marginRequired;
   if(!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lotSize, SymbolInfoDouble(_Symbol, SYMBOL_ASK), marginRequired))
   {
      Print("Error calculating margin. Error code: ", GetLastError());
      return 0;
   }
   
   if(marginRequired > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
   {
      if(LotSizing_Mode == DYNAMIC_MARGIN_CHECK)
      {
         lotSize = volMin;
         if(!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lotSize, SymbolInfoDouble(_Symbol, SYMBOL_ASK), marginRequired))
         {
            Print("Error calculating margin for minimum lot size. Error code: ", GetLastError());
            return 0;
         }
         
         if(marginRequired > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
         {
            Print("Insufficient margin even for minimum lot size");
            return 0;
         }
      }
      else
      {
         Print("Insufficient margin for desired lot size");
         return 0;
      }
   }
   
   return lotSize;
}


//+------------------------------------------------------------------+
//| Manage trailing stop                                              |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
         PositionGetInteger(POSITION_MAGIC) != MAGIC_NUMBER)
         continue;
         
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      
      bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double currentPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      double profitPips = isBuy ? (currentPrice - openPrice) / _Point :
                                 (openPrice - currentPrice) / _Point;
                                 
      // Only activate trailing stop if position is in profit by the required amount
      if(profitPips >= Trail_Activation_Pips)
      {
         // Set new SL at broker minimum distance from current price (always uses broker minimum)
         double newSL = ValidateStopLevel(currentPrice, isBuy, true);
         bool modifyNeeded = false;
         
         if(isBuy)
         {
            // Only modify if new stop loss is higher than current one
            modifyNeeded = (currentSL == 0 || newSL > currentSL);
         }
         else
         {
            // Only modify if new stop loss is lower than current one
            modifyNeeded = (currentSL == 0 || newSL < currentSL);
         }
         
         if(modifyNeeded)
         {
            // Try to modify the position with multiple attempts if needed
            bool modifySuccess = false;
            int attempts = 0;
            
            while(!modifySuccess && attempts < MAX_MODIFY_ATTEMPTS)
            {
               MqlTradeRequest request = {};
               MqlTradeResult result = {};
               
               request.action = TRADE_ACTION_SLTP;
               request.position = ticket;
               request.sl = newSL;
               request.tp = PositionGetDouble(POSITION_TP);
               
               // Log the modification attempt
               Print("Attempting to modify SL for ticket ", ticket,
                     ", Current price: ", currentPrice,
                     ", New SL: ", newSL,
                     ", Current SL: ", currentSL);
               
               modifySuccess = OrderSend(request, result);
               
               if(!modifySuccess)
               {
                  int error = GetLastError();
                  Print("Failed to modify trailing stop. Error: ", error, 
                        " Attempt: ", attempts + 1, " of ", MAX_MODIFY_ATTEMPTS);
                  
                  // Wait before retrying
                  Sleep(MODIFY_RETRY_DELAY_MS);
               }
               else
               {
                  Print("Successfully modified trailing stop for ticket ", ticket, 
                        " New SL: ", newSL, " Profit pips: ", profitPips);
               }
               
               attempts++;
            }
         }
      }
   }
}
