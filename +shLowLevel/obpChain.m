function [out, rep] = obpChain(folder, opts)
%OBPCHAIN Ocean-bottom-pressure fields (GravIS Level-3 OBP recipe).
%
%   [OUT, REP] = shLowLevel.obpChain(FOLDER, kn = KN, OceanMask = OC,
%   GADFolder = GAD) produces gridded ocean-bottom-pressure anomalies
%   in EWH following the GravIS/GFZ Level-3 OBP definition: gravisL2B
%   corrections (C20/C30/C21/S21, degree 1, minus NFIL mean, GIA) ->
%   GAD added back on the coefficient level -> filter (AFTER the GAD
%   addition - the GravIS order) -> EWH synthesis -> anomalies against
%   the mean over RefPeriod, land set to NaN.
%
%   OBP versus the barystatic oceanChain - the distinction is the
%   atmosphere: bottom pressure is the weight of the FULL column
%   (water + air), so GAD is restored and NOTHING is subtracted; the
%   ocean mean of OBP therefore contains the mean atmospheric mass
%   over the oceans. oceanChain removes that term (ocean mean of GAA,
%   Chambers & Willis 2010) to isolate water mass. Same core, one
%   step apart.
%
%   Filter note (applies to oceanChain too): GAD is added BEFORE the
%   filter, so model and observation see the same smoothing - the
%   GravIS Level-3 order. The ocean MEAN is filter-invariant to
%   0.01 mm/yr (measured); pixel FIELDS are not, so declare the
%   filter when comparing OBP grids.
%
%   Inputs
%     folder  (1 x 1) string  monthly .gfc folder (GSM-2_*, any centre)
%
%   Options
%     kn ([])            (N x 2 | N x 1) REQUIRED load Love numbers
%     OceanMask ([])     (fn handle | nLat x nLon logical) REQUIRED
%                        ocean decision, false over land
%     GADFolder ("")     (1 x 1) string  REQUIRED folder of GAD-2_*.gfc
%                        (shLowLevel.fetchGAX) - OBP without GAD is
%                        not OBP, so the empty default errors
%     GravisFolder ("")  GravIS aux folder; "" = shipped data/gravis
%     GIAFile ("GRAVIS-2B_COSTG_0200_GIA_ICE-6G_D_VM5a_0001.gz")
%                        "" disables the GIA rate (see gravisL2B)
%     GIAEpoch (2011)    (1 x 1) GIA reference epoch
%     GridStep (1)       (1 x 1) synthesis graticule [deg]
%     SpanEnd ([])       (1 x 1) keep epochs <= SpanEnd [decimal yr]
%     Filter ("gauss445") "none" | "gaussN" [km], applied after GAD
%     RefPeriod ([2002.25, 2020.25])  (1 x 2) anomaly reference window
%                        [decimal years], the GravIS 2002/04-2020/03
%                        convention
%     Quiet (true)       (1 x 1) suppress progress output
%
%   Outputs
%     out  (1 x 1) struct with fields
%       grid      (nLat x nLon x T) OBP anomaly [cm EWH], land NaN
%       lat, lon  (nLat x 1), (nLon x 1) grid vectors [deg]
%       epochs    (T x 1) decimal years
%       refMean   (nLat x nLon) subtracted reference-period mean [cm]
%       oceanMeanOBP (T x 1) area-weighted ocean mean of the anomaly
%                 [cm] - contains the atmospheric term by definition
%     rep  (1,1) struct  fields
%          steps         (1,K) string  the stages applied, with parameters
%          version       (1,1) string  shLowLevel.version at run time
%          nEpochs       (1,1) double  epochs processed
%          nGadRestored  (1,1) double  months the GAD restore reached
%          nRefEpochs    (1,1) double  epochs inside RefPeriod
%
%   Example
%     kn = readmatrix("loadLoveNumbers_Gegout97.txt", FileType = "text", ...
%         NumHeaderLines = 2);
%     [out, rep] = shLowLevel.obpChain(serFolder, kn = kn, ...
%         OceanMask = oc, GADFolder = "E:/DATAPOOL/GravityField/GAX/GAD");
%     imagesc(out.lon, out.lat, out.grid(:, :, end)); axis xy
%
%   Error identifiers
%     shLowLevel:obpChain:missingKn        kn not supplied
%     shLowLevel:obpChain:badFilter        Filter is not "none" or a valid
%         "gauss<radiusKm>" (read by shLowLevel.filterSpec; before
%         v5.7.0 any other text became a NaN radius)
%     shLowLevel:obpChain:missingGAD       GADFolder empty
%     shLowLevel:obpChain:noOcean          OceanMask not supplied; it is
%         REQUIRED, and before v5.7.1 its absence was not refused
%     shLowLevel:obpChain:emptyRefPeriod   no epochs inside RefPeriod
%
%   Developed by Matthias Weigelt with the help of Claude (Fable 5),
%   2026-08-12 (v3.11.0).
arguments
    folder (1,1) string
    opts.kn double = []
    opts.OceanMask = []
    opts.GADFolder (1,1) string = ""
    opts.GravisFolder (1,1) string = ""
    opts.GIAFile (1,1) string = "GRAVIS-2B_COSTG_0200_GIA_ICE-6G_D_VM5a_0001.gz"
    opts.GIAEpoch (1,1) double = 2011
    opts.GridStep (1,1) double {mustBePositive} = 1
    opts.SpanEnd double {mustBeScalarOrEmpty} = []
    opts.Filter (1,1) string = "gauss445"
    opts.RefPeriod (1,2) double = [2002.25, 2020.25]
    opts.Quiet (1,1) logical = true
