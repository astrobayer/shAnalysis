#!/usr/bin/env python3
"""Name coverage of the public API by the MATLAB test suite (A10).

The audit found thirteen package functions that no test file mentions at
all. Some of them are certainly exercised indirectly - ts.destripe calls
shDestripe - but nothing measured it, so the set could only grow.

WHAT THIS MEASURES, AND WHAT IT DOES NOT
  It proves that some test file names the entity in EXECUTABLE code.
  Comments are stripped first, so a name in a "% see also foo" line does
  not count. That is the whole claim. It says nothing about whether the
  test asserts anything useful about the entity, and an entity reached
  only indirectly still counts as uncovered - which is the point: the
  indirect path is invisible here by design, because a rename or a
  regression in the callee is exactly what an indirect test misses.

  Operators are NOT exempt. plus/minus/times/mtimes/uminus/disp are all
  callable by name, so a test can name them and check that the operator
  syntax and the method call agree - which is a stronger test than
  either alone. There is therefore no operator allowlist.

Surface authority: tools/dev/api_data.py (guarded against drift by
doc_sync_audit's SURFACE check).

Run: python3 tools/dev/name_coverage.py [--list]
Nonzero exit if any public entity outside ALLOW is unnamed.

Developed by Matthias Weigelt with the help of Claude (Opus 5), 2026-09-08.
"""
import os
import re
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.environ.get("SHX_ROOT", os.path.dirname(os.path.dirname(_HERE)))
sys.path.insert(0, _HERE)

# Entities deliberately not named in any test, each with the reason it
# cannot be. Keep this empty unless there is no way to name the entity in
# executable test code; "it is hard to test" is not a reason to be here.
ALLOW = {
    "runAllTests": "the test runner itself - naming it inside the suite "
                   "it runs would recurse",
}


def code_only(text):
    """MATLAB source with comments removed.

    Line comments and trailing comments go; a name surviving this is
    named in code. Block comments (%{ %}) are handled too. The apostrophe
    is left alone: it is transpose as often as it is a string delimiter,
    and mis-parsing it would only ever hide a name, never invent one.
    """
    out, in_block = [], False
    for ln in text.splitlines():
        s = ln.strip()
        if s.startswith("%{"):
            in_block = True
            continue
        if s.startswith("%}"):
            in_block = False
            continue
        if in_block or s.startswith("%"):
            continue
        out.append(re.sub(r"%.*$", "", ln))
    return "\n".join(out)


def test_code(testdir=None):
    d = testdir or os.path.join(ROOT, "tests")
    parts = []
    for f in sorted(os.listdir(d)):
        if f.endswith(".m"):
            with open(os.path.join(d, f), encoding="utf-8",
                      errors="replace") as fh:
                parts.append(code_only(fh.read()))
    return "\n".join(parts)


def entities(api):
    """[(qualified name, bare name, kind)] over the whole public surface."""
    out = []
    for e in api["shLowLevel"]:
        out.append(("shLowLevel." + e["name"], e["name"], "package"))
    for e in api["root"]:
        out.append((e["name"], e["name"], "root"))
    for c in api["classes"]:
        for m in c["methods"]:
            out.append((c["name"] + "." + m["name"], m["name"], "method"))
    return out


def uncovered(api, code):
    """Entities whose bare name appears nowhere in the test code."""
    miss = []
    for qual, bare, kind in entities(api):
        if not re.search(r"\b" + re.escape(bare) + r"\b", code):
            miss.append((qual, bare, kind))
    return miss


def main(argv=None):
    argv = argv if argv is not None else sys.argv[1:]
    from api_data import API
    code = test_code()
    miss = uncovered(API, code)

    probs = [(q, b, k) for q, b, k in miss if q not in ALLOW and b not in ALLOW]
    allowed = [(q, b, k) for q, b, k in miss if q in ALLOW or b in ALLOW]

    if "--list" in argv:
        for q, b, k in probs:
            print("  %-40s %s" % (q, k))

    total = len(entities(API))
    if probs:
        by = {}
        for q, b, k in probs:
            by.setdefault(k, []).append(q)
        print("name_coverage: %d of %d public entities are never named in "
              "executable test code" % (len(probs), total), file=sys.stderr)
        for k in sorted(by):
            print("  %s (%d): %s" % (k, len(by[k]), ", ".join(sorted(by[k]))),
                  file=sys.stderr)
        print("  (run with --list for one per line)", file=sys.stderr)
        return 1

    print("name_coverage: 0 findings - all %d public entities are named in "
          "executable test code (%d allowed exception(s)). Naming is not "
          "exercise: this proves a test mentions the entity, not what it "
          "asserts." % (total, len(allowed)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
