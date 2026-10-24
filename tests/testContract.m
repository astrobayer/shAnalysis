function tests = testContract
%TESTCONTRACT API contract tests for the shAnalysis v2 toolbox.
%
%   Verifies the *interface*, independent of numerics: every documented
%   error path throws its documented identifier, value objects are
%   immutable (methods return new objects, originals untouched), output
%   dimensions match the documented contracts, and the compat/ wrappers
%   remain signature-identical to shLowLevel internals.
%
%   Run:  results = runtests('testContract');
%
%   Claude (Fable 5), 2026-08-07.
%   Developed by Matthias Weigelt with the help of Claude (Fable 5).

tests = functiontests(localfunctions);
end

% ---------------------------------------------------------------- fixture
function setupOnce(tc)
here = fileparts(mfilename('fullpath'));
root = fileparts(here);
addpath(root);
tc.TestData.root = root;
tc.TestData.dataDir = shxTestDataDir();
shLowLevel.legendreCached('clear');
end

function g = randomField(nmax, epoch)
rng(42);
C = tril(randn(nmax+1)) * 1e-9; S = tril(randn(nmax+1), -1) * 1e-9;
C(1,1) = 1;
g = shCoefficients(C, S, GM = 3.986004415e14, R = 6.3781363e6, ...
    Epoch = epoch, ProductType = "GSM");
end

function ts = randomSeries(nmax, T)
arr = shCoefficients.empty(0, 1);
for k = 1:T
    arr(k,1) = randomField(nmax, 2020 + (k-1)/12);
end
ts = shSeries(arr);
end

% ----------------------------------------------------- shCoefficients IDs
function testConstructorBadInput(tc)
verifyError(tc, @() shCoefficients(ones(3,4), ones(3,4)), ...
    'shCoefficients:shCoefficients:badInput');                      % non-square
verifyError(tc, @() shCoefficients(ones(3), ones(4)), ...
    'shCoefficients:shCoefficients:badInput');                      % C/S size differ
verifyError(tc, @() shCoefficients(ones(3), ones(3), SigmaC = ones(4)), ...
    'shCoefficients:shCoefficients:badInput');
verifyError(tc, @() shCoefficients(ones(3), ones(3), SigmaS = ones(4)), ...
    'shCoefficients:shCoefficients:badInput');
end

function testTruncationAndIndexIDs(tc)
g = randomField(10, 2020);
verifyError(tc, @() g.truncate(11), 'shCoefficients:truncate:badTruncation');
verifyError(tc, @() g.setCoefficient(11, 0, 1, NaN), 'shCoefficients:setCoefficient:badIndex');
verifyError(tc, @() g.setCoefficient(2, 3, 1, 1), 'shCoefficients:setCoefficient:badIndex');
end

function testPairCheckIDs(tc)
a = randomField(10, 2020.0);
b = randomField(12, 2020.0);
verifyError(tc, @() a - b, 'shCoefficients:operands:sizeMismatch');
c = shCoefficients(a.C, a.S, GM = a.GM * 1.001, R = a.R, Epoch = 2020);
verifyError(tc, @() a - c, 'shCoefficients:operands:constantsMismatch');
d = randomField(10, 2021.0);        % plus enforces epoch agreement
verifyError(tc, @() a + d, 'shCoefficients:operands:epochMismatch');
end

function testMinusDoesNotEnforceEpochAgreement(tc)
% The other half of testPairCheckIDs, and the one non-obvious claim the
% A21 help blocks make: plus calls checkEpochs, minus does NOT. A
% difference between two months has no single epoch, so minus sets
% epoch = NaN instead of refusing. Documented in both help blocks; until
% v4.0.3 only the plus half was pinned, so a stray checkEpochs call in
% minus would have passed every test.
a = randomField(10, 2020.0);
d = randomField(10, 2021.0);
out = a - d;                        % must NOT raise
verifyClass(tc, out, 'shCoefficients');
verifyTrue(tc, isnan(out.epoch), ...
    'A difference carries no epoch, so minus must set it to NaN.');
end

function testTN14IDs(tc)
tnFile = writeSyntheticTN14(tc);
g0 = randomField(10, NaN);
verifyError(tc, @() g0.applyTN14(tnFile), 'shCoefficients:applyTN14:noEpoch');
g1 = randomField(10, 2035.0);       % far outside table
verifyError(tc, @() g1.applyTN14(tnFile), 'shCoefficients:applyTN14:epochNotInTable');
g2 = randomField(10, 2020.13);      % nearest row has NaN C30
verifyError(tc, @() g2.applyTN14(tnFile, ReplaceC30 = "always"), ...
    'shCoefficients:applyTN14:noC30');
verifyError(tc, @() shLowLevel.readTN14('no_such_file.txt'), ...
    'shLowLevel:readTN14:fileNotFound');
end

function testCrossoverNoSigmasID(tc)
g = randomField(10, 2020);          % constructed without sigmas
verifyError(tc, @() g.crossover(), 'shCoefficients:crossover:noSigmas');
end

function testSynthesisIDs(tc)
g = randomField(10, 2020);
verifyError(tc, ...
    @() g.synthesis(-80:10:80, 0:10:350, Quantity = "ewh"), ...
    'shLowLevel:kernelFactors:missingLoveNumbers');
verifyError(tc, ...
    @() shLowLevel.shSynthesis(g.C, g.S, g.GM, g.R, 0, 0, 'Quantity', 'nonsense'), ...
    'shLowLevel:kernelFactors:badQuantity');
end

function testDeformationIDs(tc)
% shSynthesisDeformation raised shSynthesis:* identifiers until v3.33.1,
% so a caller could not catch by owner (CLAUDE.md A3). These are the
% identifiers it owns; the ERRORS block of the file documents the same two.
g = randomField(10, 2020);
z = zeros(11, 1);
verifyError(tc, ...
    @() shLowLevel.shSynthesisDeformation(g.C, g.S(:, 1:end-1), g.R, ...
        0, 0, kn = z, hn = z, ln = z), ...
    'shLowLevel:shSynthesisDeformation:badInput');
verifyError(tc, ...
    @() shLowLevel.shSynthesisDeformation(g.C, g.S, g.R, 0, 0, ...
        kn = z(1:3), hn = z, ln = z), ...
    'shLowLevel:shSynthesisDeformation:missingLoveNumbers');
verifyError(tc, ...
    @() shLowLevel.shSynthesisDeformation(g.C, g.S, g.R, [0 10], 0, ...
        kn = z, hn = z, ln = z, Mode = "points"), ...
    'shLowLevel:shSynthesisDeformation:badInput');
% shCoefficients.deformation is a thin delegate: the identifier must
% reach the caller unchanged, not be re-wrapped by the class
verifyError(tc, @() g.deformation(0, 0, kn = z(1:3), hn = z, ln = z), ...
    'shLowLevel:shSynthesisDeformation:missingLoveNumbers');
end

function testReadIDs(tc)
verifyError(tc, @() shCoefficients.read('no_such_file.gfc'), ...
    'shLowLevel:shReadGFC:fileNotFound');
end

% ---------------------------------------------------------- shSeries IDs
function testSeriesConstructionIDs(tc)
verifyError(tc, @() shSeries(rand(3,3,4)), 'shSeries:shSeries:badInput');   % no Epochs
verifyError(tc, @() shSeries(rand(3,3,4), Ss = rand(3,3,4), ...
    Epochs = [1 2 3]), 'shSeries:shSeries:badInput');                       % T mismatch
a = randomField(8, 2020.0); b = randomField(10, 2020.1);
verifyError(tc, @() shSeries([a; b]), 'shSeries:shSeries:sizeMismatch');
c = shCoefficients(a.C, a.S, GM = a.GM, R = a.R * 1.01, Epoch = 2020.1);
verifyError(tc, @() shSeries([a; c]), 'shSeries:shSeries:constantsMismatch');
end

function testSeriesMethodIDs(tc)
ts = randomSeries(8, 8);
verifyError(tc, @() ts.at(9), 'shSeries:at:badIndex');
verifyError(tc, @() ts.basinAverage(ones(3, 1)), 'shSeries:basinAverage:badBasis');
verifyError(tc, @() ts.basinAverage(ones(3, 1), Deconvolve = true), ...
    'shSeries:basinAverage:missingOp');
verifyError(tc, @() shSeries.read('zz_no_such_*.gfc'), 'shSeries:read:noFiles');

short = randomSeries(8, 3);
verifyError(tc, @() short.climatology(), 'shSeries:climatology:tooFewEpochs');

nanEp = shSeries(ts.Cs, Ss = ts.Ss, Epochs = [NaN, 2:8], ...
    GM = ts.GM, R = ts.R);
verifyError(tc, @() nanEp.climatology(), 'shSeries:climatology:noEpoch');
verifyError(tc, @() nanEp.filter("tvANS"), 'shSeries:filter:noEpoch');

Cs = ts.Cs; Cs(2,1,3) = NaN;
nanTs = shSeries(Cs, Ss = ts.Ss, Epochs = ts.epochs, GM = ts.GM, R = ts.R);
verifyError(tc, @() nanTs.destripe(), 'shSeries:stack:nanInSeries');
end

function testRestoreIDs(tc)
gsm = randomSeries(8, 6);
gad = randomSeries(10, 6);
verifyError(tc, @() gsm.restore(gad), 'shSeries:restore:sizeMismatch');
gad8 = gsm.truncate(8);             % same nmax, but shift epochs far away
shifted = shSeries(gad8.Cs, Ss = gad8.Ss, Epochs = gad8.epochs + 5, ...
    GM = gad8.GM, R = gad8.R, ProductType = "GAD");
verifyError(tc, @() gsm.restore(shifted), 'shSeries:restore:epochMismatch');
end

% ----------------------------------------------------------- immutability
function testImmutability(tc)
g = randomField(20, 2020);
C0 = g.C; S0 = g.S; h0 = g.history;
g2 = g.destripe(MinOrder = 4); %#ok<NASGU>
g3 = g.gaussian(300);          %#ok<NASGU>
g4 = g.truncate(10);           %#ok<NASGU>
verifyEqual(tc, g.C, C0); verifyEqual(tc, g.S, S0);
verifyEqual(tc, g.history, h0);

ts = randomSeries(8, 6);
Cs0 = ts.Cs;
ts2 = ts.gaussian(500); %#ok<NASGU>
verifyEqual(tc, ts.Cs, Cs0);
end

function testFluentHistory(tc)
g = randomField(20, 2020);
g2 = g.destripe().gaussian(300).truncate(15);
verifyClass(tc, g2, 'shCoefficients');
verifyEqual(tc, numel(g2.history), numel(g.history) + 3);
verifySubstring(tc, char(g2.history(end)), 'truncate');
end

% ------------------------------------------------------------- dimensions
function testOutputDimensions(tc)
g = randomField(15, 2020);
lat = -60:5:60; lon = 0:5:355;
[grid, latO, lonO] = g.synthesis(lat, lon);
verifySize(tc, grid, [numel(lat), numel(lon)]);
verifyEqual(tc, latO(:)', lat); verifyEqual(tc, lonO(:)', lon);

spec = g.degreeRMS;
n = (spec.degree(1):spec.degree(end))';
verifyEqual(tc, numel(spec.degRMS), numel(n));
verifyEqual(tc, numel(spec.degAmplitude), numel(n));

idx = shLowLevel.shIndex(g.nmax, Nmin = 2);
x = g.vec(idx);
verifySize(tc, x, [idx.P, 1]);
g5 = shCoefficients.fromVec(x, idx, g);
verifyEqual(tc, g5.C(3:end, :), g.C(3:end, :), AbsTol = 0);

ts = randomSeries(8, 10);
[clim, resid] = ts.climatology();
verifyClass(tc, clim, 'shClimatology');
verifyEqual(tc, resid.nEpochs, 10);
m = ts.mean;
verifyClass(tc, m, 'shCoefficients');
verifySize(tc, m.C, size(ts.Cs(:, :, 1)));
end

% ------------------------------------------------- compat wrapper contract
% ----------------------------------------------------------------- helper
function f = writeSyntheticTN14(tc)
% Minimal TN-14-like table: 2 months; second month has no C30 (NaN).
f = fullfile(tempdir, 'tn14_contract.txt');
fid = fopen(f, 'w');
fprintf(fid, 'Product: synthetic TN-14 for contract tests\n');
fprintf(fid, 'end of header ===========================\n');
% MJD start, frac yr start, C20, dC20*1e10, sigC20*1e10, C30, dC30*1e10,
% sigC30*1e10, MJD end, frac yr end   (10-column TN-14 layout)
% -> mid-epochs 2020.0417 and 2020.1250
fprintf(fid, ['58849.0 2020.0000 -4.841694e-04 0.5 0.3 ' ...
    '-9.571e-07 0.4 0.2 58880.0 2020.0833\n']);
fprintf(fid, ['58880.0 2020.0833 -4.841700e-04 0.6 0.3 ' ...
    'NaN NaN NaN 58909.0 2020.1666\n']);
fclose(fid);
tc.addTeardown(@() delete(f));
end

% =================================================================== v2.1
function testAnalysisBadInputID(testCase)
verifyError(testCase, @() shLowLevel.shAnalysisGrid(ones(3,4), 1:5, 1:4, 2), ...
    'shLowLevel:shAnalysisGrid:badInput');
end

function testAnalysisBadGridID(testCase)
% non-uniform longitude must be rejected by the rings method
g = ones(8, 10);
lat = linspace(-60, 60, 8);
lon = [0 30 70 100 140 180 220 260 300 340];
verifyError(testCase, ...
    @() shLowLevel.shAnalysisGrid(g, lat, lon, 2, Method = "rings"), ...
    'shLowLevel:shAnalysisGrid:badGrid');
end

function testAnalysisAliasedGridID(testCase)
% nlon <= 2*nmax aliases orders
g = ones(20, 10); lat = linspace(-80, 80, 20); lon = (0:9)*36;
verifyError(testCase, @() shLowLevel.shAnalysisGrid(g, lat, lon, 6, Method = "rings"), ...
    'shLowLevel:shAnalysisGrid:badGrid');
end

function testSynthesisBadMethodID(testCase)
C = zeros(3); S = zeros(3);
verifyError(testCase, @() shLowLevel.shSynthesis(C, S, 1, 1, 0, [0 10 50], ...
    'Method', 'fft'), 'shLowLevel:shSynthesis:badMethod');
end

function testReadTN13ErrorIDs(testCase)
verifyError(testCase, @() shLowLevel.readTN13('/nonexistent/tn13.txt'), ...
    'shLowLevel:readTN13:fileNotFound');
f = [tempname '.txt'];
fid = fopen(f, 'w'); fprintf(fid, 'header only\nno data here\n'); fclose(fid);
cleanup = onCleanup(@() delete(f)); %#ok<NASGU>
verifyError(testCase, @() shLowLevel.readTN13(f), 'shLowLevel:readTN13:noData');
end

function testReadSINEXErrorIDs(testCase)
verifyError(testCase, @() shLowLevel.readSINEX('/nonexistent/x.snx'), ...
    'shLowLevel:readSINEX:fileNotFound');
f = [tempname '.snx'];
fid = fopen(f, 'w'); fprintf(fid, '%%=SNX 2.02\n+SOME/BLOCK\n-SOME/BLOCK\n%%ENDSNX\n'); fclose(fid);
cleanup = onCleanup(@() delete(f)); %#ok<NASGU>
verifyError(testCase, @() shLowLevel.readSINEX(f), 'shLowLevel:readSINEX:noData');
end

function testEvalGFCTEpochOutsideID(testCase)
f = [tempname '.gfc'];
fid = fopen(f, 'w');
fprintf(fid, ['product_type gravity_field\nmodelname T2\n' ...
    'earth_gravity_constant 3.986004415E+14\nradius 6378136.3\n' ...
    'max_degree 2\nformat icgem2.0\nend_of_head ====\n' ...
    'gfct 2 0 -4.84e-4 0.0 0 0 20100101 20150101\n']);
fclose(fid);
cleanup = onCleanup(@() delete(f)); %#ok<NASGU>
model = shLowLevel.shReadGFC(f);
verifyError(testCase, @() shLowLevel.shEvalGFCT(model, 2020.0), ...
    'shLowLevel:shEvalGFCT:epochOutside');
end

function testTvANSBlocksUnavailableID(testCase)
idx = shLowLevel.shIndex(4);
X = randn(idx.P, 12); t = 2002 + (0:11)'/12;
verifyError(testCase, @() shLowLevel.tvANSFilter(X, t, idx, Blocks = 'on', ...
    Constraints = ones(idx.P, 1)), 'shLowLevel:tvANSFilter:blocksUnavailable');
end

function testNoiseCovNotBlockDiagonalID(testCase)
% external NoiseCov on Blocks='on' must be block-diagonal in the
% (order, C/S, parity) partition; Blocks='auto' falls back quietly
rng(30);
idx = shLowLevel.shIndex(4);
X = randn(idx.P, 12); t = 2002 + (0:11)'/12;
Nfull = eye(idx.P) + 0.3 * ones(idx.P);          % dense: NOT block-diag
verifyError(testCase, @() shLowLevel.tvANSFilter(X, t, idx, Blocks = 'on', ...
    NoiseCov = Nfull), 'shLowLevel:buildNoiseCov:notBlockDiagonal');
[Xf, op] = shLowLevel.tvANSFilter(X, t, idx, Blocks = 'auto', NoiseCov = Nfull);
verifyTrue(testCase, all(isfinite(Xf(:))));
verifyEqual(testCase, op.layout, 'full');        % fell back to full path
% a DIAGONAL external N is block-diagonal under any partition: block
% path engages
[~, op2] = shLowLevel.tvANSFilter(X, t, idx, Blocks = 'on', NoiseCov = eye(idx.P));
verifyEqual(testCase, op2.layout, 'blocks');
end

