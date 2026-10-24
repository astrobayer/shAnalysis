function [clim, info] = neqClimatology(neqs, opts)
%NEQCLIMATOLOGY Climatology estimated from every month's normal equation.
%
%   CLIM = shLowLevel.neqClimatology(NEQS) estimates the six climatology
%   terms of shClimatology - bias, trend, annual and semi-annual cos/sin -
%   for every coefficient from the monthly normal equations themselves,
%   instead of fitting them to filtered solutions. Month t's normal
%   equation N_t x = b_t observes
%       x_t = (d_t' kron I) theta + delta_t,   delta_t ~ N(0, Sigma_d),
%   with d_t the six time functions at t (around T0) and delta_t the
%   month's deviation from the climatology. Reducing delta_t leaves the
%   month's contribution
%       W_t = (I + N_t Sigma_d)^-1 N_t,   r_t = (I + N_t Sigma_d)^-1 b_t,
%   which never inverts N_t, so a rank-deficient month enters as it is,
%   and which is (N_t^-1 + Sigma_d)^-1 where N_t is regular. Then
%       N_theta = sum_t (d_t d_t') kron W_t,   b_theta = sum_t d_t kron r_t,
%       theta = N_theta^-1 b_theta,   Cov(theta) = N_theta^-1.
%   With DeviationCov = [] (Sigma_d = 0) this is the generalized least-
%   squares fit of the solutions x_t = N_t^-1 b_t with their full
%   covariances; with Sigma_d it is the Schur reduction of the joint
%   normal equation in theta and every delta_t
%   (tools/dev/validate_neq_climatology.py CLAIMs 1-3, 1.0e-15 to
%   1.8e-14 relative).
%
%   What it buys, measured on synthetic data in that file (CLAIM 4,
%   nmax 10, 120 months): with a stripe in every order block whose
%   direction changes from month to month, the trend error is 0.44 of an
%   equal-weight fit's and 0.66 for a fit weighted by the formal sigmas;
%   the trend sigma is honest (actual over predicted 0.98 pooled) with
%   the true Sigma_d, and too small by about 1.2 without it. With a noise
%   covariance of the SAME shape every month the gain is nil - identical
%   regressors and a time-invariant correlation make the estimate a
%   per-coefficient weighting - so on real data it is as large as the
%   month-to-month change of GRACE's noise pattern, which has not been
%   measured.
%
%   Memory: N_theta is (6P x 6P), P = (nmax+1)^2 - 4 coefficients:
%   0.26 GB at nmax 30, 0.81 at 40, 3.98 at 60, 25.5 at 96. The solve
%   holds three such matrices at once (N_theta, its Cholesky factor and
%   the factor's inverse, for the sigmas), and MaxMemGB refuses a call
%   whose three would exceed it; truncate with Nmax.
%
%   Inputs
%     neqs  (1,:) string | (1,T) struct  a SINEX folder, or several, or a
%           list of SINEX files, each read with shLowLevel.readSINEX and
%           required to carry a normal-equation block (kind 'NEQ', b =
%           M x); or records with fields N (P x P), b (P x 1) and epoch
%           (1,1) [decimal years] in shLowLevel.shIndex(Nmax) order
%
%   Options
%     Nmax ([])           (1,1) double  the degree the coefficients are
%                         truncated to; [] takes it from the first file,
%                         and is required for records
%     DeviationCov ([])   (P x 1) | (P x P) double  Sigma_d, the covariance
%                         of a month's deviation from the climatology, in
%                         shIndex(Nmax) order; [] is Sigma_d = 0 (the
%                         months are taken to lie on the climatology, and
%                         the sigmas are then too small). The signal
%                         covariance of a model series' residuals
%                         (shLowLevel.buildSignalCov) is one source
%     T0 (NaN)            (1,1) double  reference epoch of the terms
%                         [decimal years]; NaN takes the mean epoch
%     GM (3.986004415e14) (1,1) double  constant of the output
%     R (6378136.3)       (1,1) double  constant of the output [m]
%     Pattern ("*.snx*")  (1,1) string  file pattern inside a folder
%     MaxMemGB (8)        (1,1) double  refuse when the three (6P x 6P)
%                         matrices of the solve would need more [GB]
%
%   Outputs
%     clim  (1,1) shClimatology  the six terms, with their 1-sigma in
%           coefSigma (so clim.trend.sigmaC is the trend's sigma)
%     info  (1,1) struct  fields
%           epochs    (T,1) double  the months used, sorted
%           nEpochs   (1,1) double  their number
%           t0        (1,1) double  the reference epoch
%           nmax      (1,1) double  the degree
%           P         (1,1) double  coefficients per term
%           memGB     (1,1) double  memory of the three matrices of the
%                     solve [GB]
%           singular  (1,T) logical  months whose normal equation is not
%                     positive definite (they still enter, as they are)
%
%   Example
%     [clim, info] = shLowLevel.neqClimatology(itsgFolder, Nmax = 40, ...
%         DeviationCov = sigd .^ 2);
%     tr = clim.trend;                  % per year, with tr.sigmaC
%
%   Error identifiers
%     shLowLevel:neqClimatology:badDeviationCov
%         DeviationCov is neither P x 1 nor P x P, or not finite
%     shLowLevel:neqClimatology:badRecord
%         a record lacks N, b or epoch, or does not match the index
%     shLowLevel:neqClimatology:noFiles
%         no file matches Pattern in a folder
%     shLowLevel:neqClimatology:noNmax
%         records were given without Nmax
%     shLowLevel:neqClimatology:notNEQ
%         a SINEX file carries no normal-equation block
%     shLowLevel:neqClimatology:singular
%         N_theta is not positive definite: too few months for six terms,
%         or a coefficient no month observes
%     shLowLevel:neqClimatology:tooLarge
%         the three matrices of the solve would exceed MaxMemGB
%
%   See also shSeries.climatology, shClimatology, shLowLevel.kalmanChain,
%   shLowLevel.readSINEX, shLowLevel.buildSignalCov.
%
%   Developed by Matthias Weigelt with the help of Claude (Opus 5.5),
%   2026-10-23 (WP9 9b).
arguments
    neqs
    opts.Nmax double = []
    opts.DeviationCov double = []
    opts.T0 (1,1) double = NaN
    opts.GM (1,1) double {mustBePositive} = 3.986004415e14
    opts.R (1,1) double {mustBePositive} = 6378136.3
    opts.Pattern (1,1) string = "*.snx*"
    opts.MaxMemGB (1,1) double {mustBePositive} = 8
end

% ---- the months
if isstruct(neqs)
    if isempty(opts.Nmax)
        error('shLowLevel:neqClimatology:noNmax', ...
            'Records need Nmax: their coefficient order is shIndex(Nmax).');
    end
    idx = shLowLevel.shIndex(opts.Nmax);
    P = idx.P;
    T = numel(neqs);
    Ns = cell(1, T);
    bs = cell(1, T);
    ep = zeros(T, 1);
    for k = 1:T
        rk = neqs(k);
        if ~all(isfield(rk, {'N', 'b', 'epoch'})) || ~isequal(size(rk.N), [P P]) ...
                || numel(rk.b) ~= P || ~isscalar(rk.epoch)
            error('shLowLevel:neqClimatology:badRecord', ...
                ['Record %d needs N (%d x %d), b (%d x 1) and a scalar ' ...
                 'epoch, in shIndex(%d) order.'], k, P, P, P, opts.Nmax);
        end
        Ns{k} = rk.N;
        bs{k} = rk.b(:);
        ep(k) = rk.epoch;
    end
else
    files = sinexFiles(string(neqs), opts.Pattern);
    T = numel(files);
    Ns = cell(1, T);
    bs = cell(1, T);
    ep = zeros(T, 1);
    for k = 1:T
        if k == 1
            if isempty(opts.Nmax)
                s0 = shLowLevel.readSINEX(files(k), Only = "estimate");
                opts.Nmax = max(s0.n);
            end
            idx = shLowLevel.shIndex(opts.Nmax);
            P = idx.P;
        end
        s = shLowLevel.readSINEX(files(k), Index = idx);
        if ~strcmp(s.kind, 'NEQ')
            error('shLowLevel:neqClimatology:notNEQ', ...
                '%s carries no normal-equation block (kind = ''%s'').', ...
                files(k), s.kind);
        end
        Ns{k} = s.M;
        bs{k} = s.M * s.x;
        ep(k) = s.epoch;
    end
end
[ep, ord] = sort(ep);
Ns = Ns(ord);
bs = bs(ord);
t0 = opts.T0;
if isnan(t0), t0 = mean(ep); end

% ---- the deviation covariance
Sd = opts.DeviationCov;
if isempty(Sd)
    Sd = zeros(P);
elseif isvector(Sd) && numel(Sd) == P && all(isfinite(Sd))
    Sd = diag(Sd(:));
elseif ~isequal(size(Sd), [P P]) || ~all(isfinite(Sd(:)))
    error('shLowLevel:neqClimatology:badDeviationCov', ...
        'DeviationCov must be %d x 1 or %d x %d and finite.', P, P, P);
end
noDev = ~any(Sd(:));

% ---- assemble N_theta and b_theta
K = 6;
memGB = 3 * (K * P)^2 * 8 / 1e9;
if memGB > opts.MaxMemGB
    error('shLowLevel:neqClimatology:tooLarge', ...
        ['The solve needs %.2f GB at nmax %d, more than ' ...
         'MaxMemGB = %g: truncate with Nmax.'], memGB, opts.Nmax, opts.MaxMemGB);
end
Nth = zeros(K * P);
bth = zeros(K * P, 1);
I = eye(P);
singularMonth = false(1, T);
for k = 1:T
    N = (Ns{k} + Ns{k}') / 2;
    [~, pd] = chol(N);
    singularMonth(k) = pd ~= 0;
    if noDev
        W = N;
        r = bs{k};
    else
        A = I + N * Sd;
        W = A \ N;
        W = (W + W') / 2;
        r = A \ bs{k};
    end
    d = timeFunctions(ep(k), t0);
    for i = 1:K
        ri = (i - 1) * P + (1:P);
        bth(ri) = bth(ri) + d(i) * r;
        for j = 1:K
            rj = (j - 1) * P + (1:P);
            Nth(ri, rj) = Nth(ri, rj) + (d(i) * d(j)) * W;
        end
    end
end
Nth = (Nth + Nth') / 2;
[Rc, flag] = chol(Nth);
if flag ~= 0
    error('shLowLevel:neqClimatology:singular', ...
        ['N_theta is not positive definite (%d months for %d terms): too ' ...
         'few months, or a coefficient no month observes.'], T, K);
end
clear Nth
theta = Rc \ (Rc' \ bth);
Ri = Rc \ eye(K * P);
sig = sqrt(sum(Ri .^ 2, 2));

% ---- repack as an shClimatology (rows: bias, trend, cos/sin annual,
%      cos/sin semi-annual over the flattened [C(:); S(:)] stack)
n1 = opts.Nmax + 1;
Nc = n1^2;
coef = zeros(K, 2 * Nc);
coefSig = zeros(K, 2 * Nc);
for i = 1:K
    ri = (i - 1) * P + (1:P);
    [c, s] = shLowLevel.csFromVec(theta(ri), idx);
    coef(i, :) = [c(:); s(:)]';
    [c, s] = shLowLevel.csFromVec(sig(ri), idx);
    coefSig(i, :) = [c(:); s(:)]';
end
tmpl = shSeries(zeros(n1, n1, T), Ss = zeros(n1, n1, T), Epochs = ep, ...
    GM = opts.GM, R = opts.R, History = sprintf( ...
    "neqClimatology: %d monthly normal equations, nmax %d, Sigma_d %s", ...
    T, opts.Nmax, tern(noDev, "zero", "given")));
clim = shClimatology.fromCoef(coef, t0, tmpl, CoefSigma = coefSig);
info = struct('epochs', ep, 'nEpochs', T, 't0', t0, 'nmax', opts.Nmax, ...
    'P', P, 'memGB', memGB, 'singular', singularMonth);
end

% ---------------------------------------------------------------- local
function d = timeFunctions(t, t0)
%TIMEFUNCTIONS the six climatology terms at epoch t, shClimatology's order.
u = t - t0;
d = [1; u; cos(2 * pi * u); sin(2 * pi * u); cos(4 * pi * u); sin(4 * pi * u)];
end

function files = sinexFiles(paths, pattern)
%SINEXFILES the SINEX files of a list of folders and files.
files = strings(0, 1);
for p = paths(:).'
    if isfolder(p)
        d = dir(fullfile(char(p), char(pattern)));
        if isempty(d)
            error('shLowLevel:neqClimatology:noFiles', ...
                'No file matching %s in %s.', pattern, p);
        end
        files = [files; string(fullfile({d.folder}, {d.name}))']; %#ok<AGROW>
    else
        files(end + 1, 1) = p; %#ok<AGROW>
    end
end
end

function out = tern(c, a, b)
if c, out = a; else, out = b; end
end
