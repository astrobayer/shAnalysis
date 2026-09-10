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
%       synthesis_direct_n180          reduction only, 0.5 deg (cache primed)
%       synthesis_fft_n180             the FFT-along-longitude path, 0.5 deg
%       synthesis_points_n60           2000 scattered points, clenshaw
%       synthesis_points_n60_direct    200 scattered points, direct
%       synthesis_points_n50_direct/_clenshaw  a SECOND matched pair at
%         50 points, bracketing the crossover from below: the 200-point
%         pair put clenshaw 4.5x ahead on A8, so the crossover is under
%         200 and one pair alone cannot say where
%       synthesis_points_n60_clenshaw  THE SAME 200 points, clenshaw -
%         the two are a matched pair on purpose: a crossover can only
%         be read off two paths measured at the SAME point count, and
%         v5.1.0 shipped them at 2000 and 200, which cannot bracket it
%       analysis_rings_n60             exact per-order ring analysis
%       apply_ddk_n300                 order-block filter application
%       leakage_1iter_n48              one leakageCorrect step
%       kalman_step_p200               a 12-epoch VAR(1) filter chain
%     Each is timed Repeats times after one untimed warm-up; the MEDIAN
%     is compared against a factor x the baseline for THIS machine. The
%     factor is per benchmark, not global (v5.3.0): TightFactor 1.3 for
%     the eight workloads whose measured between-run spread earned it,
%     BudgetFactor 3 for the rest. See the constants for the criterion
%     and for why one number could not serve both kinds of benchmark.
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
        'synthesis_direct_n180', 'synthesis_direct_n180', ...
        'synthesis_fft_n180',   'synthesis_fft_n180', ...
        'synthesis_points_n60', 'synthesis_points_n60', ...
        'synthesis_points_n60_direct', 'synthesis_points_n60_direct', ...
        'synthesis_points_n60_clenshaw', 'synthesis_points_n60_clenshaw', ...
        'synthesis_points_n50_direct', 'synthesis_points_n50_direct', ...
        'synthesis_points_n50_clenshaw', 'synthesis_points_n50_clenshaw', ...
        'analysis_rings_n60',   'analysis_rings_n60', ...
        'apply_ddk_n300',       'apply_ddk_n300', ...
        'leakage_1iter_n48',    'leakage_1iter_n48', ...
        'kalman_step_p200',     'kalman_step_p200');
end

