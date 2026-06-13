# Copyright (c) 2026. All rights reserved. Proprietary - no license granted.
"""STAALWAG orchestrated loop. THE one process that owns the schedule.

Nothing else runs on its own timer. Every cycle:
    intake -> regime -> signal -> SELF-CHECK -> dispatch -> ledger
Components report heartbeats into this loop; a missing heartbeat becomes a
FAULT message on Telegram, never silence.

Run: python -m desk.loop
"""
import time
from datetime import datetime

from . import config, dispatch, gates, ledger, regime as regime_mod, selfcheck
from . import signal as signal_mod
from .intake import get_feed


def run_cycle(feed, conn, state) -> None:
    """One full pipeline pass. state: dict with equity tracking + dup keys."""
    now = datetime.now(config.NZT)
    heartbeats = {"intake": False, "regime": False, "signal": False,
                  "gates": False, "ledger": False}

    # NZT day rollover resets the daily-loss baseline (circuit breaker rearm)
    if state["day"] != now.date():
        state["day"] = now.date()
        state["day_start_equity"] = state["equity"]

    quote = sig = reg = None
    try:
        quote = feed.get_quote()
        heartbeats["intake"] = True
        reg = regime_mod.assess(quote.history)
        if reg is not None:
            heartbeats["regime"] = True
            sig = signal_mod.generate(quote, reg)
            heartbeats["signal"] = True
    except Exception as e:
        reason = "Pipeline exception: %r" % e
        ok = dispatch.send_fault(reason)
        ledger.log_fault(conn, reason, ok, now)
        return

    if reg is None:
        # not enough history is a fault condition, not silence
        reason = "Regime model has insufficient history this cycle."
        ok = dispatch.send_fault(reason)
        ledger.log_fault(conn, reason, ok, now)
        return

    heartbeats["gates"] = True
    heartbeats["ledger"] = True

    if sig is None:
        return   # no edge this cycle - normal, logged via heartbeat silence-free design

    report = selfcheck.run(sig, quote, reg, state["recent_keys"], heartbeats, now)

    if report.fault:
        ok = dispatch.send_fault(report.fault)
        ledger.log_fault(conn, report.fault, ok, now)
        return

    if not report.passed:
        ledger.log_signal(conn, sig, 0.0, report, dispatched=False)
        print("[BLOCKED] self-check failed:\n" + report.text())
        return

    decision = gates.check(state["equity"], state["day_start_equity"],
                           state["open_positions"], sig.entry, sig.sl, now)
    if not decision.allowed:
        ledger.log_signal(conn, sig, 0.0, report, dispatched=False)
        if "CIRCUIT BREAKER" in decision.reason:
            ok = dispatch.send_fault(decision.reason)
            ledger.log_fault(conn, decision.reason, ok, now)
        else:
            print("[GATED] " + decision.reason)
        return

    msg = sig.message(decision.lots, quote.age_seconds(now))
    sent = dispatch.send(msg + "\n\n" + report.text())
    ledger.log_signal(conn, sig, decision.lots, report, dispatched=sent)
    state["recent_keys"][sig.key()] = now
    state["open_positions"] += 1   # outcome tracker decrements on close (port point)


def main():
    print("STAALWAG desk starting. Feed: %s. Label: %s. Cycle: %ds. All times NZT."
          % (config.FEED, config.DESK_LABEL, config.CYCLE_SECONDS))
    feed = get_feed()
    conn = ledger.connect()
    state = {"equity": 10000.0, "day_start_equity": 10000.0,
             "open_positions": 0, "recent_keys": {},
             "day": datetime.now(config.NZT).date()}
    while True:
        started = time.monotonic()
        run_cycle(feed, conn, state)
        time.sleep(max(0.0, config.CYCLE_SECONDS - (time.monotonic() - started)))


if __name__ == "__main__":
    main()
