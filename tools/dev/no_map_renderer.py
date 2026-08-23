#!/usr/bin/env python3
"""no_map_renderer: keep the cartographic renderer gone.

D-2026-08-23: geoMap is the single cartographic authority. This toolbox
had a second renderer - shLowLevel.plotSHMap, its own coastlines, its own
colour limits, two projections beside sixteen certified ones - and no
instrument compared the two. Deleting it is a one-line commit; keeping it
deleted is this file. A rule enforced by review erodes.

WHAT IT FORBIDS, and only this: drawing a MAP. Coastline data, projection
formulae, and raster/patch primitives in a file whose job is geography.
It does NOT forbid plotting - a degree-RMS spectrum, a coefficient
triangle, a basin time series and a covariance image are not maps, they
have no second implementation anywhere, and geoMap does not want them.

WHAT IT DELIBERATELY DOES NOT FLAG. errorMap and resolutionMap sound
like renderers and are not: they contain zero graphics calls and return
arrays. The handover that prompted this decision counted 693 lines of
"plotting-ish files" by NAME; measured by behaviour the renderer was 114
lines in one file. That is why this gate reads the code.

LIMITATION, stated rather than discovered: comments are stripped so a help
text may NAME what the code must not do, but string literals are not -
MATLAB's transpose operator makes that unsafe to parse crudely. Shipped
code that PRINTS the word "coastline" would be a false positive. tools/,
tests/ and html/ are excluded, which is where such strings actually live.

Exit 1 on any finding. Wired into CI beside the other gates.

Developed by Matthias Weigelt with the help of Claude (Opus 5),
2026-08-23.
"""
import os
import re
import sys

# three levels: tools/dev/<this> -> tools/dev -> tools -> repo. Two was
# wrong and the gate scanned tools/, which it excludes by name.
ROOT = os.path.dirname(os.path.dirname(
    os.path.dirname(os.path.abspath(__file__))))

# Files allowed to mention geoMap because their job is to hand over to it
# or to explain that they no longer draw.
BRIDGE = {
    "+shLowLevel/requireGeoMap.m",
    "+shLowLevel/writeAnimation.m",
    "+shLowLevel/gridHandover.m",
    "shCoefficients.m",
    "shSeries.m",
    "demo_shAnalysis.m",
}

# Coastline data and projection formulae: the two things that make a map a
# map. Drawing primitives alone are not enough - an image of a covariance
# matrix uses imagesc and is not cartography.
#
# THE COASTLINE CHECK IS THE ONE WITH TEETH, and it is universal: no file
# is exempt, and it alone catches the retired renderer (three hits, on the
# coastlines/coastlat/coastlon it loaded). The projection check is a
# secondary signal and CANNOT tell "names a projection" from "computes
# one" - both are quoted strings - so it is skipped for the short list of
# files that forward a projection name to geoMap. That list is the
# mechanism, so it stays short and is reviewed when it grows.
COASTLINE = re.compile(
    r"\b(coastlines?|coastlat|coastlon|landareas|worldmap|axesm|geoshow|"
    r"borders|gshhg|naturalearth)\b", re.I)
PROJECTION = re.compile(
    r"\b(hammer|mollweide|robinson|equirectangular|plate\s*carree|"
    r"stereographic|orthographic|azimuthal\s*equidistant|"
    r"lambert\s*conformal|albers)\b", re.I)


def strip_comments(text):
    """MATLAB comments, so a help text may NAME what the code must not do."""
    out = []
    for line in text.splitlines():
        i = line.find("%")
        # not inside a string literal - crude but this file only needs to
        # know whether a token survives outside a comment
        if i >= 0 and line[:i].count("'") % 2 == 0 and line[:i].count('"') % 2 == 0:
            line = line[:i]
        out.append(line)
    return "\n".join(out)


def main():
    findings = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames
                       if d not in {".git", "tools", "tests", "html", "docs"}]
        for fn in filenames:
            if not fn.endswith(".m"):
                continue
            full = os.path.join(dirpath, fn)
            rel = os.path.relpath(full, ROOT).replace(os.sep, "/")
            with open(full, encoding="utf-8", errors="replace") as fh:
                code = strip_comments(fh.read())
            for label, rx in (("coastline data", COASTLINE),
                              ("projection formula", PROJECTION)):
                for m in rx.finditer(code):
                    line = code[:m.start()].count("\n") + 1
                    tok = m.group(0)
                    # a bridge file may PASS a projection name through to
                    # geoMap; it may not compute one
                    if rel in BRIDGE and label == "projection formula":
                        continue
                    findings.append(f"{rel}:{line}: {label} '{tok}' - "
                                    f"geoMap is the single map authority")

    if findings:
        for f in findings:
            print(f)
        print(f"no_map_renderer: {len(findings)} finding(s)")
        return 1
    print("no_map_renderer: 0 findings - no map is drawn in this toolbox")
    return 0


if __name__ == "__main__":
    sys.exit(main())
