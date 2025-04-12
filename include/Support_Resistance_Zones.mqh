#property copyright "Copyright 2023"
#property strict

// Constants
#define SR_MIN_TOUCHES 1  // Reduced from 2 to 1 for testing
#define ZONE_LOOKBACK 100  // Reduced from 300 to 100 candles
#define MIN_CANDLE_SIZE_MULTIPLIER 5  // Minimum candle size in points

// Colors for zones
color SUPPORT_ZONE_COLOR = clrBlue;    // Changed from Red to Blue
color RESISTANCE_ZONE_COLOR = clrRed;   // Changed from Blue to Red

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

// Add after the existing global variables
bool g_isAboveEMA = false;  // Tracks if price is above EMA

// Function implementations from Strategy2_SR_Engulfing_EA.mq5
// Copy all functions exactly as they are but remove their definitions from the EA

// Replace the existing UpdateAndDrawValidSRZones function with this implementation
void UpdateAndDrawValidSRZones(int lookbackPeriod, int sensitivityPips, double emaValue)
{
    Print("UpdateAndDrawValidSRZones: Starting with lookback=", lookbackPeriod, 
          " sensitivity=", sensitivityPips, " EMA=", emaValue);
    
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    int available = CopyRates(_Symbol, PERIOD_CURRENT, 0, lookbackPeriod, rates);
    
    if (available <= 0)
    {
        Print("UpdateAndDrawValidSRZones: Failed to retrieve candle data. Error: ", GetLastError());
        return;
    }
    
    Print("UpdateAndDrawValidSRZones: Retrieved ", available, " bars of data");
    
    // Log the first few candles for debugging
    for (int i = 0; i < MathMin(5, available); i++)
    {
        PrintFormat("Candle[%d]: Time=%s, Open=%.5f, High=%.5f, Low=%.5f, Close=%.5f",
                    i, TimeToString(rates[i].time), rates[i].open, rates[i].high, rates[i].low, rates[i].close);
    }

    // Process broken zones
    Print("Checking for broken zones...");
    CheckAndRemoveBrokenZones(rates, emaValue);

    // Create and draw valid S/R zones
    CreateAndDrawSRZones(rates, sensitivityPips, emaValue);

    // Log the current state of zones
    LogZoneState();
}

// New function to check for broken zones
void CheckAndRemoveBrokenZones(const MqlRates &rates[], double emaValue)
{
    Print("Checking for broken zones...");

    // Check resistance zones
    for (int i = ArraySize(g_activeResistanceZones) - 1; i >= 0; i--)
    {
        if (IsZoneBroken(g_activeResistanceZones[i], rates, 0))
        {
            Print("Removing broken resistance zone at ", g_activeResistanceZones[i].topBoundary);
            DeleteZoneObjects(g_activeResistanceZones[i]);
            if (!ArrayRemove(g_activeResistanceZones, i, 1))
            {
                Print("Failed to remove resistance zone at index ", i);
            }
        }
    }

    // Check support zones
    for (int i = ArraySize(g_activeSupportZones) - 1; i >= 0; i--)
    {
        if (IsZoneBroken(g_activeSupportZones[i], rates, 0))
        {
            Print("Removing broken support zone at ", g_activeSupportZones[i].bottomBoundary);
            DeleteZoneObjects(g_activeSupportZones[i]);
            if (!ArrayRemove(g_activeSupportZones, i, 1))
            {
                Print("Failed to remove support zone at index ", i);
            }
        }
    }

    // Log the current state of zones
    LogZoneState();
}

