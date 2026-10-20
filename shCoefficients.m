classdef shCoefficients
%SHCOEFFICIENTS Spherical harmonic (Stokes) coefficient set - single epoch.
%
%   The single point of access for one gravity field: a GRACE/GRACE-FO
%   monthly solution (GSM), a dealiasing product (GAA/GAB/GAC/GAD), a
%   static model, or any derived field (difference, filtered, climatology
%   component). Immutable value class: every operation returns a NEW
%   object and appends to .history (full provenance).
%
%   Construction
%     g  = shCoefficients.read('GSM-2_2024032-2024060_....gfc');  % gfc/gfct/.gz
%     g  = shCoefficients(C, S, GM=3.986e14, R=6.378e6, Epoch=2024.12);
%     g  = shCoefficients.fromVec(x, idx, like);
%
%   Typical chain
%     d  = gB - gA;                              % monthly change
%     d2 = d.destripe(MinOrder=6).gaussian(300); % fluent filtering
%     [grid, lat, lon] = d2.synthesis(-90:90, 0:359, Quantity="ewh", kn=kn);
%     spec = d.degreeRMS;  N0 = d.crossover;  d.spectrum;  d.triangle;
%
%   GAX handling: productType is parsed from the L2 filename (GSM/GAA/
%   GAB/GAC/GAD); g + gad restores the background product, with epoch
%   matching enforced.
%
%   Properties (read-only)
%     C, S           (nmax+1)x(nmax+1) double  fully normalized coefficients
%     sigmaC, sigmaS same layout or []          formal errors
%     GM             (1,1) double  [m^3/s^2]
%     R              (1,1) double  [m]
%     Nmax           (1,1) double  (dependent, from size(C))
%     epoch          (1,1) double  decimal years, NaN if unknown/mixed
%     productType    (1,1) string  "GSM"|"GAA".."GAD"|"static"|"difference"|...
%     tideSystem     (1,1) string  from the file header, "unknown" otherwise
%     name           (1,1) string
%     header         struct        raw header key:value pairs
%     variableTerms  struct array  gfct time-variable terms (see evalAt)
%     history        string column provenance log
%
%   See also shSeries, shClimatology.
%
%   Claude (Fable 5), 2026-08-07.
%   Developed by Matthias Weigelt with the help of Claude (Fable 5).

properties (SetAccess = private)
    C double
    S double
    sigmaC double = []
    sigmaS double = []
    GM (1,1) double = 3.986004415e14
    R (1,1) double = 6378136.3
    epoch (1,1) double = NaN
    productType (1,1) string = "unknown"
    tideSystem (1,1) string = "unknown"
    name (1,1) string = ""
    header struct = struct()
    variableTerms = []
    history string = string.empty(0,1)
end

properties (Dependent)
    nmax
end

methods
    function obj = set.history(obj, h)
        % normalize to a string column: scalar-seeded (end+1) growth
        % otherwise produces rows and breaks vertcat chains (v2.2 fix)
        h = string(h);                       % chars -> scalar string first
        obj.history = h(:);
    end

    function obj = shCoefficients(C, S, opts)
        %SHCOEFFICIENTS Construct from coefficient matrices.
        %
        %   Inputs
        %     S  (nmax+1 x nmax+1) double  sine coefficients, same layout (S(:,1) = 0)
        %     C  (nmax+1 x nmax+1) double  cosine coefficients, C(n+1, m+1) layout
        %   Outputs
        %     obj        (1 x 1) shCoefficients   immutable coefficient set with GM (3.986004415e14), R (6378136.3), epoch, sigmas, history
        %
        %   Options
        %     SigmaC ([])  formal 1-sigma of the cosine coefficients, same
        %         layout as C ([]: none attached)
        %     SigmaS ([])  formal 1-sigma of the sine coefficients
        %     Epoch (NaN)  decimal year of the solution; required by every
        %         epoch-matched operation (applyTN14, addDegree1, restore)
        %     ProductType ("unknown")  provider product code, e.g. "GSM",
        %         "GAD", "GAA" - arithmetic uses it to catch mixing levels
        %     TideSystem ("unknown")  "tide_free" | "zero_tide" |
        %         "mean_tide" | "unknown"; carried through and written back
        %         out, never converted silently
        %     Name ("")  model label used in displays and plot titles
        %     Header (struct())  parsed gfc header fields, kept verbatim so
        %         writeGFC can round-trip them
        %     VariableTerms ([])  ICGEM 2.0 gfct terms (trend/periodic per
        %         coefficient) evaluated by evalAt
        %     History (string.empty(0,1))  initial processing history; every
        %         operation appends one line
        %
        %   Error identifiers
        %     shCoefficients:shCoefficients:badInput
        %         C and S are not square matrices of equal size, or SigmaC=/SigmaS=
        %         do not match the size of C/S
        %
        arguments
            C double = 0
            S double = 0
            opts.SigmaC double = []
            opts.SigmaS double = []
            opts.GM (1,1) double {mustBePositive} = 3.986004415e14
            opts.R (1,1) double {mustBePositive} = 6378136.3
            opts.Epoch (1,1) double = NaN
            opts.ProductType (1,1) string = "unknown"
            opts.TideSystem (1,1) string = "unknown"
            opts.Name (1,1) string = ""
            opts.Header struct = struct()
            opts.VariableTerms = []
            opts.History string = string.empty(0,1)
        end
        if ~isequal(size(C), size(S)) || size(C,1) ~= size(C,2)
            error('shCoefficients:shCoefficients:badInput', ...
                'C and S must be square matrices of equal size.');
        end
        if ~isempty(opts.SigmaC) && ~isequal(size(opts.SigmaC), size(C))
            error('shCoefficients:shCoefficients:badInput', 'sigmaC must match size(C).');
        end
        if ~isempty(opts.SigmaS) && ~isequal(size(opts.SigmaS), size(S))
            error('shCoefficients:shCoefficients:badInput', 'sigmaS must match size(S).');
        end
        obj.C = C; obj.S = S;
        obj.sigmaC = opts.SigmaC; obj.sigmaS = opts.SigmaS;
        obj.GM = opts.GM; obj.R = opts.R;
        obj.epoch = opts.Epoch;
        obj.productType = opts.ProductType;
        obj.tideSystem = opts.TideSystem;
        obj.name = opts.Name;
        obj.header = opts.Header;
        obj.variableTerms = opts.VariableTerms;
        obj.history = opts.History;
        if isempty(obj.history)
            obj.history = sprintf("created (Nmax=%d)", obj.nmax);
        end
    end

    function n = get.nmax(obj)
        n = size(obj.C, 1) - 1;
    end

    % ---------------------------------------------------------- arithmetic
    function out = plus(a, b)
        %PLUS Coefficient addition (e.g. GSM + GAD background restore).
        %
        %   Inputs
        %     b  (1,1) shCoefficients  right operand (same nmax and GM/R)
        %     a  (1,1) shCoefficients  left operand
        %   Outputs
        %     out        (1 x 1) shCoefficients   sum; sigmas RSS; epochs must match
        %
        %   Error identifiers
        %     shCoefficients:operands:badInput
        %         the other operand is not an shCoefficients. The `operands`
%         segment marks a check shared by the binary operators, so it
%         stays stable if the private helper behind it is renamed
        %     shCoefficients:operands:constantsMismatch
        %         the operands differ in GM or R - convert first with
        %         toReference(GM=..., R=...)
        %     shCoefficients:operands:epochMismatch
        %         the operand epochs differ by more than 0.02 yr.
        %         minus does NOT raise this: a difference has no single epoch, so it
        %         sets epoch = NaN instead of checking
        %     shCoefficients:operands:sizeMismatch
        %         the operands differ in nmax - truncate first
        %
        [a, b] = shCoefficients.checkPair(a, b, 'plus');
        shCoefficients.checkEpochs(a, b, 0.02, 'plus');
        out = a.combine(b, +1, ...
            shCoefficients.combinedType(a.productType, b.productType, '+'));
    end

    function out = minus(a, b)
        %MINUS Coefficient difference (e.g. monthly change gB - gA).
        %
        %   Inputs
        %     b  (1,1) shCoefficients  right operand (same nmax and GM/R)
        %     a  (1,1) shCoefficients  left operand
        %   Outputs
        %     out        (1 x 1) shCoefficients   difference; sigmas RSS
        %
        %   Error identifiers
        %     shCoefficients:operands:badInput
        %         the other operand is not an shCoefficients. The `operands`
