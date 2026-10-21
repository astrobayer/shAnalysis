function idx = shIndex(Lmax, opts)
%SHINDEX Canonical order-major index for SH coefficient vectors.
%   idx = shLowLevel.shIndex(Lmax) builds the index table used by all shLowLevel
%   functions: order-major ordering, C before S per (n,m), degrees
%   n = Nmin..Lmax (default Nmin = 2; degree 0/1 and the SLR-C20
%   replacement are assumed to be handled upstream).
%
%   Fields: n, m, cs (0=C, 1=S) [P x 1], P, Lmax, minDegree,
%           pos (Lmax+1 x Lmax+1 x 2) lookup: pos(n+1,m+1,cs+1) -> linear
%           index (0 if absent).
%   Inputs
%     Lmax            maximum spherical-harmonic degree of the index
%
%   Options
%     Nmin (2)  (1,1) double  first degree included (non-negative integer)
%
%   Outputs
%     idx  (1,1) struct  the canonical vector ordering of the toolbox, fields
%          n, m, cs   (P x 1) double  degree, order and 0=cosine/1=sine
%                     of every element, in vector order
%          P          (1,1) double    number of elements
%          Lmax       (1,1) double    maximum degree (the LMAX argument)
%          minDegree  (1,1) double    first degree included (the Nmin
%                     option; the FIELD keeps the older spelling)
%          pos        (Lmax+1 x Lmax+1 x 2) double  reverse map, the
%                     vector position of (n, m, cs) or 0 when absent
%
%   Developed by Matthias Weigelt with the help of Claude (Fable 5).

arguments
    Lmax (1,1) double {mustBeInteger, mustBePositive}
    opts.Nmin (1,1) double {mustBeInteger, mustBeNonnegative} = 2
end

nMax = (Lmax + 1)^2;                 % upper bound, trimmed below
n  = zeros(nMax, 1); m = zeros(nMax, 1); cs = zeros(nMax, 1);
k = 0;
for mm = 0:Lmax
    for nn = max(mm, opts.Nmin):Lmax
        k = k + 1; n(k) = nn; m(k) = mm; cs(k) = 0;
        if mm > 0
            k = k + 1; n(k) = nn; m(k) = mm; cs(k) = 1;
        end
    end
end
idx.n = n(1:k); idx.m = m(1:k); idx.cs = cs(1:k);
idx.P = k; idx.Lmax = Lmax; idx.minDegree = opts.Nmin;

pos = zeros(Lmax+1, Lmax+1, 2);
pos(sub2ind(size(pos), idx.n+1, idx.m+1, idx.cs+1)) = (1:k)';
idx.pos = pos;
end
