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
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import error_id_audit as eia  # noqa: E402


class TestRaiseDetection(unittest.TestCase):

    def test_error_first_argument(self):
        self.assertEqual(eia.raised_in("error('shLowLevel:f:bad', 'x');"),
                         {"shLowLevel:f:bad"})

    def test_warning_first_argument(self):
        self.assertEqual(eia.raised_in("warning('shLowLevel:f:w', 'x');"),
                         {"shLowLevel:f:w"})

    def test_assert_second_argument(self):
        self.assertEqual(eia.raised_in("assert(a == b, 'shLowLevel:f:bad', 'x');"),
                         {"shLowLevel:f:bad"})

    def test_continuation_is_folded(self):
        src = "error('shLowLevel:f:bad', ...\n    'message here');"
        self.assertEqual(eia.raised_in(eia.fold(src)), {"shLowLevel:f:bad"})

    def test_a_catch_comparison_is_not_a_raise(self):
        """tvANSFilter's shape - the false positive that mattered."""
        src = ("if strcmp(ME.identifier, "
               "'shLowLevel:buildNoiseCov:notBlockDiagonal')\n    x = 1;\nend")
        self.assertEqual(eia.raised_in(src), set())

    def test_a_prefix_string_is_not_a_raise(self):
        """fetchITSGSINEX's shape: the helper appends the reason."""
        src = 'mm = normalizeMonthList(months, "shLowLevel:fetchITSGSINEX");'
        self.assertEqual(eia.raised_in(src), set())

    def test_a_message_without_an_identifier_is_not_one(self):
        self.assertEqual(eia.raised_in("error('plain message, no id');"), set())


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

    def test_backlog_only_names_files_without_a_section(self):
        for stem in eia.UNDOCUMENTED:
            path = os.path.join(eia.PKG, stem + ".m")
            self.assertTrue(os.path.isfile(path), "%s is not a package file" % stem)
            src, _ = eia.code_of(path)
            self.assertNotIn(eia.SECTION, src,
                             "%s documents its identifiers - remove it" % stem)


if __name__ == "__main__":
    unittest.main(verbosity=2)
