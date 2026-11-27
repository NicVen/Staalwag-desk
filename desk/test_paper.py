"""Paper test of the candidate Gold rule. Run: python -m unittest desk.test_paper"""
import sqlite3
import unittest
from datetime import datetime, timedelta, timezone

from . import paper

DAY = 86400


def bars(closes, start=0, step=3600):
    return [{"t": start + k * step, "o": c, "h": c + 1, "l": c - 1, "c": c}
            for k, c in enumerate(closes)]


def uptrend_daily(n=260, start=0):
    return bars([1000 + k for k in range(n)], start=start, step=DAY)


class Rule(unittest.TestCase):
    def setUp(self):
        self.t0 = 300 * DAY            # hourly bars start after the daily history

    def hourly(self, last):
        flat = [2000.0] * 239
        return bars(flat + [last], start=self.t0)

    def test_long_on_breakout_with_both_trends(self):
        st = paper.check(self.hourly(2010.0), uptrend_daily())
        self.assertEqual(st.direction, 1)
        self.assertGreater(st.stop_dist, 0)

    def test_no_trade_against_daily_trend(self):
        down = bars([2000 - k for k in range(260)], step=DAY)
        self.assertIsNone(paper.check(self.hourly(2010.0), down))

    def test_no_trade_without_breakout(self):
        self.assertIsNone(paper.check(self.hourly(2000.5), uptrend_daily()))

    def test_daily_trend_uses_only_closed_days(self):
        d = uptrend_daily()
        # a day that has not closed yet must not count
        self.assertEqual(paper.daily_trend(d, datetime.fromtimestamp(0, tz=timezone.utc).date()), 0)

    def test_skips_signals_in_us_hours(self):
        # 2026-10-05 15:00 UTC = 11:00 New York: US hours, no trade
        t_us = int(datetime(2026, 10, 5, 15, tzinfo=timezone.utc).timestamp())
        h = bars([2000.0] * 239 + [2010.0], start=t_us - 239 * 3600)
        self.assertIsNone(paper.check(h, uptrend_daily()))
        # 20:00 UTC = 16:00 New York: outside US hours, trade
        h = bars([2000.0] * 239 + [2010.0], start=t_us + 5 * 3600 - 239 * 3600)
        self.assertEqual(paper.check(h, uptrend_daily()).direction, 1)

    def test_score(self):
        n, w, pf, tot = paper.score([3.0, -1.0, -1.0])
        self.assertEqual((n, w), (3, 1))
        self.assertAlmostEqual(pf, 1.5)
        self.assertAlmostEqual(tot, 1.0)


class Live(unittest.TestCase):
    def setUp(self):
        self.conn = sqlite3.connect(":memory:")
        self.sent = []
        self.p = paper.PaperTest(self.conn, self.sent.append, session=object())
        self.p.last_key = 10 ** 12   # no hourly scan (no network in tests)
        self.now = datetime(2026, 10, 5, 10, tzinfo=timezone.utc)
        self.conn.execute(
            "INSERT INTO paper_trades (rule, opened_ts, bar_ts, direction, entry, sl, tp) "
            "VALUES (?,?,?,?,?,?,?)", (paper.RULE, self.now.isoformat(), 1, "BUY", 4000, 3980, 4060))

    def row(self):
        return self.conn.execute("SELECT result, r FROM paper_trades").fetchone()

    def test_target_is_a_3r_win(self):
        self.p.tick(4061, self.now)
        self.assertEqual(self.row(), ("WIN", 3.0))
        self.assertIn("1/30 calls", self.sent[-1])

    def test_stop_is_a_1r_loss(self):
        self.p.tick(3979, self.now)
        self.assertEqual(self.row(), ("LOSS", -1.0))

    def test_time_stop_after_48h(self):
        self.p.tick(4010, self.now + timedelta(hours=47))
        self.assertEqual(self.row(), (None, None))
        self.p.tick(4010, self.now + timedelta(hours=48))
        self.assertEqual(self.row(), ("WIN", 0.5))

    def test_messages_say_paper(self):
        self.p.tick(3979, self.now)
        self.assertIn("PAPER TEST", self.sent[-1])


