function [ts, out] = regionalKalman(obsIn, B, opts)
%REGIONALKALMAN Kalman-smoothed regional gravity field in a local basis.
%
%   [TS, OUT] = shLowLevel.regionalKalman(OBSIN, B, ModelSeries=TSM) is
%   the single point of access to the regional Kalman filter of CLAUDE.md
%   WP8: Kurtenbach's normal-equation filter (2012, DGK C-683, Sec. 3.3)
%   and the RTS smoother on the coefficients a of the regional basis B of
%   shLowLevel.regionalBasis, after Woehnke et al. (2025, RBF) and Steffen
%   et al. (2026, Slepian). It chains the pieces the earlier rows built
%   and changes none of them:
%     1. the process model in the basis from the model series TSM
%        (shLowLevel.regionalProcessModel: climatology removed, every
%        epoch projected onto B, VAR(Order) by Yule-Walker, Kurtenbach's
%        alpha and ground noise on request)
%     2. one normal equation in the basis per epoch: the observation
%        series' coefficients with their covariance
%        (shLowLevel.regionalNEQ, kind "solution"), or the records the
%        caller built - any kind of regionalNEQ, combined per epoch with
%        shLowLevel.neqCombine
%     3. the forward filter in its normal-equation mode
%        (shLowLevel.kalmanFilter) and the RTS smoother
%        (shLowLevel.rtsSmoother) - together the joint least-squares
%        adjustment over all epochs (Kvas 2019, Sec. 2.3; Python-validated
%        in an RBF basis to 2e-15, gaps included)
%     4. the smoothed coefficients carried out through linear functionals
%        F a whose sigmas come from the FULL smoothed covariance,
%        sqrt(diag(F Ps F')): SH coefficients x = T a (the output series),
%        EWH at the points of the region and the area-weighted basin mean
%        of EWH. Formal sigmas of an shSeries are per coefficient, so the
%        basin sigma could not be recovered from TS afterwards - this is
%        where it is formed.
%   On the SH basis (B.T = I) the chain IS shLowLevel.kalmanChain in
%   solution mode: the same process model bit for bit, the same estimator
%   - the information-form update agrees with kalmanChain's gain form to
%   5.6e-15 relative in the states and 8.9e-16 in the sigmas
%   (tools/dev/validate_regional_kalman.py CLAIM 1). That is its oracle.
%
%   Observation modes (by class of OBSIN):
%     shSeries   solution mode: every epoch is an SH solution with noise
%                covariance - NoiseCov, or the series' formal sigmas
%                (errors loudly when neither exists). With Climatology =
%                true (default) the series' climatology is removed first,
%                as in kalmanChain, and restored afterwards IN THE BASIS:
%                TS = T (a + Proj c(t)), c the climatology's coefficients
%                - for the SH basis exactly kalmanChain's restore. The
%                climatology carries no sigma, as there.
%     struct     record mode: a (1 x M) struct array of basis normal
%                equations with fields N (K x K), b (K x 1) and epoch
%                (decimal year) - regionalNEQ contributions or a
%                neqCombine result with its epoch added. One record per
%                epoch: combine several kinds of one epoch with
%                shLowLevel.neqCombine first.
%
%   EWH outputs need the load Love numbers kn (never invented) and a
%   region: OUT.basin and OUT.grid are [] without them, or for an SH
%   basis built without a region.
%
%   Inputs
%     obsIn  (1,1) shSeries | (1,M) struct  the observations, see above;
%            a series must reach exactly degree B.idx.Lmax
%     B      (1,1) struct  a basis from shLowLevel.regionalBasis
%
%   Options
%     ModelSeries (required)  (1,1) shSeries  process realisation at the
%                    filter's sampling, nmax = B.idx.Lmax (truncate
%                    first): ESA ESM, a hydrology model, GAX
%     Order (1)      (1,1) double  VAR order (see estimateVAR)
%     Shrink (0)     (1,1) double  diagonal loading of Sigma(0)
%     Structure ("full")  "full" | "diagonal"   coupling of the VAR
%                    estimate (see regionalProcessModel)
%     CondFun ([])   function handle  covariance conditioning
%     QScale (1)     (1,1) double  Kurtenbach's alpha, Q -> alpha Q
%     GroundNoise (0)  (1,1) double  isotropic ground noise [m EWH],
%                    added to Sigma(0) (see regionalProcessModel)
%     kn ([])        (>=Lmax+1,1) double  load Love numbers: needed by
%                    GroundNoise and by the EWH outputs
%     Epochs ([])    (E,1) double  target epoch grid [decimal years];
%                    [] uses the observation epochs. A grid entry without
%                    an observation within Tolerance is a gap: prediction
%                    only
%     Tolerance (0.5/365.25)  (1,1) double  max |epoch difference| [yr]
%                    for matching an observation to a grid entry
%     NoiseCov ([])  solution mode: (P,P) full, (P,1) diagonal or (P,M)
%                    diagonal noise covariance per observation epoch of
%                    the series, in B.idx order; [] takes the formal
%                    sigmas
%     Climatology (true)  (1,1) logical  solution mode: remove and
%                    restore the observation climatology, see above
%     Lag (Inf)      (1,1) double  smoothing lag in epochs
%                    (rtsSmoother's Lag): Inf the full RTS pass, 0 the
%                    filter estimates alone
%     QC ("none")    "none" | "flag" | "reject"   innovation QC (see
%                    kalmanFilter)
%     QCAlpha (1e-3) (1,1) double  its false-alarm level
%     StoreCov ("full")  "full" | "matfile"   where the filter keeps the
%                    covariances the smoother needs (see kalmanFilter); a
%                    matfile is deleted after smoothing
%
%   Outputs
%     ts   (1,1) shSeries  T (a + Proj c) on the epoch grid with formal
%          1-sigma stacks sqrt(diag(T Ps T')), every step in the history
%     out  (1,1) struct  fields
%          mode             (1,1) string  "solution" | "records"
%          basisType        (1,1) string  B.type
%          K                (1,1) double  number of basis functions
%          order            (1,1) double  VAR order
%          epochs           (E,1) double  the epoch grid [decimal years]
%          nEpochs          (1,1) double  E
%          gap              (1,E) logical  epochs without an observation
%          nGaps            (1,1) double  their number
%          a                (K,E) double  smoothed basis coefficients, the
%                           restored climatology included (a + Proj c)
%          sigA             (K,E) double  their 1-sigma
%          covLast          (K,K) double  full smoothed covariance of the
%                           last epoch
%          qcStat           (1,E) double  innovation statistic; NaN with
%                           QC = "none"
%          nRejected        (1,1) double  epochs QC rejected
%          specRadius       (1,1) double  spectral radius of the
%                           companion matrix; < 1 is stable
%          meanContribution (1,E) double  mean data share per epoch
%                           (Kurtenbach Sec. 3.3.2); NaN in gaps
%          representation   (1,1) double  share of the model signal the
%                           basis carries (see regionalProcessModel)
%          model            (1,1) struct  the estimateVAR struct
%          basin            (1,1) struct  area-weighted basin mean of EWH
%                           over B.region.core, [] without kn or region;
%                           fields
%                           mean          (1,E) double  [m]
%                           sigma         (1,E) double  its 1-sigma [m]
%                           areaFraction  (1,1) double  region area / 4pi
%          grid             (1,1) struct  EWH at the quadrature points
%                           of the region, [] without kn or region; fields
%                           latDeg  (G,1) double  geocentric latitude
%                           lonDeg  (G,1) double  longitude
%                           ewh     (G,E) double  [m]
%                           sigma   (G,E) double  its 1-sigma [m]
%          memGB            (1,1) double  covariance storage of the
%                           filter [GB] (disk for "matfile")
%
%   Example
%     idx = shLowLevel.shIndex(60);
%     B = shLowLevel.regionalBasis(idx, "Elbe", Type = "slepian", ...
%         Threshold = 0.5);
%     [tsK, out] = shLowLevel.regionalKalman(tsGrace, B, ...
%         ModelSeries = tsESM, kn = kn, QScale = 10);
%     errorbar(out.epochs, out.basin.mean, out.basin.sigma)
%
%   Memory: the filter keeps two K x K covariances per epoch with the
%   smoother; K is the number of basis functions, which for a region is
%   far below the (nmax+1)^2 of the global chain.
%
%   Error identifiers
%     shLowLevel:regionalKalman:badBasis
%         B is not a basis from shLowLevel.regionalBasis
%     shLowLevel:regionalKalman:missingModel
%         ModelSeries was not given
%     shLowLevel:regionalKalman:nmaxMismatch
%         the observation or the model series does not reach exactly the
%         basis' band limit - truncate first
%     shLowLevel:regionalKalman:badInput
%         OBSIN is neither an shSeries nor a struct array of records
%     shLowLevel:regionalKalman:badRecord
%         a record lacks N, b or epoch, does not fit the basis, or two
%         records fall within Tolerance of each other
%     shLowLevel:regionalKalman:noNoise
%         an epoch has no formal sigmas and NoiseCov is empty
%
%   References
%     Kurtenbach, E. (2012), Entwicklung eines Kalman-Filters zur
%       Bestimmung kurzzeitiger Variationen des Erdschwerefeldes aus Daten
%       der Satellitenmission GRACE, DGK C-683, Sec. 3.3.
%     Kvas, A. (2019), Estimation of high-frequency mass variations from
%       satellite gravimetry, PhD thesis, TU Graz, Sec. 2.3.
%     Woehnke, V., Eicker, A., Weigelt, M., et al. (2025), Kalman filter
%       framework for a regional mass change model from GRACE satellite
%       gravity, GEM - Int. J. Geomath. 16:2.
%
%   Numerics pre-validated in Python (tools/dev/validate_regional_kalman.py).
%
%   Developed by Matthias Weigelt with the help of Claude (Opus 5.5),
%   2026-10-21.
arguments
    obsIn
    B (1,1) struct
    opts.ModelSeries (1,1) shSeries
    opts.Order (1,1) double {mustBeInteger, mustBePositive} = 1
    opts.Shrink (1,1) double {mustBeNonnegative} = 0
    opts.Structure (1,1) string {mustBeMember(opts.Structure, ["full", "diagonal"])} = "full"
    opts.CondFun = []
    opts.QScale (1,1) double {mustBePositive} = 1
    opts.GroundNoise (1,1) double {mustBeNonnegative} = 0
    opts.kn double = []
    opts.Epochs (:,1) double = []
    opts.Tolerance (1,1) double {mustBePositive} = 0.5/365.25
    opts.NoiseCov double = []
    opts.Climatology (1,1) logical = true
    opts.Lag (1,1) double {mustBeNonnegative} = Inf
    opts.QC (1,1) string {mustBeMember(opts.QC, ["none", "flag", "reject"])} = "none"
    opts.QCAlpha (1,1) double {mustBeInRange(opts.QCAlpha, 0, 1, "exclusive")} = 1e-3
    opts.StoreCov (1,1) string {mustBeMember(opts.StoreCov, ["full", "matfile"])} = "full"
end
if ~all(isfield(B, {'T', 'Proj', 'idx', 'type', 'region', 'K'}))
    error('shLowLevel:regionalKalman:badBasis', ...
        'B must be a basis from shLowLevel.regionalBasis.');
end
if ~isfield(opts, 'ModelSeries')
    error('shLowLevel:regionalKalman:missingModel', ...
        ['ModelSeries is required: the process model is estimated from a ' ...
         'model series, never assumed.']);
end
tsm = opts.ModelSeries;
idx = B.idx;
L = idx.Lmax;
P = idx.P;
K = B.K;
if tsm.nmax ~= L
    error('shLowLevel:regionalKalman:nmaxMismatch', ...
        'The model series reaches degree %d, the basis %d - truncate first.', ...
        tsm.nmax, L);
end

% ---- 1. process model in the basis
[model, pinfo] = shLowLevel.regionalProcessModel(tsm, B, Order = opts.Order, ...
    Shrink = opts.Shrink, Structure = opts.Structure, CondFun = opts.CondFun, ...
    QScale = opts.QScale, GroundNoise = opts.GroundNoise, kn = opts.kn);

% ---- 2. observation records
solMode = isa(obsIn, 'shSeries');
climObs = [];
if solMode
    tsObs = obsIn;
    if tsObs.nmax ~= L
        error('shLowLevel:regionalKalman:nmaxMismatch', ...
            'The observation series reaches degree %d, the basis %d - truncate first.', ...
            tsObs.nmax, L);
    end
    if opts.Climatology
        [climObs, tsObs] = tsObs.climatology;
    end
    obsEpochs = tsObs.epochs(:);
    getObs = @(k) solutionRecord(tsObs, k, B, opts.NoiseCov);
elseif isstruct(obsIn)
    recs = obsIn(:).';
    if ~all(isfield(recs, {'N', 'b', 'epoch'}))
        error('shLowLevel:regionalKalman:badRecord', ...
            'Every record needs the fields N, b and epoch.');
    end
    for k = 1:numel(recs)
        if ~isequal(size(recs(k).N), [K K]) || numel(recs(k).b) ~= K ...
                || ~isscalar(recs(k).epoch)
            error('shLowLevel:regionalKalman:badRecord', ...
                'Record %d: N must be %d x %d, b %d x 1 and epoch a scalar.', ...
                k, K, K, K);
        end
    end
    obsEpochs = [recs.epoch]';
    es = sort(obsEpochs);
    if any(diff(es) <= opts.Tolerance)
        error('shLowLevel:regionalKalman:badRecord', ...
            ['Two records lie within Tolerance of each other; combine the ' ...
             'records of one epoch with shLowLevel.neqCombine first.']);
    end
    getObs = @(k) struct('l', [], 'R', [], 'N', recs(k).N, 'b', recs(k).b(:));
else
    error('shLowLevel:regionalKalman:badInput', ...
        'OBSIN must be an shSeries or a struct array of basis normal equations.');
end
if isempty(opts.Epochs)
    epGrid = obsEpochs;
else
    epGrid = sort(opts.Epochs(:));
end
nE = numel(epGrid);
obs = repmat(struct('l', [], 'R', [], 'N', [], 'b', []), 1, nE);
for t = 1:nE
    [d, k] = min(abs(obsEpochs - epGrid(t)));
    if d <= opts.Tolerance
        obs(t) = getObs(k);
    end
end

% ---- 3. filter and smoother; 4. the functionals
filt = shLowLevel.kalmanFilter(model, obs, StoreCov = opts.StoreCov, ...
    QC = opts.QC, QCAlpha = opts.QCAlpha);
[fB, Fg, gLat, gLon, areaFrac] = regionFunctionals(B, opts.kn, tsm);
F = [B.T; fB; Fg];
smo = shLowLevel.rtsSmoother(filt, Lag = opts.Lag, Functionals = F);
if opts.StoreCov == "matfile" && isfile(filt.covFile)
    delete(filt.covFile);                      % chain-internal
end
a = smo.xs;
if solMode && opts.Climatology
    for t = 1:nE
        gc = climObs.eval(epGrid(t));
        a(:, t) = a(:, t) + B.Proj * shLowLevel.vecFromCS(gc.C, gc.S, idx);
    end
end
X = full(B.T * a);
sigX = smo.sigF(1:P, :);

% ---- the series
n1 = L + 1;
Cs = zeros(n1, n1, nE); Ss = Cs; sC = Cs; sS = Cs;
for t = 1:nE
    [Cs(:, :, t), Ss(:, :, t)] = shLowLevel.csFromVec(X(:, t), idx);
    [sC(:, :, t), sS(:, :, t)] = shLowLevel.csFromVec(sigX(:, t), idx);
end
modeName = "records";
if solMode, modeName = "solution"; end
ts = shSeries(Cs, Ss = Ss, Epochs = epGrid, GM = tsm.GM, R = tsm.R, ...
    SigmaCs = sC, SigmaSs = sS, ProductType = "KALMAN", History = sprintf( ...
    "regionalKalman: %s basis, K = %d, %s mode, VAR(%d), %d epochs (%d gaps), lag %g", ...
    B.type, K, modeName, opts.Order, nE, nnz(filt.gap), opts.Lag));

% ---- the region
basin = [];
gridOut = [];
if ~isempty(fB)
    basin = struct('mean', fB * a, 'sigma', smo.sigF(P + 1, :), ...
        'areaFraction', areaFrac);
    gridOut = struct('latDeg', gLat, 'lonDeg', gLon, 'ewh', Fg * a, ...
        'sigma', smo.sigF(P + 2:end, :));
end
memGB = 8 * nE * (model.order * K)^2 * 2 / 1e9;
out = struct('mode', modeName, 'basisType', B.type, 'K', K, ...
    'order', opts.Order, 'epochs', epGrid, 'nEpochs', nE, ...
    'gap', filt.gap, 'nGaps', nnz(filt.gap), 'a', a, 'sigA', smo.sig, ...
    'covLast', smo.PsLast, 'qcStat', filt.qcStat, ...
    'nRejected', nnz(filt.qcReject), 'specRadius', model.specRadius, ...
    'meanContribution', mean(filt.contrib, 1), ...
    'representation', pinfo.representation, 'model', model, ...
    'basin', basin, 'grid', gridOut, 'memGB', memGB);
end

% ---------------------------------------------------------------- local
function o = solutionRecord(tsObs, k, B, noiseCov)
% One epoch of the series as a basis normal equation (regionalNEQ).
g = tsObs.at(k);
l = shLowLevel.vecFromCS(g.C, g.S, B.idx);
if isempty(noiseCov)
    if isempty(g.sigmaC) || all(g.sigmaC(:) == 0)
        error('shLowLevel:regionalKalman:noNoise', ...
            ['Epoch %d has no formal sigmas and NoiseCov is empty - pass ' ...
             'NoiseCov explicitly (no silent noise assumptions).'], k);
    end
    C = shLowLevel.vecFromCS(g.sigmaC, g.sigmaS, B.idx).^2;
elseif isvector(noiseCov) || size(noiseCov, 2) == size(noiseCov, 1)
    C = noiseCov;
else
    C = noiseCov(:, k);
end
rec = shLowLevel.regionalNEQ(B, "solution", Solution = l, Cov = C);
o = struct('l', [], 'R', [], 'N', rec.N, 'b', rec.b);
end

function [fB, Fg, lat, lon, areaFrac] = regionFunctionals(B, kn, tsm)
% EWH at the region's quadrature points and their area-weighted mean, as
% rows acting on the basis coefficients; empty without kn or a region.
fB = []; Fg = []; lat = []; lon = []; areaFrac = NaN;
if isempty(kn) || isempty(B.region.core)
    return
end
idx = B.idx;
L = idx.Lmax;
os = B.region.overSample;
[~, w, qgrid] = shLowLevel.synthesisMatrix(idx, NLat = os * (L + 1), ...
    NLon = os * (2 * L + 2), GridOnly = true);
nLon = numel(qgrid.lonDeg);
core = B.region.core;
im = find(core > 0);
lat = qgrid.latDeg(ceil(im / nLon));
lat = lat(:);
lon = qgrid.lonDeg(mod(im - 1, nLon) + 1);
lon = lon(:);
f = shLowLevel.kernelFactors("ewh", L, tsm.GM, tsm.R, kn = kn);
Ye = shLowLevel.ylm(deg2rad(lat), deg2rad(lon), idx) .* f(idx.n + 1).';
Fg = full(Ye * B.T);
wc = w(im) .* core(im);
fB = (wc.' * Fg) / sum(wc);
areaFrac = w' * core;
end
