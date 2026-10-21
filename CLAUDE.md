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

Provenance: audit of `astrobayer/shAnalysis` @ `0225c8d3` (main, pushed
2026-09-06), read in a sandbox on 2026-09-08 18:30 UTC by Claude Fable 5.1.
Execution tier during the audit: **Tier B** (no MATLAB MCP bridge reachable;
static reading + Python only; nothing was run in MATLAB). Every finding below
says whether it was *read* or *inferred*.

---

## 1. What the toolbox is (verified state)

| Fact | Value | Evidence |
|---|---|---|
| Version | **5.22.0**, 21-Oct-2026 | `Contents.m` line 2, `CITATION.cff`, `CHANGELOG.md` line 3 agree |
| Branches | `main` only; `claude/getframe-recapture` and `claude/readshm` are gone (merged/deleted) | `GET /branches` |
| Public surface | 3 classes / 97 methods, 134 `+shLowLevel` functions (+5 private), 3 root functions. 87 of the 134 are reachable from a class method; each of the other 47 is a named exception (34) or in a backlog that may only shrink (13) | `tools/dev/api_extract.py`; `tools/dev/class_surface_audit.py` |
| Tests | 5 classes, **417 methods / 431 runs**: Correctness 214, Contract 121, Robustness 60, Science 9, Performance 13 methods (27 runs, `budgetCase` x14 + `nmaxP` x2). On A8 7 filter out without the optional real-data fixtures (the GravIS-grid test joined them in v5.8.0, the ESMGFZ check in v5.11.0, the HLSST check in v5.12.0); on MATTHIASPC only 2 do, because `E:\DATAPOOL` supplies the SINEX files, the GravIS folder and - with `SHX_EARTHROTATION_FOLDER` and `SHX_BRIDGE_FOLDER` set for the run, no preference is stored - the ESMGFZ and HLSST series. The counter has matched the runner EXACTLY on the last ten green A8 runs and on every local Tier-A run. | `python3 tools/dev/count_tests.py` |
| Python oracles | 31 `tools/dev/validate_*.py` (+ `regional_oracle_lib.py`, shared by the WP8 oracles) + `tools/audit/*` | listing |
| Docs | **27** hand-written `html/*.html` (24 per-entity duplicates retired in v5.0.1, WP6 stage 3; `regionalBasis.html` added in v5.14.0) + **238 generated `html/ref/*.html`** (one per entity + index, `make_refpages.py`), one shared `html/shAnalysis.css`, `helptoc.xml`, `info.xml`, guide PDF, generated `html/apiReference.html`. `docs/` holds the PDF and `apiExamples.json` only - no HTML page lives outside `html/` (gated). | listing |
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
   `tools/dev/make_guide.py` (the last needs `reportlab` + `matplotlib`;
   `pip install reportlab matplotlib`). **Four** artifacts carry the
   version, not two: `apiReference.html`, `html/ref/*`, `demos.xml` and
   the guide PDF. All four stamps are now gated by `doc_sync_audit.py`;
   `demos.xml` was not until v3.34.1, which is how a bump alone shipped a
   stale one.

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
| A36 | M | **OPEN, fix on PR (v5.23.0)** - 130 s of the suite's 248 s of test time on A8 (53%) was three OFFLINE tests sleeping: `testICGEMListFixtureAndResolve` 65.5 s, `testFetchICGEMSeriesOffline` 34.0 s, `testFetchProxyPlumbing` 30.3 s, identical to 0.03 s over four runs. Each URL they make fail on purpose paid `httpFetch`'s backoff (4 tries, 2 s base, about 15 s), and `fetchTN`/`fetchICGEM` gave a caller no way to shorten it. v5.23.0 forwards `MaxTries`/`BaseDelay` (no defaults of their own) and the tests pass `MaxTries = 1`. No numerical lane is slow: the largest is `benchPointsCrossover` at 9.9 s. Closes when A8 measures the three durations. | A8 job logs, per-test durations |
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

### WP6 — Documentation to the MathWorks layout   `[~] STAGES 1-2 DONE in v3.34.0`

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
on the series - so 14 remain; reach is 79 of 128.

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

### WP8 — Regional Kalman with local basis functions   `[~] 8a DONE (v5.14.0), 8b DONE (v5.15.0), 8c DONE (v5.16.0), 8d DONE (v5.17.0), 8e DONE (v5.18.0), 8h DONE (v5.19.0), 8i DONE (v5.20.0); 8f, 8g POSTPONED` (approved 2026-10-20)
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

- **GNSS and terrestrial gravimetry** enter as SH NEQs or point
  records built OUTSIDE shAnalysis: WP4's decision of 2026-09-10 put
  GNSS inversion and joint combination into a GNSS toolbox, and this
  WP does not reverse it - the regional filter only accepts the NEQ.
- **Tests**: per row; `metamorphic` (SH basis = global chain),
  `precision` (projector identities), `reference` (Woehnke/Steffen
  numbers), `robustness` (dateline basins, polar regions, gaps).
- **Size**: XL over the rows. **Version**: MINOR per row.

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
- 2026-10-21 — **A36: the offline fetch tests stop sleeping** (Matthias
  chose "Cut the sleeps" over a wider optimisation pass, after the A8
  profile showed no numerical hot spot). Shipped as 5.23.0: `MaxTries`
  and `BaseDelay` on `fetchTN` and `fetchICGEM`, forwarded through the
  private `webFetch`, declared without defaults so `httpFetch` keeps the
  only one. A MINOR: options added, no default moved.
- 2026-10-21 — **The profile came from the runner's durations, not from
  a profiler.** Four A8 logs gave the same per-test times to 0.03 s; a
  wait that reproducible is a sleep, not a computation, and the cause
  was read off `httpFetch`'s backoff rather than guessed.
- 2026-10-21 — **A34: the two-pass climatology fit is an option, not
  the default** (Matthias: "A34 make it optional"). Shipped as 5.22.0:
  `FitClimatology = "observations" | "filtered"`, default unchanged.
  `ClimatologyFit` was the first name and `nv_casing_audit` refused it:
  `Climatology` would have been its prefix.
- 2026-10-21 — **Two passes, not an iteration, and not a shrinkage.**
  Measured before asking: a per-degree Wiener shrinkage of the fitted
  climatology lost on the grid (about 2 cm), estimating it as static
  states inside the filter lost too (5.9 cm, the diffuse prior), and a
  third pass moved the median by at most 5.1%, against a bar of 5% set
  before the run. The option does the one pass that carries the gain.
- 2026-10-21 — **The first-pass climatology is fitted on the output
  epochs**, the grid the chain smooths onto (`Epochs`), not only the
  observed ones: the smoothed estimate exists at a gap, the noisy
  observation does not.
- 2026-10-21 — **A33 shipped as 5.21.0, a MINOR**: `readBasin` takes a
  string array or `string.empty`, and the chains use it. Basin 302's
  mask grows by its polar cap, a change of numbers; it is filed as a fix,
  since no reading of a ring that encircles the pole leaves the pole out.
- 2026-10-21 — **Measured before migrating, and the measurement moved
  the finding.** The lon-0 basins the finding named were already right
  (the chains recentre); the polar ring it did not name was wrong. The
  reference is the old rule itself, re-implemented in the test, not a
  frozen file: a mask is a deterministic function of the GeoJSON, and a
  rule is easier to audit than 132 bitmaps.
- 2026-10-21 — **Only two of the four chains parsed GeoJSON.**
  `greenlandChain` and `antarcticaChain` reach it through
  `gravisRegionChain`; their code changed in help rows only.
- 2026-10-21 — **8i's first A8 run failed on a fixture of mine, and the
  fix took the fixture from a new oracle claim, not a wider bound.** See
  6.3; CLAIM 4b mirrors kalmanFilter's own update formulas.
- 2026-10-21 — **A35 fixed inside 8i's release, not as its own.** 8i
  claims VAR(2) through the chain, and the claim was false until the
  Yule-Walker fix; shipping 5.20.0 without it would have released a
  feature its own test showed broken. The fix changes numbers only where
  they were wrong (`Order >= 2`, multivariate blocks).
- 2026-10-21 — **8i shipped as 5.20.0**: `QBlocks`, a `QScale` per
  block and `EstimateQScale` on `regionalKalman`; `kalmanFilter`'s
  `Likelihood`; `buildCondFun`'s `Basis`; VAR(2) through the chain tested.
- 2026-10-21 — **The row's "VCE of Q from the innovations" became a
  maximum likelihood of the innovations.** Kurtenbach gives no method for
  his alpha, and no source in hand gives the equations of a variance-
  component estimator for Q. Two estimators are derivable from first
  principles for one block: the innovation-likelihood maximum and the EM
  fixed point (Shumway and Stoffer 1982). The oracle shows they are the
  same stationary point (1.3e-8), so the likelihood - which serves any
  number of blocks - is the implementation, and the claim it rests on is
  checked by an independent route, not asserted.
- 2026-10-21 — **Q(alpha) = D Q D, not a block-diagonal Q.** A block
  scale keeps the cross-block correlations the Yule-Walker estimate
  measured; dropping them would change the model in a way no factor
  undoes. One fixed factor stays v5.19.0's path, bitwise.
- 2026-10-21 — **The likelihood is formed in the normal-equation form
  without log|R| + l'R^-1 l**, which a normal equation does not carry
  and no model parameter changes. Shown to equal the dense joint Gaussian
  likelihood (3.9e-15) and the solution form minus exactly that constant.
