#!/usr/bin/env python3
"""Unit tests for tools/help_audit.py, structural section rules.

Fault injection: each rule must FIRE on a help block carrying the defect
and stay SILENT on the healthy tree. The rules were added after 65 help
blocks (13 in +shLowLevel, 52 class methods) were found carrying two
sections of the same kind, the generated one contradicting the
hand-written one about the returned struct fields, with every gate green
for 27 days.

Run: python3 tools/tests/test_help_audit.py

Developed by Matthias Weigelt with the help of Claude (Opus 5),
2026-09-08.
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(
    os.path.abspath(__file__))))
import help_audit as ha  # noqa: E402


HEALTHY = """\
FOO One line of summary.

   OUT = FOO(A) does a thing.

   Inputs
     a    (1,1) double  the thing
   Options
     Scale (1)  (1,1) double  multiplier
   Outputs
     out  (1,1) double  the result
   Error identifiers
     shLowLevel:foo:badInput  a is not finite
   Example
     out = shLowLevel.foo(2);

   Developed by Matthias Weigelt with the help of Claude (Opus 5).
"""


class TestDuplicateSection(unittest.TestCase):
    def test_healthy_block_is_silent(self):
        self.assertEqual(ha.structure(HEALTHY, "foo"), [])

    def test_second_outputs_section_fires(self):
        bad = HEALTHY.replace(
            "   Error identifiers",
            "   Outputs\n     out  (1,1) double  the result, again\n"
            "   Error identifiers")
        p = ha.structure(bad, "foo")
        self.assertEqual(len(p), 1, p)
        self.assertIn("appears twice", p[0])
        self.assertIn("Outputs", p[0])

    def test_second_options_section_fires(self):
        bad = HEALTHY.replace(
            "   Outputs",
            "   Options\n     Scale (1)  (1,1) double  multiplier\n"
            "   Outputs", 1)
        p = ha.structure(bad, "foo")
        self.assertEqual(len(p), 1, p)
        self.assertIn("Options", p[0])

    def test_line_numbers_point_at_both_occurrences(self):
        bad = HEALTHY.replace(
            "   Error identifiers",
            "   Outputs\n     out  (1,1) double  again\n   Error identifiers")
        p = ha.structure(bad, "foo")[0]
        # the first Outputs is help line 9, the injected one line 11
        self.assertIn("9", p)
        self.assertIn("11", p)


class TestAfterProvenance(unittest.TestCase):
    def test_section_below_the_footer_fires(self):
        bad = HEALTHY.rstrip("\n") + \
            "\n   Outputs\n     out  (1,1) double  invisible to the builder\n"
        p = ha.structure(bad, "foo")
        # both rules see it: it is a duplicate AND it is below the footer
        self.assertTrue(any("after the provenance footer" in x for x in p), p)

    def test_a_first_section_below_the_footer_also_fires(self):
        bad = HEALTHY.replace(
            "   Error identifiers\n     shLowLevel:foo:badInput"
            "  a is not finite\n", "")
        bad = bad.rstrip("\n") + \
            "\n   Error identifiers\n     shLowLevel:foo:badInput  bad\n"
        p = ha.structure(bad, "foo")
        self.assertEqual(len(p), 1, p)
        self.assertIn("after the provenance footer", p[0])


class TestSpelling(unittest.TestCase):
    def test_near_misses_fire_with_the_house_spelling(self):
        for wrong, right in (("Output", "Outputs"),
                             ("Examples", "Example"),
                             ("Errors", "Error identifiers"),
                             ("Name/value options", "Options")):
            bad = HEALTHY.replace("   Inputs", "   " + wrong, 1)
            p = ha.structure(bad, "foo")
            self.assertTrue(any(right in x and "should be spelt" in x
                                for x in p), (wrong, p))

    def test_prose_subheadings_are_not_sections(self):
        # free-text sub-headings inside a description are legitimate and
        # must not be mistaken for the house vocabulary
        for head in ("Sampling models", "Modes", "Construction",
                     "Recognized layouts", "Typical chain"):
            bad = HEALTHY.replace("   Inputs", "   " + head + "\n   Inputs", 1)
            self.assertEqual(ha.structure(bad, "foo"), [], head)


STRUCT_SRC = """function [out, info] = foo(a)
out = struct('alpha', 1, 'beta', 2);
out.gamma = 3;
info.mode = 'x';
end
"""

STRUCT_HELP = """\
FOO One line.

   Inputs
     a    (1,1) double  the thing
   Outputs
     out   (1,1) struct  fields
           alpha  (1,1) double  first
           beta   (1,1) double  second
           gamma  (1,1) double  third
     info  (1,1) struct  fields
           mode   (1,:) char  which path ran
   Example
     out = foo(1);

   Developed by Matthias Weigelt with the help of Claude (Opus 5).
