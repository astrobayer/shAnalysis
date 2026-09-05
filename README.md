# shAnalysis CI test fixtures

This commit is the fixture set for the shAnalysis test suite. It shares
no history with `main`: it contains nothing but binary and text sample
data, so that `main` does not have to carry ~11 MB (v3.26.1).

**It is referenced by a tag, not a branch.** `.github/workflows/ci.yml`
on `main` pins an exact fixture version:

```yaml
      - name: Check out test fixtures (tag)
        uses: actions/checkout@v6
        with:
          ref: fixtures-2026-08
          path: tests/test_data
```

A tag is the honest construct here. A branch is a line of development;
this is a frozen data set. Two practical consequences follow:

* The workflow records WHICH fixture version a run used. With a moving
  branch that was invisible - the same `main` revision could run against
  different data on different days and nobody would see it.
* GitHub's "compare & pull request" banner only fires for branches, so
  updating fixtures no longer produces a misleading prompt to open a
  pull request that could never be merged.

## Updating fixtures

1. Create a commit with the new fixture set. It does not need to
   descend from this one - an orphan commit is fine.
2. Tag it, dated: `fixtures-YYYY-MM`.
3. Bump `ref:` in `.github/workflows/ci.yml` on `main`, in the same
   pull request that justifies the fixture change.

Do not move an existing tag. The point of the arrangement is that a
given `main` revision always resolves to the same data.

Do not open a pull request against `main` - there is no common
ancestor, so the diff is meaningless.

Keep it small: the checkout runs on every job. Large inputs that only
the acceptance machine needs (for example the 460 MB
`ITSG-Grace_operational_n96_2018-06.snx.gz`) belong in the local data
folder, not here.

## Local development

Development machines do not use this tag. They point at a local copy
via `setup_shAnalysis(TestDataFolder=...)`, the `SHX_TESTDATA_FOLDER`
environment variable, or the `tests/test_data` fallback. The resolution
order lives in `shLowLevel.testDataDir`.

## If the tag is deleted

A deleted commit stays reachable on GitHub for a while before garbage
collection. Recreate the ref directly:

```bash
curl -X POST -H "Authorization: token $GH_TOKEN" \
  https://api.github.com/repos/matweigelt/shAnalysis/git/refs \
  -d '{"ref":"refs/tags/fixtures-2026-08","sha":"<COMMIT_SHA>"}'
```

Past that window, push from a clone that still holds the object.

This is not hypothetical. On 2026-09-05 the fixture branch that
preceded this tag was found deleted; the first CI run on the new
self-hosted runner failed at the checkout step, and the log said only
`git.exe failed with exit code 1` - no hint that a ref had gone
missing. It was restored from `bd2e67c` byte-identically. Protect the
tag against deletion with a repository ruleset targeting tags.

## Licensing

Fixture contents are CC-BY-4.0. See `NOTICE` on `main` for attribution
of the individual products (ITSG, GRAVIS, CSR/GFZ/JPL technical notes,
DDK filter matrices).
