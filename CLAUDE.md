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
| Version | **3.34.1**, 08-Sep-2026 | `Contents.m` line 2, `CITATION.cff`, `CHANGELOG.md` line 3 agree |
| Branches | `main` only; `claude/getframe-recapture` and `claude/readshm` are gone (merged/deleted) | `GET /branches` |
| Public surface | 3 classes / 71 methods, 122 `+shLowLevel` functions (+4 private), 3 root functions | `tools/dev/api_extract.py` run in sandbox |
| Tests | 5 classes, **300 methods / 301 runs**: Correctness 159, Contract 70, Robustness 53, Science 7, Performance 11 methods (12 runs, `nmaxP` x2). 4 filter out without the optional real-data fixtures. v3.34.1 added 32 for A10/A18; the 268/269 baseline before it was confirmed exactly by the self-hosted run at `5acf14c`. | `python3 tools/dev/count_tests.py` |
| Python oracles | 16 `tools/dev/validate_*.py` + `tools/audit/*` | listing |
| Docs | 50 hand-written `html/*.html` + **200 generated `html/ref/*.html`** (one per entity + index, `make_refpages.py`), one shared `html/shAnalysis.css`, `helptoc.xml`, `info.xml`, guide PDF, generated `html/apiReference.html`. `docs/` holds the PDF and `apiExamples.json` only - no HTML page lives outside `html/` (gated). | listing |
| CI | `gates` job on ubuntu (help_audit, doc_sync_audit, no_map_renderer, toolbox_dependency_audit, nv_casing_audit, fixture_tag_audit, gate self-tests `tools/tests/`, `count_tests`, `name_coverage`, `refpages_audit`) + `runAllTests (self-hosted)` on A8/R2026a; fixtures from tag `fixtures-2026-08` | `.github/workflows/ci.yml` |
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
   `python tools/dev/refpages_audit.py`; then every `tools/tests/test_*.py`.
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
9. Regenerate what the version stamps: `tools/dev/make_apiref.py` and
   `tools/dev/make_guide.py` (needs `reportlab` + `matplotlib`;
   `pip install reportlab matplotlib`). Both stamps are gated.

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
| A2 | M | Six v1-era functions still use `inputParser` with lowercase option names (`'quantity'`, `'nmin'`, `'nmax'`, `'method'`, `'minOrder'`, ...): `shSynthesis`, `shDestripe`, `shGaussianWeights`, `shDegreeRMS`, `plotSHSpectrum`, `plotSHCoeffTriangle`. The v3.33.0 casing sweep did not reach them (inputParser is case-insensitive, so the NV gate has nothing to flag). Their `html/` syntax blocks (9 pages) still show `'quantity', q`. | `grep -l inputParser +shLowLevel/*.m` |
| A3 | M | **PARTIALLY CLOSED v3.33.1** — `shSynthesisDeformation` now raises `shLowLevel:shSynthesisDeformation:*`, documented in its own ERRORS block and pinned by `testDeformationIDs`. The rest stays open, and is wider than stated: see A15. Original finding: Error-identifier ownership is inconsistent: 147 identifiers are `shLowLevel:<fn>:<reason>`, but 12 are two-part (`shSynthesis:badP`, `shReadGFC:noData`, `shEvalGFCT:epochOutside`, `shSpectralCrossover:missingField`, `shAnalysis:geoMapRequired`), and `shSynthesisDeformation` raises `shSynthesis:*` identifiers — a caller cannot catch by owner. | `grep -ho "error('[A-Za-z:]*'"` |
| A4 | M | **CLOSED v3.33.1** — and much wider than stated — 13 files in `+shLowLevel` (Outputs, Options AND Inputs) and 52 class methods, 65 help blocks in all. Repaired against the source, not against either block: `readTN14`, `parseGraceFilename`, `resolutionMap`, `shAnalysisGrid`, `basinDeconvolve`, `buildSignalCov`, `vceRescale`, `mcPropagate` all documented fields, shapes or formulas the code does not produce. `help_audit.py` v3.0.2 rejects duplicate and below-the-footer sections; `fix_help.py` (the writer that injected them) refuses to add a second one. Original finding: Seven help blocks contain **two** `Outputs` sections (`errorMap`, `mcPropagate`, `parseGraceFilename`, `readTN14`, `resolutionMap`, `shSynthesis`, `shSynthesisDeformation`). `help_audit.py` checks presence, not uniqueness, so this passed. | sandbox scan of help blocks |
| A5 | M | **CLOSED v3.33.1** — `docs/apiReference.html` deleted — nothing wrote it or read it. `doc_sync_audit.py` now fails on any HTML page outside `html/`, fault-injected. Original finding: `docs/apiReference.html` is a byte-identical copy of `html/apiReference.html`. Two locations, one authority rule violated; nothing compares them. | `cmp` |
| A6 | L | **CLOSED v3.33.1** — README points at `ci.yml` instead of naming a tag it would have to keep in step (`fixture_tag_audit.py` already gates the tag itself). Original finding: README line 108 still says CI "pulls the orphan branch 'testdata'"; CI has pinned the tag `fixtures-2026-08` since v3.26.1/ci v2.9.0. | `README.md`, `ci.yml` |
| A7 | M | **CLOSED v3.34.0**, and partly wrong as written — `demos.xml` now exists, generated from the `demo_shAnalysis` registry (16 cases, gated both ways), and the Help browser reaches a page per entity via `html/ref/index.html`. The search database was **never missing as a capability**: `setup_shAnalysis(Docs=true)` has always run `builddocsearchdb` on `html/`; only the built index is absent from the repo, deliberately (a binary artifact belongs on the machine that searches it). No second option was added. **Unverified in Tier B**: whether `builddocsearchdb` descends into `html/ref/` — confirm on the acceptance machine. Original finding: `doc` integration is incomplete: no `helpsearch-v*` database, no `demos.xml`, `info.xml` present. | `ls html/` |
| A8 | M | **CLOSED v3.34.0** — all 250 pages link one `html/shAnalysis.css`; the inline blocks turned out to be ONE stylesheet copied fifty times (49 byte-identical + one in the generated reference), so merging them lost nothing, and `make_apiref.py` emits the link so the copy cannot return. 46 structural headings renamed to one spelling. `doc_sync_audit.py` gates the stylesheet, the link and the heading vocabulary; `refpages_audit.py` gates the generated skeleton. Original finding: The 50 hand-written `html/` pages use five different heading vocabularies for the same thing ("See also"/"See Also", "Outputs"/"Output Arguments", "Example"/"Examples", "Inputs / Outputs", "Options") and each page inlines its own `<style>` block (no shared stylesheet). 196 API entities have a dedicated page only inside the 304 KB monolith. | heading histogram over `html/*.html` |
| A9 | M | `testPerformance` asserts exactly one ratio (cache warm/cold) and one absolute bound (`dt < 5 s`); everything else is logged, not gated. There is no speed budget for `legendreALF`, `shSynthesis`, `shAnalysisGrid`, `applyDDK`, `leakageCorrect` or the Kalman step, so a 1.3× regression ships unnoticed. | `tests/testPerformance.m` |
| A10 | L | **CLOSED v3.34.1** — and the finding was **larger than recorded**: 13 package functions plus **22 public class methods** (A18). `tools/dev/name_coverage.py` measures it now, over the whole public surface, with comments stripped so a name in a `% see also` line does not count; it states its own reach in its last line (naming is not exercise). 32 new tests, each asserting a property the function's own help states. One allowed exception, `runAllTests`, with its reason in the gate. Original finding: package functions never named in `tests/`, coverage by name not measured. | `python3 tools/dev/name_coverage.py` |
| A17 | M | **CLOSED v3.34.1** — `gridHandover` continues its signature with `...`, so `api_extract.py` (single-line regex) parsed the file to NOTHING: no entity in `api_data.py`, no reference page, while `apiReference.html` sent the reader to "as built by shLowLevel.gridHandover, which documents every field". `refpages_audit`'s COVER check compares pages against that same artifact, so it was silent by construction. **Four parsers of the public surface exist; two were blind the same way and agreed with each other** — which is why the new SURFACE check in `doc_sync_audit.py` compares against the FILESYSTEM (MATLAB's file/function rule is ground truth), not a second parser. `api_extract` now refuses to write an incomplete artifact. Pinned by `tools/tests/test_api_extract.py` (5 of 7 fail pre-fix). | `python3 tools/doc_sync_audit.py` |
| A18 | M | **CLOSED v3.34.1** — A10's blind spot was not only the package: **22 public class methods** were named by no test either — every operator (`plus`, `minus`, `uminus`, `mtimes`, `times`), `disp` on all three classes, `compare`, `fan`, `spectrum`, `triangle`, and eight `shClimatology` methods. Operators were deliberately NOT allowlisted: they are callable by name, and a test checking `plus(a,b)` against `a + b` is stronger than one checking either alone. | `python3 tools/dev/name_coverage.py` |
| A19 | M | **OPEN, partially closed.** `opApply`'s help offered `mode` values `'apply' | 'applyT'` that the arguments block rejects (`'forward' | 'transp'`) — the same help block's syntax lines had it right. Fixed and pinned in v3.34.1, found while writing the A10 test, not by any gate. **The general check is not built**: a crude scan (any quoted word on a comment line naming the option) produced 25 hits of which 24 were false positives — output-field docs, prose, and the wrong method's options in a class file. A correct gate must scope each help row to its OWN arguments block; `api_data.py` already carries exactly that pairing (`args[].validators` + `args[].desc`), so the instrument is cheap — it just has to be written against the scoped data, not by grepping. | `grep -n "mustBeMember" +shLowLevel/*.m` |
| A15 | M | A3 is **wider than the audit's 12**: `kernelFactors` (`shSynthesis:missingLoveNumbers`, `:badQuantity`, `:heightInvalid`), `shSynthesisGradient` (`shSynthesis:badInput`) and `seaLevelFingerprint` (`shSynthesis:missingLoveNumbers`) also raise identifiers they do not own. Unlike `shSynthesisDeformation`'s, these ARE documented and pinned by `testContract`/`testCorrectness`, so renaming them is a MAJOR change. Belongs in WP1's identifier sweep, not in a patch. | `grep -rn "shSynthesis:" --include=*.m` |
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

### WP1 — Legacy-core modernisation   `[ ] approved`
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

### WP2 — Speed budgets, then speed   `[ ] approved`
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
**Stage 3 (open)**: retire the hand-written pages a generated page now
supersedes. Deferred deliberately: `doc_sync_audit`'s COVERAGE check
requires every entity to be named in a NARRATIVE page or the guide, so
deleting pages changes what that check means and needs its own decision.

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
| WP0 (v3.33.1) | ☑ 9 gates + 4 self-test suites, 0 findings | ☑ CI self-hosted (A8), green — 268 runs | ☑ PR #95 | ◐ pending |
| v3.34.0 (A7, A8, A12, A13, A16, WP6.1+2) | ☑ 12 gate steps + 6 self-test suites, 0 findings | ☑ **CI self-hosted (A8), green — 269 runs, 265 passed, 4 filtered** | ☑ PR #95 | ◐ pending |
| v3.34.1 (A10, A17, A18, A19-partial) | ☑ 11 gates + 8 self-test suites + mlint, 0 findings | ◐ **PREDICTED 300 methods / 301 runs — not yet run** | ◐ pending | ◐ pending |

**Tier A debt: DISCHARGED for both releases.** The local MATLAB bridge is
gone, but the self-hosted runner A8 is not: `runAllTests (self-hosted)`
went green on PR #95 at `fcaddd2` (268 runs) and again at `5acf14c`
(**269 runs, 265 passed, 4 filtered** for absent optional real-data
fixtures — `testGravisChainsRealData`, `testUserSuppliedSINEXFiles`,
`testMasconReaderOnARealFile`, `testPublishedTrendOnARealSeries`).
Per class: Contract 61, Correctness 136, Performance 12, Robustness 53,
Science 7.

So Tier A is reachable **through CI** even when it is not reachable from
a sandbox — do not record a session as Tier-B-only without saying which
of the two is meant. The 268 run refuted the predicted count (A16); the
269 run **matched `count_tests.py` exactly**, which is the first
confirmation that the counter is right about a real run and not only
about the source.

### 6.3 What the next session could be wrong for not reading
- The toolbox is at **3.34.0**, package is `+shLowLevel`. Memory summaries
  that say 3.32.2, 3.33.x or `shx.*` are stale. §1 is the authority; this
  bullet was itself stale for two commits, which is the same defect the
  release fixes.
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
- **mlint_lite is the only MATLAB syntax check a Tier-B session has, and it
  earns its keep.** It rejected fifteen `(gA + gB).C` lines: MATLAB cannot
  index into a parenthesised expression. Method dot-chains (`ts.at(k).toGrid`)
  are fine and the repo already uses them; parenthesised expressions and
  plain function calls are not. Run it on every changed `.m`, and read the
  new tests for the same shape it cannot see (`mk(1).FieldKind`).
- **Read the delegate before testing it.** `shSeries.compare` goes to
  `compareSeries`, not `compareSolutions` like `shCoefficients.compare`;
  `ts.climatology()` needs >= 6 epochs; `shCoefficients` properties are
  `SetAccess = private` so a test cannot set an epoch. Each of those was a
  test written wrong first and corrected against the source.
- **Do not write a number into this file that you did not just read.** The
  v3.34.1 per-class test counts were guessed (161/68) and were wrong
  (159/70) — in the same edit that closed a finding about unmeasured facts.
- Do not re-propose what §1.1 lists. The first audit draft did, without
  repository access; that draft is superseded by this file.
- Tier B sessions cannot measure B1–B3 or set WP2 budgets. Say so; do not
  estimate speedups.

### 6.4 Next action

Done and on PR #95: WP0, WP6 stages 1-2, and findings A1, A3 (partial),
A4, A5, A6, A7, A8, A10, A11, A12, A13, A14, A16, A17, A18 closed;
A19 partially.

**Tier-B work is now exhausted except for two rows, both needing a
decision rather than a keyboard:**

1. **WP6 stage 3** — retiring the narrative pages a generated page
   supersedes; needs a decision on what `doc_sync_audit`'s COVERAGE check
   should mean afterwards. (Note A17 made this sharper: `gridHandover` is
   named only by `html/mapBridge.html`, so deleting narrative pages can
   silently drop entities out of COVERAGE.)
2. **A19** — the scoped "documented option values must be accepted"
   gate. Buildable from `api_data.py` without MATLAB; left unbuilt here
   because a crude version was 96% false positives and the A12 lesson
   says do not ship a checker that lies first.

Everything else open (A9/WP2 budgets, WP3, WP4, WP5, WP7) needs either a
MATLAB measurement or WP1's decision.

The one thing that needs Matthias:

**Decide WP1's shape.** Hard break in **4.0.0** (recommended, consistent
with the v3.0.0 and v3.33.0 precedents) or one release with a deprecation
shim. A15 (the documented `shSynthesis:*` identifiers in `kernelFactors`,
`shSynthesisGradient`, `seaLevelFingerprint`) rides on the same decision —
MAJOR either way. Nothing else is blocked on it.

To re-run the gates and the prediction from a fresh sandbox:
```
pip install reportlab matplotlib && \
  for g in tools/*.py tools/dev/{no_map_renderer,check_api,api_audit,attribution_sweep}.py; do python3 $g; done && \
  for t in tools/tests/test_*.py; do python3 $t; done && \
  python3 tools/dev/count_tests.py
```

---
*shAnalysis v3.33.0 audited | 2026-09-08 18:30 UTC | Claude Fable 5.1 |
WP0 (v3.33.1), A7/A8/A12/A13/A14/A16 + WP6.1-2 (v3.34.0), and
A10/A17/A18 (v3.34.1) | 2026-09-08 | Claude Opus 5 |
v3.33.1 and v3.34.0 green on A8 via CI (269 runs); v3.34.1 predicts
300 methods / 301 runs and is NOT yet run |
Developed by Matthias Weigelt with the help of Claude.*