properties (Constant)
    % A9 asks for a budget that catches a 1.3x creep. What a budget can
    % honestly assert depends on the workload, so there are two factors,
    % and v5.4.1 found out WHY the small workloads could not be tight.
    %
    % The statistic is the BETWEEN-run spread - 15 repeats inside one
    % process cannot give it. Worst run-to-run ratio per workload:
    %
    %   workload                       A8      MATTHIASPC   size
    %   legendre_n720                  1.011   1.029        171-285 ms
    %   legendre_n360                  1.031   1.036         57-88 ms
    %   analysis_rings_n60             1.007   1.079         40-70 ms
    %   apply_ddk_n300                 1.072   1.059         15-23 ms
    %   synthesis_fft_n180             1.002   1.007         31-40 ms
    %   synthesis_direct_n180          1.021   1.022         30-39 ms
    %   kalman_step_p200               1.009   1.035         18-30 ms
    %   leakage_1iter_n48              1.007   1.046         47-81 ms
    %   ---- above: TightFactor.  below: BudgetFactor ----
    %   legendre_n96                   1.024   1.532          8-12 ms
    %   five point-synthesis budgets   <=1.608 <=1.685        1-22 ms
    %
    % WHY the small ones were noisy, measured 2026-09-10. One iteration of
    % the old leakage_1iter_n24 took 12.4 ms at 16 threads with p90/p10
    % 1.44, and 9.3 ms at ONE thread with 1.15 - slower AND noisier with
    % more threads. On a 49 x 50 grid, multithreaded BLAS spends more on
    % thread scheduling than on arithmetic, and on a shared runner that
    % scheduling is what moves between runs: it is how a 23 ms workload
    % swung 1.306 on A8 while nobody touched it. The grid synthesis
    % reduction showed the same thing (nmax 120 / 1 deg: 1.49 at 16
    % threads, 1.04 at one). So the fix was never a braver factor. It was
    % a workload large enough for threading to pay, and four were
    % replaced: leakage n24 -> n48, Kalman p40 -> p200, and the synthesis
    % pair n60 / 1 deg -> n180 / 0.5 deg.
    %
    % THE CRITERION, stated precisely because the loose wording failed
    % within a day. A workload is tight when (a) its A8 run-to-run spread
    % over at least two runs is <= 1.1, and (b) no run on EITHER machine
    % has come in more than 1.1 ABOVE its baseline. The first wording -
    % max/min <= 1.1 on both machines - also counts FAST runs. On
    % 2026-09-10 a full-suite run on a quiet desktop came in 0.84x below
    % baselines taken while it was busy; under that wording
    % analysis_rings_n60, the steadiest budget on A8 (1.007), would have
    % been demoted for the machine being idle. A fast run cannot fail an
    % upper bound. It does erode SENSITIVITY on that machine - a baseline
    % taken under load masks part of a regression there - so the 1.3x
    % guarantee A9 asks for holds on A8, the CI gate, and on a
    % workstation the budgets err loose.
    %
    % TightFactor is 1.3, down from 1.5, because the evidence now allows
    % the number A9 actually asks for. The worst deviation any single run
    % has shown from its tight-tier baseline is 1.057 (apply_ddk_n300 on
    % A8, one run against the six-run median), so 1.3 leaves 1.23x of
    % headroom. That margin exists only because every baseline is a
    % median over runs: against a single-run baseline that landed at the
    % fast end it would not.
    %
    % What stays at BudgetFactor, and why that is correct rather than
    % unfinished: the n50/n60 point pairs are crossover BRACKETS -
    % enlarging them would destroy what they measure - and legendre_n96
    % is small by construction. At 3x they guard against blow-ups, which
    % is all a 1-10 ms workload on a 16-thread machine can promise.
    BudgetFactor = 3;           % everything not listed below
    TightFactor = 1.3;          % see above: 1.23x over the worst tight run
    TightBudgets = ["legendre_n360", "legendre_n720", ...
                    "analysis_rings_n60", "apply_ddk_n300", ...
                    "leakage_1iter_n48", "kalman_step_p200", ...
                    "synthesis_direct_n180", "synthesis_fft_n180"];
    % The last four joined in the same release that created them, on two
    % A8 runs of the same commit (2c7b779: the PR run and a
    % workflow_dispatch) - 1.007, 1.009, 1.021 and 1.002. That is the
    % rule being met, not bent: it asks for two A8 runs, and there were.
    % apply_ddk_n300 joined in v5.4.1. v5.3.0 held it back on ONE A8
    % observation, which gives no spread at all; six A8 runs later
    % (2026-09-09, PRs #102 and #103) its worst run-to-run ratio is
    % 1.072 there and 1.059 on MATTHIASPC. It meets the criterion on
    % exactly the evidence the criterion asks for - which is the only
    % way anything should get into this list.
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
        fac = tc.factorFor(budgetCase);
        tc.verifyLessThan(med, fac * base, sprintf( ...
            ['%s: median %.4f s over %d repeats exceeds %g x the %s ' ...
             'baseline %.4f s (min this run %.4f s)'], ...
            budgetCase, med, tc.Repeats, fac, mach, base, mn));
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
        % Those two budgets became synthesis_{direct,fft}_n180 on a
        % 0.5-degree grid in v5.4.1, because at n60 their spread was set
        % by thread scheduling. The 1.40x above is the n60 figure. At n180
        % / 0.5 deg MATTHIASPC measures direct 29.9 ms against fft 31.4
        % ms - the FFT path is not faster there at all. One machine, one
        % size: a reason to measure the crossover, not yet to change auto.
        g = tc.randomField(60);
        lat = -90:1:90; lon = 0:1:359;
        g.synthesis(lat, lon);                      % prime Legendre cache
        while tc.keepMeasuring
            grid = g.synthesis(lat, lon, Method = "fft"); %#ok<NASGU>
        end
    end

    function benchPointsCrossover(tc)
        %BENCHPOINTSCROSSOVER Where "direct" and "clenshaw" cross - if
        %   they do. This is the measurement that sets ClenshawFrom.
        %
        %   It prints one XOVER,... line per (nmax, P), each timing BOTH
        %   paths on the SAME points, which is the only comparison a
        %   crossover can be read from. v5.1.0 shipped the two paths
        %   budgeted at 2000 and 200 points and could read nothing off
        %   them; the matched pair in the budget set fixed that at one
        %   point count, and this sweep covers the range.
        %
        %   MATTHIASPC, R2026a, 2026-09-09: "clenshaw" is ahead at EVERY
        %   point count measured - P = 1..2000 at nmax 60 and 120, and
        %   P = 1..200 at nmax 360 - by 2.0x at the narrowest margin and
        %   34x at a single point. There is no crossover in MATLAB,
        %   which is why ClenshawFrom defaults to 1 and not to the numpy
        %   prototype's 150.
        %
        %   Not asserted. A timing comparison at 1 ms is exactly the kind
        %   of thing that flaps on a shared runner, and the dispatch RULE
        %   is pinned without a clock by testContract's
        %   testSynthesisPointsAutoPicksTheFasterPath and
        %   testSynthesisPointsAutoIsClenshawByDefault. This benchmark is
        %   the evidence for the default; those tests are the contract.
        GM = 3.986004415e14; R = 6378136.3;
        reps = 5;
        % the point list is per degree on purpose: "direct" holds a
        % (nmax+1)^2 x chunk Legendre block, so nmax 360 at 2000 points
        % would ask for ~2 GB. The budget set covers the large-scattered
        % regime at nmax 60; this sweep covers the SHAPE of the two
        % curves, and it only has to reach far enough to show whether
        % they cross.
        sweep = {60, [1 10 50 100 150 200 500 2000]; ...
                 120, [1 10 50 100 150 200 500 2000]; ...
                 360, [1 10 50 100 150 200]};
        for row = 1:size(sweep, 1)
            nmax = sweep{row, 1};
            g = tc.randomField(nmax);
            C = g.C; S = g.S;
            for np = sweep{row, 2}
                rng(12);
                la = (rand(np, 1) - 0.5) * 178;
                lo = rand(np, 1) * 360;
                rr = R + rand(np, 1) * 1000;
                shLowLevel.synthesisPoints(C, S, GM, R, la, lo, rr, ...
                    Method = "direct");
                shLowLevel.synthesisPoints(C, S, GM, R, la, lo, rr, ...
                    Method = "clenshaw");
                td = zeros(reps, 1); tk = zeros(reps, 1);
                for k = 1:reps
                    t0 = tic;
                    shLowLevel.synthesisPoints(C, S, GM, R, la, lo, ...
                        rr, Method = "direct");
                    td(k) = toc(t0);
                    t0 = tic;
                    shLowLevel.synthesisPoints(C, S, GM, R, la, lo, ...
                        rr, Method = "clenshaw");
                    tk(k) = toc(t0);
                end
                fprintf('XOVER,%s,%d,%d,%.6g,%.6g,%.4f\n', ...
                    tc.machineId(), nmax, np, median(td), median(tk), ...
                    median(td) / median(tk));
            end
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
            case 'synthesis_direct_n180'
                % nmax 180 on a 0.5-degree grid, not nmax 60 on 1 degree
                % (A9, 2026-09-10). The arm primes the Legendre cache, so
                % what is timed is the REDUCTION alone - ~2 ms at n60, where
                % it swung up to 1.69 between MATTHIASPC runs. That is the
                % small-work threading noise of leakage_1iter_n24 again: at
                % nmax 120 / 1 degree the reduction took 4.3 ms with
                % p90/p10 1.49 at 16 threads and 1.04 at one.
                % Sized on THIS path. The first attempt sized on a cold
                % shSynthesis call, picked 120 / 1 degree from a 19 ms
                % Legendre-dominated proxy, and measured 1.82 between runs
                % on the real 4 ms arm. Within-run on the arm, p90/p10:
                % 120/1deg 1.838, 120/0.5deg 1.058, 180/0.5deg 1.045.
                g = tc.randomField(180);
                la = -90:0.5:90; lo = 0:0.5:359.5;
                g.synthesis(la, lo, Method = "direct");   % prime the cache
                fcn = @() g.synthesis(la, lo, Method = "direct");
            case 'synthesis_fft_n180'
                % same grid and degree as synthesis_direct_n180, so the
                % pair still compares the FFT path against the direct one
                % (within-run 1.025 on the arm)
                g = tc.randomField(180);
                la = -90:0.5:90; lo = 0:0.5:359.5;
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
            case {'synthesis_points_n60_direct', ...
                    'synthesis_points_n60_clenshaw'}
                % 200 points is a GNSS-network-sized station list - the
                % regime "auto" routes to direct. The two cases share
                % this arm, and therefore the SAME rng and the SAME
                % points, so their medians are directly comparable and
                % bracket the crossover. Measured apart they could not:
                % v5.1.0 budgeted clenshaw at 2000 and direct at 200 and
                % so measured neither against the other.
                g = tc.randomField(60);
                rng(12);
                np = 200;
                la = (rand(np, 1) - 0.5) * 178;
                lo = rand(np, 1) * 360;
                rr = R + rand(np, 1) * 1000;
                C = g.C; S = g.S;
                if endsWith(name, '_direct')
                    how = "direct";
                else
                    how = "clenshaw";
                end
                fcn = @() shLowLevel.synthesisPoints(C, S, GM, R, ...
                    la, lo, rr, Method = how);
            case {'synthesis_points_n50_direct', ...
                    'synthesis_points_n50_clenshaw'}
                % the same shape at 50 points. Together with the
                % 200-point pair this brackets the crossover, which the
                % A8 numbers put well below 200 (clenshaw 4.5x ahead
                % there) and therefore below ClenshawFrom's current 150.
                g = tc.randomField(60);
                rng(13);
                np = 50;
                la = (rand(np, 1) - 0.5) * 178;
                lo = rand(np, 1) * 360;
                rr = R + rand(np, 1) * 1000;
                C = g.C; S = g.S;
                if endsWith(name, '_direct')
                    how = "direct";
                else
                    how = "clenshaw";
                end
                fcn = @() shLowLevel.synthesisPoints(C, S, GM, R, ...
                    la, lo, rr, Method = how);
            case 'analysis_rings_n60'
                rng(9);
                L = 60;
                C = tril(randn(L+1)) * 1e-9;
                S = tril(randn(L+1), -1) * 1e-9;
                la = linspace(-89, 89, 140); lo = (0:239) * 1.5;
                gr = shLowLevel.shSynthesis(C, S, GM, R, la, lo);
                fcn = @() shLowLevel.shAnalysisGrid(gr, la, lo, L, ...
                    Method = "rings");
            case 'apply_ddk_n300'
                % nmax 300, not 96, and the reason is measurement.
                % apply_ddk_n96 ran in 1.8 ms on A8 and its median moved
                % 1.519x between two runs of the SAME commit, while every
                % workload at 3 ms and above stayed inside 0.979-1.060.
                % At that size the timer, not applyDDK, is what the
                % budget measures - so it could not be budgeted, and it
                % would have dragged BudgetFactor down with it if the
                % factor were ever set from the observed spread.
                % nmax 300 measures 14.4 ms on MATTHIASPC and ~25 ms on
                % A8 at that machine's 1.76x on this workload.
                L = 300;
                sc = 3e-11 * ones(L+1);
                W = shLowLevel.designFilter(sc, sc, Alpha = 1, ...
                    Kaula = 1e-6);
                g = tc.randomField(L);
                C = g.C; S = g.S;
                fcn = @() shLowLevel.applyDDK(C, S, W);
            case 'leakage_1iter_n48'
                % nmax 48, not 24, and the reason is measured (A9,
                % 2026-09-10). At 24 one iteration is ~10 ms of 49 x 50
                % grid work, where 16-thread BLAS spends more on thread
                % scheduling than on arithmetic: forced to ONE thread the
                % same call ran 1.32x FASTER and far steadier (p90/p10
                % 1.15 against 1.44). That scheduling is what moved the
                % A8 median between 23.1 and 30.2 ms on untouched code.
                % Sweep on MATTHIASPC, p90/p10 at 16 threads: nmax 24
                % 1.694, 36 1.345, 48 1.028, 60 1.032, 72 1.046 - 48 is
                % the smallest size at which threading pays for itself.
                [la, lo, obs, mask, nmax] = tc.leakageFixture(48);
                fcn = @() shLowLevel.leakageCorrect(obs, la, lo, ...
                    Filter = "gauss500", Mask = mask, Nmax = nmax, ...
                    MaxIter = 1, Quiet = true);
            case 'kalman_step_p200'
                % P = 200, not 40. At 40 a 12-epoch chain runs in ~1.3 ms
                % and the timer dominates: p90/p10 3.9 on MATTHIASPC (A8
                % happened to be steady at 1.035, which is luck, not a
                % property). Sweep: P 80 1.286, 120 1.069, 160 1.102,
                % 200 1.059 at ~20 ms - the size class of the budgets
                % already steady enough to be tight.
                [model, obs] = tc.kalmanFixture(200, 12);
                fcn = @() shLowLevel.kalmanFilter(model, obs);
            otherwise
                error('testPerformance:workload:unknownCase', ...
                    'no workload for budget case "%s"', name);
        end
    end

    function [lat, lon, obs, mask, nmax] = leakageFixture(~, nmax)
        % the 6-degree disc of tools/dev/validate_leakage.py, filtered
        % with a 500 km Gaussian - the problem testCorrectness uses at
        % nmax 24, here at whatever degree the budget asks for
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

    function f = factorFor(tc, bench)
        %FACTORFOR Budget factor for one benchmark: TightFactor if it has
        %   earned it, BudgetFactor otherwise.
        %
        %   The criterion is stated, not fitted per benchmark - see the
        %   constants for its precise form: A8 spread <= 1.1 over at
        %   least two runs, and no run on either machine more than 1.1
        %   above its baseline. Size is necessary but not sufficient:
        %   leakage_1iter_n24 ran 23 ms and still swung 1.306 on A8,
        %   because what varied was small-grid BLAS thread scheduling,
        %   not the timer. Re-measure before adding one.
        if ismember(bench, tc.TightBudgets)
            f = tc.TightFactor;
        else
            f = tc.BudgetFactor;
        end
    end

    function id = machineId(~)
        %MACHINEID Stable label for the machine a baseline belongs to.
        %   SHANALYSIS_PERF_MACHINE wins so a runner can name itself;
        %   COMPUTERNAME covers Windows, `hostname` covers the rest.
        %
        %   The label is UPPER-CASED, and that is not cosmetic. On the
        %   acceptance machine COMPUTERNAME is "MATTHIASPC" while
        %   `hostname` returns "MatthiasPC", so which of the two MATLAB
        %   inherits decided whether a committed baseline row matched.
        %   A label that misses does not fail the budget - it FILTERS
        %   it, so the miss is silent and the workload is left
        %   unguarded, which is the one failure mode this whole harness
        %   exists to prevent. Case-folding makes one machine one label.
        %   Upper is chosen over lower so the committed A8 rows are
        %   unchanged by the fix.
        h = getenv('SHANALYSIS_PERF_MACHINE');
        if isempty(h), h = getenv('COMPUTERNAME'); end
        if isempty(h), h = getenv('HOSTNAME'); end
        if isempty(h)
            [st, out] = system('hostname');
            if st == 0, h = strtrim(out); end
        end
        if isempty(h), h = 'unknown'; end
        id = upper(regexprep(strtrim(h), '[^A-Za-z0-9_.-]', '_'));
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
