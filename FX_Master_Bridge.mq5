//+------------------------------------------------------------------+
//|                                              FX_Master_Bridge.mq5|
//|                                  Copyright 2026, FX Master Tools |
//|                                             https://localhost:8501|
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, FX Master Tools"
#property link      "https://localhost:8501"
#property version   "1.10"
#property strict

#include <Trade\Trade.mqh>

// --- INPUT PARAMETERS ---
input string   InpServerUrl   = "https://raw.githubusercontent.com/ShakyaPankaj1995/FX-Trading-Scraper/master/trades.json"; 
input double   InpRiskPercent = 1.0;                            // Risk percent per trade
input int      InpTimerSeconds = 15;                            // Pinging interval (seconds)
input string   InpMagicNum    = "88888";                        // Magic number
input bool     InpDebugMode   = true;                           // Show detailed logs

// --- GLOBALS ---
CTrade trade;
string last_processed_ids = ""; 

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   EventSetTimer(InpTimerSeconds);
   trade.SetExpertMagicNumber(StringToInteger(InpMagicNum));
   Print("FX Master Bridge v1.10 Started. Tracking: ", InpServerUrl);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) { EventKillTimer(); }

//+------------------------------------------------------------------+
//| Timer function - Main Logic                                      |
//+------------------------------------------------------------------+
void OnTimer()
{
   char data[];
   char result[];
   string result_headers;
   int res;
   
   if(InpDebugMode) Print("Pinging GitHub for new signals...");

   // 1. Fetch JSON
   res = WebRequest("GET", InpServerUrl, NULL, NULL, 5000, data, 0, result, result_headers);
   
   if(res == -1)
   {
      Print("WebRequest Error: ", _LastError, ". Check Tools -> Options -> EAs -> Allow WebRequest for URL.");
      return;
   }
   
   string json_text = CharArrayToString(result);
   if(json_text == "" || json_text == "[]") 
   {
      if(InpDebugMode) Print("Connection OK. No signals found.");
      return;
   }

   ProcessSignals(json_text);
}

void ProcessSignals(string json)
{
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

void ExecuteTradeFromObject(string obj)
{
   // Check status
   string status = ExtractValue(obj, "\"status\"");
   if(status != "Active") return;
   
   // Extract ID
   string id = ExtractValue(obj, "\"id\"");
   if(id == "" || StringFind(last_processed_ids, id) != -1) return;
   
   string symbol = ExtractValue(obj, "\"symbol\"");
   string signal = ExtractValue(obj, "\"signal\"");
   double entry  = StringToDouble(ExtractValue(obj, "\"entry\""));
   double sl     = StringToDouble(ExtractValue(obj, "\"sl\""));
   double tp     = StringToDouble(ExtractValue(obj, "\"tp\""));

   if(InpDebugMode) Print("Found Signal: ", symbol, " ", signal, " @ ", entry, " (ID: ", id, ")");

   // Risk Management
   double lot = CalculateLotSize(symbol, sl, entry);
   if(lot <= 0) { Print("Lot size calculation failed. Check SL/Price distance."); return; }

   // Execution
   bool success = false;
   if(signal == "BUY")
      success = trade.Buy(lot, symbol, entry, sl, tp, "FX Master Auto");
   else if(signal == "SELL")
      success = trade.Sell(lot, symbol, entry, sl, tp, "FX Master Auto");

   if(success)
   {
      Print("Trade EXECUTED: ", signal, " ", symbol, " Lot: ", lot);
      last_processed_ids += id + "|";
   }
   else
   {
      Print("Execution FAILED for ", symbol, ". Check MT5 Journal for details.");
   }
}

double CalculateLotSize(string sym, double sl, double entry)
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double risk_amount = equity * (InpRiskPercent / 100.0);
   
   double tick_value = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double tick_size = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   
   double points_risk = MathAbs(entry - sl);
   if(points_risk <= 0 || tick_value <= 0) return 0;
   
   double lot = risk_amount / (points_risk * (tick_value / tick_size));
   
   double lot_step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   lot = MathFloor(lot / lot_step) * lot_step;
   
   return lot;
}

// Improved Extractor for both strings and numbers
string ExtractValue(string obj, string key)
{
   int key_pos = StringFind(obj, key);
   if(key_pos == -1) return "";
   
   int colon_pos = StringFind(obj, ":", key_pos);
   if(colon_pos == -1) return "";
   
   int start = colon_pos + 1;
   // Skip whitespace or quotes
   while(start < StringLen(obj) && (StringSubstr(obj, start, 1) == " " || StringSubstr(obj, start, 1) == "\"" || StringSubstr(obj, start, 1) == "\n"))
      start++;
      
   int end = start;
   // Read until comma, quote, or brace
   while(end < StringLen(obj) && StringSubstr(obj, end, 1) != "," && StringSubstr(obj, end, 1) != "\"" && StringSubstr(obj, end, 1) != "}" && StringSubstr(obj, end, 1) != "\n")
      end++;
      
   return StringTrimLeft(StringTrimRight(StringSubstr(obj, start, end - start)));
}
