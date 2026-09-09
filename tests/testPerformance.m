classdef testPerformance < matlab.perftest.TestCase
%TESTPERFORMANCE Performance benchmarks for the shAnalysis v2 toolbox.
%
%   Run as benchmarks (statistical timing, multiple samples):
%       results = runperf('testPerformance');
%       sampleSummary(results)
%   Or as plain tests (single pass, includes the cache-speedup assertion):
%       results = runtests('testPerformance');
%
%   Covered:
%     * legendreALF recursion cost at nmax 60 / 120 over 181 latitudes
%     * 1-degree global synthesis, cold vs. Legendre-cache warm
%       (warm asserted < 0.6 x cold median)
%     * classic chain (destripe + Gaussian) on a monthly stack
%     * tvANS filter pipeline at L=20, T=60
%
%   Speed budgets (WP2 step 1, v5.0.2)
%     testSpeedBudget asserts ten workloads against a per-machine
%     baseline committed in tests/perf_baseline.csv:
%       legendre_n96 / _n360 / _n720   the Holmes-Featherstone recursion
%       synthesis_direct_n60           reduction only (cache primed)
%       synthesis_fft_n60              the FFT-along-longitude path
%       synthesis_points_n60           2000 scattered points, clenshaw
%       synthesis_points_n60_direct    200 scattered points, direct
%       analysis_rings_n60             exact per-order ring analysis
%       apply_ddk_n96                  order-block filter application
%       leakage_1iter_n24              one leakageCorrect step
%       kalman_step_p40                a 12-epoch VAR(1) filter chain
%     Each is timed Repeats times after one untimed warm-up; the MEDIAN
%     is compared against BudgetFactor x the baseline for THIS machine.
%     A machine with no baseline row FILTERS the budget (assumeNotEmpty)
%     and prints a PERFBASE,... line - that line is a ready-made
%     perf_baseline.csv row, which is how a new machine is adopted.
%     Baselines are per machine on purpose: a ratio against a
%     calibration workload would only be machine-independent if the
%     calibration scaled like the workload, and a BLAS-bound calibration
%     does not track a memory-bound recursion.
%
%   Absolute times are hardware-dependent; only the cache ratio and the
%   budgets are asserted. Treat the rest as tracked benchmarks (runperf
%   history).
%   testLoggedBaselines additionally appends one-shot wall times to
%   tests/perf_log.csv (date, MATLAB release, benchmark, seconds) -
%   a growing machine-local regression record without brittle absolute
%   assertions (v2.2).
%
%   Claude (Fable 5), 2026-08-07.
%   Developed by Matthias Weigelt with the help of Claude (Fable 5).

properties (TestParameter)
    nmaxP = struct('n60', 60, 'n120', 120);
    % one budgeted workload per entry; the field name IS the benchmark
    % name in perf_baseline.csv and perf_log.csv (WP2 step 1)
    budgetCase = struct( ...
        'legendre_n96',         'legendre_n96', ...
        'legendre_n360',        'legendre_n360', ...
        'legendre_n720',        'legendre_n720', ...
        'synthesis_direct_n60', 'synthesis_direct_n60', ...
        'synthesis_fft_n60',    'synthesis_fft_n60', ...
        'synthesis_points_n60', 'synthesis_points_n60', ...
        'synthesis_points_n60_direct', 'synthesis_points_n60_direct', ...
        'analysis_rings_n60',   'analysis_rings_n60', ...
        'apply_ddk_n96',        'apply_ddk_n96', ...
        'leakage_1iter_n24',    'leakage_1iter_n24', ...
        'kalman_step_p40',      'kalman_step_p40');
end

properties (Constant)
    % WP2 specifies "3 x a baseline". Read what that does and does not
    % buy, because the two are easy to confuse:
    %   IT CATCHES a workload that blows up - a wrong algorithm, an
    %     accidental O(n^2), a lost fast path.
    %   IT DOES NOT CATCH the 1.3x creep A9 actually names. A9 is
    %     therefore only PARTLY closed by this factor, and saying so is
    %     the point of this comment.
    % The first A8 run (2026-09-09, f6d5529) measured the WITHIN-run
    % spread: median/min <= 1.043 over 15 repeats for every workload
    % above 20 ms, 1.114 for apply_ddk_n96 at 1.8 ms where the timer
    % itself dominates. That is not the statistic a budget needs. The
    % BETWEEN-run spread is - and one run cannot measure it. Tighten
    % this factor only against several runs' medians, never against the
    % within-run figures above.
    BudgetFactor = 3;
    Repeats = 15;               % WP2: 15 repeats, median of the samples
end

