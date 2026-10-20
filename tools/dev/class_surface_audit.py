#!/usr/bin/env python3
"""class_surface_audit: can a class reach every numerical lane? (WP7)

Contents.m calls the three classes "the single point of access". This
gate measures that claim instead of restating it. It builds the call
graph from the SOURCE - the three class files, every public +shLowLevel
function and the package's private helpers, with comments and string
literals blanked by mlint_lite's scanner - and takes its transitive
closure from the classes. A public +shLowLevel function is REACHED when
some class method calls it, or calls something that does, at any depth.

Every public function must be reached, or be named in exactly one of
the two lists below:

  EXCEPTIONS  not a class operation by nature: a download, a catalogue,
              a reader of an INPUT, a plot or an export, a helper on
              latitudes, masks or paths - or one of the validated chains,
              which take a FOLDER and return a product (Matthias,
              2026-09-10). Each entry says why.
  BACKLOG     a numerical lane with no class route yet. It may only
              shrink: an entry that becomes reachable is a FINDING until
              it is deleted, so the list cannot go stale in the direction
              that looks safe (the NO_BASELINE lesson, CLAUDE.md 6.3).

DELEGATES pins each WP7 method that calls a lane directly to that lane:
the method must exist in its class and its code must call the lane.
Methods that delegate to another CLASS method (ts.write, ts.gradient,
g.basinAverage) are held by their bitwise tests instead.

WHAT THIS DOES NOT MEASURE
  Reaching a lane is not exposing all of it: a class may call a function
  with fixed options, or on one path only. Whether a delegate is THIN is
  not measured either - the bitwise method-equals-lane tests in
  testContract are what hold a delegate to having no numerics of its
  own. And the graph follows NAMES, not dispatch: a function called only
  through a handle or a string would look unreached. None is today; a
  class file that starts using feval or str2func is reported, because
  from then on this gate could be wrong in the unsafe direction.

Run: python3 tools/dev/class_surface_audit.py [--list]
Nonzero exit on any finding.

Developed by Matthias Weigelt with the help of Claude (Opus 5), 2026-09-10.
"""
import os
import re
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _HERE)
sys.path.insert(0, os.path.dirname(_HERE))
from mlint_lite import strip_tokens  # noqa: E402
from error_id_audit import parse_class  # noqa: E402

ROOT = os.environ.get("SHX_ROOT", os.path.dirname(os.path.dirname(_HERE)))
CLASS_FILES = ("shCoefficients.m", "shSeries.m", "shClimatology.m")

_DOWNLOAD = ("downloads files and returns their paths; there is no field "
             "for a class to be the subject of")
_CATALOGUE = "lists what a server offers; no field is involved"
_PLUMBING = ("the HTTP and file plumbing under the fetchers, which are "
             "exceptions themselves")
_PLOT = ("draws or renders; the class surface for pictures is g.map, and "
         "geoMap is the cartographic authority")
_EXPORT = ("exports a GRID - what toGrid returns - rather than a field of "
           "the classes")
_HELPER = ("a helper on latitudes, masks, paths or documentation, not an "
           "operation on a field")
_CHAIN = ("a validated chain: it takes a FOLDER and returns a product (a "
          "trend, basin tables, grids) in one call already, so a method "
          "would only rename it - kept off the classes by decision "
          "(Matthias, 2026-09-10)")

EXCEPTIONS = {
    "fetchGAX": _DOWNLOAD,
    "fetchICGEM": _DOWNLOAD,
    "fetchITSG": _DOWNLOAD,
    "fetchITSGBackground": _DOWNLOAD,
    "fetchITSGSINEX": _DOWNLOAD,
    "fetchLoveNumbers": _DOWNLOAD,
    "fetchTN": _DOWNLOAD,
    # readDDK NAMES fetchDDK in an error message; that is a string, not a
    # call - a reader that does not blank strings counts it (and did)
    "fetchDDK": _DOWNLOAD,
    "httpFetch": _PLUMBING,
    "httpRetryDelay": _PLUMBING,
    "safeMove": _PLUMBING,
    "listICGEM": _CATALOGUE,
    "listITSG": _CATALOGUE,
    "readLoveNumbers": ("reads the Love numbers that class methods take "
                        "as kn=/hn=, an input rather than a field"),
    "readMascon": ("reads a mascon GRID product, not spherical-harmonic "
                   "coefficients"),
    "readSHM": ("reads GravIS SHM files for the GravIS chains, which are "
                "exceptions themselves"),
    "readGrid": ("reads a GRID - the input of shCoefficients.analysis - "
                 "rather than a field of the classes"),
    "plotBasinSeries": _PLOT,
    "plotCovariance": _PLOT,
    "writeAnimation": _PLOT,
    "writeFrames": _PLOT,
    "writeGrid": _EXPORT,
    "geocentric2geodetic": _HELPER,
    "erodeMask": _HELPER,
    "gravisDataFolder": _HELPER,
    "makeTutorials": _HELPER,
    "standardChain": _CHAIN,
    "greenlandChain": _CHAIN,
    "antarcticaChain": _CHAIN,
    "gravisRegionChain": _CHAIN,
    "twsChain": _CHAIN,
    "oceanChain": _CHAIN,
    "obpChain": _CHAIN,
    "gravisL2B": _CHAIN,
}

