#!/usr/bin/env python3
"""Unit tests for tools/nv_casing_audit.py.

Run: python3 tools/tests/test_nv_casing_audit.py

Developed by Matthias Weigelt with the help of Claude (Sonnet 5),
2026-09-05.
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(
    os.path.abspath(__file__))))
import nv_casing_audit as nca  # noqa: E402


SRC = """\
function out = f(options)
arguments
{decls}
end
out = 1;
end
"""


def src(*names):
    return SRC.format(decls="\n".join(
        f"    options.{n} (1,1) double = 0" for n in names))


class TestIsPascal(unittest.TestCase):
    def test_accepts(self):
        for n in ["Nmax", "GM", "R", "MinDegree", "TN14File"]:
            self.assertTrue(nca.is_pascal(n), n)

    def test_rejects(self):
        for n in ["nmax", "rho_ave", "tYears", "a", ""]:
            self.assertFalse(nca.is_pascal(n), n)

    def test_underscore_rejected_even_when_capitalised(self):
        self.assertFalse(nca.is_pascal("Rho_Ave"))


class TestBlocksIn(unittest.TestCase):
    def test_finds_names_and_line(self):
        blocks = nca.blocks_in(src("Nmax", "Quantity"))
        self.assertEqual(len(blocks), 1)
        line, names = blocks[0]
        self.assertEqual(line, 2)
        self.assertEqual(names, ["Nmax", "Quantity"])

    def test_positional_args_are_not_name_value(self):
        txt = ("function y = f(x, options)\narguments\n"
               "    x (1,1) double\n"
               "    options.Nmax (1,1) double = 0\nend\ny=1;\nend\n")
        self.assertEqual(nca.blocks_in(txt)[0][1], ["Nmax"])

    def test_block_without_nv_is_skipped(self):
        txt = "function y = f(x)\narguments\n    x double\nend\ny=1;\nend\n"
        self.assertEqual(nca.blocks_in(txt), [])

    def test_two_blocks_in_one_file(self):
        self.assertEqual(len(nca.blocks_in(src("Nmax") + src("Alpha"))), 2)

    def test_nested_end_does_not_truncate(self):
        # indentation anchors the closing end, so an inner end is safe
        txt = ("function y = f(options)\narguments\n"
               "    options.Mode (1,1) string = \"a\"\nend\n"
               "if true\n    y = 1;\nend\nend\n")
        self.assertEqual(nca.blocks_in(txt)[0][1], ["Mode"])


class TestAuditBlock(unittest.TestCase):
    def test_clean_block(self):
        self.assertEqual(nca.audit_block("x.m", 1, ["Nmax", "Alpha"]), [])

    def test_case_clash_is_the_reason_this_gate_exists(self):
        out = nca.audit_block("x.m", 7, ["Nmax", "nmax"])
        self.assertTrue(any("differ only by case" in f for f in out))
        self.assertTrue(any("unreachable" in f for f in out))

    def test_case_clash_reported_once_not_per_variant(self):
        out = [f for f in nca.audit_block("x.m", 1, ["Nmax", "nmax"])
               if "differ only by case" in f]
        self.assertEqual(len(out), 1)

    def test_new_lowercase_name_rejected(self):
        out = nca.audit_block("x.m", 1, ["brandNew"])
        self.assertEqual(len(out), 1)
        self.assertIn("not PascalCase", out[0])

    def test_legacy_name_tolerated(self):
        # LEGACY is a backlog and was drained to empty in v3.33.0, so this
        # asserts the mechanism with a temporary entry rather than naming a
        # member: the old form pinned 'nmax', which the casing sweep renamed,
        # and the test then failed silently because CI never ran it.
        nca.LEGACY.add("someOldName")
        try:
            self.assertEqual(nca.audit_block("x.m", 1, ["someOldName"]), [])
        finally:
            nca.LEGACY.discard("someOldName")

    def test_legacy_backlog_is_empty(self):
        # if this ever fails, the sweep left work behind - name it here
        self.assertEqual(sorted(nca.LEGACY), [])

    def test_symbols_entry_tolerated(self):
        nca.SYMBOLS["theta"] = "colatitude, standard notation"
        try:
            self.assertEqual(nca.audit_block("x.m", 1, ["theta"]), [])
        finally:
            del nca.SYMBOLS["theta"]

    def test_new_prefix_pair_rejected(self):
        out = nca.audit_block("x.m", 1, ["Alpha", "AlphaMax"])
        self.assertEqual(len(out), 1)
        self.assertIn("AmbiguousInputName", out[0])

    def test_baseline_prefix_pair_tolerated(self):
        self.assertEqual(nca.audit_block("x.m", 1, ["Tol", "Tolerance"]), [])

    def test_prefix_check_is_case_insensitive_like_matlab(self):
        out = nca.audit_block("x.m", 1, ["Alpha", "alphaMax"])
        self.assertTrue(any("prefix" in f for f in out))

    def test_unrelated_names_are_not_prefixes(self):
        self.assertEqual(
            nca.audit_block("x.m", 1, ["Alpha", "Beta", "Gamma"]), [])


class TestBaselineHygiene(unittest.TestCase):
    def test_symbols_and_legacy_do_not_overlap(self):
        self.assertEqual(set(nca.SYMBOLS) & nca.LEGACY, set())

    def test_no_legacy_name_is_already_pascal(self):
        # a PascalCase name in the backlog would never be worked off
        self.assertEqual([n for n in nca.LEGACY if nca.is_pascal(n)], [])

    def test_prefix_baseline_pairs_really_are_prefixes(self):
        for a, b in nca.PREFIX_BASELINE:
            self.assertTrue(b.lower().startswith(a.lower()), f"{a} {b}")


class TestIntegration(unittest.TestCase):
    def test_repository_is_clean(self):
        findings = []
        declared = set()
        for rel, s in nca.walk(nca.ROOT):
            for line, names in nca.blocks_in(s):
                declared.update(names)
                findings.extend(nca.audit_block(rel, line, names))
        self.assertEqual(findings, [], "\n".join(findings))

    def test_every_legacy_name_is_still_declared(self):
        declared = set()
        for _, s in nca.walk(nca.ROOT):
            for _, names in nca.blocks_in(s):
                declared.update(names)
        self.assertEqual(sorted(nca.LEGACY - declared), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
