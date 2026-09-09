#!/usr/bin/env python3
"""Unit tests for tools/dev/name_coverage.py (A10).

The gate's one claim is narrow: some test file names the entity in
EXECUTABLE code. These tests pin the two ways that claim can be faked or
lost - a name that only appears in a comment must not count, and an
entity nothing mentions must be reported.

Run: python3 tools/tests/test_name_coverage.py

Developed by Matthias Weigelt with the help of Claude (Opus 5), 2026-09-08.
"""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__))), "dev"))
import name_coverage as nc  # noqa: E402

API = {
    "shLowLevel": [{"name": "pctile"}, {"name": "opApply"}],
    "root": [{"name": "setup_shAnalysis"}],
    "classes": [{"name": "shCoefficients",
                 "methods": [{"name": "plus"}, {"name": "disp"}]}],
}

COVERED = """\
function testThing(tc)
v = shLowLevel.pctile(1:10, 50);
y = shLowLevel.opApply(op, Z, 1);
setup_shAnalysis();
g = plus(a, b);
disp(g);
end
"""

ONLY_IN_COMMENTS = """\
function testThing(tc)
% this test is about shLowLevel.pctile and opApply
x = 1;    % see also setup_shAnalysis, plus and disp
end
"""

BLOCK_COMMENT = """\
function testThing(tc)
%{
shLowLevel.pctile(1:10, 50)
plus(a, b)
%}
x = 1;
end
"""


class TestCodeOnly(unittest.TestCase):

    def test_line_comment_is_stripped(self):
        self.assertNotIn("pctile", nc.code_only("% call shLowLevel.pctile"))

    def test_trailing_comment_is_stripped(self):
        out = nc.code_only("x = 1;   % pctile lives here")
        self.assertIn("x = 1", out)
        self.assertNotIn("pctile", out)

    def test_block_comment_is_stripped(self):
        self.assertNotIn("pctile", nc.code_only(BLOCK_COMMENT))

    def test_code_survives(self):
        self.assertIn("pctile", nc.code_only("v = shLowLevel.pctile(x, 50);"))


class TestUncovered(unittest.TestCase):

    def test_fully_covered_tree_reports_nothing(self):
        self.assertEqual(nc.uncovered(API, nc.code_only(COVERED)), [])

    def test_names_only_in_comments_do_not_count(self):
        got = {q for q, _, _ in nc.uncovered(API, nc.code_only(ONLY_IN_COMMENTS))}
        self.assertEqual(got, {"shLowLevel.pctile", "shLowLevel.opApply",
                              "setup_shAnalysis", "shCoefficients.plus",
                              "shCoefficients.disp"})

    def test_a_missing_entity_is_reported_with_its_kind(self):
        code = nc.code_only(COVERED).replace("shLowLevel.opApply", "other")
        got = nc.uncovered(API, code)
        self.assertEqual([(q, k) for q, _, k in got],
                         [("shLowLevel.opApply", "package")])

    def test_substring_is_not_a_match(self):
        """pctile must not be matched by "mypctileHelper"."""
        got = {q for q, _, _ in nc.uncovered(API, "x = mypctileHelper(1);")}
        self.assertIn("shLowLevel.pctile", got)


class TestRealRepository(unittest.TestCase):

    def test_the_shipped_suite_names_every_public_entity(self):
        self.assertEqual(nc.main([]), 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
