#!/usr/bin/env python3
"""Speed-budget bookkeeping for testPerformance (WP2 step 1).

A9 recorded that the toolbox has no speed budget: a 1.3x regression in
legendreALF, shSynthesis, shAnalysisGrid, applyDDK, leakageCorrect or the
Kalman step ships unnoticed. WP2 step 1 makes speed measurable first, and
this gate guards the bookkeeping that makes the measurement trustworthy.

WHAT THIS CHECKS, AND WHAT IT DOES NOT
  It reads tests/perf_baseline.csv and the budgetCase / workload pair in
  tests/testPerformance.m, and checks that the three agree:

    SHAPE    the CSV parses: the header is exactly the expected one, every
             row has 7 fields, median_s and min_s are positive, min_s does
             not exceed median_s, samples is a positive integer and
             measured is an ISO date. No duplicate (machine, benchmark),
             and every machine label is UPPER CASE - machineId() folds the
             label, so a mixed-case row could never match, and an unmatched
             row filters its budget instead of failing it (v5.2.0).
    NAMES    every benchmark in the CSV is a declared budgetCase, and every
             budgetCase field name equals its value - the value is what the
             test prints and looks up, the field name is what the test is
             CALLED, and a divergence would make the CSV key and the test
             name two different strings for one thing.
    ARMS     every declared budgetCase has a case arm in workload(). This
             is the rule that earns the gate its place: a case declared
             without an arm passes every static check in this repository
             and then fails on the runner with unknownCase, which costs a
             CI round a Tier-B session cannot see coming.
    BACKLOG  every budgetCase either has at least one CSV row or sits in
             NO_BASELINE, and NO_BASELINE holds nothing else: no stale
             entry, and no case that already HAS a baseline (that entry
             would silently exempt a live budget).

  It does NOT check that a baseline is CORRECT, or current, or measured on
  the machine it claims. A baseline is a measurement someone made; this
  gate only proves the books balance. It also says nothing about whether
  BudgetFactor is well chosen - see the comment on it in testPerformance.m.

Run: python3 tools/dev/perf_baseline_audit.py
Nonzero exit on any finding.

Developed by Matthias Weigelt with the help of Claude (Opus 5), 2026-09-09.
"""
import os
import re
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.environ.get("SHX_ROOT", os.path.dirname(os.path.dirname(_HERE)))

CSV = os.path.join("tests", "perf_baseline.csv")
PERF = os.path.join("tests", "testPerformance.m")

HEADER = "machine,matlab,benchmark,median_s,min_s,samples,measured"

# Budgets that have no baseline on any machine yet, each with the reason.
# This list may only SHRINK. An entry here means the budget FILTERS rather
# than asserts, so nothing is being guarded - it is debt, not a decision.
NO_BASELINE = {
    # Empty since v5.3.0: every budgetCase has a baseline on at least one
    # machine, so every one of them ASSERTS somewhere. The n50 pair left
    # here by v5.2.0 was in fact already measured - A8 timed it at b65f9a2
    # and the numbers sat unread in the job log.
    #
    # Draining it does not make its self-test vacuous:
    # test_perf_baseline_audit.py injects its own backlog rather than
    # looping over this dict, which is the lesson A14 paid for once.
    #
    # Note what an empty backlog does NOT promise. A budget asserts only on
    # a machine that HAS a row, and apply_ddk_n300 is baselined on
    # MATTHIASPC only, so on A8 it still filters until that runner measures
    # it. Empty means no budget is unguarded everywhere; it does not mean
    # every budget is guarded everywhere.
}

_DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def declared_cases(text):
    """Field->value pairs of the budgetCase TestParameter."""
    m = re.search(r"budgetCase\s*=\s*struct\((.*?)\);", text, re.S)
    if not m:
        return None
    body = re.sub(r"%[^\n]*", "", m.group(1))          # strip comments
    lits = re.findall(r"'([^']*)'", body)
    return list(zip(lits[0::2], lits[1::2]))


def workload_arms(text):
    """Case labels of the switch inside workload().

    MATLAB lets one arm serve several labels as a cell array,
    `case {'a', 'b'}`, and v5.1.1 uses one for the matched-pair budgets.
    Reading only `case 'x'` reported both of them as having no arm - a
    FALSE finding about correct code, and the same shape as A2's
    nv_casing_audit blind spot: an instrument is not evidence about a
    construct it cannot parse.
    """
    m = re.search(r"function\s+fcn\s*=\s*workload\(.*?\)(.*?)\n    function ",
                  text, re.S)
    if not m:
        return None
    body = re.sub(r"%[^\n]*", "", m.group(1))
    arms = set()
    for hit in re.finditer(r"\bcase\s+(\{.*?\}|'[^']*')", body, re.S):
        arms |= set(re.findall(r"'([^']*)'", hit.group(1)))
    return arms


