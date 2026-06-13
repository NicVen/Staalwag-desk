# Copyright (c) 2026. All rights reserved. Proprietary - no license granted.
"""Sample deliverable generator.

Runs the real pipeline (same code paths as loop.py) over seeded dummy XAUUSD
data, simulates trade outcomes, and writes to samples/:
  sample_signal.txt        - one dispatched signal message
  sample_selfcheck.txt     - its self-check report
  sample_weekly_summary.txt- weekly performance summary from the ledger

Run: python -m desk.run_sample
"""
import random
from datetime import datetime, timedelta
from pathlib import Path

from . import config, gates, ledger, regime as regime_mod, selfcheck
from . import signal as signal_mod
from .intake import PaperFeed

SAMPLES = config.ROOT / "samples"
DB = config.ROOT / "sample_ledger.db"


def main():
    rng = random.Random(7)
    feed = PaperFeed(seed=42)
    if DB.exists():
        DB.unlink()
    conn = ledger.connect(DB)

    equity = 10000.0
    day_start = equity
    recent: dict[str, datetime] = {}
    open_positions = 0
    first_signal_txt = first_report_txt = None
    now = datetime.now(config.NZT) - timedelta(days=7)

    cycles = dispatched = 0
    while cycles < 5000 and conn.execute(
            "SELECT COUNT(*) FROM outcomes").fetchone()[0] < 14:
        cycles += 1
        now += timedelta(minutes=15)
        if now.date() != getattr(main, "_day", None):
            main._day = now.date()
            day_start = equity

        quote = feed.get_quote()
        quote.ts = now   # simulate historic timestamps
        reg = regime_mod.assess(quote.history)
        if reg is None:
            continue
        sig = signal_mod.generate(quote, reg)
        if sig is None:
            continue
        sig.ts = now

        heartbeats = {"intake": True, "regime": True, "signal": True,
                      "gates": True, "ledger": True}
        report = selfcheck.run(sig, quote, reg, recent, heartbeats, now)
        if not report.passed:
            ledger.log_signal(conn, sig, 0.0, report, dispatched=False)
            continue

        decision = gates.check(equity, day_start, open_positions,
                               sig.entry, sig.sl, now)
        if not decision.allowed:
            ledger.log_signal(conn, sig, 0.0, report, dispatched=False)
            continue

        msg = sig.message(decision.lots, quote.age_seconds(now))
        sid = ledger.log_signal(conn, sig, decision.lots, report, dispatched=True)
        recent[sig.key()] = now
        dispatched += 1
        if first_signal_txt is None:
            first_signal_txt, first_report_txt = msg, report.text()

        # simulate outcome: ~55% hit TP (placeholder until real edge ported)
        risk_usd = equity * gates.RISK_PER_TRADE
        rr = abs(sig.tp - sig.entry) / abs(sig.entry - sig.sl)
        if rng.random() < 0.55:
            pnl, result = risk_usd * rr, "WIN"
        else:
            pnl, result = -risk_usd, "LOSS"
        equity += pnl
        ledger.log_outcome(conn, sid, result, round(pnl, 2), round(equity, 2),
                           now + timedelta(hours=4))

    SAMPLES.mkdir(exist_ok=True)
    (SAMPLES / "sample_signal.txt").write_text(first_signal_txt or "no signal generated",
                                               encoding="utf-8")
    (SAMPLES / "sample_selfcheck.txt").write_text(first_report_txt or "n/a",
                                                  encoding="utf-8")
    summary = ledger.weekly_summary(conn)
    (SAMPLES / "sample_weekly_summary.txt").write_text(summary, encoding="utf-8")

    print("Sample run complete. Cycles: %d, dispatched: %d, final equity: %.2f"
          % (cycles, dispatched, equity))
    print()
    print(summary)


if __name__ == "__main__":
    main()
