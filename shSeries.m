classdef shSeries
%SHSERIES Time series of spherical harmonic coefficient sets.
%
%   Wraps a stack of shCoefficients over epochs and provides everything
%   with a time dimension: the mean field, the climatology (bias / trend /
%   annual / semi-annual), GAX background restoration, the classic
%   destripe+Gaussian chain applied per epoch, and the tvANS
%   time-variable anisotropic Wiener filter with exact basin
%   deconvolution. Immutable value class with provenance in .history.
%
%   Construction
%     ts = shSeries.read("GSM-2_*.gfc");        % pattern, sorted by epoch
%     ts = shSeries.read(fileList);              % string array of paths
%     ts = shSeries(objArray);                   % from shCoefficients array
%
%   Typical use
%     ts   = ts.restore(shSeries.read("GAD-2_*.gfc"));   % add background
%     m    = ts.mean;                                    % mean field
%     dts  = ts - m;                                     % anomalies
%     [clim, resid] = dts.climatology(Robust=true);      % + shClimatology
%     tsA  = dts.destripe(MinOrder=6).gaussian(300);     % classic chain
%     [tsF, op] = dts.filter("tvANS", Constraints=ocean);% optimal chain
%     avg  = tsF.basinAverage(B, Deconvolve=true, Op=op);
%
%   Properties (read-only)
%     Cs, Ss        (nmax+1)x(nmax+1)xT double   coefficient stacks
%     sigmaCs/Ss    same or []                    formal error stacks
%     epochs        (T,1) double  decimal years
%     GM, R         (1,1) double
%     Nmax, nEpochs (dependent)
%     productType   (1,1) string
%     names         (T,1) string
%     history       string column
%
%   See also shCoefficients, shClimatology.
%
%   Claude (Fable 5), 2026-08-07.
%   v3.29.0, 2026-08-20: mean(Range=, Estimator=) and select(Range=)
%   added; the standard error of the mean now divides by the valid
%   epoch count per coefficient - Claude (Opus 5).
%   Developed by Matthias Weigelt with the help of Claude (Fable 5).

properties (SetAccess = private)
    Cs double
    Ss double
    sigmaCs double = []
    sigmaSs double = []
    epochs (:,1) double
    GM (1,1) double = 3.986004415e14
    R (1,1) double = 6378136.3
    productType (1,1) string = "unknown"
    names (:,1) string = string.empty(0,1)
    history string = string.empty(0,1)
end

properties (Dependent)
    nmax
    nEpochs
end

methods
    function obj = set.history(obj, h)
        % normalize to a string column: scalar-seeded (end+1) growth
        % otherwise produces rows and breaks vertcat chains (v2.2 fix)
        h = string(h);                       % chars -> scalar string first
        obj.history = h(:);
    end

    function obj = shSeries(in, opts)
        %SHSERIES Construct from an shCoefficients array or raw stacks.
        %   ts = shSeries(objArray)
        %   ts = shSeries(Cs, Epochs ([])=..., Ss ([])=...)  (raw-stack form via opts)
        %
        %   Inputs
        %     in  (nmax+1 x nmax+1 x T) double or (1,T) shCoefficients  coefficient stacks or object array
        %   Outputs
        %     obj        (1 x 1) shSeries   epoch-sorted monthly stack with sigmas and history
        %
        %   Options
        %     GM (3.986004415e14)  gravitational constant times mass
        %         [m^3/s^2] of the series (overridable default)
        %     R (6378136.3)  reference radius [m] of the series
        %     ProductType ("unknown")  provider product code shared by all
        %         epochs, e.g. "GSM"
        %     Names (string.empty(0,1))  display labels, one per solution/series
        %     SigmaCs ([])  formal 1-sigma stack for Cs, same size
        %     SigmaSs ([])  formal 1-sigma stack for Ss, same size
        %     History (string.empty(0,1))  initial processing history; every
        %         operation appends one line
        %
        %   Error identifiers
        %     shSeries:shSeries:badInput
        %         the raw-stack form needs a square Cs, a matching Ss=, and one
        %         Epochs= entry per layer
        %     shSeries:shSeries:constantsMismatch
        %         GM or R differ between epochs of the series
        %     shSeries:shSeries:sizeMismatch
        %         the epochs do not all share nmax - truncate first
        arguments
            in
            opts.Ss double = []
            opts.Epochs (:,1) double = []
            opts.GM (1,1) double = 3.986004415e14
            opts.R (1,1) double = 6378136.3
            opts.ProductType (1,1) string = "unknown"
            opts.Names (:,1) string = string.empty(0,1)
            opts.SigmaCs double = []
            opts.SigmaSs double = []
            opts.History string = string.empty(0,1)
        end
        if isa(in, 'shCoefficients')
            arr = in(:);
            T = numel(arr);
            nm = arr(1).nmax;
            for k = 2:T
                if arr(k).nmax ~= nm
                    error('shSeries:shSeries:sizeMismatch', ...
                        'All epochs must share nmax (epoch %d has %d, expected %d) - truncate first.', ...
                        k, arr(k).nmax, nm);
                end
                if abs(arr(k).GM - arr(1).GM) > 1e-9*arr(1).GM || ...
                   abs(arr(k).R - arr(1).R) > 1e-9*arr(1).R
                    error('shSeries:shSeries:constantsMismatch', ...
                        'GM/R differ within the series (epoch %d).', k);
                end
            end
            obj.Cs = zeros(nm+1, nm+1, T);
            obj.Ss = zeros(nm+1, nm+1, T);
            hasSig = all(arrayfun(@(g) ~isempty(g.sigmaC), arr));
            if hasSig
                obj.sigmaCs = zeros(nm+1, nm+1, T);
                obj.sigmaSs = zeros(nm+1, nm+1, T);
            end
            ep = zeros(T,1); nmv = strings(T,1);
            for k = 1:T
                obj.Cs(:,:,k) = arr(k).C;
                obj.Ss(:,:,k) = arr(k).S;
                if hasSig
                    obj.sigmaCs(:,:,k) = arr(k).sigmaC;
                    obj.sigmaSs(:,:,k) = arr(k).sigmaS;
                end
                ep(k) = arr(k).epoch;
                nmv(k) = arr(k).name;
            end
            [ep, ord] = sortWithNaN(ep);
            obj.Cs = obj.Cs(:,:,ord); obj.Ss = obj.Ss(:,:,ord);
            if hasSig
                obj.sigmaCs = obj.sigmaCs(:,:,ord);
                obj.sigmaSs = obj.sigmaSs(:,:,ord);
            end
            obj.epochs = ep;
            obj.names = nmv(ord);
            obj.GM = arr(1).GM; obj.R = arr(1).R;
            obj.productType = arr(1).productType;
            obj.history = sprintf("series from %d shCoefficients (Nmax=%d)", T, nm);
        else
            % raw-stack form
            obj.Cs = in;
            obj.Ss = opts.Ss;
            if isempty(obj.Ss) || ~isequal(size(obj.Cs), size(obj.Ss)) ...
                    || size(in,1) ~= size(in,2)
                error('shSeries:shSeries:badInput', ...
                    'Raw-stack form requires square Cs and matching Ss=... stacks.');
            end
            T = size(in, 3);
            if isempty(opts.Epochs)
                error('shSeries:shSeries:badInput', 'Raw-stack form requires Epochs=...');
            end
            if numel(opts.Epochs) ~= T
                error('shSeries:shSeries:badInput', 'numel(Epochs) must equal size(Cs,3).');
            end
            obj.epochs = opts.Epochs;
            obj.GM = opts.GM; obj.R = opts.R;
            obj.productType = opts.ProductType;
            obj.names = opts.Names;
            obj.sigmaCs = opts.SigmaCs; obj.sigmaSs = opts.SigmaSs;
            if isempty(opts.History)
                obj.history = sprintf("series from raw stacks (T=%d)", T);
            else
                obj.history = opts.History;
            end
        end
    end

    function n = get.nmax(obj), n = size(obj.Cs, 1) - 1; end
    function T = get.nEpochs(obj), T = size(obj.Cs, 3); end

    function g = at(obj, k)
        %AT Extract epoch k as an shCoefficients.
        %   Inputs
        %     k  epoch index (1-based) or decimal year (nearest match)
        %
        %   Outputs
        %     g          (1 x 1) shCoefficients   month k with epoch and sigmas
        %
        %   Error identifiers
        %     shSeries:at:badIndex
        %         k exceeds nEpochs
        %
        arguments
            obj
            k (1,1) double {mustBeInteger, mustBePositive}
        end
        if k > obj.nEpochs
            error('shSeries:at:badIndex', 'k=%d exceeds nEpochs=%d.', k, obj.nEpochs);
        end
        sc = []; ss = [];
        if ~isempty(obj.sigmaCs), sc = obj.sigmaCs(:,:,k); ss = obj.sigmaSs(:,:,k); end
        nm = "";
        if numel(obj.names) >= k, nm = obj.names(k); end
        g = shCoefficients(obj.Cs(:,:,k), obj.Ss(:,:,k), SigmaC = sc, ...
            SigmaS = ss, GM = obj.GM, R = obj.R, Epoch = obj.epochs(k), ...
            ProductType = obj.productType, Name = nm, ...
            History = [obj.history; sprintf("extracted epoch %d", k)]);
    end

    % --------------------------------------------------- series statistics
    function [g, info] = mean(obj, opts)
        %MEAN Mean field, over the whole series or a user-given window.
        %   G = ts.mean() averages every epoch and returns an
        %   shCoefficients whose sigmas are the standard error of the
        %   temporal scatter, divided by the number of VALID epochs per
        %   coefficient (before v3.29.0 it divided by nEpochs, which
        %   understated the sigmas of any series holding NaN months).
        %
        %   G = ts.mean(Range = [t1 t2]) averages only the epochs with
        %   t1 <= t <= t2, given as decimal years or as a 1 x 2 datetime.
        %   Identical to ts.select(Range = [t1 t2]).mean(), in one call.
        %
        %   [G, INFO] = ts.mean(Range = [t1 t2], Estimator = "model")
        %   instead fits bias / trend / annual / semi-annual (+Periods) to
        %   the epochs inside the window, with the reference epoch AT the
        %   window centre, and returns the exact time integral of that
        %   model over [t1 t2]. Because the reference epoch is the centre,
        %   the integral collapses to
        %
        %       mean = bias + sum_k s(P_k) * cos_k,
        %       s(P) = sin(pi*D/P) / (pi*D/P),   D = t2 - t1,
        %
        %   the model at the window centre with every harmonic damped by a
        %   sinc factor (returned in INFO.attenuation). For a whole number
        %   of years s = 0 exactly, so the period mean is the trend line at
        %   the centre - whatever the phase of the annual signal, and
        %   wherever the gaps sit.
        %
        %   Which estimator: on a completely sampled window the two agree
        %   to round-off, and "arithmetic" is the cheaper and more robust
        %   choice. On an unevenly covered window the arithmetic mean
        %   carries the trend and annual signal of whichever epochs
        %   survived - 0.069 of a 1.2 annual amplitude for a single
        %   6-month block missing out of six years, and INFO.centroidOffset
        %   times the trend for the trend part. Voronoi time-weighting was
        %   tested as a third option and rejected: it never won and lost by
        %   4x across the 2017-2018 mission gap, because the two epochs
        %   bracketing a gap each collect half a year of weight
        %   (tools/dev/validate_meanperiod.py holds the measured table).
        %
        %   The epoch attached to G is the epoch centroid of the averaged
        %   months for "arithmetic" - which is the epoch that estimator
        %   actually refers to once a trend is present - and the window
        %   centre for "model".
        %
        %   Options
        %     Range ([])         (1 x 2) double decimal years [t1 t2], or a
        %         1 x 2 datetime; [] uses the full series
        %     Estimator ("arithmetic")  (1 x 1) string, "arithmetic" (equal
        %         weights) or "model" (fit and integrate, see above)
        %     Periods (double.empty(1,0))  (1 x K) double extra harmonic
        %         periods [yr] for Estimator = "model", beyond the built-in
        %         annual and semi-annual - e.g. 161/365.25 for the S2 alias
        %     Omitnan (true)     (1 x 1) logical, ignore NaN coefficients
        %         ("arithmetic") or drop NaN epochs ("model"); false makes
        %         a NaN month poison the result / raise shSeries:stack:nanInSeries
        %     MinEpochs (1)      (1 x 1) double, minimum number of epochs
        %         inside the window; below it the call errors
        %
        %   Outputs
        %     g          (1 x 1) shCoefficients   mean field over the window,
        %         with sigmas (scatter-based for "arithmetic", propagated
        %         through the fit for "model")
        %     info       (1,1) struct   fields
        %         estimator       (1,1) string   which estimator ran
        %         range           (1,2) double   the window requested
        %         nUsed           (1,1) double   epochs that contributed
        %         nTotal          (1,1) double   epochs in the series
        %         nDropped        (1,1) double   epochs dropped as empty
        %         span            (1,2) double   first and last epoch used
        %         coverage        (1,1) double   used*dt / window length,
        %                         capped at 1; NaN below two epochs
        %         maxGapYears     (1,1) double   largest gap between two
        %                         used epochs; NaN below two epochs
        %         centroidOffset  (1,1) double   mean(used) minus the
        %                         window centre - how lopsided the sample
        %                         is
        %         epoch           (1,1) double   the epoch stamped on the
        %                         returned field
        %         attenuation     (K+2 x 2) double  [period factor];
        %                         Estimator="model" only
        %
        %   Example
        %     gBase = ts.mean(Range = [2004 2010]);
        %     [gGap, info] = ts.mean(Range = [2015 2021], Estimator = "model");
        %
        %   Error identifiers
        %     shSeries:range:badRange
        %         Range= is not [t1 t2] with t2 > t1 (decimal years or datetime)
        %     shSeries:mean:emptyRange
        %         no epoch falls inside Range=
        %     shSeries:stack:nanInSeries
        %         Estimator="model" on stacks that carry NaN - fill or drop the gap
        %         epochs first. The `stack` segment marks a check shared by
