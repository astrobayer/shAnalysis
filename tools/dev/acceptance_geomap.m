function out = acceptance_geomap(opts)
%ACCEPTANCE_GEOMAP The checks CI structurally cannot run.
%
%   OUT = tools.dev.acceptance_geomap() - run it from the repository root
%   as run('tools/dev/acceptance_geomap.m') or by adding tools/dev to the
%   path - exercises every path where shAnalysis hands work to geoMap,
%   and then the mirror half where geoMap is deliberately absent.
%
%   WHY IT IS NOT A UNIT TEST. The CI machine has no geoMap, so the
%   suite there can only check that the drawing entry points REFUSE.
%   Everything they do when geoMap is present - the argument shapes, the
%   handle struct, the frame geometry, the written file - is invisible
%   to it. That gap was real: three releases shipped with no geo.map
%   call ever executed, and the first run found a defect no static gate
%   could have seen (see FRAME GEOMETRY below).
%
%   AND WHY IT RUNS BOTH HALVES. A developer machine has geoMap, so the
%   refusal paths never execute there either - testNoMapIsDrawnHere
%   returns early when geoMap is present. A bad constructor call inside
%   that test once survived a 264-test acceptance run and failed CI.
%   Neither half is redundant, so this script takes geoMap off the path
%   at the end and runs the other one too.
%
%   FRAME GEOMETRY is checked by REPEATING writeAnimation, not by a
%   second copy of its loop. Repetition is the point: the capture defect
%   it caught shows up about one draw in ten, so a single run would have
%   passed nine times out of ten and taught nothing. geo.map's resize does not reliably land
%   within one drawnow, so frame sizes vary run to run: a fresh figure
%   per frame looked deterministic over four draws and then produced
%   365, 340, 365 here, where 340 is the unresized starting height. A
%   check that re-implemented the loop would be testing its own copy and
%   would drift from the real one, so this runs the shipped function
%   three times and requires all three to survive - which is what a race
%   demands.
%
%   Inputs
%     none
%
%   Options
%     OutDir (tempdir)  where the test video is written [string]
%     Strict (false)  raise an error if any check fails, for scripting
%     Quiet (false)  suppress the per-check lines, keep the summary
%
%   Outputs
%     out  (1,1) struct  fields passed, failed (1,1) double; results
%          (: x 1) struct with name, ok (1,1) logical, note (1,1) string;
%          env (1,1) struct with matlab, geoMap, shAnalysis (1,1) string
%
%   Example
%     out = acceptance_geomap();
%     if out.failed > 0, disp([out.results([out.results.ok] == false).name]); end
%
%   See also SHCOEFFICIENTS/MAP, SHCOEFFICIENTS/TOGRID, WRITEANIMATION,
%   REQUIREGEOMAP, WRITEFRAMES, RUNALLTESTS.
%
%   Claude (Opus 5), 2026-08-23 (v3.32.1).
%   Developed by Matthias Weigelt with the help of Claude (Opus 5).
arguments
    opts.OutDir (1,1) string = string(tempdir)
    opts.Strict (1,1) logical = false
    opts.Quiet (1,1) logical = false
end

res = struct('name', {}, 'ok', {}, 'note', {});
    function ck(name, fn)
        note = "";
        try
            n = fn();
            if ~isempty(n) && (isstring(n) || ischar(n))
                note = string(n);
            end
            ok = true;
        catch e
            ok = false;
            note = string(e.identifier) + " | " + string(e.message);
        end
        res(end+1) = struct('name', string(name), 'ok', ok, 'note', note); %#ok<AGROW>
        if ~opts.Quiet
            fprintf('  %-4s %-44s %s\n', verdict(ok), name, note);
        end
    end

% ------------------------------------------------------------ environment
env = struct('matlab', string(version), ...
    'geoMap', "", 'shAnalysis', "");
loc = which('geo.map');
if isempty(loc)
    error('shAnalysis:acceptance:noGeoMap', ...
        ['This acceptance run needs geoMap on the path - it exists to ' ...
         'exercise exactly what a machine without geoMap cannot. Add ' ...
         'geoMap, or run runAllTests for the rest.']);
end
env.geoMap = string(fileparts(fileparts(loc)));
v = shLowLevel.version();
env.shAnalysis = string(v.Version);
if ~opts.Quiet
    fprintf('MATLAB %s\n', env.matlab);
    fprintf('shAnalysis %s at %s\n', env.shAnalysis, ...
        fileparts(which('shCoefficients')));
    fprintf('geoMap at %s\n\n', env.geoMap);
