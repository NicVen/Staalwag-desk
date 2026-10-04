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


if __name__ == "__main__":
    unittest.main()