%         several methods, so it stays stable if the private helper
%         behind it is renamed
        %     shSeries:mean:noEpoch
        %         Estimator="model" needs a finite epoch on every entry
        %     shSeries:mean:sparseWindow
        %         warning - Estimator="model" and the window is less than half
        %         covered by epochs
        %     shSeries:mean:tooFewEpochs
        %         the window holds fewer than MinEpochs epochs, or fewer than the
        %         deterministic model has parameters
        %
        %   See also select, climatology, at
        arguments
            obj
            opts.Range = []
            opts.Estimator (1,1) string ...
                {mustBeMember(opts.Estimator, ["arithmetic", "model"])} = "arithmetic"
            opts.Periods (1,:) double = double.empty(1,0)
            opts.Omitnan (1,1) logical = true
            opts.MinEpochs (1,1) double {mustBePositive} = 1
        end
        hasRange = ~isempty(opts.Range);
        if hasRange
            rg = rangeToYears(opts.Range);
            keep = find(obj.epochs(:)' >= rg(1) & obj.epochs(:)' <= rg(2));
            if isempty(keep)
                error('shSeries:mean:emptyRange', ...
                    ['No epoch falls in [%.4f %.4f]; the series spans ' ...
                     '%.4f to %.4f.'], rg(1), rg(2), ...
                    min(obj.epochs), max(obj.epochs));
            end
            sub = obj.select(keep);
        else
            sub = obj;
            rg = [min(obj.epochs), max(obj.epochs)];
        end

        nDropped = 0;
        if opts.Estimator == "model"
            if isempty(sub.epochs) || any(~isfinite(sub.epochs))
                error('shSeries:mean:noEpoch', ...
                    'Estimator="model" requires a finite epoch for every entry.');
            end
            if opts.Omitnan
                before = sub.nEpochs;
                sub = sub.dropNaN();
                nDropped = before - sub.nEpochs;
            else
                sub.assertClean('mean(Estimator="model")');
            end
        end
        if sub.nEpochs < opts.MinEpochs
            error('shSeries:mean:tooFewEpochs', ...
                'The window holds %d epoch(s), MinEpochs = %d.', ...
                sub.nEpochs, opts.MinEpochs);
        end

        atten = double.empty(0, 2);
        if opts.Estimator == "arithmetic"
            if opts.Omitnan, flag = 'omitnan'; else, flag = 'includenan'; end
            Cm = mean(sub.Cs, 3, flag);
            Sm = mean(sub.Ss, 3, flag);
            if opts.Omitnan
                nC = sum(~isnan(sub.Cs), 3);
                nS = sum(~isnan(sub.Ss), 3);
            else
                nC = repmat(sub.nEpochs, size(Cm));
                nS = repmat(sub.nEpochs, size(Sm));
            end
            % the standard error of the mean divides by the number of
            % values that actually entered it, per coefficient
            sc = std(sub.Cs, 0, 3, flag) ./ sqrt(max(nC, 1));
            ss = std(sub.Ss, 0, 3, flag) ./ sqrt(max(nS, 1));
            sc(nC < 2) = NaN;      % std of one sample is 0, not a sigma
            ss(nS < 2) = NaN;
            ep = mean(sub.epochs, 'omitnan');
        else
            nPar = 6 + 2 * numel(opts.Periods);
            if sub.nEpochs < nPar
                error('shSeries:mean:tooFewEpochs', ...
                    ['Estimator="model" needs >= %d epochs inside the ' ...
                     'window for %d parameters (got %d).'], ...
                    nPar, nPar, sub.nEpochs);
            end
            tm = 0.5 * (rg(1) + rg(2));
            D = rg(2) - rg(1);
            X = sub.flatten();                          % (2*Nc) x T
            [~, ~, coef, A, ~, resVar] = shLowLevel.fitDeterministicModel( ...
                X, sub.epochs, T0 = tm, Periods = opts.Periods);
            pers = [1, 0.5, opts.Periods];
            sFac = sincPi(D ./ pers);
            u = zeros(1, nPar);                         % integral weights
            u(1) = 1;                                   % bias
            u(3:2:end) = sFac;                          % cosine terms
            Xm = u * coef;                              % 1 x (2*Nc)
            q = u / (A.' * A) * u.';                    % cofactor of the mean
            Xs = sqrt(max(resVar, 0) * max(q, 0));
            Nc = (sub.nmax + 1)^2; n1 = sub.nmax + 1;
            Cm = reshape(Xm(1:Nc), n1, n1);
            Sm = reshape(Xm(Nc+1:end), n1, n1);
            sc = reshape(Xs(1:Nc), n1, n1);
            ss = reshape(Xs(Nc+1:end), n1, n1);
            ep = tm;
            atten = [pers(:), sFac(:)];
        end

        info = meanWindowInfo(sub, rg, obj.nEpochs, nDropped, ...
            opts.Estimator, ep, atten);
        if opts.Estimator == "model" && info.coverage < 0.5
            warning('shSeries:mean:sparseWindow', ...
                ['Estimator="model": the window is %.0f%% covered ' ...
                 '(largest gap %.2f yr) - the model is extrapolating.'], ...
                100 * info.coverage, info.maxGapYears);
        end

        if hasRange || opts.Estimator ~= "arithmetic"
            nameStr = sprintf("mean(%s, %.3f-%.3f)", obj.productType, ...
                rg(1), rg(2));
            note = sprintf("%s mean over [%.4f %.4f] from %d epochs", ...
                opts.Estimator, rg(1), rg(2), sub.nEpochs);
        else
            nameStr = "mean(" + obj.productType + ")";
            note = sprintf("mean of %d epochs", sub.nEpochs);
        end
        g = shCoefficients(Cm, Sm, SigmaC = sc, SigmaS = ss, GM = obj.GM, ...
            R = obj.R, Epoch = ep, ProductType = obj.productType, ...
            Name = nameStr, History = [obj.history; note]);
    end

    function [clim, resid] = climatology(obj, opts)
        %CLIMATOLOGY Bias/trend/annual/semi-annual (+extra periods) fit.
        %   [CLIM, RESID] = ts.climatology(Robust=false, T0 (NaN)=mean(epochs),
        %       Periods (double.empty(1,0))=[], Weights ([])=[])
        %   CLIM is an shClimatology; RESID the residual shSeries.
        %   Periods: extra periodic terms [years] - e.g. the GRACE tidal
        %   alias periods [161/365.25, 3.66, 7.48] (S2, K2, K1); without
        %   them, trend and semi-annual estimates absorb tidal aliasing.
        %   Weights: T x 1 per-epoch weights (e.g. 1./info.vce from the
        %   tvANS filter). CLIM carries per-coefficient 1-sigma
        %   significance (OLS formula, Monte-Carlo validated); component
        %   accessors return shCoefficients WITH sigmas, enabling
        %   significance-masked trend maps. Requires >= 6+2K epochs and
        %   NaN-free stacks (use dropNaN/select across the 2017-2018 gap).
        %   Options
        %     Robust (false)    (1 x 1) logical Huber re-weighting
        %     T0 (NaN)          (1 x 1) reference epoch; NaN uses the mean
        %     Periods ([])      (1 x K) extra harmonic periods [yr] beyond
        %         the built-in annual + semiannual
        %     Weights ([])      (T x 1) epoch weights
        %     ARCorrect (false) (1 x 1) AR(1) correction of the sigmas
        %
        %   Outputs
        %     clim       (1 x 1) shClimatology   fitted bias/trend/annual/semiannual (+Periods=) with coefficient sigmas
        %     resid      (1 x 1) shSeries   residual series about the fit
        %
        %   Error identifiers
        %     shSeries:stack:nanInSeries
        %         the stacks carry NaN - fill or drop the gap epochs first (raised
        %         by the shared stack check)
        %     shSeries:climatology:noEpoch
        %         climatology needs a finite epoch on every entry
        %     shSeries:climatology:tooFewEpochs
        %         fewer epochs than the climatology model has parameters
        %
        arguments
            obj
            opts.Robust (1,1) logical = false
            opts.T0 (1,1) double = NaN
            opts.Periods (1,:) double = double.empty(1,0)
            opts.Weights (:,1) double = []
            opts.ARCorrect (1,1) logical = false
        end
        obj.assertClean('climatology');
        if any(~isfinite(obj.epochs))
            error('shSeries:climatology:noEpoch', ...
                'climatology requires finite epochs for every entry.');
        end
        nPar = 6 + 2*numel(opts.Periods);
        if obj.nEpochs < nPar
            error('shSeries:climatology:tooFewEpochs', ...
                'climatology needs >= %d epochs for %d parameters (got %d).', ...
                nPar, nPar, obj.nEpochs);
        end
        t0 = opts.T0;
        if isnan(t0), t0 = mean(obj.epochs); end
        X = obj.flatten();                             % (2*Nc) x T
        [~, XresX, coef, ~, coefSigma] = shLowLevel.fitDeterministicModel( ...
            X, obj.epochs, Robust = opts.Robust, T0 = t0, ...
            Periods = opts.Periods, Weights = opts.Weights, ...
            ARCorrect = opts.ARCorrect);
        clim = shClimatology.fromCoef(coef, t0, obj, ...
            Periods = opts.Periods, CoefSigma = coefSigma);
        resid = obj;
        [resid.Cs, resid.Ss] = obj.unflatten(XresX);
        if opts.ARCorrect
            clim = clim.withNote( ...
                "coefficient sigmas AR(1)-corrected (sqrt((1+r1)/(1-r1)))");
        end
        if isempty(opts.Periods)
            resid.history(end+1) = "climatology removed (bias/trend/annual/semi-annual)";
        else
            resid.history(end+1) = sprintf( ...
                "climatology removed (+%d extra periods)", numel(opts.Periods));
        end
    end

    function out = trendBreaks(obj, opts)
        %TRENDBREAKS Piecewise-linear trends with break significance.
        %   OUT = ts.trendBreaks(Breaks=[2016.0], Periods (double.empty(1,0))=[], T0 (NaN)=,
        %       ARCorrect (false)=false) fits the standard climatology design
        %   PLUS hinge terms max(0, t - tb) per break epoch (continuous
        %   piecewise-linear trend) to every coefficient, and tests the
        %   break's significance with an F-test against the no-break
        %   model (p-values via betainc - base MATLAB, no toolbox).
        %   Python-validated: 5.1% null rejection at the 5% level;
        %   F = 23 for a 0.02/yr break in 0.05-sigma noise (T = 120).
        %
        %   Returns a plain struct, not an shClimatology - the
        %   climatology schema stays fixed. See Outputs for the fields.
        %   Options
        %     Breaks (required) (1 x B) trend break epochs [decimal years]
        %     Periods ([])      (1 x K) extra harmonic periods [yr]
        %     T0 (NaN)          (1 x 1) reference epoch; NaN uses the mean
        %     ARCorrect (false) (1 x 1) AR(1) correction of the sigmas
        %
        %   Outputs
        %     out  (1,1) struct  NOT an shCoefficients - the coefficient
        %          matrices are plain (n1 x n1) doubles - fields
        %          breaks              (1 x B) double  the break epochs, as
        %                              given [decimal years]
        %          t0                  (1,1) double  reference epoch used
        %          trend1C, trend1S    (n1 x n1) double  pre-break rate
        %                              [units/yr], cosine and sine
        %          sigmaTrend1C, sigmaTrend1S  (n1 x n1) double  their
        %                              1-sigma
        %          hingeC, hingeS      (n1 x n1 x B) double  rate CHANGE at
        %                              each break; the post-break rate is
        %                              trend1 + cumsum over the hinges
        %          sigmaHingeC, sigmaHingeS  (n1 x n1 x B) double  1-sigma
        %                              of the rate changes
        %          trendNoBreakC       (n1 x n1) double  rate of the
        %                              no-break model, the F-test's null
        %          sigmaTrendNoBreakC  (n1 x n1) double  its 1-sigma
        %          F, pValue           (n1 x n1) double  F statistic and
        %                              p-value per cosine coefficient
        %          FS, pValueS         (n1 x n1) double  the same for the
        %                              sine coefficients
        %
        %   Error identifiers
        %     shSeries:trendBreaks:noBreaks
        %         Breaks= is empty; trendBreaks needs at least one break epoch
        %
        arguments
            obj
            opts.Breaks (1,:) double
            opts.Periods (1,:) double = double.empty(1,0)
            opts.T0 (1,1) double = NaN
            opts.ARCorrect (1,1) logical = false
        end
        assert(~isempty(opts.Breaks), 'shSeries:trendBreaks:noBreaks', ...
            'trendBreaks needs at least one break epoch.');
        t0 = opts.T0;
        if isnan(t0), t0 = mean(obj.epochs); end
        n1 = obj.nmax + 1; Nc = n1^2; T = obj.nEpochs;
        X = [reshape(obj.Cs, Nc, T); reshape(obj.Ss, Nc, T)];
        K = numel(opts.Breaks);
        nP = numel(opts.Periods);
        [~, Xr1, c1, ~, cs1] = shLowLevel.fitDeterministicModel(X, obj.epochs, ...
            T0 = t0, Periods = opts.Periods, ARCorrect = opts.ARCorrect);
        [~, XrB, cB, ~, csB] = shLowLevel.fitDeterministicModel(X, obj.epochs, ...
            T0 = t0, Periods = opts.Periods, Breaks = opts.Breaks, ...
            ARCorrect = opts.ARCorrect);
        ss0 = sum(Xr1.^2, 2); ss1 = sum(XrB.^2, 2);
        d2 = T - (6 + 2*nP + K);
        F = max((ss0 - ss1) / K, 0) ./ max(ss1 / max(d2, 1), realmin);
        % p = 1 - Fcdf(F; K, d2) via the regularized incomplete beta
        pv = betainc(d2 ./ (d2 + K * F), d2/2, K/2);
        rowH = 6 + 2*nP + (1:K);
        out = struct('breaks', opts.Breaks, 't0', t0, ...
            'trend1C', reshape(cB(2, 1:Nc), n1, n1), ...
            'trend1S', reshape(cB(2, Nc+1:end), n1, n1), ...
            'sigmaTrend1C', reshape(csB(2, 1:Nc), n1, n1), ...
            'sigmaTrend1S', reshape(csB(2, Nc+1:end), n1, n1), ...
            'trendNoBreakC', reshape(c1(2, 1:Nc), n1, n1), ...
            'sigmaTrendNoBreakC', reshape(cs1(2, 1:Nc), n1, n1), ...
            'hingeC', zeros(n1, n1, K), 'hingeS', zeros(n1, n1, K), ...
            'sigmaHingeC', zeros(n1, n1, K), 'sigmaHingeS', zeros(n1, n1, K), ...
            'F', zeros(n1, n1), 'pValue', zeros(n1, n1));
        for k = 1:K
            out.hingeC(:, :, k) = reshape(cB(rowH(k), 1:Nc), n1, n1);
            out.hingeS(:, :, k) = reshape(cB(rowH(k), Nc+1:end), n1, n1);
            out.sigmaHingeC(:, :, k) = reshape(csB(rowH(k), 1:Nc), n1, n1);
            out.sigmaHingeS(:, :, k) = reshape(csB(rowH(k), Nc+1:end), n1, n1);
        end
        out.F = reshape(F(1:Nc), n1, n1);
        out.pValue = reshape(pv(1:Nc), n1, n1);
        out.FS = reshape(F(Nc+1:end), n1, n1);
        out.pValueS = reshape(pv(Nc+1:end), n1, n1);
    end

    function out = fan(obj, rDegKm, rOrdKm)
        %FAN Han fan filter on every epoch (degree x order Gaussian).
        %   OUT = ts.fan(RDEG, RORD)  - see shLowLevel.shFanFilter.
        %
        %   Inputs
        %     rOrdKm  (1,1) double  fan filter order-direction radius [km]
        %     rDegKm  (1,1) double  fan filter degree-direction radius [km]
        %   Outputs
        %     out        (1 x 1) shSeries   fan-filtered per month
        %
        arguments
            obj
            rDegKm (1,1) double {mustBePositive}
            rOrdKm (1,1) double {mustBePositive}
        end
        out = obj;
        for k = 1:obj.nEpochs
            [out.Cs(:,:,k), out.Ss(:,:,k)] = shLowLevel.shFanFilter( ...
                obj.Cs(:,:,k), obj.Ss(:,:,k), rDegKm, rOrdKm, R = obj.R);
        end
        if ~isempty(out.sigmaCs)
            Wn = shLowLevel.shGaussianWeights(obj.nmax, rDegKm, R = obj.R/1e3);
            Wm = shLowLevel.shGaussianWeights(obj.nmax, rOrdKm, R = obj.R/1e3);
            Wmat = Wn(:) .* Wm(:)';
            for k = 1:obj.nEpochs
                out.sigmaCs(:,:,k) = obj.sigmaCs(:,:,k) .* Wmat;
                out.sigmaSs(:,:,k) = obj.sigmaSs(:,:,k) .* Wmat;
            end
        end
        out.history(end+1) = sprintf( ...
            "fan filtered (deg %g km, ord %g km)", rDegKm, rOrdKm);
    end

    function out = applyTN14(obj, tn, opts)
        %APPLYTN14 Replace C20 (and flagged C30) per month from TN-14.
        %   OUT = ts.applyTN14("TN-14.txt") - series-level convenience
        %   around shCoefficients.applyTN14 (v2.4.1; the per-month epoch
        %   selects the TN entry). All options pass through.
        %   Outputs
        %     out        (1 x 1) shSeries   C20/C30 replaced epoch-matched
        %
        %   Options
        %     Tolerance (0.05)  maximum |epoch difference| [yr] accepted
        %         when matching a table entry to this epoch
        %     ReplaceC30 ("auto")  "auto" (replace when the table has a
        %         non-NaN C30 for that month) | "never" | "always"
        %
        arguments
            obj
            tn
            opts.Tolerance (1,1) double = 0.05
            opts.ReplaceC30 (1,1) string = "auto"
        end
        arr = shCoefficients.empty(0, 1);
        for k = 1:obj.nEpochs
            g = obj.at(k);
            arr(k, 1) = g.applyTN14(tn, Tolerance = opts.Tolerance, ...
                ReplaceC30 = opts.ReplaceC30);
        end
        out = shSeries(arr);
    end

    function out = addDegree1(obj, tn, opts)
        %ADDDEGREE1 Insert TN-13 geocenter degree-1 per month.
        %   OUT = ts.addDegree1("TN-13.txt") - series-level convenience
        %   around shCoefficients.addDegree1 (v2.4.1).
        %   Outputs
        %     out        (1 x 1) shSeries   degree 1 completed epoch-matched
        %
        %   Options
        %     Tolerance (0.05)  maximum |epoch difference| [yr] accepted
        %         when matching a table entry to this epoch
        %
        arguments
            obj
            tn
            opts.Tolerance (1,1) double = 0.05
        end
        arr = shCoefficients.empty(0, 1);
        for k = 1:obj.nEpochs
            g = obj.at(k);
            arr(k, 1) = g.addDegree1(tn, Tolerance = opts.Tolerance);
        end
        out = shSeries(arr);
    end

    function out = removeAlias(obj, opts)
        %REMOVEALIAS Remove a tidal alias harmonic from every epoch.
        %   TS2 = ts.removeAlias() fits, per coefficient, a harmonic at
        %   the S2 tidal alias period (161 days) TOGETHER WITH bias,
        %   trend, annual and semi-annual, and subtracts only that
        %   harmonic. This is the correction GravIS applies to its
        %   Level-2B products (https://gravis.gfz.de/corrections):
        %   errors in the ocean-tide background model alias into the
        %   monthly fields at this period, and leaving them in puts a
        %   spurious ~161-day signal into every derived series.
        %
        %   Fitting the alias jointly with the deterministic terms
        %   matters: fitted alone it absorbs part of the trend and the
        %   annual cycle, and subtracting that would damage both.
        %
        %   PHASE OFFSET. Across the GRACE / GRACE-FO boundary the nodal
        %   planes are not aligned, so one harmonic cannot describe both
        %   missions. Landerer et al. (2020) prescribe a fixed 100 degree
        %   offset for the later mission; PhaseOffset/SplitEpoch apply
        %   it. The offset is FIXED, so the model gains no free
        %   parameters - it only gains the ability to fit both spans.
        %   Ignoring it mis-estimates the amplitude badly (validated in
        %   tools/dev/validate_alias.py: 0.41 error on a unit-scale
        %   synthetic). On a series that lies entirely on one side of
        %   SplitEpoch the offset has no effect.
        %
        %   Inputs
        %     (none beyond the object)
        %
        %   Options
        %     Period (161/365.25)  alias period [years]. The default is
        %             the S2 alias; the K2 and K1 aliases (3.66 and 7.48
        %             years) are longer than most records and are better
        %             handled as climatology Periods
        %     PhaseOffset (100)  phase offset [degrees] applied to epochs
        %             at or after SplitEpoch
        %     SplitEpoch (2018.0)  mission boundary [decimal year]; the
        %             GRACE-FO record starts mid-2018
        %     T0 (NaN)  reference epoch of the fit (NaN: the mean epoch)
        %
        %   Outputs
        %     out        (1,1) shSeries  copy with the alias harmonic
        %                removed from every epoch; the operation is
        %                appended to the history
        %
        %   Example
        %     ts = ts.removeAlias();                   % S2, 100 deg offset
        %     ts = ts.removeAlias(SplitEpoch = 2018.4);
        %
        %   Error identifiers
        %     shSeries:stack:nanInSeries
        %         the stacks carry NaN - fill or drop the gap epochs first (raised
        %         by the shared stack check)
        %     shSeries:removeAlias:noEpoch
        %         removeAlias needs a finite epoch on every entry
        %     shSeries:removeAlias:tooShort
        %         the series is too short, too sparse or rank deficient to separate
        %         the alias period from the seasonal terms
        %
        %   See also shSeries.climatology, shLowLevel.standardChain.
        %
        %   Developed by Matthias Weigelt with the help of Claude
        %   (Opus 5), 2026-08-11 (v3.4.0).
        arguments
            obj
            opts.Period (1,1) double {mustBePositive} = 161/365.25
            opts.PhaseOffset (1,1) double = 100
            opts.SplitEpoch (1,1) double = 2018.0
            opts.T0 (1,1) double = NaN
        end
        obj.assertClean('removeAlias');
        t = obj.epochs(:);
        if any(~isfinite(t))
            error('shSeries:removeAlias:noEpoch', ...
                'removeAlias requires finite epochs for every entry.');
        end
        t0 = opts.T0;
        if ~isfinite(t0), t0 = mean(t); end
        w = 2 * pi;
        a = w * t / opts.Period + deg2rad(opts.PhaseOffset) * ...
            (t >= opts.SplitEpoch);
        A = [ones(numel(t), 1), t - t0, cos(w*t), sin(w*t), ...
             cos(2*w*t), sin(2*w*t), cos(a), sin(a)];
        % A short record does NOT show up as rank deficiency or bad
        % conditioning - a one-year span gives a full-rank design with a
        % condition number of 38, and a fit that means nothing. The real
        % requirements are degrees of freedom and enough alias cycles to
        % separate the harmonic from the seasonal terms.
        nPar = size(A, 2);
        span = max(t) - min(t);
        if numel(t) < 2 * nPar || span < 2 * opts.Period || rank(A) < nPar
            error('shSeries:removeAlias:tooShort', ...
                ['%d epochs spanning %.2f yr cannot support the ' ...
                 '%d-term fit (bias, trend, annual, semi-annual, ' ...
                 'alias). At least %d epochs and %.2f yr (two alias ' ...
                 'periods) are required, and in practice several years ' ...
                 'are needed before the estimate is stable.'], ...
                numel(t), span, nPar, 2 * nPar, 2 * opts.Period);
        end
        n1 = obj.nmax + 1;
        Y = [reshape(obj.Cs, [], obj.nEpochs); ...
             reshape(obj.Ss, [], obj.nEpochs)].';      % T x 2*n1^2
        coef = A \ Y;
        alias = A(:, 7:8) * coef(7:8, :);              % ONLY the harmonic
        Z = (Y - alias).';
        out = obj;
        out.Cs = reshape(Z(1:n1^2, :), n1, n1, obj.nEpochs);
        out.Ss = reshape(Z(n1^2+1:end, :), n1, n1, obj.nEpochs);
        out.history(end+1) = sprintf( ...
            "alias removed (%.1f d, %.0f deg offset from %.2f)", ...
            opts.Period * 365.25, opts.PhaseOffset, opts.SplitEpoch);
    end

    function [out, info] = removeGIA(obj, gia, opts)
        %REMOVEGIA Subtract a glacial isostatic adjustment model.
        %   OUT = ts.removeGIA(GIA, T0 (NaN)=mean(epochs)) subtracts the linear
        %   GIA signal  giaRate * (t - T0)  from every epoch. GIA is an
        %   shCoefficients object holding RATE coefficients [1/yr] - read
        %   your model (ICE-6G_D, Caron et al., ...) from its gfc file
        %   with shCoefficients.read; models are ALWAYS user-supplied,
        %   never embedded. Trends computed after this are GIA-corrected.
        %   The GIA model is truncated to the series nmax; a model with
        %   smaller nmax is zero-padded with a note in history.
        %
        %   [OUT, INFO] = ts.removeGIA(GIA, Sigma ([])=SIG) also PROPAGATES the
        %   model's own uncertainty (v5.2.0). Until v5.1.1 the model was
        %   treated as exact, which understated the trend error wherever
        %   GIA dominates it - Laurentia, Fennoscandia, Antarctica. SIG is
        %   an shCoefficients holding the per-coefficient 1-sigma of the
        %   RATE [1/yr] (an ensemble spread, e.g. Caron et al. 2018); when
        %   Sigma is not given, GIA.sigmaC/sigmaS are used if it carries
        %   them, and nothing is propagated if it does not.
        %
        %   WHAT IS ADDED, AND WHAT IT IS NOT
        %     Per epoch the model contributes  sigmaRate * (t_k - T0)  in
        %     quadrature to the coefficient sigmas, so OUT.sigmaCs/sigmaSs
        %     are correct MARGINAL per-epoch sigmas and feed
        %     shLowLevel.mcPropagate (via ts.at(k)) and every consumer of
        %     the sigma stacks unchanged.
        %     They are NOT enough for a trend. One rate error applies to
        %     EVERY epoch, so the GIA component is perfectly CORRELATED in
        %     time, and a trend fitted from per-epoch sigmas that assumes
        %     independence understates it - by roughly sqrt(nEpochs). The
        %     GIA contribution to a RATE is simply sigmaRate itself, which
        %     is why INFO returns it: add INFO.rateSigmaC/rateSigmaS to a
        %     fitted trend's sigma rather than deriving it from OUT.
        %     A series that carried NO sigmas gets stacks holding the GIA
        %     term ALONE; history says so, so they are not mistaken for
        %     full formal errors.
        %
        %   Inputs
        %     gia  GIA rate field: shCoefficients, coefficient struct or
        %          .gz/.gfc file path (subtracted as rate times (t - Epoch))
        %
        %   Options
        %     T0 (NaN)      reference epoch of the linear model; the series
        %          mean epoch when not given
        %     Sigma ([])    shCoefficients of per-coefficient 1-sigma RATE
        %          uncertainties [1/yr]; defaults to gia's own sigmaC/sigmaS
        %
        %   Outputs
        %     out        (1 x 1) shSeries   GIA trend removed about the series mean epoch
        %     info       (1 x 1) struct   what was propagated, fields
        %                t0            (1,1) double  reference epoch used
        %                rateSigmaC    (n1 x n1) double  rate 1-sigma, cosine
        %                rateSigmaS    (n1 x n1) double  rate 1-sigma, sine
        %                propagated    (1,1) logical  false when no sigma
        %                              was available and none was added
        %                sigmaWasEmpty (1,1) logical  the series carried no
        %                              sigmas, so the stacks hold the GIA
        %                              term alone
        %                correlated    (1,1) logical  always true - the GIA
        %                              term is fully correlated across
        %                              epochs; see the note above
        %
        %   Error identifiers
        %     shSeries:removeGIA:badSigma
        %         Sigma is not square or does not match gia in size
        %
        arguments
            obj
            gia (1,1) shCoefficients
            opts.T0 (1,1) double = NaN
            opts.Sigma = []
        end
        t0 = opts.T0;
        if isnan(t0), t0 = mean(obj.epochs); end
        n1 = obj.nmax + 1;
        gC = zeros(n1); gS = zeros(n1);
        nc = min(n1, size(gia.C, 1));
        gC(1:nc, 1:nc) = gia.C(1:nc, 1:nc);
        gS(1:nc, 1:nc) = gia.S(1:nc, 1:nc);

        % rate sigmas: explicit Sigma wins, else the model's own
        sC = []; sS = [];
        if ~isempty(opts.Sigma)
            sig = opts.Sigma;
            if ~isa(sig, 'shCoefficients')
                error('shSeries:removeGIA:badSigma', ...
                    'Sigma must be an shCoefficients of rate uncertainties.');
            end
            if size(sig.C, 1) ~= size(sig.C, 2) || ...
                    size(sig.C, 1) ~= size(gia.C, 1)
                error('shSeries:removeGIA:badSigma', ...
                    ['Sigma is %dx%d but the GIA model is %dx%d; they must ' ...
                     'match.'], size(sig.C, 1), size(sig.C, 2), ...
                    size(gia.C, 1), size(gia.C, 2));
            end
            sC = sig.C; sS = sig.S;
        elseif ~isempty(gia.sigmaC)
            sC = gia.sigmaC; sS = gia.sigmaS;
        end

        out = obj;
        for k = 1:obj.nEpochs
            dt = obj.epochs(k) - t0;
            out.Cs(:, :, k) = obj.Cs(:, :, k) - gC * dt;
            out.Ss(:, :, k) = obj.Ss(:, :, k) - gS * dt;
        end
        out.history(end+1) = sprintf( ...
            "GIA removed (model nmax=%d, T0=%.4f)", ...
            min(size(gia.C, 1) - 1, obj.nmax), t0);
        if nc < n1
            out.history(end+1) = sprintf( ...
                "GIA model zero-padded above degree %d", nc - 1);
        end

        rC = zeros(n1); rS = zeros(n1);
        emptyBefore = isempty(obj.sigmaCs);
        if isempty(sC)
            out.history(end+1) = ...
                "GIA rate applied as EXACT - no model sigma was supplied";
        else
            ns = min(n1, size(sC, 1));
            rC(1:ns, 1:ns) = sC(1:ns, 1:ns);
            rS(1:ns, 1:ns) = sS(1:ns, 1:ns);
            if emptyBefore
                out.sigmaCs = zeros(n1, n1, obj.nEpochs);
                out.sigmaSs = zeros(n1, n1, obj.nEpochs);
            end
            for k = 1:obj.nEpochs
                dt = obj.epochs(k) - t0;
                out.sigmaCs(:, :, k) = sqrt(out.sigmaCs(:, :, k).^2 ...
                    + (rC * dt).^2);
                out.sigmaSs(:, :, k) = sqrt(out.sigmaSs(:, :, k).^2 ...
                    + (rS * dt).^2);
            end
            if emptyBefore
                out.history(end+1) = ...
                    "sigma stacks hold the GIA term ALONE (series had none)";
            else
                out.history(end+1) = ...
                    "GIA rate sigma added in quadrature per epoch";
            end
            out.history(end+1) = ...
                "GIA sigma is FULLY CORRELATED across epochs - use " + ...
                "info.rateSigmaC/S for a trend, not the per-epoch stacks";
        end
        info = struct('t0', t0, 'rateSigmaC', rC, 'rateSigmaS', rS, ...
            'propagated', ~isempty(sC), ...
            'sigmaWasEmpty', emptyBefore && ~isempty(sC), ...
            'correlated', true);
    end

    function out = applyDDK(obj, W)
        %APPLYDDK Apply a DDK decorrelation filter to every epoch.
        %   OUT = ts.applyDDK(W), W from shLowLevel.readDDK. Sigma stacks are
        %   invalidated (NaN) - the filter correlates coefficients.
        %   Outputs
        %     out        (1 x 1) shSeries   DDK-decorrelated per month
        %
        arguments
            obj
            W
        end
        W = shLowLevel.readDDK(W);
        out = obj;
        for k = 1:obj.nEpochs
            [out.Cs(:, :, k), out.Ss(:, :, k)] = ...
                shLowLevel.applyDDK(obj.Cs(:, :, k), obj.Ss(:, :, k), W);
        end
        out.sigmaCs = []; out.sigmaSs = [];
        out.history(end+1) = sprintf("DDK filter applied (%s)", W.name);
    end

    % --------------------------------------------------------- GAX restore
    function [rep, h] = compare(obj, others, varargin)
        %COMPARE Temporal comparison against other series (v2.6.0).
        %   REP = ts.compare(TS2) or ts.compare({TS2, TS3, ...})
        %   delegates to shLowLevel.compareSeries with OBJ as the reference;
        %   all options pass through (Basin=, Names=, Plot=, ...).
        %
        %   Inputs
        %     others  shSeries or cell of shSeries  series to compare; OBJ is the reference
        %   Outputs
        %     rep        (1,1) struct   as returned by
        %                shLowLevel.compareSeries, which documents every
        %                field
        %     h          (1 x 1) graphics handle   figure (Plot = true)
        %
        if ~iscell(others), others = {others}; end
        [rep, h] = shLowLevel.compareSeries([{obj}, others], varargin{:});
    end

    function out = restore(obj, gax, opts)
        %RESTORE Add a background (GAA/GAB/GAC/GAD) series, epoch-matched.
        %   OUT = ts.restore(GAXSERIES, Tolerance=0.05, AllowMissing=false)
        %   Each epoch of OBJ is matched to the nearest GAX epoch within
        %   Tolerance [yr]. Missing matches error (or, with
        %   AllowMissing=true, leave those epochs unchanged with a note).
        %   Inputs
        %     gax  GAX product to add back: shSeries, folder of monthly
        %          .gfc, or file list (epoch-matched)
        %
        %   Outputs
        %     out        (1 x 1) shSeries   background model added back epoch-matched (e.g. GSM + GAD)
        %
        %   Error identifiers
        %     shSeries:restore:epochMismatch
        %         no GAX epoch lies within Tolerance of a series epoch and
        %         AllowMissing is false
        %     shSeries:restore:sizeMismatch
        %         nmax differs from the GAX field - truncate first
        %
        arguments
            obj
            gax (1,1) shSeries
            opts.Tolerance (1,1) double = 0.05
            opts.AllowMissing (1,1) logical = false
        end
        if obj.nmax ~= gax.nmax
            error('shSeries:restore:sizeMismatch', ...
                'nmax differs (%d vs %d) - truncate first.', obj.nmax, gax.nmax);
        end
        out = obj;
        nMissing = 0;
        for k = 1:obj.nEpochs
            [d, j] = min(abs(gax.epochs - obj.epochs(k)));
            if isfinite(d) && d <= opts.Tolerance
                out.Cs(:,:,k) = obj.Cs(:,:,k) + gax.Cs(:,:,j);
                out.Ss(:,:,k) = obj.Ss(:,:,k) + gax.Ss(:,:,j);
            elseif opts.AllowMissing
                nMissing = nMissing + 1;
            else
                error('shSeries:restore:epochMismatch', ...
                    'No %s epoch within %.3f yr of %.4f (epoch %d).', ...
                    gax.productType, opts.Tolerance, obj.epochs(k), k);
            end
        end
        out.productType = obj.productType + "+" + gax.productType;
        out.history(end+1) = sprintf("restored %s (%d/%d epochs matched)", ...
            gax.productType, obj.nEpochs - nMissing, obj.nEpochs);
    end

    % ----------------------------------------------------------- arithmetic
    function out = minus(a, b)
        %MINUS Subtract a field (shCoefficients) or an epoch-matched series.
        %
        %   Inputs
        %     b  (1,1) shSeries or shCoefficients  subtrahend (epoch-wise for series)
        %   Outputs
        %     out        (1 x 1) shSeries   per-month difference (series or single field)
        %
        %   Error identifiers
        %     shSeries:minus:badInput
        %         the right operand is neither an shCoefficients nor an shSeries
        %     shSeries:minus:epochMismatch
        %         series minus series needs matching epoch sets
        %     shSeries:minus:sizeMismatch
        %         the operands differ in nmax
        %
        if isa(b, 'shCoefficients')
            if a.nmax ~= b.nmax
                error('shSeries:minus:sizeMismatch', ...
                    'nmax differs (%d vs %d).', a.nmax, b.nmax);
            end
            out = a;
            out.Cs = a.Cs - b.C;
            out.Ss = a.Ss - b.S;
            out.history(end+1) = "subtracted field: " + b.name;
        elseif isa(b, 'shSeries')
            if a.nmax ~= b.nmax
                error('shSeries:minus:sizeMismatch', ...
                    'nmax differs (%d vs %d).', a.nmax, b.nmax);
            end
            if a.nEpochs ~= b.nEpochs || any(abs(a.epochs - b.epochs) > 0.05)
                error('shSeries:minus:epochMismatch', ...
                    'Series minus requires matching epoch sets.');
            end
            out = a;
            out.Cs = a.Cs - b.Cs; out.Ss = a.Ss - b.Ss;
            out.history(end+1) = "subtracted series (" + b.productType + ")";
        else
            error('shSeries:minus:badInput', 'Unsupported operand for minus.');
        end
    end

    % ------------------------------------------------------- classic chain
    function out = destripe(obj, opts)
        %DESTRIPE Swenson & Wahr / P3M6, applied per epoch.
        %   Outputs
        %     out        (1 x 1) shSeries   destriped per month
        %
        %   Options
        %     MinOrder (6)  lowest order to destripe; coefficients at
        %         m < minOrder pass through unchanged (below it the signal
        %         is real, not stripes)
        %     PolyOrder (3)  order of the polynomial fitted and removed
        %         per order/parity sequence
        %     WindowLength ([])  [] fits ONE polynomial over the whole
        %         sequence; an odd integer >= polyOrder+2 uses a centered
        %         moving window instead (WindowLength=6 with PolyOrder=3 is
        %         the common "P3M6" variant)
        %
        %   Error identifiers
        %     shSeries:stack:nanInSeries
        %         the stacks carry NaN - fill or drop the gap epochs first (raised
        %         by the shared stack check)
        %
        arguments
            obj
            opts.MinOrder (1,1) double = 6
            opts.PolyOrder (1,1) double = 3
            opts.WindowLength double = []
        end
        obj.assertClean('destripe');
        out = obj;
        for k = 1:obj.nEpochs
            [out.Cs(:,:,k), out.Ss(:,:,k)] = shLowLevel.shDestripe( ...
                obj.Cs(:,:,k), obj.Ss(:,:,k), 'MinOrder', opts.MinOrder, ...
                'PolyOrder', opts.PolyOrder, 'WindowLength', opts.WindowLength);
        end
        out.history(end+1) = sprintf("destriped all epochs (MinOrder=%d, PolyOrder=%d)", ...
            opts.MinOrder, opts.PolyOrder);
    end

    function out = gaussian(obj, radiusKm)
        %GAUSSIAN Jekeli smoothing per epoch (vectorized over the stack).
        %
        %   Inputs
        %     radiusKm  (1,1) double  Gaussian filter half-response radius [km]
        %   Outputs
        %     out        (1 x 1) shSeries   Gaussian-smoothed per month
        %
        %   Error identifiers
        %     shSeries:stack:nanInSeries
        %         the stacks carry NaN - fill or drop the gap epochs first (raised
        %         by the shared stack check)
        %
        arguments
            obj
            radiusKm (1,1) double {mustBePositive}
        end
        obj.assertClean('gaussian');
        Wn = shLowLevel.shGaussianWeights(obj.nmax, radiusKm);
        out = obj;
        out.Cs = obj.Cs .* Wn(:);
        out.Ss = obj.Ss .* Wn(:);
        if ~isempty(obj.sigmaCs)
            out.sigmaCs = obj.sigmaCs .* Wn(:);
            out.sigmaSs = obj.sigmaSs .* Wn(:);
        end
        out.history(end+1) = sprintf("Gaussian smoothed all epochs (%g km)", radiusKm);
    end

    function out = truncate(obj, nmaxNew)
        %TRUNCATE Reduce the maximum degree of the whole series.
        %
        %   Inputs
        %     nmaxNew  (1,1) double  new maximum degree (must not exceed the current nmax)
        %   Outputs
        %     out        (1 x 1) shSeries   truncated per month
        %
        %   Error identifiers
        %     shSeries:truncate:badTruncation
        %         the requested nmax exceeds the series' own
        %
        arguments
            obj
            nmaxNew (1,1) double {mustBeInteger, mustBeNonnegative}
        end
        if nmaxNew > obj.nmax
            error('shSeries:truncate:badTruncation', ...
                'Requested nmax %d exceeds available %d.', nmaxNew, obj.nmax);
        end
        out = obj; k = nmaxNew + 1;
        out.Cs = obj.Cs(1:k, 1:k, :); out.Ss = obj.Ss(1:k, 1:k, :);
        if ~isempty(obj.sigmaCs)
            out.sigmaCs = obj.sigmaCs(1:k,1:k,:);
            out.sigmaSs = obj.sigmaSs(1:k,1:k,:);
        end
        out.history(end+1) = sprintf("truncated to nmax=%d", nmaxNew);
    end

    % --------------------------------------------------- gap handling (v2.1)
    function out = dropNaN(obj)
        %DROPNAN Remove epochs containing any non-finite coefficient.
        %   OUT = ts.dropNaN() drops every epoch whose C or S stack has a
        %   NaN/Inf anywhere - typically placeholder months across the
        %   GRACE / GRACE-FO gap (2017.5-2018.5) or corrupt reads. The
        %   remaining series is irregularly sampled, which climatology and
        %   the tvANS filter handle natively (least-squares fit on the
        %   actual epochs; per-month VCE).
        %
        %   Outputs  out  shSeries (subset; unchanged if nothing to drop)
        %   Outputs
        %     out        (1 x 1) shSeries   gap months removed
        %
        bad = false(1, obj.nEpochs);
        for k = 1:obj.nEpochs
            bad(k) = any(~isfinite(obj.Cs(:,:,k)), 'all') ...
                  || any(~isfinite(obj.Ss(:,:,k)), 'all');
        end
        out = obj.select(~bad);
        out.history(end) = sprintf("dropNaN removed %d of %d epochs", ...
            nnz(bad), obj.nEpochs);
    end

    function out = select(obj, which, opts)
        %SELECT Subset the series by index, mask, or time range.
        %   OUT = ts.select(WHICH) with WHICH one of
        %     logical (1,T)   keep masked epochs
        %     indices         keep listed epochs (in the given order)
        %     [tMin tMax]     keep epochs with tMin <= t <= tMax
        %
        %   The two-element form is ambiguous by construction: [2004 2010]
        %   is a time range for a monthly series and a valid pair of
        %   INDICES for a daily one (T > 2010 samples is under six years).
        %   It is resolved as indices whenever both values are integers in
        %   1..T, and a warning (shSeries:select:ambiguousRange) fires when they
        %   would also have been a plausible window. Say what you mean:
        %
        %   OUT = ts.select(Range = [tMin tMax]) is always a time window,
        %   in decimal years or as a 1 x 2 datetime, never an index pair.
        %
        %   Inputs
        %     which  logical | double  mask, index list, or [tMin tMax];
        %            omit it when passing Range
        %
        %   Options
        %     Range ([])  (1 x 2) double decimal years, or a 1 x 2
        %         datetime; mutually exclusive with WHICH
        %
        %   Outputs
        %     out        (1 x 1) shSeries   the selected epochs, in the
        %         order given; the operation is appended to the history
        %         (immutable value-class pattern)
        %
        %   Example
        %     tsFO = ts.select(ts.epochs > 2018.5);
        %     tsB  = ts.select(Range = [2004 2010]);
        %
        %   Error identifiers
        %     shSeries:select:ambiguousRange
        %         warning - a two-element WHICH was read as INDICES although both
        %         values also fall inside the epoch span; pass Range= to mean years
        %     shSeries:select:badInput
        %         WHICH and Range= were both given, a logical mask has the wrong
        %         length, indices are not integers in 1..nEpochs, or neither was given
        %     shSeries:range:badRange
        %         Range= is not [t1 t2] with t2 > t1 (decimal years or datetime)
        %
        %   See also mean, dropNaN
        arguments
            obj
            which {mustBeVector(which, "allow-all-empties")} = []
            opts.Range = []
        end
        T = obj.nEpochs;
        if ~isempty(opts.Range)
            assert(isempty(which), 'shSeries:select:badInput', ...
                'Pass either WHICH or Range=, not both.');
            rg = rangeToYears(opts.Range);
            keep = find(obj.epochs(:)' >= rg(1) & obj.epochs(:)' <= rg(2));
        elseif islogical(which)
            assert(numel(which) == T, 'shSeries:select:badInput', ...
                'Logical mask must have %d elements.', T);
            keep = find(which(:)');
        elseif numel(which) == 2 && ~all(which == round(which) & which >= 1 & which <= T)
            keep = find(obj.epochs(:)' >= which(1) & obj.epochs(:)' <= which(2));
        else
            assert(~isempty(which), 'shSeries:select:badInput', ...
                'Give WHICH (mask, indices or [tMin tMax]) or Range=.');
            assert(all(which == round(which)) && all(which >= 1) && all(which <= T), ...
                'shSeries:select:badInput', 'Indices must be integers in 1..%d.', T);
            keep = which(:)';
            if numel(which) == 2 && all(isfinite(obj.epochs)) && ...
                    all(which >= min(obj.epochs)) && all(which <= max(obj.epochs))
                warning('shSeries:select:ambiguousRange', ...
                    ['select([%g %g]) was read as INDICES, but both values ' ...
                     'also fall inside the epoch span - use Range= for a ' ...
                     'time window.'], which(1), which(2));
            end
        end
        out = obj;
        out.Cs = obj.Cs(:,:,keep);
        out.Ss = obj.Ss(:,:,keep);
        if ~isempty(obj.sigmaCs), out.sigmaCs = obj.sigmaCs(:,:,keep); end
        if ~isempty(obj.sigmaSs), out.sigmaSs = obj.sigmaSs(:,:,keep); end
        out.epochs = obj.epochs(keep);
        if ~isempty(obj.names) && numel(obj.names) == T
            out.names = obj.names(keep);
        end
        out.history(end+1) = sprintf("select kept %d of %d epochs", ...
            numel(keep), T);
    end

    % ---------------------------------------------------------- tvANS chain
    function [out, op, info] = filter(obj, method, opts)
        %FILTER Optimal time-variable filtering of the series.
        %   [TSF, OP, INFO] = ts.filter("tvANS", Constraints ([])=..., NoiseCov ([])=...,
        %   SignalMode ("isotropic")="isotropic"|"inhomogeneous", NIterSignal (3)=3,
        %   Robust (false)=false, Nmin (2)=2)
        %   runs the tvANS chain (see shLowLevel.tvANSFilter): deterministic-model
        %   separation, empirical or supplied noise covariance, monthly VCE
        %   scaling, data-driven signal covariance, per-month anisotropic
        %   Wiener filter, optional hard constraints. OP is the stored
        %   linear operator - required for basinAverage(...,
        %   Deconvolve=true) and shLowLevel.resolutionMap.
        %   v2.1: Blocks ("auto")="auto"|"on"|"off" engages the block-diagonal
        %   fast path (isotropic + empirical N + no constraints; identical
        %   results, tractable to Lmax ~ 120). The filtered series carries
        %   per-coefficient posterior 1-sigma stacks in OUT.sigmaCs/Ss
        %   (from info.sigmaXfres; degrees below Nmin are NaN).
        %   v3.1.1: the three noise-covariance tuning options of
        %   shLowLevel.tvANSFilter are forwarded, so the class method is the
        %   full single point of access: Shrinkage ([])=empirical noise-
        %   covariance shrinkage, VCEMinDegree ([])=first degree entering
        %   the variance-component estimation, VCEBands ([])=order-band
        %   edges for per-band monthly VCE factors (block path only).
        %   [] means "leave the shLowLevel.tvANSFilter default in place"
        %   (0.1, round(2/3*Lmax) and no banding respectively) - the
        %   defaults are NOT duplicated here, they have exactly one home.
        %
        %   Inputs
        %     method  (1,1) string  filter chain to run; currently "tvANS"
        %             (the simple filters are their own methods:
        %             gaussian / fan / destripe / applyDDK)
        %   Options
        %     Constraints ([])   (P x P | struct) prior constraint matrix or
        %         a designFilter constraint struct added to the normals
        %     NoiseCov ([])      (P x P | struct) noise covariance from
        %         shLowLevel.buildNoiseCov; [] uses a scaled identity
        %     SignalMode ("isotropic")  "isotropic" | "inhomogeneous" signal
        %         covariance model (see shLowLevel.buildSignalCov)
        %     NIterSignal (3)    (1 x 1) signal-covariance re-estimation
        %         iterations
        %     Robust (false)     (1 x 1) logical, Huber re-weighting of
        %         epoch residuals
        %     Nmin (2)      (1 x 1) lowest degree entering the filter
        %     Blocks ("auto")    ("auto" | "on" | "off") order-block usage in
        %         the normal matrix
        %     Shrinkage ([])     (1 x 1) shrink the empirical signal
        %         covariance toward its diagonal, 0..1; [] auto-selects
        %     VCEMinDegree ([])  (1 x 1) lowest degree in the VCE bands;
        %         [] follows Nmin
        %     VCEBands ([])      (1 x B) variance-component band edges;
        %         [] uses the built-in banding
        %
        %   Outputs
        %     out        (1 x 1) shSeries   tvANS-filtered series with sigmaCs/Ss posterior stacks (exact incl. constraints, v2.5)
        %     op         (1,1) struct   the stored linear operator, as
        %                returned by shLowLevel.tvANSFilter, for
        %                shLowLevel.basinDeconvolve and
        %                shLowLevel.resolutionMap
        %     info       (1,1) struct   the noise, signal and VCE
        %                diagnostics, as returned by
        %                shLowLevel.tvANSFilter
        %
        %   Error identifiers
        %     shSeries:stack:nanInSeries
        %         the stacks carry NaN - fill or drop the gap epochs first (raised
        %         by the shared stack check)
        %     shSeries:filter:noEpoch
        %         filter needs a finite epoch on every entry
        %
        arguments
            obj
            method (1,1) string {mustBeMember(method, "tvANS")} %#ok<INUSA>
            opts.NoiseCov double = []
            opts.Constraints double = []
            opts.SignalMode (1,1) string = "isotropic"
            opts.NIterSignal (1,1) double = 3
            opts.Robust (1,1) logical = false
            opts.Nmin (1,1) double = 2
            opts.Blocks (1,1) string ...
                {mustBeMember(opts.Blocks, ["auto","on","off"])} = "auto"
            opts.Shrinkage double {mustBeScalarOrEmpty} = []
            opts.VCEMinDegree double {mustBeScalarOrEmpty} = []
            opts.VCEBands (1,:) double = []
        end
        obj.assertClean('filter');
        if any(~isfinite(obj.epochs))
            error('shSeries:filter:noEpoch', ...
                'filter requires finite epochs for every entry.');
        end
        idx = shLowLevel.shIndex(obj.nmax, Nmin = opts.Nmin);
        X = zeros(idx.P, obj.nEpochs);
        for k = 1:obj.nEpochs
            X(:,k) = shLowLevel.vecFromCS(obj.Cs(:,:,k), obj.Ss(:,:,k), idx);
        end
        % forward the tuning options only when the caller set them, so the
        % single home of their defaults stays shLowLevel.tvANSFilter.
        % NOTE: everything goes through ONE 'Name', value cell - MATLAB
        % forbids following name=value syntax with a cell expansion.
        fwd = {'NoiseCov', opts.NoiseCov, ...
               'Constraints', opts.Constraints, ...
               'SignalMode', char(opts.SignalMode), ...
               'NIterSignal', opts.NIterSignal, ...
               'Robust', opts.Robust, ...
               'Blocks', char(opts.Blocks)};
        if ~isempty(opts.Shrinkage)
            fwd = [fwd, {'Shrinkage', opts.Shrinkage}];
        end
        if ~isempty(opts.VCEMinDegree)
            fwd = [fwd, {'VCEMinDegree', opts.VCEMinDegree}];
        end
        if ~isempty(opts.VCEBands)
            fwd = [fwd, {'VCEBands', opts.VCEBands}];
        end
        [Xf, op, info] = shLowLevel.tvANSFilter(X, obj.epochs, idx, fwd{:});
        out = obj;
        out.sigmaCs = nan(size(obj.Cs));
        out.sigmaSs = nan(size(obj.Ss));
        for k = 1:obj.nEpochs
            [cf, sf] = shLowLevel.csFromVec(Xf(:,k), idx);
            [sc, ss] = shLowLevel.csFromVec(info.sigmaXfres(:,k), idx);
            % degrees below Nmin pass through unfiltered
            out.Cs(:,:,k) = obj.Cs(:,:,k);
            out.Ss(:,:,k) = obj.Ss(:,:,k);
            nz = idx.minDegree + 1;
            out.Cs(nz:end, :, k) = cf(nz:end, :);
            out.Ss(nz:end, :, k) = sf(nz:end, :);
            out.sigmaCs(nz:end, :, k) = sc(nz:end, :);
            out.sigmaSs(nz:end, :, k) = ss(nz:end, :);
        end
        out.history(end+1) = sprintf(...
            "tvANS filtered (SignalMode=%s, constraints=%d)", ...
            opts.SignalMode, size(opts.Constraints, 2));
    end

    function [avg, out] = basinAverage(obj, B, opts)
        %BASINAVERAGE Basin averages, naive or exactly deconvolved.
        %   AVG = ts.basinAverage(B) - naive averages B'*x ./ diag(B'*B),
        %   K x T, with B (P x K) basin kernels in shLowLevel.shIndex ordering
        %   (build from a grid mask via shLowLevel.synthesisMatrix:
        %   b = Y' * (w .* mask)).
        %   [AVG, OUT] = ts.basinAverage(B, Deconvolve (false)=true, Op (struct())=op) removes
        %   filter attenuation and inter-basin leakage exactly using the
        %   stored operator from ts.filter (see shLowLevel.basinDeconvolve).
        %   OUT.sigma (K x T) is the 1-sigma noise uncertainty of AVG
        %   propagated through the deconvolution (v2.1).
        %   Inputs
        %     Deconvolve (false)  apply shLowLevel.basinDeconvolve to the
        %          basin series (undo kernel attenuation)
        %
        %   Outputs
        %     avg        (K x T) double   basin averages (deconvolved when Deconvolve=true)
        %     out        (1,1) struct   on the deconvolution path, as
        %                returned by shLowLevel.basinDeconvolve (sigma,
        %                c, attn, condA, avgNaive); empty otherwise
        %
        %   Options
        %     Ridge (0)  Tikhonov ridge added to the deconvolution normal
        %         matrix; raise it when the kernel matrix is ill-conditioned
        %         (out.condA reports the condition number)
        %
        %   Error identifiers
        %     shSeries:basinAverage:badBasis
        %         B is not P x K in shLowLevel.shIndex ordering for this nmax
        %     shSeries:basinAverage:missingOp
        %         Deconvolve=true without Op= from ts.filter("tvANS", ...)
        arguments
            obj
            B double
            opts.Deconvolve (1,1) logical = false
            opts.Op struct = struct()
            opts.Ridge (1,1) double {mustBeNonnegative} = 0   % relative, see shLowLevel.basinDeconvolve
        end
        if opts.Deconvolve
            if isempty(fieldnames(opts.Op))
                error('shSeries:basinAverage:missingOp', ...
                    'Deconvolve=true requires Op=op from ts.filter("tvANS", ...).');
            end
            [avg, out] = shLowLevel.basinDeconvolve(B, opts.Op, Ridge = opts.Ridge);
        else
            idx = shLowLevel.shIndex(obj.nmax);
            if size(B,1) ~= idx.P
                error('shSeries:basinAverage:badBasis', ...
                    'B must be P x K in shLowLevel.shIndex(Nmax=%d) ordering (P=%d).', ...
                    obj.nmax, idx.P);
            end
            X = zeros(idx.P, obj.nEpochs);
            for k = 1:obj.nEpochs
                X(:,k) = shLowLevel.vecFromCS(obj.Cs(:,:,k), obj.Ss(:,:,k), idx);
            end
            avg = (B' * X) ./ diag(B' * B);
            out = struct();
        end
    end

    function b = toGrid(obj, latDeg, lonDeg, opts)
        %TOGRID Synthesize every epoch into one stack, with its metadata.
        %   B = ts.toGrid(LAT, LON, Quantity ("ewh")=..., kn ([])=...,
        %       LatType ("geodetic")=...) is shCoefficients.toGrid over a
        %   whole series: B.Z is (nlat x nlon x nEpochs) and B.Epoch
        %   carries the decimal years, so an animation can label its own
        %   frames from the data rather than from a filename.
        %
        %   ZMIN/ZMAX ARE TAKEN OVER THE WHOLE STACK, not per frame. That
        %   is the point of building the stack here: an animation drawn
        %   with a per-frame colour scale shows the scale changing and
        %   the signal not, which is the one way to make 240 honest maps
        %   into a misleading film.
        %
        %   The Legendre recursion is cached across epochs (the grid does
        %   not change), so the cost is one recursion plus nEpochs
        %   coefficient sums, not nEpochs recursions.
        %
        %   Inputs
        %     latDeg  (1,:) double  latitudes [deg], convention per LatType
        %     lonDeg  (1,:) double  longitudes [deg]
        %   Outputs
        %     b          (1,1) struct   as built by
        %                shLowLevel.gridHandover, the same bundle
        %                shCoefficients.toGrid returns, with Z
        %                (nlat x nlon x nEpochs) double, Epoch and C00
        %                (nEpochs x 1) double, and FieldKind "mixed" when
        %                the epochs disagree
        %
        %   Options
        %     Quantity ("ewh")  any kernelFactors quantity
        %     kn ([])  load Love numbers k'_n (mass quantities; never hardcoded)
        %     hn ([])  load Love numbers h'_n (deformation_up only)
        %     Nmin (0)  degrees below nmin are zeroed
        %     Nmax (NaN)  truncation degree; NaN uses the series nmax
        %     Height (0)  evaluation height [m] above the evaluation surface
        %     Surface ("sphere")  "sphere" | "ellipsoid", as g.synthesis
        %     SemiMajorAxis (6378137)  ellipsoid semi-major axis [m], WGS84
        %     rho_ave (5517)  mean Earth density [kg/m^3]
        %     rho_water (1000)  water density [kg/m^3]
        %     LatType ("geodetic")  "geodetic" | "geocentric"
        %     Flattening (1/298.257223563)  ellipsoid flattening (WGS84),
        %         for LatType and for Surface = "ellipsoid"
        %     MaxMemGB (4)  budget for the STACK itself; exceeding it is an
        %         error naming the size, not a silent swap-thrash
        %
        %   Example
        %     b = ts.toGrid(-89.5:89.5, 0.5:359.5, Quantity = "ewh", kn = kn);
        %     size(b.Z)        % [180 360 nEpochs]
        %
        %   Error identifiers
        %     shSeries:toGrid:empty
        %         the series has no epochs
        %     shSeries:toGrid:tooLarge
        %         the grid stack would exceed MaxMemGB; raise it or grid fewer
        %         epochs
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
            opts.MaxMemGB (1,1) double {mustBePositive} = 4
        end
        T = obj.nEpochs;
        assert(T > 0, 'shSeries:toGrid:empty', 'The series has no epochs.');
        nlat = numel(latDeg); nlon = numel(lonDeg);
        needGB = nlat * nlon * T * 8 / 2^30;
        assert(needGB <= opts.MaxMemGB, 'shSeries:toGrid:tooLarge', ...
            ['The stack would be %d x %d x %d = %.2f GB, over MaxMemGB ' ...
             '(%.2f). Coarsen the grid, select fewer epochs, or raise ' ...
             'the budget deliberately.'], nlat, nlon, T, needGB, opts.MaxMemGB);
        nmaxEff = opts.Nmax;
        if isnan(nmaxEff), nmaxEff = obj.nmax; end
        Z = zeros(nlat, nlon, T);
        c00 = zeros(T, 1);
        lat = []; lon = [];
        for k = 1:T
            g = obj.at(k);
            [Zk, lat, lon] = g.synthesis(latDeg, lonDeg, ...
                Quantity = opts.Quantity, kn = opts.kn, hn = opts.hn, ...
                Nmin = opts.Nmin, Nmax = nmaxEff, Height = opts.Height, ...
                rho_ave = opts.rho_ave, rho_water = opts.rho_water, ...
                LatType = opts.LatType, Flattening = opts.Flattening, ...
                Surface = opts.Surface, SemiMajorAxis = opts.SemiMajorAxis);
            Z(:, :, k) = Zk;
            c00(k) = obj.Cs(1, 1, k);
        end
        [~, ~, units] = shLowLevel.kernelFactors(char(opts.Quantity), ...
            nmaxEff, obj.GM, obj.R, kn = opts.kn, hn = opts.hn, ...
            rho_ave = opts.rho_ave, rho_water = opts.rho_water);
        nm = "";
        if ~isempty(obj.names), nm = obj.names(1); end
        b = shLowLevel.gridHandover(Z, lat, lon, units, opts.LatType, ...
            opts.Quantity, obj.productType, nm, obj.epochs, c00, ...
            obj.history, nmaxEff, opts.Nmin);
    end

    % ------------------------------------------- lanes behind the class (WP7)
    % Each method below reaches one lane and adds no numerics of its own;
    % testContract pins every one of them bitwise against the lane it
    % calls. A lane's options are declared WITHOUT defaults and forwarded
    % only when the caller gives them, so a default lives in one place.
    function [out, rep] = kalman(obj, opts)
        %KALMAN Kalman-smoothed series (Kurtenbach/Kvas), solution mode.
        %   [TSK, REP] = ts.kalman(ModelSeries = TSM) runs
        %   shLowLevel.kalmanChain with TS as the observations: the VAR
        %   process model is estimated from TSM, every epoch of TS is one
        %   observation weighted by its formal sigmas (or NoiseCov), and a
        %   forward Kalman filter plus an RTS smoother return the smoothed
        %   series. shLowLevel.kalmanChain documents the chain, its
        %   references and its memory cost.
        %
        %   Every option goes to shLowLevel.kalmanChain only when you pass
        %   it, so its default lives in that function's arguments block and
        %   nowhere else: "(lane default)" below means exactly that. The
        %   normal-equation mode, which reads a SINEX folder instead of a
        %   series, has no series to be a method of and stays on
        %   shLowLevel.kalmanChain.
        %
        %   Outputs
        %     out  (1 x 1) shSeries  smoothed series on the epoch grid, with
        %          formal 1-sigma stacks
        %     rep  (1,1) struct  as returned by shLowLevel.kalmanChain,
        %          which documents every field
        %
        %   Options
        %     ModelSeries (required)  (1 x 1) shSeries  process realization
        %         at this series' nmax, e.g. GAX/AOD1B or a hydrology model
        %     Order (lane default)  VAR order p
        %     Structure (lane default)  coupling structure of the VAR model
        %     Shrink (lane default)  diagonal loading of the VAR estimate
        %     CondFun (lane default)  covariance conditioning
        %     Epochs (lane default)  target epoch grid [decimal years]
        %     Tolerance (lane default)  epoch matching tolerance [yr]
        %     NoiseCov (lane default)  observation noise covariance
        %     Climatology (lane default)  reduce the series by its own
        %         climatology around the filter, and restore it after
        %     Smoother (lane default)  run the RTS pass
        %     QC (lane default)  innovation-based quality control
        %     QCAlpha (lane default)  false-alarm level of that test
        %     StoreCov (lane default)  where the smoother's covariances live
        %
        %   Example
        %     [tsk, rep] = ts.kalman(ModelSeries = tsm, Order = 1);
        arguments
            obj
            opts.ModelSeries
            opts.Order
            opts.Structure
            opts.Shrink
            opts.CondFun
            opts.Epochs
            opts.Tolerance
            opts.NoiseCov
            opts.Climatology
            opts.Smoother
            opts.QC
            opts.QCAlpha
            opts.StoreCov
        end
        fwd = namedargs2cell(opts);
        [out, rep] = shLowLevel.kalmanChain(obj, fwd{:});
    end

    function [modes, pcs, varExplained, info] = eof(obj, opts)
        %EOF Empirical orthogonal functions of the series.
        %   [MODES, PCS, VE, INFO] = ts.eof() decomposes the series into
        %   spatial modes and unit-variance principal components by an SVD
        %   of the time-centred coefficient stack - shLowLevel.eofAnalysis,
        %   which documents the scaling: MODES{k} times PCS(:,k)
        %   reconstructs mode k's contribution exactly. It is usually run
        %   on a residual, after ts.climatology. The options go to
        %   shLowLevel.eofAnalysis only when given; "(lane default)" is
        %   that function's.
        %
        %   Outputs
        %     modes         (1 x K) cell  shCoefficients, the spatial patterns
        %     pcs           (T x K) double  principal components, unit variance
        %     varExplained  (K x 1) double  fraction of the variance per mode
        %     info          (1,1) struct  as returned by
        %                   shLowLevel.eofAnalysis, which documents every
        %                   field
        %
        %   Options
        %     NModes (lane default)  number of modes returned
        %     Center (lane default)  remove the temporal mean first
        %
        %   Example
        %     [~, resid] = ts.climatology();
        %     [modes, pcs, ve] = resid.eof(NModes = 3);
        arguments
            obj
            opts.NModes
            opts.Center
        end
        fwd = namedargs2cell(opts);
        [modes, pcs, varExplained, info] = shLowLevel.eofAnalysis(obj, fwd{:});
    end

    function write(obj, folder, opts)
        %WRITE Export every epoch to its own ICGEM .gfc file.
        %   ts.write(FOLDER) writes epoch k with g.write, through ts.at(k),
        %   so each file is what g.write writes for that epoch. The files
        %   are named after the series' names: NAMES(k) + ".gfc", unless
        %   FileNames says otherwise.
        %
        %   A .gfc file has no epoch field. shSeries.read takes the epoch
        %   back from the file NAME, through shLowLevel.parseGraceFilename
        %   (the GRACE form PPP-2_YYYYDDD-YYYYDDD_*, or a name ending in
        %   _YYYY-MM or _YYYY-MM-DD). So write checks every name BEFORE it
        %   writes anything, and warns once, naming the first epoch whose
        %   file name would not bring it back. Pass FileNames in one of
        %   those forms when the folder must read back as this series.
        %
        %   Inputs
        %     folder  (1,1) string  existing folder to write into
        %
        %   Options
        %     FileNames (string.empty(0,1))  (T x 1) string  one file name
        %         per epoch, relative to FOLDER; empty uses NAMES + ".gfc"
        %     Comment ("")  forwarded to g.write
        %     Sidecar (false)  forwarded to g.write. Deliberately false
        %         here, where g.write defaults to true: a folder of epochs
        %         is meant to be read back as a series, and the default
        %         read pattern "*.gfc*" would pick up every
        %         "<file>.gfc.provenance.json" as well
        %
        %   Error identifiers
        %     shSeries:write:noFolder
        %         FOLDER does not exist - write does not create it
        %     shSeries:write:badFileNames
        %         there is not one non-empty, unique file name per epoch
        %         (by default: the series carries no such names)
        %     shSeries:write:epochNotInName
        %         a WARNING, not an error: at least one file name will not
        %         bring its epoch back when the folder is read
        %
        %   Example
        %     ts.write(outFolder, FileNames = "GSM-2_" + spans + "_mine.gfc");
        arguments
            obj
            folder (1,1) string
            opts.FileNames (:,1) string = string.empty(0,1)
            opts.Comment (1,1) string = ""
            opts.Sidecar (1,1) logical = false
        end
        if ~isfolder(folder)
            error('shSeries:write:noFolder', ...
                'Folder "%s" does not exist; write does not create it.', ...
                folder);
        end
        T = obj.nEpochs;
        names = opts.FileNames;
        if isempty(names)
            names = obj.names + ".gfc";
        end
        if numel(names) ~= T || any(strlength(names) == 0) ...
                || numel(unique(names)) ~= T
            error('shSeries:write:badFileNames', ...
                ['write needs one non-empty, unique file name per epoch ' ...
                 '(%d epochs, %d names); pass FileNames=.'], T, numel(names));
        end
        % 1e-6 yr (32 s) is far below the coarsest epoch a name can carry
        % (a day, 2.7e-3 yr) and far above the rounding of a decimal-year
        % epoch (~1e-13 yr): it separates "the same epoch" from "another"
        lost = false(T, 1);
        for k = 1:T
            meta = shLowLevel.parseGraceFilename(names(k));
            lost(k) = isfinite(obj.epochs(k)) && ...
                ~(abs(meta.epoch - obj.epochs(k)) <= 1e-6);
        end
        if any(lost)
            k1 = find(lost, 1);
            warning('shSeries:write:epochNotInName', ...
                ['%d of %d file names will not bring their epoch back ' ...
                 '(first: "%s" for epoch %.6f) - shSeries.read would ' ...
                 'give them another epoch or NaN. Pass FileNames= in a ' ...
                 'form shLowLevel.parseGraceFilename reads.'], ...
                nnz(lost), T, names(k1), obj.epochs(k1));
        end
        for k = 1:T
            g = obj.at(k);
            g.write(fullfile(folder, names(k)), Comment = opts.Comment, ...
                Sidecar = opts.Sidecar);
        end
    end

    function [dq, info] = gradient(obj, latDeg, lonDeg, opts)
        %GRADIENT North/east/up gradient of every epoch, stacked.
        %   [DQ, INFO] = ts.gradient(LAT, LON, ...) is g.gradient of each
        %   epoch g = ts.at(k), with DQ.north, DQ.east and DQ.up stacked
        %   along the THIRD dimension, page k for epoch k, as ts.toGrid
        %   stacks its fields: (nlat x nlon x T) on a grid and
        %   (npts x 1 x T) for Mode = "points". DQ.up stays [] for the
        %   surface quantities, which have no radial law. INFO is the first
        %   epoch's; it depends only on the options, which every epoch
        %   shares. The options go to g.gradient only when given, so
        %   "(method default)" below is shCoefficients.gradient's.
        %
        %   Inputs
        %     latDeg  (1,:) double  latitudes [deg]
        %     lonDeg  (1,:) double  longitudes [deg]
        %
        %   Outputs
        %     dq    (1,1) struct  as returned by shCoefficients.gradient,
        %           which documents every field, each component stacked
        %           along the third dimension
        %     info  (1,1) struct  as returned by shCoefficients.gradient
        %           for the first epoch, which documents every field
        %
        %   Options
        %     Quantity (method default)  any kernelFactors quantity
        %     kn (method default)  load Love numbers k'_n
        %     hn (method default)  load Love numbers h'_n
        %     Nmin (method default)  degrees below Nmin are zeroed
        %     Nmax (method default)  truncation degree
        %     Height (method default)  evaluation height [m]
        %     Surface (method default)  "sphere" or "ellipsoid"
        %     SemiMajorAxis (method default)  ellipsoid semi-major axis [m]
        %     rho_ave (method default)  mean Earth density [kg/m^3]
        %     rho_water (method default)  water density [kg/m^3]
        %     Mode (method default)  a grid, or pairwise points
        %     Units (method default)  per metre or per radian
        %     MaxMemGB (method default)  Legendre memory budget [GB]
        %     LatType (method default)  how the latitudes are read
        %     Flattening (method default)  ellipsoid flattening
        %
        %   Example
        %     [dq, info] = ts.gradient(-89:2:89, 0:2:358, Quantity = "ewh", kn = kn);
        %     size(dq.north)        % 90 x 180 x T
        arguments
            obj
            latDeg (1,:) double
            lonDeg (1,:) double
            opts.Quantity
            opts.kn
            opts.hn
            opts.Nmin
            opts.Nmax
            opts.Height
            opts.Surface
            opts.SemiMajorAxis
            opts.rho_ave
            opts.rho_water
            opts.Mode
            opts.Units
            opts.MaxMemGB
            opts.LatType
            opts.Flattening
        end
        fwd = namedargs2cell(opts);
        T = obj.nEpochs;
        g = obj.at(1);
        [d, info] = g.gradient(latDeg, lonDeg, fwd{:});
        dq = d;
        comps = ["north", "east", "up"];
        for c = comps
            if ~isempty(d.(c))
                dq.(c) = zeros(size(d.(c), 1), size(d.(c), 2), T);
                dq.(c)(:, :, 1) = d.(c);
            end
        end
        for k = 2:T
            g = obj.at(k);
            d = g.gradient(latDeg, lonDeg, fwd{:});
            for c = comps
                if ~isempty(d.(c))
                    dq.(c)(:, :, k) = d.(c);
                end
            end
        end
    end

    function [mCorr, info] = leakageCorrect(obj, latDeg, lonDeg, opts)
        %LEAKAGECORRECT Forward-model leakage correction of every epoch.
        %   [M, INFO] = ts.leakageCorrect(LAT, LON, Filter = F, kn = KN)
        %   synthesizes each epoch on the grid (g.synthesis, geocentric,
        %   Quantity "ewh" unless told otherwise) and runs
        %   shLowLevel.leakageCorrect on it with the series' GM and R: the
        %   iterative forward model that finds the field which, pushed
        %   through the chain the data saw, reproduces the filtered field.
        %   M is the corrected stack, page k for epoch k.
        %   shLowLevel.leakageCorrect documents the method, its stopping
        %   rule, and why the MASK MUST COVER EVERY REGION THAT CAN HOLD
        %   MASS, not only the one you measure.
        %
        %   Filter is REQUIRED here, although the function defaults it: a
        %   series does not know which filter its data saw, and the wrong
        %   one makes the correction meaningless without any error. The
        %   other lane options go to shLowLevel.leakageCorrect only when
        %   given; "(lane default)" below is that function's.
        %
        %   Inputs
        %     latDeg  (1,:) double  geocentric latitudes [deg]
        %     lonDeg  (1,:) double  longitudes [deg]
        %
        %   Outputs
        %     mCorr  (nLat x nLon x T) double  corrected fields, in the unit
        %            of Quantity
        %     info   (1 x T) struct  one per epoch, as returned by
        %            shLowLevel.leakageCorrect, which documents every field
        %
        %   Options
        %     Filter (required)  the filter the DATA saw: a string such as
        %         "gauss300" or "DDK3", or a W struct
        %     Quantity ("ewh")  the synthesized quantity; its unit is M's
        %     kn ([])  load Love numbers for the mass quantities (never
        %         hardcoded)
        %     Mask (lane default)  pixels allowed to hold mass
        %     Nmax (lane default)  degree of the intermediate analysis
        %     Gain (lane default)  relaxation factor
        %     NoiseLevel (lane default)  noise RMS of the field
        %     ResidualRegion (lane default)  where the residual is measured
        %     Tau (lane default)  discrepancy-principle safety factor
        %     MaxIter (lane default)  iteration cap
        %     Tol (lane default)  fallback step criterion
        %     Quiet (lane default)  suppress the per-epoch summary
        %
        %   Error identifiers
        %     shSeries:leakageCorrect:noFilter
        %         Filter was not given
        %
        %   Example
        %     [m, info] = ts.leakageCorrect(-89:89, 0:359, Filter = "gauss300", ...
        %         kn = kn, Mask = unionMask, Quiet = true);
        arguments
            obj
            latDeg (1,:) double
            lonDeg (1,:) double
            opts.Filter
            opts.Quantity (1,1) string = "ewh"
            opts.kn double = []
            opts.Mask
            opts.Nmax
            opts.Gain
            opts.NoiseLevel
            opts.ResidualRegion
            opts.Tau
            opts.MaxIter
            opts.Tol
            opts.Quiet
        end
        if ~isfield(opts, 'Filter')
            error('shSeries:leakageCorrect:noFilter', ...
                ['Filter is required: pass the filter the data actually ' ...
                 'saw ("none", "gauss<radiusKm>", "DDKn" or a W struct).']);
        end
        fwd = [namedargs2cell(rmfield(opts, ["Quantity", "kn"])), ...
            {'GM', obj.GM, 'R', obj.R}];
        T = obj.nEpochs;
        infos = cell(1, T);
        for k = 1:T
            g = obj.at(k);
            Z = g.synthesis(latDeg, lonDeg, Quantity = opts.Quantity, ...
                kn = opts.kn);
            [mk, infos{k}] = shLowLevel.leakageCorrect(Z, latDeg, lonDeg, ...
                fwd{:});
            if k == 1
                mCorr = zeros(size(mk, 1), size(mk, 2), T);
            end
            mCorr(:, :, k) = mk;
        end
        info = [infos{:}];
    end

    function [fHat, info] = leakageDataDriven(obj, latDeg, lonDeg, opts)
        %LEAKAGEDATADRIVEN Model-free leakage correction of a catchment mean.
        %   [FHAT, INFO] = ts.leakageDataDriven(LAT, LON, Mask = R,
        %   Filter = F, kn = KN) synthesizes every epoch on the grid
        %   (g.synthesis, geocentric, Quantity "ewh" unless told otherwise)
        %   and runs shLowLevel.leakageDataDriven on the stack with the
        %   series' GM and R - Vishwakarma's method of deviation, or with
        %   Method = "scale" the method of scale; both repair the
        %   catchment average from the filtered fields alone.
        %   FHAT is the corrected catchment mean, one value per epoch.
        %   shLowLevel.leakageDataDriven documents the method, the
        %   catchment size it is designed for (about 65000 km^2 and up),
        %   and why it needs at least 12 epochs and no NaN.
        %
        %   Filter is REQUIRED here, although the function defaults it: a
        %   series does not know which filter its data saw, and the wrong
        %   one mis-estimates both corrections without any error. Mask,
        %   Nmax and Method go to shLowLevel.leakageDataDriven only when
        %   given; "(lane default)" below is that function's.
        %
        %   Inputs
        %     latDeg  (1,:) double  geocentric latitudes [deg]
        %     lonDeg  (1,:) double  longitudes [deg]
        %
        %   Outputs
        %     fHat  (T x 1) double  corrected catchment average, in the
        %           unit of Quantity
        %     info  (1,1) struct  as returned by
        %           shLowLevel.leakageDataDriven, which documents every field
        %
        %   Options
        %     Filter (required)  the filter the DATA saw: a string such as
        %         "gauss300" or "DDK3", or a W struct
        %     Quantity ("ewh")  the synthesized quantity; its unit is FHAT's
        %     kn ([])  load Love numbers for the mass quantities (never
        %         hardcoded)
        %     Mask (lane default)  the catchment function, 1 inside and
        %         0 outside; required in practice
        %     Nmax (lane default)  degree of the analysis/synthesis chain
        %     Method (lane default)  the method of deviation, or of scale
        %
        %   Error identifiers
        %     shSeries:leakageDataDriven:noFilter
        %         Filter was not given
        %
        %   Example
        %     [f, info] = ts.leakageDataDriven(lat, lon, Mask = basin, ...
        %         Filter = "gauss300", kn = kn);
        arguments
            obj
            latDeg (1,:) double
            lonDeg (1,:) double
            opts.Filter
            opts.Quantity (1,1) string = "ewh"
            opts.kn double = []
            opts.Mask
            opts.Nmax
            opts.Method
        end
        if ~isfield(opts, 'Filter')
            error('shSeries:leakageDataDriven:noFilter', ...
                ['Filter is required: pass the filter the data actually ' ...
                 'saw ("none", "gauss<radiusKm>", "DDKn" or a W struct).']);
        end
        T = obj.nEpochs;
        for k = 1:T
            g = obj.at(k);
            Z = g.synthesis(latDeg, lonDeg, Quantity = opts.Quantity, ...
                kn = opts.kn);
            if k == 1
                stack = zeros(size(Z, 1), size(Z, 2), T);
            end
            stack(:, :, k) = Z;
        end
        fwd = [namedargs2cell(rmfield(opts, ["Quantity", "kn"])), ...
            {'GM', obj.GM, 'R', obj.R}];
        [fHat, info] = shLowLevel.leakageDataDriven(stack, latDeg, lonDeg, ...
            fwd{:});
    end

    function out = poleTideConvert(obj, opts)
        %POLETIDECONVERT Move every epoch's C21/S21 to another mean pole.
        %   OUT = ts.poleTideConvert(From = "IERS2010", To = "IERS2018")
        %   applies shLowLevel.poleTideConvert to each epoch at its own
        %   epoch, in the raw (C, S, EPOCH) form, so the series keeps its
        %   names, its sigmas and its history. That function documents the
        %   two models and the adjustment.
        %
        %   Outputs
        %     out  (1,1) shSeries  the converted series, history appended
        %
        %   Options
        %     From (lane default)  the convention of this series
        %     To (lane default)  the convention to move to
        %     Mode (lane default)  the solid tide, the ocean tide, or both
        %     SolidCoef (lane default)  the solid-tide coefficient
        %     OceanCoef (lane default)  the ocean-tide coefficient
        %
        %   Example
        %     ts18 = ts.poleTideConvert(From = "IERS2010", To = "IERS2018");
        arguments
            obj
            opts.From
            opts.To
            opts.Mode
            opts.SolidCoef
            opts.OceanCoef
        end
        args = namedargs2cell(opts);
        out = obj;
        for k = 1:obj.nEpochs
            [C2, S2] = shLowLevel.poleTideConvert(obj.Cs(:, :, k), ...
                obj.Ss(:, :, k), obj.epochs(k), args{:});
            out.Cs(:, :, k) = C2;
            out.Ss(:, :, k) = S2;
        end
        out.history(end+1) = "poleTideConvert: C21/S21 of every epoch moved to another mean pole";
    end

    function [d1, info] = estimateDegree1(obj, ocean, opts)
        %ESTIMATEDEGREE1 Geocentre coefficients of every epoch, from the series.
        %   [D1, INFO] = ts.estimateDegree1(OCEAN, kn = KN) is
        %   shLowLevel.estimateDegree1(ts, OCEAN, ...): C10, C11 and S11 for
        %   every epoch by the method of Swenson, Chambers & Wahr (2008).
        %   That function documents the method, its grid and its outputs;
        %   D1 drops straight into ts.addDegree1.
        %
        %   Inputs
        %     ocean  logical  the ocean mask on the LatDeg x LonDeg grid
        %
        %   Outputs
        %     d1    (1,1) struct  as returned by shLowLevel.estimateDegree1,
        %           which documents every field
        %     info  (1,1) struct  as returned by shLowLevel.estimateDegree1,
        %           which documents every field
        %
        %   Options
        %     kn (lane default)  load Love numbers, which the method needs
        %     OceanModel (lane default)  an ocean-bottom-pressure model grid
        %     LatDeg (lane default)  latitudes of the working grid
        %     LonDeg (lane default)  longitudes of the working grid
        %     Nmax (lane default)  degree of the analysis
        %
        %   Example
        %     d1 = ts.estimateDegree1(ocean, kn = kn);
        %     ts = ts.addDegree1(d1);
        arguments
            obj
            ocean
            opts.kn
            opts.OceanModel
            opts.LatDeg
            opts.LonDeg
            opts.Nmax
        end
        args = namedargs2cell(opts);
        [d1, info] = shLowLevel.estimateDegree1(obj, ocean, args{:});
    end

    function [tsComb, info] = combineCenters(obj, others, opts)
        %COMBINECENTERS Combine this series with other centres' by VCE.
        %   [TSCOMB, INFO] = ts.combineCenters({TSB, TSC}) is
        %   shLowLevel.combineCenters({ts, TSB, TSC}): one variance factor
        %   per centre and month, by variance-component estimation, on the
        %   epochs of this series. That function documents the method and
        %   what its posterior sigmas can and cannot claim.
        %
        %   Inputs
        %     others  (1,:) cell  the other centres' series, same nmax
        %
        %   Outputs
        %     tsComb  (1,1) shSeries  the combined series
        %     info    (1,1) struct  as returned by shLowLevel.combineCenters,
        %             which documents every field
        %
        %   Options
        %     Tolerance (lane default)  epoch matching [yr]
        %     AllowMissing (lane default)  combine months some centres lack
        %     Robust (lane default)  the median variance factor per month
        %     MaxIter (lane default)  the most VCE iterations
        %     Tol (lane default)  the VCE convergence tolerance
        %
        %   Example
        %     [ts, info] = tsITSG.combineCenters({tsCSR, tsGFZ});
        arguments
            obj
            others (1,:) cell
            opts.Tolerance
            opts.AllowMissing
            opts.Robust
            opts.MaxIter
            opts.Tol
        end
        args = namedargs2cell(opts);
        [tsComb, info] = shLowLevel.combineCenters([{obj}, others], args{:});
    end

    function [a, rec] = slepianProject(obj, G, idx)
        %SLEPIANPROJECT Project every epoch onto a Slepian basis, and back.
        %   [A, REC] = ts.slepianProject(G, IDX) is
        %   shLowLevel.slepianProject(ts.Cs, ts.Ss, G, IDX), with the tapers
        %   G and the index IDX of shLowLevel.slepianBasis: A holds one
        %   column of Slepian coefficients per epoch, the regional modes in
        %   time, and REC the series rebuilt from them.
        %
        %   Inputs
        %     G    (P,K) double  Slepian tapers, from shLowLevel.slepianBasis
        %     idx  (1,1) struct  the coefficient index they are ordered by
        %
        %   Outputs
        %     a    (K,T) double  the Slepian coefficients per epoch
        %     rec  (1,1) struct  as returned by shLowLevel.slepianProject,
        %          which documents every field
        %
        %   Example
        %     G = shLowLevel.slepianBasis(idx, @(la, lo) double(la > 60));
        %     a = ts.slepianProject(G, idx);
        arguments
            obj
            G
            idx
        end
        [a, rec] = shLowLevel.slepianProject(obj.Cs, obj.Ss, G, idx);
    end

    function B = regionalBasis(obj, region, opts)
        %REGIONALBASIS A local basis for a region, at this series's degree.
        %   B = ts.regionalBasis(REGION) is
        %   shLowLevel.regionalBasis(shLowLevel.shIndex(ts.nmax), REGION):
        %   radial basis functions, Slepian tapers or the SH basis for a
        %   basin or region, built for the degree this series carries, so
        %   that ts.regionalProject(B) cannot meet an index of another
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
        %     B = ts.regionalBasis("Elbe", Type = "slepian");
        %     a = ts.regionalProject(B);
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
        %REGIONALPROJECT Every epoch in a regional basis, and back.
        %   [A, REC] = ts.regionalProject(B) is
        %   shLowLevel.regionalProject(ts.Cs, ts.Ss, B): A holds the
        %   coefficients in the basis B of ts.regionalBasis per epoch,
        %   REC the series rebuilt from them.
        %
        %   Inputs
        %     B  (1,1) struct  a basis from regionalBasis
        %
        %   Outputs
        %     a    (K,T) double  basis coefficients
        %     rec  (1,1) struct  as returned by shLowLevel.regionalProject,
        %          which documents every field
        %
        %   Example
        %     B = ts.regionalBasis("Elbe");
        %     [a, rec] = ts.regionalProject(B);
        arguments
            obj
            B (1,1) struct
        end
        [a, rec] = shLowLevel.regionalProject(obj.Cs, obj.Ss, B);
    end

    function [model, info] = regionalProcessModel(obj, B, opts)
        %REGIONALPROCESSMODEL Kurtenbach's process model of this series in a basis.
        %   [MODEL, INFO] = ts.regionalProcessModel(B) is
        %   shLowLevel.regionalProcessModel(ts, B): the climatology of this
        %   model series is removed, every epoch projected onto the basis B
        %   of ts.regionalBasis, and the VAR process model of Kurtenbach
        %   (2012) estimated from the basis coefficients. That function
        %   documents the method and its two adjustments (QScale, the alpha
        %   of his eq. 4.8, and GroundNoise).
        %
        %   Inputs
        %     B  (1,1) struct  a basis from regionalBasis
        %
        %   Outputs
        %     model  (1,1) struct  as returned by
        %            shLowLevel.regionalProcessModel, which documents every
        %            field
        %     info   (1,1) struct  as returned by
        %            shLowLevel.regionalProcessModel, which documents every
        %            field
        %
        %   Options
        %     Order (lane default)  VAR order
        %     Shrink (lane default)  diagonal loading
        %     Structure (lane default)  "full" | "diagonal"
        %     CondFun (lane default)  covariance conditioning
        %     Climatology (lane default)  remove the climatology first
        %     QScale (lane default)  Kurtenbach's alpha
        %     GroundNoise (lane default)  isotropic ground noise [m EWH]
        %     kn (lane default)  load Love numbers, for GroundNoise
        %
        %   Example
        %     B = tsModel.regionalBasis("Elbe");
        %     [model, info] = tsModel.regionalProcessModel(B, QScale = 10);
        arguments
            obj
            B (1,1) struct
            opts.Order
            opts.Shrink
            opts.Structure
            opts.CondFun
            opts.Climatology
            opts.QScale
            opts.GroundNoise
            opts.kn
        end
        args = namedargs2cell(opts);
        [model, info] = shLowLevel.regionalProcessModel(obj, B, args{:});
    end

    function [tsK, out] = regionalKalman(obj, B, opts)
        %REGIONALKALMAN The regional Kalman filter on this series, in a basis.
        %   [TSK, OUT] = ts.regionalKalman(B, ModelSeries = TSM) is
        %   shLowLevel.regionalKalman(ts, B, ModelSeries = TSM): this
        %   series' coefficients and sigmas are the observations, the
        %   process model is estimated from TSM in the basis B of
        %   ts.regionalBasis, and the filter and RTS smoother run on the
        %   basis coefficients. TSK is the smoothed series T a with sigmas
        %   through T; OUT carries the basis coefficients and, with kn, the
        %   EWH grid of the region and its basin mean with sigma.
        %   shLowLevel.regionalKalman documents the chain and its oracle.
        %
        %   Inputs
        %     B  (1,1) struct  a basis from regionalBasis
        %
        %   Outputs
        %     tsK  (1,1) shSeries  the smoothed series T a
        %     out  (1,1) struct  as returned by shLowLevel.regionalKalman,
        %          which documents every field
        %
        %   Options
        %     ModelSeries (required)  the model series of the process
        %     Order (lane default)  VAR order
        %     Shrink (lane default)  diagonal loading
        %     Structure (lane default)  "full" | "diagonal"
        %     CondFun (lane default)  covariance conditioning
        %     QScale (lane default)  Kurtenbach's alpha, one per block
        %     QBlocks (lane default)  block label of every basis coefficient
        %     EstimateQScale (lane default)  estimate the alphas by maximum
        %         likelihood of the innovations
        %     GroundNoise (lane default)  isotropic ground noise [m EWH]
        %     kn (lane default)  load Love numbers, for the EWH outputs
        %     Epochs (lane default)  target epoch grid
        %     Tolerance (lane default)  epoch matching tolerance [yr]
        %     NoiseCov (lane default)  noise covariance of the series
        %     Climatology (lane default)  remove and restore it
        %     Lag (lane default)  smoothing lag in epochs
        %     QC (lane default)  innovation quality control
        %     QCAlpha (lane default)  its false-alarm level
        %     StoreCov (lane default)  "full" | "matfile"
        %     Background (lane default)  global background series, removed
        %         from the observations and restored (remove-compute-restore)
        %
        %   Example
        %     B = ts.regionalBasis("Elbe", Type = "slepian", Threshold = 0.5);
        %     [tsK, out] = ts.regionalKalman(B, ModelSeries = tsm, kn = kn);
        %     [tsK, out] = ts.regionalKalman(B, ModelSeries = tsm, kn = kn, ...
        %         Background = tsHydrologyModel);
        %     [tsK, out] = ts.regionalKalman(B, ModelSeries = tsm, ...
        %         EstimateQScale = true);           % alpha from the data
        arguments
            obj
            B (1,1) struct
            opts.ModelSeries
            opts.Order
            opts.Shrink
            opts.Structure
            opts.CondFun
            opts.QScale
            opts.QBlocks
            opts.EstimateQScale
            opts.GroundNoise
            opts.kn
            opts.Epochs
            opts.Tolerance
            opts.NoiseCov
            opts.Climatology
            opts.Lag
            opts.QC
            opts.QCAlpha
            opts.StoreCov
            opts.Background
        end
        args = namedargs2cell(opts);
        [tsK, out] = shLowLevel.regionalKalman(obj, B, args{:});
    end

    function [out, info] = bridgeGaps(obj, bridge, opts)
        %BRIDGEGAPS Fill the months this series lacks from a second series.
        %   [OUT, INFO] = ts.bridgeGaps(TSB) is shLowLevel.bridgeGaps(ts,
        %   TSB): it fills every month ts lacks within its span from the
        %   series TSB, calibrated on the months both have - an offset, a
        %   per-degree scale and a per-degree sigma - and names each filled
        %   month "bridge:" plus its name in TSB. Both series are truncated
        %   to the lower nmax and smoothed with a 750 km Gaussian unless
        %   told otherwise; shLowLevel.bridgeGaps documents the method, what
        %   it was measured to do on GRACE and HLSST, and why TN-14 comes
        %   first.
        %
        %   Inputs
        %     bridge  (1,1) shSeries  the series that fills the gaps
        %
        %   Outputs
        %     out   (1,1) shSeries  this series' months and the filled ones
        %     info  (1,1) struct  as returned by shLowLevel.bridgeGaps, which
        %           documents every field
        %
        %   Options
        %     RadiusKm (lane default)  Gaussian radius [km]; 0 for none
        %     Tolerance (lane default)  month matching [yr]
        %     MinOverlap (lane default)  the fewest matched months accepted
        %
        %   Example
        %     ts = ts.applyTN14(tnFile);
        %     [tsF, info] = ts.bridgeGaps(hlsst);
        arguments
            obj
            bridge
            opts.RadiusKm
            opts.Tolerance
            opts.MinOverlap
        end
        args = namedargs2cell(opts);
        [out, info] = shLowLevel.bridgeGaps(obj, bridge, args{:});
    end

    function [tbl, info] = excitation(obj, opts)
        %EXCITATION Earth-rotation excitation of the series' degree-2 terms.
        %   [TBL, INFO] = ts.excitation(Earth = E, kn = KN) runs
        %   shLowLevel.rotationExcitation on the series' C21 and S21 -
        %   Chen & Wilson (2003) eq. (1) solved for the excitation - and
        %   returns one row per epoch: t [yr], chi1 and chi2 [mas].
        %   shLowLevel.rotationExcitation documents the equation, the
        %   frame of chi2 (towards 90 E, not the IERS pole's 90 W) and the
        %   Earth's constants (IERS 2010 unless given).
        %
        %   [TBL, INFO] = ts.excitation(..., TN14 = TN) replaces C20 from
        %   the TN-14 table first (ts.applyTN14) and adds chi3, the axial
        %   excitation, and dLOD, the change in the length of day [ms].
        %   Without TN14 the axial term is refused - left out
        %   of the table - because GRACE determines C20 worst of all its
        %   coefficients, and a series cannot tell whether its C20 was
        %   replaced already. Passing TN14 makes it so either way.
        %
        %   Outputs
        %     tbl   table  one row per epoch: t [yr], chi1 and chi2 [mas],
        %           and chi3 (dimensionless) and dLOD [ms] when TN14 is
        %           given
        %     info  (1,1) struct  as returned by
        %           shLowLevel.rotationExcitation, which documents every field
        %
        %   Options
        %     Earth (lane default)  "IERS2010", or a struct with the Earth's
        %         M, R, C and A; see shLowLevel.rotationExcitation
        %     kn (required)  load Love numbers; kn(3) is k2'
        %     TN14 ([])  a TN-14 file name or a shLowLevel.readTN14 struct;
        %         gives chi3
        %     Tolerance (applyTN14 default)  epoch matching for TN14 [yr]
        %     Reference (lane default)  remove the series mean, or not
        %     PolarFactor (lane default)  the 1.098 of eq. (1)
        %     AxialFactor (lane default)  the 0.753 of eq. (1)
        %     Omega (lane default)  the Earth's mean angular velocity
        %
        %   Example
        %     tbl = ts.excitation(kn = kn, TN14 = tnFile);
        arguments
            obj
            opts.Earth
            opts.kn
            opts.TN14 = []
            opts.Tolerance
            opts.Reference
            opts.PolarFactor
            opts.AxialFactor
            opts.Omega
        end
        src = obj;
        fwd = rmfield(opts, intersect(fieldnames(opts), {'TN14', 'Tolerance'}));
        if ~isempty(opts.TN14)
            tnArgs = {};
            if isfield(opts, 'Tolerance')
                tnArgs = {'Tolerance', opts.Tolerance};
            end
            src = obj.applyTN14(opts.TN14, tnArgs{:});
            fwd.C20 = squeeze(src.Cs(3, 1, :));
        end
        args = namedargs2cell(fwd);
        [chi, info] = shLowLevel.rotationExcitation(squeeze(src.Cs(3, 2, :)), ...
            squeeze(src.Ss(3, 2, :)), args{:});
        tbl = table(obj.epochs, chi.chi1, chi.chi2, ...
            'VariableNames', {'t', 'chi1', 'chi2'});
        tbl.Properties.VariableUnits = {'yr', 'mas', 'mas'};
        if ~isempty(chi.chi3)
            tbl.chi3 = chi.chi3;
            tbl.dLOD = chi.dLOD;
            tbl.Properties.VariableUnits(end-1:end) = {'1', 'ms'};
        end
    end

    function disp(obj)
        %DISP Compact display: months, span, gaps, processing history.
        %   disp(TS) prints the product type, the number of epochs, the
        %   maximum degree and the covered epoch range, followed by the
        %   processing history. Called automatically when an shSeries
        %   object is shown without a semicolon.
        %
        %   Inputs
        %     obj  (1,1) shSeries  the series to display
        %   Outputs
        %     none - the summary is written to the command window
        %
        %   Example
        %     ts = shSeries.read("ITSG-Grace2018_n60_*.gfc");
        %     disp(ts)
        %
        %   Developed by Matthias Weigelt with the help of Claude (Fable 5).
        fprintf('  shSeries: %s | T=%d epochs | nmax=%d | %.4f..%.4f\n', ...
            obj.productType, obj.nEpochs, obj.nmax, ...
            min(obj.epochs), max(obj.epochs));
        fprintf('    history:\n');
        fprintf('      %s\n', obj.history);
    end
end

methods (Static)
    function obj = read(files, opts)
        %READ Read a series of gfc files (pattern or list), sorted by epoch.
        %   TS = shSeries.read("GSM-2_*.gfc") or shSeries.read(fileList).
        %   Inputs
        %     files  folder, file list or glob of monthly .gfc solutions
        %
        %   Outputs
        %     obj        (1 x 1) shSeries   wildcard-read, epoch-sorted stack
        %
        %   Options
        %     Truncate (NaN)  truncate every field to this nmax while
        %         reading (NaN: keep the file resolution)
        %
        %   Error identifiers
        %     shSeries:read:noFiles
        %         the pattern matched no file, or matched only provenance sidecars
        arguments
            files
            opts.Truncate (1,1) double = NaN
        end
        if (ischar(files) || (isstring(files) && isscalar(files))) ...
                && contains(string(files), ["*", "?"])
            d = dir(char(files));
            if isempty(d)
                error('shSeries:read:noFiles', 'Pattern matched no files: %s', ...
                    char(files));
            end
            list = string(fullfile({d.folder}, {d.name}))';
            % writeGFC drops "<file>.gfc.provenance.json" next to each
            % export, and the natural pattern "*.gfc*" (which has to be
            % loose enough for ".gfc.gz") matches those too - so a folder
            % written BY the toolbox could not be read back BY the
            % toolbox. Sidecars are metadata, never solutions.
            list = list(~endsWith(list, ".provenance.json"));
            if isempty(list)
                error('shSeries:read:noFiles', ...
                    'Pattern matched only provenance sidecars: %s', ...
                    char(files));
            end
        else
            list = string(files); list = list(:);
        end
        arr = shCoefficients.empty(0, 1);
        for k = 1:numel(list)
            g = shCoefficients.read(list(k));
            if ~isnan(opts.Truncate), g = g.truncate(opts.Truncate); end
            arr(k, 1) = g;
        end
        obj = shSeries(arr);
    end

    function obj = fromFolder(folder, opts)
        %FROMFOLDER Read every matching gfc file in a folder as a series.
        %   TS = shSeries.fromFolder(FOLDER)
        %   TS = shSeries.fromFolder(dest, Pattern="*n96*.gfc*", Truncate (NaN)=60)
        %   Convenience wrapper around shSeries.read (sorted by epoch);
        %   pairs with shLowLevel.fetchITSG, which downloads ITSG monthly
        %   solutions into <dataFolder>/series/itsg/monthly on demand.
        %   Outputs
        %     obj        (1 x 1) shSeries   all gfc(.gz) files of a folder, epoch-sorted
        %
        %   Error identifiers
        %     shSeries:fromFolder:noFiles
        %         FOLDER is not a folder
        %
        arguments
            folder (1,1) string
            opts.Pattern (1,1) string = "*.gfc*"
            opts.Truncate (1,1) double = NaN
        end
        assert(isfolder(folder), 'shSeries:fromFolder:noFiles', ...
            'Not a folder: %s', folder);
        obj = shSeries.read(string(fullfile(char(folder), ...
            char(opts.Pattern))), Truncate = opts.Truncate);
    end
end

methods (Access = private)
    function assertClean(obj, opname)
        if any(isnan(obj.Cs(:))) || any(isnan(obj.Ss(:)))
            error('shSeries:stack:nanInSeries', ...
                '%s requires NaN-free stacks - fill or drop gap epochs first.', ...
                opname);
        end
    end

    function X = flatten(obj)
        Nc = (obj.nmax + 1)^2;
        X = [reshape(obj.Cs, Nc, obj.nEpochs);
             reshape(obj.Ss, Nc, obj.nEpochs)];
    end

    function [Cs, Ss] = unflatten(obj, X)
        Nc = (obj.nmax + 1)^2;
        Cs = reshape(X(1:Nc, :), obj.nmax+1, obj.nmax+1, obj.nEpochs);
        Ss = reshape(X(Nc+1:end, :), obj.nmax+1, obj.nmax+1, obj.nEpochs);
    end
end
end

function y = sincPi(x)
% sin(pi*x)./(pi*x), 1 at x = 0. Base MATLAB: sinc is Signal Processing.
y = ones(size(x));
nz = x ~= 0;
y(nz) = sin(pi * x(nz)) ./ (pi * x(nz));
end

function rg = rangeToYears(rg)
% Accept [t1 t2] in decimal years or a 1 x 2 datetime; return 1 x 2 double.
if isdatetime(rg)
    yr = rg.Year;
    j0 = datetime(yr, 1, 1);
    j1 = datetime(yr + 1, 1, 1);
    rg = double(yr) + days(rg - j0) ./ days(j1 - j0);
end
rg = double(rg(:))';
assert(numel(rg) == 2 && all(isfinite(rg)) && rg(2) > rg(1), ...
    'shSeries:range:badRange', ...
    'Range must be [t1 t2] with t2 > t1 (decimal years or datetime).');
end

function info = meanWindowInfo(sub, rg, nTotal, nDropped, estimator, ep, atten)
% Coverage diagnostics for shSeries.mean.
contrib = false(1, sub.nEpochs);
for k = 1:sub.nEpochs
    contrib(k) = any(isfinite(sub.Cs(:,:,k)), 'all') ...
              || any(isfinite(sub.Ss(:,:,k)), 'all');
end
used = sort(sub.epochs(contrib(:) & isfinite(sub.epochs(:))));
info = struct('estimator', estimator, 'range', rg, ...
    'nUsed', numel(used), 'nTotal', nTotal, 'nDropped', nDropped, ...
    'span', [NaN NaN], 'coverage', NaN, 'maxGapYears', NaN, ...
    'centroidOffset', NaN, 'epoch', ep, 'attenuation', atten);
if isempty(used), return, end
info.span = [used(1), used(end)];
info.centroidOffset = mean(used) - 0.5 * (rg(1) + rg(2));
if numel(used) > 1
    dt = median(diff(used));
    info.coverage = min(1, numel(used) * dt / max(rg(2) - rg(1), eps));
    info.maxGapYears = max(diff(used));
end
end

function [ep, ord] = sortWithNaN(ep)
% sort by epoch, NaNs kept at the end in original order
[~, ord] = sort(ep);
ep = ep(ord);
end
