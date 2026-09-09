function spec = shDegreeRMS(C, S, opts)
%SHDEGREERMS Spectral (degree-domain) analysis of spherical harmonic coefficients.
%
%   SPEC = SHDEGREERMS(C, S) computes, per degree n = 0..nmax:
%     .degVariance(n+1)  = sum_m (Cnm^2 + Snm^2)
%     .degRMS(n+1)       = sqrt(degVariance)
%     .degAmplitude(n+1) = R * degRMS            [geoid-height-equivalent, m]
%     .cumAmplitude(n+1) = R * sqrt(cumsum(degVariance))   [cumulative, m]
%
%   C, S are (nmax+1)x(nmax+1) coefficient matrices, C(n+1,m+1), fully
%   normalized (4-pi / ICGEM convention), lower-triangular (m<=n).
%
%   SPEC = SHDEGREERMS(C, S, SigmaC=sigC, SigmaS=sigS) additionally
%   computes the error degree amplitude .errAmplitude from formal errors,
%   using the same degree-RMS formula applied to sigC, sigS.
%
%   Options
%     R (6378136.3)  (1,1) double  reference radius [m]
%     Nmin (0)       (1,1) double  lowest degree to include; coefficients
%             below it are zeroed before summation (Nmin=2 drops degree
%             0 and 1). Renamed from n0 in v4.0.0.
%     SigmaC ([])    formal 1-sigma of C, same layout
%     SigmaS ([])    formal 1-sigma of S, same layout
%
%   Claude (Sonnet 4.6), 2026-07-11; merged into +shLowLevel: Claude (Fable 5), 2026-08-07.
%   Outputs
%     spec  (1,1) struct  fields
%           degree        (nmax+1 x 1) double  the degree axis
%           degVariance, degRMS, degAmplitude  (nmax+1 x 1) double
%                         per-degree signal measures
%           cumVariance, cumRMS, cumAmplitude  (nmax+1 x 1) double
%                         their cumulative counterparts
%           R             (1,1) double  the radius the amplitudes use
%           domain        (1,:) char    'degree' (consumed by
%                         plotSHSpectrum)
%           errVariance, errRMS, errAmplitude  (nmax+1 x 1) double
%                         the same for the formal errors; present only
%                         when sigmas were supplied
%
%   Developed by Matthias Weigelt with the help of Claude (Fable 5).

arguments
    C double
    S double
    opts.R (1,1) double = 6378136.3
    opts.Nmin (1,1) double = 0
    opts.SigmaC double = []
    opts.SigmaS double = []
end
R = opts.R;
n0 = opts.Nmin;

nmax = size(C,1) - 1;
if n0 > 0
    C(1:n0,:) = 0;
    S(1:n0,:) = 0;
end

degVariance = zeros(nmax+1,1);
for n = 0:nmax
    degVariance(n+1) = sum(C(n+1,1:n+1).^2 + S(n+1,1:n+1).^2);
end
degRMS = sqrt(degVariance);

spec.degree = (0:nmax)';
spec.degVariance = degVariance;
spec.degRMS = degRMS;
spec.degAmplitude = R .* degRMS;
spec.cumVariance = cumsum(degVariance);              % v2.4.1
spec.cumRMS = sqrt(spec.cumVariance);                % v2.4.1
spec.cumAmplitude = R .* spec.cumRMS;
spec.R = R;
spec.domain = 'degree';                              % v2.4.1

if ~isempty(opts.SigmaC) && ~isempty(opts.SigmaS)
    sC = opts.SigmaC; sS = opts.SigmaS;
    sC(isnan(sC)) = 0; sS(isnan(sS)) = 0;
    if n0 > 0
        sC(1:n0,:) = 0; sS(1:n0,:) = 0;
    end
    errVariance = zeros(nmax+1,1);
    for n = 0:nmax
        errVariance(n+1) = sum(sC(n+1,1:n+1).^2 + sS(n+1,1:n+1).^2);
    end
    spec.errVariance = errVariance;                  % v2.4.1
    spec.errRMS = sqrt(errVariance);
    spec.errAmplitude = R .* spec.errRMS;
end

end
