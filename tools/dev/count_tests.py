#!/usr/bin/env python3
"""count_tests: the declared test count, per class and in total.

The prediction that is checked against a runAllTests run. It exists because
counting by hand got it wrong twice in the same way:

  grep -c '^function test' tests/*.m

counts the script-based harness entry point (`function tests =
testCorrectness`) as a test, and misses every method that does not begin
with 'test' - testPerformance's nine `bench*` rows - and every parameterised
expansion. That grep said 261; the runner ran 268.

Reported per class:
  methods    declared test methods (test* and bench*), entry point excluded
  runs       methods after TestParameter expansion (classdef suites)

Usage:
  python3 tools/dev/count_tests.py [tests_dir]
  python3 tools/dev/count_tests.py --executed 268   # errors on a mismatch

Developed by Matthias Weigelt with the help of Claude (Opus 5), 2026-09-08.
"""
import os
import re
import sys

METHOD = re.compile(r"^\s*function\s+(?:\[[^\]]*\]\s*=\s*)?(test|bench)\w*\s*"
                    r"\(([^)]*)\)", re.M)
ENTRY = re.compile(r"^function\s+tests\s*=\s*\w+", re.M)
PARAM_BLOCK = re.compile(r"properties\s*\(\s*TestParameter\s*\)(.*?)^end",
                         re.M | re.S)
PARAM_DEF = re.compile(r"^\s*(\w+)\s*=\s*struct\((.*?)\);", re.M | re.S)


def parameters(src):
    """{name: cardinality} from a properties (TestParameter) block"""
    out = {}
    for blk in PARAM_BLOCK.findall(src):
        for name, body in PARAM_DEF.findall(blk):
            out[name] = len(re.findall(r"['\"]\w+['\"]\s*,", body))
    return out


def count_file(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        src = fh.read()
    params = parameters(src)
    methods, runs = 0, 0
    for m in METHOD.finditer(src):
        methods += 1
        n = 1
        for arg in (a.strip() for a in m.group(2).split(",")):
            if arg in params:
                n *= max(params[arg], 1)
        runs += n
    return {"methods": methods, "runs": runs,
            "entry": bool(ENTRY.search(src)), "params": params}


def main(argv):
    executed = None
    args = []
    it = iter(argv)
    for a in it:
        if a == "--executed":
            executed = int(next(it))
        else:
            args.append(a)
    here = os.path.dirname(os.path.abspath(__file__))          # tools/dev
    root = os.path.dirname(os.path.dirname(here))               # repo root
    tests = args[0] if args else os.path.join(root, "tests")
    files = sorted(f for f in os.listdir(tests)
                   if f.startswith("test") and f.endswith(".m"))
    if not files:
        print("count_tests: no test files in %s" % tests)
        return 1
    total_m = total_r = 0
    print("%-24s %8s %8s  %s" % ("class", "methods", "runs", "notes"))
    for f in files:
        c = count_file(os.path.join(tests, f))
        total_m += c["methods"]
        total_r += c["runs"]
        note = []
        if c["params"]:
            note.append("parameterised: " + ", ".join(
                "%s x%d" % (k, v) for k, v in sorted(c["params"].items())))
        if c["entry"]:
            note.append("script-based (entry point not counted)")
        print("%-24s %8d %8d  %s" % (f[:-2], c["methods"], c["runs"],
                                     "; ".join(note)))
    print("%-24s %8d %8d" % ("TOTAL", total_m, total_r))
    if executed is not None and executed != total_r:
        print("count_tests: FINDING - predicted %d runs, %d executed"
              % (total_r, executed))
        return 1
    if executed is not None:
        print("count_tests: prediction matches the run (%d)" % executed)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
