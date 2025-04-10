//+------------------------------------------------------------------+
//|                                   EMA_Engulfing_Trade.mqh        |
//|                                                                   |
//|                                                                   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023"
#property link      ""
#property strict

// Structure to hold trade parameters
struct TradeParams
{
   bool isBuy;
   double entryPrice;
   double stopLoss;
   double takeProfit1;
   double takeProfit2;
   double lotSize1;
   double lotSize2;
   string comment;
};

// Position tracking
struct PositionInfo
{
   ulong ticket;
   bool isBuy;
   double lotSize;
   double entryPrice;
   double stopLoss;
   double takeProfit;
   datetime openTime;
};

// Array to store active positions
PositionInfo ActivePositions[];

// Function to execute a trade with two entries and different TPs
bool ExecuteTradeStrategy(TradeParams &params)
{
   // Get current price
   double currentPrice = params.isBuy ? 
                       SymbolInfoDouble(_Symbol, SYMBOL_ASK) : 
                       SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // Normalize prices
   params.stopLoss = NormalizePrice(params.stopLoss);
   params.takeProfit1 = NormalizePrice(params.takeProfit1);
   params.takeProfit2 = NormalizePrice(params.takeProfit2);
   
   // Prepare first trade
   MqlTradeRequest request1 = {};
   MqlTradeResult result1 = {};
   
   request1.action = TRADE_ACTION_DEAL;
   request1.symbol = _Symbol;
   request1.volume = params.lotSize1;
   request1.type = params.isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   request1.price = currentPrice;
   request1.sl = params.stopLoss;
   request1.tp = params.takeProfit1;
   request1.deviation = 10;
   request1.magic = 123456;
   request1.comment = params.comment + " TP1";
   
   // Execute first trade
   bool success1 = OrderSend(request1, result1);
   
   if(success1 && result1.retcode == TRADE_RETCODE_DONE)
   {
      // Save position info
      int posIndex = ArraySize(ActivePositions);
      ArrayResize(ActivePositions, posIndex + 1);
      
      ActivePositions[posIndex].ticket = result1.deal;
      ActivePositions[posIndex].isBuy = params.isBuy;
      ActivePositions[posIndex].lotSize = params.lotSize1;
      ActivePositions[posIndex].entryPrice = currentPrice;
      ActivePositions[posIndex].stopLoss = params.stopLoss;
      ActivePositions[posIndex].takeProfit = params.takeProfit1;
      ActivePositions[posIndex].openTime = TimeCurrent();
      
      // Prepare second trade
      MqlTradeRequest request2 = {};
      MqlTradeResult result2 = {};
      
      request2.action = TRADE_ACTION_DEAL;
      request2.symbol = _Symbol;
      request2.volume = params.lotSize2;
      request2.type = params.isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      request2.price = currentPrice;
      request2.sl = params.stopLoss;
      request2.tp = params.takeProfit2;
      request2.deviation = 10;
      request2.magic = 123456;
      request2.comment = params.comment + " TP2";
      
      // Execute second trade
      bool success2 = OrderSend(request2, result2);
      
      if(success2 && result2.retcode == TRADE_RETCODE_DONE)
      {
         // Save position info
         posIndex = ArraySize(ActivePositions);
         ArrayResize(ActivePositions, posIndex + 1);
         
         ActivePositions[posIndex].ticket = result2.deal;
         ActivePositions[posIndex].isBuy = params.isBuy;
         ActivePositions[posIndex].lotSize = params.lotSize2;
         ActivePositions[posIndex].entryPrice = currentPrice;
         ActivePositions[posIndex].stopLoss = params.stopLoss;
         ActivePositions[posIndex].takeProfit = params.takeProfit2;
         ActivePositions[posIndex].openTime = TimeCurrent();
         
         // Log trade execution
         string direction = params.isBuy ? "BUY" : "SELL";
         Print("Executed ", direction, " trades. SL at ", params.stopLoss, 
               ", TP1 at ", params.takeProfit1, ", TP2 at ", params.takeProfit2);
         
         return true;
      }
      else
      {
         // Log error for second trade
         Print("Failed to execute second trade. Error: ", GetLastError());
         return false;
      }
   }
   else
   {
      // Log error for first trade
      Print("Failed to execute first trade. Error: ", GetLastError());
      return false;
   }
}

// Function to close a specific position
bool ClosePosition(ulong ticket)
{
   for(int i = 0; i < ArraySize(ActivePositions); i++)
   {
      if(ActivePositions[i].ticket == ticket)
      {
         MqlTradeRequest request = {};
         MqlTradeResult result = {};
         
         request.action = TRADE_ACTION_DEAL;
         request.position = ticket;
         request.symbol = _Symbol;
         request.volume = ActivePositions[i].lotSize;
         
         if(ActivePositions[i].isBuy)
         {
            request.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            request.type = ORDER_TYPE_SELL;
         }
         else
         {
            request.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            request.type = ORDER_TYPE_BUY;
         }
         
         request.deviation = 10;
         request.magic = 123456;
         request.comment = "Close position";
         
         bool success = OrderSend(request, result);
         
         if(success && result.retcode == TRADE_RETCODE_DONE)
         {
            Print("Position ", ticket, " closed successfully");
            // Remove position from tracking array
            RemovePositionFromArray(i);
            return true;
         }
         else
         {
            Print("Failed to close position ", ticket, ". Error: ", GetLastError());
            return false;
         }
      }
   }
   
   Print("Position ", ticket, " not found in active positions");
   return false;
}

