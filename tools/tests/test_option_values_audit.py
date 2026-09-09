#!/usr/bin/env python3
"""Unit tests for tools/dev/option_values_audit.py (A19).

The gate exists because opApply's help offered mode values the arguments
block rejected. It was deferred for a release because the obvious
implementation - grep the help for quoted words near an option name -
was 24/25 false positives. These tests pin the narrow rule that replaced
it, and in particular the three shapes that made the naive version lie.

Run: python3 tools/tests/test_option_values_audit.py

Developed by Matthias Weigelt with the help of Claude (Opus 5), 2026-09-09.
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__))), "dev"))
import option_values_audit as ova  # noqa: E402


def api(name, allowed, desc):
    return {"shLowLevel": [{"name": name, "args": [
        {"name": "Opt", "allowed": allowed, "desc": desc}]}],
        "root": [], "classes": []}


class TestTheDefectItExistsFor(unittest.TestCase):

    def test_opApply_as_it_stood_before_v3_34_1(self):
        probs, _ = ova.audit(api("opApply", "{'forward','transp'}",
                                 "(1,1) string  'apply' | 'applyT' - forward "
                                 "or transposed operator action"))
        self.assertEqual(len(probs), 1, probs)
        self.assertIn("'apply'", probs[0])
        self.assertIn("forward", probs[0])

    def test_opApply_after_the_fix_is_silent(self):
        probs, _ = ova.audit(api("opApply", "{'forward','transp'}",
                                 "(1,:) char  'forward' (default) | 'transp'"))
        self.assertEqual(probs, [])


class TestTheShapesThatMadeTheNaiveVersionLie(unittest.TestCase):

    def test_another_options_value_quoted_in_prose(self):
        """tvANSFilter names SignalMode='isotropic' inside Blocks' row."""
        probs, _ = ova.audit(api("tvANSFilter", "{'auto','on','off'}",
                                 "'auto' (default) | 'on' | 'off' fast path: "
                                 "with SignalMode='isotropic', ..."))
        self.assertEqual(probs, [])

    def test_prose_with_no_alternatives_run_is_not_checked(self):
        probs, _ = ova.audit(api("setup", '["GFZ","CSR","JPL"]',
                                 'TN-13 providers for "core"'))
        self.assertEqual(probs, [])

    def test_a_parenthetical_inside_the_run_does_not_break_it(self):
        run = ova.documented_run("'auto' (default) | 'on' | 'off' text")
        self.assertEqual(run, {"auto", "on", "off"})

    def test_a_numeric_member_list_carries_no_quoted_values(self):
        self.assertIsNone(ova.allowed_values({"allowed": "[60, 96]"}))

    def test_an_empty_member_is_kept_not_mangled(self):
        """readLoveNumbers allows "" alongside CE/CF/CM."""
        got = ova.allowed_values({"allowed": '["", "CE", "CF", "CM"]'})
        self.assertEqual(got, {"", "CE", "CF", "CM"})


class TestRealRepository(unittest.TestCase):

    def test_the_shipped_tree_is_clean(self):
        self.assertEqual(ova.main([]), 0)

    def test_the_gate_actually_checks_something(self):
        """A rule that inspects nothing would also report zero findings."""
        from api_data import API
        _, checked = ova.audit(API)
        self.assertGreater(checked, 20,
                           "only %d alternatives runs checked" % checked)


if __name__ == "__main__":
    unittest.main(verbosity=2)
