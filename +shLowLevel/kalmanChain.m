function [ts, rep] = kalmanChain(obsIn, opts)
%KALMANCHAIN Kalman-smoothed SH series in one call (Kurtenbach/Kvas).
%
%   [TS, REP] = shLowLevel.kalmanChain(OBSIN, ModelSeries=TSM) is the
%   single point of access to the Kalman/VAR module: it turns noisy
%   per-epoch gravity information plus a geophysical model series into
%   a temporally smoothed shSeries, encoding the correctly ordered
%   chain of Kurtenbach (2012) and Kvas (2019):
%     1. reduce the model series TSM by its own climatology (mean,
%        trend, annual, semi-annual) - the residual approximates the
%        short-term process (Kurtenbach eq. 3.81)
%     2. estimate the VAR(Order) process model from the residuals
%        (shLowLevel.estimateVAR; Order=1 is Kurtenbach's B/Q)
%     3. build one observation record per requested epoch: a solution
%        with noise covariance, a SINEX normal equation, or a gap
%     4. forward Kalman filter with stationary initialization
%        (shLowLevel.kalmanFilter)
%     5. RTS smoother (shLowLevel.rtsSmoother) - with step 4 exactly
%        the joint adjustment over all epochs (Kvas Sec. 2.3)
%     6. repack into an shSeries with formal sigmas; in solution mode
%        the observation climatology removed in step 3 is restored, so
%        TS is directly comparable to the input series
%
%   Observation modes (by class of OBSIN):
%     shSeries      solution mode: each epoch's coefficient vector is
%                   the observation l = x + v. The series is reduced by
%                   its own climatology first (Climatology=true); the
%                   noise covariance comes from NoiseCov or, if empty,
%                   from the series' formal sigmas (errors loudly if
%                   neither exists - no silent noise assumptions).
%     string array  neq mode, MULTI-CENTER (v3.23): several folders,
%                   one per center. Files are grouped by epoch (within
%                   Tolerance) and each group is combined on the
%                   normal-equation level by shLowLevel.neqCombine
%                   BEFORE the filter update - VCE weights per epoch
%                   when every file carries the SINEX STATISTICS block,
%                   or fixed NeqWeights. Same-background contract of
%                   neqCombine applies across ALL centers.
%     string/char   neq mode: a folder of SINEX files carrying
%                   +SOLUTION/NORMAL_EQUATION_MATRIX blocks (e.g. ITSG,
%                   shLowLevel.fetchITSGSINEX). Each file contributes
%                   N and b = N * x_est at its epoch. THE NEQS ARE
%                   TAKEN AS-IS: they refer to the provider's
%                   background models, so TS is a RESIDUAL series with
%                   respect to that background - restoring it (GAX,
%                   static field) is the caller's responsibility, as
%                   everywhere else in the toolbox.
%
%   A second observation group (solution mode only, v5.25.0)
%   SecondSeries = TSB adds a noisier series of the same field - an HLSST
%   + SLR combination, Swarm - as a second observation of every epoch it
%   has. It observes each coefficient of degree n as
%       B = s_n x + o + e,   e ~ N(0, sigma_n^2),
%   an offset o per coefficient (reference field, tide system), a scale
%   s_n per degree (a regularised series is damped) and a noise sigma_n
%   per degree, all calibrated on the months both series have (matched
%   within SecondTolerance) against OBSIN and its noise variances sR^2,
%   over all coefficients of degree n:
%       dR = R - mean(R),  dB = B - mean(B)            over the overlap
%       s_n = sum(dB dR) / (sum(dR^2) - sum(sR^2))     errors in variables;
%                                                      0 where <= 0
%       o = mean(B) - s_n mean(R)
%       sigma_n^2 = mean((dB - s_n dR)^2) - s_n^2 mean(sR^2), floored at
%                   s_n^2 mean(sR^2): never better than OBSIN
%   B's formal sigmas are not used: for the Kalman-filtered HLSST series
%   they are 3 to 6 times too small at low degrees (bridgeGaps). Each
%   epoch of TSB enters the filter as a normal equation,
%   N = diag(s^2/sigma^2), b = s (B - o - s c)/sigma^2 with c the
%   climatology removed from OBSIN, added to OBSIN's information where
%   both observe the epoch; an epoch only TSB has is an epoch the process
%   model alone would otherwise bridge. With the process model fixed this
%   is the joint posterior of both series
%   (tools/dev/validate_kalman_bridge.py CLAIM 1, 3.3e-14). The default
%   grid (Epochs = []) is OBSIN's epochs plus every TSB epoch inside
%   OBSIN's span that OBSIN lacks - the months shLowLevel.bridgeGaps
%   fills. In the closed loop of that file (nmax 12, an 11-month gap, a
%   secondary damped above degree 6 and 4 times noisier) the gap error at
%   750 km is 0.34 of the signal, against 0.46 for bridgeGaps' fill and
%   0.69 for the chain without TSB; outside the gap it changes the error
%   by 0.3 percent, and in the gap the error is 0.98-1.13 of the
%   predicted sigma. A Kalman run holds two (P x P) covariances per epoch,
%   so for a long series run it on a window around the gap (REP.memGB).
%
%   Inputs
%     obsIn  (1 x 1) shSeries | (1 x 1) string  observations: series
%            (solution mode) or SINEX folder (neq mode)
%
%   Options
%     ModelSeries (required)  (1 x 1) shSeries  process realization at
%            the target sampling and nmax (truncate first if needed);
%            e.g. GAX/AOD1B, ESA ESM or a hydrology model as SH series
%     Order (1)         (1 x 1) VAR order p (see estimateVAR)
%     Structure ("full")  "full" | "diagonal" | "orderblock": coupling
%            structure of the VAR estimate (v3.28; see estimateVAR for
%            the measured monthly table). "orderblock" builds the
%            canonical (order m, C/S) partition from the series index
%            automatically - the recommended setting for MONTHLY input
%     Shrink (0)        (1 x 1) diagonal loading (see estimateVAR)
%     CondFun ([])      covariance conditioning (see estimateVAR)
%     Epochs ([])       (K x 1) double  target epoch grid [decimal
%            years]. [] uses the observation epochs as-is. A grid entry
%            with no observation within Tolerance becomes a gap epoch:
%            prediction only - this is how daily interpolation across
%            missing days works
%     Tolerance (0.5/365.25)  (1 x 1) max |epoch difference| [yr] to
%            match an observation to a grid entry
%     NoiseCov ([])     solution mode: (P x P) double full R, (P x 1)
%            double diagonal, or (P x T) double per-epoch diagonals;
%            [] derives diagonals from the series' formal sigmas
%     Climatology (true)  solution mode: reduce OBSIN by its own
%            climatology before filtering and restore it afterwards
%     FitClimatology ("observations")  "observations" | "filtered"   what
%            that climatology is fitted to. "observations" fits it to OBSIN
%            itself, so the noise of the fit is restored unfiltered in every
%            epoch (A34). "filtered" runs the chain once with Climatology =
%            false, fits the climatology to that smoothed series at the
%            output epochs, removes it from OBSIN, filters the residual and
%            restores it - twice the cost. In the 8e closed loop (noise
%            rising to 3 cm per coefficient at degree 30) the grid RMS is
%            14.5 cm with "observations", 0.89-1.96 cm with "filtered" and
%            0.90-2.02 cm with Climatology = false; "filtered" is the better
%            of the last two once the climatology is strong
%            (tools/dev/validate_climatology_restore.py). With noise below
%            the signal the two fits differ little. Ignored when
%            Climatology = false and in neq mode.
%     Smoother (true)   run the RTS pass (false: filter only, e.g. for
%            NRT-style one-way runs a la Kvas Ch. 3; then the internal
%            filter stores only diagonals and memory stays flat)
%     QC ("none")       "none" | "flag" | "reject": innovation-based
%            per-epoch quality control (Kvas Sec. 3.3; see
%            kalmanFilter). "reject" keeps blunder epochs out of the
%            recursion - they become prediction-only and are counted
%            in REP.nRejected
%     QCAlpha (1e-3)    false-alarm level of the test
%     StoreCov ("auto") where the filter keeps the full covariances the
%            smoother needs: "auto" = "full" (RAM) with the smoother,
%            "diag" without; "matfile" streams them through a v7.3 MAT
%            on disk instead - RAM stays flat for long daily runs,
%            results identical to the last bit. The file is deleted
%            after smoothing (it is chain-internal); REP.memGB then
%            reports the DISK footprint
%     Pattern ("*.snx*")  neq mode: file pattern inside the folder(s)
%     NeqWeights ([])   multi-center neq mode: (F x 1) double fixed
%            weights per center (skips per-epoch VCE); [] runs VCE,
%            which requires STATISTICS on every file and errors loudly
%            otherwise (neqCombine contract)
%     SecondSeries      (1 x 1) shSeries  a second, noisier series of
%            the same field at the same nmax, GM and R, observing every
%            epoch it has (above); solution mode only. Not given: the
%            chain is unchanged, bitwise
%     SecondNoise ("overlap")  "overlap" | (nmax+1 x 1) double  the
%            noise sigma_n of SecondSeries per degree: calibrated on the
%            overlap, or given; the offset and scale are calibrated either
%            way
%     SecondScale (true)  calibrate the per-degree scale s_n; false fixes
%            s_n = 1. In the closed loop the scale wins in 19 of 20 seeds
%            (gap error 0.34 against 0.35 of the signal)
%     SecondTolerance (0.05)  (1 x 1) double [yr]  an epoch of
%            SecondSeries matches an OBSIN epoch, and a grid epoch, when
%            they differ by less; one month's products sit within it
%     MinOverlap (24)   the fewest matched months the calibration accepts
%
%   Outputs
%     ts   (1 x 1) shSeries  smoothed series on the epoch grid, formal
%          1-sigma stacks filled, every step in the history
%     rep  (1,1) struct  fields
%          mode       (1,1) string  "solution" | "neq"
%          order      (1,1) double  the VAR order used
%          nEpochs    (1,1) double  epochs on the output grid
%          nGaps      (1,1) double  epochs with no data
%          qcStat     (1 x K) double  innovation statistic per epoch; NaN
%                     when QC="none"
%          nRejected  (1,1) double  epochs QC rejected
%          centers    (F x 1) string  contributor labels; "neq" mode
%          sigma2     (F x K) double  per-epoch VCE variance factors;
%                     NaN where a centre has no file, and in
%                     fixed-weight mode
%          specRadius (1,1) double  spectral radius of the companion
%                     matrix; < 1 is stable
%          meanContribution  (1 x K) double  mean data share per epoch
%                     (Kurtenbach Sec. 3.3.2); NaN in gaps
%          epochs     (K,1) double  the epoch grid
%          gap        (1 x K) logical  which epochs were gaps
%          model      (1,1) struct  the estimateVAR struct, for reuse
%          memGB      (1,1) double  covariance storage actually used
%          observedBy (1 x K) string  "primary" | "second" | "both" |
%                     "none" per epoch; with SecondSeries only
%          second     (1,1) struct  the calibration, with SecondSeries
%                     only: scale (nmax+1 x 1) s_n, sigma (nmax+1 x 1)
%                     sigma_n (both 0 at degrees the index does not hold),
%                     offsetC, offsetS (nmax+1 x nmax+1) the offset o,
%                     overlap (1,1) the matched months
%
%   Example  % daily-type smoothing of a noisy series with a GAX prior
%     tsm = shSeries.fromFolder(gaxFolder).truncate(40);
%     [ts, rep] = shLowLevel.kalmanChain(tsObs, ModelSeries=tsm, Order=1);
%
%   Memory: the smoother stores two full (pP x pP) covariances per
%   epoch: n40/p1/T365 ~ 16 GB. For long daily series run in windows
%   or set Smoother=false; REP.memGB reports the actual footprint.
%
%   Reference: Kurtenbach, DGK C-683 (2012); Kvas, TU Graz PhD thesis
%   (2019). Numerics pre-validated in Python
%   (tools/dev/validate_kalman.py).
%
%   Error identifiers
%     shLowLevel:kalmanChain:badInput
%         OBSIN is neither an shSeries nor a SINEX folder path
%     shLowLevel:kalmanChain:badNeqWeights
%         NeqWeights does not have one entry per center
%     shLowLevel:kalmanChain:badSecondNoise
%         SecondNoise is neither "overlap" nor nmax+1 positive finite
%         sigmas
%     shLowLevel:kalmanChain:nmaxMismatch
%         the observation series and the model differ in nmax - truncate
%         first
%     shLowLevel:kalmanChain:noFiles
%         a SINEX folder holds no file matching Pattern
%     shLowLevel:kalmanChain:noNoise
%         an epoch has no formal sigmas and NoiseCov is empty - the update
%         has no weight to use
%     shLowLevel:kalmanChain:noOverlap
%         fewer than MinOverlap epochs of SecondSeries match OBSIN
%     shLowLevel:kalmanChain:notNEQ
%         a SINEX file carries no normal-equation block
%     shLowLevel:kalmanChain:secondInNeqMode
%         SecondSeries was given with a SINEX folder
%     shLowLevel:kalmanChain:secondMismatch
%         SecondSeries differs from OBSIN in nmax, GM or R
%     shLowLevel:kalmanChain:secondNotFinite
%         SecondSeries holds NaN or Inf
%
%   Developed by Matthias Weigelt with the help of Claude (Fable 5),
%   2026-08-17, 20:10 UTC. FitClimatology: Claude (Opus 5.5), 2026-10-21
%   (A34). SecondSeries: Claude (Opus 5.5), 2026-10-23 (WP9 9a).