class LiveChannel(unittest.TestCase):
    """CHANNEL_RULE=new: real calls in the channel, results in closed_trades (pips)."""
    def setUp(self):
        self.conn = sqlite3.connect(":memory:")
        self.sent = []
        self.p = paper.PaperTest(self.conn, self.sent.append, session=object(), live=True)
        self.p.last_key = 10 ** 12   # no hourly scan (no network in tests)
        self.now = datetime(2026, 10, 5, 10, tzinfo=timezone.utc)
        self.conn.execute(
            "INSERT INTO paper_trades (rule, opened_ts, bar_ts, direction, entry, sl, tp) "
            "VALUES (?,?,?,?,?,?,?)", (paper.RULE, self.now.isoformat(), 1, "SELL", 4000, 4020, 3940))

    def test_win_lands_in_channel_record_in_pips(self):
        self.p.tick(3939, self.now)
        row = self.conn.execute("SELECT direction, result, pips FROM closed_trades").fetchone()
        self.assertEqual(row, ("SELL", "WIN", 600.0))
        self.assertIn("STAALWAG GOLD #1 closed", self.sent[-1])
        self.assertNotIn("PAPER", self.sent[-1])

    def test_loss_in_pips(self):
        self.p.tick(4021, self.now)
        self.assertEqual(self.conn.execute("SELECT result, pips FROM closed_trades").fetchone(),
                         ("LOSS", -200.0))


def utc(y, m, d, h):
    return int(datetime(y, m, d, h, tzinfo=timezone.utc).timestamp())


class Tokyo(unittest.TestCase):
    """Tokyo range: 00:00-01:59 UTC high/low, first break 02:00-07:59 UTC, daily trend only."""
    def day_bars(self, closes_from_00):
        t = utc(2026, 11, 27, 0)
        out = []
        for k, c in enumerate(closes_from_00):
            out.append({"t": t + k * 3600, "o": c, "h": c + 1, "l": c - 1, "c": c})
        return out

    def test_long_on_first_break_with_daily_trend(self):
        h = self.day_bars([2000, 2002, 2010])          # range 1999-2003, 02:00 closes 2010
        st = paper.check_tokyo(h, uptrend_daily())
        self.assertEqual(st.direction, 1)
        self.assertAlmostEqual(st.stop_dist, 2010 - 1999)

    def test_no_trade_against_daily_trend(self):
        down = bars([2000 - k for k in range(260)], step=DAY)
        self.assertIsNone(paper.check_tokyo(self.day_bars([2000, 2002, 2010]), down))

    def test_only_first_break_of_the_day(self):
        # 02:00 breaks down (against the uptrend), 03:00 breaks up: day already used
        h = self.day_bars([2000, 2002, 1990, 2010])
        self.assertIsNone(paper.check_tokyo(h, uptrend_daily()))

    def test_no_trade_outside_window(self):
        h = self.day_bars([2000, 2002] + [2001] * 6 + [2010])   # break at 08:00 UTC
        self.assertIsNone(paper.check_tokyo(h, uptrend_daily()))

    def test_no_trade_inside_range(self):
        self.assertIsNone(paper.check_tokyo(self.day_bars([2000, 2002, 2001]), uptrend_daily()))


