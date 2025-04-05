# MT5 Expert Advisor Setup Guide

## Directory Structure

For proper compilation, your files should be organized as follows:

```
[MT5 Directory]
├── MQL5
│   ├── Experts
│   │   └── EMA_Engulfing_EA.mq5  (Main EA file)
│   ├── Include
│   │   ├── EMA_Engulfing_EA.mqh  (EA helper functions)
│   │   ├── EMA_Engulfing_Trade.mqh  (Trade functions)
│   │   └── EMA_Engulfing_Logger.mqh  (Logging functions)
```

## Installation Instructions

1. Locate your MT5 data folder:
   - Open MetaTrader 5
   - Click on "File" > "Open Data Folder"

2. Copy files to the correct locations:
   - Copy `EMA_Engulfing_EA.mq5` to the `MQL5/Experts/` folder
   - Create the `Include` directory if it doesn't exist
   - Copy all `.mqh` files to the `MQL5/Include/` folder

3. Restart MetaTrader 5 or refresh the Navigator panel

4. Open MetaEditor (from MT5: Tools > MetaEditor or press F4)

5. Find and open your EA file in the Navigator panel

6. Compile the EA by pressing F7 or clicking the "Compile" button