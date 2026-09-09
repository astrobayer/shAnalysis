#!/usr/bin/env python3
"""Unit tests for tools/dev/make_refpages.py and refpages_audit.py.

Each rule of the gate is fault-injected on a copy of a real page and
paired with a clean-tree assertion, because a check nobody has seen fire
is not evidence.

Run: python3 tools/tests/test_refpages.py

Developed by Matthias Weigelt with the help of Claude (Opus 5), 2026-09-08.
"""
import io
import os
import shutil
import sys
import tempfile
import unittest
from contextlib import redirect_stdout

DEV = os.path.join(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__))), "dev")
sys.path.insert(0, DEV)
import make_refpages as mrp      # noqa: E402
import refpages_audit as rpa     # noqa: E402


def run(fn, *a):
    buf = io.StringIO()
    with redirect_stdout(buf):
        rc = fn(*a)
    return rc, buf.getvalue()


class TestSkeleton(unittest.TestCase):
    def test_section_order_is_the_mathworks_order(self):
        self.assertEqual(mrp.SECTIONS[:3],
                         ["Syntax", "Description", "Examples"])
        self.assertEqual(mrp.SECTIONS[-2:], ["Version History", "See Also"])

    def test_page_id_is_filename_safe(self):
        self.assertEqual(mrp.page_id("shSeries.filter"), "shSeries_filter")
        self.assertEqual(mrp.page_id("setup_shAnalysis"), "setup_shAnalysis")

    def test_syntax_line_shows_the_output_list(self):
        e = {"outputs": ["Cf", "Sf"],
             "args": [{"name": "C"}, {"name": "S"}]}
        line = mrp.syntax_lines("shLowLevel.applyDDK", e)[0]
        self.assertEqual(line, "[Cf, Sf] = shLowLevel.applyDDK(C, S)")

    def test_name_value_form_is_a_separate_syntax_line(self):
        e = {"outputs": ["y"], "args": [
            {"name": "x"}, {"name": "Nmax", "nv": True, "default": "96"}]}
        lines = mrp.syntax_lines("f", e)
        self.assertEqual(len(lines), 2)
        self.assertIn("Nmax=96", lines[1])


class TestGeneratedTree(unittest.TestCase):
    """the healthy tree stays silent - the other half of the injection"""

    def test_pages_are_up_to_date(self):
        rc, out = run(mrp.main, ["--check"])
        self.assertEqual(rc, 0, out)

    def test_audit_is_clean(self):
        rc, out = run(rpa.main)
        self.assertEqual(rc, 0, out)

    def test_every_entity_has_a_page(self):
        ents = mrp.entities(mrp.load_api())
        have = set(os.listdir(mrp.OUTDIR))
        for n, _, _ in ents:
            self.assertIn(mrp.page_id(n) + ".html", have, n)


class TestFaultInjection(unittest.TestCase):
    """each finding, provoked on a scratch copy of html/ref"""

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.real = mrp.OUTDIR
        shutil.copytree(self.real, os.path.join(self.tmp, "ref"))
        mrp.OUTDIR = rpa.mrp.OUTDIR = os.path.join(self.tmp, "ref")
        self.page = os.path.join(mrp.OUTDIR, "shLowLevel_applyDDK.html")
        # the stylesheet lives one level up from OUTDIR
        os.makedirs(os.path.join(self.tmp, "x"), exist_ok=True)
        shutil.copy(os.path.join(os.path.dirname(self.real),
                                 "shAnalysis.css"),
                    os.path.join(self.tmp, "shAnalysis.css"))

    def tearDown(self):
        mrp.OUTDIR = rpa.mrp.OUTDIR = self.real
        shutil.rmtree(self.tmp, ignore_errors=True)

    def edit(self, old, new):
        with open(self.page, encoding="utf-8") as fh:
            s = fh.read()
        assert s.count(old) >= 1, old
        with open(self.page, "w", encoding="utf-8") as fh:
            fh.write(s.replace(old, new, 1))

    def test_a_hand_edited_page_is_stale(self):
        self.edit("<h1>shLowLevel.applyDDK</h1>", "<h1>edited by hand</h1>")
        rc, out = run(rpa.main)
        self.assertEqual(rc, 1)
        self.assertIn("stale", out)

    def test_a_missing_section_fires(self):
        self.edit("<h2>See Also</h2>", "<h2>Siehe auch</h2>")
        rc, out = run(rpa.main)
        self.assertEqual(rc, 1)
        self.assertIn("See Also", out)

    def test_a_heading_outside_the_skeleton_fires(self):
        self.edit("<h2>Description</h2>",
                  "<h2>Description</h2><p>x</p><h2>Blurb</h2>")
        rc, out = run(rpa.main)
        self.assertEqual(rc, 1)
        self.assertIn("Blurb", out)

    def test_an_empty_section_fires(self):
        self.edit('<h2>Name-Value Arguments</h2>\n<p class="none">None.</p>',
                  "<h2>Name-Value Arguments</h2>\n")
        rc, out = run(rpa.main)
        self.assertEqual(rc, 1)
        self.assertIn("empty", out)

    def test_an_inline_style_block_fires(self):
        self.edit("</head>", "<style>h1{color:red}</style></head>")
        rc, out = run(rpa.main)
        self.assertEqual(rc, 1)
        self.assertIn("inline <style>", out)

    def test_a_dead_link_fires(self):
        self.edit('href="index.html"', 'href="nope.html"')
        rc, out = run(rpa.main)
        self.assertEqual(rc, 1)
        self.assertIn("does not exist", out)

    def test_an_orphaned_page_fires(self):
        with open(os.path.join(mrp.OUTDIR, "shLowLevel_gone.html"),
                  "w", encoding="utf-8") as fh:
            fh.write("<html></html>")
        rc, out = run(rpa.main)
        self.assertEqual(rc, 1)
        self.assertIn("shLowLevel_gone.html", out)


if __name__ == "__main__":
    unittest.main(verbosity=2)
