#property copyright "Copyright 2023"
#property strict

// Constants
#define SR_MIN_TOUCHES 2
#define ZONE_LOOKBACK 100  // Reduced from 300 to 100 candles

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

// Add tracking for drawn zones
struct DrawnZone
{
    long chartObjectID_Top;
    long chartObjectID_Bottom;
    bool isActive;
};

// Global S/R Zone Arrays
SRZone g_activeSupportZones[];
SRZone g_activeResistanceZones[];
int g_nearestSupportZoneIndex = -1;
int g_nearestResistanceZoneIndex = -1;

// Global array to track drawn zones
DrawnZone g_drawnZones[];

// Function implementations from Strategy2_SR_Engulfing_EA.mq5
// Copy all functions exactly as they are but remove their definitions from the EA

// Modify UpdateAndDrawValidSRZones to only draw new zones
void UpdateAndDrawValidSRZones(int lookbackPeriod, int sensitivityPips)
{
    // Clear all existing zones first
    DeleteAllSRZoneLines();
    ArrayFree(g_activeSupportZones);
    ArrayFree(g_activeResistanceZones);
    
    // Get price data
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    int copied = CopyRates(_Symbol, PERIOD_CURRENT, 0, ZONE_LOOKBACK, rates);
    if(copied < ZONE_LOOKBACK)
    {
        Print("Failed to copy rates. Error: ", GetLastError());
        return;
    }
    
    // Get EMA values
    double emaValues[];
    ArraySetAsSeries(emaValues, true);
    copied = CopyBuffer(g_ema.handle, 0, 0, ZONE_LOOKBACK, emaValues);
    if(copied != ZONE_LOOKBACK)
    {
        Print("Failed to copy EMA values. Error: ", GetLastError());
        return;
    }
    
    double sensitivity = sensitivityPips * _Point;
    
    // Look for initial zones from most recent to oldest
    for(int i = 0; i < ZONE_LOOKBACK - 1; i++)
    {
        double emaValue = emaValues[i];
        bool isBullish = rates[i].close > rates[i].open;
        
        if(rates[i].close > emaValue && isBullish)
        {
            // Potential resistance zone
            if(HasActiveZoneNearby(rates[i].close, sensitivity)) continue;
            
            SRZone newZone;
            newZone.definingClose = rates[i].close;
            newZone.topBoundary = rates[i].high;
            newZone.bottomBoundary = rates[i].open;
            newZone.isResistance = true;
            newZone.touchCount = 1;
            newZone.shift = i;
            newZone.chartObjectID_Top = TimeCurrent() + i;
            newZone.chartObjectID_Bottom = TimeCurrent() + i + 1;
            
            AddZoneIfValid(newZone, g_activeResistanceZones, sensitivity);
        }
        else if(rates[i].close < emaValue && !isBullish)
        {
            // Potential support zone
            if(HasActiveZoneNearby(rates[i].close, sensitivity)) continue;
            
            SRZone newZone;
            newZone.definingClose = rates[i].close;
            newZone.topBoundary = rates[i].open;
            newZone.bottomBoundary = rates[i].low;
            newZone.isResistance = false;
            newZone.touchCount = 1;
            newZone.shift = i;
            newZone.chartObjectID_Top = TimeCurrent() + i;
            newZone.chartObjectID_Bottom = TimeCurrent() + i + 1;
            
            AddZoneIfValid(newZone, g_activeSupportZones, sensitivity);
        }
    }
}

// New function to check for broken zones
void CheckAndRemoveBrokenZones(const MqlRates &rates[])
{
    // Check resistance zones
    for(int i = ArraySize(g_activeResistanceZones) - 1; i >= 0; i--)
    {
        if(IsZoneBroken(g_activeResistanceZones[i], rates, 0))
        {
            // Remove the zone's visual elements
            DeleteZoneObjects(g_activeResistanceZones[i]);
            // Remove from active zones array
            ArrayRemove(g_activeResistanceZones, i, 1);
        }
    }
    
    // Check support zones
    for(int i = ArraySize(g_activeSupportZones) - 1; i >= 0; i--)
    {
        if(IsZoneBroken(g_activeSupportZones[i], rates, 0))
        {
            // Remove the zone's visual elements
            DeleteZoneObjects(g_activeSupportZones[i]);
            // Remove from active zones array
            ArrayRemove(g_activeSupportZones, i, 1);
        }
    }
}

