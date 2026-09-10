function r = ellipsoidRadius(latDeg, opts)
%ELLIPSOIDRADIUS Geocentric radius of a reference ellipsoid at a latitude.
%   R = shLowLevel.ellipsoidRadius(LATDEG) is the distance from the
%   Earth's centre to the surface of the WGS84 ellipsoid at each
%   GEOCENTRIC latitude in LATDEG:
%
%       r(phi) = a sqrt( (1 - e^2) / (1 - e^2 cos^2 phi) ),  e^2 = f (2 - f)
%
%   which is the polar form of x^2/a^2 + z^2/b^2 = 1 with b = a (1 - f).
%   r is a at the equator and b = a (1 - f) at the poles, some 21.4 km
%   less.
%
%   This is the ONE place the toolbox computes r(phi). shSynthesis and
%   shSynthesisGradient call it for Surface = "ellipsoid", and it is
%   public so that a station list can be evaluated on the ellipsoid with
%   shLowLevel.synthesisPoints, which takes an explicit radius per point:
%   pass r = shLowLevel.ellipsoidRadius(lat) + h.
%
%   The latitude must be GEOCENTRIC, as for every spherical-harmonic
%   routine here. A geodetic latitude puts the point off the surface - at
%   45 degrees by the geodetic-geocentric difference (0.19 deg) times
%   dr/dphi - so convert with shLowLevel.geodetic2geocentric first.
%
%   Inputs
%     latDeg  double array  GEOCENTRIC latitudes in degrees, -90..90
%
%   Outputs
%     r       double array  geocentric radius [m], same size as latDeg
%
%   Options
%     SemiMajorAxis (6378137)  semi-major axis a [m]. The WGS84 value -
%                        the same a shLowLevel.normalFieldCS uses for its
%                        WGS84 system, and a test pins that the two agree.
%                        Deliberately NOT the coefficients' reference
%                        radius R (6378136.3 for most GRACE products): R
%                        belongs to the series, a to the surface, and
%                        pairing WGS84's flattening with R would describe
%                        an ellipsoid nobody uses
%     Flattening (1/298.257223563)  flattening f, WGS84 as everywhere else
%                        in the toolbox. 0 is allowed and gives a sphere
%                        of radius SemiMajorAxis, which is what makes the
%                        sphere a special case rather than a separate path
%
%   Example
%     % gravity disturbance at stations on the ellipsoid, 150 m up
%     r = shLowLevel.ellipsoidRadius(lat) + 150;
%     dg = shLowLevel.synthesisPoints(C, S, GM, R, lat, lon, r, ...
%         Quantity = "disturbance");
%
%   See also shLowLevel.shSynthesis, shLowLevel.synthesisPoints,
%   shLowLevel.geodetic2geocentric, shLowLevel.normalFieldCS.
%
%   Developed by Matthias Weigelt with the help of Claude (Opus 5),
%   2026-09-10 (v5.5.0).
arguments
    latDeg double {mustBeGreaterThanOrEqual(latDeg, -90), ...
        mustBeLessThanOrEqual(latDeg, 90)}
    opts.SemiMajorAxis (1,1) double {mustBePositive} = 6378137
    opts.Flattening (1,1) double {mustBeNonnegative, mustBeLessThan(opts.Flattening, 1)} = 1/298.257223563
end
e2 = opts.Flattening * (2 - opts.Flattening);
% cosd, not cos(deg2rad()): it is exact at +-90, where the pole must come
% out as b and not as b plus a rounding of cos(pi/2)
r = opts.SemiMajorAxis * sqrt((1 - e2) ./ (1 - e2 * cosd(latDeg).^2));
end
