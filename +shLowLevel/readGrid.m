function [grid, latDeg, lonDeg, info] = readGrid(filename, opts)
%READGRID Read a gridded field or stack from a CF netCDF file.
%   [GRID, LAT, LON, INFO] = shLowLevel.readGrid(FILE) reads the one
%   latitude-longitude field in FILE - a 2-D grid, or a 3-D stack with a
%   time axis - and returns it in the toolbox's layout: GRID is
%   (nlat x nlon) or (nlat x nlon x T), LAT and LON are column vectors
%   [deg], and INFO.epochs holds the epochs as decimal years. It is the
%   inverse of shLowLevel.writeGrid, and it reads CF grids from elsewhere
%   too - hydrological models, GravIS Level-3 grids - so that they can
%   enter shCoefficients.analysis.
%   [...] = shLowLevel.readGrid(FILE, Var = NAME) names the variable when
%   the file holds several on the grid, as GravIS grids do (tws, std_tws,
%   leakage, model_atmosphere).
%
%   What it normalises, and what it does not
%     - Dimensions are found by NAME, so (lon, lat, time), (time, lat,
%       lon) or any other order comes back as (lat, lon, time).
%     - Longitudes come back in 0..360, ascending, with the columns
%       reordered to match: a -180..180 grid comes back starting at 0.
%     - Latitudes come back in the file's order. GravIS stores them from
%       north to south; nothing is flipped.
%     - Fill values become NaN: ncread applies _FillValue, scale_factor and
%       add_offset. A land-only grid therefore comes back with NaN over the
%       ocean, and shCoefficients.analysis refuses NaN until it is told
%       what they mean (Fill = value).
%     - The latitude type is NOT assumed. writeGrid records it (lat_type)
%       and INFO.latType reports it; a file that does not say reports "".
%       Grids from models and data centres use geographic - that is
%       geodetic - latitudes: pass LatType = "geodetic" to analysis.
%     - Time is read by the toolbox's one CF time decoder, the one
%       shLowLevel.readMascon uses too: "<days | hours | minutes | seconds>
%       since <date>", in a standard (Gregorian) calendar only.
%
%   Inputs
%     filename  char/string  path of the .nc file
%
%   Outputs
%     grid    (nlat x nlon) or (nlat x nlon x T) double  the field, NaN
%             where the file has no value
%     latDeg  (nlat,1) double  latitudes [deg], in the file's order
%     lonDeg  (nlon,1) double  longitudes [deg], 0..360, ascending
%     info    (1,1) struct  fields
%             var          (1,1) string  the variable read
%             units        (1,1) string  its units attribute ("" if none)
%             longName     (1,1) string  its long_name attribute ("" if none)
%             latType      (1,1) string  the lat_type attribute writeGrid
%                          stores; "" when the file does not say
%             epochs       (T,1) double  epochs [decimal years]; [] for a
%                          2-D grid
%             timeUnits    (1,1) string  the time axis' units; "" for 2-D
%             calendar     (1,1) string  its calendar attribute ("" if none)
%             conventions  (1,1) string  the global Conventions attribute
%             title        (1,1) string  the global title attribute
%             file         (1,1) string  the file read
%
%   Options
%     Var ("")  the variable to read; "" reads the only variable on the
%         latitude-longitude grid, and refuses when there are several
%
%   Error identifiers
%     shLowLevel:readGrid:fileNotFound
%         FILE does not exist
%     shLowLevel:readGrid:noCoordinates
%         no 1-D latitude or longitude coordinate - not a regular grid
%     shLowLevel:readGrid:noVar
%         Var names no variable in the file
%     shLowLevel:readGrid:noData
%         no variable lies on the latitude-longitude grid
%     shLowLevel:readGrid:whichVar
%         several variables do and Var was not given
%     shLowLevel:readGrid:badDims
%         the variable has dimensions other than latitude, longitude and
%         one time axis
%     shLowLevel:readGrid:noTimeUnits
%         the third axis has no coordinate variable with a units attribute
%     shLowLevel:readGrid:badTimeUnits
%         its units are not "<unit> since <date>"
%     shLowLevel:readGrid:badCalendar
%         its calendar is not a standard (Gregorian) one
%
%   Example
%     f = fullfile(getpref('shAnalysis', 'GravisFolder'), ...
%         'GRAVIS-3_GFZOP_0600_TWS_GRID_GFZ_0006.nc');
%     [tws, lat, lon, info] = shLowLevel.readGrid(f, Var = "tws");  % cm
%     g = shCoefficients.analysis(tws(:, :, 1) / 100, lat, lon, 60, ...
%         Quantity = "ewh", kn = kn, LatType = "geodetic", Fill = 0);
%
%   See also shLowLevel.writeGrid, shLowLevel.readMascon,
%   shCoefficients.analysis.
%
%   Developed by Matthias Weigelt with the help of Claude (Opus 5),
%   2026-09-10 (v5.8.0).
arguments
    filename {mustBeTextScalar}
    opts.Var (1,1) string = ""
end
filename = char(filename);
if ~isfile(filename)
    error('shLowLevel:readGrid:fileNotFound', 'File not found: %s', filename);
