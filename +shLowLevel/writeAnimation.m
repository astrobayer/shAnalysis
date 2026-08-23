function writeAnimation(ts, filename, opts)
%WRITEANIMATION Export a series as a map animation, drawn by geoMap.
%
%   shLowLevel.writeAnimation(TS, 'ewh.avi', quantity ("ewh")=...,
%       kn ([])=...) synthesizes every epoch of TS onto one grid, draws
%   each frame with geo.map, and writes them to a video container with a
%   provenance sidecar.
%
%   THE COLOUR SCALE IS FIXED ACROSS EVERY FRAME, from shSeries.toGrid's
%   stack-wide extremes. A per-frame scale is the single most common
%   animation mistake: it shows the scale changing and the signal not,
%   which turns a stack of honest maps into a misleading film.
%
%   GEOMAP DRAWS. Since v3.32.0 this function contains no cartography of
%   its own - it assembles the stack (which is spherical-harmonic work),
%   calls geo.map once per frame, and writes the container. If geoMap is
%   absent it raises shAnalysis:geoMapRequired BEFORE synthesizing: a
%   two-minute stack followed by an undefined-function error is the
%   wrong order to discover that in. The container mechanics live in
%   shLowLevel.writeFrames, which has no graphics and therefore stays
%   under test on a machine without geoMap.
%
%   GEOMAP'S OPTIONS ARE NOT RESTATED HERE. GeoArgs is forwarded to
%   geo.map verbatim. Mirroring another toolbox's option table is how two
%   renderers drift apart in the first place, and geo.map applies exactly
%   the same rule to its own elements.
%
%   Inputs
%     ts        (1,1) shSeries    the series to animate
%     filename  (1,1) string      .mp4 (Windows/macOS) or .avi (portable)
%
%   Options
%     quantity ("ewh")  any kernelFactors quantity
%     kn ([])  load Love numbers k'_n (mass quantities; never hardcoded)
%     hn ([])  load Love numbers h'_n (deformation_up only)
%     lat (-89:2:89)  latitude grid [deg]
%     lon (0:2:358)  longitude grid [deg]
%     LatType ("geodetic")  "geodetic" | "geocentric"; a map wants geodetic
%     FrameRate (4)  frames per second
%     Sidecar (true)  write <file>.provenance.json alongside the output
%     Size ([900 470])  figure size in pixels, [width height]
%     CRS ("equirectangular")  forwarded to geo.map as its projection
%     Basemap (struct())  forwarded to geo.map's Basemap element. The
%         stack-wide CLim and the Divergent flag are inserted into it
%         unless you set them yourself, so overriding is deliberate and
%         possible rather than accidental
%     GeoArgs ({})  cell of name-value pairs forwarded to geo.map verbatim
%
%   Outputs
%     none (writes FILENAME, and FILENAME.provenance.json when Sidecar)
%
%   Example
%     shLowLevel.writeAnimation(ts, fullfile(tempdir, 'ewh.avi'), ...
%         quantity = "ewh", kn = kn, FrameRate = 6);
%
%   See also SHSERIES/TOGRID, SHLOWLEVEL/WRITEFRAMES, REQUIREGEOMAP.
%
%   Claude (Fable 5), 2026-08-07 (v2.4); routed through geoMap
%   Claude (Opus 5), 2026-08-23 (v3.32.0).
%   Developed by Matthias Weigelt with the help of Claude.
arguments
    ts (1,1) shSeries
    filename (1,1) string
    opts.quantity (1,1) string = "ewh"
    opts.kn double = []
    opts.hn double = []
    opts.lat (1,:) double = -89:2:89
    opts.lon (1,:) double = 0:2:358
    opts.LatType (1,1) string ...
        {mustBeMember(opts.LatType, ["geocentric","geodetic"])} = "geodetic"
    opts.FrameRate (1,1) double {mustBePositive} = 4
    opts.Sidecar (1,1) logical = true
    opts.Size (1,2) double = [900 470]
    opts.CRS (1,1) string = "equirectangular"
    opts.Basemap (1,1) struct = struct()
    opts.GeoArgs cell = {}
end
loc = shLowLevel.requireGeoMap();

b = ts.toGrid(opts.lat, opts.lon, quantity = opts.quantity, ...
    kn = opts.kn, hn = opts.hn, LatType = opts.LatType);
T = size(b.Z, 3);

% The colour limits are taken from the WHOLE stack, robustly - the 98th
% percentile of |value|, which is the rule the retired renderer used and
% which outliers cannot drag. b.Zmin/b.Zmax are the true extremes and go
% into the sidecar, so the figure's scale and the data's range are both
% recorded and can be compared afterwards.
bm = opts.Basemap;
if ~isfield(bm, 'CLim')
    a = shLowLevel.pctile(abs(b.Z(:)), 98);
    if a == 0, a = 1; end
    if b.FieldKind == "anomaly"
        bm.CLim = [-a, a];          % signed field: symmetric about zero
    else
        bm.CLim = [b.Zmin, b.Zmax];
    end
end
if ~isfield(bm, 'Divergent')
    bm.Divergent = (b.FieldKind == "anomaly");
end

fig = figure('Visible', 'off', ...
    'Position', [50 50 opts.Size(1) opts.Size(2)]);
figCloser = onCleanup(@() close(fig)); %#ok<NASGU>
frames = uint8.empty;
for k = 1:T
    clf(fig);
    ax = axes('Parent', fig);       % geo.map's Parent is an AXES
    G = geo.grid(b.lon, b.lat, b.Z(:, :, k), ...
        Source = b.Source, Units = b.Units);
    % name=value must come last, so everything goes in one cell (see
    % shCoefficients.map for what mixing the two forms costs)
    args = [{'Parent', ax, 'Basemap', bm, 'Title', ...
        sprintf('%s  %.3f', opts.quantity, b.Epoch(k))}, opts.GeoArgs];
    geo.map(G, opts.CRS, args{:});
    drawnow;
    F = getframe(fig);
    if isempty(frames)
        frames = zeros([size(F.cdata), T], 'uint8');
    end
    frames(:, :, :, k) = F.cdata;
end

extra = struct('nEpochs', T, 'quantity', char(opts.quantity), ...
    'renderer', ['geoMap: ' loc], 'latType', char(b.LatType), ...
    'units', char(b.Units), 'clim', bm.CLim, ...
    'dataRange', [b.Zmin, b.Zmax]);
shLowLevel.writeFrames(frames, filename, FrameRate = opts.FrameRate, ...
    Sidecar = opts.Sidecar, SidecarExtra = extra);
end
