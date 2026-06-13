# STAALWAG — Systematic XAUUSD Signal Desk

Copyright (c) 2026. All rights reserved. Private code — no license granted.

## Who builds this and why it is different

Built by a South African metal fabricator living in New Zealand — ex-mechanical
draftsman (conveyors, silos, mining structures) with years of obsessive XAUUSD/forex
trading experience. The edge logic already exists and works (Markov regime gating,
outcome-tracked indicator, multi-pair scanner, a self-improving XAUUSD paper bot).
The business failed before for exactly three engineering reasons, and this desk
exists to eliminate them:

1. **Desync** — components ran out of sync; the desk got stuck in loops, info arrived late.
2. **False signals** — technical faults reached the trader dressed as real signals.
3. **Greed** — manual mid-trade overrides blew the account.

STAALWAG answers each with structure, not willpower: one process owns the schedule,
a mandatory self-check pass sits in front of every dispatch, and risk limits are
hard-coded with no override path.

## The offer

Verified XAUUSD trading signals from a systematic desk with published results.

## The buyer

- **Stage 1 (now):** the founder. Trades his own ~$10k through the hardened pipeline.
  Deliverable: a verified live track record (the ledger).
- **Stage 2 (after 3–6 months of verified results):** subscribers via the MQL5
  Signals marketplace (MT5 handles copying and payment) plus a paid Telegram channel.

## The price

USD $30–50 / month per subscriber (Stage 2).

## The deliverable — what a signal contains

Every dispatched signal carries, always, all of:

| Field | Meaning |
|---|---|
| pair | XAUUSD |
| direction | LONG or SHORT |
| entry | price |
| sl | stop loss price |
| tp | take profit price |
| regime | Markov gate state (BULL / BEAR / SIDEWAYS) |
| confidence | gate confidence 0–1 |
| timestamp | signal time, NZT |
| freshness | source data age in seconds at dispatch, must be within limit |

No signal is dispatched without passing the full self-check (see below). If the desk
is unhealthy it sends a FAULT message instead — never silence, never a fake signal.

## Pipeline

```
intake (market data + Markov regime)
  -> signal generation (edge logic)
  -> SELF-CHECK PASS (mandatory)
  -> dispatch (Telegram only)
  -> outcome logging (SQLite ledger)
```

One orchestrated loop in one process (`desk/loop.py`). Components cannot desync
because nothing schedules itself.

### Self-check checklist (before ANY dispatch)

- data freshness: source timestamp within limit, else discard and log
- sanity: entry/SL/TP internally consistent, spread within limits
- regime agreement: Markov gate state matches signal direction
- duplicate/loop guard: same signal not resent within lookback window
- heartbeat: every component reported alive this cycle; if not -> FAULT to Telegram

### Greed gates (hard-coded in `desk/gates.py`, no Telegram command can change them)

- fixed risk per trade: max 1% of account
- max daily loss circuit breaker: 2% — hit it and the desk stops until next NZT day
- max concurrent positions: 1
- no martingale, no size increase after losses

## Ledger

Every signal, self-check result, fault, and outcome is written to `staalwag.db`
(SQLite). The ledger IS the Stage 2 product: the verified track record.

## Files

- `desk/` — pipeline code (loop.py is the entry point)
- `samples/` — sample signal, self-check report, weekly summary
- `landing/index.html` — public landing page
- `messages.md` — launch posts, MQL5 listing, forum post, peer message
- `PLAN7.md` — seven-day launch plan

## Run

```
python -m pip install -r requirements.txt
copy .env.example .env   (fill in Telegram token + chat id)
python -m desk.loop            # live loop (paper mode by default)
python -m desk.run_sample      # generate sample deliverables from dummy data
```

All times NZT. Console output is plain ASCII (cp1252-safe).
