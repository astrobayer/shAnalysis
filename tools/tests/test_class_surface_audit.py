#!/usr/bin/env python3
"""Unit tests for tools/dev/class_surface_audit.py (WP7).

The gate's claim is a closure: a public +shLowLevel function is reached
when a class calls it, directly or through other package functions or
the package's private helpers. These tests pin the closure in both
directions - what must count (a transitive path, a path through a private
helper) and what must NOT (a name in a comment or in a string, which would
let the gate pass a lane that nothing reaches) - and every rule about the
two lists and the delegates.

Run: python3 tools/tests/test_class_surface_audit.py

Developed by Matthias Weigelt with the help of Claude (Opus 5), 2026-09-10.
"""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__))), "dev"))
import class_surface_audit as csa  # noqa: E402

SERIES = """\
classdef shSeries
methods
    function out = lane(obj)
        %LANE Delegates to alpha.
        out = shLowLevel.alpha(obj);
    end
    function out = other(obj)
        %OTHER Names two lanes without calling either.
        % shLowLevel.ghost is only named in this comment
        error('shSeries:other:x', 'see shLowLevel.ghost2(1) in a string');
        out = obj;
    end
end
end
"""

PKG = {
    "alpha": "function y = alpha(x)\ny = shLowLevel.beta(x) + helper(x);\nend\n",
    "beta": "function y = beta(x)\ny = x;\nend\n",
    "delta": "function y = delta(x)\ny = x;\nend\n",
    "gamma": "function y = gamma(x)\ny = x;\nend\n",
    "ghost": "function y = ghost(x)\ny = x;\nend\n",
    "ghost2": "function y = ghost2(x)\ny = x;\nend\n",
}
PRIVATE = {
    "helper": "function y = helper(x)\ny = shLowLevel.delta(x);\nend\n",
}


def _write(path, text):
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def build(root, series=SERIES):
    os.makedirs(os.path.join(root, "+shLowLevel", "private"))
    for n, s in PKG.items():
        _write(os.path.join(root, "+shLowLevel", n + ".m"), s)
    for n, s in PRIVATE.items():
        _write(os.path.join(root, "+shLowLevel", "private", n + ".m"), s)
    _write(os.path.join(root, "shSeries.m"), series)
    _write(os.path.join(root, "shCoefficients.m"), "classdef shCoefficients\nend\n")
    _write(os.path.join(root, "shClimatology.m"), "classdef shClimatology\nend\n")


class Synthetic(unittest.TestCase):
    CLEAN = dict(exceptions={"ghost": "why"},
                 backlog={"gamma": "route", "ghost2": "route"},
                 delegates={})

    def setUp(self):
        self._d = tempfile.TemporaryDirectory()
        self.root = self._d.name
        build(self.root)

    def tearDown(self):
        self._d.cleanup()

    def check(self, **kw):
        args = dict(self.CLEAN)
        args.update(kw)
        return csa.check(self.root, **args)[0]

    def test_direct_transitive_and_private_paths_count(self):
        # alpha is called by the class, beta by alpha, delta only by the
        # private helper alpha calls
        _, reached, _ = csa.graph(self.root)
        self.assertEqual(reached, {"alpha", "beta", "delta"})

    def test_names_in_comments_and_strings_do_not_count(self):
        _, reached, _ = csa.graph(self.root)
        self.assertNotIn("ghost", reached)
        self.assertNotIn("ghost2", reached)

    def test_clean_when_every_unreached_function_is_listed(self):
        self.assertEqual(self.check(), [])

    def test_an_unlisted_unreached_function_is_a_finding(self):
        p = self.check(backlog={"ghost2": "route"})
        self.assertTrue(any("shLowLevel.gamma is reachable from no class" in x
                            for x in p), p)

    def test_the_backlog_may_only_shrink(self):
        p = self.check(backlog={"gamma": "r", "ghost2": "r", "alpha": "r"})
        self.assertTrue(any("alpha is reachable from a class now" in x
                            for x in p), p)

    def test_a_reached_exception_is_stale(self):
        p = self.check(exceptions={"ghost": "why", "beta": "why"})
        self.assertTrue(any("beta is reachable from a class, so it is no "
                            "longer an exception" in x for x in p), p)

    def test_unknown_and_doubly_listed_names(self):
        p = self.check(exceptions={"ghost": "why", "gamma": "why",
                                   "nosuch": "why"})
        self.assertTrue(any("gamma is in both" in x for x in p), p)
        self.assertTrue(any("lists nosuch" in x for x in p), p)

    def test_a_delegate_must_call_its_lane(self):
        self.assertEqual(self.check(delegates={("shSeries", "lane"): "alpha"}), [])
        p = self.check(delegates={("shSeries", "lane"): "beta"})
        self.assertTrue(any("does not call shLowLevel.beta" in x for x in p), p)
        p = self.check(delegates={("shSeries", "missing"): "alpha"})
        self.assertTrue(any("shSeries.missing does not exist" in x for x in p), p)
        p = self.check(delegates={("shSeries", "lane"): "nosuch"})
        self.assertTrue(any("which does not exist" in x for x in p), p)

    def test_a_name_in_a_comment_does_not_satisfy_a_delegate(self):
        p = self.check(delegates={("shSeries", "other"): "ghost"})
        self.assertTrue(any("does not call shLowLevel.ghost" in x for x in p), p)

    def test_feval_in_a_class_is_reported(self):
        with tempfile.TemporaryDirectory() as root:
            build(root, SERIES.replace(
                "out = obj;", 'out = feval("shLowLevel.gamma", obj);'))
            p = csa.check(root, **self.CLEAN)[0]
            self.assertTrue(any("feval/str2func" in x for x in p), p)


class RealTree(unittest.TestCase):
    def test_the_repository_is_clean(self):
        probs, _, _ = csa.check()
        self.assertEqual(probs, [])

    def test_every_list_entry_carries_a_reason(self):
        for n, why in list(csa.EXCEPTIONS.items()) + list(csa.BACKLOG.items()):
            self.assertTrue(why.strip(), n)


if __name__ == "__main__":
    unittest.main(verbosity=1)
