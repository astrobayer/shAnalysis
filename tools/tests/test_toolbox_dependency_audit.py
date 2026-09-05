#!/usr/bin/env python3
"""Unit tests for tools/toolbox_dependency_audit.py.

Run: python3 tools/tests/test_toolbox_dependency_audit.py

Developed by Matthias Weigelt with the help of Claude (Sonnet 5),
2026-09-05.
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(
    os.path.abspath(__file__))))
import toolbox_dependency_audit as tda  # noqa: E402


class TestStripComments(unittest.TestCase):
    def test_line_comment_removed(self):
        out = tda.strip_comments("x = 1; % uses parfor for speed")
        self.assertNotIn("parfor", out)
        self.assertIn("x = 1;", out)

    def test_percent_inside_string_survives(self):
        src = "s = 'a % b'; y = 2;"
        self.assertIn("y = 2;", tda.strip_comments(src))

    def test_block_comment_removed(self):
        src = "a = 1;\n%{\nparfor i = 1:3\n%}\nb = 2;"
        out = tda.strip_comments(src)
        self.assertNotIn("parfor", out)
        self.assertIn("b = 2;", out)

    def test_line_count_preserved(self):
        src = "a\n% c\n%{\nx\n%}\nb"
        self.assertEqual(len(tda.strip_comments(src).splitlines()),
                         len(src.splitlines()))


class TestStripStrings(unittest.TestCase):
    def test_string_contents_removed(self):
        # leakageCorrect.m:188 really contains "nothing to solve for"
        out = tda.strip_strings("error('id', 'nothing to solve for.');")
        self.assertNotIn("solve", out)

    def test_transpose_is_not_a_string_opener(self):
        src = "y = A' * b; z = x(:)';"
        self.assertEqual(tda.strip_strings(src), src)

    def test_transpose_then_string(self):
        out = tda.strip_strings("f(A', 'solve');")
        self.assertIn("A'", out)
        self.assertNotIn("solve", out)

    def test_escaped_quote_inside_string(self):
        out = tda.strip_strings("s = 'it''s solve time';")
        self.assertNotIn("solve", out)

    def test_length_preserved(self):
        src = "x = 'abc'; y = 1;"
        self.assertEqual(len(tda.strip_strings(src)), len(src))


class TestScanSource(unittest.TestCase):
    def test_clean_file_passes(self):
        self.assertEqual(tda.scan_source("+shLowLevel/x.m",
                                         "y = mean(a);\nz = sum(b);"), [])

    def test_parfor_caught(self):
        out = tda.scan_source("+sh/x.m", "parfor i = 1:10\nend")
        self.assertEqual(len(out), 1)
        self.assertIn("Parallel Computing Toolbox", out[0])
        self.assertIn(":1:", out[0])

    def test_statistics_caught_with_product_named(self):
        out = tda.scan_source("+sh/x.m", "q = chi2inv(0.95, 3);")
        self.assertEqual(len(out), 1)
        self.assertIn("Statistics", out[0])

    def test_line_number_is_reported(self):
        out = tda.scan_source("+sh/x.m", "a = 1;\nb = 2;\nc = fmincon(f);")
        self.assertIn(":3:", out[0])

    def test_multiple_products_all_reported(self):
        out = tda.scan_source("+sh/x.m", "a = gpuArray(x);\nb = fitlm(y);")
        self.assertEqual(len(out), 2)

    def test_the_toolboxs_own_base_substitutes_are_not_flagged(self):
        # pctile / chi2Quantile exist precisely so prctile / chi2inv are
        # not needed; their own names must not trip the gate
        src = "p = pctile(x, 95);\nq = chi2Quantile(0.95, 3);"
        self.assertEqual(tda.scan_source("+shLowLevel/x.m", src), [])

    def test_local_parameter_named_sym_is_not_symbolic(self):
        # shCoefficients.m has: function t = combinedType(ta, tb, sym)
        src = "function t = combinedType(ta, tb, sym)\nt = ta + sym + tb;"
        self.assertEqual(tda.scan_source("shCoefficients.m", src), [])

    def test_word_in_an_error_message_is_not_a_call(self):
        src = "assert(ok, 'sh:x', 'nothing to solve for.');"
        self.assertEqual(tda.scan_source("+shLowLevel/x.m", src), [])

    def test_substring_does_not_match(self):
        # 'batch' is a PCT entry; 'batchSize' as an identifier is not
        self.assertEqual(
            tda.scan_source("+sh/x.m", "batchSize = 10;\nmybatch = 2;"), [])

    def test_allow_list_suppresses(self):
        tda.ALLOW["+sh/legacy.m"] = "documented exception"
        try:
            self.assertEqual(
                tda.scan_source("+sh/legacy.m", "parfor i = 1:3\nend"), [])
        finally:
            del tda.ALLOW["+sh/legacy.m"]

    def test_allow_list_is_empty_by_default(self):
        # an exception must be a visible decision, not an inherited one
        self.assertEqual(tda.ALLOW, {})


class TestIntegration(unittest.TestCase):
    def test_repository_is_clean(self):
        findings = []
        for rel, code in tda.walk(tda.ROOT):
            findings.extend(tda.scan_source(rel, code))
        self.assertEqual(findings, [], "\n".join(findings))

    def test_walk_skips_tests_and_tools(self):
        rels = [rel for rel, _ in tda.walk(tda.ROOT)]
        self.assertTrue(rels, "walk found no .m files at all")
        for r in rels:
            self.assertFalse(r.startswith(("tests/", "tools/", "html/")), r)


if __name__ == "__main__":
    unittest.main(verbosity=2)
