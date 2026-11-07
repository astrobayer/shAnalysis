function tests = testScience
%TESTSCIENCE Regression against PUBLISHED values, not against ourselves.
%   runtests('testScience')  (run from tests/, or use runAllTests)
%
%   The other suites check that the code does what the code intends:
%   contracts, identities, round trips, pinned values produced by this
%   toolbox. All of those stay green if a formula is consistently wrong.
%   This suite compares against numbers published OUTSIDE the toolbox -
%   defining constants, load Love numbers from the literature, the
%   closed-form EWH kernel, geocenter amplitudes from the providers'
%   own technical notes - so a sign error or a missing factor has
%   somewhere to show up.
%
%   Tolerances are deliberately of two kinds. Where a published value is
%   exact (defining constants, a tabulated Love number) the tolerance is
%   numerical. Where it is an observed geophysical quantity the test
%   asserts the ORDER OF MAGNITUDE and the ORDERING that the literature
%   reports, not a digit string - a tight tolerance on a measured
%   quantity would only pin this particular fixture.
%
%   Developed by Matthias Weigelt with the help of Claude (Opus 5),
%   2026-08-11 (v3.2.1).
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
here = fileparts(mfilename('fullpath'));
root = fileparts(here);
addpath(root);
testCase.TestData.dataDir = shxTestDataDir();
end

% ------------------------------------------------- defining constants
function testWGS84NormalFieldAgainstPublishedJ2(testCase)
%TESTWGS84NORMALFIELDAGAINSTPUBLISHEDJ2 J2 from the defining constants.
%   normalFieldCS COMPUTES the even zonals from the four defining
%   constants rather than tabulating them. The published WGS84 value
%   (NIMA TR8350.2, 3rd ed.) is therefore an independent check on that
%   computation: J2 = 1.082629821313e-3, which the standard quotes to
%   all the digits reproduced here.
Cn = shLowLevel.normalFieldCS(4, System = "WGS84");
J2 = -Cn(3, 1) * sqrt(5);                 % J2 = -sqrt(5) * Cbar20
verifyEqual(testCase, J2, 1.082629821313e-3, 'RelTol', 1e-10);

% GRS80 differs from WGS84 in the 8th digit of J2 - a real, published
% difference that a tabulated implementation would miss
Cg = shLowLevel.normalFieldCS(4, System = "GRS80");
J2g = -Cg(3, 1) * sqrt(5);
verifyEqual(testCase, J2g, 1.08263e-3, 'RelTol', 1e-5);
verifyNotEqual(testCase, J2g, J2);
verifyLessThan(testCase, abs(J2g - J2) / J2, 1e-6);
end

% ------------------------------------------------------- Love numbers
function testLoadLoveNumbersAgainstPublishedPREM(testCase)
%TESTLOADLOVENUMBERSAGAINSTPUBLISHEDPREM The shipped set is the real one.
%   The bundled Gegout97 (PREM) load Love numbers must carry the
%   published k'_2 = -0.3054, and k'_1 = 0 identifies the set as being
%   in the CENTRE-OF-MASS frame - the convention matters, because
%   degree-1 load Love numbers are frame dependent and mixing frames
%   silently biases geocenter and fingerprint results.
f = fullfile(testCase.TestData.dataDir, 'loadLoveNumbers_Gegout97.txt');
kn = readmatrix(f, 'FileType', 'text', 'NumHeaderLines', 2);
verifyGreaterThan(testCase, numel(kn), 100);
verifyEqual(testCase, kn(3), -0.3054, 'AbsTol', 1e-4);   % k'_2, published
verifyEqual(testCase, kn(4), -0.1960, 'AbsTol', 1e-4);   % k'_3, published
verifyEqual(testCase, kn(2), 0, 'AbsTol', 1e-12);        % CM frame
% load Love numbers are negative and decay towards zero with degree
verifyTrue(testCase, all(kn(3:end) < 0));
verifyLessThan(testCase, abs(kn(end)), abs(kn(3)));
end