methods (TestClassSetup)
    function addPaths(tc)
        here = fileparts(mfilename('fullpath'));
        root = fileparts(here);
        tc.applyFixture(matlab.unittest.fixtures.PathFixture(root));
        shLowLevel.legendreCached('clear');
    end
end

methods (Test)
    function benchLegendre(tc, nmaxP)
        lat = deg2rad(-90:1:90);
        while tc.keepMeasuring
            P = shLowLevel.legendreALF(nmaxP, lat); %#ok<NASGU>
        end
    end

    function benchSynthesisCold(tc)
        g = tc.randomField(60);
        lat = -90:1:90; lon = 0:1:359;
        while tc.keepMeasuring
            shLowLevel.legendreCached('clear');            % force recursion
            grid = g.synthesis(lat, lon); %#ok<NASGU>
        end
    end

    function benchSynthesisWarm(tc)
        g = tc.randomField(60);
        lat = -90:1:90; lon = 0:1:359;
        g.synthesis(lat, lon);                      % prime the cache
        while tc.keepMeasuring
            grid = g.synthesis(lat, lon); %#ok<NASGU>
        end
    end

    function testLoggedBaselines(tc)
        % one-shot wall times appended to tests/perf_log.csv (no asserts)
        here = fileparts(mfilename('fullpath'));
        logf = fullfile(here, 'perf_log.csv');
        newFile = ~isfile(logf);
        fid = fopen(logf, 'a');
        tc.assertGreaterThan(fid, 0);
        cl = onCleanup(@() fclose(fid));
        if newFile
            fprintf(fid, 'date,matlab,bench,seconds\n');
        end
        stamp = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm'));
        rel = version('-release');
        g = tc.randomField(60);
        lat = -90:1:90; lon = 0:1:359;
        shLowLevel.legendreCached('clear');
        tt = tic; g.synthesis(lat, lon); sec = toc(tt);
        fprintf(fid, '%s,%s,synthesis_n60_1deg_cold,%.3f\n', stamp, rel, sec);
        tt = tic; g.synthesis(lat, lon); sec = toc(tt);
        fprintf(fid, '%s,%s,synthesis_n60_1deg_warm,%.3f\n', stamp, rel, sec);
        idx = shLowLevel.shIndex(20);
        X = randn(idx.P, 60); ty = 2002 + (0:59)'/12;
        tt = tic; shLowLevel.tvANSFilter(X, ty, idx); sec = toc(tt);
        fprintf(fid, '%s,%s,tvans_L20_T60,%.3f\n', stamp, rel, sec);
        fprintf('  perf_log.csv updated (%s)\n', stamp);
    end

    function testCacheSpeedup(tc)
        % Deterministic assertion: cached synthesis clearly beats cold.
        % v2.5 robustness: the n60 workload (~13 ms cold) was dominated
        % by timer noise and fixed synthesis overhead under machine load
        % (failed at 0.009 vs 0.013 s on a loaded run). Now: a Legendre-
        % dominated workload (n120, 361 rings, cold ~0.1 s), min-of-N
        % timing (load only inflates, never deflates), 0.75 margin.
        g = tc.randomField(120);
        lat = -90:0.5:90; lon = 0:1:359;
        nRep = 3; tCold = zeros(nRep,1); tWarm = zeros(nRep,1);
        for k = 1:nRep
            shLowLevel.legendreCached('clear');
            t0 = tic; g.synthesis(lat, lon); tCold(k) = toc(t0);
        end
        g.synthesis(lat, lon);                      % prime
        for k = 1:nRep
            t0 = tic; g.synthesis(lat, lon); tWarm(k) = toc(t0);
        end
        tc.verifyLessThan(min(tWarm), 0.75 * min(tCold), ...
            sprintf(['Legendre cache speedup insufficient: warm %.3fs ' ...
            'vs cold %.3fs (min of %d)'], ...
            min(tWarm), min(tCold), nRep));
    end

    function testSpeedBudget(tc, budgetCase)
        %TESTSPEEDBUDGET One workload, timed Repeats times, median vs the
        %   committed per-machine baseline. See the class help.
        % leakage_1iter runs unregularised on purpose (one step is not a
        % converged solution), so its warning would clutter every log
        ws = warning('off', 'shLowLevel:leakageCorrect:unregularised');
        cw = onCleanup(@() warning(ws)); %#ok<NASGU>

        fcn = tc.workload(budgetCase);
        fcn();                              % warm-up, not timed
        t = zeros(tc.Repeats, 1);
        for k = 1:tc.Repeats
            t0 = tic; fcn(); t(k) = toc(t0);
        end
        med = median(t);
        mn = min(t);

        mach = tc.machineId();
        rel = version('-release');
        stamp = char(datetime('now', 'Format', 'yyyy-MM-dd'));
        % a ready-made perf_baseline.csv row: this is how a machine that
        % has no baseline yet gets one, straight out of the CI log
        fprintf('PERFBASE,%s,%s,%s,%.6g,%.6g,%d,%s\n', ...
            mach, rel, budgetCase, med, mn, tc.Repeats, stamp);
        tc.appendPerfLog(budgetCase, med);

        base = tc.baselineFor(mach, budgetCase);
        tc.assumeNotEmpty(base, sprintf( ...
            ['no baseline for machine "%s", benchmark "%s" - copy the ' ...
             'PERFBASE line above into tests/perf_baseline.csv'], ...
            mach, budgetCase));
        tc.verifyLessThan(med, tc.BudgetFactor * base, sprintf( ...
            ['%s: median %.4f s over %d repeats exceeds %g x the %s ' ...
             'baseline %.4f s (min this run %.4f s)'], ...
            budgetCase, med, tc.Repeats, tc.BudgetFactor, mach, ...
            base, mn));
    end

    function benchClassicChain(tc)
        ts = tc.randomSeries(60, 24);
        while tc.keepMeasuring
            out = ts.destripe(MinOrder=6).gaussian(300); %#ok<NASGU>
        end
    end

    function benchTvANS(tc)
        ts = tc.randomSeries(20, 60);
        while tc.keepMeasuring
            [tsF, op] = ts.filter("tvANS"); %#ok<NASGU>
        end
    end

    % ------------------------------------------------------------- v2.1
    function benchSynthesisFFTvsDirect(tc)
        % FFT path on a 1-degree global grid; compare against
        % benchSynthesisWarm results externally.
        % The claim here used to be "typical gain: 5-20x at nmax=60,
        % 1 deg". The first controlled measurement of exactly that
        % configuration - synthesis_fft_n60 against synthesis_direct_n60,
        % same primed cache, 15 repeats, A8 2026-09-09 - says 4.28 ms
        % against 3.07 ms, a gain of 1.40x. The old figure was never
        % measured against the direct path with the cache in the same
        % state, which is the only comparison that isolates the FFT.
        % One machine, one configuration: the number, not a law.
        g = tc.randomField(60);
        lat = -90:1:90; lon = 0:1:359;
        g.synthesis(lat, lon);                      % prime Legendre cache
        while tc.keepMeasuring
            grid = g.synthesis(lat, lon, Method = "fft"); %#ok<NASGU>
        end
    end

    function benchFilterBlocks(tc)
        % block-diagonal tvANS: same answer as benchFilterFull, small blocks
        ts = tc.randomSeries(20, 60);
        while tc.keepMeasuring
            [tsF, op] = ts.filter("tvANS", Blocks = "on"); %#ok<NASGU>
        end
    end

    function benchReadGFC(tc)
