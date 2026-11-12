function rep = bprCompare(obp, station, opts)
%BPRCOMPARE A bottom-pressure recorder against an obpChain grid.
%
%   REP = shLowLevel.bprCompare(OBP, STATION) compares the series of one
%   ocean-bottom-pressure recorder with the GRACE ocean-bottom-pressure
%   field of shLowLevel.obpChain at the nearest ocean pixel (great-circle
%   distance, across lon 0/360; NaN pixels are land). Both series are
%   taken as anomalies about their mean over the epochs they share, in cm
%   of equivalent water height; a recorder in hPa is converted with
%       1 hPa = 100 / (RhoWater g) m,   1.019716 cm for 1000 and 9.80665.
%   WP9 9j. A recorder sees the full column, water and air, as
%   obpChain's field does (GAD restored, nothing subtracted); its drift
%   and tides must be removed before - that is the recorder's processing,
%   not this toolbox's.
%
%   Metrics, o the recorder and g the grid anomalies:
%     correlation  shLowLevel.effectiveCorr(o, g) (AR(1)-corrected)
%     nse          1 - sum (o - g)^2 / sum o^2
%     rms          sqrt(mean (o - g)^2)
%     gain         sum o g / sum g^2, the slope of o on g
%     ampRatio     std(g) / std(o)
%   Validated in tools/dev/validate_ocean_validation.py CLAIM 4 (the
%   conversion, the pixel across lon 0/360, the formulas to 1.1e-16).
%
%   Inputs
%     obp      (1,1) struct  an shLowLevel.obpChain output: grid (nLat x
%              nLon x T) [cm EWH], lat (nLat,1), lon (nLon,1) [deg],
%              epochs (T,1)
%     station  (1,1) struct  fields lat, lon [deg] (scalars), epochs
%              (M,1) [decimal years], value (M,1)
%
%   Options
%     Units ("hPa")       "hPa" | "cm"   the unit of station.value; "cm" is
%                         cm of equivalent water height
%     Tolerance (0.05)    (1,1) double  max |epoch difference| [yr];
%                         pairs are one-to-one
%     RhoWater (1000)     (1,1) double  [kg/m^3]
%     G (9.80665)         (1,1) double  gravity [m/s^2] for the conversion
%
%   Outputs
%     rep  (1,1) struct  fields
%          pixel        (1,2) double  [lat lon] of the pixel used [deg]
%          distanceKm   (1,1) double  station to pixel, on a sphere of
%                       6371 km
%          nEpochs      (1,1) double  common epochs used
%          epochs       (T,1) double  their epochs (the recorder's)
%          station      (T,1) double  recorder anomaly [cm EWH]
%          grace        (T,1) double  grid anomaly [cm EWH]
%          correlation  (1,1) struct  shLowLevel.effectiveCorr, which
%                       documents every field
%          nse          (1,1) double  Nash-Sutcliffe efficiency
%          rms          (1,1) double  RMS difference [cm]
%          gain         (1,1) double  slope of the recorder on the grid
%          ampRatio     (1,1) double  std(grid) / std(recorder)
%
%   Example
%     [out, ~] = shLowLevel.obpChain(folder, kn = kn, OceanMask = oc, ...
%         GADFolder = gad);
%     bpr = struct('lat', -57.5, 'lon', 295, 'epochs', t, 'value', p_hPa);
%     rep = shLowLevel.bprCompare(out, bpr);
%     fprintf("r = %.2f, NSE = %.2f\n", rep.correlation.r, rep.nse)
%
%   Error identifiers
%     shLowLevel:bprCompare:badInput
%         OBP lacks grid, lat, lon or epochs, or STATION lacks lat, lon,
%         epochs or value, or their sizes disagree
%     shLowLevel:bprCompare:noOcean
%         the grid has no finite pixel
%     shLowLevel:bprCompare:ambiguousEpochs
%         an epoch of one series lies within Tolerance of two of the other
%     shLowLevel:bprCompare:tooFewEpochs
%         fewer than 8 epochs are common to the recorder and the grid
%
%   Developed by Matthias Weigelt with the help of Claude (Opus 5.5),
%   2026-11-12 (WP9 9j).
arguments
    obp (1,1) struct
    station (1,1) struct
    opts.Units (1,1) string {mustBeMember(opts.Units, ["hPa", "cm"])} = "hPa"
    opts.Tolerance (1,1) double {mustBePositive} = 0.05
    opts.RhoWater (1,1) double {mustBePositive} = 1000
    opts.G (1,1) double {mustBePositive} = 9.80665
end
if ~all(isfield(obp, {'grid', 'lat', 'lon', 'epochs'})) || ...
        ~all(isfield(station, {'lat', 'lon', 'epochs', 'value'}))
    error('shLowLevel:bprCompare:badInput', ...
        'OBP needs grid, lat, lon and epochs; STATION lat, lon, epochs and value.');
end
la = obp.lat(:);
lo = obp.lon(:);
te = obp.epochs(:);
if size(obp.grid, 1) ~= numel(la) || size(obp.grid, 2) ~= numel(lo) || ...
        size(obp.grid, 3) ~= numel(te) || ~isscalar(station.lat) || ...
        ~isscalar(station.lon) || numel(station.epochs) ~= numel(station.value)
    error('shLowLevel:bprCompare:badInput', ...
        'The grid must be numel(lat) x numel(lon) x numel(epochs), the station one point.');
end
% the nearest ocean pixel
ocean = any(isfinite(obp.grid), 3);
if ~any(ocean(:))
    error('shLowLevel:bprCompare:noOcean', 'The grid has no finite pixel.');
end
[LO, LA] = meshgrid(lo, la);
c = sind(station.lat) .* sind(LA) + cosd(station.lat) .* cosd(LA) .* cosd(LO - station.lon);
c(~ocean) = -Inf;
[cmax, ip] = max(c(:));
[i, j] = ind2sub(size(c), ip);
gser = squeeze(obp.grid(i, j, :));
% the recorder in cm EWH
v = double(station.value(:));
if opts.Units == "hPa"
    v = v * 100 / (opts.RhoWater * opts.G) * 100;
end
ts = double(station.epochs(:));
k = NaN(numel(ts), 1);
for n = 1:numel(ts)
    near = find(abs(te - ts(n)) <= opts.Tolerance);
    if numel(near) > 1
        error('shLowLevel:bprCompare:ambiguousEpochs', ...
            '%d grid epochs lie within Tolerance of the recorder''s %.4f.', ...
            numel(near), ts(n));
    end
    if isscalar(near), k(n) = near; end
end
kk = k(~isnan(k));
if numel(unique(kk)) < numel(kk)
    error('shLowLevel:bprCompare:ambiguousEpochs', ...
        'A grid epoch lies within Tolerance of two recorder epochs.');
end
use = ~isnan(k) & isfinite(v);
use(use) = isfinite(gser(k(use)));
if nnz(use) < 8
    error('shLowLevel:bprCompare:tooFewEpochs', ...
        'The recorder and the grid share %d finite epochs; at least 8 are needed.', nnz(use));
end
o = v(use);
g = gser(k(use));
o = o - mean(o);
g = g - mean(g);
rep = struct('pixel', [la(i), lo(j)], ...
    'distanceKm', 6371 * acos(min(max(cmax, -1), 1)), ...
    'nEpochs', nnz(use), 'epochs', ts(use), 'station', o, 'grace', g, ...
    'correlation', shLowLevel.effectiveCorr(o, g), ...
    'nse', 1 - sum((o - g).^2) / sum(o.^2), ...
    'rms', sqrt(mean((o - g).^2)), ...
    'gain', sum(o .* g) / sum(g.^2), ...
    'ampRatio', std(g) / std(o));
end
