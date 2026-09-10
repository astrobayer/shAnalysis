function [fHat, info] = leakageDataDriven(gridSeries, latDeg, lonDeg, opts)
%LEAKAGEDATADRIVEN Model-free leakage/damage correction of a catchment mean.
%   FHAT = shLowLevel.leakageDataDriven(GRIDSERIES, LATDEG, LONDEG,
%   Mask = R, Filter = F) repairs the catchment average of a FILTERED
%   time series using correction terms built from the filtered fields
%   alone - Vishwakarma's "method of deviation". No hydrological model
%   is involved, which is the whole point: it is the model-independent
%   counterpart of shLowLevel.leakageCorrect's forward model.
%
%   Why a filtered catchment mean is wrong, and by exactly what
%   Split the true field g into the part inside the catchment (g R, with
%   R the catchment function) and the rest. For any filter that leaves a
%   constant alone - true of the Gaussian, whose W(0) = 1 - the filtered
%   catchment average splits with NO approximation:
%
%       gbar_c = f_c + dF_c + l_c
%
%     f_c   (1/A) int g R dOmega              the average you wanted
%     l_c   (1/A) int filter(g (1-R)) R       LEAKAGE: signal from
%                                             outside smeared in
%     dF_c  (1/A) int filter(g R - f_c) R     the DEVIATION INTEGRAL:
%                                             what the filter does to
%                                             the catchment's own signal
%                                             because it is not a
%                                             uniform layer
%
%   so f_c = gbar_c - dF_c - l_c is an identity, not a fit. The catch is
%   that l_c and dF_c need g, and nobody has g.
%
%   What is data-driven about it
%   Only the once-filtered field gbar is available. Form the same two
%   integrals one filtering step FURTHER out - from gbar and from the
%   twice-filtered gbarbar - and extrapolate one step BACK:
%     leakage    the two leakage series differ in phase as well as
%                amplitude, so the phase difference between them is
%                measured (Hilbert regression, Phillips et al. 2012),
%                used to align them, and the amplitude ratio taken;
%                lbar is then shifted and scaled to give lhat.
%     deviation  amplitude only. The thesis measured the phase
%                differences of the deviation integral and found NO
%                consistent relation, so no phase shift is applied. The
%                asymmetry is deliberate and is not an omission here.
%
%   The method is designed for catchments of roughly 65000 km^2 and up;
%   below that the published performance decays. It is stated rather
%   than enforced, because the threshold depends on the filter too.
%
%   Inputs
%     gridSeries (nLat x nLon x T) double  ALREADY-FILTERED fields, one
%                per epoch, in any unit that is linear in mass (EWH is
%                the usual one). The unit passes straight through.
%     latDeg     (1 x nLat) double  geocentric latitudes in degrees
%     lonDeg     (1 x nLon) double  longitudes in degrees
%
%   Outputs
%     fHat  (T x 1) double  corrected catchment average, same unit as
%           gridSeries
%     info  (1,1) struct  fields
%           filtered     (T x 1) double  the uncorrected catchment
%                        average of the input - what a user would have
%                        had without this function
%           leakage      (T x 1) double  lhat, the estimated true
%                        leakage that was removed
%           deviation    (T x 1) double  dFhat, the estimated deviation
%                        integral that was removed
%           leakageOnce  (T x 1) double  lbar, leakage from the once
%                        filtered fields (before extrapolation)
%           leakageTwice (T x 1) double  lbarbar, from the twice
%                        filtered fields
%           deviationOnce  (T x 1) double  dFbar
%           deviationTwice (T x 1) double  dFbarbar
%           phaseDeg     (1,1) double  phase difference applied to the
%                        leakage series, in degrees
%           leakageRatio (1,1) double  amplitude factor applied to the
%                        leakage series
%           deviationRatio (1,1) double  amplitude factor applied to the
%                        deviation integral
%           areaFraction (1,1) double  catchment area over the sphere;
%                        multiply by 5.1006e8 km^2 for a rough size, and
%                        compare against the ~65000 km^2 the method
%                        wants
%           nmax         (1,1) double  degree the chain worked at
%           filter       (1,1) string  the filter that was re-applied
%
%   Options
%     Mask      ([])      (nLat x nLon) double  the catchment function
%                         R: 1 inside, 0 outside. Fractional edge values
%                         are allowed and are used as given. The default
%                         is empty and the function then refuses: there
%                         is no sensible default catchment, so this is
%                         required in practice
%     Filter    ("gauss300")  the SAME filter the data already saw -
%                         "none" | "gauss<radiusKm>" | "DDKn" | a W
%                         struct, exactly as shLowLevel.leakageCorrect
%                         takes it. Getting this wrong does not error;
%                         it silently mis-estimates both corrections
%     Nmax      (NaN)     degree of the analysis/synthesis chain;
%                         default floor((nLat-1)/2)
%     GM        (3.986004415e14)  used identically on both sides of the
%                         chain, so it cancels
%     R         (6378136.3)  as GM
%
%   Example
%     % ewh is (nLat x nLon x T) of Gaussian-300 filtered fields
%     [fHat, info] = shLowLevel.leakageDataDriven(ewh, lat, lon, ...
%         Mask = basin, Filter = "gauss300");
%     fprintf("leakage removed: %.3f m RMS, phase %.1f deg\n", ...
%         rms(info.leakage), info.phaseDeg);
%
%   References
%     Vishwakarma, B. D. (2017), Understanding and repairing the signal
%       damage due to filtering of mass change estimates from the GRACE
%       satellite mission, PhD thesis, Institute of Geodesy, University
%       of Stuttgart - chapter 3, eqs. (3.19)-(3.29).
%     Vishwakarma, Horwath, Devaraju, Groh & Sneeuw (2017), A data-driven
%       approach for repairing the hydrological catchment signal damage
%       due to filtering of GRACE products, Water Resour. Res. 53,
%       9824-9844, doi:10.1002/2017WR021150.
%     Phillips, Nerem, Fox-Kemper, Famiglietti & Rajagopalan (2012), The
%       influence of ENSO on global terrestrial water storage using
%       GRACE, Geophys. Res. Lett. 39, L16705, doi:10.1029/2012GL052495
%       - the Hilbert phase estimator.
%     Python-validated in tools/dev/validate_leakage_datadriven.py: the
%       decomposition closes to 4e-15, the phase measure/shift pair are
%       mutual inverses to 7e-15 deg, and a closed loop removes 63% of
%       the filtering damage. testCorrectness measures 55.3% on its own
%       fixture; the grids and the basin differ, the method does not.
%
%   See also shLowLevel.leakageCorrect, shLowLevel.basinScaling,
%   shLowLevel.gridScaling, shLowLevel.basinKernel.
%
%   Error identifiers
%     shLowLevel:leakageDataDriven:badFilter
%         Filter is not a W struct, "none", "gauss<radiusKm>" or "DDKn"
%     shLowLevel:leakageDataDriven:badMask
%         Mask is missing, or is not nLat x nLon
%     shLowLevel:leakageDataDriven:badNmax
%         the grid supports nmax < 2; give at least 3 latitudes
%     shLowLevel:leakageDataDriven:badSize
%         gridSeries is not nLat x nLon x T for the given latDeg/lonDeg
%     shLowLevel:leakageDataDriven:emptyMask
%         Mask has zero area - there is no catchment to average over
%     shLowLevel:leakageDataDriven:nanInput
%         gridSeries contains a non-finite value; the phase and ratio
%         steps are least squares over the WHOLE series and cannot skip
%         one epoch, so this refuses rather than return NaN
%     shLowLevel:leakageDataDriven:tooFewEpochs
%         fewer than 12 epochs. The phase and amplitude steps are
%         regressions over the time series, and below one annual cycle
%         they fit noise
%
%   Developed by Matthias Weigelt with the help of Claude (Opus 5),
%   2026-09-09 (v5.4.0).
arguments
    gridSeries double
    latDeg double
    lonDeg double
    opts.Mask double = []
    opts.Filter = "gauss300"
    opts.Nmax (1,1) double = NaN
    opts.GM (1,1) double = 3.986004415e14
    opts.R (1,1) double = 6378136.3
