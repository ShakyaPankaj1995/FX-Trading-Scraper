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
input double   InpRiskPercent  = 5.0;   // Risk % per trade
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
   if(s == "NASDAQ")  return "USTECH100M";
   if(s == "S&P500")  return "US500M";
   if(s == "XAUUSD")  return "XAUUSD";
   if(s == "EURUSD")  return "EURUSD";
   if(s == "GBPUSD")  return "GBPUSD";
   if(s == "USDJPY")  return "USDJPY";
   return s;
}

// (Removed TradeActiveForSymbol to allow multiple trades per symbol)

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
//| Check if a slot is currently occupied by a live trade/order      |
//+------------------------------------------------------------------+
bool IsTradeActiveForSlot(string slot_id)
{
   string target_comment = "FX_" + slot_id;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         string comment = PositionGetString(POSITION_COMMENT);
         if(StringFind(comment, target_comment) != -1) return true;
      }
   }
   for(int i = 0; i < OrdersTotal(); i++)
   {
      ulong ticket = OrderGetTicket(i);
      if(OrderSelect(ticket))
      {
         string comment = OrderGetString(ORDER_COMMENT);
         if(StringFind(comment, target_comment) != -1) return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check if a slot was closed/cancelled within the last X minutes   |
//+------------------------------------------------------------------+
bool WasSlotClosedRecently(string slot_id, int minutes)
{
   datetime end_time = TimeCurrent();
   datetime start_time = end_time - (minutes * 60);
   HistorySelect(start_time, end_time);
   
   string target_comment = "FX_" + slot_id;
   for(int i = 0; i < HistoryDealsTotal(); i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket > 0)
      {
         string comment = HistoryDealGetString(ticket, DEAL_COMMENT);
         if(StringFind(comment, target_comment) != -1) return true;
      }
   }
   for(int i = 0; i < HistoryOrdersTotal(); i++)
   {
      ulong ticket = HistoryOrderGetTicket(i);
      if(ticket > 0)
      {
         string comment = HistoryOrderGetString(ticket, ORDER_COMMENT);
         if(StringFind(comment, target_comment) != -1) return true;
      }
   }
   return false;
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

   string tf         = JsonGet(obj, "timeframe");
   string strategy   = JsonGet(obj, "strategy");
   string slot_id    = symbol + "_" + tf + "_" + strategy;

   //--- GUARD 1: Already processed this EXACT signal ID in current session?
   if(id != "" && StringFind(g_processed_ids, id + "|") != -1)
   {
      if(InpDebugMode) Print("[Skip] ID already processed: ", id);
      return;
   }
   
   //--- GUARD 2: Slot Lock (Is there already an active trade for this slot?)
   if (IsTradeActiveForSlot(slot_id))
   {
       // Slot is occupied, ignore new signals for this slot
       return;
   }

   //--- GUARD 3: Slot Cooldown (Was this slot recently closed?)
   if (WasSlotClosedRecently(slot_id, 20))
   {
       if(InpDebugMode) Print("[Skip] Slot in 20-min cooldown: ", slot_id);
       return;
   }

   //--- GUARD 4: Cross-chart execution lock (Atomic Mutex)
   string lock_name = "FX_Lock_" + id;
   
   // Initialize lock if it doesn't exist
   if(!GlobalVariableCheck(lock_name))
   {
      GlobalVariableSet(lock_name, 0.0);
   }
   
   // Atomically try to acquire lock (change 0.0 to 1.0)
   if(!GlobalVariableSetOnCondition(lock_name, 1.0, 0.0))
   {
      // If it fails, another chart grabbed it microseconds ago
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
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   
   // 3 pip tolerance for market execution
   double tolerance = 30 * point; 

   if(signal == "BUY")
   {
      if(MathAbs(ask - entry) <= tolerance)
         ok = g_trade.Buy(lot, symbol, 0, sl, tp, "FX_" + slot_id);
      else if(ask > entry)
         ok = g_trade.BuyLimit(lot, entry, symbol, sl, tp, ORDER_TIME_GTC, 0, "FX_" + slot_id);
      else
         ok = g_trade.BuyStop(lot, entry, symbol, sl, tp, ORDER_TIME_GTC, 0, "FX_" + slot_id);
   }
   else if(signal == "SELL")
   {
      if(MathAbs(bid - entry) <= tolerance)
         ok = g_trade.Sell(lot, symbol, 0, sl, tp, "FX_" + slot_id);
      else if(bid < entry)
         ok = g_trade.SellLimit(lot, entry, symbol, sl, tp, ORDER_TIME_GTC, 0, "FX_" + slot_id);
      else
         ok = g_trade.SellStop(lot, entry, symbol, sl, tp, ORDER_TIME_GTC, 0, "FX_" + slot_id);
   }

   if(ok)
   {
      Print("[Executed] ", signal, " ", symbol, " Lot:", lot);
      g_processed_ids += id + "|";
   }
   else
   {
      Print("[Failed] ", signal, " ", symbol, " Error:", GetLastError());
      GlobalVariableDel(lock_name); // Delete lock so we can retry on next tick
   }
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

   // --- STRICT RISK RULE: Reject if the forced lot size exceeds max risk ---
   double actual_risk = lot * sl_ticks * tick_val;
   if(actual_risk > risk_money)
   {
      Print("[Error] Trade Rejected! Min lot ", lot, " risks $", DoubleToString(actual_risk, 2), 
            " which exceeds max allowed ", InpRiskPercent, "% ($", DoubleToString(risk_money, 2), ").");
      return 0; // Return 0 to abort execution
   }

   return lot;
}
