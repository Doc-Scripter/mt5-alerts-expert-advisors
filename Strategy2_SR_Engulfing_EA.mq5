//+------------------------------------------------------------------+
//|                                    Strategy2_SR_Engulfing_EA.mq5   |
//|                                                                    |
//|                 Support/Resistance Engulfing Strategy              |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023"
#property link      ""
#property version   "1.00"
#property strict

// Strategy-specific Magic Number
#define MAGIC_NUMBER 222222

// Trend States
#define TREND_BULLISH 1
#define TREND_BEARISH -1
#define TREND_RANGING 0

// Support/Resistance Zone Structure
struct SRZone
{
   double topBoundary;
   double bottomBoundary;
   double definingClose;
   double definingBodyLow;
   double definingBodyHigh;
   bool   isResistance;
   long   chartObjectID_Top;
   long   chartObjectID_Bottom;
   int    touchCount;
};

// Lot Sizing Modes
enum ENUM_LOT_SIZING_MODE
{
   DYNAMIC_MARGIN_CHECK, // Try input lot, fallback to min lot if margin fails
   ALWAYS_MINIMUM_LOT    // Always use the minimum allowed lot size
};

// Input Parameters
input double      Lot_Size = 1.0;     // Entry lot size (used if LotSizing_Mode=DYNAMIC_MARGIN_CHECK)
input bool        Use_Trend_Filter = false;   // Enable/Disable the main Trend Filter
input ENUM_LOT_SIZING_MODE LotSizing_Mode = DYNAMIC_MARGIN_CHECK; // Lot sizing strategy
input int         SR_Lookback = 20;    // Number of candles to look back for S/R zones
input int         SR_Sensitivity_Pips = 3; // Min distance between S/R zone defining closes
input int         SR_Min_Touches = 2;   // Minimum touches required for a zone to be tradable
input int         BreakevenTriggerPips = 0; // Pips in profit to trigger breakeven (0=disabled)
input bool        Use_Breakeven_Logic = true; // Enable/Disable automatic breakeven adjustment

// Global Variables
int emaHandle;
double emaValues[];
long barCount;
double volMin, volMax, volStep;
datetime g_lastTradeTime = 0;

// Trend Filter Handles & Buffers
int trendFastEmaHandle;
int trendSlowEmaHandle;
int trendAdxHandle;
double trendFastEmaValues[];
double trendSlowEmaValues[];
double trendAdxValues[];

// S/R Zone Arrays
SRZone g_activeSupportZones[];
SRZone g_activeResistanceZones[];
int g_nearestSupportZoneIndex = -1;
int g_nearestResistanceZoneIndex = -1;

// Constants
#define EMA_PERIOD 20
#define STRATEGY_COOLDOWN_MINUTES 60
#define SHIFT_TO_CHECK 1  // Candlestick shift to check for patterns

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
   
   // Initialize EMA indicator
   emaHandle = iMA(_Symbol, PERIOD_CURRENT, EMA_PERIOD, 0, MODE_EMA, PRICE_CLOSE);
   
   if(emaHandle == INVALID_HANDLE)
   {
      Print("Failed to create EMA indicator handle");
      return(INIT_FAILED);
   }
   
   // Initialize barCount
   barCount = Bars(_Symbol, PERIOD_CURRENT);
   
   // Initialize trend filter indicators
   if(Use_Trend_Filter)
   {
      trendFastEmaHandle = iMA(_Symbol, PERIOD_CURRENT, 20, 0, MODE_EMA, PRICE_CLOSE);
      trendSlowEmaHandle = iMA(_Symbol, PERIOD_CURRENT, 50, 0, MODE_EMA, PRICE_CLOSE);
      trendAdxHandle = iADX(_Symbol, PERIOD_CURRENT, 14);
      
      if(trendFastEmaHandle == INVALID_HANDLE || 
         trendSlowEmaHandle == INVALID_HANDLE || 
         trendAdxHandle == INVALID_HANDLE)
      {
         Print("Failed to create trend filter indicator handles");
         return(INIT_FAILED);
      }
   }
   
   // Clear S/R zone arrays
   ArrayFree(g_activeSupportZones);
   ArrayFree(g_activeResistanceZones);
   
   // Start the timer for breakeven checks
   if(Use_Breakeven_Logic && BreakevenTriggerPips > 0)
   {
      EventSetTimer(1);
   }
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(emaHandle != INVALID_HANDLE)
      IndicatorRelease(emaHandle);
      
   if(Use_Trend_Filter)
   {
      if(trendFastEmaHandle != INVALID_HANDLE)
         IndicatorRelease(trendFastEmaHandle);
      if(trendSlowEmaHandle != INVALID_HANDLE)
         IndicatorRelease(trendSlowEmaHandle);
      if(trendAdxHandle != INVALID_HANDLE)
         IndicatorRelease(trendAdxHandle);
   }
   
   DeleteAllSRZoneLines();
   EventKillTimer();
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for new bar
   int currentBars = Bars(_Symbol, PERIOD_CURRENT);
   if(currentBars == barCount) return;
   barCount = currentBars;
   
   // Update indicators
   if(!UpdateIndicators()) return;
   
   // Update S/R zones
   UpdateAndDrawValidSRZones();
   
   // Check strategy conditions
   CheckStrategy();
}