end
latDeg = latDeg(:).';
lonDeg = lonDeg(:).';
nLat = numel(latDeg);
nLon = numel(lonDeg);
assert(ndims(gridSeries) <= 3 && size(gridSeries, 1) == nLat && ...
    size(gridSeries, 2) == nLon, 'shLowLevel:leakageDataDriven:badSize', ...
    'gridSeries must be nLat x nLon x T (%d x %d x T), got %s.', ...
    nLat, nLon, mat2str(size(gridSeries)));
T = size(gridSeries, 3);

% Twelve is one annual cycle. The phase step regresses the leakage series
% on the quadrature of another series; with less than a cycle that
% regression is unidentifiable and returns an angle that looks like a
% number. Refusing is better than a confident phase from four months.
assert(T >= 12, 'shLowLevel:leakageDataDriven:tooFewEpochs', ...
    ['The phase and amplitude steps are regressions over the series; ' ...
     '%d epochs is less than one annual cycle. Give at least 12.'], T);
assert(all(isfinite(gridSeries), 'all'), ...
    'shLowLevel:leakageDataDriven:nanInput', ...
    ['gridSeries contains %d non-finite value(s). The phase and ratio ' ...
     'steps are least squares over the whole series and cannot skip an ' ...
     'epoch - fill or drop the gaps first.'], nnz(~isfinite(gridSeries)));

