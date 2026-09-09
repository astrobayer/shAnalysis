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
              "Error identifiers" help section. 61 files predate the
              convention and are listed in UNDOCUMENTED; that list only
              ever shrinks, and the gate reports its size every run.
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

# error('id', ...) / warning('id', ...) -> identifier is argument 1.
# assert(cond, 'id', ...)               -> identifier is argument 2.
# Continuations are folded first, so the id may sit on the next line.
RAISE = re.compile(
    r"\b(?:error|warning)\s*\(\s*['\"]([A-Za-z][\w]*(?::[\w]+)+)['\"]"
    r"|\bassert\s*\([^;]*?,\s*['\"]([A-Za-z][\w]*(?::[\w]+)+)['\"]")

# Both house styles: the id alone on its line with the reason indented
# below, and "id  reason" on one line. Requiring the first spelling
DOC_ID = re.compile(r"^%\s+(shLowLevel:[\w:]+)(?:\s|$)", re.M)
SECTION = "%   Error identifiers"

# Files that raise identifiers but predate the "Error identifiers" help
# section. A backlog, not an exemption: entries leave and never return.
UNDOCUMENTED = {
    "basinDeconvolve", "basinKernel", "basinScaling", "buildCondFun",
    "buildNoiseCov", "buildSignalCov", "combineCenters", "compareSeries",
    "designFilter", "diffSpectrum", "effectiveCorr", "eofAnalysis",
    "errorMap", "estimateDegree1", "estimateVAR", "evalMask", "fetchDDK",
    "fetchICGEM", "fetchITSG", "fetchLoveNumbers", "fetchTN",
    "fitDeterministicModel", "gravisDataFolder", "gravisL2B",
    "gravisRegionChain", "gridScaling", "kalmanChain", "kalmanFilter",
    "leakageCorrect", "listICGEM", "listITSG", "makeTutorials",
    "mcPropagate", "nashSutcliffe", "neqCombine", "oceanRMS",
    "plotCovariance", "plotSHCoeffTriangle", "plotSHSpectrum",
    "poleTideConvert", "readDDK", "readLoveNumbers", "readMascon",
    "readSINEX", "readTN13", "readTN14", "rtsSmoother",
    "sensitivityKernel", "shAnalysisGrid", "spatialStats",
    "standardChain", "synthesisPoints", "taylorDiagram",
    "threeCorneredHat", "tvANSFilter", "twsChain", "writeAnimation",
    "writeFrames", "writeGFC", "writeGrid", "ylm"
}


def fold(text):
    """Join MATLAB ... continuations so a raise can be read on one line."""
    return re.sub(r"\.\.\.[^\n]*\n\s*", " ", text)


def code_of(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        src = fh.read()
    body = "\n".join(l for l in src.splitlines()
                     if not l.lstrip().startswith("%"))
    return src, fold(body)


def raised_in(code):
    out = set()
    for m in RAISE.finditer(code):
        out.add(m.group(1) or m.group(2))
    return out


def documented_in(src):
    if SECTION not in src:
        return None                      # no section at all
    return set(DOC_ID.findall(src))


def main(argv=None):
    argv = argv if argv is not None else sys.argv[1:]
    probs, backlog, checked = [], [], 0
    for f in sorted(os.listdir(PKG)):
        if not f.endswith(".m"):
            continue
        stem = f[:-2]
        src, code = code_of(os.path.join(PKG, f))
        ids = raised_in(code)
        if not ids:
            continue
        checked += 1
        own = "shLowLevel:%s:" % stem
        for i in sorted(ids):
            if not i.startswith(own):
                probs.append("%s.m raises %s - it owns %s* only" % (stem, i, own))
        doc = documented_in(src)
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
            probs.append("%s.m documents %s but never raises it" % (stem, i))

    if "--list" in argv:
        for s in sorted(backlog):
            print("  backlog: %s.m" % s)
    if probs:
        print("error_id_audit: %d finding(s)" % len(probs), file=sys.stderr)
        for p in probs:
            print("  - " + p, file=sys.stderr)
        return 1
    print("error_id_audit: 0 findings - %d package files raise identifiers, "
          "every one owned by the file that raises it; %d document them, "
          "%d in the shrinking UNDOCUMENTED backlog."
          % (checked, checked - len(backlog), len(backlog)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
