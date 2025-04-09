//+------------------------------------------------------------------+
//|                                   EMA_Engulfing_EA_Tester.mq5    |
//|                                                                   |
//|                                                                   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023"
#property link      ""
#property version   "1.00"
#property strict

#include <EMA_Engulfing_EA.mqh>
#include <EMA_Engulfing_Trade.mqh>

// Input parameters for testing
input string TestSection = "=== Test Configuration ===";
input bool TestEngulfingPatterns = true;
input bool TestSupportResistance = true;
input bool TestEmaCrossover = true;
input bool TestTradeExecution = false;
input int TestPeriod = 100;

// Test indicators
int emaHandle;
double emaValues[];

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize EMA indicator
   emaHandle = iMA(_Symbol, PERIOD_CURRENT, 20, 0, MODE_EMA, PRICE_CLOSE);
   
   if(emaHandle == INVALID_HANDLE)
   {
      Print("Failed to create EMA indicator handle");
      return(INIT_FAILED);
   }
   
   // Output header for test results
   Print("=== EMA Engulfing EA Tester Started ===");
   
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
      
   Print("=== EMA Engulfing EA Tester Stopped ===");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Only run tests on the first tick
   static bool testsRun = false;
   
   if(!testsRun)
   {
      RunTests();
      testsRun = true;
   }
}

//+------------------------------------------------------------------+
//| Run all the selected tests                                       |
//+------------------------------------------------------------------+
void RunTests()
{
   Print("Starting tests with lookback period of ", TestPeriod, " bars");
   
   // Update EMA values
   ArraySetAsSeries(emaValues, true);
   if(CopyBuffer(emaHandle, 0, 0, TestPeriod, emaValues) < TestPeriod)
   {
      Print("Failed to copy EMA indicator values");
      return;
   }
   
   // Run engulfing pattern tests
   if(TestEngulfingPatterns)
      TestEngulfingPatternDetection();
      
   // Run support/resistance tests
   if(TestSupportResistance)
      TestSupportResistanceDetection();
      
   // Run EMA crossover tests
   if(TestEmaCrossover)
      TestEmaCrossoverDetection();
      
   // Run trade execution test
   if(TestTradeExecution)
      TestTradeExecutionLogic();
}

//+------------------------------------------------------------------+
//| Test engulfing pattern detection                                 |
//+------------------------------------------------------------------+
void TestEngulfingPatternDetection()
{
   Print("--- Testing Engulfing Pattern Detection ---");
   
   int bullishCount = 0;
   int bearishCount = 0;
   
   for(int i = 0; i < TestPeriod - 1; i++)
   {
      bool isBullish;
      if(IsEngulfingPattern(i, isBullish))
      {
         if(isBullish)
         {
            bullishCount++;
            Print("Bullish engulfing pattern detected at bar ", i);
         }
         else
         {
            bearishCount++;
            Print("Bearish engulfing pattern detected at bar ", i);
         }
      }
   }
   
   Print("Found ", bullishCount, " bullish and ", bearishCount, " bearish engulfing patterns");
}

//+------------------------------------------------------------------+
//| Test support/resistance detection                                |
//+------------------------------------------------------------------+
void TestSupportResistanceDetection()
{
   Print("--- Testing Support/Resistance Detection ---");
   
   int supportCount = 0;
   int resistanceCount = 0;
   
   for(int i = 0; i < TestPeriod - 1; i++)
   {
      SRLevel level;
      if(IdentifySRLevel(i, level))
      {
         if(level.isResistance)
         {
            resistanceCount++;
            Print("Resistance level detected at bar ", i, ", price: ", level.price, ", strength: ", level.strength);
         }
         else
         {
            supportCount++;
            Print("Support level detected at bar ", i, ", price: ", level.price, ", strength: ", level.strength);
         }
      }
   }
   
   Print("Found ", supportCount, " support and ", resistanceCount, " resistance levels");
}

//+------------------------------------------------------------------+
//| Test EMA crossover detection                                     |
//+------------------------------------------------------------------+
void TestEmaCrossoverDetection()
{
   Print("--- Testing EMA Crossover Detection ---");
   
   int upCrossCount = 0;
   int downCrossCount = 0;
   
   for(int i = 0; i < TestPeriod - 2; i++)
   {
      bool crossedUp;
      if(DetectEmaCross(emaValues, i, crossedUp))
      {
         if(crossedUp)
         {
            upCrossCount++;
            Print("Upward EMA cross detected at bar ", i);
         }
         else
         {
            downCrossCount++;
            Print("Downward EMA cross detected at bar ", i);
         }
      }
   }
   
   Print("Found ", upCrossCount, " upward and ", downCrossCount, " downward EMA crosses");
}

//+------------------------------------------------------------------+
//| Test trade execution logic                                       |
//+------------------------------------------------------------------+
void TestTradeExecutionLogic()
{
   Print("--- Testing Trade Execution Logic ---");
   
   // Create a sample trade for testing
   TradeParams params;
   params.isBuy = true;
   params.entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   params.stopLoss = params.entryPrice - 100 * _Point;
   params.takeProfit1 = params.entryPrice + 170 * _Point;
   params.takeProfit2 = params.entryPrice + 200 * _Point;
   params.lotSize1 = 0.01;
   params.lotSize2 = 0.02;
   params.comment = "Test Trade";
   
   Print("Executing test trade with SL at ", params.stopLoss, " and TPs at ", params.takeProfit1, " and ", params.takeProfit2);
   
   bool success = ExecuteTradeStrategy(params);
   
   if(success)
      Print("Test trade executed successfully");
   else
      Print("Test trade execution failed");
}
//+------------------------------------------------------------------+