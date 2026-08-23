function [dq, info] = shSynthesisGradient(C, S, GM, R, latDeg, lonDeg, opts)
%SHSYNTHESISGRADIENT North/east/up gradient of any synthesized quantity.
%
%   [DQ, INFO] = shLowLevel.shSynthesisGradient(C, S, GM, R, LAT, LON,
%       quantity ("geoid")=..., Units ("perMeter")=..., Mode ("grid")=...)
%   returns the spatial gradient of the field that
%   shLowLevel.shSynthesis would produce from the SAME coefficients and
%   the SAME options, resolved in the local north-east-up frame:
%
%     DQ.north = (1/r) dQ/dphi        =  (1/r) sum f_n sum dPbar_nm/dphi (...)
%     DQ.east  = (1/(r cos phi)) dQ/dlambda
%                                    =  (1/(r cos phi)) sum f_n sum m Pbar_nm (...)
%     DQ.up    = dQ/dr                = -(1/r) sum p_n f_n sum Pbar_nm (...)
%
%   with (...) = C_nm cos(m lambda) + S_nm sin(m lambda), f_n the degree
%   factor from shLowLevel.kernelFactors and p_n its radial exponent.
%
%   THE CONTRACT IS "exact derivative of shSynthesis under identical
%   options". Nothing else would be safe: a gradient that quietly used a
%   different nmin, a different kernel or a different mean field than the
%   scalar map it is drawn over is a vector field pointing at a picture
%   nobody is looking at. The defaults therefore MATCH shSynthesis
%   (quantity "geoid", nmin 0), and testCorrectness pins the identity by
%   finite differences of shSynthesis itself.
%
%   WHICH QUANTITIES HAVE AN UP COMPONENT. dQ/dr exists exactly for the
%   quantities that carry an upward-continuation law, i.e. exactly those
%   that accept Height in shLowLevel.kernelFactors:
%
%     potential, gravity_anomaly, gravity_disturbance,
%     gravity_gradient_rr                          -> G.up is a field
%     geoid, ewh, surface_density, bottom_pressure,
%     deformation_up, none                         -> G.up is [] (EMPTY)
%
%   The second group are SURFACE concepts - an equivalent water height
%   one kilometre up is not a smaller equivalent water height, it is
%   nothing - so the up component is returned EMPTY rather than as a
%   field of zeros or NaN. Empty fails loudly at the first use; a NaN
%   field would be plotted. INFO.hasUp is the programmatic form of the
%   same fact.
%
%   NOT THE SAME AS DEFORMATION. shLowLevel.shSynthesisDeformation's
%   horizontal components are NOT this gradient: elastic horizontal
%   displacement carries the load Love number l'_n and the vertical one
%   carries h'_n, so the two fields differ by a degree-dependent factor,
%   not by a constant. Use this function for "which way does the field
%   fall", use that one for "which way does the crust move".
%
%   Inputs
%     C, S    (n1,n1) double        Stokes coefficients, C(n+1,m+1);
%                                   use RESIDUAL fields for time-variable
%                                   work (the gradient of a static field
%                                   is dominated by the flattening)
%     GM      (1,1) double [m^3/s^2]
%     R       (1,1) double [m]      reference radius
%     latDeg  (1,nlat) double [deg] GEOCENTRIC latitude
%     lonDeg  (1,nlon) double [deg] longitude
%
%   Options
%     quantity ("geoid")  any quantity of shLowLevel.kernelFactors:
%         "none", "geoid", "potential", "gravity_anomaly",
%         "gravity_disturbance", "gravity_gradient_rr", "ewh",
%         "surface_density", "bottom_pressure", "deformation_up"
%     kn ([])       load Love numbers k'_n, degrees 0..nmax; REQUIRED by
%                   the mass quantities, never hardcoded
%     hn ([])       load Love numbers h'_n (deformation_up only)
%     nmin (0)      degrees below nmin are zeroed. Degree 0 and 1 have no
%                   horizontal gradient beyond the degree-1 tilt, but
%                   they DO contribute to G.up - so this is not a free
%                   choice; keep it equal to the scalar map's
%     nmax (NaN)    truncation degree; NaN uses all supplied degrees
%     Height (0)    evaluation height above R [m]; r = R + Height enters
%                   both the kernel attenuation and the metric factors.
%                   Rejected for surface quantities, by kernelFactors
%     rho_ave (5517)    mean Earth density [kg/m^3] (mass kernels)
%     rho_water (1000)  water density [kg/m^3] (ewh kernel)
%     Mode ("grid")   "grid" evaluates the nlat x nlon outer product;
%         "points" takes equal-length LAT/LON and evaluates pairwise -
%         the mode a particle advection needs when it steps tracers at
%         their own positions. NOTE the cost: "points" pays a Legendre
%         recursion per point, so a per-frame call for 10^4 tracers is
%         far slower than one grid call plus interpolation. Grid-and-
%         interpolate is the right pattern for animation; "points" is
%         for when the exact value at a station matters
%     Units ("perMeter")  "perMeter" is the true gradient [Q]/m.
%         "perRadian" multiplies every component by r, giving dQ/dphi,
%         (1/cos phi) dQ/dlambda and dQ/d(ln r) - the form a lat/lon
%         advection step wants, since dphi/dt is then G.north/r directly
%     MaxMemGB (4)  memory budget [GB] for the Legendre stack; latitudes
%         are processed in bands so nmax is not limited by it
%
%   Outputs
%     dq  (1,1) struct  fields north, east, up, each (nlat x nlon)
%           double for Mode "grid" or (npts x 1) double for "points".
%           EAST is NaN where |lat| = 90 - the east direction does not
%           exist at a pole, and the cos(phi) division there returns a
%           finite, meaningless number if it is not caught. UP is []
%           for surface quantities (see above)
%     info  (1,1) struct  quantity, units, r [m], nmin, nmax, hasUp
%           (1,1) logical, lat (1 x nlat) double, lon (1 x nlon) double -
%           the geocentric latitudes and longitudes actually used
%
%   Example
%     % a zonal degree-2 pattern: the east gradient must vanish exactly
%     C = zeros(3); S = zeros(3); C(3,1) = 1;              % C_20
%     lat = -80:10:80; lon = 0:20:340;
%     dq = shLowLevel.shSynthesisGradient(C, S, 3.986004415e14, ...
%             6378136.3, lat, lon, quantity = "none", Units = "perRadian");
%     max(abs(dq.east(:)))            % 0
%     quiver(lon, lat, dq.east, dq.north)
%
%   References
%     Wahr, Molenaar & Bryan (1998), JGR 103(B12) - the degree factors.
%     Holmes & Featherstone (2002), J Geod 76 - the Legendre recursion
%     whose exact latitude derivative shLowLevel.legendreALFDeriv carries.
%
%   Python-validated before implementation (tools/dev/validate_gradient.py):
%   all three components against 5-point finite differences of an
%   independent scalar synthesis at 1e-12 (the difference floor), the
%   radial identities d(potential)/dr = -gravity_disturbance and
%   d(gravity_disturbance)/dr = -gravity_gradient_rr at 4e-16, and
%   single-coefficient closed forms at 2e-16.
%
%   See also SHSYNTHESIS, SHSYNTHESISDEFORMATION, SHSYNTHESISGRADIENTTENSOR,
%   KERNELFACTORS, LEGENDREALFDERIV.
%
%   Claude (Opus 5), 2026-08-22 (v3.30.0).
%   Developed by Matthias Weigelt with the help of Claude (Opus 5).
arguments
    C double
    S double
    GM (1,1) double
    R (1,1) double {mustBePositive}
    latDeg (1,:) double {mustBeInRange(latDeg, -90, 90)}
    lonDeg (1,:) double
    opts.quantity (1,1) string = "geoid"
    opts.kn double = []
    opts.hn double = []
    opts.nmin (1,1) double {mustBeInteger, mustBeNonnegative} = 0
    opts.nmax (1,1) double = NaN
    opts.Height (1,1) double {mustBeNonnegative} = 0
    opts.rho_ave (1,1) double = 5517
    opts.rho_water (1,1) double = 1000
    opts.Mode (1,1) string {mustBeMember(opts.Mode, ["grid", "points"])} = "grid"
    opts.Units (1,1) string ...
        {mustBeMember(opts.Units, ["perMeter", "perRadian"])} = "perMeter"
    opts.MaxMemGB (1,1) double {mustBePositive} = 4
