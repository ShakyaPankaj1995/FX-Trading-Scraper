import asyncio
import json
import os
import requests
from datetime import datetime, timedelta
from playwright.async_api import async_playwright

# --- CONFIGURATION ---
URL = "https://fx-trading-dashboard-v4.vercel.app/"
SYMBOLS = ["EURUSD", "GBPUSD", "USDJPY", "XAUUSD", "S&P500", "NASDAQ"]
OUTPUT_FILE = "trades.json"
HISTORY_FILE = "history.json"
FRESHNESS_MINUTES = 4  # Reduced to match 2-min cron (allows 2m buffer for script runtime)

# To enable Telegram alerts, fill in your credentials:
TELEGRAM_BOT_TOKEN = ""
TELEGRAM_CHAT_ID = ""

def send_telegram_alert(trade):
    if not TELEGRAM_BOT_TOKEN or not TELEGRAM_CHAT_ID:
        return
    msg = (
        f"New FX Signal: {trade['symbol']} {trade['signal']}\n"
        f"TF: {trade['timeframe']} | Entry: {trade['entry']}\n"
        f"SL: {trade['sl']} | TP: {trade['tp']}\n"
        f"Time: {trade['trade_time']}"
    )
    try:
        requests.post(
            f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage",
            json={"chat_id": TELEGRAM_CHAT_ID, "text": msg},
            timeout=5
        )
    except:
        pass

def parse_trade_time(time_str, now):
    """
    Timezone-safe freshness check.
    GitHub Actions runs UTC; site shows local time (IST = UTC+5:30).
    Strategy: find closest candidate across ±1 day, reject if >FRESHNESS_MINUTES.
    FIX: .upper() ensures lowercase 'am/pm' parses correctly on Linux locale.
    """
    for fmt in ["%I:%M %p", "%H:%M", "%I:%M%p"]:
        try:
            # .upper() on time_str fixes Linux locale issue where lowercase 'am/pm' fails
            # Do NOT upper() the fmt string - %P is not valid, only %p is
            parsed = datetime.strptime(time_str.strip().upper(), fmt)
            candidates = []
            for day_delta in [-1, 0, 1]:
                c = parsed.replace(year=now.year, month=now.month, day=now.day)
                c = c + timedelta(days=day_delta)
                candidates.append(c)
            closest = min(candidates, key=lambda c: abs((now - c).total_seconds()))
            age_mins = (now - closest).total_seconds() / 60
            return age_mins
        except:
            continue
    return None  # Could not parse

def make_dedup_key(symbol, timeframe, entry, sl):
    """
    Deduplication key: symbol + timeframe + entry + sl.
    Creates a perfectly stable, unique ID for every trade setup.
    """
    safe_entry = str(entry).replace(' ', '').replace(':', '')
    safe_sl = str(sl).replace(' ', '').replace(':', '')
    return f"{symbol}_{timeframe}_{safe_entry}_{safe_sl}"

