#!/usr/bin/env python3
"""error_id_audit: every error identifier is owned and documented (v1.0.0).

A3/A15 were the finding: 17 raise sites in +shLowLevel used identifiers
belonging to another function - `kernelFactors` raised `shSynthesis:*`,
`writeFrames` raised `shLowLevel:writeAnimation:*` alongside its own
`shLowLevel:writeFrames:badSize`. A caller cannot catch by owner when the
owner is fiction, and `tvANSFilter` does exactly that catch:

    if strcmp(ME.identifier, 'shLowLevel:buildNoiseCov:notBlockDiagonal')

Three checks:

  OWNERSHIP   +shLowLevel/X.m raises only shLowLevel:X:<reason>.
              No backlog: the v4.0.0 sweep made this true everywhere, so
              a new violation is a new defect, not inherited debt.
  DOCUMENTED  every raised identifier appears in that file's
              "Error identifiers" help section. 61 files predated the
              convention and sat in UNDOCUMENTED, a list that only ever
              shrinks; A20 drained it in v4.0.2, so this rule now holds
              with no exemption at all.
  GHOSTS      every identifier the help documents is actually raised.
              A12's lesson: documentation drifts in BOTH directions.

WHAT COUNTS AS A RAISE. Only the identifier argument of error(), assert()
and warning(). A first pass that matched any quoted identifier reported
five violations of which FOUR were false: `tvANSFilter` COMPARES against
another function's id (the catch above), and `fetchITSGSINEX` passes
"shLowLevel:fetchITSGSINEX" as a PREFIX to a helper that appends the
reason. Neither raises anything. Read a checker's output against the
source before believing it.

Run: python3 tools/error_id_audit.py [--list]
Nonzero exit on any finding.

Developed by Matthias Weigelt with the help of Claude (Opus 5), 2026-09-09.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PKG = os.path.join(ROOT, "+shLowLevel")
# A class raises per-METHOD identifiers, so the file-level owner rule
# this gate applies does not fit them. Named, not forgotten: A21.
CLASS_FILES = {"shCoefficients.m", "shSeries.m", "shClimatology.m"}

# error('id', ...) / warning('id', ...) -> identifier is argument 1.
# assert(cond, 'id', ...)               -> identifier is argument 2.
# Continuations are folded first, so the id may sit on the next line.
RAISE = re.compile(
    r"\b(?:error|warning)\s*\(\s*['\"]([A-Za-z][\w]*(?::[\w]+)+)['\"](\s*\+)?"
    r"|\bassert\s*\([^;]*?,\s*['\"]([A-Za-z][\w]*(?::[\w]+)+)['\"](\s*\+)?")

# An identifier BUILT at runtime. setup_shAnalysis raises
#     warning("shAnalysis:setup:no" + locs(li, 1), ...)
# for five option names, so no scan of that file can name what it raises.
# Reading the literal as if it were the identifier is worse than useless:
# it invents `shAnalysis:setup:no`, which nothing ever raises. Such a
# literal is treated as a PREFIX - the help must document at least one
# identifier under it, and says so, since the gate cannot enumerate them.

# Both house styles: the id alone on its line with the reason indented
# below, and "id  reason" on one line. Requiring the first spelling
DOC_ID = re.compile(r"^%\s+((?:shLowLevel|shAnalysis):[\w:]+)(?:\s|$)", re.M)
SECTION = "%   Error identifiers"

# Files that raise identifiers but predate the "Error identifiers" help
# section. DRAINED in v4.0.2 (A20): all 61 files, 208 identifiers, were
# documented against their raise sites. The set stays as the mechanism -
# a new file may earn a temporary entry with a dated reason - but it is
# empty, so the DOCUMENTED rule now holds with no exemption. An empty
# backlog is exactly how A14's LEGACY test rotted into a no-op, so the
# self-test asserts the mechanism with a TEMPORARY entry rather than
# pinning a member name.
UNDOCUMENTED = set()


def fold(text):
    """Join MATLAB ... continuations so a raise can be read on one line."""
    return re.sub(r"\.\.\.[^\n]*\n\s*", " ", text)


def surface():
    """(path, stem, owner prefix) of every file this gate reads.

    +shLowLevel/X.m owns shLowLevel:X:*. A root function owns
    shAnalysis:<tag>:* where <tag> is its name without the toolbox
    suffix - setup_shAnalysis -> shAnalysis:setup:*, demo_shAnalysis ->
    shAnalysis:demo:*. The three class files are deliberately absent:
    their identifiers are per-METHOD, so the file-level owner rule does
    not apply to them (A21).
    """
    out = []
    for f in sorted(os.listdir(PKG)):
        if f.endswith(".m"):
            out.append((os.path.join(PKG, f), f[:-2],
                        "shLowLevel:%s:" % f[:-2]))
    for f in sorted(os.listdir(ROOT)):
        if not f.endswith(".m") or f in CLASS_FILES or f == "Contents.m":
            continue
        tag = f[:-2].replace("_shAnalysis", "")
        out.append((os.path.join(ROOT, f), f[:-2], "shAnalysis:%s:" % tag))
    return out


def code_of(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        src = fh.read()
    body = "\n".join(l for l in src.splitlines()
                     if not l.lstrip().startswith("%"))
    return src, fold(body)


def raised_in(code):
    """-> (literal identifiers, prefixes of runtime-built identifiers)"""
    ids, prefixes = set(), set()
    for m in RAISE.finditer(code):
        ident = m.group(1) or m.group(3)
        built = m.group(2) or m.group(4)
        (prefixes if built else ids).add(ident)
    return ids, prefixes


def documented_in(src):
    if SECTION not in src:
        return None                      # no section at all
    return set(DOC_ID.findall(src))


def main(argv=None):
    argv = argv if argv is not None else sys.argv[1:]
    probs, backlog, checked = [], [], 0
    for path, stem, own in surface():
        src, code = code_of(path)
        ids, prefixes = raised_in(code)
        if not ids and not prefixes:
            continue
        checked += 1
        for i in sorted(ids | prefixes):
            if not i.startswith(own):
                probs.append("%s.m raises %s - it owns %s* only" % (stem, i, own))
        doc = documented_in(src)
        for i in sorted(ids & prefixes):
            probs.append("%s.m raises %s both as a whole identifier and as a "
                         "prefix - one of the two is a typo" % (stem, i))
        if doc is None:
            if stem in UNDOCUMENTED:
                backlog.append(stem)
            else:
                probs.append("%s.m raises %d identifier(s) and has no "
                             "'Error identifiers' help section"
                             % (stem, len(ids)))
            continue
        if stem in UNDOCUMENTED:
            probs.append("%s.m now documents its identifiers - remove it "
                         "from UNDOCUMENTED (the backlog only shrinks)" % stem)
        for i in sorted(ids - doc):
            probs.append("%s.m raises %s but its help does not document it"
                         % (stem, i))
        for i in sorted(doc - ids):
            # a documented id under a runtime-built prefix is exactly what
            # that prefix asks for; it cannot be matched to a raise site
            if not any(i.startswith(pre) for pre in prefixes):
                probs.append("%s.m documents %s but never raises it"
                             % (stem, i))
        for pre in sorted(prefixes):
            if not any(i.startswith(pre) and i != pre for i in doc):
                probs.append("%s.m builds identifiers as \"%s\" + <name> and "
                             "documents none of them - the gate cannot "
                             "enumerate them, so the help must" % (stem, pre))

    if "--list" in argv:
        for s in sorted(backlog):
            print("  backlog: %s.m" % s)
    if probs:
        print("error_id_audit: %d finding(s)" % len(probs), file=sys.stderr)
        for p in probs:
            print("  - " + p, file=sys.stderr)
        return 1
    tail = ("no backlog left (A20 drained it in v4.0.2)" if not backlog
            else "%d in the shrinking UNDOCUMENTED backlog" % len(backlog))
    print("error_id_audit: 0 findings - %d files raise identifiers, every one "
          "owned by the file that raises it; %d document them, %s. Reach: "
          "+shLowLevel and the root functions. The three CLASS files are NOT "
          "read - see CLAUDE.md A21."
          % (checked, checked - len(backlog), tail))
    return 0


if __name__ == "__main__":
    sys.exit(main())
