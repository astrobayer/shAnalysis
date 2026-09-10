# shAnalysis

![CI](https://github.com/astrobayer/shAnalysis/actions/workflows/ci.yml/badge.svg)
![MATLAB](https://img.shields.io/badge/MATLAB-base%20only%2C%20R2026a%20tested-orange)
![Platforms](https://img.shields.io/badge/platforms-Windows%20%7C%20Linux-lightgrey)
![Latest tag](https://img.shields.io/github/v/tag/astrobayer/shAnalysis?label=version)
![License](https://img.shields.io/github/license/astrobayer/shAnalysis)
[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.21871298.svg)](https://doi.org/10.5281/zenodo.21871298)

Class-based MATLAB toolbox for spherical harmonic (Stokes coefficient)
analysis of GRACE/GRACE-FO, GOCE, and static gravity field models.
Three user-facing classes cover the whole chain - reading, spectra,
filtering, synthesis, climatology, basin averages - and every numerical
building block is callable directly from the `+shLowLevel` package.

Requires MATLAB R2021a or newer (`arguments` name=value syntax) and
**nothing beyond base MATLAB**: no toolboxes.

**Maps are drawn by [geoMap](https://github.com/astrobayer/geoMap),
not by this toolbox** (v3.32.0). shAnalysis renders no cartography of
its own; `g.map` and `shLowLevel.writeAnimation` synthesize, hand the
grid over, and let `geo.map` draw - a CI gate keeps it that way. The
dependency is checked, not required: everything numerical runs without
geoMap, including `g.toGrid`, which returns the field together with its
units, latitude convention and provenance so that any renderer - or a
plain `imagesc` - can draw it honestly. Only the two drawing entry
points ask for geoMap, and they say so before doing any work.

Validated against the published GravIS Greenland ice-mass series: 2.8%
on the mass trend over 2002-04..2023-02 (217 monthly solutions - the
span of the auxiliary correction tables at the time of the
reproduction), matching their documented processing step for step
(see the guide's *Validation against GravIS* chapter). The span dates
matter: the reference trend moves by ~10 Gt/yr over two years of end
date, so the percentage is only meaningful together with them.
An independent 2026-08 audit reproduced the chain end-to-end from
public data (headline -225.7 vs -224.6 Gt/yr; the wrong-noise control
-201.0 exactly). The same chain reproduces the GravIS terrestrial
water storage product over eleven major river basins to 0.032 cm/yr
trend RMS and a 1.001 median amplitude ratio (DDK3 + ICE-6G_D GIA,
full 252-month span), and locates the Antarctic one-map-inversion
limit at 14% against the AWI joint-basin product - with a 0.905
difference-pattern correlation to the official TU Dresden kernel grid,
i.e. a method-class distance, not a chain defect (guide chapters
V7/V8). All three validations are available as one-call methods with
exchangeable inputs: `shLowLevel.greenlandChain`,
`shLowLevel.antarcticaChain` and `shLowLevel.twsChain`, built on the
shared `shLowLevel.gravisL2B` correction core. All downloads retry
politely on 429/5xx honouring the server's Retry-After header
(`shLowLevel.httpFetch`). Data locations persist across sessions via
`setup_shAnalysis(SeriesFolder=..., GravisFolder=..., DDKFolder=...)`
(setpref-backed); `Quantity = "none"` synthesizes raw coefficient
fields. `shLowLevel.oceanChain` closes the chain family with the
barystatic ocean series (measured GIA lever +0.89 mm/yr), and
`slepianProject` turns the Slepian basis into well-posed regional
analysis. `shLowLevel.fetchGAX` completes the ocean story:
GAD/GAA from 2002 on, one call, full Chambers-&-Willis restoration in
`oceanChain`. The ocean lane now forks: `obpChain` keeps the air
column and delivers GravIS-style bottom-pressure fields, while
`eofSeparate` splits residual circulation from noise (North rule) so
`oceanChain`'s noise proxy stops blaming the ocean for being dynamic. The fetch family is complete and consistently named:
series via `fetchITSG`/`fetchICGEM`, products via `fetchGAX`,
`fetchITSGSINEX` (ITSG monthly normals - the only public per-month SINEX,
~460 MB each) and `fetchITSGBackground`. Those normals feed `vdkApply` - the
VDK/VADER decorrelation of Horvath et al. (2018) with true monthly
covariance structure; `run_vdk_series.m` drives the full-series batch. And the hydrology story
closes the loop from field to warning: `hydroExtremeIndex` delivers
GRACE-DSI drought categories and the Reager flood-predisposition
deficit for every cell or basin. And everything is offline by
design: chains and filters consume local paths only (the GravIS
correction tables ship frozen in `data/gravis`); the `fetch*` family
provisions once with skip-if-present semantics, so a populated data
folder never needs the network again. The barystatic chain now
carries quantified coastal-leakage controls (`CoastBufferKm`,
`RemoveLandLeakage`) - measured before built, defaults conservative.
The temporal-smoothing lane is the Kurtenbach/Kvas Kalman chain that
powers the ITSG daily solutions, implemented end to end
(`estimateVAR` with measured full/diagonal/orderblock structures,
`kalmanFilter` in solution AND normal-equation form with Joseph
update and innovation QC, `rtsSmoother` with bounded lag,
multi-center VCE via `neqCombine`) behind one entry point,
`shLowLevel.kalmanChain`; the forward+smoother pass is test-pinned as
an EXACT solver of the joint batch adjustment, and guide chapter 27
develops the theory with live-measured figures.

## Documentation

The complete **[workflow & theory guide (PDF)](docs/shAnalysis_workflow_guide.pdf)**
covers the processing chain, filter theory, uncertainty propagation, worked
recipes, and a full chapter reproducing the published GravIS Greenland
series step by step. The generated API reference lists typed inputs and
outputs with an executable example for every public function. HTML help
for MATLAB's `doc` browser ships in `html/`, and
`shLowLevel.makeTutorials` writes Live Scripts you can open and run.

## Layout

```
shAnalysis/
  shCoefficients.m   one coefficient set (value class, immutable)
  shSeries.m         time series of coefficient sets
  shClimatology.m    bias/trend/annual/semi-annual model
  runAllTests.m      full validation suite
  +shLowLevel/       numerical internals (stable, package-qualified)
  demo_shAnalysis.m  16 selectable demonstration cases
  tests/             correctness / contract / robustness / science /
                     performance (fixtures live OUTSIDE the repo: CI
                     checks out the pinned tag 'fixtures-YYYY-MM' of the
                     orphan branch 'testdata' - see .github/workflows/
                     ci.yml, which tools/fixture_tag_audit.py keeps on
                     the newest tag; local machines point
                     setup_shAnalysis(TestDataFolder=...) at a copy -
                     CC-BY-4.0 contents, see NOTICE)
  html/              doc pages for MATLAB's `doc` browser
  tools/             CI gates; tools/dev/ the doc generators (see its README)
```

## Quick start

```matlab
cd shAnalysis
setup_shAnalysis(Permanent = true, Download = "core")   % path + TN files
shLowLevel.makeTutorials(Cases = "core");   % Live Scripts to open and run
% later, monthly refresh of the growing TN files (safe, parse-verified swap):
setup_shAnalysis(Download = "core", Update = true)      % or shLowLevel.fetchTN(Update = true)
% levels: "none" (path only) | "core" (TN-13/14) | "filters" (+DDK)
%         | "starter" (+ITSG months) | "all" (+the COMPLETE monthly
%         archive, resumable); DryRun=true shows the plan
ts  = shSeries.read("GSM-2_*.gfc");     % monthly solutions, epoch-sorted
gad = shSeries.read("GAD-2_*.gfc");
ts  = ts.restore(gad);                  % GSM+GAD, epoch-matched
dts = ts - ts.mean;                     % anomalies about the mean field

[clim, resid] = dts.climatology(Robust=true);   % shClimatology + residuals
A = clim.amplitudeMap("annual", -89:89, 0:359, Quantity="ewh", kn=kn);

tsA = dts.destripe(MinOrder=6).gaussian(300);   % classic chain
[tsF, op] = dts.filter("tvANS", SignalMode="inhomogeneous");
avg = tsF.basinAverage(B, Deconvolve=true, Op=op);   % unbiased basin series
```

## Opt-in test data

Seven tests need data too large to ship. Each reads its location from an
environment variable or a MATLAB preference and reports as *filtered*,
never as passed, when there is none:

```matlab
% five locations through setup: setenv for this session AND setpref
setup_shAnalysis(SeriesFolder = "D:/grace/itsg", ...
                 MasconFile = "D:/grace/GRCTellus_JPL.nc", ...
                 GravisFolder = "D:/grace/gravis", DDKFolder = "D:/grace/DDK");
% the other two as preferences
setpref("shAnalysis", "EarthRotationFolder", "D:/grace/earthRotation");
setpref("shAnalysis", "BridgeFolder", "D:/grace/hlsst");
```

| Test | Needs | Looks in |
|---|---|---|
| `testPublishedTrendOnARealSeries` | monthly GSM `.gfc` files, > 24 epochs | `SHX_SERIES_FOLDER`, the environment only |
| `testMasconReaderOnARealFile` | a real mascon product: CSR (no login), GSFC, or JPL PO.DAAC | `SHX_MASCON_FILE` |
| `testReadGridOnTheGravISGrid` | the GravIS Level-3 TWS grid | `SHX_GRAVIS_FOLDER` or preference `GravisFolder` |
| `testGravisChainsRealData` | the GravIS folder, a monthly series and the DDK binaries | `SHX_GRAVIS_FOLDER`, `SHX_SERIES_FOLDER`, `SHX_DDK_FOLDER` or the matching preferences |
| `testExcitationAgainstESMGFZ` | the ESMGFZ angular momentum functions (`ESMGFZ/HAM`, `ESMGFZ/SLAM`) and a series | `SHX_EARTHROTATION_FOLDER` or preference `EarthRotationFolder`, plus the series |
| `testBridgeGapsAgainstGRACE` | an HLSST series such as HLSST_SLR_COMB2023s, and a series | `SHX_BRIDGE_FOLDER` or preference `BridgeFolder`, plus the series |
| `testUserSuppliedSINEXFiles` | SINEX files of your own, up to ~30 MB | the test-data folder (`SHX_TESTDATA_FOLDER` or preference `TestDataFolder`) |

They exist because the fixture suite cannot see the class of failure that
only appears on real data of real length - three bugs surfaced the first
time the toolbox ran against a full 24-year series.

## Running the tests

```matlab
results = runAllTests;        % writes tests/runAllTests_results.txt
```
The complete console output plus a per-test table always land in
`tests/runAllTests_results.txt` (fixed name, overwritten) - upload that
file for review; pasted console text gets truncated.

Five suites run: numerical correctness, API contract, robustness,
**science** (regression against values published outside this toolbox -
defining constants, load Love numbers, the closed-form EWH kernel,
geocentre amplitudes) and performance (speed budgets measured per
machine). The seven opt-in real-data tests above run whenever their
data is set up.

## What is new

The **[CHANGELOG](CHANGELOG.md)** carries the full history with the
reasoning behind each change. The headlines since v3.0.0:

**Filling the mission gap (v5.12.0).** `ts.bridgeGaps(tsH)` fills the
months a GRACE series lacks - the eleven between the missions and those
lost to battery management - from a high-low SST + SLR series such as
QuantumFrontiers HLSST_SLR_COMB2023s, calibrated per degree on the months
both have (offset, scale and an empirical sigma). Each filled month is
named `bridge:...`. Against COST-G at 750 km the fill's error is 41% of
the GRACE signal over degrees 3-60.

**Earth-rotation excitation (v5.10.0, v5.11.0).** `ts.excitation(kn = kn,
TN14 = tn)` gives the polar-motion excitation chi1, chi2 [mas] of C21/S21
(Chen & Wilson 2003) and, with the SLR C20 of TN-14, chi3 and the change
in the length of day [ms], with the IERS 2010 constants by default.

**Every lane behind the classes (v5.6.0 - v5.13.0).** Kalman smoothing,
EOFs, both leakage corrections, gradients, export, error maps, basin
averages, pointwise synthesis, the gradient tensor, VDK, pole-tide
conversion, degree-1 estimation, multi-centre combination and Slepian
projection are methods of `shSeries` and `shCoefficients`, each a thin
delegate pinned bitwise to its function.

**Data-driven leakage correction (v5.4.0, v5.9.0).**
`shLowLevel.leakageDataDriven` repairs a filtered catchment mean with no
hydrological model: Vishwakarma's method of deviation, and with
`Method = "scale"` the method of scale.

**Model grids in, NaN refused (v5.8.0, v5.12.1).** `shLowLevel.readGrid`
reads CF netCDF grids - GravIS Level-3, hydrological models - and
`shCoefficients.analysis` refuses NaN until `Fill = value` says what the
gaps mean.

**The ellipsoid (v5.5.0).** `Surface = "ellipsoid"` evaluates syntheses
and gradients on the WGS84 ellipsoid instead of the sphere r = R; at the
poles its surface lies 21.4 km lower.

**GIA with its uncertainty (v5.2.0).** `ts.removeGIA(gia, Sigma = s)`
propagates the model's rate sigma, and returns separately the term a
trend needs: the GIA error is fully correlated in time.

**Pointwise synthesis, about 100x faster (v5.1.0, v5.3.0).**
`shLowLevel.synthesisPoints` sums by Clenshaw's recursion: 2000 points at
nmax 60 in 0.022 s on the CI machine, against 2.28 s before.

**One filter vocabulary (v5.7.0).** `"none"`, `"gauss<km>"`, `"DDK1"` to
`"DDK8"` or a W struct, read by `shLowLevel.filterSpec` wherever a
`Filter` is taken; a malformed spec is refused before any data is read.

**Name=value everywhere (v4.0.0, v5.0.0).** Every function declares an
`arguments` block with house-cased options, and every error identifier
has three parts, `owner:function:reason`.

**Leakage correction (v3.2.0+).** `shLowLevel.leakageCorrect` recovers the
mass field whose filtered image matches the observation;
`shLowLevel.gridScaling` gives per-pixel scaling factors from a model
series; `shLowLevel.sensitivityKernel` (v3.7.0) trades leakage against
propagated noise *explicitly* - closed form, no iteration, no stopping
criterion.

Two rules that cost real accuracy when broken, both measured:

* **The mask must cover every region that can hold mass**, not only the
  one you are measuring. A Greenland-only mask forces the Canadian
  Arctic and Svalbard into Greenland: +12% instead of +4%.
* **Declare the filter the forward model sees**, not the one your input
  file carries. GravIS ice basin averages start from *unfiltered*
  coefficients and still apply a Wiener filter inside the inversion;
  declaring `"none"` instead of `"gauss445"` moved the trend by 3%.

**Stopping is regularisation (v3.5.0+).** `leakageCorrect` solves an
ill-posed problem and semiconverges: the error against the truth falls,
then *rises*, while the residual keeps shrinking. Pass `NoiseLevel` -
from `shLowLevel.oceanRMS`, the open-ocean noise metric - and the run
stops on the discrepancy principle. `info.stoppedBy` says whether the
answer was regularised at all.

**Self-consistent geocentre (v3.6.0).** `shLowLevel.estimateDegree1`
derives C10/C11/S11 from the data plus an ocean model (Swenson et al.
2008), so you no longer depend on somebody having published a TN-13
series for your exact Level-2 product. Output layout identical to
`readTN13`.

**GRAVIS Level-2B (v3.3.0).** `shLowLevel.readSHM` reads the SHM format
(`GRCOF2` fields, `GRDOTA` rate models) used by GravIS mean fields, GIA
models and monthly solutions - gzip transparent, GM/R from the header.

**The standard chain (v3.1.0).** `shLowLevel.standardChain` runs
read -> TN-14 -> degree 1 -> GIA -> filter in the one correct order and
returns a provenance report. Correction tables always trail the
solutions, so uncovered epochs are dropped and recorded rather than
raising an error.

**Documentation is gated (v3.1.2+).** The CI gates job runs before the
test suite (its list is in `.github/workflows/ci.yml`); `tools/doc_sync_audit.py` checks the in-file help, `html/` and
the workflow guide against the source and against each other - every
documented call is contract-checked, including option value *types*.

## Data sources

| What | Where | Toolbox route |
|---|---|---|
| ITSG monthly / daily solutions | ftp.tugraz.at | `shLowLevel.listITSG`, `fetchITSG` |
| ICGEM static models and time series | icgem.gfz.de | `shLowLevel.listICGEM`, `fetchICGEM` |
| TN-13 (degree 1), TN-14 (C20/C30) | GFZ ISDC | `shLowLevel.fetchTN` |
| DDK filter matrices | upstream repository | `shLowLevel.fetchDDK` |
| Load Love numbers (GROOPS set) | ftp.tugraz.at | `shLowLevel.fetchLoveNumbers` |
| GravIS Level-2B and Level-3 | gravis.gfz.de, ISDC | `shLowLevel.readSHM`, `shLowLevel.readGrid` (manual download) |
| AOD1B monthly means (GAA/GAB/GAC/GAD) | ICGEM / GFZ | `shLowLevel.fetchGAX` |
| ITSG monthly SINEX normals and background models | ftp.tugraz.at | `shLowLevel.fetchITSGSINEX`, `fetchITSGBackground` |
| HLSST + SLR series for the mission gap | icgem.gfz.de | `shLowLevel.listICGEM(Type="temporal")`, `fetchICGEM` |
| ESMGFZ angular momentum functions | esmdata.gfz.de | manual download (the excitation check) |

**On COST-G covariances.** COST-G publishes its combined *solutions*
through ICGEM, and combines on the normal-equation level internally, but
does not distribute per-month SINEX normal equations or covariance
matrices as a public product - Dahle et al. (2025) note the
variance-covariance information is not available for the combined
solutions. There is therefore no COST-G SINEX endpoint to fetch. For a
full covariance use **ITSG**, which does publish monthly SINEX normal
equations (`shLowLevel.readSINEX`), or the GravIS **VDK-filtered**
Level-2B products if what you want is the filtered result rather than
the covariance itself.

## History

Releases before v3.0.0 are described in the CHANGELOG. v3.0.0 was a
breaking change: the package was renamed `+shx` -> `+shLowLevel`, and the
`compat/` folder with the v1 function API was removed together with the
v1 legacy test suite. The v1 function names live on inside the package -
call `shLowLevel.shReadGFC(...)` instead of `shReadGFC(...)`, or use the
classes.

## Citing

See [CITATION.cff](CITATION.cff). Bundled third-party fixtures and their
licences are listed in [NOTICE](NOTICE).

Developed by Matthias Weigelt with the help of Claude.