- 2026-10-21 — **The "CondFun" item needed no new conditioner.** Kvas'
  conditioner acts on SH covariances; in a basis it is Proj f(T S T')
  Proj', exact because Proj T = I. So it is one option on
  `buildCondFun`, not a second conditioner.
- 2026-10-21 — **The order after the postponement** (Matthias: "Go
  ahead in this order: 8h, 8i, A33 and A34"). 8h shipped as 5.19.0:
  kind "lgd" of `regionalNEQ`.
- 2026-10-21 — **lgdToolbox has no SH forward model, so 8h's oracle is
  the two it has.** "lgdToolbox forward model" in the row means its
  point mass + J2 closed form (`lgdReferenceJ2`) and its 50-digit Kepler
  pair (oracle O2); degrees 0 and 2 of the shAnalysis design reproduce
  both to rounding of |g|. Higher degrees are checked against Cartesian
  differences of the potential. lgdToolbox was read from its `main`, in
  an extracted copy; its working clone was left on its own branch.
- 2026-10-21 — **The data go through the operator with the design, data
  first.** `lgd.spectralOperator` fits its edge predictor on its first
  column and applies the fitted map to every column, and its help says
  partials must pass through the same call. Filtered values with a
  separately filtered design would get another predictor. So `Values`
  are the unfiltered LGD (Route A's `info.components.unfiltered`) and
  `Valid` is the mask of the data's own call.
- 2026-10-21 — **shAnalysis calls no `lgd.*` function and rotates no
  frame.** The operator is a handle the caller builds, so the toolboxes
  stay independent; the orbits must be Earth-fixed, because the field is,
  and the rotation belongs to the toolbox that reads the orbits.
- 2026-10-21 — **8f postponed** (Matthias: "We have to postpone this as
  the bridge will not be available for the time being. Only the CI is
  available but has limited memory and cannot accommodate the covariance
  matrices"). The closed loop needs ESA ESM output and ITSG-Grace2018
  full covariances (at nmax 96, 9409^2 doubles, about 0.7 GB per
  month), so it waits for the bridge. 8g is postponed with it: daily
  SINEX NEQs need the same machine. Rows that need neither stay open:
  8h, 8i (on a synthetic closed loop), A33 and A34.
- 2026-10-21 — **8e approved** (Matthias: "Go ahead", after #123
  merged). Shipped as 5.18.0: `Background` on `regionalKalman` and
  `ts.regionalKalman`.
- 2026-10-21 — **Remove-compute-restore is this toolbox's own design.**
  Woehnke et al. 2025 use no background; Steffen et al. 2026 name it for
  long wavelengths and outside signal without applying it, and give no
  equations. So the oracle checks it on its own terms: the restore
  algebra exactly (with the process model fixed the chain is linear, a
  background c z leaves 1 - c of the leakage of z, 5.6e-15), and a closed
  loop with signal outside the region (+28% grid RMS without it; within
  3.6% of the no-outside-signal error with an 80% background).
- 2026-10-21 — **Woehnke's observation area was measured and not built.**
  EWH observed on the region + 300 km helped without a background (1.04
  against 1.20 cm) and cost in every seed with one (0.97 against 0.93):
  SH-coefficient observations carry more than their synthesis on an
  area. Gridded data on an area already enter as `regionalNEQ "points"`;
  the computation area is the basis' `BufferKm`. A chain option would
  have offered a measured loss as a feature.
- 2026-10-21 — **The background is error-free and removed as a series
  difference before the climatology fit.** It adds nothing to the
  sigmas; the climatology is that of the residual. In record mode it is
  only restored - the chain cannot reduce a normal equation it did not
  build. The basin mean adds the background's EWH as a separate term, so
  the chain without a background is bitwise v5.17.0.
- 2026-10-21 — **A34 recorded, not fixed.** The observation climatology
  restore re-injects the climatology's noise; it is `kalmanChain`'s
  restore and the SH-basis identity rests on it.
- 2026-10-21 — **8d approved** (Matthias: "Go ahead", after #122
  merged). Shipped as 5.17.0: `regionalKalman` and `ts.regionalKalman`,
  `rtsSmoother`'s `Functionals`, and `B.region.core`.
- 2026-10-21 — **The chain takes a built basis, not the basis' options.**
  The row sketched `ts.regionalKalman(Region=, Basis=, ...)`; that would
  copy regionalBasis' dozen options into a second home. `B =
  ts.regionalBasis(...)` first, as rows 8a-8c already do.
- 2026-10-21 — **Solution observations update in the information form.**
  A general basis observes x = T a, H = T, and kalmanFilter's solution
  mode knows H = I only. So every observation becomes a basis normal
  equation (regionalNEQ) and kalmanFilter is reused unchanged. On the
  SH basis this is the one place the chain differs from kalmanChain,
  measured at 5.6e-15 (states) and 8.9e-16 (sigmas) over 40 seeds.
- 2026-10-21 — **The basin sigma is formed inside the chain, from the
  full smoothed covariance.** An shSeries carries per-coefficient sigmas
  only, so a basin sigma computed afterwards would drop every
  correlation. `rtsSmoother` gained `Functionals` (sqrt(diag(F Ps F'))
  without the m x m product), exactly `sig` for F = I, pinned bitwise.
- 2026-10-21 — **The basin mean is taken over the UNBUFFERED region**,
  which the basis did not store; `B.region.core` is the evalMask result
  regionalBasis already computed for `areaFraction`, now kept. Additive.
- 2026-10-21 — **The climatology is restored in the basis, T (a + Proj
  c).** Adding the global climatology to a regional estimate would mix
  a global field into a regional one; on the SH basis (Proj = I) it is
  exactly kalmanChain's restore.
- 2026-10-21 — **Records mode refuses two records within Tolerance**
  instead of picking one: several kinds of one epoch belong in
  neqCombine, with variance components, before the filter.
- 2026-10-20 — **8c approved** (Matthias: "Go ahead", after #121
  merged). Shipped as 5.16.0: `regionalNEQ` with three kinds and the
  class route `g.regionalNEQ`.
- 2026-10-20 — **One function, three kinds, one weighted core.** A
  solution, an SH NEQ and point functionals differ only in the design A
  (T, T'(.)T, A_SH T); the covariance is applied in one place, through a
  Cholesky factor, so a non-positive-definite covariance is refused
  rather than inverted. The output is `neqCombine`'s contribution format,
  so combining kinds of one epoch needed no new code.
- 2026-10-20 — **The LGD shape is in 8c, its preprocessing is not.**
  `Direction` + `Combine` give a line-of-sight gravity difference
  exactly; the along-track filtering, transfer function and noise PSD of
  real LGD stay in lgdToolbox (row 8h), as the toolboxes stay
  independent. GNSS loading enters as an SH NEQ built elsewhere (WP4).
- 2026-10-20 — **Option names avoid every prefix of `R`.** `R` (the
  reference radius) is a house option; 5.14.0's `RelTol` collided with it
  in `nv_casing_audit`. So the SH normal equation is one struct option,
  `NEQ` (the neqCombine/readSINEX formats), and the point radius is
  `Height`, as in kernelFactors.
- 2026-10-20 — **8b approved** (Matthias: "Go ahead", after 8a merged as
  #120). Shipped as 5.15.0: `regionalProcessModel` and its class route,
  and `estimateVAR`'s `Sigma0Add`.
- 2026-10-20 — **Kurtenbach's ground noise is added to Sigma(0), not to
  Q, and it is a white EWH field.** His Sec. 4.3.5 says the ground noise
  changes Sigma(0) and so B and Q alike, while alpha touches Q only; his
  real-data run adds 2 cm EWH "in the form of a diagonal matrix" without
  saying in which domain. Read as the isotropic white field band-limited
  to the index - equal EWH variance per coefficient - because that is
  the one reading under which "2 cm everywhere" is exactly true (the
  addition theorem). Stated as a reading in the help.
- 2026-10-20 — **`Sigma0Add` went into `estimateVAR` rather than a
  second Yule-Walker into the new function.** The ground noise must enter
  Sigma(0) only, before the solve; `Shrink` already did exactly that for
  one special matrix, so the option generalises it (pinned bitwise) and
  the solve keeps one home.
- 2026-10-20 — **alpha leaves Sigma0 unchanged.** Eq. 4.8 scales Q and
  says the dynamics B stay; the filter's initial covariance is Sigma0,
  and nothing in the thesis rescales it. A caller who wants the
  stationary covariance of the scaled model computes it.
- 2026-10-20 — **No model output was available to this session** (the
  bridge's device was offline), so 8b is validated on synthetic series:
  the SH-basis identity with kalmanChain and a VAR(1) recovered through
  the whole pipeline. A real model series (ESA ESM, WGHM) is first needed
  in 8f.
- 2026-10-20 — **WP8 approved: a regional Kalman with local basis
  functions, inside shAnalysis** (Matthias: "1 local basis function /
  2. Reuse it / 3. All of them / 4. Make it part of the shAnalysis
  toolbox and the basin shall be selectable. Else can be a test area").
  The answers followed a review of Kurtenbach's thesis and the work
  since, which ended "once these are settled I start the basis row";
  8a starts on that reading, the later rows wait for their own tick.
- 2026-10-20 — **Every basis is a linear map to SH coefficients.**
  RBF, Slepian and SH differ only in `T`; the filter, the NEQs and the
  VAR estimate stay SH-agnostic, which is what makes "reuse it"
  possible without a second filter. The price is band-limitation at
  nmax - the RBF of Eicker (2008) and Woehnke (2025) are band-limited
  Legendre series already, so nothing is lost against the literature.
- 2026-10-20 — **The RBF kernel follows Woehnke 2025 eq. 7, not a
  window.** Their shape coefficients are phi_n = sigma_n / sqrt(2n+1)
  from the signal's degree amplitudes (Eicker 2008), and they report
  Kaula's rule within 0.07% in correlation. So the kernel options are
  the user's degree amplitudes, Kaula's 1/n^2 (default, no data
  needed) and Shannon (phi_n = 1). A Blackman window was NOT
  implemented: its formula was not in hand, and 6.3 says what happens
  to methods built from memory.
- 2026-10-20 — **The default node level makes the GLOBAL grid as large
  as the SH basis**, 10(j+1)^2 + 2 >= (nmax+1)^2. At nmax 96 that is
  j = 30, the level Woehnke's Fig. 4 labels "n = 30" (their text gives
  the node count as K = 10(j+1)^2 + 2, eq. 8).
- 2026-10-20 — **A node belongs to the basis when its nearest
  quadrature point is inside the buffered region**, one rule for every
  region form (name, polygon, handle, mask), and the same buffered mask
  the projector weights with. The cost is a node-selection resolution
  of half a grid spacing, stated in the help; OverSample refines it.
- 2026-10-20 — **The GeoJSON reader is new, and the four chains that
  parse GeoJSON themselves were left alone** (A33). Moving them onto
  `readBasin` changes their code paths in a release whose claim is
  "additive"; it is a row of its own, with captured references first.
- 2026-09-11 — **The documentation audit shipped as 5.13.1, a PATCH**
  (Matthias: "Audit the help text, html doc and pdf documentation for
  completeness and if they are in sync. Fix everything mistake or miss
  accordingly."). Findings in A32. One code change rode along, and it is a
  fix, not a feature: `demo_shAnalysis`'s real-series lookup now searches
  the v3.16 folder first. Its own help and two pages had promised that for
  fourteen releases while the code looked where fetchITSG stopped writing.
- 2026-09-11 — **Probes first; only the precise rules became a gate.**
  Twelve read-only probe rules ran over html, the guide source, README,
  Contents.m and every help block. Four had zero false positives once the
  defects were fixed and became `doc_sync_audit` PROSE (inline calls, bare
  package calls, class-page coverage, identifiers in narrative docs). The
  rest - lowercase option names, lists of stale phrases, `object.member` by
  variable name - also flag legitimate history ("plotSHMap is gone", "this
  row claimed 5-20x until v5.5.0"), and a gate that fires on history is one
  people learn to ignore.
- 2026-09-11 — **The guide gained chapters, not an appendix.** The five
  capabilities after v3.26 are Part I chapters 28-32 in the house form
  (theory as implemented, the measured numbers, one gated snippet each),
  References moved to 33, and the class lanes are Part III G14. Every
  number in them is quoted from the function's help or the changelog, not
  re-derived for the page.
- 2026-09-11 — **#115, #116 and #117 were merged on 2026-09-10**; the
  branch was fast-forwarded to `main` (`3135b7b`, the same tree as
  `385e44f`) before this release was committed.
- 2026-09-10 — **Item 4 of the agreed order, the class-surface
  backlog: the four cheapest routes, 5.13.0.** `poleTideConvert` (the
  object form on a field, the raw form at every epoch on a series, which
  keeps names, sigmas and history), `estimateDegree1`, `combineCenters`
  and `slepianProject` - thin delegates, pinned bitwise. The backlog is
  14. The rest take grids, load regions or function handles, where a
  method would do more than forward; they stay listed, not forced.
- 2026-09-10 — **B1 is measured and not built, by WP2's own bar.** The
  latitude-first recursion is 1.11-1.69x faster raw, and every caller
  indexes P(n+1, m+1, :), so a drop-in pays a permute back and lands at
  0.92-0.99x. Changing nine callers for at most 1.7x is below the 2x the
  WP set before anything was measured. Bitwise identical throughout.
- 2026-09-10 — **`shSynthesis`'s `auto` keeps FFT: no path wins on both
  machines.** On MATTHIASPC `direct` is 0-14 percent faster over the
  whole call at 13 sizes; on A8 the FFT reduction ran 1.40x faster at
  nmax 60. The gap is the longitude step alone, at most 7 ms. The help
  row now states the sweep instead of one observation.
- 2026-09-10 — **The next order agreed** (Matthias: "#113 and #114 is
  merged. Continue in the suggested order"): A30's lane guard, then B1
  (measure first), then the FFT/direct sweep, then the class-surface
  backlog. A30 shipped as 5.12.1, a PATCH like 5.7.1's refusals.
- 2026-09-10 — **A30: the lane refuses NaN, and each caller that fed it
  NaN refuses under its own identifier.** Measured first: one NaN polar
  cap reached 153 of 289 C coefficients of `shAnalysisGrid`;
  `leakageCorrect` without a Mask reported `diverged`; `gridScaling` with
  a NaN model returned 0 of 1122 finite factors. The four paths that
  worked were captured and are bitwise unchanged.
- 2026-09-10 — **An inline script with a doubled quote does not reach
  bash.** Twice this session a long command carrying `''` died at parse
  time; the fix was a script file run from the command. Nothing had
  run, so nothing was half-done - checked, not assumed.
- 2026-09-10 — **The axial factor keeps its default, 0.753** (Matthias:
  "Keep 0.753 as default"). That is Chen & Wilson's eq. (1); ESMGFZ's
  prefactors give 0.844, and a caller who takes that convention passes
  `AxialFactor`. The question the 5.11.0 entry below left open is
  closed.
- 2026-09-10 — **5d's design decided by four answers** (Matthias: the
  Kalman-filtered variant; an offset, a per-degree scale and a per-degree
  noise from the overlap; every month GRACE lacks, 32 of them; the flag
  in the epoch names). Measured before asking, so each option carried a
  number: at 750 km the fill error over degrees 3-60 is 45 percent of the
  GRACE signal for the Kalman variant and 92 for the unfiltered one.
  Executed as 5.12.0; held out and bridged back, the error is 0.38 and
  the predicted sigma matches it (1.03).
- 2026-09-10 — **The flag lives in the epoch names, not a new property.**
  Names already travel through every method that selects, truncates or
  rebuilds a series; a new property would need carrying in each of them,
  and one that missed it would drop the flag silently - as the
  constructor already drops per-epoch history.
- 2026-09-10 — **The output is smoothed throughout, not only in the
  filled months.** A series whose resolution jumped at the flagged
  epochs would carry the fill's smoothing into every trend and
  amplitude fitted across them.
- 2026-09-10 — **The HLSST series came through the house fetcher.**
  `fetchICGEM`'s whole-series archive holds both variants (83 MB in one
  request, where file by file would have been 240 rate-limited ones);
  the unfiltered files sit beside the Kalman ones, unused.
- 2026-09-10 — **5a's open points decided** (Matthias: "length of day is
  a time and consequently ms is correct. mas is an angle"; "for M,R,C,A
  use the IERS conventions 2010"; "go ahead and download the data. Store
  them in E:\DATAPOOL\EarthRotation and not in the repo"). Executed as
  5.11.0. The ESMGFZ AAM, OAM, HAM and SLAM series for 2002-2026 and
  their Product Description Document are in that folder, not the repo.
- 2026-09-10 — **5d's method set** (Matthias: "Use a 750km Gaussian
  smooting"; "Use the overlapping periods"; "Flag the Swarm Epochs";
  "You can use the QuantumFrontiers/HLSST_SLR_COMB2023s time-series. It
  contains Swarm but many more satellite but no kbr. It should be
  slightly better than Swarm but poorer than a GRACE solution with
  KBR"). The series is not in the data pool: the local
  `HLSST+SLR/QF/RL01_60` is COMB2019s, and RL02 is Matthias's own.
- 2026-09-10 — **IERS 2010 lists none of M, C and A; they are derived,
  and checked against a second publication.** M = GM/G, C - A =
  J2 M a_E^2, C = (C - A)/H, A the mean equatorial moment, R = a_E (the
  table has no mean radius). C and A agree with ESMGFZ's Table 2.1 to
  0.03 percent.
- 2026-09-10 — **The length-of-day relation came from ESMGFZ's document,
  and its misprint was read by the units, then checked against data.**
  Eq. (2.8) prints 2 pi Omega; only 2 pi / Omega is a time. The observed
  length of day against the ESMGFZ model gives slope 1.097 and
  correlation 0.943; the printed form would give 2e8.
- 2026-09-10 — **The axial factor stays 0.753, and the question goes to
  Matthias.** ESMGFZ's prefactors give 0.844 - 12 percent more, close to
  C / Cm - and the model comparison cannot tell the two apart. It is an
  option, and the difference is in the help and the changelog.
- 2026-09-10 — **The new opt-in data is found through an environment
  variable, and no preference was written.** `SHX_EARTHROTATION_FOLDER`
  (or an `EarthRotationFolder` preference, not set on this machine); the
  local runner sets the variable for its own session only.
- 2026-09-10 — **5a shipped as 5.10.0 without the length of day in
  ms.** The approval named mas and ms, but the conversion of chi3 into
  a length-of-day change is not in Chen & Wilson (2003), the source
  supplied, and the sign of the axial term differs between authors. By
  6.3's rule - a method's description is not its equations - chi3 is
  returned as eq. (1)'s dimensionless excitation, and the conversion
  waits for a source.
- 2026-09-10 — **The Earth's constants are required, like the Love
  numbers.** The paper gives no values for M, R, C and A, and section 2
  forbids hardcoding a physical constant; a default would have been a
  number from memory. The test and oracle use SYNTHETIC round numbers,
  labelled as test inputs.
- 2026-09-10 — **The axial term needs a TN-14 table as an input, not a
  history check.** A series built from coefficient objects keeps one
  history line, so it cannot tell whether its C20 was replaced, and
  products such as GravIS ship with it replaced already. Applying TN-14
  again is idempotent, so passing the table makes it so either way.
- 2026-09-10 — **chi2 points to 90 E, as eq. (1) fixes it, and there
  is no `Convention` option.** The equation treats (C21, chi1) and
  (S21, chi2) alike; the IERS pole coordinate y points to 90 W. The help
  states the frame; an option would switch something the equation does
  not leave open.
- 2026-09-10 — **The method of scale shipped as 5.9.0, as an option, not
  a function.** It shares every estimate with the method of deviation -
  the filtered average, the leakage and its phase step - and differs in
  one line, so it is `Method = "deviation" | "scale"` on
  `leakageDataDriven`. The default is unchanged, and was proven bitwise
  on four configurations captured before the edit.
- 2026-09-10 — **The method of scale wins both closed loops, and that is
  recorded as ranking nothing.** 75.0% against 55.3% of the damage on
  the `testCorrectness` fixture, 78.6% against 62.9% in the oracle - but
  both fixtures put a uniform layer inside the catchment, the one case
  the scale factor is exact for. The thesis's own caveat (s grows as the
  catchment shrinks, amplifying errors) is in the help, and the default
  stays the method of deviation.
- 2026-09-10 — **`s` is reported whichever method ran.** It costs
  nothing, since the filtered catchment function is already computed,
  and it is the number that says how far the approximation reaches: s
  near 1 means the filter barely attenuates the catchment.
- 2026-09-10 — **WP5 5e shipped as 5.8.0, and the reader only reads.**
  `readGrid` neither regrids nor fills: the two choices that change
  numbers - what a NaN means, which latitude type a grid is on - stay
  with the caller, and both are loud. `analysis` refuses NaN until `Fill`
  is given, and `readGrid` reports the latitude type rather than assume
  one ("" for a grid from elsewhere).
- 2026-09-10 — **One CF time decoder, not two.** `readMascon`'s own
  pattern could not read GravIS's one-digit month; writing a second,
  better one for `readGrid` would have left two parsers of one fact
  (A17). Both call the private `cfTimeToYears`, which never raises, so
  each keeps its own identifiers - the `filterSpec` pattern.
  `readMascon` was captured on the real CSR file before the edit and is
  bitwise unchanged.
- 2026-09-10 — **`analysis` refusing NaN is a MINOR, not a MAJOR.** No
  documented call gave a meaningful result with NaN in the grid: they
  reached every coefficient. The refusal replaces a silent failure, and
  `Fill` is the new, explicit way to say what the gaps mean.
- 2026-09-10 — **WP5 rows 5a, 5d, 5e and the 5b follow-on (the method
  of scale) approved** (Matthias: "Chen and Wilson paper is attached. For
  everything else, continue as suggested."). Order: 5e, the method of
  scale, 5a, 5d, one PR each. Adopted with the recommendations: the
  GravIS L3 TWS grid is 5e's real file instead of GLDAS (whose download
  needs an Earthdata login); `analysis` refuses NaN unless a fill value
  is given; the method of scale is `Method = "deviation" | "scale"` on
  `leakageDataDriven`; 5a returns mas and ms and refuses dLOD without the
  TN-14 C20. 5d's method stays open until Matthias settles it.
- 2026-09-10 — **WP4 moved out of shAnalysis, to a GNSS toolbox of its
  own** (Matthias: "This sounds a lot like a toolbox by itself. GNSS
  data need preprocessing." ... "Inversion and joint combination shall
  also be part of the GNSS toolbox."). Nothing of WP4 had been built;
  the question that prompted it was what the package would need. The
  proposal, the facts gathered for it and the open questions went into
  a handover note kept outside the repository, at Matthias's request.
  C1 and C2 go with it. What stays here is the forward side such a
  toolbox would call, which already exists.
- 2026-09-10 — **A28, A26 and the `.gitattributes` fix approved**
  (Matthias: "#107 is merged. Continue with A28, A26 and the
  .gitattributes fix"). Executed as 5.7.1, one PATCH on one PR; the
  task chip for the PDF, put up during WP7, was withdrawn.
- 2026-09-10 — **A28 covers `obpChain` too, though the finding named
  `oceanChain` only**: the same REQUIRED option with the same unchecked
  `[]` default. What `obpChain` did without it is read from its code,
  not measured - there is no GAD folder here - and the changelog says so.
- 2026-09-10 — **The mask guard sits after the `kn` and GAD checks, not
  first.** Existing tests pin `missingKn` and `missingGAD` on calls that
  also omit the mask; a guard ahead of them would have changed which
  identifier those calls raise.
- 2026-09-10 — **A26 keeps the lower-case folder after the fetched one
  instead of replacing it.** Someone on Linux may have put files there,
  following the old lookup; on Windows the two are one folder, so
  nothing moves.
- 2026-09-10 — **`.gitattributes` marks binary types only; text is not
  normalized.** `* text=auto` would rewrite every file's line endings in
  one commit, for no defect.
- 2026-09-10 — **A25 and the class-surface backlog approved** (Matthias:
  "Please continue and do both A25 and the backlog items"), read as the
  three routes the proposal named - `synthesisPoints`, the VDK filter, the
  gradient tensor - not all 21. Executed as 5.7.0 on one branch and PR.
- 2026-09-10 — **`filterSpec` does not raise when asked for two
  outputs, so each lane keeps its own identifier.** The lanes' badFilter
  identifiers are documented and test-pinned, and an identifier belongs
  to the file that raises it (A3). A parser that raised its own would
  have renamed four pinned identifiers - a MAJOR change - to remove
  duplication.
- 2026-09-10 — **It only parses; building the filter stays with each
  lane.** The lanes apply filters differently (a class method, weights
  times coefficients, a W through applyDDK) and each is pinned to its own
  numbers. Moving the build into one place would have been a second
  refactor hiding inside the first, with no bitwise guarantee.
- 2026-09-10 — **A malformed spec is now refused where it used to be
  accepted, and that is a MINOR, not a MAJOR.** No documented valid call
  changes: `"gaussX"`, a negative radius and `"DDK<file>"` were never
  in the vocabulary, and what they produced (NaN, no filter, a file read)
  was a defect. Measured before the edit, so the release notes state
  what it did rather than what it might have done.
- 2026-09-10 — **Two defects found during A25 were recorded and left
  open** (A26, A28), and one was fixed (A27). A27 sits on the lane behind
  the new `g.vdkApply`, whose test exposed it; A26 and A28 are in lanes
  A25 touched only for parsing, and fixing them would have mixed a
  behaviour change into a release whose claim is "bitwise unchanged".
- 2026-09-10 — **WP7's scope was settled by four answers** (Matthias):
  no generic `shCoefficients.filter`, no `shSeries.chain`, the two
  leakage lanes as two methods named after them, and a reachability
  gate with a backlog that may only shrink. Executed as 5.6.0 the same
  day. Each question carried a measurement rather than a preference:
  `shSeries.filter` dispatches tvANS only, the chains take folders and
  return different products, the two leakage lanes return different
  things, and 21 numerical lanes had no class route.
- 2026-09-10 — **A delegate declares its lane's options WITHOUT
  defaults and forwards only what the caller gave** (`namedargs2cell`).
  Copying each default into the method gives it two homes that can
  drift. The no-option bitwise call in each delegate test is what pins
  this: a method that grew a default of its own would stop equalling
  the lane.
- 2026-09-10 — **The leakage methods REQUIRE `Filter` although the
  functions default it.** A function handed a grid may assume the common
  filter; a method on a series would be asserting something about data
  it cannot know, and the wrong filter gives a plausible wrong answer
  with no error.
- 2026-09-10 — **`ts.write` warns instead of guaranteeing the epoch
  round trip.** A `.gfc` file has no epoch field; `shSeries.read` takes
  the epoch from the file name alone. An exact round trip would mean
  inventing a span from a mid-epoch - calendar arithmetic of its own in
  a method meant to have none. So it checks every name with the parser
  the reader uses, and says before writing which epochs would not come
  back.
- 2026-09-10 — **The reach figure in the scope question was a
  prototype's, and it erred in the unsafe direction.** The question said
  62 of 124 unreachable; the shipped gate says 66. The prototype stripped
  comments but not strings, so `readDDK`'s error message "Download it
  once with shLowLevel.fetchDDK" counted as a call, and three fetch
  helpers hung on that one string. No decision changed - the four are
  download plumbing and joined the exceptions - but the number did, and
  the release notes carry the corrected one.
- 2026-09-10 — **WP7's "method bodies contain only argument
  forwarding" gate was NOT built; the bitwise tests stand in for it.**
  Deciding statically whether a MATLAB body only forwards needs an
  expression parser - `.^ 2` building a diagonal covariance is
  arithmetic, `[infos{:}]` is not - and a cheap version would be one
  more checker that lies before it tells the truth (6.3). A test that
  the method equals the lane bit for bit, with and without options,
  proves more than any reading of the body. What IS gated: each
  lane-calling method calls its lane (DELEGATES), and every lane is
  reached or listed.
- 2026-09-10 — **The class-surface exception list lives in the gate, not
  here**, although WP7 said "list of deliberate exceptions in this
  file". A second copy would be a duplicated fact, and this file already
  records how those rot (the version bullet in 6.3). Here: the policy
  and the counts; there: the names, one reason each.
- 2026-09-10 — **WP3 approved, acceptance by self-consistency only**
  (Matthias: "Yes, but you can drop the EGM2008 reference. Self-consistency
  is fine"). Executed as 5.5.0 the same day.
- 2026-09-10 — **The geoid is refused on the ellipsoid, against one
  sentence of the WP.** WP3 said both "surface quantities keep erroring"
  and "geoid/gravity disturbance on the ellipsoid agree with a Python
  oracle". Both cannot hold: `kernelFactors` gives the geoid no radial law
  on purpose. And a proper ellipsoidal geoid needs gamma(phi) as well as
  r(phi) - normal gravity changes by about 0.5% from equator to pole - so
  moving only the radius would have shipped a correction that looks
  complete and is not. Resolved by the WP's own explicit rule; the error
  message carries the reason; Matthias can overrule it.
- 2026-09-10 — **The ellipsoid's semi-major axis is WGS84's a (6378137),
  not the coefficients' R (6378136.3).** R belongs to the series, a to the
  surface, and the house flattening is WGS84's: pairing it with R would
  describe an ellipsoid nobody uses. The two places now holding WGS84's a
  (`normalFieldCS`, `ellipsoidRadius`) are pinned together by a test.
- 2026-09-10 — **`synthesisPoints` got a helper, not an option.** It takes
  a radius per point already; a `Surface` option would have changed what
  that positional argument means. `r = ellipsoidRadius(lat) + h` does it.
- 2026-09-10 — **The sphere path was proven bitwise, not argued.** 26
  outputs captured from the unmodified code before any edit, 26 identical
  after. Second time in two days that capturing references first turned
  "should be unchanged" into "is unchanged" (`leakageCorrect` was first).
- 2026-09-10 — **A refuted claim survived in the help a user reads.**
  `shSynthesis`'s Method row said the FFT path is "5-20x faster at 1
  degree". v5.0.3 corrected the same claim in a `testPerformance` comment;
  the help row stayed wrong for two more days. Now: 1.40x at n60 on A8,
  slower than direct at n180 / 0.5 deg on MATTHIASPC.
- 2026-09-10 — **A9 CLOSED.** Two A8 runs of `2c7b779` put the four new
  workloads at 1.007 (leakage n48), 1.009 (Kalman p200), 1.021 and 1.002
  (synthesis direct/fft n180); all four joined the tight tier at 1.3.
  Every lane A9 names now fails CI on a 1.3x regression. Promoted in the
  same release that created them because the rule asks for two A8 runs
  and there were two - not because the release wanted to close.
- 2026-09-10 — **The promotion criterion was refined, in the open, after
  a run that would have broken it.** "max/min <= 1.1 on both machines"
  counts fast runs; a quiet-desktop run 0.84x below its baselines would
  have demoted `analysis_rings_n60`, the steadiest budget on A8, for the
  machine being idle. Refined to: A8 spread <= 1.1 over >= 2 runs, and no
  run on either machine more than 1.1 ABOVE its baseline - the direction
  an upper bound can actually fail in. Applied to every tight budget,
  not only the new ones, and the cost (desktop sensitivity) is written
  into the code. Recorded here because a criterion changed at the moment
  it bites looks exactly like one bent to fit - the difference has to be
  shown, not asserted.
- 2026-09-10 — **A workstation's between-SESSION spread is larger than
  its between-run spread - and here it erred the safe way.** The v5.4.1
  full-suite run measured `analysis_rings_n60` at 33.9 ms and
  `leakage_1iter_n48` at 38.7 ms against baselines of 40.2 and 46.9:
  0.84x, on a quieter machine than the one the baselines were taken on.
  Four back-to-back runs in one session understate how far a desktop
  moves (~1.2x here); A8 does not move like that (<= 1.072 across runs
  hours apart). For an UPPER bound the dangerous direction is a run
  slower than baseline, and the worst such run in the tight tier is
  still 1.057. The max/min criterion also counts fast runs, so it is
  conservative, not wrong - but a baseline measured on a busy desktop
  errs loose, and the CI gate that matters is A8.
- 2026-09-10 — **Order agreed: A9, then WP3, then WP7** (Matthias: "Ok.
  Let's do it in this order. Please continue with A9"). Read as the
  go-ahead for WP3 and WP7 in that sequence; WP3's box is to be ticked
  and its acceptance (self-consistency only, per the earlier "WP3
  self-consistency is fine") confirmed when it starts.
- 2026-09-10 — **The A9 noise was threads, not size, and not the
  timer.** Forcing ONE thread made `leakage_1iter_n24` 1.32x faster and
  its spread 1.44 -> 1.15. The budgets did not need braver factors; they
  needed workloads big enough for 16-thread BLAS to pay for its
  scheduling. Measured before deciding, which is why the fix is a size and
  not a number.
- 2026-09-10 — **The first grid-synthesis resize was sized on the wrong
  code path, and the between-run check caught it.** A cold `shSynthesis`
  sweep said nmax 120 / 1 deg was steady at 19 ms; the budget arm primes
  the Legendre cache and times a 4 ms reduction, which measured 1.82
  between runs. Re-sized on the arm itself. The stopping rule written
  down beforehand - revert to n60 unless within-run <= ~1.05 AND
  between-run <= 1.1 - is what kept this from becoming open-ended tuning.
- 2026-09-10 — **`TightFactor` 1.5 -> 1.3.** The worst single-run
  deviation from a tight-tier baseline is 1.057, so 1.3 leaves 1.23x.
  It is set now, for the four workloads with two-machine evidence,
  rather than with the promotions, so the next A8 runs test the factor
  as well as the new workloads.
- 2026-09-10 — **`leakageCorrect`'s duplicate residual chain was fixed
  in the same release as the budgets it affects, and proven bitwise
  first.** References were captured from the old code before the edit
  (16 outputs, four configurations, nmax 24 and 48, ResidualRegion ~=
  Mask included); all identical after. Fixing it after baselining would
  have made the new leakage baseline lie - §6.3's first bullet.
- 2026-09-10 — **FFT slower than direct at n180 / 0.5 deg is recorded,
  not acted on.** 31.4 against 29.9 ms on one machine at one size. A
  candidate like B2 was, to be measured across sizes before `auto` is
  touched.
- 2026-09-09 — **WP5 5b was unblocked by a PDF, and the block was real.**
  The previous session STOPPED the row rather than reconstruct the
  method from a half-remembered description, and that was right: the
  paper is paywalled (Wiley 403s from here) and the open restatements
  describe the method without giving a single equation. Matthias supplied
  the author's PhD thesis, which carries the derivation. Two details
  decide whether the method works and NEITHER is guessable — the
  deviation integral is weighted by the FILTERED catchment function
  (eq. 3.19), and the leakage extrapolation corrects a PHASE while the
  deviation integral deliberately gets none, because the thesis measured
  those phase differences and found no consistent relation. A confident
  reconstruction would have got both wrong and still produced numbers.
- 2026-09-09 — **The authors' MATLAB bundle is GPL-3 and shAnalysis is
  MIT, so nothing was copied from it.** The `DataDrivenCorrection`
  bundle (gis.uni-stuttgart.de) was read to confirm the method; the
  implementation is written from the thesis equations, which is what §2
  requires anyway ("reuse is by re-implementation"). Copying would have
  forced shAnalysis to GPL. Recorded here because the temptation is
  strongest exactly when a reference implementation is at hand, and
  because a future session should not "improve" the code by aligning it
  with that bundle.
- 2026-09-09 — **A closed-loop percentage is not enough to test a phase
  method.** The oracle's CLAIM 0 — that measuring a phase and applying
  one are mutual inverses — caught a sign error that left the other
  three claims passing while the correction was applied BACKWARDS. It
  cost 80 degrees on a -40 degree input. An estimator that is internally
  consistent can still be consistently wrong; assert the inverse pair.
- 2026-09-09 — **The oracle's first transform pair was wrong and the
  IDENTITY claim is what said so.** A hand-written analysis/synthesis
  pair made `smooth(constant)` return zero, so the decomposition missed
  by 61%. Replaced with the pair already validated in
  `validate_leakage.py` — the A17 lesson: two parsers of one fact
  disagree, and the newer one is usually the wrong one.
- 2026-09-09 — **`leakageDataDriven` refuses fewer than 12 epochs and
  refuses NaN.** Both correction steps are regressions over the WHOLE
  series, so they cannot skip a gap, and below one annual cycle the
  phase is unidentifiable — the regression still returns an angle, which
  is the dangerous part. `leakageCorrect` tolerates NaN outside its mask
  because it works per epoch; this one cannot, and the difference is in
  both help blocks rather than left to be discovered.
- 2026-09-09 — **TIER A IS BACK, on the acceptance machine.** The MATLAB
  MCP bridge answers again (R2026a Update 4, 16 threads, working tree at
  the acceptance path in §3), which retires the 2026-09-08 entry "Tier A
  is gone for now" for a session started HERE. The 2026-09-09 note that a
  re-homed session cannot go back still stands — it is about that
  session, not about the machine. Consequence: WP2's two-machine
  calibration, named all along as the one thing needing the bridge, is
  done. Practical note: the MCP call times out on a full suite, so run it
  with `matlab -batch` in the background and read the log.
- 2026-09-09 — **A cloud session had already shipped a v5.2.0 that this
  session did not know about.** `main` was `ea816eb` and the branch was
  two commits ahead with WP5 5c (GIA sigma) plus a handover written FOR a
  bridge session. This work was built on `main` and numbered 5.2.0 too.
  Resolved by MERGING their branch and renumbering this release to
  **5.3.0** — their commits are preserved, not rebased away. The lesson is
  §6.4's own, unheeded for an hour: **check `git ls-remote` and read the
  branch before choosing a version number**, not only before assuming a
  PR merged.
- 2026-09-09 — **The numpy crossover does not exist in MATLAB, and the
  option's design is what made that cheap to fix.** `ClenshawFrom = 150`
  was a real measurement — of numpy. In MATLAB `clenshaw` wins at every
  point count from 1 to 2000, because `direct` is bounded by
  `legendreALF` and `clenshaw` never calls it. The default is now 1.
  `testSynthesisPointsAutoPicksTheFasterPath` needed NO edit, because
  v5.1.0 deliberately pinned the RULE and drove the number by hand. That
  is the decision paying off: a test that had pinned 150 would have had to
  be rewritten by the person least able to judge whether the rewrite was
  honest.
- 2026-09-09 — **A9's own number is refuted, and the answer is two
  factors rather than a braver one.** `leakage_1iter_n24` moved 1.306
  across three A8 runs of untouched code, at 23 ms — so 1.3 is not
  achievable and not a small-timer artefact. But `legendre_n720`,
  `legendre_n360`, `analysis_rings_n60` and `apply_ddk_n300` never moved
  past 1.079 over fifteen runs on two machines. One global factor must
  serve the worst member, which is how ten noisy benchmarks were keeping
  four steady ones at 3x. The factor is now per benchmark against a
  STATED criterion (worst observed <= 1.1), not fitted per benchmark from
  three runs each. A9 stays open and its remaining work is named: make
  `leakageCorrect` and the Kalman step steady enough to budget.
- 2026-09-09 — **Every baseline is now a median OVER RUNS.** A single
  `PERFBASE` line can land at either end of a spread that reaches 1.7; a
  baseline that landed at the fast end would silently turn a 1.5x budget
  into a 1.1x one. A8 rows carry 45 samples (3 runs x 15), MATTHIASPC 60
  (4 x 15). This changes what the column MEANS, so it is written in the
  file's header rather than left to be inferred.
- 2026-09-09 — **Two A8 baselines existed and nobody had read them.** The
  n50 crossover pair sat in `NO_BASELINE` as "awaiting A8" while A8 had
  already measured it at `b65f9a2` — the numbers were in the job log. A
  measurement nobody reads back is not a measurement, and a backlog entry
  is a claim about the world that can go stale like any other.
- 2026-09-09 — **The agreement assertion in the new dispatch test was
  REMOVED rather than loosened.** It failed at 6e-13 per element where the
  documented bound is 5e-14 — but the two are different statistics: the
  oracle normalises by `max|direct|`, and a white-spectrum fixture cancels
  to a near-zero value whose per-element relative error means nothing.
  `testSynthesisPointsMethodsAgree` already owns that property and bounds
  it correctly, over three degrees, three quantities, both `Nmin` values
  and near-pole latitudes. Widening the tolerance would have been the §3.6
  violation; deleting a duplicate assertion that used the wrong
  normalisation is not, and the property stays guarded.
- 2026-09-09 — **WP5 5b is STOPPED, not attempted, and the reason is
  the right one.** The method of deviation is a PUBLISHED method
  (Vishwakarma et al. 2017, WRR 53, 9824-9844) and its equations are
  not reachable from this container: the paper (`agupubs.
  onlinelibrary.wiley.com`) and an open-access restatement
  (`hess.copernicus.org`) are both refused by the egress proxy, and a
  web search returns the SHAPE ("twice-filtered fields give two
  correction terms, the leakage and deviation integrals") but no
  formulas. Implementing a published method from a half-remembered
  description into a scientific toolbox is exactly the confident
  nonsense §6.3 records twice already (the A12 checker's 67 invented
  findings; the prose->field-list rewrite that was written and
  DISCARDED). It waits for the equations, not for effort.
  **What unblocks it**: the paper, the authors' own MATLAB scripts
  (they published them), or a session with internet access.
- 2026-09-09 — **This session cannot be moved to the bridge, and
  cannot spawn one either** (Matthias asked). `list_environments`
  offers exactly ONE environment, `env_017PPfKpV5xCVc3aD4pCGQ2w`,
  kind `anthropic_cloud`. The container is fixed at session creation,
  so there is nothing to re-home; and `create_session` needs an
  `environment_id`, so with no bridge environment listed a new
  session cannot be started on it FROM HERE either. Only Matthias can
  start one, on the machine where the bridge runs. Note the
  environment is named "trusted network access": the allowlist is a
  deliberate policy, not a fault - github, pypi and Anthropic's own
  services are reachable, which is why pushes and WebSearch work.
- 2026-09-09 — **WP5 5c approved and shipped as 5.2.0** (Matthias:
  "WP5 5c approved"). `removeGIA` propagates the model's rate sigma;
  the default call is bitwise unchanged.
- 2026-09-09 — **The per-epoch stacks are the right answer to the
  wrong question, and the help says so.** Quadrature gives correct
  MARGINAL per-epoch sigmas, which is what `mcPropagate` and the
  other sigma consumers need. It is NOT what a trend needs: one rate
  error applies to every epoch, so the GIA term is perfectly
  correlated in time and a trend fitted assuming independence
  understates it by ~sqrt(T). `info.rateSigmaC/S` return the rate
  sigma itself so a trend consumer can add it directly. Shipping the
  stacks without that warning would have replaced one silent error
  (GIA treated as exact) with a subtler one.
- 2026-09-09 — **The oracle failed first, and the EXPERIMENT was
  wrong, not the claim.** `validate_gia_sigma.py` initially tested
  the correlation claim on an ensemble where per-epoch noise (2e-11)
  swamped the GIA rate error (4e-12), and duly reported that
  independence was no worse — true in that regime, and irrelevant.
  Isolating the GIA component gives MC 4.03e-12 against sigmaRate
  4.00e-12 and an independence estimate of 1.15e-12: a 3.49x
  understatement against sqrt(T) = 3.46. Design the ensemble around
  the term under test, or the null result is about the fixture.
- 2026-09-09 — **A second `info` output exposed a deliberate
  over-reach in `help_audit`.** It appended EVERY classdef local
  function to EVERY method's source so `shSeries.mean` could see
  `meanWindowInfo`. Harmless while one method had an `info` output;
  `removeGIA` is the second and inherited all ten of that helper's
  fields as false findings. A12's lesson one level out. The rule is
  now REACHABILITY, transitive — the same idea A21a uses for
  identifiers — pinned in both directions plus the local-calls-local
  case.
- 2026-09-09 — **The matched pair reversed my crossover guess, and
  the number still is not set.** At the SAME 200 points A8 gives
  direct 0.0155 s against clenshaw 0.0034 s: clenshaw is 4.5x
  faster, so the crossover is BELOW 200 and `ClenshawFrom = 150` is
  too HIGH. I had argued the opposite from direct@200 versus
  clenshaw@2000 — different point counts, exactly the comparison the
  matched pair exists to forbid. The implied ~44 is an
  EXTRAPOLATION from two points at one size, so the default stays at
  150 and a second pair at 50 points brackets it. Conservative is
  not wrong: for 44 <= P < 150 `auto` returns the same answers by
  the slower path.
- 2026-09-09 — **Both paths stay, and `auto` DISPATCHES** (Matthias:
  "Keep both paths behind the Method option but make the faster one
  the default for each calculation type"). Neither path dominates:
  `direct` is linear in the point count, `clenshaw` nearly flat, so
  they cross. A single default would be wrong on one side of that
  crossover, which is why the option's default is a rule and not a
  path. The rule itself is pinned by
  `testSynthesisPointsAutoPicksTheFasterPath`, bitwise in both
  directions — and it pins the RULE, not the number 150, by driving
  `ClenshawFrom` explicitly, so the default can move when A8
  measures the real crossover without breaking the test.
- 2026-09-09 — **`clenshaw` cannot be bitwise, so nothing asserts it
  is.** It sums the same terms in a different order. WP2's
  acceptance ("bitwise, or <= 4 eps with the term named") is
  therefore INAPPLICABLE to this row, and writing that assertion
  anyway would have been asserting something arithmetic forbids.
  What is asserted: agreement with `direct` to 5e-14 (about 2x the
  oracle's worst case), and that neither path dominates the other
  against 60-digit truth — direct 52.7 eps worst, clenshaw 89.0 eps,
  with clenshaw better at three of six points. `direct` carries the
  bitwise guarantee instead, which is what lets the old pinned
  reference values stand untouched.
- 2026-09-09 — **The retired baseline was deleted, not kept.**
  `synthesis_points_n60`'s 2.2829 s measured the per-point path that
  no longer runs. Keeping it would have left a budget that passes
  vacuously — green, and measuring nothing. It goes back into
  `NO_BASELINE` to be re-measured, which is exactly the mechanism
  v5.0.2 built for the case of having no trustworthy number.
- 2026-09-09 — **The BETWEEN-run spread now exists, and it indicts one
  benchmark rather than the factor.** Two A8 runs (`f6d5529` baseline,
  `b70c947` second) give median ratios of **0.979-1.060 for the eight
  workloads at 3 ms and above** — and **1.519 for `apply_ddk_n96`** at
  1.8 ms. So 3x is not merely conservative for most of the set: a 1.3x
  budget would already be safe for eight of ten, and would fail on
  `apply_ddk_n96` for reasons that have nothing to do with the code.
  The conclusion is NOT "tighten the factor" but "a 1.8 ms workload
  cannot be budgeted": it must be enlarged until the timer stops
  dominating, and its baseline re-measured. Two runs is still two
  runs — this is a direction, not a settled number.
- 2026-09-09 — **A queued self-hosted job is not an offline runner.**
  `runAllTests (self-hosted)` sat QUEUED for 9 minutes at `b70c947`
  while every earlier run that day started in seconds, and I reported
  the runner as probably offline. It picked up at 09:45 and went green
  at 09:50. A8 is a single-runner queue on someone's machine; latency
  is normal. Do not retrigger, and do not diagnose from a wait.
- 2026-09-09 — **A9 is DOWNGRADED, not closed, and the difference is
  the whole point.** The budgets assert now, which is real: a lost
  fast path or an accidental O(n^2) fails CI. But A9's own words are
  "a 1.3x regression ships unnoticed", and a 3x threshold still lets
  one through. Marking the finding CLOSED because the machinery works
  would have been the most tempting sentence in this file and the
  least true one. It closes when the factor is set from evidence.
- 2026-09-09 — **The spread the first run measured is the WRONG one,
  and it must not be used to tighten the factor.** 15 repeats inside
  one process gave median/min <= 1.043 above 20 ms (1.114 at 1.8 ms,
  where the timer dominates). That is within-run scatter on a quiet
  machine. A budget is threatened by BETWEEN-run variation — a
  different runner load, a background job, a MATLAB update — which one
  run cannot show. Tightening from 1.04 would produce a gate that
  fails on noise, and a gate that cries wolf is worse than none.
- 2026-09-09 — **`synthesisPoints` is the measured hot spot, so B2
  stops being a hypothesis.** 2.28 s against 1.7-88 ms for every other
  budget, and 36.65 s of a 4:51 job, because it calls `legendreALF`
  once per point — 1.14 ms per point at n60. WP2 step 2 has a target
  and a number to beat, which is exactly what step 1 was for.
- 2026-09-09 — **A comment claimed 5-20x and the measurement says
  1.40x.** `benchSynthesisFFTvsDirect` documented the FFT gain at
  nmax=60, 1 deg — the exact configuration now measured as 4.28 ms
  direct against 3.07 ms fft with the cache primed identically. The
  old figure was never measured against the direct path in the same
  cache state. Corrected in place with its provenance rather than
  deleted, because the next reader deserves to know it was checked.
  This is what a budget harness is FOR: it measures the things the
  comments assert.
- 2026-09-09 — **WP2 approved, superseding the "A9 is ok" acceptance**
  (Matthias: "Go ahead with WP2"). The earlier entry stays below as the
  record it is; the risk it accepted is now being closed instead.
- 2026-09-09 — **A budget that cannot be measured yet FILTERS; it does
  not pass.** No baseline existed for any machine, and there are only
  three ways to ship that: assert against a guessed number, assert
  nothing and call it green, or say out loud that nothing is guarded.
  The third is the only honest one, so a machine with no baseline row
  raises an assumption failure — the same mechanism the four real-data
  fixtures already use — and the gate carries all ten budgets in a
  named `NO_BASELINE` backlog that may only shrink. A filtered budget
  guards nothing, and the run counter says so in the open.
- 2026-09-09 — **Baselines are per machine, not ratios against a
  calibration workload.** WP2's wording ("median of per-repeat ratios")
  suggests a dimensionless budget that would survive a machine change.
  It only would if the calibration scaled like the workload, and no one
  calibration tracks both a BLAS-bound reduction and a memory-bound
  Legendre recursion — a matmul on 16 OpenMP threads and a scalar
  column recursion do not move together. So the CSV is keyed by machine
  and the deviation from the WP is recorded here rather than in a
  comment nobody reads.
- 2026-09-09 — **The factor 3 is a specification, not a measurement,
  and is labelled as one.** §3.6 requires every tolerance to name the
  oracle it was measured against. This one has none: there was no
  baseline to measure a spread against, which is exactly the state A9
  records. The comment on `BudgetFactor` says so, and every run logs
  the min beside the median so the next session can replace the choice
  with the observed spread instead of inheriting it.
- 2026-09-09 — **`count_tests.py` counted a char-valued TestParameter
  twice, and the fix was to delete a parser, not to write one.** Adding
  `budgetCase` made it predict 19 runs where the runner runs 10: its
  rule was "a quoted word followed by a comma", correct only while the
  VALUES are unquoted. `help_audit.struct_field_names` already answers
  "what are this struct's fields" correctly, transpose heuristic and
  all, so the counter now calls it. Two parsers of one fact is A17.
- 2026-09-09 — **WP6 stage 3 approved and executed as 5.0.1** (Matthias:
  "WP6 is approved as suggested", then "retire the 24").
- 2026-09-09 — **The COVERAGE check did NOT have to be redefined, and
  that was a measurement, not a hope.** §6.4 had recorded stage 3 as
  blocked on deciding what COVERAGE should mean once per-entity pages
  went. Computing the retirement set answered it instead: 30 pages can go
  with ZERO entities losing narrative coverage, so the check keeps its
  current meaning and its teeth. Only the 6 pages that ARE the last
  mention of something were ever the problem, and they stay. A decision
  that looked editorial turned out to be arithmetic.
- 2026-09-09 — **`removeGIA.html` pointed at `shSeries.removeGIA` by
  accident before it did so by decision.** Its short name matches two
  entities (`shSeries.removeGIA`, `shClimatology.removeGIA`) and a
  `setdefault` picked one. Reading the retired page settled it — it
  documents both routes, `ts.removeGIA(gia)` first. The accident happened
  to be right; the fix was to make it a decision rather than leave it to
  ordering. It is the only ambiguous short name among the 24, which was
  checked rather than assumed.
- 2026-09-09 — **A21b approved and executed as 5.0.0** (Matthias:
  "A21b approved"). MAJOR: 29 documented, test-pinned identifiers stop
  working.
- 2026-09-09 — **A shared private check gets a CONCEPT segment, not its
  function name.** `checkPair`/`checkEpochs` guard the operand pair for
  both binary operators, `assertClean` guards the stacks for six methods.
  Naming the helper in the identifier
  (`shSeries:assertClean:nanInSeries`) would make renaming a private
  function a breaking change — the identifier would be pinned to an
  implementation detail the user cannot even see. They carry `operands`,
  `stack` and `range` instead, the help explains the segment rather than
  naming the helper, and the gate holds a three-entry SHARED_CHECKS list
  as the only exception to "the middle segment is a method".
- 2026-09-09 — **The constructor follows the mechanical rule, stutter and
  all.** `shCoefficients:shCoefficients:badInput` reads oddly, but the
  alternative — a special case for constructors — is a rule with an
  exception nobody will remember. The middle segment is the method name;
  for a constructor that is the class name.
- 2026-09-09 — **Three-part alone would be a spelling convention.** The
  gate checks that the middle segment names a real method of that class
  or one of the three declared shared checks, so `shSeries:att:badIndex`
  fails. Without that rule the release would have bought a longer string
  and no guarantee.
- 2026-09-09 — **A9 is accepted as it stands** (Matthias: "A9 is ok"), so
  WP2 is NOT started. The consequence, stated so it is not rediscovered
  as a gap: the toolbox has no speed budget, and a 1.3x regression in
  `legendreALF`, `shSynthesis`, `shAnalysisGrid`, `applyDDK`,
  `leakageCorrect` or the Kalman step still ships unnoticed. That is a
  known, accepted risk, not an oversight.
- 2026-09-09 — **A21 was split, and only the documentation half shipped.**
  A21a (document what the classes raise, per method) is a PATCH and is
  done. A21b (make the 29 two-part identifiers three-part) is MAJOR
  because `testContract` pins the current names, so it is a backlog with
  a gate behind it, not a promise: `TWO_PART_OK` may only shrink, and a
  two-part identifier outside it fails the gate today.
- 2026-09-09 — **The class rule follows REACHABILITY, not the raise
  site.** Documenting `shSeries:nanInSeries` only in `assertClean` would
  put it where `help` cannot reach — the helper is private. So each
  public method documents what it raises plus what the private helpers it
  calls raise, one hop. One hop is enough for this repository and the
  gate CHECKS that rather than assuming it: a private helper calling
  another private helper is reported as "the rule has become too
  shallow". An instrument that states the limit of its own rule is worth
  more than one that happens to be right.
- 2026-09-09 — **`minus` does not check epochs, and now says so.**
  Deriving the reachability map from the source turned up a real
  behavioural distinction: `shCoefficients.plus` calls `checkEpochs`,
  `minus` deliberately does not, because a difference between two months
  has no single epoch (it sets `epoch = NaN`). `testPairCheckIDs` pinned
  the `plus` half only, so a stray `checkEpochs` call added to `minus`
  would have passed every test. Both halves are pinned now. A derived map
  is worth more than a hand-written list precisely because it finds the
  asymmetries a human would smooth over.
- 2026-09-09 — **The writer put twelve blocks in the wrong place and no
  gate saw it.** The first anchor was the FIRST provenance line, but
  `readDDK` and eleven others carry a `Claude (...)` credit line in the
  MIDDLE of the help, so the section landed above `Inputs`/`Outputs`.
  `help_audit` was silent because its footer is `Developed by`, not
  `Claude (` — the two instruments disagreed on where a help block ends
  and neither said so. Caught in the diff, not by a check. The writer now
  anchors on the trailing provenance run AND asserts that its section is
  the last heading; that assertion immediately found a thirteenth file,
  `tvANSFilter`, whose `Options` section was itself stranded BELOW a
  credit line. Its layout was repaired rather than worked around.
  (`httpFetch`, `readSHM` and `safeMove` put `Example` last; that
  predates this work and was left alone.)
- 2026-09-09 — **A20 is closed, and the number in this file was wrong.**
  The backlog was recorded as 165 identifiers; it was **208**. That
  figure was never measured, only carried forward — the same fault §6.3
  already names ("do not write a number into this file that you did not
  just read"), committed inside the very finding that tracked the debt.
  The count now comes from the tree.
- 2026-09-09 — **`demo:casesFailed` and `demo:unknownCase` renamed to
  `shAnalysis:demo:*` as a PATCH, not a MAJOR.** Neither appears in any
  help block, `html/` page, the guide or the changelog — only at the
  raise site and in two `testContract` pins. The toolbox's rule is that
  an undocumented identifier is not part of the contract, which is the
  same reasoning that made `shSynthesisDeformation`'s rename a PATCH in
  v3.33.1 while `kernelFactors`' had to wait for 4.0.0. The audit named
  only `casesFailed`; `unknownCase` was found by reading the file.
- 2026-09-09 — **A gate that reads a computed identifier as a literal
  invents a finding.** `setup_shAnalysis` raises
  `"shAnalysis:setup:no" + locs(li, 1)` for five option names. Extending
  the gate to root functions made it report `shAnalysis:setup:no`, an
  identifier nothing raises. The rule now distinguishes a concatenated
  literal (a PREFIX — the help must name at least one member, since the
  gate cannot enumerate them) from a whole identifier. This is the A12
  lesson again: the checker lied before it told the truth, and the
  source settled it.
- 2026-09-09 — **The class files were NOT swept, and the gate says so.**
  A21 is measured (32 identifiers, 29 of them two-part) and left open on
  purpose: a class needs a per-METHOD owner rule, and renaming 29
  identifiers that `testContract` pins is a MAJOR change, not a PATCH
  ridealong. `error_id_audit.py`'s last line names its own reach rather
  than implying the whole toolbox is covered — the instrument states
  what it inspects, as `help_audit.py` and `name_coverage.py` already do.
- 2026-09-09 — **The drained backlog would have made its own test
  vacuous.** `test_backlog_only_names_files_without_a_section` looped
  over `UNDOCUMENTED`; emptying it leaves an assertion that cannot fail
  — exactly how A14's `test_legacy_name_tolerated` sat broken for a
  release after the v3.33.0 sweep drained `LEGACY`. The mechanism is now
  asserted with a TEMPORARY entry, and the no-section rule is
  fault-injected on a synthetic tree in both directions.
- 2026-09-09 — **CORRECTION, and it invalidates a decision below: CI IS the
  oracle tier.** The 2026-09-08 entry "WP3/WP4/WP5 (new numerics — the
  Python oracle can be written but nothing can be checked against it)" is
  WRONG and blocked four packages for a day. The oracle is a Python script
  that runs in any sandbox; the COMPARISON is a MATLAB test that runs on
  A8 through CI. Neither half needs a local interpreter. §2 already says
  "Python numerical pre-validation before MATLAB; the oracle is committed
  under `tools/dev/validate_*.py` in the same PR" — that is the whole
  mechanism, and it has always worked. WP3, WP5 and WP7 are unblocked and
  always were; they wait on approval, not on a bridge.
- 2026-09-09 — **WP2 is the only partial exception, and only in half.**
  Its acceptance calls for budgets calibrated on the acceptance machine
  AND A8 in the same repeat. The A8 half is available through CI, so step
  1 (making speed measurable: the budget harness, A8 baselines recorded
  in `tests/perf_log.csv`) can proceed. Only the two-machine calibration
  needs the bridge.
- 2026-09-09 — **A session created on the bridge and continued remotely
  does not go back.** This session was started on the bridge; when the
  computer restarted it was re-homed to the `anthropic_cloud`
  environment, and `list_environments` then offers only that one. The
  bridge agent being up again does not re-attach it — the container the
  tools execute in is fixed. Tier A locally requires a NEW session
  started on the bridge. Do not read "no MATLAB here" as "no MATLAB
  anywhere": check which of the three it is (this container, the bridge,
  CI).
- 2026-09-09 — **WP1 approved as 4.0.0, hard break, no shim** (Matthias:
  "4.0.0 is approved"). Executed the same session.
- 2026-09-09 — **The release notes state what actually breaks, which is
  less than the diff suggests.** `nv_casing_audit.py` measured against
  R2026a that Name-Value matching is CASE-INSENSITIVE, so renaming
  `'quantity'` to `Quantity` breaks no caller. Only `n0`/`N0` -> `Nmin`
  and the error identifiers are breaking. Claiming otherwise would have
  been a false alarm in a MAJOR release; a contract test pins that the
  old spelling still returns the identical numbers.
- 2026-09-09 — **No new value validators were added during the
  conversion.** `inputParser` validated nothing, so typing the options
  (`mustBePositive`, `mustBeMember`) would have rejected input the old
  code accepted — a behaviour change smuggled in under a mechanical
  refactor. The arguments blocks declare defaults and, where safe, size
  and class only. Tightening them is its own decision.
- 2026-09-09 — **`plotSHSpectrum`'s legacy `Field` option was kept, not
  dropped.** 4.0.0 would have been the moment to remove it, but WP1's
  scope is the parsing mechanism and the casing; removing a documented
  option is a separate call for Matthias. It survives as an
  empty-string sentinel because an arguments block has no
  `p.UsingDefaults`.
- 2026-09-09 — **A20's documentation backlog was NOT swept.** Writing
  165 identifier descriptions across 61 files in the same release that
  changed their names would have buried the breaking change in noise.
  Ownership is gated with no backlog; the documentation half carries a
  named, shrinking list instead.
- 2026-09-08 — **A10 was closed over the WHOLE public surface, not the 13
  recorded.** Measuring it turned up 22 more (A18). The gate covers package
  functions, root functions and public class methods together, because a
  gate scoped to the convenient part of a surface is how A10 stayed open.
- 2026-09-08 — **Operators are not allowlisted.** `plus`/`minus`/`times`/
  `mtimes`/`uminus`/`disp` are reachable by name, so the tests call them by
  name and check the result against the operator syntax. The allowlist holds
  exactly one entry, `runAllTests`, which cannot name itself without
  recursing.
- 2026-09-08 — **The name-coverage gate's claim is deliberately narrow and
  says so in its own output.** It proves a test mentions the entity in
  executable code; it does not prove the test asserts anything. An entity
  reached only indirectly still counts as uncovered — that is the point,
  since an indirect test is exactly what misses a rename in the callee.
- 2026-09-08 — **A19's general gate was NOT built, deliberately.** A crude
  scan for "documented option values the arguments block rejects" produced
  25 hits, 24 of them false (output-field docs, prose, the wrong method's
  options inside a class file). Shipping it would have repeated the A12
  checker's history of confident nonsense. The correct instrument scopes
  each help row to its own arguments block, and `api_data.py` already pairs
  them; it is cheap, but it is a separate row, not a bolt-on to this one.
- 2026-09-08 — v3.34.1 is a PATCH: a parser fix, a wrong help row, a new
  gate and 32 tests. No documented call or identifier changed.
- 2026-09-08 — Handover document retired to `tools/dev/HANDOVER_shAnalysis_RETIRED.md`;
  `CLAUDE.md` is the single point of truth. Evidence: PR `wp0-record`.
  *(§5 work packages still pending Matthias's approval.)*
- 2026-09-08 — WP0 executed on Matthias's instruction "continue working on the
  open WPs", which is §6.4's next action. Released as **3.33.1** (PATCH:
  documentation, tooling and one undocumented identifier rename — no numerical
  behaviour changed). Branch is `claude/scientific-toolbox-discipline-wps-17ssya`,
  not `wp0-hygiene`: the session harness pins the branch name and that
  overrides §3.3 for this run.
- 2026-09-08 — A3 split. `shSynthesisDeformation`'s identifiers were never
  documented, so renaming them is PATCH and was done here. `kernelFactors`,
  `shSynthesisGradient` and `seaLevelFingerprint` raise documented,
  test-pinned `shSynthesis:*` identifiers; renaming those is MAJOR and waits
  for WP1 (new finding A15).
- 2026-09-08 — **Correction to the entry below**: Tier A is unavailable
  *locally*, but the self-hosted runner A8 still runs `runAllTests` on every
  PR, so a change can still be checked against MATLAB — one PR round-trip
  later instead of immediately. WP0's debt was discharged that way the same
  evening. What genuinely cannot proceed is work whose ACCEPTANCE needs
  interactive measurement (WP2's speed budgets) or a decision (WP1).
- 2026-09-08 — **Tier A is unavailable until further notice** (Matthias:
  "Tier A is gone for now. we rely on tier B for the time being and finish
  everything that does not need the bridge"). Consequence, stated so it is
  not rediscovered: work proceeds on Tier B green alone, every WP row carries
  ◐ on the verification board, and the discharge that clears each ◐ is named
  in §6.2. Packages whose ACCEPTANCE needs MATLAB do not start: WP2 (speed
  budgets are measurements), WP3/WP4/WP5 (new numerics — the Python oracle can
  be written but nothing can be checked against it), WP7 (`metamorphic`
  method = low-level, bitwise). WP1 is additionally blocked on the 4.0.0
  decision. What remains Tier-B-completable: **WP6**, **A12**, **A13**.
- 2026-09-08 — WP0 and WP6 run as one release train on one branch, as §5
  anticipated for the hygiene packages. The harness pins the branch name for
  this session, so §3.3's one-WP-one-branch rule cannot be followed literally;
  the train is **3.34.0** (MINOR — WP6 adds `setup_shAnalysis(BuildSearch=)`
  and the generated reference pages).
- 2026-09-08 — WP6's per-entity **Version History is dropped**, by its own
  pre-registered rule. The bar was a changelog name-match rate > 80%: a loose
  match reaches 81% but matches `filter` against releases that never mention
  it, an anchored match reaches 74%. Every reference page links `CHANGELOG.md`
  and says why it claims no per-entity history.
- 2026-09-08 — WP6's **topic categories are deferred**, not silently dropped.
  The WP assumed "the existing tag categories"; there are none in the data,
  and deriving them from `helptoc.xml` maps 163/198 entities with 75 in one
  catch-all. The reference index groups by what is derivable (class, class
  methods, package, root, A-Z). Assigning topics is an editorial call for
  Matthias, not a derivation.
- 2026-09-08 — The section vocabulary of help blocks is now closed and gated:
  `Inputs`, `Outputs`, `Options`, `Example`, `Error identifiers`,
  `References`. Near-miss spellings are rejected by name. Prose sub-headings
  inside a description are explicitly not sections.

### 6.2 Verification board (◑ = one tier only, ☑ = both)
| WP | Static gates | Tier A (MATLAB) | CI | Merged |
|---|---|---|---|---|
| audit 2026-09-08 | ☑ read | — | — | — |
| WP0 (v3.33.1) | ☑ 9 gates + 4 self-test suites, 0 findings | ☑ CI self-hosted (A8), green — 268 runs | ☑ PR #95 | ☑ 2026-09-09 |
| v3.34.0 (A7, A8, A12, A13, A16, WP6.1+2) | ☑ 12 gate steps + 6 self-test suites, 0 findings | ☑ **CI self-hosted (A8), green — 269 runs, 265 passed, 4 filtered** | ☑ PR #95 | ☑ 2026-09-09 |
| v4.0.0 (WP1: A2, A3, A15) | ☑ 14 gates + 10 self-test suites + mlint, 0 findings | ☑ **CI self-hosted (A8) at `5452938`, green — 304 runs, 300 passed, 0 failed, 4 filtered**; `count_tests.py` matched EXACTLY for the third release running, per class as well as in total. First run (`ab52d4f`) also executed 304 but had 5 failures, all one cause: `plotSHSpectrum`'s `arguments` block sat below its `if ~iscell(specs)` guard, so the function did not parse. mlint_lite R6 now catches it. | ☑ PR #96 | ☑ 2026-09-09 |
| v3.34.1 (A10, A17, A18, A19-partial) | ☑ 13 gates + 8 self-test suites + mlint, 0 findings | ☑ **CI self-hosted (A8) at `7c8cb4c`, green — 301 runs, 297 passed, 0 failed, 4 filtered**; the `count_tests.py` prediction matched EXACTLY, and all 32 new tests pass. First run (`0ab29b5`) also executed 301 but had 1 failure — `testCompareDelegatesToCompareSolutions` gave `compareSeries` 8 epochs where it needs >= 12 common ones. | ☑ PR #95 | ☑ 2026-09-09 |
| v4.0.1 (A19) | ☑ 13 gates + mlint + make_demos + 11 self-test suites, 0 findings | ☑ **CI self-hosted (A8) at `0b4fb3b`, green — 304 runs, 300 passed, 0 failed, 4 filtered** (shared run with 4.0.2; both releases are on the one head) | ☑ PR #97 | ☑ 2026-09-09 |
| v4.0.2 (A20; A21 opened) | ☑ 13 gates + mlint + make_demos + 11 self-test suites, 0 findings; `count_tests.py` predicts 303 methods / 304 runs, unchanged (the two `testContract` pins changed an identifier STRING, not a method count) | ☑ **CI self-hosted (A8) at `0b4fb3b`, green — 304 runs, 300 passed, 0 failed, 4 filtered**; the prediction matched EXACTLY for the fourth release running, per class as well as in total (Contract 73, Correctness 159, Performance 12 runs, Robustness 53, Science 7). First run, no red round. | ☑ PR #97 | ☑ 2026-09-09 |
| v4.0.3 (A21a; A21b opened) | ☑ 13 gates + mlint + make_demos + 11 self-test suites, 0 findings | ☑ **CI self-hosted (A8) at `0d06e14`, green — 305 runs, 301 passed, 0 failed, 4 filtered**; the prediction matched EXACTLY for the FIFTH release running, per class as well as in total (Contract 74, Correctness 159, Performance 12 runs, Robustness 53, Science 7), and `testMinusDoesNotEnforceEpochAgreement` ran and passed. First run, no red round. | ☑ PR #98 | ☑ 2026-09-09 |
| v5.0.0 (A21b) | ☑ 13 gates + mlint + make_demos + 11 self-test suites, 0 findings | ☑ **CI self-hosted (A8) at `631d524`, green — 305 runs, 301 passed, 0 failed, 4 filtered** (shared run with 5.0.1). **TWO red rounds first, both mine, both pin errors** — see the row below. | ☑ PR #99 | ◐ pending |
| v5.0.1 (WP6 stage 3) | ☑ 13 gates + mlint + make_demos + 12 self-test suites, 0 findings; 50 hand-written pages -> 26, no entity lost COVERAGE | ☑ **CI self-hosted (A8) at `631d524`, green — 305 runs, 301 passed, 0 failed, 4 filtered**; the count prediction matched EXACTLY for the sixth release running. Round 1 (`2530e9f`) failed `testGravisChainsContract`: a pin mapped by call graph, not by which GUARD fires — `fromFolder` asserts `isfolder` (the temp folder EXISTS) then delegates to `read`. Round 2 (`f6481d7`) failed `testTN14IDs`: the pin-enumerating grep used `[A-Za-z]*` and `noC30` HAS DIGITS, so it was never rewritten — and the verification grep repeated the same character class. The new PINS rule closes the second shape. | ☑ PR #99 | ◐ pending |
| v5.0.2 (WP2 step 1 harness) | ☑ 14 gates + mlint + make_demos + 13 self-test suites, 0 findings | ☑ **CI self-hosted (A8) at `f6d5529`, green — 315 runs, 301 passed, 0 failed, 14 filtered**; the prediction matched EXACTLY for the SEVENTH release running, per class as well as in total (Contract 74, Correctness 159, Performance 22, Robustness 53, Science 7), counts parsed from the 315-row results table. The 14 filtered were the 4 real-data fixtures plus all 10 budgets, exactly as designed — and this is the run that measured the baselines. First run, no red round. | ☑ PR #99 | ◐ pending |
| v5.1.0 (WP2 step 2, B2) | ☑ 15 gates + mlint + make_demos + 13 self-test suites, 0 findings | ☑ **CI self-hosted (A8) at `640f3be` by workflow_dispatch, green — 319 runs, 313 passed, 0 failed, 6 filtered**; the NINTH exact count prediction running, per class as well as in total (Contract 75, Correctness 161, Performance 23, Robustness 53, Science 7). All three new tests passed, dispatch pin and bitwise-chunking pin included. | ☐ no PR (not asked) | ☐ |
| v5.1.1 (A8 numbers + matched-pair budget) | ☑ 15 gates + mlint + make_demos + 13 self-test suites, 0 findings | ☑ **CI self-hosted (A8) at `e8875fe`, green — 320 runs, 315 passed, 0 failed, 5 filtered**; the TENTH exact count prediction running. The matched pair measured: direct@200 0.0155142 s, clenshaw@200 0.0034370 s. | ☑ PR #101 | ◐ pending |
| v5.2.0 (WP5 5c + help_audit scoping) | ☑ 15 gates + mlint + make_demos + 13 self-test suites, 0 findings | ☑ **CI self-hosted (A8) at `b65f9a2` by workflow_dispatch, green — 326 runs, 320 passed, 0 failed, 6 filtered**; the ELEVENTH exact count prediction running, per class as well as in total (Contract 76, Correctness 164, Performance 26, Robustness 53, Science 7), and exactly the 6 the row predicted. Read back by the v5.3.0 session — the run had gone green and nobody had looked, which is also how the n50 baselines sat unused. | ☐ no PR (branch was unmerged) | ☐ |
| v5.3.0 (A22, A23, A24; A9 two-factor; WP2 both machines) | ☑ 15 gates + mlint + make_demos + 13 self-test suites, 0 findings; `NO_BASELINE` empty, 14 budgets, both machines baselined | ☑ **Tier A LOCAL on MATTHIASPC (R2026a), the first since the bridge returned** — 328 runs, count prediction matched EXACTLY (Contract 77, Correctness 164, Performance 27, Robustness 53, Science 7). Only 2 filter here, not 4: `E:\DATAPOOL` supplies the SINEX and GravIS fixtures. Then ☑ **CI self-hosted (A8) at `2a38d25` via PR #102, green — 328 runs, 323 passed, 0 failed, 5 filtered** (the 4 real-data fixtures plus `apply_ddk_n300`, which A8 had no baseline for): the TWELFTH exact count prediction running, per class as well as in total. That run also measured `apply_ddk_n300` at 23.0 ms, which is what argued it OUT of `TightBudgets` — one A8 observation is not a spread. With that baseline committed, A8 at `3c003e3` is green again with **328 runs, 324 passed, 0 failed, and only the 4 optional real-data fixtures filtered**: all fourteen speed budgets now ASSERT on both machines, which is what WP2 step 1 was for. | ☑ PR #102 | ◐ pending |
| v5.4.0 (WP5 5b: leakageDataDriven) | ☑ 15 gates + mlint + make_demos + 13 self-test suites + the new oracle, 0 findings | ☑ **Tier A LOCAL on MATTHIASPC (R2026a) — 335 runs, 333 passed, 0 failed, 2 filtered**; the count prediction matched EXACTLY, per class as well as in total (Contract 79, Correctness 168, Performance 27, Robustness 54, Science 7). All 7 new tests pass. Two red rounds locally first, both mine and both in the TESTS, not the function: a string-array `sprintf` format, and a `badNmax` case that tripped `badSize` first because the grid was not sliced with the latitudes. Then ☑ **CI self-hosted (A8) at `c1dc1d3` via PR #103, green — 335 runs, 331 passed, 0 failed, 4 filtered** (exactly the optional real-data fixtures): the THIRTEENTH exact count prediction running, per class as well as in total, and all seven new tests ran there. | ☑ PR #103 | ☑ 2026-09-10 |
| v5.4.1 (A9: four workloads replaced, apply_ddk_n300 promoted, TightFactor 1.3, leakageCorrect duplicate chain) | ☑ 15 gates + mlint + make_demos + 13 self-test suites, 0 findings; `leakageCorrect` change bitwise on 16 outputs | ☑ **Tier A LOCAL on MATTHIASPC — 335 runs, 333 passed, 0 failed, 2 filtered**; count exact per class; all fourteen budgets asserted, the four tight ones at 1.3. Then ☑ **A8 twice at `2c7b779`** (PR run + `workflow_dispatch`): 335 runs, 327 passed, 0 failed, 8 filtered each - the four fixtures plus the four new workloads, as predicted, per class as well as in total. Those two runs are the evidence the promotion rests on. A third A8 run, on the promotion commit `5d4980e` itself: 335 runs, 331 passed, 0 failed, 4 filtered - only the fixtures - with every budget asserting and the worst tight one at 1.030x. | ☑ PR #104 (A8 x3) | ☑ 2026-09-10 |
| v5.5.0 (WP3: `Surface = "ellipsoid"`, `ellipsoidRadius`) | ☑ 15 gates + mlint + make_demos + 13 self-test suites + the new oracle, 0 findings; sphere path bitwise on 26/26 pre-WP3 outputs | ☑ **Tier A LOCAL on MATTHIASPC — 346 runs, 344 passed, 0 failed, 2 filtered**; count exact per class (Contract 83, Correctness 173, Performance 27, Robustness 56, Science 7); the 11 WP3 tests passed on their first run - no red round. Then ☑ **CI self-hosted (A8) at `3f99bf3` via PR #105, green — 346 runs, 342 passed, 0 failed, 4 filtered** (exactly the optional real-data fixtures); `count_tests` confirmed the prediction against the run, per class as well as in total, and all eleven WP3 tests ran there | ☑ PR #105 | ☑ 2026-09-10 |
| v5.6.0 (WP7: eight class delegates, `Surface` through `toGrid`/`map`, `class_surface_audit`) | ☑ 16 gates + mlint + make_demos + 14 self-test suites, 0 findings; reach 58 -> 69 of 124; the 11 WP7 tests passed on their first run | ☑ **Tier A LOCAL on MATTHIASPC — 357 runs, 355 passed, 0 failed, 2 filtered**; count exact per class (Contract 94, Correctness 173, Performance 27, Robustness 56, Science 7), and all 27 performance runs asserted. Then ☑ **CI self-hosted (A8) at `78cfea9` via PR #106, green — 357 runs, 353 passed, 0 failed, 4 filtered** (exactly the optional real-data fixtures); `count_tests` confirmed the prediction per class as well as in total, and `class_surface_audit` ran in the gates job with 0 findings | ☑ PR #106 | ☑ 2026-09-10 |
| v5.7.0 (A25 `filterSpec` + eight lanes; `g.synthesisPoints`, `g.gradientTensor`, `g.vdkApply`; A27) | ☑ 16 gates + mlint + make_demos + 14 self-test suites, 0 findings; 19 valid-spec lane outputs bitwise identical before/after (plus 4 from oceanChain and greenlandChain, run on an extracted copy of the old tree and on the new; obpChain not run, for want of GAD data) | ☑ **Tier A LOCAL on MATTHIASPC — 364 runs, 362 passed, 0 failed, 2 filtered**; count exact per class (Contract 101, Correctness 173, Performance 27, Robustness 56, Science 7), and all 27 performance runs asserted. Then ☑ **CI self-hosted (A8) at `5eab68a` via PR #107, green — 364 runs, 360 passed, 0 failed, 4 filtered** (exactly the optional real-data fixtures); `count_tests` confirmed the prediction per class as well as in total, and `class_surface_audit` and `doc_sync_audit` ran in the gates job with 0 findings | ☑ PR #107 | ☑ 2026-09-10 |
| v5.7.1 (A28 in both ocean chains, A26, A29 `.gitattributes`) | ☑ 16 gates + mlint + make_demos + 15 self-test suites, 0 findings; `doc_sync`'s new xref check fired on the corrupted guide before it was rebuilt | ☑ **Tier A LOCAL on MATTHIASPC — 365 runs, 363 passed, 0 failed, 2 filtered**; count exact per class (Contract 102, Correctness 173, Performance 27, Robustness 56, Science 7), and all 27 performance runs asserted. The two `noOcean` messages were reworded while it ran - `no_map_renderer` read "coastline" in them - message text only, which no test reads. Then ☑ **CI self-hosted (A8) at `38a9a4f` via PR #108, green — 365 runs, 361 passed, 0 failed, 4 filtered** (exactly the optional real-data fixtures); `count_tests` confirmed the prediction per class as well as in total, and `doc_sync_audit` - with its two new A29 checks - and `test_doc_sync_pdf` (11 tests) passed on the ubuntu gates job | ☑ PR #108 | ☑ 2026-09-10 |
| v5.8.0 (WP5 5e: `readGrid`, `analysis(..., Fill =)`, one CF time decoder) | ☑ 16 gates + mlint + make_demos + 15 self-test suites + the new oracle, 0 findings; `readMascon` bitwise on the real CSR file and a synthetic one | ☑ **Tier A LOCAL on MATTHIASPC — 371 runs, 369 passed, 0 failed, 2 filtered**; count exact per class (Contract 104, Correctness 176, Performance 27, Robustness 57, Science 7), all 27 performance runs asserted, and the GravIS-grid test ran here on the real file. `readMascon`'s epoch assignment was split in two while it ran (`help_audit` reads `s.f = ...` assignments only); the mascon and `readGrid` tests then ran again on the final code - 14 run, 13 passed, 1 filtered (`SHX_MASCON_FILE`) - and `readMascon` was still bitwise on the real CSR file. Then ☑ **CI self-hosted (A8) at `96a1630` via PR #110, green — 371 runs, 366 passed, 0 failed, 5 filtered** (the four optional fixtures plus the GravIS grid), per class exactly as predicted (Contract 104, Correctness 176, Performance 27, Robustness 57, Science 7) | ☑ PR #110 | ☑ 2026-09-10 |
| v5.9.0 (WP5: the method of scale, `leakageDataDriven(..., Method = "scale")`) | ☑ 16 gates + mlint + make_demos + 15 self-test suites + the extended oracle (CLAIMs 4 and 5), 0 findings; the default path bitwise on 4 of 4 configurations captured before the edit | ☑ **Tier A LOCAL on MATTHIASPC — 373 runs, 371 passed, 0 failed, 2 filtered**; count exact per class (Contract 105, Correctness 177, Performance 27, Robustness 57, Science 7), all 27 performance runs asserted, and the two new tests passed on their first run. Then ☑ **CI self-hosted (A8) at `beaa434` via PR #111, green — 373 runs, 368 passed, 0 failed, 5 filtered** (the four optional fixtures plus the GravIS grid), per class exactly as predicted, and both new tests ran there | ☑ PR #111 | ☑ 2026-09-10 |
| v5.10.0 (WP5 5a: `rotationExcitation`, `ts.excitation`) | ☑ 16 gates + mlint + make_demos + 15 self-test suites + the new oracle, 0 findings; reach 73 -> 74 of 127, 9 delegates pinned | ☑ **Tier A LOCAL on MATTHIASPC — 375 runs, 373 passed, 0 failed, 2 filtered**; count exact per class (Contract 106, Correctness 178, Performance 27, Robustness 57, Science 7), all 27 performance runs asserted, and the two new tests passed on their first run. Then ☑ **CI self-hosted (A8) at `81704d3` via PR #112, green — 375 runs, 370 passed, 0 failed, 5 filtered**, per class exactly as predicted, and both new tests ran there | ☑ PR #112 | ☑ 2026-09-10 |
| v5.11.0 (WP5 5a: dLOD in ms, IERS 2010 constants, the ESMGFZ check) | ☑ 16 gates + mlint + make_demos + 15 self-test suites + the extended oracle (CLAIMs 4-6, the EOP check run with the data), 0 findings | ☑ **Tier A LOCAL on MATTHIASPC — 377 runs, 375 passed, 0 failed, 2 filtered**; count exact per class (Contract 106, Correctness 179, Performance 27, Robustness 57, Science 8), all 27 performance runs asserted, and the ESMGFZ check ran here against the real data (`SHX_EARTHROTATION_FOLDER` set for the run). Then ☑ **CI self-hosted (A8) at `413a54a` via PR #113, green — 377 runs, 371 passed, 0 failed, 6 filtered** (the ESMGFZ check joined the optional fixtures), per class exactly as predicted | ☑ PR #113 | ☑ 2026-09-10 |
| v5.12.0 (WP5 5d: `bridgeGaps`, `ts.bridgeGaps`, the `_YYYY_MM` file names) | ☑ 16 gates + mlint + make_demos + 15 self-test suites + the new oracle, 0 findings | ☑ **Tier A LOCAL on MATTHIASPC — 381 runs, 379 passed, 0 failed, 2 filtered**; count exact per class (Contract 107, Correctness 181, Performance 27, Robustness 57, Science 9), all 27 performance runs asserted, and both real-data checks - ESMGFZ and HLSST - ran here (`SHX_EARTHROTATION_FOLDER` and `SHX_BRIDGE_FOLDER` set for the run). Then ☑ **CI self-hosted (A8) at `a86dfd0` via PR #114, green — 381 runs, 374 passed, 0 failed, 7 filtered**, per class exactly as predicted | ☑ PR #114 | ☑ 2026-09-10 |
| v5.12.1 (A30: NaN refused by `shAnalysisGrid`, `leakageCorrect` without a Mask, `gridScaling`) | ☑ 16 gates + mlint + make_demos + 15 self-test suites, 0 findings; the four working paths bitwise before and after | ☑ **Tier A LOCAL on MATTHIASPC — 382 runs, 380 passed, 0 failed, 2 filtered**; count exact per class (Contract 108, Correctness 181, Performance 27, Robustness 57, Science 9), all 27 performance runs asserted. Then ☑ **CI self-hosted (A8) at `6675806` via PR #115, green — 382 runs, 375 passed, 0 failed, 7 filtered**, per class exactly as predicted, and `testNaNNeverReachesAnAnalysis` ran there | ☑ PR #115 | ☑ 2026-09-10 |
| v5.12.2 (WP2: B1 and the FFT/direct sweep measured, neither built; the `Method` help) | ☑ 16 gates + mlint + make_demos + 15 self-test suites, 0 findings; documentation only | ☑ **Tier A LOCAL on MATTHIASPC — 382 runs, 380 passed, 0 failed, 2 filtered**; count exact per class (Contract 108, Correctness 181, Performance 27, Robustness 57, Science 9), all 27 performance runs asserted. Then ☑ **CI self-hosted (A8) at `8a8141b` via PR #116, green — 382 runs, 375 passed, 0 failed, 7 filtered**, per class exactly as predicted | ☑ PR #116 | ☑ 2026-09-10 |
| v5.13.0 (WP7 backlog: `poleTideConvert`, `estimateDegree1`, `combineCenters`, `slepianProject` behind the classes) | ☑ 16 gates + mlint + make_demos + 15 self-test suites, 0 findings; reach 75 -> 79 of 128, 16 delegates pinned | ☑ **Tier A LOCAL on MATTHIASPC — 384 runs, 382 passed, 0 failed, 2 filtered**; count exact per class (Contract 110, Correctness 181, Performance 27, Robustness 57, Science 9), all 27 performance runs asserted, and both new tests passed on their first run. Then ☑ **CI self-hosted (A8) at `385e44f` via PR #117, green — 384 runs, 377 passed, 0 failed, 7 filtered**, per class exactly as predicted, and both new tests ran there | ☑ PR #117 | ☑ 2026-09-10 |
| v5.13.1 (documentation audit: help, html and guide in sync; the demo's v3.16 lookup; `doc_sync_audit` PROSE) | ☑ 16 gates + mlint + make_demos + 15 self-test suites (the new `test_doc_sync_prose`, 18 tests), 0 findings; the demo fix checked in MATLAB: D05 found the 257 fetched months it had missed | ☑ **Tier A LOCAL on MATTHIASPC — 384 runs, 382 passed, 0 failed, 2 filtered**; count exact per class (Contract 110, Correctness 181, Performance 27, Robustness 57, Science 9), all 27 performance runs asserted - unchanged from 5.13.0, as a documentation release should be; the demo fix was run on its own (D05 on the 257 fetched months) | ◐ pending | ◐ pending |
| v5.14.0 (WP8 8a: `readBasin`, `regionalBasis`, `regionalProject`, class routes; `synthesisMatrix` GridOnly) | ☑ 17 gates + mlint + make_demos + 15 self-test suites + the new oracle, 0 findings | ◑ **Tier B locally** (the bridge's device was offline). ☑ **CI self-hosted (A8) at `bc74d1b` via PR #120, green — 394 runs, 387 passed, 0 failed, 7 filtered** (the optional real-data fixtures); the count prediction matched EXACTLY, per class as well as in total (Contract 112, Correctness 188, Performance 27, Robustness 58, Science 9). One red round first, at `52913ca`: two TEST defects of mine, both root-caused - `isequal` on a basis carrying NaN, and an expected area taken from an oracle whose point-in-polygon rule drops edge points (6.3) | ☑ PR #120 | ◐ pending |
| v5.15.0 (WP8 8b: `regionalProcessModel`, `ts.regionalProcessModel`, `estimateVAR` `Sigma0Add`) | ☑ 17 gates + mlint + make_demos + 15 self-test suites + the new oracle, 0 findings | ◑ **Tier B locally** (the bridge's device offline). ☑ **CI self-hosted (A8) at `43a8b74` via PR #121, green — 399 runs, 392 passed, 0 failed, 7 filtered** (the optional real-data fixtures); the count prediction matched EXACTLY, per class as well as in total (Contract 113, Correctness 192, Performance 27, Robustness 58, Science 9). All five new tests passed on their first run - no red round | ☑ PR #121 | ◐ pending |
| v5.16.0 (WP8 8c: `regionalNEQ`, `g.regionalNEQ`) | ☑ 17 gates + mlint + make_demos + 15 self-test suites + the new oracle, 0 findings | ◑ **Tier B locally** (the bridge's device offline). ☑ **CI self-hosted (A8) at `6de6098` via PR #122, green — 406 runs, 399 passed, 0 failed, 7 filtered** (the optional real-data fixtures); the count prediction matched EXACTLY, per class as well as in total (Contract 115, Correctness 197, Performance 27, Robustness 58, Science 9). All seven new tests passed on their first run - no red round | ☑ PR #122 | ☑ 2026-10-20 |
| v5.17.0 (WP8 8d: `regionalKalman`, `ts.regionalKalman`, `rtsSmoother` `Functionals`, `B.region.core`) | ☑ 17 gates + mlint + make_demos + 15 self-test suites + the new oracle, 0 findings | ◑ **Tier B locally** (the bridge's device offline). ☑ **CI self-hosted (A8) at `9503ec3` via PR #123, green — 412 runs, 405 passed, 0 failed, 7 filtered** (the optional real-data fixtures); the count prediction matched EXACTLY, per class as well as in total (Contract 116, Correctness 201, Performance 27, Robustness 59, Science 9). All six new tests passed on their first run - no red round | ☑ PR #123 | ◐ pending |
| v5.18.0 (WP8 8e: `regionalKalman` `Background`, remove-compute-restore; A34 opened) | ☑ 17 gates + mlint + make_demos + 15 self-test suites + the new oracle, 0 findings | ◑ **Tier B locally** (the bridge's device offline). ☑ **CI self-hosted (A8) at `f4d69a5` via PR #124, green — 416 runs, 409 passed, 0 failed, 7 filtered** (the optional real-data fixtures); the count prediction matched EXACTLY, per class as well as in total (Contract 117, Correctness 203, Performance 27, Robustness 60, Science 9). All four new tests passed on their first run - no red round | ☑ PR #124 | ◐ pending |
| v5.19.0 (WP8 8h: `regionalNEQ` kind "lgd") | ☑ 17 gates + mlint + make_demos + 15 self-test suites + the new oracle, 0 findings | ◑ **Tier B locally** (no bridge). ☑ **CI self-hosted (A8) at `bf90359` via PR #126, green — 419 runs, 412 passed, 0 failed, 7 filtered** (the optional real-data fixtures); the count prediction matched EXACTLY, per class as well as in total (Contract 118, Correctness 205, Performance 27, Robustness 60, Science 9). One red round first, at `5634698`: a test bound of mine - GEMM rounds M and 2M rows differently, and the LGD's cancellation amplified it (6.3) | ☑ PR #126 | ☑ 2026-10-21 |
| v5.20.0 (WP8 8i: process-noise scales, `kalmanFilter` `Likelihood`, `buildCondFun` `Basis`, VAR(2)) | ☑ 17 gates + mlint + make_demos + 15 self-test suites + the new oracle, 0 findings | ◑ **Tier B locally** (no bridge). ☑ **CI self-hosted (A8) at `c410d72` via PR #127, green — 426 runs, 419 passed, 0 failed, 7 filtered** (the optional real-data fixtures); the count prediction matched EXACTLY. Four red rounds first, all at A8: an explosive VAR(2) fixture of mine (`26584ca`), an empty index under `shIndex`'s default Nmin 2 (`461e2b4`), the real defect A35 - `estimateVAR`'s Yule-Walker blocks transposed for Order >= 2 (`3d79780`), and a test helper of mine reading absent sigmas (`d109f59`) (6.3) | ☑ PR #127 | ☑ 2026-10-21 |
| v5.21.0 (A33: `readBasin` names and whole files; the GravIS chains on it; basin 302's polar cap) | ☑ 17 gates + mlint + make_demos + 15 self-test suites, 0 findings | ◑ **Tier B locally** (no bridge). ☑ **CI self-hosted (A8) at `d42840e` via PR #128, green — 427 runs, 420 passed, 0 failed, 7 filtered**; the count prediction matched EXACTLY, and `testGravisChainMasksAreReadBasinRegions` passed on every A8 run it was in. Red rounds before were 8i's tests riding along, and once (`2ec1496`) two Legendre budgets at 1.5x baseline with `legendreALF` untouched - 1.01x on the runs before and after (0.089 / 0.293 s against 0.088 / 0.285), so runner load, not this release | ☑ PR #128 | ◐ pending |
| v5.22.0 (A34: `FitClimatology` on both chains and their routes) | ☑ 17 gates + mlint + make_demos + 15 self-test suites + the new oracle, 0 findings | ◑ **Tier B locally** (no bridge). ☑ **CI self-hosted (A8) at `06a8200` via PR #129, green — 430 runs, 423 passed, 0 failed, 7 filtered** (the optional real-data fixtures); the count prediction matched EXACTLY, and the three A34 tests passed on their first run - no red round | ☑ PR #129 | ◐ pending |
| v5.23.0 (A36: `MaxTries`/`BaseDelay` on `fetchTN` and `fetchICGEM`; the offline tests stop sleeping) | ☑ 17 gates + mlint + make_demos + 15 self-test suites, 0 findings | ◑ **Tier B locally** (no bridge). ◐ CI self-hosted (A8) pending - predicted 431 runs | ◐ pending | ◐ pending |
| v5.0.3 (WP2 step 1 baselines) | ☑ 14 gates + mlint + make_demos + 13 self-test suites, 0 findings; `NO_BASELINE` empty | ☑ **CI self-hosted (A8) at `b70c947`, green — 315 runs, 311 passed, 0 failed, 4 filtered**; the EIGHTH exact count prediction running, per class as well as in total. All ten budgets PASSED (they filtered at `f6d5529`), and the only filtered are the four real-data fixtures. Triggered by `workflow_dispatch`, not a PR — #99 merged mid-session and `ci.yml` runs only on push-to-main, pull_request and workflow_dispatch. | ☐ no PR (#99 merged; not asked) | ☐ |

**Tier A debt: DISCHARGED for all nine releases.** The local MATLAB
bridge is gone, but the self-hosted runner A8 is not: `runAllTests
(self-hosted)` went green on PR #95 at `fcaddd2` (268 runs), `5acf14c`
(**269 runs, 265 passed, 4 filtered**) and `7c8cb4c` (**301 runs, 297
passed, 4 filtered**), on PR #96 at `5452938` (**304 runs, 300
passed, 4 filtered**), on PR #97 at `0b4fb3b` (**304 runs, 300
passed, 4 filtered**, covering 4.0.1 and 4.0.2 together), on PR #98
at `0d06e14` (**305 runs, 301 passed, 4 filtered**), and on PR #99 at
`631d524` (**305 runs, 301 passed, 4 filtered**, covering 5.0.0 and
5.0.1 — after two red rounds, both pin errors of mine). The four
filtered are the absent optional real-data fixtures throughout — `testGravisChainsRealData`,
`testUserSuppliedSINEXFiles`, `testMasconReaderOnARealFile`,
`testPublishedTrendOnARealSeries`.

So Tier A is reachable **through CI** even when it is not reachable from
a sandbox — do not record a session as Tier-B-only without saying which
of the two is meant. The 268 run refuted the predicted count (A16); the
269 run **matched `count_tests.py` exactly**, which is the first
confirmation that the counter is right about a real run and not only
about the source.

### 6.3 What the next session could be wrong for not reading
- **A duration that repeats to 0.03 s is a sleep.** Over half the A8
  suite was three offline tests waiting out a retry backoff they could
  not shorten. Profile the suite from the runner's per-test durations
  before optimising code: the expensive thing may not be numerics.
- **A speed budget can fail on runner load, and the run after says so.**
  At `2ec1496` two Legendre budgets ran 1.5x their A8 baselines in a
  release that does not touch `legendreALF`; the runs before and after
  measured 1.01x. Before calling a budget failure a regression, compare
  the same workload on the neighbouring runs - and do not re-baseline
  from the slow one.
- **Two rounding paths through an explosive model are not an identity
  test.** v5.20.0's first VAR(2) test estimated 2 x 45^2 parameters from
  240 model epochs; the estimate's companion radius was 6.8, and the
  information and gain forms, equal in exact arithmetic, drifted to
  8.6e-12 on A8. An identity comparison needs a fixture whose model is
  identifiable and stationary - and the test should assert it, as the
  fixed one now does (`specRadius < 1`). The estimateVAR warning was in
  the log; read warnings in a failing run before reading the numbers.
  The first replacement fixture then failed too, before any number: it
  used `shIndex(1)`, and `shIndex`'s default `Nmin` is 2, so the index
  was EMPTY and `estimateVAR` refused a 0 x T matrix. Read a helper's
  defaults before sizing a fixture on it. And the third run, on a
  stationary truth with 3000 epochs, still got radius 1.45: not the
  fixture, `estimateVAR` itself (A35). Two fixture defects in a row made
  the third failure look like a third; the warning said radius 1.45 for a
  truth of 0.76, and that number was the finding.
- **An oracle that implements a method correctly cannot find the
  implementation's bug unless the test compares them on the point where
  they differ.** Every VAR oracle built the Yule-Walker matrix right;
  every MATLAB test ran `Order = 1`, where the transposed blocks are the
  same. Name the configurations a test exercises against the ones the
  code admits.
- **A dense product rounds differently for a different row count.** The
  first 8h run compared kind "lgd" (M rows times B.T) with kind "points"
  (2M rows times B.T, then Combine) at 2 eps and failed at 3.7 eps: GEMM
  blocks by size, and the LGD's subtraction of two near-equal rows turns
  an eps of each into several eps of the difference. Compare such routes
  where the product is exact (the SH basis, B.T the sparse identity), or
  bound by the per-row magnitude before the cancellation.
- **A Python heredoc that writes LaTeX must use raw strings all the
  way down.** `\right` inside a plain string became a carriage return;
  text-mode reading then split the line there, and an index-based repair
  left a fragment behind that only `make_guide.py` itself caught. Write
  generator edits with the Edit tool, or `r'''...'''`.
- **`isequal` is false on NaN, whatever the bits.** A delegate test that
  compares two basis structs with `isequal` failed on A8 only for the
  Slepian basis, whose `level` and `nGlobal` are NaN; it looked like
  eigen-solver nondeterminism and was not. Compare structs that can carry
  NaN with `isequaln`.
- **An oracle's point-in-polygon rule is part of its answer.** matplotlib's
  `contains_points` leaves out points ON an edge; `inpolygon` keeps them.
  A ring starting on lon 0 put one grid column on the edge, and the
  oracle's area came out 1/244 short of the MATLAB one (v5.14.0, first A8
  run). Where a region has an exact definition, pin the handle to that
  definition, not to a second implementation's sum.
- **A tolerance can hold on one branch only.** `leakageCorrect`'s "NaN
  outside both regions is tolerated" was true with a Mask, which zeroes
  the model outside it; without one the same NaN went into the analysis
  and came out as `diverged` - the very symptom audit F-20 was written
  against. When a guard exempts a region, check every branch that reads
  it.
- **Measure a series against the reference before designing around it.**
  The unfiltered HLSST variant looked like the natural input for a
  Gaussian the user chose; at 750 km it is noise-dominated above degree
  10, and the Kalman variant halves the error. The probe took two
  minutes and turned a guess into a question with numbers.
- **A file-name parser decides whether a series has epochs at all.**
  `shSeries.read` takes each epoch from the name, and the HLSST names
  (`..._2017_08`) matched no pattern, so every epoch would have been NaN.
  Check a new product's names against `parseGraceFilename` first.
- **A published equation can be dimensionally wrong.** ESMGFZ's eq.
  (2.8) prints 2 pi Omega where only 2 pi / Omega is a time. Check the
  units of every equation taken from a document, and confirm a
  correction against data before shipping it.
- **A file's name is not its content.** The data pool's
  `deformationLoveNumbers_*` tables hold h' and l' in two unlabelled
  columns; the load Love numbers k' are in the test data's
  `loadLoveNumbers_Gegout97.txt`. `readLoveNumbers` refused the first,
  which is how it surfaced.
- **A patch that fails must stop what comes after it.** A probe patch
  missed its anchor (a `\n` collapsed in the heredoc) and the chain ran
  MATLAB on the old file anyway. Chain with `&&`, and match lines by how
  they start rather than by escaped text.
- **Write error identifiers whole in tests.** A test that built them as
  `[id 'noEarth']` from a prefix variable was invisible to the PINS rule,
  which reads literals - it read the prefix itself as a pin nothing
  raises. The gate caught it before MATLAB ran; the fix is the house
  form, one literal per pin.
- **A gate reads constructs, not documents.** SNIPPET read `<pre>`
  blocks and the guide's code(); the README quick start, every inline
  `<code>` and the guide's Courier spans were outside it, and that is where
  the one call that threw lived. Before trusting a documentation gate's
  silence, list every place a call is written and check each is read.
- **A promise in help text outlives the path that kept it.** The demo's
  help said D05/D06 switch to real data once fetchITSG has filled its
  folder; v3.16 moved the folder and the promise quietly became false. A
  lookup of a path another function writes is the A17 shape - two owners of
  one fact - and only running the demo on a machine with the data showed it.
- **A synthetic fixture can favour one method by construction.** Both
  closed loops for the data-driven correction put a uniform layer inside
  the catchment - exactly the case the method of scale is exact for - so
  its better number there says nothing about a real catchment. Before
  reading a comparison off a fixture, name what the fixture makes exact.
- **MATLAB's `regexp` DROPS the tokens of an optional group that did
  not take part.** `regexp(s, p, 'tokens', 'once')` returns fewer cells,
  not empty ones, so `tok{5}` fails when the fifth group was optional
  and absent. Python's `re` returns `None` there, so an oracle cannot
  see it; the capture on a real file did. Index tokens by count.
- **Capture before you edit even when you only move code.** Moving
  `readMascon`'s time decoding into a shared helper looked mechanical;
  the capture on the real file is what showed the helper failing, before
  a single test ran.
- **A check can pass the very file it sits next to while that file is
  broken.** `doc_sync` read the corrupted guide's version stamp without
  complaint, because ASCII85 decoding skips the inserted CR bytes; the
  file was still broken for any reader that trusts its xref offsets.
  Check the property the damage breaks, not the one convenient to read.
- **Git's text detection looks at bytes, not at file types.** A PDF
  made of ASCII85 streams has no NUL byte, so to git it is text. Mark
  binary artifacts in `.gitattributes`; do not rely on detection.
- **Run the control before explaining the treatment.** `oceanChain`
  failed with an index error on `Filter = "DDK3"`, and that went into
  a help block as a consequence of the NaN radius. It failed the same way
  on `"gauss445"` and `"none"`: the cause was a missing ocean mask
  (A28). Compare against a valid input before attributing a failure to
  the invalid one.
- **A documented identifier can be unreachable.** `vdkApply` raised
  `badSize` through an `error` call that itself threw, so the guard
  never produced its identifier (A27). A static gate sees the identifier
  raised and documented; only a test that DRIVES the guard sees the
  raise fail. A delegate test that checks error pass-through is how it
  surfaced.
- **Measure a finding's defects before fixing them.** A25 was recorded
  as duplication; running the old lanes on malformed specs turned it
  into silent NaN results and a negative radius that meant no filter.
  The release notes could say what the old code did only because the
  references were captured before the first edit.
- **Quote a number from the instrument you will ship, not from its
  prototype.** WP7's scope question carried a reach figure from a
  throwaway script; the gate, written an hour later on the repository's
  own scanner, disagreed by four, because the script read string
  literals as code. Nothing hung on it this time.
- **A reach or coverage check must blank strings, not only comments.**
  A function named in an error message ("run shLowLevel.fetchDDK
  first") is the most natural false positive there is, and it errs in
  the one direction such a check must not: it reports as reached a lane
  nothing calls. `mlint_lite.strip_tokens` already knows where a MATLAB
  literal stops; reuse it.
- **`name=value` before a `{:}` expansion is a parse error, and it came
  back twice in one day** (5.16.0, in a class delegate and in tests).
  mlint_lite catches it; write `f(x, args{:}, Name = v)` or
  `"Name", v, args{:}` from the start.
- **Tripwire counts in the self-tests move with the surface.**
  `test_count_tests` pins the run count and `test_error_id_audit` the
  number of class methods that raise identifiers; a new raising method
  moves both. Bump them in the same commit with a comment naming what
  moved - it is bookkeeping, not a regression.
- **A work package can contradict itself; resolve it by its own explicit
  rule and say so.** WP3's acceptance named the geoid, its scope said
  surface quantities keep erroring. The rule wins over the example, the
  choice goes in 6.1, and the error message carries the reason so a user
  meets the explanation where they meet the refusal.
- **Correct a refuted claim everywhere it appears, not where you found
  it.** Grep for the number. The FFT "5-20x" was fixed in one comment and
  lived on in the help block for two more days.
- **Size a benchmark on the path the budget times.** A sweep of a cold
  call measured a Legendre recursion; the budget arm primes the cache
  and times the reduction behind it, 5x smaller and noisy. The proxy
  looked rigorous and answered a different question.
- **When a mid-sized workload is noisy, try one thread before anything
  else.** If a single thread is steadier - and here it was also FASTER -
  the spread is BLAS scheduling on small matrices, and no factor fixes
  it. Only a bigger workload does.
- **Write the stopping rule down before tuning.** "Revert unless
  within-run <= 1.05 and between-run <= 1.1" is what made the synthesis
  resize a two-round decision instead of an afternoon.
- **A pushed SHA is not a running CI.** `ci.yml` fires on push-to-main,
  `pull_request` and `workflow_dispatch` only. When the branch's PR is
  merged mid-session, a further push to that branch raises NO event and
  the commit sits there green-looking and unverified. §3.7 says to read
  the SHA back with `git ls-remote`, and that is not sufficient: also
  check `gh run list` actually shows a run for it, and open a new PR if
  it does not. This has now happened twice (v5.0.3 after #99, v5.4.0
  after #102).
- **A method's published description is not its equations.** Three open
  restatements of the data-driven correction describe it accurately in
  prose ("uses twice-filtered fields to determine leakage and deviation
  integrals") and none gives a formula. Prose is enough to believe you
  understand a method and not enough to implement it. If the equations
  are not in hand, the row is STOPPED — say so, do not approximate.
- **`hilbert()` is Signal Processing Toolbox.** So is a lot of what a
  time-series method reaches for. The analytic signal is ten lines of
  FFT; check `toolbox_dependency_audit` will pass BEFORE designing
  around a function.
- **When you implement an estimator, assert its inverse.** Measuring a
  phase and applying one must round-trip. Without that assertion a sign
  error is invisible: every other claim still passes and the correction
  is simply applied the wrong way round, which looks like the method
  underperforming rather than like a bug.
- **Read the branch before you pick a version number.** This session
  built a v5.2.0 on `main` while a cloud session's v5.2.0 sat unmerged
  two commits ahead, with a handover addressed to exactly this kind of
  session. §6.4 already said "do not treat the branch as merged; check
  `git ls-remote` first" — that was read as a statement about PR status
  and it is also a statement about what work exists. `git log
  main..origin/<branch>` costs one command.
- **A constant measured in the prototype is not a constant of the
  product.** `ClenshawFrom = 150` was honestly measured — in numpy — and
  documented as such, and it still sent every station list under 150
  points down a path 2-4x slower for a whole release. When a number
  crosses languages, re-measure it there or do not ship it as a default.
- **A benchmark under ~3 ms measures the timer.** Four of them in one
  set held the global budget factor at 3x for every workload. But note
  the converse trap too: `leakage_1iter_n24` is 23 ms and still moved
  1.306 between two A8 runs, so "big enough" is not sufficient either —
  measure, do not assume from size.
- **A backlog entry can be stale in the direction that looks safe.**
  `NO_BASELINE` said the n50 pair was "awaiting A8" when A8 had already
  measured it; the numbers were sitting in a job log nobody re-read. The
  entry looked conservative and was simply wrong.
- **A failing assertion is sometimes the wrong assertion, not a wrong
  tolerance — and the difference is the normalisation.** The new
  dispatch test compared two summations per element and failed at 6e-13,
  where the documented 5e-14 is `max|diff| / max|direct|`. Widening the
  number would have violated §3.6; the honest fix was that the assertion
  duplicated a better one and should not have been written. Ask what
  statistic a documented tolerance actually bounds before reusing it.
- **`mlint_lite` now catches an unterminated literal (R7), and the gap
  it filled is the shape to look for.** It reported zero findings on a
  file MATLAB would not parse at all, so the tests in it would have
  VANISHED rather than failed — a count mismatch, not a red test. When
  adding a rule, prefer reading the fact off a scanner that already
  computes it over writing a second parser.
- **One machine can have two names.** `COMPUTERNAME` and `hostname`
  disagreed in case on the acceptance machine, and the budget harness
  keyed baselines on whichever MATLAB inherited. The failure mode was
  silent: an unmatched row FILTERS a budget instead of failing it.
  Whenever a lookup key comes from the environment, ask what happens
  when it misses — and prefer a miss that is loud.
- **A faster algorithm makes its own budget lie.** Changing which
  summation `synthesis_points_n60` runs made its committed baseline
  meaningless — the budget would still have gone green while
  measuring code that no longer executes. When an optimisation lands,
  RETIRE the baseline it invalidates in the same commit; a budget is
  only as honest as the workload it was measured on.
- **The budget set has one member that cannot be budgeted.**
  `apply_ddk_n96` runs in 1.8 ms and moved 1.519x between two runs of
  the same commit on the same machine, while everything at 3 ms and
  above stayed inside 0.979-1.060. Enlarge it (and re-measure its
  baseline) before anyone reads its number as signal, and do not let
  its noise set `BudgetFactor` for the other nine.
- **A budget that asserts is not the same as a budget that catches
  what you care about.** The ten budgets are live (v5.0.3), and A9 is
  still open, because 3x does not catch A9's own 1.3x. Two different
  questions — does the gate fire at all, and does it fire at the
  right place — and only the first is answered.
- **Do not tighten `BudgetFactor` from the within-run spread.** The
  first run's median/min (<= 1.043 above 20 ms) describes 15 repeats
  in one process on a quiet machine. What can break a budget is
  between-run variation, which needs several runs' medians. Tightening
  from 1.04 buys a gate that fails on noise.
- **The log is the artifact; the artifact is not reachable.** The A8
  `PERFBASE,` lines had to come from the job log, because
  `actions/upload-artifact` and the raw-log redirect both land on
  `*.blob.core.windows.net`, which the egress proxy refuses. Use
  `mcp__github__get_job_logs` with a large `tail_lines`; it saves
  oversized output to a file that CAN be grepped, which is better than
  paging it into context. And note the suite order is ALPHABETICAL —
  testPerformance runs third, so its stdout is in the MIDDLE of the
  log, not near the end where the results table sits.
- **A parser you write beside one that already exists will disagree
  with it, and the cheap one will be wrong.** `count_tests.py` counted
  TestParameter values by regex; `help_audit.struct_field_names` counts
  struct fields properly (even arguments only, transpose-aware). They
  agreed for two releases because no parameter had quoted VALUES. The
  first one that did made the prediction 19 against a real 10 — and a
  missed prediction is a finding by §3.5, discovered on the runner.
- **A cost model beats a taste.** The Legendre budgets use 181 / 91 /
  31 rings because `P` is `(nmax+1)^2 x nlat` doubles: n720 over the
  1441 rings B1's protocol names would allocate about 6 TB. Compute
  the array before choosing the fixture, not after the runner dies.
- **A character class is an enumeration, and a narrow one silently
  shortens the list.** A21b's pins were enumerated with
  `[A-Za-z]*` for the reason segment, so `shCoefficients:noC30` — digits
  — was never in the list, never rewritten, and cost a CI round. The
  grep written to VERIFY the sweep used the same class and confirmed the
  same blind spot. When a sweep is driven by a pattern, test the pattern
  against a known member of the awkward class before trusting its count.
- **Nothing read `tests/` until v5.0.1.** `error_id_audit`'s PINS rule
  now checks that every toolbox identifier a test names is one something
  raises. Its reach is stated in its own docstring and is narrower than
  it sounds: it catches a pin naming an identifier that exists NOWHERE,
  not a pin naming a REAL identifier the call under test cannot reach —
  that needs per-call guard analysis. Of A21b's two red rounds it
  prevents the second, not the first, and the gate says so.
- **A gate can be silenced by its own inputs.** The PINS rule first
  harvested prefix literals from `tests/` as well as the toolbox, so the
  bad pin was read as its OWN prefix and the rule went quiet on exactly
  the defect it was written for. The injection not firing is what
  revealed it. Ask what a rule reads, and whether the thing being
  checked is inside that set.
- **Check BOTH quotings when rewriting HTML links.** WP6 stage 3's first
  pass rewrote `href="x.html"` and missed `href='x.html'`; the See-also
  lines of `shSynthesis` and `legendreALF` use single quotes, and the
  pages would have shipped with dead links that no gate then covered.
  Verify a sweep by searching for what should be ABSENT afterwards, not
  by trusting the count of what was changed.
- **A decision that looks editorial may be arithmetic.** Stage 3 sat
  blocked for two releases on "what should COVERAGE mean afterwards".
  Measuring which pages could go without costing coverage dissolved the
  question: 30 could, so the check never had to change. Measure before
  asking for a decision — the measurement sometimes IS the decision.
- **An identifier must not name something the user cannot see.** A21b's
  first instinct was `shSeries:assertClean:nanInSeries` — mechanical, and
  wrong: `assertClean` is private, so the contract would have been pinned
  to a name the user cannot reach and a refactor could not touch. A
  shared check gets a concept name (`stack`), and the gate keeps that
  list to three entries so it stays an exception rather than a habit.
- **When one old name maps to several new ones, rewrite per SITE.**
  `shSeries:noEpoch` became four identifiers and `shCoefficients:badInput`
  four; a `sed` would have collapsed them. The same applies to the TEST
  pins: each was remapped by line to the method the call actually
  reaches, which needed reading `twsChain` to find it delegates to
  `gravisL2B` and thus to `fromFolder`, not `read`.
- **One constant must answer one question.** `CLASS_FILES` was both the
  list the CLASS pass reads AND the skip-list keeping class files out of
  the root-function pass. A self-test that emptied it to focus on the
  package silently re-admitted `shSeries.m` as a ROOT function owning
  `shAnalysis:shSeries:*`, and the suite went red for a reason unrelated
  to what it tested. Same shape as A17. When a name serves two purposes,
  split it before the two purposes drift.
- **Pin the half that is NOT true as well as the half that is.**
  `testPairCheckIDs` proved `plus` raises `epochMismatch`; nothing proved
  `minus` does not, so adding an epoch check to `minus` would have been
  invisible. When documenting a deliberate asymmetry, test both sides of
  it.
- **An identifier can be BUILT, and then no scan can name it.**
  `setup_shAnalysis` raises `"shAnalysis:setup:no" + locs(li, 1)` for
  five option names. Every static instrument here — grep, the gate, the
  reader — sees the literal and not the identifier. Treat a concatenated
  literal as a prefix and make the HELP carry the real names; do not let
  a checker report the fragment as if it were an identifier, which is
  what it did first.
- **Draining a backlog can silently disarm the test that guards it.**
  Any test that loops over the backlog becomes vacuous the moment the
  backlog is empty — A14 already happened once this way. When you empty
  one, re-express its test as a mechanism assertion with a temporary
  entry, and fault-inject the rule the backlog exempted.
- **§1 is the only place in this file that states the version.** This
  bullet used to repeat it and went stale three times running (3.33.1 when
  the tree was 3.34.0, then 3.34.0 when it was 3.34.1) — a duplicated fact
  rots, which is the very rule (R1) the releases below enforce elsewhere.
  Read the version from §1's table or from `Contents.m` line 2. The package
  is `+shLowLevel`; any memory saying `shx.*` is stale.
- The guide PDF is current (rebuilt at each bump) and its stamp is gated.
  Building it needs `pip install reportlab matplotlib` — not present by
  default in a fresh sandbox.
- **A green gate is not a correct document.** Nine gates were green while 65
  help blocks carried two contradictory sections and ELEVEN functions
  documented struct fields that do not exist. Read what an instrument
  inspects before trusting its silence — and prefer an instrument that
  states its own reach, as `help_audit.py`'s last line now does.
- **A new checker lies before it tells the truth.** The A12 checker produced
  67 invented findings across three bugs, then five more classes of wrong
  result during the conversion (MATLAB's `'` is transpose after a value;
  `struct()` alternates name and value; a class method's source is not the
  whole class file). Read its output against the source before acting on
  it, and fault-inject every rule.
- `doc_sync_audit.py` requires the top CHANGELOG heading to equal
  `Contents.m` and rejects `Unreleased` headings: bump the version in the
  same commit, then regenerate `apiReference.html`, `html/ref/` and the
  guide PDF, all of which carry the stamp.
- **Do not push while a CI run is in flight.** The self-hosted runner has
  a persistent temp folder, and a superseding push CANCELS the running
  MATLAB process, which then executes no `onCleanup`. That is how a
  half-written `plain.gfc` survived into the next run and failed
  `testProvenanceSidecarsDoNotBreakTheRoundTrip` with a bogus
  `shSeries:sizeMismatch` (2026-09-08). Tests now use `tempname` so a
  leftover cannot be found again, but a cancelled run still wastes an A8
  slot and can leave litter. Batch the pushes.
- **A gate's reach can be defined by the bug it should catch.** A17:
  `refpages_audit`'s COVER check compared the generated pages against
  `api_data.py` — the very artifact the broken extractor wrote. Zero
  findings, one missing page. When two instruments read the same fact,
  check them against ground truth (here: MATLAB's rule that a file defines
  the function it is named after), never against each other. Two of this
  repo's four surface parsers were blind the same way and agreed.
- **Fault injection finds bugs in the fix, not only in the code.** The
  first attempt at A17's continuation joiner happily joined a COMMENT line,
  and a `(base MATLAB only)` in the help text supplied the closing paren —
  a signature that parsed to nonsense instead of failing. That surfaced
  only because the injected fault did NOT fire when it should have. An
  injection that behaves unexpectedly is a finding about the instrument.
- **mlint_lite is only as good as its rules, and a missing rule is a
  silent CI failure.** WP1 moved `plotSHSpectrum`'s `arguments` block to
  where `inputParser` had been - below the function's `if ~iscell(specs)`
  guard. MATLAB requires the block to be FIRST, so the function stopped
  parsing and five tests went red while mlint_lite reported zero
  findings. R6 now checks it, with a self-test. When you convert a
  preamble, check what was ABOVE the thing you replaced, not only what
  you wrote.
- **mlint_lite is the only MATLAB syntax check a Tier-B session has, and it
  earns its keep.** It rejected fifteen `(gA + gB).C` lines: MATLAB cannot
  index into a parenthesised expression. Method dot-chains (`ts.at(k).toGrid`)
  are fine and the repo already uses them; parenthesised expressions and
  plain function calls are not. Run it on every changed `.m`, and read the
  new tests for the same shape it cannot see (`mk(1).FieldKind`).
- **Read the delegate's GUARDS, not only its options.** `shSeries.compare`
  goes to `compareSeries`, not `compareSolutions` like
  `shCoefficients.compare`; `ts.climatology()` needs >= 6 epochs;
  `compareSeries` needs >= 12 COMMON epochs; `shCoefficients` properties
  are `SetAccess = private` so a test cannot set an epoch. The first three
  were caught statically by reading the source; the fourth (12 epochs) was
  NOT — its `arguments` block says nothing, the guard is an `error` a
  hundred lines in, and it cost the one red test of v3.34.1. When writing
  a test for a function you cannot run, grep it for `error(` and `assert(`
  before choosing fixture sizes.
- **Do not write a number into this file that you did not just read.** The
  v3.34.1 per-class test counts were guessed (161/68) and were wrong
  (159/70) — in the same edit that closed a finding about unmeasured facts.
- **Run what CI runs, not what §3.4 lists — and if they differ, fix §3.4.**
  v3.34.1 went out with eleven local gates green and `gates` red: CI also
  runs `make_demos.py --check`, which §3.4 never named, and `demos.xml`
  carries the version stamp so the bump alone made it stale. The list in
  §3.4 is now the authority and must equal `ci.yml`; `doc_sync_audit.py`
  gained the `demos.xml` VERSION check so the omission cannot cost a CI
  round-trip again.
- **A gate that cannot see a construct is not evidence about it.**
  `nv_casing_audit` reads arguments blocks, so six functions using
  `inputParser` sailed through v3.33.0's casing sweep with lowercase
  options. Before trusting "0 findings", ask what the instrument
  parses, not what it is named after.
- **Check whether a rename actually breaks anything before calling it
  breaking.** MATLAB matches Name-Value names case-insensitively
  (measured, see `nv_casing_audit.py`'s header), so most of WP1's
  option sweep is not a break at all. The MAJOR bump is earned by the
  error identifiers and by `n0`/`N0` -> `Nmin`, nothing else.
- **A mechanical refactor must not smuggle in validation.**
  `inputParser` validated nothing; adding `mustBePositive` or
  `mustBeMember` while converting would reject input the old code
  accepted, under cover of a "no behaviour change" commit.
- **Rename identifiers per file, never globally.** The same old id
  (`shSynthesis:missingLoveNumbers`, `shSynthesis:badInput`) mapped to
  two different owners depending on which file raised it. A repo-wide
  sed would have produced confident nonsense.
- Do not re-propose what §1.1 lists. The first audit draft did, without
  repository access; that draft is superseded by this file.
- Tier B sessions cannot measure B1–B3 or set WP2 budgets. Say so; do not
  estimate speedups.

### 6.4 Next action

Done and on PR #95: WP0, WP6 stages 1-2, and findings A1, A3 (partial),
A4, A5, A6, A7, A8, A10, A11, A12, A13, A14, A16, A17, A18 closed;
A19 partially.

**Seven releases are merged to `main` (PR #95..#98). PR #99 is still
OPEN** — it was believed merged on 2026-09-09; `state: open`,
`merged: false`, `mergeable_state: clean`, and `origin/main` is still
`a3fa54b`, the #98 merge. Both of its jobs are green at `631d524` and
again at `d110752`. 5.0.0, 5.0.1 and now 5.0.2 sit on the branch behind
it. **Do not treat the branch as merged; check `git ls-remote` first.**

**Every audit finding in §4.1 is CLOSED** - A9 last, in v5.4.1, after WP2 reopened it the day it was accepted. A22-A24 were found and closed on the way.

**WP3, WP4, WP5 and WP7 wait on approval only** — see the 2026-09-09
correction in §6.1. Their acceptance is a MATLAB test against a committed
Python oracle, and CI runs exactly that. What each additionally needs
from Matthias was measured on 2026-09-09: WP7 and WP5 5b/5c need only the
tick (5b uses the shipped `data/gravis/basins_*.json`); WP3 needs either
published EGM2008 undulations as a fixture or permission to drop that
half of its acceptance (`tests/test_data` does not exist and no EGM2008,
GLDAS, tenv3 or GNET file is in the tree); WP5 5a/5d/5e need a reference
series, a Swarm fetch policy and one GLDAS file; WP4 needs the five
signatures signed off and a real GNSS network.

**5.0.0 and 5.0.1 are GREEN on A8 at `631d524` via PR #99** — 305 runs,
301 passed, 0 failed, 4 filtered; the count prediction matched exactly
for the sixth release running. Two red rounds preceded it, both mine and
both pin errors; the second shape is now gated by the PINS rule.

**Done for 5.0.3**: the ten `PERFBASE` lines from A8 at `f6d5529` are
committed and `NO_BASELINE` is empty. The budgets assert.

**HANDOVER — what a session ON THE BRIDGE should pick up first.**
Everything is pushed; nothing lives only in the cloud container. The
branch is `claude/scientific-toolbox-discipline-wps-17ssya` at
`b65f9a2` (v5.2.0), two commits ahead of `main` at `ea816eb`.
A bridge session gains BOTH Tier A locally (no CI round-trip) and
internet, which unblocks all three stuck items at once:
1. **WP5 5b** needs the Vishwakarma et al. 2017 equations — the
   paper, or the authors' published MATLAB scripts. Nothing else
   about the row is hard: `applyChain` (analysis -> filter ->
   synthesis) inside `leakageCorrect.m` is the operator it needs,
   and it is three lines to re-implement in a new file.
   **Do not reconstruct the equations from memory.**
2. **WP3** needs published EGM2008 undulations for its `reference`
   half. Matthias approved dropping that half ("WP3 self-consistency
   is fine"), so it can proceed WITHOUT the bridge — but with
   internet the stronger acceptance is available again. The geometry
   is settled: the ellipsoid's geocentric radius at geocentric
   latitude phi is `r(phi) = R*sqrt((1-e^2)/(1-e^2*cos^2(phi)))`,
   `e^2 = 2f - f^2`, and it enters the existing `(R/r)^p_n` law that
   `kernelFactors` already applies for `Height` (line ~195,
   `kernel .* (R/(R+Height)).^radialExp`). `Height` adds to `r(phi)`.
3. **WP4 / WP5 5e** need `geodesy.unr.edu` (.tenv3, open) and a GLDAS
   file (GES DISC needs an Earthdata login even with egress).
   Remember the CORRECTED framing: a "fetch" in this toolbox is a
   `Download` level in `setup_shAnalysis` plus a fetcher with
   `BaseURL=`/`Mirror=`, tested offline against a temp directory
   (`testFetchLoveNumbersMirror` is the pattern). The fetcher is
   buildable and testable WITHOUT network; only the live URL needs it.

**Next concrete actions, in order of what they buy:**
1. **The whole order agreed on 2026-09-10 is DONE**: A9 (v5.4.1), WP3
   (v5.5.0, merged via PR #105) and WP7 (v5.6.0, merged via PR #106).
2. **DONE in v5.7.0: A25, one filter-spec resolver** (`shLowLevel.filterSpec`). A28, A26 and A29 (the guide PDF's `.gitattributes`) DONE in v5.7.1. Eight parsers of `"gauss300"` /
   `"DDK3"` / `"none"` / W, accepting different subsets. The resolver
   becomes the single home; each lane keeps its admitted subset.
3. **The class-surface BACKLOG** (18 lanes after v5.7.0 took `synthesisPoints`, `vdkApply` and `shSynthesisGradientTensor`; `class_surface_audit.py`).
   Cheapest routes: `synthesisPoints` beside `g.synthesis`, `vdkApply`
   beside `applyDDK`, `shSynthesisGradientTensor` beside `g.gradient`.
   An entry that gets a method must leave the list in the same commit -
   the gate enforces it.
4. **DONE v5.12.2, the FFT/direct sweep**: `direct` is 0-14 percent
   faster on MATTHIASPC at 13 sizes, FFT 1.40x faster at n60 on A8; no path
   wins on both machines, so `auto` keeps FFT.
5. **WP5 follow-ons**: the method of scale is DONE (v5.9.0), and it
   became an option on `leakageDataDriven`, not a third leakage method
   on `shSeries`: it shares every estimate with the method of deviation.
6. **B1 (packed Legendre): MEASURED, NOT BUILT (v5.12.2)** - 1.11-1.69x
   raw, 0.92-0.99x as a drop-in; below the 2x bar.
7. **WP5 is DONE**: 5e in v5.8.0, the method of scale in v5.9.0, 5a in v5.10.0 and v5.11.0, 5d in v5.12.0. Nothing of WP5 is open: the axial factor keeps eq. (1)'s 0.753 by Matthias's decision, and ESMGFZ's 0.844 is an `AxialFactor` away. Then the order Matthias agreed on 2026-09-10: A30 (DONE v5.12.1), B1 and the FFT/direct sweep (both measured, neither built, v5.12.2), and the class-surface backlog (four routes in v5.13.0; the 14 lanes left each need more than a forward). **WP4 is moved out** to a separate GNSS toolbox (2026-09-10); do not start it here.

**What a Tier-A session should know about running the suite here.** The
MATLAB MCP tool times out on anything suite-sized. Run it detached and
read the log:
```
"/c/Program Files/MATLAB/R2026a/bin/matlab.exe" -batch "run('<script>.m')" > run.log 2>&1
```
The machine label for baselines is `MATTHIASPC` (upper-cased since
v5.3.0). Only 2 tests filter here rather than A8's 4, because
`E:\DATAPOOL` supplies the SINEX and GravIS fixtures.

To re-run the gates and the prediction from a fresh sandbox:
```
pip install reportlab matplotlib && \
  for g in tools/*.py tools/dev/{no_map_renderer,check_api,api_audit,attribution_sweep}.py; do python3 $g; done && \
  for t in tools/tests/test_*.py; do python3 $t; done && \
  python3 tools/dev/count_tests.py
```

---
*shAnalysis v3.33.0 audited | 2026-09-08 18:30 UTC | Claude Fable 5.1 |
WP0 (v3.33.1), A7/A8/A12/A13/A14/A16 + WP6.1-2 (v3.34.0),
A10/A17/A18 (v3.34.1), WP1/A2/A3/A15 (v4.0.0), A19 (v4.0.1),
A20 (v4.0.2), A21a (v4.0.3), A21b (v5.0.0)
WP6 stage 3 (v5.0.1), WP2 step 1 (v5.0.2 + v5.0.3)
WP2 step 2 B2 (v5.1.0 + v5.1.1)
and WP5 5c (v5.2.0) |
2026-09-08..09 | Claude Opus 5 |
the first four releases green on A8 via CI — 4.0.0 at `5452938`:
304 runs, 300 passed, 0 failed, 4 filtered.
4.0.1 and 4.0.2 green on A8 at `0b4fb3b` via PR #97: 304 runs,
300 passed, 0 failed, 4 filtered, no red round.
4.0.3 green on A8 at `0d06e14` via PR #98: 305 runs, 301 passed,
0 failed, 4 filtered - the fifth exact count prediction running.
5.0.0 and 5.0.1 green on A8 at `631d524` via PR #99: 305 runs,
301 passed, 0 failed, 4 filtered, after two red rounds.
5.0.2 green on A8 at `f6d5529` via PR #99: 315 runs, 301 passed,
0 failed, 14 filtered - the SEVENTH exact count prediction running,
and the run that measured the ten speed baselines now committed in
5.0.3.
5.0.3 green on A8 at `b70c947` by workflow_dispatch: 315 runs,
311 passed, 0 failed, 4 filtered - the EIGHTH, and the first run in
which all ten speed budgets ASSERT rather than filter.
5.1.0 green on A8 at `640f3be`: 319 runs, 313 passed, 6 filtered.
5.1.1 green on A8 at `e8875fe` via PR #101: 320 runs, 315 passed,
0 failed, 5 filtered - the TENTH exact count prediction running, and
the run whose matched pair put clenshaw 4.5x ahead of direct at the
same 200 points.
5.2.0 green on A8 at `b65f9a2` by workflow_dispatch: 326 runs,
320 passed, 0 failed, 6 filtered - the ELEVENTH, read back a release
late because nobody looked at a green run.
5.3.0 green BOTH ways: local Tier A on MATTHIASPC (328 runs, 326
passed, 0 failed, 2 filtered) and A8 at `2a38d25` via PR #102 (328
runs, 323 passed, 0 failed, 5 filtered) - the TWELFTH exact count
prediction, and the first release since the bridge returned. With
apply_ddk_n300's A8 baseline committed, `3c003e3` runs 328 with 324
passed and only the 4 optional fixtures filtered: every speed budget
asserts on both machines.
5.4.0 (WP5 5b) green both ways: local 335 runs / 333 passed / 2
filtered, and A8 at `c1dc1d3` via PR #103 with 335 / 331 / 0 failed /
4 filtered - the THIRTEENTH exact count prediction. |
Developed by Matthias Weigelt with the help of Claude.*
