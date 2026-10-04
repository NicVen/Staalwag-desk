# Copyright (c) 2026. All rights reserved. Proprietary - no license granted.
"""Paper test of the candidate Gold rule, sent to the owner's chat only.

Rule (won the strategy lab, PF 1.36 over 2 years, both halves > 1.3):
  on each completed 1h bar, close breaks the prior 20-bar high (low),
  close is above (below) the 1h EMA200, and the daily EMA50 is above (below)
  the daily EMA200 -> long (short). Stop 2x ATR14, target 3R, out after 48h.

It never posts to the channel and never touches the live rule. It keeps its own
table (paper_trades) in the desk ledger so every result, losses included, is
kept. Off unless PAPER_CHAT_ID is set. Any error here is logged and skipped:
the paper test can never stop the live desk.
"""
import os
import time
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from . import config

PAPER_CHAT_ID = os.getenv("PAPER_CHAT_ID", "")
# CHANNEL_RULE=new: this rule posts real calls to the channel (VIP_CHAT_ID)
# instead of the old one, and its results also land in closed_trades (pips)
# so HQ's channel record carries on. Default "old": paper test only.
CHANNEL_RULE = os.getenv("CHANNEL_RULE", "old").lower()
PIP = 0.1   # XAUUSD
LOOK, STOP_ATR, TARGET_R, MAX_HOLD_H = 20, 2.0, 3.0, 48
GOAL = 30          # calls before a verdict
PASS_PF = 1.3

URL = "https://query1.finance.yahoo.com/v8/finance/chart/GC=F?range={rng}&interval={iv}"

SCHEMA = """
CREATE TABLE IF NOT EXISTS paper_trades (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    rule TEXT NOT NULL, opened_ts TEXT NOT NULL, bar_ts INTEGER NOT NULL,
    direction TEXT NOT NULL, entry REAL NOT NULL, sl REAL NOT NULL, tp REAL NOT NULL,
    closed_ts TEXT, exit REAL, result TEXT, r REAL
);
"""
RULE = "breakout+trend+daily"


# ---------- pure rule (tested in test_paper.py) ----------

def ema(xs, n):
    k, e, out = 2 / (n + 1), xs[0], []
    for x in xs:
        e = x * k + e * (1 - k)
        out.append(e)
    return out


def atr(bars, n=14):
    trs = [max(b["h"] - b["l"], abs(b["h"] - p["c"]), abs(b["l"] - p["c"]))
           for p, b in zip(bars[-n - 1:-1], bars[-n:])]
    return sum(trs) / len(trs)


def daily_trend(daily, before_day):
    """+1/-1/0 from daily EMA50 vs EMA200 at the last daily close before before_day."""
    days = [d for d in daily if _day(d["t"]) < before_day]
    if len(days) < 200:
        return 0
    c = [d["c"] for d in days]
    e50, e200 = ema(c, 50)[-1], ema(c, 200)[-1]
    return 1 if e50 > e200 else -1 if e50 < e200 else 0


@dataclass
class Setup:
    direction: int      # +1 long, -1 short
    stop_dist: float
    bar_ts: int


def check(hourly, daily):
    """hourly = completed 1h bars, oldest first. Returns Setup or None."""
    if len(hourly) < 220:
        return None
    last = hourly[-1]
    prior = hourly[-LOOK - 1:-1]
    hi, lo = max(b["h"] for b in prior), min(b["l"] for b in prior)
    e200 = ema([b["c"] for b in hourly], 200)[-1]
    trend = daily_trend(daily, _day(last["t"]))
    d = 0
    if last["c"] > hi and last["c"] > e200 and trend == 1:
        d = 1
    elif last["c"] < lo and last["c"] < e200 and trend == -1:
        d = -1
    if not d:
        return None
    return Setup(d, STOP_ATR * atr(hourly), last["t"])


def score(rows):
    """rows = closed R values. -> (n, wins, pf, total_r)."""
    gain = sum(r for r in rows if r > 0)
    loss = -sum(r for r in rows if r < 0)
    pf = gain / loss if loss else (99.0 if gain else 0.0)
    return len(rows), sum(r > 0 for r in rows), pf, sum(rows)


def _day(t):
    return datetime.fromtimestamp(t, tz=timezone.utc).date()


# ---------- live plumbing ----------

