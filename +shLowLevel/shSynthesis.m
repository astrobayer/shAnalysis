function [grid, lat, lon, P] = shSynthesis(C, S, GM, R, latVec, lonVec, opts)
%SHSYNTHESIS Spherical harmonic synthesis of a global/regional grid.
%
%   [GRID, LAT, LON] = SHSYNTHESIS(C, S, GM, R, LATVEC, LONVEC) synthesizes
%   the disturbing-potential-derived quantity (default: geoid height) on the
%   grid LATVEC x LONVEC (degrees) from fully normalized (ICGEM) Stokes
%   coefficients C, S at the reference sphere r = R - or, with
%   Surface = "ellipsoid", on the reference ellipsoid (v5.5.0).
%
%   [GRID, LAT, LON, P] = SHSYNTHESIS(...) also returns the precomputed
%   Legendre function array P (as from LEGENDREALF). For batch processing
%   a time series on the SAME grid and NMAX (e.g. monthly GRACE-FO
%   solutions), pass it back in on subsequent calls via P=P to skip
%   the recursion entirely:
%
%       [grid1, lat, lon, P] = shSynthesis(C1, S1, GM, R, latVec, lonVec);
%       for k = 2:nMonths
%           gridK = shSynthesis(Ck, Sk, GM, R, latVec, lonVec, P=P);
%       end
%
%   Options
%     P ([])  precomputed Legendre array from a prior call/LEGENDREALF, for
%          the identical latVec and nmax -- skips recomputing the
%          recursion. Only the size is checked (badP when P has fewer
%          than Nmax+1 degrees or another latitude count); a P for other
%          latitudes of the same count silently gives wrong results.
%     Quantity ("geoid")  one of ('none' = dimensionless passthrough, kernel 1,
%                 no GM/R/kn enter - the clean way to synthesize raw
%                 coefficient fields such as kernels or masks):
%         'geoid'              N = R * sum Pbar_nm (Cnm cos m lon + Snm sin m lon)   [m]
%         'gravity_anomaly'    dg = GM/R^2 * sum (n-1) Pbar_nm (...)                 [m/s^2]
%         'gravity_disturbance' dg = GM/R^2 * sum (n+1) Pbar_nm (...)                [m/s^2]
%         'potential'          T  = GM/R * sum Pbar_nm (...)                        [m^2/s^2]
%         'ewh'                equivalent water height using love numbers 'kn'      [m]
%       and the further kernels of shLowLevel.kernelFactors:
%       'gravity_gradient_rr' [1/s^2], 'surface_density' [kg/m^2] and
%       'bottom_pressure' [Pa] (both need 'kn'), 'deformation_up' [m]
%       (needs 'kn' and 'hn')
%     Nmin (0), Nmax (size(C,1)-1)  degree range to include. Renamed
%                    from nmin/nmax in v4.0.0.
%     kn ([])        load Love number vector k_n (index 1 = degree 0), required
%                    for "ewh"; NOT supplied by default -- see note below.
%     hn ([])        load Love numbers h'_n, for deformation quantities
%     Height (0)     evaluation height [m] above the evaluation surface:
%                    above R on the sphere, above r(phi) on the ellipsoid
%     Surface ("sphere")  "sphere" | "ellipsoid". "sphere" evaluates at
%                    r = R + Height, bitwise as before v5.5.0.
%                    "ellipsoid" evaluates at r(phi) + Height, r(phi) the
%                    geocentric radius of the ellipsoid from
%                    shLowLevel.ellipsoidRadius, through the same (R/r)^p_n
%                    law Height uses. Only quantities with a radial law
%                    accept it: potential, gravity_anomaly,
%                    gravity_disturbance, gravity_gradient_rr. The geoid
%                    is refused deliberately: on the ellipsoid it also
%                    needs the latitude-dependent normal gravity
%                    gamma(phi), and correcting the radius alone would be
%                    half a correction. At high latitudes the ellipsoid
%                    lies INSIDE the sphere (21.4 km at the poles), so
%                    high degrees are amplified there - this is why the
%                    choice matters for gravity near the poles
%     SemiMajorAxis (6378137)  semi-major axis of the ellipsoid [m],
%                    WGS84; used only with Surface = "ellipsoid"
%     Flattening (1/298.257223563)  flattening of the ellipsoid, WGS84;
%                    used only with Surface = "ellipsoid"
%     MaxMemGB (4)   Legendre-block memory budget before banding
%     rho_ave (5517)   average Earth density [kg/m^3] (used for "ewh")
%     rho_water (1000) water density [kg/m^3] (used for "ewh")
%     Method ("auto")  "auto" / "direct" / "fft": FFT-along-longitude
%               synthesis for uniform full-circle longitude grids; 'auto'
%               picks it whenever applicable. The two differ only in the
%               last step, along longitude, and neither is faster
%               everywhere: FFT ran 1.40x faster at nmax 60 / 1 degree
%               on A8 (the reduction alone), while on MATTHIASPC the
%               whole call is 0-14 percent faster with direct across 13
%               sizes from nmax 30 / 1 degree to 360 / 0.5 degree
%               (v5.12.2). 'auto' keeps FFT. (This row claimed "5-20x"
%               until v5.5.0; it was never measured.)
%               Symmetric latitude grids additionally reuse the Legendre
%               recursion for +/-lat pairs via the parity relation.
%
%   NOTE on "ewh": accurate mass-change conversion requires the degree-
%   dependent load Love numbers k_n (e.g. from a PREM-based table, Wahr et
%   al. 1998 / Han & Wahr). This function does NOT hardcode a Love number
%   table to avoid silently using unvalidated constants -- pass kn
%   explicitly. Without it, EWH synthesis will error.
%
%   Outputs
%     grid  (nlat x nlon) double  synthesized field in the units of the
%           requested quantity
%     lat   (1 x nlat) double  geocentric latitude grid used [deg]
%     lon   (1 x nlon) double  longitude grid used [deg]
%     P     (nmax+1 x nmax+1 x nlat) double  Legendre array as returned by
%           LEGENDREALF; pass it back via 'P' to skip the recursion.
%           EMPTY in latitude-banded mode (MaxMemGB exceeded): the blocks
%           are streamed and discarded, so request the 4th output only
%           with a memory budget that fits the full array.
%
%   Error identifiers
%     shLowLevel:shSynthesis:badInput
%         C and S are not square matrices of equal size, or Nmax exceeds
%         the coefficients supplied
%     shLowLevel:shSynthesis:badP
%         a precomputed P does not match Nmax and the latitude vector
%     shLowLevel:shSynthesis:badMethod
%         Method is not "auto", "direct" or "fft" (any case), or
%         Method="fft" on a longitude vector that is not uniform and
%         full-circle
%     shLowLevel:shSynthesis:noRadialLaw
%         Surface="ellipsoid" for a quantity with no radial law (geoid,
%         ewh, the mass and deformation quantities, none): a surface
%         quantity cannot be moved off the sphere
%
%   Claude (Sonnet 4.6), 2026-07-11; merged into +shLowLevel and FFT/parity
%   fast paths added: Claude (Fable 5), 2026-08-07. Ellipsoidal surface:
%   Claude (Opus 5), 2026-09-10 (v5.5.0).
%   Developed by Matthias Weigelt with the help of Claude (Fable 5).

arguments
    C double
    S double
    GM double
    R double
    latVec double
    lonVec double
    opts.Quantity = 'geoid'
    opts.Nmin = 0
    opts.Nmax = size(C,1)-1
    opts.kn = []
    opts.rho_ave = 5517
    opts.rho_water = 1000
    opts.P = []
    opts.Method = 'auto'    % 'auto' | 'direct' | 'fft' (v2.1)
    opts.MaxMemGB = 4       % Legendre-block memory budget (v2.2)
    opts.hn = []            % load Love numbers h'_n (v2.3)
    opts.Height = 0         % evaluation height above R [m] (v2.3)
    opts.Surface (1,1) string {mustBeMember(opts.Surface, ["sphere", "ellipsoid"])} = "sphere"
    opts.SemiMajorAxis (1,1) double {mustBePositive} = 6378137
    opts.Flattening (1,1) double {mustBeNonnegative, mustBeLessThan(opts.Flattening, 1)} = 1/298.257223563
end
quantity = lower(opts.Quantity);
nmin = opts.Nmin;
nmax = opts.Nmax;

if size(C,1) ~= size(C,2) || size(S,1) ~= size(S,2) || size(C,1) ~= size(S,1)
    error('shLowLevel:shSynthesis:badInput', 'C and S must be square matrices of equal size.');
end
if nmax > size(C,1)-1
    error('shLowLevel:shSynthesis:badInput', ...
        'Requested nmax (%d) exceeds available coefficients (max %d).', nmax, size(C,1)-1);
end

lat = latVec(:)';
lon = lonVec(:)';
nlat = numel(lat);
nlon = numel(lon);
latRad = deg2rad(lat);
lonRad = deg2rad(lon);

if isempty(opts.P)
    % symmetric-latitude parity trick: Pbar_nm(-lat) = (-1)^(n+m) Pbar_nm(lat)
    % -> compute the recursion only for unique |lat| and mirror (validated:
    % exact identity), halving the Legendre cost for symmetric grids.
    banded = [];                                 % Legendre in memory bands
else
    P = opts.P;
    if size(P,1) < nmax+1 || size(P,3) ~= nlat
        error('shLowLevel:shSynthesis:badP', ...
            'Supplied P is incompatible with nmax/latVec (size %s).', mat2str(size(P)));
    end
    banded = false;
end

onEllipsoid = opts.Surface == "ellipsoid";
if onEllipsoid
    % The radius now depends on latitude, so the (R/r)^p_n law cannot be
    % folded into the degree kernel once. kernelFactors returns the kernel
    % at r = R together with the exponent, and the per-latitude factor is
    % applied in the reduction below. Height is validated here exactly as
    % kernelFactors validates it on the sphere path.
    mustBeNonnegative(opts.Height);
    [kernel, radialExp] = shLowLevel.kernelFactors(quantity, nmax, GM, R, ...
        kn = opts.kn, hn = opts.hn, ...
        rho_ave = opts.rho_ave, rho_water = opts.rho_water);
    if isempty(radialExp)
        why = '';
        if strcmpi(quantity, 'geoid')
            why = [' On the ellipsoid the geoid also needs the latitude-' ...
                   'dependent normal gravity gamma(phi); correcting the ' ...
                   'radius alone would be half a correction. Evaluate ' ...
                   '''potential'' on the ellipsoid and divide by gamma(phi).'];
        end
        error('shLowLevel:shSynthesis:noRadialLaw', ...
            ['Surface="ellipsoid" needs a quantity with a radial law ' ...
             '(potential, gravity_anomaly, gravity_disturbance, ' ...
             'gravity_gradient_rr); ''%s'' is a surface quantity.%s'], ...
            quantity, why);
    end
    rLat = shLowLevel.ellipsoidRadius(lat, SemiMajorAxis = opts.SemiMajorAxis, ...
        Flattening = opts.Flattening) + opts.Height;
    qLat = (R ./ rLat) .^ radialExp(:);       % (nmax+1) x nlat
else
    kernel = shLowLevel.kernelFactors(quantity, nmax, GM, R, kn = opts.kn, ...
        hn = opts.hn, Height = opts.Height, ...
        rho_ave = opts.rho_ave, rho_water = opts.rho_water);
end

% degree-factor-scaled coefficient copies, nmin truncation via zero rows
KC = kernel .* C(1:nmax+1, 1:nmax+1);
KS = kernel .* S(1:nmax+1, 1:nmax+1);
if nmin > 0
    KC(1:nmin, :) = 0;
    KS(1:nmin, :) = 0;
end

% per-order sums over degree: Am(m+1,k) = sum_n f_n C_nm Pbar_nm(lat_k)
% Memory model (v2.2): the (nmax+1)^2 x nlat Legendre stack is the memory
% driver - 7 GB at nmax=2190 / 181 latitudes. When it exceeds MaxMemGB,
% latitudes are processed in bands: compute the Legendre block, fold it
% into Am/Bm, discard. Only Am/Bm (2 x (nmax+1) x nlat) persist - the
% high-degree capability becomes real instead of nominal. Chunked ==
% monolithic exactly (Python-validated, 0.0); the parity trick still
% applies within each unique-|lat| chunk.
Am = zeros(nmax+1, nlat);
Bm = zeros(nmax+1, nlat);
if isempty(banded)
    needBytes = (nmax+1)^2 * nlat * 8;
    banded = needBytes > opts.MaxMemGB * 2^30;
end
if ~banded && isempty(opts.P)
    [uab, ~, iu] = unique(abs(latRad));
    if numel(uab) < nlat
        Pu = shLowLevel.legendreALF(nmax, uab);
        P = Pu(:, :, iu);
        parity = (-1).^((0:nmax)' + (0:nmax));      % (n+1) x (m+1)
        P(:, :, latRad < 0) = P(:, :, latRad < 0) .* parity;
    else
        P = shLowLevel.legendreALF(nmax, latRad);
    end
end
if banded
    P = [];   % Legendre blocks are streamed and discarded in banded mode;
              % request the 4th output only with a fitting memory budget
    [uab, ~, iu] = unique(abs(latRad));
    parity = (-1).^((0:nmax)' + (0:nmax));
    chunk = max(1, floor(opts.MaxMemGB * 2^30 / ((nmax+1)^2 * 8)));
    for c0 = 1:chunk:numel(uab)
        cc = c0:min(c0+chunk-1, numel(uab));
        Pu = shLowLevel.legendreALF(nmax, uab(cc));
        for j = find(ismember(iu', cc))
            Pk = Pu(:, :, iu(j) - c0 + 1);
            if latRad(j) < 0, Pk = Pk .* parity; end
            if onEllipsoid
                Am(:, j) = sum((qLat(:, j) .* KC) .* Pk, 1)';
                Bm(:, j) = sum((qLat(:, j) .* KS) .* Pk, 1)';
            else
                Am(:, j) = sum(KC .* Pk, 1)';
                Bm(:, j) = sum(KS .* Pk, 1)';
            end
        end
    end
else
    for k = 1:nlat
        Pk = P(1:nmax+1, 1:nmax+1, k);
        if onEllipsoid
            % the sphere branch below is the pre-v5.5.0 code, untouched,
            % which is what keeps it bitwise; the ellipsoid scales each
            % degree row by (R/r(lat_k))^p_n before the same reduction
            Am(:, k) = sum((qLat(:, k) .* KC) .* Pk, 1)';
            Bm(:, k) = sum((qLat(:, k) .* KS) .* Pk, 1)';
        else
            Am(:, k) = sum(KC .* Pk, 1)';
            Bm(:, k) = sum(KS .* Pk, 1)';
        end
    end
end

% method resolution: FFT along longitude for uniform full-circle grids
% (exact accumulation of aliased orders into mod(m, nlon) bins; validated
% against the direct sum to 3e-13 in Python), else direct trig product.
method = lower(opts.Method);
if strcmp(method, 'auto')
    useFFT = false;
    if nlon >= 2
        dl = diff(lonRad);
        if all(abs(dl - dl(1)) < 1e-12) && dl(1) > 0 ...
                && abs(nlon*dl(1) - 2*pi) < 1e-9
            useFFT = true;
        end
    end
elseif strcmp(method, 'fft')
    dl = diff(lonRad);
    if nlon < 2 || any(abs(dl - dl(1)) >= 1e-12) || dl(1) <= 0 ...
            || abs(nlon*dl(1) - 2*pi) >= 1e-9
        error('shLowLevel:shSynthesis:badMethod', ...
            'method=''fft'' requires a uniform, full-circle longitude vector.');
    end
    useFFT = true;
elseif strcmp(method, 'direct')
    useFFT = false;
else
    % v5.23.4: any other value used to run the direct path silently, so a
    % typo ("fast", "ftt") was indistinguishable from "direct"
    error('shLowLevel:shSynthesis:badMethod', ...
        'Method must be "auto", "direct" or "fft" (got "%s").', opts.Method);
end

if useFFT
    ph  = exp(1i * (0:nmax)' * lonRad(1));
    Csp = (Am - 1i*Bm) .* ph;                % (nmax+1) x nlat
    Cpad = zeros(nlon, nlat);
    bins = mod(0:nmax, nlon) + 1;
    for mm = 0:nmax
        Cpad(bins(mm+1), :) = Cpad(bins(mm+1), :) + Csp(mm+1, :);
    end
    grid = real(ifft(Cpad, [], 1)).' * nlon;
else
    m = (0:nmax)';
    cosMLon = cos(m * lonRad);               % (nmax+1) x nlon
    sinMLon = sin(m * lonRad);
    grid = Am.' * cosMLon + Bm.' * sinMLon;
end

end
