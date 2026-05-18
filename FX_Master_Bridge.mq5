//+------------------------------------------------------------------+
//|                                         FX_Master_Bridge.mq5    |
//|                             Copyright 2026, FX Master Tools      |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, FX Master Tools"
#property link      "https://github.com/ShakyaPankaj1995/FX-Trading-Scraper"
#property version   "3.00"

#include <Trade\Trade.mqh>

//--- Input Parameters
input string   InpServerUrl    = "https://raw.githubusercontent.com/ShakyaPankaj1995/FX-Trading-Scraper/master/trades.json";
input double   InpRiskPercent  = 1.0;   // Risk % per trade
input int      InpTimerSeconds = 15;    // Check interval (seconds)
input int      InpMagicNumber  = 88888; // Magic number
input bool     InpDebugMode    = true;  // Print detailed logs

//--- Globals
CTrade g_trade;
string g_processed_ids = "";

//+------------------------------------------------------------------+
int OnInit()
{
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   EventSetTimer(InpTimerSeconds);
   Print("FX Master Bridge v3.00 started. Interval: ", InpTimerSeconds, "s");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
}

//+------------------------------------------------------------------+
//| Resolve scraper symbol name → MT5 broker symbol name            |
//+------------------------------------------------------------------+
string ResolveSymbol(string s)
{
   if(s == "NASDAQ")  return "ND100m";
   if(s == "S&P500")  return "SP500m";
   if(s == "XAUUSD")  return "XAUUSD";
   if(s == "EURUSD")  return "EURUSD";
   if(s == "GBPUSD")  return "GBPUSD";
   if(s == "USDJPY")  return "USDJPY";
   return s;
}

//+------------------------------------------------------------------+
//| Check if we already have an open position for this symbol       |
//+------------------------------------------------------------------+
bool PositionOpenForSymbol(string symbol)
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
         if(PositionGetString(POSITION_SYMBOL) == symbol &&
            (long)PositionGetInteger(POSITION_MAGIC) == (long)InpMagicNumber)
            return true;
   }
   return false;
}

//+------------------------------------------------------------------+
void OnTimer()
{
   string url = InpServerUrl + "?t=" + IntegerToString(TimeGMT());
   if(InpDebugMode) Print("Fetching: ", url);

   char   post_data[];
   char   response[];
   string response_headers;

   int status = WebRequest(
      "GET", url,
      "Cache-Control: no-cache\r\n",
      5000, post_data, response, response_headers
   );

   if(status == -1)
   {
      Print("[Error] WebRequest failed. Code: ", GetLastError(),
            ". Add URL to: Tools > Options > Expert Advisors > Allow WebRequest.");
      return;
   }

   string json = CharArrayToString(response, 0, WHOLE_ARRAY, CP_UTF8);

   if(StringLen(json) < 5 || json == "[]")
   {
      if(InpDebugMode) Print("[OK] Connected. No active signals.");
      return;
   }

   if(InpDebugMode) Print("[Data] JSON length: ", StringLen(json));

   // Parse each trade object
   int pos = 0;
   while(true)
   {
      int obj_start = StringFind(json, "{", pos);
      if(obj_start == -1) break;
      int obj_end = StringFind(json, "}", obj_start);
      if(obj_end == -1) break;

      string obj = StringSubstr(json, obj_start, obj_end - obj_start + 1);
      TryExecuteTrade(obj);
      pos = obj_end + 1;
   }
}

//+------------------------------------------------------------------+
void TryExecuteTrade(string obj)
{
   string status = JsonGet(obj, "status");
   if(status != "Active") return;

   string id         = JsonGet(obj, "id");
   string raw_symbol = JsonGet(obj, "symbol");
   string signal     = JsonGet(obj, "signal");
   double entry      = StringToDouble(JsonGet(obj, "entry"));
   double sl         = StringToDouble(JsonGet(obj, "sl"));
   double tp         = StringToDouble(JsonGet(obj, "tp"));

   if(raw_symbol == "" || signal == "" || entry == 0) return;

   string symbol = ResolveSymbol(raw_symbol);

   //--- GUARD 1: Already processed this ID in current session?
   if(id != "" && StringFind(g_processed_ids, id + "|") != -1)
   {
      if(InpDebugMode) Print("[Skip] ID already processed: ", id);
      return;
   }

   //--- GUARD 2: Already have an open position for this symbol?
   if(PositionOpenForSymbol(symbol))
   {
      if(InpDebugMode) Print("[Skip] Position already open for: ", symbol);
      return;
   }

   Print("[Signal] ", symbol, " ", signal,
         " | Entry:", entry, " SL:", sl, " TP:", tp,
         " | ID:", id);

   double lot = CalcLot(symbol, entry, sl);
   if(lot <= 0)
   {
      Print("[Error] Lot calc failed for ", symbol,
            ". SL=", sl, " Entry=", entry,
            ". Check symbol name — broker may differ from: ", raw_symbol);
      return;
   }

   bool ok = false;
   if(signal == "BUY")
      ok = g_trade.Buy(lot, symbol, 0, sl, tp, "FX_" + id);
   else if(signal == "SELL")
      ok = g_trade.Sell(lot, symbol, 0, sl, tp, "FX_" + id);

   if(ok)
   {
      Print("[Executed] ", signal, " ", symbol, " Lot:", lot);
      g_processed_ids += id + "|";
   }
   else
      Print("[Failed] ", signal, " ", symbol, " Error:", GetLastError());
}

//+------------------------------------------------------------------+
//| Extract a value from a JSON object string                        |
//+------------------------------------------------------------------+
string JsonGet(string obj, string key)
{
   string search = "\"" + key + "\"";
   int key_pos = StringFind(obj, search);
   if(key_pos == -1) return "";

   int colon = StringFind(obj, ":", key_pos + StringLen(search));
   if(colon == -1) return "";

   int i = colon + 1;
   int len = StringLen(obj);

   while(i < len && StringGetCharacter(obj, i) == ' ') i++;

   bool is_quoted = (StringGetCharacter(obj, i) == '"');
   if(is_quoted) i++;

   string value = "";
   while(i < len)
   {
      ushort ch = StringGetCharacter(obj, i);
      if(is_quoted  && ch == '"')  break;
      if(!is_quoted && (ch == ',' || ch == '}')) break;
      value += ShortToString(ch);
      i++;
   }
   return value;
}

//+------------------------------------------------------------------+
//| Calculate lot size for X% risk                                   |
//+------------------------------------------------------------------+
double CalcLot(string symbol, double entry, double sl)
{
   double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
   double risk_money = equity * InpRiskPercent / 100.0;

   double tick_val  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double sl_dist   = MathAbs(entry - sl);

   if(sl_dist <= 0 || tick_size <= 0 || tick_val <= 0) return 0;

   double sl_ticks = sl_dist / tick_size;
   double lot = risk_money / (sl_ticks * tick_val);

   double lot_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double lot_min  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double lot_max  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);

   lot = MathFloor(lot / lot_step) * lot_step;
   lot = MathMax(lot, lot_min);
   lot = MathMin(lot, lot_max);

   return lot;
}
