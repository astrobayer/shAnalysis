#!/usr/bin/env python3
"""refpages_audit: the generated reference pages say what they claim to.

Gate for WP6. Checks, on html/ref/:
  STALE     every page matches what make_refpages.py would write now
            (the help block is the authority; a page that drifted from it
            is the "correct version stamp, help text twenty-one revisions
            old" failure this toolbox has already shipped once)
  COVER     every public entity in api_data.py has a page, and no page
            exists for an entity that does not
  SECTIONS  every page carries every section of the skeleton, in order.
            A section with nothing to say must SAY so - a missing section
            and an empty one are different claims
  VOCAB     no heading outside the skeleton: five heading vocabularies for
            the same thing is what A8 found in the hand-written pages
  STYLE     no inline <style>; every page links the shared stylesheet
  LINKS     every relative link resolves to a file that exists

Usage: python3 tools/dev/refpages_audit.py
Exit code is the number of findings, capped at 1.

Developed by Matthias Weigelt with the help of Claude (Opus 5), 2026-09-08.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import make_refpages as mrp  # noqa: E402

H2 = re.compile(r"<h2>(.*?)</h2>", re.S)
LINK = re.compile(r'(?:href|src)="([^"#:]+)(?:#[^"]*)?"')


def main():
    probs = []
    outdir = mrp.OUTDIR
    if not os.path.isdir(outdir):
        print("refpages_audit: html/ref does not exist - run "
              "tools/dev/make_refpages.py")
        return 1

    # --- STALE: regenerate in memory and compare
    if mrp.main(["--check"]) != 0:
        probs.append("pages are stale or orphaned - see the lines above")

    # --- COVER
    api = mrp.load_api()
    ents = mrp.entities(api)
    want = {mrp.page_id(n) + ".html" for n, _, _ in ents} | {"index.html"}
    have = {f for f in os.listdir(outdir) if f.endswith(".html")}
    for f in sorted(want - have):
        probs.append("%s: no page for this entity" % f)
    for f in sorted(have - want):
        probs.append("%s: page for an entity that no longer exists" % f)

    # --- per page
    for f in sorted(have & want):
        p = os.path.join(outdir, f)
        with open(p, encoding="utf-8") as fh:
            src = fh.read()
        if f == "index.html":
            continue
        heads = [re.sub(r"<[^>]+>", "", h).strip() for h in H2.findall(src)]
        if heads != mrp.SECTIONS:
            missing = [s for s in mrp.SECTIONS if s not in heads]
            extra = [s for s in heads if s not in mrp.SECTIONS]
            if missing:
                probs.append("%s: missing section(s) %s"
                             % (f, ", ".join(missing)))
            if extra:
                probs.append("%s: heading(s) outside the skeleton: %s"
                             % (f, ", ".join(extra)))
            if not missing and not extra:
                probs.append("%s: sections out of order - %s"
                             % (f, " / ".join(heads)))
        for h in mrp.SECTIONS:
            i = src.find("<h2>%s</h2>" % h)
            if i < 0:
                continue
            j = src.find("<h2>", i + 4)
            body = src[i + len(h) + 9:j if j > 0 else len(src)]
            if not re.sub(r"<[^>]+>|\s", "", body):
                probs.append("%s: section '%s' is empty - a section with "
                             "nothing to say must say so" % (f, h))

    for f in sorted(have):
        p = os.path.join(outdir, f)
        with open(p, encoding="utf-8") as fh:
            src = fh.read()
        if "<style" in src:
            probs.append("%s: inline <style> - the shared stylesheet "
                         "html/shAnalysis.css is the one authority" % f)
        if 'href="../shAnalysis.css"' not in src:
            probs.append("%s: does not link ../shAnalysis.css" % f)
        for target in set(LINK.findall(src)):
            if target.startswith(("http", "mailto")):
                continue
            if not os.path.exists(os.path.normpath(
                    os.path.join(outdir, target))):
                probs.append("%s: link to %s, which does not exist"
                             % (f, target))

    css = os.path.join(ROOT, "html", "shAnalysis.css")
    if not os.path.isfile(css):
        probs.append("html/shAnalysis.css is missing")

    if probs:
        print("refpages_audit: %d finding(s)" % len(probs))
        for x in probs:
            print("  -", x)
        return 1
    print("refpages_audit: 0 findings - %d pages, every section present, "
          "one stylesheet, every link resolves" % len(have))
    return 0


if __name__ == "__main__":
    sys.exit(main())
