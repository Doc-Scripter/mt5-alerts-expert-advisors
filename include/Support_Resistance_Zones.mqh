#property copyright "Copyright 2023"
#property strict

// Constants
#define SR_MIN_TOUCHES 1  // Reduced from 2 to 1 for testing
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
    Print("UpdateAndDrawValidSRZones: Starting...");
    
    // Clear all existing zones first
    DeleteAllSRZoneLines();
    ArrayFree(g_activeSupportZones);
    ArrayFree(g_activeResistanceZones);
    g_nearestSupportZoneIndex = -1;
    g_nearestResistanceZoneIndex = -1;
    
    // Get price data
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    int copied = CopyRates(_Symbol, PERIOD_CURRENT, 0, ZONE_LOOKBACK, rates);
    if(copied < ZONE_LOOKBACK)
    {
        Print("Failed to copy rates. Error: ", GetLastError());
        return;
    }
    
    Print("UpdateAndDrawValidSRZones: Copied ", copied, " bars");
    
    double sensitivity = sensitivityPips * _Point * 10;
    
    // Look for initial zones from most recent to oldest
    int resistanceCount = 0;
    int supportCount = 0;
    
    for(int i = 1; i < ZONE_LOOKBACK - 1; i++)
    {
        bool isBullish = rates[i].close > rates[i].open;
        
        // Check for swing high (potential resistance)
        if(isBullish && rates[i].high > rates[i+1].high && rates[i].high > rates[i-1].high)
        {
            if(!HasActiveZoneNearby(rates[i].high, sensitivity))
            {
                SRZone newZone;
                newZone.definingClose = rates[i].close;
                newZone.topBoundary = rates[i].high;
                newZone.bottomBoundary = rates[i].high - sensitivity;
                newZone.isResistance = true;
                newZone.touchCount = 1;
                newZone.shift = i;
                newZone.chartObjectID_Top = (long)TimeCurrent() + i;
                newZone.chartObjectID_Bottom = (long)TimeCurrent() + i + 1;
                
                if(AddZoneIfValid(newZone, g_activeResistanceZones, sensitivity))
                {
                    resistanceCount++;
                    Print("Created resistance zone at price ", newZone.topBoundary);
                }
            }
        }
        
        // Check for swing low (potential support)
        if(!isBullish && rates[i].low < rates[i+1].low && rates[i].low < rates[i-1].low)
        {
            if(!HasActiveZoneNearby(rates[i].low, sensitivity))
            {
                SRZone newZone;
                newZone.definingClose = rates[i].close;
                newZone.topBoundary = rates[i].low + sensitivity;
                newZone.bottomBoundary = rates[i].low;
                newZone.isResistance = false;
                newZone.touchCount = 1;
                newZone.shift = i;
                newZone.chartObjectID_Top = (long)TimeCurrent() + i;
                newZone.chartObjectID_Bottom = (long)TimeCurrent() + i + 1;
                
                if(AddZoneIfValid(newZone, g_activeSupportZones, sensitivity))
                {
                    supportCount++;
                    Print("Created support zone at price ", newZone.bottomBoundary);
                }
            }
        }
    }
    
    Print("UpdateAndDrawValidSRZones: Found ", resistanceCount, " resistance zones and ", supportCount, " support zones");
    
    // Validate zones and draw them
    CountAndValidateZoneTouches(rates, sensitivity, lookbackPeriod);
    DrawAndValidateZones(rates, sensitivity);
    
    Print("UpdateAndDrawValidSRZones: Final zones - Resistance: ", ArraySize(g_activeResistanceZones),
          ", Support: ", ArraySize(g_activeSupportZones));
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
//| Draw individual zone lines                                       |
//+------------------------------------------------------------------+
void DrawZoneLines(const SRZone &zone, const color lineColor)
{
    string topName = StringFormat("SRZone_%d_Top", zone.chartObjectID_Top);
    string bottomName = StringFormat("SRZone_%d_Bottom", zone.chartObjectID_Bottom);
    
    Print("Attempting to draw zone lines: ", topName, " and ", bottomName);
    
    // Delete any existing lines first (regardless of whether they exist)
    ObjectDelete(0, topName);
    ObjectDelete(0, bottomName);
    
    datetime zoneTime = iTime(_Symbol, PERIOD_CURRENT, zone.shift);
    datetime currentTime = TimeCurrent();
    
    Print("Creating zone lines from ", TimeToString(zoneTime), " to ", TimeToString(currentTime));
    Print("Top boundary: ", zone.topBoundary, " Bottom boundary: ", zone.bottomBoundary);
    
    if(!ObjectCreate(0, topName, OBJ_TREND, 0, zoneTime, zone.topBoundary, currentTime, zone.topBoundary))
    {
        Print("Failed to create top boundary line. Error: ", GetLastError());
        Print("Attempted coordinates: ", TimeToString(zoneTime), " ", zone.topBoundary, " to ", 
              TimeToString(currentTime), " ", zone.topBoundary);
        return;
    }
    
    if(!ObjectCreate(0, bottomName, OBJ_TREND, 0, zoneTime, zone.bottomBoundary, currentTime, zone.bottomBoundary))
    {
        Print("Failed to create bottom boundary line. Error: ", GetLastError());
        Print("Attempted coordinates: ", TimeToString(zoneTime), " ", zone.bottomBoundary, " to ", 
              TimeToString(currentTime), " ", zone.bottomBoundary);
        ObjectDelete(0, topName);  // Clean up top line if bottom line fails
        return;
    }
    
    // Set common properties for both lines
    color zoneColor = zone.isResistance ? RESISTANCE_ZONE_COLOR : SUPPORT_ZONE_COLOR;
    
    // Set properties for top line
    ObjectSetInteger(0, topName, OBJPROP_COLOR, zoneColor);
    ObjectSetInteger(0, topName, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, topName, OBJPROP_WIDTH, 1);
    ObjectSetInteger(0, topName, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, topName, OBJPROP_HIDDEN, true);
    ObjectSetInteger(0, topName, OBJPROP_RAY_RIGHT, true);
    
    // Set properties for bottom line
    ObjectSetInteger(0, bottomName, OBJPROP_COLOR, zoneColor);
    ObjectSetInteger(0, bottomName, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, bottomName, OBJPROP_WIDTH, 1);
    ObjectSetInteger(0, bottomName, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, bottomName, OBJPROP_HIDDEN, true);
    ObjectSetInteger(0, bottomName, OBJPROP_RAY_RIGHT, true);
}

