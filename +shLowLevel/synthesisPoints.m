function val = synthesisPoints(C, S, GM, R, latDeg, lonDeg, r, opts)
%SYNTHESISPOINTS Gravity field quantities at arbitrary 3-D points.
%
%   VAL = shLowLevel.synthesisPoints(C, S, GM, R, LATDEG, LONDEG, RGEO)
%   evaluates the spherical harmonic expansion POINTWISE at positions
%   given by equal-length vectors of geocentric latitude [deg],
%   longitude [deg] and geocentric radius [m] - satellite altitudes,
%   scattered stations, profiles - including the upward continuation
%   (R/r)^n that grid synthesis on the sphere cannot provide:
%     potential    T   = GM/r     sum_n (R/r)^n     sum_m Pnm (C cos + S sin)
%     disturbance  dg  = GM/r^2   sum_n (n+1)(R/r)^n ...   ( = -dT/dr )
%     anomaly      Dg  = GM/r^2   sum_n (n-1)(R/r)^n ...
%   Fully normalized coefficients, C(n+1,m+1) layout, geocentric
%   latitudes (house conventions). Python-validated: pinned reference
%   values at the surface and at 450 km altitude, and the radial
%   derivative identity dg = -dT/dr to 3e-10 (tools/validate_sh
%   pointwise block; pins in testCorrectness/testSynthesisPoints).
%
%   Two summations, same series (v5.1.0)
%     "direct"    builds Pbar_nm and contracts it against the
%                 coefficients, one point at a time. Pbar is computed for
%                 a CHUNK of points per call to shLowLevel.legendreALF
%                 (which accepts a latitude vector), so the recursion runs
%                 once per chunk instead of once per point. The per-point
%                 reduction is unchanged, so results are BITWISE identical
%                 to v5.0.3 and earlier. Cost grows linearly with the
%                 number of points; memory is bounded by MaxMemGB.
%     "clenshaw"  reorders the same double sum by ORDER, and evaluates
%                 each order's degree sum by Clenshaw summation
%                 (Holmes & Featherstone 2002 - the paper this toolbox
%                 already follows for legendreALF). Pbar is NEVER formed:
%                 memory is O(nmax + P) rather than O(nmax^2) per point,
%                 which is what makes very high degree reachable at all.
%                 The recursion is vectorised ACROSS POINTS, so its cost
%                 is nearly independent of the point count.
%     One is linear in P and the other nearly flat, so in principle they
%     cross. IN MATLAB THEY DO NOT: "clenshaw" is faster at every point
%     count measured - P = 1..2000 at nmax 60 and 120, P = 1..200 at
%     nmax 360 (benchPointsCrossover; 2.0x at the narrowest margin, 34x
%     at a single point). The crossover exists in the numpy prototype
%     and not here,
%     because "direct" is bounded by shLowLevel.legendreALF, which
%     "clenshaw" never calls. So "auto" is "clenshaw" everywhere - see
%     ClenshawFrom for how that is expressed and how to measure it again.
%
%   Clenshaw is not bitwise, and cannot be: it sums the same terms in a
%   different order. It is validated against the direct path and against
%   a 60-digit reference in tools/dev/validate_points_clenshaw.py; both
%   paths land within a few tens of eps of the truth and neither
%   dominates the other.
%
%   Options
%     Quantity ("potential")  "potential" [m^2/s^2] | "disturbance" |
%                             "anomaly" (both [m/s^2]; multiply by 1e5
%                             for mGal)
%     Nmin (2)           first degree included (0 evaluates the
%                             full field including the central term)
%     Method ("auto")    "auto" | "direct" | "clenshaw" - which
%                             summation to use; "auto" chooses "clenshaw"
%                             once the point count reaches ClenshawFrom
%     ClenshawFrom (1)   point count at or above which "auto" switches to
%                             "clenshaw". The default is 1 because MATLAB
%                             has NO crossover: benchPointsCrossover timed
%                             both paths at the same points and found
%                             "clenshaw" ahead at every count measured
%                             (P = 1..2000 at nmax 60 and 120, P = 1..200
%                             at nmax 360; narrowest margin 2.0x).
%                             Until v5.1.1 this was 150 - the
%                             crossover of the NUMPY prototype
%                             (tools/dev/validate_points_clenshaw.py,
%                             "direct" winning at P <= 100), transplanted
%                             to a language where it does not hold, which
%                             sent every station list below 150 points
%                             down the slower path. Raise it to force
%                             "direct" (the bitwise path) for short lists;
%                             re-measure with benchPointsCrossover before
%                             changing the default on a new machine
%     MaxMemGB (4)       memory budget for the "direct" path's Legendre
%                             block; the chunk size follows from it and
%                             from nmax. Ignored by "clenshaw", which
%                             never allocates one
%
%   Outputs
%     val        (P,1) double  quantity at each point
%
%   Example
%     dg = shLowLevel.synthesisPoints(g.C, g.S, g.GM, g.R, ...
%         [10; 12], [100; 101], (g.R + 450e3) * [1; 1], ...
%         Quantity = "disturbance") * 1e5;   % mGal at 450 km
%
%   Error identifiers
%     shLowLevel:synthesisPoints:sizeMismatch
%         latDeg, lonDeg and r differ in length, or C and S in size
%
%   References
%     Holmes, S.A., Featherstone, W.E. (2002): A unified approach to the
%     Clenshaw summation and the recursive computation of very high
%     degree and order normalised associated Legendre functions.
%     Journal of Geodesy 76, 279-299.
%
%   Developed by Matthias Weigelt with the help of Claude (Fable 5),
%   2026-08-10 (v3.0.0); Method option and Clenshaw path 2026-09-09
%   (v5.1.0), developed with the help of Claude.
arguments
    C double
    S double
    GM (1,1) double {mustBePositive}
    R (1,1) double {mustBePositive}
    latDeg (:,1) double {mustBeGreaterThanOrEqual(latDeg, -90), ...
        mustBeLessThanOrEqual(latDeg, 90)}
    lonDeg (:,1) double
    r (:,1) double {mustBePositive}
    opts.Quantity (1,1) string {mustBeMember(opts.Quantity, ...
        ["potential", "disturbance", "anomaly"])} = "potential"
    opts.Nmin (1,1) double {mustBeInteger, mustBeNonnegative} = 2
    opts.Method (1,1) string {mustBeMember(opts.Method, ...
        ["auto", "direct", "clenshaw"])} = "auto"
    opts.ClenshawFrom (1,1) double {mustBeInteger, mustBePositive} = 1
    opts.MaxMemGB (1,1) double {mustBePositive} = 4