mask = opts.Mask;
assert(~isempty(mask) && isequal(size(mask), [nLat, nLon]), ...
    'shLowLevel:leakageDataDriven:badMask', ...
    'Mask is required and must be nLat x nLon (%d x %d).', nLat, nLon);

nmax = opts.Nmax;
if ~isfinite(nmax)
    nmax = floor((nLat - 1) / 2);
end
assert(nmax >= 2, 'shLowLevel:leakageDataDriven:badNmax', ...
    'The grid supports nmax = %d; give at least 3 latitudes.', nmax);

wFilt = resolveFilter(opts.Filter, nmax);

% Quadrature weight per cell. Every integral below is a RATIO against the
% catchment area, so the sphere radius and the longitude spacing cancel
% and only the cos(lat) shape matters.
cellW = repmat(cosd(latDeg(:)), 1, nLon);
area = sum(mask .* cellW, 'all');
assert(area > 0, 'shLowLevel:leakageDataDriven:emptyMask', ...
    'Mask has zero area - there is no catchment to average over.');

chain = @(f) applyChain(f, latDeg, lonDeg, nmax, wFilt, opts.GM, opts.R);
avg = @(f) sum(f .* mask .* cellW, 'all') / area;

% Rbar: the filtered catchment function. Thesis eq. (3.19) writes the
% deviation integral weighted by it, which is the same quantity as
% filtering the deviation field and weighting by R - the filter is
% self-adjoint. Doing it this way filters ONCE per catchment instead of
% once per epoch.
Rbar = chain(mask);

gbarC = zeros(T, 1); gbarbarC = zeros(T, 1);
lbar = zeros(T, 1);  lbarbar = zeros(T, 1);
dFbar = zeros(T, 1); dFbarbar = zeros(T, 1);
for k = 1:T
    gbar = gridSeries(:, :, k);
    gbarbar = chain(gbar);

    gbarC(k) = avg(gbar);
    gbarbarC(k) = avg(gbarbar);

    % leakage: what the filter drags IN from outside the catchment
    lbar(k) = avg(chain(gbar .* (1 - mask)));
    lbarbar(k) = avg(chain(gbarbar .* (1 - mask)));

    % deviation integral, eq. (3.19), in the Rbar form
    dFbar(k) = sum((gbar .* mask - gbarC(k)) .* Rbar .* cellW, 'all') / area;
    dFbarbar(k) = sum((gbarbar .* mask - gbarbarC(k)) .* Rbar .* cellW, ...
        'all') / area;
end

% Leakage: align in phase, then in amplitude. Both regressions are over
% the whole series - this is why the function needs one, not an epoch.
phaseDeg = phaseDifference(lbar, lbarbar);
leakRatio = amplitudeRatio(lbar, shiftPhase(lbarbar, phaseDeg));
lHat = shiftPhase(lbar, phaseDeg) * leakRatio;

% Deviation integral: amplitude only, see the help.
devRatio = amplitudeRatio(dFbar, dFbarbar);
dFHat = dFbar * devRatio;

fHat = gbarC - dFHat - lHat;

info = struct('filtered', gbarC, 'leakage', lHat, 'deviation', dFHat, ...
    'leakageOnce', lbar, 'leakageTwice', lbarbar, ...
    'deviationOnce', dFbar, 'deviationTwice', dFbarbar, ...
    'phaseDeg', phaseDeg, 'leakageRatio', leakRatio, ...
    'deviationRatio', devRatio, ...
    'areaFraction', area / sum(cellW, 'all'), ...
    'nmax', nmax, 'filter', string(filterName(opts.Filter)));
