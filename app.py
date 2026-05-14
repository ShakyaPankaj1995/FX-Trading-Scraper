import streamlit as st
import pandas as pd
import json
import os
import time

# Page Configuration
st.set_page_config(
    page_title="FX Signal Tracker",
    page_icon="📈",
    layout="wide"
)

# Custom CSS for premium look
st.markdown("""
    <style>
    .main {
        background-color: #0e1117;
    }
    .stDataFrame {
        border-radius: 10px;
        overflow: hidden;
        box-shadow: 0 4px 15px rgba(0,0,0,0.3);
    }
    h1 {
        color: #00d2ff;
        font-family: 'Inter', sans-serif;
    }
    </style>
    """, unsafe_allow_html=True)

st.title("📈 Active FX Trade Signals")
st.subheader("Live Market Scraper Dashboard")

DATA_FILE = "trades.json"

# Auto-refresh logic
def load_data():
    if os.path.exists(DATA_FILE):
        try:
            with open(DATA_FILE, "r") as f:
                data = json.load(f)
            if not data:
                return None
            return pd.DataFrame(data)
        except Exception as e:
            st.error(f"Error loading JSON: {e}")
            return None
    return None

# Placeholder for the table
table_placeholder = st.empty()
info_placeholder = st.empty()

# The user wants auto-refreshing, so we use a loop with a sleep timer
# Note: In a production Streamlit app, you might use st_autorefresh, 
# but for a standalone script, this loop pattern works effectively.
while True:
    df = load_data()
    
    with table_placeholder.container():
        if df is not None:
            # Display interactive dataframe
            st.dataframe(
                df, 
                use_container_width=True, 
                height=500,
                column_config={
                    "symbol": "Currency Pair",
                    "entry": "Entry Price",
                    "sl": st.column_config.NumberColumn("Stop Loss", format="%.5f"),
                    "tp": st.column_config.NumberColumn("Take Profit", format="%.5f"),
                }
            )
        else:
            st.info("Searching for active signals... (Ensure the scraper is running)")

    with info_placeholder.container():
        st.caption(f"Last UI Refresh: {time.strftime('%H:%M:%S')} | Data Source: {DATA_FILE}")

    # Sleep for a short duration before checking for file updates again
    time.sleep(10) 
    # st.rerun() # Optional: triggers a full script rerun
