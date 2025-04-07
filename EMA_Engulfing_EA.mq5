//+------------------------------------------------------------------+
//|                                           EMA_Engulfing_EA.mq5    |
//|                                                                   |
//|                                                                   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023"
#property link      ""
#property version   "1.00"
#property strict

// Include spread check functionality
#include "include/SpreadCheck.mqh"

// Trend States
#define TREND_BULLISH 1
#define TREND_BEARISH -1
#define TREND_RANGING 0

// Strategy Magic Numbers
#define MAGIC_STRAT_1 111111
#define MAGIC_STRAT_2 222222
#define MAGIC_STRAT_3 333333
#define MAGIC_STRAT_4 444444
#define MAGIC_STRAT_5 555555 // Changed from 654321

// Lot Sizing Modes Enum
enum ENUM_LOT_SIZING_MODE
{
   DYNAMIC_MARGIN_CHECK, // Try input lot, fallback to min lot if margin fails
   ALWAYS_MINIMUM_LOT    // Always use the minimum allowed lot size
};

struct SRZone
{
   double topBoundary;     // Highest point of the zone (wick-based)
   double bottomBoundary;  // Lowest point of the zone (wick-based)
   double definingClose;   // The close price that defined this zone (used for sensitivity check)
   double definingBodyLow; // The low of the body of the defining candle
   double definingBodyHigh; // The high of the body of the defining candle
   bool   isResistance;    // True if resistance zone, false if support zone
   long   chartObjectID_Top; // ID for the top line object
   long   chartObjectID_Bottom; // ID for the bottom line object
   int    touchCount;      // Number of times price has tested this zone

   void operator=(const SRZone &zone)
   {
      topBoundary = zone.topBoundary;
      bottomBoundary = zone.bottomBoundary;
      definingClose = zone.definingClose;
      definingBodyLow = zone.definingBodyLow;   // Add assignment
      definingBodyHigh = zone.definingBodyHigh; // Add assignment
      isResistance = zone.isResistance;
      chartObjectID_Top = zone.chartObjectID_Top;
      chartObjectID_Bottom = zone.chartObjectID_Bottom;
      touchCount = zone.touchCount;
   }
};

// Input parameters
input int         EMA_Period = 20;       // EMA period
input double      Lot_Size_1 = 1;     // First entry lot size (used if LotSizing_Mode=DYNAMIC_MARGIN_CHECK)
input double      Lot_Size_2 = 0.5;     // Second entry lot size
input double      RR_Ratio = 1.5;           // Risk/Reward Ratio for Take Profit (Consolidated)
input int         Max_Spread = 180;      // Maximum spread for logging purposes only
input ENUM_LOT_SIZING_MODE LotSizing_Mode = DYNAMIC_MARGIN_CHECK; // Lot sizing strategy
input int         Strategy_Cooldown_Minutes = 60; // Cooldown in minutes before same strategy can trade again
input bool        Use_Strategy_1 = true; // Use EMA crossing + engulfing strategy
input bool        Use_Strategy_2 = false; // Use S/R engulfing strategy
input bool        Use_Strategy_3 = false; // Use breakout + EMA engulfing strategy
input bool        Use_Strategy_4 = false; // Use simple engulfing strategy
input bool        Use_Strategy_5 = false;  // Use simple movement strategy (for testing)
input bool        Engulfing_Use_Trend_Filter = false; // ENABLED BY DEFAULT: Use MA trend filter in IsEngulfing
input int         SL_Buffer_Pips = 10;    // Buffer in pips for Stop Loss
input int         SR_Lookback = 10;       // Number of candles to look back for S/R zones
input int         SR_Sensitivity_Pips = 5;    // Min distance between S/R zone defining closes
input double      SL_Fallback_Pips = 15;   // SL distance in pips when zone boundary is not used (Increased default further)
input int         SR_Min_Touches = 2;       // Minimum touches required for a zone to be tradable

// Trend Filter Inputs
input bool        Use_Trend_Filter = true;   // Enable/Disable the main Trend Filter
input int         Trend_FastEMA = 20;        // Fast EMA period for Trend Filter
input int         Trend_SlowEMA = 100;       // Slow EMA period for Trend Filter
input int         Trend_ADXPeriod = 14;       // ADX period for Trend Filter
input double      Trend_ADXThreshold = 20.0; // ADX threshold for trend confirmation

// Breakeven Inputs
input int         BreakevenTriggerPips = 15;  // Pips profit to trigger breakeven
input int         BreakevenBufferPips = 1;    // Pips buffer above/below breakeven

// Strategy 5 Inputs
input double      S5_Lot_Size = 1;    // Lot size for Strategy 5 (used if LotSizing_Mode=DYNAMIC_MARGIN_CHECK)
input int         S5_Min_Body_Pips = 1; // Minimum candle body size in pips for Strategy 5
input int         S5_TP_Pips = 10;      // Take Profit distance in pips for Strategy 5 (Increased Default)
input bool        S5_Use_Trailing_Stop = true; // Enable trailing stop for Strategy 5
input bool        S5_DisableTP = true;     // Disable take profit, only use trailing stop
input int         S5_Trail_Pips = 1;       // Trailing stop distance in pips (Very close)
input int         S5_Trail_Activation_Pips = 1; // Pips in profit to activate trailing stop (Quick activation)

// Global variables
int emaHandle;
double emaValues[];
long barCount; // Changed to long to match Bars() return type
ulong posTicket1 = 0;
ulong posTicket2 = 0;

// Symbol Volume Constraints
double volMin = 0.0;
double volMax = 0.0;
double volStep = 0.0;

// Global variables for stateful S/R zones
SRZone g_activeSupportZones[]; 
SRZone g_activeResistanceZones[]; 
int    g_nearestSupportZoneIndex = -1;  
int    g_nearestResistanceZoneIndex = -1; 

// Trend Filter Handles & Buffers
int trendFastEmaHandle;
int trendSlowEmaHandle;
int trendAdxHandle;
double trendFastEmaValues[];
double trendSlowEmaValues[];
double trendAdxValues[];

// Last Trade Timestamps per Strategy
datetime g_lastTradeTimeStrat1 = 0;
datetime g_lastTradeTimeStrat2 = 0;
datetime g_lastTradeTimeStrat3 = 0;
datetime g_lastTradeTimeStrat4 = 0;
datetime g_lastTradeTimeStrat5 = 0;

//+------------------------------------------------------------------+
//| SR Zone Struct                                                   |
//+------------------------------------------------------------------+


