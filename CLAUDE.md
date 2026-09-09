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
| Version | **5.0.2**, 09-Sep-2026 | `Contents.m` line 2, `CITATION.cff`, `CHANGELOG.md` line 3 agree |
| Branches | `main` only; `claude/getframe-recapture` and `claude/readshm` are gone (merged/deleted) | `GET /branches` |
| Public surface | 3 classes / 71 methods, 122 `+shLowLevel` functions (+4 private), 3 root functions | `tools/dev/api_extract.py` run in sandbox |
| Tests | 5 classes, **305 methods / 315 runs**: Correctness 159, Contract 74, Robustness 53, Science 7, Performance 12 methods (22 runs, `budgetCase` x10 + `nmaxP` x2). 4 filter out without the optional real-data fixtures; from v5.0.2 the 10 speed budgets also filter on a machine with no baseline. The counter has matched the runner EXACTLY on the last six green A8 runs (269, 301, 304, 304, 305, 305); the one time it did not was A16, before it existed. | `python3 tools/dev/count_tests.py` |
| Python oracles | 16 `tools/dev/validate_*.py` + `tools/audit/*` | listing |
| Docs | **26** hand-written `html/*.html` (24 per-entity duplicates retired in v5.0.1, WP6 stage 3) + **200 generated `html/ref/*.html`** (one per entity + index, `make_refpages.py`), one shared `html/shAnalysis.css`, `helptoc.xml`, `info.xml`, guide PDF, generated `html/apiReference.html`. `docs/` holds the PDF and `apiExamples.json` only - no HTML page lives outside `html/` (gated). | listing |
| CI | `gates` job on ubuntu (help_audit, doc_sync_audit, no_map_renderer, toolbox_dependency_audit, nv_casing_audit, fixture_tag_audit, gate self-tests `tools/tests/`, `count_tests`, `name_coverage`, `error_id_audit`, `option_values_audit`, `refpages_audit`, `make_demos --check`, `perf_baseline_audit`) + `runAllTests (self-hosted)` on A8/R2026a; fixtures from tag `fixtures-2026-08` | `.github/workflows/ci.yml` |
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
   `python tools/error_id_audit.py`,
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
| A9 | M | **REOPENED and HALF-CLOSED in v5.0.2** — accepted as it stood on 2026-09-09, then approved as WP2 the same day. Step 1 makes speed MEASURABLE: ten budgets (`legendreALF` n96/n360/n720, `shSynthesis` direct and fft, `synthesisPoints`, `shAnalysisGrid` rings, `applyDDK`, one `leakageCorrect` step, one Kalman chain), 15 repeats, median against 3x a per-machine baseline in `tests/perf_baseline.csv`. **The budgets do not yet GUARD anything**: no baseline exists, so all ten filter, and the gate carries them as a named backlog rather than pretending otherwise. The finding closes when the A8 baselines are committed and `NO_BASELINE` is empty. Original finding: `testPerformance` asserts exactly one ratio (cache warm/cold) and one absolute bound (`dt < 5 s`); everything else is logged, not gated. | `python3 tools/dev/perf_baseline_audit.py` |
| A10 | L | **CLOSED v3.34.1** — and the finding was **larger than recorded**: 13 package functions plus **22 public class methods** (A18). `tools/dev/name_coverage.py` measures it now, over the whole public surface, with comments stripped so a name in a `% see also` line does not count; it states its own reach in its last line (naming is not exercise). 32 new tests, each asserting a property the function's own help states. One allowed exception, `runAllTests`, with its reason in the gate. Original finding: package functions never named in `tests/`, coverage by name not measured. | `python3 tools/dev/name_coverage.py` |
| A17 | M | **CLOSED v3.34.1** — `gridHandover` continues its signature with `...`, so `api_extract.py` (single-line regex) parsed the file to NOTHING: no entity in `api_data.py`, no reference page, while `apiReference.html` sent the reader to "as built by shLowLevel.gridHandover, which documents every field". `refpages_audit`'s COVER check compares pages against that same artifact, so it was silent by construction. **Four parsers of the public surface exist; two were blind the same way and agreed with each other** — which is why the new SURFACE check in `doc_sync_audit.py` compares against the FILESYSTEM (MATLAB's file/function rule is ground truth), not a second parser. `api_extract` now refuses to write an incomplete artifact. Pinned by `tools/tests/test_api_extract.py` (5 of 7 fail pre-fix). | `python3 tools/doc_sync_audit.py` |
| A18 | M | **CLOSED v3.34.1** — A10's blind spot was not only the package: **22 public class methods** were named by no test either — every operator (`plus`, `minus`, `uminus`, `mtimes`, `times`), `disp` on all three classes, `compare`, `fan`, `spectrum`, `triangle`, and eight `shClimatology` methods. Operators were deliberately NOT allowlisted: they are callable by name, and a test checking `plus(a,b)` against `a + b` is stronger than one checking either alone. | `python3 tools/dev/name_coverage.py` |
| A19 | M | **CLOSED v4.0.1** — `tools/dev/option_values_audit.py` reads `api_data.py`, where each option already carries its OWN `allowed` set and its OWN help row, so the scoping problem that made the grep useless disappears. The rule is deliberately narrow: only a row's LEADING ALTERNATIVES RUN (pipe-separated quoted values, the house way of writing the choices) is compared against `mustBeMember`; a row without one documents prose and is not checked. 42 of the 61 restricted options carry such a run. Verified against the historical defect: fed `opApply`'s pre-v3.34.1 row it fires, fed the fixed row it is silent, and it stays silent on the three shapes that made the naive version lie — another option's value quoted in prose, a parenthetical inside the run, and a numeric member list. **A false finding was nearly recorded here**: a probe of mine reported `readLoveNumbers`' allowed set as `[', ']`, which looked like an extractor bug; it was my own regex matching the gap between `""` and `"CE"`. The stored value was correct all along. Original finding: | `opApply`'s help offered `mode` values `'apply' | 'applyT'` that the arguments block rejects (`'forward' | 'transp'`) — the same help block's syntax lines had it right. Fixed and pinned in v3.34.1, found while writing the A10 test, not by any gate. **The general check is not built**: a crude scan (any quoted word on a comment line naming the option) produced 25 hits of which 24 were false positives — output-field docs, prose, and the wrong method's options in a class file. A correct gate must scope each help row to its OWN arguments block; `api_data.py` already carries exactly that pairing (`args[].validators` + `args[].desc`), so the instrument is cheap — it just has to be written against the scoped data, not by grepping. | `grep -n "mustBeMember" +shLowLevel/*.m` |
| A20 | M | **CLOSED v4.0.2** — and the recorded count was wrong: the backlog held **208** identifiers, not 165; nobody had measured it. All 61 files carry an `Error identifiers` block written against the raise site and its guard, the writer refusing any file whose documented set was not exactly the set the file raises. `UNDOCUMENTED` is drained to empty, so the DOCUMENTED rule holds with no exemption, and the gate now reads the root functions too. Two things surfaced that the finding did not name: `demo_shAnalysis` raises `demo:unknownCase` as well as `demo:casesFailed` (both now `shAnalysis:demo:*`, a PATCH — neither was documented anywhere), and `setup_shAnalysis` BUILDS five identifiers at runtime (`"shAnalysis:setup:no" + locs(li,1)`) that no scan of the file can name. Read as a literal that invents `shAnalysis:setup:no`, which nothing raises — which is exactly what the extended gate reported first. A concatenated literal is now a PREFIX: the help must document at least one identifier under it, because the gate cannot enumerate them. | `python3 tools/error_id_audit.py` |
| A21a | M | **CLOSED v4.0.3** — 31 public methods across the three classes document every identifier they can raise. A class needed a different instrument, not a wider loop: identifiers belong to METHODS, and four of them are raised by PRIVATE helpers (`checkPair`, `checkEpochs`, `assertClean`, `rangeToYears`) where `help` cannot reach. The rule follows REACHABILITY, one hop — a public method documents what it raises plus what the private helpers it calls raise — and the one-hop depth is CHECKED, not assumed: a private helper calling another makes the gate say the rule has gone too shallow. The map caught a distinction prose would have blurred: `plus` calls `checkEpochs`, `minus` does not (a difference has no single epoch, so it sets `epoch = NaN`). Nine fault injections, both directions. | `python3 tools/error_id_audit.py` |
| A21b | M | **CLOSED v5.0.0** — 29 two-part identifiers became 46 three-part ones across 47 raise sites, each rewrite scoped to the function it sits in: one old id maps to SEVERAL new ones (`shSeries:noEpoch` to four, `shCoefficients:badInput` to four), which is why a repo-wide replace would have been wrong — A15's lesson, applied per raise site. The middle segment is the raising PUBLIC method, constructor included, with one deliberate exception: the four private shared checks carry a stable CONCEPT segment (`operands`, `stack`, `range`) instead of the helper's own name, so renaming a private function is not a breaking change. The gate now PROVES the middle segment names either a method of that class or a declared shared check, so three-part is a rule and not a spelling convention. 47 test pins were remapped BY LINE to the method each call actually reaches. | `python3 tools/error_id_audit.py` |
| A15 | M | **CLOSED v4.0.0** with A3 — `kernelFactors`, `shSynthesisGradient` and `seaLevelFingerprint` now own their identifiers, and the tests that pinned the old names were remapped per raising file (the same old id mapped to two different owners, so a global replace would have been wrong). Original finding: A3 is **wider than the audit's 12**: `kernelFactors` (`shSynthesis:missingLoveNumbers`, `:badQuantity`, `:heightInvalid`), `shSynthesisGradient` (`shSynthesis:badInput`) and `seaLevelFingerprint` (`shSynthesis:missingLoveNumbers`) also raise identifiers they do not own. Unlike `shSynthesisDeformation`'s, these ARE documented and pinned by `testContract`/`testCorrectness`, so renaming them is a MAJOR change. Belongs in WP1's identifier sweep, not in a patch. | `grep -rn "shSynthesis:" --include=*.m` |
| A14 | M | **CLOSED v3.33.1** — the three gate self-tests in `tools/tests/` (committed in v3.32/v3.33) were **never run by CI**, and `test_legacy_name_tolerated` had been broken since the v3.33.0 sweep drained `LEGACY` to empty — an untested instrument, silently. CI now runs `tools/tests/`; the stale test asserts the mechanism with a temporary entry instead of pinning a member name. | `.github/workflows/ci.yml` before/after |
| A13 | L | **CLOSED v3.34.0** — the km conversion is the `RadiusKm` option, default unchanged at 6371 so no number moves, documented as the MEAN radius (deliberately not the coefficients' reference radius 6378.1363 km) and overridable. Pinned by `testResolutionMapRadiusIsAChoice`, a metamorphic test: the angular half-widths are radius-invariant, every km figure scales exactly with it, and `anisotropy` — a ratio — does not. That test also removes `resolutionMap` from A10's never-named list. | `+shLowLevel/resolutionMap.m` |
| A16 | M | **CLOSED v3.34.0** — the **test count in this file was wrong** and so was the v3.33.1 prediction. `grep -c '^function test'` counts the script-based harness entry point as a test and misses every `bench*` method and every parameterised expansion: it said 261, the prediction said 262, the self-hosted runner ran **268**. `tools/dev/count_tests.py` now reports methods and runs per class, expands `TestParameter`, and exits non-zero on `--executed` mismatch; CI prints it. | PR #95 `runAllTests (self-hosted)` log vs `count_tests.py` |
| A12 | M | **CLOSED v3.34.0** — `help_audit.py` checks struct output fields in BOTH directions: documented ⇒ assigned, and assigned ⇒ documented. **Every one of the 96 documented struct outputs is now covered**: 79 carry a field list verified against the source, 17 name the function that builds them (delegation), **0 are prose**. The sweep found **eleven** help blocks naming fields the code does not produce — `shIndex`'s `nmax`/`Nmin` (the FIELDS are `Lmax`/`minDegree`, so `idx.nmax` errored), `shReadGFC`'s `tide` (it lives in `header.tide_system`), `readSINEX`'s `header`, `gravisL2B`'s `files`, and the eight found by hand in v3.33.1 — plus 55 fields the code returns that the help never named. A mechanical prose→list rewrite was written and **discarded**: it produced confident nonsense (`'full-blocks'` split at a field name, nested struct-array subfields hoisted), so all 79 were converted by hand against the source. | `python3 tools/help_audit.py` (last line) |
| A11 | L | **CLOSED v3.33.1** — `Contents.m` is 78 lines; the 74 'New in v…' sections moved to `CHANGELOG.md`. The six versions that existed ONLY in `Contents.m` (v2.1, v2.2, v2.3, v2.4, v2.4.1, v2.4.2) were written into the changelog in the same commit and the version sets were diffed to prove nothing was lost. Original finding: `Contents.m` (1149 lines) is a full changelog duplicate: "New in v…" sections for 60+ releases, out of chronological order (v2.5 after v2.4.2, v3.1.0 inside the v2.4.1 block). `help shAnalysis` prints all of it. The CHANGELOG is the authority; Contents.m should carry the product line, the class overview and the quick start only. | `grep -n "New in" Contents.m` |

### 4.2 Inferred (needs Tier A measurement before any decision)

| # | Topic | What was read | What must be measured |
|---|---|---|---|
| B1 | `legendreALF` writes every `P(n+1,m+1,:)` into a 3-D array with page stride `(nmax+1)^2`; the inner `for n` loop touches `nlat` non-contiguous doubles per iteration. A `(nlat, n1*(n1+1)/2)` packed layout or per-latitude 2-D slabs is typically 2–5× faster in MATLAB. | source | wall time n=96/180 lat and n=720/1441 lat, 15 repeats, median ratio |
| B2 | `shSynthesis` forms the full `P` (or streams bands) and reduces with `sum(KC .* Pk, 1)` per latitude — two `(n1×n1)` dense passes per latitude. A Clenshaw/per-order recursion needs no `P` and is the standard for point synthesis (`synthesisPoints`, station lists). | source | same protocol; expected win largest for scattered points |
| B3 | Evaluation surface is a sphere of radius `R` (+ scalar `Height`). Evaluating on the ellipsoid surface `r(φ)` (latitude-dependent height in the existing `(R/r)^p` law) is not offered. For geoid/gravity users the sphere approximation leaves a known ~few-cm/mGal signature at high latitudes. | `kernelFactors`, `shSynthesis` | closed-form check against ellipsoidal reference values (Python oracle) |

### 4.3 Missing functionality (keyword scan, 0 hits in source → verified absent)

| # | Capability | Why it belongs here | Nearest existing building block |
|---|---|---|---|
| C1 | **GNSS inversion** (displacements → loading coefficients / TWS) and **joint GRACE+GNSS** estimation | forward exists (`shSynthesisDeformation`), inverse does not; the joint NEQ combination machinery (`neqCombine`, VCE) exists | `shAnalysisGrid` ("ls" mode), `neqCombine`, `vceRescale`, `slepianBasis` |
| C2 | GNSS time-series I/O and station-wise comparison metrics (WRMS reduction, annual amplitude/phase, correlation with `effectiveCorr`) | today a user must write the reader and the metrics | `compareSeries`, `effectiveCorr`, `fitDeterministicModel` |
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

### WP2 — Speed budgets, then speed   `[~] STEP 1 HARNESS DONE in v5.0.2`
Approved by Matthias on 2026-09-09 ("Go ahead with WP2"), which
supersedes the "A9 is ok" acceptance recorded the same day.

**Step 1 is in two halves, and only the first has shipped.**
The HARNESS is built (v5.0.2): ten budgets, 15 repeats, median against
3x a per-machine baseline, plus `perf_baseline_audit.py` and 24
self-tests. The BASELINES are not: no machine has a row in
`tests/perf_baseline.csv`, so every budget currently FILTERS and guards
nothing. That is deliberate — a budget cannot be asserted before it has
been measured, and pretending otherwise is how a green gate comes to
mean nothing. The next A8 run prints one `PERFBASE,...` line per
budget; committing those ten lines drains `NO_BASELINE` and turns the
gate live. **Only then is step 1 done and A9 closed.**

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

### WP3 — Ellipsoidal surface and accuracy completeness   `[ ] approved`
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

### WP4 — GNSS lane (C1, C2)   `[ ] approved`
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

### WP5 — Geoscience add-ons (C3–C7)   `[ ] approved` (tick per row)
| Row | Function | Oracle | Size |
|---|---|---|---|
| 5a `[ ]` | `shSeries.excitation(kn=…, Convention=…) → table(t, chi1, chi2, dLOD)` from C21/S21/C20 with the IERS 2010 conventions and the Love-number/frame factors; input in the pole-tide convention `poleTideConvert` knows | Chen & Wilson formulas; a published GRACE excitation series | S–M |
| 5b `[ ]` | `shLowLevel.leakageDataDriven(ts, mask, Radius=…) ` (Vishwakarma 2017 method of deviation), returned with the same `info` layout as `leakageCorrect` so `basinAverage` consumes both | equations of the paper in numpy; agreement with `leakageCorrect` on the GravIS basins within the published spread | M |
| 5c `[ ]` | `removeGIA(gia, Sigma=…)` accepting a σ field; σ propagated into `basinAverage` sigmas and `mcPropagate` | analytic vs MC on a synthetic ensemble | S |
| 5d `[ ]` | Swarm: `fetchICGEM` Swarm series read and `combineCenters`-style rescaling to GRACE noise for 2017-07..2018-05; `shSeries.select` gap policy | published Swarm-vs-GRACE degree-RMS ratio | M |
| 5e `[ ]` | `shLowLevel.readGrid(ncfile, Var=…)` (netCDF → grid + metadata, inverse of `writeGrid`) so GLDAS/WGHM enter `shCoefficients.analysis` | `writeGrid` roundtrip; one GLDAS file | S |
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

### WP7 — Class surface completeness (UI simplification)   `[ ] approved`
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
| v5.0.2 (WP2 step 1 harness) | ☑ 14 gates + mlint + make_demos + 13 self-test suites, 0 findings; `count_tests.py` predicts 305 methods / **315 runs** (305 + `testSpeedBudget` x 10) | ◐ pending — this is the run that MEASURES the baselines. Expect **315 runs, 301 passed, 14 filtered** (the 4 real-data fixtures + all 10 budgets, which have no baseline yet); a budget that FAILS instead of filtering means the workload errored, not that the machine is slow. | ◐ pending | ◐ pending |

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
- **A green harness is not a guarded budget.** v5.0.2 ships ten speed
  budgets and guards nothing: no baseline exists, so all ten filter.
  `perf_baseline_audit` says so in its own last line and carries them
  as debt. Read "0 findings" as "the books balance", never as "the
  budgets hold" — the CI run count is the tell: 14 filtered, not 4.
- **Read the CI log for `PERFBASE,` after the next A8 run.** Those ten
  lines ARE `tests/perf_baseline.csv` rows. Paste them under the
  header, drain `NO_BASELINE`, and the budgets go live on the run
  after. Nothing else about the harness needs to change.
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

**All twenty-two audit findings are closed except A9, which WP2 reopened
the same day it was accepted**, and WP6 is complete:

- **A9** — half-closed in v5.0.2. The measuring harness exists; the
  baselines do not, so all ten budgets FILTER and a 1.3x regression in
  `legendreALF`, `shSynthesis`, `shAnalysisGrid`, `applyDDK`,
  `leakageCorrect` or the Kalman step *still* ships unnoticed. The
  finding closes when the A8 baselines are committed.
- Everything else in §4.1 is CLOSED.

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

**Next concrete action for 5.0.2**: read the `PERFBASE,` lines out of the
next `runAllTests (self-hosted)` log, paste them into
`tests/perf_baseline.csv`, empty `NO_BASELINE` in
`tools/dev/perf_baseline_audit.py`, and push. That single commit turns
ten filtered budgets into ten assertions and closes A9. Only then does
WP2 step 2 (B1 packed Legendre, B2 Clenshaw) have anything to be
measured against.

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
WP6 stage 3 (v5.0.1) and WP2 step 1 (v5.0.2) |
2026-09-08..09 | Claude Opus 5 |
the first four releases green on A8 via CI — 4.0.0 at `5452938`:
304 runs, 300 passed, 0 failed, 4 filtered.
4.0.1 and 4.0.2 green on A8 at `0b4fb3b` via PR #97: 304 runs,
300 passed, 0 failed, 4 filtered, no red round.
4.0.3 green on A8 at `0d06e14` via PR #98: 305 runs, 301 passed,
0 failed, 4 filtered - the fifth exact count prediction running.
5.0.0 and 5.0.1 green on A8 at `631d524` via PR #99: 305 runs,
301 passed, 0 failed, 4 filtered, after two red rounds.
5.0.2 is not yet on A8: its run is the one that measures the ten
speed baselines. |
Developed by Matthias Weigelt with the help of Claude.*
