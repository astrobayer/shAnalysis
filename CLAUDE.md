# CLAUDE.md — shAnalysis single point of truth

**Status: DRAFT FOR REVIEW. Nothing below is approved. Every work package (WP)
carries an approval box; Matthias ticks it, Claude implements. Final merge
authority stays with Matthias.**

This file replaces the chat-delivered `HANDOVER_shAnalysis.md` as the one
record Claude Code reads first. The handover is retired; its last surviving
full text (2026-08-10, v3.1.0 era) is archived verbatim with staleness marks
at `tools/dev/HANDOVER_shAnalysis_RETIRED.md`, and its still-valid
operational rules are carried into §2–§4 below.
Where this file and any skill or memory disagree, this file is right.
The history behind it - every earlier decision, the full verification
board and the lessons in full - is `tools/dev/RECORD.md`, append-only
(split out in v5.24.1).

Provenance: audit of `astrobayer/shAnalysis` @ `0225c8d3` (main, pushed
2026-09-06), read in a sandbox on 2026-09-08 18:30 UTC by Claude Fable 5.1.
Execution tier during the audit: **Tier B** (no MATLAB MCP bridge reachable;
static reading + Python only; nothing was run in MATLAB). Every finding below
says whether it was *read* or *inferred*.

---

## 1. What the toolbox is (verified state)

| Fact | Value | Evidence |
|---|---|---|
| Version | **6.1.0**, 12-Nov-2026 | `Contents.m` line 2, `CITATION.cff`, `CHANGELOG.md` line 3 agree |
| Branches | `main` only; `claude/getframe-recapture` and `claude/readshm` are gone (merged/deleted) | `GET /branches` |
| Public surface | 3 classes / 108 methods, 140 `+shLowLevel` functions (+6 private), 3 root functions. 96 of the 140 are reachable from a class method; each of the other 44 is a named exception with its reason, and the backlog is empty (v5.24.0) | `tools/dev/api_extract.py`; `tools/dev/class_surface_audit.py` |
| Tests | 5 classes, **495 methods / 509 runs**: Correctness 245, Contract 165, Robustness 63, Science 9, Performance 13 methods (27 runs, `budgetCase` x14 + `nmaxP` x2). On A8 8 filter out in an ordinary run - the optional real-data fixtures and the opt-in full-size closed loop (v5.27.2), 7 on a manual run that sets `closed_loop_nmax` (the GravIS-grid test joined them in v5.8.0, the ESMGFZ check in v5.11.0, the HLSST check in v5.12.0); on MATTHIASPC only 2 do, because `E:\DATAPOOL` supplies the SINEX files, the GravIS folder and - with `SHX_EARTHROTATION_FOLDER` and `SHX_BRIDGE_FOLDER` set for the run, no preference is stored - the ESMGFZ and HLSST series. The counter has matched the runner EXACTLY on the last ten green A8 runs and on every local Tier-A run. | `python3 tools/dev/count_tests.py` |
| Python oracles | 40 `tools/dev/validate_*.py` (+ `regional_oracle_lib.py`, shared by the WP8 oracles) + `tools/audit/*` | listing |
| Docs | **27** hand-written `html/*.html` (24 per-entity duplicates retired in v5.0.1, WP6 stage 3; `regionalBasis.html` added in v5.14.0) + **255 generated `html/ref/*.html`** (one per entity + index, `make_refpages.py`), one shared `html/shAnalysis.css`, `helptoc.xml`, `info.xml`, guide PDF (built by CI and attached to each GitHub release since v5.24.1, not committed - `doc_sync_audit` refuses a tracked copy), generated `html/apiReference.html`. `docs/` holds `apiExamples.json` and, where it was built, the PDF - no HTML page lives outside `html/` (gated). | listing |
| CI | `gates` job on ubuntu (help_audit, doc_sync_audit, no_map_renderer, toolbox_dependency_audit, nv_casing_audit, fixture_tag_audit, gate self-tests `tools/tests/`, `count_tests`, `name_coverage`, `class_surface_audit`, `error_id_audit`, `option_values_audit`, `refpages_audit`, `make_demos --check`, `perf_baseline_audit`) + `runAllTests (self-hosted)` on A8/R2026a; fixtures from tag `fixtures-2026-08` | `.github/workflows/ci.yml` |
| Namespace | `+shLowLevel` (renamed from `+shx` in v3.0.0). Any memory saying `shx.*` is stale. | README §History |

### 1.1 Already implemented — do NOT propose again

Read from `Contents.m`, `README.md`, source. The first audit draft (research
agent, no repo access) listed several of these as gaps; that was wrong.

Numerics: Holmes–Featherstone scaled Legendre recursion to degree 2190
(`legendreALF`), FFT-along-longitude + latitude-parity synthesis
(`shSynthesis Method="fft"`), latitude-banded streaming (`MaxMemGB`), exact
per-order ring analysis and chunked scattered LS (`shAnalysisGrid`),
`gaussLegendre`, Legendre cache, `synthesisPoints`, NEU gradient of any kernel
quantity + full tensor at altitude, exact `legendreALFDeriv`.

Filtering: Swenson–Wahr destriping, Gaussian (Jekeli recursion with
negativity guard), Han fan filter, all 8 DDK files + `designFilter` (build
DDK-class filters from own covariances), **VDK from ITSG monthly SINEX**
(`vdkApply`), tvANS time-variable anisotropic Wiener filter with VCE bands,
block-diagonal fast path, posterior sigmas.

Leakage/regional: `leakageCorrect` (forward model, discrepancy-principle
stopping, `oceanRMS` noise metric), `gridScaling`, `basinScaling`,
`sensitivityKernel` (Swenson–Wahr tailored kernels), `basinKernel`, Slepian
basis + projection, `basinDeconvolve`.

Low degrees / corrections: TN-13, TN-14 (C20 + C30), `estimateDegree1`
(Swenson 2008, self-consistent), `poleTideConvert`, `removeGIA`, GAX/AOD
restore (`fetchGAX`, `restore`), S2/K2/K1 alias removal, `normalFieldCS`,
GM/R rescaling, geodetic↔geocentric.

Uncertainty: `mcPropagate` (independent or full SINEX covariance),
`errorMap` (analytic, Cholesky), AR(1)-corrected climatology sigmas, exact
constrained tvANS posterior, `threeCorneredHat`.

Temporal: Kurtenbach/Kvas Kalman chain (`estimateVAR`
full/diagonal/orderblock, `kalmanFilter` solution + NEQ form, Joseph update,
innovation QC, `rtsSmoother` bounded lag, `neqCombine` VCE on NEQ level,
matfile covariance store).

Applications: Greenland/Antarctica/TWS/ocean/OBP validated chains against
GravIS/AWI, `seaLevelFingerprint` (elastic sea-level equation, mass
conserved), `shSynthesisDeformation` (GNSS **forward**: up/north/east at
stations, CE/CF/CM frame conversion of degree-1 Love numbers per Blewitt
2003), `hydroExtremeIndex` (GRACE-DSI, Reager deficit), EOF analysis and
separation, `combineCenters`, comparison suite (Taylor, NSE, effective
correlation, difference spectra), mascon reader, GRAVIS SHM reader, netCDF
CF-1.8 export, provenance sidecars, geoMap bridge (`toGrid`, `gridHandover`).

---

## 2. Non-negotiable conventions (unchanged, carried from the handover)

- `C(n+1,m+1)` indexing; geocentric latitudes; `legendreALF` takes **radians**.
- No hardcoded physical constants or version strings. `Contents.m` line 2 is
  the only version; `shLowLevel.version` reads it. Defaults
  `GM=3.986004415e14`, `R=6378136.3`, `f=1/298.257223563`, overridable.
- Love numbers always user-supplied (`readLoveNumbers`/`fetchLoveNumbers`).
- **Base MATLAB only** (R2021a+). Enforced by `tools/toolbox_dependency_audit.py`.
  Consequence: shAnalysis may not `import` sibling private toolboxes
  (`lsqvce`, `referenceSystem`, ...). Reuse is by re-implementation or by
  optional, checked dependency in the `requireGeoMap` pattern — never a hard
  dependency.
- geoMap is the single cartographic authority; `no_map_renderer.py` gates it.
- Python numerical pre-validation before MATLAB; the oracle is committed under
  `tools/dev/validate_*.py` in the same PR.
- Provenance stamp on every deliverable: `Developed by Matthias Weigelt with
  the help of Claude (<model>), <date>`; help blocks carry the model line.
- Version bumped together in `Contents.m`, `CITATION.cff`, `CHANGELOG.md`,
  `html/shAnalysis.html`; `doc_sync_audit.py` VERSION check enforces it.
- Semantic versioning: MINOR for new API, PATCH for fixes/docs, MAJOR when a
  documented call or error identifier stops working.

## 3. Session protocol for Claude Code

1. Read this file. Then `git log -3`, open PRs, `Contents.m` line 2.
2. Declare the tier in the first line: **A** = MATLAB reachable on the working
   tree (MCP bridge or local `matlab -batch`); **B** = static + Python only.
   Never report "green" without the tier.
3. One WP = one branch `wp<N>-<slug>` = one draft PR opened immediately
   (`on: pull_request` — no PR, no CI run). One commit per WP row.
