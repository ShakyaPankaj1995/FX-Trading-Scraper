import streamlit as st
import pandas as pd
import json
import os
import time
from datetime import datetime

# Page Configuration
st.set_page_config(
    page_title="FX Master | Professional Signal Dashboard",
    page_icon="💎",
    layout="wide",
    initial_sidebar_state="expanded"
)

# Custom Styling for a "Proper" Dashboard
st.markdown("""
    <style>
    @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;700&display=swap');
    
    html, body, [class*="css"] {
        font-family: 'Inter', sans-serif;
    }
    
    .stMetric {
        background: rgba(255, 255, 255, 0.05);
        padding: 15px;
        border-radius: 12px;
        border: 1px solid rgba(255, 255, 255, 0.1);
    }
    
    .status-active {
        color: #00ff88;
        font-weight: bold;
    }
    
    .main-header {
        font-size: 2.5rem;
        font-weight: 700;
        background: linear-gradient(90deg, #00d2ff 0%, #3a7bd5 100%);
        -webkit-background-clip: text;
        -webkit-text-fill-color: transparent;
        margin-bottom: 2rem;
    }
    </style>
    """, unsafe_allow_html=True)

# Sidebar Info
with st.sidebar:
    st.image("https://cdn-icons-png.flaticon.com/512/2464/2464094.png", width=80)
    st.title("Settings")
    st.info("System is monitoring 6 major FX pairs 24/7 via GitHub Actions.")
    st.divider()
    st.caption("v2.0.0 | Connected to trades.json")

# Header
st.markdown('<h1 class="main-header">💎 FX Master Signal Dashboard</h1>', unsafe_allow_html=True)

DATA_FILE = "trades.json"

def load_data():
    if os.path.exists(DATA_FILE):
        try:
            with open(DATA_FILE, "r") as f:
                data = json.load(f)
            if not data:
                return pd.DataFrame()
            return pd.DataFrame(data)
        except Exception as e:
            st.error(f"Error reading signals: {e}")
            return pd.DataFrame()
    return pd.DataFrame()

# Main Dashboard Layout
df = load_data()

col1, col2, col3, col4 = st.columns(4)

if not df.empty:
    with col1:
        st.metric("Total Active", len(df))
    with col2:
        top_pair = df['symbol'].value_counts().idxmax() if not df.empty else "N/A"
        st.metric("Hot Pair", top_pair)
    with col3:
        st.metric("System Status", "Live", delta="OK")
    with col4:
        last_time = df['time_identified'].iloc[0] if 'time_identified' in df.columns else "N/A"
        st.metric("Latest Scan", last_time.split(" ")[1] if " " in last_time else last_time)

st.divider()

# Section 1: Active Signals Table
st.header("🚀 Currently Active Signals")
if not df.empty:
    # Use column config for a professional look
    st.dataframe(
        df,
        use_container_width=True,
        hide_index=True,
        column_config={
            "symbol": st.column_config.TextColumn("Pair", help="Currency pair identifier"),
            "entry": st.column_config.NumberColumn("Entry Price", format="%.5f"),
            "sl": st.column_config.NumberColumn("Stop Loss", format="%.5f"),
            "tp": st.column_config.NumberColumn("Take Profit", format="%.5f"),
            "time_identified": st.column_config.DatetimeColumn("Identified At", format="DD/MM/YYYY HH:mm"),
        }
    )
else:
    st.info("No active signals detected in the last scan. The system will auto-refresh when a trade is identified.")

# Section 2: Historical Log (Mock-up or based on history file if we add it)
st.divider()
st.header("📜 Signal Log History")
st.caption("Historical record of signals identified by the system.")
if not df.empty:
    # In a full system, we'd have a separate history file. 
    # For now, we show the current signals as they are identified.
    st.table(df[["time_identified", "symbol", "entry"]])
else:
    st.write("No history available.")

# Footer Auto-refresh
time.sleep(10)
st.rerun()
