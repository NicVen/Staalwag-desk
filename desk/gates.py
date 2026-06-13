# Copyright (c) 2026. All rights reserved. Proprietary - no license granted.
"""GREED GATES.

These limits are constants in this file on purpose. They are not read from
.env, not read from the database, and there is no Telegram command that can
touch them. Changing them requires editing this file and restarting the desk,
which is exactly the friction they exist to create.

History: the account was blown by manual mid-trade overrides. This module is
the answer. Do not add an override path.
"""
from dataclasses import dataclass
from datetime import datetime

from . import config

RISK_PER_TRADE = 0.01        # max 1% of account per trade
MAX_DAILY_LOSS = 0.02        # 2% daily loss -> circuit breaker until next NZT day
MAX_CONCURRENT_POSITIONS = 1
# No martingale, no size increase after losses: position size is a pure
# function of (equity, stop distance). Past results are not an input.


@dataclass
class GateDecision:
    allowed: bool
    reason: str
    lots: float = 0.0


def position_size(equity: float, entry: float, sl: float,
                  usd_per_point_per_lot: float = 100.0) -> float:
    """Fixed-fraction size. XAUUSD: 1 lot ~= 100 USD per 1.00 move."""
    stop_points = abs(entry - sl)
    if stop_points <= 0:
        return 0.0
    risk_usd = equity * RISK_PER_TRADE
    lots = risk_usd / (stop_points * usd_per_point_per_lot)
    return round(max(lots, 0.0), 2)


def check(equity: float, day_start_equity: float, open_positions: int,
          entry: float, sl: float, now: datetime | None = None) -> GateDecision:
    """All greed gates in one place. Called before every dispatch."""
    now = now or datetime.now(config.NZT)

    daily_loss = (day_start_equity - equity) / day_start_equity if day_start_equity > 0 else 0.0
    if daily_loss >= MAX_DAILY_LOSS:
        return GateDecision(False, "CIRCUIT BREAKER: daily loss %.2f%% >= %.2f%%. "
                                   "Desk halted until next NZT day."
                                   % (daily_loss * 100, MAX_DAILY_LOSS * 100))

    if open_positions >= MAX_CONCURRENT_POSITIONS:
        return GateDecision(False, "Max concurrent positions (%d) reached."
                                   % MAX_CONCURRENT_POSITIONS)

    lots = position_size(equity, entry, sl)
    if lots <= 0:
        return GateDecision(False, "Position size computed as zero (bad stop distance).")

    return GateDecision(True, "Gates passed: risk %.1f%%, lots %.2f"
                              % (RISK_PER_TRADE * 100, lots), lots)
