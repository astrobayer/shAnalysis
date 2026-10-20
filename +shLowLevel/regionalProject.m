function [a, rec] = regionalProject(Cs, Ss, B)
%REGIONALPROJECT Coefficient sets in a regional basis, and back.
%
%   [A, REC] = shLowLevel.regionalProject(CS, SS, B) gives one or many
%   coefficient sets their coefficients in the regional basis B of
%   shLowLevel.regionalBasis, A = B.Proj * X, where X stacks the (C, S)
%   coefficients in B.idx ordering: the region-weighted least-squares
%   fit B.regionalBasis documents. REC returns the fit rebuilt in SH,
%   B.T * A, repacked to (C, S) arrays for direct synthesis - inside the
%   region it reproduces the field up to what the basis cannot represent,
%   outside it is whatever the basis functions carry there.
%
%   For a Slepian basis this is shLowLevel.slepianProject with G = B.T
%   (A = G' X); for an "sh" basis A is X itself. This is how a geophysical
%   model series becomes the realisation the regional process model is
%   estimated from (CLAUDE.md WP8, row 8b).
%
%   Inputs
%     Cs  (n+1,n+1,T) double  cosine coefficients, n >= B.idx.Lmax (T = 1
%         for a single set)
%     Ss  (n+1,n+1,T) double  sine coefficients, the same size
%     B   (1,1) struct  a basis from shLowLevel.regionalBasis
%
%   Outputs
%     a    (K,T) double  basis coefficients, one column per set
%     rec  (1,1) struct  the fit rebuilt in SH, fields
%          Cs  (n+1,n+1,T) double  cosine coefficients of B.T * a
%          Ss  (n+1,n+1,T) double  sine coefficients of B.T * a
%
%   Example
%     B = shLowLevel.regionalBasis(shLowLevel.shIndex(60), "Elbe");
%     [a, rec] = shLowLevel.regionalProject(ts.Cs, ts.Ss, B);
%
%   Error identifiers
%     shLowLevel:regionalProject:sizeMismatch
%         the coefficient arrays reach a lower degree than B.idx.Lmax, or
%         Cs and Ss differ in size
%     shLowLevel:regionalProject:badBasis
%         B is not a basis from shLowLevel.regionalBasis
%
%   Developed by Matthias Weigelt with the help of Claude (Opus 5.5),
%   2026-10-20.
arguments
    Cs double
    Ss double
    B (1,1) struct
end
if ~all(isfield(B, {'T', 'Proj', 'idx'}))
    error('shLowLevel:regionalProject:badBasis', ...
        'B must be a basis from shLowLevel.regionalBasis (fields T, Proj, idx).');
end
idx = B.idx;
if ~isequal(size(Cs), size(Ss)) || size(Cs, 1) < idx.Lmax + 1
    error('shLowLevel:regionalProject:sizeMismatch', ...
        ['Cs and Ss must have the same size and reach degree %d; they are ' ...
         '%s and %s.'], idx.Lmax, mat2str(size(Cs)), mat2str(size(Ss)));
end
nT = size(Cs, 3);
li = sub2ind([size(Cs, 1), size(Cs, 2)], idx.n(:) + 1, idx.m(:) + 1);
isC = idx.cs(:) == 0;
X = zeros(idx.P, nT);
for t = 1:nT
    Ck = Cs(:, :, t); Sk = Ss(:, :, t);
    X(isC, t) = Ck(li(isC));
    X(~isC, t) = Sk(li(~isC));
end
a = full(B.Proj * X);
if nargout > 1
    XR = full(B.T * a);
    n1 = size(Cs, 1);
    rec = struct('Cs', zeros(n1, size(Cs, 2), nT), 'Ss', zeros(n1, size(Cs, 2), nT));
    for t = 1:nT
        Ck = zeros(n1, size(Cs, 2)); Sk = Ck;
        Ck(li(isC)) = XR(isC, t);
        Sk(li(~isC)) = XR(~isC, t);
        rec.Cs(:, :, t) = Ck;
        rec.Ss(:, :, t) = Sk;
    end
end
end
