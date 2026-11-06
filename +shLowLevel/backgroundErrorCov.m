function [C, info] = backgroundErrorCov(tsA, tsB, opts)
%BACKGROUNDERRORCOV Background-model error covariance from two releases.
%
%   C = shLowLevel.backgroundErrorCov(TSA, TSB) estimates the covariance
%   of the error of a background model - AOD1B, an ocean tide model, any
%   product a GRACE solution has had removed and whose error is not in the
%   solution's formal covariance - from two releases or two models of it,
%   TSA and TSB, at their common epochs. The difference d_t = a_t - b_t
%   holds the two errors and none of the signal; with the mean removed
%   and the two errors independent and of equal size,
%       E[d d'] = 2 C,   so   C = Split * S_d,   Split = 1/2,
%   S_d the sample covariance of the differences (divisor T - 1). Add C
%   to the observations' noise covariance - shLowLevel.regionalKalman's
%   AddNoiseCov does that at every epoch.
%
%   What it is and is not (WP9 9i): an L2 estimate from release
%   differences. Two releases that share part of their error see only
%   the part they do not share - with correlation rho the estimate is
%   (1 - rho) C (validated) - and an error both releases make alike is
%   invisible to it; the full answer is an inversion at L1B (HB-STAR),
%   which is not this toolbox's. Split = 1 when TSB is a reference much
%   better than TSA.
%
%   Validated in tools/dev/validate_background_error.py: with 4000 epochs
%   the full estimate is within 0.064 (relative Frobenius) of the true
%   covariance and its diagonal within 5.0% (CLAIM 1, bounds 3 sqrt(P/T)
%   and 3 sqrt(2/T)); the degree form is unbiased for an isotropic error
%   (CLAIM 2); a shared error of correlation 0.5 gives 0.501 of the truth
%   (CLAIM 3); and in a closed loop (Lmax 12, VAR(1), 60 epochs, a
%   background error four times the formal variance at degrees 2-4, 20
%   seeds) a filter that knows only the formal noise is overconfident,
%   pooled z-rms 1.378, while formal + C from 60 months of release
%   differences gives 0.973 and the lower error in 20 of 20 seeds
%   (CLAIM 4).
%
%   Inputs
%     tsA  (1,1) shSeries  one release or model of the background product
%     tsB  (1,1) shSeries  the other, same nmax
%
%   Options
%     Structure ("full")  "full" | "diagonal" | "degree"   the estimate:
%                    S_d itself; its diagonal; or per degree the mean of
%                    the diagonal over all orders, C and S (isotropic)
%     Split (0.5)    (1,1) double  the share of the difference variance
%                    given to one product: 1/2 for two equally good
%                    independent ones, 1 for TSB a much better reference
%     Shrink (0)     (1,1) double in [0, 1]  (1 - Shrink) C + Shrink
%                    diag(C), for a full estimate from few epochs
%     RemoveMean (true)  (1,1) logical  remove the mean difference (a
%                    systematic offset is not an error covariance)
%     Nmin (2)       (1,1) double  the first degree of the index
%     Tolerance (0.5/365.25)  (1,1) double  max |epoch difference| [yr]
%                    for two epochs to be one
%
%   Outputs
%     C     (P,P) double  the covariance in shLowLevel.shIndex(nmax, Nmin =
%           Nmin) order, symmetric
%     info  (1,1) struct  fields
%           nEpochs    (1,1) double  common epochs used
%           epochs     (T,1) double  their epochs (TSA's) [decimal years]
%           structure  (1,1) string  the Structure option
%           rank       (1,1) double  rank of C (at most T - 1 for "full")
%           degreeRMS  (nmax+1,1) double  per degree the RMS of the
%                      estimated error over the degree's coefficients,
%                      sqrt(mean diag C); NaN below Nmin
%           meanDiff   (P,1) double  the mean difference removed (zeros
%                      with RemoveMean = false)
%
%   Example
%     % two AOD1B releases' monthly means, as shSeries, same months
%     C = shLowLevel.backgroundErrorCov(tsAODrl06, tsAODrl07, Shrink = 0.1);
%     [tsK, out] = ts.regionalKalman(B, ModelSeries = tsm, AddNoiseCov = C);
%
%   Error identifiers
%     shLowLevel:backgroundErrorCov:badSeries
%         TSA or TSB is not an shSeries, or their nmax differ
%     shLowLevel:backgroundErrorCov:tooFewEpochs
%         fewer than 3 epochs are common to the two series
%
%   Developed by Matthias Weigelt with the help of Claude (Opus 5.5),
%   2026-11-06 (WP9 9i).
arguments
    tsA
    tsB
    opts.Structure (1,1) string {mustBeMember(opts.Structure, ["full", "diagonal", "degree"])} = "full"
    opts.Split (1,1) double {mustBePositive} = 0.5
    opts.Shrink (1,1) double {mustBeInRange(opts.Shrink, 0, 1)} = 0
    opts.RemoveMean (1,1) logical = true
    opts.Nmin (1,1) double {mustBeInteger, mustBeNonnegative} = 2
    opts.Tolerance (1,1) double {mustBePositive} = 0.5/365.25
end
if ~(isa(tsA, 'shSeries') && isscalar(tsA) && isa(tsB, 'shSeries') && isscalar(tsB))
    error('shLowLevel:backgroundErrorCov:badSeries', ...
        'TSA and TSB must each be one shSeries.');
end
if tsA.nmax ~= tsB.nmax
    error('shLowLevel:backgroundErrorCov:badSeries', ...
        'The two series reach degree %d and %d; truncate to one nmax first.', ...
        tsA.nmax, tsB.nmax);
end
L = tsA.nmax;
idx = shLowLevel.shIndex(L, Nmin = opts.Nmin);
ea = tsA.epochs(:);
eb = tsB.epochs(:);
ka = [];
kb = [];
for k = 1:numel(ea)
    [dmin, j] = min(abs(eb - ea(k)));
    if ~isempty(dmin) && dmin <= opts.Tolerance
        ka(end + 1, 1) = k; %#ok<AGROW>
        kb(end + 1, 1) = j; %#ok<AGROW>
    end
end
T = numel(ka);
if T < 3
    error('shLowLevel:backgroundErrorCov:tooFewEpochs', ...
        'The two series share %d epochs within Tolerance; at least 3 are needed.', T);
end
D = zeros(idx.P, T);
for t = 1:T
    D(:, t) = shLowLevel.vecFromCS(tsA.Cs(:, :, ka(t)), tsA.Ss(:, :, ka(t)), idx) ...
        - shLowLevel.vecFromCS(tsB.Cs(:, :, kb(t)), tsB.Ss(:, :, kb(t)), idx);
end
mu = zeros(idx.P, 1);
if opts.RemoveMean
    mu = mean(D, 2);
    D = D - mu;
end
C = opts.Split * (D * D.') / (T - 1);
switch opts.Structure
    case "diagonal"
        C = diag(diag(C));
    case "degree"
        v = diag(C);
        for n = opts.Nmin:L
            sel = idx.n == n;
            v(sel) = mean(v(sel));
        end
        C = diag(v);
end
if opts.Shrink > 0
    C = (1 - opts.Shrink) * C + opts.Shrink * diag(diag(C));
end
C = (C + C.') / 2;
dr = NaN(L + 1, 1);
v = diag(C);
for n = opts.Nmin:L
    dr(n + 1) = sqrt(mean(v(idx.n == n)));
end
info = struct('nEpochs', T, 'epochs', ea(ka), 'structure', opts.Structure, ...
    'rank', rank(C), 'degreeRMS', dr, 'meanDiff', mu);
end