function testEWHKernelAgainstClosedForm(testCase)
%TESTEWHKERNELAGAINSTCLOSEDFORM The textbook EWH kernel, digit for digit.
%   Wahr et al. (1998): surface density in equivalent water height is
%       R * rho_ave / (3 * rho_water) * (2n+1) / (1 + k'_n)
%   Evaluated here with the SHIPPED Love numbers, so the test checks the
%   toolbox's kernel against the formula rather than against itself.
f = fullfile(testCase.TestData.dataDir, 'loadLoveNumbers_Gegout97.txt');
kn = readmatrix(f, 'FileType', 'text', 'NumHeaderLines', 2);
GM = 3.986004415e14;
R = 6378136.3;
rhoAve = 5517;
rhoWater = 1000;
kf = shLowLevel.kernelFactors("ewh", 6, GM, R, kn = kn);
for n = 2:6
    published = R * rhoAve / (3 * rhoWater) * (2 * n + 1) / (1 + kn(n + 1));
    verifyEqual(testCase, kf(n + 1), published, 'RelTol', 1e-12, ...
        sprintf('EWH kernel at degree %d', n));
end
end

% --------------------------------------------------------- C20 vs SLR
function testGRACEC20DiffersFromSLRAsPublished(testCase)
%TESTGRACEC20DIFFERSFROMSLRASPUBLISHED The reason TN-14 exists at all.
%   GRACE's own C20 is known to be unreliable and is routinely replaced
%   by the SLR value; the published discrepancy is at the 1e-10 level,
%   i.e. small in absolute terms but large compared with the C20 signal.
%   If this test ever finds a ZERO difference, the replacement silently
%   stopped happening.
dd = testCase.TestData.dataDir;
g = shCoefficients.read(fullfile(dd, 'ITSG-Grace2018_n60_2008-04.gfc'));
tn = shLowLevel.readTN14(fullfile(dd, 'TN-14_C30_C20_SLR_GSFC.txt'));
[~, i] = min(abs(tn.epoch - g.epoch));
verifyLessThan(testCase, abs(tn.epoch(i) - g.epoch), 0.05, ...
    'the fixture must contain a TN-14 window at the solution epoch');

d = g.C(3, 1) - tn.C20(i);
verifyGreaterThan(testCase, abs(d), 1e-12, ...
    'GRACE and SLR C20 are not identical - a zero here means no data');
verifyLessThan(testCase, abs(d), 5e-10, ...
    'the published GRACE-SLR C20 discrepancy is at the 1e-10 level');

% and the replacement must actually install the SLR value
g2 = g.applyTN14(tn);
verifyEqual(testCase, g2.C(3, 1), tn.C20(i), 'RelTol', 1e-14);
verifyNotEqual(testCase, g2.C(3, 1), g.C(3, 1));
% C20 itself is dominated by the flattening: about -4.84e-4
verifyEqual(testCase, g.C(3, 1), -4.8417e-4, 'RelTol', 1e-3);
end

% ---------------------------------------------------------- geocenter
function testGeocenterAmplitudesMatchPublishedRanges(testCase)
%TESTGEOCENTERAMPLITUDESMATCHPUBLISHEDRANGES Degree 1 in millimetres.
%   The TN-13 degree-1 coefficients describe the motion of the Earth's
%   centre of mass relative to the centre of figure. Converted to
%   Cartesian offsets, X = sqrt(3) R Cbar11, Y = sqrt(3) R Sbar11,
%   Z = sqrt(3) R Cbar10, the published amplitudes are a few
%   millimetres, with Z clearly the largest component - a robust,
%   repeatedly reported feature, not a fixture artefact.
dd = testCase.TestData.dataDir;
R = 6378136.3;
for provider = ["CSR", "GFZ", "JPL"]
    f = dir(fullfile(dd, "TN-13_GEOC_" + provider + "*"));
    assumeNotEmpty(testCase, f, "no TN-13 fixture for " + provider);
    tn = shLowLevel.readTN13(fullfile(f(1).folder, f(1).name));
    X = sqrt(3) * R * tn.C11;
    Y = sqrt(3) * R * tn.S11;
    Z = sqrt(3) * R * tn.C10;
    rmsMM = 1e3 * [rms(X), rms(Y), rms(Z)];

    % a few millimetres, and never centimetres or micrometres
    verifyTrue(testCase, all(rmsMM > 0.5 & rmsMM < 20), ...
        sprintf('%s geocenter RMS [mm] = %s, expected a few mm', ...
                provider, mat2str(round(rmsMM, 2))));
    % Z dominates: the published, consistently reported ordering
    verifyGreaterThan(testCase, rmsMM(3), rmsMM(1), ...
        sprintf('%s: Z should exceed X', provider));
    verifyGreaterThan(testCase, rmsMM(3), rmsMM(2), ...
        sprintf('%s: Z should exceed Y', provider));
end
end

% ---------------------------------------------------- filter response
function testGaussianHalfWeightDegreeScalesWithRadius(testCase)
%TESTGAUSSIANHALFWEIGHTDEGREESCALESWITHRADIUS n_half * radius ~ constant.
%   Jekeli's Gaussian averaging kernel has a half-weight degree roughly
%   inversely proportional to the averaging radius - the relation behind
%   the rule of thumb that a 500 km filter resolves about degree 20.
%   The PRODUCT n_half * radius is therefore near-constant, which tests
%   the recursion's shape rather than any single tabulated weight.
prod = zeros(1, 3);
radii = [300, 500, 1000];
for k = 1:3
    w = shLowLevel.shGaussianWeights(200, radii(k));
    verifyEqual(testCase, w(1), 1, 'AbsTol', 1e-12, ...
        'W(0) = 1 by construction');
    verifyTrue(testCase, all(diff(w) <= 1e-14), ...
        'the weights must decrease monotonically');
    nHalf = find(w < 0.5, 1) - 2;              % degrees are 0-based
    verifyGreaterThan(testCase, nHalf, 0);
    prod(k) = nHalf * radii(k);
end
% the product is constant to within a few percent across a factor of 3
% in radius; it lands near 8000-8500 km, i.e. degree ~17 at 500 km
verifyLessThan(testCase, (max(prod) - min(prod)) / mean(prod), 0.10, ...
    sprintf('n_half * radius should be near-constant, got %s', ...
            mat2str(prod)));
verifyTrue(testCase, all(prod > 6000 & prod < 11000), ...
    sprintf('n_half * radius = %s km, expected ~8000-8500', mat2str(prod)));
end

% ------------------------------------------- real series (opt-in only)
function testPublishedTrendOnARealSeries(testCase)
%TESTPUBLISHEDTRENDONAREALSERIES A real trend, when real data is present.
%   A trend regression needs a monthly SERIES, which is far too large to
%   ship as a fixture. This test is therefore OPT-IN: point
%   SHX_SERIES_FOLDER at a folder of monthly .gfc files and it runs.
%   It is deliberately not wired to the persistent data folder, so a
%   routine acceptance run never touches a network or archive drive.
%
%   What it checks are published, uncontroversial facts rather than a
%   specific number: Greenland loses mass over the GRACE era (which a
%   sign-flipped or mislocated trend cannot satisfy), and: after the standard corrections the global mean mass
%   is conserved to a small fraction of the regional signal, and the
%   secular change over the GRACE era is dominated by degree 2 and the
%   polar regions.
% the environment first, then the preference setup_shAnalysis stores
% (SeriesFolder=), as the other real-data tests do (v5.23.4: this one read
% the environment only, so a stored preference did not enable it)
folder = getenv('SHX_SERIES_FOLDER');
if isempty(folder), folder = getpref('shAnalysis', 'SeriesFolder', ''); end
assumeNotEmpty(testCase, folder, ...
    ['set SHX_SERIES_FOLDER (or setup_shAnalysis(SeriesFolder=...)) to ' ...
     'a folder of monthly .gfc files to run this']);
assumeTrue(testCase, isfolder(folder), ...
    sprintf('SHX_SERIES_FOLDER is not a folder: %s', folder));

ts = shSeries.fromFolder(folder);
assumeGreaterThan(testCase, ts.nEpochs, 24, ...
    'a trend needs at least two years of solutions');

clim = ts.climatology(ARCorrect = true);
trend = clim.trend();

% C00 carries total mass. GSM solutions have it removed or fixed, so its
% TREND must be zero to numerical precision - if it is not, a correction
% has injected mass into the series.
verifyEqual(testCase, trend.C(1, 1), 0, 'AbsTol', 1e-13, ...
    'the total-mass trend must vanish in a GSM series');

% the secular signal must be a real signal, not noise: the degree
% amplitude at low degrees has to exceed the high-degree floor
spec = shLowLevel.shDegreeRMS(trend.C, trend.S);
low = mean(spec.degAmplitude(3:6));       % degrees 2..5
high = mean(spec.degAmplitude(end-4:end));
verifyGreaterThan(testCase, low / high, 5, ...
    'the trend field should be dominated by low degrees');

% audit F-2: everything above survives a SIGN-FLIPPED trend (executed and
% demonstrated on the real 257-month ITSG series). The published fact
% this test is named after is that Greenland LOSES mass over the GRACE
% era - so synthesize the trend over Greenland and require the loss.
d = shxTestDataDir();
kn = readmatrix(fullfile(d, 'loadLoveNumbers_Gegout97.txt'), ...
    FileType = 'text', NumHeaderLines = 2);
gLat = (61:2:83)'; gLon = (288:2:340)';   % Greenland box, lon in [0,360)
G = shLowLevel.shSynthesis(trend.C, trend.S, ts.GM, ts.R, gLat, gLon, ...
    'Quantity', 'ewh', 'kn', kn, 'Nmin', 2);
mG = mean(G(:), 'omitnan');               % m/yr EWH over the box
verifyLessThan(testCase, mG, -0.01, ...
    'Greenland must LOSE mass: a sign-flipped trend fails here');
verifyGreaterThan(testCase, mG, -1.0, ...
    'and by a physically plausible amount');
end

% ------------------------------------------------ WP5 5a: Earth rotation
function testExcitationAgainstESMGFZ(testCase)
%TESTEXCITATIONAGAINSTESMGFZ GRACE's Earth-rotation excitation against an
%   independent model: ts.excitation on a GSM series, with the TN-14 C20,
%   against the ESMGFZ hydrological (HAM) plus barystatic sea-level (SLAM)
%   mass terms averaged over each GRACE month. A GSM series has the
%   atmosphere and the ocean removed, so these are what it should see -
%   apart from the ice sheets and GIA, which the model lacks and which put
%   opposite trends into the raw series, so both are detrended. What must
%   hold is the SIGN of every term: a flipped frame for chi2, or a wrong
%   sign in dLOD, turns its correlation negative. Measured on COST-G
%   RL02.1 (255 months, 2002-2026) with the Gegout97 k2' and TN-14
%   version 3: 0.343 (chi1), 0.583 (chi2), 0.690 (dLOD); the bound 0.2
%   asserts the sign and leaves room for another product. Opt-in, as the
%   other real-data tests: set SHX_SERIES_FOLDER and
%   SHX_EARTHROTATION_FOLDER, or the SeriesFolder and EarthRotationFolder
%   preferences.
sf = getenv('SHX_SERIES_FOLDER');
if isempty(sf), sf = getpref('shAnalysis', 'SeriesFolder', ''); end
ef = getenv('SHX_EARTHROTATION_FOLDER');
if isempty(ef), ef = getpref('shAnalysis', 'EarthRotationFolder', ''); end
assumeTrue(testCase, isfolder(sf) && isfolder(fullfile(ef, 'ESMGFZ', 'HAM')) ...
    && isfolder(fullfile(ef, 'ESMGFZ', 'SLAM')), ['set SHX_SERIES_FOLDER ' ...
    '(a GSM series of monthly .gfc files) and SHX_EARTHROTATION_FOLDER ' ...
    '(a folder holding ESMGFZ/HAM and ESMGFZ/SLAM)']);
d = shxTestDataDir();
kn = readmatrix(fullfile(d, 'loadLoveNumbers_Gegout97.txt'), ...
    FileType = 'text', NumHeaderLines = 2);
tn14 = fullfile(d, 'TN-14_C30_C20_SLR_GSFC.txt');
ts = coveredByTN14(testCase, shSeries.read(fullfile(sf, '*.gfc')), tn14);
[tbl, info] = ts.excitation(kn = kn, TN14 = tn14);
[mjdH, ham] = readEAMFolder(fullfile(ef, 'ESMGFZ', 'HAM'), 6);
[mjdS, slam] = readEAMFolder(fullfile(ef, 'ESMGFZ', 'SLAM'), 3);
[mjd, ia, ib] = intersect(round(2 * mjdH), round(2 * mjdS));
mjd = mjd / 2;
mass = ham(ia, 1:3) + slam(ib, 1:3);
T = ts.nEpochs;
model = nan(T, 3);
for k = 1:T
    win = monthWindow(ts.names(k), ts.epochs(k));
    in = mjd >= win(1) & mjd < win(2);
    if any(in)
        model(k, :) = mean(mass(in, :), 1);
    end
end
ok = all(isfinite(model), 2);
verifyGreaterThan(testCase, nnz(ok), 24, 'too few months overlap the model');
mas = 180 / pi * 3600e3;
g = [tbl.chi1, tbl.chi2, tbl.dLOD];
m = [model(:, 1:2) * mas, model(:, 3) * info.lodScale];
names = ["chi1", "chi2", "dLOD"];
t = ts.epochs(ok);
for j = 1:3
    a = detrendOn(t, g(ok, j));
    b = detrendOn(t, m(ok, j));
    r = (a' * b) / sqrt((a' * a) * (b' * b));
    verifyGreaterThan(testCase, r, 0.2, sprintf( ...
        '%s: detrended correlation with ESMGFZ HAM+SLAM is %.3f', names(j), r));
end
end

function ts = coveredByTN14(testCase, ts, file)
%COVEREDBYTN14 The months of TS that the TN-14 table FILE covers, by
%   applyTN14's own rule: an entry within its default Tolerance, 0.05 yr.
%   A series on disk grows every month, and the pinned table's last
%   entry (fixtures-2026-08) is centred at 2026.45; without this a test
%   errors on the months after it (shCoefficients:applyTN14:epochNotInTable)
%   instead of measuring the ones it can. The dropped months are logged.
tn = shLowLevel.readTN14(file);
keep = arrayfun(@(e) min(abs(tn.epoch - e)) <= 0.05, ts.epochs(:)');
if ~all(keep)
    testCase.log(1, sprintf('%d of %d months lie outside the TN-14 table (it ends at %.2f) and are left out', ...
        nnz(~keep), numel(keep), max(tn.epoch)));
end
ts = ts.select(keep);
end

function y = detrendOn(t, x)
%DETRENDON x minus its least-squares line in t.
X = [ones(numel(t), 1), t(:) - mean(t)];
y = x - X * (X \ x);
end

function win = monthWindow(name, epoch)
%MONTHWINDOW the MJD span of a GRACE month from its file name
%   (yyyyddd-yyyyddd), or 30 days centred on the epoch.
tok = regexp(char(name), '(\d{4})(\d{3})-(\d{4})(\d{3})', 'tokens', 'once');
if numel(tok) == 4
    v = str2double(tok);
    win = [datenum(v(1), 1, v(2)), datenum(v(3), 1, v(4)) + 1] - 678942;
else
    y = floor(epoch);
    mid = datenum(y, 1, 1) + (epoch - y) * ...
        (datenum(y + 1, 1, 1) - datenum(y, 1, 1));
    win = [mid - 15, mid + 15] - 678942;
end
end

function [mjd, x] = readEAMFolder(folder, ncol)
%READEAMFOLDER every yearly ESMGFZ file in FOLDER: the MJD and the NCOL
%   values that follow YYYY MM DD HH MJD on each data line.
f = dir(fullfile(folder, 'ESMGFZ_*_2*.asc'));
f = f(~contains({f.name}, '_mean_'));
mjd = [];
x = [];
for k = 1:numel(f)
    L = splitlines(string(fileread(fullfile(f(k).folder, f(k).name))));
    isData = ~cellfun(@isempty, regexp(cellstr(L), ...
        '^\s*\d{4}\s+\d{2}\s+\d{2}\s+\d{2}\s+\d', 'once'));
    v = sscanf(char(strjoin(L(isData), " ")), '%f');
    v = reshape(v, 5 + ncol, []).';
    mjd = [mjd; v(:, 5)]; %#ok<AGROW>
    x = [x; v(:, 6:end)]; %#ok<AGROW>
end
end

% ------------------------------------------------ WP5 5d: the gap series
function testBridgeGapsAgainstGRACE(testCase)
%TESTBRIDGEGAPSAGAINSTGRACE the gap fill on real data. GRACE months are
%   held out of a GSM series (TN-14 applied first, the documented order),
%   bridged back from an HLSST series and compared with the GRACE values
%   they replace, at 750 km over degrees 3-60. Measured on COST-G RL02.1
%   and the Kalman-filtered QuantumFrontiers HLSST_SLR_COMB2023s, every
%   sixth of the 209 months inside the HLSST span held out: the fill's
%   error is 0.381 of the GRACE signal, and the actual error 1.032 times
%   the predicted sigma. The bounds, 0.5 and [0.8, 1.25], assert a fill
%   well inside the signal and a sigma that neither hides nor inflates the
%   error, with room for another GSM series. Opt-in: set SHX_SERIES_FOLDER
%   and SHX_BRIDGE_FOLDER (the monthly files of an HLSST series), or the
%   SeriesFolder and BridgeFolder preferences.
sf = getenv('SHX_SERIES_FOLDER');
if isempty(sf), sf = getpref('shAnalysis', 'SeriesFolder', ''); end
bf = getenv('SHX_BRIDGE_FOLDER');
if isempty(bf), bf = getpref('shAnalysis', 'BridgeFolder', ''); end
assumeTrue(testCase, isfolder(sf) && isfolder(bf), ['set SHX_SERIES_FOLDER ' ...
    '(a GSM series of monthly .gfc files) and SHX_BRIDGE_FOLDER (the ' ...
    'monthly files of an HLSST series)']);
tn14 = fullfile(shxTestDataDir(), 'TN-14_C30_C20_SLR_GSFC.txt');
gr = coveredByTN14(testCase, shSeries.read(fullfile(sf, '*.gfc')), tn14);
gr = gr.applyTN14(tn14);
hl = shSeries.read(fullfile(bf, '*.gfc'));
% the full run: every filled month is one GRACE lacks, and it is flagged
[ts, info] = shLowLevel.bridgeGaps(gr, hl);
verifyGreaterThan(testCase, nnz(info.bridged), 0);
verifyTrue(testCase, all(startsWith(ts.names(info.bridged), "bridge:")));
d = min(abs(ts.epochs(info.bridged) - gr.epochs.'), [], 2);
verifyTrue(testCase, all(d >= 0.05), 'a filled month duplicates a GRACE month');
% held out and bridged back
inHL = gr.epochs > hl.epochs(1) & gr.epochs < hl.epochs(end);
idx = find(inHL);
out = idx(3:6:end);
keep = true(1, gr.nEpochs);
keep(out) = false;
[ts2, info2] = shLowLevel.bridgeGaps(gr.select(keep), hl);
nmax = ts2.nmax;
ref = gr;
if ref.nmax > nmax, ref = ref.truncate(nmax); end
ref = ref.gaussian(750);
nn = (0:nmax)';
E = zeros(nmax + 1, 1);
cnt = 0;
for j = 1:numel(out)
    [dd, k] = min(abs(ts2.epochs - ref.epochs(out(j))));
    if dd < 0.05 && info2.bridged(k)
        E = E + sum((ts2.Cs(:, :, k) - ref.Cs(:, :, out(j))).^2 + ...
            (ts2.Ss(:, :, k) - ref.Ss(:, :, out(j))).^2, 2);
        cnt = cnt + 1;
    end
end
verifyEqual(testCase, cnt, numel(out), 'every held-out month must come back');
A = ref.Cs - mean(ref.Cs, 3);
B = ref.Ss - mean(ref.Ss, 3);
w = 2 * nn + 1;
errV = E ./ (w * cnt);
sigV = squeeze(sum(sum(A.^2 + B.^2, 2), 3)) ./ (w * ref.nEpochs);
k = 4:nmax + 1;
ratio = sqrt(sum(w(k) .* errV(k)) / sum(w(k) .* sigV(k)));
honesty = sqrt(sum(w(k) .* errV(k)) / sum(w(k) .* info2.sigma(k).^2));
verifyLessThan(testCase, ratio, 0.5, sprintf( ...
    'the fill error is %.3f of the GRACE signal', ratio));
verifyGreaterThan(testCase, honesty, 0.8, sprintf( ...
    'actual over predicted sigma is %.3f', honesty));
verifyLessThan(testCase, honesty, 1.25, sprintf( ...
    'actual over predicted sigma is %.3f', honesty));
end
