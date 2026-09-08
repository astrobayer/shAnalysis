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
| Version | **3.33.0**, 05-Sep-2026 | `Contents.m` line 2, `CITATION.cff`, `CHANGELOG.md` line 3 agree |
| Branches | `main` only; `claude/getframe-recapture` and `claude/readshm` are gone (merged/deleted) | `GET /branches` |
| Public surface | 3 classes / 71 methods, 122 `+shLowLevel` functions (+4 private), 3 root functions | `tools/dev/api_extract.py` run in sandbox |
| Tests | 5 classes, 261 test methods: Correctness 136, Contract 61, Robustness 54, Science 8, Performance 2 | `grep -c 'function test' tests/*.m` |
| Python oracles | 16 `tools/dev/validate_*.py` + `tools/audit/*` | listing |
| Docs | 50 `html/*.html`, `helptoc.xml`, `info.xml`, 122-page guide PDF, generated `apiReference.html` (304 KB) | listing |
| CI | `gates` job on ubuntu (help_audit, doc_sync_audit, no_map_renderer, toolbox_dependency_audit, nv_casing_audit, fixture_tag_audit) + `runAllTests (self-hosted)` on A8/R2026a; fixtures from tag `fixtures-2026-08` | `.github/workflows/ci.yml` |
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
   `python tools/dev/api_audit.py`, `python tools/dev/attribution_sweep.py`.
5. Predict the test count before running (`runAllTests`); a missed prediction
   is a finding.
6. Never widen a tolerance to pass. Every tolerance carries a comment naming
   the term it bounds and the oracle it was measured against.
7. Push with `HEAD:refs/heads/<branch>`, read the SHA back with `git ls-remote`.
   Token read from file at call time, never echoed, never in a URL.
8. Close each WP with: CHANGELOG entry under `## [Unreleased]`, verdict per
   tier, debt named, next action as a command.

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
| A1 | H | Shipped guide PDF is stamped **v3.28.0** while the toolbox is v3.33.0. Five releases missing, including the BREAKING `MinDegree`→`Nmin` rename of v3.33.0. The doc_sync VERSION check covers `apiReference.html`, not the PDF. "Stamps are not content" — but here even the stamp is stale. | `docs/shAnalysis_workflow_guide.pdf` page 1 footer |
| A2 | M | Six v1-era functions still use `inputParser` with lowercase option names (`'quantity'`, `'nmin'`, `'nmax'`, `'method'`, `'minOrder'`, ...): `shSynthesis`, `shDestripe`, `shGaussianWeights`, `shDegreeRMS`, `plotSHSpectrum`, `plotSHCoeffTriangle`. The v3.33.0 casing sweep did not reach them (inputParser is case-insensitive, so the NV gate has nothing to flag). Their `html/` syntax blocks (9 pages) still show `'quantity', q`. | `grep -l inputParser +shLowLevel/*.m` |
| A3 | M | Error-identifier ownership is inconsistent: 147 identifiers are `shLowLevel:<fn>:<reason>`, but 12 are two-part (`shSynthesis:badP`, `shReadGFC:noData`, `shEvalGFCT:epochOutside`, `shSpectralCrossover:missingField`, `shAnalysis:geoMapRequired`), and `shSynthesisDeformation` raises `shSynthesis:*` identifiers — a caller cannot catch by owner. | `grep -ho "error('[A-Za-z:]*'"` |
| A4 | M | Seven help blocks contain **two** `Outputs` sections (`errorMap`, `mcPropagate`, `parseGraceFilename`, `readTN14`, `resolutionMap`, `shSynthesis`, `shSynthesisDeformation`). `help_audit.py` checks presence, not uniqueness, so this passed. | sandbox scan of help blocks |
| A5 | M | `docs/apiReference.html` is a byte-identical copy of `html/apiReference.html`. Two locations, one authority rule violated; nothing compares them. | `cmp` |
| A6 | L | README line 108 still says CI "pulls the orphan branch 'testdata'"; CI has pinned the tag `fixtures-2026-08` since v3.26.1/ci v2.9.0. | `README.md`, `ci.yml` |
| A7 | M | `doc` integration is incomplete: no `helpsearch-v*` database (search in the Help browser returns nothing for shAnalysis), no `demos.xml` (no Examples tab), `info.xml` present. | `ls html/` |
| A8 | M | The 50 hand-written `html/` pages use five different heading vocabularies for the same thing ("See also"/"See Also", "Outputs"/"Output Arguments", "Example"/"Examples", "Inputs / Outputs", "Options") and each page inlines its own `<style>` block (no shared stylesheet). 196 API entities have a dedicated page only inside the 304 KB monolith. | heading histogram over `html/*.html` |
| A9 | M | `testPerformance` asserts exactly one ratio (cache warm/cold) and one absolute bound (`dt < 5 s`); everything else is logged, not gated. There is no speed budget for `legendreALF`, `shSynthesis`, `shAnalysisGrid`, `applyDDK`, `leakageCorrect` or the Kalman step, so a 1.3× regression ships unnoticed. | `tests/testPerformance.m` |
| A10 | L | 14 package functions are never named in `tests/` : `antarcticaChain`, `buildSignalCov`, `gravisDataFolder`, `gridHandover`, `icgemDate2Year`, `opApply`, `pctile`, `plotBasinSeries`, `plotCovariance`, `resolutionMap`, `shDestripe`, `shGaussianFilter`, `shSpectralCrossover`, `vceRescale`. Some are certainly exercised indirectly (`ts.destripe` → `shDestripe`); the point is that coverage by name is not measured. | name scan |
| A11 | L | `Contents.m` (1149 lines) is a full changelog duplicate: "New in v…" sections for 60+ releases, out of chronological order (v2.5 after v2.4.2, v3.1.0 inside the v2.4.1 block). `help shAnalysis` prints all of it. The CHANGELOG is the authority; Contents.m should carry the product line, the class overview and the quick start only. | `grep -n "New in" Contents.m` |

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

### WP0 — Record and hygiene   `[ ] approved`
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

### WP6 — Documentation to the MathWorks layout   `[ ] approved`
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
- 2026-09-08 — Handover document retired to `tools/dev/HANDOVER_shAnalysis_RETIRED.md`;
  `CLAUDE.md` is the single point of truth. Evidence: PR `wp0-record`.
  *(§5 work packages still pending Matthias's approval.)*

### 6.2 Verification board (◑ = one tier only, ☑ = both)
| WP | Static gates | Tier A (MATLAB) | CI | Merged |
|---|---|---|---|---|
| audit 2026-09-08 | ☑ read | — | — | — |

### 6.3 What the next session could be wrong for not reading
- The toolbox is at **3.33.0**, package is `+shLowLevel`, only `main` exists.
  Memory summaries that say 3.32.2, `shx.*`, or open `claude/*` branches are
  stale.
- The guide PDF is five releases behind; do not quote it as current.
- Do not re-propose what §1.1 lists. The first audit draft did, without
  repository access; that draft is superseded by this file.
- Tier B sessions cannot measure B1–B3 or set WP2 budgets. Say so; do not
  estimate speedups.

### 6.4 Next action (once §5 is ticked)
```
git checkout -b wp0-hygiene main   # WP0 rows A1, A3-partial, A4, A5, A6, A11 — one commit per row
```

---
*shAnalysis v3.33.0 audited | 2026-09-08 18:30 UTC | Claude Fable 5.1 |
Developed by Matthias Weigelt with the help of Claude.*
