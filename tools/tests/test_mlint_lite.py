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


Q = chr(39)
BS = chr(92)
NLC = chr(10)

# The exact defect R7 was written for: a v5.2.0 edit dropped a real newline
# into an fprintf format. mlint_lite said zero findings and MATLAB refused to
# parse the class, so every test in it vanished rather than failed.
R7_BAD = NLC.join(["function f()", "fprintf(" + Q + "XOVER,%d", "', 1);", "end"])
R7_GOOD = NLC.join(["function f()",
                    "fprintf(" + Q + "XOVER,%d" + BS + "n" + Q + ", 1);",
                    "end"])
R7_CONT = NLC.join(["function f()",
                    "fprintf(" + Q + "XOVER,%d" + BS + "n" + Q + ", ...",
                    "    1);", "end"])
R7_TRANSPOSE = NLC.join(["function f()", "x = A' * b;",
                         "y = z.b' + c(1)';", "end"])
R7_DQ = NLC.join(["function f()", chr(109) + ' = "abc', '";', "end"])


def r7(src):
    return [f for f in ml.lint_text("t.m", src) if "R7" in f[2]]


class TestUnterminatedLiteral(unittest.TestCase):
    """R7, fault-injected both ways. A rule that only ever sees clean code
    proves nothing, and one that fires on legal code is worse than absent:
    a transpose after a value and a literal split by ... are both legal."""

    def test_the_injected_defect_fires(self):
        self.assertTrue(r7(R7_BAD), "R7 missed an unterminated char vector")

    def test_the_repaired_line_is_clean(self):
        self.assertEqual(r7(R7_GOOD), [])

    def test_a_continuation_is_not_an_unterminated_literal(self):
        self.assertEqual(r7(R7_CONT), [])

    def test_a_transpose_is_not_a_literal(self):
        self.assertEqual(r7(R7_TRANSPOSE), [])

    def test_an_unterminated_string_scalar_fires_too(self):
        self.assertTrue(r7(R7_DQ), "R7 only covers char vectors")


def r8(lines):
    return [f for f in ml.lint_text("t.m", "\n".join(lines)) if "R8" in f[2]]


R8_HEAD = ["function f(N, opts)", "arguments", "    N double",
           "    opts.Range (1,2) double = [0 1]", "    opts.Col (:,1) double = []",
           "    opts.K (1,1) double = 3", "end"]


class TestNonScalarFormatArgument(unittest.TestCase):
    """R8 (v5.24.1), fault-injected both ways on the three shapes that
    shipped - vdkApply's size(N), signalVarianceKaula's 1 x 2 LRange,
    obpChain's 1 x 2 RefPeriod - and silent on the legal look-alikes."""

    def test_a_declared_pair_fires(self):
        self.assertTrue(r8(R8_HEAD + ["error('a:b:c', '[%g, %g]', opts.Range);", "end"]))

    def test_a_declared_column_fires(self):
        self.assertTrue(r8(R8_HEAD + ["warning('a:b:c', '%d', opts.Col);", "end"]))

    def test_a_bare_size_fires(self):
        self.assertTrue(r8(R8_HEAD + ["error('a:b:c', '%d x %d', size(N));", "end"]))

    def test_a_continued_call_fires(self):
        self.assertTrue(r8(R8_HEAD + ["error('a:b:c', ...", "    '[%g %g]', ...",
                                      "    opts.Range);", "end"]))

    def test_indexed_elements_are_clean(self):
        self.assertEqual(r8(R8_HEAD + ["error('a:b:c', '[%g, %g]', opts.Range(1), "
                                       "opts.Range(2));", "end"]), [])

    def test_size_with_a_dimension_is_clean(self):
        self.assertEqual(r8(R8_HEAD + ["error('a:b:c', '%d', size(N, 1));", "end"]), [])

    def test_numel_and_mat2str_are_clean(self):
        self.assertEqual(r8(R8_HEAD + ["error('a:b:c', '%d %s', numel(opts.Col), "
                                       "mat2str(size(N)));", "end"]), [])

    def test_a_declared_scalar_is_clean(self):
        self.assertEqual(r8(R8_HEAD + ["error('a:b:c', '%d', opts.K);", "end"]), [])

    def test_a_message_only_call_is_clean(self):
        self.assertEqual(r8(R8_HEAD + ["error('a:b:c', 'no format here');", "end"]), [])

    def test_a_name_in_a_comment_is_not_read(self):
        self.assertEqual(r8(R8_HEAD + ["% error('a:b:c', '%g', opts.Range);", "end"]), [])


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