// Function to remove a position from the tracking array
void RemovePositionFromArray(int index)
{
   for(int i = index; i < ArraySize(ActivePositions) - 1; i++)
   {
      ActivePositions[i] = ActivePositions[i + 1];
   }
   
   ArrayResize(ActivePositions, ArraySize(ActivePositions) - 1);
}

// Function to check and update position information
void UpdatePositionInfo()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong posTicket = PositionGetTicket(i);
      
      if(PositionSelectByTicket(posTicket))
      {
         string posSymbol = PositionGetString(POSITION_SYMBOL);
         
         if(posSymbol == _Symbol)
         {
            bool found = false;
            
            // Check if we're already tracking this position
            for(int j = 0; j < ArraySize(ActivePositions); j++)
            {
               if(ActivePositions[j].ticket == posTicket)
               {
                  found = true;
                  break;
               }
            }
            
            // If not found, add it to our tracking array
            if(!found)
            {
               int posIndex = ArraySize(ActivePositions);
               ArrayResize(ActivePositions, posIndex + 1);
               
               ActivePositions[posIndex].ticket = posTicket;
               ActivePositions[posIndex].isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
               ActivePositions[posIndex].lotSize = PositionGetDouble(POSITION_VOLUME);
               ActivePositions[posIndex].entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
               ActivePositions[posIndex].stopLoss = PositionGetDouble(POSITION_SL);
               ActivePositions[posIndex].takeProfit = PositionGetDouble(POSITION_TP);
               ActivePositions[posIndex].openTime = (datetime)PositionGetInteger(POSITION_TIME);
            }
         }
      }
   }
   
   // Remove closed positions from our tracking array
   for(int i = ArraySize(ActivePositions) - 1; i >= 0; i--)
   {
      bool stillOpen = false;
      
      for(int j = PositionsTotal() - 1; j >= 0; j--)
      {
         ulong posTicket = PositionGetTicket(j);
         if(posTicket == ActivePositions[i].ticket)
         {
            stillOpen = true;
            break;
         }
      }
      
      if(!stillOpen)
      {
         RemovePositionFromArray(i);
      }
   }
}

// Function to check if we have open positions for this symbol
bool HasOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong posTicket = PositionGetTicket(i);
      
      if(PositionSelectByTicket(posTicket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol)
            return true;
      }
   }
   
   return false;
}

// Function to close all positions
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         string symbol = PositionGetString(POSITION_SYMBOL);
         if(symbol == _Symbol)
         {
            MqlTradeRequest request = {};
            MqlTradeResult result = {};
            
            request.action = TRADE_ACTION_DEAL;
            request.position = ticket;
            request.symbol = _Symbol;
            request.volume = PositionGetDouble(POSITION_VOLUME);
            request.type = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            request.price = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 
                            SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                            SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            request.deviation = 10;
            request.magic = 123456;
            request.comment = "Close all positions";
            
            OrderSend(request, result);
         }
      }
   }
}

// Function to modify stop loss of all positions
void ModifyStopLoss(double newStopLoss)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         string symbol = PositionGetString(POSITION_SYMBOL);
         if(symbol == _Symbol)
         {
            MqlTradeRequest request = {};
            MqlTradeResult result = {};
            
            request.action = TRADE_ACTION_SLTP;
            request.position = ticket;
            request.symbol = _Symbol;
            request.sl = NormalizePrice(newStopLoss);
            request.tp = PositionGetDouble(POSITION_TP);
            
            OrderSend(request, result);
         }
      }
   }
}

// Function to calculate distance in pips
double DistancePips(double price1, double price2)
{
   double pipValue = 10 * _Point; // Default for 5-digit brokers
   return MathAbs(price1 - price2) / pipValue;
}

// Function to create a trade based on entry signal
bool CreateTradeFromSignal(bool isBuy, double stopLoss, string signalType, double lotSize1 = 0.01, double lotSize2 = 0.02, double rrRatio1 = 1.7, double rrRatio2 = 2.0)
{
   // Get current price
   double entryPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // Calculate risk distance
   double riskDistance = MathAbs(entryPrice - stopLoss);
   
   // Calculate take profit levels
   double takeProfit1 = CalculateTakeProfit(isBuy, entryPrice, stopLoss, rrRatio1);
   double takeProfit2 = CalculateTakeProfit(isBuy, entryPrice, stopLoss, rrRatio2);
   
   // Prepare trade parameters
   TradeParams params;
   params.isBuy = isBuy;
   params.entryPrice = entryPrice;
   params.stopLoss = stopLoss;
   params.takeProfit1 = takeProfit1;
   params.takeProfit2 = takeProfit2;
   params.lotSize1 = lotSize1;
   params.lotSize2 = lotSize2;
   params.comment = signalType;
   
   // Execute the trade
   return ExecuteTradeStrategy(params);
}

