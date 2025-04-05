# EMA Engulfing Expert Advisor

An MT5 Expert Advisor designed specifically for the 30-minute (M30) timeframe that trades based on EMA crossovers, engulfing patterns, and support/resistance levels.

## Trading Strategies

This EA implements three complementary trading strategies optimized for the 30-minute timeframe:

### Strategy 1: EMA Crossing + Engulfing Pattern
- Enters after crossing the 20-period EMA
- Waits for an engulfing pattern to form in the EMA region
- Confirms that price has not closed on the opposite side of the EMA
- Takes entry with two positions (0.01 and 0.02 lot sizes)
- Sets take profit targets at 1:1.7 and 1:2 risk-reward ratios

### Strategy 2: Support/Resistance Engulfing Pattern
- Identifies key support and resistance levels
- Waits for an engulfing pattern to form at these levels
- Enters with the same position sizing and take profit targets as Strategy 1

### Strategy 3: Breakout + EMA Engulfing
- Identifies when price breaks past resistance/support
- Confirms price does not close on the opposite side
- Waits for an engulfing pattern to form near the EMA
- Enters with the same position sizing and take profit targets as Strategy 1

## Important: Timeframe Restriction

This EA is specifically designed to operate on the 30-minute (M30) timeframe. The indicator calculations, pattern recognition, and signal timing are all optimized for this specific timeframe. Using it on other timeframes may produce inconsistent or undesirable results.

## Installation

1. Copy the EA files to your MetaTrader 5 directory:
   - Copy `EMA_Engulfing_EA.mq5` to `[MT5 Directory]/MQL5/Experts/`

2. Restart MetaTrader 5 or refresh the Navigator panel

3. Compile the EA by right-clicking on it in the Navigator panel and selecting "Compile"

## Configuration

### General Settings
- **EMA_Period**: Period for the EMA indicator (default: 20)
- **Lot_Size_1**: Lot size for the first position (default: 0.01)
- **Lot_Size_2**: Lot size for the second position (default: 0.02)
- **RR_Ratio_1**: Risk:Reward ratio for the first take profit (default: 1.7)
- **RR_Ratio_2**: Risk:Reward ratio for the second take profit (default: 2.0)
- **SL_Buffer_Pips**: Additional buffer for stop loss in pips (default: 5)

### Spread Management
- **Max_Spread**: Maximum allowed spread in points (default: 100)
- **DynamicSpread**: Use dynamic spread calculation instead of fixed value (default: true)
- **SpreadMultiplier**: Multiple of average spread to use as maximum (default: 2.0)
- **SpreadSampleSize**: Number of recent ticks to calculate average spread (default: 50)

### Strategy Settings
- **Use_Strategy_1**: Enable/disable the EMA crossing + engulfing strategy
- **Use_Strategy_2**: Enable/disable the S/R engulfing strategy
- **Use_Strategy_3**: Enable/disable the breakout + EMA engulfing strategy

### Support/Resistance Settings
- **SR_Lookback**: Lookback period for S/R detection (default: 50)
- **SR_Min_Strength**: Minimum touches for valid S/R (default: 3)

### Timeframe Settings
- **EnforceM30**: When enabled, the EA will only operate on M30 timeframe charts (default: true)

## Usage

1. Open a 30-minute (M30) chart of your desired symbol
2. Drag the EA onto the chart
3. Configure the input parameters according to your preferences
4. Enable AutoTrading and allow algorithmic trading in MT5

## Best Practices

1. **Always Use M30**: This EA is specifically designed for the 30-minute timeframe
2. **Testing**: Always test on a demo account before using real money
3. **Risk Management**: Adjust the lot sizes based on your account size
4. **Monitoring**: Regularly check the EA performance and logs
5. **Spread Awareness**: Higher volatility pairs will generally require higher spread tolerances

## Spread Management Explained

The EA includes an advanced spread management system to help avoid trading during unfavorable market conditions:

### Fixed Spread Mode
When `DynamicSpread = false`, the EA will use the `Max_Spread` value directly as the maximum allowed spread in points.

### Dynamic Spread Mode
When `DynamicSpread = true`, the EA will:
1. Collect spread data from recent ticks (quantity defined by `SpreadSampleSize`)
2. Calculate the average spread
3. Multiply this average by the `SpreadMultiplier` to determine the maximum allowed spread
4. Skip trading when the current spread exceeds this dynamic maximum

This approach adapts to the current market conditions and different currency pairs. For example:
- During normal market conditions, the EA might allow trading with spreads up to 10-20 points
- During volatile periods, the EA might automatically increase the tolerance to 30-40 points
- During extreme volatility, the EA might require even higher spreads

## Troubleshooting High Spread Issues

If you see log messages like `"Spread too high: 168"`:

1. **Check your broker's typical spreads** for the currency pair you're trading. Some pairs naturally have higher spreads than others.

2. **Adjust the spread settings**:
   - For fixed mode: Increase the `Max_Spread` parameter to a value appropriate for your currency pair
   - For dynamic mode: Adjust the `SpreadMultiplier` to be more tolerant of spread variations

3. **Consider time of day**: Spreads are typically higher during market open/close, major news events, and low liquidity periods.

4. **Monitor spread patterns**: Use the EA's logging to understand the typical spread patterns for your broker and instruments.

## Troubleshooting

If you encounter any issues:

1. Ensure you're using the EA on a 30-minute (M30) chart
2. Check if AutoTrading is enabled
3. Verify that your broker allows algorithmic trading
4. Check if your spread exceeds the maximum allowed spread

## License

See the LICENSE file for details.
