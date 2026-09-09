#!/usr/bin/env python3
"""nv_casing_audit: keep Name-Value argument names consistent (v1.0.0).

Measured against MATLAB R2026a on 2026-09-05, not assumed:

  nvProbe(Nmax=96)      ACCEPTED    exact match
  nvProbe(nmax=96)      ACCEPTED    matching is CASE-INSENSITIVE
  nvProbe('Nma',96)     ACCEPTED    and PARTIAL
  with Nmax + NmaxOut:
  nvProbe('Nma',96)     REJECTED    MATLAB:functionValidation:AmbiguousInputName
  options.Nmax AND options.nmax in one block:  compiles and runs

Three consequences shape this gate.

First, renaming the CASE of a declared name is not API-breaking:
callers keep working, because matching ignores case. So the backlog
below can be worked off without a major release.

Second, and the reason this gate exists: two names differing only by
case in ONE arguments block compile and run. MATLAB issues no warning.
One of them is then unreachable by any caller. A casing sweep is
exactly the operation that can create such a pair, so the check has to
be in place BEFORE the sweep, not after.

Third, partial matching means a name that is a prefix of a sibling
makes every abbreviation of it ambiguous at call time. Seventeen such
pairs already exist; they are harmless while callers spell names in
full, and they are frozen in PREFIX_BASELINE so the gate reports only
NEW ones.

LEGACY is a backlog, not an exemption. Every entry is either renamed to
PascalCase or promoted to SYMBOLS with a reason. The list only ever
shrinks; a name removed from it can never come back, because the gate
then rejects it.

A fourth consequence, learned from A2: this gate reads ARGUMENTS BLOCKS,
so for six v1-era functions it had nothing to look at. They parsed with
inputParser, whose names it cannot see and which is itself
case-insensitive, so lowercase 'quantity' and 'nmin' survived the
v3.33.0 sweep unnoticed. v4.0.0 converted all six; INPUTPARSER now
rejects the construct outright, because a function that reappears with
one is invisible to every other check here.

Developed by Matthias Weigelt with the help of Claude (Sonnet 5),
2026-09-05.
"""
import os
import re
import sys
import collections

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKIP_DIRS = {".git", "html", "docs", "test_data"}

ARGS_BLOCK = re.compile(r"^([ \t]*)arguments\b(.*?)^\1end\b", re.M | re.S)
NV_DECL = re.compile(r"^\s*(?:options|opts|nv)\.([A-Za-z]\w*)", re.M)

# Domain notation that is deliberately not PascalCase, with the reason.
# Empty until the convention is settled: promoting a name here is a
# decision and must read as one in the diff.
SYMBOLS = {
    # Love numbers: Hn, Kn, Ln would be unreadable to the domain
    "hn": "load Love number h'_n",
    "kn": "load Love number k'_n",
    "ln": "load Love number l'_n",
    # ellipsoid and density symbols. GM and R are already uppercase
    # because that is how the constants themselves are written
    "a": "semi-major axis",
    "f": "flattening",
    "omega": "Earth rotation rate",
    "rho_ave": "mean Earth density; the underscore belongs to the symbol",
    "rho_water": "water density; the underscore belongs to the symbol",
    # coordinates, universally lowercase in geodesy
    "lat": "geocentric latitude",
    "lon": "longitude",
}

# Emptied on 2026-09-05: every entry was renamed to UpperCamelCase or
# promoted to SYMBOLS above. The mechanism stays for the next migration,
# but the list must always return to empty.
LEGACY = set()

# Prefix pairs present on 2026-09-05. Frozen: harmless in themselves,
# but a new one is a fresh way for a caller's abbreviation to break.
PREFIX_BASELINE = {
    ("DDK", "DDKFolder"),
    ("Degree1", "Degree1File"),
    ("GIA", "GIAEpoch"),
    ("QC", "QCAlpha"),
    ("R", "Regions"),
    ("R", "ResidualRegion"),
    ("R", "rho_ave"),
    ("R", "rho_water"),
    ("Sidecar", "SidecarExtra"),
    ("TN14", "TN14File"),
    ("Tol", "Tolerance"),
    ("lat", "LatType"),
}


