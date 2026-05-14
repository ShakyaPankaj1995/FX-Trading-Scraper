# Server Deployment & Cron Job Setup

This guide explains how to set up the FX Scraper and JSON server on a Linux-based VPS (like AWS, DigitalOcean, or Linode) to run automatically every 5 minutes.

## 1. Server Setup

First, install the necessary dependencies on your server:

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Python and Pip
sudo apt install python3 python3-pip -y

# Install Playwright and Flask
pip3 install playwright flask

# Install Playwright browser and system dependencies
playwright install chromium
sudo playwright install-deps chromium
```

## 2. Deploying the Code

Upload `fx_scraper.py` and `server.py` to a directory on your server (e.g., `/home/user/fx-scraper/`).

## 3. Setting up the Cron Job

A cron job will trigger the scraper every 5 minutes.

1. Open the crontab editor:
   ```bash
   crontab -e
   ```

2. Add the following line at the end of the file (replace paths with your actual paths):
   ```bash
   */5 * * * * /usr/bin/python3 /home/user/fx-scraper/fx_scraper.py --once >> /home/user/fx-scraper/scrape.log 2>&1
   ```
   *Note: Using `--once` tells the script to perform one scan and then exit, allowing cron to manage the timing.*

## 4. Running the JSON Server

To keep the JSON server running in the background, you can use `nohup` or a process manager like `pm2` or `systemd`.

**Using nohup:**
```bash
nohup python3 server.py > server.log 2>&1 &
```

Your JSON data will now be available at `http://your-server-ip:5000/` as raw text.

## 5. (Optional) Windows Setup via Task Scheduler

If you are staying on Windows:
1. Open **Task Scheduler**.
2. Click **Create Basic Task**.
3. Set Trigger to **Daily**, then in the final settings, set it to repeat every **5 minutes**.
4. Action: **Start a Program**.
   - Program/script: `python` (or full path to python.exe)
   - Arguments: `C:\path\to\fx_scraper.py --once`
