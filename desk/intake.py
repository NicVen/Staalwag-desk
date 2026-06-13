# Copyright (c) 2026. All rights reserved. Proprietary - no license granted.
"""Market data intake.

Paper mode: synthetic XAUUSD ticks (random walk seeded for repeatability in
sample runs). Live mode: PORT POINT - wire to MT5 (MetaTrader5 package) or the
existing Railway feed here. The rest of the pipeline only sees Quote objects,
so swapping the source touches nothing else.
"""
import random
from dataclasses import dataclass, field
from datetime import datetime

from . import config


@dataclass
class Quote:
    pair: str
    bid: float
    ask: float
    ts: datetime                      # source timestamp (NZT)
    source: str
    history: list = field(default_factory=list)   # recent closes, oldest first

    @property
    def mid(self) -> float:
        return (self.bid + self.ask) / 2

    @property
    def spread(self) -> float:
        return self.ask - self.bid

    def age_seconds(self, now: datetime | None = None) -> float:
        now = now or datetime.now(config.NZT)
        return (now - self.ts).total_seconds()


class PaperFeed:
    """Synthetic XAUUSD feed. Deterministic when seeded."""

    def __init__(self, start_price: float = 3350.0, seed: int | None = None):
        self.rng = random.Random(seed)
        self.price = start_price
        self.closes: list[float] = []
        # warm up history so the regime model has something to chew on
        for _ in range(300):
            self._step()

    def _step(self):
        drift = self.rng.gauss(0.0, 1.0) * 1.8
        self.price = max(self.price + drift, 100.0)
        self.closes.append(self.price)
        if len(self.closes) > 600:
            self.closes.pop(0)

    def get_quote(self) -> Quote:
        self._step()
        spread = abs(self.rng.gauss(0.30, 0.08))
        now = datetime.now(config.NZT)
        return Quote(pair=config.PAIR,
                     bid=round(self.price - spread / 2, 2),
                     ask=round(self.price + spread / 2, 2),
                     ts=now, source="paper",
                     history=list(self.closes))


class Mt5Feed:
    """Live/demo feed via MetaTrader5 terminal (Windows only).

    Requires: python -m pip install MetaTrader5, MT5 terminal installed,
    and MT5_LOGIN / MT5_PASSWORD / MT5_SERVER in .env (plus optionally
    MT5_PATH to terminal64.exe and MT5_SYMBOL if broker names gold
    differently, e.g. XAUUSD.x or GOLD).
    """

    def __init__(self):
        import os
        import MetaTrader5 as mt5
        self.mt5 = mt5
        self.symbol = os.getenv("MT5_SYMBOL", config.PAIR)
        kwargs = {}
        path = os.getenv("MT5_PATH", "")
        if path:
            kwargs["path"] = path
        ok = mt5.initialize(
            login=int(os.getenv("MT5_LOGIN", "0")),
            password=os.getenv("MT5_PASSWORD", ""),
            server=os.getenv("MT5_SERVER", ""), **kwargs)
        if not ok:
            raise RuntimeError("MT5 initialize failed: %s" % str(mt5.last_error()))
        if not mt5.symbol_select(self.symbol, True):
            raise RuntimeError("MT5 cannot select symbol %s" % self.symbol)
        print("MT5 connected: %s on %s" % (self.symbol,
                                           os.getenv("MT5_SERVER", "?")))

    def get_quote(self) -> Quote:
        mt5 = self.mt5
        tick = mt5.symbol_info_tick(self.symbol)
        if tick is None:
            raise RuntimeError("MT5 returned no tick for %s" % self.symbol)
        rates = mt5.copy_rates_from_pos(self.symbol, mt5.TIMEFRAME_M15, 0, 600)
        if rates is None or len(rates) < 100:
            raise RuntimeError("MT5 returned insufficient history")
        closes = [float(r["close"]) for r in rates]
        if tick.bid == 0.0 or tick.ask == 0.0:
            raise RuntimeError("MT5 returned zero bid/ask for %s - market closed "
                               "or symbol not streaming." % self.symbol)
        ts = datetime.fromtimestamp(tick.time, tz=config.NZT)
        return Quote(pair=config.PAIR, bid=float(tick.bid), ask=float(tick.ask),
                     ts=ts, source="mt5:" + self.symbol, history=closes)

    def equity(self) -> float | None:
        info = self.mt5.account_info()
        return float(info.equity) if info else None


class WebFeed:
    """Railway-compatible XAUUSD feed via Twelve Data REST API.

    Free tier: 8 requests/min, 800/day. One quote + one history refresh per
    cycle = keep CYCLE_SECONDS >= 120 on Railway to stay inside the day cap.
    Requires TWELVEDATA_API_KEY in environment.
    """

    SYMBOL = "XAU/USD"

    def __init__(self):
        import truststore
        truststore.inject_into_ssl()
        import httpx
        self.httpx = httpx
        if not config.TWELVEDATA_API_KEY:
            raise RuntimeError("TWELVEDATA_API_KEY missing - get a free key at "
                               "twelvedata.com and set it in the environment.")
        self.closes: list[float] = []
        self.last_hist = 0.0

    def _get(self, endpoint: str, **params):
        params["apikey"] = config.TWELVEDATA_API_KEY
        params["symbol"] = self.SYMBOL
        r = self.httpx.get("https://api.twelvedata.com/" + endpoint,
                           params=params, timeout=20)
        data = r.json()
        if isinstance(data, dict) and data.get("status") == "error":
            raise RuntimeError("TwelveData error: %s" % data.get("message"))
        return data

    def get_quote(self) -> Quote:
        import time as _time
        # refresh 15-min history at most every 10 minutes (rate-limit budget)
        if _time.time() - self.last_hist > 600 or len(self.closes) < 100:
            series = self._get("time_series", interval="15min", outputsize=400)
            values = series.get("values", [])
            if len(values) < 100:
                raise RuntimeError("TwelveData returned insufficient history")
            self.closes = [float(v["close"]) for v in reversed(values)]
            self.last_hist = _time.time()

        q = self._get("price")
        price = float(q["price"])
        # REST quote has no bid/ask; synthesize a conservative spread so the
        # spread sanity check still constrains dispatch.
        spread = 0.40
        now = datetime.now(config.NZT)
        closes = self.closes[:-1] + [price]
        return Quote(pair=config.PAIR, bid=round(price - spread / 2, 2),
                     ask=round(price + spread / 2, 2),
                     ts=now, source="twelvedata", history=closes)


def get_feed():
    if config.FEED == "paper":
        return PaperFeed()
    if config.FEED == "mt5":
        return Mt5Feed()
    if config.FEED == "web":
        return WebFeed()
    raise RuntimeError("Unknown FEED=%r (use paper, mt5 or web)" % config.FEED)