//+------------------------------------------------------------------+
//| Expert initialization function                                    |
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
      // You might want to fail initialization or use default safe values
      return(INIT_FAILED); 
   }
   
   Print("Symbol Volume Constraints:");
   Print("  Min Volume: ", volMin);
   Print("  Max Volume: ", volMax);
   Print("  Volume Step: ", volStep);
   
   // Initialize EMA indicator
   emaHandle = iMA(_Symbol, PERIOD_CURRENT, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   
   if(emaHandle == INVALID_HANDLE)
   {
      Print("Failed to create EMA indicator handle");
      return(INIT_FAILED);
   }
   
   // Initialize barCount to track new bars
   barCount = Bars(_Symbol, PERIOD_CURRENT);
   
   // Clear active S/R zone arrays on init
   ArrayFree(g_activeSupportZones);
   ArrayFree(g_activeResistanceZones);
   g_nearestSupportZoneIndex = -1;
   g_nearestResistanceZoneIndex = -1;
   
   // Display information about the current symbol
   Print("Symbol: ", _Symbol, ", Digits: ", _Digits, ", Point: ", _Point);
   Print("SPREAD LIMITING REMOVED: EA will trade regardless of spread conditions");
   int stopsLevel = SafeLongToInt(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL));
   PrintFormat("Broker Info: Min Stops Level = %d points (%.*f price distance)", 
               stopsLevel, _Digits, stopsLevel * _Point);
   
   // Initialize trend filter indicators
   trendFastEmaHandle = iMA(_Symbol, PERIOD_CURRENT, Trend_FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   trendSlowEmaHandle = iMA(_Symbol, PERIOD_CURRENT, Trend_SlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   trendAdxHandle = iADX(_Symbol, PERIOD_CURRENT, Trend_ADXPeriod);
   
   if(trendFastEmaHandle == INVALID_HANDLE || trendSlowEmaHandle == INVALID_HANDLE || trendAdxHandle == INVALID_HANDLE)
   {
      Print("Failed to create trend filter indicator handles");
      return(INIT_FAILED);
   }
   
   return(INIT_SUCCEEDED);
}

// Convert long to int safely with range check
int SafeLongToInt(long value)
{
   if(value > INT_MAX || value < INT_MIN)
   {
      Print("Warning: Long value ", value, " is out of int range");
      return (int)MathMin(MathMax(value, INT_MIN), INT_MAX);
   }
   return (int)value;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release indicator handle
   if(emaHandle != INVALID_HANDLE)
      IndicatorRelease(emaHandle);

   // Release trend filter indicator handles
   if(trendFastEmaHandle != INVALID_HANDLE)
      IndicatorRelease(trendFastEmaHandle);
   if(trendSlowEmaHandle != INVALID_HANDLE)
      IndicatorRelease(trendSlowEmaHandle);
   if(trendAdxHandle != INVALID_HANDLE)
      IndicatorRelease(trendAdxHandle);
      
   // Stop the timer
   EventKillTimer();
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check if we have a new bar
   int currentBars = Bars(_Symbol, PERIOD_CURRENT);
   if(currentBars == barCount)
   {  // No new bar, check for trailing stop management
      if(S5_Use_Trailing_Stop)
         ManageStrategy5Position();
      return; 
   }   
      
   barCount = currentBars;
   
   // Update indicators
   if(!UpdateIndicators())
      return;
      
   // Log current spread for reference (but don't use it to limit trading)
   IsSpreadAcceptable(Max_Spread);
   
   // Update and Draw Valid S/R Zones (NEW - Call this once per bar)
   UpdateAndDrawValidSRZones();
   
   // Reset comment
   Comment("");
      
   // Check strategy conditions (these return if they execute a trade)
   if(Use_Strategy_1 && CheckStrategy1())
      return;
      
   if(Use_Strategy_2 && CheckStrategy2())
      return;
      
   if(Use_Strategy_3 && CheckStrategy3())
      return;
      
   if(Use_Strategy_4 && CheckStrategy4())
      return;
      
   if(Use_Strategy_5 && CheckStrategy5()) 
      return;
      
   // If no trade was executed, ensure trailing stop is still managed on new bar
   if(S5_Use_Trailing_Stop)
      ManageStrategy5Position();
}

//+------------------------------------------------------------------+
//| Update indicator values                                          |
//+------------------------------------------------------------------+
bool UpdateIndicators()
{
   // Get EMA values for the last 3 bars
   ArraySetAsSeries(emaValues, true);
   if(CopyBuffer(emaHandle, 0, 0, 3, emaValues) < 3)
   {
      Print("Failed to copy EMA indicator values");
      return false;
   }
   
   // Get trend filter indicator values
   ArraySetAsSeries(trendFastEmaValues, true);
   ArraySetAsSeries(trendSlowEmaValues, true);
   ArraySetAsSeries(trendAdxValues, true);
   if(CopyBuffer(trendFastEmaHandle, 0, 0, 3, trendFastEmaValues) < 3 ||
      CopyBuffer(trendSlowEmaHandle, 0, 0, 3, trendSlowEmaValues) < 3 ||
      CopyBuffer(trendAdxHandle, 0, 0, 3, trendAdxValues) < 3)
   {
      Print("Failed to copy trend filter indicator values");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check if there are open positions for this symbol                |
//+------------------------------------------------------------------+
bool HasOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionSelectByTicket(PositionGetTicket(i)))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol)
            return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check if the current bar forms an engulfing pattern (Relaxed Indicator Logic) |
//+------------------------------------------------------------------+
bool IsEngulfing(int shift, bool bullish)
{
   // Use index i for current, i+1 for prior, aligning with indicator logic
   int i = shift;     // Typically 0 when called from CheckStrategyX -> NOW 1
   int priorIdx = i + 1; // Typically 1 when called from CheckStrategyX -> NOW 2
   
   // Basic check for sufficient bars
   if(Bars(_Symbol, PERIOD_CURRENT) < 3 || priorIdx < 0)
   {
      return false;
   }

   // Get required price data
   double open1 = iOpen(_Symbol, PERIOD_CURRENT, i);     // Current Open
   double close1 = iClose(_Symbol, PERIOD_CURRENT, i);    // Current Close
   double open2 = iOpen(_Symbol, PERIOD_CURRENT, priorIdx); // Prior Open
   double close2 = iClose(_Symbol, PERIOD_CURRENT, priorIdx);  // Prior Close
   
   // Check for valid data
   if(open1 == 0 || close1 == 0 || open2 == 0 || close2 == 0)
   {
      Print("IsEngulfing Error: Invalid price data for index ", i, " or ", priorIdx);
      return false;
   }
   
   // Minimal tolerance for float comparisons
   double tolerance = _Point; 

   Print("Analyzing candles for engulfing pattern (Relaxed Indicator Logic):");
   Print("  - Current Bar (", i, "): O=", open1, " C=", close1);
   Print("  - Previous Bar (", priorIdx, "): O=", open2, " C=", close2);

   // --- Trend Filter (Optional - Check if enabled) --- 
   bool trendOkBull = !Engulfing_Use_Trend_Filter; // Default to true if filter is OFF
   bool trendOkBear = !Engulfing_Use_Trend_Filter;
   if(Engulfing_Use_Trend_Filter)
   {
      if(ArraySize(emaValues) < priorIdx + 1)
      {
         Print("IsEngulfing Error: EMA values not available for trend filter index ", priorIdx);
         return false; 
      }
      double maPrior = emaValues[priorIdx]; 
      double midOCPrior = (open2 + close2) / 2.0; 
      trendOkBull = midOCPrior < maPrior;
      trendOkBear = midOCPrior > maPrior;
      Print("  - Trend Filter Check: Bull OK=", trendOkBull, ", Bear OK=", trendOkBear);
   }

   // --- Check Engulfing Pattern --- 
   bool isEngulfing = false;
   
   if(bullish) // Bullish Engulfing Check
   {
      bool priorIsBearish = (close2 < open2 - tolerance);
      bool currentIsBullish = (close1 > open1 + tolerance);
      bool engulfsBody = (open1 < close2 - tolerance) && (close1 > open2 + tolerance);
      
      Print("Checking Bullish Engulfing Conditions (Relaxed Indicator Logic):");
      Print("  - Prior is Bearish (C2<O2-T): ", priorIsBearish);
      Print("  - Current is Bullish (C1>O1+T): ", currentIsBullish);
      Print("  - Engulfs Prior Body (O1<C2-T && C1>O2+T): ", engulfsBody);
      if(Engulfing_Use_Trend_Filter) Print("  - Trend Filter OK: ", trendOkBull);
      
      isEngulfing = priorIsBearish && currentIsBullish && engulfsBody && trendOkBull;
   }
   else // Bearish Engulfing Check
   {
      bool priorIsBullish = (close2 > open2 + tolerance);
      bool currentIsBearish = (close1 < open1 - tolerance);
      bool engulfsBody = (open1 > close2 + tolerance) && (close1 < open2 - tolerance);
      
      Print("Checking Bearish Engulfing Conditions (Relaxed Indicator Logic):");
      Print("  - Prior is Bullish (C2>O2+T): ", priorIsBullish);
      Print("  - Current is Bearish (C1<O1-T): ", currentIsBearish);
      Print("  - Engulfs Prior Body (O1>C2+T && C1<O2-T): ", engulfsBody);
      if(Engulfing_Use_Trend_Filter) Print("  - Trend Filter OK: ", trendOkBear);
      
      isEngulfing = priorIsBullish && currentIsBearish && engulfsBody && trendOkBear;
   }
   
   Print("  - Final Result: ", isEngulfing);
   return isEngulfing;
}

//+------------------------------------------------------------------+
//| Check if price crossed EMA                                       |
//+------------------------------------------------------------------+
bool CrossedEMA(int shift, bool upward)
{
   double close1 = iClose(_Symbol, PERIOD_CURRENT, shift + 1);
   double close0 = iClose(_Symbol, PERIOD_CURRENT, shift);
   
   if(upward)
      return close1 < emaValues[shift + 1] && close0 > emaValues[shift];
   else
      return close1 > emaValues[shift + 1] && close0 < emaValues[shift];
}

//+------------------------------------------------------------------+
//| Check if price stayed on one side of EMA                         |
//+------------------------------------------------------------------+
bool StayedOnSideOfEMA(int startBar, int bars, bool above)
{
   for(int i = startBar; i < startBar + bars; i++)
   {
      double close = iClose(_Symbol, PERIOD_CURRENT, i);
      
      if(above && close < emaValues[i])
         return false;
      
      if(!above && close > emaValues[i])
         return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check if price broke through resistance/support                  |
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
//| Calculate take profit based on risk-reward ratio                 |
//+------------------------------------------------------------------+
double CalculateTakeProfit(bool isBuy, double entryPrice, double stopLoss, double rrRatio)
{
   if(isBuy)
      return entryPrice + (entryPrice - stopLoss) * rrRatio;
   else
      return entryPrice - (stopLoss - entryPrice) * rrRatio;
}

//+------------------------------------------------------------------+
//| Strategy 1: EMA Crossover (Checks last closed bar)               |
//+------------------------------------------------------------------+
bool CheckStrategy1()
{
   // Check cooldown first
   if (IsStrategyOnCooldown(1, MAGIC_STRAT_1))
      return false;
   
   Print("Checking Strategy 1 conditions...");
   
   // Check crossover on the last closed bar (index 1)
   int shiftToCheck = 1;
   // Use pre-calculated emaValues array (indices 1 and 2 needed)
   if (ArraySize(emaValues) < 3) 
   { 
      Print("CheckStrategy1 Error: Not enough EMA values calculated."); 
      return false; 
   }
   double emaCurrent = emaValues[shiftToCheck];     // EMA for bar 1
   double emaPrevious = emaValues[shiftToCheck + 1]; // EMA for bar 2
   double closeCurrent = iClose(_Symbol, PERIOD_CURRENT, shiftToCheck);    // Close for bar 1
   double closePrevious = iClose(_Symbol, PERIOD_CURRENT, shiftToCheck + 1); // Close for bar 2

   // Check for bullish crossover
   if(emaCurrent > emaPrevious && closeCurrent > emaCurrent && closePrevious <= emaPrevious)
   {
      Print("Strategy 1 - Bullish EMA Crossover detected");
      // Target: Nearest resistance zone top. SL: Nearest support zone bottom.
      if(g_nearestResistanceZoneIndex != -1 && g_nearestSupportZoneIndex != -1) 
      {
          double resistanceTop = g_activeResistanceZones[g_nearestResistanceZoneIndex].topBoundary;
          double supportBottomForSL = g_activeSupportZones[g_nearestSupportZoneIndex].bottomBoundary;
          PrintFormat("  - Target Resistance Top: %.5f, SL Support Bottom: %.5f", resistanceTop, supportBottomForSL);
          ExecuteTrade(1, MAGIC_STRAT_1, true, resistanceTop, supportBottomForSL); // Pass strat#, magic#, side, target, sl_level
          return true;
      }
      else
      {
          Print("  - Required S/R zone for Target or SL not found (Resistance Index: ", g_nearestResistanceZoneIndex, ", Support Index: ", g_nearestSupportZoneIndex, ")");
      }
   }
   
   // Check for bearish crossover
   if(emaCurrent < emaPrevious && closeCurrent < emaCurrent && closePrevious >= emaPrevious)
   {
      Print("Strategy 1 - Bearish EMA Crossover detected");
      // Target: Nearest support zone bottom. SL: Nearest resistance zone top.
      if(g_nearestSupportZoneIndex != -1 && g_nearestResistanceZoneIndex != -1)
      {
          double supportBottom = g_activeSupportZones[g_nearestSupportZoneIndex].bottomBoundary;
          double resistanceTopForSL = g_activeResistanceZones[g_nearestResistanceZoneIndex].topBoundary;
          PrintFormat("  - Target Support Bottom: %.5f, SL Resistance Top: %.5f", supportBottom, resistanceTopForSL);
          ExecuteTrade(1, MAGIC_STRAT_1, false, supportBottom, resistanceTopForSL); 
          return true;
      }
      else
      {
          Print("  - Required S/R zone for Target or SL not found (Support Index: ", g_nearestSupportZoneIndex, ", Resistance Index: ", g_nearestResistanceZoneIndex, ")");
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Strategy 2: Engulfing at S/R (Checks last bar, marks all engulfing)|
//+------------------------------------------------------------------+
bool CheckStrategy2()
{
   // Check cooldown first
   if (IsStrategyOnCooldown(2, MAGIC_STRAT_2))
      return false;
   
   Print("Checking Strategy 2 conditions...");
   int shiftToCheck = 1; // Check the last completed bar
   
   // --- Check and Mark Engulfing Pattern First --- 
   bool isBullishEngulfing = IsEngulfing(shiftToCheck, true);
   bool isBearishEngulfing = false; 
   if (!isBullishEngulfing) // Only check bearish if not bullish
   { 
       isBearishEngulfing = IsEngulfing(shiftToCheck, false);
   }
   
   // Draw marker if any engulfing pattern was found
   if (isBullishEngulfing)
   {
       DrawEngulfingMarker(shiftToCheck, true); 
       Print("Strategy 2 - Potential Bullish Engulfing Marked on bar ", shiftToCheck);
   }
   else if (isBearishEngulfing)
   {
       DrawEngulfingMarker(shiftToCheck, false);
       Print("Strategy 2 - Potential Bearish Engulfing Marked on bar ", shiftToCheck);
   }
   // --------------------------------------------------
   
   // Get prices for the completed bar (index 1) for S/R check
   double closePriceBar1 = iClose(_Symbol, PERIOD_CURRENT, shiftToCheck);
   if (closePriceBar1 == 0) 
   {   
       Print("Strategy 2 Error: Could not get close price for bar ", shiftToCheck);
       return false; // Error getting price
   }

   // Nearest support/resistance zones are now found in UpdateAndDrawValidSRZones()
   // We use the global indices g_nearestSupportZoneIndex and g_nearestResistanceZoneIndex
   
   Print("Strategy 2 - Price (Bar ", shiftToCheck, "): ", closePriceBar1);
   Print("Strategy 2 - Nearest Resistance Zone Index: ", g_nearestResistanceZoneIndex);
   Print("Strategy 2 - Nearest Support Zone Index: ", g_nearestSupportZoneIndex);
   
   // --- Now check for TRADE conditions --- 
   
   // Get Open and Close of the engulfing candle (shiftToCheck = 1)
   double openEngulfing = iOpen(_Symbol, PERIOD_CURRENT, shiftToCheck);
   double closeEngulfing = closePriceBar1; // We already have this
   
   // Condition: Bullish engulfing AND candle is retesting support zone
   if(isBullishEngulfing && g_nearestSupportZoneIndex != -1) // Check if a nearest zone exists
   {
      SRZone nearestSupport = g_activeSupportZones[g_nearestSupportZoneIndex];
      double emaEngulfing = emaValues[shiftToCheck]; // EMA value for the engulfing candle bar
      
      // Get data for the engulfing candle and surrounding candles
      double open1 = openEngulfing;
      double close1 = closeEngulfing;
      double low1 = iLow(_Symbol, PERIOD_CURRENT, shiftToCheck);
      double high1 = iHigh(_Symbol, PERIOD_CURRENT, shiftToCheck);
      
      // Get previous candle data
      double open2 = iOpen(_Symbol, PERIOD_CURRENT, shiftToCheck + 1);
      double close2 = iClose(_Symbol, PERIOD_CURRENT, shiftToCheck + 1);
      double low2 = iLow(_Symbol, PERIOD_CURRENT, shiftToCheck + 1);
      
      // Comprehensive retest detection - check all possible ways a candle can interact with the zone
      
      // 1. Check if the candle body is inside the zone
      bool bodyInZone = (open1 >= nearestSupport.bottomBoundary && open1 <= nearestSupport.topBoundary) || 
                        (close1 >= nearestSupport.bottomBoundary && close1 <= nearestSupport.topBoundary);
      
      // 2. Check if the candle body crosses/touches the zone
      bool bodyTouchingZone = (open1 <= nearestSupport.topBoundary && close1 >= nearestSupport.bottomBoundary) ||
                              (close1 <= nearestSupport.topBoundary && open1 >= nearestSupport.bottomBoundary);
      
      // 3. Check if the candle wick is inside the zone
      bool wickInZone = (low1 >= nearestSupport.bottomBoundary && low1 <= nearestSupport.topBoundary);
      
      // 4. Check if the candle wick penetrates through the zone
      bool wickThroughZone = (low1 < nearestSupport.bottomBoundary && (open1 > nearestSupport.topBoundary || close1 > nearestSupport.topBoundary));
      
      // Combined retest condition - any interaction with the zone is considered a valid retest
      bool isValidRetest = bodyInZone || bodyTouchingZone || wickInZone || wickThroughZone;
      
      // For debugging
      if(isValidRetest) {
         PrintFormat("Valid bullish retest detected: bodyInZone=%s, bodyTouchingZone=%s, wickInZone=%s, wickThroughZone=%s",
                    (bodyInZone ? "true" : "false"),
                    (bodyTouchingZone ? "true" : "false"),
                    (wickInZone ? "true" : "false"),
                    (wickThroughZone ? "true" : "false"));
      }
      
      // Check Zone Touches, Valid Retest, and Price vs EMA
      // Note: We're making the EMA condition optional by commenting it out
      if (nearestSupport.touchCount >= SR_Min_Touches && 
          isValidRetest) // && closeEngulfing > emaEngulfing)
      {
         Print("Strategy 2 - TRADE Trigger: Bullish conditions met:");
         PrintFormat("  - Zone Touches (%d) >= Min Touches (%d)", nearestSupport.touchCount, SR_Min_Touches);
         
         if(bodyInZone) PrintFormat("  - Candle body inside support zone");
         else if(bodyTouchingZone) PrintFormat("  - Candle body touching support zone");
         else if(wickInZone) PrintFormat("  - Candle wick inside support zone");
         else if(wickThroughZone) PrintFormat("  - Candle wick penetrating through support zone");
         
         PrintFormat("  - Bullish Engulfing Close (%.5f) vs EMA (%.5f)", closeEngulfing, emaEngulfing);
         PrintFormat("  - Support Zone: Top=%.5f, Bottom=%.5f", nearestSupport.topBoundary, nearestSupport.bottomBoundary);
         PrintFormat("  - Engulfing Pattern: Current (O=%.5f, C=%.5f), Previous (O=%.5f, C=%.5f)", 
                    open1, close1, open2, close2);
         
         // Target the top of the nearest resistance zone, if one exists
         double targetResistanceTop = (g_nearestResistanceZoneIndex != -1) ? g_activeResistanceZones[g_nearestResistanceZoneIndex].topBoundary : 0.0;
         Print("  - Targeting Resistance Zone Top: ", targetResistanceTop);
         ExecuteTrade(2, MAGIC_STRAT_2, true, targetResistanceTop, nearestSupport.definingBodyLow); // Pass strat#, magic#, side, target, sl_level
         return true; // Trade executed
   }
   else
   {
         PrintFormat("Strategy 2 - Bullish Engulfing signal ignored. Touches (%d<%d): %s, Valid Retest: %s, Price/EMA: %s", 
                     nearestSupport.touchCount, SR_Min_Touches,
                     (nearestSupport.touchCount >= SR_Min_Touches ? "true" : "false"),
                     (isValidRetest ? "true" : "false"), 
                     (closeEngulfing > emaEngulfing ? "true" : "false"));
         
         if(!isValidRetest) {
            PrintFormat("  - Debug: bodyInZone=%s, bodyTouchingZone=%s, wickInZone=%s, wickThroughZone=%s", 
                       (bodyInZone ? "true" : "false"),
                       (bodyTouchingZone ? "true" : "false"),
                       (wickInZone ? "true" : "false"),
                       (wickThroughZone ? "true" : "false"));
            PrintFormat("  - Debug: Support Zone (Top=%.5f, Bottom=%.5f), Candle (O=%.5f, C=%.5f, L=%.5f)",
                       nearestSupport.topBoundary, nearestSupport.bottomBoundary,
                       open1, close1, low1);
         }
      }
   }
   
   // Condition: Bearish engulfing AND candle is retesting resistance zone
   if(isBearishEngulfing && g_nearestResistanceZoneIndex != -1) // Check if a nearest zone exists
   {
      SRZone nearestResistance = g_activeResistanceZones[g_nearestResistanceZoneIndex];
      double emaEngulfing = emaValues[shiftToCheck]; // EMA value for the engulfing candle bar
      
      // Get data for the engulfing candle and surrounding candles
      double open1 = openEngulfing;
      double close1 = closeEngulfing;
   double high1 = iHigh(_Symbol, PERIOD_CURRENT, shiftToCheck);
   double low1 = iLow(_Symbol, PERIOD_CURRENT, shiftToCheck);
      
      // Get previous candle data
      double open2 = iOpen(_Symbol, PERIOD_CURRENT, shiftToCheck + 1);
      double close2 = iClose(_Symbol, PERIOD_CURRENT, shiftToCheck + 1);
      double high2 = iHigh(_Symbol, PERIOD_CURRENT, shiftToCheck + 1);
      
      // Comprehensive retest detection - check all possible ways a candle can interact with the zone
      
      // 1. Check if the candle body is inside the zone
      bool bodyInZone = (open1 >= nearestResistance.bottomBoundary && open1 <= nearestResistance.topBoundary) || 
                        (close1 >= nearestResistance.bottomBoundary && close1 <= nearestResistance.topBoundary);
      
      // 2. Check if the candle body crosses/touches the zone
      bool bodyTouchingZone = (open1 <= nearestResistance.topBoundary && close1 >= nearestResistance.bottomBoundary) ||
                              (close1 <= nearestResistance.topBoundary && open1 >= nearestResistance.bottomBoundary);
      
      // 3. Check if the candle wick is inside the zone
      bool wickInZone = (high1 >= nearestResistance.bottomBoundary && high1 <= nearestResistance.topBoundary);
      
      // 4. Check if the candle wick penetrates through the zone
      bool wickThroughZone = (high1 > nearestResistance.topBoundary && (open1 < nearestResistance.bottomBoundary || close1 < nearestResistance.bottomBoundary));
      
      // Combined retest condition - any interaction with the zone is considered a valid retest
      bool isValidRetest = bodyInZone || bodyTouchingZone || wickInZone || wickThroughZone;
      
      // For debugging
      if(isValidRetest) {
         PrintFormat("Valid bearish retest detected: bodyInZone=%s, bodyTouchingZone=%s, wickInZone=%s, wickThroughZone=%s",
                    (bodyInZone ? "true" : "false"),
                    (bodyTouchingZone ? "true" : "false"),
                    (wickInZone ? "true" : "false"),
                    (wickThroughZone ? "true" : "false"));
      }
      
      // Check Zone Touches, Valid Retest, and Price vs EMA
      // Note: We're making the EMA condition optional by commenting it out
      if(nearestResistance.touchCount >= SR_Min_Touches && 
         isValidRetest) // && closeEngulfing < emaEngulfing)
      {
         Print("Strategy 2 - TRADE Trigger: Bearish conditions met:");
         PrintFormat("  - Zone Touches (%d) >= Min Touches (%d)", nearestResistance.touchCount, SR_Min_Touches);
         
         if(bodyInZone) PrintFormat("  - Candle body inside resistance zone");
         else if(bodyTouchingZone) PrintFormat("  - Candle body touching resistance zone");
         else if(wickInZone) PrintFormat("  - Candle wick inside resistance zone");
         else if(wickThroughZone) PrintFormat("  - Candle wick penetrating through resistance zone");
         
         PrintFormat("  - Bearish Engulfing Close (%.5f) vs EMA (%.5f)", closeEngulfing, emaEngulfing);
         PrintFormat("  - Resistance Zone: Top=%.5f, Bottom=%.5f", nearestResistance.topBoundary, nearestResistance.bottomBoundary);
         PrintFormat("  - Engulfing Pattern: Current (O=%.5f, C=%.5f), Previous (O=%.5f, C=%.5f)", 
                    open1, close1, open2, close2);
         
         // Target the bottom of the nearest support zone, if one exists
         double targetSupportBottom = (g_nearestSupportZoneIndex != -1) ? g_activeSupportZones[g_nearestSupportZoneIndex].bottomBoundary : 0.0;
         Print("  - Targeting Support Zone Bottom: ", targetSupportBottom);
         ExecuteTrade(2, MAGIC_STRAT_2, false, targetSupportBottom, nearestResistance.definingBodyHigh); // Pass strat#, magic#, side, target, sl_level
         return true; // Trade executed
      }
   else
   {
         PrintFormat("Strategy 2 - Bearish Engulfing signal ignored. Touches (%d<%d): %s, Valid Retest: %s, Price/EMA: %s", 
                     nearestResistance.touchCount, SR_Min_Touches,
                     (nearestResistance.touchCount >= SR_Min_Touches ? "true" : "false"),
                     (isValidRetest ? "true" : "false"), 
                     (closeEngulfing < emaEngulfing ? "true" : "false"));
         
         if(!isValidRetest) {
            PrintFormat("  - Debug: bodyInZone=%s, bodyTouchingZone=%s, wickInZone=%s, wickThroughZone=%s", 
                       (bodyInZone ? "true" : "false"),
                       (bodyTouchingZone ? "true" : "false"),
                       (wickInZone ? "true" : "false"),
                       (wickThroughZone ? "true" : "false"));
            PrintFormat("  - Debug: Resistance Zone (Top=%.5f, Bottom=%.5f), Candle (O=%.5f, C=%.5f, H=%.5f)",
                       nearestResistance.topBoundary, nearestResistance.bottomBoundary,
                       open1, close1, high1);
         }
      }
   }
   
   // No trade executed for Strategy 2 this bar
      return false;
}

//+------------------------------------------------------------------+
//| Strategy 3: Break past resistance + EMA engulfing                |
//+------------------------------------------------------------------+
bool CheckStrategy3()
{
   // Check cooldown first
   if (IsStrategyOnCooldown(3, MAGIC_STRAT_3))
      return false;
   
   Print("Checking Strategy 3 conditions...");
   double currentPrice = iClose(_Symbol, PERIOD_CURRENT, 0);
   
   // Find nearest resistance and support - USE GLOBAL VARIABLES NOW
   double resistance = g_nearestResistanceZoneIndex != -1 ? g_activeResistanceZones[g_nearestResistanceZoneIndex].topBoundary : 0.0;
   double support = g_nearestSupportZoneIndex != -1 ? g_activeSupportZones[g_nearestSupportZoneIndex].bottomBoundary : 0.0;
   
   Print("Strategy 3 - Current Price: ", currentPrice);
   Print("Strategy 3 - Nearest Resistance Zone Top (Global): ", resistance);
   Print("Strategy 3 - Nearest Support Zone Bottom (Global): ", support);
   
   if(resistance == 0 || support == 0)
   {
      Print("Strategy 3 - No valid support/resistance zone found");
      return false;
   }
   
   // Check for bullish engulfing pattern
   if(IsEngulfing(0, true))
   {
      Print("Strategy 3 - Bullish engulfing detected");
      // Look for recently broken resistance zone (within the last 5 bars)
      for(int i = 1; i <= 5; i++)
      {
         // Check if bar i broke through resistance (TOP boundary)
         if(BrokeLevel(i, resistance, true))
         {
            Print("Strategy 3 - Resistance broken at bar ", i);
            // Check if price stayed on the right side of EMA
            if(StayedOnSideOfEMA(0, 3, true))
            {
               Print("Strategy 3 - Price stayed above EMA");
               // We already have the latest nearest resistance zone in g_nearestResistanceZoneIndex from UpdateAndDrawValidSRZones
               // We might need a concept of "further" resistance if the break happened
               // For now, let's just use the current nearest one as the target if it's further away
               // Note: This logic might need refinement depending on exact strategy goal after break.
               if(g_nearestResistanceZoneIndex != -1) // Check if a valid zone exists
               {
                  Print("Strategy 3 - Targeting nearest resistance zone top found at: ", resistance);
                  ExecuteTrade(3, MAGIC_STRAT_3, true, resistance); // SL will use fallback logic (zoneBoundary=0)
               return true;
         }
      }
         }
      }
   }
   
   // Check for bearish engulfing pattern
   if(IsEngulfing(0, false))
   {
      Print("Strategy 3 - Bearish engulfing detected");
      // Look for recently broken support zone (within the last 5 bars)
      for(int i = 1; i <= 5; i++)
      {
         // Check if bar i broke through support (BOTTOM boundary)
         if(BrokeLevel(i, support, false))
         {
            Print("Strategy 3 - Support broken at bar ", i);
            // Check if price stayed on the right side of EMA
            if(StayedOnSideOfEMA(0, 3, false))
            {
               Print("Strategy 3 - Price stayed below EMA");
               // Similar to above, use the current nearest support. Refine if needed.
               if(g_nearestSupportZoneIndex != -1) // Check if a valid zone exists
               {
                  Print("Strategy 3 - Targeting nearest support zone bottom found at: ", support);
                  ExecuteTrade(3, MAGIC_STRAT_3, false, support); // SL will use fallback logic
               return true;
               }
            }
         }
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Strategy 4: Simple engulfing pattern (Checks last closed bar)    |
//+------------------------------------------------------------------+
bool CheckStrategy4()
{
   // Check cooldown first
   if (IsStrategyOnCooldown(4, MAGIC_STRAT_4))
      return false;
   
   Print("Checking Strategy 4 conditions...");
   int shiftToCheck = 1; // Check the last completed bar
   
   // Check for bullish engulfing on the last closed bar
   if(IsEngulfing(shiftToCheck, true))
   {
      Print("Strategy 4 - Bullish engulfing detected on bar ", shiftToCheck);
      DrawEngulfingMarker(shiftToCheck, true); // Draw marker
      Print("  - Bar (", shiftToCheck, ") Close: ", iClose(_Symbol, PERIOD_CURRENT, shiftToCheck));
      Print("  - Bar (", shiftToCheck+1, ") Close: ", iClose(_Symbol, PERIOD_CURRENT, shiftToCheck+1));
      
      // Target level logic might need adjustment if based on bar 0
      double targetLevel = iClose(_Symbol, PERIOD_CURRENT, 0) + 100 * _Point; // Example target based on current price
      ExecuteTrade(4, MAGIC_STRAT_4, true, targetLevel); // SL will use fallback logic
      return true;
   }
   
   // Check for bearish engulfing on the last closed bar
   if(IsEngulfing(shiftToCheck, false))
   {                             
      Print("Strategy 4 - Bearish engulfing detected on bar ", shiftToCheck);
      DrawEngulfingMarker(shiftToCheck, false); // Draw marker
      Print("  - Bar (", shiftToCheck, ") Close: ", iClose(_Symbol, PERIOD_CURRENT, shiftToCheck));
      Print("  - Bar (", shiftToCheck+1, ") Close: ", iClose(_Symbol, PERIOD_CURRENT, shiftToCheck+1));
      
      // Target level logic might need adjustment if based on bar 0
      double targetLevel = iClose(_Symbol, PERIOD_CURRENT, 0) - 100 * _Point; // Example target based on current price
      ExecuteTrade(4, MAGIC_STRAT_4, false, targetLevel); // SL will use fallback logic
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Strategy 5: Simple movement strategy (for testing)                  |
//+------------------------------------------------------------------+
bool CheckStrategy5()
{
   // Check cooldown first
   if (IsStrategyOnCooldown(5, MAGIC_STRAT_5))
      return false;
   
   Print("Checking Strategy 5 conditions...");
   // Use shift = 1 to check the last completed bar
   int shift = 1;
   double open1 = iOpen(_Symbol, PERIOD_CURRENT, shift);
   double close1 = iClose(_Symbol, PERIOD_CURRENT, shift);
   
   // Check if bar data is available
   if(open1 == 0 || close1 == 0)
   {
      Print("Strategy 5 - Not enough data for bar at shift ", shift);
      return false;
   }
   
   double bodySize = MathAbs(close1 - open1);
   double bodySizePips = bodySize / _Point;
   
   Print("Strategy 5 - Previous Candle (shift=", shift, ") Body Size: ", bodySizePips, " pips");
   Print("  - Open: ", open1, ", Close: ", close1);
   
   if(bodySizePips > S5_Min_Body_Pips)
   {
       bool isBuy = (close1 > open1); // Determine direction based on the completed bar
       Print("Strategy 5 - Triggered based on previous bar. Direction: ", isBuy ? "BUY" : "SELL");
       ExecuteTradeStrategy5(isBuy);
       return true;
      }
      else
      {
      Print("Strategy 5 - Previous candle body size too small (", bodySizePips, " <= ", S5_Min_Body_Pips, ")");
      return false;
   }
}

//+------------------------------------------------------------------+
//| Execute Strategy 5 trade                                         |
//+------------------------------------------------------------------+
void ExecuteTradeStrategy5(bool isBuy)
{
   int strategyNum = 5;
   ulong magicNum = MAGIC_STRAT_5;
   PrintFormat("ExecuteTradeStrategy5 called (Magic: %d)", magicNum);

   Print("Attempting to execute Strategy 5 ", isBuy ? "BUY" : "SELL", " trade...");
   
   // Log current spread at time of trade execution (for information only)
   LogCurrentSpread();
   
   // Get current prices and minimum distance
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double minStopDistPoints = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   
   // Determine entry price, SL, and TP
   double entryPrice = 0;
   double stopLoss = 0;
   double takeProfit = 0;
   
   if(isBuy)
   {
      entryPrice = ask;
      // Place SL below current Bid, respecting minimum stops level
      stopLoss = bid - minStopDistPoints;
      // Correct TP logic: TP above entry for BUY
      if (!S5_DisableTP)
      {
         takeProfit = ask + S5_TP_Pips * _Point;
         // Ensure TP is at least minStopDistPoints away from Ask
         takeProfit = MathMax(takeProfit, ask + minStopDistPoints);
      }
   }
   else // Sell
   {
      entryPrice = bid;
      // Place SL above current Ask, respecting minimum stops level
      stopLoss = ask + minStopDistPoints;
      // Correct TP logic: TP below entry for SELL
      if (!S5_DisableTP)
      {
         takeProfit = bid - S5_TP_Pips * _Point;
         // Ensure TP is at least minStopDistPoints away from Bid
         takeProfit = MathMin(takeProfit, bid - minStopDistPoints);
      }
   }
   
   // Normalize prices to the correct number of digits
   stopLoss = NormalizeDouble(stopLoss, _Digits);
   if (!S5_DisableTP)
   {
      takeProfit = NormalizeDouble(takeProfit, _Digits);
   }
   
   Print("Strategy 5 Trade Parameters (Corrected TP Logic):");
   Print("  - Direction: ", isBuy ? "BUY" : "SELL");
   Print("  - Entry Price (Approx): ", entryPrice); // Market order, actual entry may vary slightly
   Print("  - Stop Loss: ", stopLoss);
   if (!S5_DisableTP)
   {
      Print("  - Take Profit: ", takeProfit);
   }
   else
   {
      Print("  - Take Profit: Disabled");
   }
   
   //--- Check if calculated SL/TP are logical --- 
   if(isBuy)
   {
      if(stopLoss >= entryPrice)
      {
         Print("Strategy 5 Error: Calculated SL (", stopLoss, ") is not below Ask price (", entryPrice, "). Aborting trade.");
         return;
      }
      if(!S5_DisableTP)
      {
         if(takeProfit >= entryPrice)
         {
            Print("Strategy 5 Warning: Calculated TP (", takeProfit, ") is not below Ask price (", entryPrice, "). Check S5_TP_Pips and Stops Level.");
            // Adjust TP further if necessary, e.g., set it equal to SL? Or skip TP?
            // For now, we proceed but log warning. Broker might still reject.
         }
      }
   }
   else // Sell
   {
      if(stopLoss <= entryPrice)
      {
         Print("Strategy 5 Error: Calculated SL (", stopLoss, ") is not above Bid price (", entryPrice, "). Aborting trade.");
         return;
      }
      if(!S5_DisableTP)
      {
         if(takeProfit <= entryPrice)
         {
            Print("Strategy 5 Warning: Calculated TP (", takeProfit, ") is not above Bid price (", entryPrice, "). Check S5_TP_Pips and Stops Level.");
            // Adjust TP further if necessary? Or skip TP?
            // For now, we proceed but log warning. Broker might still reject.
         }
      }
   }

   // --- Determine Initial Lot Size based on Mode ---
   double initialLotSize;
   if(LotSizing_Mode == ALWAYS_MINIMUM_LOT)
   {
       initialLotSize = volMin;
       PrintFormat("Strategy 5: Lot sizing mode set to ALWAYS_MINIMUM_LOT. Using %.5f lots.", initialLotSize);
   }
   else // DYNAMIC_MARGIN_CHECK
   {
       initialLotSize = NormalizeVolume(S5_Lot_Size);
       PrintFormat("Strategy 5: Lot sizing mode set to DYNAMIC_MARGIN_CHECK. Attempting %.5f lots.", initialLotSize);
   }

   // Ensure initial lot size is not zero
   if (initialLotSize <= 0)
   {
       Print("Strategy 5 Error: Initial lot size is zero or less. Cannot trade.");
       return;
   }

   double lotSize = initialLotSize; // Use the lot determined by the mode
   
   // --- Margin Check --- 
   double marginRequired = 0;
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   string orderTypeStr = isBuy ? "Buy" : "Sell"; // For logging
   
   if(!OrderCalcMargin(isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, lotSize, entryPrice, marginRequired))
   {
       Print("ExecuteTrade Error: OrderCalcMargin failed for initial lot size. Error: ", GetLastError());
       return; 
   }
   
   PrintFormat("ExecuteTrade: Checking margin for %s %.5f lots. Required: %.2f, Available Free: %.2f", 
               orderTypeStr, lotSize, marginRequired, freeMargin);
               
   if(marginRequired > freeMargin)
   {
      // Only attempt fallback to minimum lot if in DYNAMIC_MARGIN_CHECK mode
      if (LotSizing_Mode == DYNAMIC_MARGIN_CHECK)
       {
          PrintFormat("Strategy 5 Warning: Insufficient margin (%.2f) for desired lot size (%.5f). Attempting minimum lot size (%.5f).",
                      freeMargin, lotSize, volMin);
          lotSize = volMin; // Attempt minimum lot size

          // Ensure minimum lot is not zero
          if (lotSize <= 0)
          {
              Print("Strategy 5 Error: Minimum lot size (volMin) is zero or less. Cannot trade.");
              return; // Use return for void function
          }

          // Recalculate margin for minimum lot size
          if(!OrderCalcMargin(isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, lotSize, entryPrice, marginRequired))
          {
              Print("ExecuteTrade Error: OrderCalcMargin failed for minimum lot size. Error: ", GetLastError());
              return; // Use return for void function
          }

          PrintFormat("Strategy 5: Margin check for minimum lot %.5f. Required: %.2f, Available Free: %.2f",
                      lotSize, marginRequired, freeMargin);
       }
      // If not DYNAMIC_MARGIN_CHECK, and initial check failed, we just proceed to the final check below
      
      // Final Check: is there enough margin for the current lotSize?
      if(marginRequired > freeMargin)
      {   
         PrintFormat("Strategy 5 Error: Insufficient margin (%.2f) even for %s lot size (%.5f). Required: %.2f. Aborting trade.",
                     freeMargin, (LotSizing_Mode == ALWAYS_MINIMUM_LOT ? "minimum" : "fallback minimum"), lotSize, marginRequired);
         return; // Use return for void function
      }
 
      // Log if proceeding with minimum lot in dynamic mode
      if (LotSizing_Mode == DYNAMIC_MARGIN_CHECK && lotSize == volMin)
          Print("Strategy 5: Proceeding with minimum lot size: ", lotSize);
   }
   // --- End Margin Check ---
   
   // Prepare trade request
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lotSize;
   request.type = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   request.price = entryPrice;
   request.sl = stopLoss;
   request.tp = takeProfit;
   request.deviation = 10;
   request.magic = magicNum; // Use defined magic number
   request.comment = "Strategy 5 " + string(isBuy ? "Buy" : "Sell");
   
   // Check current spread and warn if high
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > Max_Spread) {
      Print("Warning: High spread (", spread, ") but proceeding with trade");
   }
   
   // Send trade order
   bool orderSent = OrderSend(request, result);
   
   if(!orderSent)
   {
      Print("OrderSend failed. Error code: ", GetLastError());
      return;
   }
   
   if(result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED)
   {
      Print("Order executed successfully. Ticket: ", result.order);
      g_lastTradeTimeStrat5 = TimeCurrent(); // Update last trade time for Strat 5
      return;
   }
   else
   {
      Print("Order execution failed. Retcode: ", result.retcode);
      return;
   }
}

//+------------------------------------------------------------------+
//| Helper to convert Trade Retcode to String (Revised & Simplified) |
//+------------------------------------------------------------------+
string TradeRetcodeToString(uint retcode)
{
    switch(retcode)
    {
        // Core MQL5 Trade Server Return Codes based on MqlTradeResult documentation
        case TRADE_RETCODE_REQUOTE:             return "Requote (10004)";
        case TRADE_RETCODE_REJECT:              return "Reject (10008)";
        case TRADE_RETCODE_CANCEL:              return "Cancel (10009)";
        case TRADE_RETCODE_PLACED:              return "Placed (10010)"; // Order placed in system
        case TRADE_RETCODE_DONE:                return "Done (10011)";   // Request completed
        case TRADE_RETCODE_DONE_PARTIAL:        return "Done Partial (10012)";
        case TRADE_RETCODE_ERROR:               return "Error (10013)";
        case TRADE_RETCODE_TIMEOUT:             return "Timeout (10014)";
        case TRADE_RETCODE_INVALID:             return "Invalid Request (10015)";
        case TRADE_RETCODE_INVALID_VOLUME:      return "Invalid Volume (10016)";
        case TRADE_RETCODE_INVALID_PRICE:       return "Invalid Price (10017)";
        case TRADE_RETCODE_INVALID_STOPS:       return "Invalid Stops (10018)";
        // case TRADE_RETCODE_INVALID_TRADE_VOLUME: return "Invalid Trade Volume (10019)"; // Often overlaps/less common
        // case TRADE_RETCODE_ORDER_FROZEN:        return "Order Frozen (10020)"; // Less common/may not be defined
        case TRADE_RETCODE_INVALID_EXPIRATION:  return "Invalid Expiration (10021)";
        case TRADE_RETCODE_CONNECTION:          return "Connection Problem (10022)";
        case TRADE_RETCODE_TOO_MANY_REQUESTS:   return "Too Many Requests (10023)";
        case TRADE_RETCODE_NO_MONEY:            return "No Money (10024)"; // Or Not Enough Money
        // case TRADE_RETCODE_NOT_ENOUGH_MONEY:    return "Not Enough Money (10025)"; // Covered by NO_MONEY
        case TRADE_RETCODE_PRICE_CHANGED:       return "Price Changed (10026)";
        case TRADE_RETCODE_TRADE_DISABLED:      return "Trade Disabled (10027)";
        case TRADE_RETCODE_MARKET_CLOSED:       return "Market Closed (10028)";
        case TRADE_RETCODE_INVALID_ORDER:       return "Invalid Order (10029)";
        case TRADE_RETCODE_INVALID_FILL:        return "Invalid Fill (10030)";
        // case TRADE_RETCODE_TRADE_NOT_ALLOWED:   return "Trade Not Allowed (10031)"; // Often covered by DISABLED
        // The following are less common or potentially platform-specific
        // case TRADE_RETCODE_AUTH_FAILED:         return "Auth Failed (10032)";
        // case TRADE_RETCODE_HEADER_INVALID:      return "Header Invalid (10033)";
        // case TRADE_RETCODE_REQUEST_INVALID:     return "Request Invalid (10034)";
        // case TRADE_RETCODE_ACCOUNT_DISABLED:    return "Account Disabled (10035)";
        // case TRADE_RETCODE_INVALID_ACCOUNT:     return "Invalid Account (10036)";
        // case TRADE_RETCODE_TRADE_TIMEOUT:       return "Trade Timeout (10037)";
        // case TRADE_RETCODE_ORDER_NOT_FOUND:     return "Order Not Found (10038)"; 
        // case TRADE_RETCODE_PRICE_OFF:           return "Price Off (10039)";
        // case TRADE_RETCODE_INVALID_STOPLOSS:    return "Invalid Stoploss (10040)";
        // case TRADE_RETCODE_INVALID_TAKEPROFIT:  return "Invalid Takeproprofit (10041)";
        // case TRADE_RETCODE_POSITION_CLOSED:     return "Position Closed (10042)";
        case TRADE_RETCODE_LIMIT_POSITIONS:     return "Limit Positions (10043)";
        case TRADE_RETCODE_LIMIT_ORDERS:        return "Limit Orders (10044)";
        // case TRADE_RETCODE_LIMIT_VOLUME:        return "Limit Volume (10045)";
        // case TRADE_RETCODE_ORDER_REJECTED:      return "Order Rejected (10046)"; // Covered by REJECT
        // case TRADE_RETCODE_UNSUPPORTED_FILL_POLICY: return "Unsupported Fill Policy (10047)";
        default:                                return "Unknown (" + (string)retcode + ")";
    }
}

//+------------------------------------------------------------------+
//| Execute trade with proper risk management                        |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Execute trade with custom risk management                        |
//+------------------------------------------------------------------+
bool ExecuteTrade(int strategyNum, ulong magicNum, bool isBuy, double targetPrice, double zoneBoundary = 0.0)
{
   PrintFormat("ExecuteTrade called by Strategy %d (Magic: %d)", strategyNum, magicNum);

   // Get current prices
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // Calculate entry price with spread consideration
   double entryPrice = isBuy ? ask : bid;
   
   // Calculate distance to EMA for TP
   double emaCurrent = emaValues[0];
   // Calculate distance from EMA to the tested S/R level (zoneBoundary)
   double distance_EMA_to_TestedZone = MathAbs(emaCurrent - zoneBoundary);
   
   // Calculate TP based on entry price and twice the distance from EMA to the tested zone
   double takeProfitPrice = isBuy ? entryPrice + (2 * distance_EMA_to_TestedZone) : entryPrice - (2 * distance_EMA_to_TestedZone);
   
   // Calculate stop loss - use 10% of account balance if no zone boundary provided
   double stopLossPrice;
   if(zoneBoundary != 0.0) {
      stopLossPrice = isBuy ? zoneBoundary - (SL_Buffer_Pips * _Point) : zoneBoundary + (SL_Buffer_Pips * _Point);
   } else {
      double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      double riskAmount = accountBalance * 0.1; // 10% of account
      double stopDistance = riskAmount / (Lot_Size_1 * SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE));
      stopLossPrice = isBuy ? entryPrice - stopDistance : entryPrice + stopDistance;
   }
   
   // Check if SL is too close (less than stops level)
   int stopsLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minStopDistance = stopsLevel * _Point;
   
   if(isBuy && (entryPrice - stopLossPrice) < minStopDistance) {
      stopLossPrice = entryPrice - minStopDistance;
      Print("Adjusted SL to minimum distance: ", stopLossPrice);
   }
   else if(!isBuy && (stopLossPrice - entryPrice) < minStopDistance) {
      stopLossPrice = entryPrice + minStopDistance;
      Print("Adjusted SL to minimum distance: ", stopLossPrice);
   }
   
   // --- Determine Initial Lot Size based on Mode ---
   double initialLotSize;
   if(LotSizing_Mode == ALWAYS_MINIMUM_LOT)
   {
       initialLotSize = volMin;
       PrintFormat("ExecuteTrade: Lot sizing mode set to ALWAYS_MINIMUM_LOT. Using %.5f lots.", initialLotSize); // Use %.5f for potentially small lots
   }
   else // DYNAMIC_MARGIN_CHECK (or any future modes defaulting to dynamic)
   {
       initialLotSize = NormalizeVolume(Lot_Size_1);
       PrintFormat("ExecuteTrade: Lot sizing mode set to DYNAMIC_MARGIN_CHECK. Attempting %.5f lots.", initialLotSize);
   }

   // Ensure initial lot size is not zero (can happen if volMin is zero or less and ALWAYS_MINIMUM_LOT is selected)
   if (initialLotSize <= 0)
   {
       Print("ExecuteTrade Error: Initial lot size is zero or less. Cannot trade.");
       return false;
   }
   
   // --- Margin Check --- 
   double marginRequired = 0;
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   string orderTypeStr = isBuy ? "Buy" : "Sell";
   double lotSize = initialLotSize; // Use the lot determined by the mode
   
   if(!OrderCalcMargin(isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, lotSize, entryPrice, marginRequired))
   {
       Print("ExecuteTrade Error: OrderCalcMargin failed for initial lot size. Error: ", GetLastError());
       return false; 
   }
   
   PrintFormat("ExecuteTrade: Checking margin for %s %.5f lots. Required: %.2f, Available Free: %.2f", 
               orderTypeStr, lotSize, marginRequired, freeMargin);
               
   if(marginRequired > freeMargin)
   {
      // Only attempt fallback to minimum lot if in DYNAMIC_MARGIN_CHECK mode
      if (LotSizing_Mode == DYNAMIC_MARGIN_CHECK)
       {
          PrintFormat("ExecuteTrade Warning: Insufficient margin (%.2f) for desired lot size (%.5f). Attempting minimum lot size (%.5f).",
                      freeMargin, lotSize, volMin);
          lotSize = volMin; // Attempt minimum lot size

          // Ensure minimum lot is not zero or less
          if (lotSize <= 0)
          {
              Print("ExecuteTrade Error: Minimum lot size (volMin) is zero or less. Cannot trade.");
              return false;
          }

          // Recalculate margin for minimum lot size
          if(!OrderCalcMargin(isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, lotSize, entryPrice, marginRequired))
          {
              Print("ExecuteTrade Error: OrderCalcMargin failed for minimum lot size. Error: ", GetLastError());
              return false; // Abort if calculation fails
          }

          PrintFormat("ExecuteTrade: Margin check for minimum lot %.5f. Required: %.2f, Available Free: %.2f",
                      lotSize, marginRequired, freeMargin);
       }
      // If not DYNAMIC_MARGIN_CHECK, and initial check failed, we just proceed to the final check below
      
      // Final check: is there enough margin for the current lotSize (either initial minimum or fallback minimum)?
      if(marginRequired > freeMargin)
      {   
          PrintFormat("ExecuteTrade Error: Insufficient margin (%.2f) even for %s lot size (%.5f). Required: %.2f. Aborting trade.",
                      freeMargin, (LotSizing_Mode == ALWAYS_MINIMUM_LOT ? "minimum" : "fallback minimum"), lotSize, marginRequired);
          return false; // Not enough margin 
      }
      
      // Log if we are proceeding with the minimum lot in dynamic mode
      if (LotSizing_Mode == DYNAMIC_MARGIN_CHECK && lotSize == volMin)
         Print("ExecuteTrade: Proceeding with minimum lot size: ", lotSize);
      // No extra print needed if ALWAYS_MINIMUM_LOT was successful initially
   }
   // --- End Margin Check ---
   
   // Prepare trade request
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lotSize;
   request.type = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   request.price = entryPrice;
   request.sl = stopLossPrice;
   request.tp = takeProfitPrice;
   request.deviation = 10;
   request.magic = magicNum;
   request.comment = "Strategy " + string(strategyNum) + " " + string(isBuy ? "Buy" : "Sell");
   
   // Check current spread and warn if high
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > Max_Spread) {
      Print("Warning: High spread (", spread, ") but proceeding with trade");
   }
   
   // Send trade order
   bool orderSent = OrderSend(request, result);
   
   if(!orderSent)
   {
      Print("OrderSend failed. Error code: ", GetLastError());
      return false;
   }
   
   if(result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED)
   {
      Print("Order executed successfully. Ticket: ", result.order);
      // Update last trade time for this strategy
      switch(strategyNum)
      {
         case 1: g_lastTradeTimeStrat1 = TimeCurrent(); break;
         case 2: g_lastTradeTimeStrat2 = TimeCurrent(); break;
         case 3: g_lastTradeTimeStrat3 = TimeCurrent(); break;
         case 4: g_lastTradeTimeStrat4 = TimeCurrent(); break;
         // Strategy 5 uses ExecuteTradeStrategy5
      }
      
      // Start monitoring for breakeven
      if(BreakevenTriggerPips > 0)
      {
         // Create a timer to check for breakeven conditions
         EventSetTimer(1); // Check every second
      }
      
      return true;
   }
   else
   {
      Print("Order execution failed. Retcode: ", result.retcode);
      return false;
   }
}
//+------------------------------------------------------------------+
//| Normalize volume according to symbol constraints                 |
//+------------------------------------------------------------------+
double NormalizeVolume(double desiredVolume)
{
   // Ensure volume is within min/max limits
   desiredVolume = MathMax(volMin, desiredVolume);
   desiredVolume = MathMin(volMax, desiredVolume);
   
   // Adjust volume to the nearest valid step
   // Calculate how many steps fit into the volume
   double steps = MathRound((desiredVolume - volMin) / volStep);
   // Calculate the normalized volume
   double normalizedVolume = volMin + steps * volStep;
   
   // Final check to ensure it doesn't slightly exceed max due to floating point math
   normalizedVolume = MathMin(volMax, normalizedVolume);
   
   // Ensure it's not below min either
   normalizedVolume = MathMax(volMin, normalizedVolume);
   
   return normalizedVolume;
}

//+------------------------------------------------------------------+
//| Manage Trailing Stop for Strategy 5 Position                     |
//+------------------------------------------------------------------+
void ManageStrategy5Position()
{
   // Iterate through open positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         // Check if position belongs to this EA and Strategy 5
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_MAGIC) == MAGIC_STRAT_5)
         {
            long positionType = PositionGetInteger(POSITION_TYPE);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentSL = PositionGetDouble(POSITION_SL);
            double currentPrice = 0;
            double newSL = 0;
            bool isBuy = (positionType == POSITION_TYPE_BUY);
            
            double profitPips = 0;
            double minStopDistPoints = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
            double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            
            // Calculate current profit in pips
            if(isBuy)
            {
               currentPrice = bid; // Use Bid for Buy profit calculation
               profitPips = (currentPrice - openPrice) / _Point;
            }
            else // Sell
            {
               currentPrice = ask; // Use Ask for Sell profit calculation
               profitPips = (openPrice - currentPrice) / _Point;
            }
            
            // Check if trailing stop activation threshold is met
            if(profitPips < S5_Trail_Activation_Pips)
            {
               // Print("S5 Trail (Ticket: ", ticket, "): Activation not met (Profit: ", profitPips, " < ", S5_Trail_Activation_Pips, ")");
               continue; // Not enough profit to activate trailing
            }
            
            Print("S5 Trail (Ticket: ", ticket, "): Activation met (Profit: ", profitPips, " >= ", S5_Trail_Activation_Pips, ")");

            // Calculate potential new Stop Loss based on trail distance
            if(isBuy)
            {               
               newSL = currentPrice - S5_Trail_Pips * _Point;
               // Ensure SL is at least breakeven (open price)
               newSL = MathMax(newSL, openPrice);
               // Ensure new SL respects minimum stops distance from Bid
               newSL = MathMin(newSL, bid - minStopDistPoints);
            }
            else // Sell
            {               
               newSL = currentPrice + S5_Trail_Pips * _Point;
               // Ensure SL is at least breakeven (open price)
               newSL = MathMin(newSL, openPrice);
               // Ensure new SL respects minimum stops distance from Ask
               newSL = MathMax(newSL, ask + minStopDistPoints);
            }
            
            // Normalize the calculated new SL
            newSL = NormalizeDouble(newSL, _Digits);
            
            Print("S5 Trail (Ticket: ", ticket, "): Calculated New SL: ", newSL, " Current SL: ", currentSL);

            // Check if the new SL is better (further in profit direction) than the current SL
            bool shouldModify = false;
            if(isBuy && newSL > currentSL)
            {
               shouldModify = true;
            }
            else if(!isBuy && newSL < currentSL)
            {
               shouldModify = true;
            }
            
            if(shouldModify)
            {
               Print("S5 Trail (Ticket: ", ticket, "): Modifying SL from ", currentSL, " to ", newSL);
               // Modify the position
               MqlTradeRequest request = {};
               MqlTradeResult result = {};
               
               request.action = TRADE_ACTION_SLTP;
               request.position = ticket;
               request.sl = newSL;
               // request.tp = PositionGetDouble(POSITION_TP); // Keep original TP
               
               if(OrderSend(request, result))
               {
                  if(result.retcode == TRADE_RETCODE_DONE)
                  {
                     Print("S5 Trail (Ticket: ", ticket, "): Position SL modified successfully to ", newSL);
                  }
                  else
                  {                     
                     Print("S5 Trail (Ticket: ", ticket, "): Position modify failed. Retcode: ", result.retcode, " (", TradeRetcodeToString(result.retcode), ") Message: ", result.comment);
                  }
               }
               else
               {
                   Print("S5 Trail (Ticket: ", ticket, "): OrderSend failed for SL modification. Error: ", GetLastError());
               }
            }
            else
            {
               Print("S5 Trail (Ticket: ", ticket, "): New SL (", newSL, ") is not better than current SL (", currentSL, "). No modification needed.");
            }
            
            // Only manage one S5 position per tick to avoid overwhelming the server
            break; 
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate Average Body Size (Ending at startIndex)              |
//+------------------------------------------------------------------+
double CalculateAverageBody(int period, int startIndex)
{
   if(period <= 0)
   {
      Print("Error: Average Body Period must be positive.");
      return 0.0;
   }
   
   double sum = 0;
   int barsAvailable = Bars(_Symbol, PERIOD_CURRENT);
   // Ensure startIndex is valid and we have enough bars for the period
   if(startIndex < 0 || startIndex + period > barsAvailable)
   {
       Print("Error: Not enough bars available or invalid start index (", startIndex, ") for average body calculation of period ", period);
       return 0.0;
   }
   
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   
   // Copy 'period' bars ending at 'startIndex'
   // MQL5 CopyRates: from start_pos (most recent), count
   // To get bars ending *at* startIndex, we start copying from startIndex
   if(CopyRates(_Symbol, PERIOD_CURRENT, startIndex, period, rates) != period)
   {
       Print("Error copying rates for Average Body calculation. Error: ", GetLastError());
       // Return 0 or handle error appropriately
       return 0.0; 
   }

   // Sum the body sizes of the copied bars
   for(int i = 0; i < period; i++)
   {
      sum += MathAbs(rates[i].open - rates[i].close);
   }
   
   // Avoid division by zero if period somehow ended up invalid
   if(period == 0) return 0.0;
   
   return sum / period;
}

//+------------------------------------------------------------------+
//| Draw an arrow marker for detected engulfing patterns             |
//+------------------------------------------------------------------+
void DrawEngulfingMarker(int barIndex, bool isBullish)
{
   datetime barTime = iTime(_Symbol, PERIOD_CURRENT, barIndex);
   string objectName = "EngulfMarker_" + (string)barTime + "_" + (string)isBullish;
   
   double priceLevel = 0;
   int arrowCode = 0;
   color arrowColor = clrNONE;
   
   if(isBullish)
   {
      priceLevel = iLow(_Symbol, PERIOD_CURRENT, barIndex) - 2 * _Point * 10; // Place below low
      arrowCode = 233; // Up arrow
      arrowColor = clrDodgerBlue;
   }
   else // Bearish
   {
      priceLevel = iHigh(_Symbol, PERIOD_CURRENT, barIndex) + 2 * _Point * 10; // Place above high
      arrowCode = 234; // Down arrow
      arrowColor = clrRed;
   }
   
   // Delete existing object with the same name first, if any (prevents duplicates)
   ObjectDelete(0, objectName);

   // Create the arrow object
   if(!ObjectCreate(0, objectName, OBJ_ARROW, 0, barTime, priceLevel))
   {
      Print("Error creating engulfing marker object '", objectName, "': ", GetLastError());
      return;
   }
   
   // Set arrow properties
   ObjectSetInteger(0, objectName, OBJPROP_ARROWCODE, arrowCode);
   ObjectSetInteger(0, objectName, OBJPROP_COLOR, arrowColor);
   ObjectSetInteger(0, objectName, OBJPROP_WIDTH, 1);
}

//+------------------------------------------------------------------+
//| Delete all previously drawn S/R lines                            |
//+------------------------------------------------------------------+
void DeleteAllSRZoneLines() 
 {
   // Note: Individual lines are deleted during invalidation. 
   // This might be needed at DeInit or if a full redraw is required.
   // For now, keep it for potential use but it's not called every tick.
   ObjectsDeleteAll(0, "SRZone_");
 }

//+------------------------------------------------------------------+
//| Draws the top and bottom lines for an S/R Zone                 |
//+------------------------------------------------------------------+
void DrawSRZoneLines(SRZone &zone) 
 {
    // --- Line Properties --- 
   // Use the specific IDs stored in the zone struct
   string topObjectName = "SRZone_" + (string)zone.chartObjectID_Top;
   string bottomObjectName = "SRZone_" + (string)zone.chartObjectID_Bottom;
   color zoneColor = zone.isResistance ? clrRed : clrBlue; 
   int lineWidth = 1;
   
   datetime startTime = TimeCurrent() - PeriodSeconds() * 200; // Approx window start
   datetime endTime = TimeCurrent() + PeriodSeconds() * 50;   // Extend slightly into future
   
   // Delete previous lines if they exist (redundant if IDs are reused correctly, but safe)
   ObjectDelete(0, topObjectName);
   ObjectDelete(0, bottomObjectName);
   
   // Create Top Boundary Line
   if(!ObjectCreate(0, topObjectName, OBJ_HLINE, 0, 0, zone.topBoundary))
   {   
       Print("Error creating HLine object ", topObjectName, ": ", GetLastError());
       return;
   }
   ObjectSetInteger(0, topObjectName, OBJPROP_COLOR, zoneColor);
   ObjectSetInteger(0, topObjectName, OBJPROP_STYLE, STYLE_DOT); 
   ObjectSetInteger(0, topObjectName, OBJPROP_WIDTH, lineWidth);
   ObjectSetInteger(0, topObjectName, OBJPROP_BACK, true); 
   
   // Create Bottom Boundary Line
   if(!ObjectCreate(0, bottomObjectName, OBJ_HLINE, 0, 0, zone.bottomBoundary))
   {   
       Print("Error creating HLine object ", bottomObjectName, ": ", GetLastError());
       return;
   }
   ObjectSetInteger(0, bottomObjectName, OBJPROP_COLOR, zoneColor);
   ObjectSetInteger(0, bottomObjectName, OBJPROP_STYLE, STYLE_DOT); 
   ObjectSetInteger(0, bottomObjectName, OBJPROP_WIDTH, lineWidth);
   ObjectSetInteger(0, bottomObjectName, OBJPROP_BACK, true); 
   
   // Redraw chart
   ChartRedraw();
 }

//+------------------------------------------------------------------+
//| Checks if a zone exists based on defining close proximity       |
//+------------------------------------------------------------------+
bool ZoneExists(double definingClose, SRZone &existingZones[], int sensitivityPips) 
 {
     double sensitivityValue = sensitivityPips * _Point;
     for(int i = 0; i < ArraySize(existingZones); i++)
     {
         // Compare the potential new zone's defining close with existing zones' defining closes
         if(MathAbs(definingClose - existingZones[i].definingClose) < sensitivityValue)
         {   
             return true; // Found a zone within the sensitivity zone
          }
     }
     return false; // No close zone found
 }

//+------------------------------------------------------------------+
//| Update, Validate, and Draw S/R Zones (Based on Local Closes)     |
//+------------------------------------------------------------------+
void UpdateAndDrawValidSRZones() 
{
   Print("Updating S/R Zones...");
   
   // --- Parameters --- 
   int lookback = SR_Lookback;
   int sensitivityPips = SR_Sensitivity_Pips;
   double sensitivityValue = sensitivityPips * _Point;
   
   // --- Get Data --- 
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   // Need lookback + 1 for neighbor checks, +1 for invalidation check bar (index 1)
   int ratesNeeded = lookback + 2;
   if (CopyRates(_Symbol, PERIOD_CURRENT, 0, ratesNeeded, rates) < ratesNeeded)
   {   
       Print("UpdateAndDrawValidSRZones Error: Could not copy rates. Error: ", GetLastError());
       // Clear levels on error to avoid using stale data
       ArrayFree(g_activeSupportZones);
       ArrayFree(g_activeResistanceZones);
       g_nearestSupportZoneIndex = -1;
       g_nearestResistanceZoneIndex = -1;
       DeleteAllSRZoneLines(); 
       return;
   }
   
   // Get the close of the last completed bar for invalidation check
   double closeBar1 = rates[1].close;
   double closeBar2 = rates[2].close; // Also get close of bar 2 for recent break check
   
   // --- 1. Invalidate Zones Crossed by Previous Bar's Close --- 
   
   // Invalidate Resistance: Remove if close[1] closed ABOVE the zone's TOP boundary
   int activeResSize = ArraySize(g_activeResistanceZones);
   for(int i = activeResSize - 1; i >= 0; i--) // Iterate backwards when removing
   {
       // Add tolerance: Invalidate only if close is clearly ABOVE level + 1 point
       if(closeBar1 > g_activeResistanceZones[i].topBoundary + _Point)
       {  
           Print("S/R Zone Invalidation: Resistance Zone (", g_activeResistanceZones[i].bottomBoundary, "-", g_activeResistanceZones[i].topBoundary, ") invalidated by Bar 1 close (", closeBar1, ")");
           // Delete the specific chart objects for this zone before removing from array
           ObjectDelete(0, "SRZone_" + (string)g_activeResistanceZones[i].chartObjectID_Top);
           ObjectDelete(0, "SRZone_" + (string)g_activeResistanceZones[i].chartObjectID_Bottom);
           
           // Remove element efficiently (replace with last, then resize)
           if (i < activeResSize - 1)
           { 
               g_activeResistanceZones[i] = g_activeResistanceZones[activeResSize - 1];
           }
           ArrayResize(g_activeResistanceZones, activeResSize - 1);
           activeResSize--; // Update size immediately
       }
   }
   
   // Invalidate Support: Remove if close[1] closed BELOW the zone's BOTTOM boundary
   int activeSupSize = ArraySize(g_activeSupportZones);
   for(int i = activeSupSize - 1; i >= 0; i--)
   {
       // Add tolerance: Invalidate only if close is clearly BELOW level - 1 point
       if(closeBar1 < g_activeSupportZones[i].bottomBoundary - _Point)
       {  
           Print("S/R Zone Invalidation: Support Zone (", g_activeSupportZones[i].bottomBoundary, "-", g_activeSupportZones[i].topBoundary, ") invalidated by Bar 1 close (", closeBar1, ")");
           // Delete the specific chart objects for this zone
           ObjectDelete(0, "SRZone_" + (string)g_activeSupportZones[i].chartObjectID_Top);
           ObjectDelete(0, "SRZone_" + (string)g_activeSupportZones[i].chartObjectID_Bottom);
           
           if (i < activeSupSize - 1)
           { 
               g_activeSupportZones[i] = g_activeSupportZones[activeSupSize - 1];
           }
           ArrayResize(g_activeSupportZones, activeSupSize - 1);
           activeSupSize--;
       }
   }
   
   // --- 2. Find New Potential Zones using Local Closes --- 
   
   // Temporary arrays to hold the BAR INDEX (relative to 'rates' array) where potential zones are defined
   int potentialResIndices[]; 
   int potentialSupIndices[];
   int potentialResCount = 0;
   int potentialSupCount = 0;
   
   // Scan from index 1 up to lookback-1 to allow checking neighbours rates[i-1] and rates[i+1]
   for(int i = 1; i < lookback; i++)
   {      
      // Check for local high close (potential Resistance)
      if(rates[i].close > rates[i-1].close && rates[i].close > rates[i+1].close)
      {       
         // Store the index 'i'
         ArrayResize(potentialResIndices, potentialResCount + 1);
         potentialResIndices[potentialResCount] = i;
         potentialResCount++;
      }
      
      // Check for local low close (potential Support)
      if(rates[i].close < rates[i-1].close && rates[i].close < rates[i+1].close)
      {      
         // Store the index 'i'
         ArrayResize(potentialSupIndices, potentialSupCount + 1);
         potentialSupIndices[potentialSupCount] = i; 
         potentialSupCount++;
      }
   }
   
   // --- 3. Add New Valid Zones (checking sensitivity vs *existing* active zones AND recent breaks) --- 
   
   // Add potential Resistance zones if they aren't too close to existing *active* ones
   for(int idx = 0; idx < potentialResCount; idx++)
   {   
      int potentialIndex = potentialResIndices[idx]; // Index in 'rates' array
      // Ensure potentialIndex allows access to neighbours rates[potentialIndex +/- 1]
      if (potentialIndex < 1 || potentialIndex >= ratesNeeded -1) continue; 
      
      double potentialDefiningClose = rates[potentialIndex].close;

      bool exists = false;
      // Check sensitivity against existing ACTIVE zones
      for(int j=0; j<ArraySize(g_activeResistanceZones); j++)
      {
         if(MathAbs(potentialDefiningClose - g_activeResistanceZones[j].definingClose) < sensitivityValue)
         {   
             exists = true;
             break;
          }
      }
      if (exists) continue; // Skip if too close to an existing active zone
      
      // Check: Was this potential zone's TOP boundary broken clearly by close[1] or close[2]?
      bool brokenRecently = false;
      // Resistance Top Boundary = max(high[i-1], high[i], high[i+1])
      double potentialTopBoundary = MathMax(rates[potentialIndex+1].high, MathMax(rates[potentialIndex].high, rates[potentialIndex-1].high));
      if (closeBar1 > potentialTopBoundary + _Point || closeBar2 > potentialTopBoundary + _Point) 
      { 
          brokenRecently = true;
          PrintFormat("S/R Filtering: Potential Resistance (Close: %.5f, Top: %.5f) ignored - broken by close[1](%.5f) or close[2](%.5f).", 
                      potentialDefiningClose, potentialTopBoundary, closeBar1, closeBar2);
      }
       
      // Add only if it doesn't exist AND wasn't broken recently
      if(!brokenRecently) // 'exists' check already done with 'continue'
      {  
         // Create the SRZone object
         SRZone newZone;
         newZone.definingClose = potentialDefiningClose;
         newZone.bottomBoundary = potentialDefiningClose; // Resistance bottom = defining close
         newZone.topBoundary = potentialTopBoundary;      // Calculated above
         newZone.definingBodyLow = MathMin(rates[potentialIndex].open, rates[potentialIndex].close); // Store defining body low
         newZone.definingBodyHigh = MathMax(rates[potentialIndex].open, rates[potentialIndex].close); // Store defining body high
         newZone.isResistance = true;
         newZone.touchCount = 1; // Initial formation counts as the first touch
         // Generate unique IDs
         newZone.chartObjectID_Top = ChartID() + TimeCurrent() + StringToInteger(DoubleToString(newZone.topBoundary * 1e5)); 
         newZone.chartObjectID_Bottom = ChartID() + TimeCurrent() + StringToInteger(DoubleToString(newZone.bottomBoundary * 1e5)) + 1; 

         PrintFormat("S/R Detection: Adding new Resistance Zone (Index %d): Close=%.5f, Bottom=%.5f, Top=%.5f", 
                     potentialIndex, newZone.definingClose, newZone.bottomBoundary, newZone.topBoundary);
                     
         int curSize = ArraySize(g_activeResistanceZones);
         ArrayResize(g_activeResistanceZones, curSize + 1);
         g_activeResistanceZones[curSize] = newZone; // Add the struct object
      }
   }
   
   // Add potential Support zones if they aren't too close to existing *active* ones
   for(int idx = 0; idx < potentialSupCount; idx++)
   {   
      int potentialIndex = potentialSupIndices[idx]; // Index in 'rates' array
      // Ensure potentialIndex allows access to neighbours rates[potentialIndex +/- 1]
      if (potentialIndex < 1 || potentialIndex >= ratesNeeded -1) continue; 
      
      double potentialDefiningClose = rates[potentialIndex].close;

      bool exists = false;
      // Check sensitivity against existing ACTIVE zones
      for(int j=0; j<ArraySize(g_activeSupportZones); j++)
      {
         if(MathAbs(potentialDefiningClose - g_activeSupportZones[j].definingClose) < sensitivityValue)
         {   
             exists = true;
             break;
          }
      }
      if (exists) continue; // Skip if too close to an existing active zone
      
      // Check: Was this potential zone's BOTTOM boundary broken clearly by close[1] or close[2]?
      bool brokenRecently = false;
      // Support Bottom Boundary = min(low[i-1], low[i], low[i+1])
      double potentialBottomBoundary = MathMin(rates[potentialIndex+1].low, MathMin(rates[potentialIndex].low, rates[potentialIndex-1].low));
      if (closeBar1 < potentialBottomBoundary - _Point || closeBar2 < potentialBottomBoundary - _Point) 
      { 
          brokenRecently = true;
          PrintFormat("S/R Filtering: Potential Support (Close: %.5f, Bottom: %.5f) ignored - broken by close[1](%.5f) or close[2](%.5f).", 
                      potentialDefiningClose, potentialBottomBoundary, closeBar1, closeBar2);
      }
       
      // Add only if it doesn't exist AND wasn't broken recently
      if(!brokenRecently) // 'exists' check already done with 'continue'
      {  
         // Create the SRZone object
         SRZone newZone;
         newZone.definingClose = potentialDefiningClose;
         newZone.topBoundary = potentialDefiningClose;    // Support top = defining close
         newZone.bottomBoundary = potentialBottomBoundary; // Calculated above
         newZone.definingBodyLow = MathMin(rates[potentialIndex].open, rates[potentialIndex].close); // Store defining body low
         newZone.definingBodyHigh = MathMax(rates[potentialIndex].open, rates[potentialIndex].close); // Store defining body high
         newZone.isResistance = false;
         newZone.touchCount = 1; // Initial formation counts as the first touch
         // Generate unique IDs
         newZone.chartObjectID_Top = ChartID() + TimeCurrent() + StringToInteger(DoubleToString(newZone.topBoundary * 1e5));
         newZone.chartObjectID_Bottom = ChartID() + TimeCurrent() + StringToInteger(DoubleToString(newZone.bottomBoundary * 1e5)) + 1;

         PrintFormat("S/R Detection: Adding new Support Zone (Index %d): Close=%.5f, Bottom=%.5f, Top=%.5f", 
                     potentialIndex, newZone.definingClose, newZone.bottomBoundary, newZone.topBoundary);
                     
         int curSize = ArraySize(g_activeSupportZones);
         ArrayResize(g_activeSupportZones, curSize + 1);
         g_activeSupportZones[curSize] = newZone; // Add the struct object
      }
   }
   
   // Sort the active zones (optional, but helps finding nearest)
   // NOTE: ArraySort might not work directly on arrays of structs unless a comparison function is provided.
   // Remove sorting for now to avoid potential issues.
   // ArraySort(g_activeResistanceZones);
   // ArraySort(g_activeSupportZones);
   
   // --- 4. Detect Touches on Active Zones (Using Bar 1 & Bar 2) --- // MODIFIED
   double touchSensitivityValue = (double)SR_Sensitivity_Pips * _Point; // Sensitivity for touch detection

   // Check Resistance Zones for touches
   activeResSize = ArraySize(g_activeResistanceZones); // Get current size again
   for(int i = 0; i < activeResSize; i++)
   { 
      // Check if bar 1 high approached the top boundary
      if(MathAbs(rates[1].high - g_activeResistanceZones[i].topBoundary) <= touchSensitivityValue)
      {
         // Check if bar 1 close did NOT break the top boundary
         // AND check if bar 2 close was ALSO below the top boundary (ensuring separation)
         if(rates[1].close < g_activeResistanceZones[i].topBoundary + _Point &&
            rates[2].close < g_activeResistanceZones[i].topBoundary + _Point) // <<< ADDED CHECK FOR BAR 2
         {
            g_activeResistanceZones[i].touchCount++;
            PrintFormat("S/R Touch: Resistance Zone (Index %d, DefC=%.5f, Top=%.5f) touched by Bar 1 High (%.5f) with Bar 2 Sep. New Count: %d", 
                        i, g_activeResistanceZones[i].definingClose, g_activeResistanceZones[i].topBoundary, rates[1].high, g_activeResistanceZones[i].touchCount);
         }
      }
   }

   // Check Support Zones for touches
   activeSupSize = ArraySize(g_activeSupportZones); // Get current size again
   for(int i = 0; i < activeSupSize; i++)
   {
      // Check if bar 1 low approached the bottom boundary
      if(MathAbs(rates[1].low - g_activeSupportZones[i].bottomBoundary) <= touchSensitivityValue)
      {
         // Check if bar 1 close did NOT break the bottom boundary
         // AND check if bar 2 close was ALSO above the bottom boundary (ensuring separation)
         if(rates[1].close > g_activeSupportZones[i].bottomBoundary - _Point &&
            rates[2].close > g_activeSupportZones[i].bottomBoundary - _Point) // <<< ADDED CHECK FOR BAR 2
         {
            g_activeSupportZones[i].touchCount++;
            PrintFormat("S/R Touch: Support Zone (Index %d, DefC=%.5f, Bottom=%.5f) touched by Bar 1 Low (%.5f) with Bar 2 Sep. New Count: %d", 
                        i, g_activeSupportZones[i].definingClose, g_activeSupportZones[i].bottomBoundary, rates[1].low, g_activeSupportZones[i].touchCount);
         }
      }
   }
   
   // --- 5. Clear Old Lines and Draw Current Valid Zones --- 
   // DeleteAllSRZoneLines(); // <<< Lines are deleted during invalidation or filtering now
   // Redraw ALL active zones first before filtering
   for(int i = 0; i < ArraySize(g_activeResistanceZones); i++) DrawSRZoneLines(g_activeResistanceZones[i]); 
   for(int i = 0; i < ArraySize(g_activeSupportZones); i++) DrawSRZoneLines(g_activeSupportZones[i]); 
   
   // --- 6. Filter Zones to Keep All Valid Zones (No Limit) --- 
   double currentPrice = rates[0].close; // Current bar's close
   if (currentPrice == 0) 
   { 
       Print("UpdateAndDrawValidSRZones Warning: Could not get current price (bar 0 close) for filtering.");
       // Skip filtering if price is invalid, but proceed to find nearest from unfiltered list
   }
   else
   {
       // --- Filter Resistance Zones (Keep all valid zones above current price) ---
       SRZone tempResistanceZones[];
       double tempResistanceDistances[];
       int tempResCount = 0;

       // Collect valid resistance zones above current price and their distances
       for (int i = 0; i < ArraySize(g_activeResistanceZones); i++)
       {
           if (g_activeResistanceZones[i].topBoundary > currentPrice)
           {
               ArrayResize(tempResistanceZones, tempResCount + 1);
               ArrayResize(tempResistanceDistances, tempResCount + 1);
               tempResistanceZones[tempResCount] = g_activeResistanceZones[i];
               tempResistanceDistances[tempResCount] = g_activeResistanceZones[i].topBoundary - currentPrice; // Distance to top boundary
               tempResCount++;
           }
       }

       // Sort collected zones by distance (simple bubble sort for small array)
       for (int i = 0; i < tempResCount - 1; i++)
       {
           for (int j = 0; j < tempResCount - i - 1; j++)
           {
               if (tempResistanceDistances[j] > tempResistanceDistances[j + 1])
               {
                   // Swap distances
                   double tempDist = tempResistanceDistances[j];
                   tempResistanceDistances[j] = tempResistanceDistances[j + 1];
                   tempResistanceDistances[j + 1] = tempDist;
                   // Swap zones
                   SRZone tempZone = tempResistanceZones[j];
                   tempResistanceZones[j] = tempResistanceZones[j + 1];
                   tempResistanceZones[j + 1] = tempZone;
               }
           }
       }

       // Keep all zones - no filtering by count
       SRZone finalResistanceZones[];
       int finalResCount = tempResCount;
       ArrayResize(finalResistanceZones, finalResCount);

       // Copy all zones to the final array
       for (int i = 0; i < finalResCount; i++)
       {
           finalResistanceZones[i] = tempResistanceZones[i];
           PrintFormat("S/R: Keeping Resistance Zone (Dist: %.5f, Top: %.5f)", tempResistanceDistances[i], finalResistanceZones[i].topBoundary);
       }
       
       // Remove chart objects for zones NOT kept
       for (int i = 0; i < ArraySize(g_activeResistanceZones); i++)
       {
           bool found = false;
           for (int k = 0; k < finalResCount; k++)
           {
               if (g_activeResistanceZones[i].chartObjectID_Top == finalResistanceZones[k].chartObjectID_Top)
               {
                   found = true;
                   break;
               }
           }
           if (!found)
           {
               PrintFormat("S/R Filtering: Removing Resistance Zone (Top: %.5f)", g_activeResistanceZones[i].topBoundary);
               ObjectDelete(0, "SRZone_" + (string)g_activeResistanceZones[i].chartObjectID_Top);
               ObjectDelete(0, "SRZone_" + (string)g_activeResistanceZones[i].chartObjectID_Bottom);
           }
       }
       
       // Update the global array
       ArrayFree(g_activeResistanceZones);
       if(ArraySize(finalResistanceZones) > 0)
       {
           ArrayResize(g_activeResistanceZones, ArraySize(finalResistanceZones));
           for(int i = 0; i < ArraySize(finalResistanceZones); i++)
           {
               g_activeResistanceZones[i] = finalResistanceZones[i];
           }
       }

       // --- Filter Support Zones (Keep all valid zones below current price) ---
       SRZone tempSupportZones[];
       double tempSupportDistances[];
       int tempSupCount = 0;

       // Collect valid support zones below current price and their distances
       for (int i = 0; i < ArraySize(g_activeSupportZones); i++)
       {
           if (g_activeSupportZones[i].bottomBoundary < currentPrice)
           {
               ArrayResize(tempSupportZones, tempSupCount + 1);
               ArrayResize(tempSupportDistances, tempSupCount + 1);
               tempSupportZones[tempSupCount] = g_activeSupportZones[i];
               tempSupportDistances[tempSupCount] = currentPrice - g_activeSupportZones[i].bottomBoundary; // Distance to bottom boundary
               tempSupCount++;
           }
       }

       // Sort collected zones by distance (simple bubble sort)
       for (int i = 0; i < tempSupCount - 1; i++)
       {
           for (int j = 0; j < tempSupCount - i - 1; j++)
           {
               if (tempSupportDistances[j] > tempSupportDistances[j + 1])
               {
                   // Swap distances
                   double tempDist = tempSupportDistances[j];
                   tempSupportDistances[j] = tempSupportDistances[j + 1];
                   tempSupportDistances[j + 1] = tempDist;
                   // Swap zones
                   SRZone tempZone = tempSupportZones[j];
                   tempSupportZones[j] = tempSupportZones[j + 1];
                   tempSupportZones[j + 1] = tempZone;
               }
           }
       }

       // Keep all zones - no filtering by count
       SRZone finalSupportZones[];
       int finalSupCount = tempSupCount;
       ArrayResize(finalSupportZones, finalSupCount);

       // Copy all zones to the final array
       for (int i = 0; i < finalSupCount; i++)
       {
           finalSupportZones[i] = tempSupportZones[i];
           PrintFormat("S/R: Keeping Support Zone (Dist: %.5f, Bottom: %.5f)", tempSupportDistances[i], finalSupportZones[i].bottomBoundary);
       }

       // Remove chart objects for zones NOT kept
       for (int i = 0; i < ArraySize(g_activeSupportZones); i++)
       {
           bool found = false;
           for (int k = 0; k < finalSupCount; k++)
           {
               if (g_activeSupportZones[i].chartObjectID_Bottom == finalSupportZones[k].chartObjectID_Bottom)
               {
                   found = true;
                   break;
               }
           }
           if (!found)
           {
               PrintFormat("S/R Filtering: Removing Support Zone (Bottom: %.5f)", g_activeSupportZones[i].bottomBoundary);
               ObjectDelete(0, "SRZone_" + (string)g_activeSupportZones[i].chartObjectID_Top);
               ObjectDelete(0, "SRZone_" + (string)g_activeSupportZones[i].chartObjectID_Bottom);
           }
       }

       // Update the global array
       ArrayFree(g_activeSupportZones);
       if(ArraySize(finalSupportZones) > 0)
       {
           ArrayResize(g_activeSupportZones, ArraySize(finalSupportZones));
           for(int i = 0; i < ArraySize(finalSupportZones); i++)
           {
               g_activeSupportZones[i] = finalSupportZones[i];
           }
       }
   } // End of filtering block (if currentPrice is valid)
   
   // --- 7. Find and Store Nearest Valid S/R Zone Index to Current Price (from FILTERED list) --- // RENUMBERED STEP
   g_nearestSupportZoneIndex = -1;
   g_nearestResistanceZoneIndex = -1;
   
   // Find nearest support zone index (highest bottom boundary BELOW current price)
   double maxSupportBottomBelowPrice = 0.0;
   int bestSupportIndex = -1;
   for(int i = 0; i < ArraySize(g_activeSupportZones); i++)
   {   
       // Check zone's bottom boundary relative to current price
       if(g_activeSupportZones[i].bottomBoundary < currentPrice)
       {   
           if(g_activeSupportZones[i].bottomBoundary > maxSupportBottomBelowPrice)
           {   
               maxSupportBottomBelowPrice = g_activeSupportZones[i].bottomBoundary;
               bestSupportIndex = i;
           }
       }
   }
   g_nearestSupportZoneIndex = bestSupportIndex;
   
   // Find nearest resistance zone index (lowest top boundary ABOVE current price)
   double minResistanceTopAbovePrice = 0.0;
   int bestResistanceIndex = -1;
   for(int i = 0; i < ArraySize(g_activeResistanceZones); i++)
   {   
       // Check zone's top boundary relative to current price
       if(g_activeResistanceZones[i].topBoundary > currentPrice)
       {   
           if(bestResistanceIndex == -1 || g_activeResistanceZones[i].topBoundary < minResistanceTopAbovePrice)
           {   
               minResistanceTopAbovePrice = g_activeResistanceZones[i].topBoundary;
               bestResistanceIndex = i;
           }
       }
   }
   g_nearestResistanceZoneIndex = bestResistanceIndex;
   
   Print("S/R Zone Update Complete. Active Support Zones: ", ArraySize(g_activeSupportZones), " Active Resistance Zones: ", ArraySize(g_activeResistanceZones));
   Print("  -> Nearest Support Index: ", g_nearestSupportZoneIndex, " (Bottom: ", (g_nearestSupportZoneIndex != -1 ? DoubleToString(g_activeSupportZones[g_nearestSupportZoneIndex].bottomBoundary, _Digits) : "N/A"), ")");
   Print("  -> Nearest Resistance Index: ", g_nearestResistanceZoneIndex, " (Top: ", (g_nearestResistanceZoneIndex != -1 ? DoubleToString(g_activeResistanceZones[g_nearestResistanceZoneIndex].topBoundary, _Digits) : "N/A"), ")");
}

//+------------------------------------------------------------------+
//| Check if a specific strategy is on cooldown                      |
//+------------------------------------------------------------------+
bool IsStrategyOnCooldown(int strategyNum, ulong magicNum)
{
   // 1. Check for Existing Open Position by this Strategy
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionSelectByTicket(PositionGetTicket(i)))
      {
         // Check symbol and magic number
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_MAGIC) == magicNum)
         {
             PrintFormat("Strategy %d skipped: Open position with magic %d already exists.", strategyNum, magicNum);
             return true; // Strategy has an open position
         }
      }
   }

   // 2. Check Time-Based Cooldown
   datetime lastTradeTime = 0;
   switch(strategyNum)
   {
      case 1: lastTradeTime = g_lastTradeTimeStrat1; break;
      case 2: lastTradeTime = g_lastTradeTimeStrat2; break;
      case 3: lastTradeTime = g_lastTradeTimeStrat3; break;
      case 4: lastTradeTime = g_lastTradeTimeStrat4; break;
      case 5: lastTradeTime = g_lastTradeTimeStrat5; break;
      default: return false; // Invalid strategy number
   }

   if (lastTradeTime == 0) return false; // No previous trade recorded

   long timeSinceLastTrade = TimeCurrent() - lastTradeTime;
   long cooldownSeconds = Strategy_Cooldown_Minutes * 60;

   if (timeSinceLastTrade < cooldownSeconds)
   {
       PrintFormat("Strategy %d skipped: On time cooldown. Time since last trade: %d seconds (< %d seconds).", 
                   strategyNum, timeSinceLastTrade, cooldownSeconds);
       return true; // Within cooldown period
   }

   return false; // Not on cooldown
}

//+------------------------------------------------------------------+
//| Timer function to check for breakeven conditions                 |
//+------------------------------------------------------------------+
void OnTimer()
{
   // Iterate through all open positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         // Check if position belongs to this EA
         if(PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            long positionType = PositionGetInteger(POSITION_TYPE);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentSL = PositionGetDouble(POSITION_SL);
            double currentPrice = 0;
            double profitPips = 0;
            
            // Calculate current profit in pips
            if(positionType == POSITION_TYPE_BUY)
            {
               currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
               profitPips = (currentPrice - openPrice) / _Point;
            }
            else // SELL
            {
               currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
               profitPips = (openPrice - currentPrice) / _Point;
            }
            
            // Check if profit has reached breakeven trigger level
            if(profitPips >= BreakevenTriggerPips)
            {
               // Calculate new breakeven SL with buffer
               double newSL = 0;
               if(positionType == POSITION_TYPE_BUY)
               {
                  newSL = openPrice + (BreakevenBufferPips * _Point);
               }
               else // SELL
               {
                  newSL = openPrice - (BreakevenBufferPips * _Point);
               }
               
               // Only modify if new SL is better than current SL
               bool shouldModify = false;
               if(positionType == POSITION_TYPE_BUY && newSL > currentSL)
               {
                  shouldModify = true;
               }
               else if(positionType == POSITION_TYPE_SELL && (currentSL == 0 || newSL < currentSL))
               {
                  shouldModify = true;
               }
               
               if(shouldModify)
               {
                  // Modify the position
                  MqlTradeRequest request = {};
                  MqlTradeResult result = {};
                  
                  request.action = TRADE_ACTION_SLTP;
                  request.position = ticket;
                  request.sl = newSL;
                  request.tp = PositionGetDouble(POSITION_TP); // Keep original TP
                  
                  if(OrderSend(request, result))
                  {
                     if(result.retcode == TRADE_RETCODE_DONE)
                     {
                        Print("Breakeven SL set successfully for position ", ticket, ". New SL: ", newSL);
                     }
                     else
                     {
                        Print("Failed to set breakeven SL. Retcode: ", result.retcode);
                     }
                  }
                  else
                  {
                     Print("OrderSend failed for breakeven SL. Error: ", GetLastError());
                  }
               }
            }
         }
      }
   }
}