async def run_scraper():
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        context = await browser.new_context(viewport={"width": 1920, "height": 1080})
        page = await context.new_page()

        print("--- FX Scraper Starting ---")
        await page.goto(URL, wait_until="networkidle")
        await asyncio.sleep(3)

        # STEP 1: Click each pair sequentially (3s between each) to warm up data
        print("Warming up: Clicking all pairs...")
        for symbol in SYMBOLS:
            try:
                await page.get_by_role("button", name=symbol, exact=True).click()
                print(f"  Clicked: {symbol}")
                await asyncio.sleep(3)
            except Exception as e:
                print(f"  [Error] Could not click {symbol}: {e}")

        # STEP 2: Open Signal Log
        print("Opening Signal Log...")
        await page.locator("button.log-nav-btn").click()
        await asyncio.sleep(5)

        # FIX: Scroll inside the log modal to ensure ALL rows are loaded/visible
        try:
            modal = page.locator(".log-modal, .log-overlay, [class*='log-table']").first
            await modal.evaluate("el => el.scrollTop = el.scrollHeight")
            await asyncio.sleep(1)
            print("  Scrolled log modal to bottom.")
        except:
            pass

        # STEP 3: Get all active rows
        active_rows = await page.locator("tr.log-row-active").all()
        print(f"Found {len(active_rows)} active trade row(s).")

        now = datetime.now()
        trades = []
        seen_symbols = set()  # DEDUP: only 1 trade per symbol per run in trades.json

        for row in active_rows:
            try:
                cells = await row.locator("td").all()
                cell_texts = [(await c.inner_text()).strip() for c in cells]

                date_str   = cell_texts[0] if len(cell_texts) > 0 else ""
                time_str   = cell_texts[1] if len(cell_texts) > 1 else ""
                symbol_val = cell_texts[2] if len(cell_texts) > 2 else ""
                tf_val     = cell_texts[3] if len(cell_texts) > 3 else ""
                strat_val  = cell_texts[4] if len(cell_texts) > 4 else ""
                signal_val = cell_texts[5].replace("\n", "").strip() if len(cell_texts) > 5 else ""
                entry_val  = cell_texts[6] if len(cell_texts) > 6 else ""
                sl_val     = cell_texts[7] if len(cell_texts) > 7 else ""
                tp_val     = cell_texts[8] if len(cell_texts) > 8 else ""

                # Clean BUY/SELL
                if "BUY" in signal_val.upper():
                    signal_val = "BUY"
                elif "SELL" in signal_val.upper():
                    signal_val = "SELL"
                else:
                    print(f"  [Skip] Unrecognized signal: '{signal_val}'")
                    continue

                dedup_key = make_dedup_key(symbol_val, tf_val, entry_val, sl_val)

                print(f"  Row: {symbol_val} {signal_val} {tf_val} | {time_str} | Entry:{entry_val}")

                # STEP 4: Freshness filter (timezone-safe)
                age_mins = parse_trade_time(time_str, now)

                if age_mins is not None and age_mins > FRESHNESS_MINUTES:
                    print(f"    -> SKIPPED ({age_mins:.0f} min old - over {FRESHNESS_MINUTES}min limit)")
                    continue
                elif age_mins is not None:
                    print(f"    -> MATCH ({age_mins:.1f} min ago)")
                else:
                    print(f"    -> INCLUDED (time unparseable - accepting by default)")

                # removed 1-trade-per-symbol dedup per user request


                trade_data = {
                    "id": dedup_key,
                    "symbol": symbol_val,
                    "timeframe": tf_val,
                    "strategy": strat_val,
                    "signal": signal_val,
                    "entry": entry_val,
                    "sl": sl_val,
                    "tp": tp_val,
                    "status": "Active",
                    "trade_time": trade_time_str,
                    "time_identified": now.strftime("%Y-%m-%d %H:%M:%S")
                }
                trades.append(trade_data)
                send_telegram_alert(trade_data)

            except Exception as e:
                print(f"  [Error] Failed to process row: {e}")

        # STEP 6: Save trades.json (EA reads this - 1 trade per symbol)
        with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
            json.dump(trades, f, indent=2)

        # STEP 7: Append to history.json with deduplication
        # Key = symbol+timeframe+trade_start_time (NOT entry price)
        history = []
        if os.path.exists(HISTORY_FILE):
            try:
                with open(HISTORY_FILE, "r", encoding="utf-8") as f:
                    history = json.load(f)
            except:
                history = []

        existing_keys = {t["id"] for t in history}
        new_count = 0
        for trade in trades:
            if trade["id"] not in existing_keys:
                history.append(trade)
                existing_keys.add(trade["id"])
                new_count += 1

        with open(HISTORY_FILE, "w", encoding="utf-8") as f:
            json.dump(history, f, indent=2)

        print(f"\n--- Done. {len(trades)} unique trade(s) sent to EA. "
              f"{new_count} new unique trade(s) added to history (total: {len(history)}) ---")
        await browser.close()

if __name__ == "__main__":
    asyncio.run(run_scraper())
