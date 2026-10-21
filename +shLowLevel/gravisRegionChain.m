function [gt, rep] = gravisRegionChain(region, folder, gravisFolder, opts)
%GRAVISREGIONCHAIN Shared engine of greenlandChain / antarcticaChain.
%
%   [GT, REP] = shLowLevel.gravisRegionChain(REGION, FOLDER,
%   GRAVISFOLDER, OPTS) is the common implementation behind the two
%   public ice chains; call those instead. REGION is "greenland" or
%   "antarctica"; OPTS is the (already argument-validated) option
%   struct of the wrappers. Stages: gravisL2B (with GIA) -> EWH
%   synthesis on a GridStep grid -> pixel-wise bias + trend + annual +
%   semiannual fit -> open-ocean residual RMS -> sigma_trend =
%   sigma_monthly / sqrt(Sxx) unless NoiseLevel is given -> regularised
%   leakage inversion over the basin mask (union with NeighbourBoxes) ->
%   mass integral over the basin mask [Gt/yr].
%
%   Inputs
%     region        (1,1) string  "greenland" | "antarctica"
%     folder        (1,1) string  monthly solution folder
%     gravisFolder  (1,1) string  GravIS aux folder
%     opts          (1,1) struct  see greenlandChain / antarcticaChain
%
%   Outputs
%     gt   (1,1) double  basin-mask mass trend [Gt/yr]
%     rep  (1,1) struct  fields
%          trendGrid   (nlat x nlon) double  the trend field [cm/yr EWH]
%          lat, lon    (1,:) double  the grid it is on [deg]
%          sigTrend    (nlat x nlon) double  its 1-sigma
%          residRMS    (1,1) double  RMS of the post-fit residual
%          mask        (nlat x nlon) logical  the region
%          unionMask   (nlat x nlon) logical  region plus the buffer the
%                      leakage step needed
%          m           (nlat x nlon) double  the inverted (leakage
%                      corrected) map
%          iterations  (1,1) double  leakage iterations run
%          stoppedBy   (1,1) string  why the iteration stopped
%          basins      table  per-polygon integrals; filled for
%                      antarctica, empty otherwise
%          steps       (1,K) string  the stages applied, with parameters
%          l2b         (1,1) struct  the shLowLevel.gravisL2B report
%          version     (1,1) string  shLowLevel.version at run time
%          created     (1,1) string  when the run happened
%
%   Example
%     % called for you by the wrappers; direct use mirrors them:
%     % [gt, rep] = shLowLevel.gravisRegionChain("greenland", ser, gd, opts)
%
%   Error identifiers
%     shLowLevel:gravisRegionChain:badFilter
%         Filter is neither "none" nor a valid "gauss<radiusKm>" for the
%         grid stage, as shLowLevel.filterSpec reads it. Before v5.7.0 a
%         radius that was not a number became NaN weights, and a negative
%         one weights of about 1 - no filter
%     shLowLevel:gravisRegionChain:missingBasins
%         the basin GeoJSON was not found
%     shLowLevel:gravisRegionChain:noKn
%         kn was not supplied; the chain will not assume a reference frame
%     shLowLevel:gravisRegionChain:noOcean
%         the default noise policy derives sigma_trend from the open-ocean
%         residual RMS, so OceanMask= or a numeric NoiseLevel= is required
%         - no coastline is ever assumed
%
%   Developed by Matthias Weigelt with the help of Claude (Fable 5),
%   2026-08-12 (v3.8.8).
arguments
    region (1,1) string {mustBeMember(region, ["greenland","antarctica"])}
    folder (1,1) string
    gravisFolder (1,1) string
    opts (1,1) struct
end
% the Filter spec is read FIRST, by the one parser of the vocabulary,
% so a malformed spec fails before any data is touched (A25)
[fspec, msg] = shLowLevel.filterSpec(opts.Filter, Allowed = ["none", "gauss"]);
if msg ~= ""
    error('shLowLevel:gravisRegionChain:badFilter', '%s', msg);
end
if isempty(opts.kn)
    error('shLowLevel:gravisRegionChain:noKn', ...
        ['Load Love numbers are required (kn=). The chain will not ' ...
         'assume a reference frame for you - see fetchLoveNumbers.']);
end
steps = strings(1, 0);
say = @(s) fprintf('  %s\n', s);
if opts.Quiet, say = @(s) []; end
% ---- basin polygons (GeoJSON -> readBasin regions -> masks, A33)
if strlength(gravisFolder) == 0
    gravisFolder = shLowLevel.gravisDataFolder();
end
bf = char(opts.BasinFile);
if ~isfile(bf), bf = fullfile(char(gravisFolder), bf); end
if ~isfile(bf)
    error('shLowLevel:gravisRegionChain:missingBasins', ...
        ['Basin GeoJSON not found: %s. Fetch it from ' ...
         'https://gravis.gfz.de/basins/GIS or /basins/AIS.'], opts.BasinFile);
end
[regs, binfo] = shLowLevel.readBasin(string.empty, File = string(bf));
% ---- trend grid: compute or reuse
if ~isempty(opts.TrendGrid)
    S = opts.TrendGrid;
    lat = S.lat(:); lon = S.lon(:);
    steps(end+1) = "reused a precomputed trend grid (TrendGrid=)";
