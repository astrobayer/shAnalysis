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
        # the synthetic tree has no class files; the CLASS pass is
        # exercised separately by _run_class. A class file missing from the
        # REAL tree stays a hard error, which is why this is patched here
        # rather than made tolerant in the gate.
        keep = (eia.PKG, eia.ROOT, eia.CLASS_FILES, eia.TEST_DIR)
        try:
            eia.PKG, eia.ROOT, eia.CLASS_FILES = pkg, d, ()
            eia.TEST_DIR = os.path.join(d, "tests")   # absent: no pins
            return eia.main([])
        finally:
            eia.PKG, eia.ROOT, eia.CLASS_FILES, eia.TEST_DIR = keep


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

    def test_the_two_part_backlog_is_empty(self):
        """A21b: likewise closed, not tracked."""
        self.assertEqual(eia.TWO_PART_OK, set())

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
        self.assertEqual(_run_on_tree(
            "function f()\n%F Does a thing.\n"
            "%   Developed by Matthias Weigelt.\n"
            "error('shLowLevel:f:bad', 'x');\n"), 1)

    def test_that_same_file_passes_once_it_documents(self):
        """The other half: the injected fault must also be curable."""
        self.assertEqual(_run_on_tree(
            "function f()\n%F Does a thing.\n"
            "%   Error identifiers\n"
            "%     shLowLevel:f:bad\n%         why\n%\n"
            "%   Developed by Matthias Weigelt.\n"
            "error('shLowLevel:f:bad', 'x');\n"), 0)

    def test_a_vanished_class_file_is_a_finding_not_a_crash(self):
        probs, _, _ = _run_class_files_missing()
        self.assertTrue(all("does not exist" in p for p in probs), probs)
        self.assertEqual(len(probs), 3)


CLASS_OK = """classdef shSeries
methods
    function out = at(obj, k)
        %AT One epoch.
        %
        %   Error identifiers
        %     shSeries:at:badIndex
        %         k exceeds nEpochs
        %
        if k > obj.nEpochs
            error('shSeries:at:badIndex', 'k=%d too big.', k);
        end
    end

    function out = filter(obj)
        %FILTER Filter the series.
        %
        %   Error identifiers
        %     shSeries:stack:nanInSeries
        %         the stacks carry NaN (the shared stack check)
        %
        obj.assertClean('filter');
        out = obj;
    end
end
methods (Access = private)
    function assertClean(obj, opname)
        if any(isnan(obj.Cs(:)))
            error('shSeries:stack:nanInSeries', '%s needs clean stacks.', opname);
        end
    end
end
end
"""


def _run_class_files_missing():
    """The CLASS pass over a tree that holds none of the three files."""
    with tempfile.TemporaryDirectory() as d:
        keep = eia.ROOT
        try:
            eia.ROOT = d
            return eia.check_classes()
        finally:
            eia.ROOT = keep


def _run_class(source, extra_two_part=None):
    """Run only the CLASS pass over a one-file synthetic tree."""
    with tempfile.TemporaryDirectory() as d:
        with open(os.path.join(d, "shSeries.m"), "w", encoding="utf-8") as fh:
            fh.write(source)
        keep = (eia.ROOT, eia.CLASS_FILES, eia.TWO_PART_OK)
        try:
            eia.ROOT, eia.CLASS_FILES = d, ("shSeries.m",)
            if extra_two_part is not None:
                eia.TWO_PART_OK = extra_two_part
            probs, backlog, checked = eia.check_classes()
            return probs, backlog, checked
        finally:
            eia.ROOT, eia.CLASS_FILES, eia.TWO_PART_OK = keep


