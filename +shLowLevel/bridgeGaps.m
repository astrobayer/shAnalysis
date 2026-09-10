function [out, info] = bridgeGaps(ref, bridge, opts)
%BRIDGEGAPS Fill the months a series lacks from a second, noisier series.
%   OUT = shLowLevel.bridgeGaps(REF, BRIDGE) fills every month that the
%   reference series REF lacks within its own span, and that BRIDGE has,
%   calibrating BRIDGE against REF on the months both have. The intended
%   pair is a GRACE / GRACE-FO series and a high-low SST + SLR series such
%   as QuantumFrontiers HLSST_SLR_COMB2023s, whose months cover the gap
%   between the two missions (2017-07 to 2018-05) and the scattered
%   months GRACE lost to battery management.
%
%   The method, on the overlap months (the two series matched within
%   Tolerance), per coefficient and per degree n:
%     1. both series are truncated to the lower of their two nmax and
%        smoothed with a Gaussian of RadiusKm. The output has that
%        resolution throughout, not only in the filled months, so the
%        series has no jump in resolution;
%     2. each coefficient's mean over the overlap is removed - R0 for REF,
%        B0 for BRIDGE. Their difference is the offset between the two,
%        which also takes up a difference in tide system (C20) or in the
%        reference field;
%     3. a scale s_n regresses REF's anomalies on BRIDGE's, all orders of
%        degree n together: s_n = sum(dB dR) / sum(dB^2);
%     4. a filled month is R0 + s_n (B - B0). Its sigma, for every
%        coefficient of degree n, is the RMS over the overlap of
%        dR - s_n dB: the fill's error as REF itself would see it.
%   REF's own months are kept, smoothed, with their own sigmas.
%
%   Measured on COST-G RL02.1 against the Kalman-filtered HLSST_SLR_
%   COMB2023s at 750 km (208 overlap months), the fill's error over
%   degrees 3-60 is 41 percent of the GRACE signal with the scale and 45
%   percent without; the unfiltered HLSST variant gives 62 and 92 percent.
%   The formal sigmas of either are too small at low degrees (by 3 to 6
%   for the Kalman variant), which is why the sigma comes from the overlap.
%
%   The flag
%   A filled month is named "bridge:" followed by its name in BRIDGE, and
%   names travel with the epochs through select, truncate and every other
%   method. INFO.bridged marks the filled months of OUT.
%
%   Degree 2, and the order of corrections
%   TN-14 has no C20 for the months between the missions, so apply TN-14
%   to REF first. The calibration then uses the SLR C20 on the overlap,
%   and a filled month keeps BRIDGE's own C20, which an HLSST + SLR
%   combination also determines from SLR.
%
%   Inputs
%     ref     (1,1) shSeries  the reference series, e.g. GRACE GSM
%     bridge  (1,1) shSeries  the series that fills its gaps, with the
%             same GM and R
%
%   Outputs
%     out   (1,1) shSeries  REF's months and the filled ones, sorted by
%           epoch, truncated and smoothed as above
%     info  (1,1) struct  fields
%           bridged    (T,1) logical  true for the filled months of OUT
%           overlap    (1,1) double  months the calibration used
%           scale      (nmax+1,1) double  s_n; 0 where BRIDGE's anomaly
%                      has no variance at that degree
%           sigma      (nmax+1,1) double  the fill's sigma per degree
%           offsetC    (nmax+1 x nmax+1) double  B0 - R0, cosine terms
%           offsetS    (nmax+1 x nmax+1) double  B0 - R0, sine terms
%           radiusKm   (1,1) double  the Gaussian radius used
%
%   Options
%     RadiusKm   (750)   Gaussian smoothing radius [km]; 0 smooths
%                        nothing, for series filtered already
%     Tolerance  (0.05)  two months match when their epochs differ by
%                        less [yr]
%     MinOverlap (24)    the fewest matched months the calibration
%                        accepts
%
%   Example
%     gr = shSeries.read("GSM-2_*.gfc").applyTN14(tnFile);
%     hl = shSeries.read(fullfile(hlFolder, "kalman", "*.gfc"));
%     [ts, info] = shLowLevel.bridgeGaps(gr, hl);
%     filled = ts.epochs(info.bridged);
%
%   Error identifiers
%     shLowLevel:bridgeGaps:constantsMismatch
%         GM or R differ between the two series
%     shLowLevel:bridgeGaps:nanInput
%         a series holds NaN or Inf
%     shLowLevel:bridgeGaps:noOverlap
%         fewer than MinOverlap months match
%
%   References
%     Weigelt, M., et al. (2024), Bridging the gap between GRACE and GRACE
%       Follow-On by combining high-low satellite-to-satellite tracking
%       data and satellite laser ranging, J. Geod. 98:84,
%       doi:10.1007/s00190-024-01888-5.
%
%   See also shSeries.bridgeGaps, shSeries.gaussian, shSeries.applyTN14,
%   shLowLevel.combineCenters.
%
%   Developed by Matthias Weigelt with the help of Claude (Opus 5),
%   2026-09-10 (v5.12.0).
arguments
    ref (1,1) shSeries
    bridge (1,1) shSeries
    opts.RadiusKm (1,1) double {mustBeNonnegative} = 750
    opts.Tolerance (1,1) double {mustBePositive} = 0.05
    opts.MinOverlap (1,1) double {mustBeInteger, mustBePositive} = 24
