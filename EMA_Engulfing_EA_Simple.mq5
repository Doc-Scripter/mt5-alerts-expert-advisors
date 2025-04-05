//+------------------------------------------------------------------+
//|                                 EMA_Engulfing_EA_Simple.mq5      |
//|                                                                   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023"
#property link      ""
#property version   "1.00"
#property strict

// Input parameters
input int         EMA_Period = 20;       // EMA period
input double      Lot_Size = 0.01;       // Lot size for trading
input double      RR_Ratio = 2.0;        // Risk:Reward ratio
input int         SL_Buffer_Pips = 5;    // Buffer for stop loss in pips

// Global variables
int emaHandle;
double emaValues[];
int barCount;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize EMA indicator
   emaHandle = iMA(_Symbol, PERIOD_CURRENT, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   
   if(emaHandle == INVALID_HANDLE)
   {
      Print("Failed to create EMA indicator handle");
      return(INIT_FAILED);
   }
   
   // Initialize barCount
   barCount = Bars(_Symbol, PERIOD_CURRENT);
   
   Print("EMA Engulfing EA Simple initialized successfully");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release indicator handle
   if(emaHandle != INVALID_HANDLE)
      IndicatorRelease(emaHandle);
      
   Print("EMA Engulfing EA Simple deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for new bar
   int currentBars = Bars(_Symbol, PERIOD_CURRENT);
   if(currentBars <= barCount)
      return;  // No new bar
      
   barCount = currentBars;
   
   // Update EMA values
   ArraySetAsSeries(emaValues, true);
   if(CopyBuffer(emaHandle, 0, 0, 3, emaValues) < 3)
   {
      Print("Failed to copy EMA values");
      return;
   }
   
   // Check for open positions
   if(PositionsTotal() > 0)
      return;
      
   // Basic engulfing pattern check
   if(IsEngulfingPattern())
   {
      ExecuteSimpleTrade();
   }
}

//+------------------------------------------------------------------+
//| Check for engulfing pattern                                      |
//+------------------------------------------------------------------+
bool IsEngulfingPattern()
{
   double open1 = iOpen(_Symbol, PERIOD_CURRENT, 1);
   double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double open2 = iOpen(_Symbol, PERIOD_CURRENT, 0);
   double close2 = iClose(_Symbol, PERIOD_CURRENT, 0);
   
   // Bullish engulfing
   if((open1 > close1) && // Prior candle is bearish
      (open2 < close2) && // Current candle is bullish
      (open2 <= close1) && // Current open is below or equal to prior close
      (close2 > open1))    // Current close is above prior open
   {
      return true;
   }
   
   // Bearish engulfing
   if((open1 < close1) && // Prior candle is bullish
      (open2 > close2) && // Current candle is bearish
      (open2 >= close1) && // Current open is above or equal to prior close
      (close2 < open1))    // Current close is below prior open
   {
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Execute a simple trade                                           |
//+------------------------------------------------------------------+
void ExecuteSimpleTrade()
{
   // Determine trade direction based on current vs EMA
   double currentPrice = iClose(_Symbol, PERIOD_CURRENT, 0);
   bool isBuy = (currentPrice > emaValues[0]);
   
   double entryPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double stopLoss = 0;
   double takeProfit = 0;
   
   // Calculate stop loss
   if(isBuy)
   {
      stopLoss = iLow(_Symbol, PERIOD_CURRENT, 1) - SL_Buffer_Pips * _Point;
      takeProfit = entryPrice + (entryPrice - stopLoss) * RR_Ratio;
   }
   else
   {
      stopLoss = iHigh(_Symbol, PERIOD_CURRENT, 1) + SL_Buffer_Pips * _Point;
      takeProfit = entryPrice - (stopLoss - entryPrice) * RR_Ratio;
   }
   
   // Execute trade
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = Lot_Size;
   request.type = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   request.price = entryPrice;
   request.sl = stopLoss;
   request.tp = takeProfit;
   request.deviation = 10;
   request.magic = 12345;
   request.comment = "EMA Engulfing Simple";
   
   if(OrderSend(request, result))
   {
      Print("Trade executed: ", (isBuy ? "BUY" : "SELL"), " at ", entryPrice, ", SL at ", stopLoss, ", TP at ", takeProfit);
   }
   else
   {
      Print("Failed to execute trade. Error: ", GetLastError());
   }
}
//+------------------------------------------------------------------+