function [model, info] = regionalProcessModel(ts, B, opts)
%REGIONALPROCESSMODEL Kurtenbach's process model in a regional basis.
%
%   [MODEL, INFO] = shLowLevel.regionalProcessModel(TS, B) estimates the
%   stochastic process model of the regional Kalman filter from a
%   geophysical model series TS - hydrology, ESA ESM, AOD1B errors - in
%   the coefficients of the regional basis B of shLowLevel.regionalBasis,
%   following Kurtenbach (2012, DGK C-683, Sec. 3.2):
%     1. the climatology of TS (mean, trend, annual, semi-annual; his eq.
%        3.81) is removed with ts.climatology;
%     2. every epoch is projected onto the basis, a_t = B.Proj x_t
%        (shLowLevel.regionalProject). The two steps commute - the
%        climatology is a fit along time with one design for every
%        coefficient, the projection a map along the coefficients - so
%        their order does not matter (Python-validated to 6e-16);
%     3. the VAR(Order) model is estimated from a_t by
%        shLowLevel.estimateVAR; Order = 1 is his eqs. 3.84-3.85,
%           B = Sigma(1) Sigma(0)^-1,   Q = Sigma(0) - B Sigma(1)'.
%   MODEL has the fields of estimateVAR's output and drives
%   shLowLevel.kalmanFilter / rtsSmoother with the basis coefficients as
%   the state. On the SH basis (B.T = I) it IS the model kalmanChain
%   builds - bitwise, which is the regional chain's oracle.
%
%   Kurtenbach's two adjustments (Sec. 4.3.5, Table 4.1):
%     QScale       Q -> alpha Q (his eq. 4.8): less trust in the process
%                  model where its variability is below the data's. B and
%                  Sigma(0) are unchanged. In his closed loop alpha = 10
%                  cut the largest error RMS from 4.83 to 3.41 cm EWH and
%                  the mean from 1.12 to 1.01 cm; above ~15 it degrades
%                  again. Underestimated process variance suppresses
%                  signal, overestimated variance is nearly harmless.
%     GroundNoise  an isotropic, temporally uncorrelated variance added
%                  to Sigma(0) - his 2 cm EWH for the real-data series
%                  (Sec. 5.2), "in the form of a diagonal matrix". Read
%                  here as the white EWH field band-limited to the index
%                  with pointwise variance GroundNoise^2 everywhere:
%                  sigma^2 / (P f_n^2) per Stokes coefficient, f_n the EWH
%                  kernel of kernelFactors (the addition theorem makes the
%                  pointwise variance exactly sigma^2; Python-validated to
%                  1.3e-14), carried into the basis as Proj G Proj'.
%                  Because it changes Sigma(0), it changes B as well as Q
%                  - in his simulation it made results worse, which is why
%                  both default to off.
%
%   INFO.representation says how much of the model's regional signal the
%   basis can carry at all: 1 - E(residual) / E(signal), the energies of
%   x_t - T a_t and of x_t over the buffered region and all epochs (1 for
%   the SH basis). A basis that represents 70% of the signal cannot give
%   the filter more.
%
%   Inputs
%     ts  (1,1) shSeries  the model series, nmax >= B.idx.Lmax, at the
%         sampling of the filter (daily for daily solutions)
%     B   (1,1) struct    a basis from shLowLevel.regionalBasis
%
%   Options
%     Order (1)          (1,1) double  VAR order (see estimateVAR)
%     Shrink (0)         (1,1) double  diagonal loading (see estimateVAR)
%     Structure ("full") "full" | "diagonal"   coupling of the estimate;
%                        estimateVAR's "orderblock" has no meaning for a
%                        regional basis
%     CondFun ([])       function handle  covariance conditioning on the
%                        K x K basis covariances (see estimateVAR)
%     Climatology (true) (1,1) logical  remove TS's climatology first;
%                        false when TS is already reduced
%     QScale (1)         (1,1) double  Kurtenbach's alpha
%     GroundNoise (0)    (1,1) double  isotropic ground noise [m EWH]
%     kn ([])            (>=Lmax+1,1) double  load Love numbers, required
%                        by GroundNoise > 0 (never invented)
%
%   Outputs
%     model  (1,1) struct  as returned by shLowLevel.estimateVAR, which
%            documents every field; Q is the scaled one
%     info   (1,1) struct  fields
%            A               (K,T) double  basis coefficients of the
%                            reduced model series - the realisation
%            epochs          (T,1) double  its epochs [decimal years]
%            clim            shClimatology  the removed climatology; []
%                            with Climatology = false
%            representation  (1,1) double  share of the regional signal
%                            energy the basis carries, see above
%            minEigQ         (1,1) double  smallest eigenvalue of Q; a
%                            negative one means Q is not a covariance
%            groundCov       (K,K) double  the covariance added to
%                            Sigma(0); [] without GroundNoise
%            qScale          (1,1) double  the QScale option
%            groundNoise     (1,1) double  the GroundNoise option [m]
%
%   Example
%     B = tsModel.regionalBasis("Elbe", Type = "slepian", Threshold = 0.5);
%     [model, info] = tsModel.regionalProcessModel(B, QScale = 10);
%     info.representation, model.specRadius
%
%   Error identifiers
%     shLowLevel:regionalProcessModel:badBasis
%         B is not a basis from shLowLevel.regionalBasis
%     shLowLevel:regionalProcessModel:nmaxMismatch
%         the series' nmax is below the basis' band limit
%     shLowLevel:regionalProcessModel:missingLoveNumbers
%         GroundNoise > 0 without kn
%
%   References
%     Kurtenbach, E. (2012), Entwicklung eines Kalman-Filters zur
%       Bestimmung kurzzeitiger Variationen des Erdschwerefeldes aus Daten
%       der Satellitenmission GRACE, DGK C-683, Sec. 3.2, 4.3.5, 5.2.
%
%   Numerics pre-validated in Python (tools/dev/validate_regional_process.py).
%
%   Developed by Matthias Weigelt with the help of Claude (Opus 5.5),
%   2026-10-20.
arguments
    ts (1,1) shSeries
    B (1,1) struct
    opts.Order (1,1) double {mustBeInteger, mustBePositive} = 1
    opts.Shrink (1,1) double {mustBeNonnegative} = 0
    opts.Structure (1,1) string {mustBeMember(opts.Structure, ["full", "diagonal"])} = "full"
    opts.CondFun = []
    opts.Climatology (1,1) logical = true
    opts.QScale (1,1) double {mustBePositive} = 1
    opts.GroundNoise (1,1) double {mustBeNonnegative} = 0
    opts.kn double = []
