function rep = seaLevelBudget(mass, total, steric, opts)
%SEALEVELBUDGET Ocean mass against altimetry minus steric sea level.
%
%   REP = shLowLevel.seaLevelBudget(MASS, TOTAL, STERIC) closes the sea-
%   level budget on the epochs the three series share: GRACE ocean mass
%   (shLowLevel.oceanChain's oceanMean, converted to the unit of the
%   others), total sea level from altimetry and the steric part from Argo,
%   all as global or basin means. The residual
%       r = total - steric - mass
%   and the two sides mass and total - steric are fitted with bias,
%   trend, annual and semi-annual terms (shLowLevel.fitDeterministicModel,
%   ARCorrect, T0 = 2000.0), and the budget CLOSES when
%       |trend(r)| <= 2 sigma(trend(r)),
%   sigma AR(1)-corrected. The three fits share one design, so trend(r)
%   is trend(total - steric) - trend(mass) exactly. WP9 9j; the published
%   budget (WCRP Global Sea Level Budget Group 2018 and its updates) is
%   the real-data check, run where the products are.
%
%   Validated in tools/dev/validate_ocean_validation.py: the trend
%   identity to 4.4e-16 and a noise-free closed budget to 1.1e-17 mm/yr
%   (CLAIM 1); with AR(1) noise (phi 0.5, 1.5 mm per component, 180
%   months) a closed budget is called closed in 92.8% of 400 seeds
%   (CLAIM 2, bound 90%) and a 0.6 mm/yr gap called open in 100% (CLAIM
%   3, bound 80%).
%
%   Inputs
%     mass, total, steric  (1,1) struct  each with fields
%           epochs  (T,1) double  decimal years
%           value   (T,1) double  the series, one unit for all three
%           (e.g. mm of global mean sea level)
%
%   Options
%     Tolerance (0.05)  (1,1) double  max |epoch difference| [yr] for two
%                    epochs to be one; pairs are one-to-one
%
%   Outputs
%     rep  (1,1) struct  fields
%          nEpochs      (1,1) double  common epochs used
%          epochs       (T,1) double  their epochs (MASS's)
%          names        (1,3) string  "mass", "total - steric", "residual"
%          trend        (3,1) double  trends [unit/yr], in names' order
%          trendSigma   (3,1) double  their AR(1)-corrected 1-sigma
%          annualAmp    (3,1) double  annual amplitudes [unit]
%          annualPhase  (3,1) double  day of year of the annual maximum
%          closes       (1,1) logical  |trend(r)| <= 2 sigma(trend(r))
%          residualRMS  (1,1) double  RMS of r about its mean [unit]
%          correlation  (1,1) struct  shLowLevel.effectiveCorr of the
%                       detrended mass and total - steric, which documents
%                       every field
%
%   Example
%     [oc, ~] = shLowLevel.oceanChain(folder, kn = kn, OceanMask = oc);
%     mass = struct('epochs', oc.epochs, 'value', 10 * oc.oceanMean);  % mm
%     rep = shLowLevel.seaLevelBudget(mass, gmsl, argo);
%     tr = rep.trend; sg = rep.trendSigma;               % mass, sides, residual
%     fprintf("residual %.2f +- %.2f mm/yr\n", tr(3), sg(3))
%
%   Error identifiers
%     shLowLevel:seaLevelBudget:badInput
%         an input lacks epochs or value, or the two differ in length or
%         are not finite
%     shLowLevel:seaLevelBudget:ambiguousEpochs
%         an epoch of one series lies within Tolerance of two of another
%     shLowLevel:seaLevelBudget:tooFewEpochs
%         fewer than 24 epochs are common to the three series
%
%   References
%     WCRP Global Sea Level Budget Group (2018), Global sea-level budget
%       1993-present, Earth Syst. Sci. Data 10, 1551-1590.
%     Chambers, D. P., Willis, J. K. (2010), A global evaluation of ocean
%       bottom pressure from GRACE, OMCT, and steric-corrected altimetry,
%       J. Atmos. Oceanic Technol. 27, 1395-1402.
%
%   Developed by Matthias Weigelt with the help of Claude (Opus 5.5),
%   2026-11-12 (WP9 9j).
arguments
    mass (1,1) struct
    total (1,1) struct
    steric (1,1) struct
    opts.Tolerance (1,1) double {mustBePositive} = 0.05
end
[tm, vm] = series(mass);
[tt, vt] = series(total);
[ts, vs] = series(steric);
km = (1:numel(tm))';
kt = pairEpochs(tm, tt, opts.Tolerance);
ks = pairEpochs(tm, ts, opts.Tolerance);
use = ~isnan(kt) & ~isnan(ks);
km = km(use); kt = kt(use); ks = ks(use);
T = numel(km);
if T < 24
    error('shLowLevel:seaLevelBudget:tooFewEpochs', ...
        'The three series share %d epochs within Tolerance; at least 24 are needed.', T);
end
t = tm(km);
m = vm(km);
s = vt(kt) - vs(ks);
X = [m.'; s.'; (s - m).'];
[~, ~, coef, ~, coefSigma] = shLowLevel.fitDeterministicModel(X, t, ...
    ARCorrect = true, T0 = 2000);
amp = hypot(coef(3, :), coef(4, :)).';
phase = mod(atan2(coef(4, :), coef(3, :)) / (2 * pi) * 365.25, 365.25).';
r = s - m;
md = m - polyval(polyfit(t, m, 1), t);
sd = s - polyval(polyfit(t, s, 1), t);
rep = struct('nEpochs', T, 'epochs', t, ...
    'names', ["mass", "total - steric", "residual"], ...
    'trend', coef(2, :).', 'trendSigma', coefSigma(2, :).', ...
    'annualAmp', amp, 'annualPhase', phase, ...
    'closes', abs(coef(2, 3)) <= 2 * coefSigma(2, 3), ...
    'residualRMS', sqrt(mean((r - mean(r)).^2)), ...
    'correlation', shLowLevel.effectiveCorr(md, sd));
end

function [t, v] = series(x)
% The epochs and values of one input, checked.
if ~all(isfield(x, {'epochs', 'value'}))
    error('shLowLevel:seaLevelBudget:badInput', ...
        'Every input needs the fields epochs and value.');
end
t = double(x.epochs(:));
v = double(x.value(:));
if numel(t) ~= numel(v) || ~all(isfinite(t)) || ~all(isfinite(v))
    error('shLowLevel:seaLevelBudget:badInput', ...
        'epochs and value must be finite and of one length.');
end
end

function k = pairEpochs(ta, tb, tol)
% For every epoch of TA the one epoch of TB within TOL, NaN for none;
% refuses an epoch with two partners, in either direction.
k = NaN(numel(ta), 1);
for i = 1:numel(ta)
    near = find(abs(tb - ta(i)) <= tol);
    if numel(near) > 1
        error('shLowLevel:seaLevelBudget:ambiguousEpochs', ...
            '%d epochs lie within Tolerance of the epoch %.4f.', numel(near), ta(i));
    end
    if isscalar(near), k(i) = near; end
end
kk = k(~isnan(k));
if numel(unique(kk)) < numel(kk)
    error('shLowLevel:seaLevelBudget:ambiguousEpochs', ...
        'One epoch lies within Tolerance of two epochs of the mass series.');
end
end
