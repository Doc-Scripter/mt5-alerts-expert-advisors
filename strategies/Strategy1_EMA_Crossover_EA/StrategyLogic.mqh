//+------------------------------------------------------------------+
//|                                             StrategyLogic.mqh     |
//|                                                                    |
//|                      Strategy Logic Functions for Strategy1       |
//+------------------------------------------------------------------+

// Constants
#define STRATEGY_COOLDOWN_MINUTES 60

//+------------------------------------------------------------------+
//| Check strategy conditions                                         |
//+------------------------------------------------------------------+
void CheckStrategy()
{
   // Check cooldown
   if(IsStrategyOnCooldown()) return;
   
   // First, check if we already have a valid EMA crossover stored
   bool havePendingCrossover = (g_crossoverBar >= 0);
   
   // If we don't have a pending crossover, check for a new one on the previous bar
   if(!havePendingCrossover)
   {
      // Get prices for crossover detection
      double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
      double close2 = iClose(_Symbol, PERIOD_CURRENT, 2);
      
      // Check for bullish crossover (price crosses above EMA)
      if(close2 < g_ema.values[2] && close1 > g_ema.values[1])
      {
         g_lastEmaCrossPrice = close1;
         g_lastEmaCrossAbove = true;
         g_crossoverBar = 1;  // Crossover occurred at bar 1
         Print("Bullish EMA crossover detected at bar 1, price: ", g_lastEmaCrossPrice);
      }
      // Check for bearish crossover (price crosses below EMA)
      else if(close2 > g_ema.values[2] && close1 < g_ema.values[1])
      {
         g_lastEmaCrossPrice = close1;
         g_lastEmaCrossAbove = false;
         g_crossoverBar = 1;  // Crossover occurred at bar 1
         Print("Bearish EMA crossover detected at bar 1, price: ", g_lastEmaCrossPrice);
      }
   }
   
   // If we have a valid crossover (either stored or new), check for engulfing pattern
   if(g_crossoverBar >= 0)
   {
      // Check for engulfing pattern on any bar after crossover
      if(g_lastEmaCrossAbove)
      {
         // Check for bullish engulfing on the current completed bar
         for(int i = 1; i <= g_crossoverBar; i++)  // Check all bars up to the crossover bar
         {
            if(IsEngulfing(i, true, Use_Trend_Filter))
            {
               // Check for no more than one swing low
               if(CountSwingPoints(5, true) <= 1)
               {
                  if(Use_Trend_Filter)
                  {
                     int trendState = GetTrendState();
                     if(trendState != TREND_BULLISH)
                     {
                        Print("Trend filter detected non-bullish trend - skipping trade");
                        return;
                     }
                  }
                  
                  double close1 = iClose(_Symbol, PERIOD_CURRENT, i);
                  // Place stop loss at the lowest point of the engulfing candle
                  double stopLoss = iLow(_Symbol, PERIOD_CURRENT, i);
                  
                  // Find the recent swing low before the engulfing pattern for Fibonacci calculation
                  double swingLow = FindSwingLowBeforeCross(g_crossoverBar, 10);
                  double swingHigh = iHigh(_Symbol, PERIOD_CURRENT, i); // Use engulfing candle high
                  
                  // If we couldn't find a valid swing low, use the engulfing candle's low
                  if(swingLow <= 0) swingLow = stopLoss;
                  
                  // Calculate Fibonacci extension (161.8%)
                  double fibExtension = swingHigh + (swingHigh - swingLow) * 1.618;
                  double takeProfit = fibExtension;
                  
                  // Fallback to 1:1.5 risk-reward if Fibonacci calculation fails
                  if(takeProfit <= close1 || MathAbs(takeProfit - close1) < 10 * _Point)
                  {
                     takeProfit = close1 + ((close1 - stopLoss) * 1.5);
                     Print("Using fallback 1:1.5 risk-reward ratio for take profit");
                  }
                  else
                  {
                     Print("Using Fibonacci 161.8% extension for take profit");
                  }
                  
                  Print("Bullish engulfing found at bar ", i, " after crossover at bar ", g_crossoverBar);
                  Print("Stop loss placed at the lowest point of engulfing candle: ", stopLoss);
                  Print("Take profit placed at Fibonacci 161.8% extension: ", takeProfit);
                  
                  // Send alert instead of executing trade
                  SendTradingAlert(true, close1, stopLoss, takeProfit, i);
                  
                  // Reset crossover after alert sent
                  g_crossoverBar = -1;
                  g_lastEmaCrossPrice = 0.0;
                  g_lastAlertTime = TimeCurrent();
                  return;
               }
               else
               {
                  Print("Too many swing points for bullish trade");
               }
            }
         }
      }
      else // Bearish crossover
      {
         // Check for bearish engulfing on the current completed bar
         for(int i = 1; i <= g_crossoverBar; i++)  // Check all bars up to the crossover bar
         {
            if(IsEngulfing(i, false, Use_Trend_Filter))
            {
               // Check for no more than one swing high
               if(CountSwingPoints(5, false) <= 1)
               {
                  if(Use_Trend_Filter)
                  {
                     int trendState = GetTrendState();
                     if(trendState != TREND_BEARISH)
                     {
                        Print("Trend filter detected non-bearish trend - skipping trade");
                        return;
                     }
                  }
                  
                  double close1 = iClose(_Symbol, PERIOD_CURRENT, i);
                  // Place stop loss at the highest point of the engulfing candle
                  double stopLoss = iHigh(_Symbol, PERIOD_CURRENT, i);
                  
                  // Find the recent swing high before the engulfing pattern for Fibonacci calculation
                  double swingHigh = FindSwingHighBeforeCross(g_crossoverBar, 10);
                  double swingLow = iLow(_Symbol, PERIOD_CURRENT, i); // Use engulfing candle low
                  
                  // If we couldn't find a valid swing high, use the engulfing candle's high
                  if(swingHigh <= 0) swingHigh = stopLoss;
                  
                  // Calculate Fibonacci extension (161.8%)
                  double fibExtension = swingLow - (swingHigh - swingLow) * 1.618;
                  double takeProfit = fibExtension;
                  
                  // Fallback to 1:1.5 risk-reward if Fibonacci calculation fails
                  if(takeProfit >= close1 || MathAbs(takeProfit - close1) < 10 * _Point)
                  {
                     takeProfit = close1 - ((stopLoss - close1) * 1.5);
                     Print("Using fallback 1:1.5 risk-reward ratio for take profit");
                  }
                  else
                  {
                     Print("Using Fibonacci 161.8% extension for take profit");
                  }
                  
                  Print("Bearish engulfing found at bar ", i, " after crossover at bar ", g_crossoverBar);
                  Print("Stop loss placed at the highest point of engulfing candle: ", stopLoss);
                  Print("Take profit placed at Fibonacci 161.8% extension: ", takeProfit);
                  
                  // Send alert instead of executing trade
                  SendTradingAlert(false, close1, stopLoss, takeProfit, i);
                  
                  // Reset crossover after alert sent
                  g_crossoverBar = -1;
                  g_lastEmaCrossPrice = 0.0;
                  g_lastAlertTime = TimeCurrent();
                  return;
               }
               else
               {
                  Print("Too many swing points for bearish trade");
               }
            }
         }
      }
      
      // If we've reached this point, we didn't find a valid engulfing pattern on this bar
      // Increment the bar counter to track how many bars since crossover
      g_crossoverBar++;
      
      // No limit on how many bars to check after crossover
      // The crossover will remain valid until a trade is executed or the EA is stopped
   }
}

//+------------------------------------------------------------------+
//| Check if strategy is on cooldown                                  |
//+------------------------------------------------------------------+
bool IsStrategyOnCooldown()
{
   if(g_lastAlertTime == 0) return false;
   
   datetime currentTime = TimeCurrent();
   if(currentTime - g_lastAlertTime < STRATEGY_COOLDOWN_MINUTES * 60)
      return true;
      
   return false;
}