function [k, info] = basinScaling(op, b, tsModel, opts)
%BASINSCALING Leakage/attenuation scaling factors by forward modelling.
%
%   [K, INFO] = shLowLevel.basinScaling(OP, B, TSMODEL) estimates the classic
%   basin scaling (gain) factor: push a MODEL series (hydrology model,
%   mascon-derived field, synthetic pattern) through the SAME filter
%   operator OP that processed the data, and regress true against
%   filtered basin averages:
%       k = sum(aTrue .* aFilt) / sum(aFilt.^2)
%   Scaled data series: k * (b' xFiltered)/(b'b). Complements
%   shLowLevel.basinDeconvolve: deconvolution inverts the operator on a kernel
%   set; scaling corrects a single series using external signal
%   structure - the standard literature approach, with its standard
%   caveat (K depends on the model's spatial pattern; INFO reports the
%   regression sigma and per-month factors so the assumption is
%   checkable).
%
%   Inputs
%     op       operator, one of
%                struct  from shLowLevel.tvANSFilter (applied via shLowLevel.opApply)
%                (P,P) double  static matrix operator (Gaussian, DDK,
%                        fan as a matrix in idx (struct()) ordering)
%                handle  @(x, t) -> filtered x
%     b        (P,1)      basin kernel (shLowLevel.basinKernel, idx order)
%     tsModel  shSeries   model series matched by nearest epoch within
%                         0.05 yr against opts.tYears ([]) / op.tYears
%   Options
%     Idx (struct())      required for matrix/handle operators
%                         (shLowLevel.shIndex); structs carry their own
%     TYears ([])         required for matrix/handle operators
%     PerMonth (false)    also return monthly factors aTrue./aFilt
%   Outputs
%     k     (1,1) double  regression scaling factor
%     info  (1,1) struct  fields
%           sigmaK    (1,1) double   1-sigma of the regression factor
%           kMonthly  (T x 1) double  per-month factors; present only
%                     with PerMonth
%           matched   (T x 1) logical  which epochs matched between the
%                     two series
%           nMatched  (1,1) double   nnz(matched), the epochs the
%                     regression actually used
%           aTrue     (T x 1) double  basin average of the model field
%           aFilt     (T x 1) double  basin average after filtering
%
%   Error identifiers
%     shLowLevel:basinScaling:badKernel
%         the basin kernel is not P x 1 in idx ordering
%     shLowLevel:basinScaling:badOp
%         OP is neither a tvANS struct, a P x P matrix nor a function
%         handle, or the matrix is not P x P
%     shLowLevel:basinScaling:needIdx
%         a matrix or handle operator was given without Idx= and TYears=;
%         only a tvANS struct carries them itself
%     shLowLevel:basinScaling:tooFewMatches
%         fewer than 3 model epochs matched TYears within 0.05 yr - the
%         scaling regression has too little to fit
%
%   Claude (Fable 5), 2026-08-07 (v2.4).
%   Developed by Matthias Weigelt with the help of Claude (Fable 5).
arguments
    op
    b (:,1) double
    tsModel (1,1) shSeries
    opts.Idx struct = struct()
    opts.TYears (1,:) double = []
    opts.PerMonth (1,1) logical = false
end
if isstruct(op) && isfield(op, 'idx')
    idx = op.idx; tY = op.tYears;
    applyOp = @(x, t) shLowLevel.opApply(op, x, t);
elseif isnumeric(op)
    assert(isfield(opts.Idx, 'P') && ~isempty(opts.TYears), ...
        'shLowLevel:basinScaling:needIdx', ...
        'Matrix operators need idx= and tYears=.');
    idx = opts.Idx; tY = opts.TYears;
    assert(isequal(size(op), [idx.P idx.P]), 'shLowLevel:basinScaling:badOp', ...
        'Matrix operator must be P x P.');
    applyOp = @(x, t) op * x;
elseif isa(op, 'function_handle')
    assert(isfield(opts.Idx, 'P') && ~isempty(opts.TYears), ...
        'shLowLevel:basinScaling:needIdx', ...
        'Handle operators need idx= and tYears=.');
    idx = opts.Idx; tY = opts.TYears;
    applyOp = op;
else
    error('shLowLevel:basinScaling:badOp', ...
        'Operator must be a tvANS struct, a P x P matrix, or a handle.');
end
assert(numel(b) == idx.P, 'shLowLevel:basinScaling:badKernel', ...
    'Kernel must be P x 1 in idx ordering (P = %d).', idx.P);
T = numel(tY);
n1 = min(tsModel.nmax + 1, idx.Lmax + 1);
aTrue = nan(T, 1); aFilt = nan(T, 1);
matched = false(T, 1);
bb = b' * b;
for t = 1:T
    [dt, j] = min(abs(tsModel.epochs - tY(t)));
    if dt > 0.05, continue; end
    matched(t) = true;
    Cm = zeros(idx.Lmax + 1); Sm = Cm;
    Cm(1:n1, 1:n1) = tsModel.Cs(1:n1, 1:n1, j);
    Sm(1:n1, 1:n1) = tsModel.Ss(1:n1, 1:n1, j);
    x = shLowLevel.vecFromCS(Cm, Sm, idx);
    xf = applyOp(x, t);
    aTrue(t) = (b' * x) / bb;
    aFilt(t) = (b' * xf) / bb;
end
assert(nnz(matched) >= 3, 'shLowLevel:basinScaling:tooFewMatches', ...
    'Only %d model epochs matched tYears within 0.05 yr.', nnz(matched));
u = aFilt(matched); v = aTrue(matched);
k = (u' * v) / (u' * u);
res = v - k * u;
sigmaK = sqrt((res' * res) / max(numel(u) - 1, 1) / (u' * u));
info = struct('sigmaK', sigmaK, 'matched', matched, ...
    'aTrue', aTrue, 'aFilt', aFilt, 'nMatched', nnz(matched));
if opts.PerMonth
    info.kMonthly = aTrue ./ aFilt;
end
end