end
if abs(ref.GM - bridge.GM) > 1e-9 * ref.GM || abs(ref.R - bridge.R) > 1e-9 * ref.R
    error('shLowLevel:bridgeGaps:constantsMismatch', ...
        ['GM and R differ (%.10g, %.10g against %.10g, %.10g): rescale ' ...
         'one series to the other first.'], ref.GM, ref.R, bridge.GM, bridge.R);
end
if ~all(isfinite(ref.Cs(:))) || ~all(isfinite(ref.Ss(:))) || ...
        ~all(isfinite(bridge.Cs(:))) || ~all(isfinite(bridge.Ss(:)))
    error('shLowLevel:bridgeGaps:nanInput', ...
        'A series holds NaN or Inf: drop those epochs first (ts.dropNaN).');
end

% 1. one resolution for both, and for the output
nmax = min(ref.nmax, bridge.nmax);
rs = ref;
bs = bridge;
if rs.nmax > nmax, rs = rs.truncate(nmax); end
if bs.nmax > nmax, bs = bs.truncate(nmax); end
if opts.RadiusKm > 0
    rs = rs.gaussian(opts.RadiusKm);
    bs = bs.gaussian(opts.RadiusKm);
end

% the months both have, and the months REF lacks within its own span
tR = rs.epochs(:);
tB = bs.epochs(:);
[dmin, near] = min(abs(tB - tR.'), [], 2);
matched = dmin < opts.Tolerance;
if nnz(matched) < opts.MinOverlap
    error('shLowLevel:bridgeGaps:noOverlap', ...
        ['Only %d months match within %g yr; the calibration needs at ' ...
         'least %d (MinOverlap).'], nnz(matched), opts.Tolerance, ...
        opts.MinOverlap);
end
iB = find(matched);
iR = near(matched);
toFill = find(~matched & tB >= min(tR) & tB <= max(tR));

% 2-4. offset, per-degree scale and per-degree noise on the overlap
n1 = nmax + 1;
R0C = mean(rs.Cs(:, :, iR), 3);
R0S = mean(rs.Ss(:, :, iR), 3);
B0C = mean(bs.Cs(:, :, iB), 3);
B0S = mean(bs.Ss(:, :, iB), 3);
dRC = rs.Cs(:, :, iR) - R0C;
dRS = rs.Ss(:, :, iR) - R0S;
dBC = bs.Cs(:, :, iB) - B0C;
dBS = bs.Ss(:, :, iB) - B0S;
num = sum(sum(dBC .* dRC + dBS .* dRS, 3), 2);
den = sum(sum(dBC.^2 + dBS.^2, 3), 2);
s = zeros(n1, 1);
s(den > 0) = num(den > 0) ./ den(den > 0);
resC = dRC - s .* dBC;
resS = dRS - s .* dBS;
sigma = sqrt(sum(sum(resC.^2 + resS.^2, 3), 2) ./ ((2 * (0:nmax)' + 1) * numel(iR)));

% the filled months and their sigmas
Fc = R0C + s .* (bs.Cs(:, :, toFill) - B0C);
Fs = R0S + s .* (bs.Ss(:, :, toFill) - B0S);
lowC = tril(ones(n1));
lowS = lowC;
lowS(:, 1) = 0;
sigC = repmat(lowC .* sigma, 1, 1, numel(toFill));
sigS = repmat(lowS .* sigma, 1, 1, numel(toFill));
T = rs.nEpochs;
if isempty(rs.sigmaCs)
    refSigC = nan(n1, n1, T);
    refSigS = nan(n1, n1, T);
else
    refSigC = rs.sigmaCs;
    refSigS = rs.sigmaSs;
end

% assemble, sorted by epoch
nameR = rs.names;
if numel(nameR) ~= T
    nameR = repmat("", T, 1);
end
nameB = bs.names;
if numel(nameB) ~= bs.nEpochs
    nameB = compose("%.4f", tB);
end
ep = [tR; tB(toFill)];
[ep, ord] = sort(ep);
Cs = cat(3, rs.Cs, Fc);
Ss = cat(3, rs.Ss, Fs);
SC = cat(3, refSigC, sigC);
SS = cat(3, refSigS, sigS);
names = [nameR; "bridge:" + nameB(toFill)];
flag = [false(T, 1); true(numel(toFill), 1)];
hist = [rs.history(:); sprintf(['bridgeGaps: %d months filled from a ' ...
    'second series, calibrated on %d months, Gaussian %g km'], ...
    numel(toFill), numel(iR), opts.RadiusKm)];
out = shSeries(Cs(:, :, ord), Ss = Ss(:, :, ord), Epochs = ep, ...
    GM = rs.GM, R = rs.R, ProductType = rs.productType, ...
    Names = names(ord), SigmaCs = SC(:, :, ord), SigmaSs = SS(:, :, ord), ...
    History = hist);
info = struct('bridged', flag(ord), 'overlap', numel(iR), 'scale', s, ...
    'sigma', sigma, 'offsetC', B0C - R0C, 'offsetS', B0S - R0S, ...
    'radiusKm', opts.RadiusKm);
end
