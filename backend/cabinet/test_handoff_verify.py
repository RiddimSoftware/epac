# backend/cabinet/test_handoff_verify.py
import unittest

class HandoffVerify(unittest.TestCase):
    def test_deliberate_failure(self):
        raise AssertionError("deliberate failure — EPAC-2013 handler verification")
