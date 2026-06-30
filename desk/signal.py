# Copyright (c) 2026. All rights reserved. Proprietary - no license granted.
"""Signal generation.

PORT POINT: this is a deliberately simple momentum edge standing in for the
real edge logic (Excalibur/BLOUSTAAL rules + Railway scanner logic). Swap the
body of generate(); the Signal contract stays fixed - that contract is the
deliverable spec in the README.
"""
from dataclasses import dataclass
from datetime import datetime

from . import config
from .intake import Quote
from .regime import RegimeView

ATR_LOOKBACK = 14
SL_ATR = 1.5
TP_ATR = 2.5


@dataclass
class Signal:
    pair: str
    direction: str        # LONG / SHORT
    entry: float
    sl: float
    tp: float
    regime: str
    confidence: float
    ts: datetime          # NZT

    def key(self) -> str:
        return "%s:%s" % (self.pair, self.direction)

    def message(self, lots: float, freshness_s: float) -> str:
        return ("STAALWAG SIGNAL\n"
                "Style: %s\n" % config.STYLE +
                "Pair: %s\n"
                "Direction: %s\n"
                "Entry: %.2f\n"
                "SL: %.2f\n"
                "TP: %.2f\n"
                "Size: %.2f lots (1%% risk, fixed)\n"
                "Regime: %s (confidence %.2f)\n"
                "Time: %s NZT\n"
                "Data freshness: %.0fs (limit %ds) - PASS"
                % (self.pair, self.direction, self.entry, self.sl, self.tp,
                   lots, self.regime, self.confidence,
                   self.ts.strftime("%Y-%m-%d %H:%M:%S"),
                   freshness_s, config.DATA_FRESHNESS_MAX_S))


def _atr_proxy(closes: list[float]) -> float:
    diffs = [abs(b - a) for a, b in zip(closes[-ATR_LOOKBACK - 1:], closes[-ATR_LOOKBACK:])]
    return sum(diffs) / len(diffs) if diffs else 0.0


def generate(quote: Quote, regime: RegimeView) -> Signal | None:
    closes = quote.history
    if len(closes) < 60:
        return None

    fast = sum(closes[-10:]) / 10
    slow = sum(closes[-50:]) / 50
    atr = _atr_proxy(closes)
    if atr <= 0:
        return None

    if fast > slow and regime.state == "BULL":
        direction, entry = "LONG", quote.ask
        sl, tp = entry - SL_ATR * atr, entry + TP_ATR * atr
    elif fast < slow and regime.state == "BEAR":
        direction, entry = "SHORT", quote.bid
        sl, tp = entry + SL_ATR * atr, entry - TP_ATR * atr
    else:
        return None

    return Signal(pair=quote.pair, direction=direction,
                  entry=round(entry, 2), sl=round(sl, 2), tp=round(tp, 2),
                  regime=regime.state, confidence=regime.confidence,
                  ts=datetime.now(config.NZT))