end
% the Filter spec is read FIRST, by the one parser of the vocabulary,
% so a malformed spec fails before any data is touched (A25)
[fspec, msg] = shLowLevel.filterSpec(opts.Filter, Allowed = ["none", "gauss"]);
if msg ~= ""
    error('shLowLevel:obpChain:badFilter', '%s', msg);
end
if isempty(opts.kn)
    error('shLowLevel:obpChain:missingKn', ...
        'obpChain requires load Love numbers: pass kn = ... explicitly.');
end
if strlength(opts.GADFolder) == 0
    error('shLowLevel:obpChain:missingGAD', ...
        ['OBP is GSM plus GAD by definition - pass GADFolder= ' ...
         '(fetch the files with shLowLevel.fetchGAX).']);
end
if isempty(opts.OceanMask)
    % documented as REQUIRED, and until v5.7.1 not refused: an empty mask
    % masked nothing, so the grid kept its land values and the ocean mean
    % came back empty - read from the code, not run (no GAD data; A28)
    error('shLowLevel:obpChain:noOcean', ...
        ['OceanMask is required: the anomalies are set to NaN over land ' ...
         'and the ocean mean is an integral over the ocean; the toolbox ' ...
         'assumes no land-ocean boundary of its own. Give a logical ' ...
         'grid or an @(lat, lon) ' ...
         'handle that is false over land (see shLowLevel.oceanRMS).']);
end
R = 6378136.3; GM = 3.986004415e14; Re = 6371e3;
% ---- corrected series (shared core)
l2bArgs = {'GIAEpoch', opts.GIAEpoch, 'GIAFile', opts.GIAFile};
if ~isempty(opts.SpanEnd), l2bArgs = [l2bArgs, {'SpanEnd', opts.SpanEnd}]; end
[ts, repL] = shLowLevel.gravisL2B(folder, opts.GravisFolder, l2bArgs{:});
ep = ts.epochs(:); T = numel(ep);
steps = repL.steps;
Cs = ts.Cs; Ss = ts.Ss;
% ---- GAD BEFORE the filter (GravIS Level-3 order)
[Cs, Ss, nGad] = addGADFolder(Cs, Ss, ep, opts.GADFolder);
steps(end+1) = sprintf("GAD restored for %d/%d epochs (folder %s)", ...
    nGad, T, opts.GADFolder);
if fspec.kind == "gauss"
    rkm = fspec.radiusKm;
    nmaxS = size(Cs, 1) - 1;
    wf = shLowLevel.shGaussianWeights(nmaxS, rkm); wf = wf(:);
    for k = 1:T
        Cs(:,:,k) = Cs(:,:,k) .* wf;
        Ss(:,:,k) = Ss(:,:,k) .* wf;
    end
    steps(end+1) = "filter " + opts.Filter + " applied after GAD";
end
% ---- synthesis
st = opts.GridStep;
lat = (-90+st/2 : st : 90-st/2)'; lon = (st/2 : st : 360-st/2)';
if isa(opts.OceanMask, 'function_handle')
    [LO, LA] = meshgrid(lon, lat);
    mk = logical(opts.OceanMask(LA, LO));
else
    mk = logical(opts.OceanMask);
end
kn = opts.kn; if size(kn, 2) > 1, kn = kn(:, 2); end
E = zeros(numel(lat), numel(lon), T); Pl = [];
for k = 1:T
    if isempty(Pl)
        [E(:,:,k), ~, ~, Pl] = shLowLevel.shSynthesis(Cs(:,:,k), ...
            Ss(:,:,k), GM, R, lat, lon, 'Quantity','ewh', 'kn',kn, 'Nmin',0);
    else
        E(:,:,k) = shLowLevel.shSynthesis(Cs(:,:,k), Ss(:,:,k), ...
            GM, R, lat, lon, 'Quantity','ewh', 'kn',kn, 'Nmin',0, 'P',Pl);
    end
end
E = E * 100;                                              % m -> cm
steps(end+1) = sprintf("EWH synthesis %d epochs, %g-deg grid", T, st);
% ---- anomalies against the RefPeriod mean, land NaN
inRef = ep >= opts.RefPeriod(1) & ep < opts.RefPeriod(2);
if ~any(inRef)
    error('shLowLevel:obpChain:emptyRefPeriod', ...
        'no epochs inside RefPeriod [%.3f, %.3f).', opts.RefPeriod);
end
refMean = mean(E(:, :, inRef), 3);
G = E - refMean;
G(repmat(~mk, 1, 1, T)) = NaN;
refMean(~mk) = NaN;
steps(end+1) = sprintf("anomalies vs mean of %d ref epochs; land NaN", ...
    nnz(inRef));
% ---- diagnostic ocean mean (contains the atmospheric term!)
dphi = deg2rad(st); dlam = deg2rad(st);
[~, LA2] = meshgrid(lon, lat);
Apix = (Re^2) * cosd(LA2) * dphi * dlam;
wA = Apix(mk);
X = reshape(G, [], T);
omOBP = (wA' * X(mk(:), :))' / sum(wA);
out = struct('grid', G, 'lat', lat, 'lon', lon, 'epochs', ep, ...
    'refMean', refMean, 'oceanMeanOBP', omOBP);
% v5.23.1: was shLowLevel.shxVersion(), a name gone since v3.0.0, so
% every run that got this far failed here; the string form is
% standardChain's and the one this help documents
v = shLowLevel.version();
rep = struct('steps', steps(:), 'version', string(v.Name + " " + v.Version), ...
    'nEpochs', T, 'nGadRestored', nGad, 'nRefEpochs', nnz(inRef));
if ~opts.Quiet, fprintf('%s\n', steps); end
end