end
I = ncinfo(filename);
V = I.Variables;
names = string({V.Name});
vLat = coordVar(V, "latitude", ["degrees_north", "degree_north", ...
    "degrees_n", "degree_n", "degreesn", "degreen"], ["lat", "latitude"]);
vLon = coordVar(V, "longitude", ["degrees_east", "degree_east", ...
    "degrees_e", "degree_e", "degreese", "degreee"], ["lon", "longitude"]);
if vLat == "" || vLon == ""
    error('shLowLevel:readGrid:noCoordinates', ...
        ['No 1-D latitude or longitude coordinate among: %s. readGrid ' ...
         'reads regular latitude-longitude grids.'], strjoin(names, ', '));
end
dLat = string(V(names == vLat).Dimensions(1).Name);
dLon = string(V(names == vLon).Dimensions(1).Name);
if opts.Var ~= ""
    if ~any(names == opts.Var)
        error('shLowLevel:readGrid:noVar', ...
            'No variable "%s" in the file; it holds: %s', opts.Var, ...
            strjoin(names, ', '));
    end
    vn = opts.Var;
else
    onGrid = false(size(V));
    for k = 1:numel(V)
        dn = string({V(k).Dimensions.Name});
        onGrid(k) = any(dn == dLat) && any(dn == dLon);
    end
    cand = names(onGrid);
    if isempty(cand)
        error('shLowLevel:readGrid:noData', ...
            'No variable lies on the (%s, %s) grid; the file holds: %s', ...
            dLat, dLon, strjoin(names, ', '));
    elseif numel(cand) > 1
        error('shLowLevel:readGrid:whichVar', ...
            'Several variables lie on the grid (%s): pass Var = name.', ...
            strjoin(cand, ', '));
    end
    vn = cand;
end
iv = find(names == vn, 1);
dn = string({V(iv).Dimensions.Name});
pLat = find(dn == dLat);
pLon = find(dn == dLon);
rest = setdiff(1:numel(dn), [pLat, pLon]);
if numel(pLat) ~= 1 || numel(pLon) ~= 1 || numel(rest) > 1
    error('shLowLevel:readGrid:badDims', ...
        ['Variable "%s" has the dimensions (%s); readGrid reads latitude ' ...
         'x longitude, with at most one time axis.'], vn, strjoin(dn, ', '));
end
X = double(ncread(filename, vn));
latDeg = double(ncread(filename, vLat));
latDeg = latDeg(:);
lonDeg = mod(double(ncread(filename, vLon)), 360);
lonDeg = lonDeg(:);
info = struct('var', vn, 'units', attr(V(iv), 'units'), ...
    'longName', attr(V(iv), 'long_name'), ...
    'latType', attr(V(names == vLat), 'lat_type'), 'epochs', [], ...
    'timeUnits', "", 'calendar', "", ...
    'conventions', attr(I, 'Conventions'), 'title', attr(I, 'title'), ...
    'file', string(filename));
if isempty(rest)
    grid = permute(X, [pLat, pLon]);
else
    dT = dn(rest);
    iT = find(names == dT, 1);
    tu = "";
    if ~isempty(iT), tu = attr(V(iT), 'units'); end
    if tu == ""
        error('shLowLevel:readGrid:noTimeUnits', ...
            ['The third axis of "%s", "%s", has no coordinate variable ' ...
             'with a units attribute, so its epochs cannot be read.'], vn, dT);
    end
    cal = attr(V(iT), 'calendar');
    if cal ~= "" && ~any(lower(cal) == ["standard", "gregorian", ...
            "proleptic_gregorian"])
        error('shLowLevel:readGrid:badCalendar', ...
            ['The time axis uses the "%s" calendar; readGrid reads ' ...
             'standard (Gregorian) calendars only.'], cal);
    end
    [ep, msg] = cfTimeToYears(ncread(filename, char(dT)), tu);
    if msg ~= ""
        error('shLowLevel:readGrid:badTimeUnits', ...
            'The third axis of "%s", "%s": %s.', vn, dT, msg);
    end
    grid = permute(X, [pLat, pLon, rest]);
    info.epochs = ep;
    info.timeUnits = tu;
    info.calendar = cal;
end
[lonDeg, order] = sort(lonDeg);
grid = grid(:, order, :);
end

function v = coordVar(V, standardName, units, names)
% a 1-D variable that says it is the coordinate, else one named like it
v = "";
for k = 1:numel(V)
    if numel(V(k).Dimensions) == 1 && (attr(V(k), 'standard_name') == ...
            standardName || any(lower(attr(V(k), 'units')) == units))
        v = string(V(k).Name);
        return
    end
end
for k = 1:numel(V)
    if numel(V(k).Dimensions) == 1 && any(lower(string(V(k).Name)) == names)
        v = string(V(k).Name);
        return
    end
end
end

function a = attr(s, name)
% an attribute of a variable, or of the file (ncinfo's own struct), as text
a = "";
if ~isfield(s, 'Attributes') || isempty(s.Attributes), return; end
k = find(strcmpi({s.Attributes.Name}, name), 1);
if ~isempty(k), a = string(s.Attributes(k).Value); end
end
