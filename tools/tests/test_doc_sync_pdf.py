#!/usr/bin/env python3
"""Unit tests for doc_sync_audit's checks of the guide PDF: the two A29
checks, and (v5.24.1) that the guide is a build output, never tracked.

The guide PDF is pure ASCII, so git took it for text and a Windows checkout
with core.autocrlf rewrote its line endings - on 2026-09-10 a pull inserted
3589 CR bytes into it. The gate checks that .gitattributes marks it binary
and that its startxref still points at its xref table. The fault injected
below is the one that happened: every LF becomes CRLF.

Run: python3 tools/tests/test_doc_sync_pdf.py

Developed by Matthias Weigelt with the help of Claude (Opus 5), 2026-09-10.
"""
import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import doc_sync_audit as dsa  # noqa: E402

GUIDE = "docs/shAnalysis_workflow_guide.pdf"


def tiny_pdf():
    """A minimal PDF whose startxref is right, as a PDF writer leaves it."""
    body = b"%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\n"
    return (body + b"xref\n0 1\n0000000000 65535 f \ntrailer\n<< /Size 1 >>\n"
            b"startxref\n" + str(len(body)).encode() + b"\n%%EOF\n")


class Xref(unittest.TestCase):
    def check(self, data):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "t.pdf")
            with open(p, "wb") as fh:
                fh.write(data)
            return dsa.pdf_xref_offset_ok(p)

    def test_a_built_pdf_points_at_its_xref(self):
        ok, n = self.check(tiny_pdf())
        self.assertTrue(ok)
        self.assertEqual(n, tiny_pdf().index(b"xref"))

    def test_a_crlf_rewrite_is_caught(self):
        ok, _ = self.check(tiny_pdf().replace(b"\n", b"\r\n"))
        self.assertFalse(ok)

    def test_no_startxref_is_not_ok(self):
        ok, n = self.check(b"%PDF-1.4\nnothing here\n")
        self.assertFalse(ok)
        self.assertIsNone(n)

    @unittest.skipUnless(os.path.isfile(os.path.join(dsa.ROOT, *GUIDE.split("/"))),
                         "the guide is not built here (CI builds it first)")
    def test_the_built_guide_is_intact(self):
        ok, n = dsa.pdf_xref_offset_ok(os.path.join(dsa.ROOT, *GUIDE.split("/")))
        self.assertTrue(ok, "the guide's startxref (%s) misses its xref" % n)


class Attributes(unittest.TestCase):
    def marked(self, text):
        with tempfile.TemporaryDirectory() as d:
            if text is not None:
                with open(os.path.join(d, ".gitattributes"), "w",
                          encoding="utf-8") as fh:
                    fh.write(text)
            return dsa.gitattributes_binary(d, GUIDE)

    def test_no_gitattributes_is_not_marked(self):
        self.assertFalse(self.marked(None))

    def test_star_pdf_binary_marks_it(self):
        self.assertTrue(self.marked("# comment\n*.pdf binary\n"))

    def test_minus_text_marks_it(self):
        self.assertTrue(self.marked("*.pdf -text\n"))

    def test_a_path_pattern_marks_it(self):
        self.assertTrue(self.marked("docs/*.pdf binary\n"))

    def test_a_later_text_line_wins(self):
        self.assertFalse(self.marked("*.pdf binary\n*.pdf text\n"))

    def test_another_pattern_does_not_mark_it(self):
        self.assertFalse(self.marked("*.png binary\n"))

    def test_the_repository_marks_it(self):
        self.assertTrue(dsa.gitattributes_binary(dsa.ROOT, GUIDE))


class Tracked(unittest.TestCase):
    """v5.24.1: the guide is built by CI and attached to the release, so
    a tracked copy is a finding - it would go stale beside the built one."""

    def repo(self, track):
        d = tempfile.mkdtemp()
        run = lambda *a: subprocess.run(["git", "-C", d] + list(a),
                                        capture_output=True, check=True)
        run("init", "-q")
        os.makedirs(os.path.join(d, "docs"))
        with open(os.path.join(d, *GUIDE.split("/")), "wb") as fh:
            fh.write(tiny_pdf())
        if track:
            run("add", GUIDE)
        return d

    def test_a_tracked_guide_is_seen(self):
        self.assertTrue(dsa.guide_tracked(self.repo(True)))

    def test_an_untracked_build_is_not(self):
        self.assertFalse(dsa.guide_tracked(self.repo(False)))

    def test_no_repository_is_not_a_finding(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertFalse(dsa.guide_tracked(d))

    def test_the_repository_does_not_track_it(self):
        self.assertFalse(dsa.guide_tracked(dsa.ROOT))

    def test_the_repository_ignores_it(self):
        r = subprocess.run(["git", "-C", dsa.ROOT, "check-ignore", "-q", GUIDE])
        self.assertEqual(r.returncode, 0, ".gitignore must list the guide")


if __name__ == "__main__":
    unittest.main(verbosity=1)
