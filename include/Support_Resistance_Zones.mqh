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
}

// New function to check for broken zones
void CheckAndRemoveBrokenZones(const MqlRates &rates[], double emaValue)
{
    // Check resistance zones
    for (int i = ArraySize(g_activeResistanceZones) - 1; i >= 0; i--)
    {
        if (IsZoneBroken(g_activeResistanceZones[i], rates, 0, emaValue))
        {
            // Remove the zone's visual elements
            DeleteZoneObjects(g_activeResistanceZones[i]);
            // Remove from active zones array
            ArrayRemove(g_activeResistanceZones, i, 1);
        }
    }

    // Check support zones
    for (int i = ArraySize(g_activeSupportZones) - 1; i >= 0; i--)
    {
        if (IsZoneBroken(g_activeSupportZones[i], rates, 0, emaValue))
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
    Print("DrawZoneLines: Starting to draw zone. Top=", zone.topBoundary, 
          " Bottom=", zone.bottomBoundary, " Color=", lineColor);
    
    string topName = StringFormat("SRZone_%d_Top", zone.chartObjectID_Top);
    string bottomName = StringFormat("SRZone_%d_Bottom", zone.chartObjectID_Bottom);
    string fillName = StringFormat("SRZone_%d_Fill", zone.chartObjectID_Top);
    
    // Delete existing objects
    ObjectDelete(0, topName);
    ObjectDelete(0, bottomName);
    ObjectDelete(0, fillName);
    
    datetime startTime = iTime(_Symbol, PERIOD_CURRENT, zone.shift);
    datetime endTime = TimeCurrent() + PeriodSeconds(PERIOD_CURRENT) * 100;
    
    // Create zone lines with fill
    if (!ObjectCreate(0, fillName, OBJ_RECTANGLE, 0, startTime, zone.topBoundary, 
                      endTime, zone.bottomBoundary))
    {
        Print("Failed to create zone fill. Error:", GetLastError());
        return;
    }
    
    // Set fill properties
    ObjectSetInteger(0, fillName, OBJPROP_COLOR, lineColor);
    ObjectSetInteger(0, fillName, OBJPROP_FILL, true);
    ObjectSetInteger(0, fillName, OBJPROP_BACK, true);
    ObjectSetInteger(0, fillName, OBJPROP_WIDTH, 1);
    ObjectSetInteger(0, fillName, OBJPROP_SELECTABLE, false);
    
    // Create border lines
    if (!ObjectCreate(0, topName, OBJ_TREND, 0, startTime, zone.topBoundary, 
                      endTime, zone.topBoundary))
    {
        Print("Failed to create top line. Error:", GetLastError());
        return;
    }
    
    if (!ObjectCreate(0, bottomName, OBJ_TREND, 0, startTime, zone.bottomBoundary, 
                      endTime, zone.bottomBoundary))
    {
        Print("Failed to create bottom line. Error:", GetLastError());
        return;
    }
    
    // Set line properties
    ObjectSetInteger(0, topName, OBJPROP_COLOR, lineColor);
    ObjectSetInteger(0, topName, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, topName, OBJPROP_WIDTH, 2);
    ObjectSetInteger(0, topName, OBJPROP_RAY_RIGHT, true);
    
    ObjectSetInteger(0, bottomName, OBJPROP_COLOR, lineColor);
    ObjectSetInteger(0, bottomName, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, bottomName, OBJPROP_WIDTH, 2);
    ObjectSetInteger(0, bottomName, OBJPROP_RAY_RIGHT, true);
    
    Print("Successfully created zone lines and fill");
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
    // Validate EMA position
    // Validate using the defining candle's open/close
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    CopyRates(_Symbol, PERIOD_CURRENT, newZone.shift, 1, rates);
    
    bool isValidEMA = newZone.isResistance 
        ? (rates[0].open > emaValue && rates[0].close > emaValue)
        : (rates[0].open < emaValue && rates[0].close < emaValue);
        
    if(!isValidEMA) {
        PrintFormat("Discarding %s zone - Boundaries [%.5f-%.5f] vs EMA %.5f",
                   newZone.isResistance ? "resistance" : "support",
                   newZone.bottomBoundary, newZone.topBoundary, emaValue);
        return false;
    }
    
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
bool IsZoneBroken(const SRZone &zone, const MqlRates &rates[], int shift, double emaValue)
{
    if (shift >= ArraySize(rates)) return false;

    double candleOpen = rates[shift].open;
    double candleClose = rates[shift].close;

    if (zone.isResistance)
    {
        // Resistance is broken if both open and close are above the top boundary
        if (candleOpen > zone.topBoundary && candleClose > zone.topBoundary)
        {
            Print("Resistance zone broken at ", TimeToString(rates[shift].time));
            return true;
        }
    }
    else
    {
        // Support is broken if both open and close are below the bottom boundary
        if (candleOpen < zone.bottomBoundary && candleClose < zone.bottomBoundary)
        {
            Print("Support zone broken at ", TimeToString(rates[shift].time));
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
void CreateAndDrawNewZone(const MqlRates &rates[], int shift, bool isResistance, double sensitivity, double emaValue)
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
        
        AddZoneIfValid(newZone, g_activeResistanceZones, sensitivity, emaValue);
    }
    else
    {
        newZone.bottomBoundary = rates[shift].low;
        newZone.topBoundary = MathMax(rates[shift].open, rates[shift].close);
        newZone.chartObjectID_Top = TimeCurrent() + shift;
        newZone.chartObjectID_Bottom = TimeCurrent() + shift + 1;
        
        AddZoneIfValid(newZone, g_activeSupportZones, sensitivity, emaValue);
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
    debugSupportZone.bottomBoundary = supportPrice;
    debugSupportZone.topBoundary = supportPrice + (10 * _Point);
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
    debugResistanceZone.bottomBoundary = resistancePrice - (10 * _Point);
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

    // Create a support zone if the current candle is valid
    if (rates[0].close < emaValue)
    {
        double supportPrice = rates[0].low;
        SRZone supportZone;
        supportZone.bottomBoundary = MathMax(rates[0].open, rates[0].close); // Bottom boundary is the higher of open/close
        supportZone.topBoundary = rates[0].high; // Top boundary starts at the high
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

    // Create a resistance zone if the current candle is valid
    if (rates[0].close > emaValue)
    {
        double resistancePrice = rates[0].high;
        SRZone resistanceZone;
        resistanceZone.bottomBoundary = MathMax(rates[0].open, rates[0].close); // Bottom boundary is the higher of open/close
        resistanceZone.topBoundary = resistancePrice; // Top boundary starts at the high
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
