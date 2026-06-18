# Copyright (c) 2026. All rights reserved. Proprietary - no license granted.
"""Telegram command listener. Read-only — listens for /selfcheck only.

Runs in a background thread. Does NOT accept risk or config commands.
The only thing it can do is return stored reports to Telegram on demand.
"""
import threading
import time

import truststore
truststore.inject_into_ssl()

import httpx

from . import config, dispatch


def _poll(state: dict):
    last_update_id = None
    while True:
        try:
            params = {"timeout": 30, "allowed_updates": ["message"]}
            if last_update_id:
                params["offset"] = last_update_id + 1
            r = httpx.get(
                "https://api.telegram.org/bot%s/getUpdates" % config.TELEGRAM_BOT_TOKEN,
                params=params, timeout=40)
            data = r.json()
            for upd in data.get("result", []):
                last_update_id = upd["update_id"]
                msg = upd.get("message", {})
                text = msg.get("text", "").strip().lower()
                chat_id = str(msg.get("chat", {}).get("id", ""))

                # only respond to the owner's chat
                if chat_id != str(config.TELEGRAM_CHAT_ID):
                    continue

                if text == "/selfcheck":
                    report = state.get("last_selfcheck")
                    if report:
                        dispatch.send("SELF-CHECK (last signal)\n\n" + report)
                    else:
                        dispatch.send("No signal processed yet this session.")

                elif text == "/status":
                    dispatch.send(
                        "STAALWAG STATUS [%s]\n"
                        "Feed: %s\n"
                        "Open positions: %s\n"
                        "Equity: %.2f\n"
                        "Day start equity: %.2f\n"
                        "Signals today: %d"
                        % (config.DESK_LABEL, config.FEED,
                           state.get("open_positions", 0),
                           state.get("equity", 0),
                           state.get("day_start_equity", 0),
                           state.get("signals_today", 0)))

        except Exception as e:
            print("[COMMANDER] poll error: %s" % e)
            time.sleep(10)


def start(state: dict):
    if not config.TELEGRAM_BOT_TOKEN:
        return
    t = threading.Thread(target=_poll, args=(state,), daemon=True)
    t.start()
    print("[COMMANDER] Listening for /selfcheck and /status commands.")
