# Copyright (c) 2026. All rights reserved. Proprietary - no license granted.
"""SQLite ledger. Every signal, self-check, fault and outcome lands here.

This database is the Stage 2 product: the verified track record. Nothing is
ever deleted; rows are append-only.
"""
import sqlite3
from datetime import datetime

from . import config

SCHEMA = """
CREATE TABLE IF NOT EXISTS signals (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ts TEXT NOT NULL, pair TEXT NOT NULL, direction TEXT NOT NULL,
    entry REAL, sl REAL, tp REAL, lots REAL,
    regime TEXT, confidence REAL,
    selfcheck_passed INTEGER NOT NULL, selfcheck_report TEXT,
    dispatched INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS outcomes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    signal_id INTEGER NOT NULL REFERENCES signals(id),
    closed_ts TEXT NOT NULL, result TEXT NOT NULL,  -- WIN / LOSS / BREAKEVEN
    pnl_usd REAL NOT NULL, equity_after REAL
);
CREATE TABLE IF NOT EXISTS faults (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ts TEXT NOT NULL, reason TEXT NOT NULL, dispatched INTEGER NOT NULL
);
"""


def connect(path=None) -> sqlite3.Connection:
    conn = sqlite3.connect(str(path or config.LEDGER_PATH))
    conn.executescript(SCHEMA)
    return conn


def log_signal(conn, sig, lots, report, dispatched) -> int:
    cur = conn.execute(
        "INSERT INTO signals (ts,pair,direction,entry,sl,tp,lots,regime,confidence,"
        "selfcheck_passed,selfcheck_report,dispatched) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
        (sig.ts.isoformat(), sig.pair, sig.direction, sig.entry, sig.sl, sig.tp,
         lots, sig.regime, sig.confidence, int(report.passed), report.text(),
         int(dispatched)))
    conn.commit()
    return cur.lastrowid


def log_outcome(conn, signal_id, result, pnl_usd, equity_after,
                closed_ts: datetime | None = None):
    conn.execute(
        "INSERT INTO outcomes (signal_id,closed_ts,result,pnl_usd,equity_after) "
        "VALUES (?,?,?,?,?)",
        (signal_id, (closed_ts or datetime.now(config.NZT)).isoformat(),
         result, pnl_usd, equity_after))
    conn.commit()


def log_fault(conn, reason, dispatched, ts: datetime | None = None):
    conn.execute("INSERT INTO faults (ts,reason,dispatched) VALUES (?,?,?)",
                 ((ts or datetime.now(config.NZT)).isoformat(), reason, int(dispatched)))
    conn.commit()


def weekly_summary(conn) -> str:
    rows = conn.execute(
        "SELECT o.result, o.pnl_usd FROM outcomes o ORDER BY o.id").fetchall()
    if not rows:
        return "WEEKLY SUMMARY\nNo closed trades yet."

    wins = [p for r, p in rows if r == "WIN"]
    losses = [p for r, p in rows if r == "LOSS"]
    total = len(rows)
    win_rate = len(wins) / total * 100 if total else 0.0
    gross_win = sum(wins)
    gross_loss = abs(sum(losses))
    pf = gross_win / gross_loss if gross_loss > 0 else float("inf")

    # max drawdown on cumulative pnl
    equity, peak, max_dd = 0.0, 0.0, 0.0
    for _, p in rows:
        equity += p
        peak = max(peak, equity)
        max_dd = max(max_dd, peak - equity)

    n_signals = conn.execute("SELECT COUNT(*) FROM signals WHERE dispatched=1").fetchone()[0]
    n_blocked = conn.execute("SELECT COUNT(*) FROM signals WHERE selfcheck_passed=0").fetchone()[0]
    n_faults = conn.execute("SELECT COUNT(*) FROM faults").fetchone()[0]

    return ("STAALWAG WEEKLY SUMMARY (all figures from ledger, append-only)\n"
            "Closed trades: %d\n"
            "Win rate: %.1f%%\n"
            "Profit factor: %s\n"
            "Net P/L: %.2f USD\n"
            "Max drawdown: %.2f USD\n"
            "Signals dispatched: %d | blocked by self-check: %d | faults raised: %d\n"
            "Risk per trade: 1%% fixed. Daily loss cap: 2%%. Max positions: 1."
            % (total, win_rate,
               ("%.2f" % pf) if pf != float("inf") else "inf (no losses yet)",
               gross_win - gross_loss, max_dd, n_signals, n_blocked, n_faults))