end

assert(isequal(size(C), size(S)) && size(C, 1) == size(C, 2), ...
    'shSynthesis:badInput', 'C and S must be equally sized square matrices.');
nmax = opts.nmax;
if isnan(nmax), nmax = size(C, 1) - 1; end
assert(nmax <= size(C, 1) - 1, 'shSynthesis:badInput', ...
    'Requested nmax (%d) exceeds available coefficients (max %d).', ...
    nmax, size(C, 1) - 1);
N1 = nmax + 1;
pts = opts.Mode == "points";
if pts
    assert(numel(latDeg) == numel(lonDeg), 'shSynthesis:badInput', ...
        'Mode="points" needs equal-length LAT and LON.');
end

% --- degree factors and the radial law, from the ONE place that owns them
[f, radialExp] = shLowLevel.kernelFactors(char(opts.quantity), nmax, GM, R, ...
    kn = opts.kn, hn = opts.hn, Height = opts.Height, ...
    rho_ave = opts.rho_ave, rho_water = opts.rho_water);
if opts.nmin > 0
    f(1:min(opts.nmin, N1)) = 0;
end
hasUp = ~isempty(radialExp);
r = R + opts.Height;

Cq = C(1:N1, 1:N1);
Sq = S(1:N1, 1:N1);
KC = f .* Cq;                       % horizontal, and the east operand
KS = f .* Sq;
if hasUp
    KCu = (radialExp .* f) .* Cq;   % d/dr = -(p_n/r) f_n
    KSu = (radialExp .* f) .* Sq;