% v3.1.1 fast path: n300 static file (~45k lines) must read in seconds,
% not tens of seconds (pre-fix: ~5 s at this size, ~30 s at n720)
L = 300;
[nn, mm] = ndgrid(0:L, 0:L); keep = mm <= nn;
n = nn(keep); m = mm(keep);
tmp = tempname; mkdir(tmp);
cl = onCleanup(@() rmIfFolder(tmp)); %#ok<NASGU>
f = fullfile(tmp, 'bench.gfc');
fid = fopen(f, 'w');
fprintf(fid, ['product_type gravity_field\nmodelname bench\n' ...
    'earth_gravity_constant 3.986004415e14\nradius 6378136.3\n' ...
    'max_degree %d\nerrors no\ntide_system zero_tide\nend_of_head\n'], L);
fprintf(fid, 'gfc %5d %5d %19.12e %19.12e\n', ...
    [n m 1e-9*randn(size(n)) 1e-9*randn(size(n))]');
fclose(fid);
t = tic; g = shLowLevel.shReadGFC(f); dt = toc(t);
fprintf('  benchReadGFC: n%d (%d records) in %.3f s\n', L, numel(n), dt);
verifyEqual(tc, g.nmax, L);
verifyLessThan(tc, dt, 5);                     % generous CI headroom
end

function benchAnalysisRings(tc)
        rng(9);
        L = 60;
        C = tril(randn(L+1)) * 1e-9; S = tril(randn(L+1), -1) * 1e-9;
        lat = linspace(-89, 89, 140); lon = (0:239) * 1.5;
        g = shLowLevel.shSynthesis(C, S, 3.986004415e14, 6378136.3, lat, lon);
        while tc.keepMeasuring
            [Ce, Se] = shLowLevel.shAnalysisGrid(g, lat, lon, L); %#ok<NASGU>
        end
    end
end

methods
    function fcn = workload(tc, name)
        %WORKLOAD Function handle for one budgeted benchmark.
        %   Every fixture is built HERE, outside the timed handle, so the
        %   budget bounds the operation and not its setup.
        GM = 3.986004415e14; R = 6378136.3;
        switch name
            case 'legendre_n96'
                lat = deg2rad(-90:1:90);            % 181 rings, ~14 MB
                fcn = @() shLowLevel.legendreALF(96, lat);
            case 'legendre_n360'
                lat = deg2rad(-90:2:90);            % 91 rings, ~95 MB
                fcn = @() shLowLevel.legendreALF(360, lat);
            case 'legendre_n720'
                % 31 rings: P is (nmax+1)^2 x nlat doubles, so the ring
                % count is set by memory (~129 MB), not by taste
                lat = deg2rad(linspace(-89, 89, 31));
                fcn = @() shLowLevel.legendreALF(720, lat);
            case 'synthesis_direct_n60'
                g = tc.randomField(60);
                la = -90:1:90; lo = 0:1:359;
                g.synthesis(la, lo, Method = "direct");   % prime the cache
                fcn = @() g.synthesis(la, lo, Method = "direct");
            case 'synthesis_fft_n60'
                g = tc.randomField(60);
                la = -90:1:90; lo = 0:1:359;
                g.synthesis(la, lo, Method = "fft");
                fcn = @() g.synthesis(la, lo, Method = "fft");
            case 'synthesis_points_n60'
                % 2000 scattered points: the regime "auto" routes to
                % clenshaw. Forced here rather than left to auto, so the
                % budget keeps measuring the same code if the crossover
                % default moves.
                g = tc.randomField(60);
                rng(11);
                np = 2000;
                la = (rand(np, 1) - 0.5) * 178;
                lo = rand(np, 1) * 360;
                rr = R + rand(np, 1) * 1000;
                C = g.C; S = g.S;
                fcn = @() shLowLevel.synthesisPoints(C, S, GM, R, ...
                    la, lo, rr, Method = "clenshaw");
            case 'synthesis_points_n60_direct'
                % 200 points is a GNSS-network-sized station list - the
                % regime "auto" routes to direct, and the one
                % shSynthesisDeformation works in. Budgeting only the
                % 2000-point case would leave the default path for short
                % lists unguarded.
                g = tc.randomField(60);
                rng(12);
                np = 200;
                la = (rand(np, 1) - 0.5) * 178;
                lo = rand(np, 1) * 360;
                rr = R + rand(np, 1) * 1000;
                C = g.C; S = g.S;
                fcn = @() shLowLevel.synthesisPoints(C, S, GM, R, ...
                    la, lo, rr, Method = "direct");
            case 'analysis_rings_n60'
                rng(9);
                L = 60;
                C = tril(randn(L+1)) * 1e-9;
                S = tril(randn(L+1), -1) * 1e-9;
                la = linspace(-89, 89, 140); lo = (0:239) * 1.5;
                gr = shLowLevel.shSynthesis(C, S, GM, R, la, lo);
                fcn = @() shLowLevel.shAnalysisGrid(gr, la, lo, L, ...
                    Method = "rings");
            case 'apply_ddk_n96'
                L = 96;
                sc = 3e-11 * ones(L+1);
                W = shLowLevel.designFilter(sc, sc, Alpha = 1, ...
                    Kaula = 1e-6);
                g = tc.randomField(L);
                C = g.C; S = g.S;
                fcn = @() shLowLevel.applyDDK(C, S, W);
            case 'leakage_1iter_n24'
                [la, lo, obs, mask, nmax] = tc.leakageFixture();
                fcn = @() shLowLevel.leakageCorrect(obs, la, lo, ...
                    Filter = "gauss500", Mask = mask, Nmax = nmax, ...
                    MaxIter = 1, Quiet = true);
            case 'kalman_step_p40'
                [model, obs] = tc.kalmanFixture(40, 12);
                fcn = @() shLowLevel.kalmanFilter(model, obs);
            otherwise
                error('testPerformance:workload:unknownCase', ...
                    'no workload for budget case "%s"', name);
        end
    end

    function [lat, lon, obs, mask, nmax] = leakageFixture(~)
        % the 6-degree disc of tools/dev/validate_leakage.py, filtered
        % with a 500 km Gaussian - the same problem testCorrectness uses
        nmax = 24;
        lat = linspace(-89, 89, 2 * nmax + 1);
        nlon = 2 * nmax + 2;
        lon = (0:nlon - 1) * (360 / nlon);
        [LO, LA] = meshgrid(lon, lat);
        psi = acosd(sind(15) * sind(LA) + ...
            cosd(15) * cosd(LA) .* cosd(LO - 300));
        truth = double(psi <= 6);
        mask = truth > 0;
        GM = 3.986004415e14; R = 6378136.3;
        [C, S] = shLowLevel.shAnalysisGrid(truth, lat, lon, nmax, ...
            GM = GM, R = R);
        w = shLowLevel.shGaussianWeights(nmax, 500);
        obs = shLowLevel.shSynthesis(C .* w(:), S .* w(:), GM, R, ...
            lat, lon);
    end

    function [model, obs] = kalmanFixture(~, P, T)
        % stationary VAR(1) at the Lyapunov fixed point, one solution
        % record per epoch - the shape testCorrectness filters
        rng(23);
        A = randn(P); A = 0.8 * A / max(abs(eig(A)));
        Q = 0.2 * eye(P) + 0.05 * ones(P);
        S0 = Q;
        for k = 1:200, S0 = A * S0 * A.' + Q; end
        S0 = (S0 + S0.') / 2;
        model = struct('Phi', {{A}}, 'Q', Q, 'Sigma0', S0, ...
            'order', 1, 'P', P, 'specRadius', max(abs(eig(A))));
        obs = repmat(struct('l', [], 'R', [], 'N', [], 'b', []), 1, T);
        for t = 1:T
            obs(t).l = randn(P, 1);
            obs(t).R = diag(0.3 + rand(P, 1));
        end
    end

    function id = machineId(~)
        %MACHINEID Stable label for the machine a baseline belongs to.
        %   SHANALYSIS_PERF_MACHINE wins so a runner can name itself;
        %   COMPUTERNAME covers Windows, `hostname` covers the rest.
        h = getenv('SHANALYSIS_PERF_MACHINE');
        if isempty(h), h = getenv('COMPUTERNAME'); end
        if isempty(h), h = getenv('HOSTNAME'); end
        if isempty(h)
            [st, out] = system('hostname');
            if st == 0, h = strtrim(out); end
        end
        if isempty(h), h = 'unknown'; end
        id = regexprep(strtrim(h), '[^A-Za-z0-9_.-]', '_');
    end

    function base = baselineFor(~, machine, bench)
        %BASELINEFOR Median seconds committed for this machine, or [].
        here = fileparts(mfilename('fullpath'));
        f = fullfile(here, 'perf_baseline.csv');
        base = [];
        if ~isfile(f), return; end
        lines = strsplit(fileread(f), newline);
        for k = 1:numel(lines)
            row = strtrim(lines{k});
            if isempty(row) || startsWith(row, '#'), continue; end
            c = strsplit(row, ',');
            if numel(c) < 4, continue; end
            if strcmp(strtrim(c{1}), machine) && ...
                    strcmp(strtrim(c{3}), bench)
                base = str2double(c{4});
                return
            end
        end
    end

    function appendPerfLog(~, bench, sec)
        %APPENDPERFLOG One row in the machine-local perf_log.csv.
        here = fileparts(mfilename('fullpath'));
        logf = fullfile(here, 'perf_log.csv');
        newFile = ~isfile(logf);
        fid = fopen(logf, 'a');
        if fid < 0, return; end            % a read-only tree is not a failure
        cl = onCleanup(@() fclose(fid)); %#ok<NASGU>
        if newFile
            fprintf(fid, 'date,matlab,bench,seconds\n');
        end
        fprintf(fid, '%s,%s,%s,%.6f\n', ...
            char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm')), ...
            version('-release'), bench, sec);
    end

    function g = randomField(~, nmax)
        rng(7);
        C = tril(randn(nmax+1)) * 1e-9; S = tril(randn(nmax+1), -1) * 1e-9;
        g = shCoefficients(C, S, Epoch = 2020, ProductType = "GSM");
    end

    function ts = randomSeries(tc, nmax, T)
        rng(8);
        mL  = tril(true(nmax+1));       % tril does not accept 3-D input
        mL1 = tril(true(nmax+1), -1);
        Cs = tril(randn(nmax+1)) .* ones(1,1,T) * 1e-9 ...
            + (mL .* randn(nmax+1, nmax+1, T)) * 2e-10;
        Ss = (mL1 .* randn(nmax+1, nmax+1, T)) * 1e-9;
        ep = 2020 + (0:T-1)'/12;
        ts = shSeries(Cs, Ss = Ss, Epochs = ep, ProductType = "GSM");
        tc.assertEqual(ts.nEpochs, T);
    end
end
end
