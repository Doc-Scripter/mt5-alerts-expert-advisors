//+------------------------------------------------------------------+
//|                                             AlertSystem.mqh       |
//|                                                                    |
//|                      Alert System Functions for Strategy1         |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Check if alert cooldown period has passed                        |
//+------------------------------------------------------------------+
bool IsAlertCooldownPassed(bool isBullish)
{
   datetime currentTime = TimeCurrent();
   datetime lastAlertTime = isBullish ? g_lastBullishAlertTime : g_lastBearishAlertTime;
   
   if(lastAlertTime == 0) return true; // First alert
   
   int cooldownSeconds = Alert_Cooldown_Minutes * 60;
   return (currentTime - lastAlertTime) >= cooldownSeconds;
}

//+------------------------------------------------------------------+
//| Send comprehensive alert for trading signal                      |
//+------------------------------------------------------------------+
void SendTradingAlert(bool isBullish, double entryPrice, double stopLoss, double takeProfit, int barIndex)
{
   if(!Enable_Alerts) return;
   
   // Check cooldown
   if(!IsAlertCooldownPassed(isBullish)) return;
   
   // Update last alert time
   if(isBullish)
      g_lastBullishAlertTime = TimeCurrent();
   else
      g_lastBearishAlertTime = TimeCurrent();
   
   // Prepare alert message
   string direction = isBullish ? "BUY" : "SELL";
   string symbol = _Symbol;
   string timeframe = EnumToString(PERIOD_CURRENT);
   
   // Calculate risk-reward ratio
   double risk = MathAbs(entryPrice - stopLoss);
   double reward = MathAbs(takeProfit - entryPrice);
   double rrRatio = (risk > 0) ? reward / risk : 0;
   
   string alertMessage = StringFormat(
      "🚨 %s SIGNAL - %s %s\n" +
      "📊 Strategy: EMA Crossover + Engulfing\n" +
      "💰 Entry: %.5f\n" +
      "🛑 Stop Loss: %.5f\n" +
      "🎯 Take Profit: %.5f\n" +
      "📈 Risk/Reward: 1:%.2f\n" +
      "⏰ Time: %s\n" +
      "📍 Bar: %d",
      direction, direction, symbol,
      entryPrice, stopLoss, takeProfit, rrRatio,
      TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES),
      barIndex
   );
   
   // Send push notification to mobile
   if(Send_Push_Notifications)
   {
      string pushMessage = StringFormat("%s Signal - %s at %.5f", direction, symbol, entryPrice);
      SendNotification(pushMessage);
      Print("Push notification sent: ", pushMessage);
   }
   
   // Send email alert
   if(Send_Email_Alerts)
   {
      string emailSubject = StringFormat("Trading Alert: %s %s", direction, symbol);
      SendMail(emailSubject, alertMessage);
      Print("Email alert sent: ", emailSubject);
   }
   
   // Play sound alert
   if(Play_Sound_Alert)
   {
      PlaySound(Alert_Sound_File);
      Print("Sound alert played: ", Alert_Sound_File);
   }
   
   // Show chart alert
   if(Show_Chart_Alert)
   {
      Alert(alertMessage);
   }
   
   // Print to experts log
   Print("=== TRADING ALERT ===");
   Print(alertMessage);
   Print("====================");
   
   // Draw signal arrow on chart
   DrawSignalArrow(isBullish, entryPrice, barIndex);
}

//+------------------------------------------------------------------+
//| Draw signal arrow on chart                                       |
//+------------------------------------------------------------------+
void DrawSignalArrow(bool isBullish, double price, int barIndex)
{
   datetime time = iTime(_Symbol, PERIOD_CURRENT, barIndex);
   string arrowName = StringFormat("Alert_%s_%s", 
                                   isBullish ? "Buy" : "Sell", 
                                   TimeToString(time, TIME_DATE|TIME_MINUTES));
   
   // Remove any existing arrow with the same name
   ObjectDelete(0, arrowName);
   
   // Create new arrow
   if(isBullish)
   {
      ObjectCreate(0, arrowName, OBJ_ARROW_BUY, 0, time, price - 20 * _Point);
      ObjectSetInteger(0, arrowName, OBJPROP_COLOR, clrLime);
   }
   else
   {
      ObjectCreate(0, arrowName, OBJ_ARROW_SELL, 0, time, price + 20 * _Point);
      ObjectSetInteger(0, arrowName, OBJPROP_COLOR, clrRed);
   }
   
   ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 3);
   ObjectSetInteger(0, arrowName, OBJPROP_SELECTABLE, false);
   ObjectSetString(0, arrowName, OBJPROP_TEXT, StringFormat("%s Alert", isBullish ? "BUY" : "SELL"));
}

//+------------------------------------------------------------------+
//| Send simple crossover alert                                      |
//+------------------------------------------------------------------+
void SendCrossoverAlert(bool isBullish, double crossPrice)
{
   if(!Enable_Alerts) return;
   
   string direction = isBullish ? "Bullish" : "Bearish";
   string message = StringFormat("EMA Crossover Alert: %s crossover detected on %s at %.5f", 
                                direction, _Symbol, crossPrice);
   
   if(Send_Push_Notifications)
   {
      SendNotification(message);
   }
   
   if(Play_Sound_Alert)
   {
      PlaySound("news.wav"); // Different sound for crossover
   }
   
   Print("Crossover Alert: ", message);
}