#!/usr/bin/env python3
"""Unit tests for tools/error_id_audit.py (A3/A15).

The gate's value is that it separates a RAISE from a mention. A first
version did not, and reported five violations of which four were false:
tvANSFilter compares against another function's identifier in a catch
block, and fetchITSGSINEX passes its own name as a prefix to a helper.
Those two shapes are pinned here, because they are the ones that make a
naive implementation lie.

Run: python3 tools/tests/test_error_id_audit.py

Developed by Matthias Weigelt with the help of Claude (Opus 5), 2026-09-09.
"""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import error_id_audit as eia  # noqa: E402


class TestRaiseDetection(unittest.TestCase):

    def test_error_first_argument(self):
        self.assertEqual(eia.raised_in("error('shLowLevel:f:bad', 'x');")[0], {"shLowLevel:f:bad"})

    def test_warning_first_argument(self):
        self.assertEqual(eia.raised_in("warning('shLowLevel:f:w', 'x');")[0], {"shLowLevel:f:w"})

    def test_assert_second_argument(self):
        self.assertEqual(eia.raised_in("assert(a == b, 'shLowLevel:f:bad', 'x');")[0], {"shLowLevel:f:bad"})

    def test_continuation_is_folded(self):
        src = "error('shLowLevel:f:bad', ...\n    'message here');"
        self.assertEqual(eia.raised_in(eia.fold(src))[0], {"shLowLevel:f:bad"})

    def test_a_catch_comparison_is_not_a_raise(self):
        """tvANSFilter's shape - the false positive that mattered."""
        src = ("if strcmp(ME.identifier, "
               "'shLowLevel:buildNoiseCov:notBlockDiagonal')\n    x = 1;\nend")
        self.assertEqual(eia.raised_in(src)[0], set())

    def test_a_prefix_string_is_not_a_raise(self):
        """fetchITSGSINEX's shape: the helper appends the reason."""
        src = 'mm = normalizeMonthList(months, "shLowLevel:fetchITSGSINEX");'
        self.assertEqual(eia.raised_in(src)[0], set())

    def test_a_message_without_an_identifier_is_not_one(self):
        self.assertEqual(eia.raised_in("error('plain message, no id');")[0], set())


class TestRuntimeBuiltIdentifiers(unittest.TestCase):
    """setup_shAnalysis raises "shAnalysis:setup:no" + <option name>.

    Reading that literal as an identifier invents `shAnalysis:setup:no`,
    which nothing raises - the gate reported exactly that before the rule
    existed. It is a PREFIX, and the help carries the five real names.
    """

    def test_a_concatenated_literal_is_a_prefix_not_an_id(self):
        src = 'warning("shAnalysis:setup:no" + locs(li, 1), \'%s\', v);'
        ids, pre = eia.raised_in(src)
        self.assertEqual(ids, set())
        self.assertEqual(pre, {"shAnalysis:setup:no"})

    def test_a_plain_literal_is_still_an_id(self):
        ids, pre = eia.raised_in("warning('shAnalysis:setup:docsFailed', 'x');")
        self.assertEqual(ids, {"shAnalysis:setup:docsFailed"})
        self.assertEqual(pre, set())

    def test_a_prefix_with_no_documented_member_is_a_finding(self):
        self.assertEqual(_run_on_tree(
            'function f()\n%F Thing.\n'
            '%   Error identifiers\n%     shAnalysis:f:other\n%         why\n%\n'
            '%   Developed by Matthias Weigelt.\n'
            'warning("shAnalysis:f:no" + nm, \'x\');\n'
            'error(\'shAnalysis:f:other\', \'x\');\n', root=True), 1)

    def test_a_prefix_with_a_documented_member_passes(self):
        self.assertEqual(_run_on_tree(
            'function f()\n%F Thing.\n'
            '%   Error identifiers\n%     shAnalysis:f:noThing\n%         why\n%\n'
            '%   Developed by Matthias Weigelt.\n'
            'warning("shAnalysis:f:no" + nm, \'x\');\n', root=True), 0)