# Numerical lanes with no class route YET, each with the route it would
# most naturally take. May only shrink (see the module docstring).
BACKLOG = {
    "basinKernel": "basin kernels B for basinAverage (a builder of its input)",
    "basinScaling": "leakage/attenuation scaling factors by forward modelling",
    "buildCondFun": "the CondFun= conditioner that ts.kalman forwards",
    "designFilter": "a DDK-class W from covariances, for applyDDK",
    "eofSeparate": "coherent modes out of a residual stack, beside ts.eof",
    "gridScaling": "per-pixel scaling factors from a model series",
    "hydroExtremeIndex": "flood and drought indices from a series",
    "mcPropagate": "Monte-Carlo propagation through a processing chain",
    "oceanRMS": "open-ocean RMS noise metric of a field",
    "resolutionMap": "filter-kernel half-widths of a filter operator",
    "seaLevelFingerprint": "elastic sea-level fingerprint of a load",
    "sensitivityKernel": "a basin kernel with a leakage/noise trade-off",
    "signalVarianceKaula": "Kaula signal variance, an input of the VDK filter",
}

DELEGATES = {
    ("shSeries", "kalman"): "kalmanChain",
    ("shSeries", "eof"): "eofAnalysis",
    ("shSeries", "leakageCorrect"): "leakageCorrect",
    ("shSeries", "leakageDataDriven"): "leakageDataDriven",
    ("shSeries", "excitation"): "rotationExcitation",
    ("shSeries", "bridgeGaps"): "bridgeGaps",
    ("shCoefficients", "poleTideConvert"): "poleTideConvert",
    ("shCoefficients", "slepianProject"): "slepianProject",
    ("shSeries", "poleTideConvert"): "poleTideConvert",
    ("shSeries", "estimateDegree1"): "estimateDegree1",
    ("shSeries", "combineCenters"): "combineCenters",
    ("shSeries", "slepianProject"): "slepianProject",
    ("shCoefficients", "errorMap"): "errorMap",
    ("shCoefficients", "synthesisPoints"): "synthesisPoints",
    ("shCoefficients", "gradientTensor"): "shSynthesisGradientTensor",
    ("shCoefficients", "vdkApply"): "vdkApply",
    ("shCoefficients", "regionalBasis"): "regionalBasis",
    ("shCoefficients", "regionalProject"): "regionalProject",
    ("shSeries", "regionalBasis"): "regionalBasis",
    ("shSeries", "regionalProject"): "regionalProject",
}


def _code(path):
    return strip_tokens(open(path, encoding="utf-8", errors="replace").read())


def graph(root=ROOT):
    """(public names, set reached from a class, {class: stripped source}).

    Package functions reach one another only as shLowLevel.<name> - MATLAB
    requires the prefix inside a package too - and reach a private helper
    by its bare name. A class cannot call a private helper of the package,
    so class files are read for the prefixed form only."""
    pkg = os.path.join(root, "+shLowLevel")
    priv = os.path.join(pkg, "private")
    pub = sorted(f[:-2] for f in os.listdir(pkg) if f.endswith(".m"))
    prv = (sorted(f[:-2] for f in os.listdir(priv) if f.endswith(".m"))
           if os.path.isdir(priv) else [])
    src = {("pub", n): _code(os.path.join(pkg, n + ".m")) for n in pub}
    src.update({("priv", n): _code(os.path.join(priv, n + ".m"))
                for n in prv})
    cls_src = {}
    for c in CLASS_FILES:
        p = os.path.join(root, c)
        if os.path.isfile(p):
            cls_src[c[:-2]] = src[("cls", c[:-2])] = _code(p)
    pubset = set(pub)

    def edges(key):
        s = src[key]
        out = {("pub", m) for m in re.findall(r"\bshLowLevel\.(\w+)", s)
               if m in pubset}
        if key[0] != "cls":
            for p in prv:
                if key != ("priv", p) and re.search(
                        r"(?<![\w.])" + re.escape(p) + r"\b", s):
                    out.add(("priv", p))
        return out

    seen, stack = set(), [k for k in src if k[0] == "cls"]
    while stack:
        for e in edges(stack.pop()):
            if e not in seen:
                seen.add(e)
                stack.append(e)
    return pub, {n for kind, n in seen if kind == "pub"}, cls_src