"""


class TestStructFields(unittest.TestCase):
    """A12: help_audit checked output VARIABLES, never the FIELDS a struct
    output promises, so readTN14 documented tn.t (no such field) and
    shAnalysisGrid documented info.condest for condEst."""

    def outs(self):
        return {"out", "info"}

    def test_healthy_struct_docs_are_silent(self):
        self.assertEqual(
            ha.struct_fields(STRUCT_HELP, STRUCT_SRC, "foo", self.outs()), [])

    def test_documented_field_the_code_never_assigns_fires(self):
        bad = STRUCT_HELP.replace("gamma  (1,1) double  third",
                                  "delta  (1,1) double  third")
        p = ha.struct_fields(bad, STRUCT_SRC, "foo", self.outs())
        self.assertTrue(any("out.delta" in x and "never assigns" in x
                            for x in p), p)

    def test_case_difference_is_a_different_field(self):
        # MATLAB field names are case-sensitive: info.condest for condEst
        # gave the user an error, not a value
        bad = STRUCT_HELP.replace("alpha  (1,1)", "Alpha  (1,1)")
        p = ha.struct_fields(bad, STRUCT_SRC, "foo", self.outs())
        self.assertTrue(any("out.Alpha" in x for x in p), p)

    def test_assigned_field_missing_from_the_section_fires(self):
        bad = STRUCT_HELP.replace(
            "           gamma  (1,1) double  third\n", "")
        p = ha.struct_fields(bad, STRUCT_SRC, "foo", self.outs())
        self.assertTrue(any("assigns 'out.gamma'" in x and
                            "never mentions it" in x for x in p), p)

    def test_nested_call_literals_are_not_fields(self):
        # struct('created', string(datetime('now','Format','...'))) is ONE
        # field, not three
        src = ("function out = f()\n"
               "out = struct('created', string(datetime('now', "
               "'Format', 'yyyy-MM-dd'))));\nend\n")
        self.assertEqual(ha.fields_assigned_to(src, "out"), {"created"})

    def test_transpose_is_not_a_quote(self):
        # MATLAB ' is transpose after a value. Reading w' as the start of a
        # string desynchronised the scan and hid three of basinKernel's
        # four fields - which would have made a correct help block look
        # wrong the moment its row was converted to a field list.
        src = ("function info = f(w, mask)\n"
               "info = struct('areaFraction', w' * mask, "
               "'nGridPoints', numel(mask), 'buffered', true, "
               "'tapered', false);\nend\n")
        self.assertEqual(
            ha.fields_assigned_to(src, "info"),
            {"areaFraction", "nGridPoints", "buffered", "tapered"})

    def test_doubled_quote_inside_a_literal(self):
        src = ("function out = f()\n"
               "out = struct('name', 'it''s fine', 'other', 1);\nend\n")
        self.assertEqual(ha.fields_assigned_to(src, "out"),
                         {"name", "other"})

    def test_a_quoted_value_is_not_a_field(self):
        # struct() alternates name, value: the "zeroField" in
        # struct(..., 'stoppedBy', "zeroField", ...) is a VALUE, and
        # counting it invented a field leakageCorrect does not have
        src = ("function info = f()\n"
               "info = struct('stoppedBy', \"zeroField\", "
               "'converged', true);\nend\n")
        self.assertEqual(ha.fields_assigned_to(src, "info"),
                         {"stoppedBy", "converged"})

    def test_sibling_method_variables_do_not_leak(self):
        # a class file holds many methods; 'info' in another one is not this
        # one's (that leak invented 57 findings)
        self.assertNotIn("mode", ha.fields_assigned_to(STRUCT_SRC, "out"))

    def test_delegated_struct_needs_no_field_list(self):
        h = STRUCT_HELP.replace(
            "     info  (1,1) struct  fields\n"
            "           mode   (1,:) char  which path ran\n",
            "     info  (1,1) struct  as returned by shLowLevel.other\n")
        stats = {"listed": 0, "prose": 0, "delegated": 0}
        ha.struct_fields(h, STRUCT_SRC, "foo", self.outs(), stats)
        self.assertEqual(stats["delegated"], 1)

    def test_prose_rows_are_counted_not_silently_passed(self):
        h = STRUCT_HELP.replace(
            "     info  (1,1) struct  fields\n"
            "           mode   (1,:) char  which path ran\n",
            "     info  (1,1) struct  mode and other things in prose\n")
        stats = {"listed": 0, "prose": 0, "delegated": 0}
        ha.struct_fields(h, STRUCT_SRC, "foo", self.outs(), stats)
        self.assertEqual(stats["prose"], 1)
        self.assertEqual(stats["listed"], 1)


class TestIntegration(unittest.TestCase):
    def test_repository_help_blocks_are_structurally_clean(self):
        """the healthy tree stays silent - the other half of the injection"""
        pkg = os.path.join(ha.ROOT, "+shLowLevel")
        probs = []
        for f in sorted(os.listdir(pkg)):
            if not f.endswith(".m"):
                continue
            e = ha.parse_file(os.path.join(pkg, f))
            if e:
                probs += ha.structure(e["help"], "shLowLevel." + e["name"])
        self.assertEqual(probs, [], "\n".join(probs))


if __name__ == "__main__":
    unittest.main(verbosity=2)
