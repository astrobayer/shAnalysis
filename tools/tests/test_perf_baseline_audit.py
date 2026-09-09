#!/usr/bin/env python3
"""Unit tests for tools/dev/perf_baseline_audit.py.

Every rule is fault-injected in BOTH directions on a synthetic tree: the
healthy tree must be silent, and each break must fire with a message that
names the thing that is broken. A rule that only ever ran against the real
repository would be evidence about that repository, not about the rule.

Run: python3 tools/tests/test_perf_baseline_audit.py

Developed by Matthias Weigelt with the help of Claude (Opus 5), 2026-09-09.
"""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__))), "dev"))
import perf_baseline_audit as pba  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__))))

PERF = """\
classdef testPerformance < matlab.perftest.TestCase
properties (TestParameter)
    nmaxP = struct('n60', 60, 'n120', 120);
    budgetCase = struct( ...
        'alpha', 'alpha', ...
        'beta',  'beta');
end

methods (Test)
    function testSpeedBudget(tc, budgetCase)
    end
end

methods
    function fcn = workload(tc, name)
        switch name
            case 'alpha'
                fcn = @() 1;
            case 'beta'
                fcn = @() 2;
            otherwise
                error('x:y:z', 'no');
        end
    end

    function g = randomField(~, nmax)
    end
end
end
"""

HEAD = pba.HEADER + "\n"
ROWS = ("# a comment line\n" + HEAD +
        "A8,2026a,alpha,1.250000,1.100000,15,2026-09-09\n"
        "A8,2026a,beta,0.500000,0.500000,15,2026-09-09\n")


def build(tmp, perf=PERF, csv=ROWS):
    os.makedirs(os.path.join(tmp, "tests"), exist_ok=True)
    with open(os.path.join(tmp, pba.PERF), "w", encoding="utf-8") as fh:
        fh.write(perf)
    with open(os.path.join(tmp, pba.CSV), "w", encoding="utf-8") as fh:
        fh.write(csv)
    return tmp


class Base(unittest.TestCase):
    def run_on(self, perf=PERF, csv=ROWS, backlog=None):
        keep = pba.NO_BASELINE
        pba.NO_BASELINE = {} if backlog is None else backlog
        try:
            with tempfile.TemporaryDirectory() as tmp:
                return pba.audit(build(tmp, perf, csv))[0]
        finally:
            pba.NO_BASELINE = keep


class TestHealthy(Base):
    def test_a_healthy_tree_is_silent(self):
        self.assertEqual(self.run_on(), [])

    def test_comments_and_blank_lines_are_not_rows(self):
        csv = "\n# note\n\n" + HEAD + \
            "A8,2026a,alpha,1,1,15,2026-09-09\n" \
            "A8,2026a,beta,1,1,15,2026-09-09\n"
        self.assertEqual(self.run_on(csv=csv), [])


NL = chr(10)


class TestMachineCase(Base):
    """v5.2.0 (A23). machineId() upper-cases the label, so a mixed-case row
    can never match. It would not FAIL its budget - it would filter it, and
    a filtered budget guards nothing while looking green. Both directions
    are injected: the fold accepts what it should and rejects what it must.
    """

    def test_a_lower_case_machine_fires(self):
        csv = HEAD + NL.join(["A8,2026a,alpha,1,1,15,2026-09-09", "MatthiasPC,2026a,beta,1,1,15,2026-09-09", ""])
        out = self.run_on(csv=csv)
        self.assertTrue(any("not upper case" in f for f in out), out)

    def test_an_upper_case_machine_is_silent(self):
        csv = HEAD + NL.join(["A8,2026a,alpha,1,1,15,2026-09-09", "MATTHIASPC,2026a,beta,1,1,15,2026-09-09", ""])
        self.assertEqual(self.run_on(csv=csv), [])

    def test_digits_and_punctuation_do_not_trip_the_fold(self):
        # the label is upper-cased, not alphabetic: A8 and BUILD_BOX.1 are
        # legal names and the rule must not reject them
        csv = HEAD + NL.join(["A8,2026a,alpha,1,1,15,2026-09-09", "BUILD_BOX.1,2026a,beta,1,1,15,2026-09-09", ""])
        self.assertEqual(self.run_on(csv=csv), [])


class TestShape(Base):
    def test_a_wrong_header_fires(self):
        csv = "machine,benchmark\nA8,alpha\n"
        f = self.run_on(csv=csv)
        self.assertTrue(any("header is" in x for x in f), f)

    def test_a_short_row_fires(self):
        csv = HEAD + "A8,2026a,alpha,1,1\n"
        f = self.run_on(csv=csv)
        self.assertTrue(any("5 fields" in x for x in f), f)

    def test_a_non_numeric_median_fires(self):
        csv = HEAD + "A8,2026a,alpha,fast,1,15,2026-09-09\n"
        f = self.run_on(csv=csv)
        self.assertTrue(any("not numbers" in x for x in f), f)

    def test_a_negative_median_fires(self):
        csv = HEAD + "A8,2026a,alpha,-1,1,15,2026-09-09\n"
        f = self.run_on(csv=csv)
        self.assertTrue(any("must be positive" in x for x in f), f)

    def test_min_above_median_fires(self):
        csv = HEAD + "A8,2026a,alpha,1.0,2.0,15,2026-09-09\n"
        f = self.run_on(csv=csv)
        self.assertTrue(any("exceeds median_s" in x for x in f), f)

    def test_a_bad_sample_count_fires(self):
        csv = HEAD + "A8,2026a,alpha,1,1,many,2026-09-09\n"
        f = self.run_on(csv=csv)
        self.assertTrue(any("positive integer" in x for x in f), f)

    def test_a_bad_date_fires(self):
        csv = HEAD + "A8,2026a,alpha,1,1,15,yesterday\n"
        f = self.run_on(csv=csv)
        self.assertTrue(any("ISO date" in x for x in f), f)

    def test_a_duplicate_baseline_fires(self):
        csv = HEAD + "A8,2026a,alpha,1,1,15,2026-09-09\n" \
                     "A8,2026a,alpha,2,2,15,2026-09-09\n"
        f = self.run_on(csv=csv)
        self.assertTrue(any("duplicate baseline" in x for x in f), f)

    def test_the_same_benchmark_on_two_machines_is_fine(self):
        csv = HEAD + "A8,2026a,alpha,1,1,15,2026-09-09\n" \
                     "ACC,2026a,alpha,2,2,15,2026-09-09\n" \
                     "A8,2026a,beta,1,1,15,2026-09-09\n"
        self.assertEqual(self.run_on(csv=csv), [])