def check(root=ROOT, exceptions=None, backlog=None, delegates=None):
    exceptions = EXCEPTIONS if exceptions is None else exceptions
    backlog = BACKLOG if backlog is None else backlog
    delegates = DELEGATES if delegates is None else delegates
    pub, reached, cls_src = graph(root)
    pubset, probs = set(pub), []
    for n in sorted(set(exceptions) & set(backlog)):
        probs.append("%s is in both EXCEPTIONS and BACKLOG - it is one or "
                     "the other" % n)
    for label, lst in (("EXCEPTIONS", exceptions), ("BACKLOG", backlog)):
        for n in sorted(lst):
            if n not in pubset:
                probs.append("%s lists %s, which is not a public "
                             "+shLowLevel function - renamed or deleted?"
                             % (label, n))
            elif n in reached and label == "BACKLOG":
                probs.append("%s is reachable from a class now - delete it "
                             "from BACKLOG (the list may only shrink)" % n)
            elif n in reached:
                probs.append("%s is reachable from a class, so it is no "
                             "longer an exception - delete it from "
                             "EXCEPTIONS" % n)
    for n in pub:
        if n not in reached and n not in exceptions and n not in backlog:
            probs.append("shLowLevel.%s is reachable from no class and is in "
                         "neither EXCEPTIONS nor BACKLOG - give it a class "
                         "route, or say why it needs none" % n)
    for c, s in sorted(cls_src.items()):
        if re.search(r"\b(feval|str2func)\b", s):
            probs.append("%s.m dispatches through feval/str2func - the call "
                         "graph cannot see those calls, so this gate could "
                         "now pass a lane that nothing reaches" % c)
    for (cls, meth), lane in sorted(delegates.items()):
        path = os.path.join(root, cls + ".m")
        funs = parse_class(path) if os.path.isfile(path) else []
        fn = next((f for f in funs if f["name"] == meth), None)
        if fn is None:
            probs.append("DELEGATES: %s.%s does not exist" % (cls, meth))
            continue
        if lane not in pubset:
            probs.append("DELEGATES: %s.%s is pinned to shLowLevel.%s, which "
                         "does not exist" % (cls, meth, lane))
        elif not re.search(r"\bshLowLevel\.%s\s*\(" % re.escape(lane),
                           strip_tokens(fn["body"])):
            probs.append("DELEGATES: %s.%s does not call shLowLevel.%s"
                         % (cls, meth, lane))
    return probs, pub, reached


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    probs, pub, reached = check()
    if "--list" in argv:
        print("REACHED (%d): %s" % (len(reached), " ".join(sorted(reached))))
        print("EXCEPTIONS (%d): %s" % (len(EXCEPTIONS),
                                       " ".join(sorted(EXCEPTIONS))))
        print("BACKLOG (%d): %s" % (len(BACKLOG), " ".join(sorted(BACKLOG))))
    for p in probs:
        print("class_surface_audit: " + p)
    print("class_surface_audit: %d finding(s) - %d public +shLowLevel "
          "functions: %d reached from a class, %d deliberate exceptions, "
          "%d in the backlog; %d WP7 delegates pinned to their lanes. "
          "Reach is by name through the call graph; how much of a lane a "
          "class exposes, and whether a delegate is thin, are not measured "
          "here - the bitwise tests hold that."
          % (len(probs), len(pub), len(reached), len(EXCEPTIONS),
             len(BACKLOG), len(DELEGATES)))
    return 1 if probs else 0


if __name__ == "__main__":
    sys.exit(main())