class PaperTest:
    def __init__(self, conn, send, session=None, live=False):
        self.conn, self.send, self.live = conn, send, live
        conn.executescript(SCHEMA)
        if live:
            conn.execute("""CREATE TABLE IF NOT EXISTS closed_trades(
                id INTEGER PRIMARY KEY AUTOINCREMENT, ts TEXT NOT NULL,
                pair TEXT, direction TEXT, entry REAL, exit REAL,
                result TEXT, pips REAL)""")
        if session is None:
            import requests
            session = requests.Session()
            session.headers.update({"User-Agent": "Mozilla/5.0"})
        self.s = session
        self.last_key = 0
        self.daily, self.daily_at = [], 0.0

    def _bars(self, rng, iv):
        res = self.s.get(URL.format(rng=rng, iv=iv), timeout=20).json()["chart"]["result"][0]
        q = res["indicators"]["quote"][0]
        out = []
        for t, o, h, l, c in zip(res["timestamp"], q["open"], q["high"], q["low"], q["close"]):
            if None not in (o, h, l, c):
                out.append({"t": t, "o": o, "h": h, "l": l, "c": c})
        return out

    def _open(self):
        return self.conn.execute(
            "SELECT id, direction, entry, sl, tp, opened_ts FROM paper_trades "
            "WHERE closed_ts IS NULL ORDER BY id DESC LIMIT 1").fetchone()

    def tick(self, price, now=None):
        """price = current spot mid. Manage the open paper trade, then look for a new one."""
        now = now or datetime.now(config.NZT)
        row = self._open()
        if row:
            self._manage(row, price, now)
            return
        self._scan(price, now)

    def _manage(self, row, price, now):
        tid, side, entry, sl, tp, opened = row
        d = 1 if side == "BUY" else -1
        risk = abs(entry - sl)
        why = None
        if d * (price - sl) <= 0:
            why, exit_px = "STOP", sl
        elif d * (price - tp) >= 0:
            why, exit_px = "TARGET", tp
        elif now - datetime.fromisoformat(opened) >= timedelta(hours=MAX_HOLD_H):
            why, exit_px = "48H TIME-STOP", price
        if not why:
            return
        r = round(d * (exit_px - entry) / risk, 2)
        result = "WIN" if r > 0 else "LOSS" if r < 0 else "BREAKEVEN"
        self.conn.execute("UPDATE paper_trades SET closed_ts=?, exit=?, result=?, r=? WHERE id=?",
                          (now.isoformat(), exit_px, result, r, tid))
        if self.live:   # the channel's own record (HQ reads it in pips)
            self.conn.execute(
                "INSERT INTO closed_trades(ts,pair,direction,entry,exit,result,pips) "
                "VALUES(?,?,?,?,?,?,?)",
                (now.astimezone(timezone.utc).replace(tzinfo=None).isoformat(), config.PAIR,
                 side, entry, exit_px, result, round(d * (exit_px - entry) / PIP, 1)))
        self.conn.commit()
        n, w, pf, tot = score([x[0] for x in self.conn.execute(
            "SELECT r FROM paper_trades WHERE r IS NOT NULL AND rule=?", (RULE,))])
        verdict = ""
        if n >= GOAL:
            verdict = ("\nVERDICT: PASSED (PF %.2f >= %.1f)" % (pf, PASS_PF) if pf >= PASS_PF
                       else "\nVERDICT: NOT PASSED (PF %.2f < %.1f)" % (pf, PASS_PF))
        head = "STAALWAG GOLD #%d closed" % tid if self.live else "PAPER TEST #%d closed" % tid
        self.send("%s: %s %s at %.2f\nResult: %+.2fR (%s)\n"
                  "Score so far: %d/%d calls, %d wins, PF %.2f, total %+.1fR%s"
                  % (head, side, why, exit_px, r, result, n, GOAL, w, pf, tot, verdict))

    def _scan(self, price, now):
        # one look per hour, 2 min after the hour so the closed bar is published
        t = time.time()
        key = int(t - 120) // 3600
        if key <= self.last_key:
            return
        hourly = [b for b in self._bars("60d", "60m") if b["t"] + 3600 <= t]
        if time.time() - self.daily_at > 6 * 3600:
            self.daily, self.daily_at = self._bars("5y", "1d"), time.time()
        self.last_key = key
        st = check(hourly, self.daily)
        if st is None:
            return
        if self.conn.execute("SELECT 1 FROM paper_trades WHERE bar_ts=?", (st.bar_ts,)).fetchone():
            return
        side = "BUY" if st.direction > 0 else "SELL"
        entry = round(price, 2)
        sl = round(entry - st.direction * st.stop_dist, 2)
        tp = round(entry + st.direction * TARGET_R * st.stop_dist, 2)
        cur = self.conn.execute(
            "INSERT INTO paper_trades (rule, opened_ts, bar_ts, direction, entry, sl, tp) "
            "VALUES (?,?,?,?,?,?,?)", (RULE, now.isoformat(), st.bar_ts, side, entry, sl, tp))
        self.conn.commit()
        if self.live:
            self.send("STAALWAG GOLD SIGNAL #%d\n%s XAUUSD (spot) at %.2f\n"
                      "SL %.2f (%.0f pips) | TP %.2f (%.0f pips)\n"
                      "Exit at market after 48h if neither is hit.\n"
                      "New rule in its live test: call %d of %d, every result posted.\n"
                      "Risk: your call. Not financial advice."
                      % (cur.lastrowid, side, entry, sl, abs(entry - sl) / PIP, tp,
                         abs(tp - entry) / PIP, self._count() + 1, GOAL))
            return
        self.send("PAPER TEST #%d - NOT A SIGNAL, do not trade\n"
                  "Gold (spot) %s at %.2f\nSL %.2f | TP %.2f (3R) | out after 48h\n"
                  "Rule: 20h breakout + 200h trend + daily trend. Testing to %d calls."
                  % (cur.lastrowid, side, entry, sl, tp, GOAL))

    def _count(self):
        return self.conn.execute("SELECT COUNT(*) FROM paper_trades WHERE r IS NOT NULL "
                                 "AND rule=?", (RULE,)).fetchone()[0]


def start(conn):
    """The new rule: live in the channel (CHANNEL_RULE=new), paper test in the
    owner's chat (PAPER_CHAT_ID), or None."""
    from . import dispatch
    if CHANNEL_RULE == "new":
        return PaperTest(conn, dispatch.send_vip, live=True)
    if not PAPER_CHAT_ID:
        return None
    return PaperTest(conn, lambda text: dispatch._post(PAPER_CHAT_ID, text))
