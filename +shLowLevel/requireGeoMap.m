function loc = requireGeoMap()
%REQUIREGEOMAP Assert that geoMap is on the path; say where it is.
%
%   LOC = shLowLevel.requireGeoMap() returns the path of geo.map, or
%   raises shLowLevel:requireGeoMap:geoMapRequired with a message that says what to do
%   instead of reporting an undefined function three frames deeper.
%
%   WHY THIS EXISTS AS ITS OWN FUNCTION. Since v3.32.0 shAnalysis draws
%   no maps: geoMap is the single cartographic authority, because there
%   were two renderers in two toolboxes and no instrument comparing
%   them. Every place that now needs geoMap asks here, so the dependency
%   has ONE spelling and ONE error message, and adding a second drawing
%   entry point cannot quietly invent a third way of failing.
%
%   The dependency is CHECKED, not required. shAnalysis still runs on
%   base MATLAB with no toolboxes and no geoMap; only the two drawing
%   entry points need it, and they say so before they fail.
%
%   Inputs
%     none
%
%   Outputs
%     loc  (1,:) char  full path of geo.map, for provenance records
%
%   Example
%     loc = shLowLevel.requireGeoMap();   % errors if geoMap is absent
%
%   See also shCoefficients.map, shCoefficients.toGrid, shLowLevel.writeAnimation.
%
%   Error identifiers
%     shLowLevel:requireGeoMap:geoMapRequired
%         geoMap is not on the MATLAB path; the message says what to do
%         instead of failing three frames deeper
%
%   Claude (Opus 5), 2026-08-23 (v3.32.0).
%   Developed by Matthias Weigelt with the help of Claude (Opus 5).
loc = which('geo.map');
if isempty(loc) || isempty(which('geo.grid'))
    error('shLowLevel:requireGeoMap:geoMapRequired', ...
        ['This draws through geoMap, which is not on the MATLAB path.\n\n' ...
         'shAnalysis stopped carrying its own map renderer in v3.32.0: ' ...
         'there were two, in two toolboxes, in different projections, ' ...
         'and no instrument compared them.\n\n' ...
         'Add geoMap to the path - and savepath if it should survive a ' ...
         'restart, since an addpath made by a setup script may last only ' ...
         'for that session - or take the numbers and draw them however ' ...
         'you like, since the bridge hands over everything a figure ' ...
         'needs:\n' ...
         '    b = g.toGrid(lat, lon, Quantity = "ewh", kn = kn);\n' ...
         '    imagesc(b.lon, b.lat, b.Z), axis xy\n' ...
         '    title(b.Source), colorbar, ylabel(b.Units)']);
end
end
