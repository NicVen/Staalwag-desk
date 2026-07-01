# Copyright (c) 2026. All rights reserved. Proprietary - no license granted.
"""STAALWAG gold trade management — the core VIP value.

Single-target gold scalp. Tracks each dispatched signal and watches price
each cycle, emitting VIP-only alerts as it develops:
  halfway (0.5R toward TP) -> move SL to breakeven (lock it risk-free)
  TP  -> target hit, close, done
  SL  -> stopped out, protect capital

State lives in SQLite (same DB as the ledger) so alerts survive Railway
restarts. One open trade at a time (single symbol).
"""
import sqlite3
from . import config


def _conn():
    c = sqlite3.connect(str(config.LEDGER_PATH))
    c.execute("""CREATE TABLE IF NOT EXISTS open_trades(
        pair TEXT PRIMARY KEY, direction TEXT, entry REAL, sl REAL, tp REAL,
        be INT DEFAULT 0)""")
    return c


def open_trade(sig) -> None:
    c = _conn()
    c.execute("INSERT OR REPLACE INTO open_trades(pair,direction,entry,sl,tp,be) "
              "VALUES(?,?,?,?,?,0)",
              (sig.pair, sig.direction, sig.entry, sig.sl, sig.tp))
    c.commit(); c.close()


def _alert(pair, direction, body) -> str:
    return "STAALWAG MANAGE — %s %s\n%s" % (pair, direction, body)


def check(price: float, pair: str = None) -> list[str]:
    """Compare live price to the open trade's levels; return VIP alerts."""
    c = _conn()
    alerts = []
    rows = c.execute("SELECT pair,direction,entry,sl,tp,be FROM open_trades").fetchall()
    for tpair, direction, entry, sl, tp, be in rows:
        if pair is not None and tpair != pair:
            continue
        longd = direction in ("LONG", "BUY")
        half = entry + (tp - entry) * 0.5      # midpoint toward target
        reached = (lambda lvl: price >= lvl) if longd else (lambda lvl: price <= lvl)
        sl_hit = (price <= sl) if longd else (price >= sl)

        if sl_hit:
            alerts.append(_alert(tpair, direction,
                "SL hit — trade closed. Capital protected, on to the next."))
            c.execute("DELETE FROM open_trades WHERE pair=?", (tpair,))
            continue
        if reached(tp):
            alerts.append(_alert(tpair, direction,
                "TP hit 🎯 — target reached, close it. Trade DONE."))
            c.execute("DELETE FROM open_trades WHERE pair=?", (tpair,))
            continue
        if not be and reached(half):
            alerts.append(_alert(tpair, direction,
                "In profit — move SL to BREAKEVEN. Trade is risk-free now; let it run to TP."))
            c.execute("UPDATE open_trades SET be=1 WHERE pair=?", (tpair,))
    c.commit(); c.close()
    return alerts
