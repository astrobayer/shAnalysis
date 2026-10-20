function [rec, info] = regionalNEQ(B, kind, opts)
%REGIONALNEQ Gravity information of any level as a normal equation in a basis.
%
%   [REC, INFO] = shLowLevel.regionalNEQ(B, KIND, ...) turns one epoch of
%   gravity information into a normal equation in the coefficients a of
%   the regional basis B of shLowLevel.regionalBasis - the observation
%   adapter of the regional Kalman filter (Kurtenbach 2012, C-683, Sec.
%   3.3; NEQ-form update P+ = (P-^-1 + N)^-1). Every kind reduces to one
%   design A in the basis and one covariance C of the data y:
%       N = A' C^-1 A,   b = A' C^-1 y,   ltpl = y' C^-1 y,
%   formed through C's Cholesky factor (or 1/sqrt of a diagonal), never
%   through an inverse. REC is a contribution in the format of
%   shLowLevel.neqCombine (N, b, ltpl, nobs, name), so several kinds of
%   one epoch combine there - with variance components - and the result
%   updates shLowLevel.kalmanFilter in its normal-equation mode.
%
%   Kinds:
%     "solution"  an SH coefficient vector with its covariance:
%                 Solution (P x 1, B.idx order) and Cov (P x P, P x 1
%                 variances or a scalar); A = B.T. A monthly or daily
%                 GRACE solution, an ITSG series with its SINEX covariance.
%     "neq"       an SH normal equation, carried into the basis:
%                 N = T' N_SH T, b = T' b_SH. NEQ is a struct with fields
%                 N and b (and optionally ltpl, nobs) - or a
%                 shLowLevel.readSINEX result of kind 'NEQ' read with
%                 Index = B.idx (fields M, x, stats: N = M, b = M x,
%                 ltpl and nobs from the STATISTICS block). ltpl passes
%                 through unchanged: the basis does not change the data,
%                 only the parameters. GNSS loading and other groups built
%                 OUTSIDE shAnalysis enter here (CLAUDE.md WP8).
%     "points"    point functionals of the field: Values at LatDeg/LonDeg
%                 (geocentric) and Height above R, in any Quantity of
%                 shLowLevel.kernelFactors - a grid of EWH (Woehnke et
%                 al. 2025's observation area), gravity disturbances at
%                 altitude, potential differences. The design row is
%                     f_n (R/r)^p_n Ybar_nm(lat, lon),  r = R + Height,
%                 with f_n and p_n from kernelFactors (Python-validated
%                 against the Legendre series of an RBF to 4e-15). With
%                 Direction (M x 3, ECEF unit vectors) each row is
%                 instead the component of the GRADIENT of the quantity
%                 along that direction - the gravity vector for
%                 Quantity = "potential" - from the north, east and up
%                 derivatives (1/r) dY/dphi, (1/(r cos phi)) dY/dlambda
%                 and -(p_n/r) Y (validated against the analytic ECEF
%                 gradient of the series to 4e-10, the oracle's own
%                 finite-difference floor). Combine (Q x M) forms Q linear
%                 combinations of the M point functionals, and Values
%                 and Cov then belong to the combinations: Combine = [1 -1]
%                 on two points along the line of sight is a line-of-sight
%                 gravity difference (LGD). The along-track processing of
%                 real LGD stays in lgdToolbox (CLAUDE.md WP8, row 8h).
%
%   The design of "points" uses only band-limited synthesis, so a point
%   outside the region sees whatever the basis functions carry there; the
%   choice of the observation area is the caller's (Woehnke et al.: the
%   region grown by 300 km).
%
%   Inputs
%     B     (1,1) struct  a basis from shLowLevel.regionalBasis
%     kind  (1,1) string  "solution" | "neq" | "points"
%
%   Options
%     Solution ([])  (P,1) double  SH coefficients in B.idx order
%                    ("solution")
%     Cov ([])       covariance of the data: (n,n), (n,1) variances or a
%                    scalar variance, n = P ("solution"), M or Q
%                    ("points"); must be positive definite
%     NEQ (struct([]))  (1,1) struct  the SH normal equation ("neq"): fields
%                    N, b [, ltpl, nobs], or a readSINEX NEQ result
%     Values ([])    (M,1) or (Q,1) double  the data ("points")
%     LatDeg ([])    (M,1) double  geocentric latitudes [deg] ("points")
%     LonDeg ([])    (M,1) double  longitudes [deg] ("points")
%     Height (0)     (1,1) or (M,1) double  height above R [m]; only for
%                    quantities with a radial law
%     Quantity ("ewh")  (1,1) string  any quantity of
%                    shLowLevel.kernelFactors
%     Direction ([]) (M,3) double  ECEF directions; rows are normalised
%     Combine ([])   (Q,M) double  linear combinations of the M points
%     kn ([])        load Love numbers, for the mass quantities
%     GM (3.986004415e14)  (1,1) double  [m^3/s^2]
%     R (6378136.3)  (1,1) double  reference radius [m]
%     Name ("")      (1,1) string  label of the contribution; the kind
%                    when empty
%
%   Outputs
%     rec   (1,1) struct  a neqCombine contribution, fields
%           N     (K,K) double  normal matrix in the basis
%           b     (K,1) double  right-hand side
%           ltpl  (1,1) double  y' C^-1 y; NaN for an NEQ without it
%           nobs  (1,1) double  number of observations; NaN for an NEQ
%                 without it
%           name  (1,1) string  the label
%     info  (1,1) struct  fields
%           kind  (1,1) string  the KIND argument
%           A     (n,K) double  the design in the basis for "points"
%                 (after Combine); [] for "solution", whose design is B.T
%                 itself, and for "neq"
%
%   Example
%     B = shLowLevel.regionalBasis(shLowLevel.shIndex(60), "Elbe");
%     r1 = shLowLevel.regionalNEQ(B, "solution", Solution = l, Cov = sig.^2);
%     r2 = shLowLevel.regionalNEQ(B, "points", Values = ewh, ...
%         LatDeg = lat, LonDeg = lon, Cov = 0.02^2, kn = kn);
%     [a, out] = shLowLevel.neqCombine([r1, r2]);     % VCE of the two
%
%   Error identifiers
%     shLowLevel:regionalNEQ:badBasis
%         B is not a basis from shLowLevel.regionalBasis
%     shLowLevel:regionalNEQ:missingInput
%         an option the kind needs was not given
%     shLowLevel:regionalNEQ:sizeMismatch
%         the data, covariance, NEQ, points, directions or combinations do
%         not fit each other or the basis
%     shLowLevel:regionalNEQ:notPositiveDefinite
%         the covariance is not positive definite (a gridded covariance
%         often is not; Woehnke et al. add a small multiple of I)
%     shLowLevel:regionalNEQ:noRadialLaw
%         Height or Direction for a surface quantity (ewh, geoid, ...),
%         which has no upward continuation
%     shLowLevel:regionalNEQ:poleDirection
%         a Direction at a pole, where the east direction does not exist
%
%   References
%     Kurtenbach, E. (2012), DGK C-683, Sec. 3.3.
%     Woehnke, V., Eicker, A., Weigelt, M., et al. (2025), Kalman filter
%       framework for a regional mass change model from GRACE satellite
%       gravity, GEM - Int. J. Geomath. 16:2, eqs. 10 and A6.
%
%   Numerics pre-validated in Python
%   (tools/dev/validate_regional_observations.py).
%
%   Developed by Matthias Weigelt with the help of Claude (Opus 5.5),
%   2026-10-20.
arguments
    B (1,1) struct
    kind (1,1) string {mustBeMember(kind, ["solution", "neq", "points"])}
    opts.Solution double = []
    opts.Cov double = []
    opts.NEQ struct = struct([])
    opts.Values double = []
    opts.LatDeg double = []
    opts.LonDeg double = []
    opts.Height double = 0
    opts.Quantity (1,1) string = "ewh"
    opts.Direction double = []
    opts.Combine double = []
    opts.kn double = []
    opts.GM (1,1) double {mustBePositive} = 3.986004415e14
    opts.R (1,1) double {mustBePositive} = 6378136.3
    opts.Name (1,1) string = ""
end
if ~all(isfield(B, {'T', 'idx'}))
    error('shLowLevel:regionalNEQ:badBasis', ...
        'B must be a basis from shLowLevel.regionalBasis.');
end
idx = B.idx;
P = idx.P;
name = opts.Name;
if name == "", name = kind; end
A = [];
switch kind
    case "solution"
        need(opts, ["Solution", "Cov"], kind);
        y = opts.Solution(:);
        if numel(y) ~= P
            error('shLowLevel:regionalNEQ:sizeMismatch', ...
                'Solution has %d entries; the basis index has P = %d.', numel(y), P);
        end
        [N, b, ltpl] = weighted(B.T, y, opts.Cov);
        nobs = P;
    case "neq"
        if isempty(opts.NEQ)
            error('shLowLevel:regionalNEQ:missingInput', ...
                'Kind "neq" needs NEQ (fields N and b, or a readSINEX NEQ result).');
        end
        e = opts.NEQ;
        ltpl = NaN;
        nobs = NaN;
        if isfield(e, 'M') && isfield(e, 'x') && ~isempty(e.M)
            Nsh = e.M;
            bsh = e.M * e.x(:);
            if isfield(e, 'stats') && ~isempty(e.stats)
                if isfield(e.stats, 'wsos'), ltpl = e.stats.wsos; end
                if isfield(e.stats, 'nobs'), nobs = e.stats.nobs; end
            end
        elseif isfield(e, 'N') && isfield(e, 'b')
            Nsh = e.N;
            bsh = e.b(:);
            if isfield(e, 'ltpl') && ~isempty(e.ltpl), ltpl = e.ltpl; end
            if isfield(e, 'nobs') && ~isempty(e.nobs), nobs = e.nobs; end
        else
            error('shLowLevel:regionalNEQ:missingInput', ...
                'NEQ carries neither N and b nor a readSINEX M and x.');
        end
        if ~isequal(size(Nsh), [P P]) || numel(bsh) ~= P
            error('shLowLevel:regionalNEQ:sizeMismatch', ...
                ['The SH normal equation is %s with %d right-hand sides; the ' ...
                 'basis index has P = %d (read SINEX with Index = B.idx).'], ...
                mat2str(size(Nsh)), numel(bsh), P);
        end
        N = full(B.T' * Nsh * B.T);
        N = (N + N') / 2;
        b = full(B.T' * bsh);
    case "points"
        need(opts, ["Values", "LatDeg", "LonDeg", "Cov"], kind);
        A = pointDesign(B, opts);
        if ~isempty(opts.Combine)
            if size(opts.Combine, 2) ~= size(A, 1)
                error('shLowLevel:regionalNEQ:sizeMismatch', ...
                    'Combine has %d columns for %d points.', ...
                    size(opts.Combine, 2), size(A, 1));
            end
            A = opts.Combine * A;
        end
        y = opts.Values(:);
        if numel(y) ~= size(A, 1)
            error('shLowLevel:regionalNEQ:sizeMismatch', ...
                'Values has %d entries for %d observations.', numel(y), size(A, 1));
        end
        [N, b, ltpl] = weighted(A, y, opts.Cov);
        nobs = numel(y);
end
rec = struct('N', N, 'b', b, 'ltpl', ltpl, 'nobs', nobs, 'name', name);
info = struct('kind', kind, 'A', A);
end

function need(opts, names, kind)
for k = 1:numel(names)
    if isempty(opts.(names(k)))
        error('shLowLevel:regionalNEQ:missingInput', ...
            'Kind "%s" needs %s.', kind, strjoin(names, ", "));
    end
end
end

function [N, b, ltpl] = weighted(A, y, C)
% N = A' C^-1 A, b = A' C^-1 y, ltpl = y' C^-1 y through a square root of C.
ny = numel(y);
if isscalar(C)
    C = repmat(C, ny, 1);
end
if isvector(C) && numel(C) == ny
    if any(~(C(:) > 0))
        error('shLowLevel:regionalNEQ:notPositiveDefinite', ...
            'A variance is zero, negative or NaN.');
    end
    s = 1 ./ sqrt(C(:));
    Aw = A .* s;
    yw = y .* s;
elseif isequal(size(C), [ny ny])
    [Lc, flag] = chol((C + C') / 2, 'lower');
    if flag ~= 0
        error('shLowLevel:regionalNEQ:notPositiveDefinite', ...
            ['The covariance is not positive definite (Cholesky failed at ' ...
             'column %d); a gridded covariance often is not - add a small ' ...
             'multiple of the identity.'], flag);
    end
    Aw = Lc \ A;
    yw = Lc \ y;
else
    error('shLowLevel:regionalNEQ:sizeMismatch', ...
        'Cov is %s for %d observations.', mat2str(size(C)), ny);
end
N = full(Aw' * Aw);
N = (N + N') / 2;
b = full(Aw' * yw);
ltpl = full(yw' * yw);
end

function A = pointDesign(B, opts)
% The design of point functionals (or their directional gradients) in the
% basis: A_SH * B.T.
idx = B.idx;
L = idx.Lmax;
lat = opts.LatDeg(:);
lon = opts.LonDeg(:);
M = numel(lat);
if numel(lon) ~= M
    error('shLowLevel:regionalNEQ:sizeMismatch', ...
        'LatDeg has %d entries and LonDeg %d.', M, numel(lon));
end
h = opts.Height(:);
if ~(isscalar(h) || numel(h) == M)
    error('shLowLevel:regionalNEQ:sizeMismatch', ...
        'Height must be a scalar or one value per point.');
end
[kern, pexp] = shLowLevel.kernelFactors(opts.Quantity, L, opts.GM, opts.R, ...
    kn = opts.kn);
hasDir = ~isempty(opts.Direction);
if isempty(pexp) && (any(h ~= 0) || hasDir)
    error('shLowLevel:regionalNEQ:noRadialLaw', ...
        ['%s is a surface quantity: it has no upward continuation, so ' ...
         'neither Height nor a Direction (which needs d/dr) applies.'], ...
        opts.Quantity);
end
r = opts.R + h .* ones(M, 1);
fn = kern(idx.n + 1)';                                  % 1 x P
if isempty(pexp)
    fr = repmat(fn, M, 1);
else
    fr = fn .* (opts.R ./ r) .^ (pexp(idx.n + 1)');      % M x P
end
latR = deg2rad(lat);
lonR = deg2rad(lon);
iC = idx.cs(:)' == 0;
mm = idx.m(:)';
cosL = cos(lonR .* mm);
sinL = sin(lonR .* mm);
trig = cosL .* iC + sinL .* ~iC;
if ~hasDir
    A = (shLowLevel.ylm(latR, lonR, idx) .* fr) * B.T;
    A = full(A);
    return
end
d = opts.Direction;
if ~isequal(size(d), [M 3])
    error('shLowLevel:regionalNEQ:sizeMismatch', ...
        'Direction must be %d x 3 (one ECEF direction per point).', M);
end
if any(abs(lat) >= 90)
    error('shLowLevel:regionalNEQ:poleDirection', ...
        'A Direction at a pole: the east direction does not exist there.');
end
d = d ./ vecnorm(d, 2, 2);
[Pb, D] = shLowLevel.legendreALFDeriv(L, latR');
lin = sub2ind([L + 1, L + 1], idx.n + 1, idx.m + 1);
Pl = reshape(Pb, (L + 1)^2, M);
Dl = reshape(D, (L + 1)^2, M);
Pl = Pl(lin, :)';                                       % M x P
Dl = Dl(lin, :)';
dtrig = (-mm .* sinL) .* iC + (mm .* cosL) .* ~iC;
north = fr .* Dl .* trig ./ r;
east = fr .* Pl .* dtrig ./ (r .* cos(latR));
up = -fr .* Pl .* trig .* (pexp(idx.n + 1)' ./ r);
sp = sin(latR); cp = cos(latR); sl = sin(lonR); cl = cos(lonR);
dn = d(:, 1) .* (-sp .* cl) + d(:, 2) .* (-sp .* sl) + d(:, 3) .* cp;
de = d(:, 1) .* (-sl) + d(:, 2) .* cl;
du = d(:, 1) .* (cp .* cl) + d(:, 2) .* (cp .* sl) + d(:, 3) .* sp;
A = full((dn .* north + de .* east + du .* up) * B.T);
end