class TestClassPass(unittest.TestCase):
    """A21: identifiers belong to METHODS, and private helpers surface
    theirs through the public methods that call them."""

    def test_a_healthy_class_is_clean(self):
        probs, _, checked = _run_class(CLASS_OK)
        self.assertEqual(probs, [])
        self.assertEqual(checked, 2)

    def test_a_private_helpers_id_must_be_documented_by_its_caller(self):
        """The rule that makes the pass worth having."""
        broken = CLASS_OK.replace(
            "        %     shSeries:stack:nanInSeries\n"
            "        %         the stacks carry NaN (the shared stack check)\n", "")
        probs, _, _ = _run_class(broken)
        self.assertTrue(any("filter can raise shSeries:stack:nanInSeries" in p
                            for p in probs), probs)

    def test_a_documented_id_the_method_cannot_reach_is_a_finding(self):
        broken = CLASS_OK.replace(
            "        %     shSeries:at:badIndex",
            "        %     shSeries:at:noSuchThing\n"
            "        %         invented\n        %     shSeries:at:badIndex")
        probs, _, _ = _run_class(broken)
        self.assertTrue(any("documents shSeries:at:noSuchThing" in p
                            for p in probs), probs)

    def test_a_missing_section_is_a_finding(self):
        broken = CLASS_OK.replace("        %   Error identifiers\n"
                                  "        %     shSeries:at:badIndex\n"
                                  "        %         k exceeds nEpochs\n", "")
        probs, _, _ = _run_class(broken)
        self.assertTrue(any("has no 'Error identifiers' section" in p
                            for p in probs), probs)

    def test_a_foreign_identifier_is_a_finding(self):
        broken = CLASS_OK.replace("error('shSeries:at:badIndex'",
                                  "error('shCoefficients:at:badIndex'")
        probs, _, _ = _run_class(broken)
        self.assertTrue(any("the class owns shSeries:* only" in p
                            for p in probs), probs)

    def test_a_two_part_identifier_is_a_finding(self):
        """A21b, v5.0.0: two-part is a defect, not a backlog entry."""
        two = CLASS_OK.replace("shSeries:at:badIndex", "shSeries:badIndex")
        probs, backlog, _ = _run_class(two)
        self.assertTrue(any("two-part shSeries:badIndex" in p
                            for p in probs), probs)
        self.assertEqual(backlog, [])

    def test_the_drained_backlog_mechanism_still_works(self):
        """A14 again: a loop over an empty set cannot fail, so assert the
        MECHANISM with a temporary entry instead of a member name."""
        two = CLASS_OK.replace("shSeries:at:badIndex", "shSeries:badIndex")
        probs, backlog, _ = _run_class(two,
                                       extra_two_part={"shSeries:badIndex"})
        self.assertEqual(probs, [])
        self.assertEqual(backlog, ["shSeries:badIndex"])

    def test_a_middle_segment_that_names_no_method_is_a_finding(self):
        """The rule that makes three-part mean something."""
        typo = CLASS_OK.replace("shSeries:at:badIndex", "shSeries:att:badIndex")
        probs, _, _ = _run_class(typo)
        self.assertTrue(any("names neither a method of this class" in p
                            for p in probs), probs)

    def test_a_declared_shared_check_is_accepted(self):
        """`stack` is not a method, and must still pass."""
        probs, _, _ = _run_class(CLASS_OK)
        self.assertEqual(probs, [])

    def test_a_second_private_hop_is_reported_not_missed(self):
        """One hop is checked, not assumed - the depth guard must fire."""
        deeper = CLASS_OK.replace(
            "    function assertClean(obj, opname)\n"
            "        if any(isnan(obj.Cs(:)))",
            "    function inner(obj)\n"
            "        error('shSeries:stack:nanInSeries', 'x');\n"
            "    end\n\n"
            "    function assertClean(obj, opname)\n"
            "        obj.inner();\n"
            "        if any(isnan(obj.Cs(:)))")
        probs, _, _ = _run_class(deeper)
        self.assertTrue(any("one-hop reachability rule is too shallow" in p
                            for p in probs), probs)


class TestRealClassFiles(unittest.TestCase):

    def test_the_shipped_classes_are_clean(self):
        probs, backlog, checked = eia.check_classes()
        self.assertEqual(probs, [])
        self.assertEqual(checked, 38)  # WP7 four, +analysis nanInGrid (WP5 5e), +regionalNEQ noSigmas (WP8 8c)
        self.assertEqual(backlog, [])

    def test_minus_does_not_claim_the_epoch_check_plus_does(self):
        """shCoefficients.plus calls checkEpochs; minus deliberately does
        not (a difference sets epoch = NaN). The reachability map must
        keep them apart, or the help would promise a wrong catch."""
        funs = eia.parse_class(os.path.join(eia.ROOT, "shCoefficients.m"))
        need, _ = eia.class_requirements(funs)
        self.assertIn("shCoefficients:operands:epochMismatch", need["plus"])
        self.assertNotIn("shCoefficients:operands:epochMismatch", need["minus"])
        # both operators DO reach the rest of the shared operand check, so
        # the `operands` segment does not flatten the distinction away
        self.assertIn("shCoefficients:operands:sizeMismatch", need["minus"])