//+------------------------------------------------------------------+
//| Update indicator values                                           |
//+------------------------------------------------------------------+
bool UpdateIndicators()
{
   // Initialize arrays with proper size (need more than 3 bars for strategy checks)
   int requiredBars = SHIFT_TO_CHECK + 4; // Need enough bars for strategy checks
   ArrayResize(emaValues, requiredBars);
   ArraySetAsSeries(emaValues, true);
   if(CopyBuffer(emaHandle, 0, 0, requiredBars, emaValues) < requiredBars)
   {
      Print("Failed to copy EMA values");
      return false;
   }
   
   if(Use_Trend_Filter)
   {
      // Initialize trend filter arrays with proper size
      ArrayResize(trendFastEmaValues, requiredBars);
      ArrayResize(trendSlowEmaValues, requiredBars);
      ArrayResize(trendAdxValues, requiredBars);
      
      ArraySetAsSeries(trendFastEmaValues, true);
      ArraySetAsSeries(trendSlowEmaValues, true);
      ArraySetAsSeries(trendAdxValues, true);
      
      if(CopyBuffer(trendFastEmaHandle, 0, 0, requiredBars, trendFastEmaValues) < requiredBars ||
         CopyBuffer(trendSlowEmaHandle, 0, 0, requiredBars, trendSlowEmaValues) < requiredBars ||
         CopyBuffer(trendAdxHandle, 0, 0, requiredBars, trendAdxValues) < requiredBars)
      {
         Print("Failed to copy trend filter values");
         return false;
      }
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check for engulfing pattern                                       |
//+------------------------------------------------------------------+
bool IsEngulfing(int shift, bool bullish)
{
   int i = shift;
   int priorIdx = i + 1;
   
   double open1 = iOpen(_Symbol, PERIOD_CURRENT, i);
   double close1 = iClose(_Symbol, PERIOD_CURRENT, i);
   double open2 = iOpen(_Symbol, PERIOD_CURRENT, priorIdx);
   double close2 = iClose(_Symbol, PERIOD_CURRENT, priorIdx);
   
   if(open1 == 0 || close1 == 0 || open2 == 0 || close2 == 0)
      return false;
      
   double tolerance = _Point;
   
   bool trendOkBull = !Use_Trend_Filter;
   bool trendOkBear = !Use_Trend_Filter;
   
   if(Use_Trend_Filter)
   {
      if(priorIdx >= ArraySize(emaValues))
         return false;
         
      double maPrior = emaValues[priorIdx];
      double midOCPrior = (open2 + close2) / 2.0;
      trendOkBull = midOCPrior < maPrior;
      trendOkBear = midOCPrior > maPrior;
   }
   
   if(bullish)
   {
      bool priorIsBearish = (close2 < open2 - tolerance);
      bool currentIsBullish = (close1 > open1 + tolerance);
      bool engulfsBody = (open1 < close2 - tolerance) && (close1 > open2 + tolerance);
      
      return priorIsBearish && currentIsBullish && engulfsBody && trendOkBull;
   }
   else
   {
      bool priorIsBullish = (close2 > open2 + tolerance);
      bool currentIsBearish = (close1 < open1 - tolerance);
      bool engulfsBody = (open1 > close2 + tolerance) && (close1 < open2 - tolerance);
      
      return priorIsBullish && currentIsBearish && engulfsBody && trendOkBear;
   }
}

//+------------------------------------------------------------------+
//| Check strategy conditions                                         |
//+------------------------------------------------------------------+
void CheckStrategy()
{
   // Check cooldown
   if(IsStrategyOnCooldown()) return;
   
   double closePrice = iClose(_Symbol, PERIOD_CURRENT, SHIFT_TO_CHECK);
   
   // Check bullish engulfing at support
   bool isBullishEngulfing = IsEngulfing(SHIFT_TO_CHECK, true);
   if(isBullishEngulfing && g_nearestSupportZoneIndex != -1 && 
      g_nearestSupportZoneIndex < ArraySize(g_activeSupportZones))
   {
      SRZone nearestSupport = g_activeSupportZones[g_nearestSupportZoneIndex];
      
      bool engulfingCloseInZone = (closePrice >= nearestSupport.bottomBoundary && 
                                  closePrice <= nearestSupport.topBoundary);
                                  
      bool priceBelowEMARecently = false;
      for(int i = SHIFT_TO_CHECK + 1; i <= SHIFT_TO_CHECK + 3 && i < ArraySize(emaValues); i++)
      {
         double close = iClose(_Symbol, PERIOD_CURRENT, i);
         if(close < emaValues[i])
         {
            priceBelowEMARecently = true;
            break;
         }
      }
      
      bool minTouchesMet = (nearestSupport.touchCount >= SR_Min_Touches);
      
      if(engulfingCloseInZone && priceBelowEMARecently && minTouchesMet)
      {
         if(Use_Trend_Filter && GetTrendState() != TREND_BULLISH)
            return;
            
         double stopLoss = nearestSupport.bottomBoundary;
         double takeProfit = closePrice + ((closePrice - stopLoss) * 1.5);
         
         ExecuteTrade(true, stopLoss, takeProfit);
         return;
      }
   }
   
   // Check bearish engulfing at resistance
   bool isBearishEngulfing = IsEngulfing(SHIFT_TO_CHECK, false);
   if(isBearishEngulfing && g_nearestResistanceZoneIndex != -1 &&
      g_nearestResistanceZoneIndex < ArraySize(g_activeResistanceZones))
   {
      SRZone nearestResistance = g_activeResistanceZones[g_nearestResistanceZoneIndex];
      
      bool engulfingCloseInZone = (closePrice >= nearestResistance.bottomBoundary && 
                                  closePrice <= nearestResistance.topBoundary);
                                  
      bool priceAboveEMARecently = false;
      for(int i = SHIFT_TO_CHECK + 1; i <= SHIFT_TO_CHECK + 3 && i < ArraySize(emaValues); i++)
      {
         double close = iClose(_Symbol, PERIOD_CURRENT, i);
         if(close > emaValues[i])
         {
            priceAboveEMARecently = true;
            break;
         }
      }
      
      bool minTouchesMet = (nearestResistance.touchCount >= SR_Min_Touches);
      
      if(engulfingCloseInZone && priceAboveEMARecently && minTouchesMet)
      {
         if(Use_Trend_Filter && GetTrendState() != TREND_BEARISH)
            return;
            
         double stopLoss = nearestResistance.topBoundary;
         double takeProfit = closePrice - ((stopLoss - closePrice) * 1.5);
         
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
   request.tp = takeProfit;
   request.deviation = 10;
   request.magic = MAGIC_NUMBER;
   request.comment = "Strategy 2 " + (isBuy ? "Buy" : "Sell");
   
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
//| Get current trend state                                          |
//+------------------------------------------------------------------+
int GetTrendState()
{
   if(!Use_Trend_Filter) return TREND_RANGING;
   
   if(ArraySize(trendFastEmaValues) == 0 || ArraySize(trendSlowEmaValues) == 0 || ArraySize(trendAdxValues) == 0)
      return TREND_RANGING;
   
   double fastEMA = trendFastEmaValues[0];
   double slowEMA = trendSlowEmaValues[0];
   double adxValue = trendAdxValues[0];
   
   bool isStrong = (adxValue > 25.0);
   bool isBullish = (fastEMA > slowEMA);
   
   if(isStrong && isBullish) return TREND_BULLISH;
   if(isStrong && !isBullish) return TREND_BEARISH;
   return TREND_RANGING;
}

//+------------------------------------------------------------------+
//| Update and validate S/R zones                                     |
//+------------------------------------------------------------------+
void UpdateAndDrawValidSRZones()
{
   // Get price data
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, PERIOD_CURRENT, 0, SR_Lookback + 2, rates) < SR_Lookback + 2)
   {
      Print("Failed to copy rates for S/R zones");
      return;
   }
   
   // Clear existing zones
   ArrayFree(g_activeSupportZones);
   ArrayFree(g_activeResistanceZones);
   g_nearestSupportZoneIndex = -1;
   g_nearestResistanceZoneIndex = -1;
   
   // Look for new zones
   double sensitivityValue = SR_Sensitivity_Pips * _Point;
   
   for(int i = 1; i < SR_Lookback; i++)
   {
      // Check for potential resistance
      if(rates[i].close > rates[i-1].close && rates[i].close > rates[i+1].close)
      {
         SRZone newZone;
         newZone.definingClose = rates[i].close;
         newZone.topBoundary = MathMax(rates[i+1].high, MathMax(rates[i].high, rates[i-1].high));
         newZone.bottomBoundary = newZone.definingClose;
         newZone.isResistance = true;
         newZone.touchCount = 0;
         
         // Add if not too close to existing zones
         bool tooClose = false;
         for(int j = 0; j < ArraySize(g_activeResistanceZones); j++)
         {
            if(MathAbs(newZone.definingClose - g_activeResistanceZones[j].definingClose) < sensitivityValue)
            {
               tooClose = true;
               break;
            }
         }
         
         if(!tooClose)
         {
            int size = ArraySize(g_activeResistanceZones);
            ArrayResize(g_activeResistanceZones, size + 1);
            g_activeResistanceZones[size] = newZone;
         }
      }
      
      // Check for potential support
      if(rates[i].close < rates[i-1].close && rates[i].close < rates[i+1].close)
      {
         SRZone newZone;
         newZone.definingClose = rates[i].close;
         newZone.bottomBoundary = MathMin(rates[i+1].low, MathMin(rates[i].low, rates[i-1].low));
         newZone.topBoundary = newZone.definingClose;
         newZone.isResistance = false;
         newZone.touchCount = 0;
         
         // Add if not too close to existing zones
         bool tooClose = false;
         for(int j = 0; j < ArraySize(g_activeSupportZones); j++)
         {
            if(MathAbs(newZone.definingClose - g_activeSupportZones[j].definingClose) < sensitivityValue)
            {
               tooClose = true;
               break;
            }
         }
         
         if(!tooClose)
         {
            int size = ArraySize(g_activeSupportZones);
            ArrayResize(g_activeSupportZones, size + 1);
            g_activeSupportZones[size] = newZone;
         }
      }
   }
   
   // Count touches for each zone
   double currentPrice = rates[0].close;
   
   for(int i = 0; i < ArraySize(g_activeResistanceZones); i++)
   {
      for(int j = 0; j < SR_Lookback; j++)
      {
         if(MathAbs(rates[j].high - g_activeResistanceZones[i].topBoundary) <= sensitivityValue)
            g_activeResistanceZones[i].touchCount++;
      }
      
      // Find nearest resistance above current price
      if(g_activeResistanceZones[i].bottomBoundary > currentPrice)
      {
         if(g_nearestResistanceZoneIndex == -1 || 
            (g_nearestResistanceZoneIndex < ArraySize(g_activeResistanceZones) &&
             g_activeResistanceZones[i].bottomBoundary < g_activeResistanceZones[g_nearestResistanceZoneIndex].bottomBoundary))
         {
            g_nearestResistanceZoneIndex = i;
         }
      }
   }
   
   for(int i = 0; i < ArraySize(g_activeSupportZones); i++)
   {
      for(int j = 0; j < SR_Lookback; j++)
      {
         if(MathAbs(rates[j].low - g_activeSupportZones[i].bottomBoundary) <= sensitivityValue)
            g_activeSupportZones[i].touchCount++;
      }
      
      // Find nearest support below current price
      if(g_activeSupportZones[i].topBoundary < currentPrice)
      {
         if(g_nearestSupportZoneIndex == -1 || 
            (g_nearestSupportZoneIndex < ArraySize(g_activeSupportZones) &&
             g_activeSupportZones[i].topBoundary > g_activeSupportZones[g_nearestSupportZoneIndex].topBoundary))
         {
            g_nearestSupportZoneIndex = i;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Delete all S/R zone lines                                         |
//+------------------------------------------------------------------+
void DeleteAllSRZoneLines()
{
   ObjectsDeleteAll(0, "SRZone_");
}

//+------------------------------------------------------------------+
//| Timer function for breakeven management                          |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(!Use_Breakeven_Logic || BreakevenTriggerPips <= 0) return;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
         PositionGetInteger(POSITION_MAGIC) != MAGIC_NUMBER)
         continue;
         
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      
      if(MathAbs(currentSL - openPrice) < _Point) continue;
      
      bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double currentPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      double profitPips = isBuy ? (currentPrice - openPrice) / _Point :
                                 (openPrice - currentPrice) / _Point;
                                 
      if(profitPips >= BreakevenTriggerPips)
      {
         MqlTradeRequest request = {};
         MqlTradeResult result = {};
         
         request.action = TRADE_ACTION_SLTP;
         request.position = ticket;
         request.sl = openPrice;
         request.tp = PositionGetDouble(POSITION_TP);
         
         if(!OrderSend(request, result))
            Print("Failed to modify position to breakeven. Error: ", GetLastError());
      }
   }
}
