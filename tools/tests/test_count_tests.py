#!/usr/bin/env python3
"""Unit tests for tools/dev/count_tests.py.

The tool exists because two hand counts were wrong the same way. These
tests pin the three things the grep got wrong: the script-based entry
point is not a test, bench* methods are, and a parameterised method runs
once per parameter value.

Run: python3 tools/tests/test_count_tests.py

Developed by Matthias Weigelt with the help of Claude (Opus 5), 2026-09-08.
"""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__))), "dev"))
import count_tests as ct  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__))))

SCRIPT_SUITE = """\
function tests = testThing
tests = functiontests(localfunctions);
end

function testOne(tc)
end

function testTwo(tc)
end
"""

CLASS_SUITE = """\
classdef testPerf < matlab.unittest.TestCase
properties (TestParameter)
    nmaxP = struct('n60', 60, 'n120', 120);
end
methods (Test)
    function benchThing(tc, nmaxP)
    end
    function testPlain(tc)
    end
end
end
"""


class TestCounting(unittest.TestCase):
    def count(self, name, src):
        d = tempfile.mkdtemp()
        p = os.path.join(d, name)
        with open(p, "w", encoding="utf-8") as fh:
            fh.write(src)
        return ct.count_file(p)

    def test_entry_point_is_not_a_test(self):
        c = self.count("testThing.m", SCRIPT_SUITE)
        self.assertEqual(c["methods"], 2)
        self.assertTrue(c["entry"])

    def test_bench_methods_count(self):
        c = self.count("testPerf.m", CLASS_SUITE)
        self.assertEqual(c["methods"], 2)

    def test_parameterised_method_runs_once_per_value(self):
        c = self.count("testPerf.m", CLASS_SUITE)
        self.assertEqual(c["params"], {"nmaxP": 2})
        self.assertEqual(c["runs"], 3)      # benchThing x2 + testPlain

    def test_a_char_valued_parameter_counts_its_fields_not_its_literals(self):
        """The v5.0.2 regression: values that are char vectors.

        The old rule counted every quoted word followed by a comma, so a
        parameter whose VALUES are also quoted counted roughly twice.
        testPerformance's budgetCase read 19 where the runner runs 10 -
        which --executed would have caught only on the runner, a full CI
        round later (A16 again).
        """
        src = CLASS_SUITE.replace(
            "    nmaxP = struct('n60', 60, 'n120', 120);",
            "    nmaxP = struct('n60', 60, 'n120', 120);\n"
            "    caseP = struct( ...\n"
            "        'alpha', 'alpha', ...\n"
            "        'beta',  'beta', ...\n"
            "        'gamma', 'gamma');").replace(
            "    function testPlain(tc)",
            "    function testCase(tc, caseP)\n    end\n"
            "    function testPlain(tc)")
        c = self.count("testPerf.m", src)
        self.assertEqual(c["params"]["caseP"], 3)
        self.assertEqual(c["params"]["nmaxP"], 2)
        self.assertEqual(c["runs"], 2 + 3 + 1)

    def test_a_nested_call_in_a_value_is_not_a_field(self):
        # struct('a', string(datetime('now','Format','x')), 'b', 2) is two
        # fields; the shared splitter skips anything below depth 0
        src = CLASS_SUITE.replace(
            "    nmaxP = struct('n60', 60, 'n120', 120);",
            "    nmaxP = struct('n60', func('x', 'y'), 'n120', 120);")
        c = self.count("testPerf.m", src)
        self.assertEqual(c["params"]["nmaxP"], 2)

    def test_unparameterised_runs_equal_methods(self):
        c = self.count("testThing.m", SCRIPT_SUITE)
        self.assertEqual(c["runs"], c["methods"])


EXPECTED_RUNS = 431          # v5.23.0: 430 + the A36 retry-forwarding contract test
                             # (5 correctness, 4 contract, 2 robustness)



class TestRepository(unittest.TestCase):
    def test_this_repository_counts(self):
        """The tripwire: bump EXPECTED_RUNS with any test added or removed.

        It is deliberately an absolute number - the whole point of A16 is
        that the prediction is checked against what the runner executed.
        """
        tests = os.path.join(ROOT, "tests")
        total = sum(ct.count_file(os.path.join(tests, f))["runs"]
                    for f in os.listdir(tests)
                    if f.startswith("test") and f.endswith(".m"))
        self.assertEqual(total, EXPECTED_RUNS)

    def test_mismatch_is_a_finding(self):
        self.assertEqual(ct.main(["--executed", "1"]), 1)

    def test_match_is_not(self):
        # one authority for the number, even inside this file
        self.assertEqual(ct.main(["--executed", str(EXPECTED_RUNS)]), 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
