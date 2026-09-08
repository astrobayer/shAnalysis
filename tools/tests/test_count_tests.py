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

    def test_unparameterised_runs_equal_methods(self):
        c = self.count("testThing.m", SCRIPT_SUITE)
        self.assertEqual(c["runs"], c["methods"])


class TestRepository(unittest.TestCase):
    def test_this_repository_counts(self):
        tests = os.path.join(ROOT, "tests")
        total = sum(ct.count_file(os.path.join(tests, f))["runs"]
                    for f in os.listdir(tests)
                    if f.startswith("test") and f.endswith(".m"))
        # the number the self-hosted runner is expected to execute; bump
        # it in the same commit as any test added or removed
        self.assertEqual(total, 269)

    def test_mismatch_is_a_finding(self):
        self.assertEqual(ct.main(["--executed", "1"]), 1)

    def test_match_is_not(self):
        self.assertEqual(ct.main(["--executed", "269"]), 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
