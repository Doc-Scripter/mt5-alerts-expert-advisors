# Troubleshooting "EX5 write error 0 0"

## Permission Issues

1. **Run MetaTrader as Administrator**:
   - Close MetaTrader 5
   - Right-click on the MetaTrader 5 icon
   - Select "Run as administrator"
   - Try compiling again

2. **Check Folder Permissions**:
   - Navigate to your MT5 installation folder
   - Right-click on the MQL5 folder
   - Select "Properties"
   - Go to the "Security" tab
   - Click "Edit" and ensure your user account has "Full control"
   - Apply changes and try compiling again

3. **Disable Read-Only Attributes**:
   - Navigate to your MT5 installation folder
   - Right-click on the MQL5 folder
   - Select "Properties"
   - Uncheck "Read-only" if it's checked
   - Click "Apply" and select "Apply changes to this folder, subfolders and files"

## Antivirus Interference

1. **Temporarily Disable Antivirus**:
   - Temporarily disable your antivirus software
   - Try compiling again
   - If successful, add an exclusion for the MT5 folder in your antivirus settings

2. **Check Windows Defender**:
   - Open Windows Security
   - Go to "Virus & threat protection"
   - Under "Virus & threat protection settings", click "Manage settings"
   - Add an exclusion for the MT5 folder

## Compiler Issues

1. **Clear MQL5 Cache**:
   - Go to your MT5 data folder (File > Open Data Folder)
   - Navigate to MQL5 > Temp
   - Delete all files in this folder
   - Restart MetaTrader and try compiling again

2. **Reinstall MetaEditor**:
   - In MetaTrader 5, go to Tools > Options
   - Select the "Expert Advisors" tab
   - Click "Delete all compiled files"
   - Restart MT5 and try compiling again

3. **Check Code Syntax**:
   - Make sure all functions are properly closed with `}` brackets
   - Check for any syntax errors highlighted in the editor
   - Verify that all included files exist in the correct locations

## Common Code Issues That Cause EX5 Write Errors

1. **Missing Brackets**: Ensure all code blocks and functions are properly closed with `}` brackets.

2. **Unterminated Strings**: Check for unterminated string literals (missing closing quotes).

3. **Recursive Includes**: Avoid circular dependencies in your include files.

4. **Memory Issues**: If your code uses a lot of memory or has memory leaks, it might cause compilation problems.

5. **File Size Limitations**: Very large source files might cause compilation issues.