import asyncio
import time
import os
import json
from playwright.async_api import async_playwright

# Configuration
URL = "https://fx-trading-dashboard-v4.vercel.app/"
SYMBOLS = ["EURUSD", "GBPUSD", "USDJPY", "XAUUSD", "S&P500", "NASDAQ"]
SCRAPE_INTERVAL_SECONDS = 300  # 5 minutes
OUTPUT_FILE = "trades.json"

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

        # 1. Click on the currency symbol button
        symbol_btn = page.get_by_role("button", name=symbol, exact=True)
        await symbol_btn.click()
        print(f"Clicked {symbol}. Waiting 5 seconds for page load...")
        
        # 2. Wait 5 seconds for the page to fully load
        await asyncio.sleep(5)
        
        # 3. Click on Signal Log
        log_btn = page.locator('button.log-nav-btn')
        await log_btn.click()
        print("Opened Signal Log.")
        
        # 3.5. Click 'Scan Market' to ensure active trades are populated
        try:
            scan_btn = page.locator('#scan-btn') # ID identified from HTML inspection
            if await scan_btn.is_visible():
                print("Clicking 'Scan Market' to populate signals...")
                await scan_btn.click()
                # Wait for the scanning process to complete and rows to appear
                await asyncio.sleep(5) 
        except Exception as e:
            print(f"  [Info] Could not click Scan Market: {e}")

        # Wait for the log table rows to appear (if any)
        try:
            # Increase wait time to 10 seconds for data to fetch
            await page.wait_for_selector('.log-table-row', timeout=10000)
        except:
            pass
        
        # 4. Filter for 'active' status trades
        active_rows_locator = page.locator('.log-table-row').filter(has_text="Active")
        active_rows = await active_rows_locator.all()
        
        if not active_rows:
            print(f"No active trades found for {symbol}.")
        else:
            print(f"Found {len(active_rows)} active trade(s).")
            for row in active_rows:
                try:
                    # 5. Extract: Symbol (3rd), Entry Price (7th), SL (8th), TP (9th)
                    # Use indices identified by browser subagent
                    sym_val = (await row.locator('div:nth-child(3)').inner_text()).strip()
                    entry_val = (await row.locator('div:nth-child(7)').inner_text()).strip()
                    sl_val = (await row.locator('div:nth-child(8)').inner_text()).strip()
                    tp_val = (await row.locator('div:nth-child(9)').inner_text()).strip()
                    
                    trades.append({
                        "symbol": sym_val,
                        "entry": entry_val,
                        "sl": sl_val,
                        "tp": tp_val
                    })
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
