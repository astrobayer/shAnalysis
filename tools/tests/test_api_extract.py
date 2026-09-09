#!/usr/bin/env python3
"""Unit tests for tools/dev/api_extract.py signature parsing (A17).

api_extract matched the function signature on a single raw line. One
public function - gridHandover - continues its signature with "..." , so
the line carried no closing paren, the file parsed to nothing, and the
entity vanished from api_data.py. With it went its reference page, while
refpages_audit's COVER check compared the pages against that same blind
artifact and reported zero findings.

These tests pin the three things that went wrong:
  1. a continued signature parses, with the right name and arguments
  2. the help block is read after the LAST continuation line, not the first
  3. a file that parses to nothing is a hard failure, never a silent drop

Run: python3 tools/tests/test_api_extract.py

Developed by Matthias Weigelt with the help of Claude (Opus 5), 2026-09-08.
"""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__))), "dev"))
import api_extract as ax  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__))))

PLAIN = """\
function b = thing(Z, lat, lon)
%THING One line summary.
%
%   Inputs
%     Z    double  the field
%   Outputs
%     b    (1,1) struct  the bundle
%
%   Developed by Matthias Weigelt with the help of Claude (Opus 5).
b = struct();
end
"""

# the gridHandover shape: signature broken across two lines with "..."
CONTINUED = """\
function b = thing(Z, lat, lon, units, latType, quantity, ...
    productType, name, epoch)
%THING One line summary.
%
%   Inputs
%     Z    double  the field
%   Outputs
%     b    (1,1) struct  the bundle
%
%   Developed by Matthias Weigelt with the help of Claude (Opus 5).
b = struct();
end
"""

# MATLAB skips comment lines inside a continuation. If the parser joins
# one instead, the parens in the help text supply a closing paren and the
# signature parses to nonsense rather than failing.
COMMENT_IN_CONTINUATION = """\
function v = thing(x, p ...
%THING Percentile without the Statistics Toolbox (base MATLAB only).
    , q)
v = 0;
end
"""

NO_PARENS = """\
function v = thing
%THING No argument list at all.
v = 0;
end
"""


def parse(src):
    fd, path = tempfile.mkstemp(suffix=".m")
    os.close(fd)
    try:
        with open(path, "w") as fh:
            fh.write(src)
        return ax.parse_function_file(path)
    finally:
        os.unlink(path)


class TestSignatureParsing(unittest.TestCase):

    def test_plain_signature(self):
        e = parse(PLAIN)
        self.assertEqual(e["name"], "thing")
        self.assertEqual(e["inputs"], ["Z", "lat", "lon"])
        self.assertEqual(e["h1"], "One line summary.")

    def test_continued_signature_parses(self):
        """A17: this returned None before the fix."""
        e = parse(CONTINUED)
        self.assertIsNotNone(e, "continued signature parsed to nothing")
        self.assertEqual(e["name"], "thing")
        self.assertEqual(e["inputs"], ["Z", "lat", "lon", "units",
                                       "latType", "quantity",
                                       "productType", "name", "epoch"])

    def test_continued_signature_still_finds_the_help(self):
        """The help starts after the last continuation line, not the first."""
        e = parse(CONTINUED)
        self.assertEqual(e["h1"], "One line summary.")
        self.assertTrue(e["outdocs"], "Outputs block lost with the help block")

    def test_comment_inside_a_continuation_is_skipped(self):
        e = parse(COMMENT_IN_CONTINUATION)
        self.assertIsNotNone(e)
        self.assertEqual(e["inputs"], ["x", "p", "q"],
                         "help-text parens leaked into the argument list")

    def test_unparseable_signature_returns_none(self):
        self.assertIsNone(parse(NO_PARENS))


class TestRealSurface(unittest.TestCase):
    """The repository itself: every public file must produce an entity."""

    def test_every_public_file_parses(self):
        import glob
        silent = []
        for p in sorted(glob.glob(os.path.join(ROOT, "+shLowLevel", "*.m"))):
            if ax.parse_function_file(p) is None:
                silent.append(os.path.basename(p))
        for f in ["setup_shAnalysis.m", "runAllTests.m", "demo_shAnalysis.m"]:
            if ax.parse_function_file(os.path.join(ROOT, f)) is None:
                silent.append(f)
        self.assertEqual(silent, [], "public files that parse to nothing")

    def test_gridHandover_is_in_the_extracted_surface(self):
        """The function A17 was found on - pinned by name."""
        e = ax.parse_function_file(
            os.path.join(ROOT, "+shLowLevel", "gridHandover.m"))
        self.assertIsNotNone(e)
        self.assertEqual(e["name"], "gridHandover")
        self.assertEqual(len(e["inputs"]), 13)


if __name__ == "__main__":
    unittest.main(verbosity=2)
