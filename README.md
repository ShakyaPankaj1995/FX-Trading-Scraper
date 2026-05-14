# FX Trading Dashboard Scraper

This script automates the extraction of active trade signals from the FX Trading Dashboard.

## Prerequisites

- Python 3.8+
- [Playwright](https://playwright.dev/python/)

## Setup

1. **Install Playwright:**
   ```bash
   pip install playwright
   ```

2. **Install Chromium Browser:**
   ```bash
   playwright install chromium
   ```

## Usage

Run the script using Python:

```bash
python fx_scraper.py
```

### 4. Running the Streamlit Dashboard
```bash
pip install streamlit pandas
streamlit run app.py
```

## Features

- **Symbol Cycling:** Automatically iterates through EURUSD, GBPUSD, USDJPY, XAUUSD, S&P500, and NASDAQ.
- **JSON Output:** Saves all active trades to `trades.json` in a strictly formatted structure.
- **Interactive UI:** Built with **Streamlit** for a clean, auto-refreshing, and sortable table of signals.
- **Raw Text Server:** Includes `server.py` to serve the JSON as a plain text file for external integrations.
- **Cron Job Support:** Use the `--once` flag to run a single scan (ideal for server-side cron jobs).

## Usage

### 1. Running the Scraper (Continuous Loop)
```bash
python fx_scraper.py
```

### 2. Running for Cron Job
```bash
python fx_scraper.py --once
```

### 3. Starting the JSON Server
```bash
pip install flask
python server.py
```
