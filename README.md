# shAnalysis CI test fixtures

**Do not delete this branch. Do not merge it into `main`.**

This is an orphan branch: it shares no history with `main` and contains
nothing but binary and text fixtures for the test suite. It exists so
that `main` does not have to carry ~11 MB of sample data (v3.26.1).

## Who depends on it

`.github/workflows/ci.yml` on `main` checks this branch out into
`tests/test_data` on every run:

```yaml
      - name: Check out test fixtures (orphan branch 'testdata')
        uses: actions/checkout@v6
        with:
          ref: testdata
          path: tests/test_data
```

Delete this branch and CI fails at that step on the next run, with no
hint that a branch went missing - the log shows only
`git.exe failed with exit code 1`.

Development machines do not use this branch. They point at a local copy
via `setup_shAnalysis(TestDataFolder=...)`, the `SHX_TESTDATA_FOLDER`
environment variable, or the `tests/test_data` fallback. The resolution
order lives in `shLowLevel.testDataDir`.

## Updating fixtures

Commit directly to this branch. Do not open a pull request against
`main` - there is no common ancestor, so the diff is meaningless.

Keep it small: the CI checkout runs on every job. Large inputs that
only the acceptance machine needs (for example the 460 MB
`ITSG-Grace_operational_n96_2018-06.snx.gz`) belong in the local data
folder, not here.

## If it is deleted anyway

A deleted commit stays reachable on GitHub for a while before garbage
collection. Recreate the ref directly:

```bash
curl -X POST -H "Authorization: token $GH_TOKEN" \
  https://api.github.com/repos/matweigelt/shAnalysis/git/refs \
  -d '{"ref":"refs/heads/testdata","sha":"<COMMIT_SHA>"}'
```

Past that window, push from a clone that still has the
`origin/testdata` remote-tracking ref.

This happened on 2026-09-05: the branch was gone, the first CI run on
the new self-hosted runner failed on the checkout step, and the branch
was restored from `bd2e67c` byte-identically. Hence this file.

## Licensing

Fixture contents are CC-BY-4.0. See `NOTICE` on `main` for attribution
of the individual products (ITSG, GRAVIS, CSR/GFZ/JPL technical notes,
DDK filter matrices).
