function [spec, msg] = filterSpec(F, opts)
%FILTERSPEC Read a filter specification - the one parser of the vocabulary.
%   SPEC = shLowLevel.filterSpec(F) reads F, a filter specification in
%   the form every lane with a Filter option takes, and says what it
%   means:
%
%     "none"             no filter
%     "gauss<radiusKm>"  an isotropic Gaussian of that radius, e.g.
%                        "gauss300"; the radius must be a finite number
%                        greater than zero
%     "DDKn"             the released DDK decorrelation filter n, 1 to 8
%                        (DDK1 strongest, as shLowLevel.ddkNames lists
%                        them) - exactly "DDK" and one digit
%     W struct           a filter as shLowLevel.readDDK or
%                        shLowLevel.designFilter return it
%
%   Text is case-sensitive, as it always was in the lanes: "Gauss300" and
%   "ddk3" are refused.
%
%   It only READS the specification. Building the filter - weights from
%   shLowLevel.shGaussianWeights, a W from shLowLevel.readDDK - stays with
%   each caller, because the lanes apply filters in different ways and
%   every one of them is pinned to its own numbers.
%
%   [SPEC, MSG] = shLowLevel.filterSpec(F, ...) never raises for a bad
%   specification: SPEC.kind is "" and MSG says why, so the CALLER raises
%   under its own identifier. The lanes' badFilter identifiers are
%   documented and pinned, and an identifier belongs to the file that
%   raises it. With one output, a bad specification is an error.
%
%   Before v5.7.0 eight functions parsed this vocabulary each on their
%   own, and they did not agree. Measured on the old code: twsChain turned
%   "gaussX" into NaN results without any error; oceanChain and obpChain
%   read ANY text as a Gaussian, so "DDK3" became a radius of NaN, which
%   makes 60 of 61 weights NaN at degree 60; and in the four chains that
%   never checked the radius, a negative one gave weights of about 1 - no
%   filter at all.
%
%   Inputs
%     F  text scalar or struct  the specification
%
%   Outputs
%     spec  (1,1) struct  fields
%           kind      (1,1) string  "none" | "gauss" | "ddk" | "W", or ""
%                     when F is refused
%           radiusKm  (1,1) double  the Gaussian radius [km]; NaN otherwise
%           ddk       (1,1) double  the DDK number, 1 to 8; NaN otherwise
%           W         struct | []  the filter for kind "W"; [] otherwise
%           name      (1,1) string  the label the lanes report: W.name
%                     for a struct ("custom W" when it has none), the
%                     text itself otherwise
%     msg   (1,1) string  "" when F is accepted, else the reason
%
%   Options
%     Allowed (["none","gauss","ddk","W"])  the kinds the caller admits.
%         The GravIS grid chains admit only "none" and "gauss"
%
%   Error identifiers
%     shLowLevel:filterSpec:badSpec
%         F is refused and the caller asked for one output only
%
%   Example
%     spec = shLowLevel.filterSpec("gauss300");    % kind "gauss", radiusKm 300
%     [s, msg] = shLowLevel.filterSpec("DDK3", Allowed = ["none", "gauss"]);
%     % s.kind is "" and msg says why
%
%   See also shLowLevel.shGaussianWeights, shLowLevel.readDDK,
%   shLowLevel.ddkNames, shLowLevel.designFilter.
%
%   Developed by Matthias Weigelt with the help of Claude (Opus 5),
%   2026-09-10 (v5.7.0).
arguments
    F
    opts.Allowed (1,:) string {mustBeMember(opts.Allowed, ...
        ["none", "gauss", "ddk", "W"])} = ["none", "gauss", "ddk", "W"]
end
spec = struct('kind', "", 'radiusKm', NaN, 'ddk', NaN, 'W', [], 'name', "");
msg = "";
if isstruct(F)
    spec.kind = "W";
    spec.W = F;
    spec.name = "custom W";
    if isfield(F, 'name')
        spec.name = string(F.name);
    end
elseif (ischar(F) && (isrow(F) || isempty(F))) || (isstring(F) && isscalar(F))
    S = string(F);
    spec.name = S;
    if S == "none"
        spec.kind = "none";
    elseif startsWith(S, "gauss")
        r = double(extractAfter(S, "gauss"));
        if isfinite(r) && r > 0
            spec.kind = "gauss";
            spec.radiusKm = r;
        else
            msg = sprintf(['A Gaussian filter is "gauss<radiusKm>" with a ' ...
                'radius greater than zero (got "%s").'], S);
        end
    elseif startsWith(S, "DDK")
        if ~isempty(regexp(char(S), '^DDK[1-8]$', 'once'))
            spec.kind = "ddk";
            spec.ddk = double(extractAfter(S, "DDK"));
        else
            msg = sprintf('A DDK filter is "DDK1" to "DDK8" (got "%s").', S);
        end
    else
        msg = sprintf(['Filter must be "none", "gauss<radiusKm>", "DDKn" ' ...
            'or a W struct (got "%s").'], S);
    end
else
    msg = sprintf('Filter must be a string or a W struct (got a %s).', class(F));
end
if msg == "" && ~ismember(spec.kind, opts.Allowed)
    msg = sprintf('Filter "%s" is a %s filter; this function takes only %s.', ...
        spec.name, spec.kind, strjoin(opts.Allowed, ", "));
end
if msg ~= ""
    spec = struct('kind', "", 'radiusKm', NaN, 'ddk', NaN, 'W', [], 'name', "");
    if nargout < 2
        error('shLowLevel:filterSpec:badSpec', '%s', msg);
    end
end
msg = string(msg);
end
