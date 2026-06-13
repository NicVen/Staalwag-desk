# Copyright (c) 2026. All rights reserved. Proprietary - no license granted.
"""One-time helper: finds your Telegram chat id after you message the bot.

1. Put TELEGRAM_BOT_TOKEN in .env
2. Send any message to your bot in Telegram
3. Run: python -m desk.get_chat_id
4. Copy the printed chat id into .env as TELEGRAM_CHAT_ID
"""
import truststore
truststore.inject_into_ssl()

import httpx

from . import config


def main():
    if not config.TELEGRAM_BOT_TOKEN:
        print("TELEGRAM_BOT_TOKEN missing in .env - get one from @BotFather first.")
        return
    r = httpx.get("https://api.telegram.org/bot%s/getUpdates"
                  % config.TELEGRAM_BOT_TOKEN, timeout=15)
    data = r.json()
    if not data.get("ok"):
        print("Telegram error: %s" % data)
        return
    chats = {}
    for upd in data.get("result", []):
        msg = upd.get("message") or upd.get("channel_post") or {}
        chat = msg.get("chat", {})
        if chat.get("id"):
            chats[chat["id"]] = chat.get("title") or chat.get("first_name") or "?"
    if not chats:
        print("No messages found. Send any message to the bot in Telegram, "
              "then run this again.")
        return
    for cid, name in chats.items():
        print("Chat id: %s  (%s)" % (cid, name))
    print("Put the right one in .env as TELEGRAM_CHAT_ID, then run: "
          "python -m desk.loop")


if __name__ == "__main__":
    main()
