#!/usr/bin/env python3
"""Unit tests for tools/fixture_tag_audit.py.

Run: python3 tools/tests/test_fixture_tag_audit.py

Developed by Matthias Weigelt with the help of Claude (Sonnet 5),
2026-09-05.
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(
    os.path.abspath(__file__))))
import fixture_tag_audit as fta  # noqa: E402


WF = """\
jobs:
  test:
    steps:
      - name: Check out repository
        uses: actions/checkout@v6
      - name: Check out test fixtures (tag)
        uses: actions/checkout@v6
        with:
          ref: {pin}
          path: tests/test_data
"""


class TestPinnedTags(unittest.TestCase):
    def test_finds_single_pin(self):
        self.assertEqual(fta.pinned_tags(WF.format(pin="fixtures-2026-08")),
                         ["fixtures-2026-08"])

    def test_quoted_forms(self):
        for q in ["'fixtures-2026-08'", '"fixtures-2026-08"']:
            self.assertEqual(fta.pinned_tags(WF.format(pin=q)),
                             ["fixtures-2026-08"], q)

    def test_ignores_non_fixture_refs(self):
        # a branch ref, an action version - neither may be picked up
        txt = "          ref: main\n          ref: v3\n"
        self.assertEqual(fta.pinned_tags(txt), [])

    def test_ignores_ref_inside_prose(self):
        # a comment mentioning a tag must not count as a pin; this is
        # the failure mode that broke testDocSyncAuditIsWired
        txt = "  # bump ref: fixtures-2026-01 when updating\n"
        self.assertEqual(fta.pinned_tags(txt), [])

    def test_finds_multiple(self):
        txt = ("          ref: fixtures-2026-08\n"
               "          ref: fixtures-2026-07\n")
        self.assertEqual(len(fta.pinned_tags(txt)), 2)


class TestNewest(unittest.TestCase):
    def test_year_rollover(self):
        tags = ["fixtures-2025-12", "fixtures-2026-01"]
        self.assertEqual(fta.newest(tags), "fixtures-2026-01")

    def test_zero_padding_beats_naive_sort(self):
        # '10' > '9' numerically but '10' < '9' as bare strings; the
        # padded form is what makes lexicographic order safe
        tags = ["fixtures-2026-09", "fixtures-2026-10"]
        self.assertEqual(fta.newest(tags), "fixtures-2026-10")

    def test_malformed_ignored(self):
        tags = ["fixtures-2026-01", "fixtures-latest"]
        self.assertEqual(fta.newest(tags), "fixtures-2026-01")

    def test_none_when_empty(self):
        self.assertIsNone(fta.newest([]))
        self.assertIsNone(fta.newest(["fixtures-latest"]))


class TestAudit(unittest.TestCase):
    def test_current_pin_passes(self):
        wf = WF.format(pin="fixtures-2026-08")
        self.assertEqual(fta.audit(wf, ["fixtures-2026-08"]), [])

    def test_current_pin_among_several(self):
        wf = WF.format(pin="fixtures-2026-08")
        tags = ["fixtures-2026-06", "fixtures-2026-07", "fixtures-2026-08"]
        self.assertEqual(fta.audit(wf, tags), [])

    def test_stale_pin_is_the_point_of_this_gate(self):
        wf = WF.format(pin="fixtures-2026-08")
        out = fta.audit(wf, ["fixtures-2026-08", "fixtures-2026-09"])
        self.assertEqual(len(out), 1)
        self.assertIn("stale", out[0])
        self.assertIn("fixtures-2026-09", out[0])

    def test_pin_missing_from_remote(self):
        wf = WF.format(pin="fixtures-2026-12")
        out = fta.audit(wf, ["fixtures-2026-08"])
        self.assertEqual(len(out), 1)
        self.assertIn("does not exist", out[0])

    def test_no_pin_at_all(self):
        out = fta.audit("jobs:\n  test:\n    steps: []\n",
                        ["fixtures-2026-08"])
        self.assertEqual(len(out), 1)
        self.assertIn("no fixtures-* tag pinned", out[0])

    def test_two_pins(self):
        txt = ("          ref: fixtures-2026-08\n"
               "          ref: fixtures-2026-07\n")
        out = fta.audit(txt, ["fixtures-2026-07", "fixtures-2026-08"])
        self.assertEqual(len(out), 1)
        self.assertIn("2 fixture refs pinned", out[0])

    def test_malformed_tag_reported(self):
        wf = WF.format(pin="fixtures-2026-08")
        out = fta.audit(wf, ["fixtures-2026-08", "fixtures-latest"])
        self.assertEqual(len(out), 1)
        self.assertIn("fixtures-latest", out[0])

    def test_malformed_tag_does_not_mask_staleness(self):
        wf = WF.format(pin="fixtures-2026-08")
        out = fta.audit(wf, ["fixtures-2026-08", "fixtures-2026-09",
                             "fixtures-latest"])
        self.assertEqual(len(out), 2)
        self.assertTrue(any("stale" in f for f in out))

    def test_no_tags_at_all_only_flags_missing_pin_target(self):
        wf = WF.format(pin="fixtures-2026-08")
        out = fta.audit(wf, [])
        self.assertEqual(len(out), 1)
        self.assertIn("does not exist", out[0])


class TestRemoteTagsOverride(unittest.TestCase):
    def tearDown(self):
        os.environ.pop("SHX_FIXTURE_TAGS", None)

    def test_env_override_parsed(self):
        os.environ["SHX_FIXTURE_TAGS"] = \
            "fixtures-2026-08\n\n  fixtures-2026-07  \n"
        self.assertEqual(fta.remote_tags(),
                         ["fixtures-2026-07", "fixtures-2026-08"])

    def test_env_override_empty_means_no_tags(self):
        os.environ["SHX_FIXTURE_TAGS"] = ""
        self.assertEqual(fta.remote_tags(), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