// Update DeleteZoneObjects to ensure complete removal
void DeleteZoneObjects(const SRZone &zone)
{
    string topName = StringFormat("SRZone_%d_Top", zone.chartObjectID_Top);
    string bottomName = StringFormat("SRZone_%d_Bottom", zone.chartObjectID_Bottom);
    
    // Force deletion of both lines
    if(ObjectFind(0, topName) >= 0)
        ObjectDelete(0, topName);
    if(ObjectFind(0, bottomName) >= 0)
        ObjectDelete(0, bottomName);
        
    ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Draw individual zone lines                                         |
//+------------------------------------------------------------------+
void DrawZoneLines(const SRZone &zone, const color lineColor)
{
    // Check if zone is already drawn
    string topName = StringFormat("SRZone_%d_Top", zone.chartObjectID_Top);
    string bottomName = StringFormat("SRZone_%d_Bottom", zone.chartObjectID_Bottom);
    
    if(ObjectFind(0, topName) >= 0 && ObjectFind(0, bottomName) >= 0)
        return;  // Zone already drawn
        
    // Get the time of the candle that created this zone
    datetime zoneTime = iTime(_Symbol, PERIOD_CURRENT, zone.shift);
    datetime currentTime = TimeCurrent();
    
    Print("Drawing zone lines: ", topName, " and ", bottomName);
    
    // Create new lines
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

// Update IsZoneBroken to be more precise
bool IsZoneBroken(const SRZone &zone, const MqlRates &rates[], int shift)
{
    if(shift >= ArraySize(rates)) return false;
    
    double candleOpen = rates[shift].open;
    double candleClose = rates[shift].close;
    bool isBullish = candleClose > candleOpen;
    
    if(zone.isResistance)
    {
        // Resistance broken by a bullish candle that opens and closes above
        if(isBullish && candleOpen > zone.topBoundary && candleClose > zone.topBoundary)
        {
            Print("Resistance zone broken by bullish candle at ", TimeToString(rates[shift].time));
            // Create new resistance zone from breaking candle
            SRZone newZone;
            newZone.definingClose = candleClose;
            newZone.topBoundary = rates[shift].high;
            newZone.bottomBoundary = candleOpen;
            newZone.isResistance = true;
            newZone.touchCount = 1;
            newZone.shift = shift;
            newZone.chartObjectID_Top = TimeCurrent() + shift;
            newZone.chartObjectID_Bottom = TimeCurrent() + shift + 1;
            
            // Add new zone after confirming break
            AddZoneIfValid(newZone, g_activeResistanceZones, _Point * 10);
            return true;
        }
    }
    else
    {
        // Support broken by a bearish candle that opens and closes below
        if(!isBullish && candleOpen < zone.bottomBoundary && candleClose < zone.bottomBoundary)
        {
            Print("Support zone broken by bearish candle at ", TimeToString(rates[shift].time));
            // Create new support zone from breaking candle
            SRZone newZone;
            newZone.definingClose = candleClose;
            newZone.topBoundary = candleOpen;
            newZone.bottomBoundary = rates[shift].low;
            newZone.isResistance = false;
            newZone.touchCount = 1;
            newZone.shift = shift;
            newZone.chartObjectID_Top = TimeCurrent() + shift;
            newZone.chartObjectID_Bottom = TimeCurrent() + shift + 1;
            
            // Add new zone after confirming break
            AddZoneIfValid(newZone, g_activeSupportZones, _Point * 10);
            return true;
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

//+------------------------------------------------------------------+
//| Check if there's an active zone near the given price              |
//+------------------------------------------------------------------+
bool HasActiveZoneNearby(double price, double sensitivity)
{
    // Check resistance zones
    for(int i = 0; i < ArraySize(g_activeResistanceZones); i++)
    {
        if(MathAbs(price - g_activeResistanceZones[i].definingClose) < sensitivity)
            return true;
    }
    
    // Check support zones
    for(int i = 0; i < ArraySize(g_activeSupportZones); i++)
    {
        if(MathAbs(price - g_activeSupportZones[i].definingClose) < sensitivity)
            return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Check if a new zone is valid at the given position                |
//+------------------------------------------------------------------+
bool IsNewValidZone(const MqlRates &rates[], int shift, double emaValue, bool isResistance)
{
    if(isResistance)
    {
        return rates[shift].close > emaValue &&                    // Price above EMA
               rates[shift].close > rates[shift-1].close &&        // Higher than previous
               rates[shift].close > rates[shift+1].close;          // Higher than next
    }
    else
    {
        return rates[shift].close < emaValue &&                    // Price below EMA
               rates[shift].close < rates[shift-1].close &&        // Lower than previous
               rates[shift].close < rates[shift+1].close;          // Lower than next
    }
}

//+------------------------------------------------------------------+
//| Create and draw a new zone                                        |
//+------------------------------------------------------------------+
void CreateAndDrawNewZone(const MqlRates &rates[], int shift, bool isResistance, double sensitivity)
{
    SRZone newZone;
    newZone.definingClose = rates[shift].close;
    newZone.shift = shift;
    newZone.isResistance = isResistance;
    newZone.touchCount = 1;
    
    if(isResistance)
    {
        newZone.bottomBoundary = MathMin(rates[shift].open, rates[shift].close);
        newZone.topBoundary = rates[shift].high;
        newZone.chartObjectID_Top = TimeCurrent() + shift;
        newZone.chartObjectID_Bottom = TimeCurrent() + shift + 1;
        
        AddZoneIfValid(newZone, g_activeResistanceZones, sensitivity);
    }
    else
    {
        newZone.bottomBoundary = rates[shift].low;
        newZone.topBoundary = MathMax(rates[shift].open, rates[shift].close);
        newZone.chartObjectID_Top = TimeCurrent() + shift;
        newZone.chartObjectID_Bottom = TimeCurrent() + shift + 1;
        
        AddZoneIfValid(newZone, g_activeSupportZones, sensitivity);
    }
    
    DrawZoneLines(newZone, isResistance ? RESISTANCE_ZONE_COLOR : SUPPORT_ZONE_COLOR);
}