%         segment marks a check shared by the binary operators, so it
%         stays stable if the private helper behind it is renamed
        %     shCoefficients:operands:constantsMismatch
        %         the operands differ in GM or R - convert first with
        %         toReference(GM=..., R=...)
        %     shCoefficients:operands:sizeMismatch
        %         the operands differ in nmax - truncate first
        %
        [a, b] = shCoefficients.checkPair(a, b, 'minus');
        out = a.combine(b, -1, "difference");
        out.epoch = NaN;
        out.history(end) = sprintf("difference: (%s|%.4f) - (%s|%.4f)", ...
            a.name, a.epoch, b.name, b.epoch);
    end

    function out = uminus(a)
        %UMINUS Unary minus: negate all coefficients.
        %
        %   Inputs
        %     a  (1,1) shCoefficients  left operand
        %   Outputs
        %     out        (1 x 1) shCoefficients   negated coefficients (sigmas kept)
        %
        out = a; out.C = -a.C; out.S = -a.S;
        out.history(end+1) = "negated";
    end

    function out = mtimes(a, b)
        %MTIMES Scalar scaling.
        %
        %   Inputs
        %     b  (1,1) double or shCoefficients  scalar factor (either side) - fields cannot be multiplied
        %   Outputs
        %     out        (1 x 1) shCoefficients   scalar-scaled; sigmas scale by |a|
        %
        %   Error identifiers
        %     shCoefficients:mtimes:badInput
        %         mtimes takes a scalar on one side and an shCoefficients on the
        %         other; two coefficient fields cannot be multiplied
        %
        if isa(a, 'shCoefficients') && isnumeric(b) && isscalar(b)
            out = a; f = b;
        elseif isa(b, 'shCoefficients') && isnumeric(a) && isscalar(a)
            out = b; f = a;
        else
            error('shCoefficients:mtimes:badInput', ...
                'mtimes supports scalar * shCoefficients only.');
        end
        out.C = out.C * f; out.S = out.S * f;
        if ~isempty(out.sigmaC), out.sigmaC = out.sigmaC * abs(f); end
        if ~isempty(out.sigmaS), out.sigmaS = out.sigmaS * abs(f); end
        out.history(end+1) = sprintf("scaled by %.6g", f);
    end

    function [rep, h] = compare(obj, other, varargin)
        %COMPARE Full comparison against another solution (v2.6.0).
        %   REP = g.compare(G2, ...) delegates to shLowLevel.compareSolutions
        %   with OBJ as the first solution; all options pass through
        %   (Plot=true for the 4-panel figure).
        %
        %   Inputs
        %     other  (1,1) shCoefficients  solution to compare against OBJ
        %   Outputs
        %     rep        (1,1) struct   as returned by
        %                shLowLevel.compareSolutions, which documents
        %                every field
        %     h          (1 x 1) graphics handle   figure (Plot = true)
        %
        [rep, h] = shLowLevel.compareSolutions(obj, other, varargin{:});
    end

    function out = times(a, b)
        %TIMES Elementwise scaling .* (scalar or triangle matrix).
        %   W .* G scales every coefficient by the matching entry of the
        %   (nmax+1 x nmax+1) matrix W (per-coefficient weighting or
        %   tapering); a scalar factor delegates to mtimes. Sigmas scale
        %   by |factor| elementwise (v2.5.1).
        %
        %   Inputs
        %     b  (1,1) shCoefficients or double array  elementwise factor
        %   Outputs
        %     out        (1 x 1) shCoefficients   elementwise-scaled coefficients
        %
        %   Error identifiers
        %     shCoefficients:times:badInput
        %         times takes a numeric factor and an shCoefficients, and the factor
        %         must be scalar or the size of C
        %
        if isa(a, 'shCoefficients') && isnumeric(b)
            out = a; f = b;
        elseif isa(b, 'shCoefficients') && isnumeric(a)
            out = b; f = a;
        else
            error('shCoefficients:times:badInput', ...
                'times supports numeric .* shCoefficients only.');
        end
        if isscalar(f)
            out = mtimes(out, f);
            return
        end
        if ~isequal(size(f), size(out.C))
            error('shCoefficients:times:badInput', ...
                'times factor must be scalar or %d x %d.', ...
                size(out.C, 1), size(out.C, 2));
        end
        out.C = f .* out.C; out.S = f .* out.S;
        if ~isempty(out.sigmaC), out.sigmaC = abs(f) .* out.sigmaC; end
        if ~isempty(out.sigmaS), out.sigmaS = abs(f) .* out.sigmaS; end
        out.history(end+1) = "elementwise scaled";
    end

    % ------------------------------------------------------------ editing
    function out = truncate(obj, nmaxNew)
        %TRUNCATE Reduce the maximum degree.
        %
        %   Inputs
        %     nmaxNew  (1,1) double  new maximum degree (must not exceed the current nmax)
        %   Outputs
        %     out        (1 x 1) shCoefficients   truncated to the new nmax
        %
        %   Error identifiers
        %     shCoefficients:truncate:badTruncation
        %         the requested nmax exceeds the field's own - truncate cannot invent
        %         degrees
        %
        arguments
            obj
            nmaxNew (1,1) double {mustBeInteger, mustBeNonnegative}
        end
        if nmaxNew > obj.nmax
            error('shCoefficients:truncate:badTruncation', ...
                'Requested nmax %d exceeds available %d.', nmaxNew, obj.nmax);
        end
        out = obj;
        k = nmaxNew + 1;
        out.C = obj.C(1:k, 1:k); out.S = obj.S(1:k, 1:k);
        if ~isempty(obj.sigmaC), out.sigmaC = obj.sigmaC(1:k, 1:k); end
        if ~isempty(obj.sigmaS), out.sigmaS = obj.sigmaS(1:k, 1:k); end
        out.history(end+1) = sprintf("truncated to nmax=%d", nmaxNew);
    end

    function out = setCoefficient(obj, n, m, Cval, Sval, opts)
        %SETCOEFFICIENT Replace a single (n,m) coefficient pair.
        %
        %   Inputs
        %     Sval  (1,1) double  new S(n+1, m+1) value (NaN keeps the current one)
        %     Cval  (1,1) double  new C(n+1, m+1) value
        %   Outputs
        %     out        (1 x 1) shCoefficients   copy with C/S(n+1, m+1) replaced
        %
        %   Options
        %     SigmaC (NaN)  formal 1-sigma for the coefficient being set
        %         (NaN leaves the existing sigma untouched)
        %     SigmaS (NaN)  same for the sine coefficient
        %
        %   Error identifiers
        %     shCoefficients:setCoefficient:badIndex
        %         (n,m) lies outside the triangle: n > nmax, or m > n
        %
        arguments
            obj
            n (1,1) double {mustBeInteger, mustBeNonnegative}
            m (1,1) double {mustBeInteger, mustBeNonnegative}
            Cval (1,1) double
            Sval (1,1) double = NaN
            opts.SigmaC (1,1) double = NaN
            opts.SigmaS (1,1) double = NaN
        end
        if n > obj.nmax || m > n
            error('shCoefficients:setCoefficient:badIndex', ...
                'Invalid (n,m) = (%d,%d) for nmax=%d.', n, m, obj.nmax);
        end
        out = obj;
        out.C(n+1, m+1) = Cval;
        if ~isnan(Sval), out.S(n+1, m+1) = Sval; end
        if ~isnan(opts.SigmaC) || ~isnan(opts.SigmaS)
            % writing either sigma initializes BOTH stacks full-size:
            % sigmas are paired throughout the toolbox and a partially
            % sigma'd object would break shSeries stacking (v2.5.1)
            if isempty(out.sigmaC), out.sigmaC = nan(obj.nmax + 1); end
            if isempty(out.sigmaS), out.sigmaS = nan(obj.nmax + 1); end
        end
        if ~isnan(opts.SigmaC), out.sigmaC(n+1, m+1) = opts.SigmaC; end
        if ~isnan(opts.SigmaS), out.sigmaS(n+1, m+1) = opts.SigmaS; end
        out.history(end+1) = sprintf("set C/S(%d,%d)", n, m);
    end

    function out = applyTN14(obj, tn, opts)
        %APPLYTN14 Replace C20 (and C30 where provided) from a TN-14 table.
        %   OUT = obj.applyTN14(TN) with TN from shLowLevel.readTN14 (or a
        %   filename). Requires a finite obj.epoch; the nearest TN epoch
        %   within opts.Tolerance (default 0.05 yr) is used.
        %   Options
        %     ReplaceC30 ("auto")  "auto" replaces C30 when the table
        %                 carries it, "always"/"never" force the choice
        %   opts.ReplaceC30: "auto" (default: replace when the table has a
        %   non-NaN C30 for that month), "never", "always".
        %   Outputs
        %     out        (1 x 1) shCoefficients   C20 (and C30 when available) replaced by the SLR values, sigmas updated
        %
        %   Error identifiers
        %     shCoefficients:applyTN14:epochNotInTable
        %         no TN-14 entry lies within Tolerance of the object's epoch
        %     shCoefficients:applyTN14:noC30
        %         ReplaceC30="always" was asked for but TN-14 carries no C30 for
        %         that month
        %     shCoefficients:applyTN14:noEpoch
        %         the object has no finite epoch; set one through read or the
        %         constructor
        %
        arguments
            obj
            tn
            opts.Tolerance (1,1) double = 0.05
            opts.ReplaceC30 (1,1) string ...
                {mustBeMember(opts.ReplaceC30, ["auto","never","always"])} = "auto"
        end
        if ischar(tn) || isstring(tn), tn = shLowLevel.readTN14(tn); end
        if ~isfinite(obj.epoch)
            error('shCoefficients:applyTN14:noEpoch', ...
                'applyTN14 requires a finite epoch (set via read/constructor).');
        end
        [dmin, k] = min(abs(tn.epoch - obj.epoch));
        if dmin > opts.Tolerance
            error('shCoefficients:applyTN14:epochNotInTable', ...
                'No TN-14 entry within %.3f yr of epoch %.4f.', ...
                opts.Tolerance, obj.epoch);
        end
        out = obj.setCoefficient(2, 0, tn.C20(k), NaN, SigmaC = tn.sigmaC20(k));
        did = "C20";
        wantC30 = (opts.ReplaceC30 == "always") || ...
                  (opts.ReplaceC30 == "auto" && ~isnan(tn.C30(k)));
        if wantC30 && obj.nmax >= 3
            if isnan(tn.C30(k))
                error('shCoefficients:applyTN14:noC30', ...
                    'ReplaceC30="always" but TN-14 has no C30 for this month.');
            end
            out = out.setCoefficient(3, 0, tn.C30(k), NaN, SigmaC = tn.sigmaC30(k));
            did = did + "+C30";
        end
        out.history(end) = sprintf("TN-14 %s replaced (table epoch %.4f)", ...
            did, tn.epoch(k));
    end

    function out = addDegree1(obj, tn, opts)
        %ADDDEGREE1 Insert TN-13 geocenter (degree-1) coefficients.
        %   OUT = obj.addDegree1(TN) with TN from shLowLevel.readTN13 (or a
        %   filename) sets C10, C11, S11 (with their sigmas) from the
        %   TN-13 record nearest to obj.epoch (within opts.Tolerance (0.05),
        %   default 0.05 yr). Without degree 1, EWH/mass grids are
        %   systematically biased - this completes the standard
        %   GSM + TN-14 + TN-13 processing chain.
        %
        %   Inputs   tn   struct from shLowLevel.readTN13, or filename
        %            Tolerance (1,1) double = 0.05 [yr]
        %   Outputs  out  shCoefficients with degree 1 set
        %   Outputs
        %     out        (1 x 1) shCoefficients   degree-1 row set from the TN-13 record nearest to obj.epoch
        %
        %   Error identifiers
        %     shCoefficients:addDegree1:badIndex
        %         the model has nmax < 1 and cannot hold degree-1 coefficients
        %     shCoefficients:addDegree1:epochNotInTable
        %         no TN-13 entry lies within Tolerance of the object's epoch
        %     shCoefficients:addDegree1:noEpoch
        %         the object has no finite epoch; set one through read or the
        %         constructor
        %
        arguments
            obj
            tn
            opts.Tolerance (1,1) double = 0.05
        end
        if ischar(tn) || isstring(tn), tn = shLowLevel.readTN13(tn); end
        if ~isfinite(obj.epoch)
            error('shCoefficients:addDegree1:noEpoch', ...
                'addDegree1 requires a finite epoch (set via read/constructor).');
        end
        if obj.nmax < 1
            error('shCoefficients:addDegree1:badIndex', ...
                'Model has nmax < 1; cannot hold degree-1 coefficients.');
        end
        [dmin, k] = min(abs(tn.epoch - obj.epoch));
        if dmin > opts.Tolerance
            error('shCoefficients:addDegree1:epochNotInTable', ...
                'No TN-13 entry within %.3f yr of epoch %.4f.', ...
                opts.Tolerance, obj.epoch);
        end
        out = obj.setCoefficient(1, 0, tn.C10(k), NaN, SigmaC = tn.sigC10(k));
        out = out.setCoefficient(1, 1, tn.C11(k), tn.S11(k), ...
            SigmaC = tn.sigC11(k), SigmaS = tn.sigS11(k));
        out.history(end) = sprintf( ...
            "TN-13 degree-1 inserted (table epoch %.4f)", tn.epoch(k));
    end

    % ---------------------------------------------------------- filtering
    function out = destripe(obj, opts)
        %DESTRIPE Swenson & Wahr (2006) / P3M6 decorrelation.
        %   OUT = obj.destripe(MinOrder=6, PolyOrder=3, WindowLength=[])
        %   Formal errors are passed through UNCHANGED (the destriping
        %   operator is data-dependent; rigorous error propagation is not
        %   defined for it - use the tvANS filter on an shSeries for a
        %   filter with proper covariance semantics).
        %   Options
        %     MinOrder (6)       lowest order the decorrelation touches
        %     PolyOrder (3)      order of the fitted/removed polynomial
        %     WindowLength ([])  sliding-window length; [] uses the
        %                        Swenson-Wahr degree-dependent width
        %
        %   Outputs
        %     out        (1 x 1) shCoefficients   Swenson-Wahr decorrelated
        %
        arguments
            obj
            opts.MinOrder (1,1) double = 6
            opts.PolyOrder (1,1) double = 3
            opts.WindowLength double = []
        end
        out = obj;
        [out.C, out.S] = shLowLevel.shDestripe(obj.C, obj.S, ...
            'MinOrder', opts.MinOrder, 'PolyOrder', opts.PolyOrder, ...
            'WindowLength', opts.WindowLength);
        if isempty(opts.WindowLength)
            out.history(end+1) = sprintf("destriped (MinOrder=%d, PolyOrder=%d)", ...
                opts.MinOrder, opts.PolyOrder);
        else
            out.history(end+1) = sprintf(...
                "destriped (MinOrder=%d, PolyOrder=%d, window=%d)", ...
                opts.MinOrder, opts.PolyOrder, opts.WindowLength);
        end
    end

    function out = gaussian(obj, radiusKm)
        %GAUSSIAN Jekeli (1981) isotropic smoothing; sigmas scaled by Wn.
        %
        %   Inputs
        %     radiusKm  (1,1) double  Gaussian filter half-response radius [km]
        %   Outputs
        %     out        (1 x 1) shCoefficients   Gaussian-smoothed; sigmas scaled by Wn
        %
        arguments
            obj
            radiusKm (1,1) double {mustBePositive}
        end
        out = obj;
        [out.C, out.S, Wn] = shLowLevel.shGaussianFilter(obj.C, obj.S, radiusKm);
        if ~isempty(obj.sigmaC)
            out.sigmaC = obj.sigmaC .* Wn(:);
        end
        if ~isempty(obj.sigmaS)
            out.sigmaS = obj.sigmaS .* Wn(:);
        end
        out.history(end+1) = sprintf("Gaussian smoothed (%g km)", radiusKm);
    end

    % ----------------------------------------------------------- spectral
    function spec = degreeRMS(obj, opts)
        %DEGREERMS Degree variance/RMS/amplitude spectrum (+ error spectrum).
        %   Outputs
        %     spec       (1,1) struct   the degree spectrum, including
        %                the formal-error curve, as returned by
        %                shLowLevel.shDegreeRMS
        %
        %   Options
        %     Nmin (0)  first degree included in the spectrum
        %             (renamed from N0 in v4.0.0)
        arguments
            obj
            opts.Nmin (1,1) double = 0
        end
        args = {'R', obj.R, 'Nmin', opts.Nmin};
        if ~isempty(obj.sigmaC) && ~isempty(obj.sigmaS)
            args = [args, {'SigmaC', obj.sigmaC, 'SigmaS', obj.sigmaS}];
        end
        spec = shLowLevel.shDegreeRMS(obj.C, obj.S, args{:});
    end

    function [n0, nInterp] = crossover(obj, opts)
        %CROSSOVER Signal-vs-formal-error crossover degree.
        %   Outputs
        %     n0 (2)       (1,1) double  first degree with err >= signal (NaN if none)
        %     nInterp  (1,1) double  interpolated crossing degree
        %
        %   Options
        %     Nmin (2)  first degree searched for the signal/error crossover
        %             (renamed from N0 in v4.0.0)
        %
        %   Error identifiers
        %     shCoefficients:crossover:noSigmas
        %         the field carries no formal errors (sigmaC/sigmaS), which the
        %         crossover degree is defined against
        arguments
            obj
            opts.Nmin (1,1) double = 2
        end
        if isempty(obj.sigmaC) || isempty(obj.sigmaS)
            error('shCoefficients:crossover:noSigmas', ...
                'crossover requires formal errors (sigmaC/sigmaS).');
        end
        [n0, nInterp] = shLowLevel.shSpectralCrossover(obj.degreeRMS(Nmin = opts.Nmin));
    end

    function h = spectrum(obj, varargin)
        %SPECTRUM Plot the degree-amplitude spectrum. h = obj.spectrum(...)
        %   Outputs
        %     h          (1 x 1) graphics handle   spectrum plot
        %
        h = shLowLevel.plotSHSpectrum(obj.degreeRMS, varargin{:});
    end

    function h = triangle(obj, varargin)
        %TRIANGLE Plot the degree/order coefficient triangle. h = obj.triangle(...)
        %   Outputs
        %     h          (1 x 1) graphics handle   coefficient triangle plot
        %
        h = shLowLevel.plotSHCoeffTriangle(obj.C, obj.S, varargin{:});
    end

    % ------------------------------------------------------------ spatial
    function [grid, lat, lon] = synthesis(obj, latVec, lonVec, opts)
        %SYNTHESIS Spatial synthesis (geoid, gravity, potential, EWH).
        %   [GRID, LAT, LON] = obj.synthesis(LATVEC, LONVEC, Quantity ("geoid")=...,
        %   kn ([])=..., Nmin (0)=..., Nmax (NaN)=..., UseCache (true)=true).
        %   The Legendre functions are served from a verified process-wide
        %   cache (shLowLevel.legendreCached), so monthly time series on a fixed
        %   grid pay the recursion only once - no manual 'P' passing.
        %   EWH requires explicitly supplied load Love numbers kn (never
        %   hardcoded).
        %   Outputs
        %     grid       (nlat x nlon) double   synthesized field
        %     lat        (1 x nlat) double   the latitudes AS GIVEN, in the
        %                convention named by LatType - not the internally
        %                converted ones (changed in v3.31.0)
        %     lon        (1 x nlon) double   longitudes
        %
        %   Options
        %     hn ([])  vertical-deformation Love numbers, degrees 0..nmax (user-supplied)
        %     Height (0)  evaluation height [m] above the evaluation
        %         surface; applies the upward continuation (R/r)^p_n
        %     Surface ("sphere")  "sphere" | "ellipsoid": evaluate on the
        %         sphere r = R or on the ellipsoid r(phi), see
        %         shLowLevel.shSynthesis. It is the SAME ellipsoid the
        %         Flattening option describes for LatType
        %     SemiMajorAxis (6378137)  ellipsoid semi-major axis [m], WGS84
        %     rho_ave (5517)  mean Earth density [kg/m^3] in the EWH kernel
        %     rho_water (1000)  water density [kg/m^3] in the EWH kernel
        %     Method ("auto")  "auto" | "direct" | "fft": FFT along
        %         longitude is much faster on uniform full-circle longitude
        %         vectors; "auto" uses it whenever it is applicable
        %     LatType ("geocentric")  "geocentric" | "geodetic": how the
        %         latitude inputs are interpreted; geodetic values are
        %         converted with Flattening before evaluation
        %     Flattening (1/298.257223563)  flattening of the reference
        %         ellipsoid for the geodetic/geocentric conversion and,
        %         with Surface = "ellipsoid", of the evaluation surface
        %         (WGS84; overridable, never silently assumed)
        %     MaxMemGB (4)  memory budget [GB]; above it the synthesis
        %         streams in latitude bands instead of allocating the full
        %         design matrix (this is what makes nmax 2190 tractable)
        arguments
            obj
            latVec (1,:) double
            lonVec (1,:) double
            opts.Quantity (1,1) string = "geoid"
            opts.kn double = []
            opts.hn double = []
            opts.Height (1,1) double = 0
            opts.Surface (1,1) string ...
                {mustBeMember(opts.Surface, ["sphere","ellipsoid"])} = "sphere"
            opts.SemiMajorAxis (1,1) double = 6378137
            opts.Nmin (1,1) double = 0
            opts.Nmax (1,1) double = NaN
            opts.rho_ave (1,1) double = 5517
            opts.rho_water (1,1) double = 1000
            opts.UseCache (1,1) logical = true
            opts.Method (1,1) string ...
                {mustBeMember(opts.Method, ["auto","direct","fft"])} = "auto"
            opts.LatType (1,1) string ...
                {mustBeMember(opts.LatType, ["geocentric","geodetic"])} = "geocentric"
            opts.Flattening (1,1) double = 1/298.257223563
            opts.MaxMemGB (1,1) double {mustBePositive} = 4
        end
        latOut = latVec;        % the convention the CALLER asked for
        if opts.LatType == "geodetic"
            % map grids are usually geodetic; SH math needs geocentric
            latVec = shLowLevel.geodetic2geocentric(latVec, ...
                Flattening = opts.Flattening);
        end
        nmaxEff = opts.Nmax;
        if isnan(nmaxEff), nmaxEff = obj.nmax; end
        args = {'Quantity', char(opts.Quantity), 'Nmin', opts.Nmin, ...
            'Nmax', nmaxEff, 'rho_ave', opts.rho_ave, ...
            'rho_water', opts.rho_water, 'Method', char(opts.Method), ...
            'MaxMemGB', opts.MaxMemGB, 'Height', opts.Height, ...
            'Surface', opts.Surface, 'SemiMajorAxis', opts.SemiMajorAxis, ...
            'Flattening', opts.Flattening};
        if ~isempty(opts.kn), args = [args, {'kn', opts.kn}]; end
        if ~isempty(opts.hn), args = [args, {'hn', opts.hn}]; end
        % cache only when the full Legendre stack fits the budget;
        % otherwise let shLowLevel.shSynthesis stream latitude bands (v2.2)
        fitsMem = (nmaxEff+1)^2 * numel(latVec) * 8 <= opts.MaxMemGB * 2^30;
        if opts.UseCache && fitsMem
            P = shLowLevel.legendreCached(nmaxEff, deg2rad(latVec(:)'));
            args = [args, {'P', P}];
        end
        [grid, ~, lon] = shLowLevel.shSynthesis(obj.C, obj.S, obj.GM, obj.R, ...
            latVec, lonVec, args{:});
        % LAT comes back in the convention that was ASKED FOR (v3.31.0).
        % It used to be the converted one, so LatType="geodetic" returned
        % geocentric latitudes - 0.1924 deg = 21.4 km at +-45, measured -
        % and a caller who fed them to a map drew the field against a
        % geodetic coastline it no longer matched. Nothing could notice.
        lat = latOut(:)';
    end

    function out = toReference(obj, opts)
        %TOREFERENCE Convert to another (GM (NaN), R (NaN)) reference (exact).
        %   OUT = g.toReference(GM=3.986004418e14, R=6378137.0)
        %   re-expresses the coefficients via shLowLevel.rescaleGMR; the
        %   physical field is invariant (Python-validated). Sigmas
        %   rescale identically; GM/R properties are updated.
        %   Outputs
        %     out        (1 x 1) shCoefficients   rescaled to the given GM/R
        %
        arguments
            obj
            opts.GM (1,1) double = NaN
            opts.R (1,1) double = NaN
        end
        GM2 = opts.GM; if isnan(GM2), GM2 = obj.GM; end
        R2 = opts.R;   if isnan(R2),  R2 = obj.R;  end
        out = obj;
        [out.C, out.S, sg] = shLowLevel.rescaleGMR(obj.C, obj.S, ...
            obj.GM, obj.R, GM2, R2, obj.sigmaC, obj.sigmaS);
        out.sigmaC = sg.C; out.sigmaS = sg.S;
        out.GM = GM2; out.R = R2;
        out.history(end+1) = sprintf( ...
            "rescaled to GM=%.10e, R=%.4f", GM2, R2);
    end

    function out = subtractNormalField(obj, opts)
        %SUBTRACTNORMALFIELD Remove the ellipsoidal normal field.
        %   OUT = g.subtractNormalField()            % WGS84
        %   OUT = g.subtractNormalField(System ("WGS84")="GRS80")
        %   Computes the even zonals from the DEFINING constants
        %   (shLowLevel.normalFieldCS, Heiskanen-Moritz closed form; validated
        %   against NIMA TR8350.2 to all published digits), rescales
        %   them from the ellipsoid's own (GM (NaN), a (NaN)) to the object's
        %   (GM, R) - the WGS84 GM and a DIFFER from the ICGEM values,
        %   skipping this step costs millimetres - and subtracts them
        %   including the degree-0 GM ratio term. The result is the
        %   disturbing field T: 'geoid' synthesis then yields proper
        %   +-100 m undulations (Bruns).
        %
        %   Permanent tide: the ellipsoid is tide-free by construction;
        %   your model's C20 carries its own convention (ICGEM header
        %   'tide_system', ~4.2e-9 zero-tide vs tide-free). Not
        %   converted silently - noted in history only.
        %   Outputs
        %     out        (1 x 1) shCoefficients   disturbing field (even zonals of the normal field removed)
        %
        %   Options
        %     f (NaN)  flattening of the normal field (NaN: the System
        %         default; give GM, a, f and omega together to define your own)
        %     omega (NaN)  angular velocity [rad/s] of the normal field
        %
        arguments
            obj
            opts.System (1,1) string ...
                {mustBeMember(opts.System, ["WGS84","GRS80"])} = "WGS84"
            opts.GM (1,1) double = NaN
            opts.a (1,1) double = NaN
            opts.f (1,1) double = NaN
            opts.omega (1,1) double = NaN
        end
        [CnEll, infoN] = shLowLevel.normalFieldCS(obj.nmax, ...
            System = opts.System, GM = opts.GM, a = opts.a, ...
            f = opts.f, omega = opts.omega);
        % normal field w.r.t. (GM_ell, a_ell) -> object's (GM, R)
        Cell = zeros(obj.nmax + 1); Cell(:, 1) = CnEll;
        Cn = shLowLevel.rescaleGMR(Cell, zeros(obj.nmax + 1), ...
            infoN.GM, infoN.a, obj.GM, obj.R);
        out = obj;
        out.C(:, 1) = obj.C(:, 1) - Cn(:, 1);
        out.history(end+1) = sprintf( ...
            ['normal field subtracted (%s from defining constants, ' ...
             'rescaled GM %.6e->%.6e, a %.1f->%.1f; permanent-tide ' ...
             'convention of the model unchanged)'], opts.System, ...
            infoN.GM, obj.GM, infoN.a, obj.R);
    end

    function H = map(obj, latDeg, lonDeg, opts)
        %MAP Synthesize and draw in one call, through geoMap.
        %   H = g.map(-89:89, 0:359, Quantity ("ewh")=..., kn ([])=...)
        %   builds the handover struct with g.toGrid and hands it to
        %   geo.map. It draws NOTHING itself.
        %
        %   GEOMAP IS THE SINGLE CARTOGRAPHIC AUTHORITY (v3.32.0). This
        %   toolbox used to carry its own renderer, shLowLevel.plotSHMap,
        %   with its own coastlines, colour limits and two projections,
        %   beside sixteen certified ones next door - one fact with two
        %   implementations, and no instrument comparing them. The
        %   renderer is gone; tools/dev/no_map_renderer.py keeps it gone.
        %
        %   GEOMAP'S OPTIONS ARE NOT RESTATED HERE. CRS picks the
        %   projection, Basemap configures the raster element, and
        %   GeoArgs is forwarded verbatim. Mirroring another toolbox's
        %   option table is how the two renderers drifted apart; geo.map
        %   applies the same rule to its own elements.
        %
        %   Without geoMap on the path this raises
        %   shLowLevel:requireGeoMap:geoMapRequired, whose message shows how to draw
        %   the numbers yourself. g.toGrid needs no geoMap at all.
        %
        %   Inputs
        %     latDeg  (1,:) double  latitudes [deg]
        %     lonDeg  (1,:) double  longitudes [deg]
        %   Outputs
        %     H          (1,1) struct   the graphics handle struct, as
        %                returned by geoMap's map function - this
        %                toolbox draws no map of its own
        %
        %   Options
        %     Quantity ("ewh")  any kernelFactors quantity
        %     kn ([])  load Love numbers k'_n (mass quantities; never hardcoded)
        %     hn ([])  load Love numbers h'_n (deformation_up only)
        %     Nmin (0)  degrees below nmin are zeroed
        %     Nmax (NaN)  truncation degree; NaN uses the object's nmax
        %     Height (0)  evaluation height [m] above the evaluation surface
        %     Surface ("sphere")  "sphere" | "ellipsoid": evaluate on the
        %         sphere r = R or on the ellipsoid r(phi), as g.synthesis
        %     SemiMajorAxis (6378137)  ellipsoid semi-major axis [m], WGS84
        %     rho_ave (5517)  mean Earth density [kg/m^3]
        %     rho_water (1000)  water density [kg/m^3]
        %     LatType ("geodetic")  "geodetic" | "geocentric"; coastlines
        %         are geodetic, so a map wants geodetic
        %     Flattening (1/298.257223563)  ellipsoid flattening (WGS84),
        %         for LatType and for Surface = "ellipsoid"
        %     CRS ("equirectangular")  projection, forwarded to geo.map
        %     Basemap (struct())  forwarded to geo.map's Basemap element;
        %         a robust symmetric CLim and the Divergent flag are
        %         inserted unless you set them yourself
        %     GeoArgs ({})  name-value pairs forwarded to geo.map verbatim
        %
        %   Example
        %     H = g.map(-89.5:89.5, 0.5:359.5, Quantity = "ewh", kn = kn, ...
        %             CRS = "robinson");
        arguments
            obj
            latDeg (1,:) double
            lonDeg (1,:) double
            opts.Quantity (1,1) string = "ewh"
            opts.kn double = []
            opts.hn double = []
            opts.Nmin (1,1) double = 0
            opts.Nmax (1,1) double = NaN
            opts.Height (1,1) double = 0
            opts.rho_ave (1,1) double = 5517
            opts.rho_water (1,1) double = 1000
            opts.LatType (1,1) string ...
                {mustBeMember(opts.LatType, ["geocentric","geodetic"])} = "geodetic"
            opts.Flattening (1,1) double = 1/298.257223563
            opts.Surface (1,1) string ...
                {mustBeMember(opts.Surface, ["sphere","ellipsoid"])} = "sphere"
            opts.SemiMajorAxis (1,1) double = 6378137
            opts.CRS (1,1) string = "equirectangular"
            opts.Basemap (1,1) struct = struct()
            opts.GeoArgs cell = {}
        end
        shLowLevel.requireGeoMap();
        b = obj.toGrid(latDeg, lonDeg, Quantity = opts.Quantity, ...
            kn = opts.kn, hn = opts.hn, Nmin = opts.Nmin, ...
            Nmax = opts.Nmax, Height = opts.Height, ...
            rho_ave = opts.rho_ave, rho_water = opts.rho_water, ...
            LatType = opts.LatType, Flattening = opts.Flattening, ...
            Surface = opts.Surface, SemiMajorAxis = opts.SemiMajorAxis);
        bm = opts.Basemap;
        if ~isfield(bm, 'CLim')
            a = shLowLevel.pctile(abs(b.Z(:)), 98);
            if a == 0, a = 1; end
            if b.FieldKind == "anomaly"
                bm.CLim = [-a, a];      % signed field: symmetric about zero
            else
                bm.CLim = [b.Zmin, b.Zmax];
            end
        end
        if ~isfield(bm, 'Divergent')
            bm.Divergent = (b.FieldKind == "anomaly");
        end
        G = geo.grid(b.lon, b.lat, b.Z, Source = b.Source, Units = b.Units);
        % NOT "Basemap = bm, opts.GeoArgs{:}": MATLAB requires name=value
        % arguments to come last, so a cell expansion after one is a PARSE
        % error - and a parse error in a classdef takes the whole class
        % down, which is how one line failed forty unrelated tests.
        args = [{'Basemap', bm}, opts.GeoArgs];
        H = geo.map(G, opts.CRS, args{:});
    end

    function out = fan(obj, rDegKm, rOrdKm)
        %FAN Han fan filter (degree x order Gaussian) - shLowLevel.shFanFilter.
        %
        %   Inputs
        %     rOrdKm  (1,1) double  fan filter order-direction radius [km]
        %     rDegKm  (1,1) double  fan filter degree-direction radius [km]
        %   Outputs
        %     out        (1 x 1) shCoefficients   fan-filtered
        %
        arguments
            obj
            rDegKm (1,1) double {mustBePositive}
            rOrdKm (1,1) double {mustBePositive}
        end
        out = obj;
        [out.C, out.S] = shLowLevel.shFanFilter(obj.C, obj.S, rDegKm, ...
            rOrdKm, R = obj.R);
        out.history(end+1) = sprintf( ...
            "fan filtered (deg %g km, ord %g km)", rDegKm, rOrdKm);
    end

    function [up, north, east] = deformation(obj, latDeg, lonDeg, opts)
        %DEFORMATION Elastic load deformation up/north/east [m].
        %   [UP, NORTH, EAST] = g.deformation(LAT, LON, kn=, hn=, ln=,
        %       Mode ("grid")="grid"|"points", Nmin (1)=1, LatType ("geocentric")="geocentric")
        %   from the object's (residual!) coefficients - remove a mean
        %   field first. Love numbers are always user-supplied; see
        %   shLowLevel.shSynthesisDeformation for formulas and validation.
        %
        %   Inputs
        %     lonDeg  (1,:) double  longitudes [deg]
        %     latDeg  (1,:) double  latitudes [deg, geocentric]
        %   Outputs
        %     up         (nlat x nlon | npts) double   vertical deformation [m]
        %     north      same size   north component [m]
        %     east       same size   east component [m]
        %
        %   Options
        %     Flattening (1/298.257223563)  ellipsoid flattening for the
        %         geodetic/geocentric conversion of the station latitudes
        arguments
            obj
            latDeg (1,:) double
            lonDeg (1,:) double
            opts.kn double
            opts.hn double
            opts.ln double
            opts.Nmin (1,1) double = 1
            opts.Mode (1,1) string ...
                {mustBeMember(opts.Mode, ["grid","points"])} = "grid"
            opts.LatType (1,1) string ...
                {mustBeMember(opts.LatType, ["geocentric","geodetic"])} = "geocentric"
            opts.Flattening (1,1) double = 1/298.257223563
        end
        if opts.LatType == "geodetic"
            latDeg = shLowLevel.geodetic2geocentric(latDeg, ...
                Flattening = opts.Flattening);
        end
        [up, north, east] = shLowLevel.shSynthesisDeformation(obj.C, obj.S, ...
            obj.R, latDeg, lonDeg, kn = opts.kn, hn = opts.hn, ...
            ln = opts.ln, Nmin = opts.Nmin, Mode = opts.Mode);
    end

    function [dq, info] = gradient(obj, latDeg, lonDeg, opts)
        %GRADIENT North/east/up gradient of a synthesized quantity.
        %   [DQ, INFO] = g.gradient(LAT, LON, Quantity ("geoid")=...,
        %       Units ("perMeter")=..., Mode ("grid")=...) is the exact
        %   spatial derivative of what g.synthesis would return under the
        %   SAME options - the vector field to draw over a scalar map, or
        %   to advect tracers through. DQ.up is EMPTY for surface
        %   quantities (ewh, geoid, surface_density, bottom_pressure,
        %   deformation_up, none), which have no radial law; INFO.hasUp
        %   says so. See shLowLevel.shSynthesisGradient for the formulas,
        %   the validation, and why this is NOT g.deformation's horizontal
        %   pair (those carry l'_n, these carry the quantity's own kernel).
        %
        %   Inputs
        %     latDeg  (1,:) double  latitudes [deg]
        %     lonDeg  (1,:) double  longitudes [deg]
        %   Outputs
        %     dq       (1,1) struct   as returned by
        %                shLowLevel.shSynthesisGradient: north, east and
        %                up, each (nlat x nlon) double or (npts x 1) for
        %                Mode="points"; up is [] for surface quantities
        %     info       (1,1) struct   as returned by
        %                shLowLevel.shSynthesisGradient (quantity, units,
        %                r, surface, nmin, nmax, hasUp, lat, lon, latType),
        %                except
        %                that lat and latType are overwritten here when
        %                geodetic input was given, so the convention
        %                travels with the numbers
        %
        %   Options
        %     Quantity ("geoid")  any kernelFactors quantity
        %     kn ([])  load Love numbers k'_n (mass quantities; never hardcoded)
        %     hn ([])  load Love numbers h'_n (deformation_up only)
        %     Nmin (0)  degrees below nmin are zeroed
        %     Nmax (NaN)  truncation degree; NaN uses the object's nmax
        %     Height (0)  evaluation height [m] above the evaluation
        %         surface; surface quantities reject it
        %     Surface ("sphere")  "sphere" | "ellipsoid", see
        %         shLowLevel.shSynthesisGradient; the components stay in
        %         the local spherical frame either way
        %     SemiMajorAxis (6378137)  ellipsoid semi-major axis [m], WGS84
        %     rho_ave (5517)  mean Earth density [kg/m^3]
        %     rho_water (1000)  water density [kg/m^3]
        %     Mode ("grid")  "grid" | "points" (pairwise LAT/LON)
        %     Units ("perMeter")  "perMeter" | "perRadian" (= r x perMeter)
        %     MaxMemGB (4)  Legendre memory budget [GB]
        %     LatType ("geocentric")  "geocentric" | "geodetic": how the
        %         latitude inputs are read. NOTE that only the evaluation
        %         POINT is converted - the components stay in the
        %         geocentric local frame, which differs from the geodetic
        %         one by up to 0.19 deg of meridian convergence. For a map
        %         that is invisible; for a station comparison it is not
        %     Flattening (1/298.257223563)  ellipsoid flattening for that
        %         conversion and for Surface = "ellipsoid" (WGS84;
        %         overridable, never silently assumed)
        %
        %   Example
        %     lat = -89:2:89; lon = 0:2:358;
        %     [dq, info] = g.gradient(lat, lon, Quantity = "ewh", kn = kn);
        %     info.hasUp        % false - EWH is a surface quantity
        arguments
            obj
            latDeg (1,:) double
            lonDeg (1,:) double
            opts.Quantity (1,1) string = "geoid"
            opts.kn double = []
            opts.hn double = []
            opts.Nmin (1,1) double = 0
            opts.Nmax (1,1) double = NaN
            opts.Height (1,1) double = 0
            opts.Surface (1,1) string ...
                {mustBeMember(opts.Surface, ["sphere","ellipsoid"])} = "sphere"
            opts.SemiMajorAxis (1,1) double = 6378137
            opts.rho_ave (1,1) double = 5517
            opts.rho_water (1,1) double = 1000
            opts.Mode (1,1) string ...
                {mustBeMember(opts.Mode, ["grid","points"])} = "grid"
            opts.Units (1,1) string ...
                {mustBeMember(opts.Units, ["perMeter","perRadian"])} = "perMeter"
            opts.MaxMemGB (1,1) double {mustBePositive} = 4
            opts.LatType (1,1) string ...
                {mustBeMember(opts.LatType, ["geocentric","geodetic"])} = "geocentric"
            opts.Flattening (1,1) double = 1/298.257223563
        end
        latOut = latDeg;        % the convention the CALLER asked for
        if opts.LatType == "geodetic"
            latDeg = shLowLevel.geodetic2geocentric(latDeg, ...
                Flattening = opts.Flattening);
        end
        nmaxEff = opts.Nmax;
        if isnan(nmaxEff), nmaxEff = obj.nmax; end
        [dq, info] = shLowLevel.shSynthesisGradient(obj.C, obj.S, obj.GM, ...
            obj.R, latDeg, lonDeg, Quantity = opts.Quantity, ...
            kn = opts.kn, hn = opts.hn, Nmin = opts.Nmin, Nmax = nmaxEff, ...
            Height = opts.Height, rho_ave = opts.rho_ave, ...
            rho_water = opts.rho_water, Mode = opts.Mode, ...
            Units = opts.Units, MaxMemGB = opts.MaxMemGB, ...
            Surface = opts.Surface, SemiMajorAxis = opts.SemiMajorAxis, ...
            Flattening = opts.Flattening);
        % INFO.lat reports what was ASKED FOR, and INFO.latType says which
        % convention that is, so a mismatch can be refused downstream
        % rather than drawn (v3.31.0)
        info.lat = latOut(:)';
        info.latType = opts.LatType;
    end

    function b = toGrid(obj, latDeg, lonDeg, opts)
        %TOGRID Synthesized field plus the metadata a map needs to draw it.
        %   B = g.toGrid(LAT, LON, Quantity ("ewh")=..., kn ([])=...,
        %       LatType ("geodetic")=...) synthesizes exactly as
        %   g.synthesis does and returns the values TOGETHER WITH what
        %   they are: units, latitude convention, product type, epoch,
        %   provenance, and whether the field is a full field or an
        %   anomaly.
        %
        %   WHY THIS EXISTS. g.synthesis returns three numeric arrays, and
        %   an array of metres is an array of metres: a static field
        %   expressed as water (1.16e7 m) and a monthly mass anomaly
        %   (+-1.2 m) are indistinguishable to any renderer, and one of
        %   them is unplottable. The interface between this toolbox and a
        %   cartographic one was measured end to end and three things did
        %   not survive the trip - the latitude convention, the units and
        %   the product type - each of which a user had to retype and
        %   could get wrong with nothing noticing.
        %
        %   LATTYPE DEFAULTS TO "geodetic" HERE, unlike g.synthesis, and
        %   that is deliberate: coastlines are geodetic (Natural Earth,
        %   GSHHG), so a map wants geodetic. The convention travels in
        %   B.LatType, so the choice is stated rather than assumed.
        %
        %   FIELDKIND COMES FROM AN IDENTITY, NOT A GUESS. C(1,1) is the
        %   degree-0 coefficient, which is exactly 1 for a field carrying
        %   the total mass and 0 for a residual - so "full" and "anomaly"
        %   are read off, and anything else is reported as "unknown"
        %   rather than decided. Synthesizing a MASS quantity from a full
        %   field warns (shLowLevel:gridHandover:fullFieldAsMass): it is the
        %   static field expressed as water, not a mass change.
        %
        %   Handover into geoMap is then one line:
        %     G = geo.grid(b.lon, b.lat, b.Z, Source = b.Source, ...
        %             Units = b.Units);
        %
        %   Inputs
        %     latDeg  (1,:) double  latitudes [deg], convention per LatType
        %     lonDeg  (1,:) double  longitudes [deg]
        %   Outputs
        %     b          (1,1) struct   the handover bundle, as built by
        %                shLowLevel.gridHandover, which documents every
        %                field: Z (nlat x nlon) double values; lat
        %                (nlat x 1) AS GIVEN; lon (1 x nlon); the string
        %                fields Units, LatType, Quantity, ProductType,
        %                Source, Name and FieldKind; the scalars Epoch,
        %                C00, Zmin, Zmax and Zmean; and History
        %
        %   Options
        %     Quantity ("ewh")  any kernelFactors quantity; the default is
        %         the one a map of a GRACE field almost always wants
        %     kn ([])  load Love numbers k'_n (mass quantities; never hardcoded)
        %     hn ([])  load Love numbers h'_n (deformation_up only)
        %     Nmin (0)  degrees below nmin are zeroed
        %     Nmax (NaN)  truncation degree; NaN uses the object's nmax
        %     Height (0)  evaluation height [m] above the evaluation surface
        %     Surface ("sphere")  "sphere" | "ellipsoid", as g.synthesis
        %     SemiMajorAxis (6378137)  ellipsoid semi-major axis [m], WGS84
        %     rho_ave (5517)  mean Earth density [kg/m^3]
        %     rho_water (1000)  water density [kg/m^3]
        %     LatType ("geodetic")  "geodetic" | "geocentric"
        %     Flattening (1/298.257223563)  ellipsoid flattening (WGS84),
        %         for LatType and for Surface = "ellipsoid"
        %     Method ("auto")  "auto" | "direct" | "fft"
        %     MaxMemGB (4)  synthesis memory budget [GB]
        %
        %   Example
        %     b = g.toGrid(-89.5:89.5, 0.5:359.5, Quantity = "ewh", kn = kn);
        %     b.Units          % "m"
        %     b.FieldKind      % "anomaly" for a residual field
        arguments
            obj
            latDeg (1,:) double
            lonDeg (1,:) double
            opts.Quantity (1,1) string = "ewh"
            opts.kn double = []
            opts.hn double = []
            opts.Nmin (1,1) double = 0
            opts.Nmax (1,1) double = NaN
            opts.Height (1,1) double = 0
            opts.rho_ave (1,1) double = 5517
            opts.rho_water (1,1) double = 1000
            opts.LatType (1,1) string ...
                {mustBeMember(opts.LatType, ["geocentric","geodetic"])} = "geodetic"
            opts.Flattening (1,1) double = 1/298.257223563
            opts.Surface (1,1) string ...
                {mustBeMember(opts.Surface, ["sphere","ellipsoid"])} = "sphere"
            opts.SemiMajorAxis (1,1) double = 6378137
            opts.Method (1,1) string ...
                {mustBeMember(opts.Method, ["auto","direct","fft"])} = "auto"
            opts.MaxMemGB (1,1) double {mustBePositive} = 4
        end
        nmaxEff = opts.Nmax;
        if isnan(nmaxEff), nmaxEff = obj.nmax; end
        [Z, lat, lon] = obj.synthesis(latDeg, lonDeg, ...
            Quantity = opts.Quantity, kn = opts.kn, hn = opts.hn, ...
            Nmin = opts.Nmin, Nmax = nmaxEff, Height = opts.Height, ...
            rho_ave = opts.rho_ave, rho_water = opts.rho_water, ...
            LatType = opts.LatType, Flattening = opts.Flattening, ...
            Method = opts.Method, MaxMemGB = opts.MaxMemGB, ...
            Surface = opts.Surface, SemiMajorAxis = opts.SemiMajorAxis);
        [~, ~, units] = shLowLevel.kernelFactors(char(opts.Quantity), ...
            nmaxEff, obj.GM, obj.R, kn = opts.kn, hn = opts.hn, ...
            rho_ave = opts.rho_ave, rho_water = opts.rho_water);
        b = shLowLevel.gridHandover(Z, lat, lon, units, opts.LatType, ...
            opts.Quantity, obj.productType, obj.name, obj.epoch, ...
            obj.C(1, 1), obj.history, nmaxEff, opts.Nmin);
    end

    function avg = basinAverage(obj, B)
        %BASINAVERAGE Basin averages of one field from basin kernels.
        %   AVG = g.basinAverage(B) is the naive basin average
        %   B'*x ./ diag(B'*B), one value per basin, with x the coefficient
        %   vector of G. It is the one-epoch case of shSeries.basinAverage
        %   and delegates to it, so the two cannot disagree. The exact
        %   deconvolution (Deconvolve = true) needs the stored operator of
        %   a filtered SERIES, so it stays on shSeries.
        %
        %   Inputs
        %     B    (P x K) double  basin kernels in shLowLevel.shIndex
        %          ordering for this nmax, exactly as shSeries.basinAverage
        %          takes them (from a grid mask with
        %          shLowLevel.synthesisMatrix: b = Y' * (w .* mask))
        %
        %   Outputs
        %     avg  (K x 1) double  basin averages, one per kernel column
        %
        %   A B of the wrong size is refused by the series method this
        %   delegates to, under that method's identifier, which
        %   shSeries.basinAverage documents.
        %
        %   Example
        %     avg = g.basinAverage(B);   % B: P x K, as for ts.basinAverage
        arguments
            obj
            B double
        end
        ts = shSeries(obj);
        avg = ts.basinAverage(B);
    end

    function [sig, latDeg, lonDeg] = errorMap(obj, latDeg, lonDeg, opts)
        %ERRORMAP Formal-error map of a synthesized quantity.
        %   SIG = g.errorMap(LAT, LON) is the pointwise 1-sigma of what
        %   g.synthesis returns on the grid LAT x LON, propagated from G's
        %   own formal sigmas (sigmaC, sigmaS) taken as a DIAGONAL
        %   covariance. SIG = g.errorMap(LAT, LON, Covariance = M,
        %   Index = IDX) propagates a full P x P covariance in IDX ordering
        %   instead, e.g. from shLowLevel.readSINEX(..., Output =
        %   "covariance"). Either way it is shLowLevel.errorMap with G's GM
        %   and R filled in. Quantity, kn, hn and Height go to
        %   shLowLevel.errorMap only when given, so their defaults live
        %   there and nowhere else: "(lane default)" below means that
        %   function's.
        %
        %   A diagonal covariance leaves out every correlation between
        %   coefficients, and for GRACE those are strong - the north-south
        %   stripes ARE correlated error. A map from formal sigmas alone
        %   shows how the error grows with latitude but not its pattern,
        %   and usually understates it. Pass the full covariance when you
        %   have one.
        %
        %   Inputs
        %     latDeg  (1,:) double  geocentric latitudes [deg]
        %     lonDeg  (1,:) double  longitudes [deg]
        %
        %   Outputs
        %     sig     (nlat x nlon) double  1-sigma of the field, in the unit
        %             of Quantity
        %     latDeg  (1,nlat) double  latitudes used [deg], as passed in
        %     lonDeg  (1,nlon) double  longitudes used [deg], as passed in
        %
        %   Options
        %     Covariance ([])  (P x P) double  covariance in Index ordering;
        %         [] builds diag(sigma.^2) from sigmaC and sigmaS
        %     Index ([])  shLowLevel.shIndex struct Covariance is ordered
        %         by; [] uses shLowLevel.shIndex(nmax)
        %     Quantity (lane default)  the quantity whose error is mapped
        %     kn (lane default)  load Love numbers, for mass quantities
        %     hn (lane default)  vertical-deformation Love numbers
        %     Height (lane default)  evaluation height above R [m]
        %
        %   Error identifiers
        %     shCoefficients:errorMap:noCovariance
        %         Covariance is empty and G carries no formal sigmas -
        %         there is no error to propagate
        %
        %   Example
        %     sig = g.errorMap(-89:2:89, 0:2:358, Quantity = "ewh", kn = kn);
        arguments
            obj
            latDeg (1,:) double
            lonDeg (1,:) double
            opts.Covariance double = []
            opts.Index = []
            opts.Quantity
            opts.kn
            opts.hn
            opts.Height
        end
        idx = opts.Index;
        if isempty(idx), idx = shLowLevel.shIndex(obj.nmax); end
        M = opts.Covariance;
        if isempty(M)
            if isempty(obj.sigmaC)
                error('shCoefficients:errorMap:noCovariance', ...
                    ['No Covariance was given and G carries no formal ' ...
                     'sigmas - there is no error to propagate.']);
            end
            M = diag(shLowLevel.vecFromCS(obj.sigmaC, obj.sigmaS, idx) .^ 2);
        end
        fwd = [namedargs2cell(rmfield(opts, ["Covariance", "Index"])), ...
            {'GM', obj.GM, 'R', obj.R}];
        [sig, latDeg, lonDeg] = shLowLevel.errorMap(M, idx, latDeg, ...
            lonDeg, fwd{:});
    end

    function val = synthesisPoints(obj, latDeg, lonDeg, r, opts)
        %SYNTHESISPOINTS Field values at scattered 3-D points.
        %   VAL = g.synthesisPoints(LAT, LON, RGEO) evaluates G pointwise at
        %   equal-length vectors of geocentric latitude and longitude [deg]
        %   and geocentric radius [m] - stations, satellite positions,
        %   profiles - with the upward continuation (R/r)^n that a grid on
        %   the sphere cannot give. It is shLowLevel.synthesisPoints with
        %   G's coefficients, GM and R; that function documents the
        %   quantities, the two summations and why "auto" means "clenshaw".
        %   Its options go there only when given, so "(lane default)"
        %   below is that function's. For points on the reference
        %   ellipsoid pass RGEO = shLowLevel.ellipsoidRadius(LAT) + h.
        %
        %   Inputs
        %     latDeg  (P,1) double  geocentric latitudes [deg]
        %     lonDeg  (P,1) double  longitudes [deg]
        %     r       (P,1) double  geocentric radii [m]
        %
        %   Outputs
        %     val  (P,1) double  the quantity at each point
        %
        %   Options
        %     Quantity (lane default)  the quantity evaluated
        %     Nmin (lane default)  first degree included
        %     Method (lane default)  which summation
        %     ClenshawFrom (lane default)  point count where "auto" switches
        %     MaxMemGB (lane default)  memory budget of the direct path [GB]
        %
        %   Example
        %     r = shLowLevel.ellipsoidRadius(lat) + 450e3;
        %     dg = g.synthesisPoints(lat, lon, r, Quantity = "disturbance");
        arguments
            obj
            latDeg (:,1) double
            lonDeg (:,1) double
            r (:,1) double
            opts.Quantity
            opts.Nmin
            opts.Method
            opts.ClenshawFrom
            opts.MaxMemGB
        end
        fwd = namedargs2cell(opts);
        val = shLowLevel.synthesisPoints(obj.C, obj.S, obj.GM, obj.R, ...
            latDeg, lonDeg, r, fwd{:});
    end

    function [comps, info] = gradientTensor(obj, latDeg, lonDeg, opts)
        %GRADIENTTENSOR Full gravity gradient tensor in the local NEU frame.
        %   [COMPS, INFO] = g.gradientTensor(LAT, LON) synthesizes the six
        %   independent components of the disturbing gravity gradient
        %   tensor - uu, nn, ee, un, ue, ne - the GOCE-style diagnostic.
        %   It is shLowLevel.shSynthesisGradientTensor with G's
        %   coefficients, GM and R; that function documents the formulas,
        %   the Laplace self-check INFO carries, and the validation. Its
        %   options go there only when given, so "(lane default)" below is
        %   that function's - and its Height defaults to a satellite
        %   ALTITUDE, not to the surface.
        %
        %   Inputs
        %     latDeg  (1,:) double  geocentric latitudes [deg]
        %     lonDeg  (1,:) double  longitudes [deg]
        %
        %   Outputs
        %     comps  (1,1) struct  as returned by
        %            shLowLevel.shSynthesisGradientTensor, which documents
        %            every field: the six components, each (nlat x nlon)
        %     info   (1,1) struct  as returned by
        %            shLowLevel.shSynthesisGradientTensor, which documents
        %            every field
        %
        %   Options
        %     Height (lane default)  evaluation altitude above R [m]
        %     Nmin (lane default)  degrees below Nmin are zeroed
        %
        %   Example
        %     [G, info] = g.gradientTensor(-89:89, 0:359, Height = 255e3);
        %     info.maxTraceResidual     % the Laplace self-check
        arguments
            obj
            latDeg (1,:) double
            lonDeg (1,:) double
            opts.Height
            opts.Nmin
        end
        fwd = namedargs2cell(opts);
        [comps, info] = shLowLevel.shSynthesisGradientTensor(obj.C, obj.S, ...
            obj.GM, obj.R, latDeg, lonDeg, fwd{:});
    end

    function [out, info] = vdkApply(obj, N, sigM, opts)
        %VDKAPPLY Apply the VDK decorrelation filter with a month's normals.
        %   [OUT, INFO] = g.vdkApply(N, SIGM) filters G with its own
        %   monthly normal-equation matrix N, xf = (N + alpha M) \ (N x)
        %   (Horvath et al. 2018), through shLowLevel.vdkApply, which
        %   documents the filter, its relation to tvANS and its cost. G's
        %   coefficients are taken in Index ordering - by default
        %   shLowLevel.shIndex(nmax, Nmin = 2), the ordering of
        %   shLowLevel.readSINEX(..., Index = idx) - filtered, and put back.
        %   Coefficients outside Index pass through unchanged. As with
        %   g.applyDDK the formal sigmas are NOT propagated through the
        %   filter; they become NaN. Alpha goes to shLowLevel.vdkApply only
        %   when given, so "(lane default)" below is that function's.
        %
        %   Inputs
        %     N     (P x P) double  normal-equation matrix in Index ordering
        %     sigM  (P x 1 | 1 x 2) double  the signal sigma per parameter,
        %           or [a, b] for sigma = a * l^b, as shLowLevel.vdkApply
        %           takes it
        %
        %   Outputs
        %     out   (1 x 1) shCoefficients  the filtered field
        %     info  (1,1) struct  as returned by shLowLevel.vdkApply, which
        %           documents every field
        %
        %   Options
        %     Index ([])  shLowLevel.shIndex struct N is ordered by; []
        %         uses shLowLevel.shIndex(nmax, Nmin = 2)
        %     Alpha (lane default)  filter strength
        %
        %   Example
        %     idx = shLowLevel.shIndex(96, Nmin = 2);
        %     snx = shLowLevel.readSINEX(f, Index = idx);
        %     gf = g.vdkApply(snx.M, ab(mo, :), Index = idx, Alpha = 1);
        arguments
            obj
            N double
            sigM double
            opts.Index = []
            opts.Alpha
        end
        idx = opts.Index;
        if isempty(idx), idx = shLowLevel.shIndex(obj.nmax, Nmin = 2); end
        fwd = namedargs2cell(rmfield(opts, "Index"));
        x = shLowLevel.vecFromCS(obj.C, obj.S, idx);
        [xf, info] = shLowLevel.vdkApply(x, N, idx.n, sigM, fwd{:});
        [cf, sf] = shLowLevel.csFromVec(xf, idx);
        out = obj;
        rows = idx.minDegree + 1 : idx.Lmax + 1;
        out.C(rows, 1:idx.Lmax + 1) = cf(rows, :);
        out.S(rows, 1:idx.Lmax + 1) = sf(rows, :);
        out.sigmaC = nan(size(obj.C)); out.sigmaS = nan(size(obj.S));
        out.history(end+1) = sprintf( ...
            "VDK filter applied (alpha = %g, %d parameters)", info.alpha, info.P);
    end

    function out = applyDDK(obj, W)
        %APPLYDDK Apply a DDK (order-block-diagonal) decorrelation filter.
        %   OUT = obj.applyDDK(W) with W from shLowLevel.readDDK (struct, .mat,
        %   or documented ASCII exchange format). Degrees not covered by
        %   the filter pass through unchanged; sigmas are NOT propagated
        %   through the filter (set to NaN - use shLowLevel.mcPropagate for
        %   filtered uncertainties).
        %   Outputs
        %     out        (1 x 1) shCoefficients   DDK-decorrelated
        %
        arguments
            obj
            W
        end
        W = shLowLevel.readDDK(W);
        out = obj;
        [out.C, out.S] = shLowLevel.applyDDK(obj.C, obj.S, W);
        out.sigmaC = nan(size(obj.C)); out.sigmaS = nan(size(obj.S));
        out.history(end+1) = sprintf("DDK filter applied (%s, Nmax=%d)", ...
            W.name, W.nmax);
    end

    % ---------------------------------------------------------- gfct, I/O
    function out = evalAt(obj, epoch)
        %EVALAT Evaluate gfct time-variable terms at an epoch.
        %   Outputs
        %     out        (1 x 1) shCoefficients   gfct variable terms evaluated at the epoch; static models pass through unchanged
        %
        arguments
            obj
            epoch (1,1) double
        end
        model = struct('C', obj.C, 'S', obj.S, ...
            'variableTerms', obj.variableTerms);
        out = obj;
        [out.C, out.S] = shLowLevel.shEvalGFCT(model, epoch);
        out.epoch = epoch;
        out.history(end+1) = sprintf("gfct evaluated at %.4f", epoch);
    end

    function write(obj, filename, opts)
        %WRITE Export to an ICGEM .gfc file (round-trip tested).
        %
        %
        %   Inputs
        %     filename  char/string  path of the file to read/write (gzipped .gz accepted where documented)
        %   Options
        %     Comment ("")  free-text comment written into the gfc header
        %     Sidecar (true)  also write "<filename>.provenance.json".
        %             Set false when exporting into a folder that will be
        %             read back as a series: the sidecar is metadata, and
        %             a loose read pattern would otherwise pick it up
        arguments
            obj
            filename {mustBeTextScalar}
            opts.Comment (1,1) string = ""
            opts.Sidecar (1,1) logical = true
        end
        cmt = strjoin(obj.history, " | ");
        if strlength(opts.Comment) > 0, cmt = opts.Comment + " | " + cmt; end
        nm = obj.name; if strlength(nm) == 0, nm = "shAnalysis_export"; end
        shLowLevel.writeGFC(filename, obj.C, obj.S, obj.GM, obj.R, ...
            SigmaC = obj.sigmaC, SigmaS = obj.sigmaS, ...
            ModelName = nm, TideSystem = obj.tideSystem, Comment = cmt, ...
            Sidecar = opts.Sidecar);
    end

    % ---------------------------------------------------- tvANS interface
    function x = vec(obj, idx)
        %VEC Pack into a coefficient vector in shLowLevel.shIndex ordering.
        %   Outputs
        %     x          (P x 1) double   coefficients in idx ordering
        %
        %   Error identifiers
        %     shCoefficients:vec:badIndex
        %         idx.Lmax exceeds the field's nmax
        %
        arguments
            obj
            idx (1,1) struct
        end
        if idx.Lmax > obj.nmax
            error('shCoefficients:vec:badIndex', ...
                'idx.Lmax=%d exceeds nmax=%d.', idx.Lmax, obj.nmax);
        end
        x = shLowLevel.vecFromCS(obj.C, obj.S, idx);
    end

    function out = poleTideConvert(obj, opts)
        %POLETIDECONVERT Move C21/S21 to another mean-pole convention.
        %   OUT = g.poleTideConvert(From = "IERS2010", To = "IERS2018") is
        %   shLowLevel.poleTideConvert(g, ...): it moves C21 and S21 from
        %   the mean-pole model the processing centre removed the pole tide
        %   with to another, at the field's own epoch. That function
        %   documents the two models and the adjustment.
        %
        %   Outputs
        %     out  (1,1) shCoefficients  the converted field, history
        %          appended
        %
        %   Options
        %     From (lane default)  the convention of this field
        %     To (lane default)  the convention to move to
        %     Mode (lane default)  the solid tide, the ocean tide, or both
        %     SolidCoef (lane default)  the solid-tide coefficient
        %     OceanCoef (lane default)  the ocean-tide coefficient
        %
        %   Example
        %     g18 = g.poleTideConvert(From = "IERS2010", To = "IERS2018");
        arguments
            obj
            opts.From
            opts.To
            opts.Mode
            opts.SolidCoef
            opts.OceanCoef
        end
        args = namedargs2cell(opts);
        out = shLowLevel.poleTideConvert(obj, args{:});
    end

    function [a, rec] = slepianProject(obj, G, idx)
        %SLEPIANPROJECT Project this field onto a Slepian basis, and back.
        %   [A, REC] = g.slepianProject(G, IDX) is
        %   shLowLevel.slepianProject(g.C, g.S, G, IDX), with the tapers G
        %   and the index IDX of shLowLevel.slepianBasis. A holds the
        %   Slepian coefficients, REC the field rebuilt from them.
        %
        %   Inputs
        %     G    (P,K) double  Slepian tapers, from shLowLevel.slepianBasis
        %     idx  (1,1) struct  the coefficient index they are ordered by
        %
        %   Outputs
        %     a    (K,1) double  the Slepian coefficients
        %     rec  (1,1) struct  as returned by shLowLevel.slepianProject,
        %          which documents every field
        %
        %   Example
        %     G = shLowLevel.slepianBasis(idx, @(la, lo) double(la > 60));
        %     a = g.slepianProject(G, idx);
        arguments
            obj
            G
            idx
        end
        [a, rec] = shLowLevel.slepianProject(obj.C, obj.S, G, idx);
    end

    function B = regionalBasis(obj, region, opts)
        %REGIONALBASIS A local basis for a region, at this field's degree.
        %   B = g.regionalBasis(REGION) is
        %   shLowLevel.regionalBasis(shLowLevel.shIndex(g.nmax), REGION):
        %   radial basis functions, Slepian tapers or the SH basis for a
        %   basin or region, built for the degree this field carries, so
        %   that g.regionalProject(B) cannot meet an index of another
        %   size. That function documents the bases and the projector.
        %
        %   Inputs
        %     region  basin name, handle, polygon or mask, as
        %             shLowLevel.regionalBasis takes it ([] for Type "sh")
        %
        %   Outputs
        %     B  (1,1) struct  the basis, as returned by
        %        shLowLevel.regionalBasis, which documents every field
        %
        %   Options
        %     Nmin (shIndex default)  first degree of the index
        %     Type (lane default)  "rbf" | "slepian" | "sh"
        %     BufferKm (lane default)  growth of the region [km]
        %     Grid (lane default)  "icosahedral" | "reuter"
        %     Level (lane default)  rbf grid level
        %     Kernel (lane default)  "kaula" | "shannon" | "amplitude"
        %     DegreeAmplitude (lane default)  sigma_n for Kernel "amplitude"
        %     Threshold (lane default)  slepian concentration cut
        %     NKeep (lane default)  slepian taper count
        %     EigTol (lane default)  rbf projector eigenvalue cut
        %     R (lane default)  sphere radius [m]
        %     OverSample (lane default)  mask quadrature refinement
        %     BasinFile (lane default)  GeoJSON for a basin name
        %
        %   Example
        %     B = g.regionalBasis("Elbe", Type = "slepian");
        %     a = g.regionalProject(B);
        arguments
            obj
            region = []
            opts.Nmin
            opts.Type
            opts.BufferKm
            opts.Grid
            opts.Level
            opts.Kernel
            opts.DegreeAmplitude
            opts.Threshold
            opts.NKeep
            opts.EigTol
            opts.R
            opts.OverSample
            opts.BasinFile
        end
        if isfield(opts, 'Nmin')
            idx = shLowLevel.shIndex(obj.nmax, Nmin = opts.Nmin);
            opts = rmfield(opts, 'Nmin');
        else
            idx = shLowLevel.shIndex(obj.nmax);
        end
        args = namedargs2cell(opts);
        B = shLowLevel.regionalBasis(idx, region, args{:});
    end

    function [a, rec] = regionalProject(obj, B)
        %REGIONALPROJECT This field in a regional basis, and back.
        %   [A, REC] = g.regionalProject(B) is
        %   shLowLevel.regionalProject(g.C, g.S, B): A holds the
        %   coefficients in the basis B of g.regionalBasis,
        %   REC the field rebuilt from them.
        %
        %   Inputs
        %     B  (1,1) struct  a basis from regionalBasis
        %
        %   Outputs
        %     a    (K,1) double  basis coefficients
        %     rec  (1,1) struct  as returned by shLowLevel.regionalProject,
        %          which documents every field
        %
        %   Example
        %     B = g.regionalBasis("Elbe");
        %     [a, rec] = g.regionalProject(B);
        arguments
            obj
            B (1,1) struct
        end
        [a, rec] = shLowLevel.regionalProject(obj.C, obj.S, B);
    end

    function disp(obj)
        %DISP Compact display: size, epoch, GM/R, processing history.
        %   disp(G) prints one header line with the model name, one
        %   contract line (nmax, epoch, product type, tide system, GM,
        %   R), whether formal sigmas are attached and how many gfct
        %   variable terms are carried, followed by the processing
        %   history. Called automatically when an shCoefficients object
        %   is shown without a semicolon.
        %
        %   Inputs
        %     obj  (1,1) shCoefficients  the coefficient set to display
        %   Outputs
        %     none - the summary is written to the command window
        %
        %   Example
        %     g = shCoefficients.read("ITSG-Grace2018_n60_2008-04.gfc");
        %     disp(g)                            % degree, epoch, history
        %
        %   Developed by Matthias Weigelt with the help of Claude (Fable 5).
        fprintf('  shCoefficients: %s\n', obj.name);
        fprintf('    nmax=%d | epoch=%.4f | product=%s | tide=%s | GM=%.6e | R=%.1f\n', ...
            obj.nmax, obj.epoch, obj.productType, obj.tideSystem, obj.GM, obj.R);
        fprintf('    sigmas: %s | variableTerms: %d\n', ...
            string(~isempty(obj.sigmaC)), numel(obj.variableTerms));
        fprintf('    history:\n');
        fprintf('      %s\n', obj.history);
    end
end

methods (Static)
    function obj = read(filename, opts)
        %READ Read an ICGEM .gfc/.gfct/.gfc.gz file into an shCoefficients.
        %   G = shCoefficients.read(FILE) parses product type and mid-epoch
        %   from standard GRACE L2 filenames (GSM/GAA/GAB/GAC/GAD-2_...);
        %   override with Epoch (NaN)=..., ProductType ("")=... when needed.
        %
        %   Inputs
        %     filename  char/string  path of the file to read/write (gzipped .gz accepted where documented)
        %   Outputs
        %     obj        (1 x 1) shCoefficients   parsed gfc/gfct(.gz) with GM, R, sigmas, variable terms, Epoch= as given
        %
        arguments
            filename {mustBeTextScalar}
            opts.Epoch (1,1) double = NaN
            opts.ProductType (1,1) string = ""
        end
        m = shLowLevel.shReadGFC(char(filename));
        meta = shLowLevel.parseGraceFilename(filename);
        ep = opts.Epoch;
        if isnan(ep), ep = meta.epoch; end
        pt = opts.ProductType;
        if strlength(pt) == 0
            pt = meta.productType;
            if pt == "unknown" && isempty(m.variableTerms) ...
                    && ~isfinite(ep)
                pt = "static";
            end
        end
        ts = "unknown"; nm = "";
        if isfield(m.header, 'tide_system'), ts = string(m.header.tide_system); end
        if isfield(m.header, 'modelname'),   nm = string(m.header.modelname); end
        [~, base, ext] = fileparts(char(filename));
        if strlength(nm) == 0
            % headers without modelname (COST-G GSM among them) used to
            % leave the name empty all the way into shSeries.names; the
            % filename stem is always available and always identifying
            nm = string(base);
        end
        obj = shCoefficients(m.C, m.S, SigmaC = m.sigmaC, SigmaS = m.sigmaS, ...
            GM = m.GM, R = m.R, Epoch = ep, ProductType = pt, ...
            TideSystem = ts, Name = nm, Header = m.header, ...
            VariableTerms = m.variableTerms, ...
            History = sprintf("read %s%s (Nmax=%d)", base, ext, m.nmax));
    end

    function obj = fromVec(x, idx, like)
        %FROMVEC Unpack a shLowLevel.shIndex-ordered vector into an shCoefficients.
        %   G = shCoefficients.fromVec(X, IDX, LIKE) copies GM/R and other
        %   metadata from the template LIKE (an shCoefficients).
        %   Inputs
        %     like  template shCoefficients supplying GM, R and metadata
        %
        %   Outputs
        %     obj        (1 x 1) shCoefficients   rebuilt from x with sizes/GM/R/epoch of the template
        %
        arguments
            x (:,1) double
            idx (1,1) struct
            like (1,1) shCoefficients
        end
        [cnm, snm] = shLowLevel.csFromVec(x, idx);
        obj = shCoefficients(cnm, snm, GM = like.GM, R = like.R, ...
            Epoch = like.epoch, ProductType = like.productType, ...
            TideSystem = like.tideSystem, Name = like.name + "_fromVec", ...
            History = [like.history; "rebuilt from vector"]);
    end

    function [obj, info] = analysis(grid, latVec, lonVec, nmax, opts)
        %ANALYSIS Spherical harmonic analysis: gridded/scattered data ->
        %   Stokes coefficients (the inverse of synthesis).
        %
        %   [OBJ, INFO] = shCoefficients.analysis(GRID, LAT, LON, NMAX,
        %       Quantity ("geoid")=..., Method ("auto")=..., Weights ("none")=..., Kaula (0)=..., ...)
        %   estimates an shCoefficients object from a ring grid
        %   (GRID nlat x nlon, uniform full-circle LON: exact fast
        %   per-order solver) or from scattered points (equal-length
        %   GRID/LAT/LON vectors: full least squares). See
        %   shLowLevel.shAnalysisGrid for the estimation options, the Kaula
        %   regularization needed for under-determined sampling, and the
        %   exactness guarantees. GM (3.986004415e14)/R (6378136.3)/Epoch (NaN)/Name ("analysis") flow into the object.
        %
        %   Inputs   grid (nlat,nlon) or (Np,1) double, lat/lon [deg]
        %     lonVec  (P,1) double  observation longitudes [deg]
        %     latVec  (P,1) double  observation latitudes [deg, geocentric]
        %            Nmax (1,1) double
        %   Options
        %     Quantity ("geoid")  physical quantity of the grid values;
        %         its kernel is divided out, see shLowLevel.kernelFactors
        %     Method ("auto")  "auto" | "rings" | "ls", see shAnalysisGrid
        %     Weights ("none") ("none" | "coslat") latitude weighting
        %     Kaula (0)     (1 x 1) Kaula regularization for "ls"
        %     kn ([])  load Love numbers, degrees 0..nmax, required for
        %         Quantity="ewh" (user-supplied, never hardcoded)
        %     hn ([])  vertical-deformation Love numbers, degrees 0..nmax
        %     rho_ave (5517)  mean Earth density [kg/m^3] in the EWH kernel
        %     rho_water (1000)  water density [kg/m^3] in the EWH kernel
        %     LatType ("geocentric")  "geocentric" | "geodetic": how latVec
        %         is interpreted; geodetic values are converted with
        %         Flattening before evaluation
        %     Flattening (1/298.257223563)  flattening of the reference
        %         ellipsoid for that conversion (WGS84; overridable,
        %         never silently assumed)
        %     GM (3.986004415e14), R (6378136.3), Epoch (NaN)  stored on
        %         the returned object
        %     Name ("analysis")  (1 x 1) string stored as the object name
        %     Fill (NaN)  the value that replaces NaN in GRID - e.g. 0 where a
        %         land-only grid has no ocean value. NaN, the default,
        %         refuses a grid that holds NaN: what the gaps mean is the
        %         caller's call, and NaN would otherwise reach every
        %         coefficient without an error (v5.8.0)
        %
        %   Outputs
        %     obj        (1 x 1) shCoefficients   Stokes coefficients estimated from the grid (exact on ring grids; Kaula for scattered points)
        %     info       (1,1) struct   the estimation diagnostics, as
        %                returned by shLowLevel.shAnalysisGrid
        %
        %   Error identifiers
        %     shCoefficients:analysis:nanInGrid
        %         GRID holds NaN and no Fill was given
        %
        arguments
            grid double
            latVec double
            lonVec double
            nmax (1,1) double
            opts.Quantity (1,1) string = "geoid"
            opts.Method (1,1) string = "auto"
            opts.Weights (1,1) string = "none"
            opts.Kaula (1,1) double = 0
            opts.kn double = []
            opts.hn double = []
            opts.rho_ave (1,1) double = 5517
            opts.rho_water (1,1) double = 1000
            opts.GM (1,1) double = 3.986004415e14
            opts.R (1,1) double = 6378136.3
            opts.Epoch (1,1) double = NaN
            opts.Name (1,1) string = "analysis"
            opts.LatType (1,1) string ...
                {mustBeMember(opts.LatType, ["geocentric","geodetic"])} = "geocentric"
            opts.Flattening (1,1) double = 1/298.257223563
            opts.Fill (1,1) double = NaN
        end
        nNaN = nnz(isnan(grid));
        if nNaN > 0
            if isnan(opts.Fill)
                error('shCoefficients:analysis:nanInGrid', ...
                    ['GRID holds %d NaN value(s) - a land-only or masked ' ...
                     'grid. analysis will not decide what they mean: pass ' ...
                     'Fill = value (0 for "no mass there").'], nNaN);
            end
            grid(isnan(grid)) = opts.Fill;
        end
        if opts.LatType == "geodetic"
            latVec = shLowLevel.geodetic2geocentric(latVec, ...
                Flattening = opts.Flattening);
        end
        [C, S, info] = shLowLevel.shAnalysisGrid(grid, latVec, lonVec, nmax, ...
            Method = opts.Method, Quantity = char(opts.Quantity), ...
            GM = opts.GM, R = opts.R, kn = opts.kn, hn = opts.hn, ...
            rho_ave = opts.rho_ave, rho_water = opts.rho_water, ...
            Weights = opts.Weights, Kaula = opts.Kaula);
        obj = shCoefficients(C, S, GM = opts.GM, R = opts.R, ...
            Epoch = opts.Epoch, Name = opts.Name, ProductType = "analysis", ...
            History = sprintf("SH analysis (%s, %d points, residRMS %.3g)", ...
                info.method, info.nPoints, info.residRMS));
    end
end

methods (Static, Access = private)
    function [a, b] = checkPair(a, b, opname)
        if ~isa(a, 'shCoefficients') || ~isa(b, 'shCoefficients')
            error('shCoefficients:operands:badInput', ...
                '%s requires two shCoefficients objects.', opname);
        end
        if a.nmax ~= b.nmax
            error('shCoefficients:operands:sizeMismatch', ...
                'nmax differs (%d vs %d) - use truncate() first.', ...
                a.nmax, b.nmax);
        end
        if abs(a.GM - b.GM) > 1e-9 * a.GM || abs(a.R - b.R) > 1e-9 * a.R
            error('shCoefficients:operands:constantsMismatch', ...
                ['GM/R differ between operands - convert first with ' ...
                 'toReference(GM=..., R=...) (exact spectral rescaling).']);
        end
    end

    function checkEpochs(a, b, tol, opname)
        if isfinite(a.epoch) && isfinite(b.epoch) && abs(a.epoch - b.epoch) > tol
            error('shCoefficients:operands:epochMismatch', ...
                '%s: epochs %.4f and %.4f differ by more than %.3f yr.', ...
                opname, a.epoch, b.epoch, tol);
        end
    end

    function t = combinedType(ta, tb, sym)
        gax = ["GAA","GAB","GAC","GAD"];
        if ta == "GSM" && any(tb == gax)
            t = "GSM" + sym + tb;
        elseif tb == "GSM" && any(ta == gax)
            t = "GSM" + sym + ta;
        elseif ta == tb
            t = ta;
        else
            t = "combined";
        end
    end
end

methods (Access = private)
    function out = combine(a, b, sgn, newType)
        out = a;
        out.C = a.C + sgn * b.C;
        out.S = a.S + sgn * b.S;
        if ~isempty(a.sigmaC) && ~isempty(b.sigmaC)
            out.sigmaC = sqrt(a.sigmaC.^2 + b.sigmaC.^2);
        else
            out.sigmaC = [];
        end
        if ~isempty(a.sigmaS) && ~isempty(b.sigmaS)
            out.sigmaS = sqrt(a.sigmaS.^2 + b.sigmaS.^2);
        else
            out.sigmaS = [];
        end
        out.productType = newType;
        out.variableTerms = [];
        if sgn > 0
            out.history(end+1) = sprintf("plus: %s + %s -> %s", ...
                a.productType, b.productType, newType);
        else
            out.history(end+1) = "minus";
        end
    end
end
end
