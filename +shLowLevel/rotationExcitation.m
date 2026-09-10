function [chi, info] = rotationExcitation(C21, S21, opts)
%ROTATIONEXCITATION Earth-rotation excitation of the degree-2 coefficients.
%   CHI = shLowLevel.rotationExcitation(C21, S21, kn = KN) is the
%   mass-load excitation of polar motion that a series of degree-2,
%   order-1 Stokes coefficients carries. It is Chen & Wilson (2003)
%   eq. (1) solved for the excitation:
%
%       chi1 = -f R^2 M / ((1 + k2') sqrt(3/5) (C - A)) dC21,    f = 1.098
%       chi2 = -f R^2 M / ((1 + k2') sqrt(3/5) (C - A)) dS21
%
%   CHI = shLowLevel.rotationExcitation(..., C20 = C20) adds the axial
%   excitation, the third line of eq. (1) solved the same way, and the
%   change in the length of day it causes:
%
%       chi3 = -g R^2 M 2 sqrt(5) / ((1 + k2') 3 C) dC20,           g = 0.753
%       dLOD = (2 pi / Omega) chi3
%
%   dC21, dS21 and dC20 are the changes of the coefficients about their
%   mean over the series (Reference = "mean"), or the input itself when it
%   already holds changes (Reference = "none"). M and R are the Earth's
%   mass and radius, C and A its principal moments of inertia, k2' the
%   degree-2 load Love number, kn(3), and Omega the Earth's mean angular
%   velocity.
%
%   The Earth's constants
%   Earth = "IERS2010", the default, takes them from the IERS Conventions
%   (2010), Table 1.1. The table lists G, GM, a_E, J2 and the dynamical
%   flattening H rather than M, C and A, which follow by definition:
%
%       M = GM / G,   C - A = J2 M a_E^2,   C = (C - A) / H,   R = a_E
%
%   with A the mean of the two equatorial moments. C and A agree with
%   those ESMGFZ tabulates (Dobslaw & Dill 2019, Table 2.1) to 0.03
%   percent. R is the equatorial radius: the table gives no mean radius,
%   which eq. (1) names, and the two differ by 0.23 percent in R^2.
%   Earth = struct('M', .., 'R', .., 'C', .., 'A', ..) uses constants of
%   the caller's own; info.earth reports the four that were used.
%
%   The length of day
%   dLOD = (2 pi / Omega) chi3 is eq. (2.8) of the ESMGFZ Product
%   Description Document (Dobslaw & Dill 2019) together with its eqs.
%   (2.3) and (2.13): the axial excitation times the rotation period. The
%   equation prints 2 pi Omega; only 2 pi / Omega is a time, and that is
%   how it is read here. Its sign agrees with eq. (1): mass moving away
%   from the axis lowers C20, raises chi3 and lengthens the day.
%
%   The factors
%   1.098 and 0.753 are the paper's, after Eubanks (1993), and are
%   options. For the polar terms the ESMGFZ prefactors give 1.101, the
%   same to 0.3 percent. For the axial term they give 1.125 x 0.750 =
%   0.844, 12 percent more than 0.753 and close to C / Cm = 1.129, the
%   whole Earth's axial moment over the mantle's; Dobslaw & Dill note that
%   some authors put the mantle's moment into the axial term. AxialFactor
%   is there for a caller who takes that convention.
%
%   What the excitation is, and what it is not
%   - It is the excitation of the mass the coefficients carry. A GSM
%     series has the atmosphere and the ocean removed (AOD1B), so it gives
%     the rest - water on land, ice, the solid Earth; restore GAC first
%     (ts.restore) for the whole mass term. The motion term - winds and
%     currents - is never in a gravity field.
%   - chi1 and chi2 are in the frame of the coefficients, x towards
%     Greenwich and y towards 90 E: eq. (1) treats (C21, chi1) and
%     (S21, chi2) alike, and S21 goes with sin(lambda). The IERS pole
%     coordinate y points to 90 W, so compare with an excitation derived
%     from polar motion only in one stated frame.
%   - C21 and S21 depend on the mean-pole model used to remove the pole
%     tide. Convert with shLowLevel.poleTideConvert before comparing
%     series processed under different conventions.
%   - GRACE determines C20 worst of all its coefficients: pass the SLR
%     value (TN-14, readTN14) as C20.
%
%   Inputs
%     C21  (T,1) double  C21 at each epoch, 4-pi normalised
%     S21  (T,1) double  S21 at each epoch
%
%   Outputs
%     chi   (1,1) struct  the excitation, fields
%           chi1         (T,1) double  polar-motion excitation along x [mas]
%           chi2         (T,1) double  along y, towards 90 E [mas]
%           chi3         (T,1) double  axial excitation, dimensionless;
%                        empty without C20
%           dLOD         (T,1) double  change in the length of day [ms];
%                        empty without C20
%     info  (1,1) struct  fields
%           k2           (1,1) double  the load Love number used, kn(3)
%           polarScale   (1,1) double  chi1 [mas] per unit dC21 (and chi2
%                        per unit dS21)
%           axialScale   (1,1) double  chi3 per unit dC20
%           lodScale     (1,1) double  dLOD [ms] per unit chi3, 2 pi / Omega
%           removedMean  (1,3) double  the means of C21, S21 and C20 that
%                        were removed: zeros with Reference = "none", NaN
%                        for C20 when it was not given
%           earth        (1,1) struct  the constants used: M [kg], R [m],
%                        C and A [kg m^2]
%
%   Options
%     Earth       ("IERS2010")  "IERS2010", or a struct with fields M [kg],
%                 R [m], and C and A [kg m^2] - the Earth's mass, radius
%                 and two principal moments of inertia
%     kn          ([])  REQUIRED: load Love numbers, kn(1) degree 0; only
%                 kn(3), the degree-2 value, is used (readLoveNumbers)
%     C20         ([])  (T,1) double  C20 at each epoch; gives chi3 and
%                 dLOD. Pass the SLR value (TN-14), not GRACE's own
%     Reference   ("mean")  "mean" | "none": remove each coefficient's
%                 mean over the series, or take the input as changes
%     PolarFactor (1.098)  the factor in the first two lines of eq. (1)
%     AxialFactor (0.753)  the factor in the third line of eq. (1)
%     Omega       (7.292115e-5)  the Earth's mean angular velocity
%                 [rad/s], as in ESMGFZ's Table 2.1; dLOD scales with
%                 2 pi / Omega
%
%   Example
%     chi = shLowLevel.rotationExcitation(squeeze(ts.Cs(3, 2, :)), ...
%         squeeze(ts.Ss(3, 2, :)), kn = kn, C20 = tn14C20);
%
%   Error identifiers
%     shLowLevel:rotationExcitation:noEarth
%         Earth is neither a convention name nor a struct with M, R, C
%         and A
%     shLowLevel:rotationExcitation:badEarth
%         the convention is unknown, a constant is not a positive finite
%         scalar, or C does not exceed A
%     shLowLevel:rotationExcitation:missingLoveNumbers
%         kn was not given
%     shLowLevel:rotationExcitation:knTooShort
%         kn has no degree-2 entry
%     shLowLevel:rotationExcitation:badSize
%         C21, S21 and C20 do not hold one value per epoch each
%     shLowLevel:rotationExcitation:nanInput
%         an input holds NaN or Inf, which the mean cannot skip
%
%   References
%     Chen, J. L., and C. R. Wilson (2003), Low degree gravitational
%       changes from earth rotation and geophysical models, Geophys. Res.
%       Lett. 30(24), 2257, doi:10.1029/2003GL018688 - equation (1).
%     Petit, G., and B. Luzum (eds.) (2010), IERS Conventions (2010), IERS
%       Technical Note 36 - Table 1.1, Chapter 1 as updated 16 Nov 2017.
%     Dobslaw, H., and R. Dill (2019), Product Description Document:
%       Effective Angular Momentum Functions from Earth System Modelling
%       at GFZ, rev. 1.1 - eqs. (2.3), (2.8), (2.13) and Table 2.1.
%     Eubanks, T. M. (1993), Variations in the orientation of the earth,
%       in Contributions of Space Geodesy to Geodynamics: Earth Dynamics,
%       Geodyn. Ser. 24, pp. 1-54, AGU - the source of eq. (1).
%     Dickman, S. R. (2003), Evaluation of "effective angular momentum
%       function" formulations with respect to core-mantle coupling,
%       J. Geophys. Res. 108(B3), 2150, doi:10.1029/2001JB001603.
%
%   See also shSeries.excitation, shLowLevel.readTN14,
%   shLowLevel.poleTideConvert, shLowLevel.readLoveNumbers.
%
%   Developed by Matthias Weigelt with the help of Claude (Opus 5),
%   2026-09-10 (v5.10.0; IERS 2010 constants and dLOD v5.11.0).
arguments
    C21 (:,1) double
    S21 (:,1) double
    opts.Earth = "IERS2010"
    opts.kn double = []
    opts.C20 (:,1) double = []
    opts.Reference (1,1) string {mustBeMember(opts.Reference, ...
        ["mean", "none"])} = "mean"
    opts.PolarFactor (1,1) double {mustBePositive} = 1.098
    opts.AxialFactor (1,1) double {mustBePositive} = 0.753
    opts.Omega (1,1) double {mustBePositive} = 7.292115e-5
end
need = ["M", "R", "C", "A"];
if (ischar(opts.Earth) || isstring(opts.Earth)) && isscalar(string(opts.Earth))
    if string(opts.Earth) ~= "IERS2010"
        error('shLowLevel:rotationExcitation:badEarth', ...
            ['Earth = "%s" is not a convention this function knows; ' ...
             'give "IERS2010" or a struct with M, R, C and A.'], ...
            string(opts.Earth));
    end
    E = iers2010Earth();
elseif ~isstruct(opts.Earth) || ~isscalar(opts.Earth) || ...
        ~all(isfield(opts.Earth, need))
    error('shLowLevel:rotationExcitation:noEarth', ...
        ['Earth must be "IERS2010" or struct(''M'', .., ''R'', .., ' ...
         '''C'', .., ''A'', ..): the Earth''s mass [kg], radius [m] and ' ...
         'principal moments of inertia [kg m^2].']);
else
    E = opts.Earth;
end
for f = need
    v = E.(f);
    if ~(isnumeric(v) && isscalar(v) && isreal(v) && isfinite(v) && v > 0)
        error('shLowLevel:rotationExcitation:badEarth', ...
            'Earth.%s must be a positive finite scalar.', f);
    end
end
if ~(E.C > E.A)
    error('shLowLevel:rotationExcitation:badEarth', ...
        ['Earth.C must exceed Earth.A: C - A, the difference of the ' ...
         'principal moments, is what polar motion rests on.']);
end
E = struct('M', E.M, 'R', E.R, 'C', E.C, 'A', E.A);
if isempty(opts.kn)
    error('shLowLevel:rotationExcitation:missingLoveNumbers', ...
        ['kn is required: load Love numbers are always user-supplied ' ...
         '(shLowLevel.readLoveNumbers), and kn(3) is k2''.']);
end
if numel(opts.kn) < 3
    error('shLowLevel:rotationExcitation:knTooShort', ...
        'kn has %d entries; the degree-2 value is kn(3).', numel(opts.kn));
end
T = numel(C21);
if T == 0 || numel(S21) ~= T || (~isempty(opts.C20) && numel(opts.C20) ~= T)
    error('shLowLevel:rotationExcitation:badSize', ...
        ['C21, S21 and C20 need one value per epoch each ' ...
         '(C21 has %d, S21 %d, C20 %d).'], T, numel(S21), numel(opts.C20));
end
if ~all(isfinite([C21; S21; opts.C20]))
    error('shLowLevel:rotationExcitation:nanInput', ...
        ['The coefficients hold NaN or Inf. The mean over the series ' ...
         'cannot skip a gap - drop those epochs first (ts.dropNaN).']);
end

k2 = opts.kn(3);
mas = 180 / pi * 3600e3;                 % milliarcseconds per radian
r2m = E.R^2 * E.M;
% eq. (1) solved for chi
polarScale = -opts.PolarFactor * r2m / ((1 + k2) * sqrt(3/5) * (E.C - E.A)) * mas;
axialScale = -opts.AxialFactor * r2m * 2 * sqrt(5) / ((1 + k2) * 3 * E.C);
% the rotation period in ms: dLOD per unit chi3 (Dobslaw & Dill, eq. 2.8)
lodScale = 2 * pi / opts.Omega * 1e3;

removed = [0, 0, NaN];
if opts.Reference == "mean"
    removed(1:2) = [mean(C21), mean(S21)];
end
chi3 = [];
dLOD = [];
if ~isempty(opts.C20)
    removed(3) = 0;
    if opts.Reference == "mean"
        removed(3) = mean(opts.C20);
    end
    chi3 = axialScale * (opts.C20 - removed(3));
    dLOD = lodScale * chi3;
end
chi = struct('chi1', polarScale * (C21 - removed(1)), ...
    'chi2', polarScale * (S21 - removed(2)), 'chi3', chi3, 'dLOD', dLOD);
info = struct('k2', k2, 'polarScale', polarScale, ...
    'axialScale', axialScale, 'lodScale', lodScale, ...
    'removedMean', removed, 'earth', E);
end

function E = iers2010Earth()
%IERS2010EARTH M, R, C and A from the IERS Conventions (2010), Table 1.1
%   (Chapter 1 as updated 16 November 2017). The table gives G, GM, a_E,
%   J2 and the dynamical flattening H; M, C and A follow from the
%   definitions J2 = (C - A) / (M a_E^2) and H = (C - A) / C, with A the
%   mean of the two equatorial moments.
G = 6.67428e-11;          % constant of gravitation [m^3 kg^-1 s^-2]
GM = 3.986004418e14;      % geocentric gravitational constant [m^3 s^-2]
aE = 6378136.6;           % equatorial radius [m], zero tide
J2 = 1.0826359e-3;        % dynamical form factor, zero tide
H = 3273795e-9;           % dynamical flattening
M = GM / G;
CminusA = J2 * M * aE^2;
C = CminusA / H;
E = struct('M', M, 'R', aE, 'C', C, 'A', C - CminusA);
end