end

% ------------------------------------------------------------- helpers
function out = applyChain(field, latDeg, lonDeg, nmax, wFilt, GM, R)
%APPLYCHAIN analysis -> filter -> synthesis, the operator the data saw.
%   GM and R are used identically on both sides, so they cancel exactly;
%   mismatching them scales the field by ~1e-7 and ruins everything
%   downstream silently.
[C, S] = shLowLevel.shAnalysisGrid(field, latDeg, lonDeg, nmax, ...
    GM = GM, R = R);
if ~isempty(wFilt)
    if isstruct(wFilt)
        [C, S] = shLowLevel.applyDDK(C, S, wFilt);
    else
        C = C .* wFilt(:);
        S = S .* wFilt(:);
    end
end
out = shLowLevel.shSynthesis(C, S, GM, R, latDeg, lonDeg);
end

function z = analytic(x)
%ANALYTIC Analytic signal by FFT - hilbert() is Signal Processing Toolbox.
%   Zero the negative frequencies and double the positive ones, leaving
%   DC (and Nyquist, when the length is even) alone. imag(z) is then the
%   Hilbert transform of x.
x = x(:);
n = numel(x);
h = zeros(n, 1);
h(1) = 1;
if mod(n, 2) == 0
    h(n/2 + 1) = 1;
    h(2:n/2) = 2;
else
    h(2:(n+1)/2) = 2;
end
z = ifft(fft(x) .* h);
end

function y = shiftPhase(x, degrees)
%SHIFTPHASE Rotate a real series in phase by DEGREES.
%   y = cos(th) x - sin(th) H(x), i.e. Re{exp(i th) analytic(x)}. This is
%   the INVERSE of phaseDifference by construction: the estimator
%   regresses onto exactly this pair, so measuring and shifting must use
%   one convention or the correction is applied the wrong way round.
th = deg2rad(degrees);
y = cos(th) * x(:) - sin(th) * imag(analytic(x));
end

function d = phaseDifference(a, b)
%PHASEDIFFERENCE Angle d (degrees) for which a ~= shiftPhase(b, d).
%   Phillips et al. (2012): express a as p + q b + r H(b) by least
%   squares. Since shiftPhase(b, d) = cos(d) b - sin(d) H(b), matching
%   gives q = cos d and r = -sin d, hence the minus below.
z = analytic(b);
A = [ones(numel(b), 1), real(z), imag(z)];
c = A \ a(:);
d = rad2deg(atan2(-c(3), c(2)));
end

function r = amplitudeRatio(target, source)
%AMPLITUDERATIO Least-squares slope of TARGET on SOURCE.
%   The thesis describes an outlier-trimmed mean of the pointwise ratio;
%   a least-squares slope is used here because a pointwise ratio divides
%   by a series that crosses zero twice a year, which no amount of
%   trimming makes stable. The two agree when the series are proportional
%   and the slope is the better-behaved estimator when they are not.
A = [ones(numel(source), 1), source(:)];
c = A \ target(:);
r = c(2);
end

function w = resolveFilter(F, nmax)
%RESOLVEFILTER "none" | "gauss<km>" | "DDKn" | W struct -> weights or W.
if isstruct(F)
    w = F;
    return
end
assert(isstring(F) || ischar(F), ...
    'shLowLevel:leakageDataDriven:badFilter', ...
    'Filter must be a string or a W struct.');
F = string(F);
if F == "none"
    w = [];
elseif startsWith(F, "gauss")
    r = double(extractAfter(F, "gauss"));
    assert(isfinite(r) && r > 0, ...
        'shLowLevel:leakageDataDriven:badFilter', ...
        'Gaussian filter must be "gauss<radiusKm>" (got "%s").', F);
    w = shLowLevel.shGaussianWeights(nmax, r);
elseif startsWith(F, "DDK")
    w = shLowLevel.readDDK(char(F), Nmax = nmax);
else
    error('shLowLevel:leakageDataDriven:badFilter', ...
        'Filter must be "none", "gauss<km>", "DDKn", or a W struct.');
end
end

function s = filterName(F)
if isstruct(F)
    s = F.name;
else
    s = char(string(F));
end
end
