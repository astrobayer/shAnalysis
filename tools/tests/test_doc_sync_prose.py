#!/usr/bin/env python3
"""Unit tests for doc_sync_audit's PROSE checks (v5.13.1).

Each rule is fault-injected with the defect the v5.13.1 documentation
audit actually found, and pinned silent on the legal shape that looks
like it. The last class runs the whole section on the tree as committed.

Run: python3 tools/tests/test_doc_sync_prose.py

Developed by Matthias Weigelt with the help of Claude (Opus 5), 2026-09-11.
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import doc_sync_audit as dsa  # noqa: E402

ENT = dsa.entities()
SIG = {k: dsa.sig_of(e) for k, e in ENT.items()}
METH = {}
for _k, _e in ENT.items():
    if "." in _k and not _k.startswith("shLowLevel."):
        METH.setdefault(_k.split(".", 1)[1], []).append(dsa.sig_of(_e))


def audit(src):
    probs = []
    dsa.audit_snippet("t", src, SIG, METH, probs)
    return probs


class InlineCalls(unittest.TestCase):
    def test_the_readme_quick_start_defect_is_caught(self):
        # README.md until v5.13.1: five positional arguments, three allowed
        self.assertTrue(audit(
            'A = clim.amplitudeMap("annual", -89:89, 0:359, "ewh", kn);'))

    def test_the_fixed_call_is_silent(self):
        self.assertEqual(audit(
            'A = clim.amplitudeMap("annual", -89:89, 0:359, '
            'Quantity="ewh", kn=kn);'), [])

    def test_every_kind_of_prose_is_read(self):
        where = [w for w, _ in dsa.prose_snippets()]
        for kind in ("guide <font>", "README.md", "Contents.m"):
            self.assertIn(kind, where)
        self.assertTrue(any(w.startswith("html/") and w.endswith("<code>")
                            for w in where))


class BareCalls(unittest.TestCase):
    NAMES = {"legendreALF", "shSynthesis"}

    def test_a_bare_package_call_is_caught(self):
        # html/legendreALF.html until v5.13.1
        self.assertEqual(dsa.bare_calls("P = legendreALF(10, lat);",
                                        self.NAMES), ["legendreALF"])

    def test_the_qualified_call_is_silent(self):
        self.assertEqual(dsa.bare_calls(
            "P = shLowLevel.legendreALF(10, lat);", self.NAMES), [])

    def test_a_method_of_the_same_name_is_silent(self):
        self.assertEqual(dsa.bare_calls("grid = g.shSynthesis(lat, lon);",
                                        self.NAMES), [])

    def test_a_comment_or_a_string_is_silent(self):
        self.assertEqual(dsa.bare_calls(
            'x = 1;  % legendreALF(10, lat)\ns = "shSynthesis(C, S)";',
            self.NAMES), [])


class ClassPages(unittest.TestCase):
    def test_a_missing_method_is_caught(self):
        self.assertEqual(dsa.class_page_missing(
            "destripe and gaussian", ["destripe", "fan", "gaussian"]), ["fan"])

    def test_a_longer_word_does_not_count(self):
        self.assertEqual(dsa.class_page_missing("a fanfare", ["fan"]),
                         ["fan"])


class Identifiers(unittest.TestCase):
    WHOLE = {"shLowLevel:readDDK:notFetched"}
    PREFIX = {"shAnalysis:setup:no"}

    def test_a_retired_identifier_is_caught(self):
        # the two-part form A21b retired in v5.0.0
        self.assertEqual(dsa.unraised("raises shSeries:noEpoch",
                                      self.WHOLE, self.PREFIX),
                         ["shSeries:noEpoch"])

    def test_a_raised_identifier_is_silent(self):
        self.assertEqual(dsa.unraised(
            "errors with shLowLevel:readDDK:notFetched.",
            self.WHOLE, self.PREFIX), [])

    def test_a_built_identifier_is_silent(self):
        self.assertEqual(dsa.unraised("shAnalysis:setup:noSeriesFolder",
                                      self.WHOLE, self.PREFIX), [])

    def test_a_wildcard_is_not_an_identifier(self):
        self.assertEqual(dsa.unraised("identifiers shLowLevel:*",
                                      self.WHOLE, self.PREFIX), [])

    def test_the_raise_scan_reads_the_toolbox(self):
        whole, prefix = dsa.raised_identifiers()
        self.assertIn("shLowLevel:readDDK:notFetched", whole)
        self.assertIn("shAnalysis:setup:no", prefix)


class PageStructure(unittest.TestCase):
    PAGE = ('<html><head><title>t</title>\n</head>\n'
            '<body><div class="content">\n<p>x</p>\n</div></body></html>')

    def test_a_well_formed_page_is_silent(self):
        self.assertEqual(dsa.page_structure(self.PAGE), [])

    def test_a_duplicated_body_line_is_caught(self):
        # six pages until v5.13.1
        line = '<body><div class="content">\n'
        self.assertEqual(dsa.page_structure(self.PAGE.replace(line, line * 2)),
                         ["<body appears 2 times"])

    def test_a_duplicated_head_close_is_caught(self):
        # html/comparison.html until v5.13.1
        self.assertEqual(dsa.page_structure(
            self.PAGE.replace("</head>\n", "</head>\n</head>\n")),
            ["</head> appears 2 times"])


class ShippedTree(unittest.TestCase):
    def test_the_prose_section_is_clean(self):
        pages = sorted(f for f in os.listdir(dsa.HTML) if f.endswith(".html"))
        self.assertEqual(dsa.prose_audit(ENT, SIG, METH, pages), [])


if __name__ == "__main__":
    unittest.main(verbosity=1)
