import asyncio
from playwright.async_api import async_playwright

async def find_row_classes():
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        page = await browser.new_page()
        await page.goto("https://fx-trading-dashboard-v4.vercel.app/", wait_until="networkidle")
        
        # Click S&P500 and open log
        await page.get_by_role("button", name="S&P500", exact=True).click()
        await asyncio.sleep(5)
        await page.locator('button.log-nav-btn').click()
        await asyncio.sleep(5)
        
        # Look for the row containing a known value from the screenshot
        # If the screenshot row is gone, we'll look for ANY row with "Active"
        target = page.locator('text=Active').first
        if await target.count() > 0:
            print("Found an 'Active' element!")
            # Find the container row. It might be a div with a specific class.
            # We'll traverse up to find the parent that looks like a row.
            parent = target
            for _ in range(5): # Up to 5 levels
                parent = parent.locator('xpath=..')
                classes = await parent.get_attribute("class")
                tag = await parent.evaluate("el => el.tagName")
                print(f"Parent Tag: {tag}, Classes: {classes}")
        else:
            print("No 'Active' element found. Let's list all elements inside the log wrapper.")
            wrapper = page.locator('.log-table-wrapper')
            if await wrapper.count() > 0:
                inner_html = await wrapper.inner_html()
                print(f"Wrapper HTML length: {len(inner_html)}")
                # Print the first 500 chars of inner HTML
                print(f"Wrapper HTML snippet: {inner_html[:500]}")
            else:
                print("Log table wrapper not found!")

        await browser.close()

if __name__ == "__main__":
    asyncio.run(find_row_classes())
