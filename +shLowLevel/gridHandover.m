function b = gridHandover(Z, lat, lon, units, latType, quantity, ...
    productType, name, epoch, c00, history, nmax, nmin)
%GRIDHANDOVER Assemble the metadata that travels with a synthesized grid.
%
%   B = shLowLevel.gridHandover(Z, LAT, LON, UNITS, LATTYPE, QUANTITY,
%       PRODUCTTYPE, NAME, EPOCH, C00, HISTORY, NMAX, NMIN) packs a
%   synthesized field together with what it is, for handover to a
%   cartographic toolbox. Called by shCoefficients.toGrid and
%   shSeries.toGrid; it exists so the two bridges cannot describe the
%   same field differently, which is the failure they were built to
%   prevent in the first place.
%
%   THE FIELD KIND IS READ OFF AN IDENTITY. C00 = C(1,1) is the degree-0
%   coefficient: exactly 1 for a field normalised by GM/R that carries
%   the total mass, and 0 for a residual. So "full" and "anomaly" are
%   facts about the coefficients, not inferences from the values, and
%   anything in between is reported as "unknown" rather than decided.
%   For a stack, C00 may be a vector; the kinds must agree or the result
%   is "mixed".
%
%   Zmin/Zmax/Zmean are the raw measured extremes of Z, carried rather
%   than turned into a verdict: a full field expressed as water spans
%   1.16e7 +- 7e4 m and a monthly anomaly spans about +-1.2 m, which any
%   consumer can tell apart without this function inventing a threshold.
%   For a stack they are taken over EVERY epoch, which is exactly the
%   fixed colour scale an animation needs.
%
%   Inputs
%     Z           (nlat,nlon[,T]) double  synthesized values
%     lat         (1,nlat) double [deg]   as given by the caller
%     lon         (1,nlon) double [deg]
%     units       (1,1) string            from shLowLevel.kernelFactors
%     latType     (1,1) string            "geodetic" | "geocentric"
%     quantity    (1,1) string
%     productType (1,1) string            e.g. "GSM", "GAD", "unknown"
%     name        (1,1) string            model label, may be ""
%     epoch       (:,1) double            decimal year(s), NaN if unset
%     c00         (:,1) double            degree-0 coefficient per epoch
%     history     (:,1) string            processing history
%     nmax, nmin  (1,1) double            degree range actually used
%
%   Outputs
%     b  (1,1) struct  Z, lat (nlat x 1) double, lon (1 x nlon) double,
%        Units, LatType, Quantity, ProductType, Name, Source, FieldKind
%        (1,1) string, Epoch (: x 1) double, C00 (: x 1) double, Zmin,
%        Zmax, Zmean (1,1) double, Nmax, Nmin (1,1) double, History
%        (: x 1) string
%
%   Example
%     b = shLowLevel.gridHandover(Z, lat, lon, "m", "geodetic", "ewh", ...
%             "GSM", "ITSG-Grace2018", 2008.29, 0, string.empty(0,1), 60, 0);
%     b.FieldKind        % "anomaly"
%
%   See also shCoefficients.toGrid, shSeries.toGrid, shLowLevel.kernelFactors.
%
%   Error identifiers
%     shLowLevel:gridHandover:fullFieldAsMass
%         warning: a mass quantity was synthesized from a FULL field
%         (C00 = 1), so the result is the static field expressed as mass
%
%   Claude (Opus 5), 2026-08-23 (v3.31.0).
%   Developed by Matthias Weigelt with the help of Claude (Opus 5).
arguments
    Z double
    lat (1,:) double
    lon (1,:) double
    units (1,1) string
    latType (1,1) string
    quantity (1,1) string
    productType (1,1) string
    name (1,1) string
    epoch (:,1) double
    c00 (:,1) double
    history string
    nmax (1,1) double
    nmin (1,1) double
end

history = history(:);      % a row history must not fail the handover
kinds = strings(numel(c00), 1);
for k = 1:numel(c00)
    if abs(c00(k) - 1) < 1e-6
        kinds(k) = "full";
    elseif abs(c00(k)) < 1e-6
        kinds(k) = "anomaly";
    else
        kinds(k) = "unknown";
    end
end
if isempty(kinds)
    kind = "unknown";
elseif all(kinds == kinds(1))
    kind = kinds(1);
else
    kind = "mixed";
end

finiteZ = Z(isfinite(Z));
if isempty(finiteZ)
    zmin = NaN; zmax = NaN; zmean = NaN;
else
    zmin = min(finiteZ); zmax = max(finiteZ); zmean = mean(finiteZ);
end

% Source is one line a figure caption can carry verbatim. Version comes
% from shLowLevel.version, never a literal.
v = shLowLevel.version();
parts = "shAnalysis " + string(v.Version);
if strlength(name) > 0
    parts(end+1) = name; %#ok<AGROW>
end
if productType ~= "unknown"
    parts(end+1) = productType; %#ok<AGROW>
end
parts(end+1) = quantity + " [" + units + "]";
parts(end+1) = sprintf('n%d-%d', nmin, nmax);
parts(end+1) = latType + " lat";
if numel(epoch) == 1 && isfinite(epoch)
    parts(end+1) = sprintf('%.3f', epoch); %#ok<AGROW>
elseif numel(epoch) > 1
    parts(end+1) = sprintf('%.3f-%.3f (%d epochs)', min(epoch), ...
        max(epoch), numel(epoch));
end

b = struct( ...
    'Z', Z, ...
    'lat', lat(:), ...
    'lon', lon(:)', ...
    'Units', units, ...
    'LatType', latType, ...
    'Quantity', quantity, ...
    'ProductType', productType, ...
    'Name', name, ...
    'Source', strjoin(parts, " | "), ...
    'FieldKind', kind, ...
    'Epoch', epoch, ...
    'C00', c00, ...
    'Zmin', zmin, ...
    'Zmax', zmax, ...
    'Zmean', zmean, ...
    'Nmax', nmax, ...
    'Nmin', nmin, ...
    'History', history);

% The one thing worth interrupting for: a full field asked for as mass.
% Measured on the geoMap side - twelve GSM solutions meaned and
% synthesized to EWH gave 1.16e7 m, the static field expressed as water,
% which a symmetric colour scale renders as one flat colour and which no
% unit string distinguishes from a real anomaly.
if kind == "full" && ismember(quantity, ...
        ["ewh", "surface_density", "bottom_pressure"])
    warning('shLowLevel:gridHandover:fullFieldAsMass', ...
        ['%s was synthesized from a FULL field (C00 = %g, not 0), so it ' ...
         'is the static field expressed as mass, not a mass change ' ...
         '(range %.4g to %.4g %s). Remove a mean field first.'], ...
        quantity, c00(1), zmin, zmax, units);
end
end
