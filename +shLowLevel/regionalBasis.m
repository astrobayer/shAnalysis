function B = regionalBasis(idx, region, opts)
%REGIONALBASIS A local basis for a region, as a linear map to SH coefficients.
%
%   B = shLowLevel.regionalBasis(IDX, REGION) builds a set of K
%   space-localising basis functions for REGION and returns them as the
%   matrix B.T (P x K) that maps basis coefficients a to spherical-harmonic
%   coefficients in IDX ordering, x = B.T * a, band-limited at IDX.Lmax.
%   Every basis enters the rest of the toolbox through T alone: an SH
%   solution or normal equation becomes T' N T and T' b, a grid or point
%   functional A_SH T, and a model series becomes basis coefficients
%   through the projector B.Proj (K x P). This is the state of the
%   regional Kalman filter of CLAUDE.md WP8 (Kurtenbach 2012, C-683,
%   outlook; Woehnke et al. 2025; Steffen et al. 2026).
%
%   Three types (Type option):
%     "rbf"      radial basis functions after Eicker (2008) and Woehnke et
%                al. (2025, eqs. 5-7), centred on the nodes x_k of a global
%                grid that fall into the region grown by BufferKm:
%                  T(:, k) = phi_n .* Ybar(x_k)',
%                so that the function synthesises to the Legendre series
%                  Psi_k(x) = sum_n phi_n (2n+1) P_n(cos psi_k)
%                (the addition theorem; Python-validated to 2e-14). The
%                shape coefficients phi_n follow Woehnke's eq. 7,
%                phi_n = sigma_n / sqrt(2n+1) from the signal's degree
%                amplitudes sigma_n (Kernel = "amplitude"); Kernel =
%                "kaula" takes phi_n = 1 / n^2, the per-coefficient decay of
%                Kaula's rule, which Woehnke found within 0.07% in
%                correlation; Kernel = "shannon" takes phi_n = 1. Scaling
%                phi by a constant scales the coefficients by its inverse
%                and changes nothing else.
%     "slepian"  the Slepian tapers of shLowLevel.slepianBasis for the
%                region grown by BufferKm (Simons et al. 2006; Steffen et
%                al. 2026): T = G, B.Proj = G'. The retained set is the
%                Shannon number (slepianBasis's default), NKeep tapers, or
%                every taper whose concentration is >= Threshold (Steffen
%                et al. use 0.5).
%     "sh"       the global SH basis itself: T = Proj = I (sparse). The
%                regional Kalman filter on this basis is the global one,
%                which makes it the filter's oracle. REGION is optional.
%
%   The projector. A field x in SH coefficients (a model series epoch) is
%   given basis coefficients by least squares over the region grown by
%   BufferKm - the computation area of Woehnke et al.:
%       a = argmin integral_region (Y x - Y T a)^2,  B.Proj = (T'KT)^+ T'K,
%   with K = Y' diag(w .* mask) Y on the Gauss-Legendre quadrature grid of
%   OverSample * (Lmax+1) rings. The pseudo-inverse drops eigenvalues of
%   T'KT below EigTol times the largest (B.rank says how many stay), so
%   a basis denser than nmax resolves still has a unique, minimum-norm
%   projection. For a Slepian basis this formula IS G', because the tapers
%   are the eigenvectors of K (Python-validated to 2e-15), so B.Proj = G'
%   is set directly and regionalProject generalises slepianProject.
%   Only grid points with a non-zero mask are formed, so the cost grows
%   with the region, not with the sphere.
%
%   Node selection (rbf). A node belongs to the basis when the quadrature
%   point nearest to it lies inside the buffered mask - one rule for
%   every REGION form, and the same mask the projector weights with. The
%   rule resolves the region edge to half a ring spacing, 90 /
%   (OverSample*(Lmax+1)) degrees; raise OverSample to refine it.
%
%   Node grids (rbf). "icosahedral": the vertices of an icosahedron whose
%   faces are divided into f^2 triangles (f = Level + 1), projected
%   centrally onto the sphere, 10 f^2 + 2 nodes - the count of the
%   triangle vertex grid of Woehnke et al. (2025, eq. 8). "reuter": the
%   Reuter (1982) grid of Eicker (2008), Level = gamma rings from pole to
%   pole, one node per pole and about 4 gamma^2 / pi in all. With
%   Level = [] the level is the smallest whose GLOBAL grid has at least
%   (Lmax+1)^2 nodes, as many as the SH basis has coefficients: j = 30
%   at nmax 96 (9612 nodes), the level Woehnke's Fig. 4 shows.
%
%   Inputs
%     idx     (1,1) struct  shLowLevel.shIndex of the coefficients the
%             basis maps to (its Lmax is the band limit)
%     region  basin name (1,1) string, function handle f(latDeg, lonDeg),
%             K x 2 [latDeg lonDeg] polygon, or Ngrid x 1 mask on the
%             OverSample quadrature grid (see shLowLevel.evalMask); a name
%             is resolved by shLowLevel.readBasin in BasinFile. [] only
%             for Type = "sh"
%
%   Options
%     Type ("rbf")  "rbf" | "slepian" | "sh"   the basis, see above
%     BufferKm (600)  (1,1) double  growth of the region [km] before the
%           nodes are selected, the tapers concentrated and the projector
%           weighted: Woehnke's computation area is the region plus 2 x
%           300 km; Steffen et al. tested 600 and 900 km
%     Grid ("icosahedral")  "icosahedral" | "reuter"   rbf node grid
%     Level ([])  (1,1) double  rbf grid level: j for "icosahedral"
%           (10 (j+1)^2 + 2 nodes), gamma for "reuter"; [] = the rule above
%     Kernel ("kaula")  "kaula" | "shannon" | "amplitude"   rbf shape
%           coefficients phi_n, see above
%     DegreeAmplitude ([])  (Lmax+1,1) double  sigma_n for n = 0..Lmax,
%           required by Kernel = "amplitude" and refused otherwise; must
%           be finite, and positive at the degrees IDX holds
%     Threshold ([])  (1,1) double in (0, 1]  slepian: keep every taper
%           with concentration >= Threshold
%     NKeep ([])  (1,1) double  slepian: keep this many tapers; give at
%           most one of Threshold and NKeep ([] for both = Shannon number)
%     EigTol (1e-10)  (1,1) double  rbf projector: relative eigenvalue
%           cut of the pseudo-inverse
%     R (6378136.3)  (1,1) double  sphere radius [m] for the km buffer
%     OverSample (2)  (1,1) double  quadrature refinement of the mask, as
%           in shLowLevel.evalMask
%     BasinFile ("basins_rivbas.json")  (1,1) string  the GeoJSON a basin
%           name is looked up in (shLowLevel.readBasin's File)
%
%   Outputs
%     B  (1,1) struct  the basis, fields
%        type        (1,1) string  "rbf", "slepian" or "sh"
%        idx         (1,1) struct  the IDX it maps to
%        T           (P,K) double  basis coefficients -> SH coefficients
%                    (sparse identity for "sh")
%        Proj        (K,P) double  SH coefficients -> basis coefficients,
%                    region-weighted least squares (sparse identity for
%                    "sh")
%        K           (1,1) double  number of basis functions
%        nodes       (K,2) double  rbf centres [latDeg lonDeg]; [] otherwise
%        kernel      (Lmax+1,1) double  rbf phi_n for n = 0..Lmax; []
%                    otherwise
%        kernelName  (1,1) string  the Kernel option; "" unless rbf
%        grid        (1,1) string  the rbf node grid; "" otherwise
%        level       (1,1) double  the rbf grid level used; NaN otherwise
%        nGlobal     (1,1) double  nodes of the global rbf grid; NaN
%                    otherwise
%        lambda      (K,1) double  slepian concentrations; [] otherwise
%        rank        (1,1) double  eigenvalues kept in the projector (K
%                    for slepian and sh)
%        eigTol      (1,1) double  the EigTol option
%        region      (1,1) struct  fields
%                    name                 (1,1) string  basin name; ""
%                                         for other region forms
%                    bufferKm             (1,1) double  the BufferKm option
%                    areaFraction         (1,1) double  region area / 4pi
%                                         on the quadrature grid; NaN
%                                         without a region
%                    areaFractionBuffered (1,1) double  the same for the
%                                         buffered region
%                    mask                 (Ngrid,1) double  the buffered
%                                         mask on the OverSample grid; []
%                                         without a region
%                    core                 (Ngrid,1) double  the region
%                                         itself, unbuffered, on the same
%                                         grid - what basin means are
%                                         taken over; [] without a region
%                    overSample           (1,1) double  the OverSample
%                                         option
%                    R                    (1,1) double  the R option
%
%   Example
%     idx = shLowLevel.shIndex(60);
%     B = shLowLevel.regionalBasis(idx, "Elbe");            % RBF, Kaula
%     a = shLowLevel.regionalProject(ts.Cs, ts.Ss, B);      % K x T
%     S = shLowLevel.regionalBasis(idx, "Elbe", Type = "slepian", ...
%                                  Threshold = 0.5);
%
%   Error identifiers
%     shLowLevel:regionalBasis:missingRegion
%         Type "rbf" or "slepian" without a region
%     shLowLevel:regionalBasis:emptyRegion
%         the buffered region has no area, no rbf node falls into it, or
%         no taper reaches Threshold
%     shLowLevel:regionalBasis:badAmplitude
%         Kernel "amplitude" without a usable DegreeAmplitude, or a
%         DegreeAmplitude given with another kernel
%     shLowLevel:regionalBasis:badThreshold
%         Threshold outside (0, 1], or both Threshold and NKeep given
%
%   References
%     Eicker, A. (2008), Gravity field refinement by radial basis functions
%       from in-situ satellite data, PhD thesis, University of Bonn.
%     Woehnke, V., Eicker, A., Weigelt, M., et al. (2025), Kalman filter
%       framework for a regional mass change model from GRACE satellite
%       gravity, GEM - Int. J. Geomath. 16:2, doi:10.1007/s13137-024-00260-1.
%     Simons, F. J., Dahlen, F. A., Wieczorek, M. A. (2006), Spatiospectral
%       concentration on a sphere, SIAM Review 48, 504-536.
%     Reuter, R. (1982), Integralformeln der Einheitssphaere und
%       harmonische Splinefunktionen, PhD thesis, RWTH Aachen.
%
%   Numerics pre-validated in Python (tools/dev/validate_regional_basis.py).
%
%   Developed by Matthias Weigelt with the help of Claude (Opus 5.5),
%   2026-10-20.
arguments
    idx (1,1) struct
    region = []
    opts.Type (1,1) string {mustBeMember(opts.Type, ["rbf", "slepian", "sh"])} = "rbf"
    opts.BufferKm (1,1) double {mustBeNonnegative} = 600
    opts.Grid (1,1) string {mustBeMember(opts.Grid, ["icosahedral", "reuter"])} = "icosahedral"
    opts.Level double {mustBeScalarOrEmpty, mustBeInteger, mustBeNonnegative} = []
    opts.Kernel (1,1) string {mustBeMember(opts.Kernel, ["kaula", "shannon", "amplitude"])} = "kaula"
    opts.DegreeAmplitude double = []
    opts.Threshold double {mustBeScalarOrEmpty} = []
    opts.NKeep double {mustBeScalarOrEmpty} = []
    opts.EigTol (1,1) double {mustBePositive} = 1e-10
    opts.R (1,1) double {mustBePositive} = 6378136.3
    opts.OverSample (1,1) double {mustBeInteger, mustBePositive} = 2
    opts.BasinFile (1,1) string = "basins_rivbas.json"
end
L = idx.Lmax;
P = idx.P;
regName = "";
if isstring(region) || ischar(region)
    [region, binfo] = shLowLevel.readBasin(string(region), File = opts.BasinFile);
    regName = binfo.name;
end
hasRegion = ~(isnumeric(region) && isempty(region));
if ~hasRegion && opts.Type ~= "sh"
    error('shLowLevel:regionalBasis:missingRegion', ...
        'Type "%s" needs a region: a basin name, a polygon, a handle or a mask.', ...
        opts.Type);
end
if ~isempty(opts.DegreeAmplitude) && opts.Kernel ~= "amplitude"
    error('shLowLevel:regionalBasis:badAmplitude', ...
        'DegreeAmplitude is used only with Kernel = "amplitude", not "%s".', ...
        opts.Kernel);
end

% ---- the region on the quadrature grid
reg = struct('name', regName, 'bufferKm', opts.BufferKm, ...
    'areaFraction', NaN, 'areaFractionBuffered', NaN, 'mask', [], ...
    'core', [], 'overSample', opts.OverSample, 'R', opts.R);
if hasRegion
    [~, w, qgrid] = shLowLevel.synthesisMatrix(idx, ...
        NLat = opts.OverSample * (L + 1), ...
        NLon = opts.OverSample * (2 * L + 2), GridOnly = true);
    m0 = shLowLevel.evalMask(idx, region, R = opts.R, OverSample = opts.OverSample);
    if opts.BufferKm > 0
        mb = shLowLevel.evalMask(idx, region, BufferKm = opts.BufferKm, ...
            R = opts.R, OverSample = opts.OverSample);
    else
        mb = m0;
    end
    reg.areaFraction = w' * m0;
    reg.areaFractionBuffered = w' * mb;
    reg.mask = mb;
    reg.core = m0;
    if reg.areaFractionBuffered <= 0
        error('shLowLevel:regionalBasis:emptyRegion', ...
            'The region grown by %g km has no area on the quadrature grid.', ...
            opts.BufferKm);
    end
end

nodes = []; phi = []; kernelName = ""; gridName = ""; level = NaN;
nGlobal = NaN; lam = [];
switch opts.Type
    case "sh"
        T = speye(P);
        Proj = speye(P);
        rnk = P;
    case "slepian"
        if ~isempty(opts.Threshold) && ~isempty(opts.NKeep)
            error('shLowLevel:regionalBasis:badThreshold', ...
                'Give at most one of Threshold and NKeep.');
        end
        if ~isempty(opts.Threshold) && ~(opts.Threshold > 0 && opts.Threshold <= 1)
            error('shLowLevel:regionalBasis:badThreshold', ...
                'Threshold must lie in (0, 1]; it is %g.', opts.Threshold);
        end
        nk = opts.NKeep;
        if ~isempty(opts.Threshold), nk = P; end
        [G, lam] = shLowLevel.slepianBasis(idx, region, NKeep = nk, ...
            BufferKm = opts.BufferKm, R = opts.R, OverSample = opts.OverSample);
        if ~isempty(opts.Threshold)
            keep = lam >= opts.Threshold;
            if ~any(keep)
                error('shLowLevel:regionalBasis:emptyRegion', ...
                    'No taper reaches the concentration Threshold %g (the best is %.3f).', ...
                    opts.Threshold, lam(1));
            end
            G = G(:, keep);
            lam = lam(keep);
        end
        T = G;
        Proj = G';
        rnk = size(G, 2);
    case "rbf"
        gridName = opts.Grid;
        level = opts.Level;
        if isempty(level), level = defaultLevel(opts.Grid, L); end
        if opts.Grid == "icosahedral"
            [latG, lonG] = icosahedralGrid(level + 1);
        else
            [latG, lonG] = reuterGrid(level);
        end
        nGlobal = numel(latG);
        near = nearestGridPoint(latG, lonG, qgrid);
        sel = mb(near) > 0.5;
        if ~any(sel)
            error('shLowLevel:regionalBasis:emptyRegion', ...
                ['No node of the %s grid at level %d falls into the region ' ...
                 'grown by %g km - raise Level or BufferKm.'], ...
                opts.Grid, level, opts.BufferKm);
        end
        nodes = [latG(sel), lonG(sel)];
        kernelName = opts.Kernel;
        phi = kernelCoefficients(opts, idx);
        T = phi(idx.n + 1) .* shLowLevel.ylm(deg2rad(nodes(:, 1)), ...
            deg2rad(nodes(:, 2)), idx)';
        % projector over the buffered region, from its grid points only
        nLon = numel(qgrid.lonDeg);
        im = find(mb > 0);
        latRow = qgrid.latDeg(ceil(im / nLon));
        lonRow = qgrid.lonDeg(mod(im - 1, nLon) + 1);
        Ym = shLowLevel.ylm(deg2rad(latRow(:)), deg2rad(lonRow(:)), idx);
        wm = w(im) .* mb(im);
        YT = Ym * T;
        M = YT' * (wm .* YT);
        M = (M + M') / 2;
        [V, D] = eig(M);
        mu = diag(D);
        keep = mu > opts.EigTol * max(mu);
        Vk = V(:, keep);
        Proj = (Vk ./ mu(keep)') * (Vk' * (YT' * (wm .* Ym)));
        rnk = nnz(keep);
end
B = struct('type', opts.Type, 'idx', idx, 'T', T, 'Proj', Proj, ...
    'K', size(T, 2), 'nodes', nodes, 'kernel', phi, ...
    'kernelName', kernelName, 'grid', gridName, 'level', level, ...
    'nGlobal', nGlobal, 'lambda', lam, 'rank', rnk, ...
    'eigTol', opts.EigTol, 'region', reg);
end

function phi = kernelCoefficients(opts, idx)
L = idx.Lmax;
nn = (0:L)';
switch opts.Kernel
    case "kaula"
        phi = 1 ./ max(nn, 1).^2;
    case "shannon"
        phi = ones(L + 1, 1);
    otherwise
        sig = opts.DegreeAmplitude(:);
        used = nn >= idx.minDegree;
        if numel(sig) ~= L + 1 || any(~isfinite(sig)) || any(sig(used) <= 0)
            error('shLowLevel:regionalBasis:badAmplitude', ...
                ['Kernel "amplitude" needs DegreeAmplitude as %d finite ' ...
                 'values (n = 0..%d), positive from degree %d on.'], ...
                L + 1, L, idx.minDegree);
        end
        phi = sig ./ sqrt(2 * nn + 1);
end
end

function level = defaultLevel(gridName, L)
% Smallest level whose global grid has at least (L+1)^2 nodes.
target = (L + 1)^2;
if gridName == "icosahedral"
    level = max(ceil((L + 1) / sqrt(10)) - 1, 0);
    while 10 * (level + 1)^2 + 2 < target
        level = level + 1;
    end
else
    level = max(ceil((L + 1) * sqrt(pi) / 2) - 2, 2);
    while numel(reuterGrid(level)) < target
        level = level + 1;
    end
end
end

function [lat, lon] = icosahedralGrid(f)
% Vertices of the icosahedron with every face divided into f^2 triangles,
% projected centrally: 10 f^2 + 2 nodes [deg].
g = (1 + sqrt(5)) / 2;
V = [0 1 g; 0 -1 g; 0 1 -g; 0 -1 -g; 1 g 0; -1 g 0; 1 -g 0; -1 -g 0; ...
     g 0 1; -g 0 1; g 0 -1; -g 0 -1];
V = V ./ vecnorm(V, 2, 2);
D = sqrt(sum((permute(V, [1 3 2]) - permute(V, [3 1 2])).^2, 3));
e = min(D(D > 1e-9));
A = abs(D - e) < 1e-9;
F = zeros(20, 3);
k = 0;
for a = 1:12
    for b = a+1:12
        for c = b+1:12
            if A(a, b) && A(b, c) && A(a, c)
                k = k + 1;
                F(k, :) = [a b c];
            end
        end
    end
end
[I, J] = meshgrid(0:f, 0:f);
inT = I + J <= f;
I = I(inT); J = J(inT); Kb = f - I - J;
nT = numel(I);
pts = zeros(20 * nT, 3);
for q = 1:20
    p = (I .* V(F(q, 1), :) + J .* V(F(q, 2), :) + Kb .* V(F(q, 3), :)) / f;
    pts((q - 1) * nT + (1:nT), :) = p ./ vecnorm(p, 2, 2);
end
pts = uniquetol(pts, 1e-9, 'ByRows', true, 'DataScale', 1);
lat = asind(pts(:, 3));
lon = mod(atan2d(pts(:, 2), pts(:, 1)), 360);
end

function [lat, lon] = reuterGrid(gam)
% Reuter (1982): gam + 1 rings from pole to pole, one node per pole.
dth = pi / gam;
latC = cell(gam + 1, 1); lonC = cell(gam + 1, 1);
latC{1} = 90; lonC{1} = 0;
for i = 1:gam-1
    th = i * dth;
    arg = (cos(dth) - cos(th)^2) / sin(th)^2;
    gi = floor(2 * pi / acos(min(max(arg, -1), 1)));
    latC{i + 1} = repmat(90 - rad2deg(th), gi, 1);
    lonC{i + 1} = ((0:gi-1)' + 0.5) * 360 / gi;
end
latC{gam + 1} = -90; lonC{gam + 1} = 0;
lat = vertcat(latC{:});
lon = vertcat(lonC{:});
end

function near = nearestGridPoint(latDeg, lonDeg, qgrid)
% Row index of the nearest quadrature point (latitude-major rows). The
% nearest point lies on the nearest ring or one of its two neighbours,
% because the ring and longitude spacings are equal to within the
% Gauss-Legendre spread (Python-validated against a brute-force search).
la = deg2rad(latDeg(:)); lo = deg2rad(lonDeg(:));
latR = deg2rad(qgrid.latDeg(:)); lonR = deg2rad(qgrid.lonDeg(:));
nL = numel(latR); nO = numel(lonR);
[~, i0] = min(abs(la - latR'), [], 2);
near = zeros(numel(la), 1);
bestDot = -inf(numel(la), 1);
for s = -1:1
    ii = min(max(i0 + s, 1), nL);
    c = sin(la) .* sin(latR(ii)) + cos(la) .* cos(latR(ii)) .* cos(lo - lonR');
    [cm, jj] = max(c, [], 2);
    upd = cm > bestDot;
    near(upd) = (ii(upd) - 1) * nO + jj(upd);
    bestDot(upd) = cm(upd);
end
end
