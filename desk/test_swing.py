"""Oil/crypto trend paper test. Run: python -m unittest desk.test_swing"""
import sqlite3
import unittest

from . import swing

DAY = 86400


def bars(closes, start=0):
    return [{"t": start + k * DAY, "o": c, "h": c + 1, "l": c - 1, "c": c} for k, c in enumerate(closes)]


class Rule(unittest.TestCase):
    def test_long_breakout_in_uptrend(self):
        b = bars([100 + k * 0.1 for k in range(240)] + [200])
        d, dist = swing.signal(b, len(b) - 1)
        self.assertEqual(d, 1)
        self.assertGreater(dist, 0)

    def test_no_signal_without_breakout(self):
        b = bars([100 + k * 0.1 for k in range(240)] + [120])
        self.assertEqual(swing.signal(b, len(b) - 1)[0], 0)

    def test_stop_then_time_exit(self):
        b = bars([100] * 30)
        self.assertEqual(swing.settle(b, 0, 1, 100, 99.5)[2], "STOP")      # low 99 hits 99.5
        self.assertEqual(swing.settle(b, 0, 1, 100, 90)[2], "20-DAY TIME EXIT")
        self.assertIsNone(swing.settle(b[:5], 0, 1, 100, 90))


class Live(unittest.TestCase):
    def test_signal_fill_and_close_are_posted(self):
        conn, sent = sqlite3.connect(":memory:"), []
        t = swing.SwingTest(conn, sent.append, session=object())
        b = bars([100 + k * 0.1 for k in range(240)] + [200])
        t.step("ETH-USD", b)
        self.assertIn("NOT A SIGNAL", sent[-1])
        b2 = b + bars([201] * 25, start=b[-1]["t"] + DAY)
        t.step("ETH-USD", b2)
        row = conn.execute("SELECT entry, result FROM swing_trades").fetchone()
        self.assertEqual(row[0], 201)
        self.assertIsNotNone(row[1])
        self.assertIn("Score so far: 1/30", sent[-1])


if __name__ == "__main__":
    unittest.main()