class TokyoLive(unittest.TestCase):
    def setUp(self):
        self.conn = sqlite3.connect(":memory:")
        self.sent = []
        self.p = paper.PaperTest(self.conn, self.sent.append, session=object(), live=True)
        self.p.last_key = 10 ** 12   # no hourly scan (no network in tests)
        self.opened = datetime(2026, 11, 27, 3, 2, tzinfo=timezone.utc)
        self.conn.execute(
            "INSERT INTO paper_trades (rule, opened_ts, bar_ts, direction, entry, sl, tp) "
            "VALUES (?,?,?,?,?,?,?)", (paper.TOKYO, self.opened.isoformat(), 1, "BUY", 3600, 3590, 3615))

    def row(self):
        return self.conn.execute("SELECT result, r FROM paper_trades WHERE rule=?",
                                 (paper.TOKYO,)).fetchone()

    def test_target_is_1_5r(self):
        self.p.tick(3616, self.opened + timedelta(hours=1))
        self.assertEqual(self.row(), ("WIN", 1.5))
        self.assertIn("Tokyo range breakout", self.sent[-1])

    def test_time_stop_at_noon_utc(self):
        self.p.tick(3605, self.opened.replace(hour=11, minute=59))
        self.assertEqual(self.row(), (None, None))
        self.p.tick(3605, self.opened.replace(hour=12, minute=0))
        self.assertEqual(self.row(), ("WIN", 0.5))
        self.assertIn("12:00 UTC TIME-STOP", self.sent[-1])

    def test_both_rules_share_the_30_call_count(self):
        self.conn.execute(
            "INSERT INTO paper_trades (rule, opened_ts, bar_ts, direction, entry, sl, tp, "
            "closed_ts, exit, result, r) VALUES (?,?,?,?,?,?,?,?,?,?,?)",
            (paper.RULE, self.opened.isoformat(), 2, "SELL", 3700, 3720, 3640,
             self.opened.isoformat(), 3640, "WIN", 3.0))
        self.p.tick(3589, self.opened + timedelta(hours=1))
        self.assertEqual(self.row(), ("LOSS", -1.0))
        self.assertIn("2/30 calls", self.sent[-1])

    def test_open_breakout_trade_does_not_block_tokyo(self):
        self.conn.execute(
            "INSERT INTO paper_trades (rule, opened_ts, bar_ts, direction, entry, sl, tp) "
            "VALUES (?,?,?,?,?,?,?)", (paper.RULE, self.opened.isoformat(), 3, "SELL", 3700, 3720, 3640))
        self.p.tick(3616, self.opened + timedelta(hours=1))
        self.assertEqual(self.row(), ("WIN", 1.5))


class FakeYahoo:
    def __init__(self, hourly, daily):
        self.hourly, self.daily = hourly, daily

    def get(self, url, timeout=0):
        b = self.daily if "1d" in url else self.hourly
        q = {"open": [x["o"] for x in b], "high": [x["h"] for x in b],
             "low": [x["l"] for x in b], "close": [x["c"] for x in b]}
        body = {"chart": {"result": [{"timestamp": [x["t"] for x in b],
                                      "indicators": {"quote": [q]}}]}}
        return type("R", (), {"json": lambda self: body})()


class TokyoScan(unittest.TestCase):
    def test_scan_posts_a_tokyo_call_to_the_channel(self):
        t = utc(2026, 11, 20, 0)
        hourly = [{"t": t + k * 3600, "o": c, "h": c + 1, "l": c - 1, "c": c}
                  for k, c in enumerate([3600, 3602, 3615])]
        daily = bars([1000 + k for k in range(260)], start=t - 261 * DAY, step=DAY)
        conn, sent = sqlite3.connect(":memory:"), []
        p = paper.PaperTest(conn, sent.append, session=FakeYahoo(hourly, daily), live=True)
        p.tick(3615.5, datetime(2026, 11, 20, 3, 2, tzinfo=timezone.utc))
        row = conn.execute("SELECT rule, direction, entry, sl, tp FROM paper_trades").fetchone()
        self.assertEqual(row, (paper.TOKYO, "BUY", 3615.5, 3599.5, 3639.5))
        self.assertIn("Tokyo range breakout", sent[-1])
        self.assertIn("call 1 of 30", sent[-1])
        self.assertIn("12:00 UTC", sent[-1])


if __name__ == "__main__":
    unittest.main()
