function tests = testCorrectness
%TESTCORRECTNESS Correctness suite: class API vs validated cores, physics.
%   runtests('testCorrectness')  (run from tests/, or use runAllTests)
%   Claude (Fable 5), 2026-08-07.
%   Developed by Matthias Weigelt with the help of Claude (Fable 5).
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
here = fileparts(mfilename('fullpath'));
root = fileparts(here);
addpath(root);
testCase.TestData.dataDir = shxTestDataDir();
shLowLevel.legendreCached('clear');
end

% ------------------------------------------------------------------- read
function testReadMatchesCompat(testCase)
f = fullfile(testCase.TestData.dataDir, 'test_static.gfc');
g = shCoefficients.read(f);
m = shLowLevel.shReadGFC(f);
verifyEqual(testCase, g.C, m.C);
verifyEqual(testCase, g.S, m.S);
verifyEqual(testCase, g.GM, m.GM);
verifyEqual(testCase, g.R, m.R);
verifyEqual(testCase, g.sigmaC, m.sigmaC);
end

function testFilenameParsing(testCase)
meta = shLowLevel.parseGraceFilename('GSM-2_2024032-2024060_GRFO_UTCSR_BA01_0600.gfc');
verifyEqual(testCase, meta.productType, "GSM");
verifyGreaterThan(testCase, meta.epoch, 2024.0);
verifyLessThan(testCase, meta.epoch, 2024.25);
meta2 = shLowLevel.parseGraceFilename('GAD-2_2024032-2024060_GRFO_UTCSR_BA01_0600.gfc.gz');
verifyEqual(testCase, meta2.productType, "GAD");
verifyEqual(testCase, meta2.epoch, meta.epoch, 'AbsTol', 1e-12);
meta3 = shLowLevel.parseGraceFilename('some_random_model.gfc');
verifyEqual(testCase, meta3.productType, "unknown");
verifyTrue(testCase, isnan(meta3.epoch));
end

% ------------------------------------------------------------- arithmetic
function testArithmeticAndSigmaRSS(testCase)
rng(1); L = 8;
[gA, gB] = randomPair(L);
d = gB - gA;
verifyEqual(testCase, d.C, gB.C - gA.C, 'AbsTol', 0);
verifyEqual(testCase, d.sigmaC, sqrt(gA.sigmaC.^2 + gB.sigmaC.^2), 'RelTol', 1e-14);
verifyEqual(testCase, d.productType, "difference");
s = gA + gB;
verifyEqual(testCase, s.C, gA.C + gB.C, 'AbsTol', 0);
g2 = 2.5 * gA;
verifyEqual(testCase, g2.C, 2.5 * gA.C, 'AbsTol', 0);
verifyEqual(testCase, g2.sigmaC, 2.5 * gA.sigmaC, 'RelTol', 1e-14);
% v2.5.1: elementwise .* with a per-coefficient weight matrix
W = 0.5 * ones(size(gA.C)); W(3, 1) = 2;
gW = W .* gA;
verifyEqual(testCase, gW.C, W .* gA.C, 'AbsTol', 0);
verifyEqual(testCase, gW.S, W .* gA.S, 'AbsTol', 0);
verifyEqual(testCase, gW.sigmaC, abs(W) .* gA.sigmaC, 'AbsTol', 0);
end

function testGSMPlusGAXType(testCase)
rng(2);
[gsm, gad] = randomPair(6);
gsm = setType(gsm, "GSM"); gad = setType(gad, "GAD");
out = gsm + gad;
verifyEqual(testCase, out.productType, "GSM+GAD");
verifyEqual(testCase, out.C, gsm.C + gad.C, 'AbsTol', 0);
end

% -------------------------------------------------- filtering vs v1 cores
% -------------------------------------------------------------- synthesis
function testQuadratureIdentity(testCase)
idx = shLowLevel.shIndex(15);
[Y, w] = shLowLevel.synthesisMatrix(idx);
verifyLessThan(testCase, norm(Y' * (w .* Y) - eye(idx.P), 'fro'), 1e-10);
end

% ------------------------------------------------------- series statistics
function testMeanField(testCase)
rng(6); L = 6; T = 24;
ts = randomSeries(L, T);
m = ts.mean;
verifyEqual(testCase, m.C, mean(ts.Cs, 3), 'AbsTol', 0);
verifyEqual(testCase, m.sigmaC, std(ts.Cs, 0, 3)/sqrt(T), 'RelTol', 1e-14);
d = ts - m;
verifyEqual(testCase, mean(d.Cs, 3), zeros(L+1), 'AbsTol', 1e-14);
end

function testClimatologyRecovery(testCase)
rng(7); L = 6; T = 96;
t = (0:T-1)'/12 + 2010;
t0 = mean(t);
n1 = L + 1;
bias = randn(n1); trend = 0.1*randn(n1); ca = randn(n1); sa = randn(n1);
csm = 0.5*randn(n1); ssm = 0.5*randn(n1);
bias = tril(bias); trend = tril(trend); ca = tril(ca); sa = tril(sa);
csm = tril(csm); ssm = tril(ssm);
Cs = zeros(n1, n1, T); Ss = zeros(n1, n1, T);
for k = 1:T
    dt = t(k) - t0;
    Cs(:,:,k) = bias + trend*dt + ca*cos(2*pi*dt) + sa*sin(2*pi*dt) ...
        + csm*cos(4*pi*dt) + ssm*sin(4*pi*dt) + 1e-9*tril(randn(n1));
    Ss(:,:,k) = 1e-9*tril(randn(n1), -1);
end
ts = shSeries(Cs, Ss = Ss, Epochs = t);
[clim, resid] = ts.climatology(T0 = t0);
verifyEqual(testCase, clim.biasC,  bias,  'AbsTol', 1e-7);
verifyEqual(testCase, clim.trendC, trend, 'AbsTol', 1e-7);
verifyEqual(testCase, clim.cosAnnC, ca,   'AbsTol', 1e-7);
verifyEqual(testCase, clim.sinAnnC, sa,   'AbsTol', 1e-7);
verifyEqual(testCase, clim.cosSemiC, csm, 'AbsTol', 1e-7);
% eval reproduces the series
g = clim.eval(t(10));
verifyEqual(testCase, g.C, Cs(:,:,10), 'AbsTol', 1e-6);
% residuals at noise level
verifyLessThan(testCase, max(abs(resid.Cs(:))), 1e-7);
% robust fit survives an outlier month
Cs(:,:,5) = Cs(:,:,5) + 100;
tsO = shSeries(Cs, Ss = Ss, Epochs = t);
climR = tsO.climatology(T0 = t0, Robust = true);
verifyEqual(testCase, climR.trendC, trend, 'AbsTol', 1e-4);
end

function testGAXRestore(testCase)
rng(8); L = 6; T = 12;
gsm = randomSeries(L, T);
gad = randomSeries(L, T);
gad = shSeries(gad.Cs, Ss = gad.Ss, ...
    Epochs = gsm.epochs + 0.01, ProductType = "GAD");   % slight offset, within tol
gsm = shSeries(gsm.Cs, Ss = gsm.Ss, Epochs = gsm.epochs, ProductType = "GSM");
out = gsm.restore(gad);
verifyEqual(testCase, out.Cs, gsm.Cs + gad.Cs, 'AbsTol', 0);
verifyEqual(testCase, out.productType, "GSM+GAD");
end

% -------------------------------------------------------------- tvANS chain
function testTvANSPipelineAndDeconvolution(testCase)
rng(9); L = 10; T = 48;
t = (0:T-1)'/12 + 2018;
idx = shLowLevel.shIndex(L);
% basin kernels
B = zeros(idx.P, 2);
B(:,1) = exp(-((idx.n - 4)/3).^2) .* shLowLevel.ylm(deg2rad(50),  deg2rad(10),  idx)' * 0.05;
B(:,2) = exp(-((idx.n - 4)/3).^2) .* shLowLevel.ylm(deg2rad(35),  deg2rad(60),  idx)' * 0.05;
cTrue = [1.5*sin(2*pi*t)'; 0.8*cos(2*pi*t + 0.7)'] + 0.3*randn(2, T);
Xtrue = B * cTrue;
% striping noise (per-order, same-parity correlated)
Xn = zeros(idx.P, T);
for m = 0:L
    for cs = 0:double(m>0)
        for par = 0:1
            nn = max(m,2):L; nn = nn(mod(nn,2)==par);
            rows = squeeze(idx.pos(nn+1, m+1, cs+1)); rows = rows(rows>0);
            if isempty(rows), continue; end
            sd = 1e-3 + 0.05*(idx.n(rows)/L).^6;
            Cb = 0.9.^(abs(idx.n(rows) - idx.n(rows)')/2) .* (sd*sd');
            Xn(rows,:) = chol(Cb + 1e-12*eye(numel(rows)), 'lower') * randn(numel(rows), T);
        end
    end
end
X = Xtrue + Xn;
% pack into an shSeries
n1 = L + 1;
Cs = zeros(n1,n1,T); Ss = zeros(n1,n1,T);
for k = 1:T
    [Cs(:,:,k), Ss(:,:,k)] = shLowLevel.csFromVec(X(:,k), idx);
end
ts = shSeries(Cs, Ss = Ss, Epochs = t);
[tsF, op] = ts.filter("tvANS");
% high-degree noise strongly damped
XfChk = zeros(idx.P, T);
for k = 1:T
    XfChk(:,k) = shLowLevel.vecFromCS(tsF.Cs(:,:,k), tsF.Ss(:,:,k), idx);
end
hi = idx.n >= 8;
r0 = mean(mean((X(hi,:)  - Xtrue(hi,:)).^2));
r1 = mean(mean((XfChk(hi,:) - Xtrue(hi,:)).^2));
% Threshold from the ORACLE Wiener bound for this construction: the basin
% kernels exp(-((n-4)/3)^2) put real signal at n=8-9, so the per-coefficient
% oracle MSE ratio s_sig/(s_sig+s_noise) averages ~0.09 with p90 ~ 0.34
% (numpy MC) - a flat 0.05 is unattainable even for the optimal filter.
% Measured 0.125 is oracle-class; 0.3 keeps the check meaningful (>= 3x
% damping) with margin.
verifyLessThan(testCase, r1/r0, 0.3);
% at n = 10 the noise dominates; the data-driven chain measures 0.125
% (deterministic under rng(9)), above the ~0.01 oracle because the
% empirical per-order noise blocks are contaminated by the stochastic
% basin signal at n=8-9 through the same-parity striping correlation - a
% known, documented empirical-N limitation, not a regression. 0.2 keeps
% a meaningful >= 5x damping assertion with margin across MATLAB builds.
h10 = idx.n == 10;
r010 = mean(mean((X(h10,:)  - Xtrue(h10,:)).^2));
r110 = mean(mean((XfChk(h10,:) - Xtrue(h10,:)).^2));
verifyLessThan(testCase, r110/r010, 0.2);
% deconvolved basin averages beat naive
avgTrue = (B' * Xtrue) ./ diag(B'*B);
[avgHat, out] = tsF.basinAverage(B, Deconvolve = true, Op = op);
rmsD = sqrt(mean((avgHat - avgTrue).^2, 2));
rmsN = sqrt(mean((out.avgNaive - avgTrue).^2, 2));
verifyLessThanOrEqual(testCase, max(rmsD ./ rmsN), 1.0);
% constrained variant reproduces the constraint functional exactly
Ac = exp(-idx.n/4) .* randn(idx.P, 1);
[~, opC] = ts.filter("tvANS", Constraints = Ac);
err = norm(Ac'*opC.Xfres - Ac'*opC.Xres) / norm(Ac'*opC.Xres);
verifyLessThan(testCase, err, 1e-8);
end

function testEigTrickEquivalence(testCase)
%TESTEIGTRICKEQUIVALENCE The eig trick AS IMPLEMENTED, not in the abstract.
%   Audit F-4: the previous version proved the Woodbury/eig identity on
%   plain MATLAB linear algebra and called ZERO toolbox functions - any
%   toolbox mutation left it green. This version reconstructs the filter
%   from the op struct tvANSFilter actually returns and requires it to
%   reproduce the returned Xf: the identity is now pinned to the code.
rng(10);
idx = shLowLevel.shIndex(6, Nmin = 2);
T = 24; t = 2020 + (0:T-1)'/12;
X = 1e-9 * randn(idx.P, T) + 5e-9 * cos(2*pi*t') .* randn(idx.P, 1);
[Xf, op] = shLowLevel.tvANSFilter(X, t, idx, Blocks = 'off', ...
    NoiseCov = eye(idx.P));
verifyEqual(testCase, string(op.layout), "full");
% generalized-eig contracts of the implementation
verifyLessThan(testCase, norm(op.Ut * op.V - eye(idx.P), 'fro'), 1e-8);
verifyTrue(testCase, all(op.lam >= -1e-12));
% reconstruct: Xf_t = model_t + V * diag(lam/(lam+s_t)) * Ut * Xres_t
Xr = op.model;
for tt = 1:T
    g = op.lam ./ (op.lam + op.s(tt));
    Xr(:, tt) = Xr(:, tt) + op.V * (g .* (op.Ut * op.Xres(:, tt)));
end
verifyEqual(testCase, Xr, Xf, 'AbsTol', 1e-12 * max(abs(Xf(:))), ...
    'the op struct must reconstruct the filter output exactly');
end

% ----------------------------------------------------------------- I/O etc
function testWriteReadRoundtrip(testCase)
rng(11); L = 12;
g = randomField(L);
f = [tempname '.gfc'];
cl = onCleanup(@() delete(f));
g.write(f);
g2 = shCoefficients.read(f);
verifyEqual(testCase, g2.C, g.C, 'RelTol', 1e-13, 'AbsTol', 1e-18);
verifyEqual(testCase, g2.S, g.S, 'RelTol', 1e-13, 'AbsTol', 1e-18);
verifyEqual(testCase, g2.GM, g.GM, 'RelTol', 1e-10);
end

function testVecRoundtrip(testCase)
rng(12); L = 9;
g = randomField(L);
idx = shLowLevel.shIndex(L);
x = g.vec(idx);
g2 = shCoefficients.fromVec(x, idx, g);
% below minDegree is zeroed by construction; compare the indexed part
verifyEqual(testCase, g2.vec(idx), x, 'AbsTol', 0);
end

function testTN14Apply(testCase)
f = writeSyntheticTN14();
cl = onCleanup(@() delete(f));
tn = shLowLevel.readTN14(f);
verifyEqual(testCase, numel(tn.epoch), 3);
verifyTrue(testCase, isnan(tn.C30(1)) && ~isnan(tn.C30(3)));
g = randomField(6);
g = setEpoch(g, tn.epoch(3));
g2 = g.applyTN14(tn);
verifyEqual(testCase, g2.C(3,1), tn.C20(3), 'AbsTol', 0);
verifyEqual(testCase, g2.C(4,1), tn.C30(3), 'AbsTol', 0);
g1 = setEpoch(g, tn.epoch(1));
g3 = g1.applyTN14(tn);                      % C30 is NaN there -> C20 only
verifyEqual(testCase, g3.C(3,1), tn.C20(1), 'AbsTol', 0);
verifyEqual(testCase, g3.C(4,1), g.C(4,1), 'AbsTol', 0);
end

% ---------------------------------------------------------------- helpers
function g = randomField(L)
n1 = L + 1;
C = tril(randn(n1)) ./ max(1, (0:L)'.^2);
S = tril(randn(n1), -1) ./ max(1, (0:L)'.^2);
S(:, 1) = 0;    % S_n0 has no meaning (sin(0*lon)=0): zero in synthesis,
                % unrecoverable in analysis - keep test fields physical
g = shCoefficients(C, S, SigmaC = 0.01*abs(tril(rand(n1)))+1e-6, ...
    SigmaS = 0.01*abs(tril(rand(n1),-1))+1e-6, Epoch = 2024.1);
end

function [gA, gB] = randomPair(L)
gA = randomField(L);
gB = randomField(L);
end

function ts = randomSeries(L, T)
n1 = L + 1;
Cs = zeros(n1,n1,T); Ss = zeros(n1,n1,T);
for k = 1:T
    Cs(:,:,k) = tril(randn(n1));
    Ss(:,:,k) = tril(randn(n1), -1);
end
ts = shSeries(Cs, Ss = Ss, Epochs = 2015 + (0:T-1)'/12);
end

function g2 = setType(g, t)
g2 = shCoefficients(g.C, g.S, SigmaC = g.sigmaC, SigmaS = g.sigmaS, ...
    GM = g.GM, R = g.R, Epoch = g.epoch, ProductType = t);
end

function g2 = setEpoch(g, ep)
g2 = shCoefficients(g.C, g.S, SigmaC = g.sigmaC, SigmaS = g.sigmaS, ...
    GM = g.GM, R = g.R, Epoch = ep, ProductType = g.productType);
end

function f = writeSyntheticTN14()
f = [tempname '.txt'];
fid = fopen(f, 'w');
fprintf(fid, 'TITLE: synthetic TN-14 for unit tests\n');
fprintf(fid, 'some header line without numbers\n');
fprintf(fid, 'PRODUCT: C20/C30 replacement\n');
% MJDb yrb C20 dC20e10 sigC20e10 C30 dC30e10 sigC30e10 MJDe yre
fprintf(fid, '58119 2018.000 -4.841e-04 1.0 0.5 NaN NaN NaN 58149 2018.082\n');
fprintf(fid, '58149 2018.082 -4.842e-04 1.1 0.5 NaN NaN NaN 58180 2018.163\n');
fprintf(fid, '58180 2018.163 -4.843e-04 1.2 0.5 -9.5e-07 2.0 1.0 58208 2018.240\n');
fclose(fid);
end

% =================================================================== v2.1
function testFFTSynthesisMatchesDirect(testCase) %#ok<INUSD>
% FFT-along-longitude path must equal the direct trig product on a uniform
% full-circle grid (Python-validated to 2.9e-13)
rng(11);
L = 24;
C = tril(randn(L+1)); S = tril(randn(L+1), -1);
lat = -87.5:5:87.5; lon = 0:5:355;
gD = shLowLevel.shSynthesis(C, S, 3.986004415e14, 6378136.3, lat, lon, ...
    'Quantity', 'geoid', 'Method', 'direct');
gF = shLowLevel.shSynthesis(C, S, 3.986004415e14, 6378136.3, lat, lon, ...
    'Quantity', 'geoid', 'Method', 'fft');
verifyEqual(testCase, gF, gD, 'AbsTol', 1e-9 * max(abs(gD(:))));
end

function testFFTSynthesisNonZeroStartLon(testCase)
% the FFT path must honor a non-zero first longitude via the phase factor
rng(12);
L = 10; C = tril(randn(L+1)); S = tril(randn(L+1), -1);
lat = 10; lon0 = 17.5; lon = lon0 + (0:359);
gD = shLowLevel.shSynthesis(C, S, 1, 1, lat, lon, 'Method', 'direct');
gF = shLowLevel.shSynthesis(C, S, 1, 1, lat, lon, 'Method', 'fft');
verifyEqual(testCase, gF, gD, 'AbsTol', 1e-10 * max(abs(gD(:))));
end

function testScaledLegendreSumRule(testCase)
% addition theorem sum_m Pbar_nm^2 = 2n+1: the sharpest cheap check of the
% scaled recursion; holds to 3e-11 at n=2190 even at lat=89.99 deg
for latDeg = [0 45 89 89.99]
    P = shLowLevel.legendreALF(2190, deg2rad(latDeg));
    for n = [60 600 2190]
        s = sum(P(n+1, 1:n+1).^2);
        verifyEqual(testCase, s / (2*n+1), 1, 'RelTol', 1e-9, ...
            sprintf('sum rule failed at n=%d, lat=%g', n, latDeg));
    end
end
verifyTrue(testCase, all(isfinite(P(:))));
end

function testAnalysisRingRoundTrip(testCase)
% band-limited synthesis -> rings analysis must be exact (8.7e-15 in Python)
rng(13);
L = 12;
C0 = tril(randn(L+1)); S0 = tril(randn(L+1), -1); S0(:,1) = 0;
lat = linspace(-84, 84, 2*L+4); lon = (0:2*L+3) * 360/(2*L+4);
g = shLowLevel.shSynthesis(C0, S0, 1, 1, lat, lon, 'Method', 'direct');
[C, S, info] = shLowLevel.shAnalysisGrid(g, lat, lon, L, GM = 1, R = 1);
verifyEqual(testCase, C, C0, 'AbsTol', 1e-10);
verifyEqual(testCase, S, S0, 'AbsTol', 1e-10);
verifyEqual(testCase, info.method, 'rings');
verifyLessThan(testCase, info.residRMS, 1e-10);
end

function testAnalysisScatteredRoundTrip(testCase)
% scattered least squares: exact for sufficient random sampling
rng(14);
L = 8;
C0 = tril(randn(L+1)); S0 = tril(randn(L+1), -1); S0(:,1) = 0;
Np = 500;
latp = asind(2*rand(Np,1) - 1); lonp = 360*rand(Np,1);
f = zeros(Np, 1);
for k = 1:Np
    f(k) = shLowLevel.shSynthesis(C0, S0, 1, 1, latp(k), lonp(k), 'Method', 'direct');
end
[C, S, info] = shLowLevel.shAnalysisGrid(f, latp, lonp, L, GM = 1, R = 1);
verifyEqual(testCase, C, C0, 'AbsTol', 1e-9);
verifyEqual(testCase, S, S0, 'AbsTol', 1e-9);
verifyEqual(testCase, info.method, 'ls');
end

function testAnalysisQuantityInversion(testCase)
% analysis of a gravity_anomaly grid recovers Stokes coefficients with
% degrees 0/1 correctly reported unobservable
rng(15);
L = 10; GM = 3.986004415e14; R = 6378136.3;
C0 = tril(randn(L+1)) * 1e-8; S0 = tril(randn(L+1), -1) * 1e-8; S0(:,1) = 0;
C0(1:2, :) = 0; S0(1:2, :) = 0;                 % nothing below degree 2
lat = linspace(-85, 85, 2*L+6); lon = (0:2*L+5) * 360/(2*L+6);
g = shLowLevel.shSynthesis(C0, S0, GM, R, lat, lon, 'Quantity', 'gravity_anomaly');
[C, S, info] = shLowLevel.shAnalysisGrid(g, lat, lon, L, ...
    Quantity = 'gravity_anomaly', GM = GM, R = R);
verifyEqual(testCase, C, C0, 'AbsTol', 1e-16);
verifyEqual(testCase, S, S0, 'AbsTol', 1e-16);
% gravity_anomaly kernel (n-1): only n=1 carries no information
% (n=0 has factor -1, observable) - matches the physics
verifyTrue(testCase, isequal(info.unobservedDegrees, 1));
end

function testAnalysisKaulaRegularization(testCase)
% under-determined sampling: plain LS must refuse, Kaula must stabilize
rng(16);
L = 8;
Np = 40;                                        % << (L+1)^2 = 81 unknowns
latp = asind(2*rand(Np,1) - 1); lonp = 360*rand(Np,1);
f = randn(Np, 1) * 1e-8;
verifyError(testCase, @() shLowLevel.shAnalysisGrid(f, latp, lonp, L), ...
    'shLowLevel:shAnalysisGrid:rankDeficient');
[C, S] = shLowLevel.shAnalysisGrid(f, latp, lonp, L, Kaula = 1);
verifyTrue(testCase, all(isfinite(C(:))) && all(isfinite(S(:))));
end

function testTvANSBlocksMatchFull(testCase)
% block-diagonal path must be IDENTICAL to the full eigendecomposition
rng(17);
Lmax = 8; T = 30;
idx = shLowLevel.shIndex(Lmax);
t = 2002 + (0:T-1)'/12;
X = randn(idx.P, T) * 1e-9;
[XfF, ~, infoF] = shLowLevel.tvANSFilter(X, t, idx, Blocks = 'off');
[XfB, opB, infoB] = shLowLevel.tvANSFilter(X, t, idx, Blocks = 'on');
verifyEqual(testCase, XfB, XfF, 'AbsTol', 1e-12 * max(abs(XfF(:))));
verifyEqual(testCase, infoB.sigmaXfres, infoF.sigmaXfres, ...
    'AbsTol', 1e-10 * max(infoF.sigmaXfres(:)));
verifyEqual(testCase, opB.layout, 'blocks');
end

function testPosteriorSigmaAgainstDirect(testCase)
% (V.^2)*(s*lam/(lam+s)) must equal diag((I-W)S) formed explicitly
rng(18);
P = 40;
A = randn(P); S = A*A' + P*eye(P);
B = randn(P); N = B*B' + P*eye(P);
[U, D] = eig(S, N, 'chol');
lam = diag(D); Ut = U'; V = inv(Ut); %#ok<MINV>
s = 0.8;
W = S / (S + s*N);
direct = diag((eye(P) - W) * S);
formula = (V.^2) * (s*lam ./ (lam + s));
verifyEqual(testCase, formula, direct, 'AbsTol', 1e-10 * max(abs(direct)));
end

function testConstrainedPosteriorSigmaExact(testCase)
% v2.5: with hard constraints the posterior is the exact diagonal of
%   (W-I)S(W-I)' + s*W*N*W',  W = W0 + S*Ac*M^-1*Ac'*(I-W0)
% - verify the O(P^2 q) eig-basis formula against the brute-force
% covariance, and the constrained-direction identity
% Ac'*Cov*Ac = s*Ac'*N*Ac (the filter passes Ac'x unfiltered).
rng(21);
P = 40; q = 3;
A0 = randn(P); S = A0*A0'/P + 0.5*eye(P);
B0 = randn(P); N = B0*B0'/P + 0.3*eye(P);
Ac = randn(P, q);
s = 0.7;
[U, D] = eig(S, N, 'chol');
lam = max(real(diag(D)), 0); Ut = U'; V = inv(Ut); %#ok<MINV>
g = lam ./ (lam + s);
W0 = V * (g .* Ut);
M = Ac' * S * Ac;
W = W0 + S * Ac * (M \ (Ac' * (eye(P) - W0)));
Cov = (W - eye(P)) * S * (W - eye(P))' + s * (W * N * W');
dTrue = diag(Cov);
% the implemented formula (identical algebra to tvANSFilter v2.5)
Cq = Ac' * V; CqT = Cq';
Fq = (lam .* CqT) / M;  VF = V * Fq;  V2 = V.^2;
w1 = (1 - g).^2 .* lam;  w2 = g .* (1 - g);
A2q = Cq * (w1 .* CqT);  A4q = Cq * ((1 - g).^2 .* CqT);
d = V2 * (w1 + s * g.^2) ...
  - 2 * sum((V * (w1 .* CqT)) .* VF, 2) ...
  + sum((VF * A2q) .* VF, 2) ...
  + 2 * s * sum((V * (w2 .* CqT)) .* VF, 2) ...
  + s * sum((VF * A4q) .* VF, 2);
verifyEqual(testCase, d, dTrue, 'AbsTol', 1e-10 * max(abs(dTrue)));
verifyEqual(testCase, Ac' * Cov * Ac, s * (Ac' * N * Ac), ...
    'AbsTol', 1e-9 * norm(N));
% and the old unconstrained formula must NOT match (it underestimates)
dOld = V2 * (s * lam ./ (lam + s));
verifyLessThan(testCase, min(dOld ./ dTrue), 0.95);
end

function testConstrainedFilterSigmaStack(testCase)
% end-to-end: the sigma stacks of a CONSTRAINED tvANS run match the
% brute-force covariance diagonal built from the returned operator.
rng(22);
L = 6; T = 18;
idx = shLowLevel.shIndex(L, Nmin = 2); P = idx.P;
Cs = zeros(L+1, L+1, T); Ss = Cs;
mL = tril(true(L+1));
for t = 1:T
    Cs(:,:,t) = (mL .* randn(L+1)) * 1e-9;
    St = (mL .* randn(L+1)) * 1e-9; St(:, 1) = 0;
    Ss(:,:,t) = St;
end
ts = shSeries(Cs, Ss = Ss, Epochs = 2015 + (0:T-1)'/12);
Ac = exp(-idx.n / 3) .* randn(P, 2);
[tsF, op, info] = ts.filter("tvANS", Constraints = Ac, Blocks = "off");
verifyTrue(testCase, contains(info.sigmaNote, "exact"));
S = op.V * (op.lam .* op.V');           % S = V diag(lam) V'
N = op.V * op.V';                       % N = V V'
for t = [1, T]
    st = op.s(t);
    g = op.lam ./ (op.lam + st);
    W0 = op.V * (g .* op.Ut);
    W = W0 + S * Ac * (op.M \ (Ac' * (eye(P) - W0)));
    dTrue = diag((W - eye(P)) * S * (W - eye(P))' + st * (W * N * W'));
    verifyEqual(testCase, info.sigmaXfres(:, t).^2, dTrue, ...
        'AbsTol', 1e-9 * max(abs(dTrue)));
end
verifyEqual(testCase, tsF.nEpochs, T);
end

function testBasinSigmaAgainstDirect(testCase)
% cov(c) = s * A^-1 (Gv' g^2 Gv) A^-T  vs the explicit matrix expression
rng(19);
P = 30; K = 2;
A0 = randn(P); S = A0*A0' + P*eye(P);
B0 = randn(P); N = B0*B0' + P*eye(P);
B = randn(P, K);
[U, D] = eig(S, N, 'chol');
lam = diag(D); Ut = U'; V = inv(Ut); %#ok<MINV>
s = 1.3;
g = lam ./ (lam + s);
W = S / (S + s*N);
A = B' * W * B;
covDirect = s * (A \ (B' * W * N * W' * B)) / A';
Gv = V' * B;
covFormula = s * (A \ (Gv' * ((g.^2) .* Gv))) / A';
verifyEqual(testCase, covFormula, covDirect, ...
    'AbsTol', 1e-9 * max(abs(covDirect(:))));
end

function testBasinSigmaIncludesDeterministic(testCase)
% v2.5: out.sigma of the deconvolution carries the OLS parameter
% uncertainty of the restored deterministic part. Non-circular check:
% rebuild the residual-noise sigma from the DIRECT operator matrices
% (full layout), add the leverage term from independently recomputed
% fit quantities, and match out.sigma. Plus the hat-matrix trace
% identity sum(h_t) = #parameters.
rng(23);
L = 6; T = 20; K = 2;
idx = shLowLevel.shIndex(L, Nmin = 2); P = idx.P;
Cs = zeros(L+1, L+1, T); Ss = Cs;
mL = tril(true(L+1));
tY = 2012 + (0:T-1)'/12;
for t = 1:T
    Cs(:,:,t) = (mL .* randn(L+1)) * 1e-9 + ...
        (mL * 2e-9) * cos(2*pi*tY(t));         % strong seasonal model
    St = (mL .* randn(L+1)) * 1e-9; St(:, 1) = 0;
    Ss(:,:,t) = St;
end
ts = shSeries(Cs, Ss = Ss, Epochs = tY);
B = randn(P, K);
[~, op] = ts.filter("tvANS", Blocks = "off");
[~, out] = shLowLevel.basinDeconvolve(B, op);
% leverage recomputed independently from the same fit call
X = zeros(idx.P, T);
for t = 1:T
    X(:, t) = shLowLevel.vecFromCS(Cs(:,:,t), Ss(:,:,t), idx);
end
[~, ~, ~, Afit, ~, resVar] = shLowLevel.fitDeterministicModel(X, tY);
h = sum((Afit / (Afit' * Afit)) .* Afit, 2)';
verifyEqual(testCase, op.detLeverage, h, 'AbsTol', 1e-12);
verifyEqual(testCase, sum(h), size(Afit, 2), 'RelTol', 1e-10);
verifyEqual(testCase, op.detResVar, resVar(:), 'AbsTol', 1e-15);
% direct residual-noise sigma from explicit matrices
S = op.V * (op.lam .* op.V'); N = op.V * op.V';
BtB = B' * B; dB = diag(BtB);
varDet = ((B.^2)' * op.detResVar) * h;           % K x T
for t = [1, T]
    st = op.s(t);
    W = S / (S + st * N);
    A = B' * W * B;
    Q = st * (B' * (W * N * W') * B);
    covAvg = (BtB * ((A \ Q) / A') * BtB') ./ (dB * dB');
    expct = sqrt(diag(covAvg) + varDet(:, t) ./ dB.^2);
    verifyEqual(testCase, out.sigma(:, t), expct, ...
        'RelTol', 1e-8);
end
end

function testBasinSigmaConstrainedExact(testCase)
% v2.5: with hard constraints the deconvolution noise covariance uses
% the exact constrained operator. Verify against explicit matrices.
rng(24);
L = 5; T = 14; K = 2;
idx = shLowLevel.shIndex(L, Nmin = 2); P = idx.P;
Cs = zeros(L+1, L+1, T); Ss = Cs;
mL = tril(true(L+1));
for t = 1:T
    Cs(:,:,t) = (mL .* randn(L+1)) * 1e-9;
    St = (mL .* randn(L+1)) * 1e-9; St(:, 1) = 0;
    Ss(:,:,t) = St;
end
ts = shSeries(Cs, Ss = Ss, Epochs = 2016 + (0:T-1)'/12);
Ac = exp(-idx.n / 3) .* randn(P, 1);
B = randn(P, K);
[~, op] = ts.filter("tvANS", Constraints = Ac, Blocks = "off");
[~, out] = shLowLevel.basinDeconvolve(B, op);
S = op.V * (op.lam .* op.V'); N = op.V * op.V';
BtB = B' * B; dB = diag(BtB);
varDet = ((B.^2)' * op.detResVar) * op.detLeverage;
for t = [1, T]
    st = op.s(t);
    g = op.lam ./ (op.lam + st);
    W0 = op.V * (g .* op.Ut);
    W = W0 + S * Ac * (op.M \ (Ac' * (eye(P) - W0)));
    A = B' * W * B;
    Q = st * (B' * (W * N * W') * B);
    covAvg = (BtB * ((A \ Q) / A') * BtB') ./ (dB * dB');
    expct = sqrt(diag(covAvg) + varDet(:, t) ./ dB.^2);
    verifyEqual(testCase, out.sigma(:, t), expct, 'RelTol', 1e-8);
end
end

function testClimatologyAliasPeriodRecovery(testCase)
% synthetic S2-alias signal must be recovered exactly by Periods=[...]
pS2 = 161/365.25;
T = 80; t = 2002 + (0:T-1)'/12;
nmax = 3; n1 = nmax + 1;
Cs = zeros(n1, n1, T); Ss = zeros(n1, n1, T);
tc = t - mean(t);
sig = 1e-9*(0.3 + 0.5*tc + 0.4*cos(2*pi*tc/pS2) - 0.2*sin(2*pi*tc/pS2));
for k = 1:T, Cs(3, 1, k) = sig(k); end
ts = shSeries(Cs, Ss = Ss, Epochs = t);
clim = ts.climatology(Periods = pS2);
[gc, gs] = clim.periodic(1);
verifyEqual(testCase, gc.C(3,1), 0.4e-9, 'AbsTol', 1e-15);
verifyEqual(testCase, gs.C(3,1), -0.2e-9, 'AbsTol', 1e-15);
verifyEqual(testCase, clim.trend().C(3,1), 0.5e-9, 'AbsTol', 1e-15);
end

function testClimatologySigmaMonteCarlo(testCase)
% empirical scatter of the trend estimate must match the claimed 1-sigma
% (OLS formula; Python MC gave ratios 0.99-1.02)
rng(20);
T = 60; t = 2002 + (0:T-1)'/12;
nmax = 2; n1 = nmax + 1;
MC = 60; sigNoise = 1e-9;
trends = zeros(MC, 1); claimed = zeros(MC, 1);
for mc = 1:MC
    Cs = zeros(n1, n1, T); Ss = zeros(n1, n1, T);
    Cs(3, 1, :) = sigNoise * randn(T, 1);
    ts = shSeries(Cs, Ss = Ss, Epochs = t);
    clim = ts.climatology();
    tr = clim.trend();
    trends(mc) = tr.C(3, 1);
    claimed(mc) = tr.sigmaC(3, 1);
end
ratio = std(trends) / mean(claimed);
verifyGreaterThan(testCase, ratio, 0.6);
verifyLessThan(testCase, ratio, 1.6);
end

function testFilterSigmaStacks(testCase)
% filtered series must carry finite posterior sigmas above Nmin
rng(21);
Lmax = 6; T = 24;
n1 = Lmax + 1;
t = 2002 + (0:T-1)'/12;
Cs = 1e-9 * randn(n1, n1, T); Ss = 1e-9 * randn(n1, n1, T);
for k = 1:T
    Cs(:,:,k) = tril(Cs(:,:,k)); Ss(:,:,k) = tril(Ss(:,:,k)); Ss(:,1,k) = 0;
end
ts = shSeries(Cs, Ss = Ss, Epochs = t);
tf = ts.filter("tvANS");
verifyTrue(testCase, all(isfinite(tf.sigmaCs(3:end, 1, 1)), 'all'));
verifyTrue(testCase, all(tf.sigmaCs(3:end, 1, 1) > 0, 'all'));
verifyTrue(testCase, all(isnan(tf.sigmaCs(1:2, 1, 1))));  % below Nmin
end

function testSelectAndDropNaN(testCase)
rng(22);
n1 = 4; T = 10;
t = 2002 + (0:T-1)';
Cs = randn(n1, n1, T); Ss = randn(n1, n1, T);
Cs(2, 1, 4) = NaN;
ts = shSeries(Cs, Ss = Ss, Epochs = t);
t2 = ts.dropNaN();
verifyEqual(testCase, t2.nEpochs, T - 1);
verifyEqual(testCase, t2.epochs, t([1:3 5:end]));
t3 = ts.select([2002.5 2005.5]);
verifyEqual(testCase, t3.nEpochs, 3);
t4 = ts.select([1 3 5]);
verifyEqual(testCase, t4.epochs, t([1 3 5]));
end

% ------------------------------------------- mean over a period (v3.29.0)
% Reference values frozen from tools/dev/validate_meanperiod.py; the
% signal below is exactly inside the fit space, so "model" must return the
% analytic window mean and "arithmetic" must miss it by the frozen amount.

function y = periodSignal(t)
y = 1.0 + 0.30*(t - 2004) + 1.20*cos(2*pi*(t - 0.08)) ...
    + 0.35*cos(4*pi*(t - 0.55));
end

function y = periodSinc(x)
% sin(pi*x)/(pi*x), 1 at 0 - the attenuation of one harmonic over a window
if x == 0, y = 1; else, y = sin(pi*x)/(pi*x); end
end

function m = periodTruth(t1, t2)
% exact analytic mean of periodSignal over [t1 t2]
tm = 0.5*(t1 + t2); D = t2 - t1;
m = 1.0 + 0.30*(tm - 2004) ...
    + 1.20*cos(2*pi*(tm - 0.08)) * periodSinc(D/1) ...
    + 0.35*cos(4*pi*(tm - 0.55)) * periodSinc(D/0.5);
end

function t = periodMonths(a, b)
t = a + ((0:round((b - a)*12) - 1)' + 0.5)/12;
end

function ts = periodSeries(t)
% fixed coefficient pattern times the reference signal
M  = [1 0 0; 2 3 0; 4 5 6];
Ms = [0 0 0; 0 1 0; 0 2 3];
y = periodSignal(t);
Cs = zeros(3, 3, numel(t)); Ss = zeros(3, 3, numel(t));
for k = 1:numel(t)
    Cs(:,:,k) = M * y(k);
    Ss(:,:,k) = Ms * y(k);
end
ts = shSeries(Cs, Ss = Ss, Epochs = t(:));
end

function testMeanPeriodGappyWindow(testCase)
% 2004-2010 with one 6-month block missing (validate_meanperiod.py)
t = periodMonths(2004, 2010);
t = t(~(t > 2006.4 & t < 2006.9));
verifyEqual(testCase, numel(t), 66);
ts = periodSeries(t);
truth = periodTruth(2004, 2010);
verifyEqual(testCase, truth, 1.9, 'AbsTol', 1e-12);   % whole years: sinc = 0

[gA, iA] = ts.mean(Range = [2004 2010]);
verifyEqual(testCase, gA.C(1,1) - truth, 0.069179522165, 'AbsTol', 1e-9);
verifyEqual(testCase, iA.nUsed, 66);
verifyEqual(testCase, iA.nTotal, 66);
verifyEqual(testCase, iA.coverage, 0.916666666667, 'AbsTol', 1e-9);
verifyEqual(testCase, iA.maxGapYears, 0.583333333333, 'AbsTol', 1e-9);
verifyEqual(testCase, iA.centroidOffset, 0.030303030303, 'AbsTol', 1e-9);
verifyEqual(testCase, iA.estimator, "arithmetic");
verifyEqual(testCase, gA.epoch, mean(t), 'AbsTol', 1e-12);   % centroid

[gM, iM] = ts.mean(Range = [2004 2010], Estimator = "model");
verifyEqual(testCase, gM.C(1,1), truth, 'AbsTol', 1e-10);
verifyEqual(testCase, gM.C(3,2), 5*truth, 'AbsTol', 1e-9);
verifyEqual(testCase, gM.S(3,3), 3*truth, 'AbsTol', 1e-9);
verifyEqual(testCase, gM.epoch, 2007, 'AbsTol', 1e-12);      % window centre
verifyEqual(testCase, iM.attenuation(:,1), [1; 0.5], 'AbsTol', 1e-12);
verifyEqual(testCase, iM.attenuation(:,2), [0; 0], 'AbsTol', 1e-12);
% signal exactly in the fit space -> no residual -> no formal sigma
verifyLessThan(testCase, max(abs(gM.sigmaC(:))), 1e-8);
end

function testMeanPeriodAttenuation(testCase)
% a window of 5.5 years annihilates the semi-annual, not the annual
t = periodMonths(2004, 2009.5);
ts = periodSeries(t);
truth = periodTruth(2004, 2009.5);
verifyEqual(testCase, truth, 1.858457517928, 'AbsTol', 1e-9);
gA = ts.mean(Range = [2004 2009.5]);
verifyEqual(testCase, gA.C(1,1) - truth, 0.000385268670, 'AbsTol', 1e-9);
[gM, iM] = ts.mean(Range = [2004 2009.5], Estimator = "model");
verifyEqual(testCase, gM.C(1,1), truth, 'AbsTol', 1e-10);
verifyEqual(testCase, iM.attenuation(:,2), [-0.057874524761; 0], ...
    'AbsTol', 1e-9);
end

function testMeanRangeMatchesSelectThenMean(testCase)
t = periodMonths(2004, 2010);
ts = periodSeries(t);
a = ts.mean(Range = [2005 2008]);
b = ts.select(Range = [2005 2008]).mean();
verifyEqual(testCase, a.C, b.C, 'AbsTol', 1e-14);
verifyEqual(testCase, a.S, b.S, 'AbsTol', 1e-14);
verifyEqual(testCase, a.sigmaC, b.sigmaC, 'AbsTol', 1e-14);
verifyEqual(testCase, a.epoch, b.epoch, 'AbsTol', 1e-12);
% the positional shorthand still means the same thing here
d = ts.select([2005 2008]).mean();
verifyEqual(testCase, d.C, a.C, 'AbsTol', 1e-14);
% datetime windows agree with decimal years
c = ts.mean(Range = [datetime(2005,1,1) datetime(2008,1,1)]);
verifyEqual(testCase, c.C, a.C, 'AbsTol', 1e-12);
% and the whole-series call is unchanged by the new options
verifyEqual(testCase, ts.mean().C, mean(ts.Cs, 3), 'AbsTol', 1e-14);
end

function testMeanSigmaUsesValidEpochCount(testCase)
% the standard error must divide by the epochs that entered it
t = periodMonths(2004, 2007);
ts = periodSeries(t);
Cs = ts.Cs; Ss = ts.Ss;
Cs(:,:,[4 8 12]) = NaN; Ss(:,:,[4 8 12]) = NaN;
tsN = shSeries(Cs, Ss = Ss, Epochs = t);
g = tsN.mean();
verifyEqual(testCase, g.C(1,1), 1.473863636364, 'AbsTol', 1e-9);
verifyEqual(testCase, g.sigmaC(1,1), 0.156294825874, 'AbsTol', 1e-9);
v = squeeze(Cs(1,1,:)); v = v(~isnan(v));
verifyEqual(testCase, numel(v), 33);
verifyEqual(testCase, g.sigmaC(1,1), std(v)/sqrt(33), 'AbsTol', 1e-12);
% fewer than two valid epochs is no sigma at all, not the std of one sample
Cs2 = Cs; Cs2(1,1,:) = NaN; Cs2(1,1,1) = 5;
g2 = shSeries(Cs2, Ss = Ss, Epochs = t).mean();
verifyEqual(testCase, g2.C(1,1), 5, 'AbsTol', 1e-12);
verifyTrue(testCase, isnan(g2.sigmaC(1,1)));
end

function testFitModelWeightsEquivalence(testCase)
% uniform weights must reproduce the unweighted fit exactly
rng(23);
T = 40; t = (0:T-1)'/12 + 2002;
X = randn(5, T);
[m1, ~, c1] = shLowLevel.fitDeterministicModel(X, t);
[m2, ~, c2] = shLowLevel.fitDeterministicModel(X, t, Weights = 2*ones(T,1));
verifyEqual(testCase, c2, c1, 'AbsTol', 1e-12 * max(abs(c1(:))));
verifyEqual(testCase, m2, m1, 'AbsTol', 1e-12 * max(abs(m1(:))));
end

% =============================================================== v2.2
function testGeodeticGeocentricRoundtrip(testCase)
lat = [-89.9, -45, -0.1, 0, 23.4567, 60, 90];
gc = shLowLevel.geodetic2geocentric(lat);
back = shLowLevel.geocentric2geodetic(gc);
verifyEqual(testCase, back, lat, 'AbsTol', 1e-12);
% known value (WGS84): atand((1-f)^2), independently computed in Python
verifyEqual(testCase, shLowLevel.geodetic2geocentric(45), 44.807576784018, 'AbsTol', 1e-9);
verifyEqual(testCase, shLowLevel.geodetic2geocentric(90), 90, 'AbsTol', 0);
% synthesis with LatType="geodetic" == manual conversion
g = randomField(12);
latGD = [-60, -10, 35, 70];
lon = 0:60:300;
g1 = g.synthesis(shLowLevel.geodetic2geocentric(latGD), lon);
g2 = g.synthesis(latGD, lon, LatType = "geodetic");
verifyEqual(testCase, g2, g1, 'AbsTol', 0);
end

function testBasinKernelAreaAndTaper(testCase)
idx = shLowLevel.shIndex(20, Nmin = 0);
cap = @(la, lo) double(la > 60);                 % polar cap, ~6.7% area
[b, info] = shLowLevel.basinKernel(idx, cap);
% indicator staircase: +4.5% at OverSample=2 / Lmax=20 (Python-computed);
% the EXACT identities below are the strong checks
verifyEqual(testCase, info.areaFraction, (1 - cosd(30))/2, 'RelTol', 0.08);
% degree-0 coefficient of the indicator = area fraction (Y00 = 1)
verifyEqual(testCase, b(1), info.areaFraction, 'AbsTol', 1e-12);
% spectral taper = elementwise Jekeli weights
[bT, ~] = shLowLevel.basinKernel(idx, cap, TaperKm = 500);
Wn = shLowLevel.shGaussianWeights(idx.Lmax, 500);
verifyEqual(testCase, bT, b .* Wn(idx.n + 1), 'AbsTol', 0);
% buffered kernel encloses more area
[~, infoG] = shLowLevel.basinKernel(idx, cap, BufferKm = 1000);
verifyGreaterThan(testCase, infoG.areaFraction, info.areaFraction);
end

function testSlepianPolarCap(testCase)
idx = shLowLevel.shIndex(12, Nmin = 0);
cap = @(la, lo) double(la > 60);
[G, lam, info] = shLowLevel.slepianBasis(idx, cap, NKeep = idx.P);
verifyGreaterThanOrEqual(testCase, min(lam), 0);
verifyLessThanOrEqual(testCase, max(lam), 1);
verifyEqual(testCase, sort(lam, 'descend'), lam, 'AbsTol', 0);
verifyEqual(testCase, G' * G, eye(idx.P), 'AbsTol', 1e-12);
% trace identity: sum(lam) = quadrature area fraction * P (addition thm)
verifyEqual(testCase, sum(info.lamAll), info.areaFraction * idx.P, ...
    'RelTol', 1e-10);
% the best taper concentrates: reconstruct on grid, energy inside > 95%
% (mask and Y/w must live on the SAME quadrature grid: evalMask defaults
% to OverSample=2 since v2.2.1, so pin both to the base grid here)
[Y, w] = shLowLevel.synthesisMatrix(idx);
[mask, ~] = shLowLevel.evalMask(idx, cap, OverSample = 1);
g1 = Y * G(:, 1);
verifyGreaterThan(testCase, sum(w .* mask .* g1.^2) / sum(w .* g1.^2), 0.95);
end

function testMCPropagateLinearFunctional(testCase)
rng(7);
g = randomFieldWithSigmas(10, 2020);
idx = shLowLevel.shIndex(10, Nmin = 0);
wv = randn(idx.P, 1);
fun = @(gs) wv' * shLowLevel.vecFromCS(gs.C, gs.S, idx);
out = shLowLevel.mcPropagate(fun, g, N = 4000, Seed = 11);
% analytic: sigma^2 = sum(w_p^2 sigma_p^2) for independent Gaussians
sv = shLowLevel.vecFromCS(g.sigmaC, g.sigmaS, idx);
sv(~isfinite(sv)) = 0;
sigAna = sqrt(sum((wv .* sv).^2));
verifyEqual(testCase, out.sigma, sigAna, 'RelTol', 0.05);   % MC ~1.1%
verifyEqual(testCase, out.mean, fun(g), 'AbsTol', 4 * sigAna / sqrt(4000));
end

function testMCPropagateFullCovariance(testCase)
% the Cov path with the REAL SINEX fixture: 12 params = shIndex(3,
% Nmin=2); propagated sigma of a linear functional must equal
% sqrt(w' M w)
f = fullfile(shxTestDataDir(), ...
    'ITSG-Grace2018_n96_2008-04_head12.snx');
verifyTrue(testCase, isfile(f));
idx = shLowLevel.shIndex(3, Nmin = 2);
snx = shLowLevel.readSINEX(f, Output = "covariance", Index = idx);
M = (snx.M + snx.M') / 2;
g = shCoefficients(zeros(4), zeros(4));
rng(5); wv = randn(idx.P, 1);
fun = @(gs) wv' * shLowLevel.vecFromCS(gs.C, gs.S, idx);
out = shLowLevel.mcPropagate(fun, g, Cov = M, Idx = idx, N = 4000, Seed = 6);
verifyEqual(testCase, out.sigma, sqrt(wv' * M * wv), 'RelTol', 0.06);
end

function testBandedVCEMatchesGlobalWhenUniform(testCase)
% with one band spanning all orders, banded == global exactly
rng(21);
idx = shLowLevel.shIndex(10, Nmin = 2);
T = 20; X = randn(idx.P, T);
t = 2020 + (0:T-1)'/12;
[Xf1, op1, i1] = shLowLevel.tvANSFilter(X, t, idx, Blocks = 'on'); %#ok<ASGLU>
[Xf2, op2, i2] = shLowLevel.tvANSFilter(X, t, idx, Blocks = 'on', ...
    VCEBands = [0, idx.Lmax + 1]); %#ok<ASGLU>
verifyEqual(testCase, Xf2, Xf1, 'AbsTol', 1e-14);
verifyEqual(testCase, op2.sBlocks, repmat(op2.s(:)', numel(op2.blocks), 1), ...
    'AbsTol', 1e-14);
end

function testBandedVCETracksOrderNoise(testCase)
% noise 3x stronger for m >= 6: band factors must reflect the contrast.
% NoiseCov must be a FIXED external model here: the default N is built
% from the data residuals and absorbs the very contrast being tested.
rng(22);
idx = shLowLevel.shIndex(12, Nmin = 2);
T = 30; t = 2020 + (0:T-1)'/12;
scale = 1 + 2 * (idx.m >= 6);
X = scale .* randn(idx.P, T);
[~, op] = shLowLevel.tvANSFilter(X, t, idx, Blocks = 'on', ...
    NoiseCov = eye(idx.P), ...
    VCEBands = [0, 6, idx.Lmax + 1], VCEMinDegree = 4);
% mean band factors: high band / low band ~ variance ratio 9 (loose)
mLow = zeros(0,1); mHigh = zeros(0,1);
for k = 1:numel(op.blocks)
    mB = idx.m(op.blocks(k).rows(1));
    if mB < 6, mLow(end+1,1) = mean(op.sBlocks(k, :)); %#ok<AGROW>
    else, mHigh(end+1,1) = mean(op.sBlocks(k, :)); end %#ok<AGROW>
end
verifyGreaterThan(testCase, mean(mHigh) / mean(mLow), 3);
end

function testBandedSynthesisEqualsMonolithic(testCase)
g = randomField(40);
lat = -85:5:85; lon = 0:6:354;
g1 = g.synthesis(lat, lon);                       % cached, monolithic
g2 = g.synthesis(lat, lon, MaxMemGB = 1e-4, UseCache = false);  % forces bands
verifyEqual(testCase, g2, g1, 'AbsTol', 1e-18);
% direct shLowLevel call with tiny budget, supplied-P path unaffected
[gr1, ~, ~] = shLowLevel.shSynthesis(g.C, g.S, g.GM, g.R, lat, lon);
[gr2, ~, ~] = shLowLevel.shSynthesis(g.C, g.S, g.GM, g.R, lat, lon, ...
    'MaxMemGB', 1e-4);
verifyEqual(testCase, gr2, gr1, 'AbsTol', 1e-18);
end


function g = randomFieldWithSigmas(nmax, epoch)
rng(40 + nmax);
n1 = nmax + 1;
mL = tril(true(n1)); mL1 = tril(true(n1), -1);
C = (mL .* randn(n1)) * 1e-9;  S = (mL1 .* randn(n1)) * 1e-9;
sC = (mL .* abs(randn(n1))) * 1e-11;
sS = (mL1 .* abs(randn(n1))) * 1e-11;
g = shCoefficients(C, S, SigmaC = sC, SigmaS = sS, Epoch = epoch);
end

function testPropertyBasedSynthesisAnalysisRoundtrip(testCase)
% property-based: random nmax / grid sizes / quantities, exact ring-grid
% roundtrip coefficients -> grid -> coefficients (v2.2)
qs = ["geoid", "potential", "gravity_disturbance"];
for seed = 1:6
    rng(100 + seed);
    nmax = randi([4, 24]);
    nlat = nmax + 1 + randi(8);
    nlon = 2*nmax + 1 + randi(10);
    q = qs(randi(3));
    g = randomField(nmax);
    [xg, ~] = shLowLevel.gaussLegendre(nlat);            % ring latitudes (nodes)
    lat = asind(xg(:)');
    lon = (0:nlon-1) * 360 / nlon;
    grid = g.synthesis(lat, lon, Quantity = q, UseCache = false);
    g2 = shCoefficients.analysis(grid, lat, lon, nmax, Quantity = char(q));
    verifyEqual(testCase, g2.C, g.C, 'AbsTol', 1e-10, ...
        sprintf('roundtrip C failed (seed %d, nmax %d, %s)', seed, nmax, q));
    verifyEqual(testCase, g2.S, g.S, 'AbsTol', 1e-10, ...
        sprintf('roundtrip S failed (seed %d, nmax %d, %s)', seed, nmax, q));
end
end

% =============================================================== v2.3
function testNewKernelIdentities(testCase)
GM = 3.986004415e14; R = 6378136.3; L = 60;
n = (0:L)';
kn = -0.30 * n ./ (n + 3.0);                     % synthetic Love numbers
sd  = shLowLevel.kernelFactors('surface_density', L, GM, R, kn = kn);
ew  = shLowLevel.kernelFactors('ewh', L, GM, R, kn = kn, rho_water = 1000);
bp  = shLowLevel.kernelFactors('bottom_pressure', L, GM, R, kn = kn);
trr = shLowLevel.kernelFactors('gravity_gradient_rr', L, GM, R);
dis = shLowLevel.kernelFactors('gravity_disturbance', L, GM, R);
% exact relations between the kernels
verifyEqual(testCase, sd, 1000 * ew, 'RelTol', 1e-15);
verifyEqual(testCase, bp, (GM/R^2) * sd, 'RelTol', 1e-15);
verifyEqual(testCase, trr, dis .* (n + 2) / R, 'RelTol', 1e-15);
% upward continuation: Python-validated attenuation powers
hgt = 400e3; r = R + hgt;
pH = shLowLevel.kernelFactors('potential', L, GM, R, Height = hgt);
p0 = shLowLevel.kernelFactors('potential', L, GM, R);
verifyEqual(testCase, pH, p0 .* (R/r).^(n+1), 'RelTol', 1e-15);
dH = shLowLevel.kernelFactors('gravity_disturbance', L, GM, R, Height = hgt);
verifyEqual(testCase, dH, dis .* (R/r).^(n+2), 'RelTol', 1e-15);
% error contracts
verifyError(testCase, @() shLowLevel.kernelFactors('surface_density', L, GM, R), ...
    'shLowLevel:kernelFactors:missingLoveNumbers');
verifyError(testCase, @() shLowLevel.kernelFactors('deformation_up', L, GM, R, ...
    kn = kn), 'shLowLevel:kernelFactors:missingLoveNumbers');
verifyError(testCase, @() shLowLevel.kernelFactors('ewh', L, GM, R, kn = kn, ...
    Height = 1e5), 'shLowLevel:kernelFactors:heightInvalid');
end

function testLegendreDerivativeIdentity(testCase)
% frozen dPbar/dphi identity vs central differences (Python-calibrated)
L = 30;
lats = deg2rad([-72.3, -33.1, -5.0, 12.7, 48.9, 81.2]);
h = 1e-6;
[~, D] = shLowLevel.legendreALFDeriv(L, lats);
for k = 1:numel(lats)
    Dnum = (shLowLevel.legendreALF(L, lats(k) + h) ...
          - shLowLevel.legendreALF(L, lats(k) - h)) / (2*h);
    verifyEqual(testCase, D(:, :, k), Dnum, 'AbsTol', 1e-6 * max(abs(Dnum(:))));
end
% poles are finite (no 1/cos singularities in D itself)
[~, Dp] = shLowLevel.legendreALFDeriv(L, deg2rad([90, -90]));
verifyTrue(testCase, all(isfinite(Dp(:))));
end

function testResolutionMapRadiusIsAChoice(testCase)
%TESTRESOLUTIONMAPRADIUSISACHOICE The km conversion is not a hidden constant.
%   resolutionMap turned degrees into kilometres with a hardcoded 6371
%   (CLAUDE.md A13). It is now the RadiusKm option, default unchanged, so
%   this pins BOTH halves: the default still gives the old numbers, and
%   scaling the radius scales the half-widths exactly. Metamorphic, so no
%   tolerance is needed beyond the arithmetic of the product itself.
rng(31);
idx = shLowLevel.shIndex(4);
X = randn(idx.P, 12) * 1e-10;
t = 2002 + (0:11)' / 12;
[~, op] = shLowLevel.tvANSFilter(X, t, idx, Blocks = 'off', ...
    NoiseCov = eye(idx.P));
lat = [0; 45];
lon = [0; 90];
r1 = shLowLevel.resolutionMap(op, 1, lat, lon, NAz = 4, NPsi = 40);
r2 = shLowLevel.resolutionMap(op, 1, lat, lon, NAz = 4, NPsi = 40, ...
    RadiusKm = 2 * 6371);
% the angular half-widths do not depend on the radius at all
verifyEqual(testCase, r2.psiHalfDeg, r1.psiHalfDeg);
verifyEqual(testCase, r2.azDeg, r1.azDeg);
% and every kilometre figure scales exactly with it
verifyEqual(testCase, r2.kmMean, 2 * r1.kmMean, 'AbsTol', 0);
verifyEqual(testCase, r2.kmMin, 2 * r1.kmMin, 'AbsTol', 0);
verifyEqual(testCase, r2.kmMax, 2 * r1.kmMax, 'AbsTol', 0);
% anisotropy is a ratio of two km figures, so it is radius-invariant
verifyEqual(testCase, r2.anisotropy, r1.anisotropy);
% the documented struct fields are the ones the reader gets
verifyEqual(testCase, sort(string(fieldnames(r1)))', ...
    sort(["psiHalfDeg", "azDeg", "kmMean", "kmMin", "kmMax", ...
          "anisotropy"]));
end

function testDeformationSynthesis(testCase)
% north/east against numerical gradients of the tangential-kernel scalar
rng(61);
L = 16; R = 6378136.3;
n1 = L + 1; n = (0:L)';
C = tril(randn(n1)) * 1e-8;
S = tril(randn(n1), -1) * 1e-8; S(:, 1) = 0;
kn = -0.30 * n ./ (n + 3.0);
hn = -0.90 * n ./ (n + 2.0) - 0.1;
ln = -0.05 * n ./ (n + 4.0) - 0.01;
lat = [37.2, -61.8]; lon = [211.0, 12.5];
[up, north, east] = shLowLevel.shSynthesisDeformation(C, S, R, lat, lon, ...
    kn = kn, hn = hn, ln = ln, Nmin = 1);
% vertical == kernel route through the standard synthesis
fUp = shLowLevel.shSynthesisDeformation(C, S, R, lat, lon, ...
    kn = kn, hn = hn, ln = ln, Nmin = 1);
upK = shLowLevel.shSynthesis(C, S, 3.986004415e14, R, lat, lon, ...
    'Quantity', 'deformation_up', 'kn', kn, 'hn', hn, 'Nmin', 1);
verifyEqual(testCase, fUp, upK, 'AbsTol', 1e-15);
% horizontal vs finite differences of the fH-scaled scalar field
fH = R * ln ./ (1 + kn); fH(1) = 0;
dphi = 1e-6;
for i = 1:2
    for j = 1:2
        gp = shLowLevel.shSynthesis(fH .* C, fH .* S, 1, 1, lat(i) + rad2deg(dphi), lon(j), ...
            'Quantity', 'geoid');
        gm_ = shLowLevel.shSynthesis(fH .* C, fH .* S, 1, 1, lat(i) - rad2deg(dphi), lon(j), ...
            'Quantity', 'geoid');
        dN = (gp - gm_) / (2 * dphi);
        verifyEqual(testCase, north(i, j), dN, 'RelTol', 1e-4, ...
            sprintf('north at (%g, %g)', lat(i), lon(j)));
        gp = shLowLevel.shSynthesis(fH .* C, fH .* S, 1, 1, lat(i), lon(j) + rad2deg(dphi), ...
            'Quantity', 'geoid');
        gm_ = shLowLevel.shSynthesis(fH .* C, fH .* S, 1, 1, lat(i), lon(j) - rad2deg(dphi), ...
            'Quantity', 'geoid');
        dE = (gp - gm_) / (2 * dphi) / cosd(lat(i));
        verifyEqual(testCase, east(i, j), dE, 'RelTol', 1e-4, ...
            sprintf('east at (%g, %g)', lat(i), lon(j)));
    end
end
% points mode == grid diagonal; east NaN at the pole, north finite
[uP, nP, eP] = shLowLevel.shSynthesisDeformation(C, S, R, lat, lon, ...
    kn = kn, hn = hn, ln = ln, Mode = "points");
% grid and points modes use different summation orders: agreement to a
% few ULP, not bit-identity (observed 1-4e-16 on R2026a)
verifyEqual(testCase, uP, [up(1,1); up(2,2)], 'RelTol', 1e-12);
verifyEqual(testCase, nP, [north(1,1); north(2,2)], 'RelTol', 1e-12);
verifyEqual(testCase, eP, [east(1,1); east(2,2)], 'RelTol', 1e-12);
[uPole, nPole, ePole] = shLowLevel.shSynthesisDeformation(C, S, R, 90, 45, ...
    kn = kn, hn = hn, ln = ln);
verifyTrue(testCase, isfinite(uPole) && isfinite(nPole) && isnan(ePole));
end

function testSurfaceDensityAnalysisRoundtrip(testCase)
rng(62);
L = 12; n = (0:L)';
kn = -0.30 * n ./ (n + 3.0);
g = randomField(L);
[xg, ~] = shLowLevel.gaussLegendre(L + 1);
lat = asind(xg(:)'); lon = (0:2*L+1) * 360 / (2*L + 2);
grid = g.synthesis(lat, lon, Quantity = "surface_density", kn = kn, ...
    UseCache = false);
g2 = shCoefficients.analysis(grid, lat, lon, L, ...
    Quantity = 'surface_density', kn = kn);
verifyEqual(testCase, g2.C, g.C, 'AbsTol', 1e-10);
verifyEqual(testCase, g2.S, g.S, 'AbsTol', 1e-10);
end

% =============================================================== v2.4
function testSecondDerivativeIdentity(testCase)
L = 25; h = 1e-5;
for lat = [-71, -20, 33.3, 66.6]
    la = deg2rad(lat);
    [P0, ~, D2] = shLowLevel.legendreALFDeriv(L, la);
    Pp = shLowLevel.legendreALF(L, la + h);
    Pm = shLowLevel.legendreALF(L, la - h);
    num = (Pp - 2*P0 + Pm) / h^2;
    verifyEqual(testCase, D2, num, 'AbsTol', 1e-5 * max(abs(num(:))));
end
end

function testGradientTensorInvariants(testCase)
rng(71);
L = 14; GM = 3.986004415e14; R = 6378136.3;
n1 = L + 1;
C = tril(randn(n1)) * 1e-8; C(1, 1) = 0;
S = tril(randn(n1), -1) * 1e-8; S(:, 1) = 0;
lat = [41, -55.5]; lon = [100, 331];
[G, info] = shLowLevel.shSynthesisGradientTensor(C, S, GM, R, lat, lon, ...
    Height = 250e3, Nmin = 2);
% Laplace: trace = 0 (Python: 7e-16)
verifyLessThan(testCase, info.maxTraceResidual, 1e-12);
% Guu == gravity_gradient_rr kernel route with Height
guuK = shLowLevel.shSynthesis(C, S, GM, R, lat, lon, ...
    'Quantity', 'gravity_gradient_rr', 'Height', 250e3, 'Nmin', 2);
verifyEqual(testCase, G.uu, guuK, 'RelTol', 1e-12);
% symmetry fields present and finite away from poles
for f = ["nn", "ee", "un", "ue", "ne"]
    verifyTrue(testCase, all(isfinite(G.(f)(:))));
end
% angular second derivatives vs finite differences through the potential
fT = shLowLevel.kernelFactors('potential', L, GM, R, Height = 250e3);
fT(1:2) = 0;
h = 1e-4; r = R + 250e3;
scal = @(la_, lo_) shLowLevel.shSynthesis(fT .* C, fT .* S, 1, 1, la_, lo_, ...
    'Quantity', 'geoid');
la = lat(1); lo = lon(1);
Tpp = (scal(la + rad2deg(h), lo) - 2*scal(la, lo) + scal(la - rad2deg(h), lo)) / h^2;
Gnn_num = Tpp / r^2 + gradTr(C, S, GM, R, L, la, lo, r) / r;
verifyEqual(testCase, G.nn(1, 1), Gnn_num, 'RelTol', 5e-4);
end

function Tr = gradTr(C, S, GM, R, L, la, lo, r)
n = (0:L)';
fTr = -(GM/R) * (n + 1) / r .* (R/r).^(n + 1);
fTr(1:2) = 0;
Tr = shLowLevel.shSynthesis(fTr .* C, fTr .* S, 1, 1, la, lo, 'Quantity', 'geoid');
end

function testCombineCentersRecovery(testCase)
rng(72);
L = 8; n1 = L + 1; T = 14;
idx = shLowLevel.shIndex(L, Nmin = 0);
% truth: smooth series
Ct = zeros(n1, n1, T); St = zeros(n1, n1, T);
base = tril(randn(n1)) * 1e-9;
for t = 1:T
    Ct(:, :, t) = base * (1 + 0.1 * sin(t/2));
    St(:, :, t) = tril(randn(n1), -1) * 1e-10; St(:, 1, t) = 0;
end
ep = 2010 + (0:T-1) / 12;
s2true = [1.0; 4.0; 2.25];                       % static center factors
tsC = cell(1, 3);
for c = 1:3
    Cs = Ct; Ss = St;
    for t = 1:T
        Nc = tril(randn(n1)) * 2e-10 * sqrt(s2true(c));
        Ns = tril(randn(n1), -1) * 2e-10 * sqrt(s2true(c)); Ns(:, 1) = 0;
        Cs(:, :, t) = Cs(:, :, t) + Nc;
        Ss(:, :, t) = Ss(:, :, t) + Ns;
    end
    tsC{c} = shSeries(Cs, Ss = Ss, Epochs = ep, ProductType = "GSM");
end
[tsComb, info] = shLowLevel.combineCenters(tsC, MaxIter = 8);
% factor RATIOS recovered (VCE fixes relative scale per month; compare
% medians across months, generous tolerance for T*P statistics)
med = median(info.s2, 2);
ratio = med / med(1);
verifyEqual(testCase, ratio, s2true / s2true(1), 'RelTol', 0.5);
% combined closer to truth than the worst center, month-wise stack
errC = zeros(3, 1);
for c = 1:3
    errC(c) = norm([tsC{c}.Cs(:) - Ct(:); tsC{c}.Ss(:) - St(:)]);
end
errComb = norm([tsComb.Cs(:) - Ct(:); tsComb.Ss(:) - St(:)]);
verifyLessThan(testCase, errComb, min(errC));
% honesty diagnostics present
verifyEqual(testCase, size(info.interCenterCorr), [3 3]);
verifyTrue(testCase, all(isfinite(info.redundancy(:))));
% posterior sigmas on the combined series
verifyEqual(testCase, size(tsComb.sigmaCs), [n1 n1 T]);
verifyTrue(testCase, all(tsComb.sigmaCs(:) >= 0));
end

function testCombineCentersContract(testCase)
rng(73);
L = 4; n1 = L + 1;
Cs = randn(n1, n1, 3) * 1e-9; Ss = Cs; Ss(:, 1, :) = 0;
ts1 = shSeries(Cs, Ss = Ss, Epochs = [2010 2010.1 2010.2]);
verifyError(testCase, @() shLowLevel.combineCenters({ts1}), ...
    'shLowLevel:combineCenters:tooFewCenters');
Cs2 = randn(L, L, 3) * 1e-9; Ss2 = Cs2; Ss2(:, 1, :) = 0;
ts2 = shSeries(Cs2, Ss = Ss2, Epochs = [2010 2010.1 2010.2]);
verifyError(testCase, @() shLowLevel.combineCenters({ts1, ts2}), ...
    'shLowLevel:combineCenters:nmaxMismatch');
ts3 = shSeries(Cs, Ss = Ss, Epochs = [2015 2015.1 2015.2]);
verifyError(testCase, ...
    @() shLowLevel.combineCenters({ts1, ts3}, AllowMissing = false), ...
    'shLowLevel:combineCenters:noCommonEpochs');
end

function testFingerprintConservation(testCase)
L = 24; n = (0:L)';
kn = -0.30 * n ./ (n + 3.0);
hn = -0.90 * n ./ (n + 2.0) - 0.1;
idx = shLowLevel.shIndex(L, Nmin = 0);
ocean = @(la, lo) ~(la > 55 & (lo < 60 | lo > 300));
loadF = @(la, lo) -100 * double(la > 65 & lo < 40);   % kg/m^2 ice loss
[S, grid, info] = shLowLevel.seaLevelFingerprint(loadF, ocean, idx, ...
    kn = kn, hn = hn);
verifyTrue(testCase, info.converged);
% mass conservation at machine precision (Python: exact)
verifyLessThan(testCase, abs(info.massResidual), 1e-12);
% classic pattern: near-field BELOW eustatic (here negative), far above
S2 = info.S2D;
[LAT, ~] = ndgrid(grid.latDeg, grid.lonDeg);
OC = S2 ~= 0;
near = mean(S2(LAT > 60 & OC));
far = mean(S2(LAT < -30 & OC));
verifyLessThan(testCase, near, info.eustatic);
verifyGreaterThan(testCase, far, info.eustatic);
verifyLessThan(testCase, near, 0);
% polygon load form runs and conserves too
poly = [66 5; 66 35; 80 35; 80 5];
[~, ~, info2] = shLowLevel.seaLevelFingerprint(poly, ocean, idx, ...
    kn = kn, hn = hn, LoadValue = -100);
verifyLessThan(testCase, abs(info2.massResidual), 1e-12);
end

function testEOFReconstruction(testCase)
rng(74);
L = 10; n1 = L + 1; T = 40;
% two orthogonal spatial patterns, known temporal amplitudes
P1 = tril(randn(n1)); P2 = tril(randn(n1));
P2 = P2 - P1 * (P1(:)' * P2(:)) / (P1(:)' * P1(:));   % orthogonalize
a1 = 3 * sin(2*pi*(1:T)/10)'; a2 = randn(T, 1);
Cs = zeros(n1, n1, T); Ss = zeros(n1, n1, T);
for t = 1:T
    Cs(:, :, t) = a1(t) * P1 + a2(t) * P2;
end
ts = shSeries(Cs, Ss = Ss, Epochs = 2010 + (1:T)/12);
[modes, pcs, ve, info] = shLowLevel.eofAnalysis(ts, NModes = 3);
% two modes carry (essentially) all variance
verifyGreaterThan(testCase, sum(ve(1:2)), 0.999);
% mode-1 spatial pattern parallel to P1 (up to sign)
m1 = modes{1}.C(:);
cosang = abs(m1' * P1(:)) / (norm(m1) * norm(P1(:)));
verifyGreaterThan(testCase, cosang, 0.98);
% pcs unit variance
verifyEqual(testCase, var(pcs(:, 1)), 1, 'RelTol', 1e-10);
verifyEqual(testCase, info.T, T);
end

function testBreakpointFTest(testCase)
rng(75);
L = 2; n1 = L + 1; T = 120;
ep = 2008 + (0:T-1)/12; tb = 2013.0;
hinge = max(ep - tb, 0);
Cs = zeros(n1, n1, T); Ss = zeros(n1, n1, T);
% C20: real break; C21: pure noise
for t = 1:T
    Cs(3, 1, t) = 0.02 * hinge(t) + 0.05 * randn;
    Cs(3, 2, t) = 0.05 * randn;
end
ts = shSeries(Cs, Ss = Ss, Epochs = ep);
out = ts.trendBreaks(Breaks = tb);
verifyGreaterThan(testCase, out.F(3, 1), 10);         % Python: F ~ 23
verifyLessThan(testCase, out.pValue(3, 1), 0.01);
verifyGreaterThan(testCase, out.pValue(3, 2), 0.01);  % null survives
% hinge slope recovered
verifyEqual(testCase, out.hingeC(3, 1), 0.02, 'AbsTol', 0.01);
end

function testFanFilterSeparable(testCase)
rng(76);
L = 30; n1 = L + 1;
C = tril(randn(n1)); S = tril(randn(n1), -1); S(:, 1) = 0;
[Cf, Sf] = shLowLevel.shFanFilter(C, S, 300, 500);
Wn = shLowLevel.shGaussianWeights(L, 300);
Wm = shLowLevel.shGaussianWeights(L, 500);
verifyEqual(testCase, Cf, C .* (Wn(:) .* Wm(:)'), 'RelTol', 1e-14);
verifyEqual(testCase, Sf, S .* (Wn(:) .* Wm(:)'), 'RelTol', 1e-14);
% equal radii on the degree axis: fan == isotropic Gaussian at m=0
[Cf2, ~] = shLowLevel.shFanFilter(C, S, 400, 400);
Wn4 = shLowLevel.shGaussianWeights(L, 400);
verifyEqual(testCase, Cf2(:, 1), C(:, 1) .* Wn4(:) * Wn4(1), 'RelTol', 1e-14);
end

function testErrorMapMatchesMC(testCase)
rng(77);
idx = shLowLevel.shIndex(3, Nmin = 2);
A = randn(idx.P) * 1e-10;
M = A * A' + 1e-22 * eye(idx.P);              % PD synthetic covariance
lat = [-40, 10, 55]; lon = [30, 200];
sig = shLowLevel.errorMap(M, idx, lat, lon, Quantity = "geoid");
% Monte-Carlo cross-check
Nmc = 4000;
Lch = chol((M + M')/2 + 1e-30*eye(idx.P), 'lower');
vals = zeros(numel(lat), numel(lon), Nmc);
for k = 1:Nmc
    x = Lch * randn(idx.P, 1);
    [Cm, Sm] = shLowLevel.csFromVec(x, idx);
    vals(:, :, k) = shLowLevel.shSynthesis(Cm, Sm, 3.986004415e14, 6378136.3, ...
        lat, lon, 'Quantity', 'geoid');
end
sigMC = std(vals, 0, 3);
verifyEqual(testCase, sig, sigMC, 'RelTol', 0.12);
end

function testWriteGridRoundtrip(testCase)
tmp = [tempname, '.nc'];
cleanup = onCleanup(@() delete(tmp)); %#ok<NASGU>
lat = (-88:4:88)'; lon = (0:4:356)';
[LA, LO] = ndgrid(lat, lon);
G = sind(LA) .* cosd(LO);
shLowLevel.writeGrid(tmp, G, lat, lon, Name = "lwe_thickness", Units = "m");
back = ncread(tmp, 'lwe_thickness')';
verifyEqual(testCase, back, G, 'AbsTol', 1e-14);
verifyEqual(testCase, ncread(tmp, 'lat'), lat, 'AbsTol', 0);
% 3-D stack
tmp2 = [tempname, '.nc'];
cleanup2 = onCleanup(@() delete(tmp2)); %#ok<NASGU>
G3 = cat(3, G, 2*G, -G);
shLowLevel.writeGrid(tmp2, G3, lat, lon, Name = "ewh", ...
    Epochs = [2010.1; 2010.2; 2010.3]);
b3 = permute(ncread(tmp2, 'ewh'), [2 1 3]);
verifyEqual(testCase, b3, G3, 'AbsTol', 1e-14);
tv = ncread(tmp2, 'time');
verifyEqual(testCase, numel(tv), 3);
verifyGreaterThan(testCase, tv(2), tv(1));
end

function testNormalFieldWGS84Values(testCase)
% closed form from defining constants vs published NIMA TR8350.2
[Cn, info] = shLowLevel.normalFieldCS(8);
verifyEqual(testCase, info.J2, 1.082629821313e-3, 'RelTol', 1e-12);
verifyEqual(testCase, Cn(3), -0.484166774985e-3, 'RelTol', 1e-11);
verifyEqual(testCase, Cn(5),  0.790303733511e-6, 'RelTol', 1e-10);
verifyEqual(testCase, Cn(7), -0.168724961151e-8, 'RelTol', 1e-9);
verifyEqual(testCase, Cn(9),  0.346052468394e-11, 'RelTol', 1e-8);
% odd degrees zero, degree 0 unity
verifyEqual(testCase, Cn([2 4 6 8]), zeros(4, 1));
verifyEqual(testCase, Cn(1), 1);
% GRS80 J2 hits its defining value through the derived flattening
[~, i80] = shLowLevel.normalFieldCS(2, System = "GRS80");
verifyEqual(testCase, i80.J2, 1.08263e-3, 'RelTol', 1e-8);
end

function testRescaleInvariance(testCase)
rng(91);
L = 12; n1 = L + 1;
C = tril(randn(n1)) * 1e-7; C(1, 1) = 1;
S = tril(randn(n1), -1) * 1e-7; S(:, 1) = 0;
GM1 = 3.986004415e14; R1 = 6378136.3;
GM2 = 3.986004418e14; R2 = 6378137.0;
g1 = shCoefficients(C, S, GM = GM1, R = R1);
g2 = g1.toReference(GM = GM2, R = R2);
% roundtrip identity
g3 = g2.toReference(GM = GM1, R = R1);
verifyEqual(testCase, g3.C, g1.C, 'RelTol', 1e-14);
% physical invariance: potential at points agrees (Python: exact)
lat = [12.5, -60]; lon = [33, 250];
% physical invariance: potential at a COMMON radius r = R2 + 100 km
V1r = g1.synthesis(lat, lon, Quantity = "potential", ...
    Height = R2 + 100e3 - R1, UseCache = false);
V2r = g2.synthesis(lat, lon, Quantity = "potential", ...
    Height = 100e3, UseCache = false);
verifyEqual(testCase, V1r, V2r, 'RelTol', 1e-12);
end

function testSubtractNormalField(testCase)
rng(92);
L = 10; n1 = L + 1;
GMm = 3.986004415e14; Rm = 6378136.3;
% construct a field = rescaled WGS84 normal field + known residual
[CnEll, infoN] = shLowLevel.normalFieldCS(L);
Cell = zeros(n1); Cell(:, 1) = CnEll;
CnResc = shLowLevel.rescaleGMR(Cell, zeros(n1), infoN.GM, infoN.a, GMm, Rm);
res = tril(randn(n1)) * 1e-9;
Sres = tril(randn(n1), -1) * 1e-9; Sres(:, 1) = 0;
g = shCoefficients(CnResc + res, Sres, GM = GMm, R = Rm);
out = g.subtractNormalField();
verifyEqual(testCase, out.C, g.C - CnResc, 'AbsTol', 1e-18);
verifyEqual(testCase, out.C(:, 1), g.C(:, 1) - CnResc(:, 1), 'AbsTol', 1e-18);
% zonals now at residual level, not 5e-4
verifyLessThan(testCase, abs(out.C(3, 1) - res(3, 1)), 1e-15);
% arithmetic guard: mismatched R errors with the documented ID
gW = shCoefficients(g.C, g.S, GM = infoN.GM, R = infoN.a);
verifyError(testCase, @() g - gW, 'shCoefficients:operands:constantsMismatch');
end

function testDiffSpectrumIdentities(testCase)
% v2.6.0 comparison suite: scaled field has degree correlation 1 and
% half the signal amplitude as difference; identical fields have zero
% difference and no crossover (Python-validated identities)
rng(5); L = 16;
g = randomField(L);
spec = shLowLevel.diffSpectrum(g.C, g.S, 0.5 * g.C, 0.5 * g.S);
verifyEqual(testCase, spec.degCorr(3:end), ones(L - 1, 1), 'AbsTol', 1e-12);
verifyEqual(testCase, spec.diffAmp, 0.5 * spec.amp1, 'RelTol', 1e-12);
verifyEqual(testCase, spec.ncross, NaN);
spec0 = shLowLevel.diffSpectrum(g.C, g.S, g.C, g.S);
verifyEqual(testCase, spec0.diffAmp, zeros(L + 1, 1), 'AbsTol', 0);
% a difference exceeding the signal from some degree sets ncross there
C2 = g.C; S2 = g.S;
C2(9:end, :) = C2(9:end, :) + 10 * max(abs(g.C(:)));
specX = shLowLevel.diffSpectrum(g.C, g.S, C2, S2);
verifyEqual(testCase, specX.ncross, 8);
end

function testSpatialStatsTaylorIdentity(testCase)
% weighted Taylor identity crmsd^2 = stdA^2 + stdB^2 - 2*stdA*stdB*corr,
% analytic bias on a constant offset, and mask handling
rng(6);
lat = -88:4:88; lon = 0:6:354;
A = randn(numel(lat), numel(lon));
B = 0.8 * A + 0.3 * randn(size(A));
st = shLowLevel.spatialStats(A, B, lat, lon);
verifyEqual(testCase, st.crmsd^2, ...
    st.stdA^2 + st.stdB^2 - 2 * st.stdA * st.stdB * st.corr, ...
    'RelTol', 1e-10);
st2 = shLowLevel.spatialStats(A, A - 3, lat, lon);
verifyEqual(testCase, st2.bias, 3, 'AbsTol', 1e-12);
verifyEqual(testCase, st2.rmsd, 3, 'AbsTol', 1e-12);
verifyEqual(testCase, st2.corr, 1, 'AbsTol', 1e-12);
mask = false(size(A)); mask(1:10, :) = true;
stM = shLowLevel.spatialStats(A, B, lat, lon, Mask = mask);
verifyEqual(testCase, stM.nUsed, nnz(mask));
end

function testNSEAndEffectiveCorr(testCase)
% NSE anchor points and the AR(1)-corrected effective sample size
rng(7); T = 240;
ref = randn(T, 1);
verifyEqual(testCase, shLowLevel.nashSutcliffe(ref, ref), 1, 'AbsTol', 1e-14);
verifyEqual(testCase, shLowLevel.nashSutcliffe(ref, mean(ref) * ones(T, 1)), ...
    0, 'AbsTol', 1e-12);
% white noise: Neff stays close to T
ecW = shLowLevel.effectiveCorr(randn(T, 1), randn(T, 1));
verifyGreaterThan(testCase, ecW.neff, 0.7 * T);
verifyTrue(testCase, ecW.p >= 0 && ecW.p <= 1);
% strong AR(1): Neff collapses well below T
x = filter(1, [1 -0.85], randn(T, 1));
y = filter(1, [1 -0.85], randn(T, 1));
ecA = shLowLevel.effectiveCorr(x, y);
verifyLessThan(testCase, ecA.neff, T / 2);
% perfect correlation stays finite
ecP = shLowLevel.effectiveCorr(x, 2 * x + 1);
verifyEqual(testCase, ecP.r, 1, 'AbsTol', 1e-12);
verifyTrue(testCase, isfinite(ecP.t) && ecP.p < 1e-6);
end

function testThreeCorneredHatRecovery(testCase)
% generalized TCH recovers injected noise levels (Python-validated to
% 1% at T = 20000; generous tolerance here at T = 8000)
rng(8); T = 8000;
sig = [1, 2, 3, 1.5];
common = 0.05 * cumsum(randn(T, 1));
X = common + randn(T, numel(sig)) .* sig;
out = shLowLevel.threeCorneredHat(X);
verifyEqual(testCase, out.sigma, sig, 'RelTol', 0.15);
verifyFalse(testCase, any(out.clipped));
verifyEqual(testCase, size(out.pairVar, 1), 6);
verifyError(testCase, @() shLowLevel.threeCorneredHat(X(:, 1:2)), ...
    'shLowLevel:threeCorneredHat:needThree');
end

function testCompareReports(testCase)
% aggregator contracts on the real ITSG chain (solutions) and a
% synthetic 3-center stack (series) incl. TCH ordering and epoch drops
d = shxTestDataDir();
fG = fullfile(d, 'ITSG-Grace2018_n60_2008-04.gfc');
verifyTrue(testCase, isfile(fG));
g = shCoefficients.read(fG, Epoch = 2008.29);
rep = shLowLevel.compareSolutions(g, g.gaussian(350), Names = ["raw", "G350"]);
verifyEqual(testCase, rep.nmax, 60);
% a pure smoothing difference is (1-w_n)*amp <= amp at every degree,
% so it NEVER crosses the signal: ncross = NaN is the correct result
% (finite-ncross behavior is covered in testDiffSpectrumIdentities)
verifyTrue(testCase, isnan(rep.spectral.ncross));
verifyTrue(testCase, isfinite(rep.chi2dof) && rep.chi2dof > 0);
verifyTrue(testCase, rep.spatial.corr > 0.5 && rep.spatial.corr <= 1);
verifyFalse(testCase, rep.rescaled);
% mixed degrees truncate to the smaller solution
rep2 = shLowLevel.compareSolutions(g, g.truncate(30));
verifyEqual(testCase, rep2.nmax, 30);
% ---- series: common signal + graded noise, one epoch missing in (3)
rng(9); L = 6; n1 = L + 1; T = 36;
tY = 2019 + (0:T-1)'/12;
Cs = 1e-9 * randn(n1, n1, T); Ss = 1e-9 * randn(n1, n1, T);
mk = @(s, sel) shSeries(Cs(:, :, sel) + s * 1e-11 * randn(n1, n1, nnz(sel)), ...
    Ss = Ss(:, :, sel) + s * 1e-11 * randn(n1, n1, nnz(sel)), ...
    Epochs = tY(sel));
all36 = true(T, 1); m35 = all36; m35(20) = false;
ts1 = mk(1, all36); ts2 = mk(2, all36); ts3 = mk(6, m35);
repS = shLowLevel.compareSeries({ts1, ts2, ts3}, Names = ["A", "B", "C"]);
verifyEqual(testCase, numel(repS.epochs), T - 1);      % common epochs
verifyEqual(testCase, repS.nDropped(3), 1);
verifyTrue(testCase, all(repS.nse(2:3) < 1));
verifyTrue(testCase, repS.tch.sigma(3) > repS.tch.sigma(2));
verifyTrue(testCase, all(isfinite(repS.trendZ(2:3))));
verifyTrue(testCase, all(abs(repS.phaseLagDays(2:3)) <= 183));
% Basin path: unit vector picks a single coefficient series
idx = shLowLevel.shIndex(L);
b = zeros(idx.P, 1); b(1) = 1;
repB = shLowLevel.compareSeries({ts1, ts2}, Basin = b, Idx = idx);
g1 = ts1.at(1);
x1 = shLowLevel.vecFromCS(g1.C, g1.S, idx);
verifyEqual(testCase, repB.y(1, 1), x1(1), 'AbsTol', 1e-15);
end

function testPoleTideConvert(testCase)
% v2.7.0: mean-pole convention conversion. Values pinned from the
% Python reference (validate_poletide.py): IERS2010 -> IERS2018,
% solid + ocean, at 2005.0 (cubic branch) and 2015.0 (linear branch).
% pins are measured on ZERO triangles so C2(3,2) IS the delta with no
% cancellation: measuring via (C2-C) on an O(1e-2) field carries
% eps*|C| ~ 1e-18 subtraction noise onto a 1e-10 quantity (found the
% hard way on CI). Python arithmetic is IEEE-identical -> bit-level pins.
Z = zeros(9);
[C2, S2] = shLowLevel.poleTideConvert(Z, Z, 2015.0);
verifyEqual(testCase, C2(3, 2), 8.954315329855e-11, 'AbsTol', 1e-22);
verifyEqual(testCase, S2(3, 2), 3.511349255389e-11, 'AbsTol', 1e-22);
[C5, S5] = shLowLevel.poleTideConvert(Z, Z, 2005.0);
verifyEqual(testCase, C5(3, 2), 1.098269022104e-11, 'AbsTol', 1e-22);
verifyEqual(testCase, S5(3, 2), -2.285129478668e-11, 'AbsTol', 1e-22);
% solid-only subset
[Cs, ~] = shLowLevel.poleTideConvert(Z, Z, 2005.0, Mode = "solid");
verifyEqual(testCase, Cs(3, 2), 9.361285926625e-12, 'AbsTol', 1e-22);
% roundtrip A->B->A on the zero field: sign-flipped deltas cancel exactly
[Cb, Sb] = shLowLevel.poleTideConvert(C2, S2, 2015.0, ...
    From = "IERS2018", To = "IERS2010");
verifyEqual(testCase, Cb(3, 2), 0, 'AbsTol', 0);
verifyEqual(testCase, Sb(3, 2), 0, 'AbsTol', 0);
% structure checks on a random field: ONLY (3,2) changes; A->A = 0
rng(21); L = 8;
g0 = randomField(L);
C = g0.C; S = g0.S;
[Cr, Sr] = shLowLevel.poleTideConvert(C, S, 2015.0);
D = Cr; D(3, 2) = C(3, 2);
verifyEqual(testCase, D, C, 'AbsTol', 0);
verifyNotEqual(testCase, Sr(3, 2), S(3, 2));
[Ca, Sa] = shLowLevel.poleTideConvert(C, S, 2015.0, To = "IERS2010");
verifyEqual(testCase, Ca, C, 'AbsTol', 0);
verifyEqual(testCase, Sa, S, 'AbsTol', 0);
% object form: epoch from the object, history through setCoefficient
d = shxTestDataDir();
fG = fullfile(d, 'ITSG-Grace2018_n60_2008-04.gfc');
verifyTrue(testCase, isfile(fG));
g = shCoefficients.read(fG, Epoch = 2008.29);
g18 = shLowLevel.poleTideConvert(g);
verifyNotEqual(testCase, g18.C(3, 2), g.C(3, 2));
verifyEqual(testCase, g18.C(4:end, :), g.C(4:end, :), 'AbsTol', 0);
verifyGreaterThan(testCase, numel(g18.history), numel(g.history));
end

function testSynthesisPoints(testCase)
% v3.0.0 pointwise synthesis: pinned against the Python reference
% (explicit deterministic field), radial identity dg = -dT/dr, and
% Nmin behaviour
GM = 3.986004415e14; R = 6378136.3;
C = zeros(5); S = zeros(5);
C(3,1) = 1.5e-7; C(3,2) = -2.0e-8; C(3,3) = 3.0e-8;
C(4,2) = 7.0e-9; C(5,5) = -4.0e-9;
S(3,2) = 1.0e-8; S(3,3) = -6.0e-9; S(4,4) = 2.5e-9; S(5,2) = -1.2e-9;
la = [37.5; -12.0]; lo = [22.0; 250.0]; r = [R; R + 450e3];
tp = shLowLevel.synthesisPoints(C, S, GM, R, la, lo, r);
verifyEqual(testCase, tp, [1.36712842337793; -9.60411712503133], ...
    'RelTol', 1e-12);
dg = shLowLevel.synthesisPoints(C, S, GM, R, la, lo, r, Quantity = "disturbance");
verifyEqual(testCase, dg, [7.37824053551527e-07; -4.18114227787271e-06], ...
    'RelTol', 1e-12);
da = shLowLevel.synthesisPoints(C, S, GM, R, la, lo, r, Quantity = "anomaly");
verifyEqual(testCase, da, [3.09131921845929e-07; -1.36804168846844e-06], ...
    'RelTol', 1e-12);
% radial identity at altitude: dg == -dT/dr (central differences)
la0 = 10; lo0 = 100; r0 = R + 200e3; d = 0.5;
Tm = shLowLevel.synthesisPoints(C, S, GM, R, la0, lo0, r0 - d);
Tp = shLowLevel.synthesisPoints(C, S, GM, R, la0, lo0, r0 + d);
an = shLowLevel.synthesisPoints(C, S, GM, R, la0, lo0, r0, Quantity = "disturbance");
verifyEqual(testCase, -(Tp - Tm) / (2 * d), an, 'RelTol', 1e-8);
% Nmin = 0 includes the central term GM/r
t0 = shLowLevel.synthesisPoints(0*C, 0*S, GM, R, 0, 0, R, Nmin = 0);
verifyEqual(testCase, t0, 0);                 % zero field, all degrees
tC = shLowLevel.synthesisPoints(C, S, GM, R, la, lo, r, Nmin = 3);
verifyNotEqual(testCase, tC(1), tp(1));
verifyError(testCase, @() shLowLevel.synthesisPoints(C, S, GM, R, la, lo(1), r), ...
    'shLowLevel:synthesisPoints:sizeMismatch');
end

function testSynthesisPointsMethodsAgree(testCase)
%TESTSYNTHESISPOINTSMETHODSAGREE v5.1.0 metamorphic: the two summations
%   in synthesisPoints evaluate the SAME series, so they must agree - but
%   they cannot agree bitwise, because Clenshaw sums the same terms in a
%   different order. The bound is the one measured by the committed
%   oracle tools/dev/validate_points_clenshaw.py, which reports 4e-15 at
%   nmax 60 and 2.8e-14 at nmax 120 over these quantities and Nmin
%   values; 5e-14 is about 2x that worst case, and bounds the reordering
%   of a sum of (nmax+1)^2/2 terms whose partial sums cancel.
tol = 5e-14;                                   % see the oracle, above
GM = 3.986004415e14; R = 6378136.3;
rng(31);
for nmax = [5 20 60]
    C = tril(randn(nmax+1)) * 1e-9;
    S = tril(randn(nmax+1), -1) * 1e-9;
    % near-pole latitudes included on purpose: that is where the u^m
    % factor is smallest and the two paths are most likely to part
    la = [89.9; -89.9; 0; 45.25; -12.5];
    lo = [10; 123; 271; 200; 355];
    rr = R + [0; 750; 100; 500; 1000];
    for q = ["potential", "disturbance", "anomaly"]
        for n0 = [0 2]
            vd = shLowLevel.synthesisPoints(C, S, GM, R, la, lo, rr, ...
                Quantity = q, Nmin = n0, Method = "direct");
            vc = shLowLevel.synthesisPoints(C, S, GM, R, la, lo, rr, ...
                Quantity = q, Nmin = n0, Method = "clenshaw");
            sc = max(max(abs(vd)), realmin);
            verifyLessThan(testCase, max(abs(vc - vd)) / sc, tol, ...
                sprintf('nmax=%d %s Nmin=%d', nmax, q, n0));
        end
    end
end
end

function testSynthesisPointsChunkingIsBitwise(testCase)
%TESTSYNTHESISPOINTSCHUNKINGISBITWISE v5.1.0: the "direct" path batches
%   legendreALF over a chunk of points. The recursion is elementwise in
%   latitude, so the chunk size cannot change a single bit - and that is
%   what makes "direct" the bitwise reference the pinned values in
%   testSynthesisPoints still rest on. MaxMemGB sets the chunk, so
%   driving it to one point per chunk and to all points at once must give
%   identical bits, not merely equal numbers.
GM = 3.986004415e14; R = 6378136.3;
rng(32);
nmax = 30;
C = tril(randn(nmax+1)) * 1e-9; S = tril(randn(nmax+1), -1) * 1e-9;
la = linspace(-88, 88, 40)'; lo = mod(7 * (1:40)', 360);
rr = R + (1:40)' * 25;
tiny = shLowLevel.synthesisPoints(C, S, GM, R, la, lo, rr, ...
    Method = "direct", MaxMemGB = 8 * (nmax+1)^2 / 2^30);   % chunk = 1
big  = shLowLevel.synthesisPoints(C, S, GM, R, la, lo, rr, ...
    Method = "direct", MaxMemGB = 4);
verifyTrue(testCase, isequal(tiny, big), ...
    'chunking changed the result - legendreALF is not elementwise in latitude');
end

function testRemoveGIASigmaQuadrature(testCase)
%TESTREMOVEGIASIGMAQUADRATURE WP5 5c: the GIA rate sigma enters the
%   per-epoch stacks in quadrature as sigmaRate*(t-T0), exactly.
%   Validated in tools/dev/validate_gia_sigma.py against a 20000-sample
%   Monte Carlo; here the closed form is checked to machine precision
%   because no sampling is involved.
nmax = 3; T = 12; n1 = nmax + 1;
ep = 2008 + (0:T-1)'/12;
rng(51);
Cs = zeros(n1, n1, T); Ss = zeros(n1, n1, T);
sC = 2e-11 * ones(n1); sS = 2e-11 * ones(n1);
SigCs = repmat(sC, 1, 1, T); SigSs = repmat(sS, 1, 1, T);
ts = shSeries(Cs, Ss = Ss, Epochs = ep, SigmaCs = SigCs, SigmaSs = SigSs);
rate = tril(ones(n1)) * 1e-11;
rsig = tril(ones(n1)) * 4e-12;
gia = shCoefficients(rate, tril(ones(n1), -1) * 1e-11);
sig = shCoefficients(rsig, tril(ones(n1), -1) * 4e-12);
[out, info] = ts.removeGIA(gia, Sigma = sig);
verifyTrue(testCase, info.propagated);
verifyTrue(testCase, info.correlated);
verifyFalse(testCase, info.sigmaWasEmpty);
verifyEqual(testCase, info.rateSigmaC, rsig, 'AbsTol', 0);
t0 = info.t0;
for k = 1:T
    dt = ep(k) - t0;
    want = sqrt(sC.^2 + (rsig * dt).^2);
    verifyEqual(testCase, out.sigmaCs(:, :, k), want, 'RelTol', 1e-14);
end
% the epoch nearest T0 gains essentially nothing; the ends gain most
[~, mid] = min(abs(ep - t0));
verifyLessThan(testCase, out.sigmaCs(1, 1, mid), out.sigmaCs(1, 1, 1));
end

function testRemoveGIASigmaMatchesMonteCarlo(testCase)
%TESTREMOVEGIASIGMAMATCHESMONTECARLO WP5 5c's named oracle, run in
%   MATLAB: analytic quadrature against a synthetic ensemble in which ONE
%   rate error is drawn per realisation and reused at every epoch (that
%   reuse IS the correlation the help warns about).
%   Tolerance: the sample standard deviation of a Gaussian has relative
%   standard error 1/sqrt(2N); at N = 4000 that is 1.1%, so 6% is about
%   5 sigma of the estimator - loose enough not to flake, far tighter
%   than the sqrt(T) = 3.5x error the independence mistake would make.
%   Cross-checked at 20000 samples in tools/dev/validate_gia_sigma.py.
rng(52);
T = 12; N = 4000;
ep = 2008 + (0:T-1)'/12;
t0 = mean(ep); dt = ep - t0;
sigmaIn = 2e-11; sigmaRate = 4e-12;
analytic = sqrt(sigmaIn^2 + (sigmaRate * dt).^2);
epsRate = sigmaRate * randn(N, 1);            % one per realisation
noise = sigmaIn * randn(N, T);
resid = noise - epsRate .* dt';               % what removeGIA leaves
empirical = std(resid, 0, 1)';
verifyEqual(testCase, empirical, analytic, 'RelTol', 0.06);
% and the claim the per-epoch stacks CANNOT carry: with the GIA term
% alone, the fitted rate sigma is sigmaRate itself, not the sqrt(T)
% smaller value an independence assumption would give
gonly = -epsRate .* dt';
A = [ones(T, 1), dt];
rates = (A \ gonly')';
verifyEqual(testCase, std(rates(:, 2)), sigmaRate, 'RelTol', 0.06);
end

function testRemoveGIAWithoutSigmaIsUnchanged(testCase)
%TESTREMOVEGIAWITHOUTSIGMAISUNCHANGED WP5 5c must not change the default
%   call: no Sigma anywhere means the coefficients are bitwise what
%   v5.1.1 produced and NO sigma stack is invented.
nmax = 3; T = 6; n1 = nmax + 1;
ep = 2008 + (0:T-1)'/12;
rng(53);
Cs = randn(n1, n1, T) * 1e-9; Ss = randn(n1, n1, T) * 1e-9;
ts = shSeries(Cs, Ss = Ss, Epochs = ep);
gia = shCoefficients(tril(ones(n1)) * 1e-11, tril(ones(n1), -1) * 1e-11);
[out, info] = ts.removeGIA(gia);
verifyFalse(testCase, info.propagated);
verifyEmpty(testCase, out.sigmaCs);
t0 = mean(ep);
for k = 1:T
    want = Cs(:, :, k) - gia.C * (ep(k) - t0);
    verifyTrue(testCase, isequal(out.Cs(:, :, k), want));
end
% a model that CARRIES sigmas propagates them without being asked
gsig = shCoefficients(gia.C, gia.S, ...
    SigmaC = tril(ones(n1)) * 3e-12, SigmaS = tril(ones(n1), -1) * 3e-12);
[out2, info2] = ts.removeGIA(gsig);
verifyTrue(testCase, info2.propagated);
verifyTrue(testCase, info2.sigmaWasEmpty);
verifySize(testCase, out2.sigmaCs, [n1 n1 T]);
end

function testDesignFilter(testCase)
% v3.1.0: W = (N + a*inv(S))^-1 N per order block. Diagonal gains and
% the full-covariance 2x2 block are pinned against the Python reference
% (validate_designfilter.py); format is readDDK-compatible.
L = 60;
sc = 3e-11 * ones(L+1); ss = sc;
[W, inf1] = shLowLevel.designFilter(sc, ss, Alpha = 1, Kaula = 1e-6);
gain = @(n) 1 ./ (1 + (3e-11 * n.^2 / 1e-6).^2);
b0 = W.blocks(strcmp({W.blocks.cs}, 'c') & [W.blocks.m] == 0);
d = diag(b0.M);
verifyEqual(testCase, d(b0.n == 10), gain(10), 'RelTol', 1e-12);
verifyEqual(testCase, d(b0.n == 30), gain(30), 'RelTol', 1e-12);
verifyEqual(testCase, d(b0.n == 60), gain(60), 'RelTol', 1e-12);
verifyTrue(testCase, inf1.gainRange(1) > 0 && inf1.gainRange(2) <= 1 + 1e-12);
% readDDK-compatible: applies through the standard machinery and damps
rng(41); g = randomField(L);
[Cf, Sf] = shLowLevel.applyDDK(g.C, g.S, W);
sp0 = shLowLevel.shDegreeRMS(g.C, g.S);
spF = shLowLevel.shDegreeRMS(Cf, Sf);
verifyLessThan(testCase, spF.degRMS(61), sp0.degRMS(61));
verifyEqual(testCase, spF.degRMS(4) / sp0.degRMS(4), 1, 'AbsTol', 1e-4);
% full-covariance block: pinned W2 from Python
idx = shLowLevel.shIndex(3);
P = idx.P;
Nn = eye(P); Ss2 = eye(P);
sel = [find(idx.n == 2 & idx.m == 2 & idx.cs == 0), ...
       find(idx.n == 3 & idx.m == 2 & idx.cs == 0)];
% Noise= carries the noise COVARIANCE; the implementation inverts it
% per block (N = inv(Cov)), so feed inv() of the Python reference's
% normal matrix here to reproduce the pinned W2
Nn(sel, sel) = inv([4, 1; 1, 3]);
Ss2(sel, sel) = [2, 0.5; 0.5, 1];
Wf = shLowLevel.designFilter(zeros(4), zeros(4), Alpha = 0.5, ...
    Noise = Nn, Signal = Ss2, Idx = idx);
bm = Wf.blocks(strcmp({Wf.blocks.cs}, 'c') & [Wf.blocks.m] == 2);
verifyEqual(testCase, bm.M, [0.92156862745098, 0.068627450980392; ...
    0.058823529411765, 0.823529411764706], 'RelTol', 1e-12);
verifyError(testCase, @() shLowLevel.designFilter(zeros(4), zeros(4), ...
    Noise = Nn), 'shLowLevel:designFilter:needIdx');
end

function testReadGFCFastPathEquivalence(testCase)
% v3.1.1: the bulk fast path (static files) and the legacy line parser
% must produce identical structs. Two files with the same gfc records -
% one pure static (fast path), one with an appended trnd line (forces
% the legacy branch) - are compared record by record. Verified live on
% PCWIN64 against 6 real fixtures incl. gz and gfct (28.6 s -> 0.21 s
% at n720; n2190 in 1.7 s).
rng(51); L = 40;
[nn, mm] = ndgrid(0:L, 0:L); keep = mm <= nn & nn >= 2;
n = nn(keep); m = mm(keep);
C = 1e-9 * randn(size(n)); S = 1e-9 * randn(size(n)); S(m == 0) = 0;
sC = 1e-12 * (1 + rand(size(n))); sS = sC * 0.9;
tmp = tempname; mkdir(tmp);
cl = onCleanup(@() rmIfFolder(tmp)); %#ok<NASGU>
head = sprintf(['product_type gravity_field\nmodelname eqtest\n' ...
    'earth_gravity_constant 3.986004415e14\nradius 6378136.3\n' ...
    'max_degree %d\nerrors formal\ntide_system zero_tide\nend_of_head\n'], L);
body = sprintf('gfc %5d %5d %19.12e %19.12e %12.5e %12.5e\n', ...
    [n m C S sC sS]');
f1 = fullfile(tmp, 'static.gfc');
fid = fopen(f1, 'w'); fprintf(fid, '%s%s', head, body); fclose(fid);
f2 = fullfile(tmp, 'variable.gfc');
fid = fopen(f2, 'w');
fprintf(fid, '%s%s', head, body);
fprintf(fid, 'trnd     2     0 %19.12e %19.12e 20080101.0000 20090101.0000\n', ...
    1e-12, 0);
fclose(fid);
g1 = shLowLevel.shReadGFC(f1);                 % bulk, static
g2 = shLowLevel.shReadGFC(f2);                 % bulk, variable (v3.1.1)
verifyEqual(testCase, g2.C, g1.C, 'AbsTol', 0);
verifyEqual(testCase, g2.S, g1.S, 'AbsTol', 0);
verifyEqual(testCase, g2.sigmaC, g1.sigmaC, 'AbsTol', 0);
verifyEqual(testCase, g1.nmax, L);
verifyEqual(testCase, size(g2.variableTerms, 1), 1);   % trnd captured
verifyTrue(testCase, isempty(g1.variableTerms) || ...
    size(g1.variableTerms, 1) == 0);
% header semantics identical between the two parsers
verifyEqual(testCase, g2.header, g1.header);
% v3.1.1: FORCE the legacy line parser with a dirty record (bulk
% rejects the file, legacy skips/NaNs it harmlessly at n=m=0) and
% require bit-for-bit agreement with the bulk-parsed variable file
f5 = fullfile(tmp, 'variable_dirty.gfc');
copyfile(f2, f5); fid = fopen(f5, 'a');
fprintf(fid, 'gfc 0 0 0.0 0.0 x y\n');
fclose(fid);
g5 = shLowLevel.shReadGFC(f5);                 % legacy path
verifyEqual(testCase, g5.C, g2.C, 'AbsTol', 0);
verifyEqual(testCase, g5.S, g2.S, 'AbsTol', 0);
verifyEqual(testCase, g5.sigmaC, g2.sigmaC, 'AbsTol', 0);
verifyEqual(testCase, g5.variableTerms, g2.variableTerms);
% v3.1.1 ragged groups (the EIGEN-5S pattern): ONE gfc line with a
% trailing epoch among uniform ones, plus gfct-1.0 and dot lines.
% Bulk must width-subgroup it and agree with forced-legacy bit-for-bit
f6 = fullfile(tmp, 'ragged.gfc');
fid = fopen(f6, 'w');
fprintf(fid, 'max_degree 4\nerrors formal\nend_of_head\n');
fprintf(fid, 'gfc 2 0 -4.84e-4 0.0 1.0e-13 0.0\n');
fprintf(fid, 'gfc 2 1 -2.7e-10 1.4e-9 7.8e-12 3.7e-11 20041001\n');
fprintf(fid, 'gfct 3 0 9.57e-7 0.0 1.1e-11 0.0 20041001\n');
fprintf(fid, 'dot 3 0 4.9e-12 0.0 0.0 0.0\n');
fprintf(fid, 'gfc 4 4 -4.0e-9 2.5e-9 1.0e-12 1.0e-12\n');
fclose(fid);
g6 = shLowLevel.shReadGFC(f6);                 % bulk, width subgroups
verifyEqual(testCase, g6.nmax, 4);             % NOT 20041001
verifyEqual(testCase, g6.C(3, 2), -2.7e-10, 'AbsTol', 0);
verifyEqual(testCase, g6.sigmaS(3, 2), 3.7e-11, 'AbsTol', 0);
f7 = fullfile(tmp, 'ragged_dirty.gfc');
copyfile(f6, f7); fid = fopen(f7, 'a');
fprintf(fid, 'gfc 0 0 0.0 0.0 x y\n');        % forces the line parser
fclose(fid);
g7 = shLowLevel.shReadGFC(f7);
verifyEqual(testCase, g7.C, g6.C, 'AbsTol', 0);
verifyEqual(testCase, g7.S, g6.S, 'AbsTol', 0);
verifyEqual(testCase, g7.sigmaC, g6.sigmaC, 'AbsTol', 0);
verifyEqual(testCase, g7.variableTerms, g6.variableTerms);
% FORTRAN D-exponents mid-file (the EIGEN-6C4 case): fast path must
% accept and match str2double semantics exactly
f3 = fullfile(tmp, 'dexp.gfc');
fid = fopen(f3, 'w');
fprintf(fid, 'max_degree 3\nerrors formal\nend_of_head\n');
fprintf(fid, 'gfc 2 0 -4.84165217061e-04 0.0 1.1081e-13 0.0\n');
fprintf(fid, 'gfc 3 0 0.983749337450D-11 0.000000000000D+00 0.7218D-12 0.0000D+00\n');
fprintf(fid, 'gfc 3 1 -.574259122710D-10 0.2D+00 0.7187D-12 0.1d-01\n');
fclose(fid);
g3 = shLowLevel.shReadGFC(f3);
% NOTE: str2double returns NaN for D-exponents (CI finding) - the
% legacy parser silently NaN'd such files before this fix. Pins are
% the true literal values; BOTH paths must produce them.
verifyEqual(testCase, g3.C(4, 1), 9.83749337450e-12, 'RelTol', 1e-15);
verifyEqual(testCase, g3.C(4, 2), -5.74259122710e-11, 'RelTol', 1e-15);
verifyEqual(testCase, g3.S(4, 2), 0.2, 'AbsTol', 0);
verifyEqual(testCase, g3.sigmaS(4, 2), 0.01, 'RelTol', 1e-15);
verifyEqual(testCase, g3.C(3, 1), -4.84165217061e-04, 'AbsTol', 0);
% same records + a trnd line = legacy branch must match on D-lines too
f4 = fullfile(tmp, 'dexp_var.gfc');
copyfile(f3, f4); fid = fopen(f4, 'a');
fprintf(fid, 'trnd 2 0 1.0e-12 0.0 20080101.0000 20090101.0000\n');
fclose(fid);
g4 = shLowLevel.shReadGFC(f4);
verifyEqual(testCase, g4.C(4, 1), 9.83749337450e-12, 'RelTol', 1e-15);
verifyEqual(testCase, g4.C(4, 2), -5.74259122710e-11, 'RelTol', 1e-15);
verifyEqual(testCase, g4.C(3:4, 1:2), g3.C(3:4, 1:2), 'AbsTol', 0);
end

function testSpectralFamilyIdentities(testCase)
rng(101);
L = 20; n1 = L + 1;
C = tril(randn(n1)) * 1e-8; S = tril(randn(n1), -1) * 1e-8; S(:, 1) = 0;
sC = abs(C) * 0.1; sS = abs(S) * 0.1;
sd = shLowLevel.shDegreeRMS(C, S, 'R', 6378136.3, 'SigmaC', sC, 'SigmaS', sS);
so = shLowLevel.shOrderRMS(C, S, SigmaC = sC, SigmaS = sS);
% degree/order marginals of the same total power
verifyEqual(testCase, sum(so.ordVariance), sum(sd.degVariance), ...
    'RelTol', 1e-14);
verifyEqual(testCase, sum(so.errVariance), sum(sd.errVariance), ...
    'RelTol', 1e-14);
% cumulative fields consistent
verifyEqual(testCase, sd.cumVariance(end), sum(sd.degVariance), 'RelTol', 1e-15);
verifyEqual(testCase, sd.cumRMS, sqrt(sd.cumVariance), 'AbsTol', 0);
verifyEqual(testCase, sd.cumAmplitude, 6378136.3 * sd.cumRMS, 'RelTol', 1e-15);
verifyEqual(testCase, so.cumVariance(end), sum(so.ordVariance), 'RelTol', 1e-15);
% conventions mirror: amplitude = R * RMS in both domains
verifyEqual(testCase, so.ordAmplitude, 6378136.3 * so.ordRMS, 'RelTol', 1e-15);
verifyEqual(testCase, so.domain, 'order');
verifyEqual(testCase, sd.domain, 'degree');
% n0 zeroing consistent between domains
sd2 = shLowLevel.shDegreeRMS(C, S, 'Nmin', 2);
so2 = shLowLevel.shOrderRMS(C, S, Nmin = 2);
verifyEqual(testCase, sum(so2.ordVariance), sum(sd2.degVariance), 'RelTol', 1e-14);
end

% ------------------------------------------------------ leakage (roadmap 8)
function [lat, lon, truth, obs, mask, nmax] = leakageFixture()
%LEAKAGEFIXTURE A 6-degree disc, filtered with a 500 km Gaussian.
%   The reference problem of tools/dev/validate_leakage.py: a cap near
%   the resolution limit, where a Gaussian removes about half the peak
%   and spreads the rest across the boundary.
nmax = 24;
nlat = 2 * nmax + 1;
nlon = 2 * nmax + 2;
lat = linspace(-89, 89, nlat);
lon = (0:nlon - 1) * (360 / nlon);          % uniform, full circle
[LO, LA] = meshgrid(lon, lat);
psi = acosd(sind(15) * sind(LA) + cosd(15) * cosd(LA) .* cosd(LO - 300));
truth = double(psi <= 6);
mask = truth > 0;
GM = 3.986004415e14; R = 6378136.3;
[C, S] = shLowLevel.shAnalysisGrid(truth, lat, lon, nmax, GM = GM, R = R);
w = shLowLevel.shGaussianWeights(nmax, 500);
obs = shLowLevel.shSynthesis(C .* w(:), S .* w(:), GM, R, lat, lon);
end

function testLeakageCorrectRecoversAKnownDisc(testCase)
%TESTLEAKAGECORRECTRECOVERSAKNOWNDISC Known truth in, known truth out.
%   Python-validated properties (tools/dev/validate_leakage.py): with an
%   exact mask the iteration recovers the disc, removes the leakage
%   outside it entirely, and beats the filtered field by a wide margin.
% noise-free synthetic data: the unregularised warning is expected
% here and would otherwise clutter every CI log
ws = warning('off', 'shLowLevel:leakageCorrect:unregularised');
cw = onCleanup(@() warning(ws)); %#ok<NASGU>
[lat, lon, ~, obs, mask, nmax] = leakageFixture();
verifyLessThan(testCase, max(obs(:)), 0.9, ...
    'the fixture must actually lose signal, or it tests nothing');

% Gain = 2 halves the iteration count on this problem (validated in
% tools/dev/validate_leakage.py; 3 is still stable, 5 diverges)
[m, info] = shLowLevel.leakageCorrect(obs, lat, lon, ...
    Filter = "gauss500", Mask = mask, Nmax = nmax, ...
    Gain = 2, MaxIter = 400, Quiet = true);
verifyTrue(testCase, info.converged, ...
    'the reference problem must converge within 400 iterations');
verifyEqual(testCase, mean(m(mask)), 1, 'AbsTol', 0.02);
verifyEqual(testCase, max(abs(m(~mask))), 0, 'AbsTol', 1e-12);

% the correction must be a large improvement, not a small one
errRaw = mean(abs(obs(mask) - 1));
errCor = mean(abs(m(mask) - 1));
verifyLessThan(testCase, errCor, errRaw / 5);

% info is the record of what happened
verifyEqual(testCase, info.nmax, nmax);
verifyEqual(testCase, info.filter, "gauss500");
verifyTrue(testCase, info.masked);
verifyEqual(testCase, numel(info.history), info.iterations);
verifyLessThan(testCase, info.history(end), info.history(1), ...
    'the residual must fall');
verifyEqual(testCase, numel(info.step), info.iterations);
verifyLessThan(testCase, info.step(end), 1e-4, ...
    'convergence is judged on the step, not the residual');
end

function testLeakageCorrectStopsOnTheDiscrepancyPrinciple(testCase)
%TESTLEAKAGECORRECTSTOPSONTHEDISCREPANCYPRINCIPLE Stopping IS regularisation.
%   The iteration semiconverges: the error against the truth falls, then
%   rises, while the residual keeps shrinking - so a step-size tolerance
%   is the wrong rule (validated in tools/dev/validate_stopping.py: the
%   final solution is 361x worse than the best, and Tol = 1e-3 stops 89x
%   past the optimum). With NoiseLevel the run stops when the residual
%   reaches the noise, which is what makes the answer reproducible.
[lat, lon, truth, obs, mask, nmax] = leakageFixture();
rng(17);
noise = 0.02 * max(abs(obs(:)));
obsN = obs + noise * randn(size(obs));

[mD, iD] = shLowLevel.leakageCorrect(obsN, lat, lon, Filter = "gauss500", ...
    Mask = mask, Nmax = nmax, Gain = 2, MaxIter = 400, ...
    NoiseLevel = noise, Quiet = true);
verifyEqual(testCase, iD.stoppedBy, "discrepancy");
verifyTrue(testCase, iD.converged);
verifyLessThanOrEqual(testCase, iD.residualRMS, 1.2 * noise * 1.001);
verifyLessThan(testCase, iD.iterations, 400, ...
    'the discrepancy principle must stop before the cap');

% and it must stop EARLIER and land CLOSER to the truth than running on
[mL, iL] = shLowLevel.leakageCorrect(obsN, lat, lon, Filter = "gauss500", ...
    Mask = mask, Nmax = nmax, Gain = 2, MaxIter = 400, Quiet = true);
verifyGreaterThan(testCase, iL.iterations, iD.iterations);
errD = norm(mD(mask) - truth(mask));
errL = norm(mL(mask) - truth(mask));
verifyLessThan(testCase, errD, errL, ...
    'stopping at the noise level must beat iterating past it');

% a run without NoiseLevel is unregularised and must say so out loud
verifyWarning(testCase, @() shLowLevel.leakageCorrect(obsN, lat, lon, ...
    Filter = "gauss500", Mask = mask, Nmax = nmax, MaxIter = 20, ...
    Quiet = true), 'shLowLevel:leakageCorrect:unregularised');

% The residual must be measured WHERE THE MODEL IS RESPONSIBLE. With a
% mask the model describes one region while the data contains signal
% everywhere else, so a GLOBAL residual never reaches the noise level
% and the principle silently never fires. Put a large signal far away
% and check the run still stops on the discrepancy.
far = obsN;
farBox = false(size(obsN));
farBox(5:12, 5:12) = true;                 % nowhere near the cap
far(farBox) = far(farBox) + 50 * noise;
[~, iF] = shLowLevel.leakageCorrect(far, lat, lon, Filter = "gauss500", ...
    Mask = mask, Nmax = nmax, Gain = 2, MaxIter = 400, ...
    NoiseLevel = noise, Quiet = true);
verifyEqual(testCase, iF.stoppedBy, "discrepancy", ...
    'unmodelled signal elsewhere must not prevent stopping');
verifyGreaterThan(testCase, iF.residualRMSGlobal, iF.residualRMS, ...
    'the global residual must exceed the regional one here');
% forcing the region to be global reproduces the failure
[~, iG2] = shLowLevel.leakageCorrect(far, lat, lon, Filter = "gauss500", ...
    Mask = mask, Nmax = nmax, Gain = 2, MaxIter = 40, ...
    NoiseLevel = noise, ResidualRegion = true(size(far)), Quiet = true);
verifyEqual(testCase, iG2.stoppedBy, "maxIter");

verifyError(testCase, @() shLowLevel.leakageCorrect(obsN, lat, lon, ...
    Mask = mask, Nmax = nmax, NoiseLevel = noise, ...
    ResidualRegion = false(size(obsN)), Quiet = true), ...
    'shLowLevel:leakageCorrect:emptyResidualRegion');

% Tau scales the stopping point
[~, iT] = shLowLevel.leakageCorrect(obsN, lat, lon, Filter = "gauss500", ...
    Mask = mask, Nmax = nmax, Gain = 2, MaxIter = 400, ...
    NoiseLevel = noise, Tau = 3, Quiet = true);
verifyLessThanOrEqual(testCase, iT.iterations, iD.iterations);
end

function testLeakageCorrectContract(testCase)
%TESTLEAKAGECORRECTCONTRACT Identity, zero, divergence, bad input.
% noise-free synthetic data: the unregularised warning is expected
% here and would otherwise clutter every CI log
ws = warning('off', 'shLowLevel:leakageCorrect:unregularised');
cw = onCleanup(@() warning(ws)); %#ok<NASGU>
[lat, lon, ~, obs, mask, nmax] = leakageFixture();

% Filter = "none" makes the chain the identity: one step, exact
[mi, ii] = shLowLevel.leakageCorrect(obs, lat, lon, Filter = "none", ...
    Nmax = nmax, Quiet = true);
verifyEqual(testCase, ii.iterations, 1);
verifyEqual(testCase, mi, obs, 'AbsTol', 1e-12);

% no mass in, no mass invented
z = shLowLevel.leakageCorrect(zeros(size(obs)), lat, lon, ...
    Filter = "gauss500", Nmax = nmax, Quiet = true);
verifyEqual(testCase, max(abs(z(:))), 0, 'AbsTol', 1e-15);

% a gain past the stability bound must be REFUSED, not returned: a
% diverged field looks like a result and would be used as one
verifyError(testCase, @() shLowLevel.leakageCorrect(obs, lat, lon, ...
    Filter = "gauss500", Mask = mask, Nmax = nmax, Gain = 40, ...
    Quiet = true), 'shLowLevel:leakageCorrect:diverged');

verifyError(testCase, @() shLowLevel.leakageCorrect(obs(1:3, :), lat, ...
    lon, Nmax = nmax, Quiet = true), 'shLowLevel:leakageCorrect:badSize');
verifyError(testCase, @() shLowLevel.leakageCorrect(obs, lat, lon, ...
    Mask = false(size(obs)), Nmax = nmax, Quiet = true), ...
    'shLowLevel:leakageCorrect:emptyMask');
verifyError(testCase, @() shLowLevel.leakageCorrect(obs, lat, lon, ...
    Filter = "bogus", Nmax = nmax, Quiet = true), ...
    'shLowLevel:leakageCorrect:badFilter');
end

function testGridScalingFactors(testCase)
%TESTGRIDSCALINGFACTORS Per-pixel k: > 1 on signal, NaN where blind.
%   Python-validated: k is amplitude-invariant (it depends on the model
%   PATTERN, not its scale) and must be NaN where the model carries no
%   signal, rather than a ratio of two numerical zeros multiplying the
%   user's data.
% noise-free synthetic data: the unregularised warning is expected
% here and would otherwise clutter every CI log
ws = warning('off', 'shLowLevel:leakageCorrect:unregularised');
cw = onCleanup(@() warning(ws)); %#ok<NASGU>
[lat, lon, truth, ~, mask, nmax] = leakageFixture();
amp = 1 + 0.4 * sin(2 * pi * (0:23) / 12);
model = truth .* reshape(amp, 1, 1, []);

[k, info] = shLowLevel.gridScaling(model, lat, lon, ...
    Filter = "gauss500", Nmax = nmax, Quiet = true);

% a smoother attenuates, so restoring it needs k > 1 inside the basin
verifyGreaterThan(testCase, median(k(mask), 'omitnan'), 1);
verifyEqual(testCase, info.epochs, 24);
verifyEqual(testCase, info.filter, "gauss500");
verifyGreaterThan(testCase, info.onSignal, 0);
verifyGreaterThan(testCase, info.kMedian, 1, ...
    'the summary must describe the pixels the model gives mass to');

% amplitude invariance to machine precision
k2 = shLowLevel.gridScaling(model * 1000, lat, lon, ...
    Filter = "gauss500", Nmax = nmax, Quiet = true);
verifyEqual(testCase, k2(mask), k(mask), 'AbsTol', 1e-12);

% blind pixels are NaN, never a number
verifyTrue(testCase, any(isnan(k(:))), ...
    'pixels the model cannot see must be NaN');
verifyFalse(testCase, any(isnan(k(mask))), ...
    'the basin the model describes must have finite factors');

% Clip bounds the factors and counts what it touched
[kc, ic] = shLowLevel.gridScaling(model, lat, lon, Filter = "gauss500", ...
    Nmax = nmax, Clip = [0.5 1.2], Quiet = true);
verifyLessThanOrEqual(testCase, max(kc(:)), 1.2);
verifyGreaterThan(testCase, ic.clipped, 0);

verifyError(testCase, @() shLowLevel.gridScaling(model, lat, lon, ...
    Clip = [2 1], Nmax = nmax, Quiet = true), ...
    'shLowLevel:gridScaling:badClip');
end

% ------------------------------------------------ GRAVIS SHM (roadmap 9)
function testReadSHMFieldAndRate(testCase)
%TESTREADSHMFIELDANDRATE The GRAVIS Level-2B format, both record types.
%   GRAVIS products are not ICGEM gfc: a YAML header, then GRCOF2
%   records for a FIELD or GRDOTA records for a RATE in 1/yr. The
%   keyword is the only thing telling the two apart, so reading them
%   with the wrong assumption is how a rate silently becomes a field.
%   Values pinned from tools/dev/validate_shm.py against the full files.
dd = testCase.TestData.dataDir;

M = shLowLevel.readSHM(fullfile(dd, 'GRAVIS-2B_MEAN_n10_trimmed.shm'));
verifyEqual(testCase, M.kind, "GRCOF2");
verifyEqual(testCase, M.GM, 3.9860044150E+14, 'RelTol', 1e-12);
verifyEqual(testCase, M.R, 6.3781364600E+06, 'RelTol', 1e-12);
verifyEqual(testCase, M.nmax, 10);
verifyEqual(testCase, M.C(1, 1), 1, 'AbsTol', 1e-15, ...
    'C00 of a field is 1 by definition');
verifyEqual(testCase, M.C(3, 1), -4.841651265210E-04, 'RelTol', 1e-12);
verifyEqual(testCase, M.sigmaC(3, 1), 3.0810E-13, 'RelTol', 1e-4);
verifyTrue(testCase, istriu(M.C') && all(M.C(1, 2:end) == 0), ...
    'the C(n+1,m+1) layout must be lower triangular');

G = shLowLevel.readSHM(fullfile(dd, ...
    'GRAVIS-2B_GIA_ICE-6G_D_VM5a_n10_trimmed.shm'));
verifyEqual(testCase, G.kind, "GRDOTA");
verifyEmpty(testCase, G.sigmaC, 'a rate model carries no sigmas');
verifyEqual(testCase, G.C(3, 1), 1.381730030000E-11, 'RelTol', 1e-12);
verifyEqual(testCase, G.C(3, 2), -2.519201320000E-12, 'RelTol', 1e-12);
verifyEqual(testCase, G.S(3, 2), 1.185349120000E-11, 'RelTol', 1e-12);
% degrees 0 and 1 vanish in this GIA model
verifyEqual(testCase, G.C(1:2, 1:2), zeros(2), 'AbsTol', 1e-20);

% the gzip path must give the identical result
Gz = shLowLevel.readSHM(fullfile(dd, ...
    'GRAVIS-2B_GIA_ICE-6G_D_VM5a_n10_trimmed.shm.gz'));
verifyEqual(testCase, Gz.C, G.C);
verifyEqual(testCase, Gz.S, G.S);

% Nmax truncates while reading
G4 = shLowLevel.readSHM(fullfile(dd, ...
    'GRAVIS-2B_GIA_ICE-6G_D_VM5a_n10_trimmed.shm'), Nmax = 4);
verifyEqual(testCase, G4.nmax, 4);
verifyEqual(testCase, G4.C, G.C(1:5, 1:5));

% a gfc is not an SHM file and must say so rather than return nonsense
verifyError(testCase, @() shLowLevel.readSHM(fullfile(dd, ...
    'ITSG-Grace2018_n60_2008-04.gfc')), 'shLowLevel:readSHM:noHeaderEnd');
verifyError(testCase, @() shLowLevel.readSHM(fullfile(dd, 'nope.shm')), ...
    'shLowLevel:readSHM:noFile');

% and a GIA rate drops straight into the chain's GIA option
gia = shCoefficients(G.C, G.S, GM = G.GM, R = G.R);
verifyEqual(testCase, gia.C(3, 1), G.C(3, 1));
end

% ------------------------------------------------- S2 tidal alias removal
function testRemoveAliasRecoversAKnownHarmonic(testCase)
%TESTREMOVEALIASRECOVERSAKNOWNHARMONIC The 161-day alias, phase offset and all.
%   Pinned against tools/dev/validate_alias.py: the harmonic is removed
%   exactly, the deterministic terms it was fitted with survive
%   untouched, and the GRACE/GRACE-FO phase offset demonstrably matters.
n1 = 5;
t = [(2004:1/12:2016.99)'; (2018.6:1/12:2025.99)'];   % with the gap
T = numel(t);
P = 161/365.25;
split = 2018.0;
a = 2*pi*t/P + deg2rad(100)*(t >= split);
Cs = zeros(n1, n1, T); Ss = Cs;
trend = 3e-11; ampC = 7e-11; ampS = -4e-11;
for k = 1:T
    Cs(3,1,k) = 1e-9 + trend*(t(k)-2015) + ampC*cos(a(k)) + ampS*sin(a(k)) ...
        + 5e-10*cos(2*pi*t(k));
    Cs(4,2,k) = ampC*cos(a(k));
end
ts = shSeries(Cs, Ss = Ss, Epochs = t);

out = ts.removeAlias();
% the alias is gone: refitting finds nothing left at that period
A = [ones(T,1), t-mean(t), cos(2*pi*t), sin(2*pi*t), ...
     cos(4*pi*t), sin(4*pi*t), cos(a), sin(a)];
c = A \ squeeze(out.Cs(3,1,:));
verifyEqual(testCase, c(7:8), [0; 0], 'AbsTol', 1e-22, ...
    'no alias may remain after removal');
% and the trend survives exactly
verifyEqual(testCase, c(2), trend, 'RelTol', 1e-8, ...
    'removing the alias must not touch the trend');
% a coefficient that was pure alias is now zero
verifyEqual(testCase, max(abs(out.Cs(4,2,:))), 0, 'AbsTol', 1e-22);
% history records the parameters actually used
verifyTrue(testCase, any(contains(out.history, "alias removed")));
verifyTrue(testCase, any(contains(out.history, "161.0 d")));

% the phase offset matters: removing with the wrong one leaves residual
bad = ts.removeAlias(PhaseOffset = 0);
cb = A \ squeeze(bad.Cs(3,1,:));
verifyGreaterThan(testCase, norm(cb(7:8)), 1e-11, ...
    'ignoring the offset must leave the alias only partly removed');

% Too short a record must be refused. Note this is NOT a rank or
% conditioning failure: a one-year span gives a full-rank design with a
% condition number of 38 and a completely meaningless fit, so the guard
% has to test degrees of freedom and alias cycles instead.
short = ts.select(t < 2005);
verifyEqual(testCase, short.nEpochs, 12);
verifyError(testCase, @() short.removeAlias(), ...
    'shSeries:removeAlias:tooShort');
% and a record long enough in span but too sparse is refused too
sparse5 = ts.select(ismember(t, t(1:40:end)));
verifyError(testCase, @() sparse5.removeAlias(), ...
    'shSeries:removeAlias:tooShort');
end

% --------------------------------------------------- open-ocean RMS metric
function testOceanRMSErosionAndWeighting(testCase)
%TESTOCEANRMSEROSIONANDWEIGHTING The GRACE noise metric, both halves right.
%   Pinned against tools/dev/validate_oceanrms.py: the erosion must move
%   the boundary by exactly the requested distance, and the average must
%   be area-weighted (an unweighted RMS over a lat/lon grid over-counts
%   the polar rows, which white noise hides and structure exposes).
lat = -89:2:89;
lon = 0:2:358;
[LO, LA] = meshgrid(lon, lat);
% "land" = a 30 degree cap at the north pole
psi = acosd(min(1, max(-1, sind(90) * sind(LA))));
isOcean = psi > 30;

% erosion moves the boundary by d/R, to within a grid step
for d = [0 1000 2000]
    [~, info] = shLowLevel.oceanRMS(ones(size(LA)), lat, lon, isOcean, ...
        MinDistanceKm = d);
    edge = min(psi(info.mask));
    verifyEqual(testCase, edge, 30 + rad2deg(d / 6371), 'AbsTol', 2.5, ...
        sprintf('erosion by %d km', d));
end
[~, i0] = shLowLevel.oceanRMS(ones(size(LA)), lat, lon, isOcean, MinDistanceKm = 0);
[~, i2] = shLowLevel.oceanRMS(ones(size(LA)), lat, lon, isOcean, MinDistanceKm = 2000);
verifyLessThan(testCase, i2.nPixels, i0.nPixels, 'erosion must remove points');

% area weighting: mean of cos^2 over the sphere is 2/3
f = cosd(LA);
r = shLowLevel.oceanRMS(f, lat, lon, true(size(LA)), MinDistanceKm = 0);
verifyEqual(testCase, r^2, 2/3, 'AbsTol', 0.01);
ru = shLowLevel.oceanRMS(f, lat, lon, true(size(LA)), MinDistanceKm = 0, ...
    Weighted = false);
verifyLessThan(testCase, ru, r, ...
    'the unweighted RMS must over-count the small polar values');

% on white noise the two agree - which is why the difference is easy to
% miss until the field has structure
rng(1);
g = randn(size(LA));
rw = shLowLevel.oceanRMS(g, lat, lon, true(size(LA)), MinDistanceKm = 0);
rn = shLowLevel.oceanRMS(g, lat, lon, true(size(LA)), MinDistanceKm = 0, ...
    Weighted = false);
verifyEqual(testCase, rw, rn, 'RelTol', 0.05);

% a function-handle mask is equivalent to the logical one
rh = shLowLevel.oceanRMS(g, lat, lon, @(la, lo) la < 0, MinDistanceKm = 0);
rl = shLowLevel.oceanRMS(g, lat, lon, LA < 0, MinDistanceKm = 0);
verifyEqual(testCase, rh, rl);

% and it feeds leakageCorrect: a noise level in the field's own units
verifyGreaterThan(testCase, rw, 0);
verifyError(testCase, @() shLowLevel.oceanRMS(g, lat, lon, ...
    false(size(LA))), 'shLowLevel:oceanRMS:emptyOcean');
verifyError(testCase, @() shLowLevel.oceanRMS(g(1:3,:), lat, lon, ...
    true(size(LA))), 'shLowLevel:oceanRMS:badSize');
end

% ------------------------------------------ self-consistent degree 1
function testEstimateDegree1RecoversAKnownGeocentre(testCase)
%TESTESTIMATEDEGREE1RECOVERSAKNOWNGEOCENTRE Swenson et al. (2008).
%   Build a world whose degree-1 content is known, blind the "observer"
%   to it, and check it comes back. Pinned against
%   tools/dev/validate_degree1.py.
lat = -89:4:89;
lon = 0:4:356;
[LO, LA] = meshgrid(lon, lat);
kn = [0; 0.021; -0.3054; -0.1960; zeros(17, 1)];   % degree-1 in CF
ocean = ~(((LA > 10) & (LA < 70) & (LO > 250) & (LO < 350)) | ...
          ((LA > -40) & (LA < 30) & (LO > 10) & (LO < 60)));
verifyGreaterThan(testCase, nnz(ocean) / numel(ocean), 0.5);

% a truth field with real degree-1 content, then observe it WITHOUT
nmax = 12;
truth = zeros(size(LA));
truth(~ocean) = 0.05 * sind(3 * LO(~ocean));
oceanModel = zeros(size(LA));
oceanModel(ocean) = 0.01 * cosd(2 * LA(ocean));
truth = truth + oceanModel;
gT = shCoefficients.analysis(truth, lat, lon, nmax, Quantity = "ewh", ...
    kn = kn);
c10 = gT.C(2, 1); c11 = gT.C(2, 2); s11 = gT.S(2, 2);
verifyGreaterThan(testCase, abs(c10) + abs(c11) + abs(s11), 0, ...
    'the truth must actually contain degree 1, or nothing is tested');

gObs = gT;                                  % GRACE is blind to degree 1
Cs = gObs.C; Ss = gObs.S;
Cs(2, :) = 0; Ss(2, :) = 0;
ts = shSeries(cat(3, Cs, Cs), Ss = cat(3, Ss, Ss), ...
    Epochs = [2008.0; 2008.1]);

[d1, info] = shLowLevel.estimateDegree1(ts, ocean, kn = kn, ...
    OceanModel = oceanModel, LatDeg = lat, LonDeg = lon, Nmax = nmax);
verifyEqual(testCase, numel(d1.C10), 2);
verifyEqual(testCase, d1.C10(1), c10, 'RelTol', 0.05);
verifyEqual(testCase, d1.C11(1), c11, 'RelTol', 0.05);
verifyEqual(testCase, d1.S11(1), s11, 'RelTol', 0.05);
verifyEqual(testCase, d1.epoch, ts.epochs(:));
verifyLessThan(testCase, info.cond(1), 5, ...
    'a global ocean must give a well-conditioned system');
% the sigmas addDegree1 requires must be there - a table without them is
% not a TN-13 drop-in, however the help describes it
for f = ["sigC10", "sigC11", "sigS11", "t0", "t1"]
    verifyTrue(testCase, isfield(d1, f), "missing field " + f);
end
verifyGreaterThan(testCase, d1.sigC10(1), 0);

% the result plugs into addDegree1 exactly like a TN-13 table
tsD = ts.addDegree1(d1);
verifyEqual(testCase, tsD.Cs(2, 1, 1), d1.C10(1), 'RelTol', 1e-12);

% omitting the ocean model biases the answer, and says so
verifyWarning(testCase, @() shLowLevel.estimateDegree1(ts, ocean, ...
    kn = kn, LatDeg = lat, LonDeg = lon, Nmax = nmax), ...
    'shLowLevel:estimateDegree1:noOceanModel');

% a degenerate ocean domain raises the condition number - the warning a
% user can see without knowing the truth
[~, iP] = shLowLevel.estimateDegree1(ts, ocean & (LA > 60), kn = kn, ...
    OceanModel = oceanModel, LatDeg = lat, LonDeg = lon, Nmax = nmax);
verifyGreaterThan(testCase, iP.cond(1), 3 * info.cond(1));
% cond must report the GEOMETRY, not the column units: an unequilibrated
% design matrix reported 3.8e7 on a problem whose geometry is fine
verifyLessThan(testCase, info.cond(1), 100, ...
    'cond must be equilibrated, or it reports units not geometry');

% Love numbers are never assumed
verifyError(testCase, @() shLowLevel.estimateDegree1(ts, ocean, ...
    LatDeg = lat, LonDeg = lon), ...
    'shLowLevel:estimateDegree1:noLoveNumbers');
verifyError(testCase, @() shLowLevel.estimateDegree1(ts, ...
    false(size(LA)), kn = kn, LatDeg = lat, LonDeg = lon), ...
    'shLowLevel:estimateDegree1:emptyOcean');
end

% ------------------------------------------- tailored sensitivity kernels
function testSensitivityKernelTradeOff(testCase)
%TESTSENSITIVITYKERNELTRADEOFF Alpha must be a real dial, not a knob.
%   Pinned against tools/dev/validate_senskernel.py: the two limits are
%   exact, leakage rises and noise falls monotonically with Alpha, and
%   at matched noise the tailored kernel leaks less than a Gaussian.
idx = shLowLevel.shIndex(30, Nmin = 0);
cap = @(la, lo) double(acosd(min(1, max(-1, sind(15) * sind(la) + ...
    cosd(15) * cosd(la) .* cosd(lo - 300)))) <= 10);

% Alpha = 0 returns the exact indicator
[k0, i0] = shLowLevel.sensitivityKernel(idx, cap, Alpha = 0);
verifyEqual(testCase, k0, i0.kExact, 'AbsTol', 1e-14);
verifyEqual(testCase, i0.leakage, 0, 'AbsTol', 1e-14);
verifyEqual(testCase, i0.gain, 1, 'RelTol', 1e-12);

% the unit-response constraint holds at every Alpha. Without it the
% cheapest way to cut noise is to shrink the kernel to nothing: gain
% fell to 0.28 at Alpha = 0.1 during development, i.e. the "optimal"
% kernel measured almost none of the basin it was averaging.
for a = [0.01 1 100 1e6]
    [~, iG] = shLowLevel.sensitivityKernel(idx, cap, Alpha = a);
    verifyEqual(testCase, iG.gain, 1, 'RelTol', 1e-10, ...
        sprintf('gain must stay 1 at Alpha = %g', a));
end

% monotone in both directions: that is what makes Alpha a trade-off
alphas = logspace(-2, 6, 9);
L = zeros(size(alphas)); S = zeros(size(alphas));
for j = 1:numel(alphas)
    [~, inf1] = shLowLevel.sensitivityKernel(idx, cap, Alpha = alphas(j));
    L(j) = inf1.leakage; S(j) = inf1.noise;
end
verifyTrue(testCase, all(diff(L) > 0), 'leakage must grow with Alpha');
verifyTrue(testCase, all(diff(S) < 0), 'noise must fall with Alpha');

% At matched noise AND matched gain it must leak less than a Gaussian -
% the whole claim of the method. The Gaussian has to be renormalised to
% unit gain too, or the comparison comes out backwards for the trivial
% reason that a shrunken kernel is quiet.
[~, it] = shLowLevel.sensitivityKernel(idx, cap, Alpha = 1);
mVec = 1 ./ (idx.n(:) + 1);
nVec = (1 + (idx.n(:) / 8).^3).^2;
kk = i0.kExact' * i0.kExact;
best = inf; bestL = inf;
for r = 50:25:4000
    wg = shLowLevel.shGaussianWeights(idx.Lmax, r);
    kg = i0.kExact .* wg(idx.n + 1);
    kg = kg * kk / (kg' * i0.kExact);          % renormalise to unit gain
    sg = sqrt(sum(nVec .* kg.^2));
    if abs(sg - it.noise) < best
        best = abs(sg - it.noise);
        bestL = sqrt(sum(mVec .* (kg - i0.kExact).^2));
    end
end
verifyLessThan(testCase, it.leakage, bestL, ...
    'the tailored kernel must leak less than a Gaussian at equal noise');

% a full covariance is accepted and gives the same answer as its
% diagonal when it IS diagonal
Nd = diag(nVec);
[kf, ifu] = shLowLevel.sensitivityKernel(idx, cap, Alpha = 10, Noise = Nd);
[kv, ivu] = shLowLevel.sensitivityKernel(idx, cap, Alpha = 10, ...
    Noise = sqrt(nVec));
verifyEqual(testCase, kf, kv, 'RelTol', 1e-10);
verifyEqual(testCase, ifu.noise, ivu.noise, 'RelTol', 1e-10);

verifyError(testCase, @() shLowLevel.sensitivityKernel(idx, cap, ...
    Noise = ones(3, 1)), 'shLowLevel:sensitivityKernel:badNoise');
verifyError(testCase, @() shLowLevel.sensitivityKernel(idx, cap, ...
    FarField = ones(3, 1)), 'shLowLevel:sensitivityKernel:badFarField');
end

% ---------------------------------------------------- audit regressions
function testKernelFactorsLoveNumberContract(testCase)
%TESTKERNELFACTORSLOVENUMBERCONTRACT Audit F-13/F-19.
%   A short kn used to die as MATLAB:badsubscript; 1+kn = 0 (the CM-frame
%   k1 = -1 convention, shipped in GROOPS' own ak135 files) produced a
%   silent Inf kernel.
d = shxTestDataDir();
kn = readmatrix(fullfile(d, 'loadLoveNumbers_Gegout97.txt'), ...
    FileType = 'text', NumHeaderLines = 2);
verifyError(testCase, @() shLowLevel.kernelFactors("ewh", 60, ...
    3.986004415e14, 6378136.3, kn = kn(1:31)), ...
    'shLowLevel:kernelFactors:knTooShort');
knBad = kn; knBad(2) = -1;
verifyError(testCase, @() shLowLevel.kernelFactors("ewh", 5, ...
    3.986004415e14, 6378136.3, kn = knBad), ...
    'shLowLevel:kernelFactors:badLoveNumbers');
% and the valid path is untouched
kf = shLowLevel.kernelFactors("ewh", 5, 3.986004415e14, 6378136.3, kn = kn);
verifyTrue(testCase, all(isfinite(kf(:))));
end

function testSensitivityKernelFullCovariancePath(testCase)
%TESTSENSITIVITYKERNELFULLCOVARIANCEPATH The matrix Noise input is used
%   IN FULL: a diagonal matrix must reproduce the vector path exactly,
%   and off-diagonal correlations must change the propagated noise -
%   pinning that the solve routes through the full covariance.
idx = shLowLevel.shIndex(12, Nmin = 0);
cap = @(la, lo) double(acosd(min(1, max(-1, sind(20)*sind(la) + ...
    cosd(20)*cosd(la).*cosd(lo - 40)))) <= 15);
sig = 1 + (idx.n / 5).^2;
[k1, i1] = shLowLevel.sensitivityKernel(idx, cap, Alpha = 0.5, Noise = sig);
[k2, i2] = shLowLevel.sensitivityKernel(idx, cap, Alpha = 0.5, ...
    Noise = diag(sig.^2));
verifyEqual(testCase, k2, k1, 'AbsTol', 1e-10 * max(abs(k1)));
verifyEqual(testCase, i2.noise, i1.noise, 'RelTol', 1e-10);
% strong off-diagonal correlation between two low-degree rows
Nf = diag(sig.^2);
Nf(2, 5) = 0.9 * sig(2) * sig(5); Nf(5, 2) = Nf(2, 5);
[k3, i3] = shLowLevel.sensitivityKernel(idx, cap, Alpha = 0.5, Noise = Nf);
verifyGreaterThan(testCase, abs(i3.noise - i1.noise), 1e-8 * i1.noise, ...
    'off-diagonals must reach the noise metric - diag-only would not');
verifyGreaterThan(testCase, norm(k3 - k1), 0, ...
    'off-diagonals must reach the solve');
verifyEqual(testCase, i3.gain, 1, 'RelTol', 1e-10);
end

function testLeakageCorrectRejectsNaNInsideMask(testCase)
%TESTLEAKAGECORRECTREJECTSNANINSIDEMASK Audit F-20: non-finite data where
%   the model or the stopping rule looks must error with the CAUSE, not
%   diverge; NaN outside both regions stays tolerated.
lat = (-89:4:89)'; lon = (1:4:359)';
rng(3); obs = randn(numel(lat), numel(lon));
mk = false(size(obs)); mk(20:30, 40:60) = true;
bad = obs; bad(25, 50) = NaN;
verifyError(testCase, @() shLowLevel.leakageCorrect(bad, lat, lon, ...
    Mask = mk, Filter = "gauss500", NoiseLevel = 1e-3, Quiet = true), ...
    'shLowLevel:leakageCorrect:nanInput');
ok = obs; ok(1, 1) = NaN;                       % far outside mask
[m, info] = shLowLevel.leakageCorrect(ok, lat, lon, Mask = mk, ...
    Filter = "gauss500", NoiseLevel = 1e-3, MaxIter = 5, Quiet = true);
verifyTrue(testCase, all(isfinite(m(mk))));
verifyTrue(testCase, info.iterations >= 1);
end

function testSlepianCapCrossValidation(testCase)
%TESTSLEPIANCAPCROSSVALIDATION v3.9.0: cross-validate the Gauss-Legendre
%   localization kernel against an INDEPENDENT Python ring-quadrature
%   reference (0.5-deg graticule, lpmv): 30-deg polar cap, Lmax 12 ->
%   lambda_1 = 0.999981, Shannon = P * (1-cosd(30))/2 = 11.32. Two
%   implementations, two quadratures, same physics.
idx = shLowLevel.shIndex(12, Nmin = 0);
% OverSample 8: the mask-quadrature area converges to the analytic cap
% (at the default 2 the quantization error is 7.5% - measured, not
% assumed)
[~, lam, info] = shLowLevel.slepianBasis(idx, @(la, lo) double(la > 60), ...
    NKeep = 3, OverSample = 8);
verifyEqual(testCase, lam(1), 0.999981, AbsTol = 2e-4);   % Python ref
verifyEqual(testCase, info.shannon, info.areaFraction * idx.P, ...
    RelTol = 1e-10);                                       % exact identity
verifyEqual(testCase, info.areaFraction, (1 - cosd(30)) / 2, ...
    RelTol = 0.02);   % boundary quantization converges O(1/NLat) - measured
end

function testSlepianProjectRoundtrip(testCase)
%TESTSLEPIANPROJECTROUNDTRIP the application half (roadmap item 8): a
%   field fully concentrated in the region survives projection onto the
%   ~Shannon leading tapers nearly unchanged; the reconstruction repack
%   is exact for K = P.
idx = shLowLevel.shIndex(12, Nmin = 0);
[G, ~, info] = shLowLevel.slepianBasis(idx, @(la, lo) double(la > 60));
% concentrated test field: leading taper itself, repacked to (C, S)
Cs = zeros(idx.Lmax+1, idx.Lmax+1); Ss = Cs;
li = sub2ind(size(Cs), idx.n(:)+1, idx.m(:)+1); isC = idx.cs(:) == 0;
Cs(li(isC)) = G(isC, 1); Ss(li(~isC)) = G(~isC, 1);
% K = P: exact roundtrip
[aF, recF] = shLowLevel.slepianProject(Cs, Ss, G, idx);
verifyEqual(testCase, recF.Cs, Cs, AbsTol = 1e-12);
verifyEqual(testCase, recF.Ss, Ss, AbsTol = 1e-12);
% K = Shannon: energy retained ~ lambda_1
K = max(1, round(info.shannon));
aK = shLowLevel.slepianProject(Cs, Ss, G(:, 1:K), idx);
verifyGreaterThan(testCase, sum(aK.^2), 0.999);
verifyEqual(testCase, aF(1), 1, AbsTol = 1e-12);          % it IS taper 1
end

function testGfcDotSynonym(testCase)
%TESTGFCDOTSYNONYM v3.9.0 (roadmap item 8): ICGEM 'dot' lines are the
%   secular-rate synonym of 'trnd' - written as a fixture in the test,
%   read back, and evaluated at t0+2 yr against the hand value.
f = fullfile(tempdir, 'dot_fixture.gfc');
fid = fopen(f, 'w');
fprintf(fid, ['product_type gravity_field\nmodelname dotfix\n' ...
    'earth_gravity_constant 3.986004415e14\nradius 6378136.3\n' ...
    'max_degree 2\nnorm fully_normalized\nend_of_head\n' ...
    'gfct 2 0 -4.84e-04 0.0 0 0 20100101\n' ...
    'dot  2 0  1.00e-11 0.0 0 0\n']);
fclose(fid);
c = onCleanup(@() delete(f));
g = shLowLevel.shReadGFC(f);
verifyEqual(testCase, numel(g.variableTerms), 1);
verifyEqual(testCase, g.variableTerms(1).type, 'trnd');   % synonym mapped
[Ct, ~] = shLowLevel.shEvalGFCT(g, 2012.0);
verifyEqual(testCase, Ct(3, 1), -4.84e-04 + 2 * 1.00e-11, RelTol = 1e-9);
end

function testHydroExtremeIndexDailyDOY(testCase)
%TESTHYDROEXTREMEINDEXDAILYDOY v3.14.0 stage 2: daily DOY climatology
%   against the Python-frozen criteria - the circular window wraps
%   Dec-Jan (a planted +3-sigma Jan-2 flood scores z >= 2), the
%   two-stage construction keeps sigma free of seasonality leak
%   (median within 6% of truth incl. the sqrt(n/(n-1)) correction;
%   raw-value window sigma measured 1.99 vs true 1.5), and "auto"
%   selects DOY for daily spacing.
rng(31, 'twister');
nYr = 6; T = nYr * 365;
t = (0:T-1)'; doy = mod(t, 365) + 1;
ep = 2015 + t / 365 + 0.5 / 365;
clim = 12 * sin(2*pi*(doy - 120)/365);
sig = 1.5;
x = clim + sig * randn(T, 1);
iEv = 4*365 + 2;                               % Jan 2, year 5
x(iEv) = clim(iEv) + 3.0 * sig;
[z, info] = shLowLevel.hydroExtremeIndex(x, ep, Detrend = "none");
verifyGreaterThanOrEqual(testCase, z(iEv), 2.0);
verifyEqual(testCase, median(info.sigma(1, :), 'omitnan'), sig, ...
    RelTol = 0.06);
verifyEqual(testCase, numel(info.nPerMonth), 365);   % auto chose DOY
% monthly override still works on the same data
[~, infM] = shLowLevel.hydroExtremeIndex(x, ep, Detrend = "none", ...
    Climatology = "monthly");
verifyEqual(testCase, numel(infM.nPerMonth), 12);
end

function testCoastalLeakageControls(testCase)
%TESTCOASTALLEAKAGECONTROLS v3.15.0: leakage controls on a
%   BAND-LIMITED synthetic world. The first version planted sharp
%   boxes and compared against their nominal amplitude - CI caught
%   the category error: at n30 the boxes ring, the "truth" does not
%   exist band-limited, and the removal also subtracts the ocean's
%   own ringing outside the mask. Correct experiment: land and ocean
%   sources are band-limited SEPARATELY, the reference is the
%   filtered OCEAN-ONLY mask mean, and the leak is the difference
%   the land source adds to it. Criteria: erodeMask monotone with
%   interior preserved; one-step removal cuts the land-induced leak
%   by > 50% (ocean-ringing contamination is second order at a 10:1
%   land:ocean amplitude ratio); the ocean reference itself stays
%   within 15% of nominal (ringing + filter).
lat = (-89.5:1:89.5)'; lon = (0.5:1:359.5)';
[LO, LA] = meshgrid(lon, lat);
ocean = abs(LA) <= 60 & (LO > 60 & LO < 160);
land  = (LA > -30 & LA < 30 & LO >= 160 & LO < 200);   % coast-adjacent
mk300 = shLowLevel.erodeMask(ocean, lat, lon, 300);
mk600 = shLowLevel.erodeMask(ocean, lat, lon, 600);
verifyTrue(testCase, all(mk300(:) <= ocean(:)));
verifyTrue(testCase, all(mk600(:) <= mk300(:)));
verifyGreaterThan(testCase, nnz(ocean) - nnz(mk300), 0);
[~, iLa] = min(abs(lat - 0)); [~, iLo] = min(abs(lon - 110));
verifyTrue(testCase, mk600(iLa, iLo));
nmax = 30; kn = zeros(nmax + 1, 1);
GM = 3.986004415e14; R = 6378136.3;
gLand = shCoefficients.analysis(double(land) * 1.0, lat, lon, nmax, ...
    kn = kn, Quantity = "ewh");
gOc = shCoefficients.analysis(double(ocean) * 0.10, lat, lon, nmax, ...
    kn = kn, Quantity = "ewh");
wf = shLowLevel.shGaussianWeights(nmax, 445); wf = wf(:);
w = cosd(LA);
mm = @(C, S) localMaskMean(shLowLevel.shSynthesis(C .* wf, S .* wf, ...
    GM, R, lat, lon, 'Quantity', 'ewh', 'kn', kn, 'Nmin', 0), w, ocean);
ref = mm(gOc.C, gOc.S);                        % ocean-only reference
verifyEqual(testCase, ref, 0.10, RelTol = 0.15);
leakRaw = mm(gOc.C + gLand.C, gOc.S + gLand.S) - ref;
verifyGreaterThan(testCase, abs(leakRaw), 1e-4);   % experiment not empty
% iterative two-sided separation exactly as the chain does it
% (pre-validated: one-step WORSENS the leak - interior ringing of the
% outside reconstruction; two-sided POCS at 5 sweeps cuts an
% adjacent-source leak by 94% in the 1D reference)
Lc = zeros(nmax + 1); Ls = Lc; Oc = Lc; Os = Lc;
for it = 1:5
    EL = shLowLevel.shSynthesis(gOc.C + gLand.C - Oc, ...
        gOc.S + gLand.S - Os, GM, R, lat, lon, ...
        'Quantity', 'ewh', 'kn', kn, 'Nmin', 0);
    EL(ocean) = 0;
    gLe = shCoefficients.analysis(EL, lat, lon, nmax, kn = kn, ...
        Quantity = "ewh");
    Lc = gLe.C; Ls = gLe.S;
    EO = shLowLevel.shSynthesis(gOc.C + gLand.C - Lc, ...
        gOc.S + gLand.S - Ls, GM, R, lat, lon, ...
        'Quantity', 'ewh', 'kn', kn, 'Nmin', 0);
    EO(~ocean) = 0;
    gOe = shCoefficients.analysis(EO, lat, lon, nmax, kn = kn, ...
        Quantity = "ewh");
    Oc = gOe.C; Os = gOe.S;
end
leakClean = mm(gOc.C + gLand.C - Lc, gOc.S + gLand.S - Ls) - ref;
verifyLessThan(testCase, abs(leakClean), 0.5 * abs(leakRaw));
end

function m = localMaskMean(F, w, mk)
m = sum(F(mk) .* w(mk)) / sum(w(mk));
end

function testHydroExtremeIndexDSI(testCase)
%TESTHYDROEXTREMEINDEXDSI v3.14.0: DSI against the Python-frozen
%   criteria - a planted -2.5-sigma month lands in D4 (<= -2.0) when
%   detrended, LOSES its category without detrending (the 0.5 cm/yr
%   trend weakened it to -1.44 in the reference run), the running
%   category rate stays honest, and one 50-cm outlier corrupts the
%   std-sigma sixfold while the robust MAD stays put.
rng(21, 'twister');
T = 240; t = (0:T-1)';
ep = 2000 + t / 12 + 1 / 24;
mo = mod(t, 12);
clim = 10 * sin(2*pi*mo/12);
sigj = 2.0 + 1.0 * cos(2*pi*mo/12);
x = clim + 0.5 * (t/12) + sigj .* randn(T, 1);
x(101) = clim(101) + 0.5*(100/12) - 2.5*sigj(101);
x(201) = clim(201) + 0.5*(200/12) + 2.5*sigj(201);
[zD, infD] = shLowLevel.hydroExtremeIndex(x, ep);
[zN, ~] = shLowLevel.hydroExtremeIndex(x, ep, Detrend = "none");
verifyLessThanOrEqual(testCase, zD(101), -2.0);
verifyGreaterThanOrEqual(testCase, zD(201), 2.0);
verifyGreaterThan(testCase, zN(101), zD(101) + 0.5);   % trend eats it
verifyEqual(testCase, infD.category(101), int8(-5));   % D4
verifyEqual(testCase, infD.categoryNames(1), "D4");
% robust sigma vs one outlier
x2 = x; x2(4) = x2(4) + 50;
[~, iS] = shLowLevel.hydroExtremeIndex(x2, ep, Sigma = "std");
[~, iR] = shLowLevel.hydroExtremeIndex(x2, ep, Sigma = "robust");
j = mo(4) + 1;
verifyGreaterThan(testCase, iS.sigma(1, j), 2 * iR.sigma(1, j));
verifyEqual(testCase, iR.sigma(1, j), sigj(4), RelTol = 0.8);
end

function testHydroExtremeIndexDeficit(testCase)
%TESTHYDROEXTREMEINDEXDEFICIT v3.14.0: the Reager storage deficit is
%   causal, non-negative, exactly zero one step after a running
%   maximum; with PrecipGrid the FPI normalizes to max 1.
rng(22, 'twister');
T = 120; ep = 2000 + (0:T-1)' / 12 + 1/24;
x = cumsum(randn(T, 1));
[Sd, inf1] = shLowLevel.hydroExtremeIndex(x, ep, Mode = "StorageDeficit");
verifyTrue(testCase, isnan(Sd(1)));
verifyGreaterThanOrEqual(testCase, min(Sd(2:end)), 0);
[~, im] = max(x(1:end-1));
verifyEqual(testCase, Sd(im + 1), 0, AbsTol = 1e-12);
verifyEqual(testCase, string(inf1.mode), "StorageDeficit");
P = max(0, 5 + 4 * randn(T, 1));
[fpi, inf2] = shLowLevel.hydroExtremeIndex(x, ep, ...
    Mode = "StorageDeficit", PrecipGrid = P);
verifyEqual(testCase, max(fpi), 1, AbsTol = 1e-12);
verifyEqual(testCase, string(inf2.mode), "FPI");
% grid shape passthrough: 2 x 3 x T in, same out
G = repmat(reshape(x, 1, 1, T), 2, 3, 1);
Zg = shLowLevel.hydroExtremeIndex(G, ep);
verifyEqual(testCase, size(Zg), [2, 3, T]);
end

function testVdkApplyCore(testCase)
%TESTVDKAPPLYCORE v3.13.0: VDK/VADER solve against the Python-frozen
%   identities - alpha=0 is the identity, M = c*N collapses to the
%   closed form x/(1+alpha*c) (1e-10), and the (N+aM)^-1 N form equals
%   the Wiener form S(S+aN^-1)^-1 with S = M^-1 (1e-9).
rng(7, 'twister');
idx = shLowLevel.shIndex(10, Nmin = 2);
P = idx.P;
A = randn(P, ceil(P/3));
N = A*A' + P*eye(P);
sig = 3.0 * double(idx.n).^(-1.8);
x = randn(P, 1);
% alpha = 0: identity
x0 = shLowLevel.vdkApply(x, N, idx.n, sig, Alpha = 0);
verifyEqual(testCase, x0, x, AbsTol = 1e-8);
% M = c*N closed form - on a DIAGONAL N, where the diagonal-M API
% represents c*N exactly (with full N it cannot, caught in CI: the
% first version pressed c*diag(N) through the API and failed by 0.1)
c = 2.5; al = 0.7;
dN = 1 + rand(P, 1);
Nd = diag(dN);
sigC = 1 ./ sqrt(c * dN);
xc = shLowLevel.vdkApply(x, Nd, idx.n, sigC, Alpha = al);
verifyEqual(testCase, xc, x / (1 + al*c), AbsTol = 1e-10);
% form equivalence vs Wiener S(S + a N^-1)^-1
xf = shLowLevel.vdkApply(x, N, idx.n, sig, Alpha = al);
S = diag(sig.^2);
xw = S * ((S + al * inv(N)) \ x); %#ok<MINV>
verifyEqual(testCase, xf, xw, AbsTol = 1e-9);
% [a, b] row input evaluates a*l^b
xab = shLowLevel.vdkApply(x, N, idx.n, [3.0, -1.8], Alpha = al);
verifyEqual(testCase, xab, xf, AbsTol = 1e-12);
end

function testSignalVarianceKaula(testCase)
%TESTSIGNALVARIANCEKAULA v3.13.0: cyclostationary a*l^b recovery with
%   the exact log-chi2 bias correction, against the Python-frozen
%   criteria: mean bias of a within 3%, per-month scatter <= 15%
%   (10 years per calendar month), b within 3%.
rng(11, 'twister');
L = 60; nYr = 10;
aTrue = 2.0 + 1.5*sin(2*pi*(0:11)/12);
bTrue = -1.8 + 0.1*cos(2*pi*(0:11)/12);
T = 12 * nYr;
Cs = zeros(L+1, L+1, T); Ss = zeros(L+1, L+1, T);
ep = zeros(T, 1);
t = 0;
for yr = 1:nYr
    for mo = 1:12
        t = t + 1;
        ep(t) = 2000 + yr + (mo - 0.5) / 12;
        for l = 2:L
            s = aTrue(mo) * l^bTrue(mo) / sqrt(2*l + 1);
            Cs(l+1, 1:l+1, t) = randn(1, l+1) * s;
            Ss(l+1, 2:l+1, t) = randn(1, l) * s;
        end
    end
end
[ab, info] = shLowLevel.signalVarianceKaula(Cs, Ss, ep, LRange = [10, 60]);
verifyEqual(testCase, info.nPerMonth, repmat(nYr, 12, 1));
verifyEqual(testCase, mean(ab(:, 1)' ./ aTrue), 1, AbsTol = 0.03);
verifyLessThan(testCase, max(abs(ab(:, 1)' - aTrue) ./ aTrue), 0.15);
verifyLessThan(testCase, max(abs(ab(:, 2)' - bTrue) ./ abs(bTrue)), 0.03);
end

function testEofSeparateNorthMultiplet(testCase)
%TESTEOFSEPARATENORTHMULTIPLET v3.16.0: North multiplet rule with the
%   median-calibrated Marchenko-Pastur bulk edge, against the
%   Python-frozen scenarios - noise-only keeps 0, a degenerate
%   equal-variance pair keeps exactly 2 (the single-mode rule drops
%   it; the unguarded group chain kept 10 on the first machine run),
%   a single strong mode keeps exactly 1. Real trigger: the grown
%   252-month ocean residuals (gap 0.44e9 vs dl 0.53e9, nKeep 0).
rng(3, 'twister');
Q = 400; T = 250;
u1 = sin(linspace(0, 3*pi, Q))'; u1 = u1 / norm(u1);
u2 = cos(linspace(0, 3*pi, Q))'; u2 = u2 / norm(u2);
w = ones(Q, 1);
[~, ~, i0] = shLowLevel.eofSeparate(randn(Q, T), w);
verifyEqual(testCase, i0.nKeep, 0);
Xp = u1 * (10.0 * randn(1, T)) + u2 * (9.97 * randn(1, T)) + randn(Q, T);
[~, ~, i2] = shLowLevel.eofSeparate(Xp, w);
verifyEqual(testCase, i2.nKeep, 2);
verifyGreaterThan(testCase, i2.lam(2), i2.bulkEdge);
X1 = u1 * (10.0 * randn(1, T)) + randn(Q, T);
[~, ~, i1] = shLowLevel.eofSeparate(X1, w);
verifyEqual(testCase, i1.nKeep, 1);
end

function testEofSeparateNorthRule(testCase)
%TESTEOFSEPARATENORTHRULE v3.11.0: EOF/North separation against the
%   frozen Python (numpy) reference: two planted modes ABOVE the
%   Marchenko-Pastur noise bulk are recovered exactly (nKeep 2), the
%   de-circulated noise RMS reproduces the planted 0.8 to 5%, and the
%   reconstruction correlates > 0.95 with the planted truth. The
%   dimensioning lesson is part of the test: with mode variance below
%   the bulk edge sigma^2*(1+sqrt(Q/T))^2 no criterion can separate.
rng(42, 'twister');
Q = 800; T = 240; t = (0:T-1)' / 12;
w = 0.5 + rand(Q, 1);
u1 = cumsum(randn(Q, 1)); u1 = u1 - mean(u1); u1 = u1 / norm(u1);
u2 = cumsum(randn(Q, 1)); u2 = u2 - (u2' * u1) * u1 - mean(u2);
u2 = u2 / norm(u2);
pc1 = 12.0 * sin(2*pi*t/4.5); pc2 = 8.0 * cos(2*pi*t/7.0 + 0.6);
R = u1 * pc1' + u2 * pc2' + 0.8 * randn(Q, T);
[circ, ~, info] = shLowLevel.eofSeparate(R, w);
verifyEqual(testCase, info.nKeep, 2);
verifyEqual(testCase, info.rmsNoise, 0.8, RelTol = 0.05);
truth = u1 * (pc1 - mean(pc1))' + u2 * (pc2 - mean(pc2))';
c = corrcoef(circ(:), truth(:));
verifyGreaterThan(testCase, c(1, 2), 0.95);
% NKeep override and the degenerate zero-mode path
[c0, n0] = shLowLevel.eofSeparate(R, w, NKeep = 0);
verifyEqual(testCase, c0, zeros(Q, T));
verifyEqual(testCase, n0, R - mean(R, 2));
end

function testObpChainContract(testCase)
%TESTOBPCHAINCONTRACT kn and GADFolder are required - OBP without GAD
%   is not OBP, and no reference frame is ever assumed.
verifyError(testCase, @() shLowLevel.obpChain(tempdir), ...
    'shLowLevel:obpChain:missingKn');
verifyError(testCase, ...
    @() shLowLevel.obpChain(tempdir, kn = (0:90)' * 0), ...
    'shLowLevel:obpChain:missingGAD');
end

function testFetchITSGSINEXContract(testCase)
%TESTFETCHITSGSINEXCONTRACT v3.12.0: loud errors before any network use -
%   bad Nmax, empty month set, malformed month strings.
verifyError(testCase, @() shLowLevel.fetchITSGSINEX("2018-06", Nmax = 90), ...
    'shLowLevel:fetchITSGSINEX:badNmax');
verifyError(testCase, @() shLowLevel.fetchITSGSINEX(strings(0, 1)), ...
    'shLowLevel:fetchITSGSINEX:noMonths');
verifyError(testCase, @() shLowLevel.fetchITSGSINEX("June 2018"), ...
    'shLowLevel:fetchITSGSINEX:badMonth');
end

function testFetchITSGBackgroundContract(testCase)
%TESTFETCHITSGBACKGROUNDCONTRACT v3.12.0: unknown products and bad
%   months fail loudly before any network use.
verifyError(testCase, ...
    @() shLowLevel.fetchITSGBackground("2018-06", Products = "GAD"), ...
    'shLowLevel:fetchITSGBackground:badProduct');
verifyError(testCase, ...
    @() shLowLevel.fetchITSGBackground(1999), ...
    'shLowLevel:fetchITSGBackground:badMonth');
end

function testFetchGAXContract(testCase)
%TESTFETCHGAXCONTRACT bad products fail loudly before any network use.
verifyError(testCase, ...
    @() shLowLevel.fetchGAX(tempdir, Products = "GAX"), ...
    'shLowLevel:fetchGAX:badProduct');
end

function testOceanChainContract(testCase)
%TESTOCEANCHAINCONTRACT kn is required (no silent frame assumption),
%   mirroring the other chains' contract.
verifyError(testCase, @() shLowLevel.oceanChain(tempdir), ...
    'shLowLevel:oceanChain:missingKn');
end

function testNVCasingToleranceAndConvention(testCase)
%TESTNVCASINGTOLERANCEANDCONVENTION v3.8.10 (roadmap item 6): both NV
%   mechanisms tolerate any casing - this pins that tolerance so future
%   refactorings cannot silently break it. Canonical spelling stays
%   Capitalized for arguments-block NV, lowercase for legacy
%   inputParser names and quantity strings.
idx = shLowLevel.shIndex(6, Nmin = 0);
tri = [10 10; 10 20; 20 20];
m1 = shLowLevel.evalMask(idx, tri, oversample = 1);   % lowercase
m2 = shLowLevel.evalMask(idx, tri, OverSample = 1);   % canonical
verifyEqual(testCase, m1, m2);
C = zeros(7); C(1, 1) = 1; S0 = zeros(7);
g1 = shLowLevel.shSynthesis(C, S0, 1, 1, (0:5)', (0:5)', 'Quantity', 'geoid');
g2 = shLowLevel.shSynthesis(C, S0, 1, 1, (0:5)', (0:5)', 'Quantity', 'geoid');
verifyEqual(testCase, g1, g2);
end

function testQuantityNonePassthrough(testCase)
%TESTQUANTITYNONEPASSTHROUGH quantity "none" synthesizes the raw
%   coefficient field: kernel 1, no GM/R/kn enter. Kills the documented
%   workaround (quantity "geoid" with GM = R = 1). C00 = 1 alone must
%   give a constant 1 field at any GM, R.
C = zeros(7); C(1, 1) = 1; S0 = zeros(7);
lat = (-60:30:60)'; lon = (0:60:300)';
f = shLowLevel.shSynthesis(C, S0, 3.986e14, 6.378e6, lat, lon, ...
    'Quantity', 'none');
verifyEqual(testCase, f, ones(numel(lat), numel(lon)), AbsTol = 1e-12);
k = shLowLevel.kernelFactors("none", 6, 3.986e14, 6.378e6);
verifyEqual(testCase, k, ones(7, 1));
% and no kn is required (would error for "ewh")
verifyError(testCase, @() shLowLevel.kernelFactors("ewh", 6, 1, 1), ...
    'shLowLevel:kernelFactors:missingLoveNumbers');
end

function testHttpRetryDelaySchedule(testCase)
%TESTHTTPRETRYDELAYSCHEDULE v3.8.9 Retry-After policy (roadmap item 5,
%   motivated by the GravIS 503 bursts): server hint wins and is capped;
%   otherwise exponential backoff, capped; jitter bounded.
d1 = shLowLevel.httpRetryDelay(1, NaN, Jitter = 0);
d3 = shLowLevel.httpRetryDelay(3, NaN, Jitter = 0);
verifyEqual(testCase, d1, 2); verifyEqual(testCase, d3, 8);
verifyEqual(testCase, shLowLevel.httpRetryDelay(1, 30), 30);       % server wins
verifyEqual(testCase, shLowLevel.httpRetryDelay(1, 999), 60);      % ...capped
verifyEqual(testCase, shLowLevel.httpRetryDelay(9, NaN, Jitter = 0), 60);  % backoff capped
dj = shLowLevel.httpRetryDelay(2, NaN);                            % with jitter
verifyTrue(testCase, dj >= 4 && dj <= 5);
end

function testHttpFetchRejectsHardClientError(testCase)
%TESTHTTPFETCHREJECTSHARDCLIENTERROR 404 must fail fast (badStatus), not
%   spin through the retry budget. Network opt-in: skipped offline.
try
    ok = true; %#ok<NASGU>
    java.net.InetAddress.getByName('icgem.gfz.de');
catch
    assumeTrue(testCase, false, 'offline - DNS for icgem failed');
end
verifyError(testCase, @() shLowLevel.httpFetch( ...
    "https://icgem.gfz.de/definitely-not-a-real-path-404", ...
    fullfile(tempdir, 'x404.bin'), MaxTries = 2), ...
    'shLowLevel:httpFetch:badStatus');
end

function testEvalMaskRejectsGeojsonOrderedPolygon(testCase)
%TESTEVALMASKREJECTSGEOJSONORDEREDPOLYGON v3.8.7 guard, born in the GravIS
%   TWS validation: a GeoJSON [lon lat] polygon handed to the [lat lon]
%   convention built a SILENT phantom basin with plausible area (Amazonas)
%   or an empty one (Lena). Vertices with |lat| > 90 now raise an
%   identified error; a valid [lat lon] polygon still works.
idx = shLowLevel.shIndex(8, Nmin = 0);
% Lena-class swap: |lon| > 90 read as latitude is detectable...
lenaGeojson = [103 55; 140 55; 140 70; 103 70; 103 55];     % [lon lat]
verifyError(testCase, @() shLowLevel.evalMask(idx, lenaGeojson), ...
    'shLowLevel:evalMask:badPolygon');
verifyError(testCase, @() shLowLevel.basinKernel(idx, lenaGeojson), ...
    'shLowLevel:evalMask:badPolygon');            % propagates through the front door
% ...the Amazon class (lon within +-90) is NOT detectable by any lat
% check - that phantom is what the basinKernel zeroArea warning and the
% grid cross-check exist for. Valid [lat lon] input must keep working:
lenaToolbox = [lenaGeojson(:, 2), lenaGeojson(:, 1)];
mask = shLowLevel.evalMask(idx, lenaToolbox);
verifyTrue(testCase, any(mask > 0.5));
[~, bi] = shLowLevel.basinKernel(idx, lenaToolbox);
verifyTrue(testCase, bi.areaFraction > 1e-3 && bi.areaFraction < 0.05);
end

function testBasinKernelWarnsOnZeroArea(testCase)
%TESTBASINKERNELWARNSONZEROAREA Audit F-18: a degenerate region used to
%   return a silent all-zero kernel that any average divides by.
idx = shLowLevel.shIndex(10, Nmin = 0);
verifyWarning(testCase, @() shLowLevel.basinKernel(idx, ...
    [10 10; 10 10; 10 10]), 'shLowLevel:basinKernel:zeroArea');
end

% ---------------------------------------------------------- kalman (v3.17)
function testVAR1MatchesKurtenbachClosedForm(testCase)
%TESTVAR1MATCHESKURTENBACHCLOSEDFORM estimateVAR(Order=1) must equal the
%   closed form of Kurtenbach (2012) eqs. (3.84)-(3.85):
%   B = Sigma(1) Sigma(0)^-1, Q = Sigma(0) - B Sigma(0) B'.
rng(42);
P = 6; T = 4000;
A = randn(P); A = 0.9 * A / max(abs(eig(A)));
X = zeros(P, T + 500);
for t = 2:T + 500
    X(:, t) = A * X(:, t-1) + sqrt(0.2) * randn(P, 1);
end
X = X(:, 501:end);
model = shLowLevel.estimateVAR(X, Order = 1);
S0 = (X * X.') / T;
S1 = (X(:, 2:end) * X(:, 1:end-1).') / (T - 1);
Bref = S1 / S0;
Qref = S0 - Bref * S0 * Bref.';
verifyEqual(testCase, model.Phi{1}, Bref, AbsTol = 1e-12);
verifyEqual(testCase, model.Q, (Qref + Qref.') / 2, AbsTol = 1e-12);
verifyTrue(testCase, model.specRadius < 1);
ev = eig(model.Q);
verifyTrue(testCase, min(ev) > -1e-10 * max(ev));   % PSD
end

function testKalmanRTSEqualsBatchAdjustment(testCase)
%TESTKALMANRTSEQUALSBATCHADJUSTMENT Kvas (2019) Sec. 2.3: with the
%   stationary initialization, forward filter + RTS smoother is the
%   exact solution of the joint block-tridiagonal least-squares system
%   over all epochs - including a data gap.
rng(7);
P = 5; T = 10;
[model, ~] = localStableModel(P);
obs = repmat(struct('l', [], 'R', [], 'N', [], 'b', []), 1, T);
for t = 1:T
    if t ~= 5                                        % epoch 5 is a gap
        obs(t).l = randn(P, 1);
        obs(t).R = diag(0.3 + rand(P, 1));
    end
end
filt = shLowLevel.kalmanFilter(model, obs);
smo = shLowLevel.rtsSmoother(filt);
xb = localBatchLSA(model.Phi{1}, model.Q, model.Sigma0, obs);
verifyEqual(testCase, smo.xs, xb, ...
    AbsTol = 1e-9 * max(abs(xb(:))));
end

function testNeqModeEqualsSolutionMode(testCase)
%TESTNEQMODEEQUALSSOLUTIONMODE the information-form update with
%   N = R^-1, b = N l must reproduce the solution-mode update exactly
%   (states and covariances).
rng(11);
P = 5; T = 6;
[model, ~] = localStableModel(P);
obsS = repmat(struct('l', [], 'R', [], 'N', [], 'b', []), 1, T);
obsN = obsS;
for t = 1:T
    l = randn(P, 1); R = diag(0.3 + rand(P, 1));
    obsS(t).l = l; obsS(t).R = R;
    N = inv(R);
    obsN(t).N = N; obsN(t).b = N * l;
end
fS = shLowLevel.kalmanFilter(model, obsS);
fN = shLowLevel.kalmanFilter(model, obsN);
verifyEqual(testCase, fN.xf, fS.xf, AbsTol = 1e-9);
verifyEqual(testCase, fN.Pf, fS.Pf, AbsTol = 1e-9);
end

function testKalmanWienerLimit(testCase)
%TESTKALMANWIENERLIMIT with Phi = 0 (white process, Q = Sigma0) a single
%   update is the per-epoch Wiener filter Sigma0 (Sigma0 + R)^-1 l -
%   the temporal generalization claim vs. tvANSFilter, made exact.
rng(3);
P = 5;
[~, S0] = localStableModel(P);
model = struct('Phi', {{zeros(P)}}, 'Q', S0, 'Sigma0', S0, ...
    'order', 1, 'P', P, 'specRadius', 0);
l = randn(P, 1); R = diag(0.3 + rand(P, 1));
obs = struct('l', l, 'R', R, 'N', [], 'b', []);
filt = shLowLevel.kalmanFilter(model, obs);
verifyEqual(testCase, filt.xf(:, 1), (S0 / (S0 + R)) * l, AbsTol = 1e-10);
end

function testKalmanGapRelaxesToPrior(testCase)
%TESTKALMANGAPRELAXESTOPRIOR over a long gap the filtered covariance
%   must relax to the stationary prior Sigma(0) and the state to zero -
%   the graceful degradation Kurtenbach designed the process model for.
rng(5);
P = 4;
[model, ~] = localStableModel(P);
T = 80;
obs = repmat(struct('l', [], 'R', [], 'N', [], 'b', []), 1, T);
obs(1).l = randn(P, 1); obs(1).R = 0.1 * eye(P);
filt = shLowLevel.kalmanFilter(model, obs);
Sst = localStationaryCov(model);
relEnd = max(abs(filt.Pf(1:P, 1:P, T) - Sst), [], 'all') / max(abs(Sst), [], 'all');
verifyTrue(testCase, relEnd < 1e-2);
verifyTrue(testCase, max(abs(filt.xf(:, T))) < 0.05 * max(abs(filt.xf(:, 1))));
verifyEqual(testCase, nnz(filt.gap), T - 1);
end

function testKalmanChainSolutionRoundtrip(testCase)
%TESTKALMANCHAINSOLUTIONROUNDTRIP end-to-end: a VAR(1) truth packed into
%   shSeries, noisy observations with formal sigmas -> kalmanChain must
%   beat the raw observations against the truth and preserve epochs.
rng(21);
nmax = 6;
idx = shLowLevel.shIndex(nmax);
P = idx.P;
T = 60;
ep = 2005 + (0:T-1).' / 12;
A = 0.85 * eye(P) + 0.02 * randn(P);  A = 0.9 * A / max(abs(eig(A)));
Xt = zeros(P, T + 200);
for t = 2:T + 200
    Xt(:, t) = A * Xt(:, t-1) + 1e-10 * randn(P, 1);
end
Xt = Xt(:, 201:end);
L1 = nmax + 1;
[Cs, Ss, sC, sS] = deal(zeros(L1, L1, T));
sigObs = 2e-10;
CsO = Cs; SsO = Ss;
for t = 1:T
    [Cs(:,:,t), Ss(:,:,t)] = shLowLevel.csFromVec(Xt(:, t), idx);
    [CsO(:,:,t), SsO(:,:,t)] = shLowLevel.csFromVec( ...
        Xt(:, t) + sigObs * randn(P, 1), idx);
    [sC(:,:,t), sS(:,:,t)] = shLowLevel.csFromVec( ...
        sigObs * ones(P, 1), idx);
end
tsModel = shSeries(Cs, Ss = Ss, Epochs = ep);      % truth as model series
tsObs = shSeries(CsO, Ss = SsO, Epochs = ep, SigmaCs = sC, SigmaSs = sS);
[ts, rep] = shLowLevel.kalmanChain(tsObs, ModelSeries = tsModel, ...
    Order = 1, Climatology = false, Shrink = 1e-6);
verifyEqual(testCase, ts.epochs, ep, AbsTol = 1e-12);
verifyEqual(testCase, rep.nGaps, 0);
eF = 0; eO = 0;
for t = 1:T
    g = ts.at(t);
    eF = eF + sum((shLowLevel.vecFromCS(g.C, g.S, idx) - Xt(:, t)).^2);
    eO = eO + sum((shLowLevel.vecFromCS(CsO(:,:,t), SsO(:,:,t), idx) - Xt(:, t)).^2);
end
verifyTrue(testCase, eF < 0.9 * eO);               % filter must help
verifyTrue(testCase, all(isfinite(rep.meanContribution)));
end

% ------------------------------------------------- kalman local helpers
function [model, S0] = localStableModel(P)
A = randn(P); A = 0.8 * A / max(abs(eig(A)));
Q = 0.2 * eye(P) + 0.05 * ones(P);                 % SPD
S0 = Q;
for k = 1:500, S0 = A * S0 * A.' + Q; end          % Lyapunov fixed point
S0 = (S0 + S0.') / 2;
model = struct('Phi', {{A}}, 'Q', Q, 'Sigma0', S0, ...
    'order', 1, 'P', P, 'specRadius', max(abs(eig(A))));
end

function Sst = localStationaryCov(model)
Sst = model.Q;
for k = 1:800
    Sst = model.Phi{1} * Sst * model.Phi{1}.' + model.Q;
end
Sst = (Sst + Sst.') / 2;
end

function xb = localBatchLSA(B, Q, S0, obs)
%LOCALBATCHLSA joint least squares over all epochs (Kvas Sec. 2.3):
%   pseudo-obs x_1 ~ N(0,S0), x_t - B x_{t-1} ~ N(0,Q), plus the data.
P = size(B, 1); T = numel(obs);
N = zeros(T * P); rhs = zeros(T * P, 1);
iS0 = inv(S0); iQ = inv(Q);
N(1:P, 1:P) = iS0;
for t = 2:T
    i0 = (t-2) * P; i1 = (t-1) * P;
    N(i1+1:i1+P, i1+1:i1+P) = N(i1+1:i1+P, i1+1:i1+P) + iQ;
    N(i0+1:i0+P, i0+1:i0+P) = N(i0+1:i0+P, i0+1:i0+P) + B.' * iQ * B;
    N(i0+1:i0+P, i1+1:i1+P) = N(i0+1:i0+P, i1+1:i1+P) - B.' * iQ;
    N(i1+1:i1+P, i0+1:i0+P) = N(i1+1:i1+P, i0+1:i0+P) - iQ * B;
end
for t = 1:T
    if isempty(obs(t).l), continue; end
    i0 = (t-1) * P;
    iR = inv(obs(t).R);
    N(i0+1:i0+P, i0+1:i0+P) = N(i0+1:i0+P, i0+1:i0+P) + iR;
    rhs(i0+1:i0+P) = rhs(i0+1:i0+P) + iR * obs(t).l;
end
xb = reshape(N \ rhs, P, T);
end

% ------------------------------------------------ buildCondFun (v3.18)
function testCondFunIdentityAtInf(testCase)
%TESTCONDFUNIDENTITYATINF with Psi0Km=Inf and no regions the conditioner
%   must be the identity to machine precision - the F*G = I contract of
%   synthesisMatrix carried through the EWH kernel and back.
rng(13);
idx = shLowLevel.shIndex(8);
kn = -0.3 * ones(idx.Lmax + 1, 1);            % synthetic Love numbers
cf = shLowLevel.buildCondFun(idx, kn = kn);
A = randn(idx.P, 2 * idx.P);
C = A * A.' / (2 * idx.P);
verifyEqual(testCase, cf(C), (C + C.') / 2, AbsTol = 1e-10 * max(abs(C(:))));
end

function testCondFunKeepsPSDAndZeroesCrossRegion(testCase)
%TESTCONDFUNKEEPSPSDANDZEROESCROSSREGION taper + hemisphere mask: the
%   conditioned covariance stays PSD (Schur product theorem) and the
%   spatial weight really zeroes cross-region entries.
rng(17);
idx = shLowLevel.shIndex(6);
kn = -0.3 * ones(idx.Lmax + 1, 1);
[cf, info] = shLowLevel.buildCondFun(idx, kn = kn, Psi0Km = 2000, ...
    Regions = @(la, lo) double(la >= 0));
A = randn(idx.P, 2 * idx.P);
C = A * A.' / (2 * idx.P);
Ct = cf(C);
ev = eig((Ct + Ct.') / 2);
verifyTrue(testCase, min(ev) > -1e-8 * max(ev));
iN = find(info.region == 1, 1);
iS = find(info.region == 0, 1);
verifyEqual(testCase, info.W(iN, iS), 0);
verifyTrue(testCase, info.W(iN, iN) == 1);
end

function testCondFunRegularizesSingularCov(testCase)
%TESTCONDFUNREGULARIZESSINGULARCOV a rank-deficient empirical Sigma(0)
%   (T < P samples) must become strictly positive definite after
%   tapering - the stabilization Kvas conditions for (his Fig. 2.5) -
%   and estimateVAR with the CondFun must run without the unstable-model
%   warning path producing NaNs.
rng(19);
idx = shLowLevel.shIndex(6);
P = idx.P;
kn = -0.3 * ones(idx.Lmax + 1, 1);
cf = shLowLevel.buildCondFun(idx, kn = kn, Psi0Km = 1500);
T = round(P / 2);                             % deliberately singular
X = randn(P, T);
Sig = X * X.' / T;
evRaw = eig(Sig);
Ct = cf(Sig);
evC = eig(Ct);
verifyTrue(testCase, min(evRaw) < 1e-10 * max(evRaw));   % singular in
verifyTrue(testCase, min(evC) > 1e-10 * max(evC));       % PD out
cleanup = onCleanup(@() warning('on', 'shLowLevel:estimateVAR:shortSeries'));
warning('off', 'shLowLevel:estimateVAR:shortSeries');   % cleanup FIRST
model = shLowLevel.estimateVAR(X, Order = 1, CondFun = cf);
verifyTrue(testCase, all(isfinite(model.Phi{1}(:))));
verifyTrue(testCase, all(isfinite(model.Q(:))));
end

% -------------------------------------------- matfile cov store (v3.19)
function testKalmanMatfileEqualsMemory(testCase)
%TESTKALMANMATFILEEQUALSMEMORY StoreCov="matfile" must reproduce the
%   in-RAM results to the last bit through filter AND smoother - the
%   store is plumbing, never numerics. The covariance file must exist
%   at the reported path after the filter and remain (read-only
%   contract) after the smoother; cleanup is registered before use.
rng(23);
P = 5; T = 8;
[model, ~] = localStableModel(P);
obs = repmat(struct('l', [], 'R', [], 'N', [], 'b', []), 1, T);
for t = 1:T
    if t ~= 3                                        % keep a gap in play
        obs(t).l = randn(P, 1);
        obs(t).R = diag(0.3 + rand(P, 1));
    end
end
fMem = shLowLevel.kalmanFilter(model, obs, StoreCov = "full");
fFil = shLowLevel.kalmanFilter(model, obs, StoreCov = "matfile");
cleanup = onCleanup(@() delete(fFil.covFile));       % BEFORE any verify
verifyTrue(testCase, isfile(fFil.covFile));
verifyEqual(testCase, fFil.xf, fMem.xf);             % bit-identical
verifyEqual(testCase, fFil.dPf, ...
    squeeze(sum(fMem.Pf .* repmat(eye(P), 1, 1, T), 2)));
sMem = shLowLevel.rtsSmoother(fMem);
sFil = shLowLevel.rtsSmoother(fFil);
verifyEqual(testCase, sFil.xs, sMem.xs);
verifyEqual(testCase, sFil.sig, sMem.sig);
verifyEqual(testCase, sFil.PsLast, sMem.PsLast);
verifyTrue(testCase, isfile(fFil.covFile));          % smoother only reads
end

function testKalmanDiagRefusesSmootherLoudly(testCase)
%TESTKALMANDIAGREFUSESSMOOTHERLOUDLY "diag" cannot feed the backward
%   gain - the refusal must be an identified error, not a field crash.
rng(29);
P = 4;
[model, ~] = localStableModel(P);
obs = struct('l', randn(P, 1), 'R', eye(P), 'N', [], 'b', []);
filt = shLowLevel.kalmanFilter(model, obs, StoreCov = "diag");
verifyError(testCase, @() shLowLevel.rtsSmoother(filt), ...
    'shLowLevel:rtsSmoother:needFullCov');
end

% ------------------------------------------------- neqCombine (v3.20)
function testNeqCombineFixedEqualsStacked(testCase)
%TESTNEQCOMBINEFIXEDEQUALSSTACKED fixed weights: the NEQ-level
%   combination must equal the directly stacked weighted least squares.
rng(31);
P = 8;
xT = randn(P, 1);
A1 = randn(300, P); l1 = A1 * xT + 1.0 * randn(300, 1);
A2 = randn(400, P); l2 = A2 * xT + 2.0 * randn(400, 1);
neqs = struct('N', {A1.'*A1, A2.'*A2}, 'b', {A1.'*l1, A2.'*l2});
w = [1; 0.25];
x = shLowLevel.neqCombine(neqs, Weights = w);
Astk = [sqrt(w(1)) * A1; sqrt(w(2)) * A2];
lstk = [sqrt(w(1)) * l1; sqrt(w(2)) * l2];
verifyEqual(testCase, x, Astk \ lstk, AbsTol = 1e-9 * max(abs(xT)));
end

function testNeqCombineVCERecoversFactors(testCase)
%TESTNEQCOMBINEVCERECOVERSFACTORS Foerstner VCE must recover known
%   variance factors [1, 4] within statistical scatter, satisfy the
%   redundancy invariant sum(r) = sum(nobs) - P, and the combination
%   must beat both single-contribution solutions against the truth.
rng(37);
P = 10;
xT = randn(P, 1);
mk = @(A, s) struct('N', A.'*A, 'b', [], 'ltpl', [], 'nobs', size(A, 1), ...
    'name', "c");
A1 = randn(4000, P); l1 = A1 * xT + 1.0 * randn(4000, 1);
A2 = randn(4000, P); l2 = A2 * xT + 2.0 * randn(4000, 1);
n1 = mk(A1, 1); n1.b = A1.' * l1; n1.ltpl = l1.' * l1;
n2 = mk(A2, 2); n2.b = A2.' * l2; n2.ltpl = l2.' * l2;
[x, out] = shLowLevel.neqCombine([n1, n2]);
verifyTrue(testCase, out.converged);
verifyEqual(testCase, out.sigma2(1), 1, AbsTol = 0.1);
verifyEqual(testCase, out.sigma2(2), 4, AbsTol = 0.4);
verifyEqual(testCase, sum(out.redundancy), 8000 - P, RelTol = 1e-6);
e = @(y) norm(y - xT);
verifyTrue(testCase, e(x) < e(n1.N \ n1.b) && e(x) < e(n2.N \ n2.b));
end

function testNeqCombineVCENeedsStatsLoudly(testCase)
%TESTNEQCOMBINEVCENEEDSSTATSLOUDLY VCE without ltpl/nobs must refuse
%   with the identified error - no silent noise assumptions.
neqs = struct('N', eye(3), 'b', ones(3, 1));
verifyError(testCase, @() shLowLevel.neqCombine(neqs), ...
    'shLowLevel:neqCombine:needStats');
end

function testReadSINEXStatsAndEpoch(testCase)
%TESTREADSINEXSTATSANDEPOCH v3.20: the +SOLUTION/STATISTICS block is
%   parsed (nobs/nunk/wsos) and snx.epoch is delivered from the
%   estimate REF_EPOCH - the help had promised epoch since v2.x but the
%   field never existed (latent kalmanChain NEQ-mode crash, fixed
%   here). The real ITSG fixture (no STATISTICS block) must yield
%   empty stats and epoch 2008-04 mid-month; a synthetic file with a
%   STATISTICS block must feed neqCombine end-to-end.
f = fullfile(shxTestDataDir(), ...
    'ITSG-Grace2018_n96_2008-04_head12.snx');
snx = shLowLevel.readSINEX(f);
verifyTrue(testCase, isempty(snx.stats));
verifyEqual(testCase, snx.epoch, 2008 + 106/366, AbsTol = 1e-9);  % 08:107
% synthetic twin WITH statistics (values invented, layout ITSG-faithful)
tmp = [tempname, '.snx'];
cleanup = onCleanup(@() delete(tmp));
lines = [ ...
"%=SNX 2.02 TUG 18:300:38958 TUG 08:092:00000 08:122:00000 C 00002 2            2"
"+SOLUTION/STATISTICS"
"*_STATISTICAL PARAMETER________ __VALUE(S)____________"
" NUMBER OF OBSERVATIONS               5000"
" NUMBER OF UNKNOWNS                      2"
" WEIGHTED SQUARE SUM OF O-C           4998.0"
"-SOLUTION/STATISTICS"
"+SOLUTION/ESTIMATE"
"     1 CN        2 --    0 08:107:00000 ---- 2  2.00000000000000e+00 1.0e-03"
"     2 CN        2 --    1 08:107:00000 ---- 2 -1.00000000000000e+00 1.0e-03"
"-SOLUTION/ESTIMATE"
"+SOLUTION/NORMAL_EQUATION_MATRIX U"
"1  1  4.00000000000000e+00  1.00000000000000e+00"
"2  2  3.00000000000000e+00"
"-SOLUTION/NORMAL_EQUATION_MATRIX U"];
writelines(lines, tmp);
snx2 = shLowLevel.readSINEX(tmp);
verifyEqual(testCase, snx2.stats.nobs, 5000);
verifyEqual(testCase, snx2.stats.nunk, 2);
verifyEqual(testCase, snx2.stats.wsos, 4998.0);
verifyEqual(testCase, snx2.kind, 'NEQ');
verifyEqual(testCase, snx2.M, [4 1; 1 3]);
% two copies through the readSINEX front door of neqCombine: equal
% contributions -> equal variance factors, x == N \ (N*xhat)
[x, out] = shLowLevel.neqCombine([snx2, snx2]);
verifyTrue(testCase, out.converged);
verifyEqual(testCase, out.sigma2(1), out.sigma2(2), RelTol = 1e-9);
verifyEqual(testCase, x, snx2.x, AbsTol = 1e-9);
end

% -------------------------------------------------- kalman QC (v3.21)
function testChi2QuantilePinnedValues(testCase)
%TESTCHI2QUANTILEPINNEDVALUES Wilson-Hilferty against scipy chi2.ppf
%   reference values (computed once, tools/dev/validate_kalman_qc.py):
%   the tolerances ARE the measured accuracy map, not hopes.
verifyEqual(testCase, shLowLevel.chi2Quantile(0.999, 1677), ...
    1861.68, RelTol = 1e-4);          % scipy: 1861.6807
verifyEqual(testCase, shLowLevel.chi2Quantile(0.999, 50), ...
    86.661, RelTol = 2e-3);           % scipy: 86.6608
verifyEqual(testCase, shLowLevel.chi2Quantile(0.99, 10), ...
    23.209, RelTol = 5e-2);           % scipy: 23.2093
end

function testKalmanQCStatisticNeqEqualsSolution(testCase)
%TESTKALMANQCSTATISTICNEQEQUALSSOLUTION the NEQ-form innovation
%   statistic u'(N Pm N + N)^+ u must equal d' S^-1 d when N = R^-1
%   (Python check Q3, here through the real filter path with QC="flag").
rng(41);
P = 5; T = 6;
[model, ~] = localStableModel(P);
obsS = repmat(struct('l', [], 'R', [], 'N', [], 'b', []), 1, T);
obsN = obsS;
for t = 1:T
    l = randn(P, 1); R = diag(0.3 + rand(P, 1));
    obsS(t).l = l; obsS(t).R = R;
    N = inv(R);
    obsN(t).N = N; obsN(t).b = N * l;
end
fS = shLowLevel.kalmanFilter(model, obsS, QC = "flag");
fN = shLowLevel.kalmanFilter(model, obsN, QC = "flag");
verifyEqual(testCase, fN.qcStat, fS.qcStat, RelTol = 1e-7);
verifyEqual(testCase, fS.qcDof, P * ones(1, T));
verifyEqual(testCase, fN.qcDof, P * ones(1, T));
verifyFalse(testCase, any(fS.qcReject));         % flag never rejects
verifyEqual(testCase, fS.xf, ...                 % flag never alters states
    shLowLevel.kalmanFilter(model, obsS).xf);
end

function testKalmanQCRejectsBlunder(testCase)
%TESTKALMANQCREJECTSBLUNDER a 50-sigma blunder epoch must be rejected
%   (prediction-only) and the downstream states must beat the
%   unprotected filter against the truth - the reason QC exists in a
%   RECURSIVE estimator (Python check Q4 through the MATLAB path).
rng(43);
P = 6; T = 30;
[model, S0] = localStableModel(P);
L = chol(S0, 'lower');
xT = zeros(P, T); xT(:, 1) = L * randn(P, 1);
Lq = chol(model.Q + 1e-14 * eye(P), 'lower');
obs = repmat(struct('l', [], 'R', [], 'N', [], 'b', []), 1, T);
sig = 0.1;
for t = 1:T
    if t > 1, xT(:, t) = model.Phi{1} * xT(:, t-1) + Lq * randn(P, 1); end
    obs(t).l = xT(:, t) + sig * randn(P, 1);
    obs(t).R = sig^2 * eye(P);
end
obs(15).l = obs(15).l + 50 * sig;                 % the blunder
fQC = shLowLevel.kalmanFilter(model, obs, QC = "reject");
fNo = shLowLevel.kalmanFilter(model, obs);
verifyTrue(testCase, fQC.qcReject(15));
verifyEqual(testCase, nnz(fQC.qcReject), 1);
post = 15:T;
eQC = norm(fQC.xf(1:P, post) - xT(:, post), 'fro');
eNo = norm(fNo.xf(1:P, post) - xT(:, post), 'fro');
verifyTrue(testCase, eQC < 0.8 * eNo);
end

% ----------------------------------------------- Joseph update (v3.22)
function testKalmanJosephSurvivesHarshR(testCase)
%TESTKALMANJOSEPHSURVIVESHARSHR with a wide-spectrum prior (1e0..1e-8)
%   and R eight orders below it, the solution-mode covariance must
%   agree with the NEQ information form (the numerically clean path)
%   to 1e-9 relative - the standard (I-K)Pm update fails this at
%   ~1e-6 (measured against a 50-digit reference in
%   tools/dev/validate_kalman_qc.py J2). Also: the Wiener-limit and
%   batch-LSA equivalence tests above pin that Joseph changes nothing
%   in exact arithmetic.
rng(47);
P = 20;
[V, ~] = qr(randn(P));
S0 = V * diag(logspace(0, -8, P)) * V.';
S0 = (S0 + S0.') / 2;
model = struct('Phi', {{zeros(P)}}, 'Q', S0, 'Sigma0', S0, ...
    'order', 1, 'P', P, 'specRadius', 0);
R = diag(10.^(-14 + 4 * rand(P, 1)));
l = randn(P, 1);
obsS = struct('l', l, 'R', R, 'N', [], 'b', []);
N = diag(1 ./ diag(R));
obsN = struct('l', [], 'R', [], 'N', N, 'b', N * l);
fS = shLowLevel.kalmanFilter(model, obsS);
fN = shLowLevel.kalmanFilter(model, obsN);
sc = max(abs(fN.Pf(:)));
verifyTrue(testCase, max(abs(fS.Pf(:) - fN.Pf(:))) / sc < 1e-9);
ev = eig((fS.Pf(:, :, 1) + fS.Pf(:, :, 1).') / 2);
verifyTrue(testCase, min(ev) > -1e-12 * max(ev));
end

% ------------------------------------- multi-center kalmanChain (v3.23)
function testKalmanChainMultiCenterNEQ(testCase)
%TESTKALMANCHAINMULTICENTERNEQ two centers with identical synthetic
%   SINEX NEQs at two shared epochs: the chain must cluster the files
%   into two epoch groups, run per-epoch VCE via neqCombine, report
%   equal variance factors for identical centers, and produce a finite
%   residual series on the group epochs. The single-folder path is
%   exercised on center A alone (also pinning the snx.epoch wiring
%   that v3.20 repaired).
rng(53);
nmax = 2;
idx = shLowLevel.shIndex(nmax);
P = idx.P;
% ---- model series: stable VAR(1) sim, 40 monthly epochs
epM = (2008 + (0:39).' / 12);
A = 0.8 * eye(P) + 0.05 * randn(P); A = 0.85 * A / max(abs(eig(A)));
X = zeros(P, 240);
for t = 2:240, X(:, t) = A * X(:, t-1) + 1e-9 * randn(P, 1); end
X = X(:, 201:240);
L1 = nmax + 1;
[Cs, Ss] = deal(zeros(L1, L1, 40));
for t = 1:40
    [Cs(:,:,t), Ss(:,:,t)] = shLowLevel.csFromVec(X(:, t), idx);
end
tsm = shSeries(Cs, Ss = Ss, Epochs = epM);
% ---- two centers, two epochs, identical files
dirA = fullfile(tempname); mkdir(dirA);
dirB = fullfile(tempname); mkdir(dirB);
cleanup = onCleanup(@() cellfun(@(d) rmdir(d, 's'), {dirA, dirB}));
Araw = randn(P + 3, P); N = Araw.' * Araw;
epochToks = ["08:107:00000", "08:137:00000"];
for e = 1:2
    xh = 1e-9 * randn(P, 1);
    for d = [string(dirA), string(dirB)]
        localWriteTestNEQ(fullfile(char(d), sprintf('c_%d.snx', e)), ...
            epochToks(e), xh, N, 1000, xh.' * N * xh + (1000 - P), idx);
    end
end
[ts, rep] = shLowLevel.kalmanChain([string(dirA), string(dirB)], ...
    ModelSeries = tsm, Order = 1, Shrink = 1e-3);
verifyEqual(testCase, ts.nEpochs, 2);
verifyEqual(testCase, numel(rep.centers), 2);
verifyEqual(testCase, size(rep.sigma2), [2 2]);
verifyEqual(testCase, rep.sigma2(1, :), rep.sigma2(2, :), RelTol = 1e-6);
verifyTrue(testCase, all(isfinite(rep.sigma2(:))));
verifyTrue(testCase, all(isfinite(ts.Cs(:))));
% ---- single-folder path: epochs come from the v3.20 snx.epoch fix
[ts1, rep1] = shLowLevel.kalmanChain(string(dirA), ...
    ModelSeries = tsm, Order = 1, Shrink = 1e-3);
verifyEqual(testCase, ts1.epochs, ...
    [2008 + 106/366; 2008 + 136/366], AbsTol = 1e-9);
verifyEqual(testCase, rep1.nGaps, 0);
end

function localWriteTestNEQ(fn, epochTok, xh, N, nobs, wsos, idx)
%LOCALWRITETESTNEQ synthetic ITSG-layout NEQ SINEX (values invented).
P = idx.P;
lines = strings(0, 1);
lines(end+1) = "%=SNX 2.02 TUG 18:300:38958 TUG 08:092:00000 08:122:00000 C 0000" + P + " 2            2";
lines(end+1) = "+SOLUTION/STATISTICS";
lines(end+1) = sprintf(" NUMBER OF OBSERVATIONS               %d", nobs);
lines(end+1) = sprintf(" NUMBER OF UNKNOWNS                    %d", P);
lines(end+1) = sprintf(" WEIGHTED SQUARE SUM OF O-C           %.10e", wsos);
lines(end+1) = "-SOLUTION/STATISTICS";
lines(end+1) = "+SOLUTION/ESTIMATE";
tp = ["CN", "SN"];
for r = 1:P
    lines(end+1) = sprintf("%6d %s %8d -- %4d %s ---- 2 %20.14e 1.0e-12", ...
        r, tp(idx.cs(r) + 1), idx.n(r), idx.m(r), epochTok, xh(r)); %#ok<AGROW>
end
lines(end+1) = "-SOLUTION/ESTIMATE";
lines(end+1) = "+SOLUTION/NORMAL_EQUATION_MATRIX U";
for i = 1:P
    j = i;
    while j <= P
        j2 = min(j + 2, P);
        lines(end+1) = sprintf("%d  %d%s", i, j, ...
            sprintf("  %.14e", N(i, j:j2))); %#ok<AGROW>
        j = j2 + 1;
    end
end
lines(end+1) = "-SOLUTION/NORMAL_EQUATION_MATRIX U";
writelines(lines, fn);
end

% ------------------------------------------- fixed-lag smoother (v3.24)
function testRTSFixedLagConvergesToFull(testCase)
%TESTRTSFIXEDLAGCONVERGESTOFULL Lag >= T-1 must reproduce the full RTS
%   to rounding, and the error against it must decrease monotonically
%   over lags 0 -> 3 -> 10 (Python checks L1/L2 through the MATLAB
%   path). Also exercised through the matfile store: lag results must
%   be independent of where the covariances live.
rng(59);
P = 5; T = 20;
[model, ~] = localStableModel(P);
obs = repmat(struct('l', [], 'R', [], 'N', [], 'b', []), 1, T);
for t = 1:T
    obs(t).l = randn(P, 1);
    obs(t).R = diag(0.3 + rand(P, 1));
end
filt = shLowLevel.kalmanFilter(model, obs);
full = shLowLevel.rtsSmoother(filt);
lagFull = shLowLevel.rtsSmoother(filt, Lag = T - 1);
verifyEqual(testCase, lagFull.xs, full.xs, AbsTol = 1e-10);
verifyEqual(testCase, lagFull.sig, full.sig, AbsTol = 1e-10);
e = zeros(1, 3); lags = [0, 3, 10];
for i = 1:3
    sl = shLowLevel.rtsSmoother(filt, Lag = lags(i));
    e(i) = norm(sl.xs - full.xs, 'fro');
end
verifyTrue(testCase, e(2) < e(1) && e(3) < e(2));
% matfile store gives identical lag results
fFil = shLowLevel.kalmanFilter(model, obs, StoreCov = "matfile");
cleanup = onCleanup(@() delete(fFil.covFile));
sFil = shLowLevel.rtsSmoother(fFil, Lag = 3);
sMem = shLowLevel.rtsSmoother(filt, Lag = 3);
verifyEqual(testCase, sFil.xs, sMem.xs);
end

% ------------------------------------- estimateVAR Structure (v3.26)
function testEstimateVARStructures(testCase)
%TESTESTIMATEVARSTRUCTURES the structured Yule-Walker variants
%   (Python S1-S3 through the MATLAB path): "diagonal" gives diagonal
%   Phi/Q equal to the per-coefficient lag-1 regression; "orderblock"
%   is exactly zero outside its blocks and errors loudly without or
%   with a broken partition; at T ~ P both structured estimates beat
%   the raw full solve out of sample - the live ITSG-monthly finding,
%   pinned synthetically.
rng(61);
P = 10;
grp = [1 1 1 1 2 2 2 2 2 2];
blocks = {find(grp == 1), find(grp == 2)};   % COLUMN vectors, like
blocks = cellfun(@(b) b(:), blocks, 'UniformOutput', false);
% shIndex consumers build them - the live run caught a horzcat bug here
PhiT = zeros(P);
for b = 1:2
    A = randn(numel(blocks{b}));
    PhiT(blocks{b}, blocks{b}) = 0.7 * A / max(abs(eig(A)));
end
L = diag(0.5 + rand(P, 1));
X = zeros(P, 260);
for t = 2:260, X(:, t) = PhiT * X(:, t-1) + L * randn(P, 1); end
X = X(:, 201:260);                       % T = 60, deliberately short
% diagonal: shape + value
mD = shLowLevel.estimateVAR(X, Structure = "diagonal");
verifyEqual(testCase, mD.Phi{1}, diag(diag(mD.Phi{1})));
verifyEqual(testCase, mD.Q, diag(diag(mD.Q)));
% convention-free value check: diagonal on row i must equal the full
% estimator run on that single row as a 1 x T series (same Sigma(h)
% machinery by construction; bridge-measured reldiff 1.4e-16)
m1 = shLowLevel.estimateVAR(X(1, :));
verifyEqual(testCase, mD.Phi{1}(1, 1), m1.Phi{1}, RelTol = 1e-10);
% orderblock: pattern + loud errors
mB = shLowLevel.estimateVAR(X, Structure = "orderblock", Blocks = blocks);
off = mB.Phi{1}; off(1:4, 1:4) = 0; off(5:10, 5:10) = 0;
verifyEqual(testCase, off, zeros(P));
verifyError(testCase, @() shLowLevel.estimateVAR(X, Structure = "orderblock"), ...
    'shLowLevel:estimateVAR:needBlocks');
verifyError(testCase, @() shLowLevel.estimateVAR(X, ...
    Structure = "orderblock", Blocks = {1:4, 4:10}), ...
    'shLowLevel:estimateVAR:badBlocks');
% short-sample ranking, each structure on the truth it matches (a
% diagonal estimate rightly LOSES on a strongly block-coupled truth -
% the first draft asserted otherwise and CI said no):
% (a) block truth, T = 30: orderblock beats full (bridge: 13.5 < 15.8)
Xtr = X(:, 1:30); Xte = X(:, 31:end);
mF = shLowLevel.estimateVAR(Xtr, Shrink = 1e-3);
mB = shLowLevel.estimateVAR(Xtr, Structure = "orderblock", Blocks = blocks, Shrink = 1e-2);
r = @(m, Zt, Ze) norm(Ze(:, 2:end) - m.Phi{1} * Ze(:, 1:end-1), 'fro');
verifyTrue(testCase, r(mB, Xtr, Xte) < r(mF, Xtr, Xte));
% (b) diagonal truth, T = 30: diagonal beats full (bridge: 18.7 < 26.2)
rng(62);
aT = 0.3 + 0.5 * rand(P, 1);
L = diag(0.5 + rand(P, 1));
Y = zeros(P, 260);
for t = 2:260, Y(:, t) = aT .* Y(:, t-1) + L * randn(P, 1); end
Y = Y(:, 201:260);
Ytr = Y(:, 1:30); Yte = Y(:, 31:end);
mFy = shLowLevel.estimateVAR(Ytr, Shrink = 1e-3);
mDy = shLowLevel.estimateVAR(Ytr, Structure = "diagonal");
verifyTrue(testCase, r(mDy, Ytr, Yte) < r(mFy, Ytr, Yte));
end

function testKalmanChainStructurePassthrough(testCase)
%TESTKALMANCHAINSTRUCTUREPASSTHROUGH kalmanChain(Structure="orderblock")
%   must build the canonical (m, C/S) partition itself and hand it to
%   estimateVAR: the resulting model in rep must carry a Phi that is
%   exactly zero outside those blocks (v3.28 single point of access).
rng(67);
nmax = 3;
idx = shLowLevel.shIndex(nmax);
P = idx.P; L1 = nmax + 1;
epM = 2008 + (0:29).' / 12;
X = zeros(P, 230);
for t = 2:230, X(:, t) = 0.8 * X(:, t-1) + 1e-9 * randn(P, 1); end
X = X(:, 201:230);
[Cs, Ss] = deal(zeros(L1, L1, 30));
for t = 1:30
    [Cs(:,:,t), Ss(:,:,t)] = shLowLevel.csFromVec(X(:, t), idx);
end
sig = 1e-10 * ones(L1, L1, 30);
tsm = shSeries(Cs, Ss = Ss, Epochs = epM, SigmaCs = sig, SigmaSs = sig);
[~, rep] = shLowLevel.kalmanChain(tsm, ModelSeries = tsm, ...
    Structure = "orderblock", Shrink = 1e-2);
Phi = rep.model.Phi{1};
mask = false(P);
for mo = 0:nmax
    for cs = 0:1
        bb = find(idx.m == mo & idx.cs == cs);
        mask(bb, bb) = true;
    end
end
verifyEqual(testCase, Phi(~mask), zeros(nnz(~mask), 1));
verifyTrue(testCase, any(Phi(mask) ~= 0));
end

% --------------------------------- fetchITSG months array (v3.27.1)
function testFetchITSGMonthsArrayOffline(testCase)
%TESTFETCHITSGMONTHSARRAYOFFLINE a 1 x K string Months array must pass
%   the input gate - the scalar-only strlength check crashed the live
%   setup(Download="all") starter level with the operator-&& array
%   error (2026-08-18). Offline: BaseURL points at an empty local
%   folder, so both months are reported missing, no network involved.
tmp = tempname;
mkdir(fullfile(tmp, 'ITSG-Grace2018', 'monthly', 'monthly_n96'));
mkdir(fullfile(tmp, 'ITSG-Grace_operational', 'monthly', 'monthly_n96'));
dst = fullfile(tmp, 'out');
cleanup = onCleanup(@() rmdir(tmp, 's'));
[files, info] = shLowLevel.fetchITSG(["2008-04", "2025-12"], ...
    BaseURL = string(tmp), Dest = string(dst), Nmax = 96, Quiet = true);
verifyEmpty(testCase, files);
verifyEqual(testCase, sort(info.missing), sort(["2008-04", "2025-12"]));
% the all-empty selection still errors loudly (scalar and array form)
verifyError(testCase, @() shLowLevel.fetchITSG("", Quiet = true), ...
    'shLowLevel:fetchITSG:noSelection');
verifyError(testCase, @() shLowLevel.fetchITSG(["", ""], Quiet = true), ...
    'shLowLevel:fetchITSG:noSelection');
end

% --------------------------------- NEU gradient (v3.30.0)
function testGradientMatchesSynthesisDerivative(testCase)
%TESTGRADIENTMATCHESSYNTHESISDERIVATIVE the declared contract of
%   shSynthesisGradient is "exact derivative of shSynthesis under
%   identical options". This test differentiates shSynthesis ITSELF
%   rather than a second model of it, which is the only version of the
%   test that can fail for the right reason: if the two ever disagree
%   about a kernel, an nmin or a normalisation, the map and the arrows
%   drawn over it disagree, and nothing else would notice.
rng(4211);
L = 10; n1 = L + 1;
C = tril(randn(n1)) * 1e-10;
S = tril(randn(n1), -1) * 1e-10; S(:, 1) = 0;
GM = 3.986004415e14; R = 6378136.3;
kn = -0.3 * (1 - exp(-(0:L)'/3));
lat = [-52.5, -7.0, 18.25, 63.0];
lon = [11.0, 133.5, 271.0];
%   The stencil is FIVE-point, and that is not fussiness. A two-point
%   central difference at h = 1e-4 rad carries a truncation error of
%   (h^2/6) f''', and f''' of a degree-10 field is ~n^3 times the field
%   itself - so wherever a component happens to be small against the
%   field it sits in, the RELATIVE error of the difference reaches 1e-5.
%   It did: CI failed here on east/ewh at 2.4e-5, EWH being the quantity
%   whose (2n+1)/(1+kn) kernel amplifies the high degrees hardest. The
%   five-point stencil drops the truncation to (h^4/30) f^(5), measured
%   at 1e-10 on this field class, which lets the tolerance be a hundred
%   times TIGHTER than the one that failed. AbsTol excuses only the
%   near-zero crossings, where a relative comparison means nothing.
h = 1e-4;                                   % rad; 5-point stencil below
for q = ["none", "geoid", "potential", "gravity_anomaly", ...
         "gravity_disturbance", "ewh"]
    g = shLowLevel.shSynthesisGradient(C, S, GM, R, lat, lon, ...
        Quantity = q, kn = kn, Units = "perRadian");
    scal = @(la, lo) shLowLevel.shSynthesis(C, S, GM, R, la, lo, ...
        'Quantity', char(q), 'kn', kn);
    d5 = @(f, x) (f(x - 2*rad2deg(h)) - 8*f(x - rad2deg(h)) ...
                + 8*f(x + rad2deg(h)) - f(x + 2*rad2deg(h))) / (12*h);
    aN = 1e-8 * max(abs(g.north(:)));
    aE = 1e-8 * max(abs(g.east(:)));
    for i = 1:numel(lat)
        for j = 1:numel(lon)
            dN = d5(@(x) scal(x, lon(j)), lat(i));
            dE = d5(@(x) scal(lat(i), x), lon(j)) / cosd(lat(i));
            verifyEqual(testCase, g.north(i, j), dN, ...
                'RelTol', 1e-7, 'AbsTol', aN, ...
                sprintf('north, %s at (%g,%g)', q, lat(i), lon(j)));
            verifyEqual(testCase, g.east(i, j), dE, ...
                'RelTol', 1e-7, 'AbsTol', aE, ...
                sprintf('east, %s at (%g,%g)', q, lat(i), lon(j)));
        end
    end
end
end

function testGradientRadialIdentities(testCase)
%TESTGRADIENTRADIALIDENTITIES the up component is not a new claim: it
%   reduces to kernels this toolbox already validates.
%     d(potential)/dr           = -gravity_disturbance
%     d(gravity_disturbance)/dr = -gravity_gradient_rr
%   Machine precision, not a tolerance dressed up as one - both sides
%   come from the same kernelFactors radial exponent.
rng(88);
L = 9; n1 = L + 1;
C = tril(randn(n1)) * 1e-10;
S = tril(randn(n1), -1) * 1e-10; S(:, 1) = 0;
GM = 3.986004415e14; R = 6378136.3;
lat = -75:25:75; lon = 0:60:300;
for hgt = [0, 250e3]
    g = shLowLevel.shSynthesisGradient(C, S, GM, R, lat, lon, ...
        Quantity = "potential", Height = hgt);
    dg = shLowLevel.shSynthesis(C, S, GM, R, lat, lon, ...
        'Quantity', 'gravity_disturbance', 'Height', hgt);
    verifyEqual(testCase, g.up, -dg, 'RelTol', 1e-12);
    g2 = shLowLevel.shSynthesisGradient(C, S, GM, R, lat, lon, ...
        Quantity = "gravity_disturbance", Height = hgt);
    trr = shLowLevel.shSynthesis(C, S, GM, R, lat, lon, ...
        'Quantity', 'gravity_gradient_rr', 'Height', hgt);
    verifyEqual(testCase, g2.up, -trr, 'RelTol', 1e-12);
end
end

function testGradientClosedForms(testCase)
%TESTGRADIENTCLOSEDFORMS single coefficients whose gradient is written
%   down by hand, so at least one test depends on no other part of the
%   toolbox. Pbar_10 = sqrt(3) sin(phi), Pbar_11 = sqrt(3) cos(phi).
R = 6378136.3; GM = 3.986004415e14;
lat = [-68.7, 12.3, 41.0]; lon = [23.0, 205.0];
[LO, LA] = meshgrid(deg2rad(lon), deg2rad(lat));
mk = @(n, m, isC) deal(local_one(n, m, isC, true), local_one(n, m, isC, false));

[C, S] = mk(1, 0, true);                       % C_10
g = shLowLevel.shSynthesisGradient(C, S, GM, R, lat, lon, ...
    Quantity = "none", Units = "perRadian");
verifyEqual(testCase, g.north, sqrt(3) * cos(LA), 'AbsTol', 1e-13);
verifyEqual(testCase, g.east, zeros(size(LA)), 'AbsTol', 1e-14);

[C, S] = mk(1, 1, true);                       % C_11
g = shLowLevel.shSynthesisGradient(C, S, GM, R, lat, lon, ...
    Quantity = "none", Units = "perRadian");
verifyEqual(testCase, g.north, -sqrt(3) * sin(LA) .* cos(LO), 'AbsTol', 1e-13);
verifyEqual(testCase, g.east, -sqrt(3) * sin(LO), 'AbsTol', 1e-13);

[C, S] = mk(1, 1, false);                      % S_11
g = shLowLevel.shSynthesisGradient(C, S, GM, R, lat, lon, ...
    Quantity = "none", Units = "perRadian");
verifyEqual(testCase, g.north, -sqrt(3) * sin(LA) .* sin(LO), 'AbsTol', 1e-13);
verifyEqual(testCase, g.east, sqrt(3) * cos(LO), 'AbsTol', 1e-13);
end

function M = local_one(n, m, isC, wantC)
M = zeros(n + 1);
if isC == wantC, M(n + 1, m + 1) = 1; end
end

% --------------------------------- geoMap bridge (v3.31.0)
function testSynthesisReturnsTheRequestedLatConvention(testCase)
%TESTSYNTHESISRETURNSTHEREQUESTEDLATCONVENTION synthesis used to return
%   the CONVERTED latitudes, so LatType="geodetic" handed back geocentric
%   ones. Nothing in either toolbox could notice: a caller fed them
%   straight into a map and drew a geocentric field against a geodetic
%   coastline. The offset is 0.1924 deg = 21.4 km north-south at +-45,
%   which on a regional 20-deg map is 1.6 mm of systematic shift - the
%   size a reader would take for a real geophysical offset.
rng(505);
L = 6; n1 = L + 1;
C = tril(randn(n1)) * 1e-10;
S = tril(randn(n1), -1) * 1e-10; S(:, 1) = 0;
g = shCoefficients(C, S);
lat = -85:10:85; lon = 0:60:300;

[Zgd, laGd] = g.synthesis(lat, lon, LatType = "geodetic");
verifyEqual(testCase, laGd, lat, ...
    'the latitudes must come back in the convention that was asked for');

latGc = shLowLevel.geodetic2geocentric(lat);
[Zgc, laGc] = g.synthesis(latGc, lon, LatType = "geocentric");
verifyEqual(testCase, laGc, latGc);
verifyEqual(testCase, Zgd, Zgc, 'RelTol', 1e-12, ...
    'only the reported latitude changed, never the field');

% the discrepancy is real and this pins its size
d = max(abs(lat - latGc));
verifyEqual(testCase, d, 0.1924, 'AbsTol', 2e-3);

% the gradient carries the convention rather than leaving it to be remembered
[~, info] = g.gradient(lat, lon, Quantity = "potential", LatType = "geodetic");
verifyEqual(testCase, info.lat, lat);
verifyEqual(testCase, info.latType, "geodetic");
[~, info2] = g.gradient(lat, lon, Quantity = "potential");
verifyEqual(testCase, info2.latType, "geocentric");
end

function testKernelFactorsReportsItsUnits(testCase)
%TESTKERNELFACTORSREPORTSITSUNITS the unit belongs to the quantity, so it
%   is returned from where the quantity is defined. Retyped by hand at
%   the toolbox boundary it was a thing a user could get wrong silently.
GM = 3.986004415e14; R = 6378136.3; L = 4;
kn = -0.3 * (1 - exp(-(0:L)'/3));
hn = -ones(L + 1, 1);
expected = ["none", ""; "geoid", "m"; "potential", "m^2/s^2"; ...
            "gravity_anomaly", "m/s^2"; "gravity_disturbance", "m/s^2"; ...
            "gravity_gradient_rr", "1/s^2"; "ewh", "m"; ...
            "surface_density", "kg/m^2"; "bottom_pressure", "Pa"; ...
            "deformation_up", "m"];
for k = 1:size(expected, 1)
    [~, ~, u] = shLowLevel.kernelFactors(char(expected(k, 1)), L, GM, R, ...
        kn = kn, hn = hn);
    verifyEqual(testCase, u, expected(k, 2), ...
        sprintf('units of %s', expected(k, 1)));
end
end

% ---------------------------------------------------------------- A10 (v3.34.1)
% Coverage by NAME of the package functions the audit found unnamed in any
% test. Each test asserts a property the function's own help states, so it
% pins documented behaviour rather than merely mentioning the name.

function testIcgemDate2YearAgainstHandComputedEpochs(testCase)
% yyyymmdd -> decimal year with proper leap years. 2024 is a leap year
% (366 d), 2023 is not (365 d); day-of-year is 0-based in the formula.
verifyEqual(testCase, shLowLevel.icgemDate2Year(20240101), 2024, ...
    'AbsTol', 1e-12);                       % doy 0 -> exactly the year
verifyEqual(testCase, shLowLevel.icgemDate2Year(20230101), 2023, ...
    'AbsTol', 1e-12);
% 1 March 2024: 31 + 29 = 60 days elapsed (the leap day is included)
verifyEqual(testCase, shLowLevel.icgemDate2Year(20240301), 2024 + 60/366, ...
    'AbsTol', 1e-12);
% 1 March 2023: 31 + 28 = 59 days elapsed (no leap day)
verifyEqual(testCase, shLowLevel.icgemDate2Year(20230301), 2023 + 59/365, ...
    'AbsTol', 1e-12);
% 31 December 2024 is the last day, doy 365 of 366
verifyEqual(testCase, shLowLevel.icgemDate2Year(20241231), 2024 + 365/366, ...
    'AbsTol', 1e-12);
% the .hhmm fraction is a fraction of a day
verifyEqual(testCase, shLowLevel.icgemDate2Year(20240101.1200), ...
    2024 + 0.5/366, 'AbsTol', 1e-12);
end

function testIcgemDate2YearPassesDecimalYearsThrough(testCase)
% the documented < 1.8e7 rule that keeps pre-v2.1 synthetic files evaluating
% identically: already-decimal years are returned UNCHANGED, bitwise.
d = [2002.5; 1997.0; 2024.123456789];
verifyEqual(testCase, shLowLevel.icgemDate2Year(d), d);
% mixed input: each element is decided on its own
mixed = [2002.5; 20240301];
got = shLowLevel.icgemDate2Year(mixed);
verifyEqual(testCase, got(1), 2002.5);
verifyEqual(testCase, got(2), 2024 + 60/366, 'AbsTol', 1e-12);
verifyEqual(testCase, size(got), size(mixed));
end

function testPctileMatchesTheDocumentedOrderStatistic(testCase)
% sample k sits at percentile 100*(k-0.5)/n, linear in between - the
% Statistics Toolbox prctile rule this base-MATLAB version reproduces.
x = 1:100;
% q_k = k - 0.5, so p = 50 lies midway between x = 50 and x = 51
verifyEqual(testCase, shLowLevel.pctile(x, 50), 50.5, 'AbsTol', 1e-12);
% odd n: the 50th percentile IS the median, exactly
xo = [3 1 4 1 5];
verifyEqual(testCase, shLowLevel.pctile(xo, 50), median(xo), 'AbsTol', 1e-12);
% outside the sampled range the value is clamped to the extreme order
% statistics, so p = 0 and p = 100 are min and max
verifyEqual(testCase, shLowLevel.pctile(x, 0), min(x), 'AbsTol', 1e-12);
verifyEqual(testCase, shLowLevel.pctile(x, 100), max(x), 'AbsTol', 1e-12);
% a vector p returns one value per request, in that shape
p = [10 25 50 75 90];
v = shLowLevel.pctile(x, p);
verifyEqual(testCase, size(v), size(p));
verifyTrue(testCase, all(diff(v) > 0), 'percentiles must increase with p');
end

function testPctileIgnoresNonFiniteAndHandlesEmpty(testCase)
x = [1 2 NaN 3 Inf 4 -Inf];
% the finite values are 1 2 3 4 - identical to passing them alone
verifyEqual(testCase, shLowLevel.pctile(x, [25 50 75]), ...
    shLowLevel.pctile([1 2 3 4], [25 50 75]), 'AbsTol', 1e-12);
verifyTrue(testCase, all(isnan(shLowLevel.pctile([], [10 90]))));
verifyTrue(testCase, all(isnan(shLowLevel.pctile([NaN NaN], 50))));
% a single finite value is that value at every percentile
verifyEqual(testCase, shLowLevel.pctile(7, [0 50 100]), [7 7 7], ...
    'AbsTol', 1e-12);
end

function testGridHandoverReadsTheFieldKindOffTheIdentity(testCase)
% C00 = 1 means the field carries the total mass, C00 = 0 means a residual.
% The help calls this a fact about the coefficients, not an inference from
% the values - so the SAME Z must be labelled differently by C00 alone.
Z = randn(5, 8);
lat = linspace(-80, 80, 5);
lon = linspace(0, 315, 8);
mk = @(c00) shLowLevel.gridHandover(Z, lat, lon, "m", "geocentric", ...
    "geoid", "GSM", "test", 2024.1, c00, "history line", 10, 0);
bFull = mk(1);  bAnom = mk(0);  bMid = mk(0.5);
verifyEqual(testCase, bFull.FieldKind, "full");
verifyEqual(testCase, bAnom.FieldKind, "anomaly");
verifyEqual(testCase, bMid.FieldKind, "unknown");
% a stack whose kinds disagree is reported as mixed, never decided
bs = shLowLevel.gridHandover(Z, lat, lon, "m", "geocentric", "geoid", ...
    "GSM", "test", [2024.1; 2024.2], [1; 0], "history line", 10, 0);
verifyEqual(testCase, bs.FieldKind, "mixed");
% and agreeing kinds collapse to the one kind
ba = shLowLevel.gridHandover(Z, lat, lon, "m", "geocentric", "geoid", ...
    "GSM", "test", [2024.1; 2024.2], [0; 0], "history line", 10, 0);
verifyEqual(testCase, ba.FieldKind, "anomaly");
end

function testGridHandoverCarriesExtremesWithoutJudgingThem(testCase)
% Zmin/Zmax/Zmean are the raw measured extremes over EVERY epoch, which is
% the fixed colour scale an animation needs. Non-finite values are skipped.
Z = cat(3, [1 2; 3 4], [-10 0; 5 20]);
lat = [-45 45]; lon = [0 180];
b = shLowLevel.gridHandover(Z, lat, lon, "m", "geocentric", "geoid", ...
    "GSM", "test", [2024.1; 2024.2], [0; 0], "h", 10, 0);
verifyEqual(testCase, b.Zmin, -10, 'AbsTol', 1e-12);
verifyEqual(testCase, b.Zmax, 20, 'AbsTol', 1e-12);
verifyEqual(testCase, b.Zmean, mean(Z(:)), 'AbsTol', 1e-12);
% lat comes back as a column and lon as a row, whatever was passed in
verifyEqual(testCase, size(b.lat), [2 1]);
verifyEqual(testCase, size(b.lon), [1 2]);
% a NaN in the field does not poison the extremes
Zn = Z; Zn(1) = NaN;
bn = shLowLevel.gridHandover(Zn, lat, lon, "m", "geocentric", "geoid", ...
    "GSM", "test", [2024.1; 2024.2], [0; 0], "h", 10, 0);
verifyEqual(testCase, bn.Zmin, -10, 'AbsTol', 1e-12);
verifyEqual(testCase, bn.Zmax, 20, 'AbsTol', 1e-12);
end

function testShGaussianFilterIsTheWeightsAppliedByDegree(testCase)
% the filter is exactly "multiply each degree row by Wn" - so it must equal
% that product bitwise, and return the weights it used.
rng(4711);
g = randomField(20);
[Cf, Sf, Wn] = shLowLevel.shGaussianFilter(g.C, g.S, 500);
verifyEqual(testCase, Cf, g.C .* Wn);
verifyEqual(testCase, Sf, g.S .* Wn);
verifyEqual(testCase, Wn, shLowLevel.shGaussianWeights(20, 500));
% Jekeli: degree 0 is untouched and the weights decay monotonically
verifyEqual(testCase, Wn(1), 1, 'AbsTol', 1e-12);
verifyTrue(testCase, all(diff(Wn) <= 0), 'weights must not increase');
verifyTrue(testCase, all(Wn >= 0), 'the negativity guard must hold');
% a larger radius smooths harder at every degree above 0
Wn2 = shLowLevel.shGaussianWeights(20, 1000);
verifyTrue(testCase, all(Wn2(2:end) <= Wn(2:end)));
end

function testShGaussianFilterMatchesTheClassMethod(testCase)
% the class method is a delegate: same numbers, or the two lanes disagree
rng(4712);
g = randomField(16);
[Cf, Sf] = shLowLevel.shGaussianFilter(g.C, g.S, 350);
gf = g.gaussian(350);
verifyEqual(testCase, gf.C, Cf);
verifyEqual(testCase, gf.S, Sf);
end

function testShDestripeRemovesAPolynomialInDegreeExactly(testCase)
% Swenson & Wahr fit a polynomial in n per (order, parity) and subtract it.
% A field that IS such a polynomial must therefore be annihilated, up to
% the conditioning of the fit - this is the defining property, not a bound.
L = 30;
C = zeros(L+1); S = zeros(L+1);
n = (0:L)';
for m = 7:L                                  % above the default minOrder 6
    rows = m+1:L+1;
    nn = n(rows);
    C(rows, m+1) = 1 + 0.5*nn + 0.02*nn.^2 + 1e-4*nn.^3;   % cubic in n
    S(rows, m+1) = 2 - 0.3*nn + 0.01*nn.^2 - 5e-5*nn.^3;
end
[Cf, Sf] = shLowLevel.shDestripe(C, S);
% filterParity leaves a subset alone when it holds <= polyOrder+1 = 4
% points, so only orders with >= 5 degrees of EACH parity are fitted:
% m..30 must hold >= 10 degrees, i.e. m <= 21.
mFit = 7:21;
% Tolerance: the residual of an exact cubic recovered by an UNCENTRED
% polyfit. Vandermonde conditioning on n <= 30 at degree 3 is ~1e5, the
% polynomial itself reaches ~37, so the roundoff floor is ~1e-9. 1e-7 is
% two orders of margin over that term, not a fitted number.
verifyLessThan(testCase, max(abs(Cf(:, mFit+1)), [], 'all'), 1e-7);
verifyLessThan(testCase, max(abs(Sf(:, mFit+1)), [], 'all'), 1e-7);
% and the guard itself: an order with too few degrees per parity is
% returned untouched rather than fitted badly
verifyEqual(testCase, Cf(:, 29), C(:, 29));      % m = 28: 2 even, 1 odd
verifyEqual(testCase, Sf(:, 29), S(:, 29));
end

function testShDestripePassesLowOrdersThroughUnchanged(testCase)
% "Coefficients at m < minOrder are passed through unchanged" - bitwise.
rng(4713);
g = randomField(24);
[Cf, Sf] = shLowLevel.shDestripe(g.C, g.S);
verifyEqual(testCase, Cf(:, 1:6), g.C(:, 1:6));
verifyEqual(testCase, Sf(:, 1:6), g.S(:, 1:6));
% and the boundary moves with the option
[Cf2, Sf2] = shLowLevel.shDestripe(g.C, g.S, 'MinOrder', 10);
verifyEqual(testCase, Cf2(:, 1:10), g.C(:, 1:10));
verifyEqual(testCase, Sf2(:, 1:10), g.S(:, 1:10));
% the class method delegates here, so the two must agree bitwise
gd = g.destripe();
verifyEqual(testCase, gd.C, Cf);
verifyEqual(testCase, gd.S, Sf);
end

function testShSpectralCrossoverFindsTheFirstCrossing(testCase)
% a constructed spectrum whose error overtakes the signal at a known degree
n = (0:20)';
spec.degree = n;
spec.degAmplitude = 10 .^ (-n/5);             % a decade per 5 degrees
spec.errAmplitude = 1e-2 * ones(size(n));     % flat noise floor
% the signal drops below 1e-2 where -n/5 < -2, i.e. from n = 11 on, so the
% crossing is strictly inside the degree range (and not at the first index)
first = find(spec.errAmplitude > spec.degAmplitude, 1, 'first');
verifyEqual(testCase, spec.degree(first), 11, ...
    'the fixture must cross where the test says it does');
[nc, ni] = shLowLevel.shSpectralCrossover(spec);
verifyEqual(testCase, nc, spec.degree(first));
% the interpolated degree lies in the interval that brackets the crossing
verifyGreaterThanOrEqual(testCase, ni, spec.degree(first-1));
verifyLessThanOrEqual(testCase, ni, spec.degree(first));
end

function testShSpectralCrossoverReturnsNaNWhenTheErrorNeverWins(testCase)
n = (0:15)';
spec.degree = n;
spec.degAmplitude = ones(size(n));
spec.errAmplitude = 1e-3 * ones(size(n));    % never exceeds the signal
[nc, ni] = shLowLevel.shSpectralCrossover(spec);
verifyTrue(testCase, isnan(nc));
verifyTrue(testCase, isnan(ni));
end

function testOpApplyIsTheAdjointOfItsForwardOperator(testCase)
% W_t = V diag(g) Ut with g = lam./(lam + s(t)). The transposed mode must
% be the true adjoint: <W z, y> = <z, W' y> for every z, y. That identity
% is what the tvANS posterior relies on, and it holds with no tolerance to
% choose beyond roundoff.
rng(90210);
P = 12;
[V, ~] = qr(randn(P));                 % orthogonal: a well-posed operator
op.lam = abs(randn(P, 1)) + 0.5;
op.s   = [0.7, 1.3];                   % one variance factor per month
op.V   = V;
op.Ut  = V';
op.Ac  = [];                           % unconstrained path
op.SA  = [];
op.M   = [];
t = 2;
Z = randn(P, 3);
Y = randn(P, 3);

g = op.lam ./ (op.lam + op.s(t));
W = op.V * diag(g) * op.Ut;
% dense P = 12 products: roundoff ~ P*eps*|W|*|Z| ~ 1e-14. 1e-12 is two
% orders over that term.
verifyEqual(testCase, shLowLevel.opApply(op, Z, t), W * Z, ...
    'AbsTol', 1e-12);                  % the 3-argument default is 'forward'
verifyEqual(testCase, shLowLevel.opApply(op, Z, t, 'forward'), W * Z, ...
    'AbsTol', 1e-12);
verifyEqual(testCase, shLowLevel.opApply(op, Z, t, 'transp'), W' * Z, ...
    'AbsTol', 1e-12);

lhs = sum(shLowLevel.opApply(op, Z, t, 'forward') .* Y, 'all');
rhs = sum(Z .* shLowLevel.opApply(op, Y, t, 'transp'), 'all');
verifyEqual(testCase, lhs, rhs, 'RelTol', 1e-12);

% s(t) selects the month: a larger noise factor shrinks harder
g1 = op.lam ./ (op.lam + op.s(1));
verifyEqual(testCase, shLowLevel.opApply(op, Z, 1), ...
    op.V * (g1 .* (op.Ut * Z)), 'AbsTol', 1e-12);
end

function testOpApplyBlockPathEqualsTheEquivalentDenseOperator(testCase)
% the block-diagonal fast path must be the dense operator restricted to
% those blocks - same numbers, not merely a similar shape
rng(90211);
P = 12; half = P / 2;
[V1, ~] = qr(randn(half));
[V2, ~] = qr(randn(half));
b1.rows = (1:half)';       b1.lam = abs(randn(half, 1)) + 0.5;
b1.V = V1;                 b1.Ut = V1';
b2.rows = (half+1:P)';     b2.lam = abs(randn(half, 1)) + 0.5;
b2.V = V2;                 b2.Ut = V2';
op.lam = [b1.lam; b2.lam];
op.s = 0.8;
op.V = blkdiag(V1, V2);
op.Ut = op.V';
op.Ac = []; op.SA = []; op.M = [];
op.layout = 'blocks';
op.blocks = [b1, b2];

Z = randn(P, 2);
g = op.lam ./ (op.lam + op.s(1));
Wdense = op.V * diag(g) * op.Ut;
verifyEqual(testCase, shLowLevel.opApply(op, Z, 1), Wdense * Z, ...
    'AbsTol', 1e-12);
verifyEqual(testCase, shLowLevel.opApply(op, Z, 1, 'transp'), ...
    Wdense' * Z, 'AbsTol', 1e-12);
end

function testVceRescaleScalesExactlyWithResidualsAndCovariance(testCase)
% s(t) is the ratio of observed squared residuals to formal variances, so
% it is homogeneous: quadratic in the residuals, inverse in the noise
% covariance. Both factors are powers of two here, which makes the
% identities BITWISE rather than approximate - no tolerance to choose.
rng(90212);
idx = shLowLevel.shIndex(12);
P = idx.P;
T = 4;
N = diag(abs(randn(P, 1)) + 1);
Xres = randn(P, T);

s0 = shLowLevel.vceRescale(N, Xres, idx);
verifyEqual(testCase, size(s0), [T 1]);
verifyTrue(testCase, all(s0 > 0), 'variance factors must be positive');

verifyEqual(testCase, shLowLevel.vceRescale(N, 4 * Xres, idx), 16 * s0);
verifyEqual(testCase, shLowLevel.vceRescale(4 * N, Xres, idx), s0 / 4);
end

function testVceRescaleReadsTheNoiseBandAndTheRowMask(testCase)
% Nmin selects the noise-dominated band; Rows narrows it further. Both are
% documented options, and both must change the estimate they select over.
rng(90213);
idx = shLowLevel.shIndex(12);
P = idx.P;
N = eye(P);
Xres = randn(P, 3);
% inflate ONLY the highest degrees, so a band that excludes them differs
hi = idx.n >= 10;
Xres(hi, :) = Xres(hi, :) * 10;

sAll  = shLowLevel.vceRescale(N, Xres, idx, Nmin = 2);
sHigh = shLowLevel.vceRescale(N, Xres, idx, Nmin = 10);
verifyGreaterThan(testCase, sHigh(1), sAll(1), ...
    'restricting to the inflated band must raise the variance factor');

% a Rows mask equal to the Nmin band reproduces that band's answer
sMask = shLowLevel.vceRescale(N, Xres, idx, Nmin = 2, Rows = hi);
verifyEqual(testCase, sMask, sHigh, 'AbsTol', 1e-12);
end

function testBuildSignalCovIsQuadraticInTheResiduals(testCase)
% the signal covariance is estimated from the residuals themselves, so
% scaling every residual by a must scale S by a^2. A power of two keeps
% the identity exact.
rng(90214);
idx = shLowLevel.shIndex(8);
P = idx.P;
T = 20;
Xres = randn(P, T) * 1e-10;
N = eye(P) * 1e-22;

S1 = shLowLevel.buildSignalCov(Xres, N, idx);
verifyEqual(testCase, size(S1), [P P]);
verifyTrue(testCase, all(diag(S1) >= 0), 'variances must be non-negative');

% the iteration is scale-equivariant: W = S(S+N)^-1 is unchanged when S
% AND N scale together, so scaling both by 4 scales S by exactly 4.
S2 = shLowLevel.buildSignalCov(2 * Xres, 4 * N, idx);
verifyEqual(testCase, S2, 4 * S1, 'RelTol', 1e-10);
end

% --- A18: public class methods no test named. The operators are covered by
% syntax elsewhere, but never by NAME, so a rename or a changed dispatch
% would not have been caught. Each test asserts that the operator syntax
% and the method call are the same operation - stronger than either alone.

function testCoefficientOperatorsEqualTheirMethodCalls(testCase)
rng(90215);
[gA, gB] = randomPair(10);
% randomField stamps every field Epoch = 2024.1, which is what plus's
% 0.02 yr epoch check needs; the properties are SetAccess = private, so a
% test cannot set them anyway.

% MATLAB cannot index into a parenthesised expression or a plain
% function call, so every result is named before it is compared.
sumOp = gA + gB;     sumFn     = plus(gA, gB);
difOp = gA - gB;     difFn     = minus(gA, gB);
negOp = -gA;         negFn     = uminus(gA);
mulOp = gA * 2;      mulFn     = mtimes(gA, 2);
mulFlip = 2 * gA;    mulFnFlip = mtimes(2, gA);
eleOp = gA .* 2;     eleFn     = times(gA, 2);

verifyEqual(testCase, sumFn.C, sumOp.C);
verifyEqual(testCase, sumFn.S, sumOp.S);
verifyEqual(testCase, difFn.C, difOp.C);
verifyEqual(testCase, difFn.S, difOp.S);
verifyEqual(testCase, negFn.C, negOp.C);
verifyEqual(testCase, negFn.S, negOp.S);
verifyEqual(testCase, mulFn.C, mulOp.C);
verifyEqual(testCase, mulFnFlip.C, mulFlip.C);
verifyEqual(testCase, eleFn.C, eleOp.C);

% and the algebra itself, which is what the operators promise
% combine forms a.C + sgn*b.C, so these are the SAME float operations:
% exact, no tolerance to justify.
verifyEqual(testCase, sumOp.C, gA.C + gB.C);
verifyEqual(testCase, difOp.C, gA.C - gB.C);
verifyEqual(testCase, negOp.C, -gA.C);
verifyEqual(testCase, mulOp.C, 2 * gA.C);
% a - b and a + (-b) are the same field
viaNeg = gA + (-gB);
verifyEqual(testCase, difOp.C, viaNeg.C);
% .* accepts a triangle matrix, * does not
W = tril(rand(gA.nmax + 1));
eleMat = times(gA, W);
verifyEqual(testCase, eleMat.C, gA.C .* W);
verifyError(testCase, @() mtimes(gA, W), 'shCoefficients:mtimes:badInput');
verifyError(testCase, @() times(gA, gB), 'shCoefficients:times:badInput');
end

function testSeriesMinusEqualsItsMethodCall(testCase)
rng(90216);
tsA = randomSeries(6, 5);
tsB = randomSeries(6, 5);
d1 = minus(tsA, tsB);
d2 = tsA - tsB;
verifyEqual(testCase, d1.Cs, d2.Cs);
verifyEqual(testCase, d1.Cs, tsA.Cs - tsB.Cs);
verifyEqual(testCase, d1.Ss, tsA.Ss - tsB.Ss);
end

function testFanMethodDelegatesToShFanFilter(testCase)
rng(90217);
g = randomField(14);
gf = g.fan(500, 300);
[Cf, Sf] = shLowLevel.shFanFilter(g.C, g.S, 500, 300);
verifyEqual(testCase, gf.C, Cf);
verifyEqual(testCase, gf.S, Sf);
% the series method filters every epoch the same way
ts = randomSeries(8, 3);
tf = ts.fan(500, 300);
[C1, S1] = shLowLevel.shFanFilter(ts.Cs(:, :, 2), ts.Ss(:, :, 2), 500, 300);
verifyEqual(testCase, tf.Cs(:, :, 2), C1);
verifyEqual(testCase, tf.Ss(:, :, 2), S1);
end

function testClimatologyComponentsCarryTheFittedCoefficients(testCase)
% cosAnnual/sinAnnual/cosSemiannual/sinSemiannual each return the matching
% fitted component as an shCoefficients, sigmas attached.
rng(90218);
ts = randomSeries(6, 48);
clim = ts.climatology();
pairs = {clim.cosAnnual(),     clim.cosAnnC, clim.cosAnnS;
         clim.sinAnnual(),     clim.sinAnnC, clim.sinAnnS;
         clim.cosSemiannual(), clim.cosSemiC, clim.cosSemiS;
         clim.sinSemiannual(), clim.sinSemiC, clim.sinSemiS};
for k = 1:size(pairs, 1)
    g = pairs{k, 1};
    verifyClass(testCase, g, 'shCoefficients');
    verifyEqual(testCase, g.C, pairs{k, 2});
    verifyEqual(testCase, g.S, pairs{k, 3});
end
% the four components are distinct fits, not the same object relabelled
gCos = clim.cosAnnual();  gSin = clim.sinAnnual();
verifyNotEqual(testCase, gCos.C, gSin.C);
end

function testClimatologyWithNoteAppendsToHistoryWithoutTouchingTheFit(testCase)
rng(90219);
ts = randomSeries(6, 36);
clim = ts.climatology();
n0 = numel(clim.history);
c2 = clim.withNote("checked against GravIS");
verifyEqual(testCase, numel(c2.history), n0 + 1);
verifyEqual(testCase, c2.history(end), "checked against GravIS");
% value class: the original is untouched and no coefficient moved
verifyEqual(testCase, numel(clim.history), n0);
verifyEqual(testCase, c2.trendC, clim.trendC);
verifyEqual(testCase, c2.cosAnnC, clim.cosAnnC);
end

function testClimatologyAmplitudeMapIsTheQuadratureOfItsComponents(testCase)
% A = sqrt(cos^2 + sin^2) pointwise, and the phase is atan2 of the same
% two fields - so the map must equal the synthesis of the components
% combined in quadrature, not an independent computation.
rng(90220);
ts = randomSeries(8, 48);
clim = ts.climatology();
lat = -60:20:60;
lon = 0:30:330;
[A, la, lo, ph] = clim.amplitudeMap("annual", lat, lon);
verifyEqual(testCase, size(A), [numel(lat) numel(lon)]);
verifyEqual(testCase, sort(la(:)), sort(lat(:)), 'AbsTol', 1e-12);
verifyEqual(testCase, sort(lo(:)), sort(lon(:)), 'AbsTol', 1e-12);
verifyTrue(testCase, all(A(:) >= 0), 'an amplitude cannot be negative');
verifyTrue(testCase, all(isfinite(A(:))));

gc = clim.cosAnnual();
gs = clim.sinAnnual();
Zc = gc.synthesis(lat, lon, Quantity = "geoid");
Zs = gs.synthesis(lat, lon, Quantity = "geoid");
% amplitudeMap runs exactly this synthesis on exactly these components,
% so the quadrature identity is bitwise, not approximate
verifyEqual(testCase, A, sqrt(Zc.^2 + Zs.^2));
verifyEqual(testCase, ph, atan2(Zs, Zc));
end

function ddcFixture = leakageDDCFixture()
%LEAKAGEDDCFIXTURE Closed loop for the data-driven leakage correction.
%   A catchment signal, a neighbour that is deliberately OUT OF PHASE
%   with it, and a distant third signal. Out-of-phase leakage is the
%   case the method exists for - in-phase leakage is just an amplitude
%   error and a scale factor would handle it.
nmax = 24;
lat = linspace(-89, 89, 2*nmax + 1);
lon = (0:(2*nmax + 1)) * (360 / (2*nmax + 2));
[LO, LA] = meshgrid(lon, lat);
capf = @(lat0, lon0, rad) double(sind(LA)*sind(lat0) + ...
    cosd(LA)*cosd(lat0).*cosd(LO - lon0) >= cosd(rad));
R = capf(0, 30, 18);
neigh = capf(6, 58, 14) .* (1 - R);
far = capf(-40, 200, 20);
T = 48;
t = (0:T-1)'/12;
inside = 0.20*sin(2*pi*t) + 0.05*t;
outside = 0.30*sin(2*pi*t + 2.1);      % ~120 deg out of phase
GM = 3.986004415e14; Rref = 6378136.3;
W = shLowLevel.shGaussianWeights(nmax, 500);
truth = zeros(numel(lat), numel(lon), T);
filt = zeros(size(truth));
for k = 1:T
    g = inside(k)*R + outside(k)*neigh + 0.10*sin(2*pi*t(k) + 0.7)*far;
    truth(:,:,k) = g;
    [C, S] = shLowLevel.shAnalysisGrid(g, lat, lon, nmax, GM = GM, R = Rref);
    filt(:,:,k) = shLowLevel.shSynthesis(C.*W(:), S.*W(:), GM, Rref, lat, lon);
end
cellW = repmat(cosd(lat(:)), 1, numel(lon));
area = sum(R .* cellW, "all");
fTrue = zeros(T, 1);
for k = 1:T
    fTrue(k) = sum(truth(:,:,k) .* R .* cellW, "all") / area;
end
ddcFixture = struct("lat", lat, "lon", lon, "mask", R, "filtered", filt, ...
    "truth", fTrue, "nmax", nmax, "cellW", cellW, "area", area);
end

function testLeakageDataDrivenRemovesFilteringDamage(testCase)
%TESTLEAKAGEDATADRIVENREMOVESFILTERINGDAMAGE WP5 5b, the science claim.
%   The method of deviation must move the catchment mean TOWARDS the
%   truth, in a closed loop where the truth is known. Measured on THIS
%   fixture at 55.3% of the RMS damage removed (ratio 0.447); the bound
%   is 0.75 because a closed
%   loop on one synthetic basin cannot pin a percentage that would
%   transfer to a real catchment - what must hold is the direction, by
%   a margin far outside round-off. The Python oracle
%   tools/dev/validate_leakage_datadriven.py measures 63% on its own
%   Gauss-Legendre grid; the two differ because the grids differ, not
%   because the method does.
f = leakageDDCFixture();
[fHat, info] = shLowLevel.leakageDataDriven(f.filtered, f.lat, f.lon, ...
    Mask = f.mask, Filter = "gauss500", Nmax = f.nmax);
errFiltered = sqrt(mean((info.filtered - f.truth).^2));
errCorrected = sqrt(mean((fHat - f.truth).^2));
verifyLessThan(testCase, errCorrected, 0.75 * errFiltered, sprintf( ...
    'the correction must beat doing nothing: filtered %.5f, corrected %.5f', ...
    errFiltered, errCorrected));
% and the leakage it removed must be a real quantity, not a rounding
verifyGreaterThan(testCase, sqrt(mean(info.leakage.^2)), 1e-3);
end

function testLeakageDataDrivenDecompositionIsConsistent(testCase)
%TESTLEAKAGEDATADRIVENDECOMPOSITIONISCONSISTENT The returned pieces must
%   add up: fHat = filtered - deviation - leakage, bitwise. That is the
%   whole method in one line (thesis eq. 3.29), so if info reports
%   something that does not reconstruct the output, one of them is lying.
f = leakageDDCFixture();
[fHat, info] = shLowLevel.leakageDataDriven(f.filtered, f.lat, f.lon, ...
    Mask = f.mask, Filter = "gauss500", Nmax = f.nmax);
verifyEqual(testCase, fHat, info.filtered - info.deviation - info.leakage);
end

function testLeakageDataDrivenFilteredMeanIsTheAreaWeightedAverage(testCase)
%TESTLEAKAGEDATADRIVENFILTEREDMEANISTHEAREAWEIGHTEDAVERAGE info.filtered
%   is what the user would have had without the function, so it must be
%   the plain cos(lat)-weighted catchment average of the input -
%   recomputed here independently rather than trusted.
f = leakageDDCFixture();
[~, info] = shLowLevel.leakageDataDriven(f.filtered, f.lat, f.lon, ...
    Mask = f.mask, Filter = "gauss500", Nmax = f.nmax);
T = numel(info.filtered);
want = zeros(T, 1);
for k = 1:T
    want(k) = sum(f.filtered(:,:,k) .* f.mask .* f.cellW, "all") / f.area;
end
verifyEqual(testCase, info.filtered, want, "RelTol", 1e-12);
end

function testLeakageDataDrivenPhaseFollowsTheLeakage(testCase)
%TESTLEAKAGEDATADRIVENPHASEFOLLOWSTHELEAKAGE Metamorphic: the phase step
%   must respond to the thing it measures. Two runs differing ONLY in
%   the phase of the signal outside the catchment must not report the
%   same phase - if they do, the Hilbert regression is not looking at
%   the leakage at all, which a single closed-loop number would hide.
f = leakageDDCFixture();
[~, a] = shLowLevel.leakageDataDriven(f.filtered, f.lat, f.lon, ...
    Mask = f.mask, Filter = "gauss500", Nmax = f.nmax);
% rebuild with the outside signal in phase with the inside one
nmax = f.nmax; lat = f.lat; lon = f.lon;
[LO, LA] = meshgrid(lon, lat);
capf = @(lat0, lon0, rad) double(sind(LA)*sind(lat0) + ...
    cosd(LA)*cosd(lat0).*cosd(LO - lon0) >= cosd(rad));
neigh = capf(6, 58, 14) .* (1 - f.mask);
far = capf(-40, 200, 20);
T = 48; t = (0:T-1)'/12;
GM = 3.986004415e14; Rref = 6378136.3;
W = shLowLevel.shGaussianWeights(nmax, 500);
filt2 = zeros(size(f.filtered));
for k = 1:T
    g = (0.20*sin(2*pi*t(k)) + 0.05*t(k))*f.mask ...
        + 0.30*sin(2*pi*t(k))*neigh ...
        + 0.10*sin(2*pi*t(k) + 0.7)*far;
    [C, S] = shLowLevel.shAnalysisGrid(g, lat, lon, nmax, GM = GM, R = Rref);
    filt2(:,:,k) = shLowLevel.shSynthesis(C.*W(:), S.*W(:), GM, Rref, lat, lon);
end
[~, b] = shLowLevel.leakageDataDriven(filt2, lat, lon, ...
    Mask = f.mask, Filter = "gauss500", Nmax = nmax);
verifyNotEqual(testCase, a.phaseDeg, b.phaseDeg);
verifyTrue(testCase, isfinite(a.phaseDeg) && abs(a.phaseDeg) <= 180);
verifyTrue(testCase, isfinite(b.phaseDeg) && abs(b.phaseDeg) <= 180);
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

function testEllipsoidSynthesisMatchesOracle(testCase)
%TESTELLIPSOIDSYNTHESISMATCHESORACLE WP3 acceptance: synthesis on the WGS84
%   ellipsoid against tools/dev/validate_ellipsoid.py, which evaluates the
%   same series point by point through an independent (textbook) Legendre
%   route. The bound is the WP's 1e-12, on max|diff| / max|pin| per
%   quantity - normalised by the field, as testSynthesisPointsMethodsAgree
%   does, so a pin near a zero crossing cannot inflate it.
[C, S, GM, R] = wp3Coefficients();
pts = [-90 0; -63.5 33; 0 121.5; 45 250; 89.5 33];
pins = struct( ...
    'potential', [0.0043226064857430887, 0.0089477505959887071, ...
        -0.065316448053777801, 0.032913591268445355, -0.060528657390604278], ...
    'gravity_disturbance', [-4.8622701506266225e-08, -4.2311914572232842e-09, ...
        -1.5474488650883772e-07, 4.3384394318088625e-08, -7.8296641453290037e-08], ...
    'gravity_anomaly', [-4.9982706197987986e-08, -7.0445103916040198e-09, ...
        -1.3426353025895537e-07, 3.3046265836462187e-08, -5.925275269694826e-08], ...
    'gravity_gradient_rr', [-3.5995610605408723e-13, -5.529726166864861e-14, ...
        -4.3560363127159758e-13, 8.4410141018049349e-14, -3.7482151441896534e-13]);
for q = string(fieldnames(pins))'
    want = pins.(q);
    got = zeros(size(want));
    for i = 1:size(pts, 1)
        got(i) = shLowLevel.shSynthesis(C, S, GM, R, pts(i, 1), pts(i, 2), ...
            Quantity = q, Surface = "ellipsoid");
    end
    verifyLessThan(testCase, max(abs(got - want)) / max(abs(want)), 1e-12, q);
end
% Height adds to r(phi), not to R
ptsH = [-63.5 33; 45 250];
wantH = [-4.1486890444900083e-09, 4.325857293161722e-08];
gotH = zeros(1, 2);
for i = 1:2
    gotH(i) = shLowLevel.shSynthesis(C, S, GM, R, ptsH(i, 1), ptsH(i, 2), ...
        Quantity = "gravity_disturbance", Surface = "ellipsoid", Height = 1500);
end
verifyLessThan(testCase, max(abs(gotH - wantH)) / max(abs(wantH)), 1e-12, ...
    'gravity_disturbance at Height 1500 above the ellipsoid');
end

function testEllipsoidGradientMatchesOracle(testCase)
%TESTELLIPSOIDGRADIENTMATCHESORACLE North, east and up at r(phi) against
%   the oracle, which checked its own north/east against finite differences
%   at FIXED r (7.6e-12) - the components are spherical-frame partials at
%   the point, and that is what is pinned.
[C, S, GM, R] = wp3Coefficients();
lat = [-63.5 0 45];
lon = [33 121.5 250];
want = [-2.806707148643133e-08,   5.7202412376681814e-09,  4.2311914572231651e-09; ...
        -8.556237628774138e-09,   1.2808321610165758e-08,  1.5474488650883774e-07; ...
        -1.1000901490334231e-07, -1.5112245273265289e-07, -4.3384394318088612e-08];
dq = shLowLevel.shSynthesisGradient(C, S, GM, R, lat, lon, ...
    Quantity = "potential", Surface = "ellipsoid", Mode = "points");
got = [dq.north(:), dq.east(:), dq.up(:)];
names = ["north", "east", "up"];
for j = 1:3
    verifyLessThan(testCase, max(abs(got(:, j) - want(:, j))) ...
        / max(abs(want(:, j))), 1e-12, names(j));
end
end

function testEllipsoidRadialIdentity(testCase)
%TESTELLIPSOIDRADIALIDENTITY d(potential)/dr = -gravity_disturbance must
%   survive the move to the ellipsoid. The gradient takes its radius per
%   latitude inside its loop and the synthesis per latitude inside its
%   reduction - two implementations of the new radial law, tied to each
%   other by an identity rather than by a shared helper.
[C, S, GM, R] = wp3Coefficients();
lat = -88:8:88;
lon = 0:30:330;
dq = shLowLevel.shSynthesisGradient(C, S, GM, R, lat, lon, ...
    Quantity = "potential", Surface = "ellipsoid");
gd = shLowLevel.shSynthesis(C, S, GM, R, lat, lon, ...
    Quantity = "gravity_disturbance", Surface = "ellipsoid");
verifyLessThan(testCase, max(abs(dq.up(:) + gd(:))) / max(abs(gd(:))), 1e-12);
end

function testEllipsoidRadiusGeometry(testCase)
%TESTELLIPSOIDRADIUSGEOMETRY r(phi) is the ellipse, a at the equator, b at
%   the poles, a sphere at f = 0, and its default a is the one
%   shLowLevel.normalFieldCS uses - two places holding WGS84's a, pinned
%   so they cannot drift apart.
lat = linspace(-90, 90, 721);
r = shLowLevel.ellipsoidRadius(lat);
a = 6378137;
f = 1/298.257223563;
b = a * (1 - f);
x = r .* cosd(lat);
z = r .* sind(lat);
verifyLessThan(testCase, max(abs((x/a).^2 + (z/b).^2 - 1)), 1e-14);
verifyEqual(testCase, shLowLevel.ellipsoidRadius(0), a);
verifyEqual(testCase, shLowLevel.ellipsoidRadius([-90 90]), [b b], 'RelTol', 1e-15);
[~, nf] = shLowLevel.normalFieldCS(2);
verifyEqual(testCase, shLowLevel.ellipsoidRadius(0), nf.a, ...
    'the default semi-major axis must be the one normalFieldCS uses');
verifyEqual(testCase, shLowLevel.ellipsoidRadius(lat, Flattening = 0), a * ones(size(lat)));
verifySize(testCase, shLowLevel.ellipsoidRadius(zeros(3, 2)), [3 2]);
end

function testEllipsoidGridMatchesPoints(testCase)
%TESTELLIPSOIDGRIDMATCHESPOINTS Grid synthesis on the ellipsoid against
%   synthesisPoints handed r = ellipsoidRadius(lat) + h: two evaluators
%   that share only legendreALF and the house constants, so this is the
%   check that the per-latitude factor puts each row at the right radius.
[C, S, GM, R] = wp3Coefficients();
lat = [-77 -31.5 0 12 58 83];
lon = [10 95 180 271 333];
[LO, LA] = meshgrid(lon, lat);
for h = [0 900]
    grid = shLowLevel.shSynthesis(C, S, GM, R, lat, lon, ...
        Quantity = "gravity_disturbance", Surface = "ellipsoid", Height = h);
    rr = shLowLevel.ellipsoidRadius(LA(:)) + h;
    pts = shLowLevel.synthesisPoints(C, S, GM, R, LA(:), LO(:), rr, ...
        Quantity = "disturbance", Method = "direct", Nmin = 0);
    verifyLessThan(testCase, max(abs(grid(:) - pts)) / max(abs(pts)), 1e-12, ...
        sprintf('h = %g', h));
end
end

% ------------------------------------------ WP5 5e: readGrid, the inverse of writeGrid
function testReadGridIsTheInverseOfWriteGrid(testCase)
%TESTREADGRIDISTHEINVERSEOFWRITEGRID a 2-D grid and a 3-D stack written by
%   writeGrid come back as they went in: the values bitwise, the latitudes
%   in their own order (north to south here), the recorded latitude type,
%   and the epochs through writeGrid's time axis.
lat = (88:-4:-88)';
lon = (0:4:356)';
[LA, LO] = ndgrid(lat, lon);
G = sind(LA) .* cosd(LO);
f2 = [tempname, '.nc'];
c2 = onCleanup(@() delete(f2));
shLowLevel.writeGrid(f2, G, lat, lon, Name = "ewh", Units = "m", ...
    LatType = "geodetic", Sidecar = false);
[g, la, lo, info] = shLowLevel.readGrid(f2);
verifyEqual(testCase, g, G);
verifyEqual(testCase, la, lat);
verifyEqual(testCase, lo, lon);
verifyEqual(testCase, [info.var, info.units, info.latType], ["ewh", "m", "geodetic"]);
verifyEmpty(testCase, info.epochs);
ep = [2010.1; 2010.2; 2016.999];          % 2016 is a leap year
f3 = [tempname, '.nc'];
c3 = onCleanup(@() delete(f3));
G3 = cat(3, G, 2 * G, -G);
shLowLevel.writeGrid(f3, G3, lat, lon, Name = "ewh", Epochs = ep, Sidecar = false);
[g3, ~, ~, i3] = shLowLevel.readGrid(f3);
verifyEqual(testCase, g3, G3);
% writeGrid stores the epochs as double days since 2002-01-01; the way back
% through datetime loses at most a few ulps of that day count, far below
% 1e-9 yr (32 ms) - validate_readgrid.py CLAIM 2 measures the chain at 0
verifyEqual(testCase, i3.epochs, ep, 'AbsTol', 1e-9);
end

function testReadGridReadsAnyDimensionOrderAndLongitudeRange(testCase)
%TESTREADGRIDREADSANYDIMENSIONORDERANDLONGITUDERANGE a file laid out
%   (latitude, longitude, time) - writeGrid writes (lon, lat, time) - with
%   coordinates found by their units rather than their names, longitudes
%   from -180, and hours as the time unit. The longitudes come back 0..360
%   ascending with the columns moved to match.
lat = (-60:30:60)';
lon = (-180:45:135)';
T = 3;
[LA, LO] = ndgrid(lat, lon);
X = zeros(numel(lat), numel(lon), T);
for k = 1:T
    X(:, :, k) = k * LA + LO / 1000;
end
f = [tempname, '.nc'];
c = onCleanup(@() delete(f));
nccreate(f, 'y', 'Dimensions', {'y', numel(lat)});
ncwrite(f, 'y', lat);
ncwriteatt(f, 'y', 'units', 'degrees_north');
nccreate(f, 'x', 'Dimensions', {'x', numel(lon)});
ncwrite(f, 'x', lon);
ncwriteatt(f, 'x', 'units', 'degrees_east');
nccreate(f, 'time', 'Dimensions', {'time', T});
ncwrite(f, 'time', [0; 36; 8784]);
ncwriteatt(f, 'time', 'units', 'hours since 2000-01-01 00:00:00');
nccreate(f, 'field', 'Dimensions', {'y', numel(lat), 'x', numel(lon), 'time', T});
ncwrite(f, 'field', X);
[g, la, lo, info] = shLowLevel.readGrid(f);
[lw, order] = sort(mod(lon, 360));
verifyEqual(testCase, lo, lw);
verifyEqual(testCase, la, lat);
verifyEqual(testCase, g, X(:, order, :));
% validate_readgrid.py CLAIM 1 prints these to 12 decimals
verifyEqual(testCase, info.epochs, [2000; 2000.004098360656; 2001], 'AbsTol', 1e-12);
end

function testCFTimeUnitsAreReadOneWay(testCase)
%TESTCFTIMEUNITSAREREADONEWAY GravIS writes "days since 2002-4-18 00:00:00"
%   - a one-digit month that readMascon's own pattern refused before
%   v5.8.0. readGrid and readMascon now share one decoder, so both read it,
%   and both give validate_readgrid.py's epochs.
lat = (-80:40:80)';
lon = (0:60:300)';
[LA, LO] = ndgrid(lat, lon);
G3 = cat(3, LA + LO, LA - LO, LA .* LO);
f = [tempname, '.nc'];
c = onCleanup(@() delete(f));
shLowLevel.writeGrid(f, G3, lat, lon, Name = "lwe_thickness", ...
    Epochs = [2010.1; 2010.2; 2010.3], Sidecar = false);
ncwrite(f, 'time', [0.29; 15.5; 8764]);
ncwriteatt(f, 'time', 'units', 'days since 2002-4-18 00:00:00');
want = [2002.293945205480; 2002.335616438356; 2026.287671232877];
[~, ~, ~, info] = shLowLevel.readGrid(f);
verifyEqual(testCase, info.epochs, want, 'AbsTol', 1e-12);
m = shLowLevel.readMascon(f);
verifyEqual(testCase, m.epoch, info.epochs, ...
    'readMascon and readGrid read one time axis two ways');
end

% ------------------------------------------------ WP5: the method of scale
function testLeakageMethodOfScale(testCase)
%TESTLEAKAGEMETHODOFSCALE the method of scale (thesis eq. 3.28) on the 5b
%   closed loop. FHAT is s (gbar_c - lhat), bitwise; s is int R / int R
%   Rbar (eq. 2.27), recomputed here through the same chain; s holds no
%   data - it is the same for any series on one catchment and filter; for
%   a uniform layer inside the catchment it repairs the attenuation
%   exactly, the case the uniform-layer approximation (2.26) makes exact;
%   and on the closed loop it moves the catchment mean towards the truth.
f = leakageDDCFixture();
[fHat, info] = shLowLevel.leakageDataDriven(f.filtered, f.lat, f.lon, ...
    Mask = f.mask, Filter = "gauss500", Nmax = f.nmax, Method = "scale");
verifyEqual(testCase, info.method, "scale");
verifyEqual(testCase, fHat, info.scale * (info.filtered - info.leakage));

% s through the same analysis-filter-synthesis chain. Measured bitwise on
% MATTHIASPC; 4 eps allows another summation order of the catchment sums.
GM = 3.986004415e14; Rref = 6378136.3;
W = shLowLevel.shGaussianWeights(f.nmax, 500);
[C, S] = shLowLevel.shAnalysisGrid(f.mask, f.lat, f.lon, f.nmax, ...
    GM = GM, R = Rref);
Rbar = shLowLevel.shSynthesis(C.*W(:), S.*W(:), GM, Rref, f.lat, f.lon);
s = f.area / sum(f.mask .* Rbar .* f.cellW, "all");
verifyEqual(testCase, info.scale, s, 'RelTol', 4*eps);

% no data in s: the method of deviation on the same series reports it too
[~, iDev] = shLowLevel.leakageDataDriven(f.filtered, f.lat, f.lon, ...
    Mask = f.mask, Filter = "gauss500", Nmax = f.nmax);
verifyEqual(testCase, iDev.scale, info.scale);

% a uniform layer confined to the catchment, as the filter delivers it
T = numel(info.filtered);
layer = 0.3 + 0.1 * sin(2*pi*(0:T-1)'/12);
U = zeros(size(f.filtered));
for k = 1:T
    U(:, :, k) = layer(k) * Rbar;
end
[~, iU] = shLowLevel.leakageDataDriven(U, f.lat, f.lon, Mask = f.mask, ...
    Filter = "gauss500", Nmax = f.nmax, Method = "scale");
verifyEqual(testCase, iU.scale, info.scale);
% worst measured 3.7e-16 here, 1.5e-16 in the oracle's CLAIM 4; 1e-14
% bounds the round-off of the ~2500-term weighted catchment sum
verifyEqual(testCase, iU.scale * iU.filtered, layer, 'RelTol', 1e-14);

% the closed loop: measured 75.0% of the RMS damage removed on THIS
% fixture (ratio 0.250; the method of deviation 0.447). The bound is
% directional, as in testLeakageDataDrivenRemovesFilteringDamage. The
% fixture's catchment signal is a uniform layer - the case s is exact
% for - so this ranks nothing; the oracle's CLAIM 5 measures 78.6%.
errFiltered = sqrt(mean((info.filtered - f.truth).^2));
errScale = sqrt(mean((fHat - f.truth).^2));
verifyLessThan(testCase, errScale, 0.5 * errFiltered, sprintf( ...
    'the method of scale must beat doing nothing: filtered %.5f, scaled %.5f', ...
    errFiltered, errScale));
end

% ------------------------------------------------ WP5 5a: Earth rotation
function testRotationExcitationInvertsChenWilson(testCase)
%TESTROTATIONEXCITATIONINVERTSCHENWILSON rotationExcitation is Chen &
%   Wilson (2003) eq. (1) solved for the excitation. Checked three ways:
%   the unit responses against tools/dev/validate_excitation.py, which
%   solves the equation independently; the inverse pair - eq. (1) as
%   printed, written out here, turns the excitation into coefficient
%   changes and the lane must return it; and a static field on every
%   epoch changes nothing. The constants are the oracle's SYNTHETIC round
%   numbers of the Earth's order: test inputs, not the Earth's constants.
E = struct('M', 6.0e24, 'R', 6.4e6, 'C', 8.0e37, 'A', 7.97e37);
kn = [0; 0.027; -0.301];
% unit responses, pinned from the oracle's CLAIM 1: two evaluations of one
% closed form that differ only in the order of the products, so 1e-14
% bounds a few eps of round-off
[u, info] = shLowLevel.rotationExcitation(1e-10, 1e-10, C20 = 1e-10, ...
    Earth = E, kn = kn, Reference = "none");
verifyEqual(testCase, u.chi1, -34.266095109520862, 'RelTol', 1e-14);
verifyEqual(testCase, u.chi2, u.chi1);
verifyEqual(testCase, u.chi3, -4.933245801278163e-10, 'RelTol', 1e-14);
verifyEqual(testCase, info.k2, -0.301);

% the inverse pair: eq. (1) as printed, from excitations to coefficients
mas = 180 / pi * 3600e3;
t = (0:23)' / 12;
chi1 = 30 * cos(2*pi*t);
chi2 = 20 * sin(2*pi*t + 0.4);
chi3 = 5e-10 * cos(4*pi*t);
k2 = kn(3);
r2m = E.R^2 * E.M;
dC21 = -(1 + k2) * sqrt(3/5) * (E.C - E.A) / (1.098 * r2m) * chi1 / mas;
dS21 = -(1 + k2) * sqrt(3/5) * (E.C - E.A) / (1.098 * r2m) * chi2 / mas;
dC20 = -(1 + k2) * 3 / (2 * sqrt(5)) * E.C / (0.753 * r2m) * chi3;
back = shLowLevel.rotationExcitation(dC21, dS21, C20 = dC20, Earth = E, ...
    kn = kn, Reference = "none");
% relative to each amplitude; the oracle closes this pair to 2.4e-16, and
% 1e-14 bounds the ten or so products of the two scale factors
verifyEqual(testCase, back.chi1, chi1, 'AbsTol', 1e-14 * 30);
verifyEqual(testCase, back.chi2, chi2, 'AbsTol', 1e-14 * 20);
verifyEqual(testCase, back.chi3, chi3, 'AbsTol', 1e-14 * 5e-10);

% a static field on every epoch goes with the mean. The offsets are of the
% order of the changes, so removing them costs ~20 eps: 1e-12 bounds it.
% (The oracle's CLAIM 2 also removes a realistic C20 of -4.8e-4, where the
% loss is 7.5e-10 relative - the digits a double holds, not the method.)
off = shLowLevel.rotationExcitation(dC21 + 1e-9, dS21 - 3e-9, ...
    C20 = dC20 + 2e-10, Earth = E, kn = kn);
ref = shLowLevel.rotationExcitation(dC21, dS21, C20 = dC20, Earth = E, ...
    kn = kn);
verifyEqual(testCase, off.chi1, ref.chi1, 'AbsTol', 1e-12 * 30);
verifyEqual(testCase, off.chi2, ref.chi2, 'AbsTol', 1e-12 * 20);
verifyEqual(testCase, off.chi3, ref.chi3, 'AbsTol', 1e-12 * 5e-10);
end

function testRotationExcitationIERS2010AndLengthOfDay(testCase)
%TESTROTATIONEXCITATIONIERS2010ANDLENGTHOFDAY the default constants are the
%   IERS Conventions (2010) Table 1.1 values turned into M, C and A by the
%   definitions of J2 and H, and dLOD is chi3 times the rotation period
%   2 pi / Omega (ESMGFZ Product Description, eq. 2.8 read dimensionally).
%   Every number is pinned from tools/dev/validate_excitation.py CLAIMs 4
%   and 5, which also checks C and A against ESMGFZ's own Table 2.1.
kn = [0; 0.027; -0.301];
[u, info] = shLowLevel.rotationExcitation(1e-10, 1e-10, C20 = 1e-10, ...
    kn = kn, Reference = "none");
% the same arithmetic in both - one division for M, two products and a
% division for C - so 1e-14 bounds a few eps of round-off
verifyEqual(testCase, info.earth.M, 5.9721863901424573e+24, 'RelTol', 1e-14);
verifyEqual(testCase, info.earth.R, 6378136.6);
verifyEqual(testCase, info.earth.C, 8.0343718677901266e+37, 'RelTol', 1e-14);
verifyEqual(testCase, info.earth.A, 8.008068981341215e+37, 'RelTol', 1e-14);
verifyEqual(testCase, u.chi1, -38.636008081516209, 'RelTol', 1e-14);
verifyEqual(testCase, u.chi3, -4.8560214957516874e-10, 'RelTol', 1e-14);
verifyEqual(testCase, info.lodScale, 86164100.637189433, 'RelTol', 1e-14);
verifyEqual(testCase, u.dLOD, -0.041841472485630353, 'RelTol', 1e-14);
verifyEqual(testCase, u.dLOD, info.lodScale * u.chi3);
% mass moved towards the equator lowers C20 and must lengthen the day
d = shLowLevel.rotationExcitation(0, 0, C20 = -1e-10, kn = kn, ...
    Reference = "none");
verifyGreaterThan(testCase, d.dLOD, 0);
% dLOD scales with the rotation period, 2 pi / Omega
[~, i2] = shLowLevel.rotationExcitation(0, 0, kn = kn, ...
    Omega = 2 * 7.292115e-5);
verifyEqual(testCase, i2.lodScale, info.lodScale / 2, 'RelTol', 1e-15);
% without C20 there is no axial term at all
verifyEmpty(testCase, shLowLevel.rotationExcitation(0, 0, kn = kn).dLOD);
end

% ------------------------------------------------ WP5 5d: the gap series
function testParseGraceFilenameQuantumFrontiersMonthly(testCase)
%TESTPARSEGRACEFILENAMEQUANTUMFRONTIERSMONTHLY the HLSST+SLR series at ICGEM
%   names its months ..._YYYY_MM. The parser gives them the month's span
%   and mid-point, exactly as it does ITSG's ..._YYYY-MM, and no epoch for
%   a thirteenth month.
m = shLowLevel.parseGraceFilename( ...
    'QuantumFrontiers_HLSST_SLR_COMB2023s_unfiltered_2017_08.gfc');
verifyEqual(testCase, [m.epochStart, m.epoch, m.epochStop], ...
    2017 + [7, 7.5, 8] / 12);
itsg = shLowLevel.parseGraceFilename('ITSG-Grace2018_n60_2017-08.gfc');
verifyEqual(testCase, m.epoch, itsg.epoch);
bad = shLowLevel.parseGraceFilename('QuantumFrontiers_x_2017_13.gfc');
verifyTrue(testCase, isnan(bad.epoch));
end

function testBridgeGapsCalibration(testCase)
%TESTBRIDGEGAPSCALIBRATION the gap fill's offset, per-degree scale and
%   sigma on the small case of tools/dev/validate_bridge.py CLAIM 0 - nmax
%   2, six reference months, eight bridge months, no smoothing - pinned;
%   the filled months flagged in their names and in info.bridged; the
%   reference months untouched; and a bridge equal to the reference fills
%   with its own values.
[ref, br] = bridgeCase(false);
[out, info] = shLowLevel.bridgeGaps(ref, br, RadiusKm = 0, MinOverlap = 6);
% the oracle sums in another order: 1e-12 bounds that round-off
verifyEqual(testCase, info.scale, [1.0866812354123745; ...
    1.1944752466336102; 1.2610735219002618], 'RelTol', 1e-12);
verifyEqual(testCase, info.sigma, [1.7114409225940354e-11; ...
    1.8937617115670034e-11; 1.698346212018187e-11], 'RelTol', 1e-12);
verifyEqual(testCase, out.Cs(3, 2, 4), -3.8803624627509443e-10, 'RelTol', 1e-12);
verifyEqual(testCase, out.Ss(3, 3, 4), -1.5297761163400555e-10, 'RelTol', 1e-12);
verifyEqual(testCase, info.bridged, logical([0 0 0 1 0 0 1 0]'));
verifyEqual(testCase, info.overlap, 6);
verifyTrue(testCase, all(startsWith(out.names(info.bridged), "bridge:")));
verifyTrue(testCase, issorted(out.epochs));
verifyTrue(testCase, isequal(out.Cs(:, :, ~info.bridged), ref.Cs) && ...
    isequal(out.Ss(:, :, ~info.bridged), ref.Ss), ...
    'the reference months must come through untouched');
low = tril(ones(3));
verifyEqual(testCase, out.sigmaCs(:, :, 4), low .* info.sigma);
lowS = low;
lowS(:, 1) = 0;
verifyEqual(testCase, out.sigmaSs(:, :, 7), lowS .* info.sigma);
% a bridge equal to the reference: the scale is one and the fill is the
% bridge, to the round-off of adding and removing one mean (~1e-26 here)
[ref2, br2] = bridgeCase(true);
[out2, info2] = shLowLevel.bridgeGaps(ref2, br2, RadiusKm = 0, MinOverlap = 6);
verifyEqual(testCase, info2.scale, ones(3, 1), 'AbsTol', 1e-12);
verifyEqual(testCase, out2.Cs(:, :, info2.bridged), br2.Cs(:, :, [4 7]), 'AbsTol', 1e-24);
verifyEqual(testCase, out2.Ss(:, :, info2.bridged), br2.Ss(:, :, [4 7]), 'AbsTol', 1e-24);
end

function [ref, br] = bridgeCase(equal)
%BRIDGECASE validate_bridge.py's small case: nmax 2, a truth T(t), the
%   reference T at months 1 2 3 5 6 8, the bridge 0.8 T plus an offset and
%   a wobble at months 1 to 8 - or T itself when EQUAL.
[m, n] = meshgrid(0:2, 0:2);
mc = double(m <= n);
ms = double(m <= n & m >= 1);
Cs = zeros(3, 3, 8);
Ss = Cs;
bC = Cs;
bS = Cs;
for t = 1:8
    c = (n + 1 + m) .* sin(t + n - m) * 1e-10 .* mc;
    s = (n + 2 - m) .* cos(t - n + m) * 1e-10 .* ms;
    Cs(:, :, t) = c;
    Ss(:, :, t) = s;
    if equal
        bC(:, :, t) = c;
        bS(:, :, t) = s;
    else
        bC(:, :, t) = 0.8 * c + (1e-11 * (n + m + 1) + 2e-11 * cos(3 * t + n .* m)) .* mc;
        bS(:, :, t) = 0.8 * s + (-1e-11 * (n - m + 1) + 2e-11 * sin(2 * t + n + m)) .* ms;
    end
end
ep = 2010 + ((1:8)' - 0.5) / 12;
keep = [1 2 3 5 6 8];
ref = shSeries(Cs(:, :, keep), Ss = Ss(:, :, keep), Epochs = ep(keep), ...
    Names = "ref" + string(keep'));
br = shSeries(bC, Ss = bS, Epochs = ep, Names = "hl" + string((1:8)'));
end

% ------------------------------------------- WP8 8a: the regional basis
function testSynthesisMatrixGridOnlyIsTheSameGrid(testCase)
%TESTSYNTHESISMATRIXGRIDONLYISTHESAMEGRID GridOnly = true returns the
%   weights and the grid of the full call bit for bit and no matrix, so
%   evalMask, which now asks for the grid only, sees the grid it saw.
idx = shLowLevel.shIndex(20);
[Y1, w1, g1] = shLowLevel.synthesisMatrix(idx, NLat = 42, NLon = 84);
[Y2, w2, g2] = shLowLevel.synthesisMatrix(idx, NLat = 42, NLon = 84, ...
    GridOnly = true);
verifyEmpty(testCase, Y2);
verifyNotEmpty(testCase, Y1);
verifyTrue(testCase, isequal(w1, w2) && isequal(g1, g2), ...
    'GridOnly changed the weights or the grid');
end

function testRegionalBasisNodeGrids(testCase)
%TESTREGIONALBASISNODEGRIDS With a region covering the sphere every node
%   is selected, so the basis carries the global grid: the icosahedral
%   grid has exactly 10 (j+1)^2 + 2 nodes (Woehnke et al. 2025, eq. 8),
%   the default level is the smallest with at least (nmax+1)^2 nodes
%   (j = 9 at nmax 30, as validate_regional_basis.py CLAIM 0c's rule
%   gives), and the Reuter grid has one node on each pole and about
%   4 gamma^2 / pi nodes (CLAIM 0b: 2013 at gamma 40, 1.2% below).
idx = shLowLevel.shIndex(12);
everywhere = @(la, lo) ones(size(la));
for j = 0:3
    B = shLowLevel.regionalBasis(idx, everywhere, Level = j, BufferKm = 0);
    verifyEqual(testCase, B.nGlobal, 10 * (j + 1)^2 + 2);
    verifyEqual(testCase, B.K, B.nGlobal);
    u = [cosd(B.nodes(:, 1)) .* cosd(B.nodes(:, 2)), ...
         cosd(B.nodes(:, 1)) .* sind(B.nodes(:, 2)), sind(B.nodes(:, 1))];
    d = acos(max(min(u * u', 1), -1)) + 4 * eye(B.K);
    verifyGreaterThan(testCase, min(d(:)), 0.5 * 1.1 / (j + 1), ...
        'two icosahedral nodes nearly coincide - deduplication failed');
end
B = shLowLevel.regionalBasis(shLowLevel.shIndex(30), everywhere, BufferKm = 0);
verifyEqual(testCase, B.level, 9);
verifyEqual(testCase, B.nGlobal, 1002);
R = shLowLevel.regionalBasis(idx, everywhere, Grid = "reuter", Level = 40, ...
    BufferKm = 0);
verifyEqual(testCase, R.nGlobal, 2013);
verifyEqual(testCase, sum(abs(R.nodes(:, 1)) == 90), 2);
verifyEqual(testCase, R.K, R.nGlobal);
end

function testRegionalBasisRBFIsTheLegendreSeries(testCase)
%TESTREGIONALBASISRBFISTHELEGENDRESERIES A column of T synthesises to
%   sum_n phi_n (2n+1) P_n(cos psi), the addition theorem, here checked
%   against MATLAB's own legendre() rather than the ALF recursion that
%   built T. Nodes include both poles (Reuter grid); the 50 points are
%   validate_regional_basis.py CLAIM 1's, which measured 1.24e-14
%   relative; the bound is 3x that.
idx = shLowLevel.shIndex(30);
lat = linspace(-89.9, 89.9, 50)';
lon = mod(137.508 * (0:49)', 360);
Yp = shLowLevel.ylm(deg2rad(lat), deg2rad(lon), idx);
worst = 0;
for kern = ["kaula", "shannon"]
    B = shLowLevel.regionalBasis(idx, @(la, lo) ones(size(la)), ...
        Grid = "reuter", Level = 12, BufferKm = 0, Kernel = kern);
    cols = [find(B.nodes(:, 1) == 90, 1), find(B.nodes(:, 1) == -90, 1), ...
            round(B.K / 3), round(2 * B.K / 3)];
    f = Yp * B.T(:, cols);
    for c = 1:numel(cols)
        x0 = B.nodes(cols(c), :);
        cpsi = sind(lat) * sind(x0(1)) + cosd(lat) .* cosd(x0(1)) .* ...
            cosd(lon - x0(2));
        cpsi = min(max(cpsi, -1), 1);
        ref = zeros(size(lat));
        for n = 2:30
            Pn = legendre(n, cpsi');
            ref = ref + B.kernel(n + 1) * (2 * n + 1) * Pn(1, :)';
        end
        worst = max(worst, max(abs(f(:, c) - ref)) / max(abs(ref)));
    end
end
verifyLessThan(testCase, worst, 3 * 1.24e-14);
end

function testRegionalProjectNormalEquations(testCase)
%TESTREGIONALPROJECTNORMALEQUATIONS The rbf projector is the region-
%   weighted least-squares fit: T'K (x - T Proj x) = 0 and a field in the
%   span of T is reproduced over the region. Configuration of
%   validate_regional_basis.py CLAIM 3 (nmax 30, a 40 deg polar cap plus
%   600 km, default icosahedral level): 143 of 1002 nodes, full rank.
%   Over two random draws the oracle measured up to 2.0e-11 for the
%   normal equations and 9.4e-12 for the span; the bounds are 3x those.
idx = shLowLevel.shIndex(30);
B = shLowLevel.regionalBasis(idx, @(la, lo) double(la > 50));
verifyEqual(testCase, B.K, 143);
verifyEqual(testCase, B.nGlobal, 1002);
verifyEqual(testCase, B.rank, 143);
nL = 2 * 31; nO = 2 * 62;
[Y, w] = shLowLevel.synthesisMatrix(idx, NLat = nL, NLon = nO);
Kq = Y' * ((w .* B.region.mask) .* Y);
rng(8);
x = randn(idx.P, 1) ./ max(idx.n, 1).^2;
ne = max(abs(B.T' * Kq * (x - B.T * (B.Proj * x)))) / max(abs(B.T' * Kq * x));
verifyLessThan(testCase, ne, 3 * 2.0e-11);
a0 = randn(B.K, 1);
d = Y * (B.T * (B.Proj * (B.T * a0)) - B.T * a0);
f0 = Y * (B.T * a0);
reg = sqrt(sum(w .* B.region.mask .* d.^2) / sum(w .* B.region.mask .* f0.^2));
verifyLessThan(testCase, reg, 3 * 9.4e-12);
end

function testRegionalProjectSlepianIsSlepianProject(testCase)
%TESTREGIONALPROJECTSLEPIANISSLEPIANPROJECT For a Slepian basis the
%   region-weighted projector IS G' (the tapers are K's eigenvectors), so
%   regionalProject equals slepianProject with G = B.T; and the general
%   formula (G'KG)^-1 G'K, formed here from K, agrees with G' to the
%   eigen-solver's rounding amplified by 1/lambda_min of the kept tapers
%   (bound 100 eps / lambda_min; the oracle measured 2.2e-15 at nmax 30).
idx = shLowLevel.shIndex(12, Nmin = 0);
cap = @(la, lo) double(la > 60);
B = shLowLevel.regionalBasis(idx, cap, Type = "slepian", BufferKm = 0, ...
    Threshold = 0.5);
verifyGreaterThanOrEqual(testCase, min(B.lambda), 0.5);
g = randomFieldNmax(12);
a1 = shLowLevel.regionalProject(g.C, g.S, B);
a2 = shLowLevel.slepianProject(g.C, g.S, B.T, idx);
% the same dot products, G' formed explicitly or by the BLAS transpose:
% at most a rounding per term apart
x = shLowLevel.vecFromCS(g.C, g.S, idx);
verifyLessThanOrEqual(testCase, max(abs(a1 - a2)), ...
    idx.P * eps * max(abs(B.T)' * abs(x)));
[Y, w] = shLowLevel.synthesisMatrix(idx, NLat = 26, NLon = 52);
Kq = Y' * ((w .* B.region.mask) .* Y);
Pg = (B.T' * Kq * B.T) \ (B.T' * Kq);
verifyLessThan(testCase, max(abs(Pg - B.T'), [], 'all'), ...
    100 * eps / min(B.lambda));
N = shLowLevel.regionalBasis(idx, cap, Type = "slepian", BufferKm = 0, NKeep = 3);
verifyEqual(testCase, N.K, 3);
end

function g = randomFieldNmax(nmax)
rng(11);
C = tril(randn(nmax + 1)) ./ ((0:nmax)' + 1).^2;
S = tril(randn(nmax + 1)) ./ ((0:nmax)' + 1).^2;
S(:, 1) = 0;
g = shCoefficients(C, S, GM = 3.986004415e14, R = 6.3781363e6);
end

function testReadBasinFindsAndWraps(testCase)
%TESTREADBASINFINDSANDWRAPS A basin is found by a unique part of its
%   name, its quadrature area is the oracle's (validate_regional_basis.py
%   CLAIM 5a: the same discrete rule gives 2.6414655704e-04 at nmax 60,
%   OverSample 2, 3.6% below the exact polygon area 2.739222e-04), and
%   a basin crossing lon 0 is inside on both sides of it (CLAIM 5b).
[reg, info] = shLowLevel.readBasin("Elbe");
verifyEqual(testCase, info.name, "Elbe River");
verifyEqual(testCase, numel(info.names), 100);
idx = shLowLevel.shIndex(60);
m = shLowLevel.evalMask(idx, reg);
[~, w] = shLowLevel.synthesisMatrix(idx, NLat = 122, NLon = 244, GridOnly = true);
verifyEqual(testCase, w' * m, 2.6414655704e-04, 'RelTol', 1e-9);
verifyEqual(testCase, reg(51, 12), 1);                 % Saale catchment
verifyEqual(testCase, reg(51, 12 + 360), 1);           % any longitude range
verifyEqual(testCase, reg(40, 12), 0);
[loire, li] = shLowLevel.readBasin("loire");           % case-insensitive
verifyEqual(testCase, li.name, "Loire");
verifyEqual(testCase, loire([47.3 47.3 47.3], [359 1 180]), [1 1 0]);
verifyFalse(testCase, any(li.polar));
end

function testReadBasinPolarRingsHolesAndParts(testCase)
%TESTREADBASINPOLARRINGSHOLESANDPARTS GeoJSON shapes the shipped rivbas
%   file does not have: a ring winding around the south pole (closed
%   through it, CLAIM 5c), a polygon with a hole, and a MultiPolygon.
f = [tempname '.json'];
cleanup = onCleanup(@() delete(f)); %#ok<NASGU>
pole = sprintf('[%d,-70],', -180:10:170);
pole = ['[' pole '[180,-70]]'];
sq = @(x0, y0, d) sprintf('[[%g,%g],[%g,%g],[%g,%g],[%g,%g],[%g,%g]]', ...
    x0, y0, x0 + d, y0, x0 + d, y0 + d, x0, y0 + d, x0, y0);
txt = ['{"type":"FeatureCollection","features":[' ...
    '{"type":"Feature","properties":{"name":"Holed"},"geometry":' ...
    '{"type":"Polygon","coordinates":[' sq(10, 40, 10) ',' sq(14, 44, 2) ']}},' ...
    '{"type":"Feature","properties":{"name":"Parts"},"geometry":' ...
    '{"type":"MultiPolygon","coordinates":[[' pole '],[' sq(-30, 10, 5) ']]}}]}'];
fid = fopen(f, 'w'); fprintf(fid, '%s', txt); fclose(fid);
[h, ih] = shLowLevel.readBasin("Holed", File = f);
verifyEqual(testCase, ih.hole, [false true]);
verifyEqual(testCase, h([42 45 45], [12 15 25]), [1 0 0]);
[p, ip] = shLowLevel.readBasin("Parts", File = f);
verifyEqual(testCase, ip.polar, [true false]);
verifyEqual(testCase, ip.polygon, [1 2]);
verifyEqual(testCase, p([-89 -75 -60 12], [123 359 10 332]), [1 1 0 1]);
idx = shLowLevel.shIndex(60);
south = @(la, lo) double(la < 0) .* p(la, lo);
[~, w, grid] = shLowLevel.synthesisMatrix(idx, NLat = 122, NLon = 244, ...
    GridOnly = true);
% the ring at -70 deg closed through the pole IS the cap lat < -70: the
% same grid points, so the same quadrature sum (0.0285811544764553 in
% validate_regional_basis.py CLAIM 5d). Points on the ring count as inside,
% which keeps the lon-0 column the ring starts and ends on; matplotlib's
% edge rule drops it, which is why the oracle's own handle reads 1/244 less.
cap = repelem(grid.latDeg(:), numel(grid.lonDeg)) < -70;
verifyEqual(testCase, w' * shLowLevel.evalMask(idx, south), w' * cap, ...
    'RelTol', 1e-12);
end

% ------------------------------------------- WP8 8b: the process model
function ts = processSeries(nmax, T, seed)
%PROCESSSERIES Monthly series with a 1/(n+1)^2 spectrum for the 8b tests.
rng(seed);
n1 = nmax + 1;
dec = 1 ./ ((0:nmax)' + 1) .^ 2;
Cs = zeros(n1, n1, T);
Ss = Cs;
for k = 1:T
    Cs(:, :, k) = tril(randn(n1) .* dec) * 1e-9;
    s = tril(randn(n1) .* dec) * 1e-9;
    s(:, 1) = 0;
    Ss(:, :, k) = s;
end
ts = shSeries(Cs, Ss = Ss, Epochs = 2003 + ((1:T)' - 0.5) / 12);
end

function testRegionalProcessModelOnTheSHBasisIsKalmanChains(testCase)
%TESTREGIONALPROCESSMODELONTHESHBASISISKALMANCHAINS On the SH basis the
%   regional process model IS the one kalmanChain builds from the same
%   model series - climatology residuals, vecFromCS, estimateVAR - bit for
%   bit. This is the oracle the regional chain stands on.
ts = processSeries(8, 60, 31);
idx = shLowLevel.shIndex(8);
B = shLowLevel.regionalBasis(idx, [], Type = "sh");
[model, info] = shLowLevel.regionalProcessModel(ts, B, Shrink = 1e-3);
[~, resid] = ts.climatology;
X = zeros(idx.P, resid.nEpochs);
for k = 1:resid.nEpochs
    g = resid.at(k);
    X(:, k) = shLowLevel.vecFromCS(g.C, g.S, idx);
end
ref = shLowLevel.estimateVAR(X, Order = 1, Shrink = 1e-3, CondFun = [], ...
    Structure = "full");
verifyTrue(testCase, isequaln(model, ref), ...
    'the SH-basis process model is not kalmanChain''s');
verifyTrue(testCase, isequal(info.A, X));
verifyEqual(testCase, info.representation, 1);
end

function testRegionalProcessModelRecoversAKnownVAR(testCase)
%TESTREGIONALPROCESSMODELRECOVERSAKNOWNVAR A VAR(1) simulated in the
%   coefficients of an RBF basis (nmax 12, a 30 deg polar cap plus 600
%   km), mapped to SH by T, given a mean and an annual cycle, comes back
%   through climatology removal, projection and Yule-Walker. The error is
%   a sampling error: validate_regional_process.py CLAIM 3 measured
%   sqrt(T) x error over 60 seeds at this configuration, medians 3.21 (B,
%   max abs) and 2.16 (Q, max abs relative to max|Q|); the bounds are 3x
%   those. The series lies in the span of T once the climatology is gone,
%   so the representation is 1 to rounding.
idx = shLowLevel.shIndex(12);
B = shLowLevel.regionalBasis(idx, @(la, lo) double(la > 60));
K = B.K;
nT = 20000;
rng(52);
Ph = 0.8 * eye(K) + 0.02 * randn(K);
Ph = Ph * (0.85 / max(abs(eig(Ph))));
Lq = randn(K) / sqrt(K);
Qtrue = Lq * Lq' + 0.1 * eye(K);
cQ = chol(Qtrue, 'lower');
a = zeros(K, nT);
for k = 2:nT
    a(:, k) = Ph * a(:, k - 1) + cQ * randn(K, 1);
end
t = 2000 + (0:nT - 1)' / 365.25;
X = full(B.T * a) + (randn(idx.P, 1) + randn(idx.P, 1) .* cos(2 * pi * t')) * 1e-3;
Cs = zeros(13, 13, nT);
Ss = Cs;
for k = 1:nT
    [Cs(:, :, k), Ss(:, :, k)] = shLowLevel.csFromVec(X(:, k), idx);
end
ts = shSeries(Cs, Ss = Ss, Epochs = t);
[model, info] = shLowLevel.regionalProcessModel(ts, B);
eB = max(abs(model.Phi{1} - Ph), [], 'all') * sqrt(nT);
eQ = max(abs(model.Q - Qtrue), [], 'all') / max(abs(Qtrue), [], 'all') * sqrt(nT);
verifyLessThan(testCase, eB, 3 * 3.21);
verifyLessThan(testCase, eQ, 3 * 2.16);
verifyGreaterThan(testCase, info.representation, 1 - 1e-10);
verifySize(testCase, info.A, [K, nT]);
verifyGreaterThan(testCase, info.minEigQ, 0);
end

function testRegionalProcessModelAdjustments(testCase)
%TESTREGIONALPROCESSMODELADJUSTMENTS Kurtenbach's alpha scales Q and
%   nothing else (his eq. 4.8): Phi and Sigma0 are bitwise unchanged and Q
%   is exactly alpha Q. The ground noise is a white EWH field of pointwise
%   variance sigma^2 everywhere (validate_regional_process.py CLAIM 2:
%   1.3e-14, bound 3x), and because it enters Sigma(0) it changes Phi too.
ts = processSeries(8, 60, 32);
idx = shLowLevel.shIndex(8);
B = shLowLevel.regionalBasis(idx, [], Type = "sh");
m1 = shLowLevel.regionalProcessModel(ts, B, Shrink = 1e-3);
m10 = shLowLevel.regionalProcessModel(ts, B, Shrink = 1e-3, QScale = 10);
verifyTrue(testCase, isequal(m10.Phi, m1.Phi) && isequal(m10.Sigma0, m1.Sigma0));
verifyTrue(testCase, isequal(m10.Q, 10 * m1.Q));
n = (0:8)';
kn = -0.30 * n ./ (n + 3.0);                       % synthetic Love numbers
[mg, ig] = shLowLevel.regionalProcessModel(ts, B, Shrink = 1e-3, ...
    GroundNoise = 0.02, kn = kn);
f = shLowLevel.kernelFactors("ewh", 8, ts.GM, ts.R, kn = kn);
lat = linspace(-89, 89, 40)';
lon = mod(97 * (1:40)', 360);
Ye = shLowLevel.ylm(deg2rad(lat), deg2rad(lon), idx) .* f(idx.n + 1)';
pv = sum((Ye * ig.groundCov) .* Ye, 2);
verifyLessThan(testCase, max(abs(pv / 0.02^2 - 1)), 3 * 1.27e-14);
verifyGreaterThan(testCase, max(abs(mg.Phi{1} - m1.Phi{1}), [], 'all'), 0);
verifyEqual(testCase, ig.groundNoise, 0.02);
end

function testEstimateVARSigma0AddGeneralisesShrink(testCase)
%TESTESTIMATEVARSIGMA0ADDGENERALISESSHRINK Shrink is Sigma0Add with
%   s trace(Sigma(0))/P I, bit for bit, and a vector Sigma0Add is its
%   diagonal matrix.
rng(9);
X = randn(6, 400);
X = filter(1, [1 -0.6], X, [], 2);
s = 0.05;
S0 = (X * X.') / size(X, 2);
m1 = shLowLevel.estimateVAR(X, Shrink = s);
m2 = shLowLevel.estimateVAR(X, Sigma0Add = s * trace(S0) / 6 * eye(6));
verifyTrue(testCase, isequal(m1, m2));
d = (1:6)' * 0.01;
m3 = shLowLevel.estimateVAR(X, Sigma0Add = d);
m4 = shLowLevel.estimateVAR(X, Sigma0Add = diag(d));
verifyTrue(testCase, isequal(m3, m4));
verifyFalse(testCase, isequal(m3.Phi, shLowLevel.estimateVAR(X).Phi));
end

% ------------------------------------------- WP8 8c: the observations
function testRegionalNEQOnTheSHBasisIsTheSHNEQ(testCase)
%TESTREGIONALNEQONTHESHBASISISTHESHNEQ On the SH basis (T = I) an SH
%   normal equation passes through unchanged, bit for bit, with its ltpl
%   and nobs; a readSINEX-shaped NEQ (M, x, stats) gives the same equation
%   up to forming b = M x; and a solution with a diagonal covariance is
%   N = diag(1/c), b = l./c to a few eps (one sqrt and one square apart).
idx = shLowLevel.shIndex(8);
B = shLowLevel.regionalBasis(idx, [], Type = "sh");
rng(21);
Mh = randn(idx.P + 10, idx.P);
Nsh = Mh' * Mh + eye(idx.P);
Nsh = (Nsh + Nsh') / 2;
bsh = randn(idx.P, 1);
rec = shLowLevel.regionalNEQ(B, "neq", NEQ = struct('N', Nsh, 'b', bsh, ...
    'ltpl', 3, 'nobs', 100));
verifyTrue(testCase, isequal(rec.N, Nsh) && isequal(rec.b, bsh));
verifyEqual(testCase, [rec.ltpl, rec.nobs], [3, 100]);
verifyEqual(testCase, rec.name, "neq");
snx = struct('M', Nsh, 'x', Nsh \ bsh, 'stats', struct('wsos', 3, 'nobs', 100));
r2 = shLowLevel.regionalNEQ(B, "neq", NEQ = snx);
verifyTrue(testCase, isequal(r2.N, Nsh));
verifyEqual(testCase, r2.b, bsh, 'RelTol', 1e-9);
verifyEqual(testCase, [r2.ltpl, r2.nobs], [3, 100]);
l = randn(idx.P, 1);
c = rand(idx.P, 1) + 0.5;
r3 = shLowLevel.regionalNEQ(B, "solution", Solution = l, Cov = c);
verifyEqual(testCase, r3.N, diag(1 ./ c), 'RelTol', 4 * eps);
verifyEqual(testCase, r3.b, l ./ c, 'RelTol', 4 * eps);
verifyEqual(testCase, r3.nobs, idx.P);
end

function testRegionalNEQRecoversAStateInTheSpan(testCase)
%TESTREGIONALNEQRECOVERSASTATEINTHESPAN Noise-free data of a state in the
%   span of an RBF basis come back from N a = b, for an SH solution and
%   for gravity disturbances at 450 km. The bound is the solve's rounding,
%   100 eps cond(N) (validate_regional_observations.py CLAIM 1: 1.1e-12 at
%   cond 4e4).
idx = shLowLevel.shIndex(20);
B = shLowLevel.regionalBasis(idx, @(la, lo) double(la > 50));
rng(22);
a0 = randn(B.K, 1);
rec = shLowLevel.regionalNEQ(B, "solution", Solution = full(B.T * a0), ...
    Cov = 1e-20);
a = rec.N \ rec.b;
verifyLessThan(testCase, max(abs(a - a0)) / max(abs(a0)), 100 * eps * cond(rec.N));
lat = 35 + 55 * rand(600, 1);
lon = 360 * rand(600, 1);
[~, info] = shLowLevel.regionalNEQ(B, "points", Values = zeros(600, 1), ...
    LatDeg = lat, LonDeg = lon, Height = 450e3, Quantity = "gravity_disturbance", ...
    Cov = 1e-16);
y = info.A * a0;
rec = shLowLevel.regionalNEQ(B, "points", Values = y, LatDeg = lat, ...
    LonDeg = lon, Height = 450e3, Quantity = "gravity_disturbance", Cov = 1e-16);
a = rec.N \ rec.b;
verifyLessThan(testCase, max(abs(a - a0)) / max(abs(a0)), 100 * eps * cond(rec.N));
verifyEqual(testCase, rec.nobs, 600);
end

function testRegionalNEQPointDesignIsSynthesisPoints(testCase)
%TESTREGIONALNEQPOINTDESIGNISSYNTHESISPOINTS The point design applied to
%   a state equals synthesisPoints of the SH coefficients T a, for the
%   potential and the gravity disturbance at 0-500 km - two summations of
%   one series; synthesisPoints documents its two paths agreeing to 5e-14,
%   and the bound 1e-12 (relative to the largest value) leaves 20x.
idx = shLowLevel.shIndex(20);
B = shLowLevel.regionalBasis(idx, @(la, lo) double(la > 50));
rng(23);
a0 = randn(B.K, 1);
[C, S] = shLowLevel.csFromVec(full(B.T * a0), idx);
GM = 3.986004415e14; R = 6378136.3;
lat = 40 + 49 * rand(50, 1);
lon = 360 * rand(50, 1);
h = 500e3 * rand(50, 1);
pairs = ["potential", "potential"; "gravity_disturbance", "disturbance"];
for k = 1:2
    [~, info] = shLowLevel.regionalNEQ(B, "points", Values = zeros(50, 1), ...
        LatDeg = lat, LonDeg = lon, Height = h, Quantity = pairs(k, 1), Cov = 1);
    ref = shLowLevel.synthesisPoints(C, S, GM, R, lat, lon, R + h, ...
        Quantity = pairs(k, 2));
    verifyLessThan(testCase, max(abs(info.A * a0 - ref)) / max(abs(ref)), 1e-12, ...
        pairs(k, 1));
end
end

function testRegionalNEQDirectionalDesignIsTheGradient(testCase)
%TESTREGIONALNEQDIRECTIONALDESIGNISTHEGRADIENT With Direction the design
%   is the gradient of the quantity along it: the local north, east and up
%   unit vectors (in ECEF) reproduce shSynthesisGradient's three components
%   at 450 km, for the potential (the gravity vector). Same series, same
%   legendreALFDeriv, another summation: 1e-12 relative to the largest
%   component. validate_regional_observations.py CLAIM 3 checks the same
%   design against the analytic ECEF gradient of an RBF (4e-10, the
%   oracle's finite-difference floor).
idx = shLowLevel.shIndex(20);
B = shLowLevel.regionalBasis(idx, @(la, lo) double(la > 50));
rng(24);
a0 = randn(B.K, 1);
[C, S] = shLowLevel.csFromVec(full(B.T * a0), idx);
GM = 3.986004415e14; R = 6378136.3;
lat = 40 + 49 * rand(30, 1);
lon = 360 * rand(30, 1);
dq = shLowLevel.shSynthesisGradient(C, S, GM, R, lat', lon', Quantity = "potential", ...
    Mode = "points", Height = 450e3, Nmin = 2);
sp = sind(lat); cp = cosd(lat); sl = sind(lon); cl = cosd(lon);
dirs = {[-sp .* cl, -sp .* sl, cp], [-sl, cl, zeros(30, 1)], [cp .* cl, cp .* sl, sp]};
refs = {dq.north, dq.east, dq.up};
for k = 1:3
    [~, info] = shLowLevel.regionalNEQ(B, "points", Values = zeros(30, 1), ...
        LatDeg = lat, LonDeg = lon, Height = 450e3, Quantity = "potential", ...
        Direction = dirs{k}, Cov = 1);
    verifyLessThan(testCase, max(abs(info.A * a0 - refs{k}(:))) / ...
        max(abs(refs{k}(:))), 1e-12, sprintf('component %d', k));
end
end

function testRegionalNEQCorrelatedCovarianceAndCombinations(testCase)
%TESTREGIONALNEQCORRELATEDCOVARIANCEANDCOMBINATIONS A full covariance
%   enters through its Cholesky factor and equals the explicit A'(C\A),
%   A'(C\y) to the rounding cond(C) amplifies (100 eps cond(C); oracle
%   CLAIM 4: 5e-16). ltpl is what variance-component estimation needs:
%   ltpl - 2x'b + x'Nx = v'C^-1 v at any x (CLAIM 5). And Combine forms
%   the rows of its combinations - [1 -1] pairs, the LGD shape - exactly.
idx = shLowLevel.shIndex(16);
B = shLowLevel.regionalBasis(idx, @(la, lo) double(la > 50));
rng(25);
M = 40;
lat = 40 + 49 * rand(M, 1);
lon = 360 * rand(M, 1);
Lc = randn(M) / sqrt(M);
Cv = (Lc * Lc' + 0.5 * eye(M)) * 1e-16;
y = randn(M, 1) * 1e-8;
args = {"LatDeg", lat, "LonDeg", lon, "Height", 450e3, "Quantity", ...
    "gravity_disturbance"};
[rec, info] = shLowLevel.regionalNEQ(B, "points", args{:}, Values = y, Cov = Cv);
A = info.A;
N2 = A' * (Cv \ A);
b2 = A' * (Cv \ y);
bound = 100 * eps * cond(Cv);
verifyLessThan(testCase, max(abs(rec.N - N2), [], 'all') / max(abs(N2), [], 'all'), bound);
verifyLessThan(testCase, max(abs(rec.b - b2)) / max(abs(b2)), bound);
x = randn(B.K, 1) * 1e-3;
v = y - A * x;
q = v' * (Cv \ v);
verifyLessThan(testCase, abs(rec.ltpl - 2 * x' * rec.b + x' * rec.N * x - q) / q, bound);
Cmb = kron(eye(M / 2), [1 -1]);
[r2, i2] = shLowLevel.regionalNEQ(B, "points", args{:}, Values = Cmb * y, ...
    Cov = 2e-16, Combine = Cmb);
verifyTrue(testCase, isequal(i2.A, Cmb * A));
verifyEqual(testCase, r2.nobs, M / 2);
end

% ------------------------------------------- WP8 8d: the chain
function [tsm, tsObs, ep, idx] = kalmanSHFixture(seed)
%KALMANSHFIXTURE The configuration of validate_regional_kalman.py CLAIM 1:
%   nmax 6 (P = 45), a VAR(1) with a 1/(n+1)^2 signal of about 1e-9 behind
%   a 240-epoch model series, and 30 monthly observations with sigmas of
%   1-2e-11 of which every fourth is missing.
rng(seed);
idx = shLowLevel.shIndex(6);
P = idx.P;
dec = 1 ./ (idx.n + 1) .^ 2;
Ph = 0.7 * eye(P) + 0.02 * randn(P);
Ph = Ph * (0.8 / max(abs(eig(Ph))));
Lq = randn(P) / sqrt(P);
cQ = chol((Lq * Lq' + 0.2 * eye(P)) .* (dec * dec') * 1e-18, 'lower');
X = zeros(P, 270);
for k = 2:270
    X(:, k) = Ph * X(:, k - 1) + cQ * randn(P, 1);
end
sig = 1e-11 * (1 + rand(P, 1));
tsm = vecSeries(X(:, 1:240), 1990 + ((1:240)' - 0.5) / 12, idx, []);
ep = 2003 + ((1:30)' - 0.5) / 12;
keep = mod(0:29, 4) ~= 3;
Lobs = X(:, 241:270) + sig .* randn(P, 30);
tsObs = vecSeries(Lobs(:, keep), ep(keep), idx, sig);
end

function ts = vecSeries(X, ep, idx, sig)
%VECSERIES An shSeries from coefficient vectors in IDX order, with a
%   constant formal sigma vector SIG when it is not empty.
n1 = idx.Lmax + 1;
nT = size(X, 2);
[Cs, Ss, sC, sS] = deal(zeros(n1, n1, nT));
for t = 1:nT
    [Cs(:, :, t), Ss(:, :, t)] = shLowLevel.csFromVec(X(:, t), idx);
    if ~isempty(sig)
        [sC(:, :, t), sS(:, :, t)] = shLowLevel.csFromVec(sig, idx);
    end
end
if isempty(sig)
    ts = shSeries(Cs, Ss = Ss, Epochs = ep);
else
    ts = shSeries(Cs, Ss = Ss, Epochs = ep, SigmaCs = sC, SigmaSs = sS);
end
end

function [x, s] = seriesVectors(ts, idx)
%SERIESVECTORS Coefficient and sigma vectors of every epoch, IDX order.
x = zeros(idx.P, ts.nEpochs);
s = x;
for t = 1:ts.nEpochs
    g = ts.at(t);
    x(:, t) = shLowLevel.vecFromCS(g.C, g.S, idx);
    s(:, t) = shLowLevel.vecFromCS(g.sigmaC, g.sigmaS, idx);
end
end

function testRegionalKalmanOnTheSHBasisIsKalmanChain(testCase)
%TESTREGIONALKALMANONTHESHBASISISKALMANCHAIN On the SH basis the regional
%   chain is kalmanChain in solution mode: the same process model bit for
%   bit, the same gaps, and the same smoothed series - the chain updates
%   in the filter's information form, kalmanChain in its gain form, which
%   agree to 5.58e-15 relative in the states and 8.88e-16 in the sigmas
%   over 40 seeds of this configuration (validate_regional_kalman.py
%   CLAIM 1); the bounds are 3x those. With the climatology removed and
%   restored, the restore through Proj = I is kalmanChain's own.
[tsm, tsObs, ep, idx] = kalmanSHFixture(61);
B = shLowLevel.regionalBasis(idx, [], Type = "sh");
for clim = [false true]
    [tsR, outR] = shLowLevel.regionalKalman(tsObs, B, ModelSeries = tsm, ...
        Epochs = ep, Climatology = clim);
    [tsC, repC] = shLowLevel.kalmanChain(tsObs, ModelSeries = tsm, ...
        Epochs = ep, Climatology = clim);
    verifyTrue(testCase, isequaln(outR.model, repC.model), ...
        'the process model is not kalmanChain''s');
    verifyEqual(testCase, outR.gap, repC.gap);
    [xR, sR] = seriesVectors(tsR, idx);
    [xC, sC] = seriesVectors(tsC, idx);
    verifyLessThan(testCase, max(abs(xR - xC), [], 'all') / max(abs(xC), [], 'all'), ...
        3 * 5.58e-15);
    verifyLessThan(testCase, max(abs(sR ./ sC - 1), [], 'all'), 3 * 8.88e-16);
    verifyEqual(testCase, tsR.epochs, ep);
end
verifyEqual(testCase, outR.nGaps, 7);
verifyEqual(testCase, outR.mode, "solution");
verifyEmpty(testCase, outR.basin);
verifyEmpty(testCase, outR.grid);
end

function testRegionalKalmanIsTheJointAdjustment(testCase)
%TESTREGIONALKALMANISTHEJOINTADJUSTMENT On an RBF basis the chain is the
%   joint least-squares adjustment over all epochs (Kvas 2019, Sec. 2.3):
%   the prior on a_1, the process steps a_t - Phi a_(t-1) ~ N(0, Q) and
%   the per-epoch basis normal equations, solved densely here. Records
%   mode, 12 epochs with 3 gaps. validate_regional_kalman.py CLAIM 2
%   measured this configuration over 20 seeds: states 2.57e-15, sigmas
%   1.67e-15, covariances 2.53e-15 (relative); the bounds are 3x those.
idx = shLowLevel.shIndex(10);
B = shLowLevel.regionalBasis(idx, @(la, lo) double(la > 55));
K = B.K;
rng(62);
Ph = 0.75 * eye(K) + 0.02 * randn(K);
Ph = Ph * (0.8 / max(abs(eig(Ph))));
Lq = randn(K) / sqrt(K);
cQ = chol(Lq * Lq' + 0.1 * eye(K), 'lower');
a = zeros(K, 612);
for k = 2:612
    a(:, k) = Ph * a(:, k - 1) + cQ * randn(K, 1);
end
tsm = vecSeries(full(B.T * a(:, 1:600)), 2000 + ((1:600)' - 0.5) / 12, idx, []);
ep = 2051 + ((1:12)' - 0.5) / 12;
recs = struct('N', {}, 'b', {}, 'epoch', {});
gaps = [4 8 9];
for t = setdiff(1:12, gaps)
    A = randn(3 * K, K);
    c = 0.5 + 1.5 * rand(3 * K, 1);
    y = A * a(:, 600 + t) + sqrt(c) .* randn(3 * K, 1);
    Aw = A ./ sqrt(c);
    recs(end + 1) = struct('N', Aw' * Aw, 'b', Aw' * (y ./ sqrt(c)), ...
        'epoch', ep(t)); %#ok<AGROW>
end
[~, out] = shLowLevel.regionalKalman(recs, B, ModelSeries = tsm, Epochs = ep);
Phi = out.model.Phi{1};
Q = out.model.Q;
Pm1 = Phi * out.model.Sigma0 * Phi' + Q;
Pm1 = (Pm1 + Pm1') / 2;
Qi = inv(Q);
M = zeros(12 * K);
r = zeros(12 * K, 1);
blk = @(t) (t - 1) * K + (1:K);
M(blk(1), blk(1)) = inv(Pm1);
for t = 2:12
    M(blk(t), blk(t)) = M(blk(t), blk(t)) + Qi;
    M(blk(t - 1), blk(t - 1)) = M(blk(t - 1), blk(t - 1)) + Phi' * Qi * Phi;
    M(blk(t), blk(t - 1)) = M(blk(t), blk(t - 1)) - Qi * Phi;
    M(blk(t - 1), blk(t)) = M(blk(t - 1), blk(t)) - Phi' * Qi;
end
j = 0;
for t = setdiff(1:12, gaps)
    j = j + 1;
    M(blk(t), blk(t)) = M(blk(t), blk(t)) + recs(j).N;
    r(blk(t)) = recs(j).b;
end
Ci = inv(M);
xj = reshape(Ci * r, K, 12);
sj = reshape(sqrt(diag(Ci)), K, 12);
verifyEqual(testCase, out.gap, ismember(1:12, gaps));
verifyEqual(testCase, out.mode, "records");
verifyLessThan(testCase, max(abs(out.a - xj), [], 'all') / max(abs(xj), [], 'all'), ...
    3 * 2.57e-15);
verifyLessThan(testCase, max(abs(out.sigA ./ sj - 1), [], 'all'), 3 * 1.67e-15);
CL = Ci(blk(12), blk(12));
verifyLessThan(testCase, max(abs(out.covLast - CL), [], 'all') / max(abs(CL), [], 'all'), ...
    3 * 2.53e-15);
end

function testRegionalKalmanCarriesSigmasThroughT(testCase)
%TESTREGIONALKALMANCARRIESSIGMASTHROUGHT The region's outputs are linear
%   functionals of the smoothed basis coefficients, checked against
%   synthesisPoints as an independent summation: the EWH at the region's
%   points is the synthesis of the output series there (EWH as the
%   potential of coefficients scaled by f_n R / GM, at r = R); the basin
%   mean is their area-weighted mean over B.region.core; and the basin
%   and grid sigmas at the last epoch are sqrt(f Ps f') with f built from
%   the synthesis of each basis function and Ps the full smoothed
%   covariance. Two summations of one series: synthesisPoints documents
%   its paths agreeing to 5e-14, and the bound 1e-12 leaves 20x.
idx = shLowLevel.shIndex(10);
B = shLowLevel.regionalBasis(idx, @(la, lo) double(la > 55));
K = B.K;
rng(63);
Ph = 0.75 * eye(K) + 0.02 * randn(K);
Ph = Ph * (0.8 / max(abs(eig(Ph))));
Lq = randn(K) / sqrt(K);
cQ = chol(Lq * Lq' + 0.1 * eye(K), 'lower') * 1e-10;
a = zeros(K, 624);
for k = 2:624
    a(:, k) = Ph * a(:, k - 1) + cQ * randn(K, 1);
end
tsm = vecSeries(full(B.T * a(:, 1:600)), 2000 + ((1:600)' - 0.5) / 12, idx, []);
ep = 2051 + ((1:24)' - 0.5) / 12;
seasonal = randn(idx.P, 1) * 3e-11 * cos(2 * pi * ep');
sig = 2e-11 * ones(idx.P, 1);
X = full(B.T * a(:, 601:624)) + seasonal + sig .* randn(idx.P, 24);
tsObs = vecSeries(X, ep, idx, sig);
n = (0:10)';
kn = -0.30 * n ./ (n + 3.0);                       % synthetic Love numbers
[tsK, out] = shLowLevel.regionalKalman(tsObs, B, ModelSeries = tsm, kn = kn);
GM = tsK.GM;
R = tsK.R;
f = shLowLevel.kernelFactors("ewh", 10, GM, R, kn = kn);
sc = f * R / GM;                                   % EWH as a scaled potential
lat = out.grid.latDeg;
lon = out.grid.lonDeg;
[~, w] = shLowLevel.synthesisMatrix(idx, NLat = 22, NLon = 44, GridOnly = true);
core = B.region.core;
im = find(core > 0);
wc = w(im) .* core(im);
verifyEqual(testCase, out.basin.areaFraction, B.region.areaFraction);
for t = [1 24]
    g = tsK.at(t);
    ref = shLowLevel.synthesisPoints(g.C .* sc, g.S .* sc, GM, R, lat, lon, ...
        R * ones(size(lat)));
    verifyLessThan(testCase, max(abs(out.grid.ewh(:, t) - ref)) / max(abs(ref)), 1e-12);
    verifyLessThan(testCase, abs(out.basin.mean(t) - wc' * ref / sum(wc)) / ...
        max(abs(ref)), 1e-12);
end
G = zeros(numel(lat), K);
for k = 1:K
    [Ck, Sk] = shLowLevel.csFromVec(full(B.T(:, k)), idx);
    G(:, k) = shLowLevel.synthesisPoints(Ck .* sc, Sk .* sc, GM, R, lat, lon, ...
        R * ones(size(lat)));
end
fb = wc' * G / sum(wc);
verifyLessThan(testCase, abs(out.basin.sigma(end) / sqrt(fb * out.covLast * fb') - 1), 1e-12);
sg = sqrt(sum((G * out.covLast) .* G, 2));
verifyLessThan(testCase, max(abs(out.grid.sigma(:, end) ./ sg - 1)), 1e-12);
verifySize(testCase, out.grid.ewh, [numel(lat), 24]);
verifyTrue(testCase, all(out.basin.sigma > 0));
end

function testRtsSmootherFunctionals(testCase)
%TESTRTSSMOOTHERFUNCTIONALS rtsSmoother's Functionals: for F = I (full or
%   sparse) the functional sigmas ARE the coefficient sigmas, bit for bit,
%   in the full pass and in the fixed-lag pass; for a general F they are
%   sqrt(diag(F Ps F')) - at the last epoch against the explicit product,
%   to 3x the worst relative difference validate_regional_kalman.py CLAIM 4
%   measured over 201 cases of this shape, read the same way - the sigma
%   squared back against diag(F Ps F') (4.40e-16).
rng(64);
P = 6;
model = localStableModel(P);
obs = repmat(struct('l', [], 'R', [], 'N', [], 'b', []), 1, 8);
for t = [1 2 4 5 7 8]
    obs(t).l = randn(P, 1);
    obs(t).R = 0.3 * eye(P);
end
filt = shLowLevel.kalmanFilter(model, obs);
s1 = shLowLevel.rtsSmoother(filt, Functionals = eye(P));
s2 = shLowLevel.rtsSmoother(filt, Functionals = speye(P));
verifyTrue(testCase, isequal(s1.sigF, s1.sig) && isequal(s2.sigF, s1.sig));
s3 = shLowLevel.rtsSmoother(filt, Lag = 2, Functionals = eye(P));
verifyTrue(testCase, isequal(s3.sigF, s3.sig));
F = randn(8, P);
s4 = shLowLevel.rtsSmoother(filt, Functionals = F);
verifyTrue(testCase, isequal(s4.xs, s1.xs) && isequal(s4.sig, s1.sig));
dx = diag(F * s4.PsLast * F');
verifyLessThan(testCase, max(abs(s4.sigF(:, end).^2 - dx)) / max(dx), 3 * 4.40e-16);
verifyEmpty(testCase, shLowLevel.rtsSmoother(filt).sigF);
end

% ------------------------------------------- WP8 8e: remove-compute-restore
function [tsm, Xobs, Z, ep, idx, B, sig] = rcrFixture(seed)
%RCRFIXTURE The configuration of validate_regional_rcr.py CLAIM 1b: nmax
%   10, an RBF basis for the cap north of 55 N, a 600-epoch model series in
%   the span of T, 24 monthly observations with sigmas of 2e-11, and a
%   random field Z of 1e-10 per coefficient outside the basis' span.
idx = shLowLevel.shIndex(10);
B = shLowLevel.regionalBasis(idx, @(la, lo) double(la > 55));
K = B.K;
rng(seed);
a = zeros(K, 624);
for k = 2:624
    a(:, k) = 0.8 * a(:, k - 1) + randn(K, 1);
end
tsm = vecSeries(full(B.T * a(:, 1:600)) * 1e-10, ...
    2000 + ((1:600)' - 0.5) / 12, idx, []);
ep = 2051 + ((1:24)' - 0.5) / 12;
sig = 2e-11 * ones(idx.P, 1);
Xobs = full(B.T * a(:, 601:624)) * 1e-10 + sig .* randn(idx.P, 24);
Z = randn(idx.P, 24) * 1e-10;
end

function testRegionalKalmanBackgroundIsLinear(testCase)
%TESTREGIONALKALMANBACKGROUNDISLINEAR With the process model fixed the
%   chain is linear in its data, so a background holding a fraction c of
%   a field Z leaves exactly 1 - c of Z's leakage:
%     x(obs + Z; c Z) = c Z + x(obs) + (1 - c) (x(obs + Z) - x(obs)),
%   for the series and the basin mean alike - the restore algebra,
%   climatology removal and restore included. validate_regional_rcr.py
%   CLAIM 1b measured the identity at this configuration over 20 seeds,
%   5.57e-15 relative to the largest value; the bound is 3x that.
[tsm, Xobs, Z, ep, idx, B, sig] = rcrFixture(66);
kn = -0.30 * (0:10)' ./ ((0:10)' + 3.0);          % synthetic Love numbers
go = @(X, bg) shLowLevel.regionalKalman(vecSeries(X, ep, idx, sig), B, ...
    ModelSeries = tsm, kn = kn, Background = bg);
[tIn, oIn] = go(Xobs, []);
[tFull, oFull] = go(Xobs + Z, []);
[~, oOne] = go(Xobs + Z, vecSeries(Z, ep, idx, []));
bz = oOne.basin.mean - oIn.basin.mean;            % Z's own basin mean
xIn = seriesVectors(tIn, idx);
xFull = seriesVectors(tFull, idx);
for c = [0.8 0.5]
    [tc, oc] = go(Xobs + Z, vecSeries(c * Z, ep, idx, []));
    xc = seriesVectors(tc, idx);
    ref = c * Z + xIn + (1 - c) * (xFull - xIn);
    verifyLessThan(testCase, max(abs(xc - ref), [], 'all') / max(abs(xc), [], 'all'), ...
        3 * 5.57e-15);
    bref = c * bz + oIn.basin.mean + (1 - c) * (oFull.basin.mean - oIn.basin.mean);
    verifyLessThan(testCase, max(abs(oc.basin.mean - bref)) / max(abs(oc.basin.mean)), ...
        3 * 5.57e-15);
    verifyTrue(testCase, oc.background && ~oIn.background);
    verifyTrue(testCase, isequal(oc.basin.sigma, oIn.basin.sigma), ...
        'the background is error-free and must not change the sigmas');
end
end

function testRegionalKalmanBackgroundRemovesAndRestores(testCase)
%TESTREGIONALKALMANBACKGROUNDREMOVESANDRESTORES The background is
%   removed from the observations as the series difference obs - b and
%   restored as the sum: the result is bit for bit the chain on obs - b
%   plus b, with the same basis coefficients and the same sigmas. The EWH
%   outputs add the background's EWH at the region's points, checked
%   against synthesisPoints of the background (EWH as the potential of
%   coefficients scaled by f_n R / GM at r = R; two summations of one
%   series, synthesisPoints' paths agree to 5e-14, the bound 1e-12 leaves
%   20x).
[tsm, Xobs, Z, ep, idx, B, sig] = rcrFixture(67);
kn = -0.30 * (0:10)' ./ ((0:10)' + 3.0);          % synthetic Love numbers
obs = vecSeries(Xobs, ep, idx, sig);
bg = vecSeries(Z, ep, idx, []);
[t1, o1] = shLowLevel.regionalKalman(obs, B, ModelSeries = tsm, kn = kn, Background = bg);
[t0, o0] = shLowLevel.regionalKalman(obs - bg, B, ModelSeries = tsm, kn = kn);
verifyTrue(testCase, isequal(t1.Cs, t0.Cs + bg.Cs) && isequal(t1.Ss, t0.Ss + bg.Ss));
verifyTrue(testCase, isequal(o1.a, o0.a) && isequal(o1.sigA, o0.sigA));
verifyTrue(testCase, isequal(t1.sigmaCs, t0.sigmaCs));
GM = t1.GM;
R = t1.R;
f = shLowLevel.kernelFactors("ewh", 10, GM, R, kn = kn);
sc = f * R / GM;
lat = o1.grid.latDeg;
lon = o1.grid.lonDeg;
for t = [1 24]
    g = bg.at(t);
    e = shLowLevel.synthesisPoints(g.C .* sc, g.S .* sc, GM, R, lat, lon, ...
        R * ones(size(lat)));
    d = o1.grid.ewh(:, t) - o0.grid.ewh(:, t);
    verifyLessThan(testCase, max(abs(d - e)) / max(abs(e)), 1e-12);
end
verifyTrue(testCase, contains(t1.history(end), "background removed and restored"));
end

% ------------------------------------------- WP8 8h: LGD observations
function [rA, rB] = lgdPairs(M, seed)
%LGDPAIRS M satellite pairs at random places and headings, 490 +- 20 km
%   high, B 220 km ahead of A, |lat| <= 85 deg (validate_regional_lgd.py's
%   pairs()).
rng(seed);
R = 6378136.3;
lat = deg2rad(-85 + 170 * rand(M, 1));
lon = -pi + 2 * pi * rand(M, 1);
r = R + 490e3 + 40e3 * (rand(M, 1) - 0.5);
u = [cos(lat) .* cos(lon), cos(lat) .* sin(lon), sin(lat)];
t = cross(u, randn(M, 3), 2);
t = t ./ vecnorm(t, 2, 2);
th = 220e3 ./ r;
rA = r .* u;
rB = r .* (cos(th) .* u + sin(th) .* t);
end

function lgdRef = lgdReferenceJ2Local(rA, rB, J2)
%LGDREFERENCEJ2LOCAL lgdToolbox realdata/lgdReferenceJ2.m, line for line:
%   e . (gB - gA) of a point mass plus J2 about the frame's z axis.
GM = 3.986004415e14; R = 6378136.3;
gA = j2Gravity(rA, GM, R, J2);
gB = j2Gravity(rB, GM, R, J2);
d = rB - rA;
e = d ./ sqrt(sum(d .^ 2, 2));
lgdRef = sum(e .* (gB - gA), 2);
end

function g = j2Gravity(r, GM, R, J2)
rr = sqrt(sum(r .^ 2, 2));
z2 = (r(:, 3) ./ rr) .^ 2;
f = 1.5 * J2 * (R ./ rr) .^ 2;
k = -GM ./ rr .^ 3;
g = k .* [r(:, 1) .* (1 - f .* (5 * z2 - 1)), r(:, 2) .* (1 - f .* (5 * z2 - 1)), ...
          r(:, 3) .* (1 - f .* (5 * z2 - 3))];
end

function testRegionalNEQLgdIsLgdToolboxsForwardModel(testCase)
%TESTREGIONALNEQLGDISLGDTOOLBOXSFORWARDMODEL Kind "lgd" against the two
%   forward models of lgdToolbox. On the SH basis of degrees 0..2 with
%   C00 = 1 and C20 = -J2/sqrt(5) the design reproduces lgdReferenceJ2
%   (point mass + J2, closed form) - the total and the J2 part on its own,
%   which is 5e-3 of it. Degree 0 alone reproduces five rows of the
%   50-digit Kepler pair of lgdToolbox's oracle O2
%   (tests/refdata/kepler_pair.json). Rounding scales with |g| at the
%   satellites, so the bounds are in units of |g|:
%   validate_regional_lgd.py measured 1.7e-15 (CLAIM 1) and 5.3e-16
%   (CLAIM 2) with a complex-step derivative; the bound 2e-14 is about 10x,
%   because MATLAB's derivative is legendreALFDeriv's, not the oracle's.
idx = shLowLevel.shIndex(2, Nmin = 0);
B = shLowLevel.regionalBasis(idx, [], Type = "sh");
J2 = 1.0826359e-3;
gsat = 3.986004415e14 / (6378136.3 + 490e3) ^ 2;
[rA, rB] = lgdPairs(200, 81);
[~, info] = shLowLevel.regionalNEQ(B, "lgd", Values = zeros(200, 1), ...
    PositionA = rA, PositionB = rB, Cov = 1);
x0 = zeros(idx.P, 1);
x0(idx.pos(1, 1, 1)) = 1;
x = x0;
x(idx.pos(3, 1, 1)) = -J2 / sqrt(5);
ref = lgdReferenceJ2Local(rA, rB, J2);
verifyLessThan(testCase, max(abs(info.A * x - ref)) / gsat, 2e-14, 'total');
refJ2 = ref - lgdReferenceJ2Local(rA, rB, 0);
verifyLessThan(testCase, max(abs(info.A * (x - x0) - refJ2)) / gsat, 2e-14, 'J2 part');
kA = [4512997.478287725, 2694451.3364104237, 4409297.116052281
      -5070483.813394559, -2853662.7653212734, 3660682.922583132
      -1462898.200822358, -978647.053148104, -6650454.147907468
      5932954.93395928, 3432291.694546043, 342269.3481886636
      -1455906.161136149, -706070.4417370488, 6673028.238021222];
kB = [4385663.580707991, 2623495.5872420436, 4576796.38841529
      -5168144.096511687, -2916462.981551038, 3471124.4759983197
      -1279284.0957959588, -871319.9938125537, -6703759.152552041
      5917750.75935825, 3429061.7307759067, 560361.235087979
      -1638482.2633512663, -815622.220504692, 6618209.754707613];
kLgd = [-0.2741007674070423; -0.2727220827822083; -0.26838615696227075
        -0.2696566435557386; -0.2706971398324607];
[~, ik] = shLowLevel.regionalNEQ(B, "lgd", Values = zeros(5, 1), ...
    PositionA = kA, PositionB = kB, Cov = 1);
verifyLessThan(testCase, max(abs(ik.A * x0 - kLgd)) / gsat, 2e-14, 'Kepler pair O2');
end

function testRegionalNEQLgdOperatorAndMask(testCase)
%TESTREGIONALNEQLGDOPERATORANDMASK Kind "lgd" is kind "points" with the
%   line of sight as Direction at both satellites and Combine = [-I, I].
%   Compared on the SH basis: there B.T is the sparse identity and every
%   step per point is elementwise, so both routes form the same two rows
%   and differ at most by the rounding of their one subtraction - bound
%   2 eps of the largest per-satellite entry. (On an RBF basis the dense
%   product with B.T rounds differently for M and 2M rows, and the LGD's
%   cancellation turns that into a few eps of the difference: 3.7 eps on
%   A8 at 5634698 - a property of GEMM, not of the design.) The operator
%   is applied once to
%   [Values, A]: a band-pass as a matrix and as a handle give identical
%   records, and noise-free data stay on the design, W y = (W A) a
%   (validate_regional_lgd.py CLAIM 4: 5.5e-16; bound 1e-13 relative).
%   Rows the operator leaves non-finite, and rows outside Valid, are
%   dropped with their rows and columns of Cov: the record equals the
%   explicit A'(C\A), A'(C\y) on the kept rows (bound 100 eps cond(C)).
idx = shLowLevel.shIndex(16);
B = shLowLevel.regionalBasis(idx, @(la, lo) double(la > 50));
R = 6378136.3;
M = 256;
r0 = R + 490e3;
th = linspace(0.6, 0.6 + 2 * pi * 0.9, M)';
lam = 0.3 - 0.0004 * (0:M - 1)';
uA = [cos(th) .* cos(lam), cos(th) .* sin(lam), sin(th)];
th2 = th + 220e3 / r0;
uB = [cos(th2) .* cos(lam), cos(th2) .* sin(lam), sin(th2)];
rA = r0 * uA; rB = r0 * uB;
rng(82);
a0 = randn(B.K, 1) * 1e-10;
[~, i0] = shLowLevel.regionalNEQ(B, "lgd", Values = zeros(M, 1), ...
    PositionA = rA, PositionB = rB, Cov = 1);
A = i0.A;
e = (rB - rA) ./ vecnorm(rB - rA, 2, 2);
X = [rA; rB];
rr = vecnorm(X, 2, 2);
Bsh = shLowLevel.regionalBasis(idx, [], Type = "sh");
[~, is] = shLowLevel.regionalNEQ(Bsh, "lgd", Values = zeros(M, 1), ...
    PositionA = rA, PositionB = rB, Cov = 1);
pts = {"LatDeg", asind(X(:, 3) ./ rr), "LonDeg", atan2d(X(:, 2), X(:, 1)), ...
    "Height", rr - R, "Quantity", "potential", "Direction", [e; e], "Cov", 1};
[~, ip] = shLowLevel.regionalNEQ(Bsh, "points", pts{:}, Values = zeros(M, 1), ...
    Combine = [-eye(M), eye(M)]);
[~, i2] = shLowLevel.regionalNEQ(Bsh, "points", pts{:}, Values = zeros(2 * M, 1));
verifyLessThan(testCase, max(abs(is.A - ip.A), [], 'all'), ...
    2 * eps * max(abs(i2.A), [], 'all'));
y = A * a0;
f = min(0:M - 1, M - (0:M - 1))' / (M * 5);
w = double(f > 1e-3 & f < 2e-2);
W = real(ifft(w .* fft(eye(M))));
[rm, im] = shLowLevel.regionalNEQ(B, "lgd", Values = y, PositionA = rA, ...
    PositionB = rB, Cov = 1e-20, Operator = W);
[rh, ih] = shLowLevel.regionalNEQ(B, "lgd", Values = y, PositionA = rA, ...
    PositionB = rB, Cov = 1e-20, Operator = @(Z) W * Z);
verifyTrue(testCase, isequaln(rm, rh) && isequaln(im, ih), 'matrix and handle differ');
verifyLessThan(testCase, max(abs(im.y - im.A * a0)) / max(abs(im.y)), 1e-13);
verifyLessThan(testCase, max(abs(im.y - W * y)) / max(abs(im.y)), 1e-13);
op = @(Z) [NaN(10, size(Z, 2)); W(11:end, :) * Z];
valid = true(M, 1);
valid(end - 19:end) = false;
Lc = randn(M) / sqrt(M);
Cv = (Lc * Lc' + 0.5 * eye(M)) * 1e-20;
[rk, ik] = shLowLevel.regionalNEQ(B, "lgd", Values = y, PositionA = rA, ...
    PositionB = rB, Cov = Cv, Operator = op, Valid = valid);
keep = [false(10, 1); true(M - 30, 1); false(20, 1)];
verifyEqual(testCase, ik.kept, keep);
verifyEqual(testCase, rk.nobs, M - 30);
Ak = W(keep, :) * A;
yk = W(keep, :) * y;
Ck = Cv(keep, keep);
N2 = Ak' * (Ck \ Ak);
bound = 100 * eps * cond(Ck);
verifyLessThan(testCase, max(abs(rk.N - N2), [], 'all') / max(abs(N2), [], 'all'), bound);
verifyLessThan(testCase, max(abs(rk.b - Ak' * (Ck \ yk))) / max(abs(rk.b)), bound);
end

% ------------------------------------------- WP8 8i: process-noise scales
function testKalmanFilterLikelihoodIsTheDenseOne(testCase)
%TESTKALMANFILTERLIKELIHOODISTHEDENSEONE kalmanFilter's Likelihood: the
%   neq-mode terms summed over the epochs, plus log|R| + l'R^-1 l of every
%   observed epoch, are the dense Gaussian -2 log likelihood of all
%   observations under the joint prior of the stationary VAR(1) states,
%   Cov(x_s, x_t) = Phi^(s-t) Sigma0 - gaps included (log(2 pi) left out of
%   both). validate_regional_adaptive.py CLAIM 1 measured 3.9e-15 in numpy;
%   the bound 1e-13 allows MATLAB's own LAPACK in the filter's inverses.
%   And the solution-mode term of an epoch exceeds the neq-mode term of the
%   same data (N = R^-1, b = R^-1 l) by exactly log|R| + l'R^-1 l (CLAIM 1:
%   1.8e-14; bound 1e-12 relative).
rng(91);
P = 4;
[model, S0] = localStableModel(P);
A1 = model.Phi{1};
T = 12;
gaps = [4 9];
cS = chol(S0, 'lower');
x = cS * randn(P, 1);
X = zeros(P, T);
cQ = chol(model.Q, 'lower');
for t = 1:T
    x = A1 * x + cQ * randn(P, 1);
    X(:, t) = x;
end
obs = repmat(struct('l', [], 'R', [], 'N', [], 'b', []), 1, T);
rows = {}; ys = {}; rs = {};
const = 0;
for t = setdiff(1:T, gaps)
    A = randn(3, P);
    r = 0.3 + rand(3, 1);
    y = A * X(:, t) + sqrt(r) .* randn(3, 1);
    obs(t).N = A' * (A ./ r);
    obs(t).b = A' * (y ./ r);
    const = const + sum(log(r)) + y' * (y ./ r);
    At = zeros(3, P * T);
    At(:, (t - 1) * P + (1:P)) = A;
    rows{end + 1} = At; ys{end + 1} = y; rs{end + 1} = r; %#ok<AGROW>
end
filt = shLowLevel.kalmanFilter(model, obs, Likelihood = true);
verifyEqual(testCase, filt.negLogLik(gaps), [0 0]);
Sig = zeros(P * T);
for s = 1:T
    for t = 1:s
        C = A1 ^ (s - t) * S0;
        Sig((s - 1) * P + (1:P), (t - 1) * P + (1:P)) = C;
        Sig((t - 1) * P + (1:P), (s - 1) * P + (1:P)) = C';
    end
end
A = vertcat(rows{:}); y = vertcat(ys{:}); r = vertcat(rs{:});
C = A * Sig * A' + diag(r);
Lc = chol((C + C') / 2, 'lower');
z = Lc \ y;
dense = 2 * sum(log(diag(Lc))) + z' * z;
verifyLessThan(testCase, abs(sum(filt.negLogLik) + const - dense) / abs(dense), 1e-13);
Lr = randn(P);
R = Lr * Lr' / P + 0.5 * eye(P);
l = randn(P, 1);
o1 = struct('l', l, 'R', R, 'N', [], 'b', []);
o2 = struct('l', [], 'R', [], 'N', inv(R), 'b', R \ l);
f1 = shLowLevel.kalmanFilter(model, o1, Likelihood = true);
f2 = shLowLevel.kalmanFilter(model, o2, Likelihood = true);
dR = 2 * sum(log(diag(chol(R)))) + l' * (R \ l);
verifyLessThan(testCase, abs(f1.negLogLik - f2.negLogLik - dR) / abs(f1.negLogLik), 1e-12);
f0 = shLowLevel.kalmanFilter(model, obs);
verifyEmpty(testCase, f0.negLogLik);
verifyTrue(testCase, isequal(f0.xf, filt.xf) && isequal(f0.Pf, filt.Pf), ...
    'Likelihood changed the filter');
end

function [tsm, tsObs, Xo, idx] = scaleFixture(seed, alpha)
%SCALEFIXTURE A VAR(1) at nmax 4 (P = 21) with a 1/(n+1)^2 signal: a model
%   series of 300 epochs from Q, and 150 observed epochs from alpha Q with
%   formal sigmas of 1e-11 - the process the model under-predicts, as in
%   Kurtenbach's Sec. 4.3.5.
rng(seed);
idx = shLowLevel.shIndex(4);
P = idx.P;
dec = 1 ./ (idx.n + 1) .^ 2;
Ph = 0.7 * eye(P) + 0.02 * randn(P);
Ph = Ph * (0.8 / max(abs(eig(Ph))));
Lq = randn(P) / sqrt(P);
Q = (Lq * Lq' + 0.2 * eye(P)) .* (dec * dec') * 1e-18;
Q = (Q + Q') / 2;
sim = @(Qs, n) simVAR(Ph, Qs, n);
Xm = sim(Q, 300);
Xo = sim(alpha * Q, 150);
sig = 1e-11 * ones(P, 1);
tsm = vecSeries(Xm, 1980 + ((1:300)' - 0.5) / 12, idx, []);
tsObs = vecSeries(Xo + sig .* randn(P, 150), 2003 + ((1:150)' - 0.5) / 12, idx, sig);
end

function X = simVAR(Ph, Q, n)
P = size(Ph, 1);
cQ = chol(Q, 'lower');
X = zeros(P, n + 100);
for k = 2:n + 100
    X(:, k) = Ph * X(:, k - 1) + cQ * randn(P, 1);
end
X = X(:, 101:end);
end

function testRegionalKalmanEstimatesTheProcessNoiseScale(testCase)
%TESTREGIONALKALMANESTIMATESTHEPROCESSNOISESCALE EstimateQScale finds
%   Kurtenbach's alpha from the data: the observed process runs with 4 Q,
%   the model series with Q. The estimate lands closer to 4 than to 1 and
%   below 8 (validate_regional_adaptive.py CLAIM 3: relative spread 9-20
%   percent at a weaker data set), it is a maximum of the likelihood (5
%   percent either side is no better), and it lowers the error of the
%   smoothed states against alpha = 1 (30 of 30 seeds in CLAIM 3).
[tsm, tsObs, Xo, idx] = scaleFixture(92, 4);
B = shLowLevel.regionalBasis(idx, [], Type = "sh");
args = {"ModelSeries", tsm, "Climatology", false};
[ts1, o1] = shLowLevel.regionalKalman(tsObs, B, args{:});
[tsE, oE] = shLowLevel.regionalKalman(tsObs, B, args{:}, EstimateQScale = true);
qs = oE.qScale;
verifyTrue(testCase, oE.qEstimate.estimated && oE.qEstimate.evaluations > 0 && ...
    ~oE.qEstimate.atBound, 'the search did not run to an interior maximum');
verifyGreaterThan(testCase, qs, 2);
verifyLessThan(testCase, qs, 8);
for f = [1.05, 1 / 1.05]
    [~, oF] = shLowLevel.regionalKalman(tsObs, B, args{:}, QScale = f * qs, ...
        QBlocks = ones(B.K, 1), EstimateQScale = false);
    verifyGreaterThanOrEqual(testCase, oF.negLogLik, oE.negLogLik - 1e-6 * abs(oE.negLogLik));
end
xE = seriesVectors(tsE, idx);
x1 = seriesVectors(ts1, idx);
verifyLessThan(testCase, sqrt(mean((xE - Xo) .^ 2, 'all')), sqrt(mean((x1 - Xo) .^ 2, 'all')));
verifyEqual(testCase, o1.qScale, 1);
verifyFalse(testCase, o1.qEstimate.estimated);
end

function testRegionalKalmanQBlocksScaleBlockwise(testCase)
%TESTREGIONALKALMANQBLOCKSSCALEBLOCKWISE With QBlocks and one QScale per
%   block the process noise is D Q D, D = diag(sqrt(alpha)), formed from
%   the same Q the plain chain estimates - bitwise; the dynamics and
%   Sigma0 are unchanged. QBlocks all ones is one block, and one fixed
%   alpha is v5.18.0's chain - bitwise.
[tsm, tsObs, ~, idx] = scaleFixture(93, 1);
B = shLowLevel.regionalBasis(idx, [], Type = "sh");
args = {"ModelSeries", tsm, "Climatology", false};
[~, o0] = shLowLevel.regionalKalman(tsObs, B, args{:});
blocks = 1 + double(idx.n >= 4);
al = [2; 0.5];
[~, oB] = shLowLevel.regionalKalman(tsObs, B, args{:}, QBlocks = blocks, QScale = al);
d = sqrt(al(blocks));
Qref = d .* o0.model.Q .* d.';
Qref = (Qref + Qref.') / 2;
verifyTrue(testCase, isequal(oB.model.Q, Qref), 'Q is not D Q D');
verifyTrue(testCase, isequal(oB.model.Phi, o0.model.Phi) && ...
    isequal(oB.model.Sigma0, o0.model.Sigma0), 'the dynamics or Sigma0 changed');
verifyEqual(testCase, oB.qScale, al);
verifyEqual(testCase, oB.qBlocks, blocks);
[t3, o3] = shLowLevel.regionalKalman(tsObs, B, args{:}, QScale = 3);
[t4, o4] = shLowLevel.regionalKalman(tsObs, B, args{:}, QScale = 3, ...
    QBlocks = ones(B.K, 1), EstimateQScale = false);
verifyTrue(testCase, isequaln(t3, t4) && isequaln(rmfield(o3, 'qBlocks'), ...
    rmfield(o4, 'qBlocks')), 'one block is not the plain chain');
end

function testRegionalKalmanOrderTwoOnTheSHBasisIsKalmanChain(testCase)
%TESTREGIONALKALMANORDERTWOONTHESHBASISISKALMANCHAIN VAR(2) through the
%   regional chain: on the SH basis it is kalmanChain at Order 2 - the same
%   process model bit for bit, and the information-form update against
%   kalmanChain's gain form in companion space. The fixture is
%   validate_regional_adaptive.py CLAIM 4b's: the five degree-2
%   coefficients, a stationary VAR(2) truth behind a 3000-epoch model
%   series, 30 observed epochs of which every fourth is missing. There the
%   two forms agree to 9.45e-16 in the smoothed states and 1.11e-15 in the
%   sigmas over 40 seeds; the bounds are 3x those. (The first fixture, nmax 6 with 240
%   model epochs, asked 2 x 45^2 VAR parameters of 240 epochs; the estimate
%   was explosive - companion radius 6.8 - and the two rounding paths grew
%   apart, 8.6e-12 in the states on A8.)
[tsm, tsObs, ep, idx] = var2Fixture(64);
B = shLowLevel.regionalBasis(idx, [], Type = "sh");
[tsR, outR] = shLowLevel.regionalKalman(tsObs, B, ModelSeries = tsm, ...
    Epochs = ep, Order = 2, Climatology = false);
[tsC, repC] = shLowLevel.kalmanChain(tsObs, ModelSeries = tsm, Epochs = ep, ...
    Order = 2, Climatology = false);
verifyTrue(testCase, isequaln(outR.model, repC.model), 'the VAR(2) model differs');
verifyEqual(testCase, outR.order, 2);
verifyLessThan(testCase, outR.model.specRadius, 1, 'the fixture is not stationary');
[xR, sR] = seriesVectors(tsR, idx);
[xC, sC] = seriesVectors(tsC, idx);
verifyLessThan(testCase, max(abs(xR - xC), [], 'all') / max(abs(xC), [], 'all'), ...
    3 * 9.45e-16);
verifyLessThan(testCase, max(abs(sR ./ sC - 1), [], 'all'), 3 * 1.11e-15);
end

function testEstimateVAROrderTwoSolvesTheYuleWalkerEquations(testCase)
%TESTESTIMATEVARORDERTWOSOLVESTHEYULEWALKEREQUATIONS A35: for Order 2 the
%   estimate satisfies the Yule-Walker equations of the series' own sample
%   covariances G(h) = E[x_(t+h) x_t'],
%     G(1) = Phi1 G(0) + Phi2 G(1)',   G(2) = Phi1 G(1) + Phi2 G(0),
%   to rounding (9.8e-17 of |G| in numpy on this configuration; bound
%   1e-13, for the conditioning of a 10 x 10 solve - the defect it guards
%   against misses by 0.30), and
%   recovers a stationary truth (companion radius about 0.7) as a
%   stationary model. Before v5.20.0 the block matrix held G(i - j) where
%   E[x_(t-i) x_(t-j)'] = G(j - i) belongs, which missed the first
%   equation by O(|G|) and put the companion radius at 1.45
%   (validate_regional_adaptive.py's Yule-Walker, and this fixture).
[tsm, ~, ~, idx] = var2Fixture(64);
X = seriesVectors(tsm, idx);
model = shLowLevel.estimateVAR(X, Order = 2);
T = size(X, 2);
G0 = X * X.' / T;
G1 = X(:, 2:end) * X(:, 1:end-1).' / (T - 1);
G2 = X(:, 3:end) * X(:, 1:end-2).' / (T - 2);
[P1, P2] = deal(model.Phi{1}, model.Phi{2});
sc = max(abs(G0), [], 'all');
verifyLessThan(testCase, max(abs(P1 * G0 + P2 * G1.' - G1), [], 'all') / sc, 1e-13);
verifyLessThan(testCase, max(abs(P1 * G1 + P2 * G0 - G2), [], 'all') / sc, 1e-13);
verifyLessThan(testCase, model.specRadius, 0.95);
end

function [tsm, tsObs, ep, idx] = var2Fixture(seed)
%VAR2FIXTURE validate_regional_adaptive.py CLAIM 4b: nmax 2 with shIndex's
%   default Nmin = 2 (P = 5, the degree-2 coefficients), a
%   VAR(2) with Phi1 = 0.9 I + noise and Phi2 = -0.5 I + noise (companion
%   radius about 0.7, capped at 0.97), a 3000-epoch model series and 30
%   monthly epochs observed directly with sigmas of 0.5-1 signal standard
%   deviations, every fourth missing.
rng(seed);
idx = shLowLevel.shIndex(2);
K = idx.P;
Bc = [0.9 * eye(K) + 0.05 * randn(K), -0.5 * eye(K) + 0.05 * randn(K); ...
      eye(K), zeros(K)];
rho = max(abs(eig(Bc)));
if rho > 0.97
    Bc(1:K, :) = Bc(1:K, :) * (0.97 / rho);
end
L = randn(K);
cQ = chol((L * L.' / K + 0.3 * eye(K)) * 1e-18, 'lower');
z = zeros(2 * K, 1);
X = zeros(K, 3030);
for t = 1:3230
    z = Bc * z;
    z(1:K) = z(1:K) + cQ * randn(K, 1);
    if t > 200
        X(:, t - 200) = z(1:K);
    end
end
sig = 0.5 * std(X(:, 1:3000), 0, 2) .* (1 + rand(K, 1));
tsm = vecSeries(X(:, 1:3000), 1750 + ((1:3000)' - 0.5) / 12, idx, []);
ep = 2003 + ((1:30)' - 0.5) / 12;
keep = mod(0:29, 4) ~= 3;
Lobs = X(:, 3001:3030) + sig .* randn(K, 30);
tsObs = vecSeries(Lobs(:, keep), ep(keep), idx, sig);
end

function testBuildCondFunInABasis(testCase)
%TESTBUILDCONDFUNINABASIS buildCondFun(..., Basis = B) conditions basis
%   covariances as Proj f(T S T') Proj'. On the SH basis (T = Proj = I) it
%   is the SH conditioner bitwise; on an RBF basis without taper and
%   regions it is the identity to the projector's tolerance
%   (validate_regional_adaptive.py CLAIM 5: 1.1e-10; bound 1e-9 of the
%   largest entry), and with a taper it stays positive semidefinite.
idx = shLowLevel.shIndex(8);
kn = -0.3 * ones(idx.Lmax + 1, 1);            % synthetic Love numbers
Bsh = shLowLevel.regionalBasis(idx, [], Type = "sh");
rng(94);
Ar = randn(idx.P, 2 * idx.P);
C = Ar * Ar.' / (2 * idx.P);
cf = shLowLevel.buildCondFun(idx, kn = kn, Psi0Km = 2000);
cfB = shLowLevel.buildCondFun(idx, kn = kn, Psi0Km = 2000, Basis = Bsh);
verifyTrue(testCase, isequal(cfB(C), cf(C)), 'not the SH conditioner on the SH basis');
B = shLowLevel.regionalBasis(idx, @(la, lo) double(la > 40));
Ak = randn(B.K, 2 * B.K);
S = Ak * Ak.' / (2 * B.K);
cfI = shLowLevel.buildCondFun(idx, kn = kn, Basis = B);
verifyLessThan(testCase, max(abs(cfI(S) - S), [], 'all') / max(abs(S), [], 'all'), 1e-9);
cfT = shLowLevel.buildCondFun(idx, kn = kn, Psi0Km = 1500, Basis = B);
St = cfT(S);
verifyEqual(testCase, size(St), [B.K B.K]);
verifyTrue(testCase, issymmetric(St));
verifyGreaterThan(testCase, min(eig(St)), -1e-12 * max(eig(St)));
end
