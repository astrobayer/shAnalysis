function [out, rep] = twsChain(folder, gravisFolder, opts)
%TWSCHAIN The validated GravIS terrestrial-water-storage basin chain.
%
%   [OUT, REP] = shLowLevel.twsChain(FOLDER, GRAVISFOLDER, kn=KN)
%   reproduces guide chapter V8: gravisL2B corrections WITH the
%   ICE-6G_D GIA rate (the GravIS TWS product carries this correction
%   even though its Technical Note omits it - subtracting it took the
%   trend RMS from 0.225 to 0.032 cm/yr), a DDK3 filter as the declared
%   stand-in for GravIS' VDK5/VDK3 blend, and cos-weighted 1-degree
%   basin means in cm EWH computed by per-basin bounding-box synthesis
%   with Legendre recycling (about 1 ms per epoch and basin). With the
%   tested defaults, the COST-G RL02.1 series and the GravIS river
%   basins, eleven major basins reproduce the GravIS portal series at a
%   median amplitude ratio of 1.001 and 0.032 cm/yr trend RMS over the
%   full 252-month span. Every input is exchangeable.
%
%   Inputs
%     folder        (1,1) string  monthly GSM-2_*.gfc folder
%     gravisFolder  (1,1) string  GravIS aux folder; "" (default) uses
%                   the shipped data/gravis copies (see gravisL2B);
%                   must also hold BasinFile and, for the default
%                   filter, the DDK binary unless full paths are given
%
%   Options
%     kn         ([])  load Love numbers k'_n, one column for degrees
%                0..nmax (kn(1) is degree 0), passed to
%                shLowLevel.kernelFactors - REQUIRED, the empty default
%                errors: no frame is assumed
%     BasinFile  ("basins_rivbas.json")  GravIS GeoJSON of the target
%                basins ([lon lat] rings, read by shLowLevel.readBasin;
%                https://gravis.gfz.de/basins/rivbas): a path, else
%                looked up in GRAVISFOLDER, else in the shipped
%                data/gravis folder (since v5.31.3)
%     Basins     (strings(0,1))  feature names to process; the empty
%                default processes every feature in BasinFile
%     Filter     ("DDK3")  "none" | "gaussN" | "DDKn" (n = 1..8) | a W
%                struct from shLowLevel.readDDK
%     DDKFolder  ("")  folder holding the Wbd_2-120.a_* binaries for
%                the "DDKn" shorthand, searched first; the empty
%                default makes that first candidate the bare file name,
%                i.e. the current folder. Then GRAVISFOLDER, then
%                <dataFolder>/DDK, where shLowLevel.fetchDDK stores them
%     GIAFile    ("GRAVIS-2B_COSTG_0200_GIA_ICE-6G_D_VM5a_0001.gz")
%                "" disables the GIA step - and reproduces the 7x
%                larger trend RMS documented in V8
%     SpanEnd    (Inf)  the TWS validation uses the full record
%     GridStep   (1)    basin-box synthesis step [deg]
%     GM         (3.986004415e14), R (6378136.3)
%     Quiet      (false)
%
%   Outputs
%     out  (1,1) struct  fields
%          name       (K,1) string  basin names, in the row order below
%          epochs     (T,1) double  the epoch grid [decimal years]
%          series     (K x T) double  basin means [cm EWH]
%          trend      (K,1) double  per-basin trend [cm/yr]
%          amplitude  (K,1) double  annual amplitude [cm]
%          phase      (K,1) double  annual phase [rad]
%     rep  (1,1) struct  fields
%          steps    (1,K) string  the stages applied, with parameters
%          filter   (1,1) string  the filter actually used
%          l2b      (1,1) struct  the shLowLevel.gravisL2B report
%          version  (1,1) struct  shLowLevel.version() at run time
%          created  (1,1) string  when the run happened
%
%   Example
%     kn = readmatrix("loadLoveNumbers_Gegout97.txt", FileType="text", ...
%         NumHeaderLines=2);
%     [out, rep] = shLowLevel.twsChain("E:/series/COSTG", "E:/GravIS", ...
%         kn = kn, Basins = ["Amazonas", "Congo", "Danube"]);
%     plot(out.epochs, out.series); legend(out.name)
%
%   Error identifiers
%     shLowLevel:twsChain:badFilter
%         Filter is refused by shLowLevel.filterSpec: it is not a W
%         struct, "none", "gauss<radiusKm>" or "DDK1" to "DDK8"
%     shLowLevel:twsChain:emptyBasin
%         a basin covers no grid point at the chosen GridStep
%     shLowLevel:twsChain:missingBasins
%         the basin GeoJSON is not a path and in neither GRAVISFOLDER
%         nor data/gravis
%     shLowLevel:twsChain:missingDDK
%         the DDK binary was in none of the searched folders
%     shLowLevel:twsChain:noKn
%         kn was not supplied; the chain will not assume a reference frame
%     shLowLevel:twsChain:unknownBasin
%         a requested basin name is not in the GeoJSON
%
%   Developed by Matthias Weigelt with the help of Claude (Fable 5),
%   2026-08-12 (v3.8.8).
arguments
    folder (1,1) string
    gravisFolder (1,1) string = ""
    opts.kn double = []
    opts.BasinFile (1,1) string = "basins_rivbas.json"
    opts.Basins string = strings(0, 1)
    opts.Filter = "DDK3"
    opts.DDKFolder (1,1) string = ""
    opts.GIAFile (1,1) string = "GRAVIS-2B_COSTG_0200_GIA_ICE-6G_D_VM5a_0001.gz"
    opts.SpanEnd (1,1) double = Inf
    opts.GridStep (1,1) double {mustBePositive} = 1
    opts.GM (1,1) double = 3.986004415e14
    opts.R (1,1) double = 6378136.3
    opts.Quiet (1,1) logical = false
end
% the Filter spec is read FIRST, by the one parser of the vocabulary,
% so a malformed spec fails before any data is touched (A25)
[fspec, msg] = shLowLevel.filterSpec(opts.Filter);
if msg ~= ""
    error('shLowLevel:twsChain:badFilter', '%s', msg);
end
if isempty(opts.kn)
    error('shLowLevel:twsChain:noKn', ...
        ['Load Love numbers are required (kn=). The chain will not ' ...
         'assume a reference frame for you - see fetchLoveNumbers.']);
end
if strlength(gravisFolder) == 0
    gravisFolder = shLowLevel.gravisDataFolder();
end
steps = strings(1, 0);
% ---- corrected series (GIA on by default: guide V8)
[ts, l2b] = shLowLevel.gravisL2B(folder, gravisFolder, ...
    GIAFile = opts.GIAFile, SpanEnd = opts.SpanEnd, Quiet = opts.Quiet);
ep = ts.epochs(:); T = ts.nEpochs; nmax = ts.nmax;
% ---- filter (the spec was read before the data)
Cs = ts.Cs; Ss = ts.Ss; filtName = "custom W";
switch fspec.kind
    case "W"
        ts = ts.applyDDK(fspec.W); Cs = ts.Cs; Ss = ts.Ss;
    case "none"
        filtName = "none";
    case "gauss"
        w = shLowLevel.shGaussianWeights(nmax, fspec.radiusKm); w = w(:);
        for k = 1:T
            Cs(:,:,k) = Cs(:,:,k) .* w; Ss(:,:,k) = Ss(:,:,k) .* w;
        end
        filtName = fspec.name;
    otherwise
        % the released file names have one home, shLowLevel.ddkNames
        % (this chain carried its own copy of the eight until v5.7.0)
        fn = shLowLevel.ddkNames(); fn = fn(fspec.ddk);
        % fetchDDK stores the files in <dataFolder>/DDK. The lower-case
        % 'ddk' this chain used to look in is kept for files placed there
        % by hand: the two are one folder on Windows, two on Linux and
        % macOS, where a fetched file was not found here (A26)
        % a string column: before v5.23.4 this was char rows joined with
        % [;], a dimension error whenever two paths differ in length -
        % that is, on every default (Filter = "DDK3") call
        cand = [string(fullfile(char(opts.DDKFolder), char(fn))); ...
                string(fullfile(char(gravisFolder), char(fn))); ...
                string(fullfile(shLowLevel.dataFolder(), 'DDK', char(fn))); ...
                string(fullfile(shLowLevel.dataFolder(), 'ddk', char(fn)))];
        fp = "";
        for c = 1:numel(cand)
            if isfile(cand(c)), fp = cand(c); break; end
        end
        if strlength(fp) == 0
            error('shLowLevel:twsChain:missingDDK', ...
                ['DDK binary %s not found (DDKFolder, GRAVISFOLDER, data ' ...
                 'folder). Get it from github.com/strawpants/GRACE-filter.'], fn);
        end
        W = shLowLevel.readDDK(fp);
        ts = ts.applyDDK(W); Cs = ts.Cs; Ss = ts.Ss;
        filtName = fspec.name;
end
steps(end+1) = "filter: " + filtName;
% ---- basins
% a path, else GRAVISFOLDER, else the shipped data/gravis copy: the
% polygons do not trail the solutions as the tables do (v5.31.3)
bf = "";
for c = [string(opts.BasinFile), ...
        string(fullfile(char(gravisFolder), char(opts.BasinFile))), ...
        string(fullfile(char(shLowLevel.gravisDataFolder()), char(opts.BasinFile)))]
    if isfile(c), bf = c; break; end
end
if strlength(bf) == 0
    error('shLowLevel:twsChain:missingBasins', ...
        ['Basin GeoJSON not found: %s (not a path, not in GRAVISFOLDER, ' ...
         'not in data/gravis). Fetch it from ' ...
         'https://gravis.gfz.de/basins/rivbas.'], opts.BasinFile);
end
[regs, binfo] = shLowLevel.readBasin(string.empty, File = string(bf));
allN = [binfo.name].';
want = opts.Basins;
if isempty(want), want = allN; end
miss = setdiff(want, allN);
if ~isempty(miss)
    error('shLowLevel:twsChain:unknownBasin', ...
        'Basin(s) not in %s: %s', opts.BasinFile, strjoin(miss, ', '));
end
K = numel(want);
% ---- per-basin box synthesis (Legendre recycled across epochs)
series = zeros(K, T);
for k = 1:K
    % the basin box from its outer rings ([lat lon], as the GeoJSON has
    % them), the mask from readBasin's wrap-safe region (A33)
    kb = find(allN == want(k), 1);
    bi = binfo(kb);
    Pall = vertcat(bi.rings{~bi.hole});
    la1 = floor(min(Pall(:,1))) - 1; la2 = ceil(max(Pall(:,1))) + 1;
    latB = (la1 + opts.GridStep/2 : opts.GridStep : la2)';
    c0 = atan2d(mean(sind(Pall(:,2))), mean(cosd(Pall(:,2))));
    lw = mod(Pall(:,2) - c0 + 180, 360) - 180;
    lo1 = floor(min(lw)) - 1; lo2 = ceil(max(lw)) + 1;
    off = (lo1 + opts.GridStep/2 : opts.GridStep : lo2)';
    lonB = mod(c0 + off, 360);
    [LOc, LAb] = meshgrid(off, latB);
    mkB = regs{kb}(LAb, c0 + LOc) > 0;
    if ~any(mkB(:))
        error('shLowLevel:twsChain:emptyBasin', ...
            'Basin %s covers no grid point at GridStep %g.', want(k), opts.GridStep);
    end
    wB = cosd(LAb); P = [];
    for t = 1:T
        if isempty(P)
            [E, ~, ~, P] = shLowLevel.shSynthesis(Cs(:,:,t), Ss(:,:,t), ...
                opts.GM, opts.R, latB, lonB, 'Quantity','ewh','kn',opts.kn,'Nmin',0);
        else
            E = shLowLevel.shSynthesis(Cs(:,:,t), Ss(:,:,t), opts.GM, ...
                opts.R, latB, lonB, 'Quantity','ewh','kn',opts.kn,'Nmin',0,'P',P);
        end
        series(k, t) = sum(E(mkB) .* wB(mkB)) / sum(wB(mkB)) * 100;
    end
end
steps(end+1) = sprintf("basin means: %d basins x %d epochs", K, T);
% ---- fits
A = [ones(T,1), ep-mean(ep), cos(2*pi*ep), sin(2*pi*ep), cos(4*pi*ep), sin(4*pi*ep)];
X = (A \ series')';
trend = X(:, 2);
amplitude = hypot(X(:, 3), X(:, 4));
phase = atan2(X(:, 4), X(:, 3));
if ~opts.Quiet
    for k = 1:K
        fprintf('  %-28s trend %+6.2f cm/yr  amp %5.1f cm\n', ...
            want(k), trend(k), amplitude(k));
    end
end
out = struct('name', want(:), 'epochs', ep, 'series', series, ...
    'trend', trend, 'amplitude', amplitude, 'phase', phase);
rep = struct('steps', steps, 'filter', filtName, 'l2b', l2b, ...
    'version', shLowLevel.version(), 'created', string(datetime('now')));
end