def read_rows(path):
    """(rows, findings) - rows are dicts, findings are shape complaints."""
    bad = []
    with open(path, encoding="utf-8") as fh:
        lines = fh.read().splitlines()
    data = [(i + 1, ln) for i, ln in enumerate(lines)
            if ln.strip() and not ln.lstrip().startswith("#")]
    if not data:
        return [], ["%s: no header line" % CSV]
    hno, header = data[0]
    if header.strip() != HEADER:
        bad.append("%s:%d: header is %r, expected %r"
                   % (CSV, hno, header.strip(), HEADER))
        return [], bad
    rows = []
    for no, ln in data[1:]:
        cells = [c.strip() for c in ln.split(",")]
        if len(cells) != 7:
            bad.append("%s:%d: %d fields, expected 7" % (CSV, no, len(cells)))
            continue
        mach, rel, bench, med, mn, ns, when = cells
        try:
            med_f, mn_f = float(med), float(mn)
        except ValueError:
            bad.append("%s:%d: median_s/min_s are not numbers (%r, %r)"
                       % (CSV, no, med, mn))
            continue
        if med_f <= 0 or mn_f <= 0:
            bad.append("%s:%d: median_s and min_s must be positive "
                       "(%g, %g)" % (CSV, no, med_f, mn_f))
        if mn_f > med_f:
            bad.append("%s:%d: min_s %g exceeds median_s %g"
                       % (CSV, no, mn_f, med_f))
        if not ns.isdigit() or int(ns) < 1:
            bad.append("%s:%d: samples %r is not a positive integer"
                       % (CSV, no, ns))
        if not _DATE.match(when):
            bad.append("%s:%d: measured %r is not an ISO date" % (CSV, no, when))
        rows.append({"line": no, "machine": mach, "matlab": rel,
                     "benchmark": bench, "median_s": med_f, "min_s": mn_f})
    return rows, bad


def audit(root):
    findings = []
    csv_path = os.path.join(root, CSV)
    perf_path = os.path.join(root, PERF)
    if not os.path.isfile(csv_path):
        return ["%s is missing" % CSV], 0
    if not os.path.isfile(perf_path):
        return ["%s is missing" % PERF], 0

    with open(perf_path, encoding="utf-8") as fh:
        perf = fh.read()

    pairs = declared_cases(perf)
    if pairs is None:
        return ["%s: no budgetCase TestParameter found" % PERF], 0
    cases = [v for _, v in pairs]
    for name, value in pairs:
        if name != value:
            findings.append(
                "%s: budgetCase field %r carries value %r - the field names "
                "the test, the value names the CSV row; they must agree"
                % (PERF, name, value))

    arms = workload_arms(perf)
    if arms is None:
        findings.append("%s: no workload() switch found" % PERF)
        arms = set()
    for c in cases:
        if c not in arms:
            findings.append("%s: budgetCase %r has no case arm in workload() "
                            "- it would fail on the runner, not here" % (PERF, c))
    for a in sorted(arms - set(cases)):
        findings.append("%s: workload() has an arm %r that no budgetCase "
                        "declares" % (PERF, a))

    rows, bad = read_rows(csv_path)
    findings.extend(bad)

    seen = {}
    for r in rows:
        key = (r["machine"], r["benchmark"])
        if key in seen:
            findings.append("%s:%d: duplicate baseline for machine %r, "
                            "benchmark %r (first at line %d)"
                            % (CSV, r["line"], key[0], key[1], seen[key]))
        seen[key] = r["line"]
        if r["benchmark"] not in cases:
            findings.append("%s:%d: baseline for %r, which no budgetCase "
                            "declares" % (CSV, r["line"], r["benchmark"]))
        if r["machine"] != r["machine"].upper():
            findings.append(
                "%s:%d: machine %r is not upper case. testPerformance's "
                "machineId() upper-cases the label, so this row can never "
                "match - and a row that never matches does not fail its "
                "budget, it FILTERS it, which is silent"
                % (CSV, r["line"], r["machine"]))

    have = {r["benchmark"] for r in rows}
    for c in cases:
        if c not in have and c not in NO_BASELINE:
            findings.append("%s: budget %r has no baseline on any machine and "
                            "is not in NO_BASELINE - it would filter silently"
                            % (CSV, c))
    for c in sorted(NO_BASELINE):
        if c not in cases:
            findings.append("NO_BASELINE names %r, which no budgetCase "
                            "declares - stale entry" % c)
        elif c in have:
            findings.append("NO_BASELINE names %r, which already has a "
                            "baseline - remove it or the budget stays exempt"
                            % c)
    return findings, len(cases)


def main():
    findings, ncase = audit(ROOT)
    if findings:
        print("perf_baseline_audit: %d finding(s)" % len(findings),
              file=sys.stderr)
        for f in findings:
            print("  " + f, file=sys.stderr)
        return 1
    print("perf_baseline_audit: 0 findings - %d speed budgets declared, "
          "%d still without any baseline. This checks that the books "
          "balance, not that a baseline is correct or current."
          % (ncase, len(NO_BASELINE)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
