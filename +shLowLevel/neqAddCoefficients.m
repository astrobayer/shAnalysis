function [neq, idxOut, info] = neqAddCoefficients(neq, idx, obs)
%NEQADDCOEFFICIENTS Add single-coefficient observations to a normal equation.
%
%   [NEQ, IDXOUT] = shLowLevel.neqAddCoefficients(NEQ, IDX, OBS) adds
%   independent values of single coefficients - C20 and C30 from SLR
%   (shLowLevel.readTN14), degree 1 from shLowLevel.readTN13 - to a
%   normal equation N x = b as pseudo-observations, so they are estimated
%   JOINTLY with the rest instead of substituted into the solution. Each
%   value v of coefficient p with 1-sigma s adds
%       N(p,p) += 1/s^2,   b(p) += v/s^2,   ltpl += v^2/s^2,   nobs += 1,
%   which is the stacked least-squares problem with the row x_p = v
%   appended (tools/dev/validate_neq_low_degree.py CLAIMs 1-2, 2.2e-15).
%   ltpl and nobs are updated only where NEQ carries them, so the result
%   still enters shLowLevel.neqCombine's variance component estimation.
%
%   A coefficient IDX does not hold - degree 1 in a GRACE normal
%   equation, whose index starts at degree 2 - is added first: IDXOUT is
%   shLowLevel.shIndex(IDX.Lmax, Nmin = the lowest degree observed), and
%   N and b get zero rows and columns there. Every coefficient the
%   extension adds must then be observed, or N would be singular.
%
%   What joint estimation buys over substitution, and what it does not:
%     - C20/C30: the GRACE normal equation's correlations carry the SLR
%       information into the other coefficients, which substitution
%       leaves at GRACE's values. The gain is set by those correlations:
%       on the synthetic polar-gapped design of the oracle (CLAIM 4) the
%       other zonals' RMS error falls to 0.99 of substitution's at a
%       C20 correlation of 0.12, and to 0.75 at 0.77. On real normal
%       equations it is as large as their C20/C30 correlations, which
%       have not been measured.
%     - Degree 1 is SUBSTITUTION: a GRACE normal equation carries no
%       degree-1 information, so the padded degree-1 block is uncoupled.
%       Its estimate equals the observed value and every other
%       coefficient is unchanged (CLAIM 3, exact). TN-13 is itself
%       computed from GRACE (Swenson et al. 2008), which would count
%       GRACE's information twice in a joint estimate; here it cannot,
%       because nothing couples - and for the same reason it adds nothing
%       beyond substitution. Joint estimation of degree 1 needs a normal
%       equation that observes it (SLR, GNSS).
%
%   CONSISTENCY IS THE CALLER'S: the values must be the same quantity as
%   the normal equation's unknowns - fully normalized coefficients, the
%   same GM, R and tide system, and full values where N x = b solves for
%   full coefficients (as shLowLevel.readSINEX's b = M x does) or
%   corrections where it solves for corrections. Nothing here can check
%   that. Drop TN-14 months whose C30 is NaN before building OBS.
%
%   Inputs
%     neq  (1,1) struct  the normal equation, either with fields N (P x P)
%          and b (P x 1), and optionally ltpl and nobs (1,1); or a
%          shLowLevel.readSINEX result with kind 'NEQ' (N = M, b = M x,
%          ltpl and nobs from its stats where present)
%     idx  (1,1) struct  shLowLevel.shIndex of NEQ
%     obs  (1,1) struct  the observed coefficients, fields n, m, cs
%          (K x 1, cs 0 for C and 1 for S), value and sigma (K x 1); the
%          same coefficient may appear more than once
%
%   Outputs
%     neq     (1,1) struct  fields N (Q x Q), b (Q x 1), and ltpl and
%             nobs (1,1) where the input carried them
%     idxOut  (1,1) struct  shLowLevel.shIndex of the result: IDX, or IDX
%             extended down to the lowest degree observed
%     info    (1,1) struct  fields
%             positions  (K x 1) double  each observation's position in
%                        IDXOUT
%             added      (:,1) double  positions in IDXOUT of the
%                        coefficients the extension added (empty if none)
%             extended   (1,1) logical  whether the index was extended
%
%   Example
%     tn = shLowLevel.readTN14(tn14File);
%     k = find(abs(tn.epoch - snx.epoch) < 1/24, 1);   % the same month
%     obs = struct('n', [2; 3], 'm', [0; 0], 'cs', [0; 0], ...
%         'value', [tn.C20(k); tn.C30(k)], ...
%         'sigma', [tn.sigmaC20(k); tn.sigmaC30(k)]);
%     [neq, idx2] = shLowLevel.neqAddCoefficients(snx, idx, obs);
%     x = neq.N \ neq.b;                % in shIndex order idx2
%
%   Error identifiers
%     shLowLevel:neqAddCoefficients:badNeq
%         NEQ lacks N and b (or M and x), or they do not match IDX, or
%         they are not finite
%     shLowLevel:neqAddCoefficients:badObs
%         OBS lacks a field, its fields differ in length, a value is not
%         finite, or an (n, m, cs) is not a coefficient
%     shLowLevel:neqAddCoefficients:badSigma
%         a sigma is not finite and positive
%     shLowLevel:neqAddCoefficients:outOfRange
%         an observed degree is above IDX.Lmax or below 1
%     shLowLevel:neqAddCoefficients:unobserved
%         the extension added a coefficient that OBS does not observe
%
%   See also shLowLevel.readTN14, shLowLevel.readTN13,
%   shLowLevel.neqCombine, shLowLevel.readSINEX, shLowLevel.kalmanChain.
%
%   Developed by Matthias Weigelt with the help of Claude (Opus 5.5),
%   2026-10-29 (WP9 9f).
arguments
    neq (1,1) struct
    idx (1,1) struct
    obs (1,1) struct
end

% ---- the normal equation
hasLtpl = false;
hasNobs = false;
if isfield(neq, 'kind') && strcmp(neq.kind, 'NEQ') && isfield(neq, 'M')
    N = neq.M;
    b = neq.M * neq.x(:);
    st = struct([]);
    if isfield(neq, 'stats'), st = neq.stats; end
    if ~isempty(st) && isfield(st, 'wsos') && isfield(st, 'nobs')
        ltpl = st.wsos;
        nobs = st.nobs;
        hasLtpl = true;
        hasNobs = true;
    end
elseif isfield(neq, 'N') && isfield(neq, 'b')
    N = neq.N;
    b = neq.b(:);
    if isfield(neq, 'ltpl'), ltpl = neq.ltpl; hasLtpl = true; end
    if isfield(neq, 'nobs'), nobs = neq.nobs; hasNobs = true; end
else
    error('shLowLevel:neqAddCoefficients:badNeq', ...
        'NEQ needs fields N and b, or a readSINEX result of kind ''NEQ''.');
end
P = idx.P;
if ~isequal(size(N), [P P]) || numel(b) ~= P || ~all(isfinite(N(:))) ...
        || ~all(isfinite(b))
    error('shLowLevel:neqAddCoefficients:badNeq', ...
        'N must be %d x %d and b %d x 1, finite, in the order of IDX.', P, P, P);
end

% ---- the observations
need = {'n', 'm', 'cs', 'value', 'sigma'};
if ~all(isfield(obs, need))
    error('shLowLevel:neqAddCoefficients:badObs', ...
        'OBS needs the fields n, m, cs, value and sigma.');
end
on = obs.n(:); om = obs.m(:); oc = obs.cs(:);
ov = obs.value(:); os = obs.sigma(:);
K = numel(on);
if K == 0 || numel(om) ~= K || numel(oc) ~= K || numel(ov) ~= K ...
        || numel(os) ~= K
    error('shLowLevel:neqAddCoefficients:badObs', ...
        'The fields of OBS must be non-empty and of one length.');
end
if ~all(isfinite(ov)) || any(on ~= round(on)) || any(om ~= round(om)) ...
        || any(om < 0) || any(om > on) || any(oc ~= 0 & oc ~= 1) ...
        || any(oc == 1 & om == 0)
    error('shLowLevel:neqAddCoefficients:badObs', ...
        ['Every value must be finite and every (n, m, cs) a coefficient: ' ...
         'integer 0 <= m <= n, cs 0 or 1, no S at order 0.']);
end
if ~all(isfinite(os) & os > 0)
    error('shLowLevel:neqAddCoefficients:badSigma', ...
        'Every sigma must be finite and positive.');
end
if any(on > idx.Lmax) || any(on < 1)
    error('shLowLevel:neqAddCoefficients:outOfRange', ...
        'Observed degrees must lie in 1..%d (IDX.Lmax).', idx.Lmax);
end

% ---- extend the index down to the lowest degree observed
idxOut = idx;
added = zeros(0, 1);
nlow = min(on);
if nlow < idx.minDegree
    idxOut = shLowLevel.shIndex(idx.Lmax, Nmin = nlow);
    map = idxOut.pos(sub2ind(size(idxOut.pos), idx.n + 1, idx.m + 1, idx.cs + 1));
    N2 = zeros(idxOut.P);
    b2 = zeros(idxOut.P, 1);
    N2(map, map) = N;
    b2(map) = b;
    N = N2;
    b = b2;
    added = setdiff((1:idxOut.P)', map(:));
end
pos = idxOut.pos(sub2ind(size(idxOut.pos), on + 1, om + 1, oc + 1));
if ~all(ismember(added, pos))
    error('shLowLevel:neqAddCoefficients:unobserved', ...
        ['Extending the index to degree %d added %d coefficient(s) OBS ' ...
         'does not observe; observe every one of them.'], nlow, ...
        numel(setdiff(added, pos)));
end

% ---- the pseudo-observations
w = 1 ./ os .^ 2;
for k = 1:K
    N(pos(k), pos(k)) = N(pos(k), pos(k)) + w(k);
    b(pos(k)) = b(pos(k)) + w(k) * ov(k);
end
neq = struct('N', N, 'b', b);
if hasLtpl, neq.ltpl = ltpl + sum(w .* ov .^ 2); end
if hasNobs, neq.nobs = nobs + K; end
info = struct('positions', pos(:), 'added', added, ...
    'extended', ~isempty(added));
end
