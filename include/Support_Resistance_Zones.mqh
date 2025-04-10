#property copyright "Copyright 2023"
#property strict

// Constants
#define SR_MIN_TOUCHES 2
#define ZONE_LOOKBACK 200  // Extended lookback for zone detection

// Colors for zones
color SUPPORT_ZONE_COLOR = clrRed;
color RESISTANCE_ZONE_COLOR = clrBlue;

// Support/Resistance Zone Structure
struct SRZone
{
   double topBoundary;
   double bottomBoundary;
   double definingClose;
   bool isResistance;
   int touchCount;
   long chartObjectID_Top;
   long chartObjectID_Bottom;
   int shift;
};

// Global S/R Zone Arrays
SRZone g_activeSupportZones[];
SRZone g_activeResistanceZones[];
int g_nearestSupportZoneIndex = -1;
int g_nearestResistanceZoneIndex = -1;

// Function implementations from Strategy2_SR_Engulfing_EA.mq5
// Copy all functions exactly as they are but remove their definitions from the EA

void UpdateAndDrawValidSRZones(int lookbackPeriod, int sensitivityPips)
{
    Print("UpdateAndDrawValidSRZones: Starting update...");
    
    // Delete existing lines before creating new ones
    DeleteAllSRZoneLines();
    
    // Get price data
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    int copied = CopyRates(_Symbol, PERIOD_CURRENT, 0, lookbackPeriod + 2, rates);
    if(copied < lookbackPeriod + 2)
    {
        Print("UpdateAndDrawValidSRZones: Failed to copy rates. Error: ", GetLastError());
        return;
    }
    
    double sensitivityValue = sensitivityPips * _Point;
    Print("UpdateAndDrawValidSRZones: Sensitivity value: ", sensitivityValue);
    
    // Remove broken zones
    for(int i = ArraySize(g_activeResistanceZones) - 1; i >= 0; i--)
    {
        if(IsZoneBroken(g_activeResistanceZones[i], rates, 0))
        {
            // Delete the zone's lines
            ObjectDelete(0, "SRZone_" + IntegerToString(g_activeResistanceZones[i].chartObjectID_Top));
            ObjectDelete(0, "SRZone_" + IntegerToString(g_activeResistanceZones[i].chartObjectID_Bottom));
            
            // Remove the zone from array
            ArrayRemove(g_activeResistanceZones, i, 1);
        }
    }
    
    for(int i = ArraySize(g_activeSupportZones) - 1; i >= 0; i--)
    {
        if(IsZoneBroken(g_activeSupportZones[i], rates, 0))
        {
            // Delete the zone's lines
            ObjectDelete(0, "SRZone_" + IntegerToString(g_activeSupportZones[i].chartObjectID_Top));
            ObjectDelete(0, "SRZone_" + IntegerToString(g_activeSupportZones[i].chartObjectID_Bottom));
            
            // Remove the zone from array
            ArrayRemove(g_activeSupportZones, i, 1);
        }
    }
    
    // Clear existing zones
    ArrayFree(g_activeSupportZones);
    ArrayFree(g_activeResistanceZones);
    g_nearestSupportZoneIndex = -1;
    g_nearestResistanceZoneIndex = -1;
    
    // Get EMA values for zone validation
    double emaValues[];
    ArraySetAsSeries(emaValues, true);
    copied = CopyBuffer(g_ema.handle, 0, 0, lookbackPeriod, emaValues);
    if(copied != lookbackPeriod)
    {
        Print("Failed to copy EMA values. Error: ", GetLastError());
        return;
    }
    
    // Look for new zones
    for(int i = 1; i < lookbackPeriod; i++)
    {
        double emaValue = emaValues[i];
        
        // Check for potential resistance (must be above EMA)
        if(rates[i].close > emaValue && rates[i].close > rates[i-1].close && rates[i].close > rates[i+1].close)
        {
            SRZone newZone;
            newZone.definingClose = rates[i].close;
            // Use lowest open/close for zone boundaries
            newZone.bottomBoundary = MathMin(rates[i].open, rates[i].close);
            newZone.topBoundary = MathMax(rates[i+1].high, MathMax(rates[i].high, rates[i-1].high));
            newZone.isResistance = true;
            newZone.touchCount = 0;
            newZone.shift = i;
            
            // Generate unique IDs for chart objects
            newZone.chartObjectID_Top = StringToInteger(IntegerToString(ChartID()) + StringSubstr(TimeToString(TimeCurrent()), 11, 5) + IntegerToString(i));
            newZone.chartObjectID_Bottom = StringToInteger(IntegerToString(ChartID()) + StringSubstr(TimeToString(TimeCurrent()), 11, 5) + IntegerToString(i+1));
            
            AddZoneIfValid(newZone, g_activeResistanceZones, sensitivityValue);
        }
        
        // Check for potential support (must be below EMA)
        if(rates[i].close < emaValue && rates[i].close < rates[i-1].close && rates[i].close < rates[i+1].close)
        {
            SRZone newZone;
            newZone.definingClose = rates[i].close;
            // Use lowest open/close for zone boundaries
            newZone.bottomBoundary = MathMin(rates[i+1].low, MathMin(rates[i].low, rates[i-1].low));
            newZone.topBoundary = MathMax(rates[i].open, rates[i].close);
            newZone.isResistance = false;
            newZone.touchCount = 0;
            newZone.shift = i;
            
            // Generate unique IDs for chart objects
            newZone.chartObjectID_Top = StringToInteger(IntegerToString(ChartID()) + StringSubstr(TimeToString(TimeCurrent()), 11, 5) + IntegerToString(i+2));
            newZone.chartObjectID_Bottom = StringToInteger(IntegerToString(ChartID()) + StringSubstr(TimeToString(TimeCurrent()), 11, 5) + IntegerToString(i+3));
            
            AddZoneIfValid(newZone, g_activeSupportZones, sensitivityValue);
        }
    }
    
    // Draw zones and update touch counts
    DrawAndValidateZones(rates, sensitivityValue);
    
    Print("UpdateAndDrawValidSRZones: Found ", ArraySize(g_activeSupportZones), " support zones and ",
          ArraySize(g_activeResistanceZones), " resistance zones");
}

