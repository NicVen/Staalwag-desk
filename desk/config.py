# Copyright (c) 2026. All rights reserved. Proprietary - no license granted.
"""STAALWAG configuration.

Operational settings live in .env. Risk limits do NOT - they are hard-coded
in gates.py and cannot be changed from Telegram or environment.
"""
import os
from pathlib import Path
from zoneinfo import ZoneInfo

from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parent.parent
load_dotenv(ROOT / ".env", override=True)

NZT = ZoneInfo("Pacific/Auckland")

PAIR = "XAUUSD"

# Operational (not risk) settings
TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "")
TELEGRAM_CHAT_ID = os.getenv("TELEGRAM_CHAT_ID", "")
PAPER_MODE = os.getenv("PAPER_MODE", "true").lower() == "true"
# FEED: paper | mt5 | web. Default keeps old PAPER_MODE behaviour.
FEED = os.getenv("FEED", "paper" if PAPER_MODE else "mt5").lower()
TWELVEDATA_API_KEY = os.getenv("TWELVEDATA_API_KEY", "")
CYCLE_SECONDS = int(os.getenv("CYCLE_SECONDS", "60"))
DESK_LABEL = os.getenv("DESK_LABEL", "PC")   # shows in messages: PC / RAILWAY
STYLE = os.getenv("STYLE", "Scalp")          # trade horizon shown on signals (15m engine)

# Self-check thresholds
DATA_FRESHNESS_MAX_S = 120          # discard data older than this
MAX_SPREAD_USD = 0.80               # XAUUSD spread limit
DUPLICATE_LOOKBACK_MIN = 60         # same signal not resent within this window
MIN_RR = 1.0                        # reward:risk must be at least this

# On Railway: mount a volume and set LEDGER_PATH=/data/staalwag.db,
# otherwise the ledger dies on every redeploy.
LEDGER_PATH = Path(os.getenv("LEDGER_PATH", str(ROOT / "staalwag.db")))
