# Copyright (c) 2026. All rights reserved. Proprietary - no license granted.
"""Dispatch. Telegram is the ONLY channel. No email, no other path.

Two audiences:
  send_vip(text)    -> paid private channel (full signals + management alerts)
  send_public(text) -> free public channel (teasers only)
send() defaults to VIP so existing calls stay full-fidelity.

There is deliberately NO command handler here. The desk talks; it does not
listen. Risk limits cannot be changed from Telegram because Telegram input
is never read.
"""
import truststore
truststore.inject_into_ssl()

import httpx

from . import config


def _post(chat_id: str, text: str) -> bool:
    if not config.TELEGRAM_BOT_TOKEN or not chat_id:
        print("[DISPATCH:console->%s] " % (chat_id or "none") + text.replace("\n", "\n  "))
        return True
    try:
        r = httpx.post(
            "https://api.telegram.org/bot%s/sendMessage" % config.TELEGRAM_BOT_TOKEN,
            json={"chat_id": chat_id, "text": text},
            timeout=15)
        ok = r.status_code == 200 and r.json().get("ok", False)
        if not ok:
            print("[DISPATCH:error] Telegram returned %s: %s" % (r.status_code, r.text[:200]))
        return ok
    except Exception as e:
        print("[DISPATCH:error] %s" % e)
        return False


def send_vip(text: str) -> bool:
    return _post(config.VIP_CHAT_ID, text)


def send_public(text: str) -> bool:
    if not config.PUBLIC_CHAT_ID:
        return True   # free channel not configured; skip silently
    return _post(config.PUBLIC_CHAT_ID, text)


def send(text: str) -> bool:
    """Back-compat: default channel is VIP."""
    return send_vip(text)


def send_fault(reason: str) -> bool:
    # Faults are operational noise — log to Railway only, never the public channel.
    print("[DISPATCH:fault] %s" % reason)
    return True