arguments
    obsIn
    opts.ModelSeries (1,1) shSeries
    opts.Order (1,1) double {mustBeInteger, mustBePositive} = 1
    opts.Shrink (1,1) double {mustBeNonnegative} = 0
    opts.Structure (1,1) string {mustBeMember(opts.Structure, ["full","diagonal","orderblock"])} = "full"
    opts.CondFun = []
    opts.Epochs (:,1) double = []
    opts.Tolerance (1,1) double {mustBePositive} = 0.5/365.25
    opts.NoiseCov double = []
    opts.Climatology (1,1) logical = true
    opts.FitClimatology (1,1) string {mustBeMember(opts.FitClimatology, ["observations", "filtered"])} = "observations"
    opts.Smoother (1,1) logical = true
    opts.QC (1,1) string {mustBeMember(opts.QC, ["none","flag","reject"])} = "none"
    opts.QCAlpha (1,1) double {mustBeInRange(opts.QCAlpha, 0, 1, "exclusive")} = 1e-3
    opts.StoreCov (1,1) string {mustBeMember(opts.StoreCov, ["auto","full","matfile"])} = "auto"
    opts.Pattern (1,1) string = "*.snx*"
    opts.NeqWeights (:,1) double = []
    opts.SecondSeries (1,1) shSeries
    opts.SecondNoise = "overlap"
    opts.SecondScale (1,1) logical = true
    opts.SecondTolerance (1,1) double {mustBePositive} = 0.05
    opts.MinOverlap (1,1) double {mustBeInteger, mustBePositive} = 24
