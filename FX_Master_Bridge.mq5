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
//| Manage Pending Orders: Delete if SL or TP is reached before entry|
//+------------------------------------------------------------------+
void ManagePendingOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(OrderSelect(ticket))
      {
         if((long)OrderGetInteger(ORDER_MAGIC) == (long)InpMagicNumber)
         {
            string sym = OrderGetString(ORDER_SYMBOL);
            double sl  = OrderGetDouble(ORDER_SL);
            double tp  = OrderGetDouble(ORDER_TP);
            long type  = OrderGetInteger(ORDER_TYPE);
            
            double bid = SymbolInfoDouble(sym, SYMBOL_BID);
            double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
            
            bool should_delete = false;
            
            // For Buy Limit / Buy Stop
            if(type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_BUY_STOP)
            {
               if((sl > 0 && bid <= sl) || (tp > 0 && bid >= tp)) should_delete = true;
            }
            // For Sell Limit / Sell Stop
            else if(type == ORDER_TYPE_SELL_LIMIT || type == ORDER_TYPE_SELL_STOP)
            {
               if((sl > 0 && ask >= sl) || (tp > 0 && ask <= tp)) should_delete = true;
            }
            
            if(should_delete)
            {
               Print("[Cancel] Price hit SL/TP before entry. Deleting pending order: ", sym);
               g_trade.OrderDelete(ticket);
            }
         }
      }
   }
}

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
//| Check if we already have an open position or pending order      |
//+------------------------------------------------------------------+
bool TradeActiveForSymbol(string symbol)
{
   // Check Open Positions
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
         if(PositionGetString(POSITION_SYMBOL) == symbol &&
            (long)PositionGetInteger(POSITION_MAGIC) == (long)InpMagicNumber)
            return true;
   }
   // Check Pending Orders
   for(int i = 0; i < OrdersTotal(); i++)
   {
      ulong ticket = OrderGetTicket(i);
      if(OrderSelect(ticket))
         if(OrderGetString(ORDER_SYMBOL) == symbol &&
            (long)OrderGetInteger(ORDER_MAGIC) == (long)InpMagicNumber)
            return true;
   }
   return false;
}

//+------------------------------------------------------------------+
void OnTimer()
{
   ManagePendingOrders();

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

   //--- GUARD 2: Already have an open position or pending order for this symbol?
   if(TradeActiveForSymbol(symbol))
   {
      if(InpDebugMode) Print("[Skip] Trade already active for: ", symbol);
      return;
   }

   //--- GUARD 3: Cross-chart race condition lock (if EA runs on multiple charts)
   string lock_name = "FX_Lock_" + symbol;
   if(GlobalVariableCheck(lock_name))
   {
      if(TimeCurrent() - (datetime)GlobalVariableGet(lock_name) < 10)
      {
         return; // Another chart's EA grabbed this exact trade in the last 10 seconds
      }
   }
   GlobalVariableSet(lock_name, TimeCurrent());

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
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   
   // 3 pip tolerance for market execution
   double tolerance = 30 * point; 

   if(signal == "BUY")
   {
      if(MathAbs(ask - entry) <= tolerance)
         ok = g_trade.Buy(lot, symbol, 0, sl, tp, "FX_" + id);
      else if(ask > entry)
         ok = g_trade.BuyLimit(lot, entry, symbol, sl, tp, ORDER_TIME_GTC, 0, "FX_" + id);
      else
         ok = g_trade.BuyStop(lot, entry, symbol, sl, tp, ORDER_TIME_GTC, 0, "FX_" + id);
   }
   else if(signal == "SELL")
   {
      if(MathAbs(bid - entry) <= tolerance)
         ok = g_trade.Sell(lot, symbol, 0, sl, tp, "FX_" + id);
      else if(bid < entry)
         ok = g_trade.SellLimit(lot, entry, symbol, sl, tp, ORDER_TIME_GTC, 0, "FX_" + id);
      else
         ok = g_trade.SellStop(lot, entry, symbol, sl, tp, ORDER_TIME_GTC, 0, "FX_" + id);
   }

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
