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
%   Remove-compute-restore (Background). A global background series b(t)
%   - a hydrology or ESM model, a global solution's long wavelengths - is
%   removed from the observations before they become normal equations in
%   the basis and restored afterwards: TS = b + T (a + Proj c), and the
%   EWH outputs carry b's EWH too. With the process model fixed the chain
%   is linear, so a background holding a fraction c of an outside signal
%   leaves exactly 1 - c of that signal's leakage (Python-validated to
%   5.6e-15). Steffen et al. (2026) name this as the treatment of long
%   wavelengths and of signal outside the region; neither they nor
%   Woehnke et al. (2025) apply it. Measured in a closed loop
%   (tools/dev/validate_regional_rcr.py; nmax 30, a polar cap, a 30 cm
%   neighbour and a degree-2..4 random walk): the outside signal raised
%   the grid RMS over the region by 28%, and with an 80% background the
%   error came within 3.6% of what the same data give without any outside
%   signal. Two cautions from the same loop: a background must be a good
%   field - the observations' own unfiltered low degrees, restored as they
%   are, put their noise back and did worse than none; and the process
%   model may come from the full model series (no worse than from the
%   reduced one). The background is taken as error-free: it adds nothing
%   to the sigmas. In record mode the records must already be reduced by
%   it; it is only restored. A basis built on an index with Nmin above 2
%   leaves the low degrees to the background entirely - remove-compute-
%   restore of the low degrees. Degrees 0 and 1 of the background are
%   restored in TS; the EWH outputs start at degree min(2, B.idx Nmin), as
%   the rest of the chain.
%
%   Process-noise scales (QScale, QBlocks, EstimateQScale). Kurtenbach
%   (2012, Sec. 4.3.5) scales Q by a hand-tuned alpha and notes that for
%   real data such a factor cannot be fixed beforehand. Here Q(alpha) =
%   D Q D, D = diag(sqrt(alpha_k)) on block k of the basis coefficients
%   (QBlocks labels them; one block is Kurtenbach's alpha), so the
%   correlations of the estimated Q are kept. With EstimateQScale the
%   alphas are the maximum of the innovation likelihood (kalmanFilter's
%   Likelihood: -2 log L of every epoch given the past, summed), found by
%   fminbnd for one block and fminsearch for several, within a factor 1e4
%   of QScale, the start. Validated (tools/dev/validate_regional_
%   adaptive.py): the likelihood equals the dense joint Gaussian one to
%   3.9e-15; for one block its maximum is the EM fixed point of Shumway
%   and Stoffer (1982) to 1.3e-8; in a closed loop with alpha = (4, 0.5)
%   on two blocks the estimates scatter about the truth (mean 3.95, 0.49
%   over 30 seeds, relative spread 9 and 20 percent) and lower the state
%   error against alpha = 1 in 30 of 30 seeds. Sigma0, the filter's
%   start, is not scaled (as for QScale since v5.15.0), and the
%   likelihood is that of the model with this start. Order > 1 and
%   CondFun pass through to regionalProcessModel: a VAR(2) truth gives
%   the lower -2 log L at Order 2 in 10 of 10 seeds (CLAIM 4), and
%   shLowLevel.buildCondFun(..., Basis = B) turns Kvas' space-domain
%   conditioner into one of basis covariances.
%
%   A prior in place of the model series' Q (ProcessCov, StartCov). An SH
%   covariance C (P x P, B.idx order) - the non-stationary SPDE-Matern
%   prior of shLowLevel.maternCovariance, or any other - replaces the
%   process noise the model series gives: Q0 = Proj C Proj', the VAR
%   coefficients still estimated from ModelSeries. QScale, QBlocks and
%   EstimateQScale then scale it as they scale the estimated Q, so the
%   block scales of 8i are the coarse form of a prior whose sigma varies
%   in space. StartCov likewise replaces Sigma0, the filter's start. A
%   model series of a few years cannot estimate a full Q in K unknowns;
%   a prior has K x K structure from two fields. In the closed loop of
%   tools/dev/validate_matern_prior.py (CLAIM 6) the true non-stationary
%   prior gives smoothed sigmas that are honest (z-rms 0.98-1.02 over 20
%   seeds) where a diagonal Q from a 60-epoch model series gives 1.14, at
%   0.94 of its error.
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
%     QScale (1)     (1,1) or (nB,1) double  Kurtenbach's alpha, one
%                    per block of QBlocks: Q -> D Q D; the start of the
%                    search with EstimateQScale
%     QBlocks ([])   (K,1) double  block label 1..nB of every basis
%                    coefficient; [] is one block
%     EstimateQScale (false)  (1,1) logical  estimate the alphas by
%                    maximum likelihood of the innovations, see above
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
%     NoiseCov ([])  solution mode, in B.idx order: a vector is one
%                    diagonal and a square matrix one full covariance,
%                    both used at every epoch; any other (P,M) matrix
%                    holds one diagonal per epoch of the series (column
%                    k for epoch k) - so with M = P it is read as a full
%                    covariance. [] takes the formal sigmas
%     Climatology (true)  (1,1) logical  solution mode: remove and
%                    restore the observation climatology, see above
%     FitClimatology ("observations")  "observations" | "filtered"   what
%                    that climatology is fitted to, as in kalmanChain:
%                    "observations" fits it to the (background-reduced)
%                    series, so the noise of the fit is restored unfiltered
%                    (A34); "filtered" runs the chain once with Climatology
%                    = false and no background, fits the climatology to
%                    that estimate, removes it, filters the residual and
%                    restores it through Proj - twice the cost; 0.89-1.96
%                    against 14.5 cm grid RMS in the 8e closed loop
%                    (tools/dev/validate_climatology_restore.py). Ignored
%                    when Climatology = false and in records mode.
%     Lag (Inf)      (1,1) double  smoothing lag in epochs
%                    (rtsSmoother's Lag): Inf the full RTS pass, 0 the
%                    filter estimates alone
%     QC ("none")    "none" | "flag" | "reject"   innovation QC (see
%                    kalmanFilter)
%     QCAlpha (1e-3) (1,1) double  its false-alarm level
%     StoreCov ("full")  "full" | "matfile"   where the filter keeps the
%                    covariances the smoother needs (see kalmanFilter); a
%                    matfile is deleted after smoothing
%     AddNoiseCov ([])  (P,P) double  solution mode: an SH covariance in
%                    B.idx order added to every epoch's noise covariance
%                    (the formal sigmas' or NoiseCov's; a scalar NoiseCov
%                    s is s I) - the error of a background model the
%                    series had removed, e.g. from
%                    shLowLevel.backgroundErrorCov; refused in record mode.
%                    Symmetric with a non-negative diagonal; the sum must
%                    be positive definite. When the noise is the same at
%                    every epoch (scalar, vector or square NoiseCov) the
%                    sum is factorised once; with formal sigmas, which
%                    change per epoch, once per epoch - a P x P Cholesky,
%                    about 3e11 flops at nmax 96
%     ProcessCov ([])  (P,P) double  SH covariance in B.idx order that
%                    replaces the process noise: Q0 = Proj C Proj', then
%                    scaled by QScale / EstimateQScale, see above
%     StartCov ([])  (P,P) double  SH covariance in B.idx order that
%                    replaces Sigma0, the filter's start: Proj C Proj'
%     Background ([]) (1,1) shSeries  global background, nmax =
%                    B.idx.Lmax, with an epoch within Tolerance of every
%                    observation and every output epoch: removed from the
%                    observations (solution mode) and restored in every
%                    output, see above
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
%                           restored climatology included (a + Proj c);
%                           the background is NOT in them
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
%          background       (1,1) logical  whether a Background was
%                           removed and restored
%          negLogLik        (1,1) double  -2 log likelihood of all
%                           observations given the process model, without
%                           the terms no model parameter changes
%                           (kalmanFilter's Likelihood, summed)
%          qScale           (nB,1) double  the alphas used (estimated
%                           with EstimateQScale)
%          qBlocks          (K,1) double  the block of every coefficient
%          landMean         (1,1) struct  for a basis built with Ocean
%                           (shLowLevel.regionalBasis, the sea-level
%                           fingerprint in T): the mean land EWH over the
%                           region core that the coefficients carry,
%                           B.fingerprint.coreLandEWH * a, with its sigma
%                           from the full smoothed covariance; [] for any
%                           other basis. The background is not in it.
%                           Fields
%                           mean   (1,E) double  [m]
%                           sigma  (1,E) double  its 1-sigma [m]
%          processCov       (1,1) logical  whether ProcessCov replaced Q
%          startCov         (1,1) logical  whether StartCov replaced
%                           Sigma0
%          qEstimate        (1,1) struct  the search, fields
%                           estimated    (1,1) logical  EstimateQScale
%                           start        (nB,1) double  QScale given
%                           evaluations  (1,1) double  filter runs of the
%                                        search; 0 when not estimated
%                           atBound      (1,1) logical  an alpha ended
%                                        within 1 percent of the factor
%                                        1e4 search limit
%                           exitFlag     (1,1) double  of fminbnd or
%                                        fminsearch; NaN when not
%                                        estimated
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
%     shLowLevel:regionalKalman:badBackground
%         Background is not an shSeries of the basis' nmax, or has no
%         epoch within Tolerance of an observation or output epoch
%     shLowLevel:regionalKalman:badQBlocks
%         QBlocks is not one label 1..nB per basis coefficient with every
%         block used, or QScale has neither 1 nor nB entries
%     shLowLevel:regionalKalman:badAddNoiseCov
%         AddNoiseCov is not a finite, symmetric P x P matrix with a
%         non-negative diagonal in the basis' index, was given in record
%         mode, or makes the noise covariance not positive definite
%     shLowLevel:regionalKalman:badPrior
%         ProcessCov or StartCov is not a finite, symmetric P x P matrix
%         with a non-negative diagonal in the basis' index
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
%     Steffen, R., Woehnke, V., Weigelt, M., Eicker, A. (2026), Improved
%       regional mass change estimation using Slepian functions in a
%       Kalman filter framework, IAG Symposia, doi:10.1007/1345_2026_348.
%     Shumway, R.H., Stoffer, D.S. (1982), An approach to time series
%       smoothing and forecasting using the EM algorithm, J. Time Ser.
%       Anal. 3, 253-264.
%     Lindgren, F., Rue, H., Lindstroem, J. (2011), An explicit link
%       between Gaussian fields and Gaussian Markov random fields: the
%       stochastic partial differential equation approach, J. R. Stat.
%       Soc. B 73, 423-498.
%
%   Numerics pre-validated in Python (tools/dev/validate_regional_kalman.py,
%   tools/dev/validate_regional_rcr.py, tools/dev/validate_regional_
%   adaptive.py, tools/dev/validate_matern_prior.py).
%
%   Developed by Matthias Weigelt with the help of Claude (Opus 5.5),
%   2026-10-21 (Background: 2026-10-21, WP8 8e; process-noise scales:
%   2026-10-21, WP8 8i; FitClimatology: 2026-10-21, A34; ProcessCov and
%   StartCov: 2026-11-06, WP9 9g; landMean: 2026-11-06, WP9 9h;
%   AddNoiseCov: 2026-11-06, WP9 9i).
arguments
    obsIn
    B (1,1) struct
    opts.ModelSeries (1,1) shSeries
    opts.Order (1,1) double {mustBeInteger, mustBePositive} = 1
    opts.Shrink (1,1) double {mustBeNonnegative} = 0
    opts.Structure (1,1) string {mustBeMember(opts.Structure, ["full", "diagonal"])} = "full"
    opts.CondFun = []
    opts.QScale (:,1) double {mustBePositive} = 1
    opts.QBlocks (:,1) double = []
    opts.EstimateQScale (1,1) logical = false
    opts.GroundNoise (1,1) double {mustBeNonnegative} = 0
    opts.kn double = []
    opts.Epochs (:,1) double = []
    opts.Tolerance (1,1) double {mustBePositive} = 0.5/365.25
    opts.NoiseCov double = []
    opts.Climatology (1,1) logical = true
    opts.FitClimatology (1,1) string {mustBeMember(opts.FitClimatology, ["observations", "filtered"])} = "observations"
    opts.Lag (1,1) double {mustBeNonnegative} = Inf
    opts.QC (1,1) string {mustBeMember(opts.QC, ["none", "flag", "reject"])} = "none"
    opts.QCAlpha (1,1) double {mustBeInRange(opts.QCAlpha, 0, 1, "exclusive")} = 1e-3
    opts.StoreCov (1,1) string {mustBeMember(opts.StoreCov, ["full", "matfile"])} = "full"
    opts.AddNoiseCov double = []
    opts.ProcessCov double = []
    opts.StartCov double = []
    opts.Background = []
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
bg = opts.Background;
hasBg = ~(isnumeric(bg) && isempty(bg));
if hasBg && ~(isa(bg, 'shSeries') && isscalar(bg) && bg.nmax == L)
    error('shLowLevel:regionalKalman:badBackground', ...
        'Background must be an shSeries reaching degree %d, the basis'' band limit.', L);
end
addC = opts.AddNoiseCov;                        % 9i, checked before any work
if ~isempty(addC)
    if ~isa(obsIn, 'shSeries')
        error('shLowLevel:regionalKalman:badAddNoiseCov', ...
            ['AddNoiseCov is a solution-mode option; add it to the records'' ' ...
             'covariances before forming their normal equations.']);
    end
    if ~covOK(addC, P)
        error('shLowLevel:regionalKalman:badAddNoiseCov', ['AddNoiseCov must be a ' ...
            'finite, symmetric %d x %d matrix in B.idx order with a non-negative ' ...
            'diagonal.'], P, P);
    end
end
if (~isempty(opts.ProcessCov) && ~covOK(opts.ProcessCov, P)) || ...
        (~isempty(opts.StartCov) && ~covOK(opts.StartCov, P))
    error('shLowLevel:regionalKalman:badPrior', ['ProcessCov and StartCov must be ' ...
        'finite, symmetric %d x %d matrices in B.idx order with a non-negative ' ...
        'diagonal.'], P, P);
end

% ---- 1. process model in the basis
[blocks, nB] = qBlocks(opts.QBlocks, K);
qs0 = opts.QScale(:);
if isscalar(qs0)
    qs0 = repmat(qs0, nB, 1);
elseif numel(qs0) ~= nB
    error('shLowLevel:regionalKalman:badQBlocks', ...
        'QScale has %d entries for %d blocks; give one, or one per block.', ...
        numel(qs0), nB);
end
hasProc = ~isempty(opts.ProcessCov);
hasStart = ~isempty(opts.StartCov);
plain = nB == 1 && ~opts.EstimateQScale && ~hasProc;   % v5.18.0's path, bitwise
qModel = 1;
if plain, qModel = qs0; end
[model, pinfo] = shLowLevel.regionalProcessModel(tsm, B, Order = opts.Order, ...
    Shrink = opts.Shrink, Structure = opts.Structure, CondFun = opts.CondFun, ...
    QScale = qModel, GroundNoise = opts.GroundNoise, kn = opts.kn);
Q0 = model.Q;
if hasProc                                      % 9g: a prior as Q
    Q0 = basisCov(opts.ProcessCov, B, P);
end
if ~plain
    model.Q = scaleQ(Q0, qs0, blocks);
end
if hasStart                                     % 9g: a prior as the start
    model.Sigma0 = basisCov(opts.StartCov, B, P);
end

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
    if hasBg                                    % remove
        [bC, bS] = backgroundAt(bg, tsObs.epochs, opts.Tolerance);
        tsObs = tsObs - shSeries(bC, Ss = bS, Epochs = tsObs.epochs, ...
            GM = tsObs.GM, R = tsObs.R);
    end
    if opts.Climatology && opts.FitClimatology == "filtered"
        % A34: fit the climatology to a first pass without one (and
        % without the background, which is already removed)
        o1 = opts;
        o1.Climatology = false;
        o1.FitClimatology = "observations";
        o1.Background = [];
        a1 = namedargs2cell(o1);
        ts1 = shLowLevel.regionalKalman(tsObs, B, a1{:});
        climObs = ts1.climatology;
        tsObs = tsObs - climatologySeries(climObs, tsObs);
    elseif opts.Climatology
        [climObs, tsObs] = tsObs.climatology;
    end
    obsEpochs = tsObs.epochs(:);
    cache = constantNoiseCache(opts.NoiseCov, addC, B, P);
    getObs = @(k) solutionRecord(tsObs, k, B, opts.NoiseCov, addC, cache);
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

% ---- 3. process-noise scales, filter and smoother; 4. the functionals
qs = qs0;
qEst = struct('estimated', opts.EstimateQScale, 'start', qs0, ...
    'evaluations', 0, 'atBound', false, 'exitFlag', NaN);
if opts.EstimateQScale
    [qs, qEst] = estimateScales(model, Q0, blocks, qs0, obs, qEst);
    model.Q = scaleQ(Q0, qs, blocks);
end
filt = shLowLevel.kalmanFilter(model, obs, StoreCov = opts.StoreCov, ...
    QC = opts.QC, QCAlpha = opts.QCAlpha, Likelihood = true);
[fB, Fg, gLat, gLon, areaFrac, wc, fEwh] = regionFunctionals(B, opts.kn, tsm);
F = [B.T; fB; Fg];
hasLand = isfield(B, 'fingerprint') && ~isempty(B.fingerprint);
if hasLand                                      % 9h: land mass of the coefficients
    F = [F; B.fingerprint.coreLandEWH];
end
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
if hasBg                                        % restore
    [bC, bS] = backgroundAt(bg, epGrid, opts.Tolerance);
    Cs = Cs + bC;
    Ss = Ss + bS;
end
modeName = "records";
if solMode, modeName = "solution"; end
ts = shSeries(Cs, Ss = Ss, Epochs = epGrid, GM = tsm.GM, R = tsm.R, ...
    SigmaCs = sC, SigmaSs = sS, ProductType = "KALMAN", History = sprintf( ...
    "regionalKalman: %s basis, K = %d, %s mode, VAR(%d), %d epochs (%d gaps), lag %g%s", ...
    B.type, K, modeName, opts.Order, nE, nnz(filt.gap), opts.Lag, ...
    tern(hasBg, ", background removed and restored", "")));

% ---- the region
basin = [];
gridOut = [];
if ~isempty(fB)
    ewh = Fg * a;
    bmean = fB * a;
    if hasBg                                    % the background's EWH
        idxBg = shLowLevel.shIndex(L, Nmin = min(2, idx.minDegree));
        Ybg = shLowLevel.ylm(deg2rad(gLat), deg2rad(gLon), idxBg) .* ...
            fEwh(idxBg.n + 1).';
        Ebg = zeros(numel(gLat), nE);
        for t = 1:nE
            Ebg(:, t) = Ybg * shLowLevel.vecFromCS(bC(:, :, t), bS(:, :, t), idxBg);
        end
        ewh = ewh + Ebg;
        bmean = bmean + (wc.' * Ebg) / sum(wc);
    end
    basin = struct('mean', bmean, 'sigma', smo.sigF(P + 1, :), ...
        'areaFraction', areaFrac);
    gridOut = struct('latDeg', gLat, 'lonDeg', gLon, 'ewh', ewh, ...
        'sigma', smo.sigF(P + 2:end, :));
end
landMean = [];
if hasLand
    landMean = struct('mean', B.fingerprint.coreLandEWH * a, ...
        'sigma', smo.sigF(end, :));
end
memGB = 8 * nE * (model.order * K)^2 * 2 / 1e9;
out = struct('mode', modeName, 'basisType', B.type, 'K', K, ...
    'order', opts.Order, 'epochs', epGrid, 'nEpochs', nE, ...
    'gap', filt.gap, 'nGaps', nnz(filt.gap), 'a', a, 'sigA', smo.sig, ...
    'covLast', smo.PsLast, 'qcStat', filt.qcStat, ...
    'nRejected', nnz(filt.qcReject), 'specRadius', model.specRadius, ...
    'meanContribution', mean(filt.contrib, 1), ...
    'representation', pinfo.representation, 'model', model, ...
    'basin', basin, 'grid', gridOut, 'memGB', memGB, 'background', hasBg, ...
    'negLogLik', sum(filt.negLogLik), 'qScale', qs, 'qBlocks', blocks, ...
    'qEstimate', qEst, 'processCov', hasProc, 'startCov', hasStart, ...
    'landMean', landMean);
end

function Cb = basisCov(C, B, P)
% An SH covariance (P x P, B.idx order) in the basis: Proj C Proj'
% (checked by covOK before section 1).
Cb = full(B.Proj * C * B.Proj.');
Cb = (Cb + Cb.') / 2;
end

function [blocks, nB] = qBlocks(lab, K)
% Block labels of the basis coefficients: 1..nB, every block used.
if isempty(lab)
    blocks = ones(K, 1);
    nB = 1;
    return
end
lab = lab(:);
nB = max(lab);
if numel(lab) ~= K || any(lab < 1 | lab ~= round(lab)) || ...
        numel(unique(lab)) ~= nB
    error('shLowLevel:regionalKalman:badQBlocks', ...
        ['QBlocks must give one label 1..nB per basis coefficient (K = %d), ' ...
         'every block used.'], K);
end
blocks = lab;
end

function Q = scaleQ(Q0, qs, blocks)
% Q(alpha) = D Q0 D, D = diag(sqrt(alpha of each coefficient's block)).
d = sqrt(qs(blocks));
Q = d .* Q0 .* d.';
Q = (Q + Q.') / 2;
end

function [qs, qEst] = estimateScales(model, Q0, blocks, qs0, obs, qEst)
% Maximum likelihood of the innovations over log alpha, within a factor
% 1e4 of the start: fminbnd for one block, fminsearch (through tanh, so
% the search stays inside the limit) for several.
lim = log(1e4);
th0 = log(qs0);
nB = numel(qs0);
nEval = 0;
    function v = nll(th)
        nEval = nEval + 1;
        m = model;
        m.Q = scaleQ(Q0, exp(th), blocks);
        f = shLowLevel.kalmanFilter(m, obs, StoreCov = "diag", ...
            Contribution = false, Likelihood = true);
        v = sum(f.negLogLik);
        if ~isfinite(v), v = realmax; end
    end
if nB == 1
    [th, ~, flag] = fminbnd(@nll, th0 - lim, th0 + lim, ...
        optimset('TolX', 1e-6, 'Display', 'off'));
else
    phi2th = @(ph) th0 + lim * tanh(ph);
    [ph, ~, flag] = fminsearch(@(ph) nll(phi2th(ph)), zeros(nB, 1), ...
        optimset('TolX', 1e-6, 'TolFun', 1e-8, 'MaxFunEvals', 400 * nB, ...
        'MaxIter', 400 * nB, 'Display', 'off'));
    th = phi2th(ph);
end
qs = exp(th(:));
qEst.evaluations = nEval;
qEst.atBound = any(abs(th(:) - th0) > 0.99 * lim);
qEst.exitFlag = flag;
end

% ---------------------------------------------------------------- local
function ok = covOK(C, P)
% One check for every SH covariance option: P x P, finite, symmetric to
% 1e-12 of its largest element, a non-negative diagonal. Definiteness is
% left to the Cholesky factor the chain forms (a rank-deficient
% empirical C is legal when added to a definite noise covariance).
ok = isnumeric(C) && isequal(size(C), [P P]) && all(isfinite(C(:)));
if ok
    sc = max(abs(C(:)));
    ok = max(abs(C - C.'), [], 'all') <= 1e-12 * sc && all(diag(C) >= 0);
end
end

function cache = constantNoiseCache(noiseCov, addC, B, P)
% With AddNoiseCov and a noise covariance that is the same at every epoch
% (scalar, vector or square NoiseCov), the epoch covariance C0 = noise + C
% and its Cholesky factor are formed once and only b changes per epoch -
% the operations of regionalNEQ's weighting, in its order, so the records
% are the ones regionalNEQ(B, "solution", Cov = C0) returns.
cache = [];
if isempty(addC) || isempty(noiseCov) || ...
        ~(isvector(noiseCov) || size(noiseCov, 2) == size(noiseCov, 1))
    return
end
C0 = expandNoise(noiseCov, P) + addC;
[Lc, flag] = chol((C0 + C0') / 2, 'lower');
if flag ~= 0
    error('shLowLevel:regionalKalman:badAddNoiseCov', ...
        ['The noise covariance plus AddNoiseCov is not positive definite ' ...
         '(Cholesky failed at column %d).'], flag);
end
Aw = Lc \ B.T;
N = full(Aw' * Aw);
cache = struct('Lc', Lc, 'Aw', Aw, 'N', (N + N') / 2);
end

function C = expandNoise(C, P)
% A scalar variance is s I, a vector the diagonal, a square matrix itself.
if isscalar(C)
    C = C * eye(P);
elseif isvector(C)
    C = diag(C);
end
end

function o = solutionRecord(tsObs, k, B, noiseCov, addC, cache)
% One epoch of the series as a basis normal equation (regionalNEQ).
g = tsObs.at(k);
l = shLowLevel.vecFromCS(g.C, g.S, B.idx);
if ~isempty(cache)                              % 9i: constant noise + C
    yw = cache.Lc \ l;
    o = struct('l', [], 'R', [], 'N', cache.N, 'b', full(cache.Aw' * yw));
    return
end
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
if ~isempty(addC)                               % 9i: background-model error
    C = expandNoise(C, numel(l)) + addC;
    try
        rec = shLowLevel.regionalNEQ(B, "solution", Solution = l, Cov = C);
    catch me
        if me.identifier ~= "shLowLevel:regionalNEQ:notPositiveDefinite"
            rethrow(me);
        end
        error('shLowLevel:regionalKalman:badAddNoiseCov', ...
            'Epoch %d: the noise covariance plus AddNoiseCov is not positive definite.', k);
    end
else
    rec = shLowLevel.regionalNEQ(B, "solution", Solution = l, Cov = C);
end
o = struct('l', [], 'R', [], 'N', rec.N, 'b', rec.b);
end

function [fB, Fg, lat, lon, areaFrac, wc, f] = regionFunctionals(B, kn, tsm)
% EWH at the region's quadrature points and their area-weighted mean, as
% rows acting on the basis coefficients; empty without kn or a region. wc
% are the area weights of the points, f the EWH kernel.
fB = []; Fg = []; lat = []; lon = []; areaFrac = NaN; wc = []; f = [];
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

function [bC, bS] = backgroundAt(bg, ep, tol)
% The background's coefficients at the epochs EP, nearest within TOL.
n1 = bg.nmax + 1;
bC = zeros(n1, n1, numel(ep));
bS = bC;
for t = 1:numel(ep)
    [d, k] = min(abs(bg.epochs - ep(t)));
    if isempty(d) || d > tol
        error('shLowLevel:regionalKalman:badBackground', ...
            'The background has no epoch within Tolerance of %.4f.', ep(t));
    end
    bC(:, :, t) = bg.Cs(:, :, k);
    bS(:, :, t) = bg.Ss(:, :, k);
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
