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

// Variables for engulfing pattern detection
double g_highestBullishOpenNearResistance = 0;
double g_highestBearishCloseNearResistance = 0;
double g_lowestBullishCloseNearSupport = 0;
double g_lowestBearishOpenNearSupport = 0;

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

// Function to check for broken zones
// Updated function to check for broken zones using completed candles
void CheckAndRemoveBrokenZones(const MqlRates &rates[], double emaValue)
{
    Print("Checking for broken zones using completed candles...");
    
    // Make sure we have enough data
    if (ArraySize(rates) < 2)
    {
        Print("CheckAndRemoveBrokenZones: Not enough candle data to check for broken zones");
        return;
    }

    // Check resistance zones
    for (int i = ArraySize(g_activeResistanceZones) - 1; i >= 0; i--)
    {
        // Use shift 1 (last completed candle) for zone breaking check
        if (IsZoneBroken(g_activeResistanceZones[i], rates, 1))
        {
            Print("Removing broken resistance zone at ", g_activeResistanceZones[i].topBoundary);
            DeleteZoneObjects(g_activeResistanceZones[i]);
            if (ArrayRemove(g_activeResistanceZones, i, 1))
            {
                Print("Successfully removed resistance zone at index ", i);
            }
            else
            {
                Print("Failed to remove resistance zone at index ", i);
            }
        }
    }

    // Check support zones
    for (int i = ArraySize(g_activeSupportZones) - 1; i >= 0; i--)
    {
        // Use shift 1 (last completed candle) for zone breaking check
        if (IsZoneBroken(g_activeSupportZones[i], rates, 1))
        {
            Print("Removing broken support zone at ", g_activeSupportZones[i].bottomBoundary);
            DeleteZoneObjects(g_activeSupportZones[i]);
            if (ArrayRemove(g_activeSupportZones, i, 1))
            {
                Print("Successfully removed support zone at index ", i);
            }
            else
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
    
    // Track highest and lowest points near zones for engulfing candle strategy
    static double highestBullishOpenNearResistance = 0;
    static double highestBearishCloseNearResistance = 0;
    static double lowestBullishCloseNearSupport = 0;
    static double lowestBearishOpenNearSupport = 0;
    
    // Reset tracking variables if needed
    if (rates[0].time > TimeCurrent() - PeriodSeconds(PERIOD_CURRENT))
    {
        highestBullishOpenNearResistance = 0;
        highestBearishCloseNearResistance = 0;
        lowestBullishCloseNearSupport = 0;
        lowestBearishOpenNearSupport = 0;
    }

    // Draw resistance zones - always use red color for resistance (top boundary)
    for(int i = 0; i < ArraySize(g_activeResistanceZones); i++)
    {
        // Draw zone lines with red color for resistance
        DrawZoneLines(g_activeResistanceZones[i], RESISTANCE_ZONE_COLOR);

        // Update nearest resistance
        if(g_activeResistanceZones[i].bottomBoundary > currentPrice)
        {
            if(g_nearestResistanceZoneIndex == -1 || 
               g_activeResistanceZones[i].bottomBoundary < g_activeResistanceZones[g_nearestResistanceZoneIndex].bottomBoundary)
            {
                g_nearestResistanceZoneIndex = i;
            }
        }
        
        // Track highest bullish open and bearish close near resistance for engulfing pattern
        double zoneProximity = sensitivity * 5; // Wider range for tracking
        
        // Check if current candle is near resistance zone
        if (MathAbs(rates[0].high - g_activeResistanceZones[i].bottomBoundary) < zoneProximity)
        {
            // For bullish candles, track the open
            if (rates[0].close > rates[0].open) // Bullish candle
            {
                if (rates[0].open > highestBullishOpenNearResistance)
                {
                    highestBullishOpenNearResistance = rates[0].open;
                    Print("Updated highest bullish open near resistance: ", highestBullishOpenNearResistance);
                }
            }
            // For bearish candles, track the close
            else if (rates[0].close < rates[0].open) // Bearish candle
            {
                if (rates[0].close > highestBearishCloseNearResistance)
                {
                    highestBearishCloseNearResistance = rates[0].close;
                    Print("Updated highest bearish close near resistance: ", highestBearishCloseNearResistance);
                }
            }
        }
    }

    // Draw support zones - always use blue color for support (bottom boundary)
    for(int i = 0; i < ArraySize(g_activeSupportZones); i++)
    {
        // Draw zone lines with blue color for support
        DrawZoneLines(g_activeSupportZones[i], SUPPORT_ZONE_COLOR);

        // Update nearest support
        if(g_activeSupportZones[i].topBoundary < currentPrice)
        {
            if(g_nearestSupportZoneIndex == -1 || 
               g_activeSupportZones[i].topBoundary > g_activeSupportZones[g_nearestSupportZoneIndex].topBoundary)
            {
                g_nearestSupportZoneIndex = i;
            }
        }
        
        // Track lowest bullish close and bearish open near support for engulfing pattern
        double zoneProximity = sensitivity * 5; // Wider range for tracking
        
        // Check if current candle is near support zone
        if (MathAbs(rates[0].low - g_activeSupportZones[i].topBoundary) < zoneProximity)
        {
            // For bullish candles, track the close
            if (rates[0].close > rates[0].open) // Bullish candle
            {
                if (lowestBullishCloseNearSupport == 0 || rates[0].close < lowestBullishCloseNearSupport)
                {
                    lowestBullishCloseNearSupport = rates[0].close;
                    Print("Updated lowest bullish close near support: ", lowestBullishCloseNearSupport);
                }
            }
            // For bearish candles, track the open
            else if (rates[0].close < rates[0].open) // Bearish candle
            {
                if (lowestBearishOpenNearSupport == 0 || rates[0].open < lowestBearishOpenNearSupport)
                {
                    lowestBearishOpenNearSupport = rates[0].open;
                    Print("Updated lowest bearish open near support: ", lowestBearishOpenNearSupport);
                }
            }
        }
    }
    
    // Log the tracking values for debugging
    if (highestBullishOpenNearResistance > 0 || highestBearishCloseNearResistance > 0 ||
        lowestBullishCloseNearSupport > 0 || lowestBearishOpenNearSupport > 0)
    {
        PrintFormat("Engulfing pattern tracking - Resistance: Bullish Open=%.5f, Bearish Close=%.5f | Support: Bullish Close=%.5f, Bearish Open=%.5f",
                   highestBullishOpenNearResistance, highestBearishCloseNearResistance,
                   lowestBullishCloseNearSupport, lowestBearishOpenNearSupport);
    }
}
//+------------------------------------------------------------------+
//| Add zone if it's valid (EMA position and proximity checks)       |
//+------------------------------------------------------------------+
bool AddZoneIfValid(SRZone &newZone, SRZone &existingZones[], double sensitivity, double emaValue)
{
    PrintFormat("Attempting to add zone: Top=%.5f, Bottom=%.5f, Close=%.5f",
                newZone.topBoundary, newZone.bottomBoundary, newZone.definingClose);

    // Check if a similar zone already exists
    for (int j = 0; j < ArraySize(existingZones); j++)
    {
        // Check both proximity (sensitivity) and time of creation
        if (MathAbs(newZone.definingClose - existingZones[j].definingClose) < sensitivity &&
            newZone.shift == existingZones[j].shift) // Ensure the shift (time) is different
        {
            Print("Zone already exists: Close=", newZone.definingClose, " Time Shift=", newZone.shift);
            return false;
        }
    }

    // Add the new zone if valid
    int size = ArraySize(existingZones);
    if (ArrayResize(existingZones, size + 1))
    {
        existingZones[size] = newZone;
        Print("Zone added: Close=", newZone.definingClose, " Time Shift=", newZone.shift);
        return true;
    }

    Print("Failed to resize zone array");
    return false;
}
// Update IsZoneBroken to use completed candles and create new zones from breaking candles
bool IsZoneBroken(const SRZone &zone, const MqlRates &rates[], int shift)
{
    // Use shift 1 by default if not specified (the last completed candle)
    if (shift == 0) shift = 1;
    
    // Safety check
    if (shift >= ArraySize(rates)) 
    {
        Print("IsZoneBroken: Invalid shift value or insufficient data");
        return false;
    }

    double candleOpen = rates[shift].open;
    double candleClose = rates[shift].close;
    double candleHigh = rates[shift].high;
    double candleLow = rates[shift].low;
    bool isBullish = candleClose > candleOpen;

    PrintFormat("IsZoneBroken: Checking %s zone [%.5f-%.5f] against completed candle at %s (O=%.5f, H=%.5f, L=%.5f, C=%.5f)",
                zone.isResistance ? "Resistance" : "Support",
                zone.bottomBoundary, zone.topBoundary,
                TimeToString(rates[shift].time), candleOpen, candleHigh, candleLow, candleClose);
    
    if (zone.isResistance)
    {
        // Resistance is broken if:
        
        // 1. A candle closes significantly above the zone
        if (candleClose > zone.topBoundary)
        {
            PrintFormat("Resistance zone broken by candle closing above zone at %s (Close=%.5f > Top=%.5f)", 
                        TimeToString(rates[shift].time), candleClose, zone.topBoundary);
            
            // Create a new resistance zone using the breaking candle
            SRZone newZone;
            newZone.isResistance = true;
            
            // For resistance zones, use the breaking candle to define new boundaries
            if (isBullish) // Bullish candle
            {
                newZone.bottomBoundary = candleOpen;
                newZone.topBoundary = candleHigh;
            }
            else // Bearish candle
            {
                newZone.bottomBoundary = candleClose;
                newZone.topBoundary = candleHigh;
            }
            
            newZone.definingClose = candleClose;
            newZone.shift = shift;
            newZone.chartObjectID_Top = TimeCurrent() + shift;
            newZone.chartObjectID_Bottom = TimeCurrent() + shift + 1;
            
            // Add the new zone
            if (AddZoneIfValid(newZone, g_activeResistanceZones, 0.0001, 0))
            {
                PrintFormat("Created new resistance zone from breaking candle - Top=%.5f, Bottom=%.5f", 
                           newZone.topBoundary, newZone.bottomBoundary);
                DrawZoneLines(newZone, RESISTANCE_ZONE_COLOR);
            }
            
            return true;
        }
        
        // 2. A bearish candle opens above the zone and closes within or below
        if (!isBullish && candleOpen > zone.topBoundary && candleClose <= zone.topBoundary)
        {
            PrintFormat("Resistance zone broken by bearish candle opening above zone at %s (Open=%.5f > Top=%.5f)", 
                        TimeToString(rates[shift].time), candleOpen, zone.topBoundary);
            return true;
        }
        
        // 3. The entire candle body is above the zone
        if (MathMin(candleOpen, candleClose) > zone.topBoundary)
        {
            PrintFormat("Resistance zone broken by candle body completely above zone at %s (Min(O,C)=%.5f > Top=%.5f)", 
                        TimeToString(rates[shift].time), MathMin(candleOpen, candleClose), zone.topBoundary);
            return true;
        }
    }
    else // Support zone
    {
        // Support is broken if:
        
        // 1. A candle closes significantly below the zone
        if (candleClose < zone.bottomBoundary)
        {
            PrintFormat("Support zone broken by candle closing below zone at %s (Close=%.5f < Bottom=%.5f)", 
                        TimeToString(rates[shift].time), candleClose, zone.bottomBoundary);
            
            // Create a new support zone using the breaking candle
            SRZone newZone;
            newZone.isResistance = false;
            
            // For support zones, use the breaking candle to define new boundaries
            if (isBullish) // Bullish candle
            {
                newZone.bottomBoundary = candleLow;
                newZone.topBoundary = candleClose;
            }
            else // Bearish candle
            {
                newZone.bottomBoundary = candleLow;
                newZone.topBoundary = candleOpen;
            }
            
            newZone.definingClose = candleClose;
            newZone.shift = shift;
            newZone.chartObjectID_Top = TimeCurrent() + shift;
            newZone.chartObjectID_Bottom = TimeCurrent() + shift + 1;
            
            // Add the new zone
            if (AddZoneIfValid(newZone, g_activeSupportZones, 0.0001, 0))
            {
                PrintFormat("Created new support zone from breaking candle - Top=%.5f, Bottom=%.5f", 
                           newZone.topBoundary, newZone.bottomBoundary);
                DrawZoneLines(newZone, SUPPORT_ZONE_COLOR);
            }
            
            return true;
        }
        
        // 2. A bullish candle opens below the zone and closes within or above
        if (isBullish && candleOpen < zone.bottomBoundary && candleClose >= zone.bottomBoundary)
        {
            PrintFormat("Support zone broken by bullish candle opening below zone at %s (Open=%.5f < Bottom=%.5f)", 
                        TimeToString(rates[shift].time), candleOpen, zone.bottomBoundary);
            return true;
        }
        
        // 3. The entire candle body is below the zone
        if (MathMax(candleOpen, candleClose) < zone.bottomBoundary)
        {
            PrintFormat("Support zone broken by candle body completely below zone at %s (Max(O,C)=%.5f < Bottom=%.5f)", 
                        TimeToString(rates[shift].time), MathMax(candleOpen, candleClose), zone.bottomBoundary);
            return true;
        }
    }

    // Zone not broken
    PrintFormat("Zone not broken: %s zone at [%.5f-%.5f], Candle O=%.5f, C=%.5f",
                zone.isResistance ? "Resistance" : "Support",
                zone.bottomBoundary, zone.topBoundary, 
                candleOpen, candleClose);

    return false;
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
void CreateAndDrawNewZone(const MqlRates &rates[], int shift, bool isResistance)
{
    // Validate input
    if (shift >= ArraySize(rates))
    {
        Print("Invalid shift value in CreateAndDrawNewZone");
        return;
    }

    // Log the candle data for debugging
    PrintFormat("Processing Candle: Time=%s, Open=%.5f, Close=%.5f, High=%.5f, Low=%.5f",
                TimeToString(rates[shift].time), rates[shift].open, rates[shift].close, rates[shift].high, rates[shift].low);

    // Handle doji candles (open == close)
    if (rates[shift].open == rates[shift].close)
    {
        Print("Doji candle detected. Skipping zone creation.");
        return;
    }

    SRZone newZone = {0}; // Initialize all members to 0/false

    if (isResistance)
    {
        // For resistance zones
        if (rates[shift].close > rates[shift].open) // Bullish candle
        {
            newZone.bottomBoundary = rates[shift].open;
            newZone.topBoundary = rates[shift].close;
        }
        else // Bearish candle
        {
            newZone.bottomBoundary = rates[shift].close;
            newZone.topBoundary = rates[shift].open;
        }
    }
    else
    {
        // For support zones
        if (rates[shift].close > rates[shift].open) // Bullish candle
        {
            newZone.bottomBoundary = rates[shift].open;
            newZone.topBoundary = rates[shift].close;
        }
        else // Bearish candle
        {
            newZone.bottomBoundary = rates[shift].close;
            newZone.topBoundary = rates[shift].open;
        }
    }

    // Validate zone boundaries
    if (newZone.topBoundary <= newZone.bottomBoundary)
    {
        Print("Invalid zone boundaries detected: Top=", newZone.topBoundary, 
              " Bottom=", newZone.bottomBoundary);
        return;
    }

    // Store the defining price
    newZone.definingClose = rates[shift].close;
    newZone.isResistance = isResistance;
    newZone.shift = shift;

    // Generate unique IDs
    datetime currentTime = TimeCurrent();
    newZone.chartObjectID_Top = (long)currentTime + (shift * 2);
    newZone.chartObjectID_Bottom = (long)currentTime + (shift * 2) + 1;

    // Add zone with validation
    if (isResistance)
    {
        if (AddZoneIfValid(newZone, g_activeResistanceZones, 0.0001, 0))
        {
            Print("Created resistance zone - Top: ", newZone.topBoundary, 
                  " Bottom: ", newZone.bottomBoundary,
                  " Close: ", newZone.definingClose);
            DrawZoneLines(newZone, RESISTANCE_ZONE_COLOR);
        }
    }
    else
    {
        if (AddZoneIfValid(newZone, g_activeSupportZones, 0.0001, 0))
        {
            Print("Created support zone - Top: ", newZone.topBoundary,
                  " Bottom: ", newZone.bottomBoundary,
                  " Close: ", newZone.definingClose);
            DrawZoneLines(newZone, SUPPORT_ZONE_COLOR);
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
// Function to create and draw S/R zones
void CreateAndDrawSRZones(const MqlRates &rates[], int sensitivityPips, double emaValue)
{
    double sensitivity = sensitivityPips * _Point;
    double minZoneHeight = MIN_CANDLE_SIZE_MULTIPLIER * _Point; // Minimum height for a zone

    Print("CreateAndDrawSRZones: Starting with sensitivity=", sensitivityPips, " EMA=", emaValue);

    // Process resistance zones
    for (int i = ArraySize(g_activeResistanceZones) - 1; i >= 0; i--)
    {
        SRZone zone = g_activeResistanceZones[i];

        // Check if the zone is broken using completed candle
        if (ArraySize(rates) >= 2 && IsZoneBroken(zone, rates, 1))
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

        // Check if the zone is broken using completed candle
        if (ArraySize(rates) >= 2 && IsZoneBroken(zone, rates, 1))
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
        // Create support zone
        SRZone supportZone;
        
        // For support zones, bottom should be lower than top
        supportZone.bottomBoundary = rates[0].low;
        supportZone.topBoundary = MathMin(rates[0].open, rates[0].close); // Use the lower of open/close as top
        
        // Ensure minimum zone height
        if (supportZone.topBoundary - supportZone.bottomBoundary < minZoneHeight)
        {
            supportZone.bottomBoundary = supportZone.topBoundary - minZoneHeight;
        }
        
        supportZone.definingClose = rates[0].close;
        supportZone.isResistance = false;
        supportZone.shift = 0;
        supportZone.chartObjectID_Top = TimeCurrent();
        supportZone.chartObjectID_Bottom = TimeCurrent() + 1;

        if (AddZoneIfValid(supportZone, g_activeSupportZones, sensitivity, emaValue))
        {
            Print("Creating support zone - Bottom=", supportZone.bottomBoundary, 
                  " Top=", supportZone.topBoundary, 
                  " Height=", (supportZone.topBoundary - supportZone.bottomBoundary));
            DrawZoneLines(supportZone, SUPPORT_ZONE_COLOR);
        }
    }

    if (rates[0].close > emaValue)
    {
        // Create resistance zone
        SRZone resistanceZone;
        
        // For resistance zones, top should be higher than bottom
        resistanceZone.bottomBoundary = MathMax(rates[0].open, rates[0].close); // Use the higher of open/close as bottom
        resistanceZone.topBoundary = rates[0].high;
        
        // Ensure minimum zone height
        if (resistanceZone.topBoundary - resistanceZone.bottomBoundary < minZoneHeight)
        {
            resistanceZone.topBoundary = resistanceZone.bottomBoundary + minZoneHeight;
        }
        
        resistanceZone.definingClose = rates[0].close;
        resistanceZone.isResistance = true;
        resistanceZone.shift = 0;
        resistanceZone.chartObjectID_Top = TimeCurrent();
        resistanceZone.chartObjectID_Bottom = TimeCurrent() + 1;

        if (AddZoneIfValid(resistanceZone, g_activeResistanceZones, sensitivity, emaValue))
        {
            Print("Creating resistance zone - Bottom=", resistanceZone.bottomBoundary, 
                  " Top=", resistanceZone.topBoundary,
                  " Height=", (resistanceZone.topBoundary - resistanceZone.bottomBoundary));
            DrawZoneLines(resistanceZone, RESISTANCE_ZONE_COLOR);
        }
    }
    
    // Log the current state of zones after creation
    LogZoneState();
}

// New function to log the current state of zones
void LogZoneState()
{
    Print("Logging current zone state...");

    Print("Active Resistance Zones:");
    for (int i = 0; i < ArraySize(g_activeResistanceZones); i++)
    {
        PrintFormat("Zone %d: Top=%.5f, Bottom=%.5f",
                    i, g_activeResistanceZones[i].topBoundary, g_activeResistanceZones[i].bottomBoundary);
    }

    Print("Active Support Zones:");
    for (int i = 0; i < ArraySize(g_activeSupportZones); i++)
    {
        PrintFormat("Zone %d: Top=%.5f, Bottom=%.5f",
                    i, g_activeSupportZones[i].topBoundary, g_activeSupportZones[i].bottomBoundary);
    }
}

