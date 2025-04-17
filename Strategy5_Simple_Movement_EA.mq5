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
   // Check for new bar
   int currentBars = Bars(_Symbol, PERIOD_CURRENT);
   
   // Only manage trailing stop on tick updates (not on new bars)
   if(currentBars == barCount) 
   {
      ManageTrailingStop();
      return;
   }
   
   barCount = currentBars;
   
   // For 30-minute timeframe optimization, check if we're on the correct timeframe
   if(Period() != PERIOD_M30 && Period() != PERIOD_CURRENT)
   {
      Print("Warning: EA is optimized for 30-minute timeframe. Current timeframe: ", EnumToString(Period()));
   }
   
   // Update indicators
   if(!UpdateIndicators()) 
   {
      Print("Failed to update indicators, skipping this bar");
      return;
   }
   
   // Check strategy conditions
   CheckStrategy();
   
   // Log completion of bar processing
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
   
   if(currentTrend == TREND_BULLISH)
   {
      // In bullish trend, take buy signals only
      executeTrade = isBuy;
   }
   else if(currentTrend == TREND_BEARISH)
   {
      // In bearish trend, take sell signals only
      executeTrade = !isBuy;
   }
   else // TREND_RANGING
   {
      // In ranging market, take both buy and sell signals
      executeTrade = true;
   }
   
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
      
      if(isBuy)
      {
         // Execute buy trade with broker minimum SL/TP
         ExecuteTrade(true, 0, 0, lotMultiplier);
      }
      else
      {
         // Execute sell trade with broker minimum SL/TP
         ExecuteTrade(false, 0, 0, lotMultiplier);
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
void ExecuteTrade(bool isBuy, double dummyStopLoss, double dummyTakeProfit, double lotMultiplier = 1.0)
{
   double baseLotSize = GetLotSize();
   if(baseLotSize <= 0) return;
   
   // Apply the lot multiplier
   double lotSize = NormalizeDouble(baseLotSize * lotMultiplier, 2);
   
   // Ensure lot size is within allowed range
   lotSize = MathMax(lotSize, volMin);
   lotSize = MathMin(lotSize, volMax);
   
   // Round to the nearest valid lot step
   lotSize = MathRound(lotSize / volStep) * volStep;
   
   // Get current price
   double currentPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // Always set SL/TP at broker minimum distance from current price
   double validatedStopLoss = ValidateStopLevel(currentPrice, isBuy, true);
   
   // Validate and adjust take profit (always uses broker minimum distance)
   double validatedTakeProfit = 0;
   if(!DisableTP)
      validatedTakeProfit = ValidateStopLevel(currentPrice, isBuy, false);
   
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lotSize;
   request.type = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   request.price = currentPrice;
   request.sl = validatedStopLoss;
   if(!DisableTP) request.tp = validatedTakeProfit;
   request.deviation = 10;
   request.magic = MAGIC_NUMBER;
   request.comment = "Strategy 5 " + (isBuy ? "Buy" : "Sell") + " Trend: " + 
                     (DetermineTrend() == TREND_BULLISH ? "Bullish" : 
                      DetermineTrend() == TREND_BEARISH ? "Bearish" : "Ranging");
   
   // Log the trade details before sending
   Print("Attempting to open ", (isBuy ? "BUY" : "SELL"), " position: ",
         "Price: ", request.price,
         ", SL: ", request.sl,
         ", TP: ", request.tp,
         ", Lot: ", lotSize);
   
   if(!OrderSend(request, result))
   {
      Print("OrderSend failed with error: ", GetLastError());
      return;
   }
   
   if(result.retcode == TRADE_RETCODE_DONE)
   {
      Print("Trade executed successfully. Ticket: ", result.order, 
            " Type: ", (isBuy ? "Buy" : "Sell"), 
            " Lot: ", lotSize, 
            " (Base: ", baseLotSize, ", Multiplier: ", lotMultiplier, ")");
   }
}

//+------------------------------------------------------------------+
//| Validate and set stop level at broker minimum                     |
//+------------------------------------------------------------------+
double ValidateStopLevel(double price, bool isBuy, bool isStopLoss)
{
   // Get minimum stop level in points
   long minStopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDistance = minStopLevel * _Point;
   
   // For indices and other instruments with large point values, ensure minimum distance
   if(minDistance < 1.0)
      minDistance = 10 * _Point; // Use at least 10 points as minimum distance
   
   if(isBuy)
   {
      if(isStopLoss)
      {
         // For buy orders, stop loss must be below current price
         return price - minDistance;
      }
      else
      {
         // For buy orders, take profit must be above current price
         return price + minDistance;
      }
   }
   else
   {
      if(isStopLoss)
      {
         // For sell orders, stop loss must be above current price
         return price + minDistance;
      }
      else
      {
         // For sell orders, take profit must be below current price
         return price - minDistance;
      }
   }
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
         double minStopDistance = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
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
                     ", Current SL: ", currentSL,
                     ", Min distance: ", minStopDistance);
               
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
