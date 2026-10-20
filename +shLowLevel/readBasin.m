function [region, info] = readBasin(name, opts)
%READBASIN A basin of a GravIS GeoJSON file as a region, by name.
%
%   [REGION, INFO] = shLowLevel.readBasin(NAME) finds the basin NAME in
%   the GravIS river-basin file shipped with the toolbox
%   (data/gravis/basins_rivbas.json, 100 basins) and returns it as a
%   REGION function handle, m = REGION(latDeg, lonDeg), 1 inside and 0
%   outside, that every region-taking function accepts (evalMask,
%   basinKernel, slepianBasis, regionalBasis). The match is exact first,
%   then case-insensitive, then a case-insensitive substring that only
%   ONE basin contains - so "Elbe" finds "Elbe River" - and INFO.name
%   says which basin was taken. A substring two basins contain is
%   refused rather than resolved.
%
%   The handle is wrap-safe, which a [lat lon] polygon in [0, 360) is
%   not: GeoJSON rings are [lon lat] in (-180, 180], and three rivbas
%   basins (Loire, Niger, Volta) cross lon 0, where shLowLevel.evalMask's
%   planar polygon test breaks. Each ring's longitudes are unwrapped
%   along the ring; a ring that winds through 360 degrees encircles a
%   pole and is closed through it (Antarctic basins); a query longitude
%   is tried at lon and lon +- 360. Inside a polygon means inside its
%   first ring and in none of the later ones (GeoJSON holes); a
%   MultiPolygon is the union of its polygons. Points on a ring count as
%   inside (inpolygon's rule). Edges are straight in (lon, lat), not great
%   circles - the GeoJSON convention; for every rivbas basin the two
%   differ by less than 1e-4 of the area (measured: worst 4.3e-5,
%   Issyk-kul; Elbe 1.5e-6).
%
%   Inputs
%     name  (1,1) string  basin name, or a unique part of one ("Elbe")
%
%   Options
%     File ("basins_rivbas.json")  (1,1) string  a GeoJSON file: a path,
%           or a name looked up in the toolbox's data/gravis folder
%           (basins_rivbas.json, basins_GIS.json, basins_AIS.json ship
%           there; https://gravis.gfz.de/basins for more)
%
%   Outputs
%     region  function handle  m = region(latDeg, lonDeg): equal-size
%             double arrays in, a double array of 0/1 of the same size
%             out; lon may be in any range
%     info    (1,1) struct  fields
%             name       (1,1) string  the basin actually taken
%             file       (1,1) string  the file it was read from
%             names      (N,1) string  every basin name in the file
%             rings      (1,R) cell  each ring as a (K,2) double
%                        [latDeg lonDeg], longitudes as in the file
%             hole       (1,R) logical  the ring is a hole of its polygon
%             polar      (1,R) logical  the ring winds around a pole
%             polygon    (1,R) double  which polygon each ring belongs to
%             properties (1,1) struct  the feature's GeoJSON properties
%
%   Example
%     [reg, info] = shLowLevel.readBasin("Elbe");
%     idx = shLowLevel.shIndex(60);
%     B = shLowLevel.regionalBasis(idx, reg, Type = "slepian");
%
%   Error identifiers
%     shLowLevel:readBasin:missingFile
%         the GeoJSON file is neither a path nor in data/gravis
%     shLowLevel:readBasin:unknownBasin
%         no basin name matches NAME, even as a substring
%     shLowLevel:readBasin:ambiguousBasin
%         NAME is a substring of several basin names
%     shLowLevel:readBasin:badGeometry
%         the feature is not a Polygon or MultiPolygon with [lon lat] rings
%
%   Developed by Matthias Weigelt with the help of Claude (Opus 5.5),
%   2026-10-20.
arguments
    name (1,1) string
    opts.File (1,1) string = "basins_rivbas.json"
end
file = opts.File;
if ~isfile(file)
    root = fileparts(fileparts(mfilename('fullpath')));
    cand = fullfile(root, 'data', 'gravis', char(file));
    if ~isfile(cand)
        error('shLowLevel:readBasin:missingFile', ...
            ['Basin file %s is neither a path nor in the toolbox''s ' ...
             'data/gravis folder.'], file);
    end
    file = string(cand);
end
J = jsondecode(fileread(file));
feats = J.features;                 % a struct array, or a cell when the
if ~iscell(feats)                   % features do not share their fields
    feats = num2cell(feats);
end
names = strings(numel(feats), 1);
for k = 1:numel(feats)
    names(k) = string(feats{k}.properties.name);
end
hit = find(names == name);
if isempty(hit), hit = find(strcmpi(names, name)); end
if isempty(hit), hit = find(contains(lower(names), lower(name))); end
if isempty(hit)
    list = strjoin(names(1:min(end, 12)), ', ');
    if numel(names) > 12, list = list + ", ..."; end
    error('shLowLevel:readBasin:unknownBasin', ...
        'No basin in %s matches "%s". The file holds: %s.', file, name, list);
elseif numel(hit) > 1
    error('shLowLevel:readBasin:ambiguousBasin', ...
        '"%s" matches %d basins in %s: %s. Give more of the name.', ...
        name, numel(hit), file, strjoin(names(hit), ', '));
end
f = feats{hit};
g = f.geometry;
switch string(g.type)
    case "Polygon"
        polys = {ringList(g.coordinates)};
    case "MultiPolygon"
        c = g.coordinates;
        if iscell(c)
            polys = cellfun(@ringList, c(:)', 'UniformOutput', false);
        else
            sz = size(c);
            polys = cell(1, sz(1));
            for p = 1:sz(1)
                polys{p} = ringList(reshape(c(p, :), [sz(2:end), 1]));
            end
        end
    otherwise
        error('shLowLevel:readBasin:badGeometry', ...
            'Basin "%s" has geometry %s; only Polygon and MultiPolygon are read.', ...
            names(hit), g.type);
end
rings = {}; hole = false(1, 0); poly = zeros(1, 0);
for p = 1:numel(polys)
    for r = 1:numel(polys{p})
        rings{end + 1} = polys{p}{r}; %#ok<AGROW>
        hole(end + 1) = r > 1; %#ok<AGROW>
        poly(end + 1) = p; %#ok<AGROW>
    end
end
if isempty(rings)
    error('shLowLevel:readBasin:badGeometry', ...
        'Basin "%s" has no rings.', names(hit));
end
U = cellfun(@unwrapRing, rings, 'UniformOutput', false);
polar = cellfun(@(u) u.polar, U);
region = @(lat, lon) inside(lat, lon, U, poly);
info = struct('name', names(hit), 'file', string(file), 'names', names, ...
    'rings', {rings}, 'hole', hole, 'polar', polar, 'polygon', poly, ...
    'properties', f.properties);
end

function rings = ringList(c)
% The rings of one polygon as [latDeg lonDeg] matrices, from what
% jsondecode makes of [[[lon, lat], ...], ...]: a cell of (K,2) rings when
% their lengths differ, an (R,K,2) array when they agree.
if iscell(c)
    rings = cellfun(@swapRing, c(:)', 'UniformOutput', false);
    return
end
sz = size(c);
if numel(sz) == 2 && sz(2) == 2
    rings = {swapRing(c)};
    return
end
if sz(end) ~= 2
    error('shLowLevel:readBasin:badGeometry', ...
        'A ring is not a list of [lon lat] pairs.');
end
c = reshape(c, [], sz(end - 1), 2);
rings = cell(1, size(c, 1));
for r = 1:size(c, 1)
    rings{r} = swapRing(reshape(c(r, :, :), sz(end - 1), 2));
end
end

function r = swapRing(c)
if ~isnumeric(c) || size(c, 2) ~= 2 || size(c, 1) < 3
    error('shLowLevel:readBasin:badGeometry', ...
        'A ring is not a list of at least three [lon lat] pairs.');
end
r = double([c(:, 2), c(:, 1)]);
end

function u = unwrapRing(r)
% Unwrapped longitudes along the ring; a ring winding through 360 deg
% encircles a pole and is closed through it.
lat = r(:, 1); lon = r(:, 2);
d = mod(diff(lon) + 180, 360) - 180;
lu = [lon(1); lon(1) + cumsum(d)];
u.polar = abs(lu(end) - lu(1)) > 180;
if u.polar
    pole = 90 * sign(mean(lat));
    lu = [lu; lu(end); lu(1)];
    lat = [lat; pole; pole];
end
u.lon = lu; u.lat = lat;
end

function m = inside(lat, lon, U, poly)
sz = size(lat);
lat = lat(:); lon = mod(lon(:) + 180, 360) - 180;
m = false(numel(lat), 1);
for p = unique(poly)
    rs = find(poly == p);
    inP = inRing(lat, lon, U{rs(1)});
    for r = rs(2:end)
        inP = inP & ~inRing(lat, lon, U{r});
    end
    m = m | inP;
end
m = reshape(double(m), sz);
end

function t = inRing(lat, lon, u)
t = inpolygon(lon, lat, u.lon, u.lat) | ...
    inpolygon(lon - 360, lat, u.lon, u.lat) | ...
    inpolygon(lon + 360, lat, u.lon, u.lat);
end
