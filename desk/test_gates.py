# Copyright (c) 2026. All rights reserved. Proprietary - no license granted.
"""Failure-path tests. Run any time: python -m desk.test_gates

Proves: stale data blocked, dead heartbeat -> FAULT dispatched (never silence),
duplicate guard, 2% circuit breaker, max-1-position gate, size shrinks after
loss (no martingale possible).
"""
from datetime import datetime, timedelta

from . import config, dispatch, gates, selfcheck
from . import regime as rm, signal as sm
from .intake import PaperFeed


def main():
    feed = PaperFeed(seed=42)
    sig = q = reg = None
    for _ in range(3000):
        q = feed.get_quote()
        reg = rm.assess(q.history)
        sig = sm.generate(q, reg)
        if sig:
            break
    assert sig, "no signal generated in 3000 ticks"
    now = datetime.now(config.NZT)
    hb = dict(intake=True, regime=True, signal=True, gates=True, ledger=True)

    r = selfcheck.run(sig, q, reg, {}, hb, now)
    assert r.passed, "clean signal should pass"
    print("PASS clean signal dispatchable")

    q.ts = now - timedelta(seconds=999)
    assert not selfcheck.run(sig, q, reg, {}, hb, now).passed
    print("PASS stale data blocked")
    q.ts = now

    hb2 = dict(hb, regime=False)
    r = selfcheck.run(sig, q, reg, {}, hb2, now)
    assert r.fault, "dead heartbeat must raise FAULT"
    assert dispatch.send_fault(r.fault), "fault must dispatch, never silence"
    print("PASS dead heartbeat -> FAULT dispatched")

    assert not selfcheck.run(sig, q, reg,
                             {sig.key(): now - timedelta(minutes=5)}, hb, now).passed
    print("PASS duplicate within lookback blocked")

    d = gates.check(9799.0, 10000.0, 0, sig.entry, sig.sl, now)
    assert not d.allowed and "CIRCUIT" in d.reason
    print("PASS 2%% daily loss circuit breaker")

    assert not gates.check(10000.0, 10000.0, 1, sig.entry, sig.sl, now).allowed
    print("PASS max 1 concurrent position")

    assert gates.position_size(9900.0, sig.entry, sig.sl) <= \
           gates.position_size(10000.0, sig.entry, sig.sl)
    print("PASS size shrinks with equity (no martingale path)")

    print()
    print("ALL GATE/FAULT TESTS PASSED")


if __name__ == "__main__":
    main()