class TestPins(unittest.TestCase):
    """PINS (v5.0.1): a test may only name an identifier something raises."""

    def _tree(self, test_src, pkg_src="function f()\n%F T.\n"
              "%   Error identifiers\n%     shLowLevel:f:bad\n"
              "%         why\n%\n%   Developed by M W.\n"
              "error('shLowLevel:f:bad', 'x');\n"):
        with tempfile.TemporaryDirectory() as d:
            pkg = os.path.join(d, "+shLowLevel")
            tests = os.path.join(d, "tests")
            os.makedirs(pkg)
            os.makedirs(tests)
            with open(os.path.join(pkg, "f.m"), "w", encoding="utf-8") as fh:
                fh.write(pkg_src)
            with open(os.path.join(tests, "testX.m"), "w", encoding="utf-8") as fh:
                fh.write(test_src)
            keep = (eia.PKG, eia.ROOT, eia.CLASS_FILES, eia.TEST_DIR)
            try:
                eia.PKG, eia.ROOT, eia.CLASS_FILES, eia.TEST_DIR = \
                    pkg, d, (), tests
                return eia.check_pins()
            finally:
                eia.PKG, eia.ROOT, eia.CLASS_FILES, eia.TEST_DIR = keep

    def test_a_pin_on_a_real_identifier_passes(self):
        probs, n = self._tree("verifyError(t, @() f(), 'shLowLevel:f:bad');\n")
        self.assertEqual(probs, [])
        self.assertEqual(n, 1)

    def test_a_pin_on_an_identifier_nothing_raises_is_a_finding(self):
        probs, _ = self._tree("verifyError(t, @() f(), 'shLowLevel:f:ghost');\n")
        self.assertTrue(any("shLowLevel:f:ghost" in p for p in probs), probs)

    def test_a_pin_cannot_validate_itself(self):
        """The bug the first version had: harvesting prefix literals from
        tests/ too let the bad pin be read as its own prefix."""
        probs, _ = self._tree("verifyError(t, @() f(), 'shLowLevel:ghost');\n"
                              "x = 'shLowLevel:ghost';\n")
        self.assertTrue(any("shLowLevel:ghost" in p for p in probs), probs)

    def test_a_prefix_covers_only_what_sits_below_it(self):
        # `shLowLevel:f:pre` is handed to a helper that appends a reason,
        # exactly as normalizeMonthList is used; it is never raised whole.
        pkg = ("function f()\n%F T.\n"
               "%   Error identifiers\n%     shLowLevel:f:bad\n"
               "%         why\n%\n%   Developed by M W.\n"
               "g(months, 'shLowLevel:f:pre');\n"
               "error('shLowLevel:f:bad', 'x');\n")
        ok, _ = self._tree("verifyError(t, @() f(), 'shLowLevel:f:pre:sub');\n",
                           pkg_src=pkg)
        self.assertEqual(ok, [])
        bad, _ = self._tree("verifyError(t, @() f(), 'shLowLevel:f:preFoo');\n",
                            pkg_src=pkg)
        self.assertTrue(any("shLowLevel:f:preFoo" in p for p in bad), bad)

    def test_an_identifier_a_test_helper_RAISES_is_not_a_pin(self):
        """tests/rmIfFolder.m warns shAnalysis:test:cleanupFailed."""
        probs, _ = self._tree(
            "warning('shAnalysis:helper:cleanupFailed', 'x');\n")
        self.assertEqual(probs, [])

    def test_the_limit_is_real_and_stated(self):
        """A pin naming a REAL identifier the call cannot reach is NOT
        caught - that needs per-call guard analysis. A21b's first red
        round was exactly this shape, and the docstring says so."""
        probs, _ = self._tree("verifyError(t, @() g(), 'shLowLevel:f:bad');\n")
        self.assertEqual(probs, [])
        self.assertIn("NOT catch a pin naming a real identifier",
                      " ".join(eia.__doc__.split()))


