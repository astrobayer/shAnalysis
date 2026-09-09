#!/usr/bin/env python3
"""option_values_audit: a documented option value must be accepted (A19).

`opApply`'s help offered mode values 'apply' | 'applyT' while its
arguments block accepted only 'forward' | 'transp'. A caller following
the row got a validation error. No gate saw it; it was found by hand
while writing an unrelated test.

WHY THIS READS api_data.py AND NOT THE SOURCE. The first attempt grepped
help comment lines for quoted words near an option name: 25 hits, 24 of
them false - output-field docs, prose, and the WRONG METHOD's options in
a class file. api_data.py already pairs each option with its own
`allowed` set (from mustBeMember) and its own `desc` (that option's help
row), so the scoping problem disappears.

THE RULE, and why it is narrow. Flagging every quoted word in a row
still gives 5 hits on a clean tree, all false: a row legitimately quotes
prose ("auto" (daily data ... selects "doy")) and other options' values
(with SignalMode='isotropic'). So the check looks only at the row's
LEADING ALTERNATIVES RUN - a pipe-separated list of quoted values, the
house way of writing "these are the choices" - and requires it to be a
subset of what mustBeMember accepts. A row with no such run is not
checked: it documents prose, not an enumeration.

That is enough to catch the defect that motivated this: opApply's row
WAS such a run, and none of its members was accepted.

Run: python3 tools/dev/option_values_audit.py [--list]
Nonzero exit on any finding.

Developed by Matthias Weigelt with the help of Claude (Opus 5), 2026-09-09.
"""
import os
import re
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _HERE)

# a quoted literal, single or double
LIT = r"""["']([^"']*)["']"""
# "'a' | 'b' | 'c'", tolerating a parenthetical between members:
#   'auto' (default) | 'on' | 'off'
RUN = re.compile(LIT + r"""(?:\s*(?:\([^)]*\))?\s*\|\s*""" + LIT + r""")+""")


def allowed_values(arg):
    """The mustBeMember set for one argument, or None when it has none."""
    al = arg.get("allowed")
    if not al:
        return None
    # numeric member lists ([60, 96]) carry no quoted values: not our business
    vals = re.findall(LIT, al)
    return set(vals) if vals else None


def documented_run(desc):
    """The leading pipe-separated run of quoted alternatives, or None."""
    if not desc:
        return None
    m = RUN.search(desc)
    if not m:
        return None
    # re-scan the matched span for every literal in it
    return set(re.findall(LIT, m.group(0)))


def entities(api):
    for e in api["shLowLevel"]:
        yield "shLowLevel." + e["name"], e
    for e in api["root"]:
        yield e["name"], e
    for c in api["classes"]:
        for m in c["methods"]:
            yield c["name"] + "." + m["name"], m


def audit(api):
    probs, checked = [], 0
    for qual, e in entities(api):
        for a in e.get("args", []):
            allowed = allowed_values(a)
            if allowed is None:
                continue
            run = documented_run(a.get("desc"))
            if run is None:
                continue
            checked += 1
            extra = sorted(run - allowed)
            if extra:
                probs.append(
                    "%s option %s: the help offers %s, but mustBeMember "
                    "accepts only %s"
                    % (qual, a["name"], ", ".join(repr(x) for x in extra),
                       ", ".join(sorted(repr(x) for x in allowed))))
    return probs, checked


def main(argv=None):
    argv = argv if argv is not None else sys.argv[1:]
    from api_data import API
    probs, checked = audit(API)
    if "--list" in argv:
        total = sum(1 for _, e in entities(API) for a in e.get("args", [])
                    if allowed_values(a) is not None)
        print("  %d options restrict values; %d document an alternatives run"
              % (total, checked))
    if probs:
        print("option_values_audit: %d finding(s)" % len(probs),
              file=sys.stderr)
        for p in probs:
            print("  - " + p, file=sys.stderr)
        return 1
    print("option_values_audit: 0 findings - %d documented alternatives "
          "runs, every member accepted by its own mustBeMember. Rows "
          "without such a run are prose and are not checked." % checked)
    return 0


if __name__ == "__main__":
    sys.exit(main())