end
hasSecond = isfield(opts, 'SecondSeries');
if hasSecond && ~isa(obsIn, 'shSeries')
    error('shLowLevel:kalmanChain:secondInNeqMode', ...
        ['SecondSeries needs solution mode: a SINEX folder''s normal ' ...
         'equations refer to their provider''s background, which a ' ...
         'series does not share.']);
end

tsm = opts.ModelSeries;
nmax = tsm.nmax;
idx = shLowLevel.shIndex(nmax);
P = idx.P;

% ---- 1./2. process model from the model series residuals
[~, resid] = tsm.climatology;
X = zeros(P, resid.nEpochs);
for k = 1:resid.nEpochs
    g = resid.at(k);
    X(:, k) = shLowLevel.vecFromCS(g.C, g.S, idx);
end
if opts.Structure == "orderblock"
    % canonical partition: one block per (order m, C/S) pair
    blocks = {};
    for mo = 0:idx.Lmax
        for cs = 0:1
            bb = find(idx.m == mo & idx.cs == cs);
            if ~isempty(bb), blocks{end+1} = bb; end %#ok<AGROW>
        end
    end
    model = shLowLevel.estimateVAR(X, Order=opts.Order, ...
        Shrink=opts.Shrink, CondFun=opts.CondFun, ...
        Structure=opts.Structure, Blocks=blocks);