class TestNames(Base):
    def test_an_orphan_baseline_fires(self):
        csv = ROWS + "A8,2026a,gamma,1,1,15,2026-09-09\n"
        f = self.run_on(csv=csv)
        self.assertTrue(any("no budgetCase" in x and "gamma" in x
                            for x in f), f)

    def test_a_field_that_does_not_match_its_value_fires(self):
        perf = PERF.replace("'alpha', 'alpha'", "'alpha', 'alfa'")
        f = self.run_on(perf=perf)
        self.assertTrue(any("must agree" in x for x in f), f)


class TestArms(Base):
    def test_a_case_without_an_arm_fires(self):
        perf = PERF.replace("            case 'beta'\n"
                            "                fcn = @() 2;\n", "")
        f = self.run_on(perf=perf)
        self.assertTrue(any("no case arm" in x and "beta" in x
                            for x in f), f)

    def test_an_arm_without_a_case_fires(self):
        perf = PERF.replace("            case 'beta'",
                            "            case 'beta'\n"
                            "                fcn = @() 3;\n"
                            "            case 'delta'")
        f = self.run_on(perf=perf)
        self.assertTrue(any("no budgetCase declares" in x and "delta" in x
                            for x in f), f)

    def test_a_cell_array_case_label_counts_for_every_label(self):
        # MATLAB: one arm can serve several labels. Reading only the
        # single-quoted form reported correct code as missing an arm
        # (v5.1.1); both labels must be seen.
        perf = PERF.replace("            case 'alpha'\n"
                            "                fcn = @() 1;\n"
                            "            case 'beta'\n"
                            "                fcn = @() 2;\n",
                            "            case {'alpha', ...\n"
                            "                    'beta'}\n"
                            "                fcn = @() 1;\n")
        self.assertEqual(self.run_on(perf=perf), [])

    def test_a_cell_label_that_names_an_undeclared_case_still_fires(self):
        perf = PERF.replace("            case 'beta'",
                            "            case {'beta', 'delta'}")
        f = self.run_on(perf=perf)
        self.assertTrue(any("no budgetCase declares" in x and "delta" in x
                            for x in f), f)

    def test_a_commented_out_arm_does_not_count(self):
        perf = PERF.replace("            case 'beta'",
                            "            % case 'beta'")
        f = self.run_on(perf=perf)
        self.assertTrue(any("no case arm" in x and "beta" in x
                            for x in f), f)


class TestBacklog(Base):
    def test_a_budget_with_no_baseline_anywhere_fires(self):
        csv = HEAD + "A8,2026a,alpha,1,1,15,2026-09-09\n"
        f = self.run_on(csv=csv)
        self.assertTrue(any("no baseline on any machine" in x and "beta" in x
                            for x in f), f)

    def test_the_backlog_exempts_exactly_that_budget(self):
        # the MECHANISM, asserted with a temporary entry rather than with a
        # member of the real list: draining the real one must not make this
        # test vacuous, which is how test_legacy_name_tolerated sat broken
        # for a release after v3.33.0 emptied LEGACY (A14).
        csv = HEAD + "A8,2026a,alpha,1,1,15,2026-09-09\n"
        self.assertEqual(self.run_on(csv=csv, backlog={"beta": "why"}), [])

    def test_a_stale_backlog_entry_fires(self):
        f = self.run_on(backlog={"gamma": "gone"})
        self.assertTrue(any("stale entry" in x for x in f), f)

    def test_a_backlog_entry_that_has_a_baseline_fires(self):
        f = self.run_on(backlog={"alpha": "still waiting"})
        self.assertTrue(any("already has a baseline" in x for x in f), f)


class TestMissing(Base):
    def test_a_missing_csv_fires(self):
        with tempfile.TemporaryDirectory() as tmp:
            os.makedirs(os.path.join(tmp, "tests"))
            with open(os.path.join(tmp, pba.PERF), "w") as fh:
                fh.write(PERF)
            f = pba.audit(tmp)[0]
        self.assertTrue(any("is missing" in x for x in f), f)

    def test_a_perf_file_without_the_parameter_fires(self):
        f = self.run_on(perf="classdef testPerformance\nend\n")
        self.assertTrue(any("no budgetCase" in x for x in f), f)


class TestRealTree(unittest.TestCase):
    def test_the_repository_is_clean(self):
        self.assertEqual(pba.audit(ROOT)[0], [])

    def test_the_gate_states_its_own_limit(self):
        doc = pba.__doc__
        self.assertIn("does NOT check that a baseline is CORRECT", doc)


if __name__ == "__main__":
    unittest.main(verbosity=2)
