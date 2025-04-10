//+------------------------------------------------------------------+
//|                                  Strategy3_Breakout_EMA_EA.mq5     |
//|                                                                    |
//|          Breakout + EMA Engulfing Confirmation Strategy           |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023"
#property link      ""
#property version   "1.00"
#property strict

// Strategy-specific Magic Number
#define MAGIC_NUMBER 333333

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
   bool   isResistance;
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
input double      SL_Fallback_Pips = 15;   // SL distance in pips when zone boundary is not used
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

// S/R Levels
double g_nearestResistance = 0.0;
double g_nearestSupport = 0.0;

// Constants
#define EMA_PERIOD 20
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
   
   // Update S/R levels
   UpdateSRLevels();
   
   // Check strategy conditions
   CheckStrategy();
}

//+------------------------------------------------------------------+
//| Update indicator values                                           |
//+------------------------------------------------------------------+
bool UpdateIndicators()
{
   ArraySetAsSeries(emaValues, true);
   if(CopyBuffer(emaHandle, 0, 0, 3, emaValues) < 3)
   {
      Print("Failed to copy EMA values");
      return false;
   }
   
   if(Use_Trend_Filter)
   {
      ArraySetAsSeries(trendFastEmaValues, true);
      ArraySetAsSeries(trendSlowEmaValues, true);
      ArraySetAsSeries(trendAdxValues, true);
      
      if(CopyBuffer(trendFastEmaHandle, 0, 0, 3, trendFastEmaValues) < 3 ||
         CopyBuffer(trendSlowEmaHandle, 0, 0, 3, trendSlowEmaValues) < 3 ||
         CopyBuffer(trendAdxHandle, 0, 0, 3, trendAdxValues) < 3)
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
//| Update Support/Resistance levels                                  |
//+------------------------------------------------------------------+
void UpdateSRLevels()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int ratesCount = CopyRates(_Symbol, PERIOD_CURRENT, 0, SR_Lookback + 2, rates);
   
   if(ratesCount < SR_Lookback + 2)
   {
      Print("Failed to copy rates for S/R levels");
      return;
   }
   
   double currentPrice = rates[0].close;
   double sensitivityValue = SR_Sensitivity_Pips * _Point;
   
   g_nearestResistance = 0.0;
   g_nearestSupport = 0.0;
   
   // Find potential levels
   for(int i = 1; i < SR_Lookback; i++)
   {
      // Look for resistance levels
      if(rates[i].close > rates[i-1].close && rates[i].close > rates[i+1].close)
      {
         double level = rates[i].high;
         if(level > currentPrice && 
            (g_nearestResistance == 0.0 || level < g_nearestResistance))
         {
            g_nearestResistance = level;
         }
      }
      
      // Look for support levels
      if(rates[i].close < rates[i-1].close && rates[i].close < rates[i+1].close)
      {
         double level = rates[i].low;
         if(level < currentPrice && 
            (g_nearestSupport == 0.0 || level > g_nearestSupport))
         {
            g_nearestSupport = level;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check if level was broken                                         |
//+------------------------------------------------------------------+
bool BrokeLevel(int shift, double level, bool breakUp)
{
   double close = iClose(_Symbol, PERIOD_CURRENT, shift);
   double prevClose = iClose(_Symbol, PERIOD_CURRENT, shift + 1);
   
   if(breakUp)
      return prevClose < level && close > level;
   else
      return prevClose > level && close < level;
}

//+------------------------------------------------------------------+
//| Check strategy conditions                                         |
//+------------------------------------------------------------------+
void CheckStrategy()
{
   // Check cooldown
   if(IsStrategyOnCooldown()) return;
   
   // Check for bullish setup
   bool bullishEngulfing = IsEngulfing(0, true);
   if(bullishEngulfing && g_nearestResistance > 0)
   {
      // Look for recently broken resistance
      for(int i = 1; i <= 5; i++)
      {
         if(BrokeLevel(i, g_nearestResistance, true))
         {
            if(Use_Trend_Filter && GetTrendState() != TREND_BULLISH)
               return;
               
            // Calculate entry and exit prices
            double stopLoss = g_nearestResistance - (SL_Fallback_Pips * _Point);
            double takeProfit = iClose(_Symbol, PERIOD_CURRENT, 0) + 
                              ((iClose(_Symbol, PERIOD_CURRENT, 0) - stopLoss) * 1.5);
            
            ExecuteTrade(true, stopLoss, takeProfit);
            return;
         }
      }
   }
   
   // Check for bearish setup
   bool bearishEngulfing = IsEngulfing(0, false);
   if(bearishEngulfing && g_nearestSupport > 0)
   {
      // Look for recently broken support
      for(int i = 1; i <= 5; i++)
      {
         if(BrokeLevel(i, g_nearestSupport, false))
         {
            if(Use_Trend_Filter && GetTrendState() != TREND_BEARISH)
               return;
               
            // Calculate entry and exit prices
            double stopLoss = g_nearestSupport + (SL_Fallback_Pips * _Point);
            double takeProfit = iClose(_Symbol, PERIOD_CURRENT, 0) - 
                              ((stopLoss - iClose(_Symbol, PERIOD_CURRENT, 0)) * 1.5);
            
            ExecuteTrade(false, stopLoss, takeProfit);
            return;
         }
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
   request.comment = "Strategy 3 " + (isBuy ? "Buy" : "Sell");
   
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
