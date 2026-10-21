# Changelog

## [5.23.0] - 2026-10-21 - A36: the offline fetch tests stop sleeping

A MINOR release: two options on `fetchTN` and `fetchICGEM`. No default
changes; a call without them behaves exactly as before.

### Measured (A8, the last four green runs, the runner's own durations)
- 130 s of the suite's 248 s of test time - 53 percent - was three
  offline tests waiting: `testICGEMListFixtureAndResolve` 65.5 s,
  `testFetchICGEMSeriesOffline` 34.0 s, `testFetchProxyPlumbing` 30.3 s,
  the same to 0.03 s on every run. Each URL those tests make fail on
  purpose went through `httpFetch`'s backoff - BaseDelay 2 s, 4 tries,
  so 2 + 4 + 8 s plus up to 25 percent jitter, about 15 s - and the
  fetchers gave a caller no way to shorten it. No numerical lane came
  close: the slowest is the Legendre crossover benchmark at 9.9 s.

### Added
- `MaxTries` and `BaseDelay` on `shLowLevel.fetchTN` and
  `shLowLevel.fetchICGEM` (single, bulk and series paths), forwarded to
  `shLowLevel.httpFetch` through the private `webFetch`. Neither has a
  default of its own: an option not given is not forwarded, so
  `httpFetch`'s default (4 tries, 2 s) stays the only one. The Proxy path
  makes one attempt and ignores both. In `fetchICGEM` they are the
  transport retries inside each download; `Retries` remains the
  rate-limit loop around it (30/60/120 s on 429 or a timeout).

### Tests
- The three offline tests pass `MaxTries = 1` to every call meant to
  fail, and the ICGEM bulk test asserts the option reached `httpFetch`
  ("after 1 attempts" in the failure report).
- `testFetchRetryOptionsReachHttpFetch` (contract): `MaxTries = 2`
  reaches `httpFetch`, an omitted `MaxTries` is `httpFetch`'s 4, and
  `MaxTries = 0` is refused.
- 417 methods / 431 runs (Contract 121).

### Measured after (A8, PR #130)
- The three tests ran 0.86, 0.86 and 7.04 s; the new contract test
  17.96 s. 26.7 s where 130 s were: 103 s off every run. What remains is
  not backoff - a refused connection to 127.0.0.1:1 costs about 3 s per
  attempt on Windows - and most of it is the contract test's 4-attempt
  half, kept because it pins that an omitted `MaxTries` is `httpFetch`'s
  own default.

Developed by Matthias Weigelt with the help of Claude (Opus 5.5),
2026-10-21.

## [5.22.0] - 2026-10-21 - A34: the observation climatology fitted to a first filter pass

A MINOR release: one option on `kalmanChain`, `regionalKalman` and
their class routes. The default is unchanged, bitwise.

### Added
- `FitClimatology = "observations" | "filtered"` on
  `shLowLevel.kalmanChain`, `shLowLevel.regionalKalman`, `ts.kalman` and
  `ts.regionalKalman` (solution mode, `Climatology = true`).
  "observations" (default) fits the removed-and-restored climatology to
  the observations, as before; "filtered" runs the chain once with
  `Climatology = false`, fits the climatology (bias, trend, annual,
  semiannual) to that smoothed estimate at the output epochs, removes it
  from the observations, filters the residual and restores it - in
  `regionalKalman` through Proj, after the background is removed and
  before it is restored. Twice the cost. Sigmas are unchanged: the
  restored climatology carries none, as before.

### Measured (tools/dev/validate_climatology_restore.py)
- The 8e closed loop (nmax 30, cap north of 60 N, RBF basis, noise
  rising to 3 cm per coefficient at degree 30), five seeds, grid RMS in
  cm for no / 5 cm / 15 cm annual climatology inside the region:
  "observations" 14.5 / 14.5 / 14.5, Climatology = false 0.90 / 1.09 /
  2.02, "filtered" 0.89 / 1.07 / 1.96; at a third of the noise 4.4,
  0.55 / 0.76 / 1.63 and 0.55 / 0.72 / 1.49. "filtered" beats
  "observations" in every seed and case, and is the better of the other
  two once the climatology is strong.
- A third pass changes the median by at most 5.1 percent and was not
  built; the bar written before the run was 5 percent.
- On the SH basis, nmax 6, noise above the signal from degree 3: the
  "filtered" coefficient RMS error is 0.391 of the default's in the
  median, 0.433 at worst over 40 seeds. With noise below the signal the
  first sizing gave 0.95-1.00 - the two fits differ only where A34's
  noise is.

### Decisions
- Optional, not the default (Matthias, 2026-10-21: "make it optional").
  The default restore is kalmanChain's documented behaviour, and every
  result computed with it stays reproducible.
- Named `FitClimatology`, not `ClimatologyFit`: `Climatology` would
  have been a prefix of the new name, so any abbreviation of it would
  have raised AmbiguousInputName (`nv_casing_audit`'s prefix rule, the
  `RelTol`/`R` lesson of 5.16.0).
- No new output field: the report of a "filtered" run is the second
  pass's, and the first pass is reproducible from the documented
  definition, which the tests check bit for bit.

### Tests
- `testKalmanChainFitClimatologyFiltered`,
  `testRegionalKalmanFitClimatologyFiltered`: "filtered" equals the two
  passes written out by hand, bitwise (on the SH basis for the regional
  chain, where restoring through Proj is exact); the default equals
  "observations" bitwise; the error ratio below 0.6 on the oracle's
  configuration.
- `testFitClimatologyRoutes`: both class routes forward it bitwise; a
  value outside the two is refused.
- 416 methods / 430 runs (Correctness 214, Contract 120).

Developed by Matthias Weigelt with the help of Claude (Opus 5.5),
2026-10-21.

## [5.21.0] - 2026-10-21 - A33: one GeoJSON reader for every GravIS chain

A MINOR release: `readBasin` takes several names, or none for the whole
file, and the GravIS chains build their basin masks with it. No
documented call or error identifier changes. One number moves, and it
is a fix: the Antarctic basin 302, whose ring encircles the pole.

### Added
- `shLowLevel.readBasin(names)` with a string array returns a cell of
  region handles and a struct array of their metadata;
  `readBasin(string.empty, File = f)` returns every basin of the file.
  A scalar name returns what it returned in v5.14.0.

### Changed
- `twsChain` and `gravisRegionChain` (and through it `greenlandChain`
  and `antarcticaChain`) no longer parse GeoJSON themselves: their masks
  are `readBasin` regions evaluated on the grid. `jsondecode` now
  appears in `readBasin` only. `twsChain`'s window box is built from the
  same rings.

### Fixed
- Antarctic basin 302 now includes the polar cap south of its ring. Its
  ring winds once around the pole (360 degrees, southernmost point
  -88.54), and the chains' own planar test, recentred at the ring's
  mean longitude, left the cap outside; `readBasin` closes such a ring
  through the pole. Measured on the 1-degree global grid against the old
  rule (`tests/testCorrectness.m` re-implements it): 686 cells differ -
  675 gained, the cap at -89.5 and -88.5 degrees, and 11 lost, in the
  -88.5 row the ring itself crosses - net 137,000 km2
  or 1.2 percent of the Antarctic total (11.72e6 km2 before, 11.86e6
  km2 now). An Antarctic mass series from `antarcticaChain` changes by
  the signal of that cap.
- Elsewhere the two rules agree: no Greenland basin and 98 of the 100
  river basins differ in a single cell; Mekong and Volga differ by one
  cell each, a grid point lying ON a ring edge (distance 1e-14 degrees),
  which the two point-in-polygon tests assign differently.

### Measured, which changed the finding
- A33 said three river basins crossing lon 0 (Loire, Niger, Volta) broke
  the chains' masks. They did not: the chains recentre each polygon at
  its circular-mean longitude before the planar test, which is wrap-safe
  for a basin narrower than 180 degrees. The real defect was the polar
  ring, which no recentring can fix.

### Tests
- `testGravisChainMasksAreReadBasinRegions`: for every basin of the
  three shipped files, the readBasin mask equals the old rule except at
  cells within 1e-6 degrees of a ring edge, and except south of the ring
  of exactly one polar basin, whose cap readBasin includes and the old
  rule did not; `twsChain`'s box rule is checked on the same regions.
- 413 methods / 427 runs (Correctness 212).

Developed by Matthias Weigelt with the help of Claude (Opus 5.5),
2026-10-21.

## [5.20.0] - 2026-10-21 - WP8 8i: process-noise scales from the data, VAR(2) and conditioning in a basis

A MINOR release: options on `regionalKalman`, `kalmanFilter` and
`buildCondFun`, and the seventh row of WP8. No documented call or error
identifier changes; without the new options every result is v5.19.0's,
except a VAR of `Order` >= 2, which was wrong until now (Fixed, below).