end

% ---------------------------------------------------------------- fixture
rng(4211);
L = 10; n1 = L + 1;
C = tril(randn(n1)) * 1e-10;
S = tril(randn(n1), -1) * 1e-10; S(:, 1) = 0;
kn = -0.3 * (1 - exp(-(0:L)'/3));
g = shCoefficients(C, S, ProductType = "GSM", Name = "acceptance", ...
    Epoch = 2008.292);
ts = shSeries(cat(3, C, C * 1.4, C * 0.6), Ss = cat(3, S, S, S), ...
    Epochs = [2008.1; 2008.2; 2008.3]);
lat = -88:4:88; lon = 0:4:356;

if ~opts.Quiet, fprintf('=== with geoMap on the path\n'); end
ck('requireGeoMap finds it', @() string(shLowLevel.requireGeoMap()));
ck('g.map returns a geo.map handle struct', @() checkMap(g, kn));
ck('writeAnimation is repeatable (3 runs)', ...
    @() checkRepeat(ts, kn, opts.OutDir));
ck('writeAnimation writes a usable file', @() checkAnim(ts, kn, opts.OutDir));
ck('writeFrames container and its named errors', @() checkFrames2(opts.OutDir));

% ------------------------------------------------- the half CI does cover
if ~opts.Quiet, fprintf('\n=== with geoMap hidden (the half a dev machine never runs)\n'); end
oldPath = path;
restorePath = onCleanup(@() sweep(oldPath, opts.Quiet)); %#ok<NASGU>
rmpath(char(env.geoMap));
clear functions %#ok<CLFUNC>
rehash
ck('geoMap is really gone', @() assertGone());
ck('requireGeoMap raises geoMapRequired', ...
    @() expectError(@() shLowLevel.requireGeoMap(), 'shLowLevel:requireGeoMap:geoMapRequired'));
ck('g.map raises geoMapRequired', ...
    @() expectError(@() g.map(lat, lon, Quantity = "geoid"), ...
        'shLowLevel:requireGeoMap:geoMapRequired'));
ck('writeAnimation refuses BEFORE writing', ...
    @() checkRefusal(ts, opts.OutDir));
ck('toGrid still works without geoMap', @() checkBridge(g, kn, lat, lon));

% ----------------------------------------------------------------- report
out = struct('passed', nnz([res.ok]), 'failed', nnz(~[res.ok]), ...
    'results', res(:), 'env', env);
fprintf('\n=== acceptance_geomap: %d passed, %d failed\n', ...
    out.passed, out.failed);
if out.failed > 0
    bad = res(~[res.ok]);
    for k = 1:numel(bad)
        fprintf('  FAILED  %s\n          %s\n', bad(k).name, bad(k).note);
    end
    if opts.Strict
        error('shAnalysis:acceptance:failed', ...
            '%d acceptance check(s) failed.', out.failed);
    end
end
fprintf('This covers the geoMap coupling only - run runAllTests for the rest.\n');
end

% ================================================================= helpers
function s = verdict(ok)
% not named 'missing': that is a MATLAB builtin, and a local function
% shadowing one is a trap for whoever edits this next
if ok, s = "PASS"; else, s = "FAIL"; end
end

function sweep(oldPath, quiet)
path(oldPath);
clear functions %#ok<CLFUNC>
rehash
if ~quiet, fprintf('[path restored, geoMap back]\n'); end
end

function note = checkMap(g, kn)
f = figure('Visible', 'off');
c = onCleanup(@() close(f)); %#ok<NASGU>
H = g.map(-88:4:88, 0:4:356, Quantity = "ewh", kn = kn, ...
    GeoArgs = {'Parent', axes('Parent', f)});
assert(isstruct(H), 'geo.map returned a %s, not a struct', class(H));
for want = ["Axes", "CRS"]
    assert(isfield(H, want), 'handle struct has no %s', want);
end
note = "fields: " + strjoin(string(fieldnames(H))', ",");
end

function note = checkRepeat(ts, kn, outDir)
% the race only shows up across runs, so run the SHIPPED function - a
% local copy of its loop would be testing itself, not what ships
sz = strings(3, 1);
geom = zeros(3, 2);
for r = 1:3
    tmp = fullfile(char(outDir), sprintf('shx_rep%d_%d.avi', r, randi(1e9)));
    shLowLevel.writeAnimation(ts, tmp, Quantity = "ewh", kn = kn, ...
        lat = -80:8:80, lon = 0:8:352, FrameRate = 2, Size = [640 340]);
    d = dir(tmp);
    assert(~isempty(d) && d.bytes > 1000, 'run %d wrote nothing usable', r);
    p = jsondecode(fileread([tmp '.provenance.json']));
    sz(r) = string(d.bytes) + "B/" + string(p.nFrames) + "f/" + ...
        string(p.frameSize(1)) + "x" + string(p.frameSize(2));
    geom(r, :) = p.frameSize(:)'; %#ok<AGROW>
    cleanFile(tmp);
end
assert(all(geom(:, 1) == geom(1, 1)) && all(geom(:, 2) == geom(1, 2)), ...
    ['frame geometry differs BETWEEN runs: %s. The figure layout is ' ...
     'pinned within a run, so a difference here means a capture was ' ...
     'accepted that did not match its own figure - see captureFrame in ' ...
     'writeAnimation, which exists because getframe intermittently ' ...
     'returns a frame larger than the figure it captured.'], mat2str(geom));
note = "runs: " + strjoin(sz', ", ");
end

function note = checkAnim(ts, kn, outDir)
tmp = fullfile(char(outDir), sprintf('shx_acc_%d.avi', randi(1e9)));
c = onCleanup(@() cleanFile(tmp)); %#ok<NASGU>
shLowLevel.writeAnimation(ts, tmp, Quantity = "ewh", kn = kn, ...
    lat = -80:8:80, lon = 0:8:352, FrameRate = 2, Size = [640 340]);
d = dir(tmp);
assert(~isempty(d) && d.bytes > 1000, 'no usable file written');
side = [tmp '.provenance.json'];
assert(isfile(side), 'no provenance sidecar');
p = jsondecode(fileread(side));
for want = ["renderer", "clim", "dataRange", "nFrames"]
    assert(isfield(p, want), 'sidecar has no %s', want);
end
assert(contains(p.renderer, 'geoMap'), 'sidecar does not name geoMap');
note = sprintf('%d bytes, %d frames, clim [%.3g %.3g]', d.bytes, ...
    p.nFrames, p.clim(1), p.clim(2));
end

function note = checkFrames2(outDir)
F = uint8(randi([0 255], 60, 120, 3, 3));
tmp = fullfile(char(outDir), sprintf('shx_accf_%d.avi', randi(1e9)));
c = onCleanup(@() cleanFile(tmp)); %#ok<NASGU>
shLowLevel.writeFrames(F, tmp, FrameRate = 2);
assert(isfile(tmp), 'no file written');
expectError(@() shLowLevel.writeFrames(F, ...
    fullfile(char(outDir), 'x.gif')), 'shLowLevel:writeAnimation:badExtension');
expectError(@() shLowLevel.writeFrames(uint8(zeros(4, 4, 3)), tmp), ...
    'shLowLevel:writeFrames:badSize');
note = "container plus badExtension and badSize";
end

function note = assertGone()
assert(isempty(which('geo.map')), 'geoMap still visible');
note = "which('geo.map') is empty";
end

function note = checkRefusal(ts, outDir)
tmp = fullfile(char(outDir), sprintf('shx_never_%d.avi', randi(1e9)));
expectError(@() shLowLevel.writeAnimation(ts, tmp, Quantity = "geoid"), ...
    'shLowLevel:requireGeoMap:geoMapRequired');
assert(~isfile(tmp), 'it wrote %s before refusing', tmp);
note = "nothing written";
end

function note = checkBridge(g, kn, lat, lon)
b = g.toGrid(lat, lon, Quantity = "ewh", kn = kn);
assert(b.Units == "m", 'units %s', b.Units);
assert(b.LatType == "geodetic");
assert(isequal(size(b.Z), [numel(lat), numel(lon)]));
note = b.FieldKind + ", " + b.Units + ", " + b.LatType;
end

function note = expectError(fn, id)
try
    fn();
catch e
    assert(strcmp(e.identifier, id), 'got %s, expected %s', e.identifier, id);
    note = "";
    return
end
error('expected %s, nothing was raised', id);
end

function cleanFile(f)
if isfile(f), delete(f); end
if isfile([f '.provenance.json']), delete([f '.provenance.json']); end
end