// Update DeleteZoneObjects to ensure complete removal
void DeleteZoneObjects(const SRZone &zone)
{
    string topName = StringFormat("SRZone_%d_Top", zone.chartObjectID_Top);
    string bottomName = StringFormat("SRZone_%d_Bottom", zone.chartObjectID_Bottom);

    if (ObjectFind(0, topName) >= 0)
        ObjectDelete(0, topName);
    if (ObjectFind(0, bottomName) >= 0)
        ObjectDelete(0, bottomName);

    ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Draw individual zone lines                                       |
//+------------------------------------------------------------------+
void DrawZoneLines(const SRZone &zone, const color lineColor)
{
    Print("DrawZoneLines: Starting to draw zone. Top=", zone.topBoundary, 
          " Bottom=", zone.bottomBoundary, " Color=", lineColor);
    
    string topName = StringFormat("SRZone_%d_Top", zone.chartObjectID_Top);
    string bottomName = StringFormat("SRZone_%d_Bottom", zone.chartObjectID_Bottom);
    
    // Delete existing objects
    ObjectDelete(0, topName);
    ObjectDelete(0, bottomName);
    
    datetime startTime = iTime(_Symbol, PERIOD_CURRENT, zone.shift);
    datetime endTime = TimeCurrent() + PeriodSeconds(PERIOD_CURRENT) * 100;
    
    // Create top boundary line
    if (!ObjectCreate(0, topName, OBJ_TREND, 0, startTime, zone.topBoundary, 
                      endTime, zone.topBoundary))
    {
        Print("Failed to create top boundary line. Error:", GetLastError());
        return;
    }
    
    // Set top boundary line properties
    ObjectSetInteger(0, topName, OBJPROP_COLOR, lineColor);
    ObjectSetInteger(0, topName, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, topName, OBJPROP_WIDTH, 2);
    ObjectSetInteger(0, topName, OBJPROP_RAY_RIGHT, true);
    
    // Create bottom boundary line
    if (!ObjectCreate(0, bottomName, OBJ_TREND, 0, startTime, zone.bottomBoundary, 
                      endTime, zone.bottomBoundary))
    {
        Print("Failed to create bottom boundary line. Error:", GetLastError());
        ObjectDelete(0, topName); // Clean up if bottom line creation fails
        return;
    }
    
    // Set bottom boundary line properties
    ObjectSetInteger(0, bottomName, OBJPROP_COLOR, lineColor);
    ObjectSetInteger(0, bottomName, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, bottomName, OBJPROP_WIDTH, 2);
    ObjectSetInteger(0, bottomName, OBJPROP_RAY_RIGHT, true);
    Print("Successfully created both boundary lines - Top:", zone.topBoundary, " Bottom:", zone.bottomBoundary);
    ChartRedraw(0);
}
//+------------------------------------------------------------------+
//| Draw zones and validate touches                                  |
//+------------------------------------------------------------------+
void DrawAndValidateZones(const MqlRates &rates[], double sensitivity, double emaValue)
{
    double currentPrice = rates[0].close;

    // Draw and validate resistance zones
    for(int i = 0; i < ArraySize(g_activeResistanceZones); i++)
    {
        // Draw zone lines
        // Validate against current EMA before drawing
        bool isValid = g_activeResistanceZones[i].bottomBoundary > emaValue && 
                       g_activeResistanceZones[i].topBoundary > emaValue;
        color zoneColor = isValid ? clrRed : clrGray;
        DrawZoneLines(g_activeResistanceZones[i], zoneColor);

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
        // Validate against current EMA before drawing
        bool isValid = g_activeSupportZones[i].topBoundary < emaValue && 
                       g_activeSupportZones[i].bottomBoundary < emaValue;
        color zoneColor = isValid ? clrGreen : clrGray;
        DrawZoneLines(g_activeSupportZones[i], zoneColor);

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
//| Add zone if it's valid (EMA position and proximity checks)       |
//+------------------------------------------------------------------+
bool AddZoneIfValid(SRZone &newZone, SRZone &existingZones[], double sensitivity, double emaValue)
{
    // Check if zone already exists
    for (int j = 0; j < ArraySize(existingZones); j++)
    {
        if (MathAbs(newZone.definingClose - existingZones[j].definingClose) < sensitivity)
        {
            Print("Zone already exists: ", newZone.definingClose);
            return false;
        }
    }

    int size = ArraySize(existingZones);
    if (ArrayResize(existingZones, size + 1))
    {
        existingZones[size] = newZone;
        Print("Zone added: ", newZone.definingClose);
        return true;
    }

    Print("Failed to resize zone array");
    return false;
}
// Update IsZoneBroken to be more precise
bool IsZoneBroken(const SRZone &zone, const MqlRates &rates[], int shift)
{
    if (shift >= ArraySize(rates)) return false;

    double candleOpen = rates[shift].open;
    double candleClose = rates[shift].close;

    if (zone.isResistance)
    {
// Resistance is broken if:
// 1. A bullish candle opens above the lower boundary
// Resistance is broken if:
// 1. A bullish candle opens above the lower boundary
        // Resistance is broken if:
        // 1. A bullish candle opens above the lower boundary
        // Resistance is broken if:
        // 1. A bullish candle opens above the lower boundary
        if (candleOpen > zone.bottomBoundary && candleClose > candleOpen)
        {
            Print("Resistance zone broken by bullish candle at ", TimeToString(rates[shift].time));
            return  true;
// 2. A bearish candle closes above the lower boundary
        }
// 2. A bearish candle closes above the lower boundary
        if (candleClose > zone.bottomBoundary && candleClose < candleOpen)
        {
            Print("Resistance zone broken by bearish candle at ", TimeToString(rates[shift].time));
// Support is broken if:
        // 1. A bearish candle opens below the upper boundary
            return true;
// Support is broken if:
        // 1. A bearish candle opens below the upper boundary
        }
    }
// Support is broken if:
        // 1. A bearish candle opens below the upper boundary
    else
    {
// Support is broken if:
        // 1. A bearish candle opens below the upper boundary
        if (candleOpen < zone.topBoundary && candleClose < candleOpen)
        {
            Print("Support zone broken by bearish candle at ", TimeToString(rates[shift].time));
           return true;
        }
// 2. A bullish candle closes below the upper boundary
        if (candleClose < zone.topBoundary && candleClose > candleOpen)
        {
            Print("Support zone broken by bullish candle at ", TimeToString(rates[shift].time));
            return true;
        }
    }

    // Log zone state for debugging
    PrintFormat("Zone not broken: %s zone at [%.5f-%.5f], Candle Open=%.5f, Close=%.5f",
                zone.isResistance ? "Resistance" : "Support",
                zone.bottomBoundary, zone.topBoundary, candleOpen, candleClose);

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
    PrintFormat("HasActiveZoneNearby: Checking price %.5f with sensitivity %.5f", price, sensitivity);

    // Check resistance zones
    for (int i = 0; i < ArraySize(g_activeResistanceZones); i++)
    {
        double zoneClose = g_activeResistanceZones[i].definingClose;
        if (MathAbs(price - zoneClose) <= sensitivity)
        {
            PrintFormat("HasActiveZoneNearby: Price %.5f is near resistance zone at %.5f", price, zoneClose);
            return true;
        }
    }

    // Check support zones
    for (int i = 0; i < ArraySize(g_activeSupportZones); i++)
    {
        double zoneClose = g_activeSupportZones[i].definingClose;
        if (MathAbs(price - zoneClose) <= sensitivity)
        {
            PrintFormat("HasActiveZoneNearby: Price %.5f is near support zone at %.5f", price, zoneClose);
            return true;
        }
    }

    Print("HasActiveZoneNearby: No active zone found near the price.");
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
void CreateAndDrawNewZone(const MqlRates &rates[], int shift, bool isResistance, double sensitivity, double emaValue)
{
    SRZone newZone;
    newZone.definingClose = rates[shift].close;
    newZone.shift = shift;
    newZone.isResistance = isResistance;
    newZone.touchCount = 1;

    if (isResistance)
    {
        newZone.bottomBoundary = MathMin(rates[shift].open, rates[shift].close);
        newZone.topBoundary = rates[shift].high;
        newZone.chartObjectID_Top = TimeCurrent() + shift;
        newZone.chartObjectID_Bottom = TimeCurrent() + shift + 1;
        if (AddZoneIfValid(newZone, g_activeResistanceZones, sensitivity, emaValue))
        {
            Print("Creating resistance zone - Bottom=", newZone.bottomBoundary, 
                  " Top=", newZone.topBoundary);
            DrawZoneLines(newZone, RESISTANCE_ZONE_COLOR);
        }
    }
    else
    {
        newZone.bottomBoundary = MathMin(rates[shift].open, rates[shift].close);
        newZone.topBoundary = MathMax(rates[shift].open, rates[shift].close);
        newZone.chartObjectID_Top = TimeCurrent() + shift;
        newZone.chartObjectID_Bottom = TimeCurrent() + shift + 1;
        if (AddZoneIfValid(newZone, g_activeSupportZones, sensitivity, emaValue))
        {
            Print("Creating support zone - Bottom=", newZone.bottomBoundary, 
                  " Top=", newZone.topBoundary);
            DrawZoneLines(newZone, SUPPORT_ZONE_COLOR);
        }
    }

    // Log the current state of zones
    LogZoneState();
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
//+------------------------------------------------------------------+
//| Check for EMA crossover                                           |
//+------------------------------------------------------------------+
bool UpdateEMACrossoverState(const MqlRates &rates[], double emaValue)
{
    bool previousState = g_isAboveEMA;
    g_isAboveEMA = rates[0].close > emaValue;
    // Return true if there was a crossover
    bool crossover = previousState != g_isAboveEMA;
    if(crossover)
    {
        Print("EMA Crossover detected: Price is now ", g_isAboveEMA ? "above" : "below", " EMA");
    }
    return crossover;
}
// New function to draw debug S/R zones
void DrawDebugSRZones(const MqlRates &rates[], int sensitivityPips, double emaValue)
{
    double sensitivity = sensitivityPips * _Point;

    // Create a support zone for debugging
    double supportPrice = rates[0].low;
    SRZone debugSupportZone;
    debugSupportZone.bottomBoundary = MathMin(rates[0].open, rates[0].close); // Bullish open or bearish close
    debugSupportZone.topBoundary = MathMax(rates[0].open, rates[0].close);   // Bearish open or bullish close
    debugSupportZone.definingClose = rates[0].close;
    debugSupportZone.isResistance = false;
    debugSupportZone.shift = 0;
    debugSupportZone.chartObjectID_Top = TimeCurrent();
    debugSupportZone.chartObjectID_Bottom = TimeCurrent() + 1;
    Print("Debug: Creating support zone - Bottom=", debugSupportZone.bottomBoundary, 
          " Top=", debugSupportZone.topBoundary);
    DrawZoneLines(debugSupportZone, SUPPORT_ZONE_COLOR);

    // Create a resistance zone for debugging
    double resistancePrice = rates[0].high;
    SRZone debugResistanceZone;
    debugResistanceZone.bottomBoundary = MathMin(rates[0].open, rates[0].close);
    debugResistanceZone.topBoundary = resistancePrice;
    debugResistanceZone.definingClose = rates[0].close;
    debugResistanceZone.isResistance = true;
    debugResistanceZone.shift = 0;
    debugResistanceZone.chartObjectID_Top = TimeCurrent();
    debugResistanceZone.chartObjectID_Bottom = TimeCurrent() + 1;
    Print("Debug: Creating resistance zone - Bottom=", debugResistanceZone.bottomBoundary, 
          " Top=", debugResistanceZone.topBoundary);
    DrawZoneLines(debugResistanceZone, RESISTANCE_ZONE_COLOR);
}
// New function to create and draw S/R zones
void CreateAndDrawSRZones(const MqlRates &rates[], int sensitivityPips, double emaValue)
{
    double sensitivity = sensitivityPips * _Point;

    // Process resistance zones
    for (int i = ArraySize(g_activeResistanceZones) - 1; i >= 0; i--)
    {
        SRZone zone = g_activeResistanceZones[i];

        // Check if the zone is broken
        if (IsZoneBroken(zone, rates, 0))
        {
            Print("Invalidating resistance zone at ", zone.topBoundary, " due to break condition.");
            DeleteZoneObjects(zone);
            ArrayRemove(g_activeResistanceZones, i, 1);
            continue;
        }

        // Adjust the bottom boundary upwards if the top boundary is not broken
        if (rates[0].low > zone.bottomBoundary && rates[0].low < zone.topBoundary)
        {
            zone.bottomBoundary = rates[0].low;
            Print("Adjusting resistance zone bottom boundary to ", zone.bottomBoundary);
        }
    }

    // Process support zones
    for (int i = ArraySize(g_activeSupportZones) - 1; i >= 0; i--)
    {
        SRZone zone = g_activeSupportZones[i];

        // Check if the zone is broken
        if (IsZoneBroken(zone, rates, 0))
        {
            Print("Invalidating support zone at ", zone.bottomBoundary, " due to break condition.");
            DeleteZoneObjects(zone);
            ArrayRemove(g_activeSupportZones, i, 1);
            continue;
        }

        // Adjust the top boundary downwards if the bottom boundary is not broken
        if (rates[0].high < zone.topBoundary && rates[0].high > zone.bottomBoundary)
        {
            zone.topBoundary = rates[0].high;
            Print("Adjusting support zone top boundary to ", zone.topBoundary);
        }
    }

    // Create new zones if the current candle is valid
    if (rates[0].close < emaValue)
    {
        SRZone supportZone;
        supportZone.bottomBoundary = rates[0].low;
        supportZone.topBoundary = MathMax(rates[0].open, rates[0].close);
        supportZone.definingClose = rates[0].close;
        supportZone.isResistance = false;
        supportZone.shift = 0;
        supportZone.chartObjectID_Top = TimeCurrent();
        supportZone.chartObjectID_Bottom = TimeCurrent() + 1;

        if (AddZoneIfValid(supportZone, g_activeSupportZones, sensitivity, emaValue))
        {
            Print("Creating support zone - Bottom=", supportZone.bottomBoundary, 
                  " Top=", supportZone.topBoundary);
            DrawZoneLines(supportZone, SUPPORT_ZONE_COLOR);
        }
    }

    if (rates[0].close > emaValue)
    {
        SRZone resistanceZone;
        resistanceZone.bottomBoundary = MathMin(rates[0].open, rates[0].close);
        resistanceZone.topBoundary = rates[0].high;
        resistanceZone.definingClose = rates[0].close;
        resistanceZone.isResistance = true;
        resistanceZone.shift = 0;
        resistanceZone.chartObjectID_Top = TimeCurrent();
        resistanceZone.chartObjectID_Bottom = TimeCurrent() + 1;

        if (AddZoneIfValid(resistanceZone, g_activeResistanceZones, sensitivity, emaValue))
        {
            Print("Creating resistance zone - Bottom=", resistanceZone.bottomBoundary, 
                  " Top=", resistanceZone.topBoundary);
            DrawZoneLines(resistanceZone, RESISTANCE_ZONE_COLOR);
        }
    }
}

// New function to log the current state of zones
void LogZoneState()
{
    Print("Logging current zone state...");

    Print("Active Resistance Zones:");
    for (int i = 0; i < ArraySize(g_activeResistanceZones); i++)
    {
        PrintFormat("Zone %d: Top=%.5f, Bottom=%.5f, Touches=%d",
                    i, g_activeResistanceZones[i].topBoundary, g_activeResistanceZones[i].bottomBoundary,
                    g_activeResistanceZones[i].touchCount);
    }

    Print("Active Support Zones:");
    for (int i = 0; i < ArraySize(g_activeSupportZones); i++)
    {
        PrintFormat("Zone %d: Top=%.5f, Bottom=%.5f, Touches=%d",
                    i, g_activeSupportZones[i].topBoundary, g_activeSupportZones[i].bottomBoundary,
                    g_activeSupportZones[i].touchCount);
    }
}

