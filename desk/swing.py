# Copyright (c) 2026. All rights reserved. Proprietary - no license granted.
"""Paper test of the slow daily-trend rule on oil and crypto, owner's chat only.

These markets passed the strategy lab's prop-firm scan with this rule
(Wolf-Desk lab/scan.py, 2026-10-04): WTI PF 1.36, Brent 1.47, ETH 1.70,
SOL 2.86, XRP 2.40. Few trades, so it needs a live test before anyone trades it.

Rule (daily bars, completed days only): daily EMA50 above EMA200 and the close
breaks the prior 20-day high -> long (mirror for short). Entry at the next
day's open, stop 3x ATR14, no target, out at the close of the 20th day.
Everything is scored from completed daily bars, so results are exact and
never depend on when the desk happens to look. Never posts to a channel.
Off unless PAPER_CHAT_ID is set. Errors are logged and skipped.
"""
import time
from datetime import datetime, timezone

MARKETS = {"CL=F": "WTI oil", "BZ=F": "Brent oil", "ETH-USD": "Ethereum",
           "SOL-USD": "Solana", "XRP-USD": "XRP"}
LOOK, STOP_ATR, HOLD = 20, 3.0, 20
GOAL, PASS_PF = 30, 1.3
URL = "https://query1.finance.yahoo.com/v8/finance/chart/{sym}?range=2y&interval=1d"

SCHEMA = """
CREATE TABLE IF NOT EXISTS swing_trades (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    symbol TEXT NOT NULL, signal_t INTEGER NOT NULL, direction TEXT NOT NULL,
    entry_t INTEGER, entry REAL, sl REAL,
    exit_t INTEGER, exit REAL, result TEXT, r REAL,
    UNIQUE(symbol, signal_t)
);
"""


# ---------- pure rule ----------

def ema(xs, n):
    k, e, out = 2 / (n + 1), xs[0], []
    for x in xs:
        e = x * k + e * (1 - k)
        out.append(e)
    return out


def atr(bars, i, n=14):
    trs = [max(b["h"] - b["l"], abs(b["h"] - p["c"]), abs(b["l"] - p["c"]))
           for p, b in zip(bars[i - n:i], bars[i - n + 1:i + 1])]
    return sum(trs) / len(trs)


def signal(bars, i):
    """+1 / -1 / 0 at the close of completed daily bar i, and the stop distance."""
    if i < 220:
        return 0, 0.0
    c = [b["c"] for b in bars[:i + 1]]
    e50, e200 = ema(c, 50)[-1], ema(c, 200)[-1]
    hi = max(b["h"] for b in bars[i - LOOK:i])
    lo = min(b["l"] for b in bars[i - LOOK:i])
    if e50 > e200 and bars[i]["c"] > hi:
        return 1, STOP_ATR * atr(bars, i)
    if e50 < e200 and bars[i]["c"] < lo:
        return -1, STOP_ATR * atr(bars, i)
    return 0, 0.0


def settle(bars, k, d, entry, sl):
    """Walk completed bars from entry bar k. -> (exit_t, exit, why) or None if still open."""
    for j in range(k, len(bars)):
        b = bars[j]
        if (d > 0 and b["l"] <= sl) or (d < 0 and b["h"] >= sl):
            return b["t"], sl, "STOP"
        if j - k + 1 >= HOLD:
            return b["t"], b["c"], "20-DAY TIME EXIT"
    return None


def score(rs):
    g, l = sum(r for r in rs if r > 0), -sum(r for r in rs if r < 0)
    return len(rs), sum(r > 0 for r in rs), (g / l if l else (99.0 if g else 0.0)), sum(rs)


# ---------- live plumbing ----------