//+------------------------------------------------------------------+
//| Draw zones and validate touches                                  |
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
      g_activeResistanceZones[i].touchCount = CountTouches(rates, g_activeResistanceZones[i], sensitivity, ZONE_LOOKBACK);
      
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
   
   // Draw and validate support zones
   for(int i = 0; i < ArraySize(g_activeSupportZones); i++)
   {
      // Draw zone lines
      DrawZoneLines(g_activeSupportZones[i], clrGreen);
      
      // Count touches
      g_activeSupportZones[i].touchCount = CountTouches(rates, g_activeSupportZones[i], sensitivity, ZONE_LOOKBACK);
      
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
//| Add zone if it's valid (not too close to existing zones)         |
//+------------------------------------------------------------------+
bool AddZoneIfValid(SRZone &newZone, SRZone &existingZones[], double sensitivity)
{
    // Check if zone already exists
    for(int j = 0; j < ArraySize(existingZones); j++)
    {
        if(MathAbs(newZone.definingClose - existingZones[j].definingClose) < sensitivity)
            return false;
    }
    
    int size = ArraySize(existingZones);
    if(ArrayResize(existingZones, size + 1))
    {
        existingZones[size] = newZone;
        return true;
    }
    
    Print("Failed to resize zone array");
    return false;
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
        // Resistance broken by a strong bullish move
        if(isBullish && candleClose > zone.topBoundary)
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
            
            AddZoneIfValid(newZone, g_activeResistanceZones, _Point * 10);
            return true;
        }
    }
    else
    {
        // Support broken by a strong bearish move
        if(!isBullish && candleClose < zone.bottomBoundary)
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
            
            AddZoneIfValid(newZone, g_activeSupportZones, _Point * 10);
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Count touches for a zone                                         |
//+------------------------------------------------------------------+
int CountTouches(const MqlRates &rates[], const SRZone &zone, double sensitivity, int lookbackPeriod = ZONE_LOOKBACK)
{
   int touches = 0;
   int barsToCheck = MathMin(lookbackPeriod, ArraySize(rates));
   
   for(int j = 0; j < barsToCheck; j++)
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
//| Delete all S/R zone lines                                        |
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
//| Check if there's an active zone near the given price             |
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
//| Check if a new zone is valid at the given position               |
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
//| Create and draw a new zone                                       |
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

// Add new function to count and validate zone touches
void CountAndValidateZoneTouches(const MqlRates &rates[], double sensitivity, int lookbackPeriod)
{
    // Process resistance zones
    for(int i = ArraySize(g_activeResistanceZones) - 1; i >= 0; i--)
    {
        g_activeResistanceZones[i].touchCount = CountTouches(rates, g_activeResistanceZones[i], sensitivity, lookbackPeriod);
        if(g_activeResistanceZones[i].touchCount < SR_MIN_TOUCHES)
        {
            Print("Removing resistance zone at ", g_activeResistanceZones[i].topBoundary, 
                  " - only ", g_activeResistanceZones[i].touchCount, " touches");
            ArrayRemove(g_activeResistanceZones, i, 1);
            continue;
        }
        else
        {
            Print("Keeping resistance zone at ", g_activeResistanceZones[i].topBoundary,
                  " - ", g_activeResistanceZones[i].touchCount, " touches");
        }
    }
    
    // Process support zones
    for(int i = ArraySize(g_activeSupportZones) - 1; i >= 0; i--)
    {
        g_activeSupportZones[i].touchCount = CountTouches(rates, g_activeSupportZones[i], sensitivity, lookbackPeriod);
        if(g_activeSupportZones[i].touchCount < SR_MIN_TOUCHES)
        {
            Print("Removing support zone at ", g_activeSupportZones[i].bottomBoundary,
                  " - only ", g_activeSupportZones[i].touchCount, " touches");
            ArrayRemove(g_activeSupportZones, i, 1);
            continue;
        }
        else
        {
            Print("Keeping support zone at ", g_activeSupportZones[i].bottomBoundary,
                  " - ", g_activeSupportZones[i].touchCount, " touches");
        }
    }
}
