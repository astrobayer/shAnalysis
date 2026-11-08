% shAnalysis - Spherical harmonic analysis toolbox
% Version 6.0.0 (R2026a-compatible) 08-Nov-2026
%
% The line above is what ver('shAnalysis') reports as the product name:
% keep it a SHORT name, not a sentence and not a version string (pinned
% by testVersionMetadataIsConsistent).
%
% Spherical harmonic (Stokes coefficient) analysis for GRACE/GRACE-FO,
% GOCE and static gravity field models: class-based, with time-series
% support, GAX background handling, climatology, and the tvANS
% time-variable anisotropic Wiener filter.
%
% Classes (single point of access)
%   shCoefficients  - One coefficient set: I/O, arithmetic, TN-14 and degree 1,
%                     filters (Gaussian, fan, destripe, DDK, VDK), spectra,
%                     synthesis on the sphere or the ellipsoid, gradients,
%                     deformation, error maps, gfct evaluation, regional
%                     bases.
%   shSeries        - Time series of coefficient sets: mean field, climatology,
%                     GAX restore, low-degree/GIA/pole-tide corrections,
%                     classic and tvANS chains, basin averages with exact
%                     deconvolution, Kalman smoothing, EOFs, leakage
%                     correction, Earth-rotation excitation, gap bridging,
%                     regional bases (RBF, Slepian) for a selectable basin
%                     with Kurtenbach's process model and the regional
%                     Kalman chain in them (a single field becomes a
%                     basis normal equation through g.regionalNEQ).
%   shClimatology   - Bias/trend/annual/semi-annual (+extra periods) model:
%                     evaluate at epochs, extract components with 1-sigma
%                     significance, amplitude/phase maps.
%
% Quick start
%   ts  = shSeries.read("GSM-2_*.gfc");
%   ts  = ts.restore(shSeries.read("GAD-2_*.gfc"));   % add background
%   dts = ts - ts.mean;                               % anomalies
%   [clim, resid] = dts.climatology;                  % seasonal model
%   tsA = dts.destripe(MinOrder=6).gaussian(300);     % classic chain
%   [tsF, op] = dts.filter("tvANS");                  % optimal chain
%   avg = tsF.basinAverage(B, Deconvolve=true, Op=op);
%
% Setup
%   setup_shAnalysis  - one call: path, data folder, optional downloads
%                     (DryRun= plans without fetching; offline-safe).
%
% Internals (package +shLowLevel, stable but not the primary API)
%   The numerical layer the classes delegate to: Legendre recursions and
%   caches, synthesis and analysis operators, filters (Gaussian, fan,
%   destripe, DDK, VDK, tvANS), leakage and basin machinery, low-degree
%   corrections (TN-13/TN-14, degree-1, GIA, pole tide), the Kalman/VAR
%   lane, readers and writers, and the plotting helpers. Every entity is
%   listed with its full signature in html/apiReference.html; the in-file
%   help block of each function is the authority.
%
%   Entry points that see the most direct use:
%     shLowLevel.legendreALF, shLowLevel.legendreCached,
%     shLowLevel.shSynthesis, shLowLevel.shAnalysisGrid,
%     shLowLevel.synthesisPoints, shLowLevel.shSynthesisGradient,
%     shLowLevel.kernelFactors, shLowLevel.shIndex,
%     shLowLevel.tvANSFilter, shLowLevel.applyDDK,
%     shLowLevel.leakageCorrect, shLowLevel.basinDeconvolve,
%     shLowLevel.kalmanFilter, shLowLevel.readLoveNumbers,
%     shLowLevel.shReadGFC, shLowLevel.writeGFC, shLowLevel.writeGrid.
%
% Tests and documentation
%   runAllTests     - full validation suite (correctness, contract,
%                     robustness, science, performance).
%   doc shAnalysis  - HTML overview (html/ subfolder on the path).
%   Workflow guide  - the narrative guide (PDF), attached to every GitHub
%                     release; tools/dev/make_guide.py builds it into docs/.
%
% Release history
%   CHANGELOG.md is the authority and the only place a release is
%   described. This file used to repeat it: 74 "New in v..." sections,
%   out of chronological order, printed in full by `help shAnalysis`.
%   They were moved to CHANGELOG.md in v3.33.1 - nothing was lost; the
%   six versions that existed only here (v2.1 to v2.4.2) were written
%   into the changelog in the same commit.
%
% Backward compatibility
%   NONE. v3.0.0 removed the compatibility layer and the v1 legacy suite
%   for good. The v1 function names live on inside the package: call
%   shLowLevel.shReadGFC, shLowLevel.shSynthesis, shLowLevel.shDestripe
%   etc., or use the classes.
%
% Claude (Fable 5), 2026-08-07 (v2.1 through v2.4.1 same day);
%   v3.1.1 documentation sync 2026-08-11 by Claude (Opus 5);
%   release history moved to CHANGELOG.md 2026-09-08 by Claude (Opus 5).
%   Developed by Matthias Weigelt with the help of Claude (Fable 5).
