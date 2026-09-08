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
