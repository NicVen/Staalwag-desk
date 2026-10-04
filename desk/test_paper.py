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


if __name__ == "__main__":
    unittest.main()