function testSelectBadInputID(testCase)
n1 = 3; T = 5;
ts = shSeries(zeros(n1,n1,T), Ss = zeros(n1,n1,T), Epochs = 2002+(0:T-1)');
verifyError(testCase, @() ts.select([0 7 9]), 'shSeries:select:badInput');
end

function testClimatologyPeriodicBadIndexID(testCase)
T = 24; n1 = 3;
ts = shSeries(1e-9*randn(n1,n1,T), Ss = zeros(n1,n1,T), ...
    Epochs = 2002 + (0:T-1)'/12);
clim = ts.climatology();
verifyError(testCase, @() clim.periodic(1), 'shClimatology:periodic:badIndex');
end

function testAddDegree1NoEpochID(testCase)
g = shCoefficients(zeros(3), zeros(3));
tn = struct('epoch', 2008.29, 'C10', 1e-10, 'C11', 2e-10, 'S11', 3e-10, ...
    'sigC10', 1e-12, 'sigC11', 1e-12, 'sigS11', 1e-12);
verifyError(testCase, @() g.addDegree1(tn), 'shCoefficients:addDegree1:noEpoch');
end

% =============================================================== v2.4
function testTriangleDiffModeFullSineWing(testCase)
% Regression (v2.4.2): the RefC/RefS difference branch masked S with
% tril(...,-1), blanking the sine SECTORALS S_nn and rendering the left
% wing one column narrower than the C wing in every diff triangle
% (demo D04/D07 figures). Pin the rendered CData: every valid sine cell
% (n >= m >= 1, sectorals included) must be finite; m=0 must be NaN on
% the sine side; the C wing must span m = 0..n.
fig = figure('Visible', 'off');
cleanup = onCleanup(@() close(fig)); %#ok<NASGU>
L = 8; n1 = L + 1;
C = tril(ones(n1));                              % all valid cells nonzero
S = tril(ones(n1)); S(:, 1) = 0;                 % incl. sectorals S_nn
ax = axes('Parent', fig);
shLowLevel.plotSHCoeffTriangle(C, S, 'RefC', 0*C, 'RefS', 0*S, 'Ax', ax);
im = findobj(ax, 'Type', 'image');
verifyNotEmpty(testCase, im, 'no image object rendered');
img = im(1).CData;                               % (L+1) x (2L+1)
verifySize(testCase, img, [n1, 2*L + 1]);
for n = 0:L
    for m = 1:n                                  % sine wing at x = -m
        verifyTrue(testCase, isfinite(img(n+1, L+1-m)), sprintf( ...
            'sine cell S(%d,%d) missing from diff triangle', n, m));
    end
    for m = 0:n                                  % cosine wing at x = +m
        verifyTrue(testCase, isfinite(img(n+1, L+1+m)), sprintf( ...
            'cosine cell C(%d,%d) missing from diff triangle', n, m));
    end
    if n < L                                     % outside the triangle
        verifyTrue(testCase, all(isnan(img(n+1, [1:L-n, L+2+n:end]))), ...
            sprintf('degree %d shows cells beyond |m| = n', n));
    end
end
end


function testNoMapIsDrawnHere(testCase)
%TESTNOMAPISDRAWNHERE geoMap is the single cartographic authority
%   (v3.32.0). This replaces the contract test of shLowLevel.plotSHMap,
%   which is gone: there were two renderers in two toolboxes, in
%   different projections, and no instrument compared them.
%
%   What is asserted here is that the drawing entry points FAIL WELL
%   when geoMap is absent - which is the state of the CI machine, so
%   this is the path a user without geoMap actually meets. The drawing
%   itself is geoMap's territory and is tested there.
%
%   NOTE the early return below: on a machine WITH geoMap this test stops
%   after the first assertion, so everything past it runs only in CI.
%   That is how a bad shSeries constructor call in this very test passed
%   a 264-test acceptance run and failed CI - the two runs cover
%   different halves, and neither is redundant.
verifyEmpty(testCase, which('shLowLevel.plotSHMap'), ...
    'the second renderer must stay deleted');

if ~isempty(which('geo.map'))
    return      % geoMap present: the error path below cannot be reached
end
rng(9);
L = 5; n1 = L + 1;
C = tril(randn(n1)) * 1e-10;
g = shCoefficients(C, zeros(n1));
lat = -60:30:60; lon = 0:90:270;

verifyError(testCase, @() g.map(lat, lon, Quantity = "geoid"), ...
    'shLowLevel:requireGeoMap:geoMapRequired');
verifyError(testCase, @() shLowLevel.requireGeoMap(), ...
    'shLowLevel:requireGeoMap:geoMapRequired');

% the numbers are still available without geoMap - that is the point of
% the bridge, and the error message says so
b = g.toGrid(lat, lon, Quantity = "geoid");
verifyEqual(testCase, size(b.Z), [numel(lat), numel(lon)]);
verifyEqual(testCase, b.Units, "m");

% and the animation refuses BEFORE synthesizing, not after
ts = shSeries(repmat(C, 1, 1, 2), Ss = zeros(n1, n1, 2), ...
    Epochs = [2010.1; 2010.2]);   % raw-stack form needs a matching Ss
verifyError(testCase, @() shLowLevel.writeAnimation(ts, ...
    fullfile(tempdir, 'never_written.avi'), Quantity = "geoid"), ...
    'shLowLevel:requireGeoMap:geoMapRequired');
verifyFalse(testCase, isfile(fullfile(tempdir, 'never_written.avi')));
end

function testSpectrumOverlays(testCase)
rng(82);
fig = figure('Visible', 'off');
cleanup = onCleanup(@() close(fig)); %#ok<NASGU>
L = 30; n1 = L + 1;
C = tril(randn(n1)) * 1e-9 ./ max(1, (0:L)').^2;
S = tril(randn(n1), -1) * 1e-9 ./ max(1, (0:L)').^2; S(:, 1) = 0;
sC = 1e-11 * max(1, (0:L)') / 10 .* ones(n1) .* tril(ones(n1));
spec = shLowLevel.shDegreeRMS(C, S, 'R', 6378136.3, ...
    'SigmaC', sC, 'SigmaS', sC);
ax = axes('Parent', fig);
h = shLowLevel.plotSHSpectrum(spec, 'Ax', ax, 'Kaula', 1e-5, 'MarkCrossover', true);
verifyClass(testCase, h(1), 'matlab.graphics.chart.primitive.Line');
end

function testWriteAnimationSmoke(testCase)
rng(83);
L = 8; n1 = L + 1; T = 2;
Cs = randn(n1, n1, T) * 1e-9; Ss = randn(n1, n1, T) * 1e-9;
for t = 1:T
    Cs(:, :, t) = tril(Cs(:, :, t));
    Ss(:, :, t) = tril(Ss(:, :, t), -1); Ss(:, 1, t) = 0;
end
ts = shSeries(Cs, Ss = Ss, Epochs = [2010.1 2010.2]);
tmp = [tempname '.avi'];                                          % CI-portable
cleanup = onCleanup(@() deleteIfThere(tmp)); %#ok<NASGU>
% v3.32.0: geoMap draws the frames and is not on this machine, so what
% is exercised here is the CONTAINER - codec choice, extension
% validation, frame rate and the sidecar, which are the parts that have
% bitten before and which never needed a renderer.
frames = uint8(randi([0 255], 60, 120, 3, 3));
shLowLevel.writeFrames(frames, tmp, FrameRate = 2, ...
    SidecarExtra = struct('quantity', 'geoid'));
verifyTrue(testCase, isfile(tmp));
d = dir(tmp);
verifyGreaterThan(testCase, d.bytes, 1000);
verifyTrue(testCase, isfile([tmp '.provenance.json']));   % v2.7.0
txt = fileread([tmp '.provenance.json']);
verifyTrue(testCase, contains(txt, '"nFrames"'));
verifyTrue(testCase, contains(txt, '"quantity"'));
delete([tmp '.provenance.json']);

% the named errors, not a codec complaint
verifyError(testCase, @() shLowLevel.writeFrames(frames, ...
    fullfile(tempdir, 'x.gif')), 'shLowLevel:writeFrames:badExtension');
verifyError(testCase, @() shLowLevel.writeFrames(uint8(zeros(4, 4, 3)), ...
    tmp), 'shLowLevel:writeFrames:badSize');
end

function deleteIfThere(f)
if isfile(f), delete(f); end
end

function testBasinScalingRecoversFactor(testCase)
rng(84);
% operator: pure Gaussian attenuation as a tvANS-like op via matFilter
L = 20; idx = shLowLevel.shIndex(L, Nmin = 0);
Wn = shLowLevel.shGaussianWeights(L, 500);
W = diag(Wn(idx.n + 1));
T = 10; ep = 2010 + (0:T-1)/12;
% static matrix operator (Gaussian in idx ordering)
% model series: fixed pattern, varying amplitude
n1 = L + 1;
pat = tril(randn(n1)) * 1e-9; patS = tril(randn(n1), -1) * 1e-9;
patS(:, 1) = 0;
amp = 1 + 0.5 * sin(2*pi*(1:T)/T);
Cs = zeros(n1, n1, T); Ss = Cs;
for t = 1:T
    Cs(:, :, t) = amp(t) * pat; Ss(:, :, t) = amp(t) * patS;
end
tsM = shSeries(Cs, Ss = Ss, Epochs = ep);
b = shLowLevel.basinKernel(idx, [ -10 100; -10 140; 25 140; 25 100 ]);
[k, info] = shLowLevel.basinScaling(W, b, tsM, Idx = idx, TYears = ep);
% k must invert the operator's basin-average attenuation: with a FIXED
% pattern, aTrue = k * aFilt exactly, so sigmaK ~ 0
x1 = shLowLevel.vecFromCS(pat, patS, idx);
kExact = (b' * x1) / (b' * (W * x1));
verifyEqual(testCase, k, kExact, 'RelTol', 1e-10);
verifyLessThan(testCase, info.sigmaK, 1e-8 * abs(k));
verifyEqual(testCase, info.nMatched, T);
verifyError(testCase, ...
    @() shLowLevel.basinScaling(W, b(1:3), tsM, Idx = idx, TYears = ep), ...
    'shLowLevel:basinScaling:badKernel');
end

function testDemoRegistryAndSmoke(testCase)
reg = demo_shAnalysis("list");
verifyEqual(testCase, numel(reg), 16);
verifyEqual(testCase, numel(unique([reg.id])), 16);
verifyTrue(testCase, all(arrayfun(@(r) isa(r.run, 'function_handle'), reg)));
% two cheap cases run headless without touching the screen; a failing
% demo raises demo:casesFailed, which is a hard test failure here
% (D01 failing via an unqualified compat-era plot call slipped through
% this smoke test once - never again)
verifyWarningFree(testCase, ...
    @() demo_shAnalysis(["D01", "D13"], Visible = false));
close all hidden;
verifyError(testCase, @() demo_shAnalysis("D99"), 'shAnalysis:demo:unknownCase');
% fail-and-continue contract: D16 into an impossible target (a FILE
% posing as OutDir) must not abort the run (warning instead);
% StopOnError=true must rethrow. writeGrid itself creates missing
% folders since v2.4.1, so a plain nonexistent dir no longer fails.
badDir = [tempname, '.txt'];
fid = fopen(badDir, 'w'); fclose(fid);
cleanupBad = onCleanup(@() delete(badDir)); %#ok<NASGU>
fprintf(['\n  NOTE: the following D16 "FAILED" line is INTENTIONAL - ' ...
    'it exercises the fail-and-continue contract.\n']);
verifyWarning(testCase, ...
    @() demo_shAnalysis("D16", Visible = false, OutDir = badDir), ...
    'shAnalysis:demo:casesFailed');
close all hidden;
verifyError(testCase, ...
    @() demo_shAnalysis("D16", Visible = false, OutDir = badDir, ...
    StopOnError = true), ?MException);
end

function testAPIExamplesRun(testCase)
% v2.5: every runnable example of the API reference (docs/
% apiExamples.json - the SAME file the workflow-guide Part IV is built
% from) must execute against the canonical fixture workspace. This is
% the executable link between documentation and contract: an API change
% that breaks a documented example fails runAllTests.
root = fileparts(fileparts(mfilename('fullpath')));
J = jsondecode(fileread(fullfile(root, 'docs', 'apiExamples.json')));
d = testCase.TestData.dataDir;
tmp = tempname; mkdir(tmp);
old = cd(tmp);
cleanup = onCleanup(@() cd(old));
cleanup2 = onCleanup(@() rmIfFolder(tmp)); %#ok<NASGU>
% bare-filename fixtures into the cwd
for f = ["ITSG-Grace2018_n60_2008-04.gfc", ...
         "ITSG-Grace_operational_n60_2025-12.gfc", ...
         "TN-13_GEOC_CSR_RL06.3.txt", "TN-14_C30_C20_SLR_GSFC.txt", ...
         "test_variable.gfct", ...
         "ITSG-Grace2018_n96_2008-04_head12.snx"]
    copyfile(fullfile(d, f), tmp);
end
ws = buildAPIWorkspace(tmp);
set(groot, 'defaultFigureVisible', 'off');
cleanup3 = onCleanup(@() set(groot, 'defaultFigureVisible', 'on')); %#ok<NASGU>
failures = strings(1, 0);
for k = 1:numel(J)
    if ~J(k).run, continue; end
    try
        runAPISnippet(J(k).example, ws);
    catch err
        failures(end+1) = J(k).name + ": " + err.message; %#ok<AGROW>
    end
    close all
end
verifyEmpty(testCase, failures, "API examples failed:" + newline + ...
    strjoin(failures, newline));
end

function ws = buildAPIWorkspace(tmp) %#ok<INUSD>
% canonical fixture workspace for the API examples (real data chain)
ws = struct();
ws.g = shCoefficients.read("ITSG-Grace2018_n60_2008-04.gfc", ...
    Epoch = 2008 + 3.5/12);
ws.gF = ws.g.gaussian(350);
ws.g10 = ws.g.truncate(10);
ws.idx = shLowLevel.shIndex(10);
ws.x = shLowLevel.vecFromCS(ws.g10.C, ws.g10.S, ws.idx);
ws.GM = ws.g.GM; ws.R = ws.g.R;
ws.GMref = 3.986004415e14; ws.Rref = 6.3781363e6;
nn = (0:120)';
ws.kn = -0.3 * nn ./ (nn + 6);
% Love-number table via the reader (real-life G7 path)
lnRows = compose("%d %.6f %.6f %.6f", nn, -0.9 * nn ./ (nn + 4), ...
    0.1 * nn ./ (nn + 8), -0.3 * nn ./ (nn + 6));
writelines(["# n h l k"; lnRows], "ln_table.txt");
ws.LN = shLowLevel.readLoveNumbers("ln_table.txt", Nmax = 120);
copyfile("ln_table.txt", "prem_load.txt");   % readLoveNumbers help example
ws.lat = -88:8:88; ws.lon = 0:12:348;    % = the grid axes below
ws.latPts = [10 20 30]; ws.lonPts = [40 50 60];
ws.latGc = [10 20 30]; ws.latGd = [10.06 20.10 30.12];
ws.theta = deg2rad(30:15:60);
ws.grid = ws.g10.synthesis(-88:8:88, 0:12:348);
ws.tn13 = shLowLevel.readTN13("TN-13_GEOC_CSR_RL06.3.txt");
ws.tn14 = shLowLevel.readTN14("TN-14_C30_C20_SLR_GSFC.txt");
ws.model = shLowLevel.shReadGFC("test_variable.gfct");   % struct incl. variableTerms
% synthetic monthly series + tvANS chain
rng(31);
L = 10; T = 48; n1 = L + 1;              % same L as ws.idx = shIndex(10)
tY = 2019 + (0:T-1)'/12;                 % continuous TN-13/14 coverage
mL = tril(true(n1)); mL1 = mL; mL1(:, 1) = false;
Cs = zeros(n1, n1, T); Ss = Cs;
for t = 1:T
    Cs(:,:,t) = (mL .* randn(n1)) * 1e-9 + (mL * 2e-9) * cos(2*pi*tY(t));
    Ss(:,:,t) = (mL1 .* randn(n1)) * 1e-9;
end
ws.ts = shSeries(Cs, Ss = Ss, Epochs = tY);
ws.Cs = Cs; ws.Ss = Ss;                  % shSeries constructor example
ws.C = ws.g10.C; ws.S = ws.g10.S;        % shCoefficients constructor example
ws.gad = ws.g;                           % plus: epoch-matched background
ws.gMean = ws.g;                         % minus: any compatible field
ws.w = ones(size(ws.g.C));               % times: per-coefficient weights
ws.c20slr = ws.tn14.C20(1);              % setCoefficient
ws.tsGAD = ws.ts;                        % restore: epoch-matched series
[ws.clim, ws.resid] = ws.ts.climatology(Periods = 161/365.25);
idxF = shLowLevel.shIndex(L);
ws.Ac = exp(-idxF.n / 3) .* randn(idxF.P, 1);
[ws.tsF, ws.op, ws.info] = ws.ts.filter("tvANS", Blocks = "off");
ws.B = randn(idxF.P, 2);
ws.b = ws.B(:, 1);
[ws.avg, ws.out] = shLowLevel.basinDeconvolve(ws.B, ws.op);
ws.Y3 = [ws.avg(1, :)', ws.avg(1, :)' + 2e-4 * randn(T, 1), ...
    ws.avg(1, :)' + 5e-4 * randn(T, 1)];   % 3-center stack for TCH
ws.tYears = tY;
XV = zeros(ws.idx.P, T);                 % idx-ordered raw stack (L = 10)
for t = 1:T
    XV(:, t) = shLowLevel.vecFromCS(Cs(:,:,t), Ss(:,:,t), ws.idx);
end
ws.X = XV;
[~, ws.Xres] = shLowLevel.fitDeterministicModel(XV, tY);   % idx-ordered residuals
ws.N = shLowLevel.buildNoiseCov(ws.Xres, ws.idx);
A0 = randn(ws.idx.P);
ws.M = (A0 * A0' / ws.idx.P) * 1e-20;   % SPD "covariance" for errorMap
% three 'centers' for combineCenters: identical series suffice for
% an example run (shSeries has no plus by design - restore covers it)
ws.tsCSR = ws.ts; ws.tsGFZ = ws.ts; ws.tsJPL = ws.ts;
ws.giaModel = 1e-10 * ws.g10;
ws.gLoad = ws.g10; ws.oceanMask = [];   % fingerprint example not run
ws.res = randn(200, 1);
ws.coef = []; ws.t0 = 2016.0;           % fromCoef example not run
ws.gT10 = ws.g10;
end

function runAPISnippet(code, ws)
% evaluate one documented example inside the fixture workspace
fn = fieldnames(ws);
for kk = 1:numel(fn)
    eval(sprintf('%s = ws.%s;', fn{kk}, fn{kk}));  %#ok<EVLDOT>
end
eval(code);  %#ok<EVLC>
end

function testSetupDryRunPlan(testCase)
% setup_shAnalysis(DryRun=true) must have ZERO side effects and return
% the full cumulative plan for the requested level.
p0 = path;
restore = onCleanup(@() path(p0)); %#ok<NASGU>
s = setup_shAnalysis(DryRun = true, Download = "starter", ...
    DDK = [2 5], Permanent = true, Docs = true, Quiet = true);
verifyEqual(testCase, path, p0);                 % path untouched
verifyEqual(testCase, s.pathAction, "planned");
txt = strjoin(s.plan, newline);
verifyTrue(testCase, contains(txt, "TN-14"));
verifyTrue(testCase, contains(txt, "TN-13"));
verifyTrue(testCase, contains(txt, "DDK2, DDK5"));
verifyTrue(testCase, contains(txt, "ITSG n96"));
verifyTrue(testCase, contains(txt, "2008-04, 2025-12"));
verifyTrue(testCase, contains(txt, "builddocsearchdb"));
verifyTrue(testCase, s.ok && isempty(s.fetched) && isempty(s.failed));
% cumulative levels: "core" plans TN but no DDK/ITSG lines
s2 = setup_shAnalysis(DryRun = true, Download = "core", Quiet = true);
t2 = strjoin(s2.plan, newline);
verifyTrue(testCase, contains(t2, "TN-13") && ~contains(t2, "DDK") ...
    && ~contains(t2, "ITSG"));
% default: path line only
s3 = setup_shAnalysis(DryRun = true, Quiet = true);
verifyEqual(testCase, numel(s3.plan), 1);
verifyTrue(testCase, startsWith(s3.plan(1), "path:"));
% Update=true is announced in the plan lines
s4 = setup_shAnalysis(DryRun = true, Download = "core", ...
    Update = true, Quiet = true);
verifyTrue(testCase, contains(strjoin(s4.plan, newline), ...
    "(update existing)"));
end

function testComparePlotsSmoke(testCase)
% v2.6.0 visualization smoke: taylorDiagram and the 4-panel figures of
% both compare aggregators build and close without error
old = get(0, 'DefaultFigureVisible');
cl = onCleanup(@() set(0, 'DefaultFigureVisible', old)); %#ok<NASGU>
set(0, 'DefaultFigureVisible', 'off');
figure;
h = shLowLevel.taylorDiagram(1.0, [0.8, 1.1], [0.9, 0.95], ...
    Labels = ["a", "b"], Normalize = true);
verifyTrue(testCase, isgraphics(h));
d = shxTestDataDir();
fG = fullfile(d, 'ITSG-Grace2018_n60_2008-04.gfc');
verifyTrue(testCase, isfile(fG));
g = shCoefficients.read(fG, Epoch = 2008.29);
[~, h1] = shLowLevel.compareSolutions(g, g.gaussian(500), Plot = true, ...
    LatDeg = -85:5:85, LonDeg = 0:9:351);
verifyTrue(testCase, isgraphics(h1));
rng(11); n1 = 7; T = 24;
Cs = 1e-9 * randn(n1, n1, T); Ss = 1e-9 * randn(n1, n1, T);
mk = @(s) shSeries(Cs + s * 1e-11 * randn(n1, n1, T), ...
    Ss = Ss + s * 1e-11 * randn(n1, n1, T), Epochs = 2019 + (0:T-1)'/12);
[~, h2] = shLowLevel.compareSeries({mk(1), mk(2), mk(3)}, Plot = true, ...
    LatDeg = -80:20:80, LonDeg = 0:30:330);
verifyTrue(testCase, isgraphics(h2));
close all
end

function testProvenanceSidecars(testCase)
% v2.7.0: writers emit <file>.provenance.json (Sidecar=false disables)
% and writeGrid netCDF is CF-1.8 complete with a dynamic source stamp
rng(22); L = 6;
C = 1e-9 * randn(L+1); S = 1e-9 * randn(L+1); S(:, 1) = 0;
tmp = tempname; mkdir(tmp);
cl = onCleanup(@() rmIfFolder(tmp)); %#ok<NASGU>
fg = fullfile(tmp, 'out.gfc');
shLowLevel.writeGFC(fg, C, S, 3.986004415e14, 6378136.3);
sj = [fg '.provenance.json'];
verifyTrue(testCase, isfile(sj));
p = jsondecode(fileread(sj));
verifyTrue(testCase, contains(p.tool, "shAnalysis"));
verifyEqual(testCase, p.nmax, L);
verifyTrue(testCase, isfield(p, 'matlab') && isfield(p, 'created'));
% opt-out
fg2 = fullfile(tmp, 'out2.gfc');
shLowLevel.writeGFC(fg2, C, S, 3.986004415e14, 6378136.3, Sidecar = false);
verifyFalse(testCase, isfile([fg2 '.provenance.json']));
% netCDF: CF-1.8 attributes + sidecar
lat = -80:20:80; lon = 0:30:330;
G = randn(numel(lat), numel(lon));
fn = fullfile(tmp, 'grid.nc');
shLowLevel.writeGrid(fn, G, lat, lon, Name = "ewh", Units = "m");
verifyEqual(testCase, ncreadatt(fn, '/', 'Conventions'), 'CF-1.8');
verifyEqual(testCase, ncreadatt(fn, 'lat', 'standard_name'), 'latitude');
verifyEqual(testCase, ncreadatt(fn, 'lon', 'axis'), 'X');
verifyEqual(testCase, ncreadatt(fn, 'ewh', 'coordinates'), 'lat lon');
src = ncreadatt(fn, '/', 'source');
v = shLowLevel.version();
verifyTrue(testCase, contains(src, char(v.Version)));   % no stale stamps
verifyTrue(testCase, isfile([fn '.provenance.json']));
end

function testStandardChain(testCase)
% v3.1.0: the canonical pipeline entry point on fixtures - order,
% report, GIA subtraction, all three filter forms, error contracts
d = shxTestDataDir();
src = fullfile(d, 'ITSG-Grace2018_n60_2008-04.gfc');
tn14 = fullfile(d, 'TN-14_C30_C20_SLR_GSFC.txt');
% the shipped GFZ fixture spells the release with an UNDERSCORE
% (RL06_3), unlike CSR and JPL. A dot here made assumeTrue filter this
% whole test out silently for four releases - a skipped test looks
% exactly like a green one in the summary, so verify the fixtures exist
% rather than assuming them away.
tn13 = fullfile(d, 'TN-13_GEOC_GFZ_RL06_3.txt');
verifyTrue(testCase, isfile(src), 'missing fixture: ' + string(src));
verifyTrue(testCase, isfile(tn14), 'missing fixture: ' + string(tn14));
verifyTrue(testCase, isfile(tn13), 'missing fixture: ' + string(tn13));
fol = tempname; mkdir(fol);
cl = onCleanup(@() rmIfFolder(fol)); %#ok<NASGU>
copyfile(src, fullfile(fol, 'ITSG-Grace2018_n60_2008-04.gfc'));
copyfile(src, fullfile(fol, 'ITSG-Grace2018_n60_2008-05.gfc'));
[ts, rep] = shLowLevel.standardChain(fol, TN14File = tn14, ...
    Degree1File = tn13, Filter = "gauss300", Quiet = true);
verifyEqual(testCase, ts.nEpochs, 2);
verifyEqual(testCase, numel(rep.steps), 4);      % read/TN14/deg1/filter
verifyTrue(testCase, contains(rep.version, "shAnalysis"));
verifyTrue(testCase, any(contains(string(ts.history), "gaussian", ...
    'IgnoreCase', true)) || numel(ts.history) >= 3);
% GIA: with t0 = first epoch, only the second epoch shifts
gT = shCoefficients(zeros(61), zeros(61));
gT = gT.setCoefficient(2, 0, 1e-9, NaN);
[t2, ~] = shLowLevel.standardChain(fol, TN14 = false, Degree1 = "none", ...
    GIA = gT, GIAEpoch = NaN, Filter = "none", Quiet = true);
[t0, ~] = shLowLevel.standardChain(fol, TN14 = false, Degree1 = "none", ...
    Filter = "none", Quiet = true);
dt = t2.epochs(2) - t2.epochs(1);
g2 = t2.at(2); g0 = t0.at(2);
% t0 = mean epoch. RelTol 1e-10 was never exercised (this whole test was
% filtered out by a fixture-name typo until v3.8.2) and is too tight for
% a value that survives a gfc write/read round trip: the epoch is stored
% as a decimal year in text, so dt carries the format's precision, not
% MATLAB's. Observed agreement 5.3e-10; 1e-8 still catches any real
% error in the GIA scaling, which would be a relative change of order 1.
verifyEqual(testCase, g0.C(3, 1) - g2.C(3, 1), (dt / 2) * 1e-9, ...
    'RelTol', 1e-8);
% custom W path (designFilter output drops in)
g1 = t0.at(1);
sc = 3e-11 * ones(61);
W = shLowLevel.designFilter(sc, sc, Kaula = 1e-6);
[tw, repW] = shLowLevel.standardChain(fol, TN14 = false, ...
    Degree1 = "none", Filter = W, Quiet = true);
verifyEqual(testCase, tw.nEpochs, 2);
verifyTrue(testCase, any(contains(repW.steps, "custom W")));
verifyError(testCase, @() shLowLevel.standardChain(fol, ...
    Filter = "bogus", TN14 = false, Degree1 = "none", Quiet = true), ...
    'shLowLevel:standardChain:badFilter');
verifyError(testCase, @() shLowLevel.standardChain(fol, ...
    TN14File = "no/such/file.txt", Degree1 = "none", Quiet = true), ...
    'shLowLevel:standardChain:noTN14');
end

function testVersionMetadata(testCase)
% shLowLevel.version reports toolbox metadata parsed from Contents.m - the
% single source of truth also honoured by MATLAB's ver().
v = shLowLevel.version();
verifyEqual(testCase, v.Name, "shAnalysis");
verifyTrue(testCase, ~isempty(regexp(v.Version, '^\d+\.\d+', 'once')));
verifyTrue(testCase, isfolder(v.Root));
txt = fileread(fullfile(v.Root, 'Contents.m'));
tok = regexp(txt, '^%\s*Version\s+(\S+).*?(\d{2}-\w{3}-\d{4})\s*$', ...
    'tokens', 'once', 'lineanchors');
verifyFalse(testCase, isempty(tok));
verifyEqual(testCase, v.Version, string(tok{1}));
verifyEqual(testCase, v.Date, string(tok{2}));
verifyTrue(testCase, contains(v.Provenance, "Claude"));
end

function testFetchITSGInputIDs(testCase)
% input validation only - no network in unit tests
verifyError(testCase, @() shLowLevel.fetchITSG("2010-4"), 'shLowLevel:fetchITSG:badMonth');
verifyError(testCase, @() shLowLevel.fetchITSG("April 2010"), 'shLowLevel:fetchITSG:badMonth');
verifyError(testCase, @() shLowLevel.fetchITSG(1990), 'shLowLevel:fetchITSG:badMonth');
% daily product (v2.4.1): n40 only; monthly rejects n40
verifyError(testCase, ...
    @() shLowLevel.fetchITSG("2010-04", Product = "daily", Nmax = 96), ...
    'shLowLevel:fetchITSG:badNmax');
verifyError(testCase, @() shLowLevel.fetchITSG("2010-04", Nmax = 40), ...
    'shLowLevel:fetchITSG:badNmax');
end

function testSpectrumPlotOptionsAndAxes(testCase)
rng(102);
fig = figure('Visible', 'off');
cleanup = onCleanup(@() close(fig)); %#ok<NASGU>
L = 15; n1 = L + 1;
C = tril(randn(n1)) * 1e-9; S = tril(randn(n1), -1) * 1e-9; S(:, 1) = 0;
sd = shLowLevel.shDegreeRMS(C, S, 'SigmaC', abs(C)*0.1, 'SigmaS', abs(S)*0.1);
so = shLowLevel.shOrderRMS(C, S);
ax = axes('Parent', fig);
% linear x-axis contract (v2.4.1)
shLowLevel.plotSHSpectrum(sd, 'Ax', ax);
verifyEqual(testCase, ax.XScale, 'linear');
verifyEqual(testCase, ax.YScale, 'log');
% every quantity renders, degree and order domain
for q = ["amplitude", "rms", "variance", "cumamplitude", "cumrms", "cumvariance"]
    cla(ax); shLowLevel.plotSHSpectrum(sd, 'Ax', ax, 'Quantity', char(q));
    cla(ax); shLowLevel.plotSHSpectrum(so, 'Ax', ax, 'Quantity', char(q));
end
% contracts
verifyError(testCase, ...
    @() shLowLevel.plotSHSpectrum({sd, so}, 'Ax', axes('Parent', fig)), ...
    'shLowLevel:plotSHSpectrum:mixedDomains');
verifyError(testCase, ...
    @() shLowLevel.plotSHSpectrum(sd, 'Ax', axes('Parent', fig), ...
    'Quantity', 'variance', 'Kaula', 1e-5), ...
    'shLowLevel:plotSHSpectrum:kaulaDomain');
verifyError(testCase, ...
    @() shLowLevel.plotSHSpectrum(sd, 'Ax', axes('Parent', fig), 'Quantity', 'xxx'), ...
    'shLowLevel:plotSHSpectrum:badQuantity');
% triangle: no center line anymore (v2.4.1)
ax2 = axes('Parent', fig);
shLowLevel.plotSHCoeffTriangle(C, S, 'Ax', ax2);
verifyEmpty(testCase, findobj(ax2, 'Type', 'constantline'));
end

function testDataFolderAndDDKNames(testCase)
% preserve any user preference across the test
had = ispref('shAnalysis', 'dataFolder');
if had
    old = getpref('shAnalysis', 'dataFolder');
    restore = onCleanup(@() setpref('shAnalysis', 'dataFolder', old)); %#ok<NASGU>
else
    restore = onCleanup(@() shLowLevel.dataFolder("reset")); %#ok<NASGU>
end
tmp = tempname;
f = shLowLevel.dataFolder(tmp);
verifyEqual(testCase, char(f), char(string(tmp)));
verifyTrue(testCase, isfolder(f));
verifyEqual(testCase, char(shLowLevel.dataFolder()), char(string(tmp)));
f2 = shLowLevel.dataFolder("reset");
verifyTrue(testCase, endsWith(f2, "data"));
% DDK mapping: 8 unique released names, DDK3 matches the shipped file
nm = shLowLevel.ddkNames();
verifyEqual(testCase, numel(nm), 8);
verifyEqual(testCase, numel(unique(nm)), 8);
verifyEqual(testCase, nm(3), "Wbd_2-120.a_1d12p_4");
% name resolution: DDK3 loads from shipped test data even with a fresh
% (empty) data folder; an unfetched filter errors with the fetch hint
shLowLevel.dataFolder(tmp);
W = shLowLevel.readDDK("DDK3", Nmax = 30);
verifyEqual(testCase, W.nmax, 30);
verifyError(testCase, @() shLowLevel.readDDK("DDK7"), 'shLowLevel:readDDK:notFetched');
verifyError(testCase, @() shLowLevel.fetchDDK(0), 'MATLAB:validators:mustBeInRange');
end


% ------------------------------------------------- tvANS option forwarding
function testFilterForwardsTvANSOptions(testCase)
%TESTFILTERFORWARDSTVANSOPTIONS ts.filter is the full single point of access.
%   The workflow guide has advertised
%   ts.filter("tvANS", Blocks="auto", VCEBands=[...]) since Edition 2 while
%   the method rejected the option (MATLAB:TooManyInputs). Pin the three
%   forwarded tuning options AND the "[] does not override" contract, so
%   the defaults keep exactly one home (shLowLevel.tvANSFilter).
rng(11);
L = 6; T = 30; n1 = L + 1;
tY = 2019 + (0:T-1)'/12;
mL = tril(true(n1)); mL1 = mL; mL1(:, 1) = false;
Cs = zeros(n1, n1, T); Ss = Cs;
for t = 1:T
    Cs(:,:,t) = (mL .* randn(n1)) * 1e-9 + (mL * 2e-9) * cos(2*pi*tY(t));
    Ss(:,:,t) = (mL1 .* randn(n1)) * 1e-9;
end
ts = shSeries(Cs, Ss = Ss, Epochs = tY);

% 1. the three options are accepted (this is what used to throw)
[tsB, ~, infoB] = ts.filter("tvANS", Blocks = "on", VCEBands = [0 3 7]);
verifyClass(testCase, tsB, 'shSeries');
verifySize(testCase, tsB.Cs, [n1 n1 T]);

% 2. banding actually reaches tvANSFilter: the banded run must differ from
%    the unbanded one (a silently dropped option would give equality)
[tsU, ~, infoU] = ts.filter("tvANS", Blocks = "on");
verifyTrue(testCase, max(abs(tsB.Cs(:) - tsU.Cs(:))) > 0);
verifyTrue(testCase, isfield(infoB, 'sigmaXfres') && ...
    isfield(infoU, 'sigmaXfres'));

% 3. [] means "do not override": explicit empties reproduce the defaults
%    bit for bit, so no default is duplicated in shSeries
tsE = ts.filter("tvANS", Blocks = "on", Shrinkage = [], ...
    VCEMinDegree = [], VCEBands = []);
verifyEqual(testCase, tsE.Cs, tsU.Cs);
verifyEqual(testCase, tsE.Ss, tsU.Ss);

% 4. Shrinkage and VCEMinDegree are forwarded too
tsS = ts.filter("tvANS", Blocks = "on", Shrinkage = 0.5);
verifyTrue(testCase, max(abs(tsS.Cs(:) - tsU.Cs(:))) > 0);
tsV = ts.filter("tvANS", Blocks = "on", VCEMinDegree = 2);
verifyTrue(testCase, max(abs(tsV.Cs(:) - tsU.Cs(:))) > 0);

% 5. scalar validators still bite
verifyError(testCase, @() ts.filter("tvANS", Shrinkage = [0.1 0.2]), ...
    'MATLAB:validators:mustBeScalarOrEmpty');

% 6. the low-level entry point rejects banding off the block path -
%    the forwarded option must not swallow that guard
verifyError(testCase, ...
    @() ts.filter("tvANS", Blocks = "off", VCEBands = [0 3 7]), ...
    'shLowLevel:tvANSFilter:bandsNeedBlocks');
end

% --------------------------------------------- documentation-metadata sync
function testVersionMetadataIsConsistent(testCase)
%TESTVERSIONMETADATAISCONSISTENT One version, parsed from Contents.m.
%   Contents.m is the single source of truth (five bugs died from
%   hardcoded version strings). CITATION.cff, the CHANGELOG top section
%   and the generated API reference must agree with it, and ver() must
%   report a short product name rather than a truncated sentence.
root = fileparts(fileparts(mfilename('fullpath')));
v = shLowLevel.version();
verifyMatches(testCase, v.Version, '^\d+\.\d+\.\d+$');

cff = string(fileread(fullfile(root, 'CITATION.cff')));
tok = regexp(cff, 'version:\s*"([^"]+)"', 'tokens', 'once');
verifyEqual(testCase, string(tok{1}), v.Version, ...
    'CITATION.cff version must match Contents.m');

chg = string(fileread(fullfile(root, 'CHANGELOG.md')));
tok = regexp(chg, '##\s*\[([^\]]+)\]', 'tokens', 'once');
verifyEqual(testCase, string(tok{1}), v.Version, ...
    'the top CHANGELOG section must be the current version');
openSec = regexp(chg, '^##\s*\[[^\]]+\]\s*-\s*Unreleased', ...
    'match', 'lineanchors');
verifyEmpty(testCase, openSec, ...
    'a tagged release must not leave "Unreleased" sections behind');

api = string(fileread(fullfile(root, 'html', 'apiReference.html')));
verifyTrue(testCase, contains(api, "API reference (v" + v.Version + ")"), ...
    'html/apiReference.html is stale - regenerate it');

% ver() name: short, no version number, no dangling sentence
mv = ver('shAnalysis');
assumeNotEmpty(testCase, mv, ...
    'ver() needs the toolbox folder to be named shAnalysis');
verifyEqual(testCase, numel(mv), 1);
verifyEqual(testCase, string(mv.Version), v.Version);
verifyLessThan(testCase, strlength(string(mv.Name)), 60);
verifyFalse(testCase, contains(string(mv.Name), digitsPattern));
end

function testHelpBrowserTocIsComplete(testCase)
%TESTHELPBROWSERTOCISCOMPLETE Every help page is reachable from helptoc.xml.
%   Eleven pages were orphaned (invisible in the Help browser) while the
%   files sat in html/. Both directions are pinned: no orphan pages, no
%   dead targets.
root = fileparts(fileparts(mfilename('fullpath')));
hdir = fullfile(root, 'html');
toc = string(fileread(fullfile(hdir, 'helptoc.xml')));
tk = regexp(toc, 'target="([^"]+)"', 'tokens');
targets = unique(string(cellfun(@(c) c{1}, tk, 'UniformOutput', false)));
d = dir(fullfile(hdir, '*.html'));
files = string({d.name}');
verifyEmpty(testCase, setdiff(files, targets), ...
    'help pages missing from helptoc.xml');
% A target may name a page in a subfolder: html/ref/ holds one generated
% page per entity (WP6) and is represented in the TOC by its index, so
% resolve every target against html/ instead of matching bare names. The
% generated pages themselves are gated by tools/dev/refpages_audit.py.
exists = arrayfun(@(t) isfile(fullfile(hdir, t)), targets);
verifyEmpty(testCase, targets(~exists), ...
    'helptoc.xml points at files that do not exist');
% the removed compat/ folder must not be advertised anywhere as current
lp = string(fileread(fullfile(hdir, 'shAnalysis.html')));
verifyFalse(testCase, contains(lp, "remains available"), ...
    'the landing page still advertises the removed compat/ folder');
cm = string(fileread(fullfile(root, 'Contents.m')));
verifyFalse(testCase, contains(cm, "folder compat/, add to path"), ...
    'Contents.m still advertises the removed compat/ folder');
end

% ------------------------------------------------ in-file help completeness
function testHelpHasNoPlaceholders(testCase)
%TESTHELPHASNOPLACEHOLDERS No option is documented as "see arguments block".
%   58 name-value options across 23 entities used to be "documented" with
%   a pointer to the code, so `help` said nothing while the generated
%   apiReference.html showed size, type and default. Pin that to zero:
%   the in-file help is the primary source, not a redirect.
root = fileparts(fileparts(mfilename('fullpath')));
files = [ ...
    string(fullfile(root, {'shCoefficients.m', 'shSeries.m', ...
                           'shClimatology.m', 'setup_shAnalysis.m'})), ...
    string(fullfile(root, '+shLowLevel', {dir(fullfile(root, ...
        '+shLowLevel', '*.m')).name}))];
bad = strings(0, 1);
for f = files
    if ~isfile(f), continue; end
    txt = string(fileread(f));
    if contains(txt, "see arguments block")
        bad(end+1) = f; %#ok<AGROW>
    end
end
verifyEmpty(testCase, bad, sprintf( ...
    'placeholder help ("see arguments block") in: %s', ...
    strjoin(bad, ', ')));
end

% -------------------------------------------------- documentation sync gate
function testDocSyncAuditIsWired(testCase)
%TESTDOCSYNCAUDITISWIRED The sixth gate exists and runs in CI.
%   The five older gates were all green while the API reference was
%   stale, eleven help pages were unreachable and the guide advertised a
%   call that threw. tools/doc_sync_audit.py closes that hole, so pin
%   that it is present and actually wired into the required CI job -
%   a gate nobody runs is not a gate.
root = fileparts(fileparts(mfilename('fullpath')));
gate = fullfile(root, 'tools', 'doc_sync_audit.py');
verifyTrue(testCase, isfile(gate), 'tools/doc_sync_audit.py is missing');

wf = fullfile(root, '.github', 'workflows', 'ci.yml');
assumeTrue(testCase, isfile(wf), 'no workflow file in this checkout');
txt = string(fileread(wf));
verifyTrue(testCase, contains(txt, "tools/doc_sync_audit.py"), ...
    'doc_sync_audit.py is not run by the CI workflow');
% it must run BEFORE MATLAB: a python gate that only fires after the
% toolbox is up wastes the fast feedback it exists for.
% Match the STEP, not the bare action id. A header comment naming the
% action put that id at byte 913 while the gate sat at 3399, so this
% check read the prose as the MATLAB step and failed a workflow whose
% step order was correct throughout (2026-09-05). The 'uses: ' prefix
% cannot occur in a comment, so only the real step matches.
%
% THE ANCHOR MOVED (2026-09-06). It used to be setup-matlab, which has
% been removed: its condition was false for every leg the matrix
% produces, so it had been skipped on every run, and it could not have
% worked anyway on a private repository. Anchoring on a step that no
% longer exists made this check fail with 'must run before the MATLAB
% setup step' on a workflow whose order was correct - the same false
% report as 2026-09-05, from the opposite cause.
%
% The anchor is now the FIRST step that touches MATLAB at all, whichever
% it is: the shared probe action or any matlab-actions step. Taking the
% minimum means a reordering cannot slip the gate behind MATLAB by
% introducing a new first step.
iGate = strfind(txt, "tools/doc_sync_audit.py");
iML = [strfind(txt, "uses: matlab-actions/"), ...
       strfind(txt, "uses: astrobayer/ci-actions/matlab-probe")];
verifyTrue(testCase, ~isempty(iML) && iGate(1) < min(iML), ...
    'doc_sync_audit.py must run before the first MATLAB step');
end

% ------------------------------------------------------------- safeMove
function testSafeMoveContract(testCase)
%TESTSAFEMOVECONTRACT The fetchers' final swap: verify, retry, report.
%   safeMove replaces a bare movefile in all six fetchers. It must move
%   the file, VERIFY the outcome rather than trust the status flag,
%   retry a configurable number of times, and fail with an actionable
%   identifier rather than a bare OS message.
d = tempname;
mkdir(d);
cl = onCleanup(@() rmIfFolder(d)); %#ok<NASGU>
src = fullfile(d, 'a.bin');
dst = fullfile(d, 'b.bin');

% happy path: one attempt, file actually moved
writematrix(magic(4), src, 'FileType', 'text');
n = shLowLevel.safeMove(src, dst);
verifyEqual(testCase, n, 1);
verifyTrue(testCase, isfile(dst));
verifyFalse(testCase, isfile(src));

% overwriting an existing destination is the normal fetcher case
writematrix(magic(3), src, 'FileType', 'text');
verifyEqual(testCase, shLowLevel.safeMove(src, dst), 1);
verifyEqual(testCase, readmatrix(dst, 'FileType', 'text'), magic(3));

% a missing source is a caller bug, not a lock: say so immediately
verifyError(testCase, @() shLowLevel.safeMove(fullfile(d, 'nope'), dst), ...
    'shLowLevel:safeMove:noSource');

% a missing destination folder cannot be cured by waiting: report it
% at once, and do not blame a scanner for a caller bug
writematrix(1, src, 'FileType', 'text');
bad = fullfile(d, 'no_such_dir', 'c.bin');
t0 = tic;
verifyError(testCase, @() shLowLevel.safeMove(src, bad), ...
    'shLowLevel:safeMove:noDestFolder');
verifyLessThan(testCase, toc(t0), 1, ...
    'an impossible move must not spend the retry budget');
verifyTrue(testCase, isfile(src), ...
    'a failed move must leave the source in place');
end


function testSafeMoveSurvivesALockedDestination(testCase)
%TESTSAFEMOVESURVIVESALOCKEDDESTINATION The case this function exists for.
%   On Windows an antivirus or sync client holds a freshly written file
%   for a moment and movefile fails with a sharing violation. Reproduced
%   here by keeping the destination open and releasing it from a timer
%   while safeMove retries.
%
%   This is the ONLY test of the retry loop, deliberately. POSIX renames
%   over open files, and permission tricks do not substitute: the CI
%   runner is root, so a read-only destination folder does not block it
%   either (tried; the move succeeded). Rather than fake a failure on
%   Linux, the loop is tested on the platform whose behaviour it exists
%   for - which is also the acceptance machine.
assumeTrue(testCase, ispc, ...
    'file locking during a move is Windows behaviour');
d = tempname;
mkdir(d);
cl = onCleanup(@() rmIfFolder(d)); %#ok<NASGU>
src = fullfile(d, 'a.bin');
dst = fullfile(d, 'b.bin');
writematrix(magic(4), src, 'FileType', 'text');
fid = fopen(dst, 'w');
fwrite(fid, 'held by a scanner');
verifyFalse(testCase, movefile(src, dst, 'f'), ...
    'the destination is not actually locked - test cannot conclude');

% Retries = 0 is a plain movefile: it must fail against the held file,
% spend no time waiting, and leave the source in place
t0 = tic;
verifyError(testCase, @() shLowLevel.safeMove(src, dst, Retries = 0), ...
    'shLowLevel:safeMove:locked');
verifyLessThan(testCase, toc(t0), 1);
verifyTrue(testCase, isfile(src), ...
    'a failed move must leave the source in place');

% with retries, the lock is outlived: released at 0.4 s from a timer
rel = timer('StartDelay', 0.4, 'TimerFcn', @(~, ~) fclose(fid));
clT = onCleanup(@() delete(rel)); %#ok<NASGU>
start(rel);
t0 = tic;
n = shLowLevel.safeMove(src, dst, Pause = 0.15, Retries = 6);
verifyGreaterThan(testCase, n, 1, ...
    'the first attempt must have failed against the held file');
verifyGreaterThanOrEqual(testCase, toc(t0), 0.15);   % backoff was spent
verifyTrue(testCase, isfile(dst));
verifyFalse(testCase, isfile(src));
end

% ------------------------------------- correction tables trail the data
function testStandardChainHandlesTrailingCorrectionTables(testCase)
%TESTSTANDARDCHAINHANDLESTRAILINGCORRECTIONTABLES The newest months.
%   TN-13 and TN-14 are published weeks after the monthly solutions, so
%   the newest one or two epochs of a fresh series are ALWAYS uncovered.
%   The chain used to stop with "No TN-13 entry within 0.050 yr", which
%   made routine use of an up-to-date series impossible. Uncovered
%   epochs are now dropped and the fact recorded in the report.
dd = shxTestDataDir();
fol = tempname;
mkdir(fol);
cl = onCleanup(@() rmIfFolder(fol)); %#ok<NASGU>

% one solution the tables cover, and one far in the future that no
% table can reach - the situation a fresh download produces
% epoch is read-only on the value class; a series takes its epochs from
% the ITSG-style filename, which is also how a real folder works
g = shCoefficients.read(fullfile(dd, 'ITSG-Grace2018_n60_2008-04.gfc'));
g.write(fullfile(fol, 'ITSG-Grace2018_n60_2008-04.gfc'), Sidecar = false);
g.write(fullfile(fol, 'ITSG-Grace2018_n60_2099-07.gfc'), Sidecar = false);

tn14 = fullfile(dd, 'TN-14_C30_C20_SLR_GSFC.txt');
tn13 = fullfile(dd, 'TN-13_GEOC_CSR_RL06.3.txt');

[ts, rep] = shLowLevel.standardChain(fol, TN14File = tn14, ...
    Degree1File = tn13, Filter = "none", Quiet = true);
verifyEqual(testCase, ts.nEpochs, 1, ...
    'the uncovered epoch must be dropped, not carried uncorrected');
verifyLessThan(testCase, ts.epochs, 2099);
verifyTrue(testCase, any(contains(rep.steps, "dropped")), ...
    'a dropped epoch must be visible in the provenance report');

% the old behaviour is still available for anyone who wants it
verifyError(testCase, @() shLowLevel.standardChain(fol, ...
    TN14File = tn14, Degree1File = tn13, Filter = "none", ...
    OnMissing = "error", Quiet = true), ...
    'shLowLevel:standardChain:uncoveredEpochs');

% a series with no overlap at all is a different mistake and says so
folF = tempname;
mkdir(folF);
clF = onCleanup(@() rmIfFolder(folF)); %#ok<NASGU>
g.write(fullfile(folF, 'ITSG-Grace2018_n60_2099-07.gfc'), Sidecar = false);
verifyError(testCase, @() shLowLevel.standardChain(folF, ...
    TN14File = tn14, Degree1File = tn13, Filter = "none", ...
    Quiet = true), 'shLowLevel:standardChain:noCoveredEpochs');
end

function testProvenanceSidecarsDoNotBreakTheRoundTrip(testCase)
%TESTPROVENANCESIDECARSDONOTBREAKTHEROUNDTRIP Write a folder, read it back.
%   writeGFC drops "<file>.gfc.provenance.json" beside every export, and
%   the read pattern has to be loose enough for ".gfc.gz" - so "*.gfc*"
%   matched the sidecars and a folder written BY the toolbox could not be
%   read back BY the toolbox. Also pins that the class API can switch the
%   sidecar off, which it previously could not.
dd = shxTestDataDir();
fol = tempname;
mkdir(fol);
cl = onCleanup(@() rmIfFolder(fol)); %#ok<NASGU>
g = shCoefficients.read(fullfile(dd, 'ITSG-Grace2018_n60_2008-04.gfc'));

g.write(fullfile(fol, 'ITSG-Grace2018_n60_2008-04.gfc'));   % sidecar on
g.write(fullfile(fol, 'ITSG-Grace2018_n60_2009-04.gfc'));
verifyTrue(testCase, isfile(fullfile(fol, ...
    'ITSG-Grace2018_n60_2008-04.gfc.provenance.json')), ...
    'the sidecar is expected - this test is about reading past it');

ts = shSeries.fromFolder(fol);
verifyEqual(testCase, ts.nEpochs, 2, ...
    'sidecars must not be read as solutions');
verifyEqual(testCase, sort(ts.epochs(:)), [2008.292; 2009.292], ...
    'AbsTol', 0.01);

% and the class API can suppress it
g.write(fullfile(fol, 'plain.gfc'), Sidecar = false);
verifyFalse(testCase, isfile(fullfile(fol, 'plain.gfc.provenance.json')));
end

% ------------------------------------------------- generated tutorials
function testMakeTutorialsFollowsTheRegistry(testCase)
%TESTMAKETUTORIALSFOLLOWSTHEREGISTRY Tutorials are generated, not curated.
%   demo_shAnalysis is the single source of truth for what the toolbox
%   demonstrates. A parallel set of hand-written tutorials would drift
%   from it within a release - and .mlx is a binary zip, so the drift
%   would not even show in a diff. Pin that every case gets a tutorial
%   and that the content comes from the registry.
d = tempname;
cl = onCleanup(@() rmIfFolder(d)); %#ok<NASGU>

out = shLowLevel.makeTutorials(Dest = d, Cases = ["D01" "D05"], ...
    Convert = false, Quiet = true);
verifyEqual(testCase, numel(out.files), 2);
verifyEmpty(testCase, out.mlx);
verifyTrue(testCase, all(isfile(out.files)));

reg = demo_shAnalysis("list");
r1 = reg(string({reg.id}) == "D01");
txt = string(fileread(out.files(1)));
verifyTrue(testCase, contains(txt, r1.title), ...
    'the title must come from the registry');
verifyTrue(testCase, contains(txt, r1.fns), ...
    'the function list must come from the registry');
verifyTrue(testCase, contains(txt, "demo_shAnalysis(""D01"""), ...
    'the tutorial must actually run its case');
verifyTrue(testCase, startsWith(txt, "%%"), ...
    'Live Editor section markers are what make this a live script');
verifyTrue(testCase, contains(txt, "overwritten on the next run"), ...
    'a generated file must say it is generated');

% "all" covers every registered case, one file each
outAll = shLowLevel.makeTutorials(Dest = d, Convert = false, Quiet = true);
verifyEqual(testCase, numel(outAll.files), numel(reg));

verifyError(testCase, @() shLowLevel.makeTutorials(Dest = d, ...
    Cases = "D99", Convert = false, Quiet = true), ...
    'shLowLevel:makeTutorials:unknownCase');
end

function testGravisChainsContract(testCase)
%TESTGRAVISCHAINSCONTRACT v3.8.8 chains fail loudly on missing pieces.
kn = [(0:4)', zeros(5,1)];
tmp = tempname; mkdir(tmp);
cl = onCleanup(@() rmdir(tmp, 's'));
% kn is required - no frame is assumed
verifyError(testCase, @() shLowLevel.greenlandChain(tmp, tmp), ...
    'shLowLevel:gravisRegionChain:noKn');
verifyError(testCase, @() shLowLevel.twsChain(tmp, tmp), ...
    'shLowLevel:twsChain:noKn');
% an empty series folder fails loudly at the first stage (the aux-file
% check with its fetch hint sits behind the series read by design)
% shSeries.fromFolder asserts isfolder and then DELEGATES to
% shSeries.read: tmp exists, so the isfolder guard passes and the empty
% folder is caught by read's pattern check. Which guard fires depends on
% the input, not only on which function is called (v5.0.1).
verifyError(testCase, @() shLowLevel.twsChain(tmp, tmp, kn = kn), ...
    'shSeries:read:noFiles');
verifyError(testCase, @() shLowLevel.gravisL2B(tmp, tmp), ...
    'shSeries:read:noFiles');
end

function testGravisChainsRealData(testCase)
%TESTGRAVISCHAINSREALDATA Opt-in science anchor (SHX_GRAVIS_FOLDER +
%   SHX_SERIES_FOLDER + SHX_DDK_FOLDER): twsChain must reproduce the
%   validated Amazonas numbers (guide V8) on the real series.
% opt-in via env vars OR persistent MATLAB preferences - the latter
% survive sessions without touching the environment:
%   setpref("shAnalysis", "GravisFolder", "E:/.../GravIS") etc.
gf = getenv('SHX_GRAVIS_FOLDER');
if isempty(gf), gf = getpref('shAnalysis', 'GravisFolder', ''); end
sf = getenv('SHX_SERIES_FOLDER');
if isempty(sf), sf = getpref('shAnalysis', 'SeriesFolder', ''); end
df = getenv('SHX_DDK_FOLDER');
if isempty(df), df = getpref('shAnalysis', 'DDKFolder', ''); end
assumeTrue(testCase, ~isempty(gf) && ~isempty(sf) && ~isempty(df), ...
    ['set SHX_* env vars or setpref("shAnalysis", ...) preferences ' ...
     '(GravisFolder/SeriesFolder/DDKFolder) to enable']);
kn = readmatrix(fullfile(shxTestDataDir(), ...
    'loadLoveNumbers_Gegout97.txt'), FileType = 'text', NumHeaderLines = 2);
out = shLowLevel.twsChain(sf, gf, kn = kn, DDKFolder = df, ...
    Basins = "Amazonas", Quiet = true);
verifyEqual(testCase, out.trend(1), 0.01, AbsTol = 0.05);
verifyEqual(testCase, out.amplitude(1), 20.6, AbsTol = 0.5);
end

% ------------------------------------ mean/select period contract (v3.29.0)
function testMeanPeriodContract(testCase)
t = 2004 + ((0:35)' + 0.5)/12;
ts = shSeries(ones(3,3,36), Ss = zeros(3,3,36), Epochs = t);
verifyError(testCase, @() ts.mean(Range = [2010 2011]), ...
    'shSeries:mean:emptyRange');
verifyError(testCase, @() ts.mean(Range = [2006 2004]), ...
    'shSeries:range:badRange');
verifyError(testCase, @() ts.mean(Range = [2004 2007], MinEpochs = 99), ...
    'shSeries:mean:tooFewEpochs');
% "model" needs 6 + 2K epochs inside the window
verifyError(testCase, @() ts.mean(Range = [2004 2004.4], ...
    Estimator = "model"), 'shSeries:mean:tooFewEpochs');
verifyError(testCase, @() ts.select([1 2], Range = [2004 2005]), ...
    'shSeries:select:badInput');
verifyError(testCase, @() ts.mean(Estimator = "voronoi"), ?MException);
end

function testSelectAmbiguousRangeWarns(testCase)
% on a daily series [2004 2010] is a valid INDEX pair as well as a window
T = 2600;
t = 2003 + (0:T-1)'/365.25;
ts = shSeries(zeros(3,3,T), Ss = zeros(3,3,T), Epochs = t);
verifyGreaterThan(testCase, max(t), 2010);
verifyWarning(testCase, @() ts.select([2004 2010]), ...
    'shSeries:select:ambiguousRange');
w = warning('off', 'shSeries:select:ambiguousRange');
restore = onCleanup(@() warning(w));
idx = ts.select([2004 2010]);
verifyEqual(testCase, idx.nEpochs, 2);            % indices, as documented
win = ts.select(Range = [2004 2010]);
verifyEqual(testCase, win.nEpochs, nnz(t >= 2004 & t <= 2010));
verifyGreaterThan(testCase, win.nEpochs, 2000);
end

% --------------------------------- NEU gradient (v3.30.0)
function testGradientContract(testCase)
%TESTGRADIENTCONTRACT the invariants a particle animation depends on:
%   points and grid agree, the two unit conventions differ by exactly r,
%   the east component is NaN where east does not exist, and a zonal
%   field has an east gradient of exactly zero (not "small").
rng(31);
L = 8; n1 = L + 1;
C = tril(randn(n1)) * 1e-10;
S = tril(randn(n1), -1) * 1e-10; S(:, 1) = 0;
GM = 3.986004415e14; R = 6378136.3;
lat = [-60, -12.5, 33, 71]; lon = [0, 47, 190, 359.5];

% points reproduces the grid diagonal exactly (same code path, same data)
gg = shLowLevel.shSynthesisGradient(C, S, GM, R, lat, lon);
gp = shLowLevel.shSynthesisGradient(C, S, GM, R, lat, lon, Mode = "points");
verifyEqual(testCase, size(gg.north), [numel(lat), numel(lon)]);
verifyEqual(testCase, size(gp.north), [numel(lat), 1]);
for k = 1:numel(lat)
    verifyEqual(testCase, gp.north(k), gg.north(k, k), 'RelTol', 1e-13);
    verifyEqual(testCase, gp.east(k), gg.east(k, k), 'RelTol', 1e-13);
end

% perRadian is r times perMeter in EVERY component, up included
a = shLowLevel.shSynthesisGradient(C, S, GM, R, lat, lon, Quantity = "potential");
b = shLowLevel.shSynthesisGradient(C, S, GM, R, lat, lon, ...
    Quantity = "potential", Units = "perRadian");
for f = ["north", "east", "up"]
    verifyEqual(testCase, b.(f), R * a.(f), 'RelTol', 1e-13);
end

% the pole: east does not exist, north does. Without the guard the
% cos(phi) division returns a finite, meaningless number.
gpole = shLowLevel.shSynthesisGradient(C, S, GM, R, [90, -90, 45], lon);
verifyTrue(testCase, all(isnan(gpole.east(1, :))));
verifyTrue(testCase, all(isnan(gpole.east(2, :))));
verifyTrue(testCase, all(isfinite(gpole.east(3, :))));
verifyTrue(testCase, all(isfinite(gpole.north(:))));

% a zonal field has NO east gradient - exactly zero, not nearly
Cz = zeros(3); Sz = zeros(3); Cz(3, 1) = 1;                % C_20
gz = shLowLevel.shSynthesisGradient(Cz, Sz, GM, R, [-45 0 45], lon, ...
    Quantity = "none");
verifyEqual(testCase, gz.east, zeros(3, numel(lon)));
verifyTrue(testCase, any(abs(gz.north(:)) > 0));
end

function testGradientSurfaceQuantitiesHaveNoUp(testCase)
%TESTGRADIENTSURFACEQUANTITIESHAVENOUP an EWH one kilometre up is not a
%   smaller EWH, it is nothing. The up component is EMPTY for surface
%   quantities - empty fails at first use, a NaN field would be plotted.
L = 6; n1 = L + 1;
C = tril(ones(n1)) * 1e-10; S = zeros(n1);
GM = 3.986004415e14; R = 6378136.3;
kn = -0.3 * (1 - exp(-(0:L)'/3));
hn = -1.0 * ones(n1, 1);
lat = -60:30:60; lon = 0:90:270;
for q = ["none", "geoid", "ewh", "surface_density", "bottom_pressure", ...
         "deformation_up"]
    [g, info] = shLowLevel.shSynthesisGradient(C, S, GM, R, lat, lon, ...
        Quantity = q, kn = kn, hn = hn);
    verifyEmpty(testCase, g.up, sprintf('%s must have no up component', q));
    verifyFalse(testCase, info.hasUp);
    verifyEqual(testCase, size(g.north), [numel(lat), numel(lon)]);
end
for q = ["potential", "gravity_anomaly", "gravity_disturbance", ...
         "gravity_gradient_rr"]
    [g, info] = shLowLevel.shSynthesisGradient(C, S, GM, R, lat, lon, ...
        Quantity = q);
    verifyTrue(testCase, info.hasUp);
    verifyEqual(testCase, size(g.up), [numel(lat), numel(lon)]);
end
% Height and d/dr are the same fact, so they are refused together
verifyError(testCase, @() shLowLevel.shSynthesisGradient(C, S, GM, R, ...
    lat, lon, Quantity = "ewh", kn = kn, Height = 250e3), ...
    'shLowLevel:kernelFactors:heightInvalid');
% mass quantities still refuse to invent Love numbers
verifyError(testCase, @() shLowLevel.shSynthesisGradient(C, S, GM, R, ...
    lat, lon, Quantity = "ewh"), 'shLowLevel:kernelFactors:missingLoveNumbers');
% and the input gates hold
verifyError(testCase, @() shLowLevel.shSynthesisGradient(C, S, GM, R, ...
    lat, lon, Nmax = L + 3), 'shLowLevel:shSynthesisGradient:badInput');
verifyError(testCase, @() shLowLevel.shSynthesisGradient(C, S, GM, R, ...
    [0 10 20], [0 10], Mode = "points"), 'shLowLevel:shSynthesisGradient:badInput');
verifyError(testCase, @() shLowLevel.shSynthesisGradient(C, S, GM, R, ...
    [0 95], lon), 'MATLAB:validators:mustBeInRange');
end

function testGradientClassMethodMatchesCore(testCase)
%TESTGRADIENTCLASSMETHODMATCHESCORE the class method must be a pass-
%   through, not a second implementation - and its geodetic option must
%   convert the evaluation POINT, exactly as synthesis does.
rng(19);
L = 7; n1 = L + 1;
C = tril(randn(n1)) * 1e-10;
S = tril(randn(n1), -1) * 1e-10; S(:, 1) = 0;
g = shCoefficients(C, S);          % GM/R defaults are the toolbox's own
lat = [-40, 5, 52]; lon = [15, 200];
[a, ia] = g.gradient(lat, lon, Quantity = "potential");
b = shLowLevel.shSynthesisGradient(C, S, g.GM, g.R, lat, lon, ...
    Quantity = "potential");
for f = ["north", "east", "up"]
    verifyEqual(testCase, a.(f), b.(f));
end
verifyEqual(testCase, ia.quantity, "potential");
verifyTrue(testCase, ia.hasUp);
verifyEqual(testCase, ia.r, g.R);
% geodetic input is converted before evaluation
c = g.gradient(lat, lon, Quantity = "potential", LatType = "geodetic");
latGc = shLowLevel.geodetic2geocentric(lat);
d = shLowLevel.shSynthesisGradient(C, S, g.GM, g.R, latGc, lon, ...
    Quantity = "potential");
verifyEqual(testCase, c.north, d.north);
verifyGreaterThan(testCase, max(abs(c.north(:) - a.north(:))), 0);
end

% --------------------------------- geoMap bridge (v3.31.0)
function testToGridCarriesWhatTheNumbersAre(testCase)
%TESTTOGRIDCARRIESWHATTHENUMBERSARE the interface between this toolbox
%   and a cartographic one is numbers, which is right - but an array of
%   metres is an array of metres, and three things did not survive the
%   trip when it was measured end to end: the latitude convention, the
%   units and the product type. Each had to be retyped by a user who
%   could get it wrong with nothing noticing.
rng(77);
L = 6; n1 = L + 1;
C = tril(randn(n1)) * 1e-10;
S = tril(randn(n1), -1) * 1e-10; S(:, 1) = 0;
kn = -0.3 * (1 - exp(-(0:L)'/3));
g = shCoefficients(C, S, ProductType = "GSM", Name = "ITSG-Grace2018", ...
    Epoch = 2008.292);
lat = -80:20:80; lon = 0:45:315;

b = g.toGrid(lat, lon, Quantity = "ewh", kn = kn);
verifyEqual(testCase, size(b.Z), [numel(lat), numel(lon)]);
verifyEqual(testCase, b.lat, lat(:));            % column, as geo.grid wants
verifyEqual(testCase, b.lon, lon);               % row
verifyEqual(testCase, b.Units, "m");
verifyEqual(testCase, b.LatType, "geodetic");    % a map wants geodetic
verifyEqual(testCase, b.Quantity, "ewh");
verifyEqual(testCase, b.ProductType, "GSM");
verifyEqual(testCase, b.Name, "ITSG-Grace2018");
verifyEqual(testCase, b.Epoch, 2008.292);
verifyEqual(testCase, b.Nmax, L);
verifyTrue(testCase, contains(b.Source, "shAnalysis"));
verifyTrue(testCase, contains(b.Source, "GSM"));
verifyTrue(testCase, contains(b.Source, "geodetic"));

% the values are the synthesis, unchanged - the bridge adds no arithmetic
Z = g.synthesis(lat, lon, Quantity = "ewh", kn = kn, LatType = "geodetic");
verifyEqual(testCase, b.Z, Z);
verifyEqual(testCase, b.Zmin, min(Z(:)));
verifyEqual(testCase, b.Zmax, max(Z(:)));

% units follow the quantity, they are not a property of the bridge
bp = g.toGrid(lat, lon, Quantity = "potential");
verifyEqual(testCase, bp.Units, "m^2/s^2");
bs = g.toGrid(lat, lon, Quantity = "surface_density", kn = kn);
verifyEqual(testCase, bs.Units, "kg/m^2");
end

function testToGridFieldKindIsReadOffDegreeZero(testCase)
%TESTTOGRIDFIELDKINDISREADOFFDEGREEZERO a full field and a residual are
%   indistinguishable by units - measured: twelve GSM solutions meaned
%   and synthesized to EWH give 1.16e7 m, the static field expressed as
%   water, which a symmetric colour scale renders as one flat colour.
%   C(1,1) tells them apart as an IDENTITY, not a guess: exactly 1 for a
%   field carrying the total mass, 0 for a residual.
L = 5; n1 = L + 1;
kn = -0.3 * (1 - exp(-(0:L)'/3));
lat = -60:30:60; lon = 0:90:270;

Cres = zeros(n1); Cres(3, 1) = 1e-10;
gRes = shCoefficients(Cres, zeros(n1));
bRes = gRes.toGrid(lat, lon, Quantity = "geoid");
verifyEqual(testCase, bRes.FieldKind, "anomaly");
verifyEqual(testCase, bRes.C00, 0);

Cfull = Cres; Cfull(1, 1) = 1;
gFull = shCoefficients(Cfull, zeros(n1));
bFull = gFull.toGrid(lat, lon, Quantity = "geoid");
verifyEqual(testCase, bFull.FieldKind, "full");

Codd = Cres; Codd(1, 1) = 0.5;
gOdd = shCoefficients(Codd, zeros(n1));
bOdd = gOdd.toGrid(lat, lon, Quantity = "geoid");
verifyEqual(testCase, bOdd.FieldKind, "unknown", ...
    'in between is reported, not decided');

% a MASS quantity from a full field is the one case worth interrupting for
verifyWarning(testCase, @() gFull.toGrid(lat, lon, Quantity = "ewh", ...
    kn = kn), 'shLowLevel:gridHandover:fullFieldAsMass');
% ... and geoid from a full field is legitimate, so it must stay silent.
% The warning is deliberately NOT disabled here - a suppressed warning
% would make verifyWarningFree pass whatever the code did.
verifyWarningFree(testCase, @() gFull.toGrid(lat, lon, Quantity = "geoid"));
end

function testSeriesToGridStacksWithOneColourScale(testCase)
%TESTSERIESTOGRIDSTACKSWITHONECOLOURSCALE Zmin/Zmax are taken over the
%   WHOLE stack. An animation drawn with a per-frame scale shows the
%   scale changing and the signal not, which is how 240 honest maps
%   become a misleading film.
rng(1212);
L = 5; n1 = L + 1; T = 4;
Cs = zeros(n1, n1, T); Ss = zeros(n1, n1, T);
for k = 1:T
    Cs(:, :, k) = tril(randn(n1)) * 1e-10 * k;
    Ss(:, :, k) = tril(randn(n1), -1) * 1e-10;
end
ts = shSeries(Cs, Ss = Ss, Epochs = (2008:2008+T-1)', ProductType = "GSM");
kn = -0.3 * (1 - exp(-(0:L)'/3));
lat = -60:30:60; lon = 0:90:270;

b = ts.toGrid(lat, lon, Quantity = "ewh", kn = kn);
verifyEqual(testCase, size(b.Z), [numel(lat), numel(lon), T]);
verifyEqual(testCase, b.Epoch, (2008:2008+T-1)');
verifyEqual(testCase, numel(b.C00), T);
verifyEqual(testCase, b.FieldKind, "anomaly");
verifyEqual(testCase, b.Zmin, min(b.Z(:)));
verifyEqual(testCase, b.Zmax, max(b.Z(:)));

% every frame equals the single-epoch bridge - no second implementation
for k = 1:T
    bk = ts.at(k).toGrid(lat, lon, Quantity = "ewh", kn = kn);
    verifyEqual(testCase, b.Z(:, :, k), bk.Z);
end

% the budget is a stated error, not a silent thrash
verifyError(testCase, @() ts.toGrid(-89.9:0.02:89.9, 0:0.02:359.98, ...
    Quantity = "geoid", MaxMemGB = 0.01), 'shSeries:toGrid:tooLarge');
end

% ---------------------------------------------------------------- A10 (v3.34.1)
% Contract-level coverage of package functions and class methods the audit
% found unnamed in any test: shipped paths, error identifiers, and the
% graphics handles the plot helpers promise.

function testGravisDataFolderResolvesToTheShippedCopies(testCase)
p = shLowLevel.gravisDataFolder();
verifyClass(testCase, p, 'string');
verifyTrue(testCase, isfolder(p), 'the shipped data/gravis folder must exist');
% it is the folder the chains fall back to, so it must carry the basins
verifyTrue(testCase, isfile(fullfile(p, 'basins_AIS.json')) || ...
                     isfile(fullfile(p, 'basins_GIS.json')), ...
    'no GravIS basin polygon found in the shipped folder');
% derived from the package location, never hardcoded: it must sit next to
% the +shLowLevel folder this very function was loaded from
verifyEqual(testCase, exist(char(p), 'dir'), 7);
end

function testAntarcticaChainRefusesToAssumeAFrame(testCase)
% "kn REQUIRED, the empty default errors: no frame is assumed". The guard
% runs before any file is touched, so a nonexistent folder still reaches it.
verifyError(testCase, @() shLowLevel.antarcticaChain("no_such_folder_here"), ...
    'shLowLevel:gravisRegionChain:noKn');
end

function testShSpectralCrossoverNeedsAnErrorSpectrum(testCase)
spec.degree = (0:10)';
spec.degAmplitude = ones(11, 1);
% no errAmplitude field: shDegreeRMS was called without sigmaC/sigmaS
verifyError(testCase, @() shLowLevel.shSpectralCrossover(spec), ...
    'shLowLevel:shSpectralCrossover:missingField');
end

function testPlotBasinSeriesReturnsAxesForTheStandardFigure(testCase)
fig = figure('Visible', 'off');
cleanup = onCleanup(@() close(fig)); %#ok<NASGU>
rng(515);
t = (2003:1/12:2015)';
c = 100 * sin(2*pi*t) + 3 * randn(size(t));
s = 2 * ones(size(t));
h = shLowLevel.plotBasinSeries(t, c, s, Label = "test basin", Units = "Gt");
verifyTrue(testCase, isgraphics(h), 'plotBasinSeries must return a handle');
% sigma is documented as optional - [] means "no band", not an error
h2 = shLowLevel.plotBasinSeries(t, c, [], Trend = false);
verifyTrue(testCase, isgraphics(h2));
% and a gap wider than GapThreshold is hatched rather than interpolated
tGap = [t(1:60); t(90:end)];
cGap = [c(1:60); c(90:end)];
h3 = shLowLevel.plotBasinSeries(tGap, cGap, []);
verifyTrue(testCase, isgraphics(h3));
end

function testPlotCovarianceDrawsBothTypes(testCase)
fig = figure('Visible', 'off');
cleanup = onCleanup(@() close(fig)); %#ok<NASGU>
rng(516);
idx = shLowLevel.shIndex(6);
A = randn(idx.P);
M = A * A' + idx.P * eye(idx.P);        % symmetric positive definite
h = shLowLevel.plotCovariance(M, idx);
verifyTrue(testCase, isgraphics(h), 'plotCovariance must return a handle');
h2 = shLowLevel.plotCovariance(M, idx, Type = "covariance", BlockLines = false);
verifyTrue(testCase, isgraphics(h2));
verifyError(testCase, @() shLowLevel.plotCovariance(M, idx, Type = "nope"), ...
    'MATLAB:validators:mustBeMember');
end

function testCoefficientSpectrumAndTriangleReturnHandles(testCase)
fig = figure('Visible', 'off');
cleanup = onCleanup(@() close(fig)); %#ok<NASGU>
rng(517);
g = shCoefficients(tril(randn(13)) * 1e-9, tril(randn(13), -1) * 1e-9, ...
    Epoch = 2024.1);
verifyTrue(testCase, isgraphics(g.spectrum()));
verifyTrue(testCase, isgraphics(g.triangle()));
end

function testDispPrintsTheIdentifyingFacts(testCase)
rng(518);
g = shCoefficients(tril(randn(9)) * 1e-9, tril(randn(9), -1) * 1e-9, ...
    Epoch = 2024.1, Name = "unit test field");
out = evalc('disp(g)');
verifyTrue(testCase, contains(out, "shCoefficients"));
verifyTrue(testCase, contains(out, "unit test field"));
verifyTrue(testCase, contains(out, "nmax=8"));

n1 = 7;
T = 24;                    % climatology fits 6 parameters: it needs >= 6
Cs = zeros(n1, n1, T);  Ss = zeros(n1, n1, T);
for k = 1:T
    Cs(:, :, k) = tril(randn(n1));
    Ss(:, :, k) = tril(randn(n1), -1);
end
ts = shSeries(Cs, Ss = Ss, Epochs = 2015 + (0:T-1)'/12);
outTs = evalc('disp(ts)');
verifyTrue(testCase, contains(outTs, "shSeries"));
verifyTrue(testCase, contains(outTs, "T=24 epochs"));

clim = ts.climatology();
outC = evalc('disp(clim)');
verifyTrue(testCase, contains(outC, "shClimatology"));
end

function testCompareDelegatesToCompareSolutions(testCase)
rng(519);
n1 = 11;
C = tril(randn(n1)) * 1e-9;  S = tril(randn(n1), -1) * 1e-9;
gA = shCoefficients(C, S, Epoch = 2024.1);
gB = shCoefficients(C * 1.01, S * 1.01, Epoch = 2024.1);
lat = -80:20:80;  lon = 0:40:320;
rep = gA.compare(gB, LatDeg = lat, LonDeg = lon);
ref = shLowLevel.compareSolutions(gA, gB, LatDeg = lat, LonDeg = lon);
verifyEqual(testCase, rep.spatial.rmsd, ref.spatial.rmsd, 'RelTol', 1e-12);
verifyTrue(testCase, isfield(rep, 'spectral'));
verifyTrue(testCase, isfield(rep, 'spatial'));
% a field compared with itself has zero difference, whatever the grid
same = gA.compare(gA, LatDeg = lat, LonDeg = lon);
verifyEqual(testCase, same.spatial.rmsd, 0, 'AbsTol', 1e-18);

% shSeries.compare is a DIFFERENT delegate - shLowLevel.compareSeries -
% which prepends the object as the reference series.
% compareSeries needs >= 12 COMMON epochs (its own guard, line ~112) and
% fits trends and phase lags, so give it two full years rather than the
% bare minimum.
L = 6; T = 24;
Cs = zeros(L+1, L+1, T);  Ss = zeros(L+1, L+1, T);
for k = 1:T
    Cs(:, :, k) = tril(randn(L+1));
    Ss(:, :, k) = tril(randn(L+1), -1);
end
t = 2015 + (0:T-1)'/12;
tsA = shSeries(Cs, Ss = Ss, Epochs = t);
tsB = shSeries(Cs * 1.05, Ss = Ss * 1.05, Epochs = t);
idxS = shLowLevel.shIndex(L);
basis = zeros(idxS.P, 1);  basis(1) = 1;      % pick one coefficient
repTs = tsA.compare(tsB, Basin = basis, Idx = idxS, Names = ["A", "B"]);
verifyEqual(testCase, repTs.names, ["A", "B"]);
verifyEqual(testCase, size(repTs.y), [T 2]);
% column 1 is the reference - the object the method was called on
gA1 = tsA.at(1);
xA1 = shLowLevel.vecFromCS(gA1.C, gA1.S, idxS);
verifyEqual(testCase, repTs.y(1, 1), xA1(1), 'AbsTol', 1e-15);
% B is A scaled by 1.05 and the basin functional is linear, so column 2
% is that same multiple of column 1
verifyEqual(testCase, repTs.y(:, 2), 1.05 * repTs.y(:, 1), 'RelTol', 1e-12);
end

function testClimatologyFromCoefHonoursTheDocumentedRowLayout(testCase)
% COEF is (6+2K) x (2*Nc): rows are bias, trend, cosAnn, sinAnn, cosSemi,
% sinSemi, then the cos/sin pair of each extra period; columns 1:Nc are
% C(:) and Nc+1:2*Nc are S(:) of the flattened series. Each row is given a
% distinct constant here, so a row swapped in the mapping is visible.
n1 = 5;
Nc = n1^2;
ts = shSeries(zeros(n1, n1, 4), Ss = zeros(n1, n1, 4), ...
    Epochs = 2015 + (0:3)'/12);
coef = zeros(6, 2*Nc);
for r = 1:6
    coef(r, 1:Nc)     = r;            % the C half of row r
    coef(r, Nc+1:end) = -r;           % the S half of row r
end
clim = shClimatology.fromCoef(coef, 2016.0, ts);
verifyClass(testCase, clim, 'shClimatology');
verifyEqual(testCase, clim.t0, 2016.0);
verifyEqual(testCase, clim.biasC,    1 * ones(n1));
verifyEqual(testCase, clim.trendC,   2 * ones(n1));
verifyEqual(testCase, clim.cosAnnC,  3 * ones(n1));
verifyEqual(testCase, clim.sinAnnC,  4 * ones(n1));
verifyEqual(testCase, clim.cosSemiC, 5 * ones(n1));
verifyEqual(testCase, clim.sinSemiC, 6 * ones(n1));
verifyEqual(testCase, clim.biasS,   -1 * ones(n1));
verifyEqual(testCase, clim.sinSemiS, -6 * ones(n1));
% GM/R travel from the series, not from a hardcoded default
verifyEqual(testCase, clim.GM, ts.GM);
verifyEqual(testCase, clim.R, ts.R);

% K extra periods need exactly 6 + 2K rows - the assertion is documented
coefK = zeros(8, 2*Nc);
coefK(7, 1:Nc) = 7;                   % cos of the first extra period
coefK(8, 1:Nc) = 8;                   % sin of the first extra period
climK = shClimatology.fromCoef(coefK, 2016.0, ts, Periods = 1.5);
verifyEqual(testCase, climK.periods, 1.5);
verifyEqual(testCase, climK.extraCosC(:, :, 1), 7 * ones(n1));
verifyEqual(testCase, climK.extraSinC(:, :, 1), 8 * ones(n1));
verifyError(testCase, ...
    @() shClimatology.fromCoef(coef, 2016.0, ts, Periods = 1.5), ...
    'shClimatology:fromCoef:badInput');
end

% ---------------------------------------------------------------- WP1 (v4.0.0)
% The six v1-era functions now take arguments blocks with house-cased
% Name=value options. MATLAB matches Name-Value names case-insensitively,
% so the OLD lowercase spellings still reach the same option - that is
% measured, not assumed (tools/nv_casing_audit.py documents the probe).
% Only n0 -> Nmin is a real rename, and only the error identifiers are a
% breaking change. These tests pin both halves.

function testRenamedOptionsAreAcceptedInHouseCasing(testCase)
rng(4000);
L = 12;
C = tril(randn(L+1)) * 1e-9;  S = tril(randn(L+1), -1) * 1e-9;
GM = 3.986004415e14;  R = 6378136.3;
lat = -60:30:60;  lon = 0:60:300;

% shSynthesis: Quantity / Nmin / Nmax / Method
g1 = shLowLevel.shSynthesis(C, S, GM, R, lat, lon, Quantity = 'geoid', ...
    Nmin = 0, Nmax = L, Method = 'direct');
verifyEqual(testCase, size(g1), [numel(lat) numel(lon)]);
% case-insensitive matching means the pre-4.0.0 spelling still lands on
% the same option - the same numbers, not merely a working call
g1old = shLowLevel.shSynthesis(C, S, GM, R, lat, lon, quantity = 'geoid', ...
    nmin = 0, nmax = L, method = 'direct');
verifyEqual(testCase, g1old, g1);

% shDegreeRMS: R / Nmin / SigmaC / SigmaS
sC = abs(C) * 0.1;  sS = abs(S) * 0.1;
sd = shLowLevel.shDegreeRMS(C, S, R = R, Nmin = 2, SigmaC = sC, SigmaS = sS);
verifyTrue(testCase, isfield(sd, 'errAmplitude'));
verifyEqual(testCase, sd.R, R);
% Nmin zeroes the degrees below it, so degree 0 and 1 carry no variance
verifyEqual(testCase, sd.degVariance(1:2), [0; 0], 'AbsTol', 0);

% shDestripe: MinOrder / PolyOrder / WindowLength
[Cd, Sd] = shLowLevel.shDestripe(C, S, MinOrder = 8, PolyOrder = 3);
verifyEqual(testCase, Cd(:, 1:8), C(:, 1:8));
verifyEqual(testCase, Sd(:, 1:8), S(:, 1:8));

% shGaussianWeights: R stays R
w1 = shLowLevel.shGaussianWeights(L, 400);
w2 = shLowLevel.shGaussianWeights(L, 400, R = 6378.1363);
verifyEqual(testCase, w2, w1);

% shOrderRMS and shCoefficients.degreeRMS/crossover took N0; all three
% spectral entry points now spell the same concept Nmin
so = shLowLevel.shOrderRMS(C, S, Nmin = 2);
verifyTrue(testCase, isfield(so, 'ordVariance'));
end

function testRenamedOptionsMatchTheClassMethods(testCase)
% the class methods forward to the renamed options; a name that did not
% arrive would silently take the default, so compare the NUMBERS
rng(4001);
L = 10;
C = tril(randn(L+1)) * 1e-9;  S = tril(randn(L+1), -1) * 1e-9;
g = shCoefficients(C, S, SigmaC = abs(C)*0.1, SigmaS = abs(S)*0.1, ...
    Epoch = 2024.1);

sdClass = g.degreeRMS(Nmin = 2);
sdLow = shLowLevel.shDegreeRMS(C, S, R = g.R, Nmin = 2, ...
    SigmaC = g.sigmaC, SigmaS = g.sigmaS);
verifyEqual(testCase, sdClass.degVariance, sdLow.degVariance);
verifyEqual(testCase, sdClass.errAmplitude, sdLow.errAmplitude);

gd = g.destripe(MinOrder = 8, PolyOrder = 3);
[Cd, Sd] = shLowLevel.shDestripe(C, S, MinOrder = 8, PolyOrder = 3);
verifyEqual(testCase, gd.C, Cd);
verifyEqual(testCase, gd.S, Sd);
end

function testSynthesisPointsAutoPicksTheFasterPath(testCase)
%TESTSYNTHESISPOINTSAUTOPICKSTHEFASTERPATH v5.1.0: "auto" must DISPATCH,
%   not merely be accepted. The whole point of the option is that the
%   default is the faster summation for the calculation in hand, so the
%   rule itself is pinned: below ClenshawFrom "auto" IS "direct", at or
%   above it "auto" IS "clenshaw" - bitwise in both directions, because
%   auto only chooses, it does not compute.
%
%   This test deliberately pins the DISPATCH RULE and not the number: it
%   drives ClenshawFrom explicitly, so changing the default cannot
%   silently break it. That is exactly what it bought - the default moved
%   from 150 to 1 in v5.2.0, when benchPointsCrossover measured MATLAB
%   and found no crossover at all, and this test needed no edit.
%   testSynthesisPointsAutoIsClenshawByDefault pins the shipped number.
GM = 3.986004415e14; R = 6378136.3;
rng(33);
nmax = 12;
C = tril(randn(nmax+1)) * 1e-9; S = tril(randn(nmax+1), -1) * 1e-9;
n = 20;
la = linspace(-80, 80, n)'; lo = mod(11 * (1:n)', 360); rr = R + (1:n)' * 10;
% n = 20 points, threshold above it -> auto must be the direct path
aLo = shLowLevel.synthesisPoints(C, S, GM, R, la, lo, rr, ClenshawFrom = 50);
dir = shLowLevel.synthesisPoints(C, S, GM, R, la, lo, rr, Method = "direct");
verifyTrue(testCase, isequal(aLo, dir), ...
    'auto below ClenshawFrom must be exactly the direct path');
% same points, threshold at or below the count -> auto must be clenshaw
aHi = shLowLevel.synthesisPoints(C, S, GM, R, la, lo, rr, ClenshawFrom = n);
cle = shLowLevel.synthesisPoints(C, S, GM, R, la, lo, rr, Method = "clenshaw");
verifyTrue(testCase, isequal(aHi, cle), ...
    'auto at or above ClenshawFrom must be exactly the clenshaw path');
% and the two paths are genuinely different code, or the test above is
% vacuous - they agree numerically but must not be bit-identical here
verifyFalse(testCase, isequal(dir, cle), ...
    'direct and clenshaw returned identical bits: one path is not running');
% the option surface itself
verifyError(testCase, @() shLowLevel.synthesisPoints(C, S, GM, R, ...
    la, lo, rr, Method = "fft"), 'MATLAB:validators:mustBeMember');
verifyError(testCase, @() shLowLevel.synthesisPoints(C, S, GM, R, ...
    la, lo, rr, ClenshawFrom = 0), 'MATLAB:validators:mustBePositive');
end

function testSynthesisPointsAutoIsClenshawByDefault(testCase)
%TESTSYNTHESISPOINTSAUTOISCLENSHAWBYDEFAULT v5.3.0: the SHIPPED default.
%   testSynthesisPointsAutoPicksTheFasterPath pins the rule while driving
%   ClenshawFrom by hand; this pins the number the toolbox actually
%   ships, because that is the thing a user gets and the thing that
%   changed. ClenshawFrom = 1 means "auto" is "clenshaw" for ANY point
%   count, including a single point.
%
%   Why 1 and not 150: benchPointsCrossover timed both paths on the same
%   points and "clenshaw" won at every count measured (P = 1..2000 at
%   nmax 60 and 120, P = 1..200 at nmax 360). 150 was the numpy
%   prototype's crossover and does not hold in
%   MATLAB, where "direct" is bounded by legendreALF and "clenshaw" never
%   calls it. No clock is involved here - dispatch is checked bitwise.
GM = 3.986004415e14; R = 6378136.3;
rng(52);
nmax = 10;
C = tril(randn(nmax+1)) * 1e-9; S = tril(randn(nmax+1), -1) * 1e-9;
for n = [1, 2, 17, 400]
    la = linspace(-70, 70, n)';
    lo = mod(7 * (1:n)', 360);
    rr = R + (1:n)' * 25;
    auto = shLowLevel.synthesisPoints(C, S, GM, R, la, lo, rr);
    cle = shLowLevel.synthesisPoints(C, S, GM, R, la, lo, rr, ...
        Method = "clenshaw");
    verifyTrue(testCase, isequal(auto, cle), sprintf( ...
        'default auto must be the clenshaw path at P = %d', n));
end
% the default is 1, so nothing can fall below it: mustBePositive already
% forbids 0, which makes "auto is always clenshaw" a property of the
% shipped surface and not merely of the numbers chosen above
verifyError(testCase, @() shLowLevel.synthesisPoints(C, S, GM, R, ...
    la, lo, rr, ClenshawFrom = 0), 'MATLAB:validators:mustBePositive');
% and direct is still reachable - the fast default must not have retired
% the bitwise path
dir = shLowLevel.synthesisPoints(C, S, GM, R, la, lo, rr, ...
    Method = "direct");
verifyFalse(testCase, isequal(dir, cle), ...
    'direct and clenshaw returned identical bits: one path is not running');
% Deliberately NOT re-asserting how closely the two agree.
% testCorrectness/testSynthesisPointsMethodsAgree owns that property and
% bounds it the way the oracle defines it - max|clenshaw - direct| over
% max|direct|, across three degrees, three quantities, both Nmin values
% and near-pole latitudes. A per-element RelTol here is a DIFFERENT
% statistic: on a white-spectrum fixture the sum cancels to a near-zero
% value whose relative error is 6e-13 while the field-relative error is
% 6e-14, so such an assertion fails without anything being wrong. This
% test owns dispatch, which it checks bitwise.
end

function testRemoveGIASigmaContract(testCase)
%TESTREMOVEGIASIGMACONTRACT WP5 5c: the Sigma option's surface and its
%   one identifier. Sigma must match the GIA model in size - a mismatched
%   sigma field silently zero-padded would attach the wrong uncertainty
%   to the wrong degree, which is worse than refusing.
nmax = 3; n1 = nmax + 1; T = 4;
ep = 2008 + (0:T-1)'/12;
ts = shSeries(zeros(n1, n1, T), Ss = zeros(n1, n1, T), Epochs = ep);
gia = shCoefficients(tril(ones(n1)) * 1e-11, tril(ones(n1), -1) * 1e-11);
bad = shCoefficients(tril(ones(n1 + 2)) * 1e-12, ...
    tril(ones(n1 + 2), -1) * 1e-12);
verifyError(testCase, @() ts.removeGIA(gia, Sigma = bad), ...
    'shSeries:removeGIA:badSigma');
verifyError(testCase, @() ts.removeGIA(gia, Sigma = 42), ...
    'shSeries:removeGIA:badSigma');
% info is a documented struct: every field the help names must exist
sig = shCoefficients(tril(ones(n1)) * 4e-12, tril(ones(n1), -1) * 4e-12);
[~, info] = ts.removeGIA(gia, Sigma = sig);
for f = ["t0", "rateSigmaC", "rateSigmaS", "propagated", ...
        "sigmaWasEmpty", "correlated"]
    verifyTrue(testCase, isfield(info, f), ...
        sprintf('info lacks the documented field %s', f));
end
% an explicit Sigma OVERRIDES the model's own
gsig = shCoefficients(gia.C, gia.S, ...
    SigmaC = tril(ones(n1)) * 9e-12, SigmaS = tril(ones(n1), -1) * 9e-12);
[~, iOver] = ts.removeGIA(gsig, Sigma = sig);
verifyEqual(testCase, iOver.rateSigmaC, sig.C, 'AbsTol', 0);
[~, iOwn] = ts.removeGIA(gsig);
verifyEqual(testCase, iOwn.rateSigmaC, gsig.sigmaC, 'AbsTol', 0);
end

function testSynthesisOwnsItsOwnIdentifiers(testCase)
% shSynthesis raised bare shSynthesis:* until v4.0.0. badInput and badP
% had no test at all; badMethod is pinned above.
rng(4002);
L = 8;
C = tril(randn(L+1));  S = tril(randn(L+1), -1);
GM = 1;  R = 1;  lat = [-30 0 30];  lon = 0:90:270;
verifyError(testCase, ...
    @() shLowLevel.shSynthesis(C, S(:, 1:end-1), GM, R, lat, lon), ...
    'shLowLevel:shSynthesis:badInput');
verifyError(testCase, ...
    @() shLowLevel.shSynthesis(C, S, GM, R, lat, lon, Nmax = L + 5), ...
    'shLowLevel:shSynthesis:badInput');
% a P that does not match nmax/latVec is refused rather than used
verifyError(testCase, ...
    @() shLowLevel.shSynthesis(C, S, GM, R, lat, lon, P = zeros(2, 2, 1)), ...
    'shLowLevel:shSynthesis:badP');
end

function testLeakageDataDrivenIDs(testCase)
%TESTLEAKAGEDATADRIVENIDS WP5 5b: every identifier the function raises.
%   Seven guards, each pinned. tooFewEpochs and nanInput exist because
%   the phase and amplitude steps are regressions over the WHOLE series:
%   they cannot skip a gap, and below one annual cycle they fit noise.
%   Refusing is better than returning a confident number from four
%   months of data.
lat = linspace(-89, 89, 25);
lon = (0:25) * (360/26);
R = zeros(numel(lat), numel(lon)); R(10:14, 5:9) = 1;
good = repmat(R, 1, 1, 12) .* reshape(1:12, 1, 1, []) * 0.01;
verifyError(testCase, @() shLowLevel.leakageDataDriven(good(:,:,1:4), ...
    lat, lon, Mask = R), "shLowLevel:leakageDataDriven:tooFewEpochs");
bad = good; bad(3, 3, 2) = NaN;
verifyError(testCase, @() shLowLevel.leakageDataDriven(bad, lat, lon, ...
    Mask = R), "shLowLevel:leakageDataDriven:nanInput");
verifyError(testCase, @() shLowLevel.leakageDataDriven(good, lat, lon), ...
    "shLowLevel:leakageDataDriven:badMask");
verifyError(testCase, @() shLowLevel.leakageDataDriven(good, lat, lon, ...
    Mask = R(1:3, 1:3)), "shLowLevel:leakageDataDriven:badMask");
verifyError(testCase, @() shLowLevel.leakageDataDriven(good, lat, lon, ...
    Mask = zeros(size(R))), "shLowLevel:leakageDataDriven:emptyMask");
verifyError(testCase, @() shLowLevel.leakageDataDriven(good(1:3,:,:), ...
    lat, lon, Mask = R), "shLowLevel:leakageDataDriven:badSize");
verifyError(testCase, @() shLowLevel.leakageDataDriven(good, lat, lon, ...
    Mask = R, Filter = "wavelet"), ...
    "shLowLevel:leakageDataDriven:badFilter");
verifyError(testCase, @() shLowLevel.leakageDataDriven(good, lat, lon, ...
    Mask = R, Filter = "gaussnope"), ...
    "shLowLevel:leakageDataDriven:badFilter");
% the grid must be sliced too, or badSize fires first and the badNmax
% guard is never reached - which is exactly what happened here
verifyError(testCase, @() shLowLevel.leakageDataDriven(good(1:3,:,:), ...
    lat(1:3), lon, Mask = R(1:3,:), Nmax = 1), ...
    "shLowLevel:leakageDataDriven:badNmax");
end

function testLeakageDataDrivenInfoFields(testCase)
%TESTLEAKAGEDATADRIVENINFOFIELDS Every field the help documents must
%   exist and have the documented shape. help_audit checks the two
%   agree statically; this checks the code actually builds them.
lat = linspace(-89, 89, 33);
lon = (0:33) * (360/34);
[LO, LA] = meshgrid(lon, lat);
R = double(sind(LA)*sind(0) + cosd(LA)*cosd(0).*cosd(LO - 40) >= cosd(20));
T = 24; t = (0:T-1)'/12;
g = zeros(numel(lat), numel(lon), T);
for k = 1:T
    g(:,:,k) = (0.1*sin(2*pi*t(k)) + 0.02*t(k)) * R;
end
[fHat, info] = shLowLevel.leakageDataDriven(g, lat, lon, Mask = R);
verifyEqual(testCase, size(fHat), [T 1]);
for f = ["filtered", "leakage", "deviation", "leakageOnce", ...
        "leakageTwice", "deviationOnce", "deviationTwice"]
    verifyTrue(testCase, isfield(info, f), ...
        sprintf("info lacks the documented field %s", f));
    verifyEqual(testCase, size(info.(f)), [T 1], ...
        sprintf("info.%s must be T x 1", f));
end
for f = ["phaseDeg", "leakageRatio", "deviationRatio", ...
        "areaFraction", "nmax", "filter"]
    verifyTrue(testCase, isfield(info, f), ...
        sprintf("info lacks the documented field %s", f));
    verifyEqual(testCase, numel(info.(f)), 1, ...
        sprintf("info.%s must be scalar", f));
end
verifyClass(testCase, info.filter, "string");
verifyEqual(testCase, info.filter, "gauss300");   % the documented default
verifyGreaterThan(testCase, info.areaFraction, 0);
verifyLessThan(testCase, info.areaFraction, 1);
end

function [C, S, GM, R] = wp3Coefficients()
%WP3COEFFICIENTS The deterministic set tools/dev/validate_ellipsoid.py pins
%   against, rebuilt without an RNG so both languages hold the same numbers.
nmax = 40;
[n, m] = ndgrid(0:nmax, 0:nmax);
C = 1e-9 * cos(0.7*n + 1.3*m) ./ (1 + n);
S = 1e-9 * sin(0.4*n + 0.9*m) ./ (1 + n);
C(m > n) = 0;
S(m > n) = 0;
S(:, 1) = 0;
C(1:2, :) = 0;
S(1:2, :) = 0;
GM = 3.986004415e14;
R = 6378136.3;
end

function testEllipsoidWithZeroFlatteningIsTheSphere(testCase)
%TESTELLIPSOIDWITHZEROFLATTENINGISTHESPHERE WP3 metamorphic: the ellipsoid
%   path must DEGENERATE to the sphere, not approximate it. With f = 0 and
%   a = R, r(phi) is R exactly, (R/r)^p_n is 1 exactly and x*1 is exact, so
%   at Height 0 the two paths agree bitwise - synthesis, banded synthesis
%   and gradient alike. With Height > 0 the product is associated
%   differently ((f q) C against q (f C)), so there it is round-off.
[C, S, GM, R] = wp3Coefficients();
lat = -90:6:90;
lon = 0:10:350;
for q = ["potential", "gravity_disturbance", "gravity_anomaly", "gravity_gradient_rr"]
    s = shLowLevel.shSynthesis(C, S, GM, R, lat, lon, Quantity = q);
    e = shLowLevel.shSynthesis(C, S, GM, R, lat, lon, Quantity = q, ...
        Surface = "ellipsoid", Flattening = 0, SemiMajorAxis = R);
    verifyTrue(testCase, isequal(s, e), ...
        sprintf('%s: ellipsoid(f=0, a=R) is not the sphere', q));
end
sb = shLowLevel.shSynthesis(C, S, GM, R, lat, lon, Quantity = "potential", ...
    MaxMemGB = 1e-5);
eb = shLowLevel.shSynthesis(C, S, GM, R, lat, lon, Quantity = "potential", ...
    Surface = "ellipsoid", Flattening = 0, SemiMajorAxis = R, MaxMemGB = 1e-5);
verifyTrue(testCase, isequal(sb, eb), 'banded: ellipsoid(f=0, a=R) is not the sphere');
gs = shLowLevel.shSynthesisGradient(C, S, GM, R, lat, lon, Quantity = "potential");
ge = shLowLevel.shSynthesisGradient(C, S, GM, R, lat, lon, Quantity = "potential", ...
    Surface = "ellipsoid", Flattening = 0, SemiMajorAxis = R);
% isequaln: east is NaN at the poles on both paths, and must stay so
verifyTrue(testCase, isequaln(gs, ge), 'gradient: ellipsoid(f=0, a=R) is not the sphere');
sh = shLowLevel.shSynthesis(C, S, GM, R, lat, lon, ...
    Quantity = "gravity_disturbance", Height = 2500);
eh = shLowLevel.shSynthesis(C, S, GM, R, lat, lon, ...
    Quantity = "gravity_disturbance", Surface = "ellipsoid", ...
    Flattening = 0, SemiMajorAxis = R, Height = 2500);
verifyLessThan(testCase, max(abs(sh(:) - eh(:))) / max(abs(sh(:))), 1e-14);
end

function testEllipsoidSurfaceIDs(testCase)
%TESTELLIPSOIDSURFACEIDS The refusal is scoped and it says why. A quantity
%   with no radial law cannot be moved off the sphere; the geoid's message
%   names gamma(phi), because "half a correction" is the reason it is
%   refused and a bare identifier would not carry that.
[C, S, GM, R] = wp3Coefficients();
kn = zeros(41, 1);
verifyError(testCase, @() shLowLevel.shSynthesis(C, S, GM, R, 0:10:20, 0:10:20, ...
    Quantity = "geoid", Surface = "ellipsoid"), 'shLowLevel:shSynthesis:noRadialLaw');
verifyError(testCase, @() shLowLevel.shSynthesis(C, S, GM, R, 0:10:20, 0:10:20, ...
    Quantity = "ewh", kn = kn, Surface = "ellipsoid"), ...
    'shLowLevel:shSynthesis:noRadialLaw');
verifyError(testCase, @() shLowLevel.shSynthesisGradient(C, S, GM, R, 0:10:20, ...
    0:10:20, Quantity = "geoid", Surface = "ellipsoid"), ...
    'shLowLevel:shSynthesisGradient:noRadialLaw');
verifyError(testCase, @() shLowLevel.shSynthesis(C, S, GM, R, 0, 0, ...
    Surface = "oblate"), 'MATLAB:validators:mustBeMember');
verifyError(testCase, @() shLowLevel.shSynthesis(C, S, GM, R, 0, 0, ...
    Quantity = "potential", Surface = "ellipsoid", Height = -5), ...
    'MATLAB:validators:mustBeNonnegative');
try
    shLowLevel.shSynthesis(C, S, GM, R, 0, 0, Quantity = "geoid", Surface = "ellipsoid");
    verifyFail(testCase, 'the geoid on the ellipsoid did not error');
catch err
    verifySubstring(testCase, err.message, 'gamma(phi)');
end
% the surface quantities still work on the sphere - the refusal is scoped
verifyTrue(testCase, all(isfinite(shLowLevel.shSynthesis(C, S, GM, R, ...
    0:10:20, 0:10:20, Quantity = "geoid")), 'all'));
end

function testEllipsoidGradientInfo(testCase)
%TESTELLIPSOIDGRADIENTINFO info.r is one radius on the sphere and one per
%   latitude (grid) or per point (points) on the ellipsoid; info.surface
%   says which, so the number travels with its meaning.
[C, S, GM, R] = wp3Coefficients();
lat = [-60 0 30 75];
lon = 0:45:315;
[~, is] = shLowLevel.shSynthesisGradient(C, S, GM, R, lat, lon, Quantity = "potential");
[~, ie] = shLowLevel.shSynthesisGradient(C, S, GM, R, lat, lon, ...
    Quantity = "potential", Surface = "ellipsoid", Height = 300);
verifyEqual(testCase, is.surface, "sphere");
verifyEqual(testCase, ie.surface, "ellipsoid");
verifyEqual(testCase, is.r, R);
verifyEqual(testCase, ie.r, shLowLevel.ellipsoidRadius(lat) + 300);
[~, ip] = shLowLevel.shSynthesisGradient(C, S, GM, R, lat, [5 6 7 8], ...
    Quantity = "potential", Surface = "ellipsoid", Mode = "points");
verifyEqual(testCase, ip.r, shLowLevel.ellipsoidRadius(lat));
end

function testClassSurfaceForwarding(testCase)
%TESTCLASSSURFACEFORWARDING g.synthesis and g.gradient forward Surface,
%   SemiMajorAxis and the one Flattening the class already had - the same
%   ellipsoid for the latitude conversion and for the evaluation surface.
%   UseCache = false so both sides compute the Legendre functions the same
%   way and the comparison can be bitwise.
[C, S] = wp3Coefficients();
g = shCoefficients(C, S);
lat = -80:20:80;
lon = 0:40:320;
a = g.synthesis(lat, lon, Quantity = "gravity_disturbance", ...
    Surface = "ellipsoid", UseCache = false);
b = shLowLevel.shSynthesis(g.C, g.S, g.GM, g.R, lat, lon, ...
    Quantity = 'gravity_disturbance', Surface = "ellipsoid");
verifyTrue(testCase, isequal(a, b), 'g.synthesis did not forward Surface');
a2 = g.synthesis(lat, lon, Quantity = "gravity_disturbance", ...
    Surface = "ellipsoid", Flattening = 1/300, SemiMajorAxis = 6378000, ...
    UseCache = false);
b2 = shLowLevel.shSynthesis(g.C, g.S, g.GM, g.R, lat, lon, ...
    Quantity = 'gravity_disturbance', Surface = "ellipsoid", ...
    Flattening = 1/300, SemiMajorAxis = 6378000);
verifyTrue(testCase, isequal(a2, b2), 'g.synthesis did not forward the ellipsoid');
dg = g.gradient(lat, lon, Quantity = "potential", Surface = "ellipsoid");
dl = shLowLevel.shSynthesisGradient(g.C, g.S, g.GM, g.R, lat, lon, ...
    Quantity = "potential", Surface = "ellipsoid");
verifyTrue(testCase, isequaln(dg, dl), 'g.gradient did not forward Surface');
end

% ------------------------------------------- WP7: lanes behind the class
% Every WP7 method is a thin delegate. These pin each one BITWISE against
% the call it makes, with options and with none. The no-option call is the
% one that holds a method which declares no defaults to the lane's own.

function ts = wp7Series(nmax, T, seed)
%WP7SERIES Deterministic series for the WP7 delegation tests: random
%   coefficients whose degree amplitude falls as 1/(n+1)^2, formal sigmas
%   and monthly epochs. Raw-stack form, so the series carries no names.
rng(seed);
n1 = nmax + 1;
dec = 1 ./ ((0:nmax)' + 1) .^ 2;
Cs = zeros(n1, n1, T);
Ss = zeros(n1, n1, T);
for k = 1:T
    Cs(:, :, k) = tril(randn(n1) .* dec) * 1e-9;
    s = tril(randn(n1) .* dec) * 1e-9;
    s(:, 1) = 0;
    Ss(:, :, k) = s;
end
sig = repmat(tril(1e-11 * ones(n1)), 1, 1, T);
ts = shSeries(Cs, Ss = Ss, Epochs = 2005 + ((1:T)' - 0.5) / 12, ...
    SigmaCs = sig, SigmaSs = sig);
end

function testSeriesKalmanIsKalmanChain(testCase)
%TESTSERIESKALMANISKALMANCHAIN ts.kalman is shLowLevel.kalmanChain with the
%   series as the observations - bitwise, with options and with the lane's
%   defaults.
tsObs = wp7Series(3, 36, 71);
tsModel = wp7Series(3, 36, 72);
[a, ra] = tsObs.kalman(ModelSeries = tsModel, Order = 1, ...
    Climatology = false, Shrink = 1e-6);
[b, rb] = shLowLevel.kalmanChain(tsObs, ModelSeries = tsModel, Order = 1, ...
    Climatology = false, Shrink = 1e-6);
verifyTrue(testCase, isequaln(a, b), 'ts.kalman differs from kalmanChain');
verifyTrue(testCase, isequaln(ra, rb), 'the report differs from kalmanChain''s');
[a0, ra0] = tsObs.kalman(ModelSeries = tsModel);
[b0, rb0] = shLowLevel.kalmanChain(tsObs, ModelSeries = tsModel);
verifyTrue(testCase, isequaln(a0, b0) && isequaln(ra0, rb0), ...
    'with the lane defaults, ts.kalman differs from kalmanChain');
end

function testFetchRetryOptionsReachHttpFetch(testCase)
%TESTFETCHRETRYOPTIONSREACHHTTPFETCH A36: fetchTN forwards MaxTries and
%   BaseDelay to shLowLevel.httpFetch, and forwards nothing it was not
%   given - so an omitted MaxTries is httpFetch's own default (4). Offline:
%   BaseDelay = 0.01 keeps the backoff below 0.1 s, but a refused
%   connection to 127.0.0.1:1 is NOT instant on Windows - A8 measured 18 s
%   for the six attempts here, about 3 s each (v5.23.0, PR #130).
dst = tempname;
c = onCleanup(@() rmdir(dst, 's')); %#ok<NASGU>
[~, i2] = shLowLevel.fetchTN(Dest = dst, BaseURL = "https://127.0.0.1:1", ...
    Providers = "CSR", TN14 = false, Timeout = 2, Quiet = true, ...
    MaxTries = 2, BaseDelay = 0.01);
verifyEqual(testCase, numel(i2.failed), 1);
verifyTrue(testCase, contains(i2.failed, "after 2 attempts"), i2.failed);
[~, i4] = shLowLevel.fetchTN(Dest = dst, BaseURL = "https://127.0.0.1:1", ...
    Providers = "CSR", TN14 = false, Timeout = 2, Quiet = true, BaseDelay = 0.01);
verifyTrue(testCase, contains(i4.failed, "after 4 attempts"), i4.failed);
verifyError(testCase, @() shLowLevel.fetchTN(Dest = dst, MaxTries = 0), ...
    'MATLAB:validators:mustBePositive');
end

function testFitClimatologyRoutes(testCase)
%TESTCLIMATOLOGYFITROUTES A34: ts.kalman and ts.regionalKalman forward
%   FitClimatology to their lanes bitwise, and both lanes refuse a value
%   outside "observations" | "filtered".
tsObs = wp7Series(3, 36, 74);
tsModel = wp7Series(3, 120, 75);
[a, ra] = tsObs.kalman(ModelSeries = tsModel, FitClimatology = "filtered");
[b, rb] = shLowLevel.kalmanChain(tsObs, ModelSeries = tsModel, FitClimatology = "filtered");
verifyTrue(testCase, isequaln(a, b) && isequaln(ra, rb), ...
    'ts.kalman does not forward FitClimatology');
B = tsObs.regionalBasis(@(la, lo) double(la > 50));
[a1, o1] = tsObs.regionalKalman(B, ModelSeries = tsModel, FitClimatology = "filtered");
[a2, o2] = shLowLevel.regionalKalman(tsObs, B, ModelSeries = tsModel, ...
    FitClimatology = "filtered");
verifyTrue(testCase, isequaln(a1, a2) && isequaln(o1, o2), ...
    'ts.regionalKalman does not forward FitClimatology');
verifyError(testCase, @() shLowLevel.kalmanChain(tsObs, ModelSeries = tsModel, ...
    FitClimatology = "model"), 'MATLAB:validators:mustBeMember');
verifyError(testCase, @() shLowLevel.regionalKalman(tsObs, B, ModelSeries = tsModel, ...
    FitClimatology = "model"), 'MATLAB:validators:mustBeMember');
end

function testKalmanSecondSeriesRouteAndGuards(testCase)
%TESTKALMANSECONDSERIESROUTEANDGUARDS WP9 9a: ts.kalman forwards the
%   second-series options to shLowLevel.kalmanChain bitwise; without
%   SecondSeries the report carries no second-series fields; and each
%   guard of the second group raises its own identifier.
tsObs = wp7Series(3, 36, 76);
tsSec = wp7Series(3, 36, 77);
tsModel = wp7Series(3, 120, 78);
[a, ra] = tsObs.kalman(ModelSeries = tsModel, SecondSeries = tsSec, ...
    SecondScale = false, MinOverlap = 12, SecondTolerance = 0.02);
[b, rb] = shLowLevel.kalmanChain(tsObs, ModelSeries = tsModel, ...
    SecondSeries = tsSec, SecondScale = false, MinOverlap = 12, ...
    SecondTolerance = 0.02);
verifyTrue(testCase, isequaln(a, b) && isequaln(ra, rb), ...
    'ts.kalman does not forward the second-series options');
verifyTrue(testCase, all(ra.observedBy == "both"));
[~, r0] = shLowLevel.kalmanChain(tsObs, ModelSeries = tsModel);
verifyFalse(testCase, isfield(r0, 'second') || isfield(r0, 'observedBy'), ...
    'a chain without SecondSeries reports second-series fields');
verifyError(testCase, @() shLowLevel.kalmanChain(string(tempname), ...
    ModelSeries = tsModel, SecondSeries = tsSec), ...
    'shLowLevel:kalmanChain:secondInNeqMode');
verifyError(testCase, @() shLowLevel.kalmanChain(tsObs, ModelSeries = tsModel, ...
    SecondSeries = wp7Series(4, 36, 77)), 'shLowLevel:kalmanChain:secondMismatch');
bad = tsSec.Cs;
bad(3, 1, 5) = NaN;
tsNaN = shSeries(bad, Ss = tsSec.Ss, Epochs = tsSec.epochs);
verifyError(testCase, @() shLowLevel.kalmanChain(tsObs, ModelSeries = tsModel, ...
    SecondSeries = tsNaN), 'shLowLevel:kalmanChain:secondNotFinite');
verifyError(testCase, @() shLowLevel.kalmanChain(tsObs, ModelSeries = tsModel, ...
    SecondSeries = tsSec, MinOverlap = 37), 'shLowLevel:kalmanChain:noOverlap');
verifyError(testCase, @() shLowLevel.kalmanChain(tsObs, ModelSeries = tsModel, ...
    SecondSeries = tsSec, SecondNoise = [1 2 3]), ...
    'shLowLevel:kalmanChain:badSecondNoise');
verifyError(testCase, @() shLowLevel.kalmanChain(tsObs, ModelSeries = tsModel, ...
    SecondSeries = tsSec, SecondNoise = "formal"), ...
    'shLowLevel:kalmanChain:badSecondNoise');
[~, rg] = shLowLevel.kalmanChain(tsObs, ModelSeries = tsModel, ...
    SecondSeries = tsSec, SecondNoise = 1e-11 * ones(4, 1));
verifyEqual(testCase, rg.second.sigma, [0; 0; 1e-11; 1e-11], ...
    'a given SecondNoise is used as given, 0 where the index holds no degree');
end

function testSeriesEofIsEofAnalysis(testCase)
%TESTSERIESEOFISEOFANALYSIS ts.eof is shLowLevel.eofAnalysis(ts), bitwise.
ts = wp7Series(6, 20, 73);
[m1, p1, v1, i1] = ts.eof(NModes = 3, Center = false);
[m2, p2, v2, i2] = shLowLevel.eofAnalysis(ts, NModes = 3, Center = false);
verifyTrue(testCase, isequaln({m1, p1, v1, i1}, {m2, p2, v2, i2}), ...
    'ts.eof differs from eofAnalysis');
[m1, p1, v1, i1] = ts.eof();
[m2, p2, v2, i2] = shLowLevel.eofAnalysis(ts);
verifyTrue(testCase, isequaln({m1, p1, v1, i1}, {m2, p2, v2, i2}), ...
    'with the lane defaults, ts.eof differs from eofAnalysis');
end

function testSeriesWriteIsCoefficientsWrite(testCase)
%TESTSERIESWRITEISCOEFFICIENTSWRITE ts.write writes, per epoch, the file
%   g.write writes for ts.at(k) - identical except the "# written by" line,
%   which carries the minute of writing - leaves no sidecar by default, and
%   a folder written with epoch-bearing names reads back as the series.
names = ["GSM-2_2005001-2005031_WP7.gfc"; "GSM-2_2005032-2005059_WP7.gfc"; ...
    "GSM-2_2005060-2005090_WP7.gfc"];
ep = zeros(3, 1);
for k = 1:3
    meta = shLowLevel.parseGraceFilename(names(k));
    ep(k) = meta.epoch;
end
src = wp7Series(5, 3, 74);
ts = shSeries(src.Cs, Ss = src.Ss, Epochs = ep, SigmaCs = src.sigmaCs, ...
    SigmaSs = src.sigmaSs, ProductType = "GSM");
d1 = tempname; mkdir(d1); c1 = onCleanup(@() rmIfFolder(d1));
d2 = tempname; mkdir(d2); c2 = onCleanup(@() rmIfFolder(d2));
ts.write(d1, FileNames = names);
keep = @(x) x(~startsWith(x, "# written by"));
for k = 1:3
    g = ts.at(k);
    g.write(fullfile(d2, names(k)), Sidecar = false);
    a = splitlines(string(fileread(fullfile(d1, names(k)))));
    b = splitlines(string(fileread(fullfile(d2, names(k)))));
    verifyEqual(testCase, keep(a), keep(b), ...
        sprintf('file %d is not what g.write writes', k));
end
verifyEmpty(testCase, dir(fullfile(d1, '*.json')), ...
    'ts.write must not leave provenance sidecars by default');
back = shSeries.fromFolder(d1);
verifyEqual(testCase, back.epochs, ts.epochs, ...
    'the epochs did not come back from the file names');
% %22.14e keeps 15 significant digits, so the round trip is bounded by that
% print precision - the same bound as testWriteReadRoundtrip
verifyEqual(testCase, back.Cs, ts.Cs, 'RelTol', 1e-13, 'AbsTol', 1e-18);
verifyEqual(testCase, back.Ss, ts.Ss, 'RelTol', 1e-13, 'AbsTol', 1e-18);
end

function testSeriesWriteGuardsItsNames(testCase)
%TESTSERIESWRITEGUARDSITSNAMES ts.write refuses a missing folder and names
%   that are not one-per-epoch, and warns when a name would lose its epoch.
ts = wp7Series(3, 2, 75);
d = tempname; mkdir(d); c = onCleanup(@() rmIfFolder(d));
verifyError(testCase, @() ts.write(fullfile(d, 'nope')), ...
    'shSeries:write:noFolder');
verifyError(testCase, @() ts.write(d), 'shSeries:write:badFileNames');
verifyError(testCase, @() ts.write(d, FileNames = ["a.gfc"; "a.gfc"]), ...
    'shSeries:write:badFileNames');
verifyWarning(testCase, @() ts.write(d, FileNames = ["a.gfc"; "b.gfc"]), ...
    'shSeries:write:epochNotInName');
end

function testSeriesGradientStacksEpochs(testCase)
%TESTSERIESGRADIENTSTACKSEPOCHS page k of ts.gradient is g.gradient of
%   epoch k, on a grid and at points; INFO is the first epoch's.
ts = wp7Series(8, 3, 76);
lat = -60:30:60;
lon = 0:45:315;
[dq, info] = ts.gradient(lat, lon, Quantity = "potential");
[dp, ~] = ts.gradient([10 20 30], [5 15 25], Quantity = "geoid", ...
    Mode = "points");
for k = 1:3
    g = ts.at(k);
    [d, ik] = g.gradient(lat, lon, Quantity = "potential");
    verifyTrue(testCase, isequal(dq.north(:, :, k), d.north) && ...
        isequal(dq.east(:, :, k), d.east) && isequal(dq.up(:, :, k), d.up), ...
        sprintf('page %d is not g.gradient of epoch %d', k, k));
    if k == 1
        verifyTrue(testCase, isequaln(info, ik), 'INFO is not the first epoch''s');
    end
    e = g.gradient([10 20 30], [5 15 25], Quantity = "geoid", Mode = "points");
    verifyTrue(testCase, isequal(dp.north(:, :, k), e.north) && ...
        isequal(dp.east(:, :, k), e.east), ...
        sprintf('points: page %d is not epoch %d', k, k));
end
verifyEqual(testCase, size(dq.north), [numel(lat), numel(lon), 3]);
verifyEqual(testCase, size(dp.north), [3, 1, 3]);
verifyEmpty(testCase, dp.up, 'a surface quantity has no up component');
end

function testSeriesLeakageCorrectIsTheLane(testCase)
%TESTSERIESLEAKAGECORRECTISTHELANE ts.leakageCorrect is g.synthesis plus
%   shLowLevel.leakageCorrect per epoch, with the series' GM and R.
ws = warning('off', 'shLowLevel:leakageCorrect:unregularised');
cw = onCleanup(@() warning(ws));
ts = wp7Series(10, 2, 77);
lat = -85:10:85;
lon = 0:10:350;
kn = -0.3 * (1 - exp(-(0:10)' / 3));
[LO, LA] = meshgrid(lon, lat);
mask = cosd(LA) .* cosd(LO - 40) >= cosd(30);
[m, info] = ts.leakageCorrect(lat, lon, Filter = "gauss500", kn = kn, ...
    Mask = mask, MaxIter = 5, Quiet = true);
for k = 1:2
    g = ts.at(k);
    Z = g.synthesis(lat, lon, Quantity = "ewh", kn = kn);
    [mk, ik] = shLowLevel.leakageCorrect(Z, lat, lon, Filter = "gauss500", ...
        Mask = mask, MaxIter = 5, Quiet = true, GM = ts.GM, R = ts.R);
    verifyTrue(testCase, isequal(m(:, :, k), mk) && isequaln(info(k), ik), ...
        sprintf('epoch %d is not the lane''s answer', k));
end
verifyEqual(testCase, size(m), [numel(lat), numel(lon), 2]);
end

function testSeriesLeakageDataDrivenIsTheLane(testCase)
%TESTSERIESLEAKAGEDATADRIVENISTHELANE ts.leakageDataDriven is the stack of
%   g.synthesis fields through shLowLevel.leakageDataDriven, with the
%   series' GM and R.
ts = wp7Series(8, 12, 78);
lat = linspace(-87, 87, 30);
lon = (0:35) * 10;
kn = -0.3 * (1 - exp(-(0:8)' / 3));
[LO, LA] = meshgrid(lon, lat);
basin = double(cosd(LA) .* cosd(LO - 40) >= cosd(25));
[f, info] = ts.leakageDataDriven(lat, lon, Mask = basin, ...
    Filter = "gauss300", kn = kn);
stack = zeros(numel(lat), numel(lon), 12);
for k = 1:12
    g = ts.at(k);
    stack(:, :, k) = g.synthesis(lat, lon, Quantity = "ewh", kn = kn);
end
[f2, info2] = shLowLevel.leakageDataDriven(stack, lat, lon, Mask = basin, ...
    Filter = "gauss300", GM = ts.GM, R = ts.R);
verifyTrue(testCase, isequal(f, f2) && isequaln(info, info2), ...
    'ts.leakageDataDriven is not the lane''s answer');
end

function testLeakageMethodsRequireAFilter(testCase)
%TESTLEAKAGEMETHODSREQUIREAFILTER a series cannot know which filter its data
%   saw, so both leakage methods refuse to guess - unlike the functions,
%   which default to gauss300.
ts = wp7Series(4, 12, 79);
lat = -80:20:80;
lon = 0:30:330;
verifyError(testCase, @() ts.leakageCorrect(lat, lon, kn = zeros(5, 1)), ...
    'shSeries:leakageCorrect:noFilter');
verifyError(testCase, @() ts.leakageDataDriven(lat, lon, kn = zeros(5, 1), ...
    Mask = ones(numel(lat), numel(lon))), ...
    'shSeries:leakageDataDriven:noFilter');
end

function testCoefficientsBasinAverageIsTheSeriesMethod(testCase)
%TESTCOEFFICIENTSBASINAVERAGEISTHESERIESMETHOD g.basinAverage is the
%   one-epoch shSeries.basinAverage, bitwise, and inherits its size check.
ts = wp7Series(4, 1, 80);
g = ts.at(1);
idx = shLowLevel.shIndex(4);
rng(81);
B = randn(idx.P, 3);
verifyTrue(testCase, isequal(g.basinAverage(B), ts.basinAverage(B)), ...
    'g.basinAverage is not the one-epoch shSeries.basinAverage');
verifyEqual(testCase, size(g.basinAverage(B)), [3 1]);
verifyError(testCase, @() g.basinAverage(B(1:end-1, :)), ...
    'shSeries:basinAverage:badBasis');
end

function testCoefficientsErrorMapIsTheLane(testCase)
%TESTCOEFFICIENTSERRORMAPISTHELANE g.errorMap is shLowLevel.errorMap with
%   the object's GM and R: from its formal sigmas as a diagonal covariance
%   by default, from a full covariance unchanged when one is given.
ts = wp7Series(3, 1, 82);
g = ts.at(1);
lat = [-40 10 55];
lon = [30 200];
idx = shLowLevel.shIndex(3);
M0 = diag(shLowLevel.vecFromCS(g.sigmaC, g.sigmaS, idx) .^ 2);
verifyTrue(testCase, isequal(g.errorMap(lat, lon), ...
    shLowLevel.errorMap(M0, idx, lat, lon, GM = g.GM, R = g.R)), ...
    'the formal-sigma map is not the lane''s');
idx2 = shLowLevel.shIndex(3, Nmin = 2);
rng(83);
A = randn(idx2.P) * 1e-10;
M = A * A';
a = g.errorMap(lat, lon, Covariance = M, Index = idx2, ...
    Quantity = "gravity_anomaly");
b = shLowLevel.errorMap(M, idx2, lat, lon, Quantity = "gravity_anomaly", ...
    GM = g.GM, R = g.R);
verifyTrue(testCase, isequal(a, b), 'a full covariance is not passed through');
bare = shCoefficients(g.C, g.S);
verifyError(testCase, @() bare.errorMap(lat, lon), ...
    'shCoefficients:errorMap:noCovariance');
end

function testToGridForwardsSurface(testCase)
%TESTTOGRIDFORWARDSSURFACE g.toGrid and ts.toGrid forward Surface and
%   SemiMajorAxis to g.synthesis, so their grids are the ones g.synthesis
%   returns. g.map forwards the same two options to g.toGrid; it needs
%   geoMap to run, so it is covered by the forwarding, not here.
ts = wp7Series(6, 2, 84);
g = ts.at(2);
lat = -80:20:80;
lon = 0:40:320;
b = g.toGrid(lat, lon, Quantity = "gravity_disturbance", ...
    Surface = "ellipsoid", SemiMajorAxis = 6378000, LatType = "geocentric");
z = g.synthesis(lat, lon, Quantity = "gravity_disturbance", ...
    Surface = "ellipsoid", SemiMajorAxis = 6378000);
verifyTrue(testCase, isequal(b.Z, z), 'g.toGrid did not forward Surface');
s = g.toGrid(lat, lon, Quantity = "gravity_disturbance", LatType = "geocentric");
verifyFalse(testCase, isequal(s.Z, b.Z), 'Surface = "ellipsoid" changed nothing');
bs = ts.toGrid(lat, lon, Quantity = "gravity_disturbance", ...
    Surface = "ellipsoid", SemiMajorAxis = 6378000, LatType = "geocentric");
verifyTrue(testCase, isequal(bs.Z(:, :, 2), z), 'ts.toGrid did not forward Surface');
end

% ------------------------------------------ A25: one filter-spec parser
function testFilterSpecReadsTheVocabulary(testCase)
%TESTFILTERSPECREADSTHEVOCABULARY each accepted form, and what it means.
s = shLowLevel.filterSpec("none");
verifyEqual(testCase, [s.kind, s.name], ["none", "none"]);
s = shLowLevel.filterSpec("gauss300");
verifyEqual(testCase, s.kind, "gauss");
verifyEqual(testCase, s.radiusKm, 300);
s = shLowLevel.filterSpec('gauss250');
verifyEqual(testCase, [s.kind, s.name], ["gauss", "gauss250"]);
verifyEqual(testCase, s.radiusKm, 250);
s = shLowLevel.filterSpec("DDK3");
verifyEqual(testCase, s.kind, "ddk");
verifyEqual(testCase, s.ddk, 3);
verifyTrue(testCase, isnan(s.radiusKm));
W = struct('blocks', {{}}, 'nmax', 10, 'name', "myW");
s = shLowLevel.filterSpec(W);
verifyEqual(testCase, [s.kind, s.name], ["W", "myW"]);
verifyTrue(testCase, isequal(s.W, W), 'a W struct must pass through unchanged');
s = shLowLevel.filterSpec(rmfield(W, 'name'));
verifyEqual(testCase, s.name, "custom W");
end

function testFilterSpecRefusesMalformedSpecs(testCase)
%TESTFILTERSPECREFUSESMALFORMEDSPECS the spellings that one lane or another
%   used to accept silently - a radius that is not a number, zero or
%   negative, a DDK outside 1..8, a file name that happens to start with
%   "DDK" - and the ones every lane refused. With two outputs the reason
%   comes back; with one it is an error.
bad = {"gauss", "gauss0", "gauss-5", "gaussX", "DDK0", "DDK9", "DDK3.mat", ...
    "ddk3", "Gauss300", "", "bogus", 3, {"none"}, ["none", "gauss300"]};
for i = 1:numel(bad)
    [s, msg] = shLowLevel.filterSpec(bad{i});
    verifyEqual(testCase, s.kind, "", sprintf('spec %d was accepted', i));
    verifyNotEqual(testCase, msg, "", sprintf('spec %d carries no reason', i));
    verifyError(testCase, @() shLowLevel.filterSpec(bad{i}), ...
        'shLowLevel:filterSpec:badSpec');
end
end

function testFilterSpecAllowedSubset(testCase)
%TESTFILTERSPECALLOWEDSUBSET a caller admits a subset - the GravIS grid
%   chains take only "none" and "gauss".
[s, msg] = shLowLevel.filterSpec("DDK3", Allowed = ["none", "gauss"]);
verifyEqual(testCase, s.kind, "");
verifyTrue(testCase, contains(msg, "ddk"), 'the reason must name the kind');
s = shLowLevel.filterSpec("gauss445", Allowed = ["none", "gauss"]);
verifyEqual(testCase, s.radiusKm, 445);
verifyError(testCase, @() shLowLevel.filterSpec(struct('name', "w"), ...
    Allowed = ["none", "gauss"]), 'shLowLevel:filterSpec:badSpec');
end

function testLanesRefuseAMalformedFilterFirst(testCase)
%TESTLANESREFUSEAMALFORMEDFILTERFIRST every lane refuses a malformed spec
%   under its OWN identifier, and the chains do it before they touch their
%   data: the folders below do not exist, so any other order would fail
%   with a different identifier. oceanChain and obpChain used to read any
%   text as a Gaussian radius, and the grid chains never checked one.
nf = string(tempname);
verifyError(testCase, @() shLowLevel.oceanChain(nf, Filter = "DDK3"), ...
    'shLowLevel:oceanChain:badFilter');
verifyError(testCase, @() shLowLevel.obpChain(nf, Filter = "gauss-1"), ...
    'shLowLevel:obpChain:badFilter');
verifyError(testCase, @() shLowLevel.greenlandChain(nf, nf, Filter = "gaussX"), ...
    'shLowLevel:gravisRegionChain:badFilter');
verifyError(testCase, @() shLowLevel.antarcticaChain(nf, nf, Filter = "DDK3"), ...
    'shLowLevel:gravisRegionChain:badFilter');
verifyError(testCase, @() shLowLevel.twsChain(nf, nf, Filter = "DDK9"), ...
    'shLowLevel:twsChain:badFilter');
verifyError(testCase, @() shLowLevel.standardChain(nf, Filter = "gauss0"), ...
    'shLowLevel:standardChain:badFilter');
lat = -80:20:80;
lon = 0:30:330;
verifyError(testCase, @() shLowLevel.gridScaling(ones(numel(lat), ...
    numel(lon), 2), lat, lon, Filter = "gauss"), 'shLowLevel:gridScaling:badFilter');
end

% ------------------------------------------- WP7 backlog: three more routes
function testCoefficientsSynthesisPointsIsTheLane(testCase)
%TESTCOEFFICIENTSSYNTHESISPOINTSISTHELANE g.synthesisPoints is
%   shLowLevel.synthesisPoints with the object's coefficients, GM and R.
ts = wp7Series(12, 1, 85);
g = ts.at(1);
lat = [-60; -10; 35; 80];
lon = [10; 100; 200; 300];
r = shLowLevel.ellipsoidRadius(lat) + [0; 1e3; 450e3; 5e3];
for q = ["potential", "disturbance", "anomaly"]
    a = g.synthesisPoints(lat, lon, r, Quantity = q, Nmin = 0);
    b = shLowLevel.synthesisPoints(g.C, g.S, g.GM, g.R, lat, lon, r, ...
        Quantity = q, Nmin = 0);
    verifyTrue(testCase, isequal(a, b), "g.synthesisPoints differs for " + q);
end
verifyTrue(testCase, isequal(g.synthesisPoints(lat, lon, r), ...
    shLowLevel.synthesisPoints(g.C, g.S, g.GM, g.R, lat, lon, r)), ...
    'with the lane defaults, g.synthesisPoints differs');
end

function testCoefficientsGradientTensorIsTheLane(testCase)
%TESTCOEFFICIENTSGRADIENTTENSORISTHELANE g.gradientTensor is
%   shLowLevel.shSynthesisGradientTensor with the object's C, S, GM and R.
ts = wp7Series(10, 1, 88);
g = ts.at(1);
lat = -60:30:60;
lon = 0:60:300;
[a, ia] = g.gradientTensor(lat, lon, Height = 3e5, Nmin = 3);
[b, ib] = shLowLevel.shSynthesisGradientTensor(g.C, g.S, g.GM, g.R, ...
    lat, lon, Height = 3e5, Nmin = 3);
verifyTrue(testCase, isequaln(a, b) && isequaln(ia, ib), ...
    'g.gradientTensor differs from the lane');
[a0, ia0] = g.gradientTensor(lat, lon);
[b0, ib0] = shLowLevel.shSynthesisGradientTensor(g.C, g.S, g.GM, g.R, lat, lon);
verifyTrue(testCase, isequaln(a0, b0) && isequaln(ia0, ib0), ...
    'with the lane defaults, g.gradientTensor differs');
end

function testCoefficientsVdkApplyIsTheLane(testCase)
%TESTCOEFFICIENTSVDKAPPLYISTHELANE the degrees inside Index are
%   shLowLevel.vdkApply's answer, the ones outside pass through, the
%   sigmas become NaN as for applyDDK, and the default Index is
%   shIndex(nmax, Nmin = 2).
ts = wp7Series(6, 1, 86);
g = ts.at(1);
idx = shLowLevel.shIndex(6, Nmin = 2);
rng(87);
A = randn(idx.P);
N = (A * A' + idx.P * eye(idx.P)) * 1e20;
sigM = [1e-10, -1.5];
[out, info] = g.vdkApply(N, sigM, Alpha = 0.5);
[xf, info2] = shLowLevel.vdkApply(shLowLevel.vecFromCS(g.C, g.S, idx), ...
    N, idx.n, sigM, Alpha = 0.5);
[cf, sf] = shLowLevel.csFromVec(xf, idx);
verifyTrue(testCase, isequal(out.C(3:end, :), cf(3:end, :)) && ...
    isequal(out.S(3:end, :), sf(3:end, :)), 'the filtered degrees are not the lane''s');
verifyTrue(testCase, isequal(out.C(1:2, :), g.C(1:2, :)) && ...
    isequal(out.S(1:2, :), g.S(1:2, :)), 'degrees outside Index must pass through');
verifyTrue(testCase, isequaln(info, info2), 'INFO is not the lane''s');
verifyTrue(testCase, all(isnan(out.sigmaC(:))) && all(isnan(out.sigmaS(:))), ...
    'the sigmas must become NaN, as for applyDDK');
verifyTrue(testCase, isequaln(g.vdkApply(N, sigM, Alpha = 0.5), ...
    g.vdkApply(N, sigM, Index = idx, Alpha = 0.5)), ...
    'the default Index is not shIndex(nmax, Nmin = 2)');
verifyError(testCase, @() g.vdkApply(N(1:end-1, 1:end-1), sigM), ...
    'shLowLevel:vdkApply:badSize');
end

% ------------------------------------------------- A28: the mask is required
function testOceanChainsRefuseAMissingMask(testCase)
%TESTOCEANCHAINSREFUSEAMISSINGMASK both ocean chains document OceanMask as
%   REQUIRED and defaulted it to [] without checking; oceanChain then failed
%   with MATLAB:badsubscript in its trend fit (A28). Both now refuse before
%   any data is read - the folder below does not exist.
nf = string(tempname);
kn = zeros(91, 1);
verifyError(testCase, @() shLowLevel.oceanChain(nf, kn = kn), ...
    'shLowLevel:oceanChain:noOcean');
verifyError(testCase, @() shLowLevel.obpChain(nf, kn = kn, GADFolder = nf), ...
    'shLowLevel:obpChain:noOcean');
end

% ------------------------------------------ WP5 5e: readGrid and analysis' Fill
function testReadGridContract(testCase)
%TESTREADGRIDCONTRACT every refusal of readGrid, each on a file built to
%   provoke it and nothing else.
verifyError(testCase, @() shLowLevel.readGrid([tempname, '.nc']), ...
    'shLowLevel:readGrid:fileNotFound');
d = tempname;
mkdir(d);
c = onCleanup(@() rmIfFolder(d));
nf = @(n) fullfile(d, n + ".nc");
% no coordinates at all
f = nf("nocoord");
nccreate(f, 'q', 'Dimensions', {'n', 3});
verifyError(testCase, @() shLowLevel.readGrid(f), 'shLowLevel:readGrid:noCoordinates');
% a grid holding two fields, a time axis in months, a calendar without leap years
f = nf("two");
wgrid(f, 'days since 2002-01-01', "");
nccreate(f, 'b', 'Dimensions', {'lat', 3, 'lon', 4});
verifyError(testCase, @() shLowLevel.readGrid(f), 'shLowLevel:readGrid:whichVar');
verifyError(testCase, @() shLowLevel.readGrid(f, Var = "nope"), 'shLowLevel:readGrid:noVar');
f = nf("months");
wgrid(f, 'months since 2002-01', "");
verifyError(testCase, @() shLowLevel.readGrid(f), 'shLowLevel:readGrid:badTimeUnits');
f = nf("noleap");
wgrid(f, 'days since 2002-01-01', "noleap");
verifyError(testCase, @() shLowLevel.readGrid(f), 'shLowLevel:readGrid:badCalendar');
% coordinates, but nothing on them
f = nf("nodata");
wcoords(f);
nccreate(f, 'q', 'Dimensions', {'n', 3});
verifyError(testCase, @() shLowLevel.readGrid(f), 'shLowLevel:readGrid:noData');
% a third axis without a coordinate variable, and a fourth axis
f = nf("band");
wcoords(f);
nccreate(f, 'a', 'Dimensions', {'lat', 3, 'lon', 4, 'band', 2});
verifyError(testCase, @() shLowLevel.readGrid(f), 'shLowLevel:readGrid:noTimeUnits');
f = nf("fourd");
wcoords(f);
nccreate(f, 'a', 'Dimensions', {'lat', 3, 'lon', 4, 'band', 2, 'time', 1});
verifyError(testCase, @() shLowLevel.readGrid(f), 'shLowLevel:readGrid:badDims');
end

function wcoords(f)
%WCOORDS lat (3) and lon (4) coordinates for the readGrid contract files.
nccreate(f, 'lat', 'Dimensions', {'lat', 3});
ncwrite(f, 'lat', [-30; 0; 30]);
ncwriteatt(f, 'lat', 'units', 'degrees_north');
nccreate(f, 'lon', 'Dimensions', {'lon', 4});
ncwrite(f, 'lon', [0; 90; 180; 270]);
ncwriteatt(f, 'lon', 'units', 'degrees_east');
end

function wgrid(f, timeUnits, calendar)
%WGRID a (lat, lon, time) field 'a' with the given time units and calendar.
wcoords(f);
nccreate(f, 'time', 'Dimensions', {'time', 2});
ncwrite(f, 'time', [0; 1]);
ncwriteatt(f, 'time', 'units', timeUnits);
if strlength(calendar) > 0
    ncwriteatt(f, 'time', 'calendar', char(calendar));
end
nccreate(f, 'a', 'Dimensions', {'lat', 3, 'lon', 4, 'time', 2});
end

function testAnalysisRefusesNaNUntilToldWhatTheyMean(testCase)
%TESTANALYSISREFUSESNANUNTILTOLDWHATTHEYMEAN a grid with NaN used to reach
%   every coefficient without an error. analysis now refuses it until Fill
%   says what the gaps mean - and with Fill it is exactly the analysis of
%   the filled grid, while Fill changes nothing on a grid without NaN.
lat = -85:10:85;
lon = 0:10:350;
[LO, LA] = meshgrid(lon, lat);
G = sind(LA) .* cosd(LO) + 0.1;
Gn = G;
Gn(LA > 60 & LO < 90) = NaN;
verifyError(testCase, @() shCoefficients.analysis(Gn, lat, lon, 8), ...
    'shCoefficients:analysis:nanInGrid');
a = shCoefficients.analysis(Gn, lat, lon, 8, Fill = 0);
Gz = Gn;
Gz(isnan(Gz)) = 0;
b = shCoefficients.analysis(Gz, lat, lon, 8);
verifyTrue(testCase, isequal(a.C, b.C) && isequal(a.S, b.S), ...
    'Fill = 0 is not the analysis of the zero-filled grid');
p = shCoefficients.analysis(G, lat, lon, 8, Fill = 5);
q = shCoefficients.analysis(G, lat, lon, 8);
verifyTrue(testCase, isequal(p.C, q.C) && isequal(p.S, q.S), ...
    'Fill changed a grid that holds no NaN');
end

% ------------------------------------------------ WP5: the method of scale
function testLeakageDataDrivenMethodContract(testCase)
%TESTLEAKAGEDATADRIVENMETHODCONTRACT the method of deviation stays the
%   default, bit for bit; the method used is reported; an unknown method is
%   refused; and ts.leakageDataDriven forwards Method to the lane.
lat = linspace(-89, 89, 33);
lon = (0:33) * (360/34);
[LO, LA] = meshgrid(lon, lat);
mask = double(cosd(LA) .* cosd(LO - 40) >= cosd(20));
T = 24;
t = (0:T-1)' / 12;
g = zeros(numel(lat), numel(lon), T);
for k = 1:T
    g(:, :, k) = (0.1 * sin(2*pi*t(k)) + 0.02 * t(k)) * mask + ...
        0.03 * cos(2*pi*t(k) + 1) * (1 - mask) .* cosd(LA);
end
[a, ia] = shLowLevel.leakageDataDriven(g, lat, lon, Mask = mask);
[b, ib] = shLowLevel.leakageDataDriven(g, lat, lon, Mask = mask, ...
    Method = "deviation");
verifyTrue(testCase, isequal(a, b) && isequaln(ia, ib), ...
    'the default is not the method of deviation');
verifyEqual(testCase, ia.method, "deviation");
verifyError(testCase, @() shLowLevel.leakageDataDriven(g, lat, lon, ...
    Mask = mask, Method = "median"), 'MATLAB:validators:mustBeMember');
ts = wp7Series(8, 12, 89);
kn = -0.3 * (1 - exp(-(0:8)' / 3));
lat2 = linspace(-87, 87, 30);
lon2 = (0:35) * 10;
[LO2, LA2] = meshgrid(lon2, lat2);
basin = double(cosd(LA2) .* cosd(LO2 - 40) >= cosd(25));
[f1, i1] = ts.leakageDataDriven(lat2, lon2, Mask = basin, ...
    Filter = "gauss300", kn = kn, Method = "scale");
stack = zeros(numel(lat2), numel(lon2), 12);
for k = 1:12
    gk = ts.at(k);
    stack(:, :, k) = gk.synthesis(lat2, lon2, Quantity = "ewh", kn = kn);
end
[f2, i2] = shLowLevel.leakageDataDriven(stack, lat2, lon2, Mask = basin, ...
    Filter = "gauss300", Method = "scale", GM = ts.GM, R = ts.R);
verifyTrue(testCase, isequal(f1, f2) && isequaln(i1, i2), ...
    'ts.leakageDataDriven did not forward Method');
verifyEqual(testCase, i1.method, "scale");
end

% ------------------------------------------------ WP5 5a: Earth rotation
function testRotationExcitationContract(testCase)
%TESTROTATIONEXCITATIONCONTRACT the Earth's constants and the Love numbers
%   are required and checked, sizes and gaps are refused, and ts.excitation
%   is the lane on the series' C21 and S21, bitwise - with the axial term
%   only when a TN-14 table gives C20.
E = struct('M', 6.0e24, 'R', 6.4e6, 'C', 8.0e37, 'A', 7.97e37);
kn = [0; 0.027; -0.301];
c = [1; 2; 3] * 1e-10;
verifyError(testCase, @() shLowLevel.rotationExcitation(c, c, kn = kn, ...
    Earth = 42), 'shLowLevel:rotationExcitation:noEarth');
verifyError(testCase, @() shLowLevel.rotationExcitation(c, c, kn = kn, ...
    Earth = "IERS1996"), 'shLowLevel:rotationExcitation:badEarth');
verifyError(testCase, @() shLowLevel.rotationExcitation(c, c, kn = kn, ...
    Earth = rmfield(E, 'A')), 'shLowLevel:rotationExcitation:noEarth');
bad = E;
bad.A = E.C;
verifyError(testCase, @() shLowLevel.rotationExcitation(c, c, kn = kn, ...
    Earth = bad), 'shLowLevel:rotationExcitation:badEarth');
bad = E;
bad.M = -1;
verifyError(testCase, @() shLowLevel.rotationExcitation(c, c, kn = kn, ...
    Earth = bad), 'shLowLevel:rotationExcitation:badEarth');
verifyError(testCase, @() shLowLevel.rotationExcitation(c, c, Earth = E), ...
    'shLowLevel:rotationExcitation:missingLoveNumbers');
verifyError(testCase, @() shLowLevel.rotationExcitation(c, c, Earth = E, ...
    kn = [0; 0]), 'shLowLevel:rotationExcitation:knTooShort');
verifyError(testCase, @() shLowLevel.rotationExcitation(c, c(1:2), ...
    Earth = E, kn = kn), 'shLowLevel:rotationExcitation:badSize');
verifyError(testCase, @() shLowLevel.rotationExcitation(c, c, ...
    C20 = c(1:2), Earth = E, kn = kn), 'shLowLevel:rotationExcitation:badSize');
verifyError(testCase, @() shLowLevel.rotationExcitation([c; NaN], ...
    [c; 0], Earth = E, kn = kn), 'shLowLevel:rotationExcitation:nanInput');
verifyError(testCase, @() shLowLevel.rotationExcitation(c, c, Earth = E, ...
    kn = kn, Reference = "median"), 'MATLAB:validators:mustBeMember');

% the class method: the lane on the series' C21 and S21, no axial term
ts = wp7Series(4, 12, 91);
[tbl, info] = ts.excitation(Earth = E, kn = kn);
[pol, i2] = shLowLevel.rotationExcitation(squeeze(ts.Cs(3, 2, :)), ...
    squeeze(ts.Ss(3, 2, :)), Earth = E, kn = kn);
verifyTrue(testCase, isequal(tbl.chi1, pol.chi1) && ...
    isequal(tbl.chi2, pol.chi2) && isequaln(info, i2), ...
    'ts.excitation does not return the lane result');
verifyEqual(testCase, tbl.t, ts.epochs);
verifyFalse(testCase, ismember('chi3', tbl.Properties.VariableNames), ...
    'the axial term must be refused without a TN-14 C20');

% with a TN-14 table the axial term comes from the table C20
tn = struct('epoch', ts.epochs, ...
    'C20', -4.8416e-4 + 1e-10 * sin(ts.epochs), ...
    'sigmaC20', 1e-12 * ones(12, 1), 'C30', NaN(12, 1), ...
    'sigmaC30', NaN(12, 1));
[tbl2, info2] = ts.excitation(Earth = E, kn = kn, TN14 = tn, ...
    Reference = "none");
[ax, i3] = shLowLevel.rotationExcitation(squeeze(ts.Cs(3, 2, :)), ...
    squeeze(ts.Ss(3, 2, :)), C20 = tn.C20, Earth = E, kn = kn, ...
    Reference = "none");
verifyTrue(testCase, isequal(tbl2.chi3, ax.chi3) && ...
    isequal(tbl2.dLOD, ax.dLOD) && isequal(tbl2.chi1, ax.chi1) && ...
    isequaln(info2, i3), 'the axial term does not come from the TN-14 C20');
verifyEqual(testCase, tbl2.Properties.VariableUnits, ...
    {'yr', 'mas', 'mas', '1', 'ms'});
end

% ------------------------------------------------ WP5 5d: the gap series
function testBridgeGapsContract(testCase)
%TESTBRIDGEGAPSCONTRACT the refusals of shLowLevel.bridgeGaps, and
%   ts.bridgeGaps is the lane, bitwise, with options and with the lane's
%   default smoothing.
[ref, br] = bridgeCaseContract();
verifyError(testCase, @() shLowLevel.bridgeGaps(ref, br, MinOverlap = 7), ...
    'shLowLevel:bridgeGaps:noOverlap');
brGM = shSeries(br.Cs, Ss = br.Ss, Epochs = br.epochs, GM = 3.9860044e14);
verifyError(testCase, @() shLowLevel.bridgeGaps(ref, brGM, MinOverlap = 6), ...
    'shLowLevel:bridgeGaps:constantsMismatch');
bad = br.Cs;
bad(2, 1, 3) = NaN;
brNaN = shSeries(bad, Ss = br.Ss, Epochs = br.epochs);
verifyError(testCase, @() shLowLevel.bridgeGaps(ref, brNaN, MinOverlap = 6), ...
    'shLowLevel:bridgeGaps:nanInput');
[a, ia] = ref.bridgeGaps(br, RadiusKm = 0, MinOverlap = 6);
[b, ib] = shLowLevel.bridgeGaps(ref, br, RadiusKm = 0, MinOverlap = 6);
verifyTrue(testCase, isequaln(a.Cs, b.Cs) && isequaln(a.sigmaCs, b.sigmaCs) ...
    && isequal(a.names, b.names) && isequaln(ia, ib), ...
    'ts.bridgeGaps is not the lane, with options');
[a, ia] = ref.bridgeGaps(br, MinOverlap = 6);
[b, ib] = shLowLevel.bridgeGaps(ref, br, MinOverlap = 6);
verifyTrue(testCase, isequaln(a.Cs, b.Cs) && isequaln(ia, ib), ...
    'ts.bridgeGaps is not the lane, with the default smoothing');
verifyEqual(testCase, ia.radiusKm, 750);
end

function [ref, br] = bridgeCaseContract()
%BRIDGECASECONTRACT eight monthly fields at nmax 4; the reference lacks
%   months 4 and 7, the bridge has them all.
rng(95);
Cs = zeros(5, 5, 8);
Ss = Cs;
for t = 1:8
    Cs(:, :, t) = tril(randn(5)) * 1e-10;
    s = tril(randn(5)) * 1e-10;
    s(:, 1) = 0;
    Ss(:, :, t) = s;
end
ep = 2010 + ((1:8)' - 0.5) / 12;
keep = [1 2 3 5 6 8];
ref = shSeries(Cs(:, :, keep), Ss = Ss(:, :, keep), Epochs = ep(keep));
br = shSeries(0.9 * Cs + 1e-11 * tril(ones(5)), Ss = 0.9 * Ss, Epochs = ep);
end

% ------------------------------------------------ A30: NaN in the analysis
function testNaNNeverReachesAnAnalysis(testCase)
%TESTNANNEVERREACHESANANALYSIS A30. One NaN in a grid reaches every
%   coefficient of shAnalysisGrid, so the lane refuses it, in both of its
%   layouts; and the two lanes that fed it NaN refuse under their own
%   identifiers - leakageCorrect without a Mask (it reported 'diverged'),
%   gridScaling with a NaN model (it returned no finite k, silently).
%   leakageCorrect's tolerance of NaN outside both regions with a Mask
%   stays pinned in testLeakageCorrectRejectsNaNInsideMask.
lat = linspace(-89, 89, 33);
lon = (0:33) * (360 / 34);
[LO, LA] = meshgrid(lon, lat);
disc = cosd(LA) .* cosd(LO - 40) >= cosd(20);
field = 0.1 * disc + 0.02 * cosd(LA) .* sind(2 * LO);
bad = field;
bad(LA < -60) = NaN;
verifyError(testCase, @() shLowLevel.shAnalysisGrid(bad, lat, lon, 16), ...
    'shLowLevel:shAnalysisGrid:nanInGrid');
verifyError(testCase, @() shLowLevel.shAnalysisGrid(bad(:), LA(:), LO(:), 4, ...
    Method = "ls"), 'shLowLevel:shAnalysisGrid:nanInGrid');
res = cosd(LA) .* cosd(LO - 40) >= cosd(45);
verifyError(testCase, @() shLowLevel.leakageCorrect(bad, lat, lon, ...
    ResidualRegion = res, MaxIter = 5, NoiseLevel = 1e-3, Quiet = true), ...
    'shLowLevel:leakageCorrect:nanInput');
model = repmat(field, 1, 1, 12);
model(repmat(LA < -60, 1, 1, 12)) = NaN;
verifyError(testCase, @() shLowLevel.gridScaling(model, lat, lon, Quiet = true), ...
    'shLowLevel:gridScaling:nanInput');
end

% ------------------------------------------------ the class-surface backlog
function testCoefficientsBacklogRoutesAreTheirLanes(testCase)
%TESTCOEFFICIENTSBACKLOGROUTESARETHEIRLANES g.poleTideConvert and
%   g.slepianProject are their lanes, bitwise, with options and without.
ts = wp7Series(12, 2, 101);
g = ts.at(1);
a = g.poleTideConvert();
b = shLowLevel.poleTideConvert(g);
verifyTrue(testCase, isequal(a.C, b.C) && isequal(a.S, b.S), ...
    'g.poleTideConvert is not the lane with its defaults');
a = g.poleTideConvert(From = "IERS2018", To = "IERS2010", Mode = "solid");
b = shLowLevel.poleTideConvert(g, From = "IERS2018", To = "IERS2010", ...
    Mode = "solid");
verifyTrue(testCase, isequal(a.C, b.C) && isequal(a.S, b.S), ...
    'g.poleTideConvert is not the lane with options');
idx = shLowLevel.shIndex(12, Nmin = 0);
G = shLowLevel.slepianBasis(idx, @(la, lo) double(la > 60));
[a1, r1] = g.slepianProject(G, idx);
[a2, r2] = shLowLevel.slepianProject(g.C, g.S, G, idx);
verifyTrue(testCase, isequal(a1, a2) && isequal(r1, r2), ...
    'g.slepianProject is not the lane');
end

function testSeriesBacklogRoutesAreTheirLanes(testCase)
%TESTSERIESBACKLOGROUTESARETHEIRLANES ts.poleTideConvert is the lane's
%   raw form at every epoch, with names, sigmas and history kept;
%   ts.estimateDegree1, ts.combineCenters and ts.slepianProject are their
%   lanes, bitwise.
ts = wp7Series(12, 3, 102);
out = ts.poleTideConvert(From = "IERS2010", To = "IERS2018");
for k = 1:3
    [C2, S2] = shLowLevel.poleTideConvert(ts.Cs(:, :, k), ts.Ss(:, :, k), ...
        ts.epochs(k), From = "IERS2010", To = "IERS2018");
    verifyTrue(testCase, isequal(out.Cs(:, :, k), C2) && ...
        isequal(out.Ss(:, :, k), S2), sprintf('epoch %d is not the lane', k));
end
verifyEqual(testCase, out.sigmaCs, ts.sigmaCs);
verifyEqual(testCase, numel(out.history), numel(ts.history) + 1);
% estimateDegree1, on the grid and mask of
% testEstimateDegree1RecoversAKnownGeocentre
lat = -89:4:89;
lon = 0:4:356;
[LO, LA] = meshgrid(lon, lat);
kn = [0; 0.021; -0.3054; -0.1960; zeros(17, 1)];
ocean = ~(((LA > 10) & (LA < 70) & (LO > 250) & (LO < 350)) | ...
          ((LA > -40) & (LA < 30) & (LO > 10) & (LO < 60)));
t1 = wp7Series(12, 2, 103);
[d1, i1] = t1.estimateDegree1(ocean, kn = kn, LatDeg = lat, LonDeg = lon, ...
    Nmax = 12);
[d2, i2] = shLowLevel.estimateDegree1(t1, ocean, kn = kn, LatDeg = lat, ...
    LonDeg = lon, Nmax = 12);
verifyTrue(testCase, isequaln(d1, d2) && isequaln(i1, i2), ...
    'ts.estimateDegree1 is not the lane');
% combineCenters: three centres of 14 epochs, as testCombineCentersRecovery
tc = cell(1, 3);
for c = 1:3
    tc{c} = wp7Series(6, 14, 110 + c);
end
[m1, j1] = tc{1}.combineCenters(tc(2:3), MaxIter = 4);
[m2, j2] = shLowLevel.combineCenters(tc, MaxIter = 4);
verifyTrue(testCase, isequaln(m1.Cs, m2.Cs) && isequaln(m1.sigmaCs, ...
    m2.sigmaCs) && isequaln(j1, j2), 'ts.combineCenters is not the lane');
% slepianProject
idx = shLowLevel.shIndex(12, Nmin = 0);
G = shLowLevel.slepianBasis(idx, @(la, lo) double(la > 60));
[a1, r1] = ts.slepianProject(G, idx);
[a2, r2] = shLowLevel.slepianProject(ts.Cs, ts.Ss, G, idx);
verifyTrue(testCase, isequal(a1, a2) && isequal(r1, r2), ...
    'ts.slepianProject is not the lane');
end

function testCoefficientsLastBacklogRoutesAreTheirLanes(testCase)
%TESTCOEFFICIENTSLASTBACKLOGROUTESARETHEIRLANES g.basinKernel,
%   g.sensitivityKernel, g.designFilter and g.mcPropagate are their lanes,
%   bitwise, with options and without (v5.24.0). The kernels are built in
%   shIndex(nmax), the ordering g.basinAverage reads; designFilter reads
%   the object's sigmas, and none of them when Noise is given.
ts = wp7Series(12, 1, 121);
g = ts.at(1);
idx = shLowLevel.shIndex(12);
cap = @(la, lo) double(la > 50);
[b1, i1] = g.basinKernel(cap);
[b2, i2] = shLowLevel.basinKernel(idx, cap);
verifyTrue(testCase, isequaln(b1, b2) && isequaln(i1, i2), ...
    'g.basinKernel is not the lane with its defaults');
[b1, i1] = g.basinKernel(cap, BufferKm = 500, TaperKm = 300);
[b2, i2] = shLowLevel.basinKernel(idx, cap, BufferKm = 500, TaperKm = 300);
verifyTrue(testCase, isequaln(b1, b2) && isequaln(i1, i2), ...
    'g.basinKernel is not the lane with options');
verifyEqual(testCase, size(g.basinAverage(b1)), [1 1]);
[k1, j1] = g.sensitivityKernel(cap);
[k2, j2] = shLowLevel.sensitivityKernel(idx, cap);
verifyTrue(testCase, isequaln(k1, k2) && isequaln(j1, j2), ...
    'g.sensitivityKernel is not the lane with its defaults');
[k1, j1] = g.sensitivityKernel(cap, Alpha = 0.5, TaperKm = 300);
[k2, j2] = shLowLevel.sensitivityKernel(idx, cap, Alpha = 0.5, TaperKm = 300);
verifyTrue(testCase, isequaln(k1, k2) && isequaln(j1, j2), ...
    'g.sensitivityKernel is not the lane with options');
% designFilter: the formal sigmas, then a full covariance that replaces them
[W1, f1] = g.designFilter();
[W2, f2] = shLowLevel.designFilter(g.sigmaC, g.sigmaS);
verifyTrue(testCase, isequaln(W1, W2) && isequaln(f1, f2), ...
    'g.designFilter is not the lane with its defaults');
[W1, f1] = g.designFilter(Alpha = 0.5, Nmin = 3, Name = "mine");
[W2, f2] = shLowLevel.designFilter(g.sigmaC, g.sigmaS, Alpha = 0.5, ...
    Nmin = 3, Name = "mine");
verifyTrue(testCase, isequaln(W1, W2) && isequaln(f1, f2), ...
    'g.designFilter is not the lane with options');
rng(122);
A = randn(idx.P);
M = (A * A' + idx.P * eye(idx.P)) * 1e-22;
bare = shCoefficients(g.C, g.S);
[W1, f1] = bare.designFilter(Noise = M, Idx = idx);
[W2, f2] = shLowLevel.designFilter(g.sigmaC, g.sigmaS, Noise = M, Idx = idx);
verifyTrue(testCase, isequaln(W1, W2) && isequaln(f1, f2), ...
    'with Noise the sigmas must not matter, and a field without them must work');
verifyError(testCase, @() bare.designFilter(), ...
    'shLowLevel:designFilter:badSigma');
% mcPropagate: same seed, same draws
fun = @(gs) [gs.C(3, 1); gs.S(4, 2)];
o1 = g.mcPropagate(fun, N = 50, Seed = 123);
o2 = shLowLevel.mcPropagate(fun, g, N = 50, Seed = 123);
verifyTrue(testCase, isequaln(o1, o2), 'g.mcPropagate is not the lane');
o1 = g.mcPropagate(fun, N = 20, Seed = 124, KeepSamples = true);
o2 = shLowLevel.mcPropagate(fun, g, N = 20, Seed = 124, KeepSamples = true);
verifyTrue(testCase, isequaln(o1, o2), 'g.mcPropagate is not the lane with options');
end

function testSeriesLastBacklogRoutesAreTheirLanes(testCase)
%TESTSERIESLASTBACKLOGROUTESARETHEIRLANES ts.basinKernel,
%   ts.sensitivityKernel, ts.signalVarianceKaula, ts.basinScaling and
%   ts.buildCondFun are their lanes, bitwise (v5.24.0). buildCondFun takes
%   GM and R from the series - pinned on a series with a radius that is
%   not the lane's default.
ts = wp7Series(12, 24, 125);
idx = shLowLevel.shIndex(12);
cap = @(la, lo) double(la > 50);
[b1, i1] = ts.basinKernel(cap, OverSample = 3);
[b2, i2] = shLowLevel.basinKernel(idx, cap, OverSample = 3);
verifyTrue(testCase, isequaln(b1, b2) && isequaln(i1, i2), 'ts.basinKernel is not the lane');
verifyEqual(testCase, size(ts.basinAverage(b1)), [1 24]);
[k1, j1] = ts.sensitivityKernel(cap, Alpha = 2);
[k2, j2] = shLowLevel.sensitivityKernel(idx, cap, Alpha = 2);
verifyTrue(testCase, isequaln(k1, k2) && isequaln(j1, j2), ...
    'ts.sensitivityKernel is not the lane');
% signalVarianceKaula: the lane's default LRange [10, 60] exceeds nmax 12,
% so the bare call must meet the lane's refusal - the default is the lane's
[a1, s1] = ts.signalVarianceKaula(LRange = [3, 10]);
[a2, s2] = shLowLevel.signalVarianceKaula(ts.Cs, ts.Ss, ts.epochs, LRange = [3, 10]);
verifyTrue(testCase, isequaln(a1, a2) && isequaln(s1, s2), ...
    'ts.signalVarianceKaula is not the lane');
verifyError(testCase, @() ts.signalVarianceKaula(), ...
    'shLowLevel:signalVarianceKaula:badRange');
% basinScaling: a Gaussian as a static operator in Nmin = 0 ordering, as in
% testBasinScalingRecoversFactor
idx0 = shLowLevel.shIndex(12, Nmin = 0);
Wn = shLowLevel.shGaussianWeights(12, 500);
W = diag(Wn(idx0.n + 1));
b0 = shLowLevel.basinKernel(idx0, cap);
ep = ts.epochs';
[q1, r1] = ts.basinScaling(W, b0, Idx = idx0, TYears = ep);
[q2, r2] = shLowLevel.basinScaling(W, b0, ts, Idx = idx0, TYears = ep);
verifyTrue(testCase, isequaln(q1, q2) && isequaln(r1, r2), 'ts.basinScaling is not the lane');
[q1, r1] = ts.basinScaling(W, b0, Idx = idx0, TYears = ep, PerMonth = true);
[q2, r2] = shLowLevel.basinScaling(W, b0, ts, Idx = idx0, TYears = ep, ...
    PerMonth = true);
verifyTrue(testCase, isequaln(q1, q2) && isequaln(r1, r2), ...
    'ts.basinScaling is not the lane with PerMonth');
% buildCondFun on a series of another radius
t6 = wp7Series(6, 3, 126);
t6 = shSeries(t6.Cs, Ss = t6.Ss, Epochs = t6.epochs, R = 6371000);
idx6 = shLowLevel.shIndex(6);
kn = -0.3 * ones(7, 1);
[c1, h1] = t6.buildCondFun(kn = kn, Psi0Km = 2000);
[c2, h2] = shLowLevel.buildCondFun(idx6, kn = kn, Psi0Km = 2000, ...
    GM = t6.GM, R = 6371000);
rng(127);
A = randn(idx6.P, 2 * idx6.P);
C = A * A' / (2 * idx6.P);
verifyTrue(testCase, isequaln(c1(C), c2(C)) && isequaln(h1, h2), ...
    'ts.buildCondFun is not the lane with the series'' GM and R');
end

function testDesignFilterRefusesANaNSigma(testCase)
%TESTDESIGNFILTERREFUSESANANSIGMA a NaN sigma failed "<= 0" as well, so
%   before v5.24.0 it passed the guard and made its whole block NaN, with
%   no error. It is refused as badSigma now, like a non-positive one.
sc = 3e-11 * ones(5);
sc(4, 2) = NaN;
verifyError(testCase, @() shLowLevel.designFilter(sc, 3e-11 * ones(5)), ...
    'shLowLevel:designFilter:badSigma');
verifyError(testCase, @() shLowLevel.designFilter(nan(5), nan(5)), ...
    'shLowLevel:designFilter:badSigma');
end

% ------------------------------------- v5.24.1: DRIVEN, the first batch
% error_id_audit's DRIVEN rule asks that every identifier the toolbox
% raises be named by a test. Three documented identifiers could never be
% raised - vdkApply:badSize, signalVarianceKaula:badRange and
% obpChain:emptyRefPeriod threw on a non-scalar format argument - and each
% sat in a guard no test drove. These four tests drive the cheapest guards
% of the backlog, each with the smallest input that reaches it; every call
% was checked against the guards above it in its function.

function testDrivenGuardsOfTheStatisticsLanes(testCase)
%TESTDRIVENGUARDSOFTHESTATISTICSLANES comparison, statistics and
%   time-series lanes refuse what they cannot use, by their own identifier.
ts8 = wp7Series(3, 8, 131);
verifyError(testCase, @() shLowLevel.compareSeries({ts8}), ...
    'shLowLevel:compareSeries:needTwo');
verifyError(testCase, @() shLowLevel.compareSeries({ts8, 5}), ...
    'shLowLevel:compareSeries:badInput');
verifyError(testCase, @() shLowLevel.compareSeries({ts8, ts8}), ...
    'shLowLevel:compareSeries:tooFewEpochs');            % 8 common < 12
verifyError(testCase, @() shLowLevel.spatialStats(ones(3, 4), ones(3, 5), ...
    1:3, 1:4), 'shLowLevel:spatialStats:sizeMismatch');
verifyError(testCase, @() shLowLevel.spatialStats(ones(3, 4), ones(3, 4), ...
    1:3, 1:4, Weights = ones(2, 2)), 'shLowLevel:spatialStats:badWeights');
verifyError(testCase, @() shLowLevel.spatialStats(nan(3, 4), ones(3, 4), ...
    1:3, 1:4), 'shLowLevel:spatialStats:emptyMask');
verifyError(testCase, @() shLowLevel.nashSutcliffe(1:5, 1:4), ...
    'shLowLevel:nashSutcliffe:sizeMismatch');
verifyError(testCase, @() shLowLevel.diffSpectrum(zeros(3), zeros(3), ...
    zeros(4), zeros(4)), 'shLowLevel:diffSpectrum:sizeMismatch');
verifyError(testCase, @() shLowLevel.taylorDiagram(1, [1 2], 0.5), ...
    'shLowLevel:taylorDiagram:sizeMismatch');            % before any figure
verifyError(testCase, @() shLowLevel.effectiveCorr((1:5)', (1:5)'), ...
    'shLowLevel:effectiveCorr:tooShort');
verifyError(testCase, @() shLowLevel.threeCorneredHat(randn(5, 3)), ...
    'shLowLevel:threeCorneredHat:tooShort');             % T x N, 5 < 12
verifyError(testCase, @() shLowLevel.estimateVAR(randn(3, 2)), ...
    'shLowLevel:estimateVAR:tooShort');                  % T = 2 <= Order + 1
verifyError(testCase, @() shLowLevel.eofAnalysis(wp7Series(3, 2, 132)), ...
    'shLowLevel:eofAnalysis:tooFewEpochs');
verifyWarning(testCase, @() shLowLevel.fitDeterministicModel(randn(1, 2), ...
    [2010; 2011]), 'shLowLevel:fitDeterministicModel:fewEpochs');
verifyError(testCase, @() shLowLevel.eofSeparate(randn(4, 6), ones(3, 1)), ...
    'shLowLevel:eofSeparate:badSize');
verifyError(testCase, @() shLowLevel.hydroExtremeIndex(randn(5, 1), (1:4)'), ...
    'shLowLevel:hydroExtremeIndex:badSize');
end

function testDrivenGuardsOfTheSpectralLanes(testCase)
%TESTDRIVENGUARDSOFTHESPECTRALLANES uncertainty, normal-equation, filter
%   and kernel lanes refuse inconsistent sizes and missing inputs.
g = wp7Series(3, 1, 133).at(1);
idx = shLowLevel.shIndex(3);
fun = @(gs) gs.C(3, 1);
verifyError(testCase, @() shLowLevel.mcPropagate(fun, g, Cov = eye(3)), ...
    'shLowLevel:mcPropagate:needIdx');
verifyError(testCase, @() shLowLevel.mcPropagate(fun, g, Cov = eye(2), ...
    Idx = idx), 'shLowLevel:mcPropagate:badCov');
verifyError(testCase, @() shLowLevel.mcPropagate(fun, g, Cov = -eye(idx.P), ...
    Idx = idx), 'shLowLevel:mcPropagate:covNotPD');
verifyError(testCase, @() shLowLevel.mcPropagate(fun, ...
    shCoefficients(g.C, g.S)), 'shLowLevel:mcPropagate:noSigmas');
verifyError(testCase, @() shLowLevel.neqCombine(struct('N', {})), ...
    'shLowLevel:neqCombine:empty');
two = [struct('N', eye(2), 'b', [1; 2]), struct('N', eye(2), 'b', [2; 1])];
verifyError(testCase, @() shLowLevel.neqCombine(two, Weights = [1; 2; 3]), ...
    'shLowLevel:neqCombine:badWeights');
verifyError(testCase, @() shLowLevel.neqCombine( ...
    [struct('N', eye(2), 'b', [1; 2]), struct('N', eye(3), 'b', [1; 2; 3])]), ...
    'shLowLevel:neqCombine:sizeMismatch');
verifyError(testCase, @() shLowLevel.neqCombine(struct('M', eye(2), ...
    'x', [1; 2])), 'shLowLevel:neqCombine:notNEQ');        % no kind "NEQ"
verifyError(testCase, @() shLowLevel.neqCombine(struct('foo', 1)), ...
    'shLowLevel:neqCombine:badInput');
verifyError(testCase, @() shLowLevel.designFilter(ones(4), ones(5)), ...
    'shLowLevel:designFilter:sizeMismatch');
verifyError(testCase, @() shLowLevel.designFilter(ones(4), ones(4), ...
    DegVar = [1 2]), 'shLowLevel:designFilter:badDegVar');
% a nmax-4 filter asked to read its noise in a nmax-3 index
verifyError(testCase, @() shLowLevel.designFilter(ones(5), ones(5), ...
    Noise = eye(idx.P), Idx = idx), 'shLowLevel:designFilter:idxMiss');
verifyError(testCase, @() shLowLevel.ylm([0; 1], 0, shLowLevel.shIndex(2)), ...
    'shLowLevel:ylm:sizeMismatch');
verifyError(testCase, @() shLowLevel.slepianProject(zeros(4), zeros(4), ...
    zeros(3, 2), idx), 'shLowLevel:slepianProject:sizeMismatch');
verifyError(testCase, @() shLowLevel.poleTideConvert(zeros(2), zeros(2), 2010), ...
    'shLowLevel:poleTideConvert:badSize');
verifyError(testCase, @() shLowLevel.poleTideConvert( ...
    shCoefficients(zeros(4), zeros(4))), 'shLowLevel:poleTideConvert:noEpoch');
verifyError(testCase, @() shLowLevel.errorMap(eye(2), idx, 0, 0), ...
    'shLowLevel:errorMap:badSize');
verifyError(testCase, @() shLowLevel.kernelFactors("geoid", 5, 3.986004415e14, ...
    6378136.3, hn = [1 2]), 'shLowLevel:kernelFactors:hnTooShort');
verifyError(testCase, @() shLowLevel.seaLevelFingerprint(@(la, lo) la > 0, ...
    @(la, lo) la < 0, shLowLevel.shIndex(4, Nmin = 0), kn = zeros(2, 1), ...
    hn = zeros(5, 1)), 'shLowLevel:seaLevelFingerprint:missingLoveNumbers');
verifyError(testCase, @() shLowLevel.buildCondFun(shLowLevel.shIndex(4), ...
    kn = -0.3 * ones(5, 1), Regions = [1 2 3]), 'shLowLevel:buildCondFun:badRegions');
end

function testDrivenGuardsOfTheGridLanes(testCase)
%TESTDRIVENGUARDSOFTHEGRIDLANES the grid lanes refuse a grid, mask or
%   kernel that does not fit, before any analysis runs.
verifyError(testCase, @() shLowLevel.gridScaling(zeros(3, 4), 1:4, 1:4), ...
    'shLowLevel:gridScaling:badSize');
verifyError(testCase, @() shLowLevel.gridScaling(zeros(3, 4, 2), [-30 0 30], ...
    1:4), 'shLowLevel:gridScaling:badNmax');             % 3 latitudes: nmax 1
verifyError(testCase, @() shLowLevel.oceanRMS(zeros(3, 4), 1:3, 1:4, ...
    true(2, 2)), 'shLowLevel:oceanRMS:badMask');
verifyError(testCase, @() shLowLevel.leakageCorrect(zeros(3, 4), [-30 0 30], ...
    1:4), 'shLowLevel:leakageCorrect:badNmax');
verifyError(testCase, @() shLowLevel.leakageCorrect(zeros(5, 4), -60:30:60, ...
    1:4, Mask = true(2, 2)), 'shLowLevel:leakageCorrect:badMask');
verifyError(testCase, @() shLowLevel.estimateDegree1(wp7Series(3, 2, 134), ...
    true(2, 2), kn = [0; 0.021; -0.3054; -0.196]), ...
    'shLowLevel:estimateDegree1:badMask');
f = [tempname, '.nc'];
verifyError(testCase, @() shLowLevel.writeGrid(f, zeros(3, 4), (1:2)', ...
    (1:4)'), 'shLowLevel:writeGrid:badSize');
idx0 = shLowLevel.shIndex(3, Nmin = 0);
tsM = wp7Series(3, 4, 135);
b = ones(idx0.P, 1);
verifyError(testCase, @() shLowLevel.basinScaling("x", b, tsM), ...
    'shLowLevel:basinScaling:badOp');
verifyError(testCase, @() shLowLevel.basinScaling(eye(idx0.P), b, tsM), ...
    'shLowLevel:basinScaling:needIdx');
verifyError(testCase, @() shLowLevel.basinScaling(eye(idx0.P), b, tsM, ...
    Idx = idx0, TYears = [1900 1901 1902]), 'shLowLevel:basinScaling:tooFewMatches');
end

function testDrivenGuardsOfTheClasses(testCase)
%TESTDRIVENGUARDSOFTHECLASSES class methods refuse mismatched operands,
%   impossible truncations, missing epochs and unknown choices.
ts = wp7Series(3, 8, 136);
g4 = wp7Series(4, 1, 137).at(1);
verifyError(testCase, @() ts - g4, 'shSeries:minus:sizeMismatch');
shifted = shSeries(ts.Cs, Ss = ts.Ss, Epochs = ts.epochs + 0.5);
verifyError(testCase, @() ts - shifted, 'shSeries:minus:epochMismatch');
verifyError(testCase, @() minus(ts, 5), 'shSeries:minus:badInput');
verifyError(testCase, @() ts.truncate(10), 'shSeries:truncate:badTruncation');
nanEp = shSeries(ts.Cs, Ss = ts.Ss, Epochs = [NaN; ts.epochs(2:end)]);
verifyError(testCase, @() nanEp.mean(Estimator = "model"), 'shSeries:mean:noEpoch');
verifyError(testCase, @() nanEp.removeAlias(), 'shSeries:removeAlias:noEpoch');
verifyError(testCase, @() ts.trendBreaks(Breaks = double.empty(1, 0)), ...
    'shSeries:trendBreaks:noBreaks');
g = ts.at(1);
verifyError(testCase, @() g.vec(shLowLevel.shIndex(10)), 'shCoefficients:vec:badIndex');
verifyError(testCase, @() plus(g, 5), 'shCoefficients:operands:badInput');
clim = wp7Series(3, 24, 138).climatology();
verifyError(testCase, @() clim.amplitudeMap("weird", -60:30:60, 0:90:270), ...
    'shClimatology:amplitudeMap:badInput');
end

% ------------------------------------------- WP8 8a: the regional basis
function testRegionalRoutesAreTheirLanes(testCase)
%TESTREGIONALROUTESARETHEIRLANES ts/g.regionalBasis are
%   shLowLevel.regionalBasis on the object's own index, and
%   ts/g.regionalProject are shLowLevel.regionalProject, bitwise, with
%   options and without - so neither grew a default of its own.
ts = wp7Series(12, 3, 120);
g = ts.at(1);
cap = @(la, lo) double(la > 60);
idx = shLowLevel.shIndex(12);
B1 = ts.regionalBasis(cap);
B2 = shLowLevel.regionalBasis(idx, cap);
verifyTrue(testCase, isequaln(B1, B2), 'ts.regionalBasis is not the lane');
verifyTrue(testCase, isequaln(g.regionalBasis(cap), B2), ...
    'g.regionalBasis is not the lane');
idx0 = shLowLevel.shIndex(12, Nmin = 0);
S1 = ts.regionalBasis(cap, Nmin = 0, Type = "slepian", NKeep = 4, BufferKm = 0);
S2 = shLowLevel.regionalBasis(idx0, cap, Type = "slepian", NKeep = 4, BufferKm = 0);
% isequaln: a Slepian basis carries NaN in level and nGlobal (no rbf grid),
% and isequal is false on NaN whatever the bits
verifyTrue(testCase, isequaln(S1, S2), 'ts.regionalBasis with options is not the lane');
[a1, r1] = ts.regionalProject(B1);
[a2, r2] = shLowLevel.regionalProject(ts.Cs, ts.Ss, B2);
verifyTrue(testCase, isequal(a1, a2) && isequal(r1, r2), ...
    'ts.regionalProject is not the lane');
verifySize(testCase, a1, [B1.K, 3]);
[c1, q1] = g.regionalProject(S1);
[c2, q2] = shLowLevel.regionalProject(g.C, g.S, S2);
verifyTrue(testCase, isequal(c1, c2) && isequal(q1, q2), ...
    'g.regionalProject is not the lane');
end

function testRegionalBasisIDs(testCase)
%TESTREGIONALBASISIDS Every documented identifier of readBasin,
%   regionalBasis and regionalProject, each driven by the guard it names.
idx = shLowLevel.shIndex(12);
cap = @(la, lo) double(la > 60);
verifyError(testCase, @() shLowLevel.regionalBasis(idx, []), ...
    'shLowLevel:regionalBasis:missingRegion');
verifyError(testCase, @() shLowLevel.regionalBasis(idx, ...
    @(la, lo) double(la > 89.99), BufferKm = 0), ...
    'shLowLevel:regionalBasis:emptyRegion');
verifyError(testCase, @() shLowLevel.regionalBasis(idx, cap, ...
    Kernel = "amplitude"), 'shLowLevel:regionalBasis:badAmplitude');
verifyError(testCase, @() shLowLevel.regionalBasis(idx, cap, ...
    DegreeAmplitude = ones(13, 1)), 'shLowLevel:regionalBasis:badAmplitude');
verifyError(testCase, @() shLowLevel.regionalBasis(idx, cap, ...
    Type = "slepian", Threshold = 1.5), 'shLowLevel:regionalBasis:badThreshold');
verifyError(testCase, @() shLowLevel.regionalBasis(idx, cap, ...
    Type = "slepian", Threshold = 0.5, NKeep = 2), ...
    'shLowLevel:regionalBasis:badThreshold');
B = shLowLevel.regionalBasis(idx, cap, Type = "sh");
verifyEqual(testCase, B.K, idx.P);
verifyError(testCase, @() shLowLevel.regionalProject(zeros(5), zeros(5), B), ...
    'shLowLevel:regionalProject:sizeMismatch');
verifyError(testCase, @() shLowLevel.regionalProject(zeros(13), zeros(13), ...
    struct('T', 1)), 'shLowLevel:regionalProject:badBasis');
verifyError(testCase, @() shLowLevel.readBasin("No Such River"), ...
    'shLowLevel:readBasin:unknownBasin');
verifyError(testCase, @() shLowLevel.readBasin("River"), ...
    'shLowLevel:readBasin:ambiguousBasin');
verifyError(testCase, @() shLowLevel.readBasin("Elbe", File = "nope.json"), ...
    'shLowLevel:readBasin:missingFile');
f = [tempname '.json'];
cleanup = onCleanup(@() delete(f)); %#ok<NASGU>
fid = fopen(f, 'w');
fprintf(fid, ['{"type":"FeatureCollection","features":[{"type":"Feature",' ...
    '"properties":{"name":"Spot"},"geometry":{"type":"Point",' ...
    '"coordinates":[10,50]}}]}']);
fclose(fid);
verifyError(testCase, @() shLowLevel.readBasin("Spot", File = f), ...
    'shLowLevel:readBasin:badGeometry');
end

% ------------------------------------------- WP8 8b: the process model
function testRegionalProcessModelRouteAndIDs(testCase)
%TESTREGIONALPROCESSMODELROUTEANDIDS ts.regionalProcessModel is the lane,
%   bitwise, with options and without; and every identifier of the lane
%   and of estimateVAR's new option is driven by the guard it names.
ts = wp7Series(8, 40, 130);
B = ts.regionalBasis([], Type = "sh");
[m1, i1] = ts.regionalProcessModel(B, Shrink = 1e-3);
[m2, i2] = shLowLevel.regionalProcessModel(ts, B, Shrink = 1e-3);
verifyTrue(testCase, isequaln(m1, m2) && isequaln(i1, i2), ...
    'ts.regionalProcessModel is not the lane');
[m1, i1] = ts.regionalProcessModel(B, Shrink = 1e-3, QScale = 5, ...
    Structure = "diagonal");
[m2, i2] = shLowLevel.regionalProcessModel(ts, B, Shrink = 1e-3, ...
    QScale = 5, Structure = "diagonal");
verifyTrue(testCase, isequaln(m1, m2) && isequaln(i1, i2), ...
    'ts.regionalProcessModel with options is not the lane');
verifyError(testCase, @() shLowLevel.regionalProcessModel(ts, struct('T', 1)), ...
    'shLowLevel:regionalProcessModel:badBasis');
B12 = shLowLevel.regionalBasis(shLowLevel.shIndex(12), [], Type = "sh");
verifyError(testCase, @() shLowLevel.regionalProcessModel(ts, B12), ...
    'shLowLevel:regionalProcessModel:nmaxMismatch');
verifyError(testCase, @() shLowLevel.regionalProcessModel(ts, B, ...
    GroundNoise = 0.02), 'shLowLevel:regionalProcessModel:missingLoveNumbers');
verifyError(testCase, @() shLowLevel.estimateVAR(randn(3, 50), ...
    Sigma0Add = eye(2)), 'shLowLevel:estimateVAR:badSigma0Add');
end

% ------------------------------------------- WP8 8c: the observations
function testRegionalNEQRouteAndIDs(testCase)
%TESTREGIONALNEQROUTEANDIDS g.regionalNEQ is the lane's "solution" kind
%   with the field's coefficients and squared formal sigmas, bitwise, and
%   with an explicit Cov; every identifier is driven by the guard it names.
ts = wp7Series(8, 1, 140);
g = ts.at(1);
idx = shLowLevel.shIndex(8);
B = g.regionalBasis(@(la, lo) double(la > 60));
l = shLowLevel.vecFromCS(g.C, g.S, idx);
c = shLowLevel.vecFromCS(g.sigmaC, g.sigmaS, idx) .^ 2;
[r1, i1] = g.regionalNEQ(B);
[r2, i2] = shLowLevel.regionalNEQ(B, "solution", Solution = l, Cov = c);
verifyTrue(testCase, isequaln(r1, r2) && isequaln(i1, i2), 'g.regionalNEQ is not the lane');
r1 = g.regionalNEQ(B, Cov = 2 * c, Name = "grace");
r2 = shLowLevel.regionalNEQ(B, "solution", Solution = l, Cov = 2 * c, Name = "grace");
verifyTrue(testCase, isequaln(r1, r2), 'g.regionalNEQ with options is not the lane');
g0 = shCoefficients(g.C, g.S, GM = g.GM, R = g.R);
verifyError(testCase, @() g0.regionalNEQ(B), 'shCoefficients:regionalNEQ:noSigmas');
P = idx.P;
pts = {"LatDeg", [70; 75], "LonDeg", [10; 20]};
verifyError(testCase, @() shLowLevel.regionalNEQ(struct('a', 1), "neq"), ...
    'shLowLevel:regionalNEQ:badBasis');
verifyError(testCase, @() shLowLevel.regionalNEQ(B, "solution", Solution = l), ...
    'shLowLevel:regionalNEQ:missingInput');
verifyError(testCase, @() shLowLevel.regionalNEQ(B, "neq"), ...
    'shLowLevel:regionalNEQ:missingInput');
verifyError(testCase, @() shLowLevel.regionalNEQ(B, "neq", NEQ = struct('q', 1)), ...
    'shLowLevel:regionalNEQ:missingInput');
verifyError(testCase, @() shLowLevel.regionalNEQ(B, "solution", ...
    Solution = ones(P - 1, 1), Cov = 1), 'shLowLevel:regionalNEQ:sizeMismatch');
verifyError(testCase, @() shLowLevel.regionalNEQ(B, "neq", ...
    NEQ = struct('N', eye(3), 'b', ones(3, 1))), 'shLowLevel:regionalNEQ:sizeMismatch');
verifyError(testCase, @() shLowLevel.regionalNEQ(B, "solution", Solution = l, ...
    Cov = eye(3)), 'shLowLevel:regionalNEQ:sizeMismatch');
verifyError(testCase, @() shLowLevel.regionalNEQ(B, "points", Values = [1; 2], ...
    LatDeg = [70; 75], LonDeg = 10, Cov = 1, Quantity = "potential"), ...
    'shLowLevel:regionalNEQ:sizeMismatch');
verifyError(testCase, @() shLowLevel.regionalNEQ(B, "points", pts{:}, Values = [1; 2; 3], ...
    Cov = 1, Quantity = "potential"), 'shLowLevel:regionalNEQ:sizeMismatch');
verifyError(testCase, @() shLowLevel.regionalNEQ(B, "points", pts{:}, Values = 1, ...
    Cov = 1, Quantity = "potential", Combine = [1 -1 0]), ...
    'shLowLevel:regionalNEQ:sizeMismatch');
verifyError(testCase, @() shLowLevel.regionalNEQ(B, "points", pts{:}, Values = [1; 2], ...
    Cov = 1, Quantity = "potential", Direction = [1 0 0]), ...
    'shLowLevel:regionalNEQ:sizeMismatch');
verifyError(testCase, @() shLowLevel.regionalNEQ(B, "solution", Solution = l, ...
    Cov = -c), 'shLowLevel:regionalNEQ:notPositiveDefinite');
verifyError(testCase, @() shLowLevel.regionalNEQ(B, "points", pts{:}, Values = [1; 2], ...
    Cov = [1 2; 2 1], Quantity = "potential"), ...
    'shLowLevel:regionalNEQ:notPositiveDefinite');
kn = -0.3 * (0:8)' ./ ((0:8)' + 3);
verifyError(testCase, @() shLowLevel.regionalNEQ(B, "points", pts{:}, Values = [1; 2], ...
    Cov = 1, kn = kn, Height = 1000), 'shLowLevel:regionalNEQ:noRadialLaw');
verifyError(testCase, @() shLowLevel.regionalNEQ(B, "points", pts{:}, Values = [1; 2], ...
    Cov = 1, kn = kn, Direction = [0 0 1; 0 0 1]), ...
    'shLowLevel:regionalNEQ:noRadialLaw');
verifyError(testCase, @() shLowLevel.regionalNEQ(B, "points", Values = [1; 2], ...
    LatDeg = [90; 75], LonDeg = [10; 20], Cov = 1, Quantity = "potential", ...
    Direction = [0 0 1; 0 0 1]), 'shLowLevel:regionalNEQ:poleDirection');
end

function testRegionalNEQFeedsNeqCombineAndTheFilter(testCase)
%TESTREGIONALNEQFEEDSNEQCOMBINEANDTHEFILTER Contributions of two kinds
%   combine in neqCombine with variance components (ltpl and nobs are
%   there), and a contribution's N and b update kalmanFilter in its
%   normal-equation mode - the two consumers row 8d will chain.
idx = shLowLevel.shIndex(10);
B = shLowLevel.regionalBasis(idx, @(la, lo) double(la > 55));
rng(26);
a0 = randn(B.K, 1) * 1e-10;
lat = 40 + 49 * rand(300, 1);
lon = 360 * rand(300, 1);
[~, info] = shLowLevel.regionalNEQ(B, "points", Values = zeros(300, 1), ...
    LatDeg = lat, LonDeg = lon, Quantity = "potential", Cov = 1);
yp = info.A * a0 + 1e-4 * randn(300, 1);
r1 = shLowLevel.regionalNEQ(B, "points", Values = yp, LatDeg = lat, ...
    LonDeg = lon, Quantity = "potential", Cov = 1e-8, Name = "points");
l = full(B.T * a0) + 1e-11 * randn(idx.P, 1);
r2 = shLowLevel.regionalNEQ(B, "solution", Solution = l, Cov = 1e-22);
[x, out] = shLowLevel.neqCombine([r1, r2]);
verifySize(testCase, x, [B.K, 1]);
verifyTrue(testCase, all(isfinite(out.sigma2)) && all(out.sigma2 > 0));
verifyEqual(testCase, out.names, ["points"; "solution"]);
X = randn(B.K, 200) * 1e-10;
model = shLowLevel.estimateVAR(X, Shrink = 1e-2);
obs = repmat(struct('l', [], 'R', [], 'N', [], 'b', []), 1, 3);
obs(2).N = r2.N;
obs(2).b = r2.b;
filt = shLowLevel.kalmanFilter(model, obs, StoreCov = "diag");
verifyEqual(testCase, filt.gap, [true false true]);
verifyTrue(testCase, all(isfinite(filt.xf(:))));
end

% ------------------------------------------- WP8 8d: the chain
function testRegionalKalmanRouteAndIDs(testCase)
%TESTREGIONALKALMANROUTEANDIDS ts.regionalKalman is the lane with the
%   series as the observations - bitwise, with options and with the lane's
%   defaults; every identifier of the lane, and rtsSmoother's new one, is
%   driven by the guard it names.
tsObs = wp7Series(6, 30, 150);
tsm = wp7Series(6, 120, 151);
B = tsObs.regionalBasis(@(la, lo) double(la > 50));
[a1, o1] = tsObs.regionalKalman(B, ModelSeries = tsm);
[a2, o2] = shLowLevel.regionalKalman(tsObs, B, ModelSeries = tsm);
verifyTrue(testCase, isequaln(a1, a2) && isequaln(o1, o2), ...
    'ts.regionalKalman is not the lane');
kn = -0.3 * (0:6)' ./ ((0:6)' + 3);
opt = {"Shrink", 1e-3, "QScale", 3, "Lag", 2, "Climatology", false};
[a1, o1] = tsObs.regionalKalman(B, opt{:}, ModelSeries = tsm, kn = kn);
[a2, o2] = shLowLevel.regionalKalman(tsObs, B, opt{:}, ModelSeries = tsm, kn = kn);
verifyTrue(testCase, isequaln(a1, a2) && isequaln(o1, o2), ...
    'ts.regionalKalman with options is not the lane');
verifyNotEmpty(testCase, o1.basin);
K = B.K;
rec = struct('N', eye(K), 'b', zeros(K, 1), 'epoch', 2005.5);
verifyError(testCase, @() shLowLevel.regionalKalman(tsObs, struct('T', 1), ...
    ModelSeries = tsm), 'shLowLevel:regionalKalman:badBasis');
verifyError(testCase, @() shLowLevel.regionalKalman(tsObs, B), ...
    'shLowLevel:regionalKalman:missingModel');
verifyError(testCase, @() shLowLevel.regionalKalman(tsObs, B, ...
    ModelSeries = tsm.truncate(5)), 'shLowLevel:regionalKalman:nmaxMismatch');
verifyError(testCase, @() shLowLevel.regionalKalman(tsObs.truncate(5), B, ...
    ModelSeries = tsm), 'shLowLevel:regionalKalman:nmaxMismatch');
verifyError(testCase, @() shLowLevel.regionalKalman(5, B, ModelSeries = tsm), ...
    'shLowLevel:regionalKalman:badInput');
verifyError(testCase, @() shLowLevel.regionalKalman(rmfield(rec, 'epoch'), B, ...
    ModelSeries = tsm), 'shLowLevel:regionalKalman:badRecord');
verifyError(testCase, @() shLowLevel.regionalKalman(struct('N', eye(2), ...
    'b', [0; 0], 'epoch', 2005.5), B, ModelSeries = tsm), ...
    'shLowLevel:regionalKalman:badRecord');
verifyError(testCase, @() shLowLevel.regionalKalman([rec, rec], B, ...
    ModelSeries = tsm), 'shLowLevel:regionalKalman:badRecord');
tsNo = shSeries(tsObs.Cs, Ss = tsObs.Ss, Epochs = tsObs.epochs);
verifyError(testCase, @() shLowLevel.regionalKalman(tsNo, B, ModelSeries = tsm), ...
    'shLowLevel:regionalKalman:noNoise');
filt = struct('storeCov', "full", 'B', 0.5, 'P', 1, 'xf', [1 2], ...
    'xp', [1 2], 'Pf', ones(1, 1, 2), 'Pp', ones(1, 1, 2), 'order', 1);
verifyError(testCase, @() shLowLevel.rtsSmoother(filt, Functionals = ones(2)), ...
    'shLowLevel:rtsSmoother:badFunctionals');
end

% ------------------------------------------- WP8 8e: remove-compute-restore
function testRegionalKalmanBackgroundRouteAndIDs(testCase)
%TESTREGIONALKALMANBACKGROUNDROUTEANDIDS ts.regionalKalman forwards
%   Background to the lane, bitwise; the background is refused when it is
%   not an shSeries, does not reach the basis' degree, or lacks an epoch
%   the observations or the output grid need.
tsObs = wp7Series(6, 30, 160);
tsm = wp7Series(6, 120, 161);
bgS = wp7Series(6, 30, 162);
B = tsObs.regionalBasis(@(la, lo) double(la > 50));
[a1, o1] = tsObs.regionalKalman(B, ModelSeries = tsm, Background = bgS);
[a2, o2] = shLowLevel.regionalKalman(tsObs, B, ModelSeries = tsm, Background = bgS);
verifyTrue(testCase, isequaln(a1, a2) && isequaln(o1, o2), ...
    'ts.regionalKalman with Background is not the lane');
verifyTrue(testCase, o1.background);
verifyError(testCase, @() shLowLevel.regionalKalman(tsObs, B, ModelSeries = tsm, ...
    Background = 5), 'shLowLevel:regionalKalman:badBackground');
verifyError(testCase, @() shLowLevel.regionalKalman(tsObs, B, ModelSeries = tsm, ...
    Background = bgS.truncate(5)), 'shLowLevel:regionalKalman:badBackground');
short = shSeries(bgS.Cs(:, :, 1:10), Ss = bgS.Ss(:, :, 1:10), ...
    Epochs = bgS.epochs(1:10));
verifyError(testCase, @() shLowLevel.regionalKalman(tsObs, B, ModelSeries = tsm, ...
    Background = short), 'shLowLevel:regionalKalman:badBackground');
end

function testRegionalNEQLgdIDs(testCase)
%TESTREGIONALNEQLGDIDS Every identifier kind "lgd" can raise, each driven
%   by the guard it names: a missing orbit, orbits or a mask that do not fit
%   the data, a covariance of the wrong size, an operator of the wrong kind
%   or returning the wrong size, and a mask that leaves nothing.
idx = shLowLevel.shIndex(8);
B = shLowLevel.regionalBasis(idx, @(la, lo) double(la > 60));
R = 6378136.3;
th = linspace(0.9, 1.3, 20)';
rA = (R + 490e3) * [cos(th), zeros(20, 1), sin(th)];
rB = (R + 490e3) * [cos(th + 0.03), zeros(20, 1), sin(th + 0.03)];
y = zeros(20, 1);
base = {"Values", y, "PositionA", rA, "PositionB", rB};
verifyError(testCase, @() shLowLevel.regionalNEQ(B, "lgd", Values = y, ...
    PositionA = rA, Cov = 1), 'shLowLevel:regionalNEQ:missingInput');
verifyError(testCase, @() shLowLevel.regionalNEQ(B, "lgd", Values = y, ...
    PositionA = rA(1:19, :), PositionB = rB, Cov = 1), 'shLowLevel:regionalNEQ:sizeMismatch');
verifyError(testCase, @() shLowLevel.regionalNEQ(B, "lgd", base{:}, Cov = 1, ...
    Valid = true(19, 1)), 'shLowLevel:regionalNEQ:sizeMismatch');
verifyError(testCase, @() shLowLevel.regionalNEQ(B, "lgd", base{:}, Cov = ones(19, 1)), ...
    'shLowLevel:regionalNEQ:sizeMismatch');
verifyError(testCase, @() shLowLevel.regionalNEQ(B, "lgd", base{:}, Cov = 1, ...
    Operator = eye(19)), 'shLowLevel:regionalNEQ:badOperator');
verifyError(testCase, @() shLowLevel.regionalNEQ(B, "lgd", base{:}, Cov = 1, ...
    Operator = @(Z) Z(1:19, :)), 'shLowLevel:regionalNEQ:badOperator');
verifyError(testCase, @() shLowLevel.regionalNEQ(B, "lgd", base{:}, Cov = 1, ...
    Valid = false(20, 1)), 'shLowLevel:regionalNEQ:noObservations');
[rec, info] = shLowLevel.regionalNEQ(B, "lgd", base{:}, Cov = 1);
verifyEqual(testCase, rec.nobs, 20);
verifyEqual(testCase, info.kept, true(20, 1));
end

function testRegionalKalmanQScaleRouteAndIDs(testCase)
%TESTREGIONALKALMANQSCALEROUTEANDIDS ts.regionalKalman forwards QBlocks,
%   a QScale per block and EstimateQScale to the lane - bitwise - and the
%   new identifiers are driven by the guards they name: block labels that
%   do not fit the basis, a block left empty, a QScale of the wrong length;
%   and buildCondFun refuses a basis on another index.
tsObs = wp7Series(6, 30, 152);
tsm = wp7Series(6, 120, 153);
B = tsObs.regionalBasis(@(la, lo) double(la > 50));
K = B.K;
blocks = 1 + double((1:K)' > K / 2);
opt = {"QBlocks", blocks, "QScale", [2; 0.5], "Climatology", false};
[a1, o1] = tsObs.regionalKalman(B, opt{:}, ModelSeries = tsm);
[a2, o2] = shLowLevel.regionalKalman(tsObs, B, opt{:}, ModelSeries = tsm);
verifyTrue(testCase, isequaln(a1, a2) && isequaln(o1, o2), ...
    'ts.regionalKalman with QBlocks is not the lane');
[a1, o1] = tsObs.regionalKalman(B, ModelSeries = tsm, EstimateQScale = true, ...
    Climatology = false);
[a2, o2] = shLowLevel.regionalKalman(tsObs, B, ModelSeries = tsm, ...
    EstimateQScale = true, Climatology = false);
verifyTrue(testCase, isequaln(a1, a2) && isequaln(o1, o2), ...
    'ts.regionalKalman with EstimateQScale is not the lane');
verifyTrue(testCase, o1.qEstimate.estimated);
verifyError(testCase, @() shLowLevel.regionalKalman(tsObs, B, ModelSeries = tsm, ...
    QBlocks = ones(K - 1, 1)), 'shLowLevel:regionalKalman:badQBlocks');
verifyError(testCase, @() shLowLevel.regionalKalman(tsObs, B, ModelSeries = tsm, ...
    QBlocks = 2 * ones(K, 1)), 'shLowLevel:regionalKalman:badQBlocks');
verifyError(testCase, @() shLowLevel.regionalKalman(tsObs, B, ModelSeries = tsm, ...
    QBlocks = 1.5 * ones(K, 1)), 'shLowLevel:regionalKalman:badQBlocks');
verifyError(testCase, @() shLowLevel.regionalKalman(tsObs, B, ModelSeries = tsm, ...
    QBlocks = blocks, QScale = [1; 2; 3]), 'shLowLevel:regionalKalman:badQBlocks');
kn = -0.3 * ones(7, 1);
verifyError(testCase, @() shLowLevel.buildCondFun(shLowLevel.shIndex(5), kn = kn, ...
    Basis = B), 'shLowLevel:buildCondFun:badBasis');
verifyError(testCase, @() shLowLevel.buildCondFun(shLowLevel.shIndex(6), kn = kn, ...
    Basis = struct('T', 1)), 'shLowLevel:buildCondFun:badBasis');
end

function testApplyDDKRefusesAnUnknownBlockType(testCase)
%TESTAPPLYDDKREFUSESANUNKNOWNBLOCKTYPE v5.23.1: a block whose cs is not
%   0 or 1 is refused. A W saved from designFilter before v5.23.1 carries
%   'c'/'s', which used to send every block down the S branch silently.
W = struct('nmax', 2, 'name', 'old', 'blocks', ...
    struct('m', 0, 'cs', 'c', 'n', 2, 'M', 0.5));
verifyError(testCase, @() shLowLevel.applyDDK(zeros(3), zeros(3), W), ...
    'shLowLevel:applyDDK:badBlock');
end

function testStandardChainDropsAnEpochInAnInteriorGap(testCase)
%TESTSTANDARDCHAINDROPSANEPOCHINANINTERIORGAP v5.23.4: OnMissing = "drop"
%   drops an epoch no record reaches within Tolerance, also inside a
%   table's range. TN-13 has no record for the 2017-07..2018-05 gap, so a
%   2017-12 month used to pass the range check and stop the chain in
%   addDegree1 with epochNotInTable.
dd = shxTestDataDir();
fol = tempname; mkdir(fol);
cl = onCleanup(@() rmIfFolder(fol)); %#ok<NASGU>
g = shCoefficients.read(fullfile(dd, 'ITSG-Grace2018_n60_2008-04.gfc'));
g.write(fullfile(fol, 'ITSG-Grace2018_n60_2008-04.gfc'), Sidecar = false);
g.write(fullfile(fol, 'ITSG-Grace2018_n60_2017-12.gfc'), Sidecar = false);
tn13 = fullfile(dd, 'TN-13_GEOC_CSR_RL06.3.txt');
[ts, rep] = shLowLevel.standardChain(fol, TN14 = false, ...
    Degree1File = tn13, Filter = "none", Quiet = true);
verifyEqual(testCase, ts.nEpochs, 1, 'the gap month must be dropped');
verifyLessThan(testCase, ts.epochs, 2009);
verifyTrue(testCase, any(contains(rep.steps, "without a TN-13 record")));
verifyError(testCase, @() shLowLevel.standardChain(fol, TN14 = false, ...
    Degree1File = tn13, Filter = "none", OnMissing = "error", ...
    Quiet = true), 'shLowLevel:standardChain:uncoveredEpochs');
end

function testEstimateDegree1UsesTheSeriesRadius(testCase)
%TESTESTIMATEDEGREE1USESTHESERIESRADIUS v5.23.4: the degree-1 basis takes
%   the series' R, as the synthesis of the observations does. The EWH
%   kernel is linear in R, so the same coefficients on another radius
%   must give the same estimate; with the fixed 6378136.3 in the basis
%   they came back scaled by the ratio of the radii.
lat = -89:4:89;
lon = 0:4:356;
[LO, LA] = meshgrid(lon, lat);
ocean = ~(((LA > 10) & (LA < 70) & (LO > 250) & (LO < 350)) | ...
          ((LA > -40) & (LA < 30) & (LO > 10) & (LO < 60)));
kn = [0; 0.021; -0.3054; -0.1960; zeros(17, 1)];
t1 = wp7Series(12, 2, 103);
t2 = shSeries(t1.Cs, Ss = t1.Ss, Epochs = t1.epochs, R = 1.01 * t1.R);
ws = warning('off', 'shLowLevel:estimateDegree1:noOceanModel');
cw = onCleanup(@() warning(ws));
d1 = shLowLevel.estimateDegree1(t1, ocean, kn = kn, LatDeg = lat, ...
    LonDeg = lon, Nmax = 12);
d2 = shLowLevel.estimateDegree1(t2, ocean, kn = kn, LatDeg = lat, ...
    LonDeg = lon, Nmax = 12);
% rounding of the two syntheses and solves only; the bug was a factor 1.01
verifyEqual(testCase, [d2.C10, d2.C11, d2.S11], [d1.C10, d1.C11, d1.S11], ...
    'RelTol', 1e-10);
end

function testSynthesisRefusesAnUnknownMethod(testCase)
%TESTSYNTHESISREFUSESANUNKNOWNMETHOD v5.23.4: a Method other than "auto",
%   "direct" or "fft" ran the direct path silently.
C = zeros(3); S = zeros(3);
verifyError(testCase, @() shLowLevel.shSynthesis(C, S, 1, 1, 0, [0 10 50], ...
    'Method', 'fast'), 'shLowLevel:shSynthesis:badMethod');
% any case of a valid value still works
g = shLowLevel.shSynthesis(C, S, 1, 1, 0, [0 10 50], 'Method', 'DIRECT');
verifyEqual(testCase, size(g), [1 3]);
end

function testPlotSHSpectrumOverlaysAStructArray(testCase)
%TESTPLOTSHSPECTRUMOVERLAYSASTRUCTARRAY v5.23.4: a struct array of
%   spectra is overlaid like a cell array; it was wrapped as one cell and
%   failed.
fig = figure('Visible', 'off');
cleanup = onCleanup(@() close(fig)); %#ok<NASGU>
rng(48);
L = 10; n1 = L + 1;
C = tril(randn(n1)) * 1e-9; S = tril(randn(n1), -1) * 1e-9; S(:, 1) = 0;
sd = shLowLevel.shDegreeRMS(C, S);
axA = subplot(1, 2, 1, 'Parent', fig);
axB = subplot(1, 2, 2, 'Parent', fig);
shLowLevel.plotSHSpectrum({sd, sd}, 'Ax', axA);
shLowLevel.plotSHSpectrum([sd, sd], 'Ax', axB);
verifyEqual(testCase, numel(findobj(axB, 'Type', 'line')), ...
    numel(findobj(axA, 'Type', 'line')));
end

function testDemoEmptyOutDirIsATempFolder(testCase)
%TESTDEMOEMPTYOUTDIRISATEMPFOLDER v5.23.4: OutDir = "" writes the D16
%   exports into a fresh folder under tempdir; it reached fullfile as ''
%   and wrote them into the current folder.
here = pwd;
tmp = tempname; mkdir(tmp);
cd(tmp);
% one cleanup, in this order: Windows cannot remove the current folder
cl = onCleanup(@() leaveAndRemove(here, tmp)); %#ok<NASGU>
% the outcome of the export itself is not this test's subject (D16 also
% writes a video, which needs a codec); only where it writes is
ws = warning('off', 'shAnalysis:demo:casesFailed');
cw = onCleanup(@() warning(ws)); %#ok<NASGU>
evalc('demo_shAnalysis("D16", Visible = false, OutDir = "");');
close all hidden;
verifyEmpty(testCase, dir(fullfile(tmp, 'shx_demo_*')), ...
    'OutDir = "" wrote into the current folder');
end

function leaveAndRemove(here, tmp)
%LEAVEANDREMOVE Return to HERE, then remove TMP.
cd(here);
rmIfFolder(tmp);
end