class SwingTest:
    def __init__(self, conn, send, session=None):
        self.conn, self.send = conn, send
        conn.executescript(SCHEMA)
        if session is None:
            import requests
            session = requests.Session()
            session.headers.update({"User-Agent": "Mozilla/5.0"})
        self.s = session
        self.last = 0.0

    def _bars(self, sym):
        res = self.s.get(URL.format(sym=sym), timeout=20).json()["chart"]["result"][0]
        q = res["indicators"]["quote"][0]
        now = time.time()
        out = []
        for t, o, h, l, c in zip(res["timestamp"], q["open"], q["high"], q["low"], q["close"]):
            if None not in (o, h, l, c) and t + 86400 <= now and l > 0:   # completed days only
                out.append({"t": t, "o": o, "h": h, "l": l, "c": c})
        return out

    def tick(self, now=None):
        """Look once an hour; everything is decided from completed daily bars."""
        if time.time() - self.last < 3600:
            return
        self.last = time.time()
        for sym in MARKETS:
            try:
                self.step(sym, self._bars(sym))
            except Exception as e:
                print("[SWING] %s skipped: %r" % (sym, e))

    def step(self, sym, bars):
        idx = {b["t"]: i for i, b in enumerate(bars)}
        # 1. fill and settle what is open
        for tid, sig_t, side, entry_t, entry, sl in self.conn.execute(
                "SELECT id, signal_t, direction, entry_t, entry, sl FROM swing_trades "
                "WHERE symbol=? AND exit_t IS NULL", (sym,)).fetchall():
            d = 1 if side == "BUY" else -1
            i = idx.get(sig_t)
            if i is None or i + 1 >= len(bars):
                continue
            if entry_t is None:     # entry = next day's open
                k = i + 1
                entry = bars[k]["o"]
                sl = entry - d * self._stop_dist(tid)
                self.conn.execute("UPDATE swing_trades SET entry_t=?, entry=?, sl=? WHERE id=?",
                                  (bars[k]["t"], entry, sl, tid))
                self.conn.commit()
                self.send("PAPER TEST (oil/crypto trend) #%d - NOT A SIGNAL\n%s %s filled at %.4g\n"
                          "Stop %.4g | no target | out after 20 days"
                          % (tid, MARKETS[sym], side, entry, sl))
            k = idx.get(self.conn.execute("SELECT entry_t FROM swing_trades WHERE id=?",
                                          (tid,)).fetchone()[0])
            if k is None:
                continue
            done = settle(bars, k, d, entry, sl)
            if done:
                self._close(tid, sym, side, d, entry, sl, *done)
        # 2. a new signal on the last completed day (one open trade per market)
        if self.conn.execute("SELECT 1 FROM swing_trades WHERE symbol=? AND exit_t IS NULL",
                             (sym,)).fetchone():
            return
        i = len(bars) - 1
        d, dist = signal(bars, i)
        if not d:
            return
        side = "BUY" if d > 0 else "SELL"
        cur = self.conn.execute(
            "INSERT OR IGNORE INTO swing_trades (symbol, signal_t, direction, sl) VALUES (?,?,?,?)",
            (sym, bars[i]["t"], side, dist))     # sl holds the stop DISTANCE until filled
        self.conn.commit()
        if cur.rowcount:
            self.send("PAPER TEST (oil/crypto trend) #%d - NOT A SIGNAL, do not trade\n"
                      "%s %s at tomorrow's open (closed at %.4g, 20-day breakout + daily trend)\n"
                      "Testing to %d calls." % (cur.lastrowid, MARKETS[sym], side, bars[i]["c"], GOAL))

    def _stop_dist(self, tid):
        return self.conn.execute("SELECT sl FROM swing_trades WHERE id=?", (tid,)).fetchone()[0]

    def _close(self, tid, sym, side, d, entry, sl, exit_t, exit_px, why):
        r = round(d * (exit_px - entry) / abs(entry - sl), 2)
        result = "WIN" if r > 0 else "LOSS" if r < 0 else "BREAKEVEN"
        self.conn.execute("UPDATE swing_trades SET exit_t=?, exit=?, result=?, r=? WHERE id=?",
                          (exit_t, exit_px, result, r, tid))
        self.conn.commit()
        n, w, pf, tot = score([x[0] for x in self.conn.execute(
            "SELECT r FROM swing_trades WHERE r IS NOT NULL")])
        verdict = ""
        if n >= GOAL:
            verdict = "\nVERDICT: %s (PF %.2f)" % ("PASSED" if pf >= PASS_PF else "NOT PASSED", pf)
        self.send("PAPER TEST (oil/crypto trend) #%d closed: %s %s, %s at %.4g\n"
                  "Result: %+.2fR (%s)\nScore so far: %d/%d calls, %d wins, PF %.2f, total %+.1fR%s"
                  % (tid, MARKETS[sym], side, why, exit_px, r, result, n, GOAL, w, pf, tot, verdict))


def start(conn):
    from . import dispatch, paper
    if not paper.PAPER_CHAT_ID:
        return None
    return SwingTest(conn, lambda text: dispatch._post(paper.PAPER_CHAT_ID, text))