class TestDriven(unittest.TestCase):
    """DRIVEN (v5.24.1): every raised identifier is named by a test, or
    backlogged in a list that may only shrink."""

    PKG = ("function f()\n%F T.\n"
           "%   Error identifiers\n%     shLowLevel:f:bad\n"
           "%         why\n%     shLowLevel:f:worse\n%         why\n%\n"
           "%   Developed by M W.\n"
           "error('shLowLevel:f:bad', 'x');\n"
           "error('shLowLevel:f:worse', 'y');\n")

    def _driven(self, test_src, undriven):
        with tempfile.TemporaryDirectory() as d:
            pkg = os.path.join(d, "+shLowLevel")
            tests = os.path.join(d, "tests")
            os.makedirs(pkg)
            os.makedirs(tests)
            with open(os.path.join(pkg, "f.m"), "w", encoding="utf-8") as fh:
                fh.write(self.PKG)
            with open(os.path.join(tests, "testX.m"), "w", encoding="utf-8") as fh:
                fh.write(test_src)
            keep = (eia.PKG, eia.ROOT, eia.CLASS_FILES, eia.TEST_DIR)
            try:
                eia.PKG, eia.ROOT, eia.CLASS_FILES, eia.TEST_DIR = \
                    pkg, d, (), tests
                return eia.check_driven(set(undriven))
            finally:
                eia.PKG, eia.ROOT, eia.CLASS_FILES, eia.TEST_DIR = keep

    BOTH = ("verifyError(t, @() f(), 'shLowLevel:f:bad');\n"
            "verifyError(t, @() f(), 'shLowLevel:f:worse');\n")

    def test_every_identifier_named_passes(self):
        probs, n, back = self._driven(self.BOTH, [])
        self.assertEqual(probs, [])
        self.assertEqual((n, back), (2, 0))

    def test_an_undriven_identifier_is_a_finding(self):
        probs, _, _ = self._driven(
            "verifyError(t, @() f(), 'shLowLevel:f:bad');\n", [])
        self.assertTrue(any("shLowLevel:f:worse" in p and "no test names it"
                            in p for p in probs), probs)

    def test_a_backlogged_identifier_passes(self):
        probs, _, back = self._driven(
            "verifyError(t, @() f(), 'shLowLevel:f:bad');\n",
            ["shLowLevel:f:worse"])
        self.assertEqual(probs, [])
        self.assertEqual(back, 1)

    def test_the_backlog_only_shrinks(self):
        probs, _, _ = self._driven(self.BOTH, ["shLowLevel:f:worse"])
        self.assertTrue(any("delete it from" in p for p in probs), probs)

    def test_a_stale_backlog_entry_is_a_finding(self):
        probs, _, _ = self._driven(self.BOTH, ["shLowLevel:f:gone"])
        self.assertTrue(any("nothing raises it" in p for p in probs), probs)

    def test_a_name_in_a_comment_does_not_drive(self):
        probs, _, _ = self._driven(
            "verifyError(t, @() f(), 'shLowLevel:f:bad');\n"
            "% verifyError(t, @() f(), 'shLowLevel:f:worse');\n", [])
        self.assertTrue(any("shLowLevel:f:worse" in p for p in probs), probs)

    def test_the_real_backlog_file_is_read(self):
        self.assertTrue(os.path.isfile(eia.UNDRIVEN_FILE))
        self.assertEqual(eia.UNDRIVEN, eia.load_undriven())
        for i in eia.UNDRIVEN:
            self.assertRegex(i, r"^(shLowLevel|shAnalysis|shCoefficients|"
                                r"shSeries|shClimatology):\w+:\w+$")

    def test_the_limit_is_stated(self):
        self.assertIn("naming is not driving", " ".join(eia.__doc__.split()))


if __name__ == "__main__":
    unittest.main(verbosity=2)
