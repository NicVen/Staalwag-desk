# Copyright (c) 2026. All rights reserved. Proprietary - no license granted.
"""Dispatch. Telegram is the ONLY channel. No email, no other path.

If no Telegram credentials configured (paper/sample runs), messages print to
console (plain ASCII, cp1252-safe) so nothing is ever silently dropped.

There is deliberately NO command handler here. The desk talks; it does not
listen. Risk limits cannot be changed from Telegram because Telegram input
is never read.
"""
import truststore
truststore.inject_into_ssl()

import httpx

from . import config


def send(text: str) -> bool:
    """Send to Telegram; fall back to console. Returns True on confirmed send."""
    if not config.TELEGRAM_BOT_TOKEN or not config.TELEGRAM_CHAT_ID:
        print("[DISPATCH:console] " + text.replace("\n", "\n  "))
        return True
    try:
        r = httpx.post(
            "https://api.telegram.org/bot%s/sendMessage" % config.TELEGRAM_BOT_TOKEN,
            json={"chat_id": config.TELEGRAM_CHAT_ID, "text": text},
            timeout=15)
        ok = r.status_code == 200 and r.json().get("ok", False)
        if not ok:
            print("[DISPATCH:error] Telegram returned %s: %s" % (r.status_code, r.text[:200]))
        return ok
    except Exception as e:
        print("[DISPATCH:error] %s" % e)
        return False


def send_fault(reason: str) -> bool:
    # Faults are operational noise — log to Railway only, never the public channel.
    print("[DISPATCH:fault] %s" % reason)
    return True