//+------------------------------------------------------------------+
//| Draw individual zone lines                                         |
//+------------------------------------------------------------------+
void DrawZoneLines(const SRZone &zone, const color lineColor)
{
   // Get the time of the candle that created this zone
   datetime zoneTime = iTime(_Symbol, PERIOD_CURRENT, zone.shift);
   datetime currentTime = TimeCurrent();
   
   string topName = StringFormat("SRZone_%d_Top", zone.chartObjectID_Top);
   string bottomName = StringFormat("SRZone_%d_Bottom", zone.chartObjectID_Bottom);
   
   Print("Drawing zone lines: ", topName, " and ", bottomName);
   
   // Delete existing objects
   ObjectDelete(0, topName);
   ObjectDelete(0, bottomName);
   
   // Draw horizontal lines from zone creation point to current time
   if(!ObjectCreate(0, topName, OBJ_TREND, 0, 
      zoneTime, zone.topBoundary, 
      currentTime, zone.topBoundary))
   {
      Print("Failed to create top boundary line. Error: ", GetLastError());
      return;
   }
   
   if(!ObjectCreate(0, bottomName, OBJ_TREND, 0, 
      zoneTime, zone.bottomBoundary, 
      currentTime, zone.bottomBoundary))
   {
      Print("Failed to create bottom boundary line. Error: ", GetLastError());
      return;
   }
   
   // Set line properties
   color zoneColor = lineColor;
   
   // Top line properties
   ObjectSetInteger(0, topName, OBJPROP_COLOR, zone.isResistance ? RESISTANCE_ZONE_COLOR : SUPPORT_ZONE_COLOR);
   ObjectSetInteger(0, topName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, topName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, topName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, topName, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, topName, OBJPROP_RAY_RIGHT, true);
   
   // Bottom line properties
   ObjectSetInteger(0, bottomName, OBJPROP_COLOR, zone.isResistance ? RESISTANCE_ZONE_COLOR : SUPPORT_ZONE_COLOR);
   ObjectSetInteger(0, bottomName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, bottomName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, bottomName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, bottomName, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, bottomName, OBJPROP_RAY_RIGHT, true);
   
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Draw zones and validate touches                                    |
//+------------------------------------------------------------------+
void DrawAndValidateZones(const MqlRates &rates[], double sensitivity)
{
   double currentPrice = rates[0].close;
   
   // Draw and validate resistance zones
   for(int i = 0; i < ArraySize(g_activeResistanceZones); i++)
   {
      // Draw zone lines
      DrawZoneLines(g_activeResistanceZones[i], clrRed);
      
      // Count touches
      g_activeResistanceZones[i].touchCount = CountTouches(rates, g_activeResistanceZones[i], sensitivity);
      
      // Update nearest resistance
      if(g_activeResistanceZones[i].bottomBoundary > currentPrice)
      {
         if(g_nearestResistanceZoneIndex == -1 || 
            g_activeResistanceZones[i].bottomBoundary < g_activeResistanceZones[g_nearestResistanceZoneIndex].bottomBoundary)
         {
            g_nearestResistanceZoneIndex = i;
         }
      }
   }
   
   //+------------------------------------------------------------------+
//| Update and validate S/R zones                                     |
//+------------------------------------------------------------------+


   // Draw and validate support zones
   for(int i = 0; i < ArraySize(g_activeSupportZones); i++)
   {
      // Draw zone lines
      DrawZoneLines(g_activeSupportZones[i], clrGreen);
      
      // Count touches
      g_activeSupportZones[i].touchCount = CountTouches(rates, g_activeSupportZones[i], sensitivity);
      
      // Update nearest support
      if(g_activeSupportZones[i].topBoundary < currentPrice)
      {
         if(g_nearestSupportZoneIndex == -1 || 
            g_activeSupportZones[i].topBoundary > g_activeSupportZones[g_nearestSupportZoneIndex].topBoundary)
         {
            g_nearestSupportZoneIndex = i;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Add zone if it's valid (not too close to existing zones)          |
//+------------------------------------------------------------------+
void AddZoneIfValid(SRZone &newZone, SRZone &existingZones[], double sensitivity)
{
   for(int j = 0; j < ArraySize(existingZones); j++)
   {
      if(MathAbs(newZone.definingClose - existingZones[j].definingClose) < sensitivity)
         return;
   }
   
   int size = ArraySize(existingZones);
   ArrayResize(existingZones, size + 1);
   existingZones[size] = newZone;
}

//+------------------------------------------------------------------+
//| Check if S/R zone is broken                                        |
//+------------------------------------------------------------------+
bool IsZoneBroken(const SRZone &zone, const MqlRates &rates[], int shift)
{
   if(shift + 1 >= ArraySize(rates)) return false;
   
   if(zone.isResistance)
   {
      // Price action must form above the zone
      if(rates[shift].open > zone.topBoundary && rates[shift].close > zone.topBoundary)
      {
         // Confirm with previous candle
         if(rates[shift+1].open > zone.topBoundary && rates[shift+1].close > zone.topBoundary)
         {
            Print("Resistance zone broken at ", TimeToString(rates[shift].time));
            return true;
         }
      }
   }
   else
   {
      // Price action must form below the zone
      if(rates[shift].open < zone.bottomBoundary && rates[shift].close < zone.bottomBoundary)
      {
         // Confirm with previous candle
         if(rates[shift+1].open < zone.bottomBoundary && rates[shift+1].close < zone.bottomBoundary)
         {
            Print("Support zone broken at ", TimeToString(rates[shift].time));
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Count touches for a zone                                           |
//+------------------------------------------------------------------+
int CountTouches(const MqlRates &rates[], const SRZone &zone, double sensitivity)
{
   int touches = 0;
   for(int j = 0; j < SR_Lookback; j++)
   {
      if(zone.isResistance)
      {
         if(MathAbs(rates[j].high - zone.topBoundary) <= sensitivity)
            touches++;
      }
      else
      {
         if(MathAbs(rates[j].low - zone.bottomBoundary) <= sensitivity)
            touches++;
      }
   }
   return touches;
}


//+------------------------------------------------------------------+
//| Delete all S/R zone lines                                         |
//+------------------------------------------------------------------+
void DeleteAllSRZoneLines()
{
   Print("DeleteAllSRZoneLines: Starting cleanup...");
   
   // Delete all objects with our prefix
   int totalObjects = ObjectsTotal(0);
   for(int i = totalObjects - 1; i >= 0; i--)
   {
      string objName = ObjectName(0, i);
      if(StringFind(objName, "SRZone_") == 0)
      {
         if(!ObjectDelete(0, objName))
         {
            Print("Failed to delete object ", objName, ". Error: ", GetLastError());
         }
      }
   }
   
   ChartRedraw(0);
   Print("DeleteAllSRZoneLines: Cleanup completed");
}