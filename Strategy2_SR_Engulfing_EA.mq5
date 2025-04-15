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
input bool        Use_Breakeven_Logic = true; // Enable/Disable automatic breakeven adjustment
// Trend Filter Parameters
input int         Trend_Confirmation_Periods = 2; // Default periods needed to confirm trend change
input bool        Debug_Mode = false;         // Enable detailed debug logging

#include "include/CommonPatternDetection.mqh"
#include "include/Support_Resistance_Zones.mqh"

// Global Variables
long barCount;
double volMin, volMax, volStep;
datetime g_lastTradeTime = 0;

// Trend Filter Handles & Buffers
double ADX_Threshold = 25;  // ADX threshold for trend strength
double multiplier = 0.5;  // Multiplier for ADX threshold based on volatility
int trendFastEmaHandle;
int trendSlowEmaHandle;
int trendAdxHandle;
int atrHandle;  // ATR indicator handle
double trendFastEmaValues[];
double trendSlowEmaValues[];
double trendAdxValues[];
double atrValues[];  // ATR values buffer
int Dynamic_Trend_Confirmation_Periods; // Dynamic confirmation periods based on instrument

// Constants
#define STRATEGY_COOLDOWN_MINUTES 60
#define SHIFT_TO_CHECK 1  // Candlestick shift to check for patterns

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   // At the beginning of your OnInit() function
if(_Symbol == "Volatility 75 Index")
{
   ADX_Threshold = 35.0;
   Dynamic_Trend_Confirmation_Periods = 3; // Higher confirmation for more volatile instrument
}
else if(_Symbol == "Volatility 25 Index")
{
   ADX_Threshold = 23.0;
   Dynamic_Trend_Confirmation_Periods = 2; // Default confirmation periods
}
else if(_Symbol == "Volatility 25 Index (1s)")
{
   ADX_Threshold = 21.0;
   Dynamic_Trend_Confirmation_Periods = 3; // Higher confirmation for 1-second timeframe
}
else if(_Symbol == "Volatility 50 Index")
{
   ADX_Threshold = 25.0;
   Dynamic_Trend_Confirmation_Periods = 2; // Default confirmation periods
}
else if(_Symbol == "Volatility 10 Index")
{
   ADX_Threshold = 22.0;
   Dynamic_Trend_Confirmation_Periods = 2; // Default confirmation periods
}
else if(_Symbol == "XAUUSD") // Gold
{
   ADX_Threshold = 24.0;
   Dynamic_Trend_Confirmation_Periods = 2; // Default confirmation periods
}
else
{
   // For any other instrument, use the input parameter value
   Dynamic_Trend_Confirmation_Periods = Trend_Confirmation_Periods;
}

Print("OnInit: Symbol=", _Symbol, ", ADX Threshold=", ADX_Threshold, 
      ", Trend Confirmation Periods=", Dynamic_Trend_Confirmation_Periods);
Print("OnInit: Starting initialization...");

// Create ATR indicator handle
atrHandle = iATR(_Symbol, PERIOD_CURRENT, 14);
if(atrHandle == INVALID_HANDLE)
{
    Print("OnInit: Failed to create ATR indicator handle");
    return INIT_FAILED;
}

// Wait for the indicator to calculate values
bool atrValuesReady = false;
for(int attempt = 0; attempt < 10; attempt++)
{
    // Try to copy ATR values
    ArrayResize(atrValues, 1);
    if(CopyBuffer(atrHandle, 0, 0, 1, atrValues) == 1)
    {
        // Successfully copied ATR values
        double atr = atrValues[0];
        
        // Only use dynamic threshold if it's valid
        if(atr > 0)
        {
            double dynamicThreshold = MathMin(20.0 + (atr * multiplier), 40.0);
            ADX_Threshold = dynamicThreshold;
            atrValuesReady = true;
            Print("OnInit: Dynamic ADX threshold calculated: ", ADX_Threshold);
        }
        
        break; // Exit the loop if successful
    }
    
    // If we couldn't copy values, wait a bit and try again
    Sleep(100);
}

// Even if we couldn't get ATR values, continue with the symbol-specific thresholds
Print("OnInit: Symbol=", _Symbol, ", ADX Threshold=", ADX_Threshold, 
      ", ATR values ready: ", (atrValuesReady ? "Yes" : "No"));
    
    // Request sufficient historical data first
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    int copied = CopyRates(_Symbol, PERIOD_CURRENT, 0, 100, rates);  // Request 100 bars
    
    if(copied < 20)
    {
        Print("OnInit: Failed to get enough historical data. Bars copied: ", copied);
        return INIT_FAILED;
    }
   
   // Check if automated trading is allowed
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   {
      Print("OnInit: Automated trading is not allowed. Please enable it in MetaTrader 5.");
      return INIT_FAILED;  // Changed from return(INIT_FAILED)
   }
   
   // Check if trading is allowed for the symbol
   if(!SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_FULL)
   {
      Print("Trading is not allowed for ", _Symbol);
      return INIT_FAILED;  // Changed from return(INIT_FAILED)
   }
   
   // Get symbol volume constraints
   volMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   volMax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   volStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   if(volMin <= 0 || volMax <= 0 || volStep <= 0)
   {
      Print("Failed to get valid volume constraints for ", _Symbol);
      return INIT_FAILED;  // Changed from return(INIT_FAILED)
   }
   
   // Initialize EMA indicator
   Print("OnInit: Initializing EMA indicator...");
   if(!InitializeEMA())
   {
      Print("OnInit: Failed to initialize EMA indicator");
      return INIT_FAILED;  // Changed from return(INIT_FAILED)
   }
   
   // Initialize barCount
   barCount = Bars(_Symbol, PERIOD_CURRENT);
   Print("OnInit: Initial bar count is ", barCount);
   
   // Clear any existing S/R lines at startup
   DeleteAllSRZoneLines();
   
   // Initialize trend filter indicators
   if(Use_Trend_Filter)
   {
      Print("OnInit: Initializing trend filter indicators...");
      
      Print("OnInit: Creating Fast EMA indicator...");
      trendFastEmaHandle = iMA(_Symbol, PERIOD_CURRENT, 20, 0, MODE_EMA, PRICE_CLOSE);
      
      Print("OnInit: Creating Slow EMA indicator...");
      trendSlowEmaHandle = iMA(_Symbol, PERIOD_CURRENT, 50, 0, MODE_EMA, PRICE_CLOSE);
      
      Print("OnInit: Creating ADX indicator...");
      trendAdxHandle = iADX(_Symbol, PERIOD_CURRENT, 14);
      
      if(trendFastEmaHandle == INVALID_HANDLE || 
         trendSlowEmaHandle == INVALID_HANDLE || 
         trendAdxHandle == INVALID_HANDLE)
      {
         Print("OnInit: Failed to create trend filter indicators. Handles: Fast EMA=", trendFastEmaHandle,
               ", Slow EMA=", trendSlowEmaHandle, ", ADX=", trendAdxHandle);
         return INIT_FAILED;  // Changed from return(INIT_FAILED)
      }
      
      Print("OnInit: Successfully created trend filter indicators");
      
      // Initialize static variables for trend state tracking
      if(Debug_Mode)
         Print("OnInit: Initializing trend state tracking variables");
   }

   // Set up timer for breakeven management if enabled
if(Use_Breakeven_Logic)
{
    EventSetTimer(60); // Check every minute
}

   return INIT_SUCCEEDED;  // Changed from return(INIT_SUCCEEDED)
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{   
   Print("OnDeinit: Starting cleanup with reason code ", reason);
   
   // Release EMA indicator
   Print("OnDeinit: Releasing EMA indicator...");
   ReleaseEMA();
   
   // Release trend indicators only if they were created
   if(Use_Trend_Filter)
   {
      Print("OnDeinit: Releasing trend filter indicators...");
      if(trendFastEmaHandle != INVALID_HANDLE)
      {
         IndicatorRelease(trendFastEmaHandle);
         trendFastEmaHandle = INVALID_HANDLE;
      }
      if(trendSlowEmaHandle != INVALID_HANDLE)
      {
         IndicatorRelease(trendSlowEmaHandle);
         trendSlowEmaHandle = INVALID_HANDLE;
      }
      if(trendAdxHandle != INVALID_HANDLE)
      {
         IndicatorRelease(trendAdxHandle);
         trendAdxHandle = INVALID_HANDLE;
      }
   }

   // In OnDeinit()
if(atrHandle != INVALID_HANDLE)
{
    IndicatorRelease(atrHandle);
    atrHandle = INVALID_HANDLE;
}
   
   Print("OnDeinit: Cleaning up S/R zone lines...");
   DeleteAllSRZoneLines();
   
   Print("OnDeinit: Killing timer...");
   EventKillTimer();
   
   Print("OnDeinit: Cleanup complete");
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
    int currentBars = Bars(_Symbol, PERIOD_CURRENT);
    if (currentBars == barCount) return;
    barCount = currentBars;

    if (!UpdateIndicators()) return;
    double currentEMA = g_ema.values[0];

    // Update and draw support/resistance zones
    UpdateAndDrawValidSRZones(SR_Lookback, SR_Sensitivity_Pips, currentEMA);

    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    int available = CopyRates(_Symbol, PERIOD_CURRENT, 0, SR_Lookback, rates);

    if (available > 0)
    {
        // Check for engulfing patterns and execute trades using the new function
        CheckForEngulfingAndTrade(rates, SR_Sensitivity_Pips * _Point);
    }

    // Log the current state of zones
    LogZoneState();
}
//+------------------------------------------------------------------+
//| Update indicator values                                           |
//+------------------------------------------------------------------+
bool UpdateIndicators()
{
   Print("UpdateIndicators: Starting update...");
   
   // Update EMA and draw it
   int barsNeeded = SHIFT_TO_CHECK + 4;
   Print("UpdateIndicators: Requesting ", barsNeeded, " bars for EMA");
   
   if(!UpdateEMAValues(barsNeeded))
   {
      Print("UpdateIndicators: Failed to update EMA values");
      return false;
   }
   
   Print("UpdateIndicators: Drawing EMA line");
   DrawEMALine();
   
   // Update ATR values
   if(atrHandle != INVALID_HANDLE)
   {
      ArrayResize(atrValues, 1);
      if(CopyBuffer(atrHandle, 0, 0, 1, atrValues) == 1)
      {
         double atr = atrValues[0];
         if(atr > 0)
         {
            double dynamicThreshold = MathMin(20.0 + (atr * multiplier), 40.0);
            ADX_Threshold = dynamicThreshold;
            
            if(Debug_Mode)
               Print("UpdateIndicators: Updated ADX threshold to ", ADX_Threshold, " based on ATR ", atr);
         }
         else
         {
            if(Debug_Mode)
               Print("UpdateIndicators: ATR value is zero or negative: ", atr);
         }
      }
      else
      {
         if(Debug_Mode)
            Print("UpdateIndicators: Failed to copy ATR values");
      }
   }
   
   if(Use_Trend_Filter)
   {
      if(Debug_Mode)
         Print("UpdateIndicators: Updating trend filter indicators");
      
      // Initialize trend filter arrays with proper size
      int requiredBars = SHIFT_TO_CHECK + 4;
      if(Debug_Mode)
         Print("UpdateIndicators: Resizing trend arrays for ", requiredBars, " bars");
      
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
//| Execute trade                                                     |
//+------------------------------------------------------------------+
void ExecuteTrade(bool isBuy, double price, double stopLoss = 0, double takeProfit = 0)
{
    // Get appropriate lot size based on account balance and risk management
    double lotSize = GetLotSize();
    if (lotSize <= 0)
    {
        Print("ExecuteTrade: Invalid lot size. Trade aborted.");
        return;
    }
    
    // If stopLoss and takeProfit weren't provided, use default values
    if (stopLoss == 0)
    {
        stopLoss = isBuy ? price - 50 * _Point : price + 50 * _Point;
    }
    
    if (takeProfit == 0)
    {
        takeProfit = isBuy ? price + 100 * _Point : price - 100 * _Point;
    }

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
    request.comment = "Engulfing Trade";

    PrintFormat("ExecuteTrade: Sending %s order. Price=%.5f, SL=%.5f, TP=%.5f, Lot=%.2f", 
                isBuy ? "Buy" : "Sell", request.price, stopLoss, takeProfit, lotSize);

    if (!OrderSend(request, result))
    {
        Print("ExecuteTrade: OrderSend failed. Error: ", GetLastError());
        return;
    }

    if (result.retcode == TRADE_RETCODE_DONE)
    {
        Print("ExecuteTrade: Trade executed successfully. Ticket: ", result.order);
        g_lastTradeTime = TimeCurrent(); // Update last trade time
    }
    else
    {
        Print("ExecuteTrade: Trade failed. Retcode: ", result.retcode);
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
   static int lastTrendState = TREND_RANGING;  // Remember last trend state for confirmation
   static int confirmationCount = 0;           // Counter for trend confirmation
   
   // Skip detailed logging unless in debug mode
   if(Debug_Mode)
      Print("GetTrendState: Checking trend state...");
   
   if(!Use_Trend_Filter)
   {
      if(Debug_Mode)
         Print("GetTrendState: Trend filter disabled, returning RANGING");
      return TREND_RANGING;
   }
   
   int fastSize = ArraySize(trendFastEmaValues);
   int slowSize = ArraySize(trendSlowEmaValues);
   int adxSize = ArraySize(trendAdxValues);
   
   if(Debug_Mode)
      Print("GetTrendState: Array sizes - Fast EMA: ", fastSize,
            ", Slow EMA: ", slowSize, ", ADX: ", adxSize);
   
   // Ensure we have enough data
   if(fastSize < 2 || slowSize < 2 || adxSize < 2)
   {
      Print("GetTrendState: Insufficient indicator data, returning RANGING");
      return TREND_RANGING;
   }
   
   // Get current and previous values
   double fastEMA = trendFastEmaValues[0];
   double slowEMA = trendSlowEmaValues[0];
   double adxValue = trendAdxValues[0];
   
   double prevFastEMA = trendFastEmaValues[1];
   double prevSlowEMA = trendSlowEmaValues[1];
   
   // Determine current trend conditions
   bool isStrong = (adxValue > ADX_Threshold);
   bool isBullish = (fastEMA > slowEMA);
   
   // Check for crossover (change in trend direction)
   bool isCrossover = (prevFastEMA <= prevSlowEMA && fastEMA > slowEMA) ||  // Bullish crossover
                      (prevFastEMA >= prevSlowEMA && fastEMA < slowEMA);     // Bearish crossover
   
   if(Debug_Mode)
      Print("GetTrendState: Values - Fast EMA: ", fastEMA,
            ", Slow EMA: ", slowEMA, ", ADX: ", adxValue,
            " (Strong: ", isStrong, ", Bullish: ", isBullish, 
            ", Crossover: ", isCrossover, ")");
   
   // Determine current trend state
   int currentTrendState;
   
   if(isStrong && isBullish)
      currentTrendState = TREND_BULLISH;
   else if(isStrong && !isBullish)
      currentTrendState = TREND_BEARISH;
   else
      currentTrendState = TREND_RANGING;
   
   // Handle trend confirmation logic
   if(currentTrendState != lastTrendState)
   {
      // Potential new trend detected
      if(confirmationCount < Dynamic_Trend_Confirmation_Periods) // Use dynamic periods instead of input parameter
      {
         // Not yet confirmed, increment counter
         confirmationCount++;
         
         if(Debug_Mode)
            PrintFormat("GetTrendState: Potential trend change to %s detected. Confirmation: %d/%d", 
                      currentTrendState == TREND_BULLISH ? "BULLISH" : 
                      currentTrendState == TREND_BEARISH ? "BEARISH" : "RANGING",
                      confirmationCount, Dynamic_Trend_Confirmation_Periods);
         
         // Return the last confirmed trend until we have enough confirmation
         return lastTrendState;
      }
      else
      {
         // New trend confirmed
         Print("GetTrendState: Trend changed from ", 
               lastTrendState == TREND_BULLISH ? "BULLISH" : 
               lastTrendState == TREND_BEARISH ? "BEARISH" : "RANGING",
               " to ",
               currentTrendState == TREND_BULLISH ? "BULLISH" : 
               currentTrendState == TREND_BEARISH ? "BEARISH" : "RANGING");
         
         lastTrendState = currentTrendState;
         confirmationCount = 0;
         return currentTrendState;
      }
   }
   else
   {
      // Same trend continues
      confirmationCount = 0;
      
      if(Debug_Mode)
      {
         if(currentTrendState == TREND_BULLISH)
            Print("GetTrendState: Strong bullish trend continues");
         else if(currentTrendState == TREND_BEARISH)
            Print("GetTrendState: Strong bearish trend continues");
         else
            Print("GetTrendState: No strong trend detected, remaining in RANGING state");
      }
      
      return currentTrendState;
   }
}

//+------------------------------------------------------------------+
//| Timer function for breakeven management                          |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(!Use_Breakeven_Logic) return;
   
   bool modificationsPerformed = false;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
         PositionGetInteger(POSITION_MAGIC) != MAGIC_NUMBER)
         continue;
         
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      
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
         request.tp = currentTP; // Keep the same TP
         
         if(OrderSend(request, result))
         {
            if(result.retcode == TRADE_RETCODE_DONE)
            {
               Print("OnTimer: Modified position #", ticket, " to breakeven at 1:1 risk-reward. Risk: ", 
                     riskPips, " pips, Profit: ", profitPips, " pips");
               modificationsPerformed = true;
            }
            else
            {
               Print("OnTimer: Failed to modify position to breakeven. Result code: ", result.retcode);
            }
         }
         else
         {
            Print("OnTimer: Failed to send breakeven modification. Error: ", GetLastError());
         }
      }
   }
   
   // If any modifications were performed, refresh the chart
   if(modificationsPerformed)
      ChartRedraw();
}