else
    model = shLowLevel.estimateVAR(X, Order=opts.Order, ...
        Shrink=opts.Shrink, CondFun=opts.CondFun, ...
        Structure=opts.Structure);
end

% ---- 3. observation records
solMode = isa(obsIn, 'shSeries');
if solMode
    tsObs = obsIn;
    if tsObs.nmax ~= nmax
        error('shLowLevel:kalmanChain:nmaxMismatch', ...
            'Observation nmax %d ~= model nmax %d - truncate first.', ...
            tsObs.nmax, nmax);
    end
    if opts.Climatology && opts.FitClimatology == "filtered"
        % A34: fit the climatology to a first pass without one
        o1 = opts;
        o1.Climatology = false;
        o1.FitClimatology = "observations";
        a1 = namedargs2cell(o1);
        ts1 = shLowLevel.kalmanChain(obsIn, a1{:});
        climObs = ts1.climatology;
        tsObs = tsObs - climatologySeries(climObs, tsObs);
    elseif opts.Climatology
        [climObs, tsObs] = tsObs.climatology;
    else
        climObs = [];
    end
    obsEpochs = tsObs.epochs(:);
    getObs = @(k) solutionRecord(tsObs, k, idx, opts.NoiseCov);
    sigma2Ep = [];
elseif isstring(obsIn) || ischar(obsIn)
    folders = string(obsIn); folders = folders(:).';
    F = numel(folders);
    snxAll = {}; epAll = []; ctrAll = [];
    for c = 1:F
        files = dir(fullfile(char(folders(c)), char(opts.Pattern)));
        if isempty(files)
            error('shLowLevel:kalmanChain:noFiles', ...
                'No files matching %s in %s.', opts.Pattern, folders(c));
        end
        for k = 1:numel(files)
            s = shLowLevel.readSINEX( ...
                fullfile(files(k).folder, files(k).name), Index=idx);
            if ~strcmp(s.kind, 'NEQ')
                error('shLowLevel:kalmanChain:notNEQ', ...
                    '%s carries no normal-equation block (kind = ''%s'').', ...
                    files(k).name, s.kind);
            end
            snxAll{end+1} = s; %#ok<AGROW>
            epAll(end+1, 1) = s.epoch; %#ok<AGROW>
            ctrAll(end+1, 1) = c; %#ok<AGROW>
        end
    end
    if F > 1 && ~isempty(opts.NeqWeights) && numel(opts.NeqWeights) ~= F
        error('shLowLevel:kalmanChain:badNeqWeights', ...
            'NeqWeights has %d entries for %d centers.', ...
            numel(opts.NeqWeights), F);
    end
    % ---- cluster files into epoch groups within Tolerance
    [epS, ordS] = sort(epAll);
    snxAll = snxAll(ordS); ctrAll = ctrAll(ordS);
    grpOf = zeros(numel(epS), 1); g = 0;
    for k = 1:numel(epS)
        if k == 1 || epS(k) - epS(k-1) > opts.Tolerance
            g = g + 1;
        end
        grpOf(k) = g;
    end
    nGrp = g;
    obsEpochs = zeros(nGrp, 1);
    groups = cell(1, nGrp); groupCtr = cell(1, nGrp);
    for g = 1:nGrp
        mem = find(grpOf == g);
        obsEpochs(g) = mean(epS(mem));
        groups{g} = snxAll(mem); groupCtr{g} = ctrAll(mem);
    end
    sigma2Ep = NaN(F, nGrp);
    climObs = [];
    getObs = @(g) neqGroupRecord(groups{g}, opts.NeqWeights, groupCtr{g});
