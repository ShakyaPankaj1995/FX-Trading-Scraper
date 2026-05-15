import asyncio
import json
import requests
from datetime import datetime, timedelta
from playwright.async_api import async_playwright

# --- CONFIGURATION ---
URL = "https://fx-trading-dashboard-v4.vercel.app/"
SYMBOLS = ["EURUSD", "GBPUSD", "USDJPY", "XAUUSD", "S&P500", "NASDAQ"]
OUTPUT_FILE = "trades.json"
FRESHNESS_MINUTES = 5  # Only capture trades started within this window

# To enable Telegram alerts, fill in your credentials:
TELEGRAM_BOT_TOKEN = ""
TELEGRAM_CHAT_ID = ""

def send_telegram_alert(trade):
    if not TELEGRAM_BOT_TOKEN or not TELEGRAM_CHAT_ID:
        return
    msg = (
        f"New FX Signal: {trade['symbol']} {trade['signal']}\n"
        f"Entry: {trade['entry']}\nSL: {trade['sl']}\nTP: {trade['tp']}\n"
        f"Strategy: {trade['strategy']} | Time: {trade['trade_time']}"
    )
    try:
        requests.post(
            f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage",
            json={"chat_id": TELEGRAM_CHAT_ID, "text": msg},
            timeout=5
        )
    except:
        pass

async def run_scraper():
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        context = await browser.new_context(viewport={"width": 1920, "height": 1080})
        page = await context.new_page()

        print("--- FX Scraper Starting ---")
        await page.goto(URL, wait_until="networkidle")
        await asyncio.sleep(3)

        # STEP 1: Click each pair sequentially (3s between each)
        print("Warming up: Clicking all pairs...")
        for symbol in SYMBOLS:
            try:
                await page.get_by_role("button", name=symbol, exact=True).click()
                print(f"  Clicked: {symbol}")
                await asyncio.sleep(3)
            except Exception as e:
                print(f"  [Error] Could not click {symbol}: {e}")

        # STEP 2: Click Signal Log button
        print("Opening Signal Log...")
        await page.locator("button.log-nav-btn").click()
        await asyncio.sleep(5)

        # STEP 3: Scrape .log-row-active rows (rows that are Active)
        # The site uses <tr class="log-row log-row-active"> for active trades
        active_rows = await page.locator("tr.log-row-active").all()
        print(f"Found {len(active_rows)} active trade row(s).")

        now = datetime.now()
        trades = []

        for row in active_rows:
            try:
                # Extract each <td> cell
                cells = await row.locator("td").all()
                cell_texts = []
                for c in cells:
                    cell_texts.append((await c.inner_text()).strip())

                # Map cells to fields based on confirmed structure
                date_str    = cell_texts[0] if len(cell_texts) > 0 else ""
                time_str    = cell_texts[1] if len(cell_texts) > 1 else ""
                symbol_val  = cell_texts[2] if len(cell_texts) > 2 else ""
                tf_val      = cell_texts[3] if len(cell_texts) > 3 else ""
                strat_val   = cell_texts[4] if len(cell_texts) > 4 else ""
                signal_val  = cell_texts[5].replace("\n", "").strip() if len(cell_texts) > 5 else ""
                entry_val   = cell_texts[6] if len(cell_texts) > 6 else ""
                sl_val      = cell_texts[7] if len(cell_texts) > 7 else ""
                tp_val      = cell_texts[8] if len(cell_texts) > 8 else ""

                # Clean BUY/SELL from signal (may have SVG text)
                if "BUY" in signal_val.upper():
                    signal_val = "BUY"
                elif "SELL" in signal_val.upper():
                    signal_val = "SELL"
                else:
                    print(f"  [Skip] Unrecognized signal: '{signal_val}'")
                    continue

                print(f"  Row: {symbol_val} {signal_val} | Entry:{entry_val} SL:{sl_val} TP:{tp_val} | Time:{time_str}")

                # STEP 4: 5-minute freshness filter
                is_fresh = True
                age_mins = -1

                if time_str:
                    for fmt in ["%I:%M %p", "%H:%M", "%I:%M%p"]:
                        try:
                            parsed = datetime.strptime(time_str.strip(), fmt)
                            trade_time = parsed.replace(year=now.year, month=now.month, day=now.day)
                            age_mins = (now - trade_time).total_seconds() / 60
                            if age_mins < -60:   # Handle midnight rollover
                                age_mins += 1440
                            is_fresh = 0 <= age_mins <= FRESHNESS_MINUTES
                            break
                        except:
                            continue

                if age_mins >= 0:
                    status = "MATCH (sending to EA)" if is_fresh else f"SKIPPED ({age_mins:.1f} min old)"
                    print(f"    -> {status}")
                else:
                    print(f"    -> Time parse failed for '{time_str}', including by default")

                if is_fresh:
                    trade_data = {
                        "id": f"{symbol_val}_{time_str.replace(':', '').replace(' ', '')}_{entry_val}",
                        "symbol": symbol_val,
                        "timeframe": tf_val,
                        "strategy": strat_val,
                        "signal": signal_val,
                        "entry": entry_val,
                        "sl": sl_val,
                        "tp": tp_val,
                        "status": "Active",
                        "trade_time": f"{date_str} {time_str}",
                        "time_identified": now.strftime("%Y-%m-%d %H:%M:%S")
                    }
                    trades.append(trade_data)
                    send_telegram_alert(trade_data)

            except Exception as e:
                print(f"  [Error] Failed to process row: {e}")

        # STEP 5: Save to trades.json
        with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
            json.dump(trades, f, indent=2)

        print(f"\n--- Done. {len(trades)} fresh trade(s) sent to EA via trades.json ---")
        await browser.close()

if __name__ == "__main__":
    asyncio.run(run_scraper())
