# Copyright (c) 2026. All rights reserved. Proprietary - no license granted.
"""Mandatory self-check pass. Runs before EVERY dispatch.

A signal that fails any check is discarded and logged - it never reaches
Telegram as a signal. A missing heartbeat produces a FAULT message instead
of a signal. Silence is not an outcome this module can produce.
"""
from dataclasses import dataclass, field
from datetime import datetime

from . import config
from .intake import Quote
from .regime import RegimeView
from .signal import Signal


@dataclass
class CheckResult:
    name: str
    passed: bool
    detail: str


@dataclass
class SelfCheckReport:
    results: list[CheckResult] = field(default_factory=list)
    fault: str | None = None       # set -> send FAULT message, not a signal

    @property
    def passed(self) -> bool:
        return self.fault is None and all(r.passed for r in self.results)

    def text(self) -> str:
        lines = ["SELF-CHECK REPORT"]
        for r in self.results:
            lines.append("[%s] %s - %s" % ("PASS" if r.passed else "FAIL", r.name, r.detail))
        if self.fault:
            lines.append("[FAULT] %s" % self.fault)
        lines.append("VERDICT: %s" % ("DISPATCH" if self.passed else "BLOCKED"))
        return "\n".join(lines)


def run(signal: Signal, quote: Quote, regime: RegimeView,
        recent_keys: dict[str, datetime], heartbeats: dict[str, bool],
        now: datetime | None = None) -> SelfCheckReport:
    now = now or datetime.now(config.NZT)
    rep = SelfCheckReport()

    # 1. heartbeat - checked first; a dead component means FAULT, not signal
    dead = [name for name, alive in heartbeats.items() if not alive]
    if dead:
        rep.fault = "Components missed heartbeat this cycle: %s" % ", ".join(dead)
        rep.results.append(CheckResult("heartbeat", False, rep.fault))
        return rep
    rep.results.append(CheckResult("heartbeat", True,
                       "all components alive: %s" % ", ".join(sorted(heartbeats))))

    # 2. data freshness
    age = quote.age_seconds(now)
    rep.results.append(CheckResult(
        "data_freshness", age <= config.DATA_FRESHNESS_MAX_S,
        "source age %.0fs (limit %ds)" % (age, config.DATA_FRESHNESS_MAX_S)))

    # 3. sanity: SL/TP on correct sides, RR acceptable, spread within limit
    if signal.direction == "LONG":
        sides_ok = signal.sl < signal.entry < signal.tp
    else:
        sides_ok = signal.tp < signal.entry < signal.sl
    risk = abs(signal.entry - signal.sl)
    reward = abs(signal.tp - signal.entry)
    rr = reward / risk if risk > 0 else 0.0
    rep.results.append(CheckResult(
        "sanity_levels", sides_ok and rr >= config.MIN_RR,
        "sides %s, RR %.2f (min %.1f)" % ("ok" if sides_ok else "BAD", rr, config.MIN_RR)))
    rep.results.append(CheckResult(
        "sanity_spread", quote.spread <= config.MAX_SPREAD_USD,
        "spread %.2f (limit %.2f)" % (quote.spread, config.MAX_SPREAD_USD)))

    # 4. regime agreement
    agree = ((signal.direction == "LONG" and regime.state == "BULL") or
             (signal.direction == "SHORT" and regime.state == "BEAR"))
    rep.results.append(CheckResult(
        "regime_agreement", agree,
        "signal %s vs regime %s" % (signal.direction, regime.state)))

    # 5. duplicate / loop guard
    last = recent_keys.get(signal.key())
    if last is not None:
        mins = (now - last).total_seconds() / 60
        dup_ok = mins >= config.DUPLICATE_LOOKBACK_MIN
        detail = "same signal sent %.0f min ago (lookback %d min)" % (
            mins, config.DUPLICATE_LOOKBACK_MIN)
    else:
        dup_ok, detail = True, "no recent duplicate"
    rep.results.append(CheckResult("duplicate_guard", dup_ok, detail))

    return rep