else
    error('shLowLevel:kalmanChain:badInput', ...
        'OBSIN must be an shSeries or a SINEX folder path.');
end

if hasSecond
    sec = secondCalibration(opts.SecondSeries, obsIn, idx, opts);
end
if isempty(opts.Epochs)
    epGrid = obsEpochs;
    if hasSecond
        dS = min(abs(sec.t - obsEpochs.'), [], 2);
        add = sec.t(dS >= opts.SecondTolerance & sec.t >= min(obsEpochs) & ...
            sec.t <= max(obsEpochs));
        epGrid = sort([obsEpochs; add]);
    end
else
    epGrid = sort(opts.Epochs(:));
end
T = numel(epGrid);
obs = repmat(struct('l', [], 'R', [], 'N', [], 'b', []), 1, T);
for t = 1:T
    [d, k] = min(abs(obsEpochs - epGrid(t)));
    if d <= opts.Tolerance
        [obs(t), s2k, ck] = getObs(k);
        if ~solMode && ~isempty(s2k)
            sigma2Ep(ck, k) = s2k;
        end
    end
end
if hasSecond
    % each epoch of the second series observes the grid epoch nearest it
    by = repmat("none", 1, T);
    for t = 1:T
        if ~isempty(obs(t).l), by(t) = "primary"; end
    end
    [dS, tS] = min(abs(epGrid.' - sec.t), [], 2);
    for kS = find(dS < opts.SecondTolerance).'
        t = tS(kS);
        c = zeros(P, 1);
        if opts.Climatology
            gc = climObs.eval(sec.t(kS));
            c = shLowLevel.vecFromCS(gc.C, gc.S, idx);
        end
        obs(t) = addSecond(obs(t), sec, kS, idx, c);
        if any(by(t) == ["primary", "both"])
            by(t) = "both";
        else
            by(t) = "second";
        end
    end
end

% ---- 4./5. filter and smooth
if opts.StoreCov == "auto"
    store = "full"; if ~opts.Smoother, store = "diag"; end
else
    store = opts.StoreCov;
end
filt = shLowLevel.kalmanFilter(model, obs, StoreCov=store, ...
    QC=opts.QC, QCAlpha=opts.QCAlpha);
if opts.Smoother
    smo = shLowLevel.rtsSmoother(filt);
    xs = smo.xs; sig = smo.sig;
    if store == "matfile" && isfile(filt.covFile)
        delete(filt.covFile);                  % chain-internal temp
    end
else
    xs = filt.xf(1:P, :); sig = sqrt(max(filt.dPf(1:P, :), 0));
    if store == "matfile" && isfile(filt.covFile)
        delete(filt.covFile);                  % never read: no leak
    end
end

% ---- 6. repack (restore the observation climatology on the grid first)
L1 = nmax + 1;
Cs = zeros(L1, L1, T); Ss = zeros(L1, L1, T);
sC = zeros(L1, L1, T); sS = zeros(L1, L1, T);
for t = 1:T
    [Cs(:,:,t), Ss(:,:,t)] = shLowLevel.csFromVec(xs(:, t), idx);
    [sC(:,:,t), sS(:,:,t)] = shLowLevel.csFromVec(sig(:, t), idx);
    if solMode && opts.Climatology
        gc = climObs.eval(epGrid(t));
        Cs(:,:,t) = Cs(:,:,t) + gc.C;
        Ss(:,:,t) = Ss(:,:,t) + gc.S;
    end
end
hist = sprintf( ...
    "kalmanChain: %s mode, VAR(%d), %d epochs (%d gaps), smoother=%d", ...
    tern(solMode, "solution", "neq"), opts.Order, T, nnz(filt.gap), ...
    opts.Smoother);
if hasSecond
    hist = [hist, sprintf(", second series: %d epochs, %d of them alone", ...
        nnz(by == "second" | by == "both"), nnz(by == "second"))];
end
ts = shSeries(Cs, Ss=Ss, Epochs=epGrid, SigmaCs=sC, SigmaSs=sS, ...
    ProductType="KALMAN", History=hist);

memGB = 8 * numel(epGrid) * (model.order * P)^2 * 2 * double(opts.Smoother) / 1e9;
rep = struct('mode', tern(solMode, "solution", "neq"), ...
    'order', opts.Order, 'nEpochs', T, 'nGaps', nnz(filt.gap), ...
    'qcStat', filt.qcStat, 'nRejected', nnz(filt.qcReject), ...
    'specRadius', model.specRadius, ...
    'meanContribution', mean(filt.contrib, 1), ...
    'epochs', epGrid, 'gap', filt.gap, 'model', model, 'memGB', memGB);
if ~solMode
    rep.centers = folders(:);
    rep.sigma2 = sigma2Ep;
end
if hasSecond
    [oc, os] = shLowLevel.csFromVec(sec.off, idx);
    rep.observedBy = by;
    rep.second = struct('scale', sec.scale, 'sigma', sec.sigma, ...
        'offsetC', oc, 'offsetS', os, 'overlap', sec.overlap);
end
end

% ---------------------------------------------------------------- local
function [o, s2, ctr] = solutionRecord(tsObs, k, idx, noiseCov)
s2 = []; ctr = []; %#ok<NASGU> % uniform 3-output record contract
g = tsObs.at(k);
o = struct('l', shLowLevel.vecFromCS(g.C, g.S, idx), 'R', [], 'N', [], 'b', []);
if isempty(noiseCov)
    if isempty(g.sigmaC) || all(g.sigmaC(:) == 0)
        error('shLowLevel:kalmanChain:noNoise', ...
            ['Epoch %d has no formal sigmas and NoiseCov is empty - ' ...
             'pass NoiseCov explicitly (no silent noise assumptions).'], k);
    end
    o.R = shLowLevel.vecFromCS(g.sigmaC, g.sigmaS, idx).^2;
elseif isvector(noiseCov)
    o.R = noiseCov(:);
elseif size(noiseCov, 2) == size(noiseCov, 1)
    o.R = noiseCov;
else
    o.R = noiseCov(:, k);
end
end

function [o, s2, ctr] = neqGroupRecord(grp, wFixed, ctr)
%NEQGROUPRECORD one epoch group -> combined N/b via neqCombine.
if numel(grp) == 1
    s = grp{1};
    o = struct('l', [], 'R', [], 'N', s.M, 'b', s.M * s.x);
    s2 = NaN;
    return
end
neqs = [grp{:}];
if isempty(wFixed)
    [xc, out] = shLowLevel.neqCombine(neqs);            % per-epoch VCE
    s2 = out.sigma2;
else
    [xc, out] = shLowLevel.neqCombine(neqs, Weights=wFixed(ctr));
    s2 = NaN(numel(grp), 1);
end
o = struct('l', [], 'R', [], 'N', out.N, 'b', out.N * xc);
end

function sec = secondCalibration(tsB, tsR, idx, opts)
%SECONDCALIBRATION offset, scale and noise of the second series against
%   the observations, on the epochs both have (the help's equations).
nmax = idx.Lmax;
P = idx.P;
if tsB.nmax ~= nmax || abs(tsB.GM - tsR.GM) > 1e-9 * tsR.GM || ...
        abs(tsB.R - tsR.R) > 1e-9 * tsR.R
    error('shLowLevel:kalmanChain:secondMismatch', ...
        ['SecondSeries has nmax %d, GM %.10g, R %.10g; the observations ' ...
         'nmax %d, GM %.10g, R %.10g - truncate or rescale it first.'], ...
        tsB.nmax, tsB.GM, tsB.R, nmax, tsR.GM, tsR.R);
end
if ~all(isfinite(tsB.Cs(:))) || ~all(isfinite(tsB.Ss(:)))
    error('shLowLevel:kalmanChain:secondNotFinite', ...
        'SecondSeries holds NaN or Inf: drop those epochs first (ts.dropNaN).');
end
n1 = nmax + 1;
given = ~(isstring(opts.SecondNoise) || ischar(opts.SecondNoise));
if given
    g = opts.SecondNoise;
    if ~isnumeric(g) || numel(g) ~= n1 || ~all(isfinite(g(:))) || any(g(:) <= 0)
        error('shLowLevel:kalmanChain:badSecondNoise', ...
            'SecondNoise must be "overlap" or %d positive finite sigmas, one per degree.', n1);
    end
elseif string(opts.SecondNoise) ~= "overlap"
    error('shLowLevel:kalmanChain:badSecondNoise', ...
        'SecondNoise must be "overlap" or %d positive finite sigmas, one per degree.', n1);
end
tB = tsB.epochs(:);
tR = tsR.epochs(:);
XB = zeros(P, numel(tB));
for k = 1:numel(tB)
    gB = tsB.at(k);
    XB(:, k) = shLowLevel.vecFromCS(gB.C, gB.S, idx);
end
[dmin, near] = min(abs(tR.' - tB), [], 2);
matched = dmin < opts.SecondTolerance;
if nnz(matched) < opts.MinOverlap
    error('shLowLevel:kalmanChain:noOverlap', ...
        ['Only %d epochs of SecondSeries match the observations within %g ' ...
         'yr; the calibration needs at least %d (MinOverlap).'], ...
        nnz(matched), opts.SecondTolerance, opts.MinOverlap);
end
iB = find(matched);
iR = near(matched);
M = numel(iB);
XR = zeros(P, M);
VR = zeros(P, M);
for j = 1:M
    rec = solutionRecord(tsR, iR(j), idx, opts.NoiseCov);
    XR(:, j) = rec.l;
    if isvector(rec.R)
        VR(:, j) = rec.R(:);
    else
        VR(:, j) = diag(rec.R);
    end
end
dR = XR - mean(XR, 2);
dB = XB(:, iB) - mean(XB(:, iB), 2);
s = zeros(n1, 1);
sig = zeros(n1, 1);
for n = 0:nmax
    k = idx.n == n;
    if ~any(k), continue; end
    if opts.SecondScale
        den = sum(dR(k, :).^2, 'all') - sum(VR(k, :), 'all');
        if den > 0
            s(n + 1) = max(sum(dB(k, :) .* dR(k, :), 'all') / den, 0);
        end
    else
        s(n + 1) = 1;
    end
    fl = s(n + 1)^2 * mean(VR(k, :), 'all');
    v = mean((dB(k, :) - s(n + 1) * dR(k, :)).^2, 'all') - fl;
    sig(n + 1) = sqrt(max(v, fl));
end
if given
    sig = opts.SecondNoise(:);
    sig(setdiff(0:nmax, unique(idx.n)) + 1) = 0;
end
off = mean(XB(:, iB), 2) - s(idx.n + 1) .* mean(XR, 2);
sec = struct('t', tB, 'X', XB, 'scale', s, 'sigma', sig, 'off', off, ...
    'overlap', M);
end

function o = addSecond(o, sec, kS, idx, c)
%ADDSECOND add epoch kS of the second series to record o as a normal
%   equation, converting a solution record to its information form.
P = idx.P;
sv = sec.scale(idx.n + 1);
gv = sec.sigma(idx.n + 1);
use = sv > 0 & gv > 0;
w = zeros(P, 1);
w(use) = sv(use).^2 ./ gv(use).^2;
bb = zeros(P, 1);
bb(use) = sv(use) ./ gv(use).^2 .* (sec.X(use, kS) - sec.off(use) - sv(use) .* c(use));
if ~isempty(o.N)
    o.N = o.N + diag(w);
    o.b = o.b + bb;
elseif ~isempty(o.l)
    if isvector(o.R)
        N = diag(1 ./ o.R(:));
        b = o.l ./ o.R(:);
    else
        Rc = chol(o.R);
        N = Rc \ (Rc' \ eye(P));
        N = (N + N') / 2;
        b = N * o.l;
    end
    o = struct('l', [], 'R', [], 'N', N + diag(w), 'b', b + bb);
else
    o = struct('l', [], 'R', [], 'N', diag(w), 'b', bb);
end
end

function out = tern(c, a, b)
if c, out = a; else, out = b; end
end

function s = climatologySeries(clim, ts)
%CLIMATOLOGYSERIES The climatology CLIM evaluated at the epochs of TS, as
%   an shSeries with TS's constants, so that TS - s is epoch-matched.
n1 = ts.nmax + 1;
nT = ts.nEpochs;
C = zeros(n1, n1, nT);
S = C;
for k = 1:nT
    g = clim.eval(ts.epochs(k));
    C(:, :, k) = g.C;
    S(:, :, k) = g.S;
end
s = shSeries(C, Ss = S, Epochs = ts.epochs, GM = ts.GM, R = ts.R);
end
