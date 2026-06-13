# STAALWAG on Railway (web-feed desk)

Two desks, one codebase, separate ledgers and separate track records:

| Desk | Feed | Runs on | Purpose |
|---|---|---|---|
| PC desk | MT5 (FEED=mt5) | Windows PC | MQL5 marketplace verified record |
| Railway desk | Twelve Data (FEED=web) | Railway 24/7 | Public/paid Telegram channel |

Never merge the two ledgers in published stats - different feeds, different
records. The DESK_LABEL env var stamps every message so subscribers always
know which desk is talking.

## Deploy steps

1. Free API key: https://twelvedata.com (free tier: 8 req/min, 800/day).
2. Push this folder to a PRIVATE GitHub repo (`.gitignore` already excludes
   `.env` and `*.db`).
3. Railway -> New Project -> Deploy from GitHub repo. Nixpacks detects Python
   via requirements.txt; Procfile starts `python -m desk.loop` as a worker.
4. Add a Volume to the service, mount path `/data`.
5. Service -> Variables:

   ```
   FEED=web
   DESK_LABEL=RAILWAY
   TWELVEDATA_API_KEY=<your key>
   TELEGRAM_BOT_TOKEN=<channel bot token>
   TELEGRAM_CHAT_ID=<channel chat id>
   CYCLE_SECONDS=120
   LEDGER_PATH=/data/staalwag.db
   ```

   CYCLE_SECONDS=120 keeps the free Twelve Data tier inside its daily cap.
   Use a separate bot (or same bot, channel chat id) for the public channel.
6. Deploy. Logs should show:
   `STAALWAG desk starting. Feed: web ...`
7. Weekly: download `/data/staalwag.db` (railway volume) to update the
   landing-page results table for the Railway record.

## PC desk stays as-is

`.env` on the PC: `FEED=mt5`, `DESK_LABEL=PC`, own bot/chat id, local
`staalwag.db`. Greed gates identical on both - they are in code, not config.
