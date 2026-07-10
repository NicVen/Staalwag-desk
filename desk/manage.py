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
from datetime import datetime, timezone
from . import config

MAX_HOLD_HOURS = 12   # a scalp that hasn't hit TP/SL by now exits at market —
                      # so one stuck trade can NEVER freeze the desk again.


def _conn():
    c = sqlite3.connect(str(config.LEDGER_PATH))
    c.execute("""CREATE TABLE IF NOT EXISTS open_trades(
        pair TEXT PRIMARY KEY, direction TEXT, entry REAL, sl REAL, tp REAL,
        be INT DEFAULT 0, opened TEXT)""")
    try:                       # migrate older DBs that predate the opened column
        c.execute("ALTER TABLE open_trades ADD COLUMN opened TEXT")
    except sqlite3.OperationalError:
        pass
    c.execute("""CREATE TABLE IF NOT EXISTS closed_trades(
        id INTEGER PRIMARY KEY AUTOINCREMENT, ts TEXT NOT NULL,
        pair TEXT, direction TEXT, entry REAL, exit REAL,
        result TEXT, pips REAL)""")
    return c


def _log_close(c, pair, direction, entry, exit_, result, pips):
    from datetime import datetime
    c.execute("INSERT INTO closed_trades(ts,pair,direction,entry,exit,result,pips) "
              "VALUES(?,?,?,?,?,?,?)",
              (datetime.utcnow().isoformat(), pair, direction, entry, exit_, result, pips))


def open_trade(sig) -> None:
    c = _conn()
    c.execute("INSERT OR REPLACE INTO open_trades(pair,direction,entry,sl,tp,be,opened) "
              "VALUES(?,?,?,?,?,0,?)",
              (sig.pair, sig.direction, sig.entry, sig.sl, sig.tp,
               datetime.now(timezone.utc).isoformat()))
    c.commit(); c.close()


def _alert(pair, direction, body) -> str:
    return "STAALWAG MANAGE — %s %s\n%s" % (pair, direction, body)


def check(price: float, pair: str = None) -> list[str]:
    """Compare live price to the open trade's levels; return VIP alerts."""
    c = _conn()
    alerts = []
    rows = c.execute("SELECT pair,direction,entry,sl,tp,be,opened FROM open_trades").fetchall()
    now = datetime.now(timezone.utc)
    for tpair, direction, entry, sl, tp, be, opened in rows:
        if pair is not None and tpair != pair:
            continue
        longd = direction in ("LONG", "BUY")
        half = entry + (tp - entry) * 0.5      # midpoint toward target
        reached = (lambda lvl: price >= lvl) if longd else (lambda lvl: price <= lvl)
        sl_hit = (price <= sl) if longd else (price >= sl)

        PIP = 0.1  # XAUUSD

        # TIME STOP: no open-time (legacy stuck row) or held too long -> exit at
        # market so the desk is never frozen at max-positions again.
        try:
            age_h = (now - datetime.fromisoformat(opened)).total_seconds() / 3600 if opened else 1e9
        except Exception:
            age_h = 1e9
        if age_h > MAX_HOLD_HOURS:
            sign = 1 if longd else -1
            pips = round((price - entry) / PIP * sign, 1)
            res = "WIN" if pips > 0 else ("LOSS" if pips < 0 else "BREAKEVEN")
            _log_close(c, tpair, direction, entry, price, res, pips)
            alerts.append(_alert(tpair, direction,
                "Time exit — %d h with no target hit, closed at market (%+.1f pips)." % (int(MAX_HOLD_HOURS), pips)))
            c.execute("DELETE FROM open_trades WHERE pair=?", (tpair,))
            continue

        if sl_hit:
            pips = -round(abs(entry - sl) / PIP, 1)
            _log_close(c, tpair, direction, entry, sl, "LOSS", pips)
            alerts.append(_alert(tpair, direction,
                "SL hit — trade closed (%+.1f pips). Capital protected, on to the next." % pips))
            c.execute("DELETE FROM open_trades WHERE pair=?", (tpair,))
            continue
        if reached(tp):
            pips = round(abs(tp - entry) / PIP, 1)
            _log_close(c, tpair, direction, entry, tp, "WIN", pips)
            alerts.append(_alert(tpair, direction,
                "TP hit 🎯 — target reached (+%.1f pips), close it. Trade DONE." % pips))
            c.execute("DELETE FROM open_trades WHERE pair=?", (tpair,))
            continue
        if not be and reached(half):
            alerts.append(_alert(tpair, direction,
                "In profit — move SL to BREAKEVEN. Trade is risk-free now; let it run to TP."))
            c.execute("UPDATE open_trades SET be=1 WHERE pair=?", (tpair,))
    c.commit(); c.close()
    return alerts
