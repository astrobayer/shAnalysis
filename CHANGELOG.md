# Changelog

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

## [2.4.2] - earlier

- Full-sine-wing triangle difference plots; robust cache-speedup test;
  DDK reader; ICGEM catalogue; persistent data folder.