// Function to calculate take profit based on risk:reward ratio
double CalculateTakeProfit(bool isBuy, double entryPrice, double stopLoss, double rrRatio)
{
   if(isBuy)
      return entryPrice + (entryPrice - stopLoss) * rrRatio;
   else
      return entryPrice - (stopLoss - entryPrice) * rrRatio;
}

// Function to check if we have a trailing stop condition
void CheckTrailingStop(double activationPips = 20, double trailDistance = 10)
{
   for(int i = 0; i < ArraySize(ActivePositions); i++)
   {
      if(!PositionSelectByTicket(ActivePositions[i].ticket))
         continue;
         
      double currentPrice = ActivePositions[i].isBuy ? 
                         SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                         SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                         
      double currentStop = PositionGetDouble(POSITION_SL);
      
      // Check if position is in profit enough to activate trailing stop
      if(ActivePositions[i].isBuy)
      {
         double profitPips = DistancePips(currentPrice, ActivePositions[i].entryPrice);
         
         if(profitPips >= activationPips)
         {
            double newStop = currentPrice - (trailDistance * 10 * _Point);
            
            if(newStop > currentStop)
            {
               MqlTradeRequest request = {};
               MqlTradeResult result = {};
               
               request.action = TRADE_ACTION_SLTP;
               request.position = ActivePositions[i].ticket;
               request.symbol = _Symbol;
               request.sl = NormalizePrice(newStop);
               request.tp = PositionGetDouble(POSITION_TP);
               
               OrderSend(request, result);
            }
         }
      }
      else // Sell position
      {
         double profitPips = DistancePips(ActivePositions[i].entryPrice, currentPrice);
         
         if(profitPips >= activationPips)
         {
            double newStop = currentPrice + (trailDistance * 10 * _Point);
            
            if(newStop < currentStop || currentStop == 0)
            {
               MqlTradeRequest request = {};
               MqlTradeResult result = {};
               
               request.action = TRADE_ACTION_SLTP;
               request.position = ActivePositions[i].ticket;
               request.symbol = _Symbol;
               request.sl = NormalizePrice(newStop);
               request.tp = PositionGetDouble(POSITION_TP);
               
               OrderSend(request, result);
            }
         }
      }
   }
}

bool IsEngulfing(const int shift, const bool bullish, const bool useFilter)
{
   if(shift < 0 || shift >= Bars(_Symbol, PERIOD_CURRENT)) 
   {
      Print("IsEngulfing: Invalid shift value");
      return false;
   }

   // Get candle data
   double close1 = iClose(_Symbol, PERIOD_CURRENT, shift);
   double open1 = iOpen(_Symbol, PERIOD_CURRENT, shift);
   double close2 = iClose(_Symbol, PERIOD_CURRENT, shift + 1);
   double open2 = iOpen(_Symbol, PERIOD_CURRENT, shift + 1);
   
   // Verify we have valid data
   if(close1 == 0 || open1 == 0 || close2 == 0 || open2 == 0)
   {
      Print("IsEngulfing: Invalid price data at shift ", shift);
      return false;
   }

   bool isEngulfing = false;
   
   if(bullish)
   {
      // Bullish engulfing
      isEngulfing = (close1 > open1 &&           // Current candle is bullish
                    close2 < open2 &&           // Previous candle is bearish
                    close1 > open2 &&           // Current close above previous open
                    open1 < close2);           // Current open below previous close
   }
   else
   {
      // Bearish engulfing
      isEngulfing = (close1 < open1 &&           // Current candle is bearish
                    close2 > open2 &&           // Previous candle is bullish
                    close1 < open2 &&           // Current close below previous open
                    open1 > close2);           // Current open above previous close
   }
   
   if(isEngulfing)
   {
      Print("IsEngulfing: ", (bullish ? "Bullish" : "Bearish"), " engulfing pattern detected at shift ", shift);
      
      // Additional validation using EMA if required
      if(useFilter && ArraySize(g_ema.values) > shift + 1)
      {
         bool validPosition = bullish ? 
            (close1 > g_ema.values[shift] && open1 < g_ema.values[shift]) :
            (close1 < g_ema.values[shift] && open1 > g_ema.values[shift]);
            
         if(!validPosition)
         {
            Print("IsEngulfing: Pattern rejected by EMA filter");
            return false;
         }
      }
   }
   
   return isEngulfing;
}

void ReleaseEMA()
{
   Print("ReleaseEMA: Starting cleanup...");
   if(g_ema.handle != INVALID_HANDLE)
   {
      Print("ReleaseEMA: Releasing indicator handle ", g_ema.handle);
      bool released = IndicatorRelease(g_ema.handle);
      if(!released)
      {
         int error = GetLastError();
         Print("ReleaseEMA: Failed to release indicator handle. Error: ", error);
      }
      g_ema.handle = INVALID_HANDLE;
   }
   ArrayFree(g_ema.values);
   Print("ReleaseEMA: Cleanup completed");
}
//+------------------------------------------------------------------+
