//+------------------------------------------------------------------+
//|                                 EMA_Engulfing_Logger.mqh         |
//|                                                                   |
//|                                                                   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023"
#property link      ""
#property strict

// Enum for log levels
enum ENUM_LOG_LEVEL
{
   LOG_LEVEL_ERROR,   // Only errors
   LOG_LEVEL_WARNING, // Errors and warnings
   LOG_LEVEL_INFO,    // Normal information
   LOG_LEVEL_DEBUG    // Detailed debug information
};

// Global log level setting
input ENUM_LOG_LEVEL InpLogLevel = LOG_LEVEL_INFO; // Logging level

// Class for handling logging functionality
class CEmaLogger
{
private:
   string m_prefix;
   string m_logFile;
   bool m_logToFile;
   ENUM_LOG_LEVEL m_logLevel;

public:
   // Constructor
   CEmaLogger(string prefix = "EMA_EA", bool logToFile = false)
   {
      m_prefix = prefix;
      m_logToFile = logToFile;
      m_logLevel = InpLogLevel;
      
      if(m_logToFile)
      {
         m_logFile = "EMA_Engulfing_EA_" + TimeToString(TimeCurrent(), TIME_DATE) + ".log";
      }
   }
   
   // Set log level
   void SetLogLevel(ENUM_LOG_LEVEL level)
   {
      m_logLevel = level;
   }
   
   // Log error messages
   void Error(string message)
   {
      if(m_logLevel >= LOG_LEVEL_ERROR)
      {
         string logMessage = m_prefix + " ERROR: " + message;
         Print(logMessage);
         
         if(m_logToFile)
            WriteToFile(logMessage);
      }
   }
   
   // Log warning messages
   void Warning(string message)
   {
      if(m_logLevel >= LOG_LEVEL_WARNING)
      {
         string logMessage = m_prefix + " WARNING: " + message;
         Print(logMessage);
         
         if(m_logToFile)
            WriteToFile(logMessage);
      }
   }
   
   // Log info messages
   void Info(string message)
   {
      if(m_logLevel >= LOG_LEVEL_INFO)
      {
         string logMessage = m_prefix + " INFO: " + message;
         Print(logMessage);
         
         if(m_logToFile)
            WriteToFile(logMessage);
      }
   }
   
   // Log debug messages
   void Debug(string message)
   {
      if(m_logLevel >= LOG_LEVEL_DEBUG)
      {
         string logMessage = m_prefix + " DEBUG: " + message;
         Print(logMessage);
         
         if(m_logToFile)
            WriteToFile(logMessage);
      }
   }
   
   // Write to log file
   private void WriteToFile(string message)
   {
      int handle = FileOpen(m_logFile, FILE_WRITE|FILE_READ|FILE_TXT);
      
      if(handle != INVALID_HANDLE)
      {
         FileSeek(handle, 0, SEEK_END);
         FileWriteString(handle, TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES|TIME_SECONDS) + " " + message + "\n");
         FileClose(handle);
      }
   }
};

// Global logger instance
CEmaLogger Logger("EMA_EA", false);

// Helper function to translate error codes to readable messages
string GetErrorMessage(int errorCode)
{
   switch(errorCode)
   {
      case ERR_NO_ERROR:
         return "No error";
      case ERR_NO_RESULT:
         return "No error returned, but the result is unknown";
      case ERR_COMMON_ERROR:
         return "Common error";
      case ERR_INVALID_TRADE_PARAMETERS:
         return "Invalid trade parameters";
      case ERR_SERVER_BUSY:
         return "Trade server is busy";
      case ERR_OLD_VERSION:
         return "Old version of the client terminal";
      case ERR_NO_CONNECTION:
         return "No connection with trade server";
      case ERR_NOT_ENOUGH_RIGHTS:
         return "Not enough rights";
      case ERR_TOO_FREQUENT_REQUESTS:
         return "Too frequent requests";
      case ERR_MALFUNCTIONAL_TRADE:
         return "Malfunctional trade operation";
      case ERR_ACCOUNT_DISABLED:
         return "Account disabled";
      case ERR_INVALID_ACCOUNT:
         return "Invalid account";
      case ERR_TRADE_TIMEOUT:
         return "Trade timeout";
      case ERR_INVALID_PRICE:
         return "Invalid price";
      case ERR_INVALID_STOPS:
         return "Invalid stops";
      case ERR_INVALID_TRADE_VOLUME:
         return "Invalid trade volume";
      case ERR_MARKET_CLOSED:
         return "Market is closed";
      case ERR_TRADE_DISABLED:
         return "Trade is disabled";
      case ERR_NOT_ENOUGH_MONEY:
         return "Not enough money";
      case ERR_PRICE_CHANGED:
         return "Price changed";
      case ERR_OFF_QUOTES:
         return "Off quotes";
      case ERR_BROKER_BUSY:
         return "Broker is busy";
      case ERR_REQUOTE:
         return "Requote";
      case ERR_ORDER_LOCKED:
         return "Order is locked";
      case ERR_LONG_POSITIONS_ONLY_ALLOWED:
         return "Long positions only allowed";
      case ERR_TOO_MANY_REQUESTS:
         return "Too many requests";
      case ERR_TRADE_MODIFY_DENIED:
         return "Modification denied because an order is too close to market";
      case ERR_TRADE_CONTEXT_BUSY:
         return "Trade context is busy";
      case ERR_TRADE_EXPIRATION_DENIED:
         return "Expirations are denied by broker";
      case ERR_TRADE_TOO_MANY_ORDERS:
         return "The amount of open and pending orders has reached the limit set by the broker";
      case ERR_TRADE_HEDGE_PROHIBITED:
         return "An attempt to open an order opposite to the existing one when hedging is disabled";
      case ERR_TRADE_PROHIBITED_BY_FIFO:
         return "An attempt to close an order contravening the FIFO rule";
      default:
         return "Unknown error " + IntegerToString(errorCode);
   }
}
//+------------------------------------------------------------------+