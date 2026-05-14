//+------------------------------------------------------------------+
//|                                              FX_Master_Bridge.mq5|
//|                                  Copyright 2026, FX Master Tools |
//|                                             https://localhost:8501|
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, FX Master Tools"
#property link      "https://localhost:8501"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

// --- INPUT PARAMETERS ---
input string   InpServerUrl   = "https://raw.githubusercontent.com/ShakyaPankaj1995/FX-Trading-Scraper/master/trades.json"; 
input double   InpRiskPercent = 1.0;                            // Risk percent per trade
input int      InpTimerSeconds = 30;                            // Pinging interval (seconds)
input string   InpMagicNum    = "88888";                        // Magic number

// --- GLOBALS ---
CTrade trade;
string last_processed_ids = ""; // Simple way to track processed trades

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   EventSetTimer(InpTimerSeconds);
   trade.SetExpertMagicNumber(StringToInteger(InpMagicNum));
   Print("FX Master Bridge EA Started. Targeting: ", InpServerUrl);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
}

//+------------------------------------------------------------------+
//| Timer function - Main Logic                                      |
//+------------------------------------------------------------------+
void OnTimer()
{
   char data[];
   char result[];
   string result_headers;
   int res;
   
   // 1. Fetch JSON from our Bridge Server
   res = WebRequest("GET", InpServerUrl, NULL, NULL, 5000, data, 0, result, result_headers);
   
   if(res == -1)
   {
      Print("Error in WebRequest. Check MT5 -> Tools -> Options -> Expert Advisors -> Allow WebRequest for URL.");
      return;
   }
   
   string json_text = CharArrayToString(result);
   if(json_text == "" || json_text == "[]") return;

   // 2. Simple Parsing (Since MQL5 native JSON is limited, we use string searching for this demo)
   // For production, highly recommend using a library like JAson.mqh
   ProcessSignals(json_text);
}

//+------------------------------------------------------------------+
//| Parse and Execute trades                                         |
//+------------------------------------------------------------------+
void ProcessSignals(string json)
{
   // Note: This is a simplified parsing approach for the template.
   // We look for active trades in the JSON string.
   
   // Find the start of an object
   int start_pos = 0;
   while((start_pos = StringFind(json, "{", start_pos)) != -1)
   {
      int end_pos = StringFind(json, "}", start_pos);
      if(end_pos == -1) break;
      
      string obj = StringSubstr(json, start_pos, end_pos - start_pos + 1);
      ExecuteTradeFromObject(obj);
      
      start_pos = end_pos + 1;
   }
}

//+------------------------------------------------------------------+
//| Extract values and Send Order                                    |
//+------------------------------------------------------------------+
void ExecuteTradeFromObject(string obj)
{
   // Check if Active
   if(StringFind(obj, "\"status\":\"Active\"") == -1) return;
   
   // Extract ID to prevent duplicates
   string id = ExtractValue(obj, "\"id\":\"");
   if(StringFind(last_processed_ids, id) != -1) return; // Already traded this signal
   
   string symbol = ExtractValue(obj, "\"symbol\":\"");
   string signal = ExtractValue(obj, "\"signal\":\"");
   double entry  = StringToDouble(ExtractValue(obj, "\"entry\":\""));
   double sl     = StringToDouble(ExtractValue(obj, "\"sl\":\""));
   double tp     = StringToDouble(ExtractValue(obj, "\"tp\":\""));

   // 3. Risk Management: Calculate Lot Size
   double lot = CalculateLotSize(symbol, sl, entry);
   
   if(lot <= 0) return;

   // 4. Execution
   bool success = false;
   if(signal == "BUY")
      success = trade.Buy(lot, symbol, entry, sl, tp, "FX Master Auto Signal");
   else if(signal == "SELL")
      success = trade.Sell(lot, symbol, entry, sl, tp, "FX Master Auto Signal");

   if(success)
   {
      Print("Successfully executed ", signal, " on ", symbol, " with lot ", lot);
      last_processed_ids += id + "|";
   }
}

//+------------------------------------------------------------------+
//| Calculate Lot Size for 1% Risk                                   |
//+------------------------------------------------------------------+
double CalculateLotSize(string sym, double sl, double entry)
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double risk_amount = equity * (InpRiskPercent / 100.0);
   
   double tick_value = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double tick_size = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   
   if(tick_value <= 0 || tick_size <= 0) return 0;
   
   double points_risk = MathAbs(entry - sl);
   if(points_risk <= 0) return 0;
   
   // Lot calculation formula: Risk Amount / (Points Risk * (Tick Value / Tick Size))
   double lot = risk_amount / (points_risk * (tick_value / tick_size));
   
   // Normalize lot size
   double lot_step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   lot = MathFloor(lot / lot_step) * lot_step;
   
   double min_lot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   
   if(lot < min_lot) lot = min_lot;
   if(lot > max_lot) lot = max_lot;
   
   return lot;
}

// Helper to extract values from simple JSON strings
string ExtractValue(string obj, string key)
{
   int start = StringFind(obj, key);
   if(start == -1) return "";
   start += StringLen(key);
   int end = StringFind(obj, "\"", start);
   if(end == -1) return "";
   return StringSubstr(obj, start, end - start);
}