end
P = numel(latDeg);
if numel(lonDeg) ~= P || numel(r) ~= P
    error('shLowLevel:synthesisPoints:sizeMismatch', ...
        'latDeg, lonDeg and r must have equal length.');
end
if ~isequal(size(C), size(S))
    error('shLowLevel:synthesisPoints:sizeMismatch', 'C and S must match.');
end
nmax = size(C, 1) - 1;
n0 = min(opts.Nmin, nmax);

method = lower(opts.Method);
if strcmp(method, 'auto')
    if P >= opts.ClenshawFrom
        method = 'clenshaw';
    else
        method = 'direct';
    end
end

if strcmp(method, 'clenshaw')
    val = clenshawSum(C, S, GM, R, latDeg, lonDeg, r, nmax, n0, opts.Quantity);
else
    val = directSum(C, S, GM, R, latDeg, lonDeg, r, nmax, n0, ...
        opts.Quantity, opts.MaxMemGB);
end
end


function val = directSum(C, S, GM, R, latDeg, lonDeg, r, nmax, n0, ...
    quantity, maxMemGB)
%DIRECTSUM Pbar built per CHUNK of points, contracted one point at a time.
%   The per-point reduction is byte-for-byte what v3.0.0..v5.0.3 did;
%   only the shLowLevel.legendreALF call moved out of the loop. The
%   recursion is elementwise in latitude, so batching cannot change a
%   single bit of Pbar - which is why this path is the bitwise reference.
P = numel(latDeg);
val = zeros(P, 1);
mvec = 0:nmax;
% one Legendre block is 8*(nmax+1)^2 bytes per point; keep it under budget
chunk = floor(maxMemGB * 2^30 / (8 * (nmax + 1)^2));
chunk = max(1, min(chunk, P));
for s = 1:chunk:P
    e = min(s + chunk - 1, P);
    Pblk = shLowLevel.legendreALF(nmax, deg2rad(latDeg(s:e)));  % radians in!
    for k = s:e
        Pnm = Pblk(:, :, k - s + 1);
        cm = cosd(mvec * lonDeg(k));
        sm = sind(mvec * lonDeg(k));
        q = (R / r(k)) .^ (0:nmax)';
        switch quantity
            case "potential"
                f = GM / r(k) .* q;
            case "disturbance"
                f = GM / r(k)^2 .* ((0:nmax)' + 1) .* q;
            case "anomaly"
                f = GM / r(k)^2 .* ((0:nmax)' - 1) .* q;
        end
        inner = sum(Pnm .* (C .* cm + S .* sm), 2);  % per-degree sums
        val(k) = f(n0+1:end)' * inner(n0+1:end);
    end
end
end


function val = clenshawSum(C, S, GM, R, latDeg, lonDeg, r, nmax, n0, quantity)
%CLENSHAWSUM Per-ORDER lumped coefficients, Clenshaw summation over degree.
%   For each order m the two degree sums
%       A_m = sum_n f_n C_nm Pbar_nm ,  B_m = sum_n f_n S_nm Pbar_nm
%   are evaluated by the Clenshaw recurrence for Pbar_nm, so no Pbar is
%   ever stored. Both recurrences run vectorised over ALL points at once,
%   which is what makes the cost nearly independent of the point count.
%   The sectorial Pbar_mm carries the same 1e-280 scaling that
%   legendreALF uses, so the u^m factor cannot underflow near the poles.
P = numel(latDeg);
t = sind(latDeg(:)');                       % 1 x P, sin(geocentric lat)
u = cosd(latDeg(:)');
lam = deg2rad(lonDeg(:)');
rr = r(:)';

nvec = (0:nmax)';
q = (R ./ rr) .^ nvec;                      % (nmax+1) x P
switch quantity
    case "potential"
        f = (GM ./ rr) .* q;
    case "disturbance"
        f = (GM ./ rr.^2) .* (nvec + 1) .* q;
    case "anomaly"
        f = (GM ./ rr.^2) .* (nvec - 1) .* q;
end
f(1:n0, :) = 0;                             % Nmin truncation

val = zeros(1, P);
scalef = 1e-280;                            % as in legendreALF
pmm = scalef;                               % latitude-independent factor
rescalem = (1 / scalef) * ones(1, P);       % u^m / scalef, accumulated
for m = 0:nmax
    if m >= 1
        rescalem = rescalem .* u;
        if m == 1
            pmm = pmm * sqrt(3);
        else
            pmm = pmm * sqrt((2*m + 1) / (2*m));
        end
    end
    bc1 = zeros(1, P); bc2 = zeros(1, P);
    bs1 = zeros(1, P); bs2 = zeros(1, P);
    for n = nmax:-1:m
        if n + 1 <= nmax
            np = n + 1;
            a1 = sqrt((2*np - 1) * (2*np + 1) / ((np - m) * (np + m)));
        else
            a1 = 0;
        end
        if n + 2 <= nmax
            nq = n + 2;
            b2 = sqrt((2*nq + 1) * (nq + m - 1) * (nq - m - 1) ...
                / ((nq - m) * (nq + m) * (2*nq - 3)));
        else
            b2 = 0;
        end
        bcn = f(n+1, :) * C(n+1, m+1) + a1 * t .* bc1 - b2 * bc2;
        bsn = f(n+1, :) * S(n+1, m+1) + a1 * t .* bs1 - b2 * bs2;
        bc2 = bc1; bc1 = bcn;
        bs2 = bs1; bs1 = bsn;
    end
    pbarmm = pmm * rescalem;                % Pbar_mm at every point
    val = val + cos(m * lam) .* (bc1 .* pbarmm) ...
              + sin(m * lam) .* (bs1 .* pbarmm);
end
val = val(:);
end
