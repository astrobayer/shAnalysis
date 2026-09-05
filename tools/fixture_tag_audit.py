#!/usr/bin/env python3
"""fixture_tag_audit: the pinned fixture tag must be the newest one.

Fixtures moved from the moving branch 'testdata' to dated tags
(v2.9.0). That bought provenance - a given main revision now resolves
to exactly one data set - at the cost of a new silent failure: publish
a newer fixtures-* tag, forget to bump 'ref:' in the workflow, and CI
keeps passing against stale data with nothing to show for it. The
moving branch could not fail that way.

This gate closes that hole. It reads the pinned ref out of the
workflow, lists the fixtures-* tags on the remote, and fails when the
two disagree.

Findings:
  1. no fixtures-* ref pinned in the workflow, or more than one
  2. the pinned tag does not exist on the remote
  3. a newer fixtures-* tag exists than the one pinned
  4. a tag does not match the fixtures-YYYY-MM naming rule

Tag list resolution, in order:
  1. SHX_FIXTURE_TAGS, newline separated - for tests and dry runs
  2. git ls-remote --tags origin

Developed by Matthias Weigelt with the help of Claude (Sonnet 5),
2026-09-05.
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORKFLOW = os.path.join(ROOT, ".github", "workflows", "ci.yml")

# fixtures-YYYY-MM. Zero padded, so lexicographic order IS chronological
# order and no date parsing is needed to find the newest.
TAG_RE = re.compile(r"^fixtures-(\d{4})-(\d{2})$")
# 'ref:' lines in the workflow that name a fixture tag. Anchored on the
# fixtures- prefix so branch refs and action versions cannot match.
PIN_RE = re.compile(r"^\s*ref:\s*[\"']?(fixtures-[\w.-]+)[\"']?\s*$", re.M)


def pinned_tags(text):
    """Fixture refs pinned in the workflow.

    Inputs
      text  (str)  raw workflow file contents

    Outputs
      (list of str)  every fixtures-* ref named on a 'ref:' line, in
                     file order; normally exactly one
    """
    return PIN_RE.findall(text)


def remote_tags():
    """Available fixture tags.

    Outputs
      (list of str)  fixtures-* tag names, unsorted, duplicates removed
    """
    override = os.environ.get("SHX_FIXTURE_TAGS")
    if override is not None:
        raw = [ln.strip() for ln in override.splitlines()]
        return sorted({r for r in raw if r})

    out = subprocess.run(
        ["git", "ls-remote", "--tags", "origin", "refs/tags/fixtures-*"],
        cwd=ROOT, capture_output=True, text=True, check=True).stdout

    names = set()
    for line in out.splitlines():
        parts = line.split("\t")
        if len(parts) != 2:
            continue
        # strip refs/tags/ and the ^{} peel suffix of annotated tags
        names.add(parts[1][len("refs/tags/"):].removesuffix("^{}"))
    return sorted(names)


def newest(tags):
    """The chronologically newest well-formed tag, or None.

    Inputs
      tags  (list of str)

    Outputs
      (str | None)  greatest tag matching fixtures-YYYY-MM
    """
    ok = [t for t in tags if TAG_RE.match(t)]
    return max(ok) if ok else None


def audit(workflow_text, tags):
    """Compare the pinned ref against the available tags.

    Inputs
      workflow_text  (str)        raw workflow contents
      tags           (list of str) available fixtures-* tags

    Outputs
      (list of str)  findings; empty means the pin is current
    """
    findings = []

    for t in tags:
        if not TAG_RE.match(t):
            findings.append(
                f"tag '{t}' does not match fixtures-YYYY-MM - rename it "
                f"or it will never be seen as newest")

    pins = pinned_tags(workflow_text)
    if not pins:
        findings.append(
            "no fixtures-* tag pinned in .github/workflows/ci.yml - the "
            "fixture checkout step must name one")
        return findings
    if len(pins) > 1:
        findings.append(
            f"{len(pins)} fixture refs pinned ({', '.join(pins)}) - "
            f"exactly one is expected")
        return findings

    pin = pins[0]
    if pin not in tags:
        findings.append(
            f"pinned tag '{pin}' does not exist on the remote - the "
            f"fixture checkout will fail")
        return findings

    top = newest(tags)
    if top is not None and pin != top:
        findings.append(
            f"pinned tag '{pin}' is stale: '{top}' is newer. CI is "
            f"passing against outdated fixtures. Bump 'ref:' in "
            f".github/workflows/ci.yml, or delete the unused tag.")

    return findings


def main():
    if not os.path.isfile(WORKFLOW):
        print(f"fixture_tag_audit: no workflow at {WORKFLOW}")
        return 1
    with open(WORKFLOW, encoding="utf-8", errors="replace") as fh:
        text = fh.read()

    try:
        tags = remote_tags()
    except subprocess.CalledProcessError as exc:
        print("fixture_tag_audit: could not list remote tags "
              f"(git exit {exc.returncode})")
        print(exc.stderr.strip())
        return 1

    findings = audit(text, tags)
    if findings:
        print(f"fixture_tag_audit: {len(findings)} finding(s)")
        for f in findings:
            print(f"  {f}")
        return 1

    print(f"fixture_tag_audit: 0 findings - pinned "
          f"{pinned_tags(text)[0]}, the newest of {len(tags)} tag(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