end
if ~all(isfield(B, {'T', 'Proj', 'idx', 'type', 'region'}))
    error('shLowLevel:regionalProcessModel:badBasis', ...
        'B must be a basis from shLowLevel.regionalBasis.');
end
idx = B.idx;
if ts.nmax < idx.Lmax
    error('shLowLevel:regionalProcessModel:nmaxMismatch', ...
        'The series reaches degree %d, the basis needs %d.', ts.nmax, idx.Lmax);
end
if opts.GroundNoise > 0 && isempty(opts.kn)
    error('shLowLevel:regionalProcessModel:missingLoveNumbers', ...
        ['GroundNoise is an EWH variance and needs the load Love numbers ' ...
         'kn to become a Stokes variance; the toolbox never invents them.']);
end

% ---- 1./2. climatology removed, then every epoch in the basis
if opts.Climatology
    [clim, resid] = ts.climatology;
else
    clim = [];
    resid = ts;
end
A = shLowLevel.regionalProject(resid.Cs, resid.Ss, B);

% ---- ground noise in the basis
G = [];
if opts.GroundNoise > 0
    f = shLowLevel.kernelFactors("ewh", idx.Lmax, ts.GM, ts.R, kn = opts.kn);
    vs = opts.GroundNoise^2 ./ (idx.P * f(idx.n + 1).^2);
    G = full(B.Proj * (vs .* B.Proj'));
    G = (G + G') / 2;
end

% ---- 3. VAR(p), then alpha
model = shLowLevel.estimateVAR(A, Order = opts.Order, Shrink = opts.Shrink, ...
    CondFun = opts.CondFun, Structure = opts.Structure, Sigma0Add = G);
if opts.QScale ~= 1
    model.Q = opts.QScale * model.Q;
end

info = struct('A', A, 'epochs', resid.epochs(:), 'clim', clim, ...
    'representation', representation(resid, A, B), ...
    'minEigQ', min(eig((model.Q + model.Q') / 2)), 'groundCov', G, ...
    'qScale', opts.QScale, 'groundNoise', opts.GroundNoise);
end

function rep = representation(resid, A, B)
% Share of the signal energy over the buffered region that T A carries.
if B.type == "sh" || isempty(B.region.mask)
    rep = 1;
    return
end
idx = B.idx;
L = idx.Lmax;
os = B.region.overSample;
[~, w, qgrid] = shLowLevel.synthesisMatrix(idx, NLat = os * (L + 1), ...
    NLon = os * (2 * L + 2), GridOnly = true);
nLon = numel(qgrid.lonDeg);
im = find(B.region.mask > 0);
latRow = qgrid.latDeg(ceil(im / nLon));
lonRow = qgrid.lonDeg(mod(im - 1, nLon) + 1);
Ym = shLowLevel.ylm(deg2rad(latRow(:)), deg2rad(lonRow(:)), idx);
wm = w(im) .* B.region.mask(im);
n1 = size(resid.Cs, 1);
nT = size(resid.Cs, 3);
li = sub2ind([n1, size(resid.Cs, 2)], idx.n(:) + 1, idx.m(:) + 1);
isC = idx.cs(:) == 0;
Cr = reshape(resid.Cs, [], nT);
Sr = reshape(resid.Ss, [], nT);
X = zeros(idx.P, nT);
X(isC, :) = Cr(li(isC), :);
X(~isC, :) = Sr(li(~isC), :);
S = Ym * X;
E = S - Ym * full(B.T * A);
rep = 1 - sum(wm .* sum(E.^2, 2)) / sum(wm .* sum(S.^2, 2));
end
