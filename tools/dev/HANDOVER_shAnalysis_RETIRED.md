# shAnalysis — Handover (RETIRED 2026-09-08)

**This document is retired.** The single point of truth is now
[`/CLAUDE.md`](../../CLAUDE.md) at the repository root; read that, not this.

It is kept here for the record: it is the last chat-delivered handover
whose full text survived (2026-08-10, v3.1.0 era, prepared at the end of the
session that also committed `tools/dev/`). Later revisions (up to the one
CHANGELOG v3.32.3 calls "the v3.28 handover") lived only inside chat
sessions and were superseded release by release; their still-valid rules were
folded into `CLAUDE.md` §2–§3 during the 2026-09-08 audit.

Everything below is **historical text, verbatim**. Facts that are known to be
stale are marked with `[STALE]` inline; anything unmarked may still be stale —
verify against `CLAUDE.md` and the source before acting on it.

Retired by Claude Fable 5.1, 2026-09-08. Developed by Matthias Weigelt with
the help of Claude.

---
---

# shAnalysis — Handover (2026-08-10, end of session)

Add this file to the project knowledge of the new chat. It is the
authoritative state transfer; the toolchain itself is preserved in the
repo under `tools/dev/` (PR #12).

---

## 1. Project identity

MATLAB toolbox **shAnalysis** for GRACE/GRACE-FO spherical harmonic
analysis. Author: Matthias Weigelt. Public repo:
`https://github.com/matweigelt/shAnalysis`. `[STALE: now the private repo astrobayer/shAnalysis]`

**Non-negotiable house rules**
- Base MATLAB only, no toolboxes (`shLowLevel.pctile`, `effectiveCorr` etc. replace toolbox functions).
- Every numeric Python-validated (numpy/scipy) BEFORE MATLAB implementation; pinned values in tests trace to `tools/dev/validate_*.py`.
- Quality gates before any PR, all zero findings: `mlint_lite.py`, `check_api.py`, `attribution_sweep.py`, `api_audit.py`, `tools/help_audit.py` (the last also runs in CI). `[STALE: the gate list grew — see CLAUDE.md §3 and tools/dev/README.md]`
- Unit tests + regenerated HTML/PDF docs + "Developed by ..." provenance stamps on every deliverable.
- No hardcoded physical constants (GM=3.986004415e14, R=6378136.3, f=1/298.257223563 are overridable defaults). No hardcoded VERSION strings anywhere — parse `Contents.m` (five separate bugs died from this).
- Love numbers always user-supplied (architectural decision; `shLowLevel.fetchLoveNumbers` automates obtaining published sets).
- Conventions: C(n+1,m+1) indexing, geocentric latitudes, `legendreALF` takes RADIANS.
- Communication: terse, directive; production quality; English replies.

## 2. Current state `[STALE: describes v3.1.0; the toolbox is at v3.33.0]`

- **Version 3.1.0** (`Contents.m` = single source of truth, honoured by `ver('shAnalysis')` and `shLowLevel.version()`); CHANGELOG `[3.1.0] Unreleased`.
- Releases/DOIs: concept DOI `10.5281/zenodo.21871298`; v3.0.0 version DOI `10.5281/zenodo.21876348`; v2.6.0 `10.5281/zenodo.21871299`. `CITATION.cff` at 3.0.0 — bump to 3.1.0 at the next release.
- **v3.1.0 release tag is PENDING** (choreography: merge open PRs → tag `v3.1.0` → GitHub release with the CHANGELOG section as notes → Zenodo mints the DOI automatically → PR bumping CITATION.cff).
- All tests green on acceptance machine (R2026a Update 4, PCWIN64); ~190 tests. `testUserSuppliedSINEXFiles` filtered unless user drops `.snx` into `tests/test_data/` (gitignored; >30 MB streams estimate-only).
- Namespace is `+shLowLevel` since v3.0.0 (BREAKING rename from `+shx`, error IDs `shLowLevel:*`). `compat/` and legacy suite removed for good.
- Merged PRs #1–#12. Nothing open at handover.

## 3. GitHub collaboration workflow (established, do not reinvent)

- Fine-grained PAT in project file `GitHub_Access_Token`; read with `TOKEN=$(tr -d ' \n' < /mnt/project/GitHub_Access_Token)`. Permissions: Contents RW, Pull requests RW, **Workflows RW** (needed whenever `.github/workflows/` changes). Single-repo, ~90-day expiry from Aug 2026 — expect renewal around Nov 2026.
- Git identity: `Claude (Fable 5) <claude-noreply@anthropic.com>`. Clone to `/tmp/shx_git` (tooling path convention; symlink `/home/claude/shx_build/shAnalysis → /tmp/shx_git` if scripts want it). `[STALE: the generators now derive the root from their own location]`
- **Never touch `main`.** Branch `claude/<topic>` → commit → push → open PR via API → poll `commits/<branch>/check-runs` in a sleep-25 loop → Matthias merges. Required check: `runAllTests (ubuntu-latest)`; 0 approvals; ruleset on main only. `[STALE: required check is now runAllTests (self-hosted)]`
- CI (`.github/workflows/ci.yml`): checkout@v6 → **`python3 tools/help_audit.py` runs BEFORE MATLAB inside the required job** → setup-matlab@v3 (R2026a, cache) → `runtests('tests')` + `assertSuccess`. `[STALE: gates run in their own ubuntu job; MATLAB runs on the self-hosted runner via astrobayer/ci-actions/matlab-probe]`
- CI-red loop: fetch failing log via API (`runs?head_sha=$SHA` → jobs → `/logs`), diagnose from the framework diagnostic, fix, push same branch, re-poll. Distinguish test bugs from implementation bugs before patching — twice a wrong TEST was fixed, not the code (designFilter Noise semantics; poleTide delta pins).
- **Merge conflicts on Claude branches: hand them to Claude.** The one manual resolution (PR #6 "Update branch") kept the wrong side; repair required a tree-wide grep for remnants.

## 4. MCP MATLAB bridge (new this session — use it)

Tools `MATLAB:evaluate_matlab_code` / `run_matlab_file` / `check_matlab_code` reach Matthias's live MATLAB. Toolbox at `C:\Users\matth\Documents\MATLAB\shAnalysis`, fixtures under `...\tests\test_data`.
- Check availability at session start (`version`, `which('shLowLevel.version')`). If absent, fall back to Python ports for validation and his `runAllTests` logs for acceptance.
- **Shadow-package technique** for testing changed functions without touching his checkout: `websave` the raw file(s) into `tempdir/.../+shLowLevel/`, `addpath` that root (packages merge across path roots; first hit wins). Three learned traps: (1) fetch raw files by **commit SHA**, not branch name (CDN caches ~5 min); (2) `+` in raw URLs must be `%2B`; (3) a shadowed function resolves `private/` helpers only from ITS OWN folder — copy every private helper it calls (`webFetch.m` etc.) into the shadow too.
- Always `rmpath` the shadow, delete temp files, and leave his MATLAB stock. Announce that you did.
- Do not hammer `icgem.gfz.de` from his IP — it rate-limits (HTTP 429/tarpit); that was the "fetchICGEM stalls" root cause.

## 5. Toolchain & documentation pipeline

Everything in `tools/dev/` with a README (gate order, regeneration steps, path conventions). Key facts:
- `api_extract.py` parses arguments blocks + help into `api_data.py` (never pipe through `head` — SIGPIPE kills it before the write; redirect to file).
- Example merge step fills empty examples from `api_examples.py` (curated dicts, keys `shLowLevel.*` / `Class.method`), mlints all examples, syncs `docs/apiExamples.json` **preserving run flags** (`shLowLevel.standardChain` is `run=false`).
- `make_apiref.py` → `html/apiReference.html` (generated; never hand-edit). `make_guide.py` → workflow guide PDF (VERSION parsed from Contents.m; copy PDF to `docs/`).
- `fix_help.py` holds the curated OPTDESC/INDESC/OUTDESC dictionaries from the v3.0.1 help sweep — extend there, wording stays consistent.
- `tools/help_audit.py` defines "fully documented": every input mentioned, every option WITH default (ANY line mentioning it may carry the default), Outputs section naming every output with size/type tokens (letter dims `(1,N)` and `matlab.*` types accepted), example in-file or in apiExamples.json. `disp` overrides exempt. Class parser tracks `methods(Access=...)` blocks by indentation.

## 6. Domain/API contracts worth remembering

- `shSeries`: `fromFolder(folder, Pattern="*n96*.gfc*")`, `applyTN14(tn)`, `addDegree1(tn13)`, `gaussian(r)`, `fan`, `destripe`, `applyDDK(W)`, `minus(shSeries|shCoefficients)`, `at(k)`, `mean`, `compare`, `filter("tvANS", ...)` — **filter is tvANS-only**; simple filters are their own methods. Constructor `shSeries(Cs, Ss=, Epochs=)`.
- `shCoefficients(C, S)` positional ctor; `setCoefficient(n, m, Cval, Sval)` (SigmaC on a sigma-less field must pair-initialize sigmaS — invariant). Immutable value classes; history appended.
- `readDDK` W format: `struct(nmax, name, blocks(m, cs 'c'/'s', n, M))`. `designFilter` emits exactly this; **`Noise=` is a COVARIANCE** (implementation does `N = inv(Noise)` per block). `shLowLevel.shIndex` `idx.cs` is NUMERIC 0=c, 1=s.
- `standardChain(folder, ...)`: read → TN-14 → degree-1 → GIA → filter; TN files default to `<dataFolder>/tn/TN-14_C30_C20_SLR_GSFC.txt` and `TN-13_GEOC_<prov>_RL06.3.txt`; explicit `TN14File=`/`Degree1File=` for offline.
- `shReadGFC`: bulk fast path for static bodies (validates sscanf consumed everything, else falls back to the line parser — corrupt-file semantics preserved); variable-term files (gfct/trnd/dot/acos/asin) always take the line parser. 28.6 s → 0.2 s at n720; n2190 in 1.7 s.
- Fetchers: safe-swap everywhere (`.part` → parse-verify → movefile); `Update=` refresh; `BaseURL=` accepts local mirror folders for offline tests. `listITSG`/`fetchITSG(Catalog=)` numbered like `listICGEM`/`fetchICGEM(idx|"all")`. fetchICGEM bulk: `Pause=` 3 s throttle, 429/timeout backoff 30/60/120 s, fail-and-continue with summary, `Quiet=`; **no HEAD preflights** (doubles request rate).
- Love numbers: GROOPS set at `https://ftp.tugraz.at/pub/ITSG/groops/data/loading/` (9 files verified); GROOPS matrix format = 2 header lines + one column, kn from degree 0; fixture `tests/test_data/loadLoveNumbers_Gegout97.txt`, kn(3) = −0.3054020195.
- `synthesisPoints(C,S,GM,R,lat,lon,r, Quantity=, MinDegree=2)`: pointwise with (R/r)^n upward continuation; SI units (×1e5 for mGal). `[STALE: MinDegree is Nmin since v3.33.0]`

## 7. MATLAB traps (each cost real debugging time)

`regexp` 'tokens' returns only outermost groups (flatten nested parens); `regexp` on scalar string returns char not cell (`cellstr` before `cellfun`); `(expr).method` is a parse error; `shLowLevel.f(...).field` is a runtime error (package functions are never variables); `times()` must be real elementwise; `sscanf` fixed-column matrix form needs uniform lines — validate full consumption; `grep -c` returning 0 exits 1 and kills `&&` chains; bash brace-expansion `{a,b}.py` fails inside some quoting — use loops; Python `%` formatting crashes on `%` in MATLAB strings — concatenate; curated Python dicts die with the process — persist into module files; write files then immediately grep a distinctive string to confirm the write landed.

## 8. Open items (approved roadmap + carry-forwards) `[STALE: items 1–4 delivered in v3.2–v3.33; COST-G SINEX dropped (no such product); guide figures real since v3.8]`

1. **Roadmap 8**: iterative forward-modeling leakage correction + gridded scaling factors (next feature item).
2. **Roadmap 9**: scientific regression tests vs published values (Greenland/Antarctica trends etc. against literature, with tolerance bands).
3. **Roadmap 10**: Live Script tutorials generated from the demo registry (D01–D16, `demo_shAnalysis` dispatcher is fail-and-continue).
4. Strategic v3.x: name-value casing standardization (audit-enforced), self-consistent degree-1 estimation, Slepian/arbitrary-region concentration.
5. Carry-forwards: COST-G SINEX fetcher; real mascon validation data; guide map-based figures for D02/D05/D10/D11/D13/D14/D15 (still Edition-2 placeholders); consider honouring HTTP `Retry-After` in fetchICGEM backoff; fetchICGEM remains server-bound slow (by ICGEM's design — document, don't fight).
6. **Immediate housekeeping**: tag + release v3.1.0 (CHANGELOG section = release notes), then CITATION.cff → 3.1.0 with the new date in a follow-up PR.

## 9. New-session checklist `[STALE: superseded by CLAUDE.md §3 — in particular, the token never goes into a URL any more]`

1. Clone: `git clone https://x-access-token:$TOKEN@github.com/matweigelt/shAnalysis /tmp/shx_git` (token via `tr -d ' \n'` from the project file).
2. `git log --oneline -3 origin/main`; check open PRs and release/tag state via API.
3. Read `tools/dev/README.md`; the toolchain runs from the repo now.
4. Probe the MATLAB MCP bridge; if present, acceptance testing is live.
5. Matthias communicates tersely and expects production quality, complete typed help (the CI audit enforces it), Python-validated numerics, and PRs that arrive green after Claude's own CI loop.

*Prepared by Claude (Fable 5), 2026-08-10, session end.*