def _run_on_tree(source, root=False):
    """Run the gate over a one-file tree; returns its exit code."""
    with tempfile.TemporaryDirectory() as d:
        pkg = os.path.join(d, "+shLowLevel")
        os.makedirs(pkg)
        with open(os.path.join(d if root else pkg, "f.m"), "w",
                  encoding="utf-8") as fh:
            fh.write(source)
        keepP, keepR = eia.PKG, eia.ROOT
        try:
            eia.PKG, eia.ROOT = pkg, d
            return eia.main([])
        finally:
            eia.PKG, eia.ROOT = keepP, keepR


class TestDocumentation(unittest.TestCase):

    def test_no_section_reads_as_None_not_empty(self):
        self.assertIsNone(eia.documented_in("%   Outputs\n%     x\n"))

    def test_id_alone_on_its_line(self):
        src = "%   Error identifiers\n%     shLowLevel:f:bad\n%         why\n"
        self.assertEqual(eia.documented_in(src), {"shLowLevel:f:bad"})

    def test_id_and_reason_on_one_line(self):
        """The second house style, which the first regex missed."""
        src = "%   Error identifiers\n%     shLowLevel:f:bad   why it happens\n"
        self.assertEqual(eia.documented_in(src), {"shLowLevel:f:bad"})


class TestRealRepository(unittest.TestCase):

    def test_the_shipped_tree_is_clean(self):
        self.assertEqual(eia.main([]), 0)

    def test_the_backlog_is_empty(self):
        """A20: the finding is closed, not merely tracked."""
        self.assertEqual(eia.UNDOCUMENTED, set())

    def test_the_backlog_mechanism_still_works_while_empty(self):
        """A14's lesson: a drained list makes a membership test vacuous.

        `test_backlog_only_names_files_without_a_section` iterated over
        UNDOCUMENTED, so draining it would have left an assertion that
        can no longer fail - the exact shape in which
        `test_legacy_name_tolerated` sat broken for a release. So assert
        the MECHANISM with a temporary entry instead of a member name.
        """
        stem = "ylm"                       # documents its identifiers now
        keep = eia.UNDOCUMENTED
        try:
            eia.UNDOCUMENTED = {stem}
            self.assertEqual(eia.main([]), 1,
                             "a documented file left in the backlog must be "
                             "reported, or the backlog can never drain")
        finally:
            eia.UNDOCUMENTED = keep

    def test_a_file_outside_the_backlog_must_document(self):
        """The rule the drained backlog now applies to every file."""
        with tempfile.TemporaryDirectory() as d:
            pkg = os.path.join(d, "+shLowLevel")
            os.makedirs(pkg)
            with open(os.path.join(pkg, "f.m"), "w", encoding="utf-8") as fh:
                fh.write("function f()\n%F Does a thing.\n"
                         "%   Developed by Matthias Weigelt.\n"
                         "error('shLowLevel:f:bad', 'x');\n")
            keep = eia.PKG
            try:
                eia.PKG = pkg
                self.assertEqual(eia.main([]), 1)
            finally:
                eia.PKG = keep

    def test_that_same_file_passes_once_it_documents(self):
        """The other half: the injected fault must also be curable."""
        with tempfile.TemporaryDirectory() as d:
            pkg = os.path.join(d, "+shLowLevel")
            os.makedirs(pkg)
            with open(os.path.join(pkg, "f.m"), "w", encoding="utf-8") as fh:
                fh.write("function f()\n%F Does a thing.\n"
                         "%   Error identifiers\n"
                         "%     shLowLevel:f:bad\n%         why\n%\n"
                         "%   Developed by Matthias Weigelt.\n"
                         "error('shLowLevel:f:bad', 'x');\n")
            keep = eia.PKG
            try:
                eia.PKG = pkg
                self.assertEqual(eia.main([]), 0)
            finally:
                eia.PKG = keep


if __name__ == "__main__":
    unittest.main(verbosity=2)