4. Gates before push, in this order, all zero findings:
   `python tools/help_audit.py`, `python tools/doc_sync_audit.py`,
   `python tools/dev/no_map_renderer.py`, `python tools/toolbox_dependency_audit.py`,
   `python tools/nv_casing_audit.py`, `python tools/fixture_tag_audit.py`,
   `python tools/dev/mlint_lite.py <changed files>`, `python tools/dev/check_api.py`,
   `python tools/dev/api_audit.py`, `python tools/dev/attribution_sweep.py`,
   `python tools/dev/refpages_audit.py`, `python tools/dev/name_coverage.py`,
   `python tools/dev/class_surface_audit.py`, `python tools/error_id_audit.py`,
   `python tools/dev/option_values_audit.py`,
   `python tools/dev/count_tests.py` (also §5's prediction),
   `python tools/dev/make_demos.py --check`,
   `python tools/dev/perf_baseline_audit.py`;
   then every `tools/tests/test_*.py`.
   **This list must CONTAIN what `ci.yml` runs.** It did not, and CI failed
   on `make_demos --check` at `0ab29b5` while eleven local gates were green.
   Four entries are local-only by design and have no CI step: `mlint_lite`
   (run on changed files), `check_api`, `api_audit`, `attribution_sweep`.
   Regenerate before auditing when help blocks changed:
   `api_extract.py` -> `make_apiref.py` -> `make_refpages.py` -> `make_guide.py`.
5. Predict the test count before running (`runAllTests`) with
   `python3 tools/dev/count_tests.py`; a missed prediction is a finding.
   Do NOT count with `grep -c '^function test'` - it counts the
   script-based entry point and misses `bench*` and parameterised
   methods; it said 261 where the runner ran 268 (A16).
6. Never widen a tolerance to pass. Every tolerance carries a comment naming
   the term it bounds and the oracle it was measured against.
7. Push with `HEAD:refs/heads/<branch>`, read the SHA back with `git ls-remote`.
   Token read from file at call time, never echoed, never in a URL.
8. Close each WP with: a CHANGELOG entry under a **new version heading**
   (`doc_sync_audit.py` requires the top `## [x.y.z]` to equal `Contents.m`
   and rejects any `Unreleased` heading — bump in the same commit), verdict
   per tier, debt named, next action as a command.
9. Regenerate what the version stamps: `tools/dev/make_apiref.py`,
   `tools/dev/make_refpages.py`, `tools/dev/make_demos.py` and
   `tools/dev/make_guide.py` (the last needs
   `pip install -r tools/dev/guide-requirements.txt`). **Four** artifacts
   carry the version, not two: `apiReference.html`, `html/ref/*`,
   `demos.xml` and the guide PDF. All four stamps are gated by
   `doc_sync_audit.py`; `demos.xml` was not until v3.34.1, which is how a
   bump alone shipped a stale one. Since v5.24.1 the guide is NOT
   committed: build it locally to check its stamp (the gate checks a
   built copy, and requires one in CI), and leave it untracked - CI builds
   it on every run and `release.yml` attaches it to the release.

Machine facts: acceptance machine `C:\Users\matth\Documents\MATLAB\shAnalysis`,
data `E:\DATAPOOL\GravityField`; self-hosted runner A8 (R2026a, MinGW64,
16 OpenMP threads, Parallel Computing Toolbox present — which is why the
base-MATLAB rule is gated by source reading, not by the environment).
Composite action `astrobayer/ci-actions/matlab-probe@v1.0.0` (immutable tags).

Acceptance machine, measured 2026-09-09 (each of these cost a wrong turn):
- MATLAB is at `C:\Program Files\MATLAB\R2026a\bin\matlab.exe`. The MATLAB
  MCP tool TIMES OUT on anything suite-sized; run
  `matlab -batch "run('<script>.m')"` detached and read the log instead.
- Two Python interpreters. `python3` is 3.14 and runs every gate;
  `python` is 3.13 and is the one `pip` installs into, so
  `make_guide.py` (reportlab + matplotlib) must be run as `python`.
- The perf machine label is `MATTHIASPC` (upper-cased since v5.3.0 — see
  A23; `COMPUTERNAME` and `hostname` disagree in case here).
- Only 2 tests filter locally rather than A8's 4: `E:\DATAPOOL` supplies
  the SINEX and GravIS fixtures, so those two run for real.

---

## 4. Audit findings (2026-09-08)

Severity: **H** = wrong or misleading for a user; **M** = rot that the gates
do not see; **L** = polish.

### 4.1 Read from the repository (verified)

| # | Sev | Finding | Evidence |
|---|---|---|---|
| A1 | H | **CLOSED v3.33.1** — guide PDF rebuilt at the current version; `doc_sync_audit.py` now reads its page-1 running head (standard library, ASCII85+Flate) and fails on disagreement, fault-injected both ways. Original finding: Shipped guide PDF is stamped **v3.28.0** while the toolbox is v3.33.0. Five releases missing, including the BREAKING `MinDegree`→`Nmin` rename of v3.33.0. The doc_sync VERSION check covers `apiReference.html`, not the PDF. "Stamps are not content" — but here even the stamp is stale. | `docs/shAnalysis_workflow_guide.pdf` page 1 footer |
| A2 | M | **CLOSED v4.0.0** — all six take `arguments` blocks in house casing, and seven `html/` pages were rewritten to `Name=value`. The important measurement: **only `n0`/`N0` -> `Nmin` actually breaks a caller.** Every other rename is case-only, and MATLAB matches Name-Value names case-insensitively, so old call sites keep working — pinned by a test that the old spelling returns the IDENTICAL numbers. `nv_casing_audit.py` now rejects `inputParser` outright, since a function using it is invisible to that gate (which is exactly how these six survived v3.33.0's sweep). `plotSHSpectrum` was the one non-mechanical case: it used `p.UsingDefaults`, which an arguments block has no equivalent of; the legacy `Field` override keeps its behaviour through an empty-string sentinel. | `python3 tools/nv_casing_audit.py` |
| A3 | M | **CLOSED v4.0.0** — the remaining 17 raise sites were swept, all nine affected files gained an `Error identifiers` help block, and `tools/error_id_audit.py` gates ownership with no backlog. Two were wrong in ways the audit had not seen: `gridHandover`'s warning named `shCoefficients:toGrid` although `shSeries.toGrid` calls it too, and `writeFrames` raised `shLowLevel:writeAnimation:*` beside its own `shLowLevel:writeFrames:badSize`. **PARTIALLY CLOSED v3.33.1** — `shSynthesisDeformation` now raises `shLowLevel:shSynthesisDeformation:*`, documented in its own ERRORS block and pinned by `testDeformationIDs`. The rest stays open, and is wider than stated: see A15. Original finding: Error-identifier ownership is inconsistent: 147 identifiers are `shLowLevel:<fn>:<reason>`, but 12 are two-part (`shSynthesis:badP`, `shReadGFC:noData`, `shEvalGFCT:epochOutside`, `shSpectralCrossover:missingField`, `shAnalysis:geoMapRequired`), and `shSynthesisDeformation` raises `shSynthesis:*` identifiers — a caller cannot catch by owner. | `grep -ho "error('[A-Za-z:]*'"` |
| A4 | M | **CLOSED v3.33.1** — and much wider than stated — 13 files in `+shLowLevel` (Outputs, Options AND Inputs) and 52 class methods, 65 help blocks in all. Repaired against the source, not against either block: `readTN14`, `parseGraceFilename`, `resolutionMap`, `shAnalysisGrid`, `basinDeconvolve`, `buildSignalCov`, `vceRescale`, `mcPropagate` all documented fields, shapes or formulas the code does not produce. `help_audit.py` v3.0.2 rejects duplicate and below-the-footer sections; `fix_help.py` (the writer that injected them) refuses to add a second one. Original finding: Seven help blocks contain **two** `Outputs` sections (`errorMap`, `mcPropagate`, `parseGraceFilename`, `readTN14`, `resolutionMap`, `shSynthesis`, `shSynthesisDeformation`). `help_audit.py` checks presence, not uniqueness, so this passed. | sandbox scan of help blocks |
| A5 | M | **CLOSED v3.33.1** — `docs/apiReference.html` deleted — nothing wrote it or read it. `doc_sync_audit.py` now fails on any HTML page outside `html/`, fault-injected. Original finding: `docs/apiReference.html` is a byte-identical copy of `html/apiReference.html`. Two locations, one authority rule violated; nothing compares them. | `cmp` |
| A6 | L | **CLOSED v3.33.1** — README points at `ci.yml` instead of naming a tag it would have to keep in step (`fixture_tag_audit.py` already gates the tag itself). Original finding: README line 108 still says CI "pulls the orphan branch 'testdata'"; CI has pinned the tag `fixtures-2026-08` since v3.26.1/ci v2.9.0. | `README.md`, `ci.yml` |
| A7 | M | **CLOSED v3.34.0**, and partly wrong as written — `demos.xml` now exists, generated from the `demo_shAnalysis` registry (16 cases, gated both ways), and the Help browser reaches a page per entity via `html/ref/index.html`. The search database was **never missing as a capability**: `setup_shAnalysis(Docs=true)` has always run `builddocsearchdb` on `html/`; only the built index is absent from the repo, deliberately (a binary artifact belongs on the machine that searches it). No second option was added. **Unverified in Tier B**: whether `builddocsearchdb` descends into `html/ref/` — confirm on the acceptance machine. Original finding: `doc` integration is incomplete: no `helpsearch-v*` database, no `demos.xml`, `info.xml` present. | `ls html/` |
| A8 | M | **CLOSED v3.34.0** — all 250 pages link one `html/shAnalysis.css`; the inline blocks turned out to be ONE stylesheet copied fifty times (49 byte-identical + one in the generated reference), so merging them lost nothing, and `make_apiref.py` emits the link so the copy cannot return. 46 structural headings renamed to one spelling. `doc_sync_audit.py` gates the stylesheet, the link and the heading vocabulary; `refpages_audit.py` gates the generated skeleton. Original finding: The 50 hand-written `html/` pages use five different heading vocabularies for the same thing ("See also"/"See Also", "Outputs"/"Output Arguments", "Example"/"Examples", "Inputs / Outputs", "Options") and each page inlines its own `<style>` block (no shared stylesheet). 196 API entities have a dedicated page only inside the 304 KB monolith. | heading histogram over `html/*.html` |
| A9 | M | **CLOSED v5.4.1.** Every lane it names - `legendreALF`, `shSynthesis`, `shAnalysisGrid`, `applyDDK`, `leakageCorrect`, the Kalman step - now has a budget on A8 that fails CI on a 1.3x regression, which is the finding's own wording. The road there: v5.3.0 refuted a global 1.3 (a 23 ms workload swung 1.306 on A8, untouched); v5.4.1 found the cause - small-grid multithreaded BLAS (one thread was 1.32x faster and steadier) - and replaced four workloads with sizes where threading pays. Eight are tight at `TightFactor` 1.3 (A8 spreads 1.002-1.072); the rest are small by construction or are crossover brackets and stay at 3x. Stated limit: a desktop moves ~1.2x between sessions, so the 1.3x guarantee holds on A8, the CI gate; on a workstation the budgets err loose. | `tests/perf_baseline.csv` |
| A10 | L | **CLOSED v3.34.1** — and the finding was **larger than recorded**: 13 package functions plus **22 public class methods** (A18). `tools/dev/name_coverage.py` measures it now, over the whole public surface, with comments stripped so a name in a `% see also` line does not count; it states its own reach in its last line (naming is not exercise). 32 new tests, each asserting a property the function's own help states. One allowed exception, `runAllTests`, with its reason in the gate. Original finding: package functions never named in `tests/`, coverage by name not measured. | `python3 tools/dev/name_coverage.py` |
| A17 | M | **CLOSED v3.34.1** — `gridHandover` continues its signature with `...`, so `api_extract.py` (single-line regex) parsed the file to NOTHING: no entity in `api_data.py`, no reference page, while `apiReference.html` sent the reader to "as built by shLowLevel.gridHandover, which documents every field". `refpages_audit`'s COVER check compares pages against that same artifact, so it was silent by construction. **Four parsers of the public surface exist; two were blind the same way and agreed with each other** — which is why the new SURFACE check in `doc_sync_audit.py` compares against the FILESYSTEM (MATLAB's file/function rule is ground truth), not a second parser. `api_extract` now refuses to write an incomplete artifact. Pinned by `tools/tests/test_api_extract.py` (5 of 7 fail pre-fix). | `python3 tools/doc_sync_audit.py` |
| A18 | M | **CLOSED v3.34.1** — A10's blind spot was not only the package: **22 public class methods** were named by no test either — every operator (`plus`, `minus`, `uminus`, `mtimes`, `times`), `disp` on all three classes, `compare`, `fan`, `spectrum`, `triangle`, and eight `shClimatology` methods. Operators were deliberately NOT allowlisted: they are callable by name, and a test checking `plus(a,b)` against `a + b` is stronger than one checking either alone. | `python3 tools/dev/name_coverage.py` |
| A19 | M | **CLOSED v4.0.1** — `tools/dev/option_values_audit.py` reads `api_data.py`, where each option already carries its OWN `allowed` set and its OWN help row, so the scoping problem that made the grep useless disappears. The rule is deliberately narrow: only a row's LEADING ALTERNATIVES RUN (pipe-separated quoted values, the house way of writing the choices) is compared against `mustBeMember`; a row without one documents prose and is not checked. 42 of the 61 restricted options carry such a run. Verified against the historical defect: fed `opApply`'s pre-v3.34.1 row it fires, fed the fixed row it is silent, and it stays silent on the three shapes that made the naive version lie — another option's value quoted in prose, a parenthetical inside the run, and a numeric member list. **A false finding was nearly recorded here**: a probe of mine reported `readLoveNumbers`' allowed set as `[', ']`, which looked like an extractor bug; it was my own regex matching the gap between `""` and `"CE"`. The stored value was correct all along. Original finding: | `opApply`'s help offered `mode` values `'apply' | 'applyT'` that the arguments block rejects (`'forward' | 'transp'`) — the same help block's syntax lines had it right. Fixed and pinned in v3.34.1, found while writing the A10 test, not by any gate. **The general check is not built**: a crude scan (any quoted word on a comment line naming the option) produced 25 hits of which 24 were false positives — output-field docs, prose, and the wrong method's options in a class file. A correct gate must scope each help row to its OWN arguments block; `api_data.py` already carries exactly that pairing (`args[].validators` + `args[].desc`), so the instrument is cheap — it just has to be written against the scoped data, not by grepping. | `grep -n "mustBeMember" +shLowLevel/*.m` |
| A20 | M | **CLOSED v4.0.2** — and the recorded count was wrong: the backlog held **208** identifiers, not 165; nobody had measured it. All 61 files carry an `Error identifiers` block written against the raise site and its guard, the writer refusing any file whose documented set was not exactly the set the file raises. `UNDOCUMENTED` is drained to empty, so the DOCUMENTED rule holds with no exemption, and the gate now reads the root functions too. Two things surfaced that the finding did not name: `demo_shAnalysis` raises `demo:unknownCase` as well as `demo:casesFailed` (both now `shAnalysis:demo:*`, a PATCH — neither was documented anywhere), and `setup_shAnalysis` BUILDS five identifiers at runtime (`"shAnalysis:setup:no" + locs(li,1)`) that no scan of the file can name. Read as a literal that invents `shAnalysis:setup:no`, which nothing raises — which is exactly what the extended gate reported first. A concatenated literal is now a PREFIX: the help must document at least one identifier under it, because the gate cannot enumerate them. | `python3 tools/error_id_audit.py` |
| A21a | M | **CLOSED v4.0.3** — 31 public methods across the three classes document every identifier they can raise. A class needed a different instrument, not a wider loop: identifiers belong to METHODS, and four of them are raised by PRIVATE helpers (`checkPair`, `checkEpochs`, `assertClean`, `rangeToYears`) where `help` cannot reach. The rule follows REACHABILITY, one hop — a public method documents what it raises plus what the private helpers it calls raise — and the one-hop depth is CHECKED, not assumed: a private helper calling another makes the gate say the rule has gone too shallow. The map caught a distinction prose would have blurred: `plus` calls `checkEpochs`, `minus` does not (a difference has no single epoch, so it sets `epoch = NaN`). Nine fault injections, both directions. | `python3 tools/error_id_audit.py` |
| A21b | M | **CLOSED v5.0.0** — 29 two-part identifiers became 46 three-part ones across 47 raise sites, each rewrite scoped to the function it sits in: one old id maps to SEVERAL new ones (`shSeries:noEpoch` to four, `shCoefficients:badInput` to four), which is why a repo-wide replace would have been wrong — A15's lesson, applied per raise site. The middle segment is the raising PUBLIC method, constructor included, with one deliberate exception: the four private shared checks carry a stable CONCEPT segment (`operands`, `stack`, `range`) instead of the helper's own name, so renaming a private function is not a breaking change. The gate now PROVES the middle segment names either a method of that class or a declared shared check, so three-part is a rule and not a spelling convention. 47 test pins were remapped BY LINE to the method each call actually reaches. | `python3 tools/error_id_audit.py` |
| A22 | H | **CLOSED v5.3.0** — `synthesisPoints`'s `auto` sent every station list below 150 points down the SLOWER path. `ClenshawFrom = 150` was the crossover of the numpy prototype, transplanted to MATLAB where **there is no crossover at all**: `benchPointsCrossover` timed both summations on the SAME points and `clenshaw` won at every count measured — P = 1..2000 at nmax 60 and 120, P = 1..200 at nmax 360 — by 2.3x at the narrowest margin and 37x at a single point. The cause is structural: `direct` is bounded by `legendreALF`, which `clenshaw` never calls, so the margin GROWS with degree. Confirmed independently on A8 by the n50/n60 matched pairs, both in the SAME run (`b65f9a2`): 3.56x at 50 points, 6.99x at 200. The run before it put the 200-point pair at 4.61x, which is the between-run spread these small budgets are known for — the direction is what is reproducible, not the factor. Default is now 1, so `auto` is `clenshaw` everywhere; the option stays because `direct` is the bitwise path. `testSynthesisPointsAutoPicksTheFasterPath` needed NO edit — it pins the rule while driving `ClenshawFrom` by hand, which is exactly what that design bought. | `benchPointsCrossover` |
| A23 | M | **CLOSED v5.3.0** — one machine had two labels. `machineId()` read `COMPUTERNAME` (`MATTHIASPC`) before falling back to `hostname` (`MatthiasPC`), so which label a baseline row needed depended on how MATLAB was launched. The failure is silent by construction: a row that misses does not FAIL its budget, it FILTERS it, so the machine looks green while guarding nothing. Label is now upper-cased (upper, so the committed `A8` rows are untouched) and `perf_baseline_audit.py` rejects a row that is not, fault-injected both ways plus a digits/punctuation case so the rule cannot reject legal names. | `python3 tools/dev/perf_baseline_audit.py` |
| A24 | M | **CLOSED v5.3.0** — `mlint_lite` could not see a parse error. An edit put a real newline inside an `fprintf` format; the gate reported zero findings and MATLAB refused to parse the whole `testPerformance` class, so every test in it would have VANISHED rather than failed — and a Tier-B session has no other syntax check. **R7** reports a literal running off its line, read off the scanner that already had to know where a literal stops rather than from a second parser (the A17 lesson). Silent on the two legal shapes that look like it: a transpose after a value, and a literal split with `...`. Zero findings across all 149 `.m` files. | `python3 tools/dev/mlint_lite.py` |
| A25 | M | **CLOSED v5.7.0** - `shLowLevel.filterSpec` is the one parser; the eight lanes call it and keep their own identifiers and admitted subsets. Every valid spec is bitwise unchanged on 19 captured outputs (plus 4 from oceanChain and greenlandChain, run on an extracted copy of the old tree and on the new; obpChain not run, for want of GAD data). It was worse than recorded, measured on the old code: `twsChain` turned `"gaussX"` into NaN in 255 of 507 outputs without an error, and four chains took a negative radius as no filter at all. Original finding: The filter-spec vocabulary (`"none"`, `"gauss<radiusKm>"`, `"DDKn"`, a W struct) is parsed in **eight** places: a local `resolveFilter` copied into `leakageCorrect`, `leakageDataDriven` and `gridScaling`, and inline code in `standardChain`, `twsChain`, `gravisRegionChain`, `oceanChain` and `obpChain`. They do not accept the same set - `gravisRegionChain`, `oceanChain` and `obpChain` take only `"none"` and `"gaussN"` - so a spelling one lane learns is silently refused by another, and no gate compares them. The A17 shape: several parsers of one fact. Fix: one `+shLowLevel` resolver every lane calls, each lane stating the subset it admits. A generic class `filter(spec)` was declined for WP7 partly because it would have been a ninth. | `grep -nE 'resolveFilter\|startsWith\(.*"gauss"' +shLowLevel/*.m` |
| A26 | L | **CLOSED v5.7.1** - `twsChain` looks in `<dataFolder>/DDK` first and keeps `ddk` after it, for files placed there by hand. Verified by reading: on Windows, A8 included, the two spellings name one folder, so no test here can tell them apart. Original finding: `twsChain` looks for DDK files in `dataFolder/ddk`; `fetchDDK` stores them in `dataFolder/DDK`. The two agree only on a case-insensitive filesystem, so on Linux or macOS a fetched DDK file is not found there (`DDKFolder` and the GravIS folder still are). Left alone in A25 so that release stayed bitwise. | `grep -n "'ddk'\|'DDK'" +shLowLevel/twsChain.m +shLowLevel/fetchDDK.m` |
| A27 | M | **CLOSED v5.7.0** - `shLowLevel.vdkApply`'s documented `badSize` identifier could never be raised: its message passed `size(N)` to a `%d` slot, so `error` itself threw "Formatted arguments must be scalar". `error_id_audit` saw an identifier raised and documented and could not see that the raise throws; the bitwise test written for `g.vdkApply`, which drives the guard, found it. | `testCoefficientsVdkApplyIsTheLane` |
| A28 | M | **CLOSED v5.7.1** - both ocean chains refuse a missing mask with their own `noOcean`, before any data is read. `obpChain` had the same defect, and a quieter one: read from its code (no GAD data here to run it), an empty mask masked nothing, so the grid kept its land values and the ocean mean came back empty, without an error. Original finding: `oceanChain` documents `OceanMask` as REQUIRED, defaults it to `[]`, and does not refuse it: without a mask it fails with `MATLAB:badsubscript` in its trend fit, whatever the filter. `gravisRegionChain` refuses the same omission with `noOcean`. First misread as a consequence of `Filter = "DDK3"` - the same error for `"gauss445"` and `"none"` is what placed it. | `oceanChain` line 280, run with the preferences' data |
| A29 | M | **CLOSED v5.7.1** - the guide PDF is pure ASCII (reportlab, ASCII85 streams), so git took it for text and `core.autocrlf` rewrote it on a Windows checkout: the pull of #107 inserted 3589 CR bytes and left `startxref` pointing into a stream. Nothing noticed - the committed blob was intact, and `doc_sync`'s stamp check decodes the streams, which ignore the bytes. `.gitattributes` marks `*.pdf` (and the other binary types) `binary`; `doc_sync` now checks the attribute and the xref offset, and the offset check fired on the corrupted copy before it was rebuilt. | `git ls-files --eol docs/` |
| A30 | M | **CLOSED v5.12.1** - the lane refuses NaN too (`shAnalysisGrid:nanInGrid`), and its two NaN-exposed callers refuse under their own identifiers: `leakageCorrect` without a Mask, which reported `diverged`, and `gridScaling` with a NaN model, which returned no finite k, silently. Measured before the fix: one NaN polar cap put NaN into 153 of 289 C coefficients. **PARTIALLY CLOSED v5.8.0** - a grid holding NaN (a land-only model grid, a masked field) reached every coefficient of `shCoefficients.analysis` without an error. The class now refuses it until `Fill = value` says what the gaps mean. The lane `shLowLevel.shAnalysisGrid` still passed NaN through. | `testAnalysisRefusesNaNUntilToldWhatTheyMean`, `testNaNNeverReachesAnAnalysis` |
| A31 | L | **CLOSED v5.8.0** - `readMascon` read its time axis with a pattern of its own that took two-digit months only, so it refused GravIS's `days since 2002-4-18 00:00:00`. `readGrid` needed the same decoding, and a second copy would have been the A17 shape; both now call one private `cfTimeToYears`, and `readMascon` is bitwise unchanged on the real CSR file. | `testCFTimeUnitsAreReadOneWay` |
| A32 | H | **CLOSED v5.13.1** - an audit of the help, the html pages and the guide, asked for by Matthias, run as read-only probes over what the documentation gates do NOT read. With all 19 gates green it found: **wrong for a user** - the README quick start called `clim.amplitudeMap` with five positional arguments (three allowed); ten guide snippets and two html pages assigned `Idx=` and then used `idx`; guide G9 called `shLowLevel.plotSHMap`, removed in v3.32.0; `shSynthesis.html` and `legendreALF.html` called both functions without `shLowLevel.`; `demo_shAnalysis` looked for fetched ITSG data only in the pre-v3.16 folders, so D05/D06 never found a fetch made since (Tier A: 257 months found now, 0 before); six guide paragraphs printed a literal `%%` and one a mangled path; six html pages opened `<body>` twice and one closed `</head>` twice. **Stale** - the refuted "5-20x" on two pages; GIA "treated as exact" (v5.2.0 propagates it); "two" opt-in tests (seven); the pre-v3.16 download layout in five pages, four help blocks and the guide; fixtures "shipped in tests/test_data" (a plain clone has none); "four" suites; "six" CI gates; the guide's Edition 5, "169 unit tests" and two-part identifier convention; `standardChain`'s "DDKn (fetched on demand)". **Missing** - 28 public methods from the three class pages; guide chapters for everything after v3.26 (now 28-32 and G14); 51 of 128 functions in the guide's "Utilities" index (now 5, the utilities). The four probe rules that fire only on defects, and a one-head-one-body check, are gated as `doc_sync_audit` PROSE, fault-injected in `tools/tests/test_doc_sync_prose.py`. | `python3 tools/doc_sync_audit.py` |
| A34 | M | **CLOSED v5.22.0**, as an option - `FitClimatology = "filtered"` on `kalmanChain`, `regionalKalman` and their class routes fits the climatology to a first pass run without one, removes it, filters the residual and restores it. In the 8e closed loop 0.89-1.96 cm grid RMS against the default's 14.5 cm, never more than 2% above `Climatology = false` and better than it with a strong climatology; on the SH basis 0.43 of the default's error at worst with noise above the signal, 0.95-1.00 with noise below it. The default stays `"observations"`, by Matthias's decision, bitwise. Original finding: `Climatology = true` (`kalmanChain`, and `regionalKalman` after it) fits the observation climatology to the NOISY observations and restores it unfiltered, so the climatology's noise comes back in every output. | `tools/dev/validate_climatology_restore.py` |
| A36 | M | **CLOSED v5.23.0**, measured on A8 at `82fabb2`: the three tests ran 0.86, 0.86 and 7.04 s, and the new contract test 17.96 s - 26.7 s where 130 s were, **103 s off every run**. The remainder is not backoff: a refused connection to 127.0.0.1:1 costs about 3 s per attempt on Windows, which is why the 4-attempt half of the contract test, kept to pin that an omitted `MaxTries` is `httpFetch`'s own default, is the largest of them. Original finding: 130 s of the suite's 248 s of test time on A8 (53%) was three OFFLINE tests sleeping: `testICGEMListFixtureAndResolve` 65.5 s, `testFetchICGEMSeriesOffline` 34.0 s, `testFetchProxyPlumbing` 30.3 s, identical to 0.03 s over four runs. Each URL they make fail on purpose paid `httpFetch`'s backoff (4 tries, 2 s base, about 15 s), and `fetchTN`/`fetchICGEM` gave a caller no way to shorten it. v5.23.0 forwards `MaxTries`/`BaseDelay` (no defaults of their own) and the tests pass `MaxTries = 1`. No numerical lane is slow: the largest is `benchPointsCrossover` at 9.9 s. | A8 job logs, per-test durations |
| A37 | H | **CLOSED v5.23.1** - `designFilter` never filtered C, from v3.1.0 on. Its blocks stored `cs` as the char `'c'`/`'s'`, `applyDDK` branches on `cs == 0` (the numeric 0/1 `readDDK` stores), so every block took the S branch; `g.applyDDK(W)`, `ts.applyDDK(W)` and `standardChain(Filter = W)` with a designed W passed C unfiltered. `testDesignFilter` checked the degree RMS of C and S TOGETHER, which the S filtering alone damps. Blocks carry 0/1 now; `applyDDK` refuses any other `cs` (`badBlock`). Found by reading `readDDK`'s help, which also said `'c'\|'s'` - the help was the likely origin of the bug. | `testDesignFilterFiltersBothCoefficients` (bitwise per block) |
| A38 | H | **CLOSED v5.23.1** - `obpChain` could not finish a run: its last line called `shLowLevel.shxVersion`, a name gone since the v3.0.0 rename. Every call that passed the guards failed after the synthesis; the tests reached the guards only. Same release: `readSINEX(Only = "estimate")` returned `sigma` (not `sig`) and ignored `Index`; `hydroExtremeIndex`'s `int8` category turned NaN into -6 (now double, NaN where Z is - Matthias's call, merged). | `testObpChainRunsToTheEnd` |
| A39 | M | **CLOSED v5.23.2** - `tools/dev/fix_help.py` documented a missing default by writing ` (<default>)` after the FIRST mention of the option anywhere in the help. From v3.0.1 (`9bd487f`, the "328 findings to zero" sweep) that left 125 markers in 32 files: syntax lines that are not MATLAB (`setup_shAnalysis(Permanent (false) = true)`) and prose such as `Convert to another (GM (NaN), R (NaN)) reference`, copied into 31 generated pages. `help_audit`'s default check was satisfied by them - it only asks that the default appear on SOME line naming the option. 41 options had no other record of their default and got a proper row. `help_audit` rejects a marker outside the option's own row (`misplaced_defaults`); the writer writes only into that row. A writer that satisfies a gate by putting text where the gate looks is the A12 shape. | `python3 tools/help_audit.py`; `tools/tests/test_help_audit.py` |
| A40 | M | **CLOSED v5.23.3** - a help-versus-code review of all 234 entities, asked for by Matthias, found about 80 places where a help block contradicted its code, with all 18 gates green. Wrong for a user: `gravisRegionChain`'s `sigTrend`/`residRMS` shapes swapped; `shClimatology.periodic(k)` "1 = annual"; `Nmax` for the property `nmax`; five `ts.filter("tvANS")` option rows; inputs the help accepted and the code refused (`ts.at(year)`, `removeGIA(file)`, `restore`/`read` with a folder, `readDDK(folder)`). Corrected with the CODE as the authority, comment lines only; code defects were listed, not bent into the help (A41). | CHANGELOG 5.23.3 |
| A41 | H | **CLOSED v5.23.4** - fifteen code defects A40 recorded. The worst: `twsChain` joined its DDK candidate paths as char rows with `[;]`, a dimension error on every default `Filter = "DDK3"` call (confirmed on A8 by the first test to reach it). Also: `standardChain(OnMissing = "drop")` stopped on an interior table gap; `combineCenters` dropped GM/R and fixed ProductType "GSM" (now kept, mixed types "unknown", mixed references refused); `estimateDegree1` hardcoded R in its basis; `fetchICGEM`, `fetchITSGBackground`, `fetchITSG` (daily Catalog rows now skipped with `dailySkipped` - Matthias's call, merged), `fetchLoveNumbers` (deformation tables, two columns - inferred from the layout in 6.3, pinned on synthetic files); `shSynthesis` Method, `writeGrid` 2-D epoch, `plotSHSpectrum` struct arrays, `demo_shAnalysis(OutDir = "")`, `obpChain`/`oceanChain` Quiet; two opt-in tests now read the stored preference. | 10 tests, A8 445 runs at `b8c487b` |
| A42 | L | **OPEN** - recorded by A40/A41, deliberately not changed: `readSINEX` misreads an estimate line without a std field (needs a file of that layout); `synthesisPoints` quotes 2.0x/34x where A22 says 2.3x/37x (needs a run); `gravisRegionChain` has `rep.basins` for Antarctica only; `standardChain`'s `rep.files` is the raw listing; MaxFailures counts in total. And one test whose reach is unverified: `testStandardChainDropsAnEpochInAnInteriorGap` assumes the TN-13 fixture spans 2017-07..2018-05; if the fixture copy ends earlier it tests the end of the table instead. | CHANGELOG 5.23.4 "Recorded, not changed" |
| A35 | H | **CLOSED v5.20.0** - `estimateVAR` with `Order` >= 2 built its Yule-Walker block matrix from Sigma(i - j) where E[x_(t-i) x_(t-j)'] = Sigma(j - i) belongs: each block transposed. Exact for `Order = 1` and for 1 x 1 blocks, so no default call and no earlier test could see it; a multivariate VAR(2) of a stationary truth (radius 0.76) came back with radius 1.45, missing its own Yule-Walker equations by 0.30 of Sigma(0). Present since the function was written (2026-08-17); `kalmanChain` and `regionalKalman` at `Order >= 2` inherited it. The Python oracles built the matrix correctly and so never disagreed with anything MATLAB was asked; 8i's VAR(2) identity test on A8 is what reached it. | `testEstimateVAROrderTwoSolvesTheYuleWalkerEquations` |
| A33 | M | **CLOSED v5.21.0** - `twsChain` and `gravisRegionChain` (and through it the Greenland and Antarctica chains) take their masks from `readBasin`; `jsondecode` lives there only. **The finding's premise was wrong, measured**: the chains recentre each polygon at its circular-mean longitude, so Loire, Niger and Volta were never broken. The defect was elsewhere - Antarctic basin 302's ring winds once around the pole, and the old rule left the cap south of -88.54 outside: 686 cells of the 1-degree grid differ, net 137,000 km2, 1.2 percent of the Antarctic area. Every other basin agrees cell for cell except two ring-edge cells (Mekong, Volga, distance 1e-14 deg). Pinned by `testGravisChainMasksAreReadBasinRegions`, which keeps the old rule as the captured reference. Original finding: GravIS basin GeoJSON is parsed in four places (`twsChain`, `gravisRegionChain`, `greenlandChain`, `antarcticaChain`), each converting `[lon lat]` rings itself; three rivbas basins (Loire, Niger, Volta) cross lon 0, where `evalMask`'s planar polygon test in `[0, 360)` breaks. | `grep -ln jsondecode +shLowLevel/*.m` |
| A15 | M | **CLOSED v4.0.0** with A3 — `kernelFactors`, `shSynthesisGradient` and `seaLevelFingerprint` now own their identifiers, and the tests that pinned the old names were remapped per raising file (the same old id mapped to two different owners, so a global replace would have been wrong). Original finding: A3 is **wider than the audit's 12**: `kernelFactors` (`shSynthesis:missingLoveNumbers`, `:badQuantity`, `:heightInvalid`), `shSynthesisGradient` (`shSynthesis:badInput`) and `seaLevelFingerprint` (`shSynthesis:missingLoveNumbers`) also raise identifiers they do not own. Unlike `shSynthesisDeformation`'s, these ARE documented and pinned by `testContract`/`testCorrectness`, so renaming them is a MAJOR change. Belongs in WP1's identifier sweep, not in a patch. | `grep -rn "shSynthesis:" --include=*.m` |
| A14 | M | **CLOSED v3.33.1** — the three gate self-tests in `tools/tests/` (committed in v3.32/v3.33) were **never run by CI**, and `test_legacy_name_tolerated` had been broken since the v3.33.0 sweep drained `LEGACY` to empty — an untested instrument, silently. CI now runs `tools/tests/`; the stale test asserts the mechanism with a temporary entry instead of pinning a member name. | `.github/workflows/ci.yml` before/after |
| A13 | L | **CLOSED v3.34.0** — the km conversion is the `RadiusKm` option, default unchanged at 6371 so no number moves, documented as the MEAN radius (deliberately not the coefficients' reference radius 6378.1363 km) and overridable. Pinned by `testResolutionMapRadiusIsAChoice`, a metamorphic test: the angular half-widths are radius-invariant, every km figure scales exactly with it, and `anisotropy` — a ratio — does not. That test also removes `resolutionMap` from A10's never-named list. | `+shLowLevel/resolutionMap.m` |
| A16 | M | **CLOSED v3.34.0** — the **test count in this file was wrong** and so was the v3.33.1 prediction. `grep -c '^function test'` counts the script-based harness entry point as a test and misses every `bench*` method and every parameterised expansion: it said 261, the prediction said 262, the self-hosted runner ran **268**. `tools/dev/count_tests.py` now reports methods and runs per class, expands `TestParameter`, and exits non-zero on `--executed` mismatch; CI prints it. | PR #95 `runAllTests (self-hosted)` log vs `count_tests.py` |
| A12 | M | **CLOSED v3.34.0** — `help_audit.py` checks struct output fields in BOTH directions: documented ⇒ assigned, and assigned ⇒ documented. **Every one of the 96 documented struct outputs is now covered**: 79 carry a field list verified against the source, 17 name the function that builds them (delegation), **0 are prose**. The sweep found **eleven** help blocks naming fields the code does not produce — `shIndex`'s `nmax`/`Nmin` (the FIELDS are `Lmax`/`minDegree`, so `idx.nmax` errored), `shReadGFC`'s `tide` (it lives in `header.tide_system`), `readSINEX`'s `header`, `gravisL2B`'s `files`, and the eight found by hand in v3.33.1 — plus 55 fields the code returns that the help never named. A mechanical prose→list rewrite was written and **discarded**: it produced confident nonsense (`'full-blocks'` split at a field name, nested struct-array subfields hoisted), so all 79 were converted by hand against the source. | `python3 tools/help_audit.py` (last line) |
| A11 | L | **CLOSED v3.33.1** — `Contents.m` is 78 lines; the 74 'New in v…' sections moved to `CHANGELOG.md`. The six versions that existed ONLY in `Contents.m` (v2.1, v2.2, v2.3, v2.4, v2.4.1, v2.4.2) were written into the changelog in the same commit and the version sets were diffed to prove nothing was lost. Original finding: `Contents.m` (1149 lines) is a full changelog duplicate: "New in v…" sections for 60+ releases, out of chronological order (v2.5 after v2.4.2, v3.1.0 inside the v2.4.1 block). `help shAnalysis` prints all of it. The CHANGELOG is the authority; Contents.m should carry the product line, the class overview and the quick start only. | `grep -n "New in" Contents.m` |

### 4.2 Inferred (needs Tier A measurement before any decision)

| # | Topic | What was read | What must be measured |
|---|---|---|---|
| B1 | **MEASURED, NOT BUILT v5.12.2** - the latitude-first recursion is 1.11-1.69x faster raw and 0.92-0.99x as a drop-in (the permute back), below WP2's 2x bar; bitwise identical. Original: `legendreALF` writes every `P(n+1,m+1,:)` into a 3-D array with page stride `(nmax+1)^2`; the inner `for n` loop touches `nlat` non-contiguous doubles per iteration. A `(nlat, n1*(n1+1)/2)` packed layout or per-latitude 2-D slabs is typically 2–5× faster in MATLAB. | source | wall time n=96/180 lat and n=720/1441 lat, 15 repeats, median ratio |
| B2 | `shSynthesis` forms the full `P` (or streams bands) and reduces with `sum(KC .* Pk, 1)` per latitude — two `(n1×n1)` dense passes per latitude. A Clenshaw/per-order recursion needs no `P` and is the standard for point synthesis (`synthesisPoints`, station lists). | source | same protocol; expected win largest for scattered points |
| B3 | **ADDRESSED v5.5.0 (WP3)**: `Surface = "ellipsoid"` in synthesis and gradient, the radius from `shLowLevel.ellipsoidRadius`. Measured, the ellipsoid lies 21.4 km inside the sphere at the poles and (R/b)^(n+2) there is 1.23 at n 60 and 1.84 at n 180. Original: Evaluation surface is a sphere of radius `R` (+ scalar `Height`). Evaluating on the ellipsoid surface `r(φ)` (latitude-dependent height in the existing `(R/r)^p` law) is not offered. For geoid/gravity users the sphere approximation leaves a known ~few-cm/mGal signature at high latitudes. | `kernelFactors`, `shSynthesis` | closed-form check against ellipsoidal reference values (Python oracle) |

### 4.3 Missing functionality (keyword scan, 0 hits in source → verified absent)

| # | Capability | Why it belongs here | Nearest existing building block |
|---|---|---|---|
| C1 | *(moved out to a GNSS toolbox, 2026-09-10 - see WP4)* **GNSS inversion** (displacements → loading coefficients / TWS) and **joint GRACE+GNSS** estimation | forward exists (`shSynthesisDeformation`), inverse does not; the joint NEQ combination machinery (`neqCombine`, VCE) exists | `shAnalysisGrid` ("ls" mode), `neqCombine`, `vceRescale`, `slepianBasis` |
| C2 | *(moved out to a GNSS toolbox, 2026-09-10 - see WP4)* GNSS time-series I/O and station-wise comparison metrics (WRMS reduction, annual amplitude/phase, correlation with `effectiveCorr`) | today a user must write the reader and the metrics | `compareSeries`, `effectiveCorr`, `fitDeterministicModel` |
| C3 | Earth-rotation excitation (χ1, χ2 from C21/S21; ΔLOD from C20) | degree-2 is the best-determined GRACE signal; standard in SHBundle/GRAMAT lanes | `shSeries`, `poleTideConvert` conventions |
| C4 | Data-driven leakage correction (Vishwakarma et al. 2017) | model-independent alternative to the forward-model lane; "data-driven" appears only for the tvANS covariance | `leakageCorrect`, `basinKernel`, `shGaussianFilter` |
| C5 | GIA as an ensemble (mean + per-coefficient σ, e.g. Caron 2018) propagated into basin sigmas | `removeGIA` takes one deterministic rate field | `removeGIA`, `mcPropagate` |
| C6 | Swarm / kinematic-orbit series for the 2017–2018 gap | `listICGEM` already lists Swarm series; reading them is untested, gap-bridging (rescaling to GRACE noise) does not exist | `fetchICGEM`, `combineCenters` |
| C7 | Hydrological-model comparison (GLDAS/WGHM netCDF → grid → `shCoefficients.analysis` → same filter as GRACE) | needed for scaling factors and for C4; `analysis` exists, the reader/regridder does not | `writeGrid` (netCDF write exists; read does not) |
| C8 | Clenshaw summation / MEX-OpenMP option / single precision | none present; MEX is optional-only under the base-MATLAB rule (pure fallback mandatory) | B1/B2 |

### 4.4 Documentation vs the MathWorks layout

MathWorks reference pages have a fixed skeleton: title + one-line H1 →
**Syntax** (one call form per line, each a link) → **Description** (one
paragraph per syntax) → **Examples** (collapsible, runnable) → **Input
Arguments** (positional, then *Name-Value Arguments* with `Name=value`
form, type, default) → **Output Arguments** → **More About** → **Algorithms**
→ **References** → **Version History** → **See Also**. Category pages list
functions in a two-column table (name | H1 line). The browser needs
`info.xml` + `helptoc.xml` + `builddocsearchdb(<html>)` → `helpsearch-v4`
(R2022a+), and `demos.xml` for the Examples tab. shAnalysis has the first two
(A7) and a page skeleton that varies per page (A8). The existing generator
already parses every help block into `api_data.py`; the missing step is a
per-entity page template, a shared CSS and the search database.

---

## 5. Work packages (proposals — tick to approve)

Every WP below states: goal, scope, acceptance, tests (categories per
`scientific-toolbox-discipline`), oracle, dependencies, size, version. Sizes:
S ≤ 1 session, M 2–3, L 4–6, XL > 6. "Oracle" names what the result is
checked against that was not built here; a WP without one is not ready.

Proposed order: WP0 → WP1 → WP6 → WP2 → WP3 → WP4 → WP5 → WP7. WP0/WP1/WP6
are hygiene and can run in one release train (3.34.0 or 4.0.0, see WP1).

### WP0 — Record and hygiene   `[x] DONE in v3.33.1` (2026-09-08)
- **Goal**: this file becomes the single point of truth; the rot in §4.1 is
  removed and made impossible to recur.
- **Scope**: commit `CLAUDE.md`; delete the retired handover reference in
  CHANGELOG line 82 wording ("from the v3.28 handover" → "from CLAUDE.md
  §…"); fix A4 (7 duplicate `Outputs`) and extend `help_audit.py` to reject
  duplicate section headers; fix A5 (delete `docs/apiReference.html`, or make
  `make_apiref.py` write both and `doc_sync_audit.py` compare them); fix A6;
  A1: regenerate the guide PDF and add a VERSION check of the PDF footer to
  `doc_sync_audit.py` (parse page 1 text; fails if ≠ `Contents.m`); A3 partial:
  `shSynthesisDeformation` gets its own identifiers (its callers are
  `g.deformation` tests — update); A11: move the "New in v…" history out of
  `Contents.m` into `CHANGELOG.md` (check no entry is lost by diffing the two),
  keep product line + class overview + quick start + "see CHANGELOG".
- **Acceptance**: gates zero; `help shAnalysis` < 120 lines; PDF footer
  version = `Contents.m`; fault-injection: a duplicated `Outputs` header and a
  stale PDF stamp each make the gate exit non-zero.
- **Tests**: `contract` (identifiers of `shSynthesisDeformation`), gate
  self-tests in `tools/tests/`.
- **Oracle**: none needed (documentation and tooling).
- **Size**: S–M. **Version**: PATCH (3.33.1) unless bundled with WP1.

### WP1 — Legacy-core modernisation   `[x] DONE in v4.0.0` (2026-09-09)
Approved by Matthias on 2026-09-09 as option (a), the hard break.
- **Goal**: A2 + A3. The six `inputParser` functions get `arguments` blocks,
  `Name=value` options in the house casing (`Quantity`, `Nmin`, `Nmax`,
  `Method`, `MinOrder`, `PolyOrder`, `WindowLength`, `Units`, …) and
  `shLowLevel:<fn>:<reason>` identifiers; the 9 html syntax blocks follow.
- **Scope**: `shSynthesis`, `shDestripe`, `shGaussianWeights`, `shDegreeRMS`,
  `plotSHSpectrum`, `plotSHCoeffTriangle`; `shReadGFC`, `shEvalGFCT`,
  `shSpectralCrossover`, `requireGeoMap` identifiers. Decision needed from
  Matthias: (a) hard break in **4.0.0** (consistent with the v3.0.0 and
  v3.33.0 precedents, no shim), or (b) one release with a shim that maps the
  old lowercase names and raises the old identifiers with a deprecation
  warning. Recommendation: (a) — the class methods already hide these calls
  and a shim doubles the surface the gates must check.
- **Acceptance**: `grep -l inputParser +shLowLevel` returns nothing; every
  raised identifier is documented in that file's ERRORS block and starts with
  `shLowLevel:`; `nv_casing_audit.py` extended to fail on any lowercase
  option name; bitwise-identical numerical output before/after
  (`metamorphic` test against frozen fixtures of v3.33.0).
- **Tests**: `contract` for every renamed option and identifier; `metamorphic`
  old-vs-new on the shipped fixtures.
- **Oracle**: v3.33.0 outputs frozen into `tests/test_data` (fixtures tag
  bump `fixtures-2026-09`).
- **Size**: M. **Version**: MAJOR (4.0.0) under (a).

### WP2 — Speed budgets, then speed   `[x] STEP 1 DONE, A9 CLOSED (v5.4.1); STEP 2 B2 DONE (v5.1.0), CORRECTED (v5.3.0); B1 MEASURED, NOT BUILT (v5.12.2)`
Approved by Matthias on 2026-09-09 ("Go ahead with WP2"), which
supersedes the "A9 is ok" acceptance recorded the same day.

**v5.3.0 closed the two halves that needed a machine.** The acceptance
machine has baselines for all fourteen budgets, so WP2's "green on both
machines" is satisfied for the first time; and B2's dispatch constant was
re-measured IN MATLAB, where the crossover it encoded turns out not to
exist (A22). The budget factor stopped being a specification and became a
measurement — two of them, because one number could not serve a set that
holds both 171 ms guards and 0.8 ms crossover brackets. A9 is still open;
see its row for the specific remaining work.

**Step 1 shipped in two halves.** v5.0.2 built the HARNESS (ten
budgets, 15 repeats, median against 3x a per-machine baseline,
`perf_baseline_audit.py`, 24 self-tests) with every budget FILTERING,
because a budget cannot be asserted before it has been measured.
v5.0.3 committed the BASELINES that A8 then measured, drained
`NO_BASELINE`, and the budgets assert.

**A9 is downgraded, not closed**, and the reason is the factor rather
than the machinery: 3x catches a blow-up, not the 1.3x creep A9 names.
The statistic that would justify tightening it is the BETWEEN-run
spread, and one run cannot measure it. Do not tighten from the
within-run figures the first run produced (median/min <= 1.043 above
20 ms) — they describe 15 repeats inside one process, not two runs on
a shared machine.

**Step 2, row B2: DONE in v5.1.0.** `synthesisPoints` gained
`Method = "auto" | "direct" | "clenshaw"`. Measured in
`tools/dev/validate_points_clenshaw.py` against the per-point code it
replaces: `direct` (batched Legendre, BITWISE) 52-61x, `clenshaw`
(per-order lumped coefficients, no `Pbar` ever formed) 68-356x over
three configurations (nmax 60 at 200 and 2000 points, nmax 120 at
2000). On A8 the 2000-point clenshaw case measured **0.0221 s against
the retired path's 2.2829 s - 103x**; the MATLAB win is smaller than
numpy's because MATLAB's array ops were never the bottleneck. The two
shipped paths cross between 100 and 200 points at BOTH nmax 60 and 120 —
the crossover barely moves with degree, which is why `ClenshawFrom` is
one scalar (150) and not a rule in `nmax`. **That 150 is numpy, not
MATLAB**, and both paths are budgeted so A8 can replace it.

**Two things that did NOT need changing, checked rather than assumed.**
The GRID default was already the faster one: `shSynthesis`'s `auto`
picks FFT for any uniform full-circle longitude vector, measured at
1.40x direct in v5.0.3 (where `benchSynthesisFFTvsDirect`'s comment had
claimed 5-20x). And `shSynthesisDeformation` does NOT share the
per-point pathology — it calls `legendreALFDeriv` once with the whole
latitude vector. An earlier note in this session said the restructure
applied to it; that was wrong.

**B1 (packed Legendre) is the weaker candidate** on the v5.0.3 numbers:
`legendre_n720` is 0.285 s against `synthesisPoints`' 2.28 s.

Two deviations from the scope below, both stated rather than smuggled:
the budget is an absolute median per machine, NOT a per-repeat ratio
against a calibration workload (a ratio is machine-independent only if
the calibration scales like the workload, and none tracks both a
BLAS-bound reduction and a memory-bound recursion); and the acceptance
machine half of "both machines" is unreachable while the bridge is
gone, so A8 is the only machine that can be calibrated from here.

- **Goal**: A9 + B1/B2. First make speed measurable, then only what the
  measurement justifies.
- **Scope, step 1 (budgets)**: `testPerformance` gains ratio budgets for
  `legendreALF` (n96/n360/n720), `shSynthesis` fft and direct, `synthesisPoints`,
  `shAnalysisGrid` rings, `applyDDK`, one `leakageCorrect` iteration, one
  `kalmanFilter` step; each budget = 3× a baseline measured on the acceptance
  machine and A8 in the same repeat, 15 repeats, median of per-repeat ratios;
  N and provenance in `tests/perf_log.csv`. **Step 2 (candidates, each its own
  row, each measured before built)**: B1 packed/2-D Legendre layout; B2
  Clenshaw path for `synthesisPoints` and station-mode deformation; optional
  `shLowLevel.legendreALF(..., Layout="packed")` only if the win is ≥ 2×.
  Explicitly out of scope: MEX/OpenMP (C8) until a pure-MATLAB row shows a
  hot spot ≥ 30 % of a validated chain's wall time; single precision (no
  demonstrated need at n ≤ 2190 and it breaks the 1e-15 identities the tests
  pin).
- **Acceptance**: budgets green on both machines; any accepted optimisation
  is bitwise (or ≤ 4 eps with the term named) against the current code.
- **Tests**: `speed` (ratios), `metamorphic` (old = new), `precision`
  (addition theorem Σ_m P²_nm = 2n+1 at n=2190, lat 89.99°, existing 3e-11).
- **Oracle**: `tools/audit/audit_alf_ref.json` (50-digit mpmath references)
  for Legendre; `validate_gradient.py` for synthesis.
- **Size**: M (step 1) + M (step 2). **Version**: MINOR. **Tier A required.**

### WP3 — Ellipsoidal surface and accuracy completeness   `[x] DONE in v5.5.0` (2026-09-10)
Approved by Matthias on 2026-09-10 with **self-consistency acceptance only**
("Yes, but you can drop the EGM2008 reference. Self-consistency is fine").
Shipped: `Surface = "sphere" | "ellipsoid"` in `shSynthesis`,
`shSynthesisGradient`, `g.synthesis` and `g.gradient`; the new
`shLowLevel.ellipsoidRadius` as the one place r(phi) is computed. Oracle
`tools/dev/validate_ellipsoid.py` (five claims, every one against an
independent route inside the file). The sphere path is bitwise unchanged on
26 of 26 outputs captured from the pre-WP3 code; with f = 0 and a = R the
ellipsoid path reproduces the sphere bitwise. Three deviations from the text
below, each in the changelog and in 6.1: the geoid is REFUSED on the
ellipsoid (it also needs gamma(phi)), `synthesisPoints` got the helper and
not an option, and the class methods forward `Surface`.

- **Goal**: B3. `Surface="sphere"|"ellipsoid"` in `shSynthesis`,
  `synthesisPoints`, `shSynthesisGradient`: evaluate at `r(φ)` of the default
  ellipsoid (`f` overridable) for every quantity that has a radial law
  (`kernelFactors` already returns the exponent; surface quantities keep
  erroring, as `gradient` does for `up`).
- **Acceptance**: geoid/gravity disturbance on the ellipsoid agree with a
  Python oracle (per-point upward continuation) to 1e-12 relative; the
  `Surface="sphere"` path is bitwise unchanged.
- **Tests**: `precision`, `metamorphic` (sphere path unchanged), `robustness`
  (poles, `Height` + `Surface` combined), `contract`.
- **Oracle**: `tools/dev/validate_ellipsoid.py` (new, numpy); published
  EGM2008 geoid undulations at a handful of points as `reference`.
- **Size**: S–M. **Version**: MINOR.

### WP4 — GNSS lane (C1, C2)   `[-] MOVED OUT` (2026-09-10)
**Moved out of shAnalysis by Matthias on 2026-09-10**, to become a GNSS
toolbox of its own, to be worked on later ("GNSS data need preprocessing";
"Inversion and joint combination shall also be part of the GNSS
toolbox"). Nothing of WP4 was built. The proposal below, the facts
gathered for it and the six questions that were open went into a
handover note that is kept OUTSIDE this repository, by the same
decision. Do not start WP4 here: the reader, the preprocessing,
`compareGNSS`, `invertLoading` and `combineGRACEGNSS` belong to that
toolbox. What shAnalysis offers it is the forward side - the
deformation synthesis (`shSynthesisDeformation`, `g.deformation`), the
Love numbers and their CE/CF/CM frames, and `neqCombine`. The original
proposal stays below as the record.

- **Goal**: close the loop forward ↔ inverse and make station comparison a
  one-call operation. Base MATLAB only; `lsqvce`/`referenceSystem` are not
  dependencies — VCE is already inside `neqCombine`/`vceRescale`, frames are
  in `readLoveNumbers`.
- **Proposed functions** (names/signatures for approval, not final):
  - `shLowLevel.readGNSSSeries(files, Format=("tenv3")|"pos"|"csv") → table`
    with columns `site (string)`, `lat`, `lon` (geodetic deg, converted
    internally), `t (datetime)`, `dN dE dU (m)`, `sN sE sU (m)`, `frame`.
  - `shSeries.deformation(stations, kn=,hn=,ln=, Frame=("CF"), Nmin=1)
    → table` : per-epoch NEU prediction at station list; epoch matching via
    `shSeries.at`; degree-1 handled by the same CE/CF/CM conversion the Love
    numbers carry (GNSS lives in CF, GSM+TN-13 in CM — the function refuses
    when `Frame` and the coefficients' degree-1 frame are not both declared).
  - `shLowLevel.compareGNSS(gnssTable, predTable, Detrend=true, Periods=[1 0.5])
    → stats` : WRMS before/after subtraction, WRMS reduction %, correlation
    with `effectiveCorr`, annual amplitude/phase for both, per site and
    network median.
  - `shLowLevel.invertLoading(gnssTable, Nmax, Method=("global")|"slepian",
    Basis=…, Regularisation=("kaula")|"tikhonov"|"none", Lambda=…, Frame="CF")
    → [shSeries, info]` : per-epoch LS of NEU residuals on loading
    coefficients (design from the deformation kernels
    `R h'/(1+k')`, `R l'/(1+k')` and `legendreALFDeriv`), regularisation via
    the existing Kaula path of `shAnalysisGrid`, posterior covariance
    returned; Slepian variant for regional networks.
  - `shLowLevel.combineGRACEGNSS(neqGrace, neqGnss, …)` : thin wrapper over
    `neqCombine` with the GNSS NEQ built by `invertLoading(…, Output="neq")`.
- **Acceptance**: checkerboard/synthetic-load recovery to 1e-10 in the
  noise-free case; with realistic station noise the posterior σ matches a
  1000-run Monte Carlo within 10 %; frame round-trips exact; on a real
  network (Greenland GNET or Amazon) the WRMS reduction is positive and
  reported, not asserted.
- **Tests**: all seven categories for `invertLoading`; `reference` against
  Kusche & Schrama 2005 / Fu & Freymueller 2012 magnitudes; `robustness`
  (missing epochs, single-component sites, poles).
- **Oracle**: `tools/dev/validate_gnss.py` (numpy: synthetic load → NEU →
  inversion) plus one published station series comparison.
- **Size**: XL. **Version**: MINOR (new API; nothing existing changes).

### WP5 — Geoscience add-ons (C3–C7)   `[x] DONE - 5e v5.8.0, the method of scale v5.9.0, 5a v5.10.0 + v5.11.0, 5d v5.12.0` (tick per row)
| Row | Function | Oracle | Size |
|---|---|---|---|
| 5a `[x]` **DONE v5.10.0 + v5.11.0** (approved 2026-09-10; Chen & Wilson 2003 eq. (1), supplied): `shLowLevel.rotationExcitation` and `ts.excitation`, with the IERS 2010 constants by default and dLOD in ms (ESMGFZ PDD eq. 2.8, read as 2 pi / Omega and confirmed against the observed length of day); checked against ESMGFZ HAM + SLAM by an opt-in test | `shSeries.excitation(kn=…, Convention=…) → table(t, chi1, chi2, dLOD)` from C21/S21/C20 with the IERS 2010 conventions and the Love-number/frame factors; input in the pole-tide convention `poleTideConvert` knows | Chen & Wilson formulas; a published GRACE excitation series | S–M |
| 5b `[x]` **DONE v5.4.0**; its follow-on, the method of scale (`Method = "scale"`, thesis eq. 3.28), **DONE v5.9.0** | `shLowLevel.leakageDataDriven(gridSeries, latDeg, lonDeg, Mask=, Filter=)` - Vishwakarma's method of deviation. **Unblocked by Matthias supplying the author's PhD thesis** (chapter 3, eqs. 3.19-3.29) on 2026-09-09; the row had been STOPPED because the equations were unreachable, and that block was real - two details decide whether the method works and neither is guessable: the deviation integral is weighted by the FILTERED catchment function, and the leakage extrapolation corrects a PHASE while the deviation integral deliberately gets none. Oracle `tools/dev/validate_leakage_datadriven.py`: decomposition closes to 4.3e-15, filter self-adjointness 5.0e-16, phase measure/shift are mutual inverses to 7.1e-15 deg, closed loop removes 63% of the damage (MATLAB 55.3% on the `testCorrectness` fixture, whose grid and basin geometry differ). Three deviations from this row's sketch, all recorded in the changelog: `Filter=` not `Radius=` (matches `leakageCorrect`), a grid stack not an `shSeries` (a class method is WP7), and NOT `leakageCorrect`'s `info` layout - the two return different things, a corrected field against a corrected series. | thesis eqs. + closed loop | M |
| 5c `[x]` **DONE v5.2.0** (the row was never ticked when it shipped; corrected in v5.4.1) | `removeGIA(gia, Sigma=…)` accepting a σ field; σ propagated into `basinAverage` sigmas and `mcPropagate` | analytic vs MC on a synthetic ensemble | S |
| 5d `[x]` **DONE v5.12.0** (approved, and its method set, 2026-09-10): `shLowLevel.bridgeGaps` and `ts.bridgeGaps` - the Kalman-filtered QuantumFrontiers HLSST_SLR_COMB2023s at 750 km, calibrated on the overlap by an offset, a per-degree scale and a per-degree sigma, every month GRACE lacks filled and flagged in the epoch names. Held out and bridged back, the fill's error is 0.38 of the GRACE signal | Swarm: `fetchICGEM` Swarm series read and `combineCenters`-style rescaling to GRACE noise for 2017-07..2018-05; `shSeries.select` gap policy | published Swarm-vs-GRACE degree-RMS ratio | M |
| 5e `[x]` **DONE v5.8.0** (approved 2026-09-10): `shLowLevel.readGrid`, and `Fill` on `analysis`; the real file is the GravIS TWS grid instead of GLDAS | `shLowLevel.readGrid(ncfile, Var=…)` (netCDF → grid + metadata, inverse of `writeGrid`) so GLDAS/WGHM enter `shCoefficients.analysis` | `writeGrid` roundtrip; one GLDAS file | S |
Version: MINOR per approved row.

### WP6 — Documentation to the MathWorks layout   `[x] STAGES 1-2 DONE in v3.34.0, STAGE 3 in v5.0.1; topic categories deferred`

**Stage 1 (done)**: `make_refpages.py` + `html/shAnalysis.css` + the
`refpages_audit.py` gate + `helptoc.xml` entry — 199 pages, one skeleton,
one stylesheet. Items (1), (2) partly, (3) partly, (4) partly.
**Stage 1 measurements that changed the plan**: item (6), per-entity
Version History, FAILS its own >80% bar (74% strict / 81% loose-and-wrong)
and is dropped; item (3)'s "existing tag categories" do not exist in the
data (helptoc-derived mapping: 163/198, 75 in one catch-all), so topic
categories need an editorial decision from Matthias.
**Stage 2 (done in v3.34.0)**: the 50 narrative pages link the shared
stylesheet and use one structural heading vocabulary (A8 closed);
`demos.xml` generated from the demo registry (A7's Examples tab);
`setup_shAnalysis(Docs=true)` already built the search index, so no
`BuildSearch` option was added — the WP proposed something that existed.
**Stage 3 (DONE in v5.0.1)**: approved by Matthias 2026-09-09 as scope
item (7). 24 of the 50 hand-written pages retired; 26 remain. The set was
COMPUTED, not chosen by file name: retire a page only if every entity
stays covered afterwards. 30 qualify; the other 6 are the last narrative
mention of 11 entities. Of the 30, six read as narrative by the WP's own
rule (`standardChain` a chain, `shSeries` a class overview,
`legendreALF`/`seaLevelFingerprint`/`eofAnalysis`/`slepianBasis` theory)
and were kept, leaving 24. **The COVERAGE question did not arise**: since
no entity lost coverage, the check keeps its meaning unchanged. Every
inbound link and helptoc target was repointed at `html/ref/` first.

Original scope below.

- **Goal**: A7, A8; `doc`, `help`, `lookfor` and the Help-browser search all
  work; every public entity has a reference page with the MathWorks skeleton.
- **Scope**: (1) `tools/dev/make_refpages.py`: from `api_data.py` emit
  `html/ref/<entity>.html` with Syntax / Description / Examples / Input
  Arguments / Name-Value Arguments / Output Arguments / More About /
  References / Version History / See Also; the help block is the authority
  (R1) — pages are derived, and `doc_sync_audit.py` diffs generated bodies
  against the help block (content, not stamp). (2) Shared `html/shAnalysis.css`
  modelled on the MathWorks doc look (system font stack, 14 px body,
  `#0076a8` link colour, grey `Syntax` code panel, bordered argument tables,
  collapsible example blocks with plain JS); every page links it; inline
  `<style>` removed. (3) Category pages: Getting Started / Functions (by the
  existing `tag` categories) / Classes / Examples / Release Notes, two-column
  tables (name | H1). (4) `helptoc.xml` rebuilt from the same source;
  `demos.xml` pointing at `demo_shAnalysis` cases and the Live Scripts.
  (5) `builddocsearchdb(fullfile(root,'html'))` runs in the self-hosted CI job
  after the tests and the resulting `helpsearch-v4/` is uploaded as an
  artifact and committed on release (decision: commit or build-on-setup —
  recommendation: `setup_shAnalysis(BuildSearch=true)` builds it locally so
  the repo stays free of binary indexes). (6) Version History per entity from
  `CHANGELOG.md` by name match — "could", only if the match rate is > 80 %.
  (7) Retire the hand-written duplicates where a generated page now exists;
  keep narrative pages (chains, theory) as "More About" links.
- **Acceptance**: `doc shAnalysis` shows the TOC with categories; Help-browser
  search finds `applyDDK`; every entity in `api_data.py` has a page and every
  page has every section (a section may say "None"); zero inline `<style>`;
  headings vocabulary is exactly the MathWorks set (gate).
- **Tests**: gate self-tests; `contract` for `setup_shAnalysis(BuildSearch=)`.
- **Oracle**: MathWorks "Display Custom Documentation" and
  "Create Help Summary Files" pages (R2026a) for the file contract.
- **Size**: L. **Version**: MINOR.

### WP7 — Class surface completeness (UI simplification)   `[x] DONE in v5.6.0` (2026-09-10)
The last of the order agreed on 2026-09-10; its scope was settled by four
answers the same day (6.1). Shipped: `ts.kalman`, `ts.eof`,
`ts.leakageCorrect`, `ts.leakageDataDriven`, `ts.gradient`, `ts.write`,
`g.basinAverage`, `g.errorMap`, and `Surface` through `toGrid` and `map`
on both classes - each a thin delegate pinned BITWISE by `testContract`,
with options and without. The acceptance's reachability clause is
`tools/dev/class_surface_audit.py`, in CI: 69 of 124 public functions
reachable from a class (58 before), each of the other 55 a named
exception (34) or in a backlog that may only shrink (21). Deviations from
the text below, each in the changelog and 6.1: no generic
`shCoefficients.filter` and no `shSeries.chain` (declined by decision);
`deformation` and `excitation` stay with WP4 and 5a, whose functions do
not exist; the "only argument forwarding" gate was not built - the
bitwise tests prove more than a reading of the body could; and the
exception list lives in the gate, not in this file.

**v5.7.0** took the backlog's three cheapest routes - `g.synthesisPoints`,
`g.gradientTensor`, `g.vdkApply` - so 18 lanes remain there; reach is 73
of 125. **v5.13.0** took four more - `poleTideConvert` and
`slepianProject` on both classes, `estimateDegree1` and `combineCenters`
on the series - so 14 remain; reach is 79 of 128. **v5.24.0** emptied
it: seven lanes got nine routes (`basinKernel` and `sensitivityKernel`
on both classes, `g.designFilter`, `g.mcPropagate`,
`ts.signalVarianceKaula`, `ts.basinScaling`, `ts.buildCondFun`) and six
became exceptions (6.1, 2026-10-22); reach is 94 of 134.

- **Goal**: `Contents.m` promises "Classes (single point of access)", but the
  validated chains, the Kalman lane, EOF, leakage, error maps, deformation
  series and export exist only as `shLowLevel.*` calls with C,S,GM,R
  plumbing the user must unpack. Surface them as methods; the low-level
  functions stay as they are.
- **Scope (proposed methods)**: `shCoefficients.filter(method, …)` generic
  dispatch (gauss | fan | destripe | DDK | designed W) mirroring
  `shSeries.filter`; `shCoefficients.basinAverage`; `shCoefficients.errorMap`;
  `shSeries.kalman(…)` → `kalmanChain`; `shSeries.leakage(…)` →
  `leakageCorrect`/5b; `shSeries.eof(…)`; `shSeries.deformation(…)` (WP4);
  `shSeries.gradient`; `shSeries.write(folder, …)`; `shSeries.chain(name, …)`
  → the four validated chains with their provenance report;
  `shSeries.excitation` (5a). Consistent return pattern `[obj, op, info]`.
- **Acceptance**: every method is a thin delegate (no numerics of its own —
  gate: method bodies contain only argument forwarding); `metamorphic` test
  method = low-level call bitwise; `api_data.py` shows every `shLowLevel`
  numerical lane reachable from a class (list of deliberate exceptions in
  this file).
- **Tests**: `contract`, `metamorphic`.
- **Oracle**: none (delegation).
- **Size**: M. **Version**: MINOR.

### WP8 — Regional Kalman with local basis functions   `[~] 8a DONE (v5.14.0), 8b DONE (v5.15.0), 8c DONE (v5.16.0), 8d DONE (v5.17.0), 8e DONE (v5.18.0), 8h DONE (v5.19.0), 8i DONE (v5.20.0), 8j MEASURED (v5.28.1); 8f, 8g POSTPONED` (approved 2026-10-20)
Approved by Matthias on 2026-10-20 in four answers to the review of
Kurtenbach (DGK C-683) and the work since: (1) the state is a set of
LOCAL basis functions (RBF, Slepian), not global SH; (2) the existing
filter is REUSED - `estimateVAR`, `kalmanFilter`, `rtsSmoother`,
`neqCombine` are already generic in the state vector; (3) ALL
observation levels, in the row order below; (4) it is part of
shAnalysis, the basin is selectable, and otherwise a test area.

- **Goal**: Kurtenbach's NEQ-form filter (C-683 eqs. 3.84-3.88,
  3.112-3.113, RTS 3.127-3.129) on the coefficients of a regional
  basis, so that daily or monthly gravity information of every level
  updates one regional state. The outlook of C-683 (local support,
  extra observation groups) and the closed loops of Woehnke et al.
  2025 (RBF, GEM 16:2) and Steffen et al. 2026 (Slepian, IAG Symp.)
  are the starting point.
- **The one design idea**: every basis is a LINEAR MAP `T` from its
  coefficients to SH coefficients (`x_SH = T a`, `P x K`), band-limited
  at the series' nmax. RBF: `T(:,k) = phi_n .* Ybar(x_k)'` (addition
  theorem); Slepian: the tapers `G`; SH: the identity. Everything else
  is then SH machinery the toolbox already validates: an SH solution or
  NEQ enters as `T' N T`, `T' b`; a grid or point functional as
  `A_SH T`; the process model as `estimateVAR` on projected model
  output. **SH with T = I is the oracle**: the regional chain must
  reproduce `kalmanChain` there.
- **Rows** (each its own release, each measured before built):

| Row | Content | Oracle |
|---|---|---|
| 8a `[x]` **DONE v5.14.0** | `readBasin` (GravIS GeoJSON -> wrap-safe region; the basin is selectable by name), `regionalBasis` (RBF on an icosahedral or Reuter grid with a degree-amplitude, Kaula or Shannon kernel; Slepian by threshold or count; SH), `regionalProject` (region-weighted LS projector), class routes `regionalBasis`/`regionalProject` | `validate_regional_basis.py`: node counts, kernel = Legendre series, projector normal equations, projector = `G'` for Slepian, polygon area of the Elbe |
| 8b `[x]` **DONE v5.15.0** (approved 2026-10-20: "Go ahead") | process model in the basis: model series -> basis coefficients -> climatology reduced -> `estimateVAR`; diagnostics (spectral radius, Q PSD, signal variance ratio), Kurtenbach's alpha and ground-noise options | Order 1 = C-683 eqs. 3.84-3.85 on the projected series |
| 8c `[x]` **DONE v5.16.0** (approved 2026-10-20: "Go ahead") | observation adapters to basis NEQs: SH solution + covariance, SH NEQ (SINEX), grid (EWH + covariance, observation area = region + buffer, Woehnke's dO), point functionals (potential, gravity disturbance, gravity vector along a direction, differences of two points = LGD) | `T' N T` against the SH NEQ; grid design against `synthesisPoints` |
| 8d `[x]` **DONE v5.17.0** (approved 2026-10-21: "Go ahead"; the basis is passed in, not built inside - 6.1) | the chain and its single point of access, `ts.regionalKalman(Region=, Basis=, ModelSeries=, ...)`: filter + RTS (reused), output as basis coefficients, EWH grids on the region, basin mean with sigma through T, an shSeries of `T a` | SH basis = `kalmanChain` (machine precision) |
| 8e `[x]` **DONE v5.18.0** (approved 2026-10-21: "Go ahead"; the background built, the observation area measured and not built - 6.1) | regional consistency: remove-compute-restore against a global background (low degrees / outside signal), the investigation/observation/computation areas of Woehnke 2025 | closed loop with signal outside the region |
| 8f `[-]` **POSTPONED** (2026-10-21: the bridge is unavailable, and A8 cannot hold the covariances - 6.1) | closed loop of Woehnke 2025 / Steffen 2026: ESA ESM truth, ITSG-Grace2018 covariance noise, monthly, then daily | their published RMSD 0.62 / 0.58 cm, correlation 0.98 |
| 8g `[-]` **POSTPONED** with 8f (needs the same data machine) | daily real data: ITSG daily NEQs (SINEX) in the basis; the Elbe (2013) and the September 2024 central-European flood as test cases | ITSG daily Kalman product, GravIS basin series |
| 8h `[x]` **DONE v5.19.0** (approved 2026-10-21: "Go ahead in this order: 8h, 8i, A33 and A34") | LGD observations: the point-functional design here; along-track preprocessing, transfer function and noise PSD stay in lgdToolbox, which hands over records (toolboxes stay independent) | lgdToolbox forward model |
| 8i `[x]` **DONE v5.20.0** (approved 2026-10-21 with 8h; the closed loop synthetic, 8f being postponed - 6.1; A35, `estimateVAR`'s Order >= 2, fixed on the way) | adaptive process noise (VCE of Q per block from the innovations, replacing Kurtenbach's hand-tuned alpha), VAR(p > 1), space-domain conditioning through `CondFun` | closed loop of 8f |
| 8j `[x]` **MEASURED v5.28.1** (lgdToolbox D141, Matthias 2026-11-06: "Go ahead with all three of them") | LGD records in a mascon basis with a model-series prior: does the chain give a localised load an honest sigma, and how does it fail (lgdToolbox F171/F175 in this chain). Without a background NO - the global signal the regional basis cannot carry makes sigma too small even for the right model; with 80% of it as `Background`, yes. Isotropic and 5x-too-small models stay overconfident at the point, `EstimateQScale` repairs part, a wrong footprint nothing | `validate_regional_lgd_mascon.py`: filter = dense posterior; 20-seed closed loop |

- **GNSS and terrestrial gravimetry** enter as SH NEQs or point
  records built OUTSIDE shAnalysis: WP4's decision of 2026-09-10 put
  GNSS inversion and joint combination into a GNSS toolbox, and this
  WP does not reverse it - the regional filter only accepts the NEQ.
- **Tests**: per row; `metamorphic` (SH basis = global chain),
  `precision` (projector identities), `reference` (Woehnke/Steffen
  numbers), `robustness` (dateline basins, polar regions, gaps).
- **Size**: XL over the rows. **Version**: MINOR per row.

### WP9 — More from existing observations   `[~] 9a DONE (v5.25.0), 9b DONE (v5.26.0), 9c DONE (v5.27.0), 9d MEASURED (v5.27.2), 9e CHECKED (v5.27.4, desk), 9f DONE (v5.28.0, as pseudo-observations), 9g DONE (v5.29.0, the published SPDE), 9h DONE (v5.30.0), 9i DONE (v5.31.0, from release differences; reviewed v6.0.5), 9j DONE (v6.1.0) - WP9 complete` (approved 2026-10-23)
Approved by Matthias on 2026-10-23 ("Go ahead") on a ranked proposal of
2026-10-22 whose premise was that the toolbox mostly consumes finished
solutions, while much of the information sits in normal equations,
covariances and the series it does not combine. Each row is its own
release, measured before built; the order is the proposal's - the rows
that need no new data first.

| Row | Content | Oracle | Size |
|---|---|---|---|
| 9a `[x]` **DONE v5.25.0** | a second observation group on `kalmanChain` / `ts.kalman` (`SecondSeries`): an HLSST or Swarm series calibrated on the overlap (offset, per-degree scale with the errors-in-variables correction, per-degree noise) and added as a normal equation, so the gap is bridged by the estimator | `validate_kalman_bridge.py`: joint posterior, calibration consistency, closed loop against `bridgeGaps` | S-M |
| 9b `[x]` **DONE v5.26.0** | `shLowLevel.neqClimatology`: the six climatology terms from ALL monthly normal equations, each month's deviation reduced (Schur complement, never inverting N) - instead of fitting filtered solutions. The gain is the month-to-month change of the noise pattern, nil for a constant one; not measured on real NEQs | `validate_neq_climatology.py`: GLS fit with full covariance, joint reduction, closed loop | M |
| 9c `[x]` **DONE v5.27.0** | basin-scale mascons (spherical caps) as a fourth `regionalBasis` type; T analytic: an rbf with the cap kernel c_n / ((2n+1) f_n), coefficients in EWH metres, equal-area default radius. The `readMascon` comparison is debt (no product reachable) | `validate_regional_mascon.py`: c_n against 40-digit values, the column against scipy's Legendre series, area, telescoping centre, projector | S |
| 9d `[x]` **MEASURED v5.27.2** (opt-in, Matthias 2026-10-24): one month at a time, the peak is two P x P - 0.21 GB at nmax 60, 1.32 GB at nmax 96, 2.2 s/month - against A8's 21 GB largest array; memory does not stop 8f there. The loop's honesty RMS is 11.7 / 5.6 without a background (outside signal in the basis) | 8f on A8: measure whether a truncated closed loop (nmax 60, 3721^2 doubles = 0.11 GB per month) or order-block covariance storage fits A8 - measured, then decided | memory and wall time on A8 | S |
| 9e `[x]` **CHECKED v5.27.4, desk only** (approved 2026-10-27: "Go ahead with 9e"): besides ITSG, GFZ publishes monthly RL06/RL06.x NEQs in SINEX to d/o 96 at ISDC, and a Zenodo dataset (PyHawk) monthly reduced NEQs to d/o 60; CNES and AIUB give theirs to COST-G, with no public download found. Nothing built - no second centre's file has been read, and neither this sandbox nor A8 reaches the GFZ hosts (6.1) | normal-equation combination of analysis centres with VCE: `neqCombine` does it already (inside `kalmanChain`'s multi-center mode too); what is missing is DATA - which centres besides ITSG publish usable NEQs. A check first; possibly nothing to build | COST-G combined solutions | M |
| 9f `[x]` **DONE v5.28.0, as pseudo-observations** (approved 2026-10-29: "Go ahead with 9f", then "Also include degree 1"): no public SLR normal equations exist, so `shLowLevel.neqAddCoefficients` adds TN-14 C20/C30 and TN-13 degree 1 (value + sigma) to a GRACE NEQ, extending the index to degree 1. C20/C30 are joint; degree 1 is exactly substitution, the GRACE NEQ carrying no degree-1 information (6.1) | C20, C30 and degree 1 estimated jointly from SLR and GRACE normal equations instead of the TN-14 substitution | blocked on a source of SLR NEQs -> `validate_neq_low_degree.py`: stacked LS, l'Pl, degree 1 = substitution, exact gain against correlation | M |
| 9g `[x]` **DONE v5.29.0** (Matthias 2026-11-06: "Go ahead with 9g"): `shLowLevel.maternCovariance` (Lindgren et al. 2011, alpha 2, Galerkin in SH, local range and sigma as fields) and `ProcessCov` / `StartCov` on `regionalKalman`; HB-STAR's own field parameterisation was not found, so the fields are the caller's (6.1) | HB-STAR's non-stationary SPDE-Matern prior as a Q / Sigma0 option of `regionalKalman` (8i's block scales are its coarse form) | closed-form stationary Matern covariance on the sphere -> `validate_matern_prior.py`: closed form 1.1e-14, constant fields exact, locality within 0.5%, closed loop z-rms 0.98-1.02 | M-L |
| 9h `[x]` **DONE v5.30.0** (Matthias 2026-11-06: "Merge and go ahead with 9h"): `regionalBasis(..., Ocean = ...)` - each column the land part of its function plus its elastic sea-level response, mass zero per column; `out.landMean` on `regionalKalman` | land mass and sea-level fingerprint solved jointly: `seaLevelFingerprint` inside T, mass conserved by construction | closed loop with leakage across the coast -> `validate_sea_level_basis.py`: dense solve 7.5e-15, mass 1.2e-15, ocean bias +5.7/+6.6% removed to 0.6/0.2% of the representation floor | M |
| 9i `[x]` **DONE v5.31.0** (Matthias 2026-11-06: "Merge and go ahead with 9i"): `shLowLevel.backgroundErrorCov` (half the covariance of two releases' differences) and `AddNoiseCov` on `regionalKalman`; no real release pair read here | background-model error (AOD1B, ocean tides) as an additive empirical SH covariance - L2 only, so limited; the full gain is an L1B inversion (HB-STAR) | release differences of the background products -> `validate_background_error.py`: consistent to 0.064, shared error leaves (1 - rho) C, closed loop z-rms 1.38 -> 0.97 | L |
| 9j `[x]` **DONE v6.1.0** (Matthias 2026-11-12: "proceed as suggested"): `shLowLevel.seaLevelBudget` (mass against total - steric, AR(1)-corrected closure at 2 sigma) and `shLowLevel.bprCompare` (a recorder against `obpChain`'s nearest ocean pixel, hPa to cm EWH); no real product read here | validation lane: ocean mass against altimetry minus Argo steric sea level, and against bottom-pressure recorders | the published sea-level budget -> `validate_ocean_validation.py`: identity 4.4e-16, a closed budget closed in 92.8%, a 0.6 mm/yr gap open in 100% of 400 seeds; the published budget is acceptance-machine debt | M |

- **Not here**: L1B processing (range acceleration, accelerometer, LRI)
  belongs to the processing toolboxes and HB-STAR; GNSS to the GNSS
  toolbox (WP4). shAnalysis takes in their normal equations.

### Deliberately not proposed
- MAGIC/GRACE-C/NGGM readiness — no product format exists to read; revisit
  when simulated L2 products are public.
- Replacing the Python doc toolchain with MATLAB `publish` — the gates and
  the guide generator are Python and run without a licence on the ubuntu job.
- ARMA/DAWG filters (Ditmar) — VDK with true monthly covariance covers the
  same need with a published oracle; add only on request.

---

## 6. Records

### 6.1 Decisions (append-only; date, decision, evidence)
Current entries only; every earlier one is in `tools/dev/RECORD.md` §1,
verbatim. An entry moves there when it stops describing the current
state; nothing is deleted.
- 2026-11-12 — **9j built as 6.1.0, WP9 complete.** Two functions, no
  class route (their inputs are means and chain outputs): the budget
  closes when the residual trend is within 2 AR(1)-corrected sigma - one
  design for all three fits, so the residual trend is exactly the
  difference of the two sides; the recorder is compared at the nearest
  OCEAN pixel and converted from hPa with g and rho_w as options. No
  altimetry, Argo or BPR product is reachable here: the published budget
  is debt for the acceptance machine, and no number for it is written.
- 2026-11-12 — **6.0.6, one sea-level equation, proven not argued.** The
  private `sleSolve` serves both callers; `seaLevelFingerprint`'s pre-6.0.6
  body lives verbatim in `testCorrectness` (identifiers renamed) and A8
  must find the two BITWISE equal - the 6.3 rule "capture references
  BEFORE an edit" met without a Tier-A session.
- 2026-11-12 — **The 9i review fixed in one PR, 6.0.5** (Matthias: "Fix
  all of them in a single PR and proceed as suggested", on a plan that
  put all ten findings of a code review of 5.31.0 into one patch). Two
  calls made as recommended: an epoch that pairs with two is REFUSED
  (`ambiguousEpochs`) rather than paired silently - a duplicated month
  is a data defect; and only the `AddNoiseCov` path factorises a
  constant noise covariance once - the older constant-noise paths keep
  their per-epoch `regionalNEQ` call and their rounding, which existing
  tests pin. The factor-once route repeats `regionalNEQ`'s weighting in
  its order, so it is bitwise the per-epoch route, not merely close.
- 2026-11-12 — **The covariance check stops at symmetry and the
  diagonal.** Definiteness is left to the one Cholesky factor of noise +
  C: a rank-deficient empirical C (T < P) is legal when added to a
  definite noise covariance, and a P x P eigenvalue check would cost
  what the cache saves. A failure there is re-raised as `badAddNoiseCov`
  so the message names the option.
- 2026-11-12 — **Next, as the plan put it:** 6.0.6 makes the sea-level
  equation one implementation, with the old `seaLevelFingerprint` loop
  kept test-local as the captured reference so A8 proves bitwise (the
  A33 pattern) - no Tier-A session needed; then 9j as 6.1.0.
- 2026-11-08 — **6.0.0: every download goes to the data pool**
  (Matthias: "All data go always to the data pool. Only model code or
  libraries go to the toolbox."; contract: the installer's
  `docs/DATA_POOL.md`). `dataFolder()` is the stored preference, then
  `<DATAPOOL>/GravityField`, then `<READING_DATA_POOL>/GravityField`,
  else `noDataPool`; no `<toolbox>/data` default, and a folder inside
  the toolbox is refused. Lookups with a fallback use `Probe = true`.
  Committed `data/gravis` and the fixtures are not read through it.
  MAJOR, because a documented call - `dataFolder()` or a fetcher's
  default `Dest` on a machine with no pool set - stops working; a
  MINOR reading is possible and is Matthias' call in the PR. One
  spelling per folder, the writer's: `standardChain` read `tn` where
  `fetchTN` writes `TN`, `twsChain` tried `ddk` as well as `DDK`.
  `setup_shAnalysis` keeps its `DataFolder=` option; no `DataPool=`
  option was added (the contract allows the existing one).
- 2026-11-08 — **5.31.3: GravIS tests hold on a newer download** (Matthias:
  "ensure that the test will also work with future downloads"). The
  basin GeoJSON falls back to `data/gravis` in both GravIS chains. The
  twsChain anchor runs on its validated span (SpanEnd 2025.96, 252
  months). GFZ rewrites the TWS grid each month: its earlier months move
  by about 1e-7 relative, as scipy confirms. So the scipy pins hold for
  the 256-month edition only, and a newer edition is checked against the
  raw netCDF read, bit for bit. A wider tolerance was never an option.
- 2026-11-07 — **5.31.2: the real-data tests trim to TN-14, the fixture
  stays** (Matthias: "Go for 1"). A growing series outruns the pinned
  table: COST-G reaches July 2026, the table's last entry is centred at
  2026.45. The two tests that apply TN-14 themselves now keep the months
  applyTN14's 0.05 yr rule accepts; standardChain already drops
  uncovered months. Re-pinning a newer table was the alternative, not
  chosen.
- 2026-11-07 — **5.31.1: `fetchICGEM` resumes a partial series and stops
  on a rate limit** (Matthias: "Fix the two weaknesses"). Measured on the
  acceptance machine with HLSST_SLR_COMB2023s: the archive was refused,
  480 per-file requests went into the limit, and the 168 files left were
  then "present, skipped" for good. A marker `.fetchICGEM-incomplete`
  now says a folder is unfinished. A refused archive does not fall back
  to per-file, and the per-file loop stops at the first file still
  refused. 80 of the 114 failures were a bare "A low level error has
  occurred", not reproduced afterwards (the server answered 429). It is
  left as an ordinary failure, not guessed into a rate limit.
- 2026-11-06 — **9i built as 5.31.0 from release differences**
  (Matthias: "Merge and go ahead with 9i"). `backgroundErrorCov` takes
  two releases or models of a background product and returns half the
  covariance of their differences, mean removed; `AddNoiseCov` adds it
  to every epoch's noise in `regionalKalman`'s solution mode. The row's
  own limit is stated where the function is: an error both releases
  share is invisible, (1 - rho) C. No real pair (AOD1B RL06/RL07, two
  tide models) is reachable here; its size is acceptance-machine debt.
- 2026-11-06 — **`kalmanChain` got no `AddNoiseCov`.** With constant
  formal sigmas `NoiseCov = diag(sigma^2) + C` is the same thing - the
  identity the new test pins for `regionalKalman` - and kalmanChain's
  per-epoch sigma path was not touched without a run.
- 2026-11-06 — **9h built as 5.30.0, an option of `regionalBasis`**
  (Matthias: "Merge and go ahead with 9h"). `Ocean = ...` turns every
  column into the land part of its function plus its elastic sea-level
  response, so every downstream function (8b-8j, 9g) takes the basis
  unchanged; `regionalKalman` adds `out.landMean`, the land EWH the
  coefficients carry. A new function would have needed its own copy of
  the projector; an option reuses it.
- 2026-11-06 — **The coastal mask is half the gain, measured.** In the
  closed loop an unmasked rbf basis recovers 0.64 / 0.83 of the land
  loss with or without the ocean response in the truth - band-limited
  functions put land mass over the ocean. Masking the columns to land is
  what the sea-level equation needs anyway; the fingerprint then
  removes the +5.7 / +6.6% the ocean response adds to a masked basis.
- 2026-11-06 — **CLAIM 4 amended after its first run, against the
  floor.** Written as "within 2% of the truth" from a coarser
  exploratory selection; at 300 km the basis' representation error
  (-6.1%) exceeds the bias and cancels it in the masked basis. Claimed
  now against the same basis on a truth without ocean response; 4R
  keeps the refuted form.
- 2026-11-06 — **Two implementations of the sea-level equation,
  knowingly.** The column solve is a vectorised copy of
  `seaLevelFingerprint`'s loop, pinned to it by a test; merging them
  would change `seaLevelFingerprint` without a captured reference
  (6.3), which a Tier-B session cannot take. A follow-up for a Tier-A
  session.
- 2026-11-06 — **9g built as 5.29.0 on the published SPDE** (Matthias:
  "Go ahead with 9g"). HB-STAR's own parameterisation of the range and
  sigma fields was not found by search; Lindgren, Rue and Lindstroem
  (2011) publish the equations HB-STAR's prior rests on, with log kappa
  and log tau as fields (the R-INLA form). So 6.3's rule - no equations,
  no row - did not stop it: the equations are published, only HB-STAR's
  choice of fields is not, and that choice is left to the caller.
- 2026-11-06 — **Galerkin in SH, not finite elements.** The toolbox's
  basis is band-limited SH, so the SPDE is discretised there: Gram
  matrices of kappa^2 and 1/tau on an over-sampled grid, degrees 0..Lmax
  solved, the index' degrees taken as the sub-matrix. Exact for constant
  fields; for varying ones the multiplications are truncated at the band
  limit. Five (Lmax+1)^2 matrices: 0.55 GB at Lmax 60, 3.5 GB at 96.
- 2026-11-06 — **A prior replaces Q, it does not replace the dynamics.**
  `ProcessCov` sets Q0 = Proj C Proj' and QScale / QBlocks /
  EstimateQScale scale it, so 8i's scales estimate the prior's overall
  sigma from the innovations; Phi stays the model series'. `StartCov` is
  separate because a prior for the start and one for the noise are
  different statements.
- 2026-11-06 — **CLAIM 4's bounds were set after an exploratory run**
  (0.2 / 0.7 percent measured, 1 / 2 percent asserted), and the closed
  loop (CLAIM 6) runs in the oracle only: the MATLAB tests pin the
  covariance and the chain's identities. The gain measured is honesty
  (z-rms 1.00 against 1.14) more than error (0.94).
- 2026-11-06 — **8j measured, as 5.28.1** (lgdToolbox R-049, Matthias on
  its D138: "Go ahead with all three of them"; (c) is this row). No
  function changed: the chain already had what the row needed (mascon
  basis 9c, LGD records 8h, Background 8e, EstimateQScale 8i). lgdToolbox
  decided in the same release that it hands over records, not a Route C
  state (its D141).
- 2026-11-06 — **CLAIM 2 refuted, recorded, not moved.** Written before
  the run as "the right model is calibrated"; it gave basin z-rms 1.80.
  An exploratory run (8 seeds) placed the cause in the global broad
  field, which the regional basis represents only partly; the amendment
  (claims 7-10, written before their run) adds the 8e background at 80%.
  The refuted claim stays in the oracle and fails if it ever holds.
- 2026-11-06 — **The MATLAB test's E first ran on model A's series**, a
  test bug (the oracle's E is C with EstimateQScale); its alpha came out
  0.24 and the alpha check failed. Fixed to C; alpha median 2.42 (oracle
  2.08). Recorded because the first red was the test's, not the chain's.
- 2026-10-29 — **9f built as pseudo-observations, 5.28.0** (Matthias:
  "Go ahead with 9f"; asked how, given no public SLR normal equations:
  "Also include degree 1"). `shLowLevel.neqAddCoefficients` adds a
  coefficient's value and sigma to N and b - the stacked least-squares
  row - and extends the index to degree 1 when the values need it. The
  desk check found no public SLR gravity NEQs: ILRS weekly SINEX are
  station coordinates and EOP; AIUB and CNES give theirs to COST-G.
- 2026-10-29 — **Degree 1 from TN-13 is substitution, read and proven,
  not chosen.** A GRACE normal equation holds nothing of degree 1, so
  the padded block is uncoupled: its estimate is the observed value and
  no other coefficient moves (oracle CLAIM 3, exact). The double count
  of GRACE that TN-13 would bring to a joint estimate cannot happen, and
  nothing is gained over substitution either. Joint degree 1 needs a
  normal equation that observes it.
- 2026-10-29 — **The gain claim moved from a Monte Carlo to the exact
  covariance, after it failed.** Written first as "the 40-seed RMS ratio
  of the other zonals, joint over substitution, below 1", it came out
  1.005 at a C20 correlation of 0.12, where the expected gain is about
  rho^2 in variance and 40 seeds cannot resolve it. The exact ratio is
  0.993 there and 0.749 at rho 0.77; the Monte Carlo is kept as its
  check (0.793 against 0.749). Recorded because a claim moved after a
  run looks like one bent to fit; the design was not changed.
- 2026-10-27 — **9e checked from the desk, as 5.27.4; nothing built**
  (Matthias: "Go ahead with 9e"). Found by web search, no file opened:
  GFZ's monthly RL06 (GRACE) and RL06.x (GRACE-FO) normal equations in
  SINEX to d/o 96 at ISDC since 2020 (RL06.3 release notes:
  `isdc-data.gfz.de/grace-fo/Level-2/GFZ/RL06.3_NEQs_SINEX/`, files
  `GSM-2_..._GRFO_GFZOP_BB01_0603.snx`); a Zenodo dataset (record
  22122647, PyHawk) with monthly reduced NEQs in SINEX, degrees 2-60,
  2002-04 to 2026-06; CNES/GRGS and AIUB, both COST-G analysis centres,
  provide unconstrained monthly NEQs to COST-G, with no public download
  found for either. COST-G's own NEQ-level work (EGU26) uses AIUB, GFZ
  and TUG NEQs. Nothing was built because no second centre's file was
  read: `readSINEX` says "verify once against your provider's file", and
  this sandbox reaches neither data host, nor does A8 reach
  `isdc-data.gfz.de` or `isdcftp.gfz.de` (`probe-8f`, 2026-10-24,
  tcp443 = False; `ftp.tugraz.at` and `isdc.gfz.de` do answer).
- 2026-10-27 — **What a combination would meet first, read from the
  code.** `neqCombine` requires every contribution on the SAME
  `shIndex` and the SAME background models, and says no algebra will
  warn if they are not. GFZ's d/o 96 matches ITSG's degree-96 product in
  index; their backgrounds are not known to agree and were not checked.
  The PyHawk NEQs stop at degree 60, so combining them with a degree-96
  one needs the higher degrees reduced out (a Schur complement, as
  `neqClimatology` does internally), which no public function does for a
  SINEX NEQ today - the one build candidate, and only once a file is
  read. A 2023 GJI paper notes that most providers' NEQ stochastic models
  are unrealistic and need empirical scaling, which is what
  `neqCombine`'s VCE estimates.
- 2026-10-26 — **The DRIVEN tests ported onto 5.27.2 as 5.27.3; the
  history rewrite skipped** (Matthias: "Go ahead with 1 and 2, skip the
  rewrite"). The sixteen tests written as 5.24.2 on the rewritten
  history were re-applied to `main`; the WP9 releases between had not
  touched a guard they drive (`kalmanChain`'s new guards sit behind
  `SecondSeries`, which none of them passes). The branch was reset to
  `main`. The 112 guide PDFs stay in `.git`; the rewrite script was not
  committed, and the 5.24.2 commit that holds it (`50cf4dc`) is the
  record if the question returns.
- 2026-10-24 — **9d's answer: memory does not stop 8f on A8.** Measured
  on A8, one month at a time: 0.21 GB peak at nmax 60, 1.32 GB at nmax
  96 (two P x P; the predicted third is a temporary between samples),
  2.2 s per month at nmax 96, against 27.8 GB physical and a 21.2 GB
  largest array. What still blocks 8f is the DATA - ESA ESM output and
  the ITSG-Grace2018 monthly covariances - not the machine; whether A8
  may fetch or hold them is Matthias's call. And the synthetic loop is
  not honest yet (sigma ratio 11.7 / 5.6): without a background the
  outside signal enters the basis. 8f must run with 8e's
  remove-compute-restore, and the opt-in test can grow a background
  before it does.
- 2026-10-24 — **9d is an opt-in test** (Matthias: "Make it opt-in", on
  the choice between that and a one-off workflow). It is filtered in every
  ordinary run and switched on by `SHX_CLOSEDLOOP_NMAX`, the preference
  `ClosedLoopNmax`, or on CI by a manual run's `closed_loop_nmax` input -
  so the suite carries the instrument and A8 runs it only when asked.
- 2026-10-24 — **9d measures the data flow 8g would use, not a covariance
  stack.** One SH normal matrix per month is built, used and released
  (`regionalNEQ(B, "neq")` keeps only K x K), so the predicted peak is
  three P x P matrices - 0.31 GB at nmax 60, 1.98 GB at nmax 96
  (`tools/dev/closed_loop_budget.py`). Whether 8f fits A8 is then a
  question of one month at a time, which the 2026-10-21 postponement did
  not separate from holding the covariances of every month. The data are
  synthetic (no ESA ESM, no ITSG covariances here); the honesty statistic
  is logged, not asserted - no oracle has measured it at this size.
- 2026-10-24 — **The README is a release, 5.27.1** (Matthias: "Where is
  the pdf? It is not part of the repo. Also the readme of the repo is
  outdated"). The PDF question was the README's fault as much as anyone's:
  it said "attached to every release rather than committed" once, at the
  end of a paragraph. It now says so first, with the `releases/latest`
  link. The README's quick-start fence is contract-checked by
  `doc_sync_audit` (a misspelled option fails it), so the two variables
  it used undefined (`kn`, `B`) were invisible to the gate - it checks
  calls, not that their arguments exist. Recorded, not gated.
- 2026-10-24 — **#138-#140 merged in order** by Matthias; each release
  carries the guide PDF (`release.yml`, confirmed on v5.25.0, v5.26.0,
  v5.27.0).
- 2026-10-23 — **9c shipped as 5.27.0**: `Type = "mascon"` in
  `regionalBasis`, an rbf with the cap kernel, so every downstream
  function (8b-8i) takes it unchanged. The coefficients are the caps' EWH
  [m], which needs the EWH kernel and so `kn` - required, as everywhere
  else Love numbers enter; degrees below the index's first are zeroed
  before `kernelFactors` sees them, so a CM-frame k_1 = -1 is usable.
- 2026-10-23 — **The default cap radius is equal-area** (cos psi0 = 1 -
  2/N over the GLOBAL grid), one rule tied to the rbf level rule, rather
  than a fixed 3 deg of the JPL product. At nmax 60 it gives 201.7 km
  caps whose band-limited centre value is 0.73: smaller than nmax
  resolves. Stated in the help with the closed form 1 - (P_L + P_L+1)/2,
  not hidden by a coarser default; `Level` and `CapRadiusKm` change it.
- 2026-10-23 — **CLAIM 0's first bound was the quadrature's error, not
  the formula's.** Against Gauss-Legendre quadrature the closed form
  missed 1e-12 by 2.9x; 40-digit mpmath values put the closed form at
  4.3e-17 and the quadrature at 2.8e-13 (1200 terms times (2n+1)/2).
  The reference became mpmath; the quadrature stays as a second route
  with its own bound.
- 2026-10-23 — **What a coefficient means for a smooth load is measured,
  not promised**: a uniform 1 m layer projects to interior caps of median
  1.02 m, 0.53 to 1.20 (nmax 30, level 6). The test asserts the median
  within 0.1 of 1, the oracle's bound set before it ran.
- 2026-10-23 — **9b shipped as 5.26.0**: `shLowLevel.neqClimatology`,
  without a class route (it reads normal equations; an exception in
  `class_surface_audit`, like `kalmanChain`'s neq mode).
- 2026-10-23 — **9b's first closed loop showed no gain, and that was the
  finding.** With a noise covariance of the same shape every month the
  normal-equation trend equals a per-coefficient weighted fit (ratio
  1.000): GLS with identical regressors and a time-invariant correlation
  reduces to it. The gain appears only when the stripe pattern changes
  between months (0.44 of the equal-weight error at the strength
  measured). The claim names that condition, the help states it, and the
  real-data size of the effect is debt for the acceptance machine.
- 2026-10-23 — **The honesty claim is made on the pooled ratio.** It was
  first written per seed (0.8-1.25) and one seed gave 0.75: a seed's
  ratio is an RMS over trends correlated within each stripe block, with
  few effective degrees of freedom. Pooled over the seeds it is 0.98;
  the per-seed range is printed beside it.
- 2026-10-23 — **The MATLAB closed loop moved from nmax 5 to 8, not its
  bound.** At nmax 5 the stripe blocks hold at most three coefficients
  and the worst of 20 seeds was 0.977; at nmax 8 it is 0.583, and the
  test keeps the bound 0.8 written before either run.
- 2026-10-23 — **The solve's memory is three (6P x 6P) matrices** (the
  normal matrix, its factor, the factor's inverse for the sigmas), and
  `MaxMemGB` (8) refuses beyond them: nmax 40 fits, nmax 60 needs 12 GB.
- 2026-10-23 — **WP9 approved, in the proposed order** (Matthias: "Go
  ahead", on a ranked list of further improvements asked for the day
  before: "Find other ways to make use of existing GRACE like
  observations for better gravity field estimates"). 9a shipped as
  5.25.0. Row 9e was rewritten on recording: `neqCombine` already
  combines centres on the NEQ level, so that row is a data question.
- 2026-10-23 — **9a is an option on the Kalman chain, not a second
  `bridgeGaps` method.** The second series is a general observation
  group (HLSST, Swarm, any noisier series of the field); bridging is one
  use. `bridgeGaps` stays as it is: it needs no process model and no
  covariance memory, which the chain does.
- 2026-10-23 — **The scale is calibrated with an errors-in-variables
  correction.** Regressing B on the noisy primary underestimates s_n
  where the primary is noisy (0.41 of the truth at degree 8 in CLAIM 2);
  subtracting the primary's noise variances from the denominator makes
  the estimate consistent. `bridgeGaps` regresses the other way, for a
  prediction, and keeps its own rule.
- 2026-10-23 — **The second series' noise is never better than the
  primary's**: sigma_n is floored at s_n^2 times the primary's mean
  variance. Without the floor a degree where the two agree to within the
  primary's noise would give the second series a near-zero sigma and an
  unbounded weight.
- 2026-10-23 — **Measured on synthetic data only.** No HLSST or COST-G
  series is reachable from this session; the real-data comparison with
  `bridgeGaps` (the 0.38 of testBridgeGapsAgainstGRACE) is debt for the
  acceptance machine, and no number for it is written anywhere.
- 2026-10-23 — **The closed-loop test asserts 0.9, the oracle 0.8.** The
  0.8 was set before the oracle ran and holds over its 40 seeds (worst
  0.794); the MATLAB fixture is not one of them, so the test asserts a
  bound above the oracle's worst rather than at it. Recorded because a
  bound moved after a measurement looks like one bent to fit.
- 2026-10-22 — **Five refinements, one PATCH, 5.24.1** (Matthias: "Go
  ahead with 1, 5 and 2", "3: go for (a)", "4: go ahead", on a list of
  six that ranked them). 1: `obpChain:emptyRefPeriod`, the third raise
  that threw on a non-scalar format argument. 5: `upload-artifact` on
  Node 24. 2: the DRIVEN rule, R8, and the first 56 identifiers driven.
  3(a): the guide is built by CI and attached to releases. 4: this
  file split, its history into `tools/dev/RECORD.md`. Item 6 (a Tier-A
  checklist script) was offered and not taken up.
- 2026-10-22 — **DRIVEN measures naming, and says so.** 395 raised
  identifiers, 164 named by no test, 108 after the first batch. A name
  in a `verifyError` proves the test asks; only MATLAB proves the call
  reaches the guard (the PINS limit). The backlog may only shrink, and
  a new raise must arrive with its test - there is no third list.
- 2026-10-22 — **R8 reads declarations, not values.** It flags `opts.X`
  or an input declared non-scalar, and a bare `size(x)`; a vector held
  in a local variable is not seen. It fires on all three historical
  defects and on nothing in the tree; `size(x, dim)` is a scalar and
  was the one false positive the probe showed.
- 2026-10-22 — **The guide's history stays in `.git`.** Removing the
  file stops the growth (about 3 MB per bump); the 43.5 MB already
  committed remain until the history is rewritten, which would change
  every commit SHA on `main` and need a force-push. That is a call for
  Matthias, not a ride-along. The gates job builds the guide in a venv
  from `tools/dev/guide-requirements.txt` (ubuntu-latest refuses a
  system-wide pip), and `release.yml` attaches it only when the release
  lacks it, so the asset is always the tagged commit's.
- 2026-10-22 — **The split moved text, it did not rewrite it.** Every
  non-blank line of the old file is in the new one or in the record
  (checked by script; the one exception is the 5.24.0 board row, which
  gained its merge date). 6.3's rules are new one-line summaries; their
  stories are the old bullets, verbatim, in the record.
- 2026-10-22 — **The class-surface backlog is empty, as 5.24.0**
  (Matthias: "Go ahead with the class-surface backlog"). Thirteen lanes:
  seven got nine thin delegates, pinned bitwise in `testContract`; six
  became EXCEPTIONS with their reason in the gate. A new lane now goes
  into a class or into EXCEPTIONS; there is no third list to park it in.
- 2026-10-22 — **A lane is routed when a class object is its natural
  input, and not when it takes a grid.** `eofSeparate`, `gridScaling`,
  `hydroExtremeIndex` and `oceanRMS` read grids or pixel stacks; a method
  would run `toGrid` first and carry two option sets - the
  `writeGrid` reasoning of WP7. `resolutionMap` reads a filter operator,
  `seaLevelFingerprint` a load region; neither reads a field.
- 2026-10-22 — **Where a route fills an argument from the object, it is
  the one the class already owns.** The kernels take `shIndex(nmax)`,
  the index `basinAverage` refuses any other kernel in, and no `Nmin`
  option for that reason; `buildCondFun` takes `shIndex(nmax)` with the
  series' GM and R (the `errorMap` precedent - field constants), while
  the kernels' R stays the lane's (the `regionalBasis` precedent - a
  buffer radius). `g.designFilter` passes NaN for absent sigmas, so the
  lane's own `badSigma` refuses them rather than a new identifier.
- 2026-10-22 — **`designFilter`'s NaN guard fixed in the same release.**
  `any(sigma <= 0)` let NaN through and built a NaN block silently; the
  route made it reachable from the most natural input there is, a field
  after `applyDDK`, whose sigmas are NaN. Refused as `badSigma`.
- 2026-10-22 — **The review closed in four releases, 5.23.1 to 5.23.4**
  (Matthias: "Review the current status of the repo ... Review the
  documentation and help text of each function if it is in sync with
  the code", then "Go ahead" for each step). The order was code defects
  first, then the injector, then the help, then the code defects the
  help review recorded - so no help text was ever written to describe a
  bug that the same release fixed.
- 2026-10-22 — **Help follows code; a code defect is listed, not
  described away.** In 5.23.3 every help correction took the code as
  the authority, and where the code looked wrong the help was made to
  say what the code did and the defect went into the CHANGELOG. 5.23.4
  then fixed those defects with a test each, and updated the same help
  rows again. The alternative - writing the intended behaviour into the
  help - would have left help promising what the code did not do, which
  is the defect the review existed to remove.
- 2026-10-22 — **Comment-only releases are checked on the diff, not
  trusted.** 5.23.2 and 5.23.3 were edited partly by parallel agents; a
  filter of the diff for changed lines not starting with `%` came back
  empty before each commit. That is the proof a "documentation only"
  release needs; a reviewer's statement is not.
- 2026-10-22 — **Three calls left to Matthias and merged as proposed**:
  `hydroExtremeIndex`'s `category` is double (NaN where Z is) instead of
  `int8`; `fetchITSG(Catalog = ...)` skips a daily row with a warning
  rather than fetching tens of GB; `combineCenters` labels mixed product
  types "unknown". Each was named in its PR as a decision to confirm or
  overrule.
- 2026-10-22 — **Five items stay open on purpose (A42)**: each needs data
  or a run this session did not have, and a fix built from a guess is
  6.3's confident nonsense.
- 2026-11-09 — **An install leaves `git status` empty, as 6.0.1**
  (Matthias: "This shall not generate uncommitted changes."). Everything
  an install or a test run writes into the toolbox is ignored:
  `tests/test_data/`, `tests/runAllTests_results.txt`,
  `html/helpsearch-v*/`, `html/custom_toolbox.json` (the last two
  written by `builddocsearchdb`, measured on R2026a). The fixtures stay in `tests/test_data`
  (Matthias' earlier decision); only git stops reporting them. The
  `head12.snx` negation is dropped, not honoured: v3.26.3 (`dc01482`)
  removed that file with the other 19 fixtures, so the rule from
  `671d6e8` had described a tracked file that has not existed since.
  Not tracking it again keeps one source for all 20, the tag.
  6.0.2: `doc_sync_audit`'s one-location walk skips what git ignores
  (Matthias: "skip files that git ignores"): the fetched
  `icgem_*_fixture.html` pages were its only findings once the fixtures
  were present. Tracked or unignored pages are still findings.
- 2026-11-09 — **6.0.4: every listed fixture is read by the code** (Matthias,
  "fix all"): `test_static.gfc.gz`, read by nothing, left
  `tests/data/SOURCES.json` (the tag still carries it; 19 of its 20 files
  are listed). `testEveryListedFixtureIsNamedOrCarried` counts `tools/`
  code beside the suites, so `gravis_gis_basins.geojson`
  (`tools/audit/audit_gravis.m`) is named and the test passes without a
  fixture folder instead of filtering. The installer's registry copy
  changes in toolboxInstaller 2.4.0. PATCH: no function changes.
- 2026-11-09 — **6.0.3: the repository owns its fixture list** (Matthias:
  the installer reads the test-data list from the repository, no longer
  from its registry). `tests/data/SOURCES.json`, `{"schema": 1,
  "sources": [...]}`, the registry's `tests.data.sources` copied
  verbatim. Not `tests/test_data/SOURCES.json`: that folder is the
  ignored fixture checkout (6.0.1). Four `testContract` tests hold it to
  the suites in both directions, reading the names from the code. Two
  listed fixtures are named by no suite (`gravis_gis_basins.geojson`,
  `test_static.gfc.gz`); kept, because the list is the registry's
  verbatim - dropping them is Matthias' call (decided 6.0.4: the first is
  read by a tool and stays, the second left the list). PATCH: no function
  changes.

### 6.2 Verification board (◑ = one tier only, ☑ = both)
The last releases only; the full board, in version order, is
`tools/dev/RECORD.md` §2.

| WP | Static gates | Tier A (MATLAB) | CI | Merged |
|---|---|---|---|---|
| v5.23.4 (A41: fifteen code defects recorded by A40) | ☑ 17 gates + mlint (21 files) + make_demos + 15 self-test suites, 0 findings | ◑ **Tier B locally**. ☑ **CI self-hosted (A8) at `b8c487b` via PR #134, green — 445 runs, 438 passed, 0 failed, 7 filtered**; the count prediction matched EXACTLY, and all ten new tests and the three extended ones passed on their first run - the `twsChain` one is the first to reach the DDK lookup on A8 | ☑ PR #134 | ☑ 2026-10-22 |
| v5.24.0 (the class-surface backlog: nine routes, six exceptions; `designFilter` NaN, `signalVarianceKaula` badRange) | ☑ 17 gates + mlint + make_demos + 15 self-test suites, 0 findings; reach 87 -> 94 of 134, backlog 13 -> 0 | ◑ **Tier B locally**. ☑ **CI self-hosted (A8) at `7b0d331` via PR #136, green — 448 runs, 441 passed, 0 failed, 7 filtered**; the count prediction matched EXACTLY, per class as well as in total (Contract 130). One red round first, at `962b4b8`: the new series test drove `signalVarianceKaula`'s range guard, whose `error` call threw `nonScalarInput` on its vector format argument - a lane defect of the A27 shape, fixed | ☑ PR #136 | ☑ 2026-10-22 |
| v5.24.1 (`obpChain:emptyRefPeriod`; DRIVEN + R8 and 56 identifiers driven; the guide built by CI; Node 24 artifact action; this file split) | ☑ 17 gates + mlint + make_demos + 15 self-test suites, 0 findings; DRIVEN: 231 -> 287 of 395 raised identifiers named by a test, backlog 164 -> 108 | ◑ **Tier B locally**. ☑ **CI self-hosted (A8) at `392d9a6` via PR #137, green — 452 runs, 445 passed, 0 failed, 7 filtered**; the count prediction matched EXACTLY, per class as well as in total (Contract 134), and all five new or extended tests passed on their first run. The gates job built the guide (2.2 MB artifact) and `doc_sync_audit` checked it there; no Node 20 warning | ☑ PR #137 | ☑ 2026-10-22 |
| v5.25.0 (WP9 9a: `SecondSeries` on `kalmanChain` and `ts.kalman`) | ☑ 17 gates + mlint + make_demos + 15 self-test suites + the new oracle, 0 findings | ◑ **Tier B locally** (no bridge). ☑ **CI self-hosted (A8) at `fe9fe24` via PR #138, green — 456 runs, 449 passed, 0 failed, 7 filtered** (the optional real-data fixtures); the count prediction matched EXACTLY, and the four 9a tests passed on their first run - no red round | ☑ PR #138 | ☑ 2026-10-24 |
| v5.27.0 (WP9 9c: `Type = "mascon"` in `regionalBasis`) | ☑ 17 gates + mlint + make_demos + 15 self-test suites + the new oracle, 0 findings | ◑ **Tier B locally** (no bridge). ☑ **CI self-hosted (A8) at `de4e0c4` via PR #140, green — 464 runs, 457 passed, 0 failed, 7 filtered** (the optional real-data fixtures); the count prediction matched EXACTLY, and the four 9c tests passed on their first run - no red round | ☑ PR #140 | ☑ 2026-10-24 |
| v5.27.1 (the README brought up to date; documentation only) | ☑ 17 gates + make_demos + 15 self-test suites, 0 findings; README fence contract-checked, fault-injected | ◑ **Tier B locally**; no MATLAB file changed. ☑ **CI self-hosted (A8) at `4552eab` via PR #141, green — 464 runs, 457 passed, 0 failed, 7 filtered** | ☑ PR #141 | ☑ 2026-10-24 |
| v5.27.2 (WP9 9d: the opt-in full-size closed loop, `closed_loop_budget.py`, the manual-run inputs) | ☑ 17 gates + mlint + make_demos + 15 self-test suites, 0 findings | ◑ **Tier B locally**. ☑ **CI self-hosted (A8) at `953fa26` via PR #142, green — 465 runs, 457 passed, 0 failed, 8 filtered** (prediction exact); ☑ **manual run 40062134202 with `closed_loop_nmax = 60,96`: 465 runs, 458 passed, 7 filtered**, the closed loop 31.7 s - numbers in CHANGELOG 5.27.2 | ☑ PR #142 | ◐ pending |
| v5.27.3 (DRIVEN: 98 identifiers driven, 10 left with reasons; tests only) | ☑ 17 gates + mlint + make_demos + 15 self-test suites, 0 findings; DRIVEN 301 -> 399 of 409 | ◑ **Tier B locally**; predicted 481 runs (Contract 153). First A8 run at `809a071`: 1 failed - `makeTutorials:noConverter` not raised, the converter wrote through a folder at the `.mlx` target; the check removed and the identifier listed. ☑ **CI self-hosted (A8) at `780e4de` via PR #144, green — 481 runs, 473 passed, 0 failed, 8 filtered**; the count prediction matched EXACTLY | ☑ PR #144 | ☑ 2026-10-27 |
| v5.27.4 (WP9 9e: the NEQ sources, a desk check; documentation only) | ☑ 17 gates + make_demos + 15 self-test suites, 0 findings | ◑ **Tier B**; no MATLAB file changed. ☑ **CI self-hosted (A8) at `590b322` via PR #145, green on the third attempt — 481 runs, 473 passed, 0 failed, 8 filtered**; the first two failed three speed budgets (`legendre_n360`/`n720`, `apply_ddk_n300`, 1.4-1.6x) while Windows Update ran on A8, and the post-update run matched the baselines to 2% | ☑ PR #145 | ☑ 2026-10-27 |
| v5.28.0 (WP9 9f: `neqAddCoefficients`, low degrees as pseudo-observations) | ☑ 17 gates + mlint + make_demos + 15 self-test suites + the new oracle, 0 findings | ◑ **Tier B locally**; predicted 484 runs (Correctness 232, Contract 154). ☑ **CI self-hosted (A8) at `8801b4a` via PR #146, green — 484 runs, 476 passed, 0 failed, 8 filtered**; the count prediction matched EXACTLY, and the three new tests passed on their first run | ☑ PR #146 | ☑ 2026-10-29 |
| v5.28.1 (WP8 8j: LGD records in a mascon basis, oracle + two tests) | ☑ 17 gates + mlint + make_demos + 15 self-test suites + the new oracle (claims 1, 3-10 pass, CLAIM 2 refuted as recorded), 0 findings | ☑ **Tier A on MATTHIASPC** (temp clone, R2026a): the two 8j tests 2 of 2 at `8325964` (77 s; one red round first at `f37a4e7`, the test's own case E on the wrong series). ☑ **CI self-hosted (A8) at `c0d43b9` via PR #147, green — 486 runs, 478 passed, 0 failed, 8 filtered**; the count prediction matched EXACTLY; the 8j tests 27 s and 65 s | ☑ PR #147 | ☑ 2026-11-06 |
| v5.29.0 (WP9 9g: `maternCovariance`, `ProcessCov` / `StartCov` on `regionalKalman`) | ☑ 17 gates + mlint + make_demos + 15 self-test suites + the new oracle, 0 findings | ◑ **Tier B locally**; predicted 490 runs (Correctness 237, Contract 155). ☑ **CI self-hosted (A8) at `d1e82e0` via PR #149, green — 490 runs, 482 passed, 0 failed, 8 filtered**; the count prediction matched EXACTLY, and the four 9g tests passed on their first run (1.6, 2.6, 0.55 and 0.23 s) | ☑ PR #149 | ☑ 2026-11-06 |
| v5.30.0 (WP9 9h: `regionalBasis(Ocean = ...)`, `out.landMean`) | ☑ 17 gates + mlint + make_demos + 15 self-test suites + the new oracle, 0 findings | ◑ **Tier B locally**; predicted 493 runs (Correctness 239, Contract 156). ☑ **CI self-hosted (A8) at `47dd85e` via PR #150, green — 493 runs, 485 passed, 0 failed, 8 filtered**; the count prediction matched EXACTLY, and the three 9h tests passed on their first run (0.07, 0.45 and 0.30 s) | ☑ PR #150 | ☑ 2026-11-06 |
| v5.31.0 (WP9 9i: `backgroundErrorCov`, `AddNoiseCov`) | ☑ 17 gates + mlint + make_demos + 15 self-test suites + the new oracle, 0 findings | ◑ **Tier B locally**; predicted 496 runs (Correctness 241, Contract 157). ☑ **CI self-hosted (A8) at `ab7acec` via PR #151, green — 496 runs, 488 passed, 0 failed, 8 filtered**; the count prediction matched EXACTLY, and the three 9i tests passed on their first run | ☑ PR #151 | ☑ 2026-11-06 |
| v6.0.0 (the data pool: `dataFolder` resolves `<DATAPOOL>/GravityField`, no `<toolbox>/data`; `TN`/`DDK` spelled as written) | ☑ 17 gates + mlint + make_demos + 15 self-test suites, 0 findings | ☑ **Tier A on MATTHIASPC** (worktree, copied prefdir): predicted 499 runs (Contract 159), ran 499 in both configurations - owner's preferences and no pool at all. Failures outside the change: `testVersionMetadataIsConsistent` (worktree name) and speed budgets under load (an `origin/main` control failed the same). `testAPIExamplesRun` red with no pool, fixed, then green | ☐ | ☐ |
| v6.0.4 (every listed fixture is read by the code: `test_static.gfc.gz` left the list; the converse test counts `tools/`) | ☑ doc_sync, error_id, help, nv_casing, toolbox_dependency, fixture_tag audits + make_demos --check, 0 findings; apiReference, refpages, demos regenerated | ◑ **Tier A on MATTHIASPC** (worktree): the four fixture-list tests of `testContract` - 3 passed and the folder test filtered without fixtures; with `SHX_TESTDATA_FOLDER` = the main clone's fixtures both folder-dependent tests passed. `testEveryListedFixtureIsNamedOrCarried` now PASSES without a fixture folder (it filtered at 6.0.3). Predicted 503 runs (no test added); the full suite was not run here | ☐ | ☐ |
| v6.0.5 (the 9i review: ten findings - scalar NoiseCov with AddNoiseCov, divisor T, GM/R, NaN and one-to-one epochs in `backgroundErrorCov`, early and shared covariance checks, factor-once noise, no P x P SVD) | ☑ 17 gates + mlint + make_demos + 15 self-test suites + the extended oracle, 0 findings | ◑ **Tier B locally**; predicted 505 runs (Correctness 242, Contract 164) | ☐ | ☐ |
| v6.0.6 (one sea-level equation: private `sleSolve` for `seaLevelFingerprint` and `regionalBasis(Ocean)`, the old loop kept test-local) | ☑ 17 gates + mlint + make_demos + 15 self-test suites, 0 findings | ◑ **Tier B locally**; predicted 506 runs (Correctness 243); the bitwise proof is A8's | ☐ | ☐ |
| v6.1.0 (WP9 9j: `seaLevelBudget`, `bprCompare`) | ☑ 17 gates + mlint + make_demos + 15 self-test suites + the new oracle, 0 findings | ◑ **Tier B locally**; predicted 509 runs (Correctness 245, Contract 165) | ☐ | ☐ |
| v6.0.3 (the fixture list: `tests/data/SOURCES.json`, four `testContract` tests) | ☑ 14 CI gates + mlint + check_api/api_audit/attribution_sweep + 15 self-test files, 0 findings; guide built locally | ☑ **Tier A on MATTHIASPC** (worktree, copied prefdir, `SHX_TESTDATA_FOLDER` = the main clone's fetched fixtures): predicted 503 runs (Contract 163), ran 503, 493 passed, 2 filtered (`testUserSuppliedSINEXFiles`, `testRegionalClosedLoopAtFullSize`), 8 failed outside the change: `testVersionMetadataIsConsistent` (`ver` finds the main clone, 6.0.2 - the worktree name, as at v6.0.0) and seven 1.3x speed budgets on a desktop; an `origin/main` control in the same session failed `legendre_n360`/`n720` alike. The four new tests passed, and seven single-defect injections turned exactly the expected ones red or filtered | ☐ | ☐ |
| v5.26.0 (WP9 9b: `shLowLevel.neqClimatology`) | ☑ 17 gates + mlint + make_demos + 15 self-test suites + the new oracle, 0 findings | ◑ **Tier B locally** (no bridge). ☑ **CI self-hosted (A8) at `4aa3aa9` via PR #139, green — 460 runs, 453 passed, 0 failed, 7 filtered** (the optional real-data fixtures); the count prediction matched EXACTLY, and the four 9b tests passed on their first run - no red round | ☑ PR #139 | ☑ 2026-10-24 |

### 6.3 What the next session could be wrong for not reading

One line per rule; the incident behind each, with its numbers, is in
`tools/dev/RECORD.md` §3. Read the rule here, the story there when it bites.

**Numbers and measurement**
- Write no number into this file that you did not just read from the tree or a run; quote the shipped instrument, never its prototype.
- A constant measured in a prototype (numpy) is not a constant of the product - re-measure it in MATLAB (A22's `ClenshawFrom`).
- Capture references BEFORE an edit, even one that only moves code; "bitwise unchanged" is proven, not argued.
- Measure a finding's defects before fixing them, and measure before asking for a decision - the measurement is sometimes the decision.
- Run the control before explaining the treatment: the same failure on a valid input points elsewhere (A28).
- Read the warnings of a failing run before its numbers; a warning's number can be the finding (A35).

**Tests**
- A static gate cannot see a raise that throws; only a test that DRIVES the guard can (A27, then twice more - hence DRIVEN and R8).
- Code no test reaches can be broken in a way only a run shows: ask what the test must run before it gets there, and build that input (A41).
- A statistic over two things cannot see one of them broken - test each half (A37); pin the half that is NOT true as well as the one that is.
- An oracle finds an implementation's bug only on the configuration where the two differ - name what a test exercises against what the code admits (A35).
- Assert an estimator's inverse; a sign error otherwise reads as a weak method.
- `isequal` is false on NaN - compare structs that can carry NaN with `isequaln`.
- A failing assertion may be the wrong assertion: ask what statistic a documented tolerance bounds. Never widen it (§3.6).
- Before sizing a fixture, grep the function for `error(`/`assert(` and read its helpers' defaults (`shIndex`'s `Nmin` is 2).
- A fixture can favour a method by construction (a uniform layer is exact for the method of scale) - name what it makes exact.
- Identity tests need an identifiable, stationary model, asserted in the test; two rounding paths through an explosive one drift.
- A dense product rounds differently for a different row count; compare routes where the product is exact.
- Write error identifiers whole in tests - the PINS and DRIVEN rules read literals.
- Tripwire counts in the self-tests (`EXPECTED_RUNS`, raising-method counts) move with the surface; bump them with a comment.

**Gates and instruments**
- A green gate is not a correct document: read what an instrument inspects before trusting its silence; prefer one that states its reach.
- A new checker lies before it tells the truth - fault-inject every rule in both directions.
- Two parsers of one fact will disagree, and the newer one is usually wrong; check both against ground truth (the filesystem), never against each other (A17).
- A gate can be silenced by its own inputs - ask what a rule reads, and whether the checked thing is inside that set.
- A reach or coverage check must blank strings as well as comments; reuse `mlint_lite.strip_tokens`.
- A writer that satisfies a gate by inserting text where the gate looks will satisfy it anywhere - gate where the writer writes (A39).
- Draining a backlog disarms any test that loops over it; assert the mechanism with a temporary entry instead.
- One constant must answer one question; split a name that serves two purposes.
- A character class is an enumeration: test a sweep's pattern on the awkward member (`noC30`), and verify a sweep by searching for what must be absent.
- An identifier can be built at runtime; treat a concatenated literal as a prefix and let the help name the members.
- Rename identifiers per raise site, never globally; an identifier must not name a private helper the user cannot see (A21b).

**MATLAB in a Tier-B session**
- `mlint_lite` on every changed `.m` is the only syntax check here: R3 dot on `(expr)`, R5 `name=value` before `{:}`, R6 arguments block first, R7 unterminated literal, R8 non-scalar `error` format argument.
- `regexp(..., 'tokens', 'once')` drops the tokens of an optional group that did not take part; index by count.
- Much of what a time-series method reaches for is a toolbox (`hilbert`) - check `toolbox_dependency_audit` before designing around it.
- A mechanical refactor must not smuggle in validation; and check whether a rename breaks at all - Name-Value matching is case-insensitive.
- Option names avoid every prefix of a house option (`R`, `Climatology`); `nv_casing_audit` refuses them.

**Process and CI**
- Read the branch before choosing a version: `git ls-remote` and `git log main..origin/<branch>`.
- A pushed SHA is not a running CI: after a PR merges, a push to its branch raises no event - open a new PR.
- Do not push while a run is in flight; the cancelled MATLAB process skips its `onCleanup`. A queued self-hosted job is not an offline runner.
- A speed budget can fail on runner load: compare the neighbouring runs, never re-baseline from the slow one. Under ~3 ms a benchmark measures the timer; try one thread first; size on the path the budget times; retire the baseline an optimisation invalidates; write the stopping rule before tuning.
- Profile the suite from the runner's per-test durations; a duration that repeats to 0.03 s is a sleep (A36).
- The A8 log is the artifact: `get_job_logs` with a large tail saves a file you can grep; the suite runs alphabetically, so `testPerformance` sits mid-log.
- With parallel agents, give each disjoint files and check the diff for non-comment lines before committing.
- Shell: generator edits with raw strings or the Edit tool, scripts in files when a command carries `''`, chains with `&&`; `git log -S` on a shallow clone names the wrong commit.

**Science and documentation**
- A method's published description is not its equations; without the equations the row is STOPPED.
- Check the units of every equation taken from a document, and confirm a correction against data (ESMGFZ eq. 2.8).
- A file's name is not its content, and a file-name parser decides whether a series has epochs at all.
- A promise in help outlives the path that kept it; correct a refuted claim everywhere it appears (grep the number).
- A documentation gate reads constructs, not documents - list every place a call is written and check each is read.
- Git's text detection looks at bytes: binaries are marked in `.gitattributes`. A check can pass a file the damage has broken - check the property the damage breaks.
- A work package can contradict itself: resolve it by its own explicit rule and record the choice in 6.1.
- §1 is the only place in this file that states the version; the package is `+shLowLevel` (`shx.*` is stale). Do not re-propose what §1.1 lists.

### 6.4 Next action

**State, 2026-11-12.** `main` is `9ae0227`, v6.0.4 (#159, the fixture
list read by the code); v6.0.0 (#155) moved every download to the data
pool. 9i (5.31.0, #151) is merged; its review's ten findings are fixed
as v6.0.5 on branch `wp9-9i-review` (#160); v6.0.6 (one sea-level
equation, `wp9-one-sea-level`) and v6.1.0 (9j, `wp9-ocean-validation`)
are stacked on it, each to open as its PR once the one below merges.
WP9 is complete with 6.1.0. Every release since v5.24.1 carries
`shAnalysis_workflow_guide.pdf`. A re-measurement is a manual run of the
CI workflow with `closed_loop_nmax`, read from the log's `CLOSEDLOOP`
lines. Every finding in 4.1 is CLOSED except A42, which holds five low
items that need data or a run, not effort. Read the version from 1's
table or `Contents.m` line 2, never from this paragraph.

**Open, in the order of what they buy:**
0. **WP9, in its table's order** (approved 2026-10-23): 9e is checked
   from the desk (6.1, 2026-10-27); what settles it is one GFZ RL06.3
   `.snx` and the ITSG file of the same month read with `readSINEX` on
   the acceptance machine (A8 does not reach the GFZ hosts) - if both
   parse onto one `shIndex`, `kalmanChain`'s multi-center neq mode runs
   them. 9f is done as pseudo-observations (6.1, 2026-10-29); its gain on
   real normal equations - their C20/C30 correlations - is debt for the
   acceptance machine. 9g is done (6.1, 2026-11-06); choosing the range
   and sigma fields from data is not part of it. 9h is done (6.1,
   2026-11-06); its column solve and `seaLevelFingerprint` share one
   solver since 6.0.6, proven bitwise against the captured old loop. 9i is done (6.1, 2026-11-06) and its review fixed as
   6.0.5; its size on a real release pair is acceptance-machine debt.
   9j is done as 6.1.0 (6.1, 2026-11-12); the published sea-level
   budget and real recorders are acceptance-machine debt. WP9 has no
   open row. Waiting on
   Matthias: whether 8f now runs on A8 - memory is measured to suffice;
   it needs ESA ESM output and the ITSG-Grace2018 covariances there. Real-data
   debt for the acceptance machine: 9a against `bridgeGaps` on COST-G and
   HLSST, 9b's gain on ITSG normal equations (it is the month-to-month
   change of their noise pattern, not measured), and 9c's mascons against
   a `readMascon` product.
1. **A42**, each a small, separate change once its input exists:
   - one look at `tests/test_data` on A8 or MATTHIASPC settles whether
     the TN-13 fixture spans 2017-07..2018-05, i.e. whether
     `testStandardChainDropsAnEpochInAnInteriorGap` reaches an interior
     gap or the table's end;
   - a Tier-A run of `benchPointsCrossover` settles 2.0x/34x against
     A22's 2.3x/37x in `synthesisPoints`' help;
   - a SINEX file whose estimate lines lack the std column is what a
     `readSINEX` fix needs - until then the parser's assumption stands,
     documented;
   - `gravisRegionChain`'s Greenland `rep.basins`, `standardChain`'s
     `rep.files`, MaxFailures: documented as they behave; changing any
     is a design call for Matthias.
2. **A7, unverified on Tier A**: whether `builddocsearchdb` descends into
   `html/ref/` - the acceptance machine only.
3. **WP8 8f and 8g**, POSTPONED until the bridge returns (6.1,
   2026-10-21): they need ESA ESM output and full covariances that A8
   cannot hold.
4. **The DRIVEN backlog** is 10 identifiers since v5.27.3, each with
   the reason no offline test reaches it (`tools/undriven_ids.txt`);
   it shrinks only when one of those reasons goes away.
5. **WP6's topic categories** for the reference index: an editorial call
   for Matthias (6.1, 2026-09-08).

**What a Tier-A session should know about running the suite here.** The
MATLAB MCP tool times out on anything suite-sized. Run it detached and
read the log:
```
"/c/Program Files/MATLAB/R2026a/bin/matlab.exe" -batch "run('<script>.m')" > run.log 2>&1
```
The machine label for baselines is `MATTHIASPC` (upper-cased since
v5.3.0). Only 2 tests filter here rather than A8's 7, because
`E:\DATAPOOL` supplies the real-data fixtures (with the environment
variables of 1's Tests row set for the run).

To re-run the gates and the prediction from a fresh sandbox (the list
of 3.4; `mlint_lite` takes the changed files as arguments):
```
pip install -r tools/dev/guide-requirements.txt && python3 tools/dev/make_guide.py && \
  for g in tools/help_audit.py tools/doc_sync_audit.py \
      tools/dev/no_map_renderer.py tools/toolbox_dependency_audit.py \
      tools/nv_casing_audit.py tools/fixture_tag_audit.py \
      tools/dev/check_api.py tools/dev/api_audit.py \
      tools/dev/attribution_sweep.py tools/dev/refpages_audit.py \
      tools/dev/name_coverage.py tools/dev/class_surface_audit.py \
      tools/error_id_audit.py tools/dev/option_values_audit.py \
      "tools/dev/make_demos.py --check" tools/dev/perf_baseline_audit.py; \
    do python3 $g || echo "FAILED: $g"; done && \
  for t in tools/tests/test_*.py; do python3 $t || echo "FAILED: $t"; done && \
  python3 tools/dev/count_tests.py
```

---
*Audit of shAnalysis v3.33.0, 2026-09-08, and every release since -
the full provenance is in `tools/dev/RECORD.md` §4. Developed by
Matthias Weigelt with the help of Claude.*
