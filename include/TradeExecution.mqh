//+------------------------------------------------------------------+
//| Execute trade                                                     |
//+------------------------------------------------------------------+
void ExecuteTrade(bool isBuy, double stopLoss, double takeProfit)
{
   // Check if we already have an open position with our magic number
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      // Check if position belongs to this EA and this symbol
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
         PositionGetInteger(POSITION_MAGIC) == MAGIC_NUMBER)
      {
         Print("INFO: Trade rejected - already have an open position. Only one trade at a time allowed.");
         return; // Exit without opening a new trade
      }
   }
   
   double lotSize = GetLotSize();
   if(lotSize <= 0) return;
   
   // Get current market prices
   double askPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bidPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double entryPrice = isBuy ? askPrice : bidPrice;
   
   // Validate stop loss and take profit levels
   if(isBuy)
   {
      // For BUY orders: SL must be below entry price, TP must be above entry price
      if(stopLoss >= entryPrice)
      {
         Print("ERROR: Invalid stop loss for BUY order. SL (", stopLoss, ") must be below entry price (", entryPrice, ")");
         return;
      }
      
      if(takeProfit <= entryPrice)
      {
         Print("ERROR: Invalid take profit for BUY order. TP (", takeProfit, ") must be above entry price (", entryPrice, ")");
         return;
      }
   }
   else
   {
      // For SELL orders: SL must be above entry price, TP must be below entry price
      if(stopLoss <= entryPrice)
      {
         Print("ERROR: Invalid stop loss for SELL order. SL (", stopLoss, ") must be above entry price (", entryPrice, ")");
         return;
      }
      
      if(takeProfit >= entryPrice)
      {
         Print("ERROR: Invalid take profit for SELL order. TP (", takeProfit, ") must be below entry price (", entryPrice, ")");
         return;
      }
   }
   
   // Check minimum distance for SL and TP
   int stopLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double pointValue = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double minDistance = stopLevel * pointValue;
   
   if(isBuy)
   {
      if(entryPrice - stopLoss < minDistance)
      {
         Print("WARNING: Stop loss too close to entry price. Adjusting SL to minimum allowed distance.");
         stopLoss = entryPrice - minDistance;
      }
      
      if(takeProfit - entryPrice < minDistance)
      {
         Print("WARNING: Take profit too close to entry price. Adjusting TP to minimum allowed distance.");
         takeProfit = entryPrice + minDistance;
      }
   }
   else
   {
      if(stopLoss - entryPrice < minDistance)
      {
         Print("WARNING: Stop loss too close to entry price. Adjusting SL to minimum allowed distance.");
         stopLoss = entryPrice + minDistance;
      }
      
      if(entryPrice - takeProfit < minDistance)
      {
         Print("WARNING: Take profit too close to entry price. Adjusting TP to minimum allowed distance.");
         takeProfit = entryPrice - minDistance;
      }
   }
   
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lotSize;
   request.type = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   request.price = entryPrice;
   request.sl = stopLoss;
   request.tp = takeProfit;
   request.deviation = 10;
   request.magic = MAGIC_NUMBER;
   request.comment = "Strategy 1 " + (isBuy ? "Buy" : "Sell");
   
   if(!OrderSend(request, result))
   {
      Print("ERROR: OrderSend failed with error: ", GetLastError());
      return;
   }
   
   if(result.retcode == TRADE_RETCODE_DONE)
   {
      g_lastTradeTime = TimeCurrent();
      Print("SIGNAL: Trade executed successfully. Ticket: ", result.order);
   }
}