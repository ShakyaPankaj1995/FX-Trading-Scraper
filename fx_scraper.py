import asyncio
import time
import os
import json
import requests
from datetime import datetime
from playwright.async_api import async_playwright

# --- CONFIGURATION ---
URL = "https://fx-trading-dashboard-v4.vercel.app/"
SYMBOLS = ["EURUSD", "GBPUSD", "USDJPY", "XAUUSD", "S&P500", "NASDAQ"]
SCRAPE_INTERVAL_SECONDS = 300  # 5 minutes
OUTPUT_FILE = "trades.json"

# To enable telegram alerts, provide your details here
TELEGRAM_BOT_TOKEN = "" # e.g. "123456789:ABCDEF..."
TELEGRAM_CHAT_ID = ""   # e.g. "987654321"

def send_telegram_alert(trade, is_update=False):
    if not TELEGRAM_BOT_TOKEN or not TELEGRAM_CHAT_ID:
        return
    
    if is_update:
        message = f"📢 *Trade Update Alert*\n\n"
        message += f"💎 *Pair:* {trade['symbol']}\n"
        message += f"📊 *Strategy:* {trade['strategy']}\n"
        message += f"🏁 *New Status:* {trade['status'].upper()}\n"
        message += f"💵 *PNL:* {trade['pnl']}\n"
    else:
        message = f"🚀 *New FX Signal Found!*\n\n"
        message += f"💎 *Pair:* {trade['symbol']}\n"
        message += f"📊 *Strategy:* {trade['strategy']}\n"
        message += f"📈 *Entry:* {trade['entry']}\n"
        message += f"🛑 *SL:* {trade['sl']}\n"
        message += f"🎯 *TP:* {trade['tp']}\n"
    
    message += f"\n⏰ _Time: {trade['time_identified']}_"
    
    url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
    try:
        requests.post(url, json={"chat_id": TELEGRAM_CHAT_ID, "text": message, "parse_mode": "Markdown"})
        print(f"  [Telegram] {'Update' if is_update else 'New Alert'} sent for {trade['symbol']}")
    except Exception as e:
        print(f"  [Telegram Error] {e}")

async def scrape_active_trades(page, symbol):
    """
    Clicks a currency symbol, waits for the page to load, opens the Signal Log,
    and scrapes all active trades. Returns a list of trade dictionaries.
    """
    print(f"\n--- Processing {symbol} ---")
    trades = []
    
    try:
        # Ensure any previous modal is closed
        if await page.locator('.log-overlay').is_visible():
            close_btn = page.locator('.log-close-btn')
            if await close_btn.is_visible():
                await close_btn.click()
            else:
                await page.keyboard.press("Escape")
            await page.locator('.log-overlay').wait_for(state="hidden", timeout=5000)

        # --- ONE-TIME INITIALIZATION ---
        # On a fresh page load, we must trigger one scan to populate the global log data.
        # This only happens once per run.
        if symbol == SYMBOLS[0]:
            print("🔄 Initializing Signal Data (First Pair Scan)...")
            try:
                # Open log first to find the button
                await page.locator('button.log-nav-btn').click()
                await asyncio.sleep(2)
                scan_btn = page.locator('#scan-btn')
                if await scan_btn.is_visible():
                    await scan_btn.click()
                    print("  [Trigger] Global scan started...")
                    await asyncio.sleep(10) # Wait for initial data to load
                # Close log to start the pair-by-pair path
                await page.keyboard.press("Escape")
                await asyncio.sleep(2)
            except:
                pass

        # --- YOUR REQUESTED PATH START ---
        # 1. Click on the currency symbol button
        symbol_btn = page.get_by_role("button", name=symbol, exact=True)
        await symbol_btn.click()
        print(f"Clicked {symbol}. Waiting 5 seconds for dashboard update...")
        await asyncio.sleep(5)
        
        # 2. Open Signal Log
        log_btn = page.locator('button.log-nav-btn')
        await log_btn.click()
        print(f"Opened Signal Log for {symbol}.")
        await asyncio.sleep(5) # Give table time to render
        
        # 3. Scrape ONLY 'Active' status trades from the table
        # Using a much more robust selector to catch both .log-row and .log-table-row
        active_rows = await page.locator('.log-table-wrapper div').filter(has_text="Active").all()
        
        final_rows = []
        seen_ids = set()
        for el in active_rows:
            txt = await el.inner_text()
            # Ensure it's a full row containing a Signal (BUY/SELL)
            if ("BUY" in txt or "SELL" in txt) and len(txt) > 20:
                # Deduplicate based on content
                if txt[:50] not in seen_ids:
                    final_rows.append(el)
                    seen_ids.add(txt[:50])

        print(f"Found {len(final_rows)} active trade(s) in the log.")
        
        for row in final_rows:
            try:
                # Extract: Symbol(3), Strategy(5), Signal(6), Entry(7), SL(8), TP(9), Status(12)
                sym_val = (await row.locator('div:nth-child(3)').inner_text()).strip()
                strat_val = (await row.locator('div:nth-child(5)').inner_text()).strip()
                signal_val = (await row.locator('div:nth-child(6)').inner_text()).strip().upper()
                entry_val = (await row.locator('div:nth-child(7)').inner_text()).strip()
                sl_val = (await row.locator('div:nth-child(8)').inner_text()).strip()
                tp_val = (await row.locator('div:nth-child(9)').inner_text()).strip()
                status_val = "Active"
                
                # Unique ID for tracking (Symbol + Strategy + Entry)
                trade_id = f"{sym_val}_{strat_val}_{entry_val}"
                
                now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                trade_data = {
                    "id": trade_id,
                    "symbol": sym_val,
                    "strategy": strat_val,
                    "signal": signal_val,
                    "entry": entry_val,
                    "sl": sl_val,
                    "tp": tp_val,
                    "pnl": "0.0",
                    "status": status_val,
                    "time_identified": now
                }
                
                # Check for duplicates in the current list
                if not any(t["id"] == trade_id for t in trades):
                    trades.append(trade_data)
                    print(f"  [New] Captured active trade: {sym_val} {signal_val}")
                    send_telegram_alert(trade_data)
                        
            except Exception as e:
                print(f"  [Error] Failed to extract row data: {e}")
                        
            except Exception as e:
                print(f"  [Error] Failed to extract row data: {e}")

        # Close the Signal Log dialog
        close_btn = page.locator('.log-close-btn')
        if await close_btn.is_visible():
            await close_btn.click()
        else:
            await page.keyboard.press("Escape")
            
        # Wait for it to disappear so the next symbol button is clickable
        await page.locator('.log-overlay').wait_for(state="hidden", timeout=5000)
        await asyncio.sleep(1) 
        
    except Exception as e:
        print(f"Error scraping {symbol}: {e}")
        try:
            await page.keyboard.press("Escape")
            await asyncio.sleep(1)
        except:
            pass
            
    return trades

import argparse

async def main():
    parser = argparse.ArgumentParser(description="FX Dashboard Scraper")
    parser.add_argument("--once", action="store_true", help="Run once and exit (for cron jobs)")
    args = parser.parse_args()

    async with async_playwright() as p:
        print("Launching Headless Browser (Chromium)...")
        browser = await p.chromium.launch(headless=True)
        context = await browser.new_context(viewport={'width': 1280, 'height': 800})
        page = await context.new_page()

        try:
            while True:
                start_time = time.time()
                all_active_trades = []
                print(f"\n==========================================")
                print(f"SCRAPE CYCLE START: {time.strftime('%Y-%m-%d %H:%M:%S')}")
                print(f"==========================================")
                
                try:
                    await page.goto(URL, wait_until="networkidle")
                    
                    for symbol in SYMBOLS:
                        symbol_trades = await scrape_active_trades(page, symbol)
                        all_active_trades.extend(symbol_trades)
                    
                    # Update the JSON file with the latest trades
                    with open(OUTPUT_FILE, "w") as f:
                        json.dump(all_active_trades, f, indent=4)
                    print(f"\nSuccessfully updated {OUTPUT_FILE} with {len(all_active_trades)} trades.")
                    
                except Exception as e:
                    print(f"Critical error in cycle loop: {e}")
                
                if args.once:
                    print("Run-once mode enabled. Exiting.")
                    break

                elapsed = time.time() - start_time
                wait_time = max(0, SCRAPE_INTERVAL_SECONDS - elapsed)
                
                print(f"Cycle completed in {elapsed:.1f}s. Waiting {wait_time/60:.1f} mins...")
                await asyncio.sleep(wait_time)
                
        except KeyboardInterrupt:
            print("\nScraper stopped by user.")
        finally:
            await browser.close()

if __name__ == "__main__":
    asyncio.run(main())
