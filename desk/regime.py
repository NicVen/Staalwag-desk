# Copyright (c) 2026. All rights reserved. Proprietary - no license granted.
"""Markov regime gate.

Compact observable-Markov model: label each bar window BULL/BEAR/SIDEWAYS from
rolling returns, build the transition matrix with STRIDE SAMPLING (Markov 2.0
fix - overlapping windows fake persistence), gate on the most likely next state.

PORT POINT: replace with the full Markov 2.0 skill (stride sampling + label
self-check) for live running; this module keeps the same interface.
"""
from dataclasses import dataclass

STATES = ("BULL", "BEAR", "SIDEWAYS")
WINDOW = 20          # rolling return window (bars)
STRIDE = 20          # non-overlapping sampling
BULL_TH = 0.0015     # 20-bar return thresholds
BEAR_TH = -0.0015


@dataclass
class RegimeView:
    state: str          # current state
    next_state: str     # most likely next state from transition matrix
    confidence: float   # probability of next_state


def _label(ret: float) -> str:
    if ret > BULL_TH:
        return "BULL"
    if ret < BEAR_TH:
        return "BEAR"
    return "SIDEWAYS"


def assess(closes: list[float]) -> RegimeView | None:
    if len(closes) < WINDOW * 4:
        return None

    labels = []
    i = WINDOW
    while i < len(closes):
        ret = (closes[i] - closes[i - WINDOW]) / closes[i - WINDOW]
        labels.append(_label(ret))
        i += STRIDE

    if len(labels) < 3:
        return None

    # transition counts
    idx = {s: k for k, s in enumerate(STATES)}
    counts = [[1.0] * 3 for _ in range(3)]   # Laplace smoothing
    for a, b in zip(labels, labels[1:]):
        counts[idx[a]][idx[b]] += 1

    cur = labels[-1]
    row = counts[idx[cur]]
    total = sum(row)
    probs = [c / total for c in row]
    best = max(range(3), key=lambda k: probs[k])

    return RegimeView(state=cur, next_state=STATES[best],
                      confidence=round(probs[best], 3))