def is_pascal(name):
    """True when the name starts uppercase and has no underscore.

    Inputs
      name  (str)

    Outputs
      (bool)
    """
    return bool(name) and name[0].isupper() and "_" not in name


def blocks_in(text):
    """Every arguments block's NV names.

    Inputs
      text  (str)  MATLAB source

    Outputs
      (list of (int, list of str))  1-based start line and declared
                                    Name-Value names, in file order
    """
    out = []
    for m in ARGS_BLOCK.finditer(text):
        names = NV_DECL.findall(m.group(2))
        if names:
            out.append((text[:m.start()].count("\n") + 1, names))
    return out


def audit_block(rel, line, names):
    """Findings for one arguments block.

    Inputs
      rel    (str)          repo-relative path
      line   (int)          1-based line of the arguments keyword
      names  (list of str)  declared Name-Value names

    Outputs
      (list of str)  findings; empty when the block is clean
    """
    findings = []

    by_lower = collections.defaultdict(list)
    for n in names:
        by_lower[n.lower()].append(n)
    for variants in by_lower.values():
        uniq = sorted(set(variants))
        if len(uniq) > 1:
            findings.append(
                f"{rel}:{line}: {uniq} differ only by case in one "
                f"arguments block. MATLAB compiles this and matches "
                f"case-insensitively, so one of them is unreachable.")

    for n in sorted(set(names)):
        if is_pascal(n) or n in SYMBOLS or n in LEGACY:
            continue
        findings.append(
            f"{rel}:{line}: Name-Value '{n}' is not PascalCase. Rename "
            f"it, or add it to SYMBOLS with a reason if it is domain "
            f"notation.")

    uniq = sorted(set(names))
    for a in uniq:
        for b in uniq:
            if a == b or not b.lower().startswith(a.lower()):
                continue
            if (a, b) in PREFIX_BASELINE:
                continue
            findings.append(
                f"{rel}:{line}: '{a}' is a prefix of '{b}', so any "
                f"abbreviation of '{a}' now raises "
                f"AmbiguousInputName. Rename one of them.")
    return findings


def walk(root):
    """Yield (relative path, source) for every MATLAB file in scope."""
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fn in sorted(filenames):
            if not fn.endswith(".m"):
                continue
            full = os.path.join(dirpath, fn)
            rel = os.path.relpath(full, root).replace(os.sep, "/")
            with open(full, encoding="utf-8", errors="replace") as fh:
                yield rel, fh.read()


PARSER_USE = re.compile(r"\binputParser\s*[;(]|\badd(?:Parameter|Optional"
                        r"|Required)\s*\(|\bp\.Results\.")


def main():
    findings, declared = [], set()
    for rel, src in walk(ROOT):
        for line, names in blocks_in(src):
            declared.update(names)
            findings.extend(audit_block(rel, line, names))
        # INPUTPARSER: the construct this gate cannot inspect (A2).
        # Scan the real lines, skipping comments, so the reported line
        # number points at the file and not at a stripped copy of it.
        hit = next((i for i, l in enumerate(src.splitlines(), 1)
                    if not l.lstrip().startswith("%")
                    and PARSER_USE.search(l)), None)
        if hit:
            findings.append(
                f"{rel}:{hit}: parses with "
                f"inputParser. Its Name-Value names are invisible to this "
                f"gate and match case-insensitively, which is how six "
                f"functions kept lowercase options through v3.33.0's sweep. "
                f"Use an arguments block.")

    # a backlog entry that no longer exists is stale bookkeeping: it
    # would silently re-permit the name if it ever came back
    for name in sorted(LEGACY - declared):
        findings.append(
            f"LEGACY lists '{name}', which is no longer declared "
            f"anywhere. Remove it - the backlog must only shrink.")

    if findings:
        for f in findings:
            print(f)
        print(f"nv_casing_audit: {len(findings)} finding(s)")
        return 1
    print(f"nv_casing_audit: 0 findings - {len(declared)} Name-Value "
          f"names, {len(LEGACY)} awaiting the casing decision")
    return 0


if __name__ == "__main__":
    sys.exit(main())
