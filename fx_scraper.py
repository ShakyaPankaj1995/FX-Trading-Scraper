import asyncio
import time
import os
import json
import requests
from datetime import datetime, timedelta
from playwright.async_api import async_playwright

# --- CONFIGURATION ---
URL = "https://fx-trading-dashboard-v4.vercel.app/"
SYMBOLS = ["EURUSD", "GBPUSD", "USDJPY", "XAUUSD", "S&P500", "NASDAQ"]
OUTPUT_FILE = "trades.json"

# To enable telegram alerts, provide your details here
TELEGRAM_BOT_TOKEN = "" 
TELEGRAM_CHAT_ID = ""   

def send_telegram_alert(trade, is_update=False):
    if not TELEGRAM_BOT_TOKEN or not TELEGRAM_CHAT_ID:
        return
    
    if is_update:
        message = f"📢 *Trade Update Alert*\n\n"
        message += f"💎 *Pair:* {trade['symbol']}\n"
        message += f"🏁 *New Status:* {trade['status'].upper()}\n"
    else:
        message = f"🚀 *New FX Signal Found!*\n\n"
        message += f"💎 *Pair:* {trade['symbol']}\n"
        message += f"📈 *Entry:* {trade['entry']}\n"
        message += f"🛑 *SL:* {trade['sl']}\n"
        message += f"🎯 *TP:* {trade['tp']}\n"
    
    message += f"\n⏰ _Time: {trade['time_identified']}_"
    
    url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
    try:
        requests.post(url, json={"chat_id": TELEGRAM_CHAT_ID, "text": message, "parse_mode": "Markdown"})
    except: pass

async def run_new_flow():
    async with async_playwright() as p:
        print("🚀 Starting New Optimized Scraper Flow...")
        browser = await p.chromium.launch(headless=True)
        context = await browser.new_context(viewport={'width': 1920, 'height': 1080})
        page = await context.new_page()
        
        await page.goto(URL, wait_until="networkidle")
        
        # 1. Sequential Pair Clicks (Warm-up)
        for symbol in SYMBOLS:
            print(f"  - Clicking {symbol}...")
            try:
                btn = page.get_by_role("button", name=symbol, exact=True)
                await btn.click()
                await asyncio.sleep(3) # Wait 3 seconds as requested
            except:
                print(f"    [Error] Could not click {symbol}")

        # 2. Open Signal Log once
        print("📂 Opening Signal Log...")
        await page.locator('button.log-nav-btn').click()
        await asyncio.sleep(5) # Wait for table to populate
        
        # 3. Identify and Filter Trades
        trades = []
        rows = await page.locator('.log-table-wrapper div').filter(has_text="Active").all()
        
        # Get current time for the 5-min filter
        now = datetime.now()
        print(f"🔍 Scanning Log (Current UTC: {now.strftime('%H:%M')})")

        processed_texts = set()
        for row in rows:
            try:
                txt = await row.inner_text()
                if ("BUY" in txt or "SELL" in txt) and len(txt) > 30 and txt not in processed_texts:
                    processed_texts.add(txt)
                    
                    # Extract Data (Indices based on site structure)
                    # Date(1), StartTime(2), Symbol(3), Strategy(5), Signal(6), Entry(7), SL(8), TP(9)
                    cells = await row.locator('div').all()
                    if len(cells) < 10: continue
                    
                    start_time_str = (await cells[1].inner_text()).strip() # e.g. "12:45"
                    symbol_val = (await cells[2].inner_text()).strip()
                    signal_val = (await cells[5].inner_text()).strip().upper()
                    entry_val = (await cells[6].inner_text()).strip()
                    sl_val = (await cells[7].inner_text()).strip()
                    tp_val = (await cells[8].inner_text()).strip()
                    
                    # 4. Check if trade started within last 5 minutes
                    try:
                        trade_time = datetime.strptime(start_time_str, "%H:%M").replace(
                            year=now.year, month=now.month, day=now.day
                        )
                        # Handle day crossover if necessary (simple version)
                        time_diff = (now - trade_time).total_seconds() / 60
                        
                        if 0 <= time_diff <= 5:
                            print(f"✅ MATCH: {symbol_val} {signal_val} started {int(time_diff)} mins ago.")
                            trade_data = {
                                "id": f"{symbol_val}_{start_time_str}",
                                "symbol": symbol_val,
                                "signal": signal_val,
                                "entry": entry_val,
                                "sl": sl_val,
                                "tp": tp_val,
                                "status": "Active",
                                "time_identified": now.strftime("%Y-%m-%d %H:%M:%S")
                            }
                            trades.append(trade_data)
                            send_telegram_alert(trade_data)
                        else:
                            print(f"⏩ SKIPPED: {symbol_val} is too old ({int(time_diff)} mins ago).")
                    except:
                        print(f"⚠️ Could not parse time for {symbol_val}")

            except: continue

        # 5. Save and Finish
        with open(OUTPUT_FILE, "w") as f:
            json.dump(trades, f, indent=2)
        
        print(f"📊 Done. Sent {len(trades)} fresh trades to EA.")
        await browser.close()

if __name__ == "__main__":
    asyncio.run(run_new_flow())
