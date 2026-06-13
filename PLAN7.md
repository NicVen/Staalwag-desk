# STAALWAG seven-day plan (max 1 hour/day)

- **Day 1** — Done 2026-06-12: questions answered (code on Railway only -> built
  fresh with port points marked; demo MT5 first, then live; 2% daily cap).
- **Day 2** — Review `desk/gates.py` and the self-check list in `desk/selfcheck.py`.
  Confirm 2% daily loss cap. Read the README deliverable spec once.
- **Day 3** — Fill `.env` (Telegram token + chat id), run `python -m desk.loop`
  in paper mode. Watch signals + self-check reports arrive on Telegram.
- **Day 4** — Kill the data feed on purpose (or set freshness limit low) and
  confirm a FAULT message arrives on Telegram. No silent failures.
- **Day 5** — Open `staalwag.db`, review the ledger rows and the weekly summary
  format (`samples/sample_weekly_summary.txt` shows the layout).
- **Day 6** — Wire demo MT5 feed (port point in `desk/intake.py`), then go live
  with minimum size on the funded account.
- **Day 7** — Do nothing. Confirm the desk runs without being touched.

Then: **90 days untouched live running.** The ledger is the product.
When it shows 3 months of verified discipline: MQL5 listing + paid Telegram
(messages ready in `messages.md`, page in `landing/index.html`).

Founder's weekend job: motorcycles, not charts.