//+------------------------------------------------------------------+
//| Check for engulfing pattern and execute trade                    |
//+------------------------------------------------------------------+
void CheckForEngulfingAndTrade(const MqlRates &rates[], double sensitivity)
{
    // Make sure we have enough data
    if (ArraySize(rates) < SHIFT_TO_CHECK + 10) // Changed from +2 to +101 to accommodate 100 candle lookback
    {
        Print("CheckForEngulfingAndTrade: Not enough candle data for 100 candle lookback. Need at least ", 
              SHIFT_TO_CHECK + 101, " candles, but only have ", ArraySize(rates));
        return;
    }
    
    // Get current candle data for later use in trade execution
    double currentOpen = rates[SHIFT_TO_CHECK].open;
    double currentClose = rates[SHIFT_TO_CHECK].close;
    double currentHigh = rates[SHIFT_TO_CHECK].high;
    double currentLow = rates[SHIFT_TO_CHECK].low;
    
    // Check for bullish and bearish engulfing patterns using IsEngulfing function
    // Modified to use 100 candle lookback instead of just the previous candle
    bool isBullishEngulfing = IsEngulfing(SHIFT_TO_CHECK, true, false, 10);  // Added lookback parameter of 100
    bool isBearishEngulfing = IsEngulfing(SHIFT_TO_CHECK, false, false, 10); // Added lookback parameter of 100
    
    // If no engulfing pattern detected, exit
    if (!isBullishEngulfing && !isBearishEngulfing)
    {
        Print("CheckForEngulfingAndTrade: No engulfing pattern detected within 100 candle lookback");
        return;
    }
    
    // Check cooldown before proceeding with trade execution
    if (IsStrategyOnCooldown())
    {
        Print("CheckForEngulfingAndTrade: Strategy on cooldown, pattern marked but skipping trade execution");
        return;
    }
    
    // Apply trend filter if enabled
    if (Use_Trend_Filter)
    {
        int trendState = GetTrendState();
        
        if (isBullishEngulfing && trendState != TREND_BULLISH)
        {
            PrintFormat("Bullish engulfing detected but trend filter not bullish (trend state: %d), pattern marked but skipping trade", trendState);
            return;
        }
        
        if (isBearishEngulfing && trendState != TREND_BEARISH)
        {
            PrintFormat("Bearish engulfing detected but trend filter not bearish (trend state: %d), pattern marked but skipping trade", trendState);
            return;
        }
    }
    
    // Debug: Print all support zones to check if they exist
    PrintFormat("Active support zones count: %d", ArraySize(g_activeSupportZones));
    for (int i = 0; i < ArraySize(g_activeSupportZones); i++)
    {
        PrintFormat("Support zone %d: [%.5f-%.5f]", i, g_activeSupportZones[i].bottomBoundary, g_activeSupportZones[i].topBoundary);
    }
    
    // Debug: Print all resistance zones to check if they exist
    PrintFormat("Active resistance zones count: %d", ArraySize(g_activeResistanceZones));
    for (int i = 0; i < ArraySize(g_activeResistanceZones); i++)
    {
        PrintFormat("Resistance zone %d: [%.5f-%.5f]", i, g_activeResistanceZones[i].bottomBoundary, g_activeResistanceZones[i].topBoundary);
    }
    
    // Check if bullish engulfing interacts with support zone
    if (isBullishEngulfing)
    {
        bool interactsWithSupportZone = false;
        double stopLoss = 0;
        double takeProfit = 0;
        int zoneIndex = -1;
        
        // Check if the engulfing pattern interacts with a support zone
        for (int i = 0; i < ArraySize(g_activeSupportZones); i++)
        {
            // Check if any part of the candle (body or wick) is within or touches the zone
            bool bodyInZone = (currentOpen >= g_activeSupportZones[i].bottomBoundary && currentOpen <= g_activeSupportZones[i].topBoundary) ||
                             (currentClose >= g_activeSupportZones[i].bottomBoundary && currentClose <= g_activeSupportZones[i].topBoundary);
                             
            bool wickInZone = (currentLow >= g_activeSupportZones[i].bottomBoundary && currentLow <= g_activeSupportZones[i].topBoundary) ||
                             (currentHigh >= g_activeSupportZones[i].bottomBoundary && currentHigh <= g_activeSupportZones[i].topBoundary);
                             
            bool zoneWithinCandle = (g_activeSupportZones[i].bottomBoundary >= currentLow && g_activeSupportZones[i].topBoundary <= currentHigh);
            
            PrintFormat("Bullish engulfing - Zone %d: Body in zone: %s, Wick in zone: %s, Zone within candle: %s", 
                       i, bodyInZone ? "Yes" : "No", wickInZone ? "Yes" : "No", zoneWithinCandle ? "Yes" : "No");
            
            if (bodyInZone || wickInZone || zoneWithinCandle)
            {
                PrintFormat("Bullish engulfing confirmed interacting with support zone [%.5f-%.5f]", 
                            g_activeSupportZones[i].bottomBoundary, g_activeSupportZones[i].topBoundary);
                
                interactsWithSupportZone = true;
                zoneIndex = i;
                
                // Set stop loss below support zone with a small buffer
                stopLoss = g_activeSupportZones[i].bottomBoundary - (sensitivity * 2);
                
                // Set take profit with 1:2 risk-reward ratio
                takeProfit = currentClose + ((currentClose - stopLoss) * 2);
                
                // Draw signal arrow on chart
                string arrowName = "BuySignal_" + TimeToString(rates[SHIFT_TO_CHECK].time);
                ObjectCreate(0, arrowName, OBJ_ARROW_BUY, 0, rates[SHIFT_TO_CHECK].time, currentLow - (sensitivity * 3));
                ObjectSetInteger(0, arrowName, OBJPROP_COLOR, clrGreen);
                ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 2);
                
                break;
            }
        }
        
        if (interactsWithSupportZone)
        {
            PrintFormat("BUY SIGNAL generated: Entry=%.5f, SL=%.5f, TP=%.5f, Zone Index=%d", 
                       currentClose, stopLoss, takeProfit, zoneIndex);
            ExecuteTrade(true, currentClose, stopLoss, takeProfit);
            g_lastTradeTime = TimeCurrent();
        }
        else
        {
            Print("Bullish engulfing detected but not interacting with any support zone");
        }
    }
    
    // Check if bearish engulfing interacts with resistance zone
    if (isBearishEngulfing)
    {
        bool interactsWithResistanceZone = false;
        double stopLoss = 0;
        double takeProfit = 0;
        int zoneIndex = -1;
        
        // Check if the engulfing pattern interacts with a resistance zone
        for (int i = 0; i < ArraySize(g_activeResistanceZones); i++)
        {
            // Check if any part of the candle (body or wick) is within or touches the zone
            bool bodyInZone = (currentOpen >= g_activeResistanceZones[i].bottomBoundary && currentOpen <= g_activeResistanceZones[i].topBoundary) ||
                             (currentClose >= g_activeResistanceZones[i].bottomBoundary && currentClose <= g_activeResistanceZones[i].topBoundary);
                             
            bool wickInZone = (currentLow >= g_activeResistanceZones[i].bottomBoundary && currentLow <= g_activeResistanceZones[i].topBoundary) ||
                             (currentHigh >= g_activeResistanceZones[i].bottomBoundary && currentHigh <= g_activeResistanceZones[i].topBoundary);
                             
            bool zoneWithinCandle = (g_activeResistanceZones[i].bottomBoundary >= currentLow && g_activeResistanceZones[i].topBoundary <= currentHigh);
            
            PrintFormat("Bearish engulfing - Zone %d: Body in zone: %s, Wick in zone: %s, Zone within candle: %s", 
                       i, bodyInZone ? "Yes" : "No", wickInZone ? "Yes" : "No", zoneWithinCandle ? "Yes" : "No");
            
            if (bodyInZone || wickInZone || zoneWithinCandle)
            {
                PrintFormat("Bearish engulfing confirmed interacting with resistance zone [%.5f-%.5f]", 
                            g_activeResistanceZones[i].bottomBoundary, g_activeResistanceZones[i].topBoundary);
                
                interactsWithResistanceZone = true;
                zoneIndex = i;
                
                // Set stop loss above resistance zone with a small buffer
                stopLoss = g_activeResistanceZones[i].topBoundary + (sensitivity * 2);
                
                // Set take profit with 1:2 risk-reward ratio
                takeProfit = currentClose - ((stopLoss - currentClose) * 2);
                
                // Draw signal arrow on chart
                string arrowName = "SellSignal_" + TimeToString(rates[SHIFT_TO_CHECK].time);
                ObjectCreate(0, arrowName, OBJ_ARROW_SELL, 0, rates[SHIFT_TO_CHECK].time, currentHigh + (sensitivity * 3));
                ObjectSetInteger(0, arrowName, OBJPROP_COLOR, clrRed);
                ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 2);
                
                break;
            }
        }
        
        if (interactsWithResistanceZone)
        {
            PrintFormat("SELL SIGNAL generated: Entry=%.5f, SL=%.5f, TP=%.5f, Zone Index=%d", 
                       currentClose, stopLoss, takeProfit, zoneIndex);
            ExecuteTrade(false, currentClose, stopLoss, takeProfit);
            g_lastTradeTime = TimeCurrent();
        }
        else
        {
            Print("Bearish engulfing detected but not interacting with any resistance zone");
        }
    }
}


