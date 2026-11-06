function [C, info] = maternCovariance(idx, opts)
%MATERNCOVARIANCE Non-stationary SPDE-Matern prior covariance of SH coefficients.
%
%   C = shLowLevel.maternCovariance(IDX, PracticalRangeKm = RHO, Sigma = S)
%   is the covariance (P x P, IDX order) of the coefficients of the
%   Gaussian field u of the stochastic PDE of Lindgren, Rue and Lindstroem
%   (2011, Sec. 3.1-3.2), alpha = 2 (nu = 1 on a surface), on the sphere:
%       (kappa(x)^2 - Laplace) (tau(x) u(x)) = W(x),
%   W white noise. RHO and S are the LOCAL practical range [km] and the
%   LOCAL pointwise standard deviation: scalars give the stationary Matern
%   field, function handles f(latDeg, lonDeg) a non-stationary one - the
%   form HB-STAR and R-INLA use, with log kappa and log tau given as
%   fields. kappa = sqrt(8) / RHO (the correlation is about 0.13 at
%   distance RHO in the plane), on the sphere of radius R.
%
%   Discretisation. Galerkin in the 4pi-normalised SH of degrees 0..Lmax
%   (in place of the finite elements of Lindgren et al.): with Y the basis
%   on an over-sampled Gauss-Legendre grid and w its weights (sum 1),
%       A = Y' diag(w kappa~^2) Y + diag(n (n+1)),
%       M = Y' diag(w / tau) Y,
%       Cov = M A^-1 A^-1 M / (4 pi),   kappa~ = kappa R,
%   and IDX's degrees taken as the sub-matrix (their marginal covariance).
%   1/tau(x) = S(x) / sqrt(s(kappa~(x))), s(k) the pointwise variance of a
%   stationary field of unit tau over IDX's degrees,
%       s(k) = sum_{n = IDX.minDegree..Lmax} (2n+1) / (4 pi (k^2 + n(n+1))^2),
%   so with constant fields the pointwise standard deviation is S
%   EXACTLY at every point; with varying fields it is S where the fields
%   vary slowly against the range. The multiplications by kappa^2 and 1/tau
%   are truncated to the band limit, the discretisation error of this
%   approach; for constant fields there is none.
%
%   Validated in tools/dev/validate_matern_prior.py: the stationary
%   Legendre series equals the closed form d/dlambda [P_nu(-cos psi) /
%   (4 sin(pi nu))], nu (nu + 1) = -kappa~^2, to 1.1e-14 (CLAIM 1);
%   constant fields give the diagonal Matern degree variances to 3.0e-14
%   and the pointwise std S to 5.4e-13 (CLAIM 2); with a range of 1500 /
%   3000 km and S 2 / 1 in two hemispheres (Lmax 30) the std deep in each
%   half is within 0.34% of the local S and the 0.139-correlation distance
%   within 0.47% of the stationary field's with the local parameters
%   (CLAIM 4) - the prior is local. As the process noise of a VAR(1) it
%   gives honest smoothed sigmas (z-rms 0.98-1.02 over 20 seeds) where a
%   diagonal Q from a 60-epoch model series gives 1.14 (CLAIM 6).
%
%   Units. With kn the field is equivalent water height: S is in metres
%   EWH and C is the covariance of Stokes coefficients, C_ij / (f_i f_j)
%   with f the EWH kernel of shLowLevel.kernelFactors. Without kn the field
%   is the SH expansion of the coefficients themselves and S is in their
%   units.
%
%   Use: shLowLevel.regionalKalman(..., ProcessCov = C) carries it into a
%   regional basis as the process noise (Proj C Proj'), StartCov as the
%   filter's start; QScale, QBlocks and EstimateQScale then scale it.
%
%   Inputs
%     idx  (1,1) struct  shLowLevel.shIndex of the coefficients
%
%   Options
%     PracticalRangeKm (required)  (1,1) double | function handle  local
%                        practical range [km], positive; a handle takes
%                        geocentric latitude and longitude [deg] as column
%                        vectors and returns a column
%     Sigma (1)          (1,1) double | function handle  local pointwise
%                        standard deviation, positive [m EWH with kn]
%     kn ([])            (>=Lmax+1,1) double  load Love numbers; with them
%                        the field is EWH, see Units
%     GM (3.986004415e14) (1,1) double  [m^3/s^2], for the EWH kernel
%     R (6378136.3)      (1,1) double  [m], the sphere's radius
%     OverSample (2)     (1,1) double  grid over-sampling of the Gram
%                        matrices (latitudes OverSample * (Lmax + 1))
%     MaxMemGB (8)       (1,1) double  refuse when the five (Lmax+1)^2
%                        square matrices of the solve exceed it
%
%   Outputs
%     C     (P,P) double  covariance in IDX order, symmetric positive
%           definite
%     info  (1,1) struct  fields
%           stationary  (1,1) logical  both fields scalars
%           kappaRange  (1,2) double   min and max of kappa~ on the grid
%           sigmaRange  (1,2) double   min and max of Sigma on the grid
%           units       (1,1) string   "ewh-stokes" with kn, "field"
%                       without
%           memGB       (1,1) double   the solve's memory estimate
%
%   Example
%     idx = shLowLevel.shIndex(60);
%     rho = @(lat, lon) 300 + 500 * (abs(lat) > 60);     % km
%     C = shLowLevel.maternCovariance(idx, PracticalRangeKm = rho, ...
%         Sigma = 0.02, kn = kn);                         % 2 cm EWH
%     [tsK, out] = shLowLevel.regionalKalman(ts, B, ModelSeries = tsm, ...
%         ProcessCov = C, EstimateQScale = true);
%
%   Error identifiers
%     shLowLevel:maternCovariance:badRange
%         PracticalRangeKm is missing, or not positive and finite on the
%         grid
%     shLowLevel:maternCovariance:badSigma
%         Sigma is not positive and finite on the grid
%     shLowLevel:maternCovariance:tooLarge
%         the solve needs more than MaxMemGB
%
%   References
%     Lindgren, F., Rue, H., Lindstroem, J. (2011), An explicit link
%       between Gaussian fields and Gaussian Markov random fields: the
%       stochastic partial differential equation approach, J. R. Stat.
%       Soc. B 73, 423-498.
%
%   Developed by Matthias Weigelt with the help of Claude (Opus 5.5),
%   2026-11-06 (WP9 9g).
arguments
    idx (1,1) struct
    opts.PracticalRangeKm
    opts.Sigma = 1
    opts.kn double = []
    opts.GM (1,1) double {mustBePositive} = 3.986004415e14
    opts.R (1,1) double {mustBePositive} = 6378136.3
    opts.OverSample (1,1) double {mustBeInteger, mustBePositive} = 2
    opts.MaxMemGB (1,1) double {mustBePositive} = 8
end
L = idx.Lmax;
idx0 = shLowLevel.shIndex(L, Nmin = 0);
P0 = idx0.P;
memGB = 5 * 8 * P0^2 / 1e9;
if memGB > opts.MaxMemGB
    error('shLowLevel:maternCovariance:tooLarge', ...
        'The solve needs %.1f GB at Lmax %d, above MaxMemGB = %g.', ...
        memGB, L, opts.MaxMemGB);
end
if ~isfield(opts, 'PracticalRangeKm')
    error('shLowLevel:maternCovariance:badRange', ...
        'PracticalRangeKm is required: the prior has no default length scale.');
end

% ---- the grid and the two fields on it
nLat = opts.OverSample * (L + 1);
nLon = opts.OverSample * (2 * L + 2);
[~, w, g] = shLowLevel.synthesisMatrix(idx0, NLat = nLat, NLon = nLon, ...
    GridOnly = true);
[LON, LAT] = meshgrid(g.lonDeg(:), g.latDeg(:));
LAT = reshape(LAT.', [], 1);                    % latitude-major rows
LON = reshape(LON.', [], 1);
rho = fieldOnGrid(opts.PracticalRangeKm, LAT, LON);
if ~all(isfinite(rho) & rho > 0)
    error('shLowLevel:maternCovariance:badRange', ...
        'PracticalRangeKm must be positive and finite at every grid point.');
end
sig = fieldOnGrid(opts.Sigma, LAT, LON);
if ~all(isfinite(sig) & sig > 0)
    error('shLowLevel:maternCovariance:badSigma', ...
        'Sigma must be positive and finite at every grid point.');
end
kap = sqrt(8) * (opts.R / 1000) ./ rho;        % kappa~ on the unit sphere
nn = (idx.minDegree:L);
s = sum((2 * nn + 1) ./ (kap.^2 + nn .* (nn + 1)).^2, 2) / (4 * pi);
itau = sig ./ sqrt(s);

% ---- the Gram matrices, one latitude ring at a time
Mk = zeros(P0);
Mt = zeros(P0);
for i = 1:nLat
    r = (i - 1) * nLon + (1:nLon);
    Yr = shLowLevel.ylm(deg2rad(LAT(r)), deg2rad(LON(r)), idx0);
    Mk = Mk + Yr.' * ((w(r) .* kap(r).^2) .* Yr);
    Mt = Mt + Yr.' * ((w(r) .* itau(r)) .* Yr);
end
A = Mk + diag(idx0.n .* (idx0.n + 1));
A = (A + A.') / 2;
Mt = (Mt + Mt.') / 2;
X = A \ Mt;
C0 = (X.' * X) / (4 * pi);

% ---- IDX's degrees, and EWH -> Stokes
map = idx0.pos(sub2ind(size(idx0.pos), idx.n + 1, idx.m + 1, idx.cs + 1));
C = C0(map, map);
units = "field";
if ~isempty(opts.kn)
    f = shLowLevel.kernelFactors("ewh", L, opts.GM, opts.R, kn = opts.kn);
    fi = f(idx.n + 1);
    fi = fi(:);
    C = C ./ (fi .* fi.');
    units = "ewh-stokes";
end
C = (C + C.') / 2;
info = struct('stationary', isnumeric(opts.PracticalRangeKm) && ...
    isnumeric(opts.Sigma), 'kappaRange', [min(kap), max(kap)], ...
    'sigmaRange', [min(sig), max(sig)], 'units', units, 'memGB', memGB);
end

function v = fieldOnGrid(f, lat, lon)
% A scalar or a handle f(latDeg, lonDeg), evaluated on the grid points.
if isa(f, 'function_handle')
    v = f(lat, lon);
    v = double(v(:));
    if numel(v) ~= numel(lat)
        v = NaN(numel(lat), 1);
    end
elseif isnumeric(f) && isscalar(f)
    v = repmat(double(f), numel(lat), 1);
else
    v = NaN(numel(lat), 1);
end
end
