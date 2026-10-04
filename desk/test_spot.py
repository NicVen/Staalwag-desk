"""Spot-price shift and breakeven recording. Run: python -m unittest desk.test_spot"""
import os
import tempfile
import time
import unittest
from datetime import datetime, timezone
from types import SimpleNamespace

from . import config, intake, manage


class SpotShift(unittest.TestCase):
    def setUp(self):
        intake.WebFeed._basis, intake.WebFeed._basis_ts = None, 0.0
        self.feed = intake.WebFeed()

    def test_levels_move_onto_spot(self):
        self.feed._spot = lambda: 4141.8
        out = self.feed._to_spot([4150.0, 4162.3])
        self.assertAlmostEqual(out[-1], 4141.8, places=2)
        self.assertAlmostEqual(out[0], 4129.5, places=2)

    def test_no_spot_no_quote(self):
        def boom(): raise IOError("down")
        self.feed._spot = boom
        with self.assertRaises(RuntimeError):
            self.feed._to_spot([4162.3])

    def test_recent_basis_reused(self):
        intake.WebFeed._basis, intake.WebFeed._basis_ts = 20.5, time.time()
        def boom(): raise IOError("down")
        self.feed._spot = boom
        self.assertAlmostEqual(self.feed._to_spot([4162.3])[-1], 4141.8, places=2)

    def test_crazy_spot_rejected(self):
        self.feed._spot = lambda: 2000.0
        with self.assertRaises(RuntimeError):
            self.feed._to_spot([4162.3])


class Breakeven(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        config.LEDGER_PATH = os.path.join(self.tmp, "t.db")
        manage.open_trade(SimpleNamespace(pair="XAUUSD", direction="LONG",
                                          entry=4000.0, sl=3995.0, tp=4010.0))

    def closed(self):
        c = manage._conn()
        rows = c.execute("SELECT result, pips FROM closed_trades").fetchall()
        c.close()
        return rows

    def test_back_to_entry_after_halfway_is_breakeven(self):
        manage.check(4006.0, "XAUUSD")          # past halfway -> SL to BE
        manage.check(3994.0, "XAUUSD")          # falls through entry and old SL
        self.assertEqual(self.closed(), [("BREAKEVEN", 0.0)])

    def test_stop_before_halfway_is_loss(self):
        manage.check(3994.0, "XAUUSD")
        self.assertEqual(self.closed(), [("LOSS", -50.0)])


if __name__ == "__main__":
    unittest.main()
