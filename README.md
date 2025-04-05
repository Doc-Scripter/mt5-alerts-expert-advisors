# EMA Engulfing Expert Advisor

An MT5 Expert Advisor that implements three trading strategies based on EMA crossovers, engulfing patterns, and support/resistance levels.

## Trading Strategies

### Strategy 1: EMA Crossing + Engulfing Pattern
- After crossing the 20-period EMA, if it forms an engulfing pattern on the EMA region without ever closing on the opposite side, it initiates an entry.
- Uses two entries with lot sizes of 0.01 and 0.02.
- Takes profit at 1:1.7 and 1:2 risk-reward ratios from the previous resistance or support.

### Strategy 2: Support/Resistance Engulfing Pattern
- Formation of engulfing candle on resistance/support level.
- Uses the same entry rules as Strategy 1.

### Strategy 3: Breakout + EMA Engulfing
- Breaking past resistance and not closing on the opposite side, and then afterwards forming an engulfing pattern on EMA.
- Uses the same entry rules as Strategy 1.

## Features
- Automatic detection of support and resistance levels
- Customizable EMA period
- Adjustable lot sizes and risk-reward ratios
- Built-in spread control
- Position tracking and management
- Multiple trade entries with different take profit levels

## Installation

1. Copy all files to your MetaTrader 5 directory:
   ```
   /home/gamer/mt5-expert-advisor/EMA_Engulfing_EA.mq5 → [MT5 Directory]/MQL5/Experts/
   /home/gamer/mt5-expert-advisor/Include/EMA_Engulfing_EA.mqh → [MT5 Directory]/MQL5/Include/
   /home/gamer/mt5-expert-advisor/Include/EMA_Engulfing_Trade.mqh → [MT5 Directory]/MQL5/Include/
   ```

2. Restart MetaTrader 5 or refresh the Navigator panel

3. Compile the EA by right-clicking on it in the Navigator panel and selecting "Compile"

## Configuration

The EA includes several configurable parameters:

### General Settings
- **EMA_Period**: Period for the EMA indicator (default: 20)
- **Lot_Size_1**: Lot size for the first position (default: 0.01)
- **Lot_Size_2**: Lot size for the second position (default: 0.02)
- **RR_Ratio_1**: Risk:Reward ratio for the first take profit (default: 1.7)
- **RR_Ratio_2**: Risk:Reward ratio for the second take profit (default: 2.0)
- **Max_Spread**: Maximum allowed spread in points (default: 20)
- **SL_Buffer_Pips**: Additional buffer for stop loss in pips (default: 5)

### Strategy Settings
- **Use_Strategy_1**: Enable/disable the EMA crossing + engulfing strategy
- **Use_Strategy_2**: Enable/disable the S/R engulfing strategy
- **Use_Strategy_3**: Enable/disable the breakout + EMA engulfing strategy

### Support/Resistance Settings
- **SR_Lookback**: Lookback period for S/R detection (default: 50)
- **SR_Min_Strength**: Minimum touches for valid S/R (default: 3)
- **SR_Buffer_Pips**: Buffer zone around S/R levels in pips (default: 10)

## Usage

1. Drag the EA onto a chart
2. Configure the input parameters according to your preferences
3. Enable AutoTrading and allow algorithmic trading in MT5

## Best Practices

1. **Timeframes**: This EA works best on M15, M30, and H1 timeframes
2. **Testing**: Always test on a demo account before using real money
3. **Risk Management**: Adjust the lot sizes based on your account size
4. **Monitoring**: Regularly check the EA logs for execution details

## Troubleshooting

If you encounter any issues:

1. Check the EA logs in the "Experts" tab
2. Ensure that AutoTrading is enabled
3. Verify that your broker allows algorithmic trading
4. Check if your spread exceeds the maximum allowed spread

## License

This project is licensed under the MIT License - see the LICENSE file for details.