### Fixed
- **`estimateVAR` with `Order` >= 2 solved the wrong Yule-Walker
  system** (A35, since the function was written). Block (i, j) of the
  system matrix must be E[x_(t-i) x_(t-j)'] = Sigma(j - i); the code
  held Sigma(i - j), each block transposed. That is exact for `Order = 1`
  and for 1 x 1 blocks (`Structure = "diagonal"`), so every default call
  and every earlier test was unaffected; a multivariate VAR(2) came back
  wrong - from a stationary truth with companion radius 0.76, a model
  with radius 1.45, missing the Yule-Walker equations by 0.30 of |Sigma(0)|
  against 1e-16 now. `kalmanChain(..., Order >= 2)` and
  `regionalKalman(..., Order >= 2)` inherited it. Found by this release's
  VAR(2) test on A8, after its first two fixtures failed for reasons of
  their own (below); pinned by `testEstimateVAROrderTwoSolvesTheYuleWalkerEquations`.

### Added
- `regionalKalman(..., QBlocks = lab, QScale = alpha)`: one process-noise
  factor per block of basis coefficients, Q(alpha) = D Q D,
  D = diag(sqrt(alpha_k)), so the correlations of the estimated Q are
  kept. One block is Kurtenbach's alpha (DGK C-683, Sec. 4.3.5), and one
  fixed factor is v5.19.0's chain, bitwise.
- `regionalKalman(..., EstimateQScale = true)`: the factors as the
  maximum of the innovation likelihood. Kurtenbach notes that for real
  data such a factor cannot be fixed beforehand.
  - The search is fminbnd for one block and fminsearch for several,
    within a factor 1e4 of QScale (the start).
  - `out.qScale`, `out.qBlocks` and `out.qEstimate` (evaluations, exit
    flag, and whether the search ended at the limit) report it.
  - `out.negLogLik` is the -2 log likelihood of every run.
  - New identifier `shLowLevel:regionalKalman:badQBlocks`.
- `kalmanFilter(..., Likelihood = true)`: `filt.negLogLik`, the -2 log
  likelihood term of every epoch given the past, formed through Cholesky
  factors. In normal-equation form it is log|I + P N| + m'N m - 2 m'b -
  u'(P^-1 + N)^-1 u; the omitted log|R| + l'R^-1 l does not depend on
  the model. 0 in a gap or a rejected epoch; `[]` without the option.
  The filter's states and covariances are unchanged.
- `buildCondFun(..., Basis = B)`: Kvas' space-domain conditioner for the
  K x K covariances of a regional basis, Proj f(T S T') Proj'. It is the
  SH conditioner, bitwise, on the SH basis, and the identity to the
  projector's tolerance without a taper. New identifier
  `shLowLevel:buildCondFun:badBasis`.
- VAR(2) through the regional chain is now tested: on the SH basis it is
  kalmanChain at Order 2.
- `tools/dev/validate_regional_adaptive.py`:
  - CLAIM 1: the summed likelihood equals the dense Gaussian -2 log L of
    all observations under the joint prior to 3.9e-15, gaps included;
    the solution-mode term exceeds the neq-mode term by exactly log|R| +
    l'R^-1 l (1.8e-14);
  - CLAIM 2: for one block the likelihood maximum is the EM fixed point
    (Shumway and Stoffer 1982), from the smoother and its lag-one
    covariance, to 1.3e-8;
  - CLAIM 3: with true factors (4, 0.5) on two blocks the estimates
    average (3.95, 0.49) over 30 seeds, relative spread 9 and 20 percent,
    and lower the state error against alpha = 1 in 30 of 30 seeds;
  - CLAIM 4: with a VAR(2) truth Order 2 has the lower -2 log L in 10 of
    10 seeds; information and gain form agree in companion space (states
    6.8e-15, sigmas 7.5e-15); CLAIM 4b repeats it in the MATLAB test's
    configuration (the five degree-2 coefficients, a 3000-epoch model
    series, direct observations, smoothed output, kalmanFilter's and
    regionalNEQ's own formulas): 9.45e-16 in the states, 1.11e-15 in the
    sigmas over 40 seeds. The
    first A8 run of this release failed that test at 8.6e-12: its fixture
    (nmax 6, 240 model epochs) asked 2 x 45^2 VAR parameters of 240
    epochs, the estimate was explosive (companion radius 6.8), and two
    rounding paths through an explosive model grow apart. A test fixture
    defect, not a filter one; the test now also asserts the model it
    compares is stationary;
  - CLAIM 5: the basis conditioner is the identity to 1.1e-10 and stays
    positive semidefinite with a taper.

### Decisions
- Maximum likelihood of the innovations, not a variance-component
  formula. Kurtenbach gives no method for estimating his alpha, and the
  one-block case has two derivable estimators that must agree: the
  likelihood maximum and the EM fixed point. They agree (CLAIM 2), so
  the implementation uses the likelihood, which works for any number of
  blocks.
- Q(alpha) = D Q D rather than a block-diagonal Q: scaling blocks keeps
  the cross-block correlations the Yule-Walker estimate measured.
  Dropping them would change the model in a way no factor reverses.
- Sigma0 is not scaled, as for QScale since v5.15.0; the likelihood is
  that of the model with this start.
- The 8i row's "closed loop of 8f" needs the data 8f was postponed for;
  the closed loops here are synthetic, as in 8b.

## [5.19.0] - 2026-10-21 - WP8 8h: line-of-sight gravity differences as observations

A MINOR release: one new kind of `regionalNEQ` and the sixth row of WP8.
No documented call or error identifier changes.

### Added
- `shLowLevel.regionalNEQ(B, "lgd", ...)`: line-of-sight gravity
  differences of a satellite pair, LGD = e . (gB - gA),
  e = (rB - rA) / |rB - rA|, the definition of lgdToolbox (its HANDOVER
  D1), as a normal equation in the basis.
  - The design comes from the two orbits (`PositionA`, `PositionB`, one
    arc in time order): the potential's gradient design along e at B
    minus that at A. The orbits must be in the Earth-fixed frame of the
    coefficients; lgdToolbox works in an inertial frame and the caller
    rotates both.
  - `Operator` is the along-track filter, a handle or an (M, M) matrix,
    applied ONCE to [Values, A], data first. `lgd.spectralOperator`
    fits its edge predictor on that first column and applies the fitted
    map to every column, so the design is filtered as the data are. So
    `Values` are the unfiltered LGD and `Valid` is the data's own mask.
  - Rows the operator leaves non-finite, and rows outside `Valid`, are
    dropped with their rows and columns of `Cov`, which belongs to the
    filtered data.
  - New identifiers `shLowLevel:regionalNEQ:badOperator` and
    `shLowLevel:regionalNEQ:noObservations`; new fields `info.y` (the
    data as used) and `info.kept` (the epochs used), empty for the other
    kinds.
- `tools/dev/validate_regional_lgd.py`, against lgdToolbox's own forward
  models:
  - CLAIM 1: degrees 0 and 2 with C00 = 1 and C20 = -J2/sqrt(5) reproduce
    `lgdReferenceJ2` (point mass + J2, closed form) to 1.7e-15 |g|, the
    J2 part on its own to 2.4e-16 |g|;
  - CLAIM 2: degree 0 reproduces five rows of lgdToolbox's 50-digit
    Kepler pair (oracle O2) to 5.3e-16 |g|;
  - CLAIM 3: degrees 2..30 agree with Cartesian central differences of
    the potential to 1.8e-8, the difference floor;
  - CLAIM 4: a band-pass on [y, A] keeps noise-free data on the design
    (5.5e-16); an operator fitted on its first column does so only when
    the data are that column.

### Decisions
- The along-track processing stays in lgdToolbox (CLAUDE.md WP8): band
  filter, transfer function and noise PSD. shAnalysis takes the filter as
  a function handle and calls no `lgd.*` function, so the two toolboxes
  stay independent.
- The data go through the operator with the design, rather than arriving
  filtered: the only way the predictor lgdToolbox fits on its first
  column is the one applied to the partials.
- No frame rotation inside shAnalysis. The LGD is a scalar; only the
  orbits must be Earth-fixed, and the rotation (EOP, precession-nutation)
  belongs to the toolbox that reads the orbits.

## [5.18.0] - 2026-10-21 - WP8 8e: remove-compute-restore in the regional Kalman filter

A MINOR release: one additive option on `regionalKalman` and its class
route, and the fifth row of WP8. No documented call or error identifier
changes.

### Added
- `shLowLevel.regionalKalman(..., Background = tsb)` and
  `ts.regionalKalman(..., Background = tsb)`: a global background series
  (a hydrology or ESM model, a global solution's long wavelengths) is
  removed from the observations before they become normal equations in
  the basis and restored in every output:
  - the series is b + T (a + Proj c); `out.a` stays the basis
    coefficients without the background;
  - `out.grid` and `out.basin` carry the background's EWH, from degree
    min(2, Nmin) as the rest of the chain;
  - the background is taken as error-free: no sigma changes;
  - in record mode the records must already be reduced by it; it is only
    restored;
  - a basis on an index with Nmin above 2 leaves the low degrees to the
    background entirely: remove-compute-restore of the low degrees.
  New identifier `shLowLevel:regionalKalman:badBackground` (not an
  shSeries, wrong nmax, or no epoch within Tolerance of an observation or
  output epoch). New output field `out.background`.
- `tools/dev/validate_regional_rcr.py`:
  - CLAIM 1: with the process model fixed the chain is linear, so a
    background c z leaves exactly 1 - c of the leakage of z: 4.8e-14 at
    nmax 30, 5.6e-15 at the MATLAB test's nmax 10 over 20 seeds;
  - CLAIM 2: in a closed loop (nmax 30, cap north of 60 N, a 30 cm
    seasonal neighbour and a degree-2..4 random walk, five seeds) the
    outside signal raises the grid RMS over the region by 28% (median);
    with an 80% background the error is within 3.6% of the error without
    any outside signal;
  - CLAIM 3: the observations' own unfiltered low degrees as background
    are worse than none, 1.57 against 1.20 cm;
  - CLAIM 4: the process model from the full model series is no worse
    (worst ratio 1.011);
  - CLAIM 5: Woehnke's observation area (EWH on the region + 300 km)
    helps without a background (1.04 against 1.20 cm, 4 of 5 seeds) and
    costs in every seed with one (0.97 against 0.93 cm).

### Decisions
- Remove-compute-restore is this toolbox's own design. Woehnke et al.
  (2025) use no background; Steffen et al. (2026) name it as the
  treatment of long wavelengths and outside signal without applying it.
  Neither gives equations, so the oracle checks the scheme on its own
  terms: the algebra exactly, and what it buys in a closed loop.
- Woehnke's observation and computation areas are not a chain option. As
  measured (CLAIM 5), the observation area helps only where a background
  would help more, and costs where one is removed: SH-coefficient
  observations carry more than their synthesis on an area. Who has
  gridded data on an area gets it through `regionalNEQ "points"`
  records. The computation area is the basis' `BufferKm`, as before.
- The background is removed as a series difference, before the
  observation climatology is fitted, so the climatology is the
  climatology of the residual.
- The basin mean adds the background's EWH as a separate term, so the
  chain without a background is bitwise v5.17.0 (plus the new field).

### Found, not changed
- A34: the observation climatology restored by `Climatology = true` is a
  fit to the noisy observations and is restored unfiltered, so its noise
  comes back. With the oracle's noise (3 cm per coefficient at degree 30)
  it dominated the grid error, 14.6 cm against 1.2 cm without it. This is
  `kalmanChain`'s restore, kept bit for bit in v5.17.0; changing it is a
  decision of its own.

## [5.17.0] - 2026-10-21 - WP8 8d: the regional Kalman filter in one call

A MINOR release: one new function, one class method, two additive options
on existing functions, and the fourth row of WP8. No documented call or
error identifier changes.

### Added
- `shLowLevel.regionalKalman(obs, B, ModelSeries = tsm)` is the single
  point of access to the regional Kalman filter. It chains the earlier
  rows and changes none of them:
  - the process model in the basis (`regionalProcessModel`, with QScale
    and GroundNoise);
  - one basis normal equation per epoch: an shSeries with formal sigmas
    or `NoiseCov` (via `regionalNEQ`, kind "solution"), or a struct array
    of basis normal equations with an `epoch` field;
  - `kalmanFilter` in its normal-equation mode and `rtsSmoother`
    (`Lag`: Inf the full pass, 0 the filter), which together are the
    joint least-squares adjustment over all epochs;
  - the output through linear functionals with sigmas from the full
    smoothed covariance: the series T a (sigmas through T), the EWH at
    the region's quadrature points (`out.grid`) and its area-weighted
    basin mean with sigma (`out.basin`). The EWH outputs need `kn`.

  In solution mode the observation climatology is removed first and
  restored in the basis, T (a + Proj c). On the SH basis that is exactly
  kalmanChain's restore.
- `ts.regionalKalman(B, ModelSeries = tsm, ...)` is the lane with the
  series as the observations, pinned bitwise.
- `shLowLevel.rtsSmoother(..., Functionals = F)` returns
  `smo.sigF = sqrt(diag(F Ps F'))` per epoch, formed as
  `sum((F Ps) .* F, 2)` without the m x m product. For F = I it is
  `smo.sig` bit for bit. New identifier
  `shLowLevel:rtsSmoother:badFunctionals`.
- `B.region.core` in `regionalBasis`: the unbuffered region on the
  basis' quadrature grid, which the basin mean is taken over. Every
  other field is unchanged.
- `tools/dev/validate_regional_kalman.py`:
  - on the SH basis the information form equals kalmanChain's gain form,
    states 5.6e-15 and sigmas 8.9e-16 over 40 seeds;
  - on an RBF basis filter + RTS equal the dense joint least-squares
    adjustment over 20 seeds (2.6e-15), gaps included;
  - in a closed loop the basin-mean error is 1.07 predicted sigmas (RMS,
    60 seeds);
  - the functional rule equals diag(F Ps F') to 4.4e-16, and is exactly
    diag(Ps) for F = I.

### Decisions
- The chain takes a basis built by `regionalBasis`, not the basis'
  options. CLAUDE.md sketched `Region = , Basis =`; folding regionalBasis'
  option set into the chain would have given it a second home.
- Solution observations update in the information form, because a
  general basis has H = T, not I, and kalmanFilter's solution mode only
  knows H = I. On the SH basis this is the one place the chain differs
  from kalmanChain, by 5.6e-15.

## [5.16.0] - 2026-10-20 - WP8 8c: every observation level as a normal equation in the basis

A MINOR release: one new function, one class method, and the third row of
WP8. No documented call or error identifier changes.

### Added
- `shLowLevel.regionalNEQ(B, kind, ...)` turns one epoch of gravity
  information into a normal equation in the coefficients of a regional
  basis: N = A' C^-1 A, b = A' C^-1 y, ltpl = y' C^-1 y. These are formed
  through the Cholesky factor of C, or 1/sqrt of a diagonal, never an
  inverse. A non-positive-definite covariance is refused.
  The result is a `neqCombine` contribution (N, b, ltpl, nobs, name), so
  several kinds from one epoch combine with variance components, and its
  N and b update `kalmanFilter` in normal-equation mode. The kinds are:
  - `"solution"`: SH coefficients and their covariance; A = T.
  - `"neq"`: an SH normal equation, struct N/b or a readSINEX NEQ result,
    carried into the basis as T'NT, T'b. ltpl and nobs pass through.
    GNSS and other groups built outside shAnalysis enter this way.
  - `"points"`: point functionals in any `kernelFactors` quantity at any
    height. `Direction` gives the gradient along a direction (the gravity
    vector for the potential). `Combine` forms linear combinations,
    including differences of two points, the LGD shape.
- `g.regionalNEQ(B)` is the field as an observation in the basis, using
  its formal sigmas, or `Cov=`.
- `tools/dev/validate_regional_observations.py`:
  - T'NT, T'b solve to the generating state (1.1e-12).
  - The point design equals the RBF's Legendre series at 0-500 km
    (4.2e-15).
  - The directional design equals the analytic ECEF gradient (4.0e-10,
    the oracle's finite-difference floor).
  - The Cholesky route equals the explicit route (5e-16).
  - ltpl - 2x'b + x'Nx = v'C^-1 v.
  - Combined rows equal row differences.

  The shared RBF builder moved into `regional_oracle_lib.py`.

## [5.15.0] - 2026-10-20 - WP8 8b: Kurtenbach's process model in a regional basis

A MINOR: one new function, one class method and one estimateVAR option,
the second row of WP8. No documented call or error identifier changes;
`estimateVAR` without the new option is bitwise unchanged.

### Added
- `shLowLevel.regionalProcessModel(ts, B)` and `ts.regionalProcessModel(B)`:
  the stochastic process model of Kurtenbach (2012, DGK C-683, Sec. 3.2)
  in the coefficients of a regional basis. The model series' climatology
  is removed, every epoch projected onto the basis, and the VAR model
  estimated by `estimateVAR`. On the SH basis it is, bit for bit, the
  model `kalmanChain` builds. Kurtenbach's two adjustments are options:
  - `QScale`, the alpha of his eq. 4.8, scales Q alone (Phi and Sigma0
    are bitwise unchanged);
  - `GroundNoise`, an isotropic white EWH variance added to Sigma(0), read
    as sigma^2 / (P f_n^2) per Stokes coefficient. That gives pointwise
    variance sigma^2 everywhere and needs `kn`.
  `info.representation` reports the share of the model's regional signal
  energy the basis can carry.
- `shLowLevel.estimateVAR(..., Sigma0Add = G)`: a covariance added to
  Sigma(0) only, after Shrink and before CondFun. Shrink is the special
  case s trace(Sigma0)/P I, which a test pins bitwise.
- `tools/dev/validate_regional_process.py`:
  - climatology removal and projection commute (6e-16);
  - the ground noise's pointwise variance is exact (1.3e-14);
  - a VAR(1) simulated in an RBF basis is recovered through the whole
    pipeline within the sampling error, measured over 60 seeds;
  - a Sigma(0) addition changes B, and Q stays positive definite.

  The basis routines it shares with `validate_regional_basis.py` moved to
  `tools/dev/regional_oracle_lib.py`, so the two oracles check one basis.

## [5.14.0] - 2026-10-20 - WP8 8a: a regional basis for a selectable basin

A MINOR: three new functions and four class methods, the first row of
WP8, the regional Kalman filter on local basis functions (CLAUDE.md 5).
No documented call or error identifier changes.

### Added
- `shLowLevel.readBasin(name)`: a basin of a GravIS GeoJSON file as a
  region handle, by name or a unique part of one ("Elbe" finds "Elbe
  River"). The handle is wrap-safe: rings are unwrapped along their
  longitudes, a ring winding around a pole is closed through it, and a
  query is tried at lon and lon +- 360, so the three rivbas basins that
  cross lon 0 (Loire, Niger, Volta) and the Antarctic basins are inside
  where they should be. Holes and MultiPolygons are read.
- `shLowLevel.regionalBasis(idx, region, Type=...)`: K local basis
  functions as a linear map `T` (P x K) to SH coefficients, and the
  region-weighted least-squares projector `Proj` (K x P) back.
  - `"rbf"`: radial basis functions after Eicker (2008) and Woehnke et
    al. (2025), `T(:,k) = phi_n .* Ybar(x_k)'`, on an icosahedral grid
    of 10 (j+1)^2 + 2 nodes (their eq. 8) or a Reuter grid; shape
    coefficients from the signal's degree amplitudes (their eq. 7),
    Kaula's 1/n^2 (default) or Shannon. The default level makes the
    global grid as large as the SH basis: j = 30 at nmax 96.
  - `"slepian"`: the tapers of `slepianBasis`, by Shannon number, count or
    concentration threshold (Steffen et al. 2026 use 0.5).
  - `"sh"`: the identity - the global filter, and so the oracle of the
    regional one.
  The region is grown by `BufferKm` (600, Woehnke's computation area)
  before nodes are selected, tapers concentrated and the projector
  weighted. Only grid points inside the buffered region are formed, so
  the cost follows the region, not the sphere.
- `shLowLevel.regionalProject(Cs, Ss, B)`: coefficient sets in the basis
  and back; for a Slepian basis it equals `slepianProject`.
- `ts.regionalBasis`, `g.regionalBasis` (the basis at the object's own
  degree, so the index cannot disagree) and `ts.regionalProject`,
  `g.regionalProject` - thin delegates, pinned bitwise.
- `shLowLevel.synthesisMatrix(..., GridOnly = true)`: the weights and the
  grid without the matrix.
- `tools/dev/validate_regional_basis.py`: node counts, the RBF against
  the Legendre series (1.2e-14), the projector's normal equations
  (2e-11) and span reproduction (9e-12), projector = G' for Slepian
  (2.2e-15), the Elbe's area against its exact spherical polygon, the
  Loire and a polar ring.

### Changed
- `shLowLevel.evalMask` asks `synthesisMatrix` for the grid only. It used
  to build the whole synthesis matrix to read the grid off it - 0.9 GB at
  nmax 60 and OverSample 2, 5.6 GB at nmax 96 - and discard it. The mask
  and grid are bitwise unchanged (pinned by
  `testSynthesisMatrixGridOnlyIsTheSameGrid`).
- `slepianBasis` and `evalMask` are now reached from a class (through
  `regionalBasis`): the class-surface backlog is 13, the exceptions 34,
  and 84 of 131 public functions are reachable.

### Measured
- The Elbe polygon of basins_rivbas.json has 140 031 km^2 on a sphere of
  6378.1363 km; the mask quadrature at nmax 60, OverSample 2 is 3.6%
  below it, at nmax 96, OverSample 4 1.2% above. Straight (lon, lat)
  edges and great-circle edges differ by less than 1e-4 of the area for
  every rivbas basin (worst 4.3e-5, Issyk-kul).

### Open
- A33: four chains parse GravIS GeoJSON themselves; moving them onto
  `readBasin` is left for a release with captured references.

## [5.13.1] - 2026-09-11 - Documentation audit: help, html and guide in sync

A PATCH: documentation, one demo fix, and a wider documentation gate. No
documented call or error identifier changes.

### Fixed
- README quick start: `clim.amplitudeMap` was called with five positional
  arguments; the contract takes three, with `Quantity=` and `kn=` as options.
- Guide: ten snippets assigned `Idx=` and then used `idx`; the G9 recipe
  called `shLowLevel.plotSHMap`, removed in v3.32.0; six paragraphs printed a
  literal `%%`; one printed a mangled download path.
- `shSynthesis.html` and `legendreALF.html` called both functions without
  `shLowLevel.`, which v3.0.0 made necessary; `seaLevelFingerprint.html` and
  `slepianBasis.html` had the `Idx=` defect too.
- `demo_shAnalysis`: D05/D06 looked for a fetched ITSG series only in the
  pre-v3.16 folders, so no fetch made since v3.16 was found. The v3.16 folder,
  `<dataFolder>/series/itsg/monthly`, is searched first; on the acceptance
  machine D05 now finds the 257 fetched months.
- Stale statements corrected: the "5-20x" FFT figure, never measured, on the
  shSynthesis and shCoefficients pages; GIA "treated as exact" in the guide
  (v5.2.0 propagates its sigma), and a pointer to that route in
  `shClimatology.removeGIA`'s help; the v3.16 download layout in five pages,
  in the `fetchICGEM`, `dataFolder`, `setup_shAnalysis` and `fromFolder` help
  and in the guide; test fixtures "shipped in tests/test_data" (a plain clone
  has none; NOTICE now says where they are); "four" test suites (five); "six"
  CI gates; `standardChain`'s "DDKn (fetched on demand)" (it reads the data
  folder and never fetches); the guide's error-identifier convention (three
  parts since v5.0.0), its edition, its test count, and the date in its page
  stamp, which is now read from Contents.m.
- Five help blocks named their see-also targets in the old upper-case form
  (`SHSERIES/TOGRID`); they name the qualified entities now.
- Six html pages opened `<body><div class="content">` twice and one closed
  `</head>` twice - invisible in a browser, which forgives both; each page
  opens one head and one body now.

### Added (documentation)
- The seven opt-in real-data tests are documented, each with what it needs and
  where it looks: the setup page, README and the guide said two.
- The class pages name every public method: 17 were missing from
  shCoefficients, 10 from shSeries, 1 from shClimatology.
- Guide chapters 28-32 - the ellipsoid, the data-driven leakage correction,
  model grids, Earth-rotation excitation, bridging the mission gap - and
  guide G14, the lanes behind the classes. References gain the sources those
  chapters cite; the function index of the API reference sorts 123 of 128
  functions into categories (51 had fallen into "Utilities"); a heading no
  longer ends a page without its text.
- README "What is new" covers v4.0.0 to v5.13.0, and its data-source table the
  fetchers added since.

### Gates
- `doc_sync_audit.py` PROSE: the contract check now reaches html `<code>`
  spans, the guide's Courier spans, README code fences and the Contents.m
  quick start; no code block may call a package function without its
  namespace; every public method must be named on its class page; every error
  identifier a narrative page names must be one something raises; and each
  hand-written page must open one head and one body. Each rule is
  fault-injected with the defect found here
  (`tools/tests/test_doc_sync_prose.py`, 18 tests).

### Tests
- 384 runs, unchanged.

## [5.13.0] - 2026-09-10 - WP7 backlog: four more lanes behind the classes

A MINOR: six class methods, each a thin delegate.

### Added
- `g.poleTideConvert` and `ts.poleTideConvert`: C21/S21 moved to another
  mean-pole convention - on a field through `shLowLevel.poleTideConvert`'s
  object form, on a series through its raw form at every epoch, which
  keeps the series' names, sigmas and history.
- `ts.estimateDegree1(ocean, kn = ...)`: the geocentre coefficients of
  every epoch (Swenson, Chambers & Wahr 2008), ready for `ts.addDegree1`.
- `ts.combineCenters({tsB, tsC})`: the VCE combination of this series with
  other centres', on this series' epochs.
- `g.slepianProject(G, idx)` and `ts.slepianProject(G, idx)`: projection
  onto a Slepian basis, and back.
- Each is pinned bitwise to its lane in testContract. The class-surface
  gate's backlog shrinks from 18 to 14, and 79 of the 128 public lanes are
  now reached from a class. The fourteen that remain take grids, load
  regions or function handles, where a method would do more than forward.

### Tests
- 382 -> 384 runs: `testCoefficientsBacklogRoutesAreTheirLanes` and
  `testSeriesBacklogRoutesAreTheirLanes` in testContract.

## [5.12.2] - 2026-09-10 - WP2: two speed candidates measured, neither built

A PATCH: documentation and records only; no code path changes.

### Measured
- **B1, the packed Legendre layout, is not built.** The same recursion
  writing latitude-first, so that every write is contiguous, is 1.67x
  faster at nmax 96 / 181 latitudes and 1.69x at 180 / 361, but only 1.21x
  at 360 / 91 and 1.11x at 720 / 31. Every caller indexes P(n+1, m+1, :),
  so a drop-in has to permute back, and that leaves 0.92-0.99x. The
  results are bitwise identical in all four cases. WP2's own bar was 2x.
- **`shSynthesis`'s `auto` keeps FFT.** Across 13 sizes from nmax 30 /
  1 degree to 360 / 0.5 degree on MATTHIASPC, the whole call is 0 to 14
  percent faster with `direct` - the largest gaps at nmax 30 and 60,
  within 1 percent from nmax 240 up - and the two agree to 8e-14. The
  paths share the Legendre recursion and the reduction, so the gap is the
  longitude step alone, at most 7 ms. On A8 the reduction alone ran 1.40x
  faster with FFT at nmax 60. No path wins on both machines, so `auto` is
  unchanged, and the `Method` help now says so.

## [5.12.1] - 2026-09-10 - A30: no NaN reaches an analysis

A PATCH: three refusals where NaN used to pass silently, or with the
wrong cause.

### Fixed
- **`shLowLevel.shAnalysisGrid` refuses a grid holding NaN or Inf**
  (`nanInGrid`). Measured before the fix, a ring grid with a NaN polar cap
  came back with 153 of 289 C and 136 of 289 S coefficients NaN, and no
  error. `shCoefficients.analysis` has refused NaN since 5.8.0; the lane
  now does too, for every caller.
- **`leakageCorrect` without a Mask refuses NaN anywhere** (`nanInput`).
  Without a Mask the whole grid is the model the chain analyses, so a NaN
  outside the ResidualRegion spread through it and the call failed with
  `diverged` - the misleading cause audit F-20 was written against. With a
  Mask nothing changes: NaN outside both regions is still tolerated.
- **`gridScaling` refuses a model holding NaN** (`nanInput`). A model with
  NaN over the ocean returned no finite factor at all (0 of 1122 pixels),
  silently, and `readGrid` makes such land-only models easy to load. Fill
  the gaps first: 0 over an ocean is a choice to make explicitly.

### Unchanged
- Every call that worked before, bitwise: `leakageCorrect` with a Mask and
  NaN outside both regions, and NaN-free `leakageCorrect`, `gridScaling`
  and `shAnalysisGrid`, captured before the edit and compared after.

### Tests
- 381 -> 382 runs: `testNaNNeverReachesAnAnalysis` in testContract pins
  the three refusals, the lane's in both of its layouts.

## [5.12.0] - 2026-09-10 - WP5 5d: bridging the GRACE gaps

A MINOR: new API - `shLowLevel.bridgeGaps` and `shSeries.bridgeGaps`.

### Added
- `shLowLevel.bridgeGaps(ref, bridge)` fills every month a reference
  series lacks within its span from a second series, calibrated on the
  months both have. Both are truncated to the lower nmax and smoothed with
  a 750 km Gaussian (`RadiusKm`); per coefficient the offset between the
  overlap means is removed; per degree a scale regresses the reference's
  anomalies on the bridge's; a filled month is R0 + s_n (B - B0), and its
  sigma is the overlap residual RMS of that degree. Filled months are
  named "bridge:" plus their name in the bridge series, and
  `info.bridged` marks them.
- `ts.bridgeGaps(tsB)`, a thin delegate.
- `parseGraceFilename` reads QuantumFrontiers-style monthly names,
  `..._YYYY_MM`, so the HLSST+SLR series at ICGEM gets its epochs in
  `shSeries.read`.
- `tools/dev/validate_bridge.py`: the method written out, a small case the
  tests pin, the identity case, and - on a synthetic series with held-out
  months - a scale that halves the fill error and a predicted sigma that
  matches the actual one (0.98).
- `testBridgeGapsAgainstGRACE` in testScience, opt-in, with the new
  `SHX_BRIDGE_FOLDER` (or the `BridgeFolder` preference) and
  `SHX_SERIES_FOLDER`.

### Measured
- **The two variants.** QuantumFrontiers HLSST_SLR_COMB2023s at ICGEM
  (240 Kalman-filtered and 240 unfiltered monthly solutions, 2003-2022,
  degree 60) against COST-G RL02.1 GSM, both at 750 km, over the 208
  months both have: the fill's error over degrees 3-60 is 45 percent of
  the GRACE signal for the Kalman variant (41 with the scale) and 92
  percent for the unfiltered one (62). The unfiltered variant is
  noise-dominated above degree 10 at this radius, so the Kalman variant
  is the one to use.
- **Held out and bridged back.** With TN-14 applied first, 35 of the 209
  GRACE months inside the HLSST span were removed and filled: the error is
  0.381 of the GRACE signal over degrees 3-60, and the actual error 1.03
  times the predicted sigma. The HLSST formal sigmas are 3 to 6 times too
  small at low degrees, which is why the sigma comes from the overlap.
- **32 months are filled** on the full run: June 2003, the 2011-2017
  battery-management months, July 2017 to May 2018, and August and
  September 2018.
- **Tide system.** COST-G's files are tide-free and HLSST's zero-tide; the
  offset step takes up the 4.2e-9 difference in C20.

### Data, outside the repository
- HLSST_SLR_COMB2023s (both variants, 83 MB), fetched with the toolbox's
  own `fetchICGEM` into the data pool's series folder.

### Tests
- 377 -> 381 runs: `testParseGraceFilenameQuantumFrontiersMonthly` and
  `testBridgeGapsCalibration` in testCorrectness, `testBridgeGapsContract`
  in testContract, and `testBridgeGapsAgainstGRACE` in testScience (opt-in,
  so A8 now filters seven tests).

## [5.11.0] - 2026-09-10 - WP5 5a: the length of day, the IERS constants, a real-data check

A MINOR: `Earth` defaults to the IERS Conventions (2010), and
`rotationExcitation` and `ts.excitation` return the change in the length
of day in ms.

### Added
- `dLOD`, the change in the length of day [ms], beside chi3:
  `dLOD = (2 pi / Omega) chi3`, eq. (2.8) of the ESMGFZ Product
  Description Document (Dobslaw & Dill 2019) with its eqs. (2.3) and
  (2.13). `ts.excitation(..., TN14 = ...)` adds it as a column,
  `info.lodScale` gives the ms per unit chi3, and `Omega`
  (7.292115e-5 rad/s, ESMGFZ Table 2.1) is an option.
- `Earth = "IERS2010"`, the default: M, R, C and A from the IERS
  Conventions (2010), Table 1.1. The table gives G, GM, a_E, J2 and the
  dynamical flattening H, so M = GM/G, C - A = J2 M a_E^2,
  C = (C - A)/H and R = a_E. `info.earth` reports the four used; a
  struct of your own still works.
- `testExcitationAgainstESMGFZ` in testScience, opt-in: GRACE's
  excitation against the ESMGFZ hydrology (HAM) plus sea-level (SLAM)
  model series. It reads the new `SHX_EARTHROTATION_FOLDER` (or the
  `EarthRotationFolder` preference) and `SHX_SERIES_FOLDER`.
- `validate_excitation.py` CLAIMs 4-6: the IERS 2010 constants and their
  agreement with ESMGFZ's own table; the dLOD scale and sign; and,
  opt-in, the observed length of day against the ESMGFZ model.

### Changed
- `Earth` is no longer required. Omitting it now means IERS 2010, where
  5.10.0 refused the call with `noEarth`. `noEarth` now means an `Earth`
  that is neither a convention name nor a struct with M, R, C and A; an
  unknown convention name raises `badEarth`. No call that worked in
  5.10.0 changes its result.

### Measured
- **The ESMGFZ document prints eq. (2.8) as 2 pi Omega, which is not a
  time.** Read as 2 pi / Omega it is, and the data agree. The observed
  length of day (EOP 14 C04, 2002-2022, 241 months, a 25-month running
  mean removed) against the ESMGFZ atmosphere, ocean, hydrology and sea
  level converted that way gives correlation 0.943 and slope 1.097; read
  as printed, the slope would be 2e8. The Python oracle and a MATLAB
  probe agree to the digits.
- **GRACE against the model.** COST-G RL02.1 (255 months) with the TN-14
  C20, against ESMGFZ HAM + SLAM, detrended: correlation 0.343 (chi1),
  0.583 (chi2), 0.690 (dLOD) - every sign agrees. The raw series
  correlate negatively (-0.66, -0.63, -0.39), because GRACE holds the
  ice-sheet loss and GIA that the model lacks.
- **IERS 2010 against ESMGFZ's constants:** C and A agree with ESMGFZ's
  Table 2.1 to 0.03 percent.
- **The axial factor.** ESMGFZ's prefactors give 0.844 where Chen &
  Wilson's eq. (1) has 0.753 - 12 percent, close to C / Cm = 1.129 - while
  the polar ones agree to 0.3 percent. `AxialFactor` stays 0.753: the
  model comparison (a dLOD amplitude ratio of 0.94) cannot tell the two
  apart.

### Data, outside the repository
- The ESMGFZ AAM, OAM, HAM and SLAM series for 2002-2026 (27 MB) and the
  Product Description Document (16.7 MB), downloaded to the data pool's
  EarthRotation folder.

### Tests
- 375 -> 377 runs: `testRotationExcitationIERS2010AndLengthOfDay` in
  testCorrectness (the IERS constants, the unit responses and the dLOD
  scale and sign, pinned from the oracle), and `testExcitationAgainstESMGFZ`
  in testScience (opt-in, so A8 now filters six tests).
  `testRotationExcitationContract` moved its `noEarth` pin to a malformed
  `Earth`, and gained the unknown-convention and dLOD checks.

## [5.10.0] - 2026-09-10 - WP5 5a: Earth-rotation excitation

A MINOR: new API - `shLowLevel.rotationExcitation` and `shSeries.excitation`.

### Added
- `shLowLevel.rotationExcitation(C21, S21, Earth = E, kn = kn)`: the
  mass-load excitation of polar motion that the degree-2, order-1
  coefficients carry - Chen & Wilson (2003) eq. (1), solved for the
  excitation. chi1 and chi2 come in mas; with `C20 = ...` it adds chi3,
  the axial excitation. The changes are taken about the series mean
  (`Reference = "mean"`), or the input is taken as changes (`"none"`).
  The factors 1.098 and 0.753 are the paper's (after Eubanks 1993) and
  are options.
- `ts.excitation(Earth = E, kn = kn)`: the lane on the series' C21 and
  S21, as a table of t, chi1 and chi2. With `TN14 = table` it replaces
  C20 from TN-14 first and adds chi3. Without it the axial term is left
  out: GRACE determines C20 worst of all its coefficients, and a series
  cannot tell whether its C20 was already replaced.
- `tools/dev/validate_excitation.py`: eq. (1) as printed and solved,
  written independently of the MATLAB code. The inverse pair closes to
  2.4e-16; the unit responses it prints are what the tests pin.

### Not done, and why
- **The Earth's constants are required inputs, with no defaults.** Chen
  & Wilson give no values for M, R, C and A, and the toolbox hardcodes no
  physical constant, so the caller supplies them - as for the Love
  numbers.
- **No length-of-day change in ms.** The conversion of chi3 into a
  length-of-day change is not in the paper the function is written from,
  so chi3 is returned as eq. (1)'s dimensionless excitation until a
  source for the conversion is at hand.
- **No comparison with a published excitation series.** It needs the
  atmospheric and oceanic angular momentum (ESMGFZ) or a published GRACE
  series, and neither is in the data pool.
- chi1 and chi2 are in the frame of the coefficients, y towards 90 E,
  which eq. (1) fixes; the IERS pole coordinate y points to 90 W. The
  help says so, and there is no `Convention` option.

### Tests
- 373 -> 375 runs: `testRotationExcitationInvertsChenWilson` in
  `testCorrectness` (the oracle's unit responses, the inverse pair against
  eq. (1) as printed, mean removal) and `testRotationExcitationContract`
  in `testContract` (six refusals, the bitwise delegate, and the axial
  term only from a TN-14 C20).

## [5.9.0] - 2026-09-10 - WP5: the method of scale

A MINOR: new API - `Method` on `shLowLevel.leakageDataDriven` and
`shSeries.leakageDataDriven`.

### Added
- `leakageDataDriven(..., Method = "scale")`: Vishwakarma's method of
  scale (thesis eq. 3.28), the second of the two data-driven corrections.
  It removes the same leakage estimate as the method of deviation - phase
  step included - and then scales the remainder up,
  `fHat = s (gbar_c - lhat)`, instead of subtracting a deviation
  integral. The scale factor `s = int R / int R Rbar` (eq. 2.27) depends
  on the catchment and the filter only; `info.scale` reports it whichever
  method ran, and `info.method` names the one that did.
  `ts.leakageDataDriven` forwards `Method`.
- The help states the thesis's two caveats: `s` rests on the
  uniform-layer approximation (eq. 2.26), so it repairs the attenuation
  exactly only for a uniform layer; and `s` grows as the catchment
  shrinks, which amplifies errors in small catchments.
- `validate_leakage_datadriven.py` CLAIM 4: for a uniform layer inside the
  catchment, `s` times the filtered catchment average returns the layer
  (to 1.5e-16). CLAIM 5: the method of scale on the closed loop.

### Unchanged
- The default is still the method of deviation, and it is bitwise
  unchanged. Four configurations (Gaussian 300 and 500 km, a fractional
  mask, DDK3) were captured before the edit and are identical after, apart
  from the two new `info` fields.

### Measured
- On the closed loops the method of scale removes more of the damage than
  the method of deviation: 75.0% against 55.3% on the `testCorrectness`
  fixture, and 78.6% against 62.9% in the oracle. **This ranks nothing.**
  Both fixtures put a uniform layer inside the catchment, which is exactly
  the case the scale factor is exact for. A real catchment's signal is
  not uniform, and the thesis's caveat applies, so the default stays the
  method of deviation.

### Tests
- 371 -> 373 runs: `testLeakageMethodOfScale` in `testCorrectness` (the
  formula bitwise; `s` recomputed through the same chain; `s` holding no
  data; the uniform-layer identity; the closed loop) and
  `testLeakageDataDrivenMethodContract` in `testContract` (the default is
  the method of deviation bit for bit, an unknown method is refused, and
  `ts.leakageDataDriven` forwards `Method`).

## [5.8.0] - 2026-09-10 - WP5 5e: CF grids in, and analysis refuses NaN

A MINOR: new API - `shLowLevel.readGrid`, and `Fill` on
`shCoefficients.analysis`.

### Added
- `shLowLevel.readGrid(file, Var = ...)` reads a latitude-longitude field
  or stack from a CF netCDF file into the toolbox's layout -
  (nlat x nlon [x T]), longitudes 0..360 ascending, epochs as decimal
  years. It is the inverse of `writeGrid` and the way in for grids from
  elsewhere: hydrological models, GravIS Level-3 grids. Dimensions are
  found by name and coordinates by their standard name or units, in any
  order; latitudes keep the file's order; fill values become NaN, as
  `ncread` applies them. The latitude type is reported, never assumed:
  `writeGrid` records `lat_type`, and a grid from elsewhere reports "" -
  by convention those are geodetic, so pass `LatType = "geodetic"` to
  `analysis`.
- `shCoefficients.analysis(..., Fill = value)`. A grid holding NaN - a
  land-only model grid, a masked field - used to reach every coefficient
  without an error. `analysis` now refuses it
  (`shCoefficients:analysis:nanInGrid`) until `Fill` says what the gaps
  mean. With `Fill` it is bitwise the analysis of the filled grid; on a
  grid without NaN it changes nothing.
- `tools/dev/validate_readgrid.py`: an independent CF time decoder
  (Python's datetime) and an independent read of the GravIS grid (scipy),
  pinning the values the tests check.

### Changed
- **One CF time decoder.** `readMascon` had a pattern of its own that read
  `days since YYYY-MM-DD` with two-digit months only, and so refused
  GravIS's `days since 2002-4-18 00:00:00`. Both readers now call one
  private decoder: days, hours, minutes or seconds, one- or two-digit
  fields, an optional clock time. On the real CSR mascon file
  `readMascon`'s output is bitwise unchanged - captured before the edit:
  the epochs, the axes, the units, a sample of the values, their sum and
  their NaN count. A reference time with a non-zero clock was read at
  midnight before; it is read at the stated time now.

### Measured
- **The GravIS TWS grid** `GRAVIS-3_GFZOP_0600_TWS_GRID_GFZ_0006.nc`, this
  row's real file (a GLDAS file needs an Earthdata login): `readGrid` and
  scipy give the same stored doubles at four land cells, 50,090 NaN - the
  ocean - in the first epoch, and 256 epochs from 2002.29 to 2026.29. It
  then enters `analysis` with `Fill = 0`.
- **A MATLAB behaviour the oracle could not see.** `regexp(..., 'tokens',
  'once')` DROPS the tokens of an optional group that did not take part,
  instead of returning them empty, so the decoder's first draft failed on
  the CSR file, whose time units carry no clock. Python's `re` returns
  `None` for such a group; the capture on the real file is what found it.

### Tests
- 365 -> 371 runs: three in `testCorrectness` (the `writeGrid` round trip;
  any dimension order and longitude range; one time decoder for both
  readers), two in `testContract` (`readGrid`'s nine refusals; `Fill`),
  and one real-file test in `testRobustness`. That one is skipped without
  the GravIS folder, so A8 now skips five tests, not four.

## [5.7.1] - 2026-09-10 - A28, A26, and a guide PDF git no longer rewrites

A PATCH: three fixes. One new error identifier per ocean chain, on a path
that used to crash or return an empty result; no valid call changes.

### Fixed
- **A28: `oceanChain` and `obpChain` refuse a missing `OceanMask`**
  (`shLowLevel:oceanChain:noOcean`, `shLowLevel:obpChain:noOcean`). Both
  document the mask as REQUIRED and defaulted it to `[]` without checking.
  `oceanChain` then failed with `MATLAB:badsubscript` in its trend fit,
  whatever the filter - measured with the preferences' data. `obpChain`
  would have returned a grid with its land values intact and an empty
  ocean-mean series, without an error - read from its code, because this
  machine has no GAD folder to run it with. Both now refuse before any
  data is read, as `gravisRegionChain` already did with `noOcean`.
- **A26: `twsChain` looks for DDK files where `fetchDDK` puts them**,
  `<dataFolder>/DDK`. It looked only in the lower-case `ddk` - the same
  folder on Windows, a different one on Linux and macOS. `ddk` stays in the
  list, after `DDK`, for files placed there by hand. This cannot be
  observed on Windows, A8 included, where both spellings name one folder,
  so it is verified by reading.
- **A29: the guide PDF is no longer rewritten by git.** It is pure ASCII
  (reportlab's ASCII85 streams), so git took it for text and
  `core.autocrlf` converted it on a Windows checkout: the pull of #107 on
  the acceptance machine inserted 3589 CR bytes and left `startxref`
  pointing into the middle of a stream. The committed blob was always
  intact. A new `.gitattributes` marks `*.pdf` - and the other binary types
  - `binary`; text files are deliberately not normalized.

### Checked from now on
- `doc_sync_audit.py` fails when `.gitattributes` stops marking the guide
  PDF binary, and when the PDF's `startxref` does not point at its xref
  table. The second check was run on the corrupted working copy before it
  was rebuilt, and it fired; the page-1 stamp check beside it had passed
  that file, because ASCII85 ignores the inserted bytes. 11 self-tests,
  the CRLF rewrite among the injected faults.

### Tests
- 364 -> 365 runs (`testContract` 101 -> 102): both ocean chains refuse a
  missing mask before they touch a folder that does not exist.

## [5.7.0] - 2026-09-10 - A25, and three more class routes

A MINOR: new API - `shLowLevel.filterSpec` and three `shCoefficients`
methods. Every valid filter spec gives bitwise the numbers it gave before;
what changes is that a malformed spec is now refused, loudly, by every lane.

### A25: one reader of the Filter vocabulary
- `shLowLevel.filterSpec(F)` reads a filter specification - `"none"`,
  `"gauss<radiusKm>"` with a radius greater than zero, `"DDK1"` to
  `"DDK8"`, or a W struct - and says what it means. With two outputs it
  never raises: it returns the reason, so each caller keeps raising under
  its own documented identifier. `Allowed` states the kinds a caller admits.
- The eight lanes that parsed it each on their own now call it:
  `leakageCorrect`, `leakageDataDriven` and `gridScaling` (three copies of
  one private `resolveFilter`, identical but for the identifier),
  `standardChain`, `twsChain`, `gravisRegionChain` (and so `greenlandChain`
  and `antarcticaChain`), `oceanChain` and `obpChain`. The chains read the
  spec before any data, so a typo no longer costs a full read first.
- `twsChain` carried its own copy of the eight DDK file names; it now uses
  `shLowLevel.ddkNames`, which calls itself the single source of truth for
  them. The eight names were compared and are identical.

**Measured on the old code, before any edit** - the defects the finding
had only inferred:
- `twsChain(..., Filter = "gaussX")` ran and returned NaN in 255 of its
  507 output numbers, without any error.
- `oceanChain` and `obpChain` read any text as a Gaussian radius, so
  `"DDK3"` became a radius of NaN, and `shGaussianWeights(60, NaN)` makes
  60 of its 61 weights NaN.
- The four chains that never checked the radius accepted a negative one,
  and `shGaussianWeights(60, -5)` gives weights between 0.9992 and 1: no
  filter at all, without a word.
- Text that starts with `"DDK"` but is not `DDK1`..`DDK8` went to `readDDK`
  as a FILE path in four lanes. It is now refused; pass the W struct
  `readDDK(file)` returns instead.

**Proven bitwise, not argued.** Every lane was run on every kind of spec
before the edit and again after it - `leakageCorrect`, `leakageDataDriven`
and `gridScaling` on fixtures (four specs each), `standardChain` on the
shipped monthly file (four), and `twsChain` on the real GravIS data
(three): all 19 outputs identical, and the only entries that differ are
the refusals. `oceanChain` (with a latitude-band ocean mask) and `greenlandChain` (with a numeric `NoiseLevel`), which the first capture could not run for want of inputs, were then run on an extracted copy of the old tree and on the new one: four more outputs, all identical. `obpChain` could not be run here - it needs a GAD
folder this machine does not have - so its valid path is equivalent by
construction and not by measurement.

### Three class routes off the backlog
- `g.synthesisPoints(lat, lon, r, ...)` - `shLowLevel.synthesisPoints` at
  scattered 3-D points.
- `g.gradientTensor(lat, lon, ...)` - the full gradient tensor,
  `shLowLevel.shSynthesisGradientTensor`.
- `g.vdkApply(N, sigM, Index = idx, Alpha = ...)` -
  `shLowLevel.vdkApply`, the coefficients taken in `Index` ordering
  (default `shIndex(nmax, Nmin = 2)`) and put back, the degrees outside it
  unchanged, the sigmas NaN as for `g.applyDDK`.
- As for every WP7 delegate, a lane's options are forwarded only when
  given, and each method is pinned bitwise against its lane with options
  and without. The class-surface backlog shrinks from 21 to 18; reach
  rises to 73 of 125.

### Fixed
- **`shLowLevel.vdkApply`'s documented `badSize` identifier could never be
  raised** (A27). Its message passed `size(N)` - two numbers - to the
  format, so MATLAB threw "Formatted arguments must be scalar" first. The
  test written for `g.vdkApply` found it; it now passes scalars.

### Recorded, not fixed
- **A26**: `twsChain` looks for DDK files in `dataFolder/ddk`, `fetchDDK`
  stores them in `dataFolder/DDK`; the two agree only on a
  case-insensitive filesystem.
- **A28**: `oceanChain` documents `OceanMask` as REQUIRED, defaults it to
  `[]` and does not refuse it: without a mask it fails with
  `MATLAB:badsubscript` at its trend fit. `gravisRegionChain` refuses the
  same omission with `noOcean`.

### Tests
- 357 -> 364 runs (`testContract` 94 -> 101): four for `filterSpec` and
  the lanes' refusals (every chain refuses a malformed spec before it
  touches a folder that does not exist), three for the new routes.

## [5.6.0] - 2026-09-10 - WP7: the classes reach the lanes

A MINOR: new API, and nothing existing changes. Eight methods put lanes
that were reachable only as `shLowLevel.*` calls behind the classes, and
`Surface` now reaches `toGrid` and `map`. Every new method is a thin
delegate, pinned **bitwise** against the call it makes. A new gate
measures what `Contents.m` claims when it calls the classes "the single
point of access": before this release **58 of 124** public `+shLowLevel`
functions were reachable from a class method, now **69**, and each of the
other 55 is a named exception with its reason or sits in a backlog that
may only shrink.

### Added
- `ts.kalman(ModelSeries = tsm, ...)` - `shLowLevel.kalmanChain` with the
  series as the observations (solution mode). The normal-equation mode
  reads a SINEX folder, has no series to be a method of, and stays on the
  function.
- `ts.eof(...)` - `shLowLevel.eofAnalysis`.
- `ts.leakageCorrect(lat, lon, Filter = ..., kn = ...)` - every epoch
  through `g.synthesis` and `shLowLevel.leakageCorrect`, with the series'
  GM and R; the corrected stack and one `info` per epoch.
- `ts.leakageDataDriven(lat, lon, Mask = ..., Filter = ..., kn = ...)` -
  the synthesized stack through `shLowLevel.leakageDataDriven`.
- `ts.gradient(lat, lon, ...)` - `g.gradient` of every epoch, each
  component stacked along the third dimension as `ts.toGrid` stacks its
  fields.
- `ts.write(folder, FileNames = ...)` - one `.gfc` file per epoch
  through `g.write`.
- `g.basinAverage(B)` - the one-epoch `shSeries.basinAverage`.
- `g.errorMap(lat, lon, Covariance = M, Index = idx, ...)` -
  `shLowLevel.errorMap` with the object's GM and R. Without `Covariance`
  it propagates the object's formal sigmas as a diagonal covariance, and
  its help says what that leaves out: every correlation, which for GRACE
  is the stripes.
- `Surface` and `SemiMajorAxis` on `g.toGrid`, `g.map` and `ts.toGrid`,
  forwarded to `g.synthesis`. WP3 had stopped at `g.synthesis` and
  `g.gradient` on purpose.
- `tools/dev/class_surface_audit.py`, in CI: the call graph read from the
  source (comments and string literals blanked by `mlint_lite`'s
  scanner), its closure taken from the three classes. 12 self-tests.

### Design
- **A lane's options are declared without defaults and forwarded only
  when given** (`namedargs2cell`). Each default lives in the lane's
  arguments block and nowhere else, so a method cannot drift from its
  lane; the help rows say "(lane default)". `shSeries.filter`'s help
  already stated this rule for its tuning options; WP7 applies it to
  every option of every new delegate.
- **Both leakage methods REQUIRE `Filter`,** although the functions
  default it to `gauss300`. A series cannot know which filter its data
  saw, and the wrong one makes the correction meaningless without any
  error: `shSeries:leakageCorrect:noFilter`,
  `shSeries:leakageDataDriven:noFilter`.
- **`ts.write` warns when a file name will not bring its epoch back**
  (`shSeries:write:epochNotInName`): a `.gfc` file has no epoch field,
  and `shSeries.read` takes the epoch from the name alone. It refuses a
  missing folder rather than create one (`shSeries:write:noFolder`) and
  names that are not one per epoch (`shSeries:write:badFileNames`).
  `Sidecar` defaults to false here, where `g.write` defaults to true,
  because the default read pattern `*.gfc*` would read every sidecar
  back as data.
- `g.errorMap` raises `shCoefficients:errorMap:noCovariance` when there is
  neither a covariance nor a formal sigma.

### Not built, by decision (Matthias, 2026-09-10)
- **No generic `shCoefficients.filter(method, ...)`.** The four named
  filter methods already are the class surface. Measured on the way: the
  filter-spec strings (`"gauss300"`, `"DDK3"`, `"none"`, a W struct) are
  parsed in **eight** separate places - recorded as A25, not fixed here.
- **No `shSeries.chain(name, ...)`.** The chains take a folder, return
  different products, and are one call each already. They are
  exceptions in the gate, with that reason.
- `shSeries.deformation` and `shSeries.excitation` stay with WP4 and
  WP5 5a; the functions they would call do not exist yet.

### Measured
- Reach from the classes, read by the gate: 58 of 124 before, 69 after.
  The eleven newly reached are the five lanes the delegates call and what
  those call in turn - `estimateVAR`, `kalmanFilter`, `rtsSmoother`,
  `neqCombine`, `readSINEX`, `chi2Quantile`.
- The first count, made before the gate existed, said 62 unreached where
  there are 66. That prototype did not blank string literals, so
  `readDDK`'s error message "Download it once with shLowLevel.fetchDDK"
  counted as a call - and three fetch helpers hung on that one string.
  That is the direction a reach check must not err in; the scanner the
  gate reuses is what caught it.
- Tests: 346 -> 357 runs (`testContract` 83 -> 94). All eleven new tests
  passed locally on their first run.

## [5.5.0] - 2026-09-10 - WP3: synthesis on the ellipsoid

A MINOR: new API. `Surface = "sphere" | "ellipsoid"` in `shSynthesis`,
`shSynthesisGradient`, `g.synthesis` and `g.gradient`, and a new
`shLowLevel.ellipsoidRadius`. The sphere path - the default - is **bitwise
unchanged**: 26 of 26 outputs captured from the pre-WP3 code before any
edit (six quantities, direct, FFT and banded, Height, the gradient on grids
and points) are identical afterwards.

### What finding B3 was about, in numbers

Every synthesis evaluated on a sphere of radius R. The ellipsoid lies
**inside** that sphere at high latitudes - 21.4 km at the poles - and the
radial law (R/r)^(n+2) amplifies high degrees there:

| degree | (R/b)^(n+2) at the poles |
|---|---|
| 60 | 1.23 |
| 96 | 1.39 |
| 180 | 1.84 |

So a degree-60 gravity term evaluated on the sphere at a pole is about 19%
smaller than on the ellipsoid. Low degrees barely move; the effect is a
high-latitude, high-degree one, which is exactly where polar ice and
gravity users look.

### The design

- The ellipsoid is **WGS84**: `SemiMajorAxis` 6378137 and `Flattening`
  1/298.257223563, both overridable. `a` is WGS84's, deliberately not the
  coefficients' reference radius R: R belongs to the series, `a` to the
  surface, and pairing WGS84's flattening with R would describe an
  ellipsoid nobody uses. A test pins that the default `a` is the one
  `normalFieldCS` uses.
- `shLowLevel.ellipsoidRadius(lat)` is the ONE place r(phi) is computed.
- `Height` adds to r(phi), so it means height above the surface either way.
- Gradient components stay in the local **spherical** frame: `up` is
  radial, not the ellipsoid normal, which differs by up to 0.19 deg. Said
  in the help rather than left to be discovered.

### Deviations from the WP, stated rather than smuggled

- **The geoid is refused on the ellipsoid.** The WP said both "surface
  quantities keep erroring" and "geoid on the ellipsoid". A proper
  ellipsoidal geoid also needs the latitude-dependent normal gravity
  gamma(phi), so correcting the radius alone would ship half a correction.
  The error says exactly that and points to evaluating `potential` on the
  ellipsoid and dividing by gamma(phi). Accepted quantities: potential,
  gravity_anomaly, gravity_disturbance, gravity_gradient_rr.
- **`synthesisPoints` has no `Surface` option.** It already takes a radius
  per point; `r = shLowLevel.ellipsoidRadius(lat) + h` does the job without
  overloading that argument's meaning.
- **The class methods forward `Surface`**, one line each, because they
  already forward `Height` and `Flattening` - and the class's one
  `Flattening` now describes both the latitude conversion and the
  evaluation surface, which is the same ellipsoid.
- **The EGM2008 reference was dropped** (Matthias, 2026-09-10: "you can
  drop the EGM2008 reference. Self-consistency is fine"). Acceptance is
  the oracle below.

### Measured

`tools/dev/validate_ellipsoid.py`, every claim against an independent
route inside the file:

| claim | result |
|---|---|
| the point lies on x^2/a^2 + z^2/b^2 = 1 | 4.4e-16 |
| f = 0 is the sphere | exact |
| textbook Legendre vs numpy's Legendre polynomials | 7.8e-14 |
| -dV/dr (finite differences) = gravity_disturbance on the ellipsoid | 3.2e-11 |
| gradient north/east vs finite differences at fixed r | 7.6e-12 |

The MATLAB tests pin synthesis and gradient against the oracle's values
at the WP's 1e-12, tie the gradient to the synthesis through the radial
identity, check grid synthesis against `synthesisPoints` at r(phi), and
prove the ellipsoid DEGENERATES to the sphere: with f = 0 and a = R the
output is bitwise the sphere's, in synthesis, banded synthesis and gradient.

### Fixed on the way

`shSynthesis`'s help said the FFT path is "5-20x faster at 1 degree". It was
never measured: A8 measured 1.40x at nmax 60, and at nmax 180 / 0.5 deg the
FFT path is slower than direct on MATTHIASPC. The row now says that.

### Record

v5.4.1's third A8 run, at `5d4980e`: 335 runs, 331 passed, 0 failed, 4
filtered - only the optional real-data fixtures, with all fourteen speed
budgets asserting on A8 and the worst tight one at 1.030x its baseline.
## [5.4.1] - 2026-09-10 - A9 closed: the noise had a cause, and it was not the timer

A PATCH that closes A9: four speed-budget workloads replaced, five promoted
to a tight tier at the number A9 asks for, and one wasted chain removed
from `leakageCorrect` with bitwise-identical output. No documented call or
identifier changes.

### Why the small budgets were noisy

`leakage_1iter_n24` moved between **23.1 and 30.2 ms** across seven A8
runs of untouched code. It was not the timer - at 23 ms the timer is
irrelevant. Measured on the acceptance machine:

| one `leakageCorrect` iteration, nmax 24 | median | p90/p10 |
|---|---|---|
| 16 threads | 12.4 ms | 1.44 |
| **1 thread** | **9.3 ms** | **1.15** |

Slower **and** noisier with more threads. On a 49 x 50 grid,
multithreaded BLAS spends more on thread scheduling than on arithmetic,
and on a shared runner that scheduling is what moves between runs. The
grid synthesis reduction showed the same signature (nmax 120 / 1 deg:
1.49 at 16 threads, 1.04 at one).

So the fix was not a braver factor. It was a workload large enough for
threading to pay for itself - the same move that made `apply_ddk_n300`
steady in v5.3.0:

| replaced | by | between-run spread, MATTHIASPC |
|---|---|---|
| `leakage_1iter_n24` | `leakage_1iter_n48` | 1.694 within-run -> **1.046** |
| `kalman_step_p40` | `kalman_step_p200` | 3.9 within-run -> **1.035** |
| `synthesis_direct_n60` | `synthesis_direct_n180`, 0.5 deg | 1.689 -> **1.022** |
| `synthesis_fft_n60` | `synthesis_fft_n180`, 0.5 deg | 1.709 -> **1.007** |

Their old baselines are deleted, not carried over: a baseline measured on
a workload that no longer runs is a budget that passes vacuously. The new
ones were baselined on MATTHIASPC first and filtered on A8 until it had
measured them twice (below).

### A sizing mistake, caught by the check it was sized for

The first grid-synthesis replacement was nmax 120 at 1 degree, chosen from
a sweep that called `shSynthesis` cold: 19 ms, steady. The budget arm
primes the Legendre cache and times only the reduction, which at that
size is **4 ms** - and between runs it measured **1.82**, worse than the
workload it replaced. The proxy timed a different code path from the one
the budget measures. Re-sized on the arm's own path: nmax 180 / 0.5 deg.

### `apply_ddk_n300` joins the tight tier

v5.3.0 held it back on one A8 observation. Six A8 runs later its worst
run-to-run ratio is 1.072 there and 1.059 on MATTHIASPC - the criterion,
met on the evidence the criterion asks for. Its A8 baseline is now the
median of those six runs.

### `TightFactor` 1.5 -> 1.3

The worst deviation any run has shown from its tight-tier baseline is
**1.057**, so 1.3 leaves 1.23x of headroom - and 1.3 is the number A9
asks for. For `legendreALF`, `shAnalysisGrid` and `applyDDK`, a 1.3x
regression now fails CI. That margin exists only because every baseline
is a median over runs.

### `leakageCorrect` built its final residual twice

`info.residualRMS` and `info.residualRMSGlobal` each re-ran the full
analysis -> filter -> synthesis chain on the same field: 3.07
chain-equivalents per one-iteration call where 2 suffice. Now built once.
**Bitwise identical** on all 16 outputs checked (four configurations at
nmax 24 and 48, including `ResidualRegion` differing from `Mask`, where
the two residuals genuinely differ). At nmax 48 one iteration went from
69 to 47 ms, as the 3 -> 2 chain count predicts.

### A9 is closed

Two A8 runs of one commit (`2c7b779`: the PR run and a `workflow_dispatch`)
measured the four new workloads:

| workload | A8 run 1 | A8 run 2 | spread |
|---|---|---|---|
| `leakage_1iter_n48` | 81.19 ms | 80.66 ms | 1.007 |
| `kalman_step_p200` | 29.55 ms | 29.80 ms | 1.009 |
| `synthesis_direct_n180` | 38.61 ms | 37.83 ms | 1.021 |
| `synthesis_fft_n180` | 39.64 ms | 39.55 ms | 1.002 |

All four join the tight tier at 1.3, with their A8 baselines as the median
of those runs. Every lane A9 names - `legendreALF`, `shSynthesis`,
`shAnalysisGrid`, `applyDDK`, `leakageCorrect`, the Kalman step - now has a
budget that fails CI on a 1.3x regression. That is the finding's own
wording, and it closes there.

Both runs: **335 runs, 327 passed, 0 failed, 8 filtered** - the four
real-data fixtures and the four workloads A8 had no baseline for yet,
exactly as predicted.

### The criterion needed stating precisely, and why is on record

It read "worst run-to-run ratio <= 1.1 on both machines". A max/min ratio
counts FAST runs too - and on 2026-09-10 a full-suite run on a quiet
desktop came in 0.84x below baselines taken while it was busy. Under that
wording `analysis_rings_n60`, the steadiest budget on A8 (1.007), would
have been demoted for the machine being idle. A fast run cannot fail an
upper bound. The criterion is now: A8 spread <= 1.1 over at least two
runs, and no run on either machine more than 1.1 above its baseline.

That is not free, and the code says so: a baseline taken under load masks
part of a regression on that machine. The 1.3x guarantee holds on A8, the
CI gate; on a workstation the budgets err loose.

### Noticed, deliberately not acted on

At n180 / 0.5 deg the FFT synthesis path is **slower** than direct (31.4
against 29.9 ms), while at n60 on A8 it was 1.40x faster. `auto` may pick
the slower path on large grids, as `synthesisPoints` did before v5.3.0.
One machine, one size: recorded as a candidate to measure, not changed.

### Record

WP5 row 5c was never ticked when v5.2.0 shipped it; corrected.
## [5.4.0] - 2026-09-09 - WP5 5b: leakage correction without a model

`shLowLevel.leakageDataDriven` repairs the catchment average of a filtered
time series using correction terms built from the filtered fields alone.
It is the model-independent counterpart of `leakageCorrect`'s forward
model - Vishwakarma's "method of deviation".

### The row was blocked on equations, and the block was real

WP5 5b sat stopped because the method could not be implemented from a
half-remembered description, and the paper was unreachable. Matthias
supplied the author's PhD thesis, which carries the full derivation
(chapter 3, eqs. 3.19-3.29). That was the whole blocker.

It was a real one. Two details decide whether the method works and
neither is guessable:

- the deviation integral is weighted by the **filtered** catchment
  function, not the mask (eq. 3.19);
- the leakage extrapolation corrects a **phase** difference, not just an
  amplitude - and the deviation integral deliberately gets **no** phase
  correction, because the thesis measured those phase differences and
  found no consistent relation. That asymmetry looks like an omission
  and is a finding.

### Why the correction is exact algebra, not a fit

For a filter that leaves a constant alone (`W(0) = 1`), the filtered
catchment average splits with no approximation:

```
gbar_c = f_c + dF_c + l_c
```

true average, deviation integral (what the filter does to the catchment's
own signal, because it is not a uniform layer), and leakage in from
outside. So `f_c = gbar_c - dF_c - l_c` is a rearrangement. The hard part
is that both corrections need the unfiltered field, which nobody has - so
they are estimated from the once- and twice-filtered fields and
extrapolated one filtering step back.

### Measured, not asserted

`tools/dev/validate_leakage_datadriven.py` checks four claims:

| claim | result |
|---|---|
| the decomposition closes | 4.3e-15 relative |
| the two forms of the deviation integral agree (filter self-adjointness) | 5.0e-16 |
| measuring a phase and applying it are mutual inverses | 7.1e-15 deg |
| a closed loop moves towards the truth | **63%** of the RMS damage removed |

MATLAB removes **55.3%** on the `testCorrectness` fixture; the two differ
because the grids and the basin geometry differ (Gauss-Legendre against
equiangular), not because the method does. Both numbers were measured on
the configuration they are quoted for - an earlier draft of this entry
carried 57%, which was a third configuration's figure.

The phase claim earned its place immediately: it caught a sign error that
left every other claim passing while the correction was applied backwards.
A closed-loop percentage alone would not have found it.

### Deviations from the WP sketch, stated rather than smuggled

- The option is `Filter=` (`"gauss<km>"` | `"DDKn"` | `"none"` | a W
  struct), not `Radius=`, so it matches `leakageCorrect` and accepts the
  filters the data actually saw.
- The input is a grid stack, not an `shSeries`: `shLowLevel` works on
  arrays, and a class method belongs to WP7.
- The `info` layout is NOT `leakageCorrect`'s, because the two return
  different things - a corrected field against a corrected series. It
  carries the method's own pieces instead, each documented.
- The function needs **at least 12 epochs** and refuses NaN. Both steps
  are regressions over the whole series: they cannot skip a gap, and
  below one annual cycle the phase is unidentifiable. Returning a
  confident angle from four months would be worse than refusing.

`hilbert()` is Signal Processing Toolbox, so the analytic signal is built
by FFT here - the base-MATLAB rule again.

### Licence

The authors publish a MATLAB `DataDrivenCorrection` bundle under GPL-3.
shAnalysis is MIT, so nothing here derives from that code: the
implementation is written from the thesis equations, which is what
CLAUDE.md section 2 requires anyway ("reuse is by re-implementation").
Citations are in the function's References block.
## [5.3.0] - 2026-09-09 - MATLAB has no crossover, and the budget factor is finally a measurement

First Tier-A session since the local bridge was lost: MATLAB R2026a runs on
the acceptance machine again, so the two WP2 items that needed a machine
rather than a sandbox are both closed by measurement.

### `synthesisPoints` sent every short station list down the slower path

`ClenshawFrom` defaulted to **150** - the crossover of the numpy prototype,
carried into MATLAB where it does not hold. The new `benchPointsCrossover`
times both summations on the SAME points, and there is no crossover to find:

| nmax | P = 1 | 10 | 50 | 100 | 150 | 200 | 500 | 2000 |
|---|---|---|---|---|---|---|---|---|
| 60  | 5.0x | 2.3x | 3.2x | 3.6x | 3.6x | 3.3x | 4.0x | 4.9x |
| 120 | 19.8x | 3.2x | 4.2x | 5.5x | 6.2x | 6.5x | 5.0x | 6.4x |
| 360 | 37.2x | 2.9x | 3.9x | 4.2x | 4.4x | 4.7x | - | - |

(MATTHIASPC, R2026a; `direct` median over `clenshaw` median, so every entry
above 1.0 means `clenshaw` won.) It wins at **every** count measured, by
2.3x at the narrowest margin. The reason is structural rather than
incidental: `direct` is bounded by `legendreALF`, and `clenshaw` never calls
it - which is also why the margin grows with degree.

So **`ClenshawFrom` now defaults to 1** and `auto` is `clenshaw` everywhere.
A 100-station network was getting 3.6x less than the toolbox could give it.
The option stays, because `direct` is still the bitwise path and a caller
may want it; raising `ClenshawFrom` restores the old routing exactly.

**What changes for a caller**: `auto` below 150 points now returns clenshaw's
numbers instead of direct's. They agree to the documented 5e-14 and neither
is more accurate (both land within a few tens of eps of a 60-digit
reference, `direct` 52.7 eps worst against `clenshaw` 89.0, with clenshaw
closer at three of six points). `Method="direct"` is unchanged and still
bitwise with v3.0.0..v5.1.1.

`testSynthesisPointsAutoPicksTheFasterPath` needed no edit - it pins the
dispatch RULE while driving `ClenshawFrom` by hand, which is exactly what
that design was for. `testSynthesisPointsAutoIsClenshawByDefault` pins the
shipped number alongside it.

### A9: one factor could not do it, so there are now two

Fifteen runs of untouched code - twelve on MATTHIASPC, three on A8 - give
the BETWEEN-run spread that one run cannot. Worst run-to-run ratio per
workload, sorted by how steady it is:

| workload | size | worst run/run |
|---|---|---|
| `legendre_n720` | 171 ms | 1.011 |
| `legendre_n360` | 57 ms | 1.036 |
| `apply_ddk_n300` | 15 ms | 1.059 |
| `analysis_rings_n60` | 40 ms | 1.079 |
| `kalman_step_p40` | 1.2 ms | 1.267 |
| `leakage_1iter_n24` | **23 ms** | **1.306** |
| `legendre_n96` | 8 ms | 1.532 |
| the six point-synthesis budgets | 0.8-11 ms | 1.540 .. 1.685 |
| `synthesis_fft_n60` | 2.1 ms | 1.709 |

Two things follow, pointing opposite ways.

**A9's own 1.3 is refuted, and not by a timer artefact.**
`leakage_1iter_n24` measured 23.1, 23.1 and **30.2 ms** across three A8
runs of code nobody touched. That is 1.306 on a 23 ms workload - it cannot
be engineered away by enlarging anything, and a 1.3x budget would have gone
red on it. A gate that cries wolf is worse than no gate.

**But the four workloads at 15 ms and up never moved past 1.079**, over
fifteen runs on two machines, one of them busy. Holding those at 3x because
ten small benchmarks are noisy lets the worst member set every budget in
the set.

So the factor is now **per benchmark against a stated criterion** - worst
observed ratio <= 1.1 earns `TightFactor = 1.5`, everything else keeps
`BudgetFactor = 3`. Three qualify: `legendre_n360`, `legendre_n720` and
`analysis_rings_n60` - two of the six lanes A9 names (`legendreALF`,
`shAnalysisGrid`).

`apply_ddk_n300` is the obvious fourth and is deliberately held back. It
was in the tight list on MATTHIASPC evidence alone, and A8's first
measurement of it (23.0 ms) argued it out: that is the same size as
`leakage_1iter_n24`, which swings 1.306 on A8, and one run gives no spread
at all. Promote it when A8 has measured it twice. Applying the criterion
only to the data that happens to exist is how a criterion becomes a
rationalisation.

**A9 stays open**, and what it waits for is now specific rather than "more
runs": `leakageCorrect` and the Kalman step are still at 3x, and closing A9
means making *them* steady enough to budget. The small ones cannot simply
be enlarged - the n50/n60 pairs are crossover BRACKETS, and a bracket
measured at a different point count measures nothing.

`apply_ddk_n96` -> **`apply_ddk_n300`**. At 1.8 ms it measured the timer,
not `applyDDK`, and swung 1.519x on A8; at nmax 300 it measures 15 ms and
is now steady enough to be one of the four tight budgets. Its A8 baseline
is deleted rather than carried over: a baseline measured on a workload that
no longer runs is a budget that passes vacuously.

Every baseline is now a **median over runs** rather than a single
`PERFBASE` line (A8 45 samples = 3 runs x 15, MATTHIASPC 60 = 4 x 15). A
single run can land at either end of the spread above, and a baseline that
landed at the fast end would silently turn a 1.5x budget into a 1.1x one.

### The acceptance machine has baselines - WP2's "both machines" at last

WP2's acceptance asks for budgets calibrated on the acceptance machine AND
A8. The bridge has been gone since 2026-09-08 and it is back, so all
fourteen budgets now have a `MATTHIASPC` row - the missing half of that
acceptance, and the first thing this session did that no sandbox could.

`NO_BASELINE` is empty. Two of the entries it held were not actually
unmeasured: A8 timed the `n50` crossover pair at `b65f9a2` and the numbers
sat unread in the job log, which is its own small lesson - a measurement
that nobody reads back is not a measurement. The gate now also says what an
empty backlog does NOT mean: `apply_ddk_n300` is baselined here only, so on
A8 it still filters until that runner measures it.

The `n50` pair also settles the crossover from below on the SECOND machine.
In one A8 run (`b65f9a2`): direct 3.80 ms against clenshaw 1.07 ms at 50
points (3.56x), and 14.94 against 2.14 ms at 200 (6.99x). The run before it
put the 200-point pair at 4.61x - these are 1-15 ms budgets and their
between-run spread is exactly what the A9 section is about, so read the
direction as reproducible and the factor as not. Both machines, and every
run, agree on the direction.

### A23 (new): one machine, two labels, silently unguarded budgets

`machineId()` read `COMPUTERNAME` (`MATTHIASPC`) before falling back to
`hostname` (`MatthiasPC`), so which label a baseline row had to carry
depended on how MATLAB happened to be launched. A row that misses does not
fail its budget - it **filters** it, so the machine would have looked green
while guarding nothing. The label is now upper-cased (upper, so the
committed `A8` rows are untouched) and `perf_baseline_audit.py` rejects any
row that is not, fault-injected both ways.

### A24 (new): mlint_lite could not see a parse error

An edit put a real newline inside an `fprintf` format. `mlint_lite` reported
zero findings; MATLAB refused to parse the whole `testPerformance` class, so
every test in it would have vanished rather than failed. On CI that is a
round-trip a Tier-B session cannot predict. **R7** reports a literal that
runs off its line - read off the scanner that already had to know, not from
a second parser - and is silent on the two legal shapes that look like it
(a transpose after a value, a literal split with `...`). Zero findings
across all 149 `.m` files in the tree.
## [5.2.0] - 2026-09-09 - WP5 5c: the GIA model stops being exact

`shSeries.removeGIA` gains `Sigma=` and a second output `info`. Until now
its own help said the model "is treated as exact (its uncertainty, often
the dominant trend error over Laurentia/Fennoscandia/Antarctica, is NOT
propagated - documented limitation)". That limitation is closed.

`Sigma` is an `shCoefficients` of per-coefficient 1-sigma RATE
uncertainties [1/yr] - an ensemble spread such as Caron et al. 2018. When
it is not given, the model's own `sigmaC`/`sigmaS` are used if it carries
them, so a GIA file read with sigmas propagates without being asked.
**The default call is unchanged**: no sigma anywhere means bitwise the
same coefficients and no sigma stack invented.

### What is added, and what it deliberately is not

Per epoch the model contributes `sigmaRate * (t_k - T0)` in quadrature,
so `sigmaCs`/`sigmaSs` are correct MARGINAL per-epoch sigmas and feed
`shLowLevel.mcPropagate` (through `ts.at(k)`) and every other consumer of
the stacks with no new plumbing.

**They are not enough for a trend, and the help says so.** One rate error
applies to every epoch, so the GIA component is perfectly CORRELATED in
time. A trend fitted from per-epoch sigmas that assumes independence
understates it. `info.rateSigmaC/rateSigmaS` return the rate sigma itself
precisely so a trend consumer can add it directly.

### The oracle failed first, and it was the experiment that was wrong

`tools/dev/validate_gia_sigma.py` checks both claims against a
20000-sample Monte Carlo. The first version tested the correlation claim
on an ensemble where the per-epoch noise (2e-11) swamped the GIA rate
error (4e-12), and it duly reported that the independence assumption was
no worse - because in that regime the GIA component is invisible. The
claim is about the GIA COMPONENT, so the experiment has to isolate it.
On a GIA-only ensemble:

```
MC (truth, one rate error reused) : 4.029e-12
sigmaRate itself                  : 4.000e-12
assuming INDEPENDENCE             : 1.155e-12
understatement                    : 3.49x   (sqrt(T) = 3.46)
```

So "roughly sqrt(nEpochs)" in the help is measured, not asserted. A
badly-posed experiment that fails loudly is worth more than a
well-posed one that was never run.

### The second `info` output exposed a gate defect

`help_audit` appended EVERY local function of a classdef to EVERY
method's source, deliberately, so that `shSeries.mean` could see the
`info` struct built in `meanWindowInfo`. That was harmless while exactly
one method had an `info` output. `removeGIA` is the second, and it
immediately inherited all ten of `meanWindowInfo`'s fields as false
findings.

Same shape as A12's "a class method's source is not the whole class
file", one level out. A method now gets the local functions it actually
REACHES, transitively - the reachability rule A21a already uses for
identifiers. Pinned in both directions: a sibling that never calls the
local does not inherit its fields, the caller still does (so the fix did
not simply narrow the gate), and a local calling a local is followed.

### Also

A series carrying NO sigmas gets stacks holding the GIA term ALONE, and
`history` plus `info.sigmaWasEmpty` say so, so they cannot be mistaken
for full formal errors. `Sigma` must match the model in size -
`shSeries:removeGIA:badSigma` - because a silently zero-padded sigma
field would attach the wrong uncertainty to the wrong degree.

### Carried along: the WP2 crossover, measured and pointing the other way

v5.1.1's matched pair ran on A8, and it corrects a guess of mine. At the
SAME 200 points:

```
direct   0.0155142 s
clenshaw 0.0034370 s     clenshaw is 4.5x FASTER
```

I had speculated MATLAB's crossover was HIGHER than numpy's, reasoning
from direct@200 against clenshaw@2000 - different point counts, which is
precisely the mistake the matched pair was built to prevent. It is
LOWER: clenshaw already wins comfortably at 200, so the crossover sits
under 200 and `ClenshawFrom = 150` is too high, not too low.

`ClenshawFrom` stays at 150 regardless, because 44 is an EXTRAPOLATION
from two points at one size, and this release will not set a default
from a number it did not measure. A second matched pair at 50 points
brackets it from below; the next A8 run resolves it. Note the current
default is conservative, not wrong: for 44 <= P < 150 `auto` returns the
same answers by the slower path.

Test count: 312 methods / **326 runs** (+4 tests, +2 budgets).

## [5.1.1] - 2026-09-09 - the A8 numbers, and a budget pair that can actually bracket the crossover

v5.1.0 is green on A8: **319 runs, 313 passed, 0 failed, 6 filtered**, the
ninth exact count prediction running. The two point budgets it left
unbaselined are measured and committed:

| budget | A8 median | against |
|---|---|---|
| `synthesis_points_n60` (clenshaw, 2000 pts) | **0.0220564 s** | the retired per-point path's 2.2829 s - **103x** |
| `synthesis_points_n60_direct` (direct, 200 pts) | 0.0156066 s | - |

### The budgets as shipped could not do what their help claimed

`ClenshawFrom`'s help says `perf_baseline.csv` "budgets both paths so the
real crossover can replace it". It did not. v5.1.0 budgeted clenshaw at
2000 points and direct at 200 - two different workloads, so neither
measures the other and no crossover can be read off them. A crossover
needs both paths at the SAME point count.

`synthesis_points_n60_clenshaw` fixes it: the same arm, the same `rng`,
the same 200 points as `synthesis_points_n60_direct`, differing only in
`Method`. The pair brackets the crossover; the 2000-point case keeps
guarding the large-scattered regime.

**So `ClenshawFrom = 150` is still the numpy number.** It cannot be
replaced until that pair has run. What the A8 figures already hint at is
that MATLAB's crossover is HIGHER than numpy's - direct at 200 points
(0.0156 s) is faster than clenshaw at 2000 (0.0221 s), and clenshaw is
not flat enough in P for that to be dismissed - but hinting is not
measuring, and the number stays until the matched pair says otherwise.

### The gate found a false finding in itself

Adding the matched pair used `case {'a', 'b'}` - one MATLAB arm serving
two labels. `perf_baseline_audit`'s ARMS rule read only `case 'x'`, so it
reported both budgets as having no arm: a FALSE finding about correct
code, and precisely A2's shape (`nv_casing_audit` was blind to
`inputParser` and so reported nothing about six functions). The rule now
parses cell-array labels, with two self-tests - one that the multi-label
form is accepted, one that an undeclared label inside a cell list still
fires, so the fix cannot have made the rule permissive. 26 self-tests.

### Corrected

`CLAUDE.md` gave clenshaw's speedup as 68-310x. That was the range over
the two configurations quoted; the third (nmax 120, 2000 points, which
finished after the release) is **356x**, and direct there is 59.2x,
bitwise. The range is now 68-356x and names all three configurations.

Test count: 308 methods / **320 runs**.

## [5.1.0] - 2026-09-09 - two summations for synthesisPoints, faster one by default

WP2 step 2, row B2. `shLowLevel.synthesisPoints` gains `Method`,
`ClenshawFrom` and `MaxMemGB`. Nothing existing changes its answer: the
default path at the point counts the old tests use is BITWISE identical.

### What was wrong

`synthesisPoints` aggregated per point, and per point it built the FULL
`(nmax+1)x(nmax+1)` Legendre matrix - calling `legendreALF` with a SCALAR
latitude, though it accepts a vector - then formed three more full
matrices before reducing. Four allocations and four passes over `nmax^2`
per point. v5.0.3 measured the cost: 2.28 s for 2000 points at nmax 60,
1.14 ms per point, 36.65 s of a 4:51 CI job.

### Two paths, and the faster one is the default

| `Method` | what it does | cost in the point count |
|---|---|---|
| `"direct"` | builds `Pbar`, contracts per point; the recursion now runs once per CHUNK of points instead of once per point | linear |
| `"clenshaw"` | reorders the sum by ORDER and evaluates each order's degree sum by Clenshaw summation; `Pbar` is never formed | nearly flat |
| `"auto"` (default) | `"clenshaw"` at or above `ClenshawFrom` points, `"direct"` below | - |

Measured in the committed oracle `tools/dev/validate_points_clenshaw.py`
(numpy, same recursion coefficients as `legendreALF.m`), against the
per-point code it replaces:

```
nmax=60  P=2000    direct  52x faster    clenshaw 310x faster
nmax=60  P=200     direct  61x           clenshaw  68x
```

and the crossover between the two shipped paths:

```
             P:    10     50    100    200    400
nmax=60      direct wins  ---------|  clenshaw wins
nmax=120     direct wins  ---------|  clenshaw wins
```

The crossover sits between 100 and 200 points at BOTH degrees - it barely
moves with `nmax`, which is what makes one scalar `ClenshawFrom` (150)
defensible instead of a rule in `nmax`. **That number is measured in
numpy, not on MATLAB**, and the help says so; `tests/perf_baseline.csv`
now budgets both paths so A8 can replace it.

### `"direct"` is bitwise, `"clenshaw"` cannot be

Batching only moves the `legendreALF` call out of the loop, and the
recursion is elementwise in latitude, so the chunk size cannot change a
bit - pinned by `testSynthesisPointsChunkingIsBitwise`, which drives
`MaxMemGB` to one point per chunk and to all points at once and compares
with `isequal`. That is why the pinned reference values in
`testSynthesisPoints` still hold unchanged.

Clenshaw sums the same terms in a different order, so **bitwise agreement
is arithmetically impossible** and no test asserts it. WP2's "bitwise, or
<= 4 eps" acceptance does not apply to it, and pretending otherwise would
have meant writing an assertion that cannot hold. What is asserted
instead: agreement with `"direct"` to 5e-14 relative (about 2x the worst
case the oracle measures), and - in the oracle - that neither path
dominates the other against a 60-digit `mpmath` reference:

```
lat      direct   clenshaw
 89.5   12.9 eps   89.0 eps
 12.3   52.7 eps   59.5 eps
 62.0    4.4 eps    0.5 eps
```

Both sit within tens of eps, which is what a sum of `nmax^2/2` terms with
cancellation costs. Clenshaw is better at three of six points and worse
at the near-pole one.

### Budgets

`synthesis_points_n60` now forces `"clenshaw"` at 2000 points, and its old
2.2829 s baseline is RETIRED rather than kept: it measured the path that
no longer runs, so it would have passed vacuously. A new
`synthesis_points_n60_direct` budgets `"direct"` at 200 points - a
GNSS-network-sized station list, the regime `"auto"` routes to `"direct"`.
Both sit in `NO_BASELINE` until A8 measures them.

### Not changed, and why

The GRID default was already the faster one: `shSynthesis`'s `"auto"`
picks the FFT path for any uniform full-circle longitude vector, and
v5.0.3 measured that at 1.40x the direct path. Nothing to do.
`shSynthesisDeformation` does NOT share the pathology - it calls
`legendreALFDeriv` once with the whole latitude vector already.

Test count: 308 methods / **319 runs** (305/315 + 3 tests + 1 budget).

## [5.0.3] - 2026-09-09 - WP2 step 1: the budgets go live

v5.0.2 built the harness and measured nothing; A8 has now measured it.
The ten `PERFBASE` lines from the `runAllTests (self-hosted)` run at
`f6d5529` are committed as `tests/perf_baseline.csv` rows and
`NO_BASELINE` is **empty**, so every budget asserts instead of filtering.

| benchmark | median (s) | min (s) |
|---|---|---|
| `synthesis_points_n60` | 2.2829 | 2.26137 |
| `legendre_n720` | 0.284863 | 0.281566 |
| `legendre_n360` | 0.0883628 | 0.0873293 |
| `analysis_rings_n60` | 0.069954 | 0.0687578 |
| `leakage_1iter_n24` | 0.0231963 | 0.0222312 |
| `legendre_n96` | 0.012063 | 0.01194 |
| `synthesis_direct_n60` | 0.0042843 | 0.0039347 |
| `synthesis_fft_n60` | 0.0030666 | 0.0029098 |
| `apply_ddk_n96` | 0.0018487 | 0.0016592 |
| `kalman_step_p40` | 0.0016711 | 0.0016445 |

A8, R2026a, 15 repeats each, median of the samples.

### A9 is only PARTLY closed, and the factor is why

The budgets now guard something, which they did not yesterday. But 3x
catches a workload that blows up - a lost fast path, an accidental
O(n^2) - and it does **not** catch the 1.3x creep A9 actually names. The
finding is downgraded, not closed, and the comment on `BudgetFactor`
says so in the file rather than only here.

Tightening it needs a statistic this release cannot supply. The run
measured the WITHIN-run spread: median/min <= 1.043 over 15 repeats for
every workload above 20 ms, 1.114 for `apply_ddk_n96` at 1.8 ms where
the timer dominates. A budget needs the BETWEEN-run spread, and one run
cannot measure it. Several runs of logged medians can, and then the
factor is a decision with evidence behind it.

### Two things the first measurement contradicted

**`synthesisPoints` is the hot spot, by a wide margin.** 2.28 s against
1.7-88 ms for everything else, and 36.65 s of the job's 4:51 - because
it calls `legendreALF` once PER POINT (1.14 ms per point at n60). That
is B2's premise, now measured rather than inferred, and it is the
strongest candidate for WP2 step 2.

**The FFT path is 1.40x, not "5-20x".** `benchSynthesisFFTvsDirect`
carried the claim "typical gain: 5-20x at nmax=60, 1 deg" - exactly the
configuration measured here, which came out 4.28 ms direct against
3.07 ms fft with the cache primed identically. The old figure was never
measured against the direct path in the same cache state, which is the
only comparison that isolates the FFT. The comment now carries the
measured number and its provenance.

### Verification

`runAllTests (self-hosted)` at `f6d5529`: **315 runs, 301 passed, 0
failed, 14 filtered** - the count prediction matched EXACTLY for the
seventh release running, per class as well as in total (Contract 74,
Correctness 159, Performance 22, Robustness 53, Science 7). Counts
parsed from the 315-row results table, not a log tail. The 14 filtered
were the 4 real-data fixtures plus the 10 budgets, which is what this
release removes: the next run should filter 4.

## [5.0.2] - 2026-09-09 - WP2 step 1: speed becomes measurable

A9 recorded that the toolbox has no speed budget, so a 1.3x regression in
`legendreALF`, `shSynthesis`, `shAnalysisGrid`, `applyDDK`,
`leakageCorrect` or the Kalman step ships unnoticed. WP2 says: make speed
measurable first, and build only what the measurement justifies. This is
the measuring half. **No numerical behaviour changes and no public call
changes** - the release is a PATCH.

### Ten budgets, one harness

`testPerformance` gains `testSpeedBudget`, a parameterised method with one
run per workload:

| benchmark | what it bounds |
|---|---|
| `legendre_n96` / `_n360` / `_n720` | the Holmes-Featherstone recursion at 181 / 91 / 31 rings |
| `synthesis_direct_n60` | the reduction only - the Legendre cache is primed first |
| `synthesis_fft_n60` | the FFT-along-longitude path |
| `synthesis_points_n60` | 2000 scattered points |
| `analysis_rings_n60` | exact per-order ring analysis |
| `apply_ddk_n96` | order-block filter application |
| `leakage_1iter_n24` | one `leakageCorrect` step |
| `kalman_step_p40` | a 12-epoch VAR(1) filter chain |

Each is timed 15 times after one untimed warm-up, and the MEDIAN is
compared against `BudgetFactor` (3) times the baseline for this machine
in the new, committed `tests/perf_baseline.csv`.

### A budget cannot be asserted before it has been measured

So it is not. A machine with no baseline row FILTERS the budget rather
than failing it, and prints a `PERFBASE,...` line that is already a
`perf_baseline.csv` row. That is how a machine is adopted: run once, paste
the lines, and the budgets go live on the next run. All ten sit in the
gate's `NO_BASELINE` backlog today, which is honest debt - a filtered
budget guards nothing.

Baselines are per machine rather than ratios against a calibration
workload. A ratio is machine-independent only when the calibration scales
like the workload, and no one calibration tracks both a BLAS-bound
reduction and a memory-bound recursion.

The factor 3 is WP2's specification, not a measured spread - there was no
baseline to measure a spread against, which is precisely what A9 records.
Every run logs the median AND the min, so the choice can be replaced with
the observed spread rather than inherited.

### The bookkeeping is gated

`tools/dev/perf_baseline_audit.py` (new, in `ci.yml`) checks that the CSV,
the `budgetCase` parameter and the `workload()` switch agree: row shape and
uniqueness, no orphan baselines, field names equal their values, **every
declared case has a case arm**, and the backlog holds neither a stale entry
nor a case that already has a baseline. The arm rule is the one that earns
its place - a case without an arm passes every other static check here and
then fails on the runner with `unknownCase`. 24 self-tests, every rule
fault-injected in both directions; the backlog rule is asserted with a
TEMPORARY entry, per A14.

### Fixed: `count_tests.py` counted a char-valued parameter twice

Adding `budgetCase` made the counter say 19 where the runner runs 10. Its
rule was "count every quoted word followed by a comma", which is right only
while the parameter's VALUES are not themselves quoted. It now counts
struct FIELDS through `help_audit.struct_field_names` - the one authority
in this repository for that question - instead of a second, weaker parser
of the same fact. That is A17's lesson: the failure would otherwise have
surfaced as a red `--executed` check on the runner, a full CI round later.

### Files

- `tests/testPerformance.m` - `testSpeedBudget`, `workload`, the two
  fixtures, `machineId`, `baselineFor`, `appendPerfLog`
- `tests/perf_baseline.csv` - new, committed (the machine-local
  `perf_log.csv` stays git-ignored)
- `tools/dev/perf_baseline_audit.py`,
  `tools/tests/test_perf_baseline_audit.py` - new
- `tools/dev/count_tests.py`, `tools/tests/test_count_tests.py` - the
  cardinality fix and its regression tests
- `.github/workflows/ci.yml` - the new gate step

Test count: 305 methods / **315 runs** (305 + `testSpeedBudget` x 10).

## [5.0.1] - 2026-09-09 - WP6 stage 3: 24 duplicate pages retired

The hand-written page per package function existed because
`doc_sync_audit`'s COVERAGE check demanded a NARRATIVE mention of every
entity, and before WP6 there was nowhere else to put one. There is now:
`html/ref/` carries a generated page per entity. 24 of the 50
hand-written pages were restating theirs.

### Chosen by measurement, not by file name

A17 left a warning: a narrative page can be the only mention of an
entity, so deleting by name drops entities out of COVERAGE silently. So
the set was computed - retire a page only if every entity stays covered
afterwards. That is true of **30**; the other 6 are the last narrative
mention of 11 entities (`fetchITSG.html` for `listITSG`,
`shCoefficients.html` for six of its own methods, ...) and stay.

Of the 30, six read as narrative rather than reference and were kept by
the WP's own rule ("keep narrative pages (chains, theory)"):
`standardChain` is a chain, `shSeries` a class overview, and
`legendreALF`, `seaLevelFingerprint`, `eofAnalysis` and `slepianBasis`
carry theory. **24 were retired.**

COVERAGE therefore keeps its current meaning untouched - the question of
what it should become does not arise, because nothing it guarantees was
given up.

### Retired, not deleted

Every inbound link and every `helptoc.xml` target was REPOINTED at
`html/ref/<entity>.html` before the files were removed, so nothing a
reader could reach became unreachable. Four category headers pointed at
a page in their own group that is now gone
(`Reading and writing` -> `readSINEX`, `Filtering` -> `tvANS`,
`Spectra and diagnostics` -> `comparison`,
`Regional and geophysical analysis` -> `leakage`).

Two link rewrites nearly escaped: the See-also lines of `shSynthesis` and
`legendreALF` use `href='...'` with single quotes, and the first pass
only matched double ones. Checking both quotings found them.

`removeGIA.html` was the one page whose short name matched two entities
(`shSeries.removeGIA` and `shClimatology.removeGIA`) - a `setdefault`
picked one by accident. Reading the page settled it: it documents both
routes with `ts.removeGIA(gia)` first, so it points at
`ref/shSeries_removeGIA.html` by decision now rather than by luck.

50 hand-written pages -> 26. No entity lost coverage; the test count is
unchanged.

## [5.0.0] - 2026-09-09 - Every class identifier names its method (A21b)

**BREAKING.** The 29 two-part identifiers the three classes raised are
now three-part. A caller could not tell which of the 35 methods raised
`shSeries:badInput`; now they can.

### BREAKING - what changes for a caller

Any `catch`, `verifyError` or `warning('off', ...)` naming one of these
must be updated. **One old identifier maps to several new ones** - that
is the point of the change, and it is why a repo-wide replace would have
been wrong (the A15 lesson, applied per raise site rather than per file):

| was | now |
|---|---|
| `shClimatology:badIndex` | `shClimatology:periodic:badIndex` |
| `shClimatology:badInput` | `shClimatology:amplitudeMap:badInput`<br>`shClimatology:fromCoef:badInput` |
| `shCoefficients:badIndex` | `shCoefficients:addDegree1:badIndex`<br>`shCoefficients:setCoefficient:badIndex`<br>`shCoefficients:vec:badIndex` |
| `shCoefficients:badInput` | `shCoefficients:mtimes:badInput`<br>`shCoefficients:operands:badInput`<br>`shCoefficients:shCoefficients:badInput`<br>`shCoefficients:times:badInput` |
| `shCoefficients:badTruncation` | `shCoefficients:truncate:badTruncation` |
| `shCoefficients:constantsMismatch` | `shCoefficients:operands:constantsMismatch` |
| `shCoefficients:epochMismatch` | `shCoefficients:operands:epochMismatch` |
| `shCoefficients:epochNotInTable` | `shCoefficients:addDegree1:epochNotInTable`<br>`shCoefficients:applyTN14:epochNotInTable` |
| `shCoefficients:noC30` | `shCoefficients:applyTN14:noC30` |
| `shCoefficients:noEpoch` | `shCoefficients:addDegree1:noEpoch`<br>`shCoefficients:applyTN14:noEpoch` |
| `shCoefficients:noSigmas` | `shCoefficients:crossover:noSigmas` |
| `shCoefficients:sizeMismatch` | `shCoefficients:operands:sizeMismatch` |
| `shSeries:ambiguousRange` | `shSeries:select:ambiguousRange` |
| `shSeries:badBasis` | `shSeries:basinAverage:badBasis` |
| `shSeries:badIndex` | `shSeries:at:badIndex` |
| `shSeries:badInput` | `shSeries:minus:badInput`<br>`shSeries:select:badInput`<br>`shSeries:shSeries:badInput` |
| `shSeries:badRange` | `shSeries:range:badRange` |
| `shSeries:badTruncation` | `shSeries:truncate:badTruncation` |
| `shSeries:constantsMismatch` | `shSeries:shSeries:constantsMismatch` |
| `shSeries:emptyRange` | `shSeries:mean:emptyRange` |
| `shSeries:epochMismatch` | `shSeries:minus:epochMismatch`<br>`shSeries:restore:epochMismatch` |
| `shSeries:missingOp` | `shSeries:basinAverage:missingOp` |
| `shSeries:nanInSeries` | `shSeries:stack:nanInSeries` |
| `shSeries:noBreaks` | `shSeries:trendBreaks:noBreaks` |
| `shSeries:noEpoch` | `shSeries:climatology:noEpoch`<br>`shSeries:filter:noEpoch`<br>`shSeries:mean:noEpoch` |
| `shSeries:noFiles` | `shSeries:fromFolder:noFiles`<br>`shSeries:read:noFiles` |
| `shSeries:sizeMismatch` | `shSeries:minus:sizeMismatch`<br>`shSeries:restore:sizeMismatch`<br>`shSeries:shSeries:sizeMismatch` |
| `shSeries:sparseWindow` | `shSeries:mean:sparseWindow` |
| `shSeries:tooFewEpochs` | `shSeries:climatology:tooFewEpochs`<br>`shSeries:mean:tooFewEpochs` |

Three identifiers were already three-part and are unchanged:
`shSeries:removeAlias:tooShort`, `shSeries:toGrid:empty`,
`shSeries:toGrid:tooLarge`.

### The middle segment: a method, or a named shared check

Normally it is the raising **public method**, the constructor included
(`shCoefficients:shCoefficients:badInput`) so the rule has no exception
to remember.

The four private helpers are the deliberate exception. `checkPair` and
`checkEpochs` guard the operand pair for the binary operators;
`assertClean` guards the stacks for six methods; `rangeToYears` parses a
`Range=`. Naming *them* in the identifier would make renaming a private
function a breaking change, so they carry a stable CONCEPT segment
instead - `operands`, `stack`, `range` - and the help says so rather
than naming the helper.

The distinction that matters survives it: `plus` reaches
`shCoefficients:operands:epochMismatch`, `minus` does not, because
`minus` calls only `checkPair`. A test pins both halves.

### The gate now proves the middle segment

Three-part alone would be a spelling convention. `error_id_audit.py`
checks that the middle segment names either a method of that class or one
of the three declared shared checks, so `shSeries:att:badIndex` fails.
`TWO_PART_OK` is drained to empty and, per A14, its self-test asserts the
MECHANISM with a temporary entry rather than looping over a set that can
no longer fail.

### Verification

47 raise sites rewritten, scoped to the function each sits in; 58 source
lines and 58 help rows. 47 test pins were remapped **by line**, each to
the method the call under test actually reaches - `ts.mean(Range=...)`
raising a bad range goes to `shSeries:range:badRange` (the shared parser)
while the empty-window case goes to `shSeries:mean:emptyRange`. Three
`html/` references and one line of `make_guide.py` followed.

No numerical behaviour changed; no signature changed; the test count is
unchanged at 304 methods / 305 runs.

**One pin was wrong and CI caught it** (`testGravisChainsContract`, first
run of PR #99). The two chain pins were mapped to
`shSeries:fromFolder:noFiles` by tracing the call graph -
`twsChain` -> `gravisL2B` -> `fromFolder` - but `fromFolder` asserts
`isfolder` and then DELEGATES to `shSeries.read`: the temp folder EXISTS,
so that guard passes and the empty folder is caught by `read`'s pattern
check. Corrected to `shSeries:read:noFiles`. Which guard fires depends on
the input, not only on which function is called.

The other 45 pins were then re-verified against the guard ORDER of every
method they exercise. `noFiles` is the only reason raised by two
functions that a test reaches through a delegation, so this was the one
instance of the shape rather than the first of several.

**A second pin was wrong too, and the enumeration is why.** The grep that
listed the pins to rewrite used `[A-Za-z]*` for the reason segment, and
`shCoefficients:noC30` **has digits in it** - so it was never listed, was
never rewritten, and `testTN14IDs` went red on the next run. The
verification grep repeated the same character class and repeated the same
blind spot.

### Added - `error_id_audit.py` PINS: tests may only name real identifiers

Nothing read `tests/` before. The rule collects every identifier the
toolbox can raise - including the prefixes handed to
`+shLowLevel/private/normalizeMonthList`, and the few identifiers test
helpers raise themselves - and reports any pin outside that set. 184 pins
checked.

Its reach is stated in its own docstring because it is narrower than it
sounds: it catches a pin naming an identifier that exists NOWHERE (the
`noC30` case), and **not** a pin naming a real identifier the call under
test cannot reach (the `fromFolder`/`read` case), which needs per-call
guard analysis. One of the two red rounds is preventable here; the other
is not.

The first version reported three findings, all false - `rmIfFolder`
*raises* its identifier rather than pinning it, and two are built by a
private helper from a prefix its callers pass. Narrowed rather than
"fixing" the tests. Then fault injection found a worse bug: harvesting
prefix literals from `tests/` as well let the bad pin be read as its own
prefix, so the rule went quiet on the very defect it was written for.
Prefix literals now come from the toolbox only, and a prefix covers only
what sits below it (`shSeries:read` does not validate `shSeries:readFoo`).
Six self-tests, one of which pins the stated limit.

## [4.0.3] - 2026-09-09 - The class surface joins the identifier gate (A21a)

A21's documentation half. The three class files raised **32** error
identifiers with no `Error identifiers` section anywhere; 31 public
methods now carry one, and `error_id_audit.py` reads them. The rename
half (A21b) stays open and is now a measured, shrinking backlog rather
than a paragraph.

### Added - per-method `Error identifiers` blocks in the three classes

A class needed a different instrument, not a wider loop. Identifiers
belong to METHODS, and a user catching one calls a PUBLIC method - but
several are raised by PRIVATE helpers (`shCoefficients.checkPair`,
`checkEpochs`, `shSeries.assertClean`, `rangeToYears`), where `help`
cannot reach them. So the rule follows REACHABILITY, one hop: a public
method documents what it raises itself plus what the private helpers it
calls raise. `shSeries.filter` therefore documents `shSeries:nanInSeries`
even though `assertClean` is what raises it.

One hop is **checked, not assumed**: if a private helper ever calls
another private helper the gate says the rule has become too shallow,
rather than quietly under-reporting.

The map is derived from the source, and it caught a real distinction that
prose would have blurred: `shCoefficients.plus` calls `checkEpochs`,
`minus` does **not** - a difference between two months has no single
epoch, so `minus` sets `epoch = NaN` instead of refusing. Both help
blocks now say so, and a new contract test pins the half that was
untested (`plus` raising `shCoefficients:epochMismatch` was pinned;
`minus` *not* raising it was not, so a stray `checkEpochs` call in
`minus` would have passed every test).

### Added - A21b: the two-part identifiers are a named backlog

29 of the 32 are two-part (`shSeries:badInput`), so a caller cannot tell
which of the 35 methods raised; only three
(`shSeries:removeAlias:tooShort`, `shSeries:toGrid:empty`,
`shSeries:toGrid:tooLarge`) name their method. Making the rest
three-part is MAJOR - `testContract` pins the current names - so they sit
in `TWO_PART_OK`, which may only shrink and whose size the gate prints
every run. A two-part identifier **not** in that set is a new defect and
fails the gate.

### Fixed - one constant was answering two different questions

`CLASS_FILES` was both the list of files the CLASS pass reads and the
skip-list `surface()` uses to keep class files out of the root-function
pass. A self-test that emptied it to focus on the package therefore
re-admitted `shSeries.m` as a ROOT function owning
`shAnalysis:shSeries:*`, and the suite went red for a reason that had
nothing to do with what it was testing. The skip-list is now its own
frozen constant. This is A17's shape again: when one name answers two
questions, the answers drift apart silently.

A missing class file is now a finding rather than a traceback.

### Verification

Nine new self-tests fault-inject every class rule in both directions - a
private helper's identifier left undocumented, a documented identifier
the method cannot reach, a missing section, a foreign identifier, a
two-part identifier outside the backlog, and the second-hop depth guard.
30 tests in `test_error_id_audit.py`, all green.

## [4.0.2] - 2026-09-09 - Every raised identifier is documented

A20 closed. The 61 package files that raised error identifiers without
an `Error identifiers` help block now carry one - **208 identifiers**,
each description written against the raise site and its guard, not
against the message string. The backlog in `tools/error_id_audit.py` is
drained to empty and the DOCUMENTED rule holds with no exemption.

### Added - `Error identifiers` blocks in 61 `+shLowLevel` files

The count in `CLAUDE.md` said 165. It was 208; nobody had measured it.
Every block was checked against the code before it was written: the
writer refused any file whose documented set was not exactly the set the
file raises, so a description can be wrong in its wording but not in its
name.

### Added - the root functions, and the identifiers no scan could see

`demo_shAnalysis` and `setup_shAnalysis` gained blocks too, and the gate
now reads them. `setup_shAnalysis` turned out to raise five identifiers
**no static scan of the file can find**:

    warning("shAnalysis:setup:no" + locs(li, 1), ...)

built from the option name. Read as a literal it invents
`shAnalysis:setup:no`, which nothing raises - and that is precisely what
the extended gate reported first. A concatenated literal is now treated
as a PREFIX: the help must document at least one identifier under it,
because the gate cannot enumerate them. All five (`noSeriesFolder`,
`noMasconFile`, `noGravisFolder`, `noDDKFolder`, `noTestDataFolder`) are
named in the help.

### Changed - `demo:*` identifiers get the toolbox namespace

`demo:casesFailed` and `demo:unknownCase` had no namespace at all. They
are now `shAnalysis:demo:casesFailed` and `shAnalysis:demo:unknownCase`,
consistent with `shAnalysis:setup:*`. This is a PATCH, not a break:
neither was documented anywhere (`grep` over help, `html/`, the guide
and the changelog found only the raise site), and the toolbox's rule is
that an undocumented identifier is not part of the contract - the same
reasoning that made `shSynthesisDeformation`'s rename a PATCH in
v3.33.1. The two `testContract` pins were updated with them.

### Changed - the backlog self-test no longer goes vacuous when drained

`test_backlog_only_names_files_without_a_section` iterated over
`UNDOCUMENTED`; emptying it would have left an assertion that cannot
fail. That is exactly how A14's `test_legacy_name_tolerated` sat broken
for a release. The mechanism is now asserted with a TEMPORARY entry, and
two more tests fault-inject the no-section rule on a synthetic tree -
one that must fire, one that must pass once the section is added.

### Fixed - `tvANSFilter`'s stranded `Options` section

Writing the blocks turned up a help block whose `Options` section sat
BELOW a `Claude (...)` credit line, separated from the other sections.
The credit line is reunited with the provenance footer, so `Options`
now sits with `Inputs` and `Outputs` where a reader looks for it.

### Known - A21: the three class files are outside every gate

Measured, not estimated: `shCoefficients`, `shSeries` and
`shClimatology` raise **32 identifiers** between them and carry **no**
`Error identifiers` section. 29 of the 32 are two-part
(`shSeries:badInput`), so a caller cannot tell which of the 35 methods
raised. The gate does not read them, and says so in its own output
rather than implying a reach it does not have: a class needs a
per-method owner rule, which is a different instrument, not a wider
loop. Recorded as A21 in `CLAUDE.md`.

## [4.0.1] - 2026-09-09 - The option-values gate, and a correction to the record

A19 closed, and one decision in `CLAUDE.md` corrected because it was
wrong in a way that blocked work.

### Added - `tools/dev/option_values_audit.py` (A19)

`opApply` documented `mode` values (`'apply' | 'applyT'`) that its
arguments block rejected (`'forward' | 'transp'`). v3.34.1 fixed the row
but left the general check unbuilt: the obvious implementation - grep
help lines for quoted words near an option name - produced 25 hits of
which 24 were false.

The gate reads `api_data.py` instead, where each option already carries
its own `allowed` set and its own help row, so the scoping problem
disappears. The rule is deliberately narrow: only a row's LEADING
ALTERNATIVES RUN - a pipe-separated list of quoted values, the house way
of writing the choices - is compared against `mustBeMember`. A row
without one documents prose and is not checked. 42 of the 61
value-restricted options carry such a run.

Verified against the historical defect rather than asserted: fed
`opApply`'s pre-v3.34.1 row the gate fires; fed the fixed row it is
silent; and it stays silent on the three shapes that made the naive
version lie - another option's value quoted in prose
(`SignalMode='isotropic'` inside `Blocks`' row), a parenthetical inside
the run (`'auto' (default) | 'on'`), and a numeric member list
(`[60, 96]`).

### Fixed - CLAUDE.md said CI could not serve as an oracle. It can.

The 2026-09-08 tier decision recorded that WP3/WP4/WP5 could not
proceed because "the Python oracle can be written but nothing can be
checked against it". That is false, and it blocked four packages for a
day. The oracle is a Python script that runs in any sandbox; the
comparison is a MATLAB test that runs on the self-hosted runner through
CI. Neither half needs a local interpreter - which is exactly the
mechanism §2 has always described. WP3, WP5 and WP7 wait on approval,
not on a bridge. Only WP2's two-machine speed calibration genuinely
needs the acceptance machine.

### Changed - §3.4's invariant is now literally true

It claimed the gate list "must equal what `ci.yml` runs" while omitting
`count_tests.py` and including four local-only tools. It now says
CONTAIN, names the four (`mlint_lite`, `check_api`, `api_audit`,
`attribution_sweep`) as having no CI step by design, and lists
`count_tests`.

All four releases (3.33.1, 3.34.0, 3.34.1, 4.0.0) are merged; the
verification board's Merged column is no longer pending.

## [4.0.0] - 2026-09-09 - Every identifier owned, every option in house casing

WP1. The last six v1-era functions leave `inputParser`, and every error
identifier is owned by the function that raises it. Approved as a hard
break with no deprecation shim.

### BREAKING - what actually changes for a caller

Read this list literally: it is shorter than the diff suggests, and the
reason is measured rather than assumed.

**Error identifiers.** Seventeen raise sites used an identifier
belonging to another function. Any `catch`/`verifyError` on these must
be updated:

| was | now |
|---|---|
| `shSynthesis:badInput` (in shSynthesis) | `shLowLevel:shSynthesis:badInput` |
| `shSynthesis:badP`, `:badMethod` | `shLowLevel:shSynthesis:*` |
| `shSynthesis:missingLoveNumbers`, `:badQuantity`, `:heightInvalid` | `shLowLevel:kernelFactors:*` |
| `shSynthesis:badInput` (in shSynthesisGradient) | `shLowLevel:shSynthesisGradient:badInput` |
| `shSynthesis:missingLoveNumbers` (in seaLevelFingerprint) | `shLowLevel:seaLevelFingerprint:missingLoveNumbers` |
| `shReadGFC:*` (4), `shEvalGFCT:*` (3) | `shLowLevel:<fn>:*` |
| `shSpectralCrossover:missingField` | `shLowLevel:shSpectralCrossover:missingField` |
| `shAnalysis:geoMapRequired` | `shLowLevel:requireGeoMap:geoMapRequired` |
| `shCoefficients:toGrid:fullFieldAsMass` | `shLowLevel:gridHandover:fullFieldAsMass` |
| `shLowLevel:writeAnimation:badExtension`, `:mp4Unsupported` | `shLowLevel:writeFrames:*` |

Two of those were wrong in a way worth naming. `gridHandover` is called
by BOTH `shCoefficients.toGrid` and `shSeries.toGrid`, so the old
warning name misattributed it for every series user. `writeFrames`
raised `shLowLevel:writeAnimation:badExtension` next to its own
`shLowLevel:writeFrames:badSize` - inconsistent inside one function.

**One option rename.** `n0` -> `Nmin` on `shDegreeRMS`, and `N0` ->
`Nmin` on `shOrderRMS`, `shCoefficients.degreeRMS` and
`shCoefficients.crossover`. Three spellings for "lowest degree
included" are now one.

**The other option renames break nothing.** `quantity` -> `Quantity`,
`nmin`/`nmax` -> `Nmin`/`Nmax`, `method` -> `Method`, `minOrder` ->
`MinOrder`, `sigmaC` -> `SigmaC`, `ax` -> `Ax` and the rest are
case-only, and MATLAB matches Name-Value names case-insensitively -
measured against R2026a and documented in `nv_casing_audit.py`. Old
call sites keep working; a contract test pins that the old spelling
returns the identical numbers, not merely that it runs.

### Fixed - the gate that could not see the problem

`nv_casing_audit.py` reads ARGUMENTS BLOCKS, so for these six functions
it had nothing to look at: they parsed with `inputParser`, which is
itself case-insensitive, and lowercase names survived v3.33.0's sweep
unnoticed. It now rejects the construct outright, with the line number
read from the real file.

`plotSHSpectrum` was the one non-mechanical conversion: it used
`p.UsingDefaults` to let a legacy `field` option override `Quantity`,
and an arguments block has no equivalent. `Field` keeps its behaviour
through an empty-string sentinel, documented as such.

### Added - `tools/error_id_audit.py`

Three rules, each fault-injected: ownership (no backlog - the sweep made
it true everywhere), raised implies documented, documented implies
raised. 61 files predate the "Error identifiers" convention and sit in a
named backlog the gate reports every run and that only shrinks.

It found three gaps in files this release never touched: `readSHM`
documented 3 of the 5 identifiers it raises, `hydroExtremeIndex` 2 of 3.

Its first version reported five ownership violations of which four were
false - `tvANSFilter` COMPARES against another function's identifier in
a catch, `fetchITSG*` pass their own name as a prefix to a helper. It
now matches only the identifier argument of error/assert/warning, and
both shapes are pinned in its self-test.

### Fixed - the arguments block that was not first (found by CI)

`plotSHSpectrum` normalises a single spectrum into a cell before doing
anything else. WP1 put its `arguments` block where `inputParser` had
been, which is BELOW that guard - and MATLAB requires the block to be
the first statement. The function no longer parsed, so every call to it
raised, and five tests went red on a green `mlint_lite`.

`mlint_lite.py` gains **R6**: an arguments block must be the first
executable statement of its function. It fires on the exact file CI
rejected, stays silent when the same guard sits below the block, and is
pinned by `tools/tests/test_mlint_lite.py` - the first self-test that
tool has had.

### Unchanged - the numerics

No numerical line moved. Each conversion replaced the parsing preamble
and kept the local variable names, so the body diffs to nothing: for
`shGaussianWeights` and `shDestripe` the body is byte-identical from the
first computed line onward, and for the rest the only body change is the
option access itself. 301 -> 304 tests.

## [3.34.1] - 2026-09-08 - A public function nothing could see, and coverage by name

Two instruments were measuring less than their silence suggested. No
numerical behaviour changes; one help block corrected.

### Fixed - a public function was invisible to the API extractor (A17)

`gridHandover` continues its signature across two lines with `...`.
`api_extract.py` matched the signature on a single raw line, so the file
parsed to nothing and the entity never reached `api_data.py`. It
therefore had no reference page - while `apiReference.html` told the
reader the handover bundle was "as built by shLowLevel.gridHandover,
which documents every field", linking nowhere.

`refpages_audit.py`'s COVER check compares the generated pages against
`api_data.py`, so it reported zero findings: the gate's reach was
defined by the bug it should have caught.

Four parsers of "what is a public entity" live in this repository. Two
were blind the same way - `api_extract.parse_function_file` and
`doc_sync_audit.parse_one` - and they agreed with each other. That is
why the new guard checks the FILESYSTEM, not a second parser's opinion:
MATLAB requires a file to define the function it is named after, so
every `+shLowLevel/X.m` owes exactly one entity `shLowLevel.X`.

- both parsers join `...` continuations and read the help block after
  the LAST continuation line. Both skip comment lines inside a
  continuation, as MATLAB does - joining one let a `(base MATLAB only)`
  in a help line supply the closing paren and parse to nonsense. Found
  while fault-injecting, not by review.
- `api_extract.py` refuses to write `api_data.py` when any public file
  produces no entity.
- `doc_sync_audit.py` gains a SURFACE check, fault-injected both ways.
- `tools/tests/test_api_extract.py`: 5 of its 7 tests fail against the
  pre-fix extractor; the 2 that pass cover shapes never broken.

122 package entities (was 121), 200 reference pages (was 199).

### Fixed - `opApply` documented option values it rejects

Its Inputs row offered `'apply' | 'applyT'`; the arguments block accepts
only `'forward' | 'transp'`, which the same help block's syntax lines
had right. A caller following the row got a validation error. Found
while writing the test that now pins both modes.

### Added - `tools/dev/name_coverage.py`, and the 32 tests that satisfy it (A10)

The audit found thirteen package functions no test file mentioned, by
hand. Nothing measured it, so the set could only grow - and it was
larger than recorded: **22 public class methods** were unnamed too
(A18), among them every operator (`plus`, `minus`, `uminus`, `mtimes`,
`times`) and `disp` on all three classes.

The gate strips comments first, so a name in a `% see also` line does
not count. Its claim is deliberately narrow and it says so in its own
output: naming is not exercise. Operators get no exemption - they are
callable by name, and a test that checks `plus(a, b)` against `a + b`
is stronger than one that checks either alone.

New tests assert a property each function's own help states:

- `icgemDate2Year` hand-computed epochs across a leap and a non-leap
  year, and the documented `< 1.8e7` pass-through
- `pctile` against the documented order statistic, the median identity,
  clamping, non-finite handling and empty input
- `gridHandover` reads FieldKind off the C00 identity - the same grid is
  labelled full, anomaly, unknown or mixed by C00 alone
- `shDestripe` annihilates a polynomial in degree, passes `m < MinOrder`
  through bitwise, and leaves a subset with too few degrees alone
- `shGaussianFilter` is exactly the weights applied by degree
- `shSpectralCrossover` finds the first crossing and returns NaN for none
- `vceRescale` is quadratic in the residuals and inverse in the
  covariance - powers of two, so the identities are bitwise
- `opApply` is the true adjoint of its forward operator, dense and
  block-diagonal
- `buildSignalCov` is scale-equivariant
- `plotBasinSeries`, `plotCovariance`, `spectrum`, `triangle` return
  graphics handles; `disp` prints the identifying facts
- `shClimatology.fromCoef` honours its documented row layout, one
  distinct constant per row so a swapped mapping is visible

268/269 -> 300/301 tests, and the self-hosted runner executed **exactly
301** - the prediction matched. 296 passed, 4 filtered (the optional
real-data fixtures), 1 failed: `testCompareDelegatesToCompareSolutions`
gave `compareSeries` 8 epochs where it requires >= 12 common ones. That
guard is an `error` a hundred lines into the function, not part of its
`arguments` block, so reading the signature was not enough. Fixed by
giving the fixture two full years.

### Fixed - `demos.xml` carries the version stamp, and nothing said so

The first push of this release failed CI on `make_demos.py --check`:
`demos.xml` is generated from the demo registry AND stamped with the
toolbox version, so bumping to 3.34.1 made it stale on its own. It was
regenerated by neither of CLAUDE.md's two lists, because `make_demos`
appeared in neither - eleven local gates were green while `gates` was
red.

- `doc_sync_audit.py`'s VERSION check now covers `demos.xml` too, so the
  gate that owns version agreement owns all four stamped artifacts
  (`apiReference.html`, `html/ref/*`, `demos.xml`, the guide PDF).
  Fault-injected both ways: a stale stamp and a missing one.
- CLAUDE.md §3.4's gate list is now stated to equal `ci.yml` and names
  `make_demos --check` and `name_coverage`; §3.9 names all four
  generators.

## [3.34.0] - 2026-09-08 - Struct fields, a correct test count, and reference pages

Second half of the documentation-rot work, and the check that closes the
class of defect v3.33.1 fixed by hand. No numerical behaviour changes.

### Added - `help_audit.py` now checks struct output FIELDS, both ways

v3.33.1 fixed eight help blocks that named struct fields the code does not
produce (`tn.t`, `info.condest` for `condEst`, `out.q16/q50/q84`, ...). It
fixed them by reading; nothing stopped the next one. Now:

- **documented => assigned.** Every field a help block lists must be
  assigned somewhere in that function. Runs where the help gives a field
  LIST (the house form: the struct row ends with `fields`, one field per
  deeper-indented line - the spelling already dominant in the tree).
- **assigned => documented.** Every field the function writes on a
  documented struct output must appear in its Outputs section. Needs no
  parsing, so it runs on prose rows too - and it found **55** fields the
  code returns and `help` never named.

`help_audit.py` reports its own reach rather than implying full
coverage, and that reach is now total: **96 documented struct outputs -
79 with a field list verified against the source, 17 naming the function
that builds them, 0 prose.** A mechanical prose-to-list rewrite was
written, inspected and **discarded** because it produced confident
nonsense (`'full-blocks'` split at a field name, a nested struct array's
subfields hoisted to the top level), so all 79 were converted by hand
against the source, with the gate verifying every name as it went.

That conversion found **three more** help blocks naming fields that do
not exist, on top of the eight v3.33.1 fixed by reading - eleven in all:

| Function | Documented | Reality |
|---|---|---|
| `shReadGFC` | `model.tide` | the tide system is `model.header.tide_system`, which is where `shCoefficients.read` gets it |
| `readSINEX` | `snx.header` | no such field |
| `gravisL2B` | `rep.files` | no such field |

**Five defects in the checker itself**, each caught by reading its output
against the source before trusting it, each now with a regression test:

- MATLAB's `'` is transpose after a value, so
  `struct('areaFraction', w' * mask, ...)` desynchronised the scan and
  hid three of `basinKernel`'s four fields. Converting that row first
  would have made a **correct** help block look wrong.
- `struct()` alternates name and value: the `"zeroField"` in
  `struct(..., 'stoppedBy', "zeroField", ...)` is a VALUE, and counting
  it invented a field `leakageCorrect` does not have.
- the field-row grammar demanded two spaces before the type, so
  `epochStart, epochStop (T x 1 double)` broke the parse.
- the list marker was case-sensitive, so a preamble ending `Fields` was
  not seen.
- a classdef's local functions were excluded from a method's source,
  hiding the struct `shSeries.mean` builds in `meanWindowInfo`.

The delegation marker was tightened as well: a bare "from" or "see"
appears in ordinary prose ("removed from the file", "from the ocean-fit
residual") and had silently excused five rows that were in fact
documented here and verifiable. It now requires an explicit reference to
the function that builds the struct.

### Fixed - 55 struct fields the code returns and the help did not name

Found by the new direction. Among them:

- `shIndex`: the help named `nmax` and `Nmin`. The FIELDS are `Lmax` and
  `minDegree` - the help had copied the option spellings - and `pos`, the
  reverse map, was undocumented. `shIndex` is the toolbox's canonical
  vector ordering, so this one was in everybody's way.
- `trendBreaks`: 15 of its 17 fields were described only in the prose
  paragraph, and the Outputs section called them `shCoefficients` when
  they are plain `(n1 x n1)` doubles.
- `tvANSFilter`: `op.layout`, `op.blocks`, `op.sBlocks`, `op.detLeverage`,
  `op.detResVar`, `info.vce`, `info.sigmaNote` - including which of the
  two operator layouts is filled, which a caller must know.
- `httpFetch.transport` was documented as if always present; it exists
  only on the websave-fallback path. The correction says so.
- `shReadGFC.variableTerms` (documented as two words, "variable terms"),
  `header`, `modelname`; `shOrderRMS`'s `err*` glob spelled out;
  `eofAnalysis`, `eofSeparate`, `fetchDDK`, `fetchGAX`, `fetchICGEM`,
  `fetchITSG`, `fetchITSGBackground`, `basinScaling`, `oceanChain`,
  `kalmanFilter`, `seaLevelFingerprint`,
  `shSynthesisGradientTensor`.

### Added - `tools/dev/count_tests.py`, and a corrected test count

The predicted test count was **wrong**, on a green run. `grep -c '^function
test' tests/*.m` counts the script-based harness entry point (`function
tests = testCorrectness`) as a test, and misses every `bench*` method and
every parameterised expansion. It said 261, and this release predicted 262;
the runner ran **268**.

`count_tests.py` reports methods and runs per class, expands
`TestParameter` blocks, and with `--executed N` exits non-zero on a
mismatch. It reproduces the self-hosted run exactly. CI prints it beside
the run. The corrected figures: Correctness 135, Contract 61, Robustness
53, Science 7, Performance 11 methods / 12 runs - **267 methods, 268 runs**,
of which 3 filter out when the optional real-data fixtures are absent.

### Fixed - three defects in the new checker, found by reviewing its own output

Recorded because each produced confident, wrong findings before it was
caught, and each is the kind of thing a gate is supposed to prevent:

- an `id(src)`-keyed cache returned another file's field set (CPython
  reuses ids after garbage collection) - 6 invented findings;
- a class method was given the WHOLE class file as its source, so a
  variable named `op` or `info` in a sibling method counted - 57 invented
  findings;
- quoted literals inside a call NESTED in `struct(...)` were read as field
  names, so `struct('created', string(datetime('now', 'Format', ...)))`
  looked like three fields - 4 invented findings.

### Added - WP6 stage 1: a reference page per entity

`doc` integration was a monolith: 196 entities had a dedicated page only
inside the 304 KB `apiReference.html`, the 50 hand-written pages used five
heading vocabularies, and each inlined its own `<style>` (A7, A8).

- **`tools/dev/make_refpages.py`** emits `html/ref/<entity>.html` for all
  198 public entities plus an index - 199 pages - in the MathWorks order:
  Syntax, Description, Examples, Input Arguments, Name-Value Arguments,
  Output Arguments, Error Identifiers, Version History, See Also. Every
  page carries every section; a section with nothing to say says so,
  because a missing section and an empty one are different claims. Nothing
  on a page is hand-written: all of it derives from `api_data.py`, which is
  parsed out of the help blocks, so a page cannot drift from its source.
- **`html/shAnalysis.css`**, one stylesheet for the look: system font
  stack, 14 px body, `#0076a8` links, a grey Syntax panel, bordered
  argument tables, collapsible examples in plain HTML `<details>` (no JS).
- **`api_extract.py`** now also captures `Error identifiers` (14 files) and
  `See also` (15), neither of which is derivable. `See Also` is completed
  from the entities a help block actually names - measured, not asserted.
- **`tools/dev/refpages_audit.py`**, the gate: pages match what the
  generator would write now, every entity has a page and no page outlives
  its entity, every section present and in order, no heading outside the
  skeleton, no inline `<style>`, every relative link resolves. Seven
  fault injections in `tools/tests/test_refpages.py`.
- `helptoc.xml` reaches the new index, so the pages are visible in the
  Help browser.

Two of WP6's own premises did not survive measurement, and are recorded
rather than papered over:

- **Per-entity Version History from the changelog** was to be included
  "only if the match rate is > 80 %". A loose name match reaches 81 % but
  matches `filter` against releases that never mention it; a match
  anchored on the qualified name reaches 74 %. Below the bar either way,
  so every page links `CHANGELOG.md` and says why it does not claim a
  per-entity history.
- **"Functions by the existing tag categories"**: there are no tag
  categories in the data. Deriving them from `helptoc.xml` mapped 163 of
  198 entities and put 75 in one catch-all. The index groups by what IS
  derivable - classes, class methods, package functions, root functions,
  plus an A-Z list - and topic categories wait for an editorial decision.

### Added - WP6 stage 2: one look, one vocabulary, an Examples tab

- **The 50 hand-written pages now link `html/shAnalysis.css`.** They had
  carried an inline `<style>` block each - and only **two were distinct**:
  49 were byte-identical and one more sat in the generated
  `apiReference.html`. One stylesheet copied fifty times is exactly what
  A8 described. `make_apiref.py` emits the link instead of the block, so
  the copy cannot come back with the next regeneration.
- **One spelling per structural heading.** 46 headings were renamed:
  `See also` -> `See Also` (34), `Outputs` -> `Output Arguments` (7),
  `Example` -> `Examples` (6), `Inputs` -> `Input Arguments`,
  `Inputs / Outputs` -> `Arguments` (5, where one table genuinely covers
  both). Narrative pages keep their own page-specific headings; only the
  structural ones are pinned.
- **`demos.xml`** (`tools/dev/make_demos.py`), derived from the case
  registry inside `demo_shAnalysis.m` so a case cannot exist in one and
  not the other. 16 cases, each with a `demo_shAnalysis("Dnn")` callback.
- `doc_sync_audit.py` gates all three: no inline `<style>` anywhere in
  `html/`, every page links the stylesheet, structural headings use the
  house spelling, and `demos.xml` matches the registry both ways. Six
  more fault injections.

`setup_shAnalysis(Docs=true)` already ran `builddocsearchdb` on `html/` -
the audit's A7 missed it, so no second option was added; its help now
says the index covers `html/ref/` too and explains why the binary index
is not committed.

### Fixed - A13: the kilometre conversion was a hidden constant

`resolutionMap` turned its half-widths from degrees into kilometres with
a hardcoded `R = 6371`, against the toolbox's own rule that physical
constants are defaults, not literals. It is now the `RadiusKm` option -
default unchanged, so no number moves - documented as the MEAN Earth
radius, which is the right choice for a great-circle distance and is
deliberately not the coefficients' reference radius (6378.1363 km).

`testResolutionMapRadiusIsAChoice` pins both halves metamorphically, so
no tolerance is involved: the angular half-widths do not depend on the
radius, every kilometre figure scales exactly with it, and `anisotropy`
- a ratio of two of them - is invariant. It also asserts the struct's
field names, and it takes `resolutionMap` off A10's list of functions
never named in a test. Declared test count 268 methods / 269 runs.

### Fixed - ten tests whose temp folder a killed run could poison

`runAllTests (self-hosted)` failed on
`testProvenanceSidecarsDoNotBreakTheRoundTrip` with

```
[Warning: Directory already exists.]
[Warning: ...\shx_sidecar_176639289\plain.gfc: 1502 of 1891 coefficient
 records (degrees 0..54) for the header's max_degree 60 - truncated file?]
Error ID: 'shSeries:sizeMismatch'
All epochs must share nmax (epoch 3 has 54, expected 60)
```

Two CI runs had been **cancelled** mid-suite by the next push. A killed
MATLAB process runs no `onCleanup`, so a half-written `plain.gfc` stayed
behind in the runner's temp folder - and the folder name,
`sprintf('shx_sidecar_%d', randi(1e9))`, is reproducible whenever the rng
state at that point is, so the next run walked straight back into it and
read the truncated file as a third epoch.

Ten tests built their temp path that way. They now use `tempname`, which
is the pattern this repo already documents in `tests/rmIfFolder.m` and
uses in eight other places: it returns a path that does not exist, so no
leftover can be found and no two runs can collide. The test was never
skipped, widened or given a tolerance - it isolates itself now, which is
what it should always have done.

To be exact about what this change did and did not do: the leftover had
already cleared itself by the next run, which was green **before** this
fix existed. It is hardening against recurrence, not the cure for a red
build. The failure was intermittent in practice but not a flake - the
mechanism is deterministic given its precondition.

### Fixed - two gates that were not looking where they claimed

- `attribution_sweep.py` globbed `html/*.html`, so it kept reporting 50
  pages while 199 more existed one directory down. Now recursive: 249.
- `doc_sync_audit.py` and `testHelpBrowserTocIsComplete` both compared
  `helptoc.xml` targets against bare filenames, so any target in a
  subfolder read as a dead link. Both resolve targets against `html/` now.

### Added

- `tools/tests/test_help_audit.py` grows to 17 tests; `test_count_tests.py`
  (7) and `test_refpages.py` (14) are new. Every rule fault-injected and
  paired with a clean-tree assertion. Five self-test suites, 81 tests.

## [3.33.1] - 2026-09-08 - Documentation rot, and the gates that missed it

Hygiene release: no numerical behaviour changes. Every finding below was
green on all nine gates for weeks - the gates checked that a section was
present, never that it appeared once, and never that what it claimed was
what the code returns.

### Fixed - 65 help blocks carried two sections of the same kind

`fix_help.py` appended a generated `Outputs`/`Options`/`Inputs` section
below the hand-written one instead of editing it, in every run since
2026-08-12. `help_audit.py` reads the FIRST such section, so the second
was invisible to it - and the two disagreed. Where they disagreed, the
code was consulted and both were often wrong:

- `readTN14`: the help promised a field `tn.t`. There is none; the
  reader returns `epoch`, `epochStart`, `epochStop`.
- `parseGraceFilename`: `center`, `product`, `release`, `year`, `month`,
  `nmax` and "raw tokens" were documented. The parser returns
  `productType`, `epoch`, `epochStart`, `epochStop` and nothing else.
- `resolutionMap`: documented as returning an `(nlat x nlon)` double of
  half-widths. It returns a struct - `psiHalfDeg`, `azDeg`, `kmMean`,
  `kmMin`, `kmMax`, `anisotropy`.
- `shAnalysisGrid`: every documented `info` field name was wrong -
  `condest` for `condEst` (MATLAB is case-sensitive on fields), `nObs`
  for `nPoints`, and a `kaula` field that does not exist. `method`,
  `unobservedDegrees`, `regularized` and `residRMS` were undocumented.
- `basinDeconvolve`: the two `Ridge` descriptions contradicted each
  other and neither matched the code, which solves
  `(A'A + lam^2 I) \ (A' v)` with `lam = Ridge*||A||_2` - relative to
  the spectral norm, which is the whole point of the v2.1 change.
- `buildSignalCov`: `info` was documented as `mode` and `iterations`,
  neither of which exists; it holds `c` (P x NIter+1, one column per
  iteration) and `varMap`.
- `vceRescale`: documented as returning `(nBands x T)`. It returns
  `(T x 1)`; `tvANSFilter` assembles the band matrix itself.
- `mcPropagate`: `q16/q50/q84` percentiles were documented and are not
  computed; `N` was undocumented; `samples` is conditional on
  `KeepSamples`.
- `shSynthesis`: the fourth output `P` is EMPTY in latitude-banded mode
  (`MaxMemGB` exceeded) - undocumented, and a caller passing it back in
  would have been puzzled.
- `readMascon`, `shSynthesisDeformation`, `errorMap`, `rescaleGMR`,
  `buildNoiseCov`, `shCoefficients.analysis` and 35 class methods:
  corrected against the source in the same sweep. `errorMap`'s
  description had been truncated mid-sentence since its first commit.

### Fixed - error identifiers a caller could not catch by owner

`shSynthesisDeformation` raised `shSynthesis:badInput` and
`shSynthesis:missingLoveNumbers`. It now raises
`shLowLevel:shSynthesisDeformation:badInput` and
`:missingLoveNumbers`, documented in its own `Error identifiers` block
and pinned by `testDeformationIDs` (which also checks the identifier
survives the `shCoefficients.deformation` delegation). Not a breaking
change: these identifiers were never documented.

`kernelFactors`, `shSynthesisGradient` and `seaLevelFingerprint` still
raise `shSynthesis:*`; those identifiers ARE documented and pinned by
tests, so renaming them is a major-version change and stays with the
identifier sweep of the next major release.

### Fixed - documentation that had aged

- The shipped workflow guide PDF was stamped v3.28.0 - five releases
  behind, missing the BREAKING `MinDegree`/`MaxDegree` -> `Nmin`/`Nmax`
  rename. Rebuilt, and `doc_sync_audit.py` now reads the PDF's page-1
  running head and fails when it disagrees with `Contents.m` (standard
  library only: reportlab writes ASCII85 + Flate streams).
- `docs/apiReference.html` was a byte-identical copy of
  `html/apiReference.html`. Nothing wrote it, nothing read it, nothing
  compared them. Deleted; `doc_sync_audit.py` now fails on any HTML page
  outside `html/`.
- `README.md` said CI pulls the orphan branch `testdata`. CI has pinned
  the tag `fixtures-YYYY-MM` since v3.26.1. The README now points at
  `ci.yml` rather than naming a tag it would have to keep in step.
- `Contents.m` was 1149 lines, 74 "New in v..." sections out of
  chronological order, printed in full by `help shAnalysis`. Now 78
  lines: product line, classes, quick start, internals, tests, and a
  pointer to this file. Nothing was lost - v2.1, v2.2, v2.3, v2.4,
  v2.4.1 and v2.4.2 existed only in `Contents.m` and are written up
  below in this release.
- Section headings in help blocks now use one vocabulary:
  `Name/value options:` -> `Options` (5 files), `Errors` -> `Error
  identifiers` (2), `Output`/`Examples` -> `Outputs`/`Example` in
  `setup_shAnalysis`.

### Added - the checks that would have caught all of it

- `help_audit.py` (v3.0.2): a house-vocabulary section may appear at
  most once per help block; no section may appear below the provenance
  footer, where the doc builder stops reading; near-miss spellings are
  named with the spelling to use. Prose sub-headings inside a
  description are explicitly not sections.
- `tools/tests/test_help_audit.py`: nine tests, each rule fault-injected
  (fires on the defect) and paired with a clean-tree assertion.
- `fix_help.py` refuses to create a second section of a kind that
  already exists, and says so instead of writing.
- `api_extract.py`: a row in an `Outputs` section starts at the
  section's own indent; anything deeper is a continuation. Six entities
  (`httpFetch`, `obpChain`, `oceanChain`, `poleTideConvert`,
  `readMascon`, `readTN13`) had their struct sub-fields parsed as
  separate outputs, so the generated reference invented outputs the
  functions do not have.
- CI runs `tools/tests/` at last. The three gate self-tests committed in
  v3.32/v3.33 had never run in CI; one of them
  (`test_legacy_name_tolerated`) had been broken since the v3.33.0
  casing sweep drained `LEGACY` to empty, and nothing said so. It now
  asserts the mechanism instead of a member name.

### Changed

- `CLAUDE.md` records the audit findings this release closes, the ones
  it leaves open, and the four it adds (A12-A15).

## [3.33.0] - 2026-09-05 - Name-Value casing, and one real rename

### BREAKING: `MinDegree` and `MaxDegree` are gone

`shLowLevel.shIndex`, `designFilter`, `synthesisPoints`, `vceRescale`
and `shSeries.filter` took `MinDegree`; `readLoveNumbers` took
`MaxDegree`. Three spellings existed side by side for one concept -
`Nmax`/`nmax`, `nmin`, and `MaxDegree`/`MinDegree` - so they are merged
onto `Nmax` and `Nmin`.

This one IS a breaking change, and unlike the rest of this release it
cannot be papered over: MATLAB's case-insensitive Name-Value matching
rescues `nmax` -> `Nmax`, but `MinDegree` and `Nmin` are different
names. Update calls:

```matlab
idx = shLowLevel.shIndex(96, MinDegree = 2);   % before
idx = shLowLevel.shIndex(96, Nmin = 2);        % after
kn  = shLowLevel.readLoveNumbers(f, MaxDegree = 96);   % before
kn  = shLowLevel.readLoveNumbers(f, Nmax = 96);        % after
```

`VCEMinDegree` in `tvANSFilter` is unchanged - a different option, and
already conformant.

### Name-Value casing standardised (not breaking)

Declarations follow the MATLAB Coding Standards rule for Name-Value
arguments, UpperCamelCase: `quantity`, `gravisFolder`, `idx`,
`sigmaC`, `sigmaS`, `ax`, `minOrder`, `polyOrder`, `windowLength`,
`tYears`, `nmax`, `nmin`, `n0` become `Quantity`, `GravisFolder`,
`Idx`, `SigmaC`, `SigmaS`, `Ax`, `MinOrder`, `PolyOrder`,
`WindowLength`, `TYears`, `Nmax`, `Nmin`, `N0`.

Existing code keeps working: Name-Value matching is case-insensitive,
measured on R2026a rather than assumed.

Domain notation stays lowercase and is now documented as a deliberate
exception: `hn`, `kn`, `ln`, `a`, `f`, `omega`, `rho_ave`,
`rho_water`, `lat`, `lon`. `GM` and `R` were already uppercase.

Struct FIELD names are untouched. `info.nmax`, `info.quantity` and the
`n0` returned by `shCoefficients.crossover` are outputs, not arguments.

### New gate: `tools/nv_casing_audit.py`

Two Name-Value names differing only by case compile and run with no
warning, leaving one unreachable - and a casing sweep is exactly the
operation that creates such a pair. The gate also rejects new
non-conformant names and new prefix relations, which partial matching
turns into `AmbiguousInputName` at call time.

### Fixed: the documentation toolchain could not run outside one sandbox

Nine scripts in `tools/dev` carried absolute paths from their authoring
sessions. `make_apiref.py` wrote the regenerated API reference into a
clone from an earlier session while `doc_sync_audit` reported the
untouched page as stale. All paths now derive from `__file__`, with
`SHX_ROOT`, `SHX_API_DATA`, `SHX_GUIDE_OUT`, `SHX_GUIDE_ASSETS` and
`SHX_PORT` as overrides.

## [3.32.3] - 2026-08-23 - review of v3.29-v3.32.2, with fresh eyes

A model change is a review opportunity: everything since v3.28.0 was
re-read for mathematical, implementation and documentation defects,
with the mathematics re-derived rather than re-tested.

### Verified (container, by derivation)
The kernel table against the standard formulas (Wahr 1998 mass kernels,
free-air `n-1`, disturbance `n+1`, Trr `(n+1)(n+2)`), the radial
exponents n+1/n+2/n+3 and their chained identities, the sinc period-mean
derivation (trend and sine terms vanish for a centred T0; whole years
kill annual and semi-annual exactly), the design-matrix column
alignment of the `u` weights in `shSeries.mean`, the cofactor
u'(A'A)^-1 u, the per-coefficient sigma denominator, `select`'s
index/range disambiguation, `flatten` ordering, the FieldKind identity
and the stack-wide colour extremes. **No defect found.**

### Verified (acceptance machine, real data)
- The deferred whole-year check from the v3.28 handover:
  `mean(Range=[2021 2022], Estimator="model")` on 12 ITSG GRACE-FO n96
  months gives attenuation **exactly 0** for the annual and semi-annual
  terms, and agrees with the arithmetic mean to **2.2e-16** - the
  "round-off" claim in the help, measured true (ITSG epochs sit on
  exact twelfths, which is what makes the two estimators coincide).
- The deferred n96 runtime: synthesis 0.04 s, gradient 0.07 s on a
  180x360 grid. Not a concern.
- The gradient against a 5-point finite difference of `synthesis` on
  the real n96 field: north 1.1e-11, east 5.0e-12 relative; the up
  channel against the closed identity at 1.3e-14.
- Physics, not self-consistency: the deflection of the vertical from
  the n=2..96 field is **5.35 arcsec RMS**, where the published
  truncated value sits - a check against knowledge outside the toolbox.

### Fixed
- `html/shSynthesisGradient.html`: the advection note said "with
  Units='perRadian', dphi/dt is dq.north/r directly". Dimensionally the
  /r belongs to the **perMeter** form (v = mu*dq.north in m/s, dphi/dt
  = v/r); the point of perRadian is that an angular mobility needs no
  metric factor at all. The sentence now says so, and says it was
  wrong.
- `README.md` never mentioned the geoMap relationship: a reader calling
  `g.map` met an error the front page never hinted at. Four sentences
  now state who draws, that a gate keeps it that way, and that the
  dependency is checked rather than required.

### Noted, deliberately not changed
- `gradient` documents that geodetic input is converted and the vector
  resolved in the geocentric local frame (up to 0.19 deg of meridian
  convergence) - present and correct in the help since v3.31.0.
- `gravity_anomaly` keeps its `n-1` kernel down to degree 0, where a
  full field produces a large spurious term; unchanged since long
  before this window, out of scope here.

## [3.32.2] - 2026-08-23 - the acceptance run refuted the fix that installed it

v3.32.1 added `acceptance_geomap` and, in the same release, a fix for
the frame-capture defect. Its first run against the **installed**
v3.32.1 failed: `[401 656; 365 640; 365 640]`. The instrument refuted
the repair it shipped alongside.

### Fixed
- **`writeAnimation` frame capture, third attempt.** Under rapid figure
  churn the layout passes through a transient state - 401x656 against a
  target of 640x365, changing **both** dimensions - and `settleFigure`
  watched only the height, so it declared that state settled after three
  polls. It now watches the full `Position` and requires five stable
  polls, and `captureFrame` validates every capture against the **pin**,
  the size each frame of that video must have, rather than against
  whatever the figure reports at the moment of asking.

  Three hypotheses were measured and **refuted** before this one was
  adopted:

  | hypothesis | measurement | verdict |
  |---|---|---|
  | cold-session warm-up | clear geoMap's cache, redraw | refuted - a warm draw failed, cleared ones did not |
  | a geo.map layout difference | figure `Position` over 20 draws | refuted - never left 640 wide |
  | `set(Position)` not sticking | 12 isolated draws | refuted - stuck 12 of 12 |

  In isolation with a longer settle the fault did not appear at all, 12
  of 12. That is precisely why a timing-based repair could not be
  trusted: more waiting makes the symptom rare, not absent.

- `shLowLevel.requireGeoMap`'s message now mentions `savepath`. An
  `addpath` made by a setup script may last only for that session, and
  someone who has installed geoMap and still meets this error deserves
  the next step rather than a restatement of the problem.

### Notes
- **This is the third attempt at one defect, and the evidence behind the
  first two was too thin.** v3.32.0 shipped on four clean draws, v3.32.1
  on three. The base rate is about **1 in 6 exports**, so three runs
  pass by luck more often than not. This release rests on **32 exports
  across 8 acceptance passes, 96 frames, all byte-identical at
  365x640** - and on three refuted hypotheses rather than one confirmed
  guess.
- The instrument earned its place immediately: without
  `acceptance_geomap`, v3.32.1 would have shipped a defect that no
  static gate and no CI run can see, because CI has no geoMap.
- The geoMap path not surviving a MATLAB restart is **not a defect
  here**: `geoMapSetup` currently adds the path for the session only,
  and that is tracked in the Mapping project. The message change above
  is generic and stays correct once it is fixed.

## [3.32.1] - 2026-08-23 - the acceptance run, installed

### Added
- **`tools/dev/acceptance_geomap.m`** - the checks CI structurally
  cannot run, now repeatable instead of living in one session's
  scrollback. It exercises every path where shAnalysis hands work to
  geoMap, then takes geoMap off the path and runs the mirror half.

  Both halves, because **neither machine runs both**. CI has no geoMap,
  so it only sees the refusals. A developer machine has geoMap, so it
  never reaches them - `testNoMapIsDrawnHere` returns early when geoMap
  is present, and a bad `shSeries` call inside that very test once
  survived a 264-test acceptance run and failed CI.

  The frame-geometry check runs the shipped `writeAnimation` three times
  rather than re-implementing its loop. A check that copies the loop
  tests its own copy and drifts from the real one - which is the same
  mistake, one level up, as the two renderers this toolbox just removed.

### Fixed
- **`writeAnimation` was racing geo.map's resize, and v3.32.0's fix was
  luck.** "One fresh figure per frame" was measured over four draws,
  came back 365 px every time, and shipped. The first acceptance run
  produced **365, 340, 365** - 340 being the unresized starting height,
  i.e. `getframe` capturing before the resize landed. A single `drawnow`
  is not a barrier for it.

  The first repair attempt was a settle loop, and it had a hole worth
  recording: **two equal polls of a figure whose resize has not started
  look exactly like a settled one.** Frames are now captured only after
  the height has been stable across three consecutive polls and at least
  four polls have run, and every later frame is **pinned** to the first
  frame's settled size - equal by construction, not by timing. Nine
  consecutive exports of the same data are now byte-identical at
  165770 B, 365x640; before, one in three differed.

- `shLowLevel.writeFrames` records `frameSize` in the provenance
  sidecar. Two exports of the same data differed by 0.4% in bytes and
  nothing on disk could explain it. That difference turned out to BE the
  defect above; the geometry is now a recorded fact rather than
  something to infer from a file size.

### Notes
- Verified on the acceptance machine (R2026a Update 4, geoMap 2.0.541):
  **10 of 10, three passes in a row**, plus the nine byte-identical
  exports. A race deserves more than one green run.
- CI still cannot see any of this, and that remains permanent rather
  than temporary. The split is now written down in the script itself.

## [3.32.0] - 2026-08-23 - geoMap is the single cartographic authority

Matthias's decision, taken on the open question left at the end of
v3.31.0. This toolbox no longer draws maps.

### Removed
- **`shLowLevel.plotSHMap`.** It had its own coastlines, its own colour
  limits and two projections, beside sixteen certified against PROJC in
  geoMap - one fact with two implementations, and no instrument
  comparing them.

  **The scope was measured before anything was deleted, and it was
  smaller than the handover that raised it said.** That document counted
  "693 lines of plotting-ish files" by NAME. By behaviour:
  `shLowLevel.errorMap` and `shLowLevel.resolutionMap` contain **zero
  graphics calls** - they compute formal-error and resolution fields and
  return arrays. The renderer was 114 lines in one file. Both computing
  functions stay untouched.

### Changed
- `shCoefficients.map` synthesizes through `toGrid` and hands the result
  to `geo.map`. It draws nothing. Its `Units`, `Title`, `Projection`,
  `Colormap`, `CLim` and `Coast` options are gone: **geoMap's option
  table is not restated here.** `CRS` picks the projection, `Basemap`
  configures the raster element, and `GeoArgs` forwards verbatim -
  mirroring another toolbox's options is how two renderers drift apart,
  and `geo.map` applies the same rule to its own elements.
- `shLowLevel.writeAnimation` likewise: shAnalysis assembles the stack
  and writes the container, geoMap draws every frame. It now refuses
  **before** synthesizing - a two-minute stack followed by an
  undefined-function error is the wrong order to discover a missing
  dependency in. The fixed stack-wide colour scale is unchanged, still
  the robust 98th percentile, and now recorded in the sidecar beside the
  data's true range.
- `demo_shAnalysis` routes its fourteen map panels through one local
  helper that draws with geoMap or says the panel was skipped. A demo
  that silently degrades to a lesser picture teaches the wrong thing.

### Added
- `shLowLevel.requireGeoMap` - the ONE place that checks for geoMap, so
  the dependency has one spelling and one error message, and a future
  drawing entry point cannot invent a third way of failing. The message
  shows how to draw the numbers without geoMap. The dependency is
  **checked, not required**: shAnalysis still runs on base MATLAB with
  no toolboxes, and only the two drawing entry points need it.
- `shLowLevel.writeFrames` - a video container written from ready-made
  RGB frames, with no graphics at all. This split is why CI still tests
  codec selection, extension validation, frame rate and the provenance
  sidecar: those are the parts that have bitten before, they never
  needed a renderer, and folding them in with the drawing would have
  taken them out of the suite along with it.
- **`tools/dev/no_map_renderer.py`, wired into CI.** Deleting a renderer
  is a one-line commit; keeping it deleted is a gate. The coastline
  check is universal and has no exemptions - run against the retired
  file it fires three times on the `coastlines`/`coastlat`/`coastlon` it
  loaded. The projection check is a secondary signal and cannot tell
  "names a projection" from "computes one", since both are quoted
  strings, so it is skipped for the short list of files that forward a
  name to geoMap; that list is the mechanism and is stated as such.

- `docs/apiExamples.json` - the committed example registry the suite
  executes - lost its `shLowLevel.plotSHMap` entry, and the `g.map` and
  `writeAnimation` entries are marked `run: false` with examples that
  show the current API. They need geoMap, which the CI machine does not
  have. `writeFrames` is registered as a runnable one in their place.
  This file is a second place documentation lives, and only CI saw that
  it had gone stale: the static gates read help text and HTML, not it.
- `tools/dev/mlint_lite.py` gained rule **R5**: a `name = value`
  argument before a `{:}` expansion in the same call. MATLAB requires
  name-value arguments to come last, so `f(a, Name = v, rest{:})` is a
  **parse** error - and a parse error inside a classdef takes the whole
  class down. Both `geo.map` call sites in this release were written
  that way, `shCoefficients.m` stopped loading, and forty unrelated
  tests failed in CI for one line. `mlint_lite` counts brackets and
  blocks; it does not parse MATLAB grammar, so it could not see this
  until it was told to look.

### Verified on hardware
The MATLAB bridge came back and the gap named below was closed. On the
acceptance machine (R2026a Update 4, geoMap 2.0.541), against a shadow
checkout of this branch: the v3.30 gradient identities, the v3.31 bridge
and latitude fix, `requireGeoMap`, `g.map`, `writeAnimation` and
`writeFrames` - **10 of 10**, with `g.map` returning a real geo.map
handle struct and `writeAnimation` writing a 166 kB video whose frames
geoMap drew.

**It found one defect that no static gate could have.** `writeAnimation`
reused one figure across frames, and `geo.map` fits the figure to the
map it drew while `clf` does not undo that, so the figure RATCHETED:
six successive draws of the same three grids came back 365, 387, 407,
424, 439 and 453 pixels tall, and the second frame failed the
preallocated stack. Pinning `Position` at the top of each iteration does
not help - `geo.map` resizes after it, to a different height each time
(364.6, 340, 386.9, 365). A fresh figure per frame is deterministic: 365
every frame, for different data. There is now also a named
`shLowLevel:writeAnimation:frameSizeChanged` instead of MATLAB's
`subsassigndimmismatch`, because frames of different sizes are not a
video and the reason should say so.

**The two runs cover different halves, and neither is redundant.** A bad
`shSeries` constructor call inside `testNoMapIsDrawnHere` itself passed
the 264-test acceptance run and failed CI: that test returns early when
geoMap is present, so everything past the early return executes only on
a machine WITHOUT geoMap. It was then reproduced here by taking geoMap
off the path deliberately, rather than by pushing and waiting.

### Notes
- **This is API-breaking for anyone drawing maps.** `g.map` now needs
  geoMap on the path and no longer takes the display options above;
  `shLowLevel.plotSHMap` is gone. `g.toGrid` needs no geoMap at all and
  hands over everything a figure needs, which is what the error message
  points at.
- **CI still cannot see the drawing**, and that has not changed: the CI
  machine has no geoMap, so it checks only that the entry points raise
  `shAnalysis:geoMapRequired`, that the animation refuses before writing
  anything, that the container mechanics pass and that the renderer
  stays deleted. The drawing itself is covered by the acceptance run
  above and by geoMap's own suite, and that split is now permanent
  rather than temporary.

## [3.31.0] - 2026-08-23 - the cartographic bridge, and a latitude that lied

### Fixed
- **`shCoefficients.synthesis` returned the CONVERTED latitudes.** With
  `LatType="geodetic"` it converted the input to geocentric, evaluated
  there - correctly - and then handed the *converted* values back as its
  `lat` output. A caller who fed that straight into a map drew a field
  against a coastline it no longer matched, and nothing in either
  toolbox could notice, because both sides were internally consistent.

  The size, computed independently and agreeing with the measurement
  made from the map side: **0.1924 deg = 21.4 km** north-south at +-45,
  0.1240 deg = 13.8 km at 70 N. On a global 17 cm sheet that is under a
  fifth of a millimetre and beneath the spherical approximation already
  in use. On a **regional** map 20 deg tall - Greenland, West
  Antarctica, the Amazon, which is what these fields are made for - it
  is **1.6 mm**, a systematic shift of the whole signal relative to the
  coast, in the direction a reader takes for a real geophysical offset.

  `synthesis` now returns the latitudes in the convention that was
  asked for. **This changes a return value**: code that relied on
  getting geocentric latitudes back from a geodetic call must convert
  explicitly with `shLowLevel.geodetic2geocentric`. The field itself is
  unchanged, and a test pins that.
- `shCoefficients.gradient` had the same defect in `info.lat`, freshly
  introduced in v3.30.0. It now reports the latitudes as given plus
  `info.latType`, so a mismatch can be refused downstream instead of
  drawn.

### Added
- **`shCoefficients.toGrid` and `shSeries.toGrid`** - the synthesized
  field together with what it is: `Units`, `LatType`, `Quantity`,
  `ProductType`, `Name`, `Epoch`, `Source`, `FieldKind`, `C00`, `Zmin`,
  `Zmax`, `Zmean`, `History`. Handover is then one line:

  ```matlab
  b = g.toGrid(lat, lon, quantity = "ewh", kn = kn);
  G = geo.grid(b.lon, b.lat, b.Z, Source = b.Source, Units = b.Units);
  ```

  `LatType` defaults to `"geodetic"` here, unlike `synthesis`, because
  coastlines are geodetic and a map is what this output is for. The
  choice is stated in `b.LatType` rather than assumed.

- **`FieldKind` is read off an identity, not guessed.** `C(1,1)` is the
  degree-0 coefficient: exactly 1 for a field normalised by GM/R that
  carries the total mass, 0 for a residual. So `"full"` and `"anomaly"`
  are facts about the coefficients, and anything in between is reported
  as `"unknown"` rather than decided. A **mass** quantity synthesized
  from a full field warns
  (`shCoefficients:toGrid:fullFieldAsMass`): measured, twelve GSM
  solutions meaned and synthesized to EWH give 1.16e7 m, which is the
  static field expressed as water, not a mass change - and which a
  symmetric colour scale renders as one flat colour. `Units = "m"` is
  true of both and distinguishes nothing.

- `Zmin`/`Zmax`/`Zmean` are carried as measured numbers rather than
  turned into a verdict. For `shSeries.toGrid` they span the **whole
  stack**, which is the fixed colour scale an animation needs: a
  per-frame scale shows the scale changing and the signal not.

- `shLowLevel.gridHandover` - the metadata assembly both bridges share,
  so the two cannot describe the same field differently.

### Changed
- `shLowLevel.kernelFactors` gained a third output, the quantity's
  **units**, set in the same `switch` case that sets its kernel. The
  unit belongs to the quantity; retyped by hand at a toolbox boundary it
  was one more thing a user could get wrong silently.

### Notes
- **Not verified on hardware.** The MATLAB MCP bridge was still
  unavailable; static gates, the independent latitude computation and CI
  only.
- The remaining item from the same measurement is **not** a defect in
  any file and is not decided here: `shLowLevel.plotSHMap`,
  `errorMap` and `resolutionMap` are a second cartographic renderer,
  roughly 690 lines, in two projections. Whether it is routed through
  the map toolbox, kept deliberately as a dependency-free quick-look and
  said so in its help, or kept silently, is Matthias's decision. Only
  the third option is certainly wrong.

## [3.30.0] - 2026-08-22 - north/east/up gradient of any quantity

### Added
- `shLowLevel.shSynthesisGradient` and the class method
  `shCoefficients.gradient`: the spatial gradient of any quantity
  `kernelFactors` knows, resolved in the local north-east-up frame, on a
  grid (`Mode="grid"`) or at scattered points (`Mode="points"`).
  The horizontal components come from the exact `dPbar/dphi` of
  `shLowLevel.legendreALFDeriv`; the up component from the quantity's own
  upward-continuation exponent.

  The motivating gap: the only vector field the toolbox could produce was
  elastic load deformation, and that is a vector because horizontal
  displacement carries `l'_n` - not because gradients were available. Any
  scalar quantity has a gradient; only one quantity had a deformation.

- `Units="perRadian"` returns `r` times the gradient in every component
  (`dQ/dphi`, `sec(phi) dQ/dlambda`, `dQ/d(ln r)`), which is what a
  lat/lon advection step consumes without a further metric factor.

### Changed
- `shLowLevel.kernelFactors` gained a second output, the radial exponent
  `p_n` in `f_n(r) = kernel_n (R/r)^p_n`, and its `Height` branch now
  uses it. The exponent was previously written down inside that branch;
  the gradient needs the same number for `d/dr = -(p_n/r) f_n`, and a
  second copy would be the same fact decided in two places.

### Notes
- **`up` is empty, not zero, for surface quantities.** `ewh`, `geoid`,
  `surface_density`, `bottom_pressure`, `deformation_up` and `none` have
  no radial law - an equivalent water height one kilometre up is not a
  smaller equivalent water height, it is nothing. `g.up` is `[]` and
  `info.hasUp` is `false`. Empty fails at the first use; a NaN field
  would be plotted. `Height` is refused for the same quantities and for
  the same reason, by the same test.
- **The declared contract is "exact derivative of `shSynthesis` under
  identical options"**, so the defaults match `shSynthesis` (`quantity`
  `"geoid"`, `nmin` 0) and `testCorrectness` differentiates
  `shSynthesis` itself rather than a second model of it. Arrows drawn
  over a map that was truncated differently are arrows over the wrong
  picture, and no other test would see it.
- `east` is `NaN` at `|lat| = 90`. Without the guard the `cos(phi)`
  division returns a finite, meaningless number - confirmed in the
  Python pre-validation, which printed exactly that.
- Python-validated before implementation
  (`tools/dev/validate_gradient.py`): all three components against
  5-point finite differences of an independent scalar synthesis at
  1e-12, the identities `d(potential)/dr = -gravity_disturbance` and
  `d(gravity_disturbance)/dr = -gravity_gradient_rr` at 4e-16, and
  single-coefficient closed forms at 2e-16. The first run failed at
  2.9e-1 on `north` only - a doubled `sqrt(2)` in the Python model's own
  normalisation, visible only through the m/m+-1 mixing of the
  derivative stencil.
### Fixed (tooling)
- `tools/dev/make_apiref.py` wrote the regenerated API reference to
  `/tmp/shx_git/html/apiReference.html` - a clone location from an
  earlier session, i.e. outside the tree being built. It now derives the
  path from `SRC`, like every other path in that file. Nothing in the
  repository was wrong; the next person to regenerate the reference
  would simply have found it unchanged and not known why.

### Notes (continued)
- **Not verified on hardware.** The MATLAB MCP bridge was unavailable
  this session; everything here rests on the static gates, the Python
  pre-validation and CI.

## [3.29.0] - 2026-08-20 - mean over a user-given period; two sigma/selection fixes

`shSeries.mean` gains `Range=` (decimal years or datetime) and a second
estimator. `Estimator="model"` fits bias/trend/annual/semi-annual
(+`Periods`) inside the window with the reference epoch at the window
centre and returns the exact time integral of that fit, which collapses
to `bias + sum_k s(P_k)*cos_k` with `s(P) = sin(pi*D/P)/(pi*D/P)` - for
a whole number of years `s = 0` and the period mean is the trend line at
the centre. The second output reports coverage, largest gap, centroid
offset and the applied attenuation. Voronoi time-weighting was tested
and rejected (never won; 4x worse across the 2017-2018 gap) -
tools/dev/validate_meanperiod.py holds the measured table.

Two fixes found while reading the code for this:

- `mean` divided the temporal scatter by `nEpochs` instead of by the
  number of VALID epochs per coefficient, understating the sigmas of
  every series holding NaN months (4.3% for 3 of 36). Coefficients with
  fewer than two valid epochs now return NaN rather than the `std` of a
  single sample, which is 0.
- `select([t1 t2])` is resolved as INDICES whenever both values are
  valid indices - true for `[2004 2010]` on any daily series longer than
  2010 samples, i.e. under six years, and silent. `select(Range=[t1 t2])`
  is now the unambiguous form, and the positional shorthand warns
  (`shSeries:ambiguousRange`) when it resolves an index pair that would
  also have been a plausible window.

The old help promised "sigmas RSS/T when present", which was never
implemented; it now describes what the code does.

## [3.28.0] - 2026-08-18 - guide chapter 27 (Kalman/VAR); kalmanChain Structure

Guide gains the self-contained Kalman/VAR chapter with two computed
figures: the measured VAR order/structure holdout table, and a live
run on the acceptance machine (degree-RMS attenuation 0.95->0.52 over
n=2..40, data contribution 0.93->0.63) - plus the honest note that an
11-deg basin average changes 2% RMS only on monthly data (daily is
the target regime). kalmanChain passes Structure= to estimateVAR and
builds the orderblock partition itself. README/kalman.html updated;
references renumbered (28).

## [3.27.1] - 2026-08-18 - fetchITSG accepts Months arrays again

The no-selection gate crashed on 1 x K string Months (array logical in
&&), hit live by the starter level of setup(Download="all"). Two sites carried the pattern (no-selection gate and the
"all"-detection); the first fix missed the second and the machine
rerun caught it before CI ever saw the branch. Both fixed; offline
regression test with a local BaseURL covers the
array path and both loud empty-selection forms. Diagnosed from the
failure label and skip counts of the user's summary struct.

## [3.27.0] - 2026-08-18 - Download="all" (BREAKING: FetchITSG removed)

setup_shAnalysis gains the fifth cumulative download level "all":
starter + the complete ITSG monthly archive at Nmax, resumable. The
misunderstood v3.0.0 FetchITSG option is removed - it was an earlier
request for exactly this, delivered as a bolt-on instead of a level.
Callers using FetchITSG= now get MATLAB:TooManyInputs (measured on
R2026a). DryRun plan, help, setup.html and the contract test updated;
cumulative plan and the error ID verified on the acceptance machine
before commit.

## [3.26.3] - 2026-08-18 - fixtures leave the repository

tests/test_data removed from main; CI consumes the orphan branch
'testdata' (step live since #71), machines use SHX_TESTDATA_FOLDER.
Current-state doc claims updated; historical release notes untouched.

## [3.26.2] - 2026-08-18 - packaged sample-data resolver

The acceptance run with fixtures only on the data drive exposed the
gap in v3.25.0: readDDK's "DDK3" name form and two demo loaders
resolve the shipped samples from toolbox code, which cannot depend on
tests/. New shLowLevel.testDataDir carries the env/pref/fallback
order; readDDK, demo_shAnalysis and tests/shxTestDataDir (now a thin
delegate) share it. One acceptance failure -> zero.

## [3.26.1] - 2026-08-18 - CI fixtures from the orphan branch

Fixtures now live on the orphan branch 'testdata' (20 files, 11 MB,
no history); CI checks it out into tests/test_data before the suite.
The step is idempotent against main still carrying the folder, so the
in-repo copy can be deleted in a later commit without coordination.
Tooling only.

## [3.26.0] - 2026-08-18 - structured VAR estimation

estimateVAR gains Structure="diagonal"|"orderblock" (block-wise
Yule-Walker, structure-consistent Q and Sigma0, loud Blocks
validation). Driven by the first live VAR-order table (ITSG monthly,
36-month holdout): the dense estimate overfits at monthly sample
sizes while order-block (best, 3.268e-12, stationary) and diagonal beat
climatology-only by 21-23%; p >= 2 explodes. Numbers re-measured
through the shipped estimator on the acceptance machine (a first
run through the API also caught a column-vector bug in the Blocks
partition check that the synthetic row-block test had missed). Order=1 and Structure="full" defaults confirmed/kept
for the daily target regime; monthly guidance documented in the help.
Python S1-S3 checks + one MATLAB test covering shape, values, loud
errors, and the short-sample ranking.

## [3.25.0] - 2026-08-18 - relocatable test fixtures

New tests/shxTestDataDir: SHX_TESTDATA_FOLDER env var, then the
TestDataFolder preference, then the in-repo tests/test_data fallback.
All direct fixture paths in the suites route through it; new
setup_shAnalysis option TestDataFolder (env + setpref, like
SeriesFolder). Removing the fixtures from the repository itself
remains a separate decision: CI consumes the in-repo copy until a CI
data source (e.g. a release-asset download step) exists.

## [3.24.1] - 2026-08-18 - gate hardening: mlint_lite R5

New static rule R5 in tools/dev/mlint_lite.py: name-value structs of
arguments blocks must be the last input on the function line
(MismatchBetweenBlockAndLine otherwise). Motivated by the one defect
that escaped this session's gates; the broken v3.24.0 rtsSmoother now
trips the rule (regression-checked against that exact commit). Repo
sweep of all 143 .m files: clean. Tooling only.

## [3.24.0] - 2026-08-18 - fixed-lag smoother

rtsSmoother gains Lag=L: bounded-latency smoothing for NRT-style daily
production (definition-true windowed backward recursion, O(T*L)).
Lag=0 == filter, Lag >= T-1 == full RTS to rounding; identical through
memory and matfile stores (all unit-tested); error-vs-lag decay
Python-measured. Completes this session's Kalman-module program:
QC (3.21), Joseph update (3.22), multi-center (3.23), fixed lag (3.24).

## [3.23.0] - 2026-08-18 - multi-center Kalman chain

kalmanChain neq mode accepts several SINEX folders (one per center),
clusters files into epoch groups and combines each group with
neqCombine (per-epoch VCE, or fixed NeqWeights) before the Kalman
update; rep.sigma2 reports the per-epoch variance factors. New test
with two synthetic centers (identical files -> equal factors) plus a
single-folder run pinning the v3.20 snx.epoch wiring end to end.

## [3.22.0] - 2026-08-18 - Joseph-stabilized solution update

kalmanFilter's solution-mode covariance update moves to the Joseph
form: exact-arithmetic identical (all equivalence tests unchanged),
six orders of magnitude more accurate when R is small against the
prior (measured against a 50-digit mpmath reference; the decision was
made on that A/B, not on textbook habit). New discriminating MATLAB
test: wide-spectrum prior vs harsh R must match the NEQ information
form to 1e-9 - the old update fails at ~1e-6.

## [3.21.0] - 2026-08-18 - innovation-based quality control (Kvas 3.3)

kalmanFilter/kalmanChain gain QC="flag"|"reject": per-epoch chi-square
innovation test (solution and NEQ form, algebraically identical when
N = R^-1); rejected epochs become prediction-only so blunders never
enter the recursive state. New base-MATLAB shLowLevel.chi2Quantile
(Wilson-Hilferty) with measured accuracy map. Python pre-validation
tools/dev/validate_kalman_qc.py Q1-Q4 (statistic calibration E[T]=dof,
NEQ==solution identity, blunder detection); three MATLAB tests with
scipy-pinned quantile references.

## [3.20.0] - 2026-08-17 - neqCombine (NEQ-level VCE combination)

shLowLevel.neqCombine combines normal equations before solving
(COST-G style) with Foerstner variance components and asserted
redundancy invariant; accepts readSINEX NEQ structs directly.
readSINEX gains the +SOLUTION/STATISTICS parse (snx.stats) and finally
delivers the long-promised snx.epoch (decimal year from REF_EPOCH) -
closing a latent kalmanChain NEQ-mode crash. Python pre-validation in
tools/dev/validate_neqcombine.py (5 checks); four new MATLAB tests
including a synthetic-SINEX end-to-end run through neqCombine.

## [3.19.0] - 2026-08-17 - matfile covariance store

kalmanFilter/rtsSmoother/kalmanChain gain StoreCov="matfile": full
covariances stream through a v7.3 MAT with partial I/O instead of RAM,
making long daily Kalman runs (n40, a year: ~16 GB) feasible on
ordinary machines. Bit-identical to the in-RAM path (unit-tested
through filter and smoother, including a gap); explicit file-ownership
contract (filter's caller deletes; the smoother only reads; the chain
cleans up its internal temp in both branches).

## [3.18.0] - 2026-08-17 - buildCondFun (Kvas covariance conditioning)

shLowLevel.buildCondFun builds the estimateVAR CondFun after Kvas
(2019) Sec. 2.4: exact spectral<->EWH round trip on the Gauss-Legendre
grid (identity at psi0=Inf, unit-tested to 1e-10), land/ocean-style
region-block masking (eq. 2.117) and the exp(-psi/psi0) distance taper
(eq. 2.120). PSD preserved by the Schur product theorem; a
rank-deficient empirical Sigma(0) becomes strictly PD (the Yule-Walker
stabilization of his Fig. 2.5). Python pre-validation in
tools/dev/validate_condfun.py (4 checks). Three new MATLAB tests.

## [3.17.0] - 2026-08-17 - Kalman/VAR module (Kurtenbach/Kvas)

Temporal smoothing of SH series after Kurtenbach (DGK C-683, 2012) and
Kvas (TU Graz, 2019): estimateVAR (Yule-Walker VAR(p); p=1 == Kurtenbach
closed form), kalmanFilter (solution and SINEX-NEQ information-form
updates, gap handling, data-contribution diagnostics), rtsSmoother
(exactly the joint least-squares adjustment under the stationary
initialization - unit-tested to machine precision), and the single point
of access kalmanChain. Python pre-validation in
tools/dev/validate_kalman.py (8 tests). New doc page html/kalman.html.

## [3.16.2] - 2026-08-13 - final documentation audit

Guide Part IV input tables gain a description column (881 arguments,
100% coverage after completing demo_shAnalysis).

## [3.16.1] - 2026-08-13 - CoastBufferKm default 300

Author decision on the live 6e table: the 300 km Chambers-style
coastal buffer becomes the oceanChain default (baseline +1.557 mm/yr,
in the published band); CoastBufferKm=0 reproduces the old numbers.

## [3.16.0] - 2026-08-13 - uniform fetch layout (BREAKING)

fetchSINEX -> fetchITSGSINEX; uniform on-disk layout: temporal
products under series/ (series/itsg/*, series/icgem/*, series/GAX/*),
static models under static/. fetchGAX dest now optional. Fetchers
warn once on pre-v3.16 data locations instead of re-downloading
silently - move old folders (itsg_series, itsg_daily, itsg_sinex,
itsg_background, icgem/) into the new layout. run_vdk_series fixed
(fetch rename + a latent version-helper typo caught by the first
bridge run).

## [3.15.1] - 2026-08-13 - guide: complete theory edition

Part I now starts from zero (chapter 0: mission, products, vocabulary)
and covers everything through v3.15 (chapters 21-26: VDK theory,
SINEX/normal equations, ocean chains, coastal leakage incl. the
one-step warning, hydro indices, daily NRT), plus a full reference
list and four computed theory figures from the validated experiments.

## [3.15.0] - 2026-08-13 - coastal-leakage controls

oceanChain gains CoastBufferKm (great-circle mask erosion; 300 km
cuts 54% of the gauss445 coastal leak, measured) and
RemoveLandLeakage (one-step forward modelling of all outside-mask
sources before the filter; >60% leak-bias reduction with 5%
ocean-mean fidelity in the CI experiment). Defaults off until the
machine acceptance re-baselines the published barystatic trend.

## [3.14.0] - 2026-08-13 - flood/drought indices

hydroExtremeIndex: GRACE-DSI with USDM-style categories, WSDI, and
the causal Reager storage deficit (full FPI with a precipitation
grid) - per grid cell or basin. Detrend policy and robust-sigma
behaviour quantified by pre-validation, not assumed.

## [3.13.0] - 2026-08-12 - VDK/VADER decorrelation

vdkApply implements Horvath et al. (2018) on the ITSG monthly SINEX
normals (fetchSINEX/readSINEX), signalVarianceKaula estimates the
cyclostationary signal model with an exact log-chi-square bias
correction, and run_vdk_series.m is the resumable batch driver for
the full-series run on another machine. tvANS relation documented:
same Wiener family, different inputs - formal monthly N vs empirical
stationary structure.

## [3.12.0] - 2026-08-12 - fetch family: SINEX and ITSG background

fetchSINEX (ITSG monthly normals, the only public per-month SINEX;
months required, one month ~460 MB) and fetchITSGBackground (monthly
background-model means, era-dependent palettes verified live; not the
AOD1B GAX split). Consistent naming across the family; one shared
robust download loop (fetchFileSet) and shared month validation.

## [3.11.0] - 2026-08-12 - obpChain, residual circulation separation, fetch fallback

obpChain delivers GravIS-style bottom-pressure fields (GSM + GAD,
GravIS filter order and reference window, land NaN) - one GAA step
apart from the barystatic oceanChain. eofSeparate splits residual
ocean circulation from noise (weighted EOF + North rule,
Python-prevalidated with the Marchenko-Pastur separability limit
stated); oceanChain gains SeparateCirculation=. httpFetch falls back
to websave on transport-level failures only. GAD filter-order note
documented; machine acceptance script shipped for the next bridge
session.

## [3.10.1] - 2026-08-12 - fetch robustness (ICGEM 429)

fetchGAX hardening: consecutive-failure cap, polite inter-download
pause, single capped retry on HTTP 429. Root cause of the bridge
hangs identified: ICGEM rate-limits bursts and httpFetch honoured the
server's Retry-After so faithfully that calls outgrew the tool window.

## [3.10.0] - 2026-08-12 - fetchGAX, full ocean restoration, API completeness

fetchGAX downloads the AOD1B GAA/GAB/GAC/GAD monthly means from the
GFZ ICGEM pages (2002 on, centre-independent). oceanChain gains the
GAAFolder ocean-mean subtraction completing the Chambers & Willis
(2010) restoration, with epoch coverage reported. API tables: blank
argument descriptions 616 -> 0 (convention lexicon as final pass +
26 functions with new help lines); chains_flow now shows all four
lanes including the fetchGAX feed.

## [3.9.0] - 2026-08-12 - oceanChain, Slepian application, gfc dot terms

oceanChain delivers the barystatic ocean-mean series (+1.49 +/- 0.02
mm/yr, +312 Gt/yr on COST-G RL02.1 with the ICE-6G_D ocean-floor GIA
lever of +0.89 mm/yr measured); the ocean mean is filter-invariant to
0.01 mm/yr and sigMon 0.0121 m is the honest post-separation noise
proxy. slepianProject adds the application half of slepianBasis
(cross-validated against an independent Python quadrature). ICGEM
'dot' secular lines are read as 'trnd' synonyms via the line parser.

## [3.8.10] - 2026-08-12 - NV convention, quantity "none", setup preferences

Name-value casing convention codified (Capitalized canonical for
arguments-block options, lowercase for legacy inputParser names and
quantity strings) with a regression test pinning the case-insensitive
tolerance of both mechanisms. quantity "none" gives a dimensionless
passthrough (kernel 1, no GM/R/kn), retiring the GM=R=1 workaround.
setup_shAnalysis now persists SeriesFolder/MasconFile/GravisFolder/
DDKFolder via setpref('shAnalysis', ...) alongside the session SHX_*
env vars.

## [3.8.9] - 2026-08-12 - Retry-After fetchers, API tables, V9 additions

httpFetch/httpRetryDelay give every toolbox download Retry-After-aware
retries with capped exponential backoff (the GravIS 503 case); listing
reads retry with backoff. Opt-in tests accept setpref("shAnalysis",...)
preferences besides SHX_* env vars. Guide V9 gains the standardChain
flow diagram; API reference tables now always carry sizes (n x 1 /
n x m fallback) and merge descriptions from help Inputs/Options
sections (missing descriptions cut from 775 to ~120, rest on the
roadmap).

## [3.8.8] - 2026-08-12 - validated chains as methods

gravisL2B (shared GravIS Level-2B correction core) plus one-call
greenlandChain (-225.6 Gt/yr, 32 s), antarcticaChain (-125.7 + per-basin
table) and twsChain (amplitude ratio 1.001, trend RMS 0.032 cm/yr vs
GravIS) - the executed guide V1-V8 validations with exchangeable inputs,
provenance reports, TrendGrid= re-use for sensitivity studies, and a
user-supplied OceanMask for the sigma_trend policy (must be false over
land: a bare latitude band verifiably shifts the answer by 5 Gt/yr).

## [3.8.7] - 2026-08-12 - Antarctica + TWS validation

Guide chapters V7/V8: the GravIS chain validated against Antarctica
(-125.7 vs AWI -146.9; the 14% is the map-estimator-vs-joint-inversion
method distance, proven by a 0.905 difference-pattern correlation with
the official TUD kernel grid) and terrestrial water storage (eleven
river basins, amplitude ratio 1.001, trend RMS 0.032 cm/yr after GIA -
documenting that the GravIS TWS product carries a GIA correction its
Technical Note omits). evalMask rejects |lat| > 90 polygon vertices
(catches [lon lat] GeoJSON handed to the [lat lon] toolbox convention,
which used to build silent phantom basins).

## [3.8.6] - 2026-08-12 - audit fixes

Twenty findings from an independent adversarial audit, fixed with
regression tests. Highlights: readMascon no longer returns raw days as
decimal years on CSR files (case-insensitive attributes, loud time-unit
errors, name-based grid orientation); 22 shipped-fixture assumes are
verifies; the real-series science test now fails a sign-flipped trend;
shReadGFC warns on truncation/corruption; kernelFactors validates Love
numbers; leakageCorrect names NaN input instead of 'diverged';
fetchLoveNumbers reads headerless GROOPS columns; series names populate
for headers without modelname; sensitivityKernel's 2-16% claim is scoped
to its 1-D validation (2-D: 1-42%, ordering reversed; full-covariance
path confirmed and pinned); doc gate checks HTML structure; the GravIS
span (2002-04..2023-02, n=217) is pinned beside every 2.8%.

All notable changes to shAnalysis. The version line in `Contents.m`
(read by `shLowLevel.version` and MATLAB's `ver`) is the single source of truth.

## [3.8.5] - 2026-08-11

### Fixed
- `html/shAnalysis.html`, the page a user reaches from `doc shAnalysis`,
  announced **v3.0.0** - eight releases stale. Nothing caught it because
  the version gate only compared pages that already carried a version,
  and this one carried an old one in prose. It now has an explicit
  version stamp and `doc_sync_audit` checks it; a negative test confirms
  the gate fires when the two disagree.
- `NOTICE` listed the GFZ TN-13 fixture as `TN-13_GEOC_GFZ_RL06.3.txt`.
  It ships as `RL06_3.txt` - the same underscore/dot confusion that kept
  `testStandardChain` filtered out for four releases.

### Audited, no change needed
- Every `shLowLevel.*` function named in the README exists; every path
  it names exists or is documented as generated output.
- Every fixture listed in NOTICE is present (after the correction
  above).
- No dangling cross-references in the in-file help of the 84 package
  functions and 3 classes.
- Version strings agree across Contents.m, CITATION.cff, CHANGELOG.md,
  apiReference.html, the guide cover and the overview page.

## [3.8.4] - 2026-08-11

### Fixed
- `testStandardChain` had been silently SKIPPING since v3.1.0. It asked
  for `TN-13_GEOC_GFZ_RL06.3.txt`; the shipped GFZ fixture spells the
  release with an underscore (`RL06_3`), unlike the CSR and JPL ones.
  The `assumeTrue` guard turned that typo into a filtered test, which in
  the summary looks exactly like a passing one - so the canonical
  pipeline entry point went unverified through four releases and every
  CI run. The fixture checks are `verifyTrue` now: a missing fixture is
  a failure, not a shrug. An audit of every fixture filename referenced
  in the suite found no other case.
- With the test running for the first time, CI immediately found an
  assertion inside it that had never been exercised: the GIA epoch check
  demanded `RelTol 1e-10` on a value that survives a gfc write/read
  round trip. Epochs are stored as decimal years in text, so the
  observed agreement is 5.3e-10 - the format's precision, not MATLAB's.
  Relaxed to 1e-8, which still catches any real error in the GIA
  scaling (those are of order 1 in relative terms). Nothing wrong with
  `standardChain` itself.

### Checked, not changed
- The workflow guide's demo-gallery figures were carried on the roadmap
  as "Edition-2 placeholders". They are not: all ten are real rendered
  figures from real data (the ITSG month, the DDK3 Wbd binary, the
  GRACE-FO minus GRACE difference), and all ten are present in
  `tools/dev/guide_assets/`. The roadmap entry was stale, like the
  COST-G SINEX fetcher removed in 3.8.1. Removed.

## [3.8.3] - 2026-08-11

### Added
- `setup_shAnalysis` gained `SeriesFolder=` and `MasconFile=`, which
  export `SHX_SERIES_FOLDER` and `SHX_MASCON_FILE` for the session and
  report them in `summary.testData`. Until now those variables were
  mentioned only inside the test files that read them, so nobody would
  have found them.
- The workflow guide gained an **Installation and data** chapter
  covering setup, the download levels, the persistent data folder, and
  both opt-in variables with a table of where the data comes from. Also
  documented on the setup page and in the README.
- `DryRun` reports what it *would* set without calling `setenv`, and a
  path that does not exist warns rather than failing silently.

### Notes
- Both variables are optional. Without them the suite runs complete and
  the two tests report as FILTERED, not as passing - the distinction
  matters, because a silently skipped test looks like a green one.
- `SHX_SERIES_FOLDER` is deliberately NOT wired to the persistent data
  folder: a routine acceptance run must never reach for a network or
  archive drive, so pointing at that data stays an explicit decision.
- MATLAB was unavailable for this change, so it is verified by the
  static gates and CI only.

## [3.8.2] - 2026-08-11

### Added
- Opt-in test of `readMascon` against a REAL mascon product, via
  `SHX_MASCON_FILE`. Verified on the JPL RL06.3Mv04 CRI file (0.5 deg,
  257 months, 46 MB), which reads correctly in 0.8 s.
- The test checks GEOGRAPHY, not dimensions. The synthetic fixture
  writes `lwe_thickness(lon, lat, time)` while the real JPL file writes
  `(time, lat, lon)` - a size check passes either way, and a transposed
  grid would sail through it. Greenland must LOSE mass over the GRACE
  era: measured -124 cm between 2003 and 2024, with the largest change
  at 76 N / 291 E (northwest Greenland), which is the right place.

### Documented
- The verified JPL layout, and that the reader permutes whatever order
  it finds to (lat, lon, time).
- Mascon latitudes are conventionally GEODETIC while this toolbox
  synthesises on GEOCENTRIC ones. The difference peaks near 45 deg at
  0.19 deg - about 21 km, or 0.4 of a 0.5-degree mascon cell. The help
  said "typically geodetic" before; it now says what that costs and
  where to convert.

## [3.8.1] - 2026-08-11

### Changed
- README rewritten. It still described `compat/` and `tests/legacy/`,
  both removed in v3.0.0, and its newest feature section was "New in
  v2.5" - nine releases behind. It now describes the current toolbox,
  the six documentation gates, the GravIS validation result, and a
  table of where each data source actually comes from. Cut from 404 to
  ~175 lines: the per-release history belongs in the CHANGELOG, which
  has it.

### Removed from the roadmap
- **COST-G SINEX fetcher.** There is no such source to fetch from.
  COST-G combines on the normal-equation level internally and publishes
  the combined SOLUTIONS through ICGEM, but does not distribute
  per-month SINEX normal equations or covariance matrices as a public
  product; Dahle et al. (2025) state that the variance-covariance
  information is not available for the combined solutions. The roadmap
  item traced back to a v2.5 note recording an AIUB 503 during a
  download attempt - a retry reminder that had hardened into a planned
  feature. For a full covariance use ITSG, which does publish monthly
  SINEX normal equations, or the GravIS VDK-filtered Level-2B products
  when the filtered result is what is wanted. Documented on the
  readSINEX page.

## [3.8.0] - 2026-08-11

### Added
- `shLowLevel.makeTutorials` (roadmap item 10): writes one Live Script
  per demonstration case into `tutorials/` - set up the path, run the
  case with figures visible, and point at the topic page and workflow
  guide. Open, press Run, change something.
- They are GENERATED from the demo registry, not hand-written.
  `demo_shAnalysis` is the single source of truth for what the toolbox
  demonstrates; a parallel set of curated tutorials would drift from it
  within a release, and `.mlx` is a binary zip, so the drift would not
  even show in a diff. Each tutorial says so in its own footer.
- Conversion to `.mlx` uses `matlab.internal.livecode.FileModel`, an
  internal API that is not in every release. When it is missing the `.m`
  files are still written - they are the useful artefact either way -
  and a warning explains the manual Save As route.
- New topic page `tutorials.html`, reachable from the Help browser.

### Fixed
- CI now sets `timeout-minutes` on the job (20) and on the MATLAB setup
  step (8). That step hung four times in one session, taking 5-10
  minutes against its usual 1.2 and each time needing a manual cancel.
  It now fails fast and visibly instead of sitting pending.

### Note
- Two bugs the acceptance machine caught in the generator:
  `repmat("x", 1, 40)` builds a 1x40 STRING ARRAY rather than a
  40-character string, so the padding trick that works for char produced
  a non-scalar file name; and `demo_shAnalysis("list")` PRINTS the case
  table as well as returning it, which would have spammed every
  generator run and every test.

## [3.7.0] - 2026-08-11

### Added
- `shLowLevel.sensitivityKernel`: a basin kernel that trades leakage
  against propagated GRACE noise explicitly (Swenson & Wahr 2002 - the
  construction behind the ESA CCI and GravIS gridded ice products),
  rather than by choosing a filter radius and hoping. Minimises
  leakage + Alpha * noise SUBJECT TO unit response over the basin,
  closed form via one Lagrange multiplier. No iteration and no stopping
  criterion, which is exactly its advantage over `leakageCorrect`:
  nothing about the answer depends on where you stop.
- Sweep `Alpha`, plot `info.leakage` against `info.noise`, take the
  L-curve corner. `Noise` accepts a full covariance, a sigma vector, or
  falls back to a degree-dependent default; a real covariance is what
  makes the kernel *tailored* rather than merely smoothed.

### Notes on getting it right
- The UNIT-RESPONSE CONSTRAINT is what makes the result an average.
  Without it the cheapest way to cut noise is to shrink the kernel
  towards zero: during development `info.gain` fell to 0.28 at
  Alpha = 0.1 and 0.001 at Alpha = 100, i.e. the "optimal" kernel
  measured almost none of the basin it was averaging - and the
  comparison against a Gaussian came out backwards for that reason.
- Measured benefit over a Gaussian at matched noise AND matched gain:
  **2% to 16%** less leakage across plausible far-field weightings.
  The largest margin comes with a high-degree weighting, which is not
  the intuitive ordering. The help says so rather than quoting a
  headline number.

## [3.6.0] - 2026-08-11

### Added
- `shLowLevel.estimateDegree1`: geocentre coefficients (C10, C11, S11)
  estimated from GRACE itself plus an ocean model, following Swenson,
  Chambers & Wahr (2008) - the method both GravIS and geogravL3 use.
  This removes the dependency on somebody having published a TN-13
  series for your exact Level-2 product and release, and guarantees the
  degree-1 terms are consistent with the solutions actually processed.
  The output struct matches `readTN13` exactly, sigmas included, so it
  drops into `addDegree1` unchanged. `kn` is required: degree-1 load
  Love numbers are frame dependent and are never assumed.
- Python-validated (`tools/dev/validate_degree1.py`): exact recovery of
  a known geocentre from a synthetic land/ocean world, 1.5-4% error at
  2 mm noise, a demonstrable bias when the ocean model is omitted, and
  a rising condition number on a degenerate ocean domain.

### Notes on three things the acceptance machine caught
- A CONSTANT nuisance column is carried beside the three patterns. The
  ocean residual generally has a degree-0 component (the observed field
  is degrees 2+, and any mass imbalance between data and ocean model is
  an offset), and without a constant to absorb it that offset lands on
  C10, which has a large ocean mean: a **153% error** before the fix.
- The design matrix is column-equilibrated before `cond` is reported.
  The constant column has a completely different scale from the basis
  patterns, so an unscaled condition number reports the units rather
  than the geometry - 3.8e7 on a problem whose geometry is fine. After
  equilibration: 1.3 for a global ocean, 58 for a polar-only one.
- `addDegree1` REQUIRES sigma fields, so the first version was not the
  drop-in its own help text claimed. Formal sigmas now come from the
  ocean-fit residual propagated through the least-squares solution.

## [3.5.2] - 2026-08-11

### Fixed
- `leakageCorrect` gained `ResidualRegion=` (default: the `Mask`). The
  discrepancy principle added in 3.5.0 measured the residual GLOBALLY,
  and with a regional mask that can never reach the noise level: the
  model describes one region while the data contains Antarctica,
  Alaska and global hydrology. On the GravIS Greenland case the
  residual was 0.0085 globally against 0.0008 near the mask, with a
  noise level of 0.0024 - so the principle silently never fired and
  every run stopped at `MaxIter`. `info.residualRMSGlobal` now exposes
  the gap; a large one means unmodelled signal elsewhere.

### Measured
- The GravIS Greenland comparison, rerun with a real stopping criterion:
  **-224.6 Gt/yr** against a published -231.1, i.e. **2.8%**. This
  replaces -227.4 (1.6%), which came from stopping at an arbitrary
  iteration count. The closer number was a coincidence of where the
  iteration happened to be; a result that depends on an arbitrary
  choice is not a result.
- The noise level must match the quantity being inverted. The
  open-ocean RMS of a TREND field is 0.0024 m/yr, but most of that is
  real barystatic sea-level rise, not error - using it stops after 4
  iterations and gives -201.0 Gt/yr, 13% low. The trend's noise is the
  monthly noise propagated through the fit, sigma_monthly / sqrt(Sxx) =
  0.0115 / sqrt(8353) = 0.000125 m/yr, nineteen times smaller. That
  stops at 82 iterations and gives the -224.6 above.

## [3.5.1] - 2026-08-11

### Added
- `shLowLevel.oceanRMS`: area-weighted RMS of a field over the OPEN
  ocean - ocean points more than `MinDistanceKm` (default 1000) from the
  nearest non-ocean point. Far from land a GRACE field should contain
  almost no real signal, so what remains is error; this is the standard
  noise metric processing centres quote, and the value `leakageCorrect`
  needs for `NoiseLevel`. Without it, v3.5.0's discrepancy principle had
  no natural input.
- The ocean mask is USER-SUPPLIED, deliberately. Base MATLAB's
  `coastlines` data set is not present in every installation (it is
  absent on the acceptance machine, which is why `plotSHMap` carries a
  fallback), and a wrong mask silently changes the number.
- Area weighting is on by default: an unweighted RMS over a lat/lon grid
  over-counts the polar rows. On white noise the weighted and unweighted
  values agree, which is exactly why the difference goes unnoticed until
  the field has structure - the test pins both cases.
- Python-validated (`tools/dev/validate_oceanrms.py`): the erosion moves
  the boundary by exactly d/R against an analytic spherical cap, and the
  weighted mean of cos^2 over the sphere comes out 0.6666 against 2/3.

## [3.5.0] - 2026-08-11

### Fixed (correctness of a shipped result)
- `leakageCorrect` solves an ill-posed inverse problem and therefore
  SEMICONVERGES: the error against the truth falls, reaches a minimum,
  then rises as the iteration begins to fit noise - while the residual
  keeps shrinking. The previous stopping rule chased a small solution
  step, which is exactly wrong. Measured on the reference problem
  (`tools/dev/validate_stopping.py`): the final solution is **361x**
  worse than the best one, `Tol = 1e-3` stops **89x** past the optimum,
  and the shipped default `Tol = 1e-4` never triggers at all.
- `NoiseLevel=` enables the discrepancy principle (Morozov): stop once
  the residual reaches the noise level of the data, since fitting more
  closely than the noise is fitting noise. It lands within 2% of the
  optimum. `Tau=` (1.2) is the safety factor; 1.2-1.5 is best, 1.0
  slightly overfits. The natural estimate for `NoiseLevel` is the
  open-ocean RMS of the field, which is what processing centres use.
- On a noisy version of the reference disc, verified on the acceptance
  machine: the discrepancy principle stopped after 2 iterations and was
  **4.3x closer to the truth** than the unregularised run, which took
  239.
- `info.stoppedBy` ("discrepancy" | "step" | "maxIter" | "zeroField")
  plus `residualRMS` and `noiseLevel` make the regularisation state
  inspectable. Without `NoiseLevel` a warning states that the result
  depends on `MaxIter`.

## [3.4.1] - 2026-08-11

### Documented
- The GravIS Greenland comparison closes to **1.6%** once the filter is
  declared correctly. Dahle et al. (2025, Sect. 2.2.1) specify the
  basin-average method: spectral masking, then a Wiener optimal filter
  approximately equivalent to a Gaussian of 4 deg latitude half-width,
  then conversion to surface mass, then least-squares adjustment. The
  forward model is filtered IDENTICALLY to the observations. The inputs
  are genuinely unfiltered Level-2B coefficients, so `Filter="none"`
  looked right and was not: declaring `Filter="gauss445"` moved the
  trend from -234.9 to -227.4 Gt/yr against a published -231.1, turning
  a 1.6% overshoot into a 1.6% undershoot. It also drifts less with
  continued iteration (2.0 Gt/yr over 300->900 steps against 2.5),
  because the filter regularises the inverse problem.
- The same paper specifies the mask: 1 until 200 km outside the
  grounding line, tapering to 0 by 600 km - `basinKernel(BufferKm=200,
  TaperKm=400)`, not a hard outline.
- **VDK**: it is DDK with the filter matrix rebuilt from each MONTH's
  formal error covariance, i.e. a per-epoch usage of `designFilter` with
  `Noise=`. What the toolbox lacks is the data, not the method - monthly
  full covariances are not distributed with Level-2 products, and for
  COST-G they are not available at all. Documented on the designFilter
  page with the two practical routes (GravIS VDK-filtered Level-2B
  products, or a SINEX normal-equation covariance). Note the GravIS ice
  basin averages do not use VDK at all.

## [3.4.0] - 2026-08-11

### Added
- `shSeries.removeAlias`: fits a tidal-alias harmonic (S2, 161 days by
  default) jointly with bias, trend, annual and semi-annual and
  subtracts only that harmonic - the correction GravIS applies to its
  Level-2B products. Across the GRACE/GRACE-FO boundary the nodal
  planes are not aligned, so a FIXED 100 degree phase offset applies to
  the later mission (Landerer et al. 2020). The offset adds no free
  parameters and ignoring it mis-estimates the amplitude badly
  (validated in `tools/dev/validate_alias.py`).
- Guide chapter "Validation against GravIS": the complete worked
  comparison against the published Greenland basin averages - the
  reference and why it must be recomputed over the span actually used,
  all four Level-2B corrections, the basin average, the results table,
  and what each step is worth.

### Measured
- Removing the S2 alias moves a twenty-year Greenland trend by
  **0.2 Gt/yr**, i.e. nothing: a 161-day harmonic is very nearly
  orthogonal to a linear trend over two decades. It remains a real
  correction for the monthly series. Recorded because it was expected to
  explain part of the residual gap and did not.

## [3.3.1] - 2026-08-11

### Fixed (documentation)
- `leakageCorrect`: the mask must cover EVERY region that can hold mass,
  not only the one being measured. A target-only mask tells the
  iteration that mass exists nowhere else, so neighbouring signal is
  forced into the target and the result is biased high. Validated
  against the published GravIS Greenland basin-average series (COST-G
  RL02, -231.1 Gt/yr over the matching span, all four GravIS
  corrections applied to the same Level-2 input):

  | mask | Gt/yr | vs published |
  |---|---|---|
  | none (naive grid integral) | -170.3 | -26% |
  | Greenland only | -259.8 | +12% |
  | union with Canadian Arctic, Iceland, Svalbard | -242.5 | +5% |

  The neighbours absorb -112 Gt/yr in the union solution, and it
  converges faster. No API change: `Mask=` already accepts any union -
  the error was in how it was used, which is exactly why it needed
  saying in the help rather than fixing in code.

## [3.3.0] - 2026-08-11

### Added
- `shLowLevel.readSHM`: the GRAVIS/GRACE SHM format - a YAML header
  followed by `GRCOF2` (a field) or `GRDOTA` (a rate in 1/yr) records,
  gzip transparent, GM and the reference radius taken from the header.
  GravIS Level-2B products - monthly solutions, mean fields, the
  ICE-6G_D (VM5a) GIA model - are a major public data source the
  toolbox could not read at all. A `GRDOTA` result feeds
  `standardChain(GIA=)` directly, which is what it always wanted.
  Python-validated first (`tools/dev/validate_shm.py`).
- Fixtures for both record types, and the GravIS Greenland drainage
  basin geometries, under CC-BY-4.0 with attribution in NOTICE.

## [3.2.2] - 2026-08-11

### Fixed
- `standardChain` stopped with "No TN-13 entry within 0.050 yr" whenever
  the correction tables trailed the solutions - which they always do,
  since TN-13/TN-14 are published weeks after the monthly fields. On a
  current 257-month ITSG series the two newest epochs were uncovered and
  the whole chain failed. Uncovered epochs are now dropped and the fact
  recorded in `rep.steps`; `OnMissing="error"` restores the old
  behaviour and `Tolerance=` is settable. Dropping beats the
  alternative of keeping them, which would splice UNCORRECTED months
  onto corrected ones - a step in the series exactly where people look
  for the newest signal.
- `shSeries.read` / `fromFolder` treated `writeGFC`'s
  `<file>.gfc.provenance.json` sidecars as solutions: the read pattern
  has to be loose enough for `.gfc.gz`, so `*.gfc*` matched them and a
  folder written BY the toolbox could not be read back BY the toolbox.
- `shCoefficients.write` gained `Sidecar=`, which only the low-level
  `writeGFC` had, so class-API users could not turn the sidecar off.

### Notes
- All three were found by running the toolbox against a full 24-year
  ITSG series (257 monthly n96 solutions, 2002-2026) rather than against
  fixtures. The suite is fixture-bound by necessity; the failures it
  cannot see are the ones that need real data of real length.

## [3.2.1] - 2026-08-11

### Added
- `tests/testScience.m`: regression against values published OUTSIDE the
  toolbox - WGS84 and GRS80 J2 from the defining constants, the Gegout97
  (PREM) load Love numbers including the CM-frame `k'_1 = 0`, the
  closed-form EWH kernel of Wahr et al. (1998) evaluated with the
  shipped Love numbers, the GRACE-minus-SLR C20 discrepancy, TN-13
  geocenter amplitudes for all three providers, and the Gaussian
  half-weight relation. The existing suites check that the code does
  what the code intends, and stay green if a formula is consistently
  wrong; these have somewhere to fail. Verified that the kernel test
  catches both a missing `rho_water` (factor 1000) and a `k_n` sign
  error.
- The trend regression is opt-in via `SHX_SERIES_FOLDER`, because a
  trend needs a monthly series that is far too large to ship. It
  deliberately does NOT read the persistent data folder, so a routine
  acceptance run never touches a network or archive drive.

### Fixed
- Test cleanups no longer throw from `onCleanup` destructors. `d =
  tempname` invents a NAME, so a test whose code path did not reach the
  `mkdir` left `rmdir` with nothing to remove: every CI log carried a
  destructor warning that MATLAB cannot attach to any test, and which
  can mask the real failure that ended the test early. All 30 sites now
  use `tests/rmIfFolder.m`, and one genuinely dead variable in
  `testRobustness` (a `tempname` that was never used for anything) is
  gone.

## [3.2.0] - 2026-08-11

### Added
- `shLowLevel.leakageCorrect`: iterative forward modelling of filter
  leakage and attenuation. Finds the mass field whose filtered image
  matches the observation, using only the filter - no external signal
  model. `Mask=` confines the solution to where mass can exist, which is
  both better conditioned and the variant that removes leakage rather
  than redistributing it: on a synthetic disc with an exact mask it
  recovers 0.9998 of the truth and leaves exactly zero outside.
- `shLowLevel.gridScaling`: per-pixel scaling factors from a model
  series pushed through the same chain. Amplitude-invariant to 1e-15 -
  the factors describe the model's PATTERN, not its scale.
- Both implemented and validated in Python
  (`tools/dev/validate_leakage.py`, a compact numpy SH port whose
  analysis/synthesis round trip is exact to 4e-16 and whose Gaussian
  weights match `shGaussianWeights` to 2.7e-11) BEFORE the MATLAB port.
  The validation caught two design errors before any MATLAB was written:
  a scaling test that was exact by construction and therefore validated
  nothing, and a test cap so large the filter barely touched it.

### Two contracts that are easy to get wrong
- Convergence is judged on the CHANGE OF THE SOLUTION, not the residual.
  A masked problem is inconsistent - no field confined to the region
  reproduces an observation with energy outside it - so the residual
  plateaus at a nonzero floor while the solution is converged. The first
  implementation stopped on the residual and reported failure on exactly
  the case the mask exists for.
- `gridScaling` returns NaN where the model carries no signal instead of
  a ratio of two numerical zeros, and `info.kMedian` summarises the
  pixels the model gives mass to. Over all finite pixels the median is
  dominated by pure-leakage pixels, whose `k = 0` is correct but is not
  the basin scaling factor anyone is looking for.

## [3.1.4] - 2026-08-11

### Added
- `shLowLevel.safeMove`: the `.part` -> target swap every fetcher ends
  with, now with verification and exponential-backoff retries
  (0.25/0.5/1/2/4 s). Windows antivirus and cloud-sync clients open a
  just-written file to scan it and hold it briefly; a plain `movefile`
  hits that window and reports a download failure for a file that
  downloaded perfectly. Each attempt checks that the destination exists
  and the source is gone rather than trusting the status flag, because
  synced and network volumes have been observed reporting success early.
  All six call sites in fetchICGEM (2), fetchITSG, fetchTN,
  fetchLoveNumbers and fetchDDK go through it.
- `shLowLevel:safeMove:locked` names the usual cause and the two fixes
  (exclude the data folder from on-access scanning, or move it off the
  synced drive) instead of surfacing a bare OS message.

## [3.1.3] - 2026-08-11

### Added
- `tools/doc_sync_audit.py`, a sixth quality gate, wired into CI before
  the MATLAB setup step. The five existing gates were all green while
  the API reference listed 5 of 12 `fetchICGEM` options, eleven help
  pages were unreachable from the Help browser, the v3.1.1 tag reported
  3.1.0 and the guide advertised a call that threw - none of that was
  detectable automatically. The gate checks doc snippets against the
  parsed contracts (including option VALUE types, which is the class a
  name-only check misses), API-reference freshness, `helptoc.xml`
  reachability, version consistency, help placeholders and defaults, and
  a narrative-coverage floor. Every check is verified by deliberately
  breaking the repository and confirming it fires.
- `tools/dev/README.md`: gate order, regeneration order, the SIGPIPE
  trap, and the guide-asset recovery note.

### Fixed
- `fetchITSG` help claimed `Nmax (96)` unconditionally. The default is
  NaN, which resolves to 96 for monthly and 40 for daily solutions, and
  120 is also accepted for monthly - the help listed neither.
- `seaLevelFingerprint` documented `Tol` as `1e-8 * |eustatic|`, mixing
  the option's value with its effect; the default is 1e-8 and the
  tolerance is relative.
- `vceRescale` help wrote `round(2/3*Lmax)` where the arguments block
  says `round(2/3 * idx.Lmax)`.
- `shCoefficients.mtimes`/`uminus` and `shClimatology.withNote`/
  `fromCoef` were documented only in the generated API reference.

## [3.1.2] - 2026-08-11

### Added
- Narrative documentation for the v3.x features that existed only in the
  generated API reference: new help pages `standardChain.html`,
  `designFilter.html` and `icgemSeries.html`, plus sections for
  `poleTideConvert` (referenceSystems), `synthesisPoints` (shSynthesis),
  `listITSG` (fetchITSG) and `fetchLoveNumbers` (readLoveNumbers). All
  reachable from `helptoc.xml` (46/46 pages).
- Workflow guide Edition 5: the ICGEM time-series workflow and why
  `Mode="auto"` fetches one archive rather than 300 files, the standard
  chain and why its order is not negotiable, custom filter design, and a
  section on what real provider files actually contain (FORTRAN
  D-exponents, the ICGEM 2.0 column order, ragged record groups).

### Fixed
- The guide's figures were read from a container path that does not
  survive a session, so the PDF was not reproducible and `make_figs.py`
  could only regenerate 3 of the 10. The assets were recovered from the
  shipped PDF and now live in `tools/dev/guide_assets/` in the repo.
- 58 name-value options across 23 entities were "documented" as `see
  arguments block`: `help` showed nothing while the generated API
  reference showed size, type and default. All replaced with real
  descriptions; pinned to zero by `testHelpHasNoPlaceholders`.
- Four help defaults disagreed textually with their arguments blocks
  (`synthesisMatrix.NLat/NLon`, `tvANSFilter.VCEMinDegree`,
  `vceRescale.MinDegree`).
- `fetchICGEM` Outputs help never mentioned `info.mode`, added in the
  series work, nor that bulk selections concatenate their file lists.

## [3.1.1] - 2026-08-11

### Added
- `fetchICGEM` fetches TIME SERIES: temporal-catalogue rows (from
  `listICGEM(Type="temporal")`) download a whole monthly series into
  `<dataFolder>/icgem/series/<group>_<center>_<series>/` - per file
  (resumable, throttled, each file verified before swap; `Files=`
  filter, `FileList=` injection for subsets/mirrors). DEFAULT is the
  server's whole-series ZIP in ONE request (`Mode="auto"`; the rate
  limiter punishes hundreds of per-file requests), with automatic
  per-file fallback; `Mode="archive"|"files"` force either. `Type=`
  mirrors listICGEM so numeric/name selection works on either
  catalogue; the result folder feeds `shSeries.fromFolder` and
  `standardChain` directly.

### Fixed
- `fetchICGEM` bulk selection of temporal series: the multi-selection
  loop assumed one file per row and crashed assigning a 283-file
  series into `strings(1,K)` - AFTER the download had succeeded. File
  outputs are now collected per selection and concatenated; `info`
  carries a uniform `mode` field ("model"|"archive"|"files") across
  all paths; the summary reports selections and files separately.
- `shSeries.filter("tvANS", ...)` accepts and forwards `Shrinkage`,
  `VCEMinDegree` and `VCEBands`. The workflow guide has advertised
  `ts.filter("tvANS", Blocks="auto", VCEBands=[0 16 33 61])` since
  Edition 2; the class method rejected it (`MATLAB:TooManyInputs`), so
  banded VCE was reachable only through the low-level entry point. The
  defaults stay in `shLowLevel.tvANSFilter` - `[]` means "do not
  override" - so there is exactly one home for each default.
- Documentation metadata brought back in sync with the code: `Contents.m`
  is at 3.1.1 (the v3.1.1 tag shipped a 3.1.0 version line, so
  `ver('shAnalysis')` under-reported), `CITATION.cff` follows, and the
  `[3.1.0]`/`[3.0.1]`/`[2.7.0]` sections are dated instead of
  "Unreleased". `Contents.m` no longer advertises the `compat/` folder
  and the legacy v1 suite, both removed in v3.0.0, and its first line is
  now a short product name (MATLAB's `ver` printed a truncated sentence).
- `apiReference.html` regenerated: it predated the series work and listed
  5 of the 12 `fetchICGEM` options. `make_apiref.py` now parses the
  version from `Contents.m` instead of carrying a hardcoded string.
- `helptoc.xml` reaches all 43 help pages (11 were unreachable from the
  Help browser) and its labels no longer name superseded versions;
  `shAnalysis.html` is a v3 page again instead of describing `compat/`.
- `shCoefficients.disp`, `shSeries.disp` and `shClimatology.disp` have
  help text; `help_audit.py` no longer exempts `disp`.
- `shReadGFC` bulk parser survives ragged record groups: EIGEN-5S/5C
  carry a single gfc line with a trailing epoch among thousands of
  uniform ones, which silently misaligned the rectangular sscanf and
  requested a (date x date) coefficient matrix. Groups are now checked
  for rectangularity (rows out == lines in), split by numeric width
  when ragged, and guarded by an n/m integer/bound sanity net; dirty
  groups still fall back to the line parser.

## [3.1.0] - 2026-08-10

### Fixed
- `shReadGFC` ICGEM 2.0 acos/asin column order corrected to the
  real-world layout `... sigC sigS t0 t1 period` (verified against
  CNES_GRGS.RL05MF). The previous parser assumed period-first and
  MIS-PARSED such files (period = a date code, t1 = 1.0) - a
  correctness bug independent of, and older than, the speed problem.
- `shReadGFC` parses variable-term files (GRGS mean fields, ICGEM 2.0)
  in bulk too: group-wise sscanf per record key, vectorized epoch
  conversion, vectorized variableTerms assembly (the per-element
  struct growth was O(N^2)). `icgemDate2Year` is pure arithmetic now -
  the datetime/calendarDuration construction cost ~1 ms per call and
  was invoked per record. A 73 MB CNES_GRGS mean field verification
  went from tens of minutes (the second reported "stall") to seconds;
  dirty records still fall back to the authoritative line parser,
  which itself now assembles variableTerms vectorized.
- `shReadGFC` fast path accepts FORTRAN D-exponents (EIGEN-6C4 switches
  from e to D serialization at degree 371): normalized to E after the
  key strip, matching str2double semantics. Previously such files fell
  back to the legacy line parser - minutes for a 178 MB model, which
  presented as fetchICGEM "stalling" during download verification.
  CI exposed the deeper bug: str2double returns NaN for D-exponents,
  so the legacy parser had silently corrupted such files to NaN above
  the switch degree - both paths now normalize and agree.
- `fetchICGEM` bulk mode ("all", index vectors) no longer stalls after
  the first file: the ICGEM server rate-limits rapid requests (HTTP
  429 / tarpit). Bulk fetching now throttles between models (`Pause=`,
  3 s), retries 429/timeouts with 30/60/120 s backoff (`Retries=`),
  prints a [k/K] counter with per-file size and timing, continues past
  failed models with a summary instead of aborting, and honours
  `Quiet=`. Interrupted runs resume (present files are skipped).

### Changed
- `shReadGFC` is ~100x faster on large static files: bulk parsing
  replaces the per-line fgetl/str2double loop (28.6 s -> 0.21 s at
  n720 measured on PCWIN64; EGM2008-class n2190 in 1.7 s instead of
  minutes). Variable-term files (gfct/trnd/dot/acos/asin) keep the
  proven line parser; both paths verified struct-identical on all
  fixtures and guarded by an equivalence test.

### Added
- `shLowLevel.standardChain`: the canonical GRACE post-processing chain
  (read folder -> TN-14 C20/C30 -> degree-1 -> optional GIA trend ->
  Gaussian/DDK/custom-W filter) as one correctly ordered call with a
  step-by-step provenance report; explicit-file overrides for
  reproducible pipelines.
- `shLowLevel.designFilter`: DDK-class anisotropic filter
  W = (N + Alpha*inv(S))^-1 N per order block, from formal sigmas +
  Kaula rule or full covariances (buildNoiseCov/buildSignalCov);
  output in the readDDK block format (drops into applyDDK and the
  class methods unchanged). Python-validated with pinned references.
- Workflow guide version stamp is generated from Contents.m (the PDF
  title claimed v2.5 since the beginning).

## [3.0.1] - 2026-08-10

### Added
- `tools/help_audit.py`: documentation completeness gate, run in CI
  before the test suite. Every public function and method must document
  every positional input, every option WITH its default, and every
  output with size/type annotations, plus an example. 328 findings
  fixed across the tree to reach zero; the gate keeps it there.

## [3.0.0] - 2026-08-10 - DOI: 10.5281/zenodo.21876348

### BREAKING
- Namespace renamed `+shx` -> `+shLowLevel`: every call site changes
  from `shx.fun` to `shLowLevel.fun`; error identifiers from `shx:*`
  to `shLowLevel:*`. Mechanical migration: replace `shx.` and `shx:`.
- `compat/` (v1 wrappers) and the legacy v1 suite are removed for good.

### Added
- `shLowLevel.listITSG`: numbered catalogue of the TU Graz server
  (releases x monthly n60/n96/n120 x daily), local-mirror mode.
- `fetchITSG`: `Release=` override (no more silent 2018/operational
  mixing), `months = "all"`, `Catalog=` selection by catalogue row,
  `BaseURL=` mirror, n120.
- `listICGEM` numbered; `fetchICGEM` accepts row indices, name vectors,
  and `"all"`.
- `setup_shAnalysis`: `DataFolder=` (applied before any fetcher) and
  `FetchITSG = "all"`.
- `shLowLevel.fetchLoveNumbers`: load/deformation Love numbers from the
  GROOPS collection (TU Graz), safe-swap + parser.
- `shLowLevel.synthesisPoints`: pointwise potential/disturbance/anomaly
  at arbitrary (lat, lon, r) incl. upward continuation; Python-pinned.
- Generated API reference page `html/apiReference.html` (inputs,
  options with defaults, outputs for every public function/method).

## [2.7.0] - 2026-08-10

### Added
- `shLowLevel.poleTideConvert`: C21/S21 conversion between the IERS2010 and
  IERS2018 (secular pole) mean-pole conventions, solid + ocean pole
  tide, overridable coefficients; raw (C, S, epoch) and object forms.
  Python-validated (identities exact, dS21 trend to < 1% of the
  dominant term).
- `Proxy=` option in all four fetchers and `setup_shAnalysis`:
  per-call proxy via matlab.net.http (base MATLAB) for institutional
  networks; websave path continues to honour MATLAB Web Preferences.
- Provenance JSON sidecars (`<file>.provenance.json`: tool version,
  MATLAB release, metadata) on `writeGFC`, `writeGrid`,
  `writeAnimation`; `Sidecar = false` disables.
- `writeGrid` netCDF output is CF-1.8 complete (standard_name, axis,
  coordinates, long_name, Conventions/title/source/history globals);
  the source stamp is dynamic (was hardcoded "v2.4").

## [2.6.0] - 2026-08-10 - DOI: 10.5281/zenodo.21871299

### Added
- Comparison suite: `shLowLevel.compareSolutions` / `shLowLevel.compareSeries`
  aggregators (also `g.compare` / `ts.compare`) over new standalone
  metrics `diffSpectrum`, `spatialStats`, `nashSutcliffe`,
  `effectiveCorr` (AR(1)-corrected significance), `threeCorneredHat`
  (N >= 3), and `shLowLevel.taylorDiagram`. All numerics Python-validated.
- GitHub Actions CI (`ci/shanalysis-ci.yml`); full suite green on
  Linux and Windows.

### Fixed
- `writeAnimation`: platform-aware VideoWriter profile (.avi portable;
  MPEG-4 unavailable on Linux now errors clearly).
- `shDegreeRMS` help documented fields that did not exist
  (`n`/`amp` -> `degree`/`degAmplitude`/...).
- Demo provenance line now generated from `shLowLevel.version`.

## [2.5.1] - 2026-08-08

### Added
- `Update=` option in all four fetchers (safe, parse-verified swap;
  TN-13/TN-14 grow monthly upstream); `BaseURL=` mirror-folder mode in
  `fetchTN`; forwarded through `setup_shAnalysis(Update=true)`.
- `shLowLevel.version`: toolbox metadata parsed from `Contents.m`.

### Fixed
- `applyDDK` truncates Lmax-120 filter blocks to the field nmax
  (standard n60/n96 use; previously errored).
- `shLowLevel.pctile` accepts vector percentiles.
- `setCoefficient` initializes both sigma stacks (pairing invariant);
  a lone sigmaC used to break shSeries stacking.

## [2.5.0] - 2026-08-07

### Added
- Exact constrained tvANS posterior sigmas (the pre-2.5 formula
  UNDERESTIMATED; documented); basin sigmas include the deterministic
  model contribution.
- Kendall AR(1) correction in `fitDeterministicModel`.
- `shLowLevel.readLoveNumbers` (layouts, frames CE/CF/CM, pchip in log(1+n)).
- `setup_shAnalysis` one-call setup; `shLowLevel.fetchTN`.
- Generated 69-page API reference (Part IV) with executable examples
  (`docs/apiExamples.json`, `testAPIExamplesRun`).
- Real-file validation: CSR/JPL/GFZ TN-13, GSFC TN-14, DDK Wbd
  binaries, ITSG monthly/daily, 460 MB operational SINEX streaming.

## [2.4.2] - 2026-08-07

- MIT LICENSE file (Matthias Weigelt); every help text and doc page
  closes with the attribution statement.
- `plotSHCoeffTriangle` difference mode: sine sectorals S_nn no longer
  blanked (the S wing was one column narrow).
- `shLowLevel.listICGEM(Type="temporal")`: full ~70-series catalogue
  (was 3 release-note rows) + `Series=` listing single downloadable
  files.
- Full-sine-wing triangle difference plots; robust cache-speedup test;
  DDK reader; ICGEM catalogue; persistent data folder.

## [2.4.1] - 2026-08-07

### Added
- Triangle plots without the centre line; spectrum plots on a LINEAR
  degree axis (log y kept).
- `plotSHSpectrum` `Quantity=` amplitude | rms | variance |
  cumamplitude | cumrms | cumvariance; order-domain plots via
  `shLowLevel.shOrderRMS` (the striping axis; marginals tested against
  `shDegreeRMS`); cumulative variance/RMS fields added to
  `shDegreeRMS`.
- `shLowLevel.version` - toolbox metadata (name, version, date, root)
  parsed from `Contents.m`.
- `shLowLevel.fetch*` take `Update=true` for a safe, parse-verified
  refresh of existing files (TN-13/TN-14 grow monthly upstream).

## [2.4] - 2026-08-07

### Added
- Visualization: `shLowLevel.plotSHMap` / `g.map` (divergent map,
  coastlines, Hammer projection; `plotSHMap` was REMOVED again in
  3.32.0), `shLowLevel.plotBasinSeries` (sigma band, gaps, trend),
  triangle difference mode (`RefC`/`RefS`), `shLowLevel.plotCovariance`
  (block boundaries), `plotSHSpectrum` Kaula + crossover overlays,
  `shLowLevel.writeAnimation` (MP4, fixed robust scale).
- `shLowLevel.errorMap` - analytic sigma maps from full covariances
  (Cholesky, cross-checked against `mcPropagate`).
- `shLowLevel.eofAnalysis` - EOF/PCA modes as shCoefficients + unit PCs.
- `shLowLevel.basinScaling` - forward-modelled gain factors
  (struct | matrix | handle operators).
- `shSeries.trendBreaks` - hinge breakpoints with F-test (betainc-based
  p-values, no toolbox; null calibrated at 5.1%/5%).
- `shLowLevel.shFanFilter` / `g.fan` / `ts.fan` - Han degree x order
  Gaussian.
- `shLowLevel.combineCenters` - per-(center, month) VCE combination with
  partial redundancies, robust block-median option, inter-center
  correlation diagnostic, posterior sigmas.
- `shLowLevel.seaLevelFingerprint` - elastic sea-level equation (mass
  exactly conserved; near-field fall / far-field excess validated).
- `shLowLevel.writeGrid` - CF-style netCDF export (roundtrip-tested).
- Reference systems: `shLowLevel.normalFieldCS` (even zonals COMPUTED
  from WGS84/GRS80 defining constants, matching NIMA TR8350.2 to all
  published digits), `g.subtractNormalField` (auto-rescaled),
  `shLowLevel.rescaleGMR` / `g.toReference` (exact (GM, R) conversion;
  field invariance verified); arithmetic guards GM/R mismatches.
- `demo_shAnalysis` - selectable case registry (D01..D16,
  "list"/"core"/"all"/subset, `Visible=` for headless runs); rendered
  gallery with explanations in the workflow guide PDF.
- `shLowLevel.fetchITSG` / `shSeries.fromFolder` - on-demand ITSG
  download (websave, release routing, gap-aware) + folder loading;
  demos D01-D06 use real data when present, D12-D14 stay synthetic by
  design (known-truth recovery).
- `shLowLevel.pctile` - percentile without the Statistics Toolbox (an
  audit found `prctile` had slipped into two plot functions; fixed).

## [2.3] - 2026-08-07

### Added
- New synthesis/analysis quantities in `shLowLevel.kernelFactors`:
  `surface_density` [kg/m^2] R rho_ave/3 (2n+1)/(1+kn),
  `bottom_pressure` [Pa] g0 * surface density (OBP),
  `deformation_up` [m] R hn/(1+kn) elastic vertical,
  `gravity_gradient_rr` [1/s^2] (GM/R^3)(n+1)(n+2) (T_rr).
- `Height` option: upward continuation (R/r)^p to satellite altitude.
- `shLowLevel.shSynthesisDeformation` / `g.deformation` - up/north/east
  elastic load deformation (the GNSS comparison); grid and station-list
  modes; exact dPbar/dphi via `shLowLevel.legendreALFDeriv` (frozen
  validated identity, ~5e-10 against numerical gradients).

## [2.2] - 2026-08-07

All rows Python-validated before the MATLAB implementation.

### Added
- `shLowLevel.basinKernel` - basin kernels from polygons/masks/functions
  (buffering + spectral taper).
- `shLowLevel.slepianBasis` - Slepian localization (regional analysis).
- `shLowLevel.readDDK`, `shLowLevel.applyDDK`, `g.applyDDK`,
  `ts.applyDDK` - DDK anisotropic decorrelation filters (native binary
  Wbd support + Nmax truncation in 2.2.1).
- `ts.removeGIA`, `clim.removeGIA` - GIA correction (user-supplied rate
  models).
- `ts.climatology(ARCorrect=true)` - AR(1)-corrected trend/coefficient
  sigmas.
- `shLowLevel.mcPropagate` - Monte-Carlo sigma propagation (independent
  or full SINEX covariance).
- `shLowLevel.readMascon` - JPL/CSR mascon netCDF reader.
- `shLowLevel.geodetic2geocentric`, `shLowLevel.geocentric2geodetic`,
  and `LatType="geodetic"` in the synthesis/analysis entry points.
- `shLowLevel.shSynthesis(..., MaxMemGB=4)` - latitude-banded streaming
  makes nmax 2190 real on ordinary RAM.
- `shLowLevel.tvANSFilter(..., VCEBands=[0 16 33 61])` - per-order-band
  VCE.
- `shLowLevel.readSINEX(..., Only="estimate")` - streaming estimate
  block of multi-100-MB SINEX in seconds.

## [2.1] - 2026-08-07

### Added
- `shCoefficients.analysis` - SH ANALYSIS: gridded or scattered data ->
  Stokes coefficients (rings: exact fast per-order solver; scattered:
  least squares + Kaula).
- `addDegree1` - TN-13 geocenter insertion (with
  `shLowLevel.readTN13`), completing the GSM + TN-14 + TN-13 chain.
- `filter(..., Blocks="auto")` - block-diagonal tvANS (identical
  results, Lmax ~ 120 tractable) + posterior sigma stacks
  (`tsF.sigmaCs`/`Ss`) and basin-average sigmas.
- `climatology(Periods=[161/365.25, 3.66, 7.48])` - S2/K2/K1 tidal
  alias terms; per-coefficient significance on components.
- `synthesis(..., Method="fft")` - FFT-along-longitude + latitude
  parity trick; Legendre recursion stable to degree 2190.
- `dropNaN` / `select` - GRACE <-> GRACE-FO gap handling.
- ICGEM 2.0 piecewise gfct files; `shLowLevel.readSINEX` covariances /
  normal equations.
