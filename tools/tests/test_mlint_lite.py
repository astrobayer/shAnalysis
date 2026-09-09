#!/usr/bin/env python3
"""Unit tests for tools/dev/mlint_lite.py, R6 in particular.

mlint_lite is the only MATLAB syntax check a Tier-B session has, so a
class of error it cannot see reaches CI intact. R6 exists because one
did: WP1 replaced plotSHSpectrum's inputParser preamble with an
arguments block, but the function's "if ~iscell(specs)" guard sat ABOVE
where inputParser had been. An arguments block must be the first
statement, so the result was a parse error and every call to the
function failed - five red tests on a green mlint_lite.

Run: python3 tools/tests/test_mlint_lite.py

Developed by Matthias Weigelt with the help of Claude (Opus 5), 2026-09-09.
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__))), "dev"))
import mlint_lite as ml  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__))))

GUARD_ABOVE = """\
function h = f(specs, opts)
%F One line.
if ~iscell(specs)
    specs = {specs};
end
arguments
    specs
    opts.A = 1
end
h = opts.A;
end
"""

GUARD_BELOW = """\
function h = f(specs, opts)
%F One line.
arguments
    specs
    opts.A = 1
end
if ~iscell(specs)
    specs = {specs};
end
h = opts.A;
end
"""

NO_ARGUMENTS = """\
function y = g(x)
%G One line.
y = x + 1;
end
"""

# a local function further down must not be blamed for the one above it
TWO_FUNCTIONS = """\
function y = a(x, opts)
%A One line.
arguments
    x
    opts.A = 1
end
y = local(x) + opts.A;
end

function z = local(w)
%LOCAL One line.
z = w * 2;
end
"""


def findings(src):
    return ml.lint_text("t.m", src)


class TestArgumentsFirst(unittest.TestCase):

    def test_a_statement_above_the_block_is_a_finding(self):
        f = findings(GUARD_ABOVE)
        self.assertEqual(len(f), 1, f)
        self.assertIn("not the first statement", f[0][2])

    def test_the_same_guard_below_the_block_is_clean(self):
        self.assertEqual(findings(GUARD_BELOW), [])

    def test_a_function_without_an_arguments_block_is_clean(self):
        self.assertEqual(findings(NO_ARGUMENTS), [])

    def test_a_later_local_function_is_not_blamed(self):
        self.assertEqual(findings(TWO_FUNCTIONS), [])

    def test_a_comment_above_the_block_is_not_a_statement(self):
        src = GUARD_BELOW.replace("arguments", "% a comment\narguments", 1)
        self.assertEqual(findings(src), [])


class TestRealRepository(unittest.TestCase):

    def test_every_shipped_m_file_is_clean(self):
        import glob
        paths = (glob.glob(os.path.join(ROOT, "+shLowLevel", "*.m"))
                 + glob.glob(os.path.join(ROOT, "*.m"))
                 + glob.glob(os.path.join(ROOT, "tests", "*.m")))
        bad = []
        for p in paths:
            with open(p, encoding="utf-8", errors="replace") as fh:
                bad += ml.lint_text(os.path.basename(p), fh.read())
        self.assertEqual(bad, [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