end

latRad = deg2rad(latDeg(:)');
lonRad = deg2rad(lonDeg(:)');
nlat = numel(latRad);
nlon = numel(lonRad);
m = (0:nmax)';
if pts
    nOut = nlat;
    sz = [nlat, 1];
else
    nOut = nlat;
    sz = [nlat, nlon];
    cosML = cos(m * lonRad);        % N1 x nlon
    sinML = sin(m * lonRad);
end

% w folds the metric AND the unit choice into one factor: perRadian is
% exactly r times perMeter in every component, up included (r dQ/dr is
% dQ/d(ln r)), so there is one multiplication, not three conventions.
if opts.Units == "perMeter"
    w = 1 / r;
else
    w = 1;
end

gN = zeros(sz);
gE = zeros(sz);
if hasUp, gU = zeros(sz); else, gU = []; end

% Legendre in latitude bands: P and D are each N1^2 x nBand doubles, and
% the recursion needs a third of that as headroom
bytesPerLat = 3 * N1^2 * 8;
nBand = max(1, floor(opts.MaxMemGB * 2^30 / bytesPerLat));
for b0 = 1:nBand:nOut
    b = b0:min(b0 + nBand - 1, nOut);
    [P, D] = shLowLevel.legendreALFDeriv(nmax, latRad(b));
    for j = 1:numel(b)
        k = b(j);
        Pk = P(:, :, j);
        Dk = D(:, :, j);
        if pts
            cM = cos(m * lonRad(k));
            sM = sin(m * lonRad(k));
        else
            cM = cosML;
            sM = sinML;
        end
        vN = (sum(KC .* Dk, 1) * cM + sum(KS .* Dk, 1) * sM) * w;
        cl = cos(latRad(k));
        if abs(cl) < 1e-12
            vE = NaN(1, size(cM, 2));
        else
            vE = (sum(KC .* Pk, 1) * (-(m .* sM)) ...
                + sum(KS .* Pk, 1) * (m .* cM)) * (w / cl);
        end
        if pts
            gN(k) = vN;
            gE(k) = vE;
        else
            gN(k, :) = vN;
            gE(k, :) = vE;
        end
        if hasUp
            vU = -(sum(KCu .* Pk, 1) * cM + sum(KSu .* Pk, 1) * sM) * w;
            if pts, gU(k) = vU; else, gU(k, :) = vU; end
        end
    end
end

dq = struct('north', gN, 'east', gE, 'up', gU);
info = struct('quantity', opts.quantity, 'units', opts.Units, 'r', r, ...
    'nmin', opts.nmin, 'nmax', nmax, 'hasUp', hasUp, ...
    'lat', latDeg(:)', 'lon', lonDeg(:)');
end
