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

// Lot Sizing Modes
enum ENUM_LOT_SIZING_MODE
{
   DYNAMIC_MARGIN_CHECK, // Try input lot, fallback to min lot if margin fails
   ALWAYS_MINIMUM_LOT    // Always use the minimum allowed lot size
};

// Input Parameters
input double      Lot_Size = 1.0;     // Entry lot size (used if LotSizing_Mode=DYNAMIC_MARGIN_CHECK)
input ENUM_LOT_SIZING_MODE LotSizing_Mode = DYNAMIC_MARGIN_CHECK; // Lot sizing strategy
input int         Min_Body_Pips = 1;   // Minimum candle body size in pips
input int         TP_Pips = 10;        // Take Profit distance in pips
input bool        DisableTP = true;    // Disable take profit, only use trailing stop
input int         Trail_Activation_Pips = 10; // Pips in profit to activate trailing stop
input int         Trail_Pips = 5;      // Trailing stop distance in pips

// Global Variables
long barCount;
double volMin, volMax, volStep;
datetime g_lastTradeTime = 0;

// Constants
#define STRATEGY_COOLDOWN_MINUTES 60

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
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
   // Nothing to clean up for this strategy
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for new bar
   int currentBars = Bars(_Symbol, PERIOD_CURRENT);
   if(currentBars == barCount) 
   {
      ManageTrailingStop();
      return;
   }
   barCount = currentBars;
   
   // Check strategy conditions
   CheckStrategy();
}

//+------------------------------------------------------------------+
//| Check strategy conditions                                         |
//+------------------------------------------------------------------+
void CheckStrategy()
{
   // Check cooldown
   if(IsStrategyOnCooldown()) return;
   
   int shift = 1; // Check the last completed bar
   double open1 = iOpen(_Symbol, PERIOD_CURRENT, shift);
   double close1 = iClose(_Symbol, PERIOD_CURRENT, shift);
   
   if(open1 == 0 || close1 == 0) return;
   
   double bodySize = MathAbs(close1 - open1);
   double bodySizePips = bodySize / _Point;
   
   if(bodySizePips > Min_Body_Pips)
   {
      bool isBuy = (close1 > open1);
      
      if(isBuy)
      {
         double stopLoss = close1 - (Trail_Pips * _Point);
         double takeProfit = DisableTP ? 0 : (close1 + (TP_Pips * _Point));
         
         ExecuteTrade(true, stopLoss, takeProfit);
      }
      else
      {
         double stopLoss = close1 + (Trail_Pips * _Point);
         double takeProfit = DisableTP ? 0 : (close1 - (TP_Pips * _Point));
         
         ExecuteTrade(false, stopLoss, takeProfit);
      }
   }
}

//+------------------------------------------------------------------+
//| Execute trade                                                     |
//+------------------------------------------------------------------+
void ExecuteTrade(bool isBuy, double stopLoss, double takeProfit)
{
   double lotSize = GetLotSize();
   if(lotSize <= 0) return;
   
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lotSize;
   request.type = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   request.price = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   request.sl = stopLoss;
   if(!DisableTP) request.tp = takeProfit;
   request.deviation = 10;
   request.magic = MAGIC_NUMBER;
   request.comment = "Strategy 5 " + (isBuy ? "Buy" : "Sell");
   
   if(!OrderSend(request, result))
   {
      Print("OrderSend failed with error: ", GetLastError());
      return;
   }
   
   if(result.retcode == TRADE_RETCODE_DONE)
   {
      g_lastTradeTime = TimeCurrent();
      Print("Trade executed successfully. Ticket: ", result.order);
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
//| Check if strategy is on cooldown                                  |
//+------------------------------------------------------------------+
bool IsStrategyOnCooldown()
{
   if(g_lastTradeTime == 0) return false;
   
   datetime currentTime = TimeCurrent();
   if(currentTime - g_lastTradeTime < STRATEGY_COOLDOWN_MINUTES * 60)
      return true;
      
   return false;
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
                                 
      if(profitPips >= Trail_Activation_Pips)
      {
         double newSL;
         if(isBuy)
         {
            newSL = currentPrice - (Trail_Pips * _Point);
            if(currentSL == 0 || newSL > currentSL)
            {
               MqlTradeRequest request = {};
               MqlTradeResult result = {};
               
               request.action = TRADE_ACTION_SLTP;
               request.position = ticket;
               request.sl = newSL;
               request.tp = PositionGetDouble(POSITION_TP);
               
               if(!OrderSend(request, result))
                  Print("Failed to modify trailing stop. Error: ", GetLastError());
            }
         }
         else
         {
            newSL = currentPrice + (Trail_Pips * _Point);
            if(currentSL == 0 || newSL < currentSL)
            {
               MqlTradeRequest request = {};
               MqlTradeResult result = {};
               
               request.action = TRADE_ACTION_SLTP;
               request.position = ticket;
               request.sl = newSL;
               request.tp = PositionGetDouble(POSITION_TP);
               
               if(!OrderSend(request, result))
                  Print("Failed to modify trailing stop. Error: ", GetLastError());
            }
         }
      }
   }
}