else
    [ts, l2b] = shLowLevel.gravisL2B(folder, gravisFolder, ...
        GIAFile = opts.GIAFile, SpanEnd = opts.SpanEnd, Quiet = opts.Quiet);
    ep = ts.epochs(:); T = ts.nEpochs; nmax = ts.nmax;
    lat = (-90 + opts.GridStep/2 : opts.GridStep : 90)';
    lon = (opts.GridStep/2 : opts.GridStep : 360)';
    w = ones(nmax + 1, 1);
    if fspec.kind == "gauss"
        w = shLowLevel.shGaussianWeights(nmax, fspec.radiusKm); w = w(:);
    end
    E = zeros(numel(lat), numel(lon), T); P = [];
    for k = 1:T
        Ck = ts.Cs(:,:,k) .* w; Sk = ts.Ss(:,:,k) .* w;
        if isempty(P)
            [E(:,:,k), ~, ~, P] = shLowLevel.shSynthesis(Ck, Sk, opts.GM, ...
                opts.R, lat, lon, 'Quantity','ewh','kn',opts.kn,'Nmin',0);
        else
            E(:,:,k) = shLowLevel.shSynthesis(Ck, Sk, opts.GM, opts.R, ...
                lat, lon, 'Quantity','ewh','kn',opts.kn,'Nmin',0,'P',P);
        end
    end
    steps(end+1) = sprintf("synthesized %d EWH grids (%s, %g deg)", ...
        T, opts.Filter, opts.GridStep);
    A = [ones(T,1), ep-mean(ep), cos(2*pi*ep), sin(2*pi*ep), ...
         cos(4*pi*ep), sin(4*pi*ep)];
    X = reshape(E, [], T)';
    coef = A \ X;
    res = X - A * coef;
    trendGrid = reshape(coef(2,:), numel(lat), numel(lon));
    residRMS = reshape(rms(res, 1), numel(lat), numel(lon));
    Sxx = sum((ep - mean(ep)).^2);
    % open-ocean sigma and the TREND-matched noise (guide V4c). The
    % ocean mask is USER-SUPPLIED (oceanRMS contract - no coastline is
    % assumed), so the sigma_trend policy requires OceanMask=.
    if isempty(opts.OceanMask) && isnan(opts.NoiseLevel)
        error('shLowLevel:gravisRegionChain:noOcean', ...
            ['The default noise policy derives sigma_trend from the ' ...
             'open-ocean residual RMS, and the ocean mask is a caller ' ...
             'decision (see oceanRMS). Give OceanMask= (logical grid or ' ...
             '@(lat,lon) handle) or a numeric NoiseLevel=.']);
    end
    sigMon = NaN;
    if ~isempty(opts.OceanMask)
        sigMon = shLowLevel.oceanRMS(residRMS, lat, lon, opts.OceanMask);
    end
    S = struct('trendGrid', trendGrid, 'lat', lat, 'lon', lon, ...
        'residRMS', residRMS, 'sigTrend', sigMon / sqrt(Sxx));
    steps(end+1) = sprintf("pixel fit: sigma_mon %.4g m -> sigma_trend %.3g m/yr", ...
        sigMon, S.sigTrend);
end
% ---- masks (readBasin's wrap-safe regions, A33: a ring around the pole
% is closed through it, holes are holes)
[LO, LA] = meshgrid(lon, lat);
mask = false(size(LA));
basinMasks = cell(numel(regs), 1);
for k = 1:numel(regs)
    mk = regs{k}(LA, LO) > 0;
    basinMasks{k} = mk; mask = mask | mk;
end
unionMask = mask;
for b = 1:size(opts.NeighbourBoxes, 1)
    bx = opts.NeighbourBoxes(b, :);
    unionMask = unionMask | (LA >= bx(1) & LA <= bx(2) & ...
        LO >= bx(3) & LO <= bx(4));
end
steps(end+1) = sprintf("mask: %d basin pixels, union %d", nnz(mask), nnz(unionMask));
% ---- inversion + mass
noise = opts.NoiseLevel;
if isnan(noise), noise = S.sigTrend; end
[m, info] = shLowLevel.leakageCorrect(S.trendGrid, lat, lon, ...
    Mask = unionMask, Filter = opts.Filter, NoiseLevel = noise, ...
    MaxIter = opts.MaxIter, Quiet = true);
steps(end+1) = sprintf("leakage inversion: %d iterations, stopped by %s", ...
    info.iterations, info.stoppedBy);
gt = local_mass(m, lat, lon, mask);
say(sprintf('%s: %+.1f Gt/yr (%d it, %s)', region, gt, ...
    info.iterations, info.stoppedBy));
rep = struct('trendGrid', S.trendGrid, 'lat', lat, 'lon', lon, ...
    'sigTrend', S.sigTrend, 'mask', mask, 'unionMask', unionMask, ...
    'm', m, 'iterations', info.iterations, 'stoppedBy', string(info.stoppedBy), ...
    'steps', steps, 'version', shLowLevel.version(), ...
    'created', string(datetime('now')));
if isfield(S, 'residRMS'), rep.residRMS = S.residRMS; end
if exist('l2b', 'var'), rep.l2b = l2b; end
if region == "antarctica"
    K = numel(basinMasks);
    nm = strings(K,1); gtb = zeros(K,1);
    for k = 1:K
        nm(k) = binfo(k).name;
        gtb(k) = local_mass(m, lat, lon, basinMasks{k});
    end
    rep.basins = table(nm, gtb, 'VariableNames', {'name', 'gt'});
end
end

function gt = local_mass(m, lat, lon, mask)
Re = 6371e3;
dphi = deg2rad(abs(lat(2)-lat(1))); dlam = deg2rad(abs(lon(2)-lon(1)));
[~, LA] = meshgrid(lon, lat);
A = (Re^2) * cosd(LA) * dphi * dlam;
gt = sum(m(mask) .* A(mask), 'omitnan') * 1000 / 1e12;
end

