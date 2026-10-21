function spec = shOrderRMS(C, S, opts)
%SHORDERRMS Order-domain spectral diagnostics (striping direction).
%
%   SPEC = shLowLevel.shOrderRMS(C, S) sums coefficient power per ORDER m -
%   the complementary view to shLowLevel.shDegreeRMS and the natural axis for
%   GRACE striping (correlated errors live at high orders):
%
%       ordVariance(m) = sum_n ( C_nm^2 + S_nm^2 )
%       ordRMS         = sqrt(ordVariance)
%       ordAmplitude   = R * ordRMS
%       cumVariance/cumRMS/cumAmplitude = running sums over m
%
%   Conventions mirror shDegreeRMS exactly (RMS = sqrt of the summed
%   power, amplitude = R * RMS; degree/order power partitions are two
%   marginals of the same total: sum(ordVariance) == sum(degVariance),
%   tested). Formal errors via SigmaC/SigmaS give errVariance/errRMS/
%   errAmplitude per order.
%
%   Inputs
%     C, S        (n1,n1) double
%   Options
%     R (6378136.3) [m], Nmin (0)  zero degrees below it first,
%     SigmaC, SigmaS ([])        formal errors
%   Outputs
%     spec  (1,1) struct  fields
%           order         (nmax+1 x 1) double  the order axis
%           ordVariance, ordRMS, ordAmplitude  (nmax+1 x 1) double
%                         per-order signal measures
%           cumVariance, cumRMS, cumAmplitude  (nmax+1 x 1) double
%                         their cumulative counterparts
%           R             (1,1) double  the radius the amplitudes use
%           domain        (1,:) char    'order' (consumed by
%                         plotSHSpectrum)
%           errVariance, errRMS, errAmplitude  (nmax+1 x 1) double
%                         the same for the formal errors; present only
%                         when sigmas were supplied
%
%   Claude (Fable 5), 2026-08-07 (v2.4.1).
%   Developed by Matthias Weigelt with the help of Claude (Fable 5).
arguments
    C double
    S double
    opts.R (1,1) double = 6378136.3
    opts.Nmin (1,1) double {mustBeInteger, mustBeNonnegative} = 0
    opts.SigmaC double = []
    opts.SigmaS double = []
end
nmax = size(C, 1) - 1;
if opts.Nmin > 0
    C(1:opts.Nmin, :) = 0; S(1:opts.Nmin, :) = 0;
end
ordVariance = (sum(C.^2, 1) + sum(S.^2, 1))';
spec.order = (0:nmax)';
spec.ordVariance = ordVariance;
spec.ordRMS = sqrt(ordVariance);
spec.ordAmplitude = opts.R .* spec.ordRMS;
spec.cumVariance = cumsum(ordVariance);
spec.cumRMS = sqrt(spec.cumVariance);
spec.cumAmplitude = opts.R .* spec.cumRMS;
spec.R = opts.R;
spec.domain = 'order';
if ~isempty(opts.SigmaC) && ~isempty(opts.SigmaS)
    sC = opts.SigmaC; sS = opts.SigmaS;
    sC(isnan(sC)) = 0; sS(isnan(sS)) = 0;
    if opts.Nmin > 0
        sC(1:opts.Nmin, :) = 0; sS(1:opts.Nmin, :) = 0;
    end
    ev = (sum(sC.^2, 1) + sum(sS.^2, 1))';
    spec.errVariance = ev;
    spec.errRMS = sqrt(ev);
    spec.errAmplitude = opts.R .* spec.errRMS;
end
end
