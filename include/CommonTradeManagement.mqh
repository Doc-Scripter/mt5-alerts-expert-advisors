// Common Trade Management Functions
// Used by both Strategy1 and Strategy2

// Lot Sizing Modes - Adding the enum definition here
enum ENUM_LOT_SIZING_MODE
{
   DYNAMIC_MARGIN_CHECK, // Try input lot, fallback to min lot if margin fails
   ALWAYS_MINIMUM_LOT    // Always use the minimum allowed lot size
};

//+------------------------------------------------------------------+
//| Check for valid price structure                                   |
//+------------------------------------------------------------------+
bool IsValidPriceStructure(int startBar, int endBar, bool isBullish)
{
   double highs[], lows[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);
   
   if(CopyHigh(_Symbol, PERIOD_CURRENT, 0, startBar + 1, highs) != startBar + 1 ||
      CopyLow(_Symbol, PERIOD_CURRENT, 0, startBar + 1, lows) != startBar + 1)
      return false;
      
   if(isBullish)
   {
      bool hadLowerLows = false;
      for(int i = startBar + 1; i < ArraySize(lows) - 1; i++)
      {
         if(lows[i] < lows[i-1])
         {
            hadLowerLows = true;
            break;
         }
      }
      
      if(!hadLowerLows) return false;
      
      double lowestLow = lows[startBar];
      double highestHigh = highs[startBar];
      
      for(int i = startBar-1; i >= endBar; i--)
      {
         if(highs[i] > highestHigh || lows[i] > lowestLow)
            return false;
      }
   }
   else
   {
      bool hadHigherHighs = false;
      for(int i = startBar + 1; i < ArraySize(highs) - 1; i++)
      {
         if(highs[i] > highs[i-1])
         {
            hadHigherHighs = true;
            break;
         }
      }
      
      if(!hadHigherHighs) return false;
      
      double highestLow = lows[startBar];
      double lowestHigh = highs[startBar];
      
      for(int i = startBar-1; i >= endBar; i--)
      {
         if(lows[i] < highestLow || highs[i] < lowestHigh)
            return false;
      }
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Get appropriate lot size based on mode and margin                 |
//+------------------------------------------------------------------+
double GetLotSize(double lotSize, ENUM_LOT_SIZING_MODE lotSizingMode, double riskPercent = 0.0, double stopLossPrice = 0.0)
{
   // Get symbol volume constraints
   double volMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double volMax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double volStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   // If using risk-based sizing
   if(riskPercent > 0.0 && stopLossPrice > 0.0)
   {
      double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double riskPips = MathAbs(entryPrice - stopLossPrice) / _Point;
      
      // Get account balance and calculate risk amount
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double riskAmount = balance * (riskPercent / 100.0);
      
      // Calculate pip value
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double pipValue = (tickValue / tickSize) * _Point;
      
      // Calculate lot size based on risk
      if(pipValue > 0 && riskPips > 0)
      {
         lotSize = NormalizeDouble(riskAmount / (riskPips * pipValue), 2);
      }
   }
   
   // If using fixed lot size mode
   if(lotSizingMode == ALWAYS_MINIMUM_LOT)
   {
      lotSize = volMin;
   }
   
   // Ensure lot size is within allowed range
   lotSize = MathMax(lotSize, volMin);
   lotSize = MathMin(lotSize, volMax);
   
   // Round to nearest allowed lot step
   if(volStep > 0)
   {
      lotSize = NormalizeDouble(MathRound(lotSize / volStep) * volStep, 2);
   }
   
   // Check if we have enough margin for this lot size
   double marginRequired;
   if(!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lotSize, SymbolInfoDouble(_Symbol, SYMBOL_ASK), marginRequired))
   {
      Print("Error calculating margin. Error code: ", GetLastError());
      return 0;
   }
   
   if(marginRequired > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
   {
      if(lotSizingMode == DYNAMIC_MARGIN_CHECK)
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
bool IsStrategyOnCooldown(datetime lastTradeTime, int cooldownMinutes)
{
   if(lastTradeTime == 0) return false;
   
   datetime currentTime = TimeCurrent();
   if(currentTime - lastTradeTime < cooldownMinutes * 60)
      return true;
      
   return false;
}

//+------------------------------------------------------------------+
//| Get trend state using EMA crossover and ATR filter                |
//+------------------------------------------------------------------+
int GetTrendState(double ema50, double ema100, double atr, double atrMultiplier = 1.0, double minAtrThreshold = 0.0001)
{
   // Check if ATR meets minimum threshold for valid trend detection
   if(atr < minAtrThreshold)
      return 0; // TREND_RANGING - Not enough volatility to determine trend
   
   // Calculate EMA separation as percentage of ATR
   double emaSeparation = MathAbs(ema50 - ema100) / atr;
   
   // Determine if separation is significant based on ATR
   bool isSignificantSeparation = (emaSeparation >= atrMultiplier);
   
   // Determine trend direction
   bool isBullish = (ema50 > ema100);
   
   // Return trend state
   if(isSignificantSeparation && isBullish)
      return 1;  // TREND_BULLISH
   else if(isSignificantSeparation && !isBullish)
      return -1; // TREND_BEARISH
   else
      return 0;  // TREND_RANGING
}

//+------------------------------------------------------------------+
//| Process breakeven logic for open positions                        |
//+------------------------------------------------------------------+
void ProcessBreakeven(bool useBreakevenLogic, int breakevenTriggerPips, int magicNumber)
{
   if(!useBreakevenLogic || breakevenTriggerPips <= 0) return;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
         PositionGetInteger(POSITION_MAGIC) != magicNumber)
         continue;
         
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      
      if(MathAbs(currentSL - openPrice) < _Point) continue;
      
      bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double currentPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      double profitPips = isBuy ? (currentPrice - openPrice) / _Point :
                                 (openPrice - currentPrice) / _Point;
                                 
      if(profitPips >= breakevenTriggerPips)
      {
         MqlTradeRequest request = {};
         MqlTradeResult result = {};
         
         request.action = TRADE_ACTION_SLTP;
         request.position = ticket;
         request.sl = openPrice;
         request.tp = PositionGetDouble(POSITION_TP);
         
         if(!OrderSend(request, result))
            Print("Failed to modify position to breakeven. Error: ", GetLastError());
         else
            Print("Successfully moved position #", ticket, " to breakeven");
      }
   }
}

//+------------------------------------------------------------------+
//| Process breakeven at 1:1 risk-reward ratio                        |
//+------------------------------------------------------------------+
void ProcessBreakevenAt1to1(bool useBreakevenLogic, int magicNumber)
{
   if(!useBreakevenLogic) return;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
         PositionGetInteger(POSITION_MAGIC) != magicNumber)
         continue;
         
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      
      // Skip if already at breakeven
      if(MathAbs(currentSL - openPrice) < _Point) continue;
      
      bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double currentPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      // Calculate risk in pips (distance from entry to stop loss)
      double riskPips = isBuy ? (openPrice - currentSL) / _Point : 
                              (currentSL - openPrice) / _Point;
      
      // Calculate current profit in pips
      double profitPips = isBuy ? (currentPrice - openPrice) / _Point :
                                (openPrice - currentPrice) / _Point;
                                
      // Move to breakeven when profit equals risk (1:1 risk-reward)
      if(profitPips >= riskPips && riskPips > 0)
      {
         MqlTradeRequest request = {};
         MqlTradeResult result = {};
         
         request.action = TRADE_ACTION_SLTP;
         request.position = ticket;
         request.sl = openPrice;
         request.tp = PositionGetDouble(POSITION_TP);
         
         if(!OrderSend(request, result))
            Print("Failed to modify position to breakeven. Error: ", GetLastError());
         else
            Print("Successfully moved position #", ticket, " to breakeven at 1:1 risk-reward");
      }
   }
}
