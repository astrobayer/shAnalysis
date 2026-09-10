# Changelog

## [5.4.0] - 2026-09-09 - WP5 5b: leakage correction without a model

`shLowLevel.leakageDataDriven` repairs the catchment average of a filtered
time series using correction terms built from the filtered fields alone.
It is the model-independent counterpart of `leakageCorrect`'s forward
model - Vishwakarma's "method of deviation".

### The row was blocked on equations, and the block was real

WP5 5b sat stopped because the method could not be implemented from a
half-remembered description, and the paper was unreachable. Matthias
supplied the author's PhD thesis, which carries the full derivation
(chapter 3, eqs. 3.19-3.29). That was the whole blocker.

It was a real one. Two details decide whether the method works and
neither is guessable:

- the deviation integral is weighted by the **filtered** catchment
  function, not the mask (eq. 3.19);
- the leakage extrapolation corrects a **phase** difference, not just an
  amplitude - and the deviation integral deliberately gets **no** phase
  correction, because the thesis measured those phase differences and
  found no consistent relation. That asymmetry looks like an omission
  and is a finding.

### Why the correction is exact algebra, not a fit

For a filter that leaves a constant alone (`W(0) = 1`), the filtered
catchment average splits with no approximation:

```
gbar_c = f_c + dF_c + l_c
```

true average, deviation integral (what the filter does to the catchment's
own signal, because it is not a uniform layer), and leakage in from
outside. So `f_c = gbar_c - dF_c - l_c` is a rearrangement. The hard part
is that both corrections need the unfiltered field, which nobody has - so
they are estimated from the once- and twice-filtered fields and
extrapolated one filtering step back.

### Measured, not asserted

`tools/dev/validate_leakage_datadriven.py` checks four claims:

| claim | result |
|---|---|
| the decomposition closes | 4.3e-15 relative |
| the two forms of the deviation integral agree (filter self-adjointness) | 5.0e-16 |
| measuring a phase and applying it are mutual inverses | 7.1e-15 deg |
| a closed loop moves towards the truth | **63%** of the RMS damage removed |

MATLAB removes **55.3%** on the `testCorrectness` fixture; the two differ
because the grids and the basin geometry differ (Gauss-Legendre against
equiangular), not because the method does. Both numbers were measured on
the configuration they are quoted for - an earlier draft of this entry
carried 57%, which was a third configuration's figure.

The phase claim earned its place immediately: it caught a sign error that
left every other claim passing while the correction was applied backwards.
A closed-loop percentage alone would not have found it.

### Deviations from the WP sketch, stated rather than smuggled

- The option is `Filter=` (`"gauss<km>"` | `"DDKn"` | `"none"` | a W
  struct), not `Radius=`, so it matches `leakageCorrect` and accepts the
  filters the data actually saw.
- The input is a grid stack, not an `shSeries`: `shLowLevel` works on
  arrays, and a class method belongs to WP7.
- The `info` layout is NOT `leakageCorrect`'s, because the two return
  different things - a corrected field against a corrected series. It
  carries the method's own pieces instead, each documented.
- The function needs **at least 12 epochs** and refuses NaN. Both steps
  are regressions over the whole series: they cannot skip a gap, and
  below one annual cycle the phase is unidentifiable. Returning a
  confident angle from four months would be worse than refusing.

`hilbert()` is Signal Processing Toolbox, so the analytic signal is built
by FFT here - the base-MATLAB rule again.

### Licence

The authors publish a MATLAB `DataDrivenCorrection` bundle under GPL-3.
shAnalysis is MIT, so nothing here derives from that code: the
implementation is written from the thesis equations, which is what
CLAUDE.md section 2 requires anyway ("reuse is by re-implementation").
Citations are in the function's References block.
## [5.3.0] - 2026-09-09 - MATLAB has no crossover, and the budget factor is finally a measurement

First Tier-A session since the local bridge was lost: MATLAB R2026a runs on
the acceptance machine again, so the two WP2 items that needed a machine
rather than a sandbox are both closed by measurement.

### `synthesisPoints` sent every short station list down the slower path

`ClenshawFrom` defaulted to **150** - the crossover of the numpy prototype,
carried into MATLAB where it does not hold. The new `benchPointsCrossover`
times both summations on the SAME points, and there is no crossover to find:

| nmax | P = 1 | 10 | 50 | 100 | 150 | 200 | 500 | 2000 |
|---|---|---|---|---|---|---|---|---|
| 60  | 5.0x | 2.3x | 3.2x | 3.6x | 3.6x | 3.3x | 4.0x | 4.9x |
| 120 | 19.8x | 3.2x | 4.2x | 5.5x | 6.2x | 6.5x | 5.0x | 6.4x |
| 360 | 37.2x | 2.9x | 3.9x | 4.2x | 4.4x | 4.7x | - | - |

(MATTHIASPC, R2026a; `direct` median over `clenshaw` median, so every entry
above 1.0 means `clenshaw` won.) It wins at **every** count measured, by
2.3x at the narrowest margin. The reason is structural rather than
incidental: `direct` is bounded by `legendreALF`, and `clenshaw` never calls
it - which is also why the margin grows with degree.

So **`ClenshawFrom` now defaults to 1** and `auto` is `clenshaw` everywhere.
A 100-station network was getting 3.6x less than the toolbox could give it.
The option stays, because `direct` is still the bitwise path and a caller
may want it; raising `ClenshawFrom` restores the old routing exactly.

**What changes for a caller**: `auto` below 150 points now returns clenshaw's
numbers instead of direct's. They agree to the documented 5e-14 and neither
is more accurate (both land within a few tens of eps of a 60-digit
reference, `direct` 52.7 eps worst against `clenshaw` 89.0, with clenshaw
closer at three of six points). `Method="direct"` is unchanged and still
bitwise with v3.0.0..v5.1.1.

`testSynthesisPointsAutoPicksTheFasterPath` needed no edit - it pins the
dispatch RULE while driving `ClenshawFrom` by hand, which is exactly what
that design was for. `testSynthesisPointsAutoIsClenshawByDefault` pins the
shipped number alongside it.

### A9: one factor could not do it, so there are now two

Fifteen runs of untouched code - twelve on MATTHIASPC, three on A8 - give
the BETWEEN-run spread that one run cannot. Worst run-to-run ratio per
workload, sorted by how steady it is:

| workload | size | worst run/run |
|---|---|---|
| `legendre_n720` | 171 ms | 1.011 |
| `legendre_n360` | 57 ms | 1.036 |
| `apply_ddk_n300` | 15 ms | 1.059 |
| `analysis_rings_n60` | 40 ms | 1.079 |
| `kalman_step_p40` | 1.2 ms | 1.267 |
| `leakage_1iter_n24` | **23 ms** | **1.306** |
| `legendre_n96` | 8 ms | 1.532 |
| the six point-synthesis budgets | 0.8-11 ms | 1.540 .. 1.685 |
| `synthesis_fft_n60` | 2.1 ms | 1.709 |

Two things follow, pointing opposite ways.

**A9's own 1.3 is refuted, and not by a timer artefact.**
`leakage_1iter_n24` measured 23.1, 23.1 and **30.2 ms** across three A8
runs of code nobody touched. That is 1.306 on a 23 ms workload - it cannot
be engineered away by enlarging anything, and a 1.3x budget would have gone
red on it. A gate that cries wolf is worse than no gate.

**But the four workloads at 15 ms and up never moved past 1.079**, over
fifteen runs on two machines, one of them busy. Holding those at 3x because
ten small benchmarks are noisy lets the worst member set every budget in
the set.

So the factor is now **per benchmark against a stated criterion** - worst
observed ratio <= 1.1 earns `TightFactor = 1.5`, everything else keeps
`BudgetFactor = 3`. Three qualify: `legendre_n360`, `legendre_n720` and
`analysis_rings_n60` - two of the six lanes A9 names (`legendreALF`,
`shAnalysisGrid`).

`apply_ddk_n300` is the obvious fourth and is deliberately held back. It
was in the tight list on MATTHIASPC evidence alone, and A8's first
measurement of it (23.0 ms) argued it out: that is the same size as
`leakage_1iter_n24`, which swings 1.306 on A8, and one run gives no spread
at all. Promote it when A8 has measured it twice. Applying the criterion
only to the data that happens to exist is how a criterion becomes a
rationalisation.

**A9 stays open**, and what it waits for is now specific rather than "more
runs": `leakageCorrect` and the Kalman step are still at 3x, and closing A9
means making *them* steady enough to budget. The small ones cannot simply
be enlarged - the n50/n60 pairs are crossover BRACKETS, and a bracket
measured at a different point count measures nothing.

`apply_ddk_n96` -> **`apply_ddk_n300`**. At 1.8 ms it measured the timer,
not `applyDDK`, and swung 1.519x on A8; at nmax 300 it measures 15 ms and
is now steady enough to be one of the four tight budgets. Its A8 baseline
is deleted rather than carried over: a baseline measured on a workload that
no longer runs is a budget that passes vacuously.

Every baseline is now a **median over runs** rather than a single
`PERFBASE` line (A8 45 samples = 3 runs x 15, MATTHIASPC 60 = 4 x 15). A
single run can land at either end of the spread above, and a baseline that
landed at the fast end would silently turn a 1.5x budget into a 1.1x one.

### The acceptance machine has baselines - WP2's "both machines" at last

WP2's acceptance asks for budgets calibrated on the acceptance machine AND
A8. The bridge has been gone since 2026-09-08 and it is back, so all
fourteen budgets now have a `MATTHIASPC` row - the missing half of that
acceptance, and the first thing this session did that no sandbox could.

`NO_BASELINE` is empty. Two of the entries it held were not actually
unmeasured: A8 timed the `n50` crossover pair at `b65f9a2` and the numbers
sat unread in the job log, which is its own small lesson - a measurement
that nobody reads back is not a measurement. The gate now also says what an
empty backlog does NOT mean: `apply_ddk_n300` is baselined here only, so on
A8 it still filters until that runner measures it.

The `n50` pair also settles the crossover from below on the SECOND machine.
In one A8 run (`b65f9a2`): direct 3.80 ms against clenshaw 1.07 ms at 50
points (3.56x), and 14.94 against 2.14 ms at 200 (6.99x). The run before it
put the 200-point pair at 4.61x - these are 1-15 ms budgets and their
between-run spread is exactly what the A9 section is about, so read the
direction as reproducible and the factor as not. Both machines, and every
run, agree on the direction.

### A23 (new): one machine, two labels, silently unguarded budgets

`machineId()` read `COMPUTERNAME` (`MATTHIASPC`) before falling back to
`hostname` (`MatthiasPC`), so which label a baseline row had to carry
depended on how MATLAB happened to be launched. A row that misses does not
fail its budget - it **filters** it, so the machine would have looked green
while guarding nothing. The label is now upper-cased (upper, so the
committed `A8` rows are untouched) and `perf_baseline_audit.py` rejects any
row that is not, fault-injected both ways.

### A24 (new): mlint_lite could not see a parse error

An edit put a real newline inside an `fprintf` format. `mlint_lite` reported
zero findings; MATLAB refused to parse the whole `testPerformance` class, so
every test in it would have vanished rather than failed. On CI that is a
round-trip a Tier-B session cannot predict. **R7** reports a literal that
runs off its line - read off the scanner that already had to know, not from
a second parser - and is silent on the two legal shapes that look like it
(a transpose after a value, a literal split with `...`). Zero findings
across all 149 `.m` files in the tree.
## [5.2.0] - 2026-09-09 - WP5 5c: the GIA model stops being exact

`shSeries.removeGIA` gains `Sigma=` and a second output `info`. Until now
its own help said the model "is treated as exact (its uncertainty, often
the dominant trend error over Laurentia/Fennoscandia/Antarctica, is NOT
propagated - documented limitation)". That limitation is closed.

`Sigma` is an `shCoefficients` of per-coefficient 1-sigma RATE
uncertainties [1/yr] - an ensemble spread such as Caron et al. 2018. When
it is not given, the model's own `sigmaC`/`sigmaS` are used if it carries
them, so a GIA file read with sigmas propagates without being asked.
**The default call is unchanged**: no sigma anywhere means bitwise the
same coefficients and no sigma stack invented.

### What is added, and what it deliberately is not

Per epoch the model contributes `sigmaRate * (t_k - T0)` in quadrature,
so `sigmaCs`/`sigmaSs` are correct MARGINAL per-epoch sigmas and feed
`shLowLevel.mcPropagate` (through `ts.at(k)`) and every other consumer of
the stacks with no new plumbing.

**They are not enough for a trend, and the help says so.** One rate error
applies to every epoch, so the GIA component is perfectly CORRELATED in
time. A trend fitted from per-epoch sigmas that assumes independence
understates it. `info.rateSigmaC/rateSigmaS` return the rate sigma itself
precisely so a trend consumer can add it directly.

### The oracle failed first, and it was the experiment that was wrong

`tools/dev/validate_gia_sigma.py` checks both claims against a
20000-sample Monte Carlo. The first version tested the correlation claim
on an ensemble where the per-epoch noise (2e-11) swamped the GIA rate
error (4e-12), and it duly reported that the independence assumption was
no worse - because in that regime the GIA component is invisible. The
claim is about the GIA COMPONENT, so the experiment has to isolate it.
On a GIA-only ensemble:

```
MC (truth, one rate error reused) : 4.029e-12
sigmaRate itself                  : 4.000e-12
assuming INDEPENDENCE             : 1.155e-12
understatement                    : 3.49x   (sqrt(T) = 3.46)
```

So "roughly sqrt(nEpochs)" in the help is measured, not asserted. A
badly-posed experiment that fails loudly is worth more than a
well-posed one that was never run.

### The second `info` output exposed a gate defect

`help_audit` appended EVERY local function of a classdef to EVERY
method's source, deliberately, so that `shSeries.mean` could see the
`info` struct built in `meanWindowInfo`. That was harmless while exactly
one method had an `info` output. `removeGIA` is the second, and it
immediately inherited all ten of `meanWindowInfo`'s fields as false
findings.

Same shape as A12's "a class method's source is not the whole class
file", one level out. A method now gets the local functions it actually
REACHES, transitively - the reachability rule A21a already uses for
identifiers. Pinned in both directions: a sibling that never calls the
local does not inherit its fields, the caller still does (so the fix did
not simply narrow the gate), and a local calling a local is followed.

### Also

A series carrying NO sigmas gets stacks holding the GIA term ALONE, and
`history` plus `info.sigmaWasEmpty` say so, so they cannot be mistaken
for full formal errors. `Sigma` must match the model in size -
`shSeries:removeGIA:badSigma` - because a silently zero-padded sigma
field would attach the wrong uncertainty to the wrong degree.

### Carried along: the WP2 crossover, measured and pointing the other way

v5.1.1's matched pair ran on A8, and it corrects a guess of mine. At the
SAME 200 points:

```
direct   0.0155142 s
clenshaw 0.0034370 s     clenshaw is 4.5x FASTER
```

I had speculated MATLAB's crossover was HIGHER than numpy's, reasoning
from direct@200 against clenshaw@2000 - different point counts, which is
precisely the mistake the matched pair was built to prevent. It is
LOWER: clenshaw already wins comfortably at 200, so the crossover sits
under 200 and `ClenshawFrom = 150` is too high, not too low.

`ClenshawFrom` stays at 150 regardless, because 44 is an EXTRAPOLATION
from two points at one size, and this release will not set a default
from a number it did not measure. A second matched pair at 50 points
brackets it from below; the next A8 run resolves it. Note the current
default is conservative, not wrong: for 44 <= P < 150 `auto` returns the
same answers by the slower path.

Test count: 312 methods / **326 runs** (+4 tests, +2 budgets).

## [5.1.1] - 2026-09-09 - the A8 numbers, and a budget pair that can actually bracket the crossover

v5.1.0 is green on A8: **319 runs, 313 passed, 0 failed, 6 filtered**, the
ninth exact count prediction running. The two point budgets it left
unbaselined are measured and committed:

| budget | A8 median | against |
|---|---|---|
| `synthesis_points_n60` (clenshaw, 2000 pts) | **0.0220564 s** | the retired per-point path's 2.2829 s - **103x** |
| `synthesis_points_n60_direct` (direct, 200 pts) | 0.0156066 s | - |

### The budgets as shipped could not do what their help claimed

`ClenshawFrom`'s help says `perf_baseline.csv` "budgets both paths so the
real crossover can replace it". It did not. v5.1.0 budgeted clenshaw at
2000 points and direct at 200 - two different workloads, so neither
measures the other and no crossover can be read off them. A crossover
needs both paths at the SAME point count.

`synthesis_points_n60_clenshaw` fixes it: the same arm, the same `rng`,
the same 200 points as `synthesis_points_n60_direct`, differing only in
`Method`. The pair brackets the crossover; the 2000-point case keeps
guarding the large-scattered regime.

**So `ClenshawFrom = 150` is still the numpy number.** It cannot be
replaced until that pair has run. What the A8 figures already hint at is
that MATLAB's crossover is HIGHER than numpy's - direct at 200 points
(0.0156 s) is faster than clenshaw at 2000 (0.0221 s), and clenshaw is
not flat enough in P for that to be dismissed - but hinting is not
measuring, and the number stays until the matched pair says otherwise.

### The gate found a false finding in itself

Adding the matched pair used `case {'a', 'b'}` - one MATLAB arm serving
two labels. `perf_baseline_audit`'s ARMS rule read only `case 'x'`, so it
reported both budgets as having no arm: a FALSE finding about correct
code, and precisely A2's shape (`nv_casing_audit` was blind to
`inputParser` and so reported nothing about six functions). The rule now
parses cell-array labels, with two self-tests - one that the multi-label
form is accepted, one that an undeclared label inside a cell list still
fires, so the fix cannot have made the rule permissive. 26 self-tests.

### Corrected

`CLAUDE.md` gave clenshaw's speedup as 68-310x. That was the range over
the two configurations quoted; the third (nmax 120, 2000 points, which
finished after the release) is **356x**, and direct there is 59.2x,
bitwise. The range is now 68-356x and names all three configurations.

Test count: 308 methods / **320 runs**.

## [5.1.0] - 2026-09-09 - two summations for synthesisPoints, faster one by default

WP2 step 2, row B2. `shLowLevel.synthesisPoints` gains `Method`,
`ClenshawFrom` and `MaxMemGB`. Nothing existing changes its answer: the
default path at the point counts the old tests use is BITWISE identical.

### What was wrong

`synthesisPoints` aggregated per point, and per point it built the FULL
`(nmax+1)x(nmax+1)` Legendre matrix - calling `legendreALF` with a SCALAR
latitude, though it accepts a vector - then formed three more full
matrices before reducing. Four allocations and four passes over `nmax^2`
per point. v5.0.3 measured the cost: 2.28 s for 2000 points at nmax 60,
1.14 ms per point, 36.65 s of a 4:51 CI job.

### Two paths, and the faster one is the default

| `Method` | what it does | cost in the point count |
|---|---|---|
| `"direct"` | builds `Pbar`, contracts per point; the recursion now runs once per CHUNK of points instead of once per point | linear |
| `"clenshaw"` | reorders the sum by ORDER and evaluates each order's degree sum by Clenshaw summation; `Pbar` is never formed | nearly flat |
| `"auto"` (default) | `"clenshaw"` at or above `ClenshawFrom` points, `"direct"` below | - |

Measured in the committed oracle `tools/dev/validate_points_clenshaw.py`
(numpy, same recursion coefficients as `legendreALF.m`), against the
per-point code it replaces:

```
nmax=60  P=2000    direct  52x faster    clenshaw 310x faster
nmax=60  P=200     direct  61x           clenshaw  68x
```

and the crossover between the two shipped paths:

```
             P:    10     50    100    200    400
nmax=60      direct wins  ---------|  clenshaw wins
nmax=120     direct wins  ---------|  clenshaw wins
```

The crossover sits between 100 and 200 points at BOTH degrees - it barely
moves with `nmax`, which is what makes one scalar `ClenshawFrom` (150)
defensible instead of a rule in `nmax`. **That number is measured in
numpy, not on MATLAB**, and the help says so; `tests/perf_baseline.csv`
now budgets both paths so A8 can replace it.

### `"direct"` is bitwise, `"clenshaw"` cannot be

Batching only moves the `legendreALF` call out of the loop, and the
recursion is elementwise in latitude, so the chunk size cannot change a
bit - pinned by `testSynthesisPointsChunkingIsBitwise`, which drives
`MaxMemGB` to one point per chunk and to all points at once and compares
with `isequal`. That is why the pinned reference values in
`testSynthesisPoints` still hold unchanged.

Clenshaw sums the same terms in a different order, so **bitwise agreement
is arithmetically impossible** and no test asserts it. WP2's "bitwise, or
<= 4 eps" acceptance does not apply to it, and pretending otherwise would
have meant writing an assertion that cannot hold. What is asserted
instead: agreement with `"direct"` to 5e-14 relative (about 2x the worst
case the oracle measures), and - in the oracle - that neither path
dominates the other against a 60-digit `mpmath` reference:

```
lat      direct   clenshaw
 89.5   12.9 eps   89.0 eps
 12.3   52.7 eps   59.5 eps
 62.0    4.4 eps    0.5 eps
```

Both sit within tens of eps, which is what a sum of `nmax^2/2` terms with
cancellation costs. Clenshaw is better at three of six points and worse
at the near-pole one.

### Budgets

`synthesis_points_n60` now forces `"clenshaw"` at 2000 points, and its old
2.2829 s baseline is RETIRED rather than kept: it measured the path that
no longer runs, so it would have passed vacuously. A new
`synthesis_points_n60_direct` budgets `"direct"` at 200 points - a
GNSS-network-sized station list, the regime `"auto"` routes to `"direct"`.
Both sit in `NO_BASELINE` until A8 measures them.

### Not changed, and why

The GRID default was already the faster one: `shSynthesis`'s `"auto"`
picks the FFT path for any uniform full-circle longitude vector, and
v5.0.3 measured that at 1.40x the direct path. Nothing to do.
`shSynthesisDeformation` does NOT share the pathology - it calls
`legendreALFDeriv` once with the whole latitude vector already.

Test count: 308 methods / **319 runs** (305/315 + 3 tests + 1 budget).

## [5.0.3] - 2026-09-09 - WP2 step 1: the budgets go live

v5.0.2 built the harness and measured nothing; A8 has now measured it.
The ten `PERFBASE` lines from the `runAllTests (self-hosted)` run at
`f6d5529` are committed as `tests/perf_baseline.csv` rows and
`NO_BASELINE` is **empty**, so every budget asserts instead of filtering.

| benchmark | median (s) | min (s) |
|---|---|---|
| `synthesis_points_n60` | 2.2829 | 2.26137 |
| `legendre_n720` | 0.284863 | 0.281566 |
| `legendre_n360` | 0.0883628 | 0.0873293 |
| `analysis_rings_n60` | 0.069954 | 0.0687578 |
| `leakage_1iter_n24` | 0.0231963 | 0.0222312 |
| `legendre_n96` | 0.012063 | 0.01194 |
| `synthesis_direct_n60` | 0.0042843 | 0.0039347 |
| `synthesis_fft_n60` | 0.0030666 | 0.0029098 |
| `apply_ddk_n96` | 0.0018487 | 0.0016592 |
| `kalman_step_p40` | 0.0016711 | 0.0016445 |

A8, R2026a, 15 repeats each, median of the samples.

### A9 is only PARTLY closed, and the factor is why

The budgets now guard something, which they did not yesterday. But 3x
catches a workload that blows up - a lost fast path, an accidental
O(n^2) - and it does **not** catch the 1.3x creep A9 actually names. The
finding is downgraded, not closed, and the comment on `BudgetFactor`
says so in the file rather than only here.

Tightening it needs a statistic this release cannot supply. The run
measured the WITHIN-run spread: median/min <= 1.043 over 15 repeats for
every workload above 20 ms, 1.114 for `apply_ddk_n96` at 1.8 ms where
the timer dominates. A budget needs the BETWEEN-run spread, and one run
cannot measure it. Several runs of logged medians can, and then the
factor is a decision with evidence behind it.

### Two things the first measurement contradicted

**`synthesisPoints` is the hot spot, by a wide margin.** 2.28 s against
1.7-88 ms for everything else, and 36.65 s of the job's 4:51 - because
it calls `legendreALF` once PER POINT (1.14 ms per point at n60). That
is B2's premise, now measured rather than inferred, and it is the
strongest candidate for WP2 step 2.

**The FFT path is 1.40x, not "5-20x".** `benchSynthesisFFTvsDirect`
carried the claim "typical gain: 5-20x at nmax=60, 1 deg" - exactly the
configuration measured here, which came out 4.28 ms direct against
3.07 ms fft with the cache primed identically. The old figure was never
measured against the direct path in the same cache state, which is the
only comparison that isolates the FFT. The comment now carries the
measured number and its provenance.

### Verification

`runAllTests (self-hosted)` at `f6d5529`: **315 runs, 301 passed, 0
failed, 14 filtered** - the count prediction matched EXACTLY for the
seventh release running, per class as well as in total (Contract 74,
Correctness 159, Performance 22, Robustness 53, Science 7). Counts
parsed from the 315-row results table, not a log tail. The 14 filtered
were the 4 real-data fixtures plus the 10 budgets, which is what this
release removes: the next run should filter 4.

## [5.0.2] - 2026-09-09 - WP2 step 1: speed becomes measurable

A9 recorded that the toolbox has no speed budget, so a 1.3x regression in
`legendreALF`, `shSynthesis`, `shAnalysisGrid`, `applyDDK`,
`leakageCorrect` or the Kalman step ships unnoticed. WP2 says: make speed
measurable first, and build only what the measurement justifies. This is
the measuring half. **No numerical behaviour changes and no public call
changes** - the release is a PATCH.

### Ten budgets, one harness

`testPerformance` gains `testSpeedBudget`, a parameterised method with one
run per workload:

| benchmark | what it bounds |
|---|---|
| `legendre_n96` / `_n360` / `_n720` | the Holmes-Featherstone recursion at 181 / 91 / 31 rings |
| `synthesis_direct_n60` | the reduction only - the Legendre cache is primed first |
| `synthesis_fft_n60` | the FFT-along-longitude path |
| `synthesis_points_n60` | 2000 scattered points |
| `analysis_rings_n60` | exact per-order ring analysis |
| `apply_ddk_n96` | order-block filter application |
| `leakage_1iter_n24` | one `leakageCorrect` step |
| `kalman_step_p40` | a 12-epoch VAR(1) filter chain |

Each is timed 15 times after one untimed warm-up, and the MEDIAN is
compared against `BudgetFactor` (3) times the baseline for this machine
in the new, committed `tests/perf_baseline.csv`.

### A budget cannot be asserted before it has been measured

So it is not. A machine with no baseline row FILTERS the budget rather
than failing it, and prints a `PERFBASE,...` line that is already a
`perf_baseline.csv` row. That is how a machine is adopted: run once, paste
the lines, and the budgets go live on the next run. All ten sit in the
gate's `NO_BASELINE` backlog today, which is honest debt - a filtered
budget guards nothing.

Baselines are per machine rather than ratios against a calibration
workload. A ratio is machine-independent only when the calibration scales
like the workload, and no one calibration tracks both a BLAS-bound
reduction and a memory-bound recursion.

The factor 3 is WP2's specification, not a measured spread - there was no
baseline to measure a spread against, which is precisely what A9 records.
Every run logs the median AND the min, so the choice can be replaced with
the observed spread rather than inherited.

### The bookkeeping is gated

`tools/dev/perf_baseline_audit.py` (new, in `ci.yml`) checks that the CSV,
the `budgetCase` parameter and the `workload()` switch agree: row shape and
uniqueness, no orphan baselines, field names equal their values, **every
declared case has a case arm**, and the backlog holds neither a stale entry
nor a case that already has a baseline. The arm rule is the one that earns
its place - a case without an arm passes every other static check here and
then fails on the runner with `unknownCase`. 24 self-tests, every rule
fault-injected in both directions; the backlog rule is asserted with a
TEMPORARY entry, per A14.

### Fixed: `count_tests.py` counted a char-valued parameter twice

Adding `budgetCase` made the counter say 19 where the runner runs 10. Its
rule was "count every quoted word followed by a comma", which is right only
while the parameter's VALUES are not themselves quoted. It now counts
struct FIELDS through `help_audit.struct_field_names` - the one authority
in this repository for that question - instead of a second, weaker parser
of the same fact. That is A17's lesson: the failure would otherwise have
surfaced as a red `--executed` check on the runner, a full CI round later.

### Files

- `tests/testPerformance.m` - `testSpeedBudget`, `workload`, the two
  fixtures, `machineId`, `baselineFor`, `appendPerfLog`
- `tests/perf_baseline.csv` - new, committed (the machine-local
  `perf_log.csv` stays git-ignored)
- `tools/dev/perf_baseline_audit.py`,
  `tools/tests/test_perf_baseline_audit.py` - new
- `tools/dev/count_tests.py`, `tools/tests/test_count_tests.py` - the
  cardinality fix and its regression tests
- `.github/workflows/ci.yml` - the new gate step

Test count: 305 methods / **315 runs** (305 + `testSpeedBudget` x 10).

## [5.0.1] - 2026-09-09 - WP6 stage 3: 24 duplicate pages retired

The hand-written page per package function existed because
`doc_sync_audit`'s COVERAGE check demanded a NARRATIVE mention of every
entity, and before WP6 there was nowhere else to put one. There is now:
`html/ref/` carries a generated page per entity. 24 of the 50
hand-written pages were restating theirs.

### Chosen by measurement, not by file name

A17 left a warning: a narrative page can be the only mention of an
entity, so deleting by name drops entities out of COVERAGE silently. So
the set was computed - retire a page only if every entity stays covered
afterwards. That is true of **30**; the other 6 are the last narrative
mention of 11 entities (`fetchITSG.html` for `listITSG`,
`shCoefficients.html` for six of its own methods, ...) and stay.

Of the 30, six read as narrative rather than reference and were kept by
the WP's own rule ("keep narrative pages (chains, theory)"):
`standardChain` is a chain, `shSeries` a class overview, and
`legendreALF`, `seaLevelFingerprint`, `eofAnalysis` and `slepianBasis`
carry theory. **24 were retired.**

COVERAGE therefore keeps its current meaning untouched - the question of
what it should become does not arise, because nothing it guarantees was
given up.

### Retired, not deleted

Every inbound link and every `helptoc.xml` target was REPOINTED at
`html/ref/<entity>.html` before the files were removed, so nothing a
reader could reach became unreachable. Four category headers pointed at
a page in their own group that is now gone
(`Reading and writing` -> `readSINEX`, `Filtering` -> `tvANS`,
`Spectra and diagnostics` -> `comparison`,
`Regional and geophysical analysis` -> `leakage`).

Two link rewrites nearly escaped: the See-also lines of `shSynthesis` and
`legendreALF` use `href='...'` with single quotes, and the first pass
only matched double ones. Checking both quotings found them.

`removeGIA.html` was the one page whose short name matched two entities
(`shSeries.removeGIA` and `shClimatology.removeGIA`) - a `setdefault`
picked one by accident. Reading the page settled it: it documents both
routes with `ts.removeGIA(gia)` first, so it points at
`ref/shSeries_removeGIA.html` by decision now rather than by luck.

50 hand-written pages -> 26. No entity lost coverage; the test count is
unchanged.

## [5.0.0] - 2026-09-09 - Every class identifier names its method (A21b)

**BREAKING.** The 29 two-part identifiers the three classes raised are
now three-part. A caller could not tell which of the 35 methods raised
`shSeries:badInput`; now they can.

### BREAKING - what changes for a caller

Any `catch`, `verifyError` or `warning('off', ...)` naming one of these
must be updated. **One old identifier maps to several new ones** - that
is the point of the change, and it is why a repo-wide replace would have
been wrong (the A15 lesson, applied per raise site rather than per file):

| was | now |
|---|---|
| `shClimatology:badIndex` | `shClimatology:periodic:badIndex` |
| `shClimatology:badInput` | `shClimatology:amplitudeMap:badInput`<br>`shClimatology:fromCoef:badInput` |
| `shCoefficients:badIndex` | `shCoefficients:addDegree1:badIndex`<br>`shCoefficients:setCoefficient:badIndex`<br>`shCoefficients:vec:badIndex` |
| `shCoefficients:badInput` | `shCoefficients:mtimes:badInput`<br>`shCoefficients:operands:badInput`<br>`shCoefficients:shCoefficients:badInput`<br>`shCoefficients:times:badInput` |
| `shCoefficients:badTruncation` | `shCoefficients:truncate:badTruncation` |
| `shCoefficients:constantsMismatch` | `shCoefficients:operands:constantsMismatch` |
| `shCoefficients:epochMismatch` | `shCoefficients:operands:epochMismatch` |
| `shCoefficients:epochNotInTable` | `shCoefficients:addDegree1:epochNotInTable`<br>`shCoefficients:applyTN14:epochNotInTable` |
| `shCoefficients:noC30` | `shCoefficients:applyTN14:noC30` |
| `shCoefficients:noEpoch` | `shCoefficients:addDegree1:noEpoch`<br>`shCoefficients:applyTN14:noEpoch` |
| `shCoefficients:noSigmas` | `shCoefficients:crossover:noSigmas` |
| `shCoefficients:sizeMismatch` | `shCoefficients:operands:sizeMismatch` |
| `shSeries:ambiguousRange` | `shSeries:select:ambiguousRange` |
| `shSeries:badBasis` | `shSeries:basinAverage:badBasis` |
| `shSeries:badIndex` | `shSeries:at:badIndex` |
| `shSeries:badInput` | `shSeries:minus:badInput`<br>`shSeries:select:badInput`<br>`shSeries:shSeries:badInput` |
| `shSeries:badRange` | `shSeries:range:badRange` |
| `shSeries:badTruncation` | `shSeries:truncate:badTruncation` |
| `shSeries:constantsMismatch` | `shSeries:shSeries:constantsMismatch` |
| `shSeries:emptyRange` | `shSeries:mean:emptyRange` |
| `shSeries:epochMismatch` | `shSeries:minus:epochMismatch`<br>`shSeries:restore:epochMismatch` |
| `shSeries:missingOp` | `shSeries:basinAverage:missingOp` |
| `shSeries:nanInSeries` | `shSeries:stack:nanInSeries` |
| `shSeries:noBreaks` | `shSeries:trendBreaks:noBreaks` |
| `shSeries:noEpoch` | `shSeries:climatology:noEpoch`<br>`shSeries:filter:noEpoch`<br>`shSeries:mean:noEpoch` |
| `shSeries:noFiles` | `shSeries:fromFolder:noFiles`<br>`shSeries:read:noFiles` |
| `shSeries:sizeMismatch` | `shSeries:minus:sizeMismatch`<br>`shSeries:restore:sizeMismatch`<br>`shSeries:shSeries:sizeMismatch` |
| `shSeries:sparseWindow` | `shSeries:mean:sparseWindow` |
| `shSeries:tooFewEpochs` | `shSeries:climatology:tooFewEpochs`<br>`shSeries:mean:tooFewEpochs` |

Three identifiers were already three-part and are unchanged:
`shSeries:removeAlias:tooShort`, `shSeries:toGrid:empty`,
`shSeries:toGrid:tooLarge`.

### The middle segment: a method, or a named shared check

Normally it is the raising **public method**, the constructor included
(`shCoefficients:shCoefficients:badInput`) so the rule has no exception
to remember.

The four private helpers are the deliberate exception. `checkPair` and
`checkEpochs` guard the operand pair for the binary operators;
`assertClean` guards the stacks for six methods; `rangeToYears` parses a
`Range=`. Naming *them* in the identifier would make renaming a private
function a breaking change, so they carry a stable CONCEPT segment
instead - `operands`, `stack`, `range` - and the help says so rather
than naming the helper.

The distinction that matters survives it: `plus` reaches
`shCoefficients:operands:epochMismatch`, `minus` does not, because
`minus` calls only `checkPair`. A test pins both halves.

### The gate now proves the middle segment

Three-part alone would be a spelling convention. `error_id_audit.py`
checks that the middle segment names either a method of that class or one
of the three declared shared checks, so `shSeries:att:badIndex` fails.
`TWO_PART_OK` is drained to empty and, per A14, its self-test asserts the
MECHANISM with a temporary entry rather than looping over a set that can
no longer fail.

### Verification

47 raise sites rewritten, scoped to the function each sits in; 58 source
lines and 58 help rows. 47 test pins were remapped **by line**, each to
the method the call under test actually reaches - `ts.mean(Range=...)`
raising a bad range goes to `shSeries:range:badRange` (the shared parser)
while the empty-window case goes to `shSeries:mean:emptyRange`. Three
`html/` references and one line of `make_guide.py` followed.

No numerical behaviour changed; no signature changed; the test count is
unchanged at 304 methods / 305 runs.

**One pin was wrong and CI caught it** (`testGravisChainsContract`, first
run of PR #99). The two chain pins were mapped to
`shSeries:fromFolder:noFiles` by tracing the call graph -
`twsChain` -> `gravisL2B` -> `fromFolder` - but `fromFolder` asserts
`isfolder` and then DELEGATES to `shSeries.read`: the temp folder EXISTS,
so that guard passes and the empty folder is caught by `read`'s pattern
check. Corrected to `shSeries:read:noFiles`. Which guard fires depends on
the input, not only on which function is called.

The other 45 pins were then re-verified against the guard ORDER of every
method they exercise. `noFiles` is the only reason raised by two
functions that a test reaches through a delegation, so this was the one
instance of the shape rather than the first of several.

**A second pin was wrong too, and the enumeration is why.** The grep that
listed the pins to rewrite used `[A-Za-z]*` for the reason segment, and
`shCoefficients:noC30` **has digits in it** - so it was never listed, was
never rewritten, and `testTN14IDs` went red on the next run. The
verification grep repeated the same character class and repeated the same
blind spot.

### Added - `error_id_audit.py` PINS: tests may only name real identifiers

Nothing read `tests/` before. The rule collects every identifier the
toolbox can raise - including the prefixes handed to
`+shLowLevel/private/normalizeMonthList`, and the few identifiers test
helpers raise themselves - and reports any pin outside that set. 184 pins
checked.

Its reach is stated in its own docstring because it is narrower than it
sounds: it catches a pin naming an identifier that exists NOWHERE (the
`noC30` case), and **not** a pin naming a real identifier the call under
test cannot reach (the `fromFolder`/`read` case), which needs per-call
guard analysis. One of the two red rounds is preventable here; the other
is not.

The first version reported three findings, all false - `rmIfFolder`
*raises* its identifier rather than pinning it, and two are built by a
private helper from a prefix its callers pass. Narrowed rather than
"fixing" the tests. Then fault injection found a worse bug: harvesting
prefix literals from `tests/` as well let the bad pin be read as its own
prefix, so the rule went quiet on the very defect it was written for.
Prefix literals now come from the toolbox only, and a prefix covers only
what sits below it (`shSeries:read` does not validate `shSeries:readFoo`).
Six self-tests, one of which pins the stated limit.

## [4.0.3] - 2026-09-09 - The class surface joins the identifier gate (A21a)

A21's documentation half. The three class files raised **32** error
identifiers with no `Error identifiers` section anywhere; 31 public
methods now carry one, and `error_id_audit.py` reads them. The rename
half (A21b) stays open and is now a measured, shrinking backlog rather
than a paragraph.

### Added - per-method `Error identifiers` blocks in the three classes

A class needed a different instrument, not a wider loop. Identifiers
belong to METHODS, and a user catching one calls a PUBLIC method - but
several are raised by PRIVATE helpers (`shCoefficients.checkPair`,
`checkEpochs`, `shSeries.assertClean`, `rangeToYears`), where `help`
cannot reach them. So the rule follows REACHABILITY, one hop: a public
method documents what it raises itself plus what the private helpers it
calls raise. `shSeries.filter` therefore documents `shSeries:nanInSeries`
even though `assertClean` is what raises it.

One hop is **checked, not assumed**: if a private helper ever calls
another private helper the gate says the rule has become too shallow,
rather than quietly under-reporting.

The map is derived from the source, and it caught a real distinction that
prose would have blurred: `shCoefficients.plus` calls `checkEpochs`,
`minus` does **not** - a difference between two months has no single
epoch, so `minus` sets `epoch = NaN` instead of refusing. Both help
blocks now say so, and a new contract test pins the half that was
untested (`plus` raising `shCoefficients:epochMismatch` was pinned;
`minus` *not* raising it was not, so a stray `checkEpochs` call in
`minus` would have passed every test).

### Added - A21b: the two-part identifiers are a named backlog

29 of the 32 are two-part (`shSeries:badInput`), so a caller cannot tell
which of the 35 methods raised; only three
(`shSeries:removeAlias:tooShort`, `shSeries:toGrid:empty`,
`shSeries:toGrid:tooLarge`) name their method. Making the rest
three-part is MAJOR - `testContract` pins the current names - so they sit
in `TWO_PART_OK`, which may only shrink and whose size the gate prints
every run. A two-part identifier **not** in that set is a new defect and
fails the gate.

### Fixed - one constant was answering two different questions

`CLASS_FILES` was both the list of files the CLASS pass reads and the
skip-list `surface()` uses to keep class files out of the root-function
pass. A self-test that emptied it to focus on the package therefore
re-admitted `shSeries.m` as a ROOT function owning
`shAnalysis:shSeries:*`, and the suite went red for a reason that had
nothing to do with what it was testing. The skip-list is now its own
frozen constant. This is A17's shape again: when one name answers two
questions, the answers drift apart silently.

A missing class file is now a finding rather than a traceback.

### Verification

Nine new self-tests fault-inject every class rule in both directions - a
private helper's identifier left undocumented, a documented identifier
the method cannot reach, a missing section, a foreign identifier, a
two-part identifier outside the backlog, and the second-hop depth guard.
30 tests in `test_error_id_audit.py`, all green.

## [4.0.2] - 2026-09-09 - Every raised identifier is documented

A20 closed. The 61 package files that raised error identifiers without
an `Error identifiers` help block now carry one - **208 identifiers**,
each description written against the raise site and its guard, not
against the message string. The backlog in `tools/error_id_audit.py` is
drained to empty and the DOCUMENTED rule holds with no exemption.

### Added - `Error identifiers` blocks in 61 `+shLowLevel` files

The count in `CLAUDE.md` said 165. It was 208; nobody had measured it.
Every block was checked against the code before it was written: the
writer refused any file whose documented set was not exactly the set the
file raises, so a description can be wrong in its wording but not in its
name.

### Added - the root functions, and the identifiers no scan could see

`demo_shAnalysis` and `setup_shAnalysis` gained blocks too, and the gate
now reads them. `setup_shAnalysis` turned out to raise five identifiers
**no static scan of the file can find**:

    warning("shAnalysis:setup:no" + locs(li, 1), ...)

built from the option name. Read as a literal it invents
`shAnalysis:setup:no`, which nothing raises - and that is precisely what
the extended gate reported first. A concatenated literal is now treated
as a PREFIX: the help must document at least one identifier under it,
because the gate cannot enumerate them. All five (`noSeriesFolder`,
`noMasconFile`, `noGravisFolder`, `noDDKFolder`, `noTestDataFolder`) are
named in the help.

### Changed - `demo:*` identifiers get the toolbox namespace

`demo:casesFailed` and `demo:unknownCase` had no namespace at all. They
are now `shAnalysis:demo:casesFailed` and `shAnalysis:demo:unknownCase`,
consistent with `shAnalysis:setup:*`. This is a PATCH, not a break:
neither was documented anywhere (`grep` over help, `html/`, the guide
and the changelog found only the raise site), and the toolbox's rule is
that an undocumented identifier is not part of the contract - the same
reasoning that made `shSynthesisDeformation`'s rename a PATCH in
v3.33.1. The two `testContract` pins were updated with them.

### Changed - the backlog self-test no longer goes vacuous when drained

`test_backlog_only_names_files_without_a_section` iterated over
`UNDOCUMENTED`; emptying it would have left an assertion that cannot
fail. That is exactly how A14's `test_legacy_name_tolerated` sat broken
for a release. The mechanism is now asserted with a TEMPORARY entry, and
two more tests fault-inject the no-section rule on a synthetic tree -
one that must fire, one that must pass once the section is added.

### Fixed - `tvANSFilter`'s stranded `Options` section

Writing the blocks turned up a help block whose `Options` section sat
BELOW a `Claude (...)` credit line, separated from the other sections.
The credit line is reunited with the provenance footer, so `Options`
now sits with `Inputs` and `Outputs` where a reader looks for it.

### Known - A21: the three class files are outside every gate

Measured, not estimated: `shCoefficients`, `shSeries` and
`shClimatology` raise **32 identifiers** between them and carry **no**
`Error identifiers` section. 29 of the 32 are two-part
(`shSeries:badInput`), so a caller cannot tell which of the 35 methods
raised. The gate does not read them, and says so in its own output
rather than implying a reach it does not have: a class needs a
per-method owner rule, which is a different instrument, not a wider
loop. Recorded as A21 in `CLAUDE.md`.

## [4.0.1] - 2026-09-09 - The option-values gate, and a correction to the record

A19 closed, and one decision in `CLAUDE.md` corrected because it was
wrong in a way that blocked work.

### Added - `tools/dev/option_values_audit.py` (A19)

`opApply` documented `mode` values (`'apply' | 'applyT'`) that its
arguments block rejected (`'forward' | 'transp'`). v3.34.1 fixed the row
but left the general check unbuilt: the obvious implementation - grep
help lines for quoted words near an option name - produced 25 hits of
which 24 were false.

The gate reads `api_data.py` instead, where each option already carries
its own `allowed` set and its own help row, so the scoping problem
disappears. The rule is deliberately narrow: only a row's LEADING
ALTERNATIVES RUN - a pipe-separated list of quoted values, the house way
of writing the choices - is compared against `mustBeMember`. A row
without one documents prose and is not checked. 42 of the 61
value-restricted options carry such a run.

Verified against the historical defect rather than asserted: fed
`opApply`'s pre-v3.34.1 row the gate fires; fed the fixed row it is
silent; and it stays silent on the three shapes that made the naive
version lie - another option's value quoted in prose
(`SignalMode='isotropic'` inside `Blocks`' row), a parenthetical inside
the run (`'auto' (default) | 'on'`), and a numeric member list
(`[60, 96]`).

### Fixed - CLAUDE.md said CI could not serve as an oracle. It can.

The 2026-09-08 tier decision recorded that WP3/WP4/WP5 could not
proceed because "the Python oracle can be written but nothing can be
checked against it". That is false, and it blocked four packages for a
day. The oracle is a Python script that runs in any sandbox; the
comparison is a MATLAB test that runs on the self-hosted runner through
CI. Neither half needs a local interpreter - which is exactly the
mechanism §2 has always described. WP3, WP5 and WP7 wait on approval,
not on a bridge. Only WP2's two-machine speed calibration genuinely
needs the acceptance machine.

### Changed - §3.4's invariant is now literally true

It claimed the gate list "must equal what `ci.yml` runs" while omitting
`count_tests.py` and including four local-only tools. It now says
CONTAIN, names the four (`mlint_lite`, `check_api`, `api_audit`,
`attribution_sweep`) as having no CI step by design, and lists
`count_tests`.

All four releases (3.33.1, 3.34.0, 3.34.1, 4.0.0) are merged; the
verification board's Merged column is no longer pending.

## [4.0.0] - 2026-09-09 - Every identifier owned, every option in house casing

WP1. The last six v1-era functions leave `inputParser`, and every error
identifier is owned by the function that raises it. Approved as a hard
break with no deprecation shim.

### BREAKING - what actually changes for a caller

Read this list literally: it is shorter than the diff suggests, and the
reason is measured rather than assumed.

**Error identifiers.** Seventeen raise sites used an identifier
belonging to another function. Any `catch`/`verifyError` on these must
be updated:

| was | now |
|---|---|
| `shSynthesis:badInput` (in shSynthesis) | `shLowLevel:shSynthesis:badInput` |
| `shSynthesis:badP`, `:badMethod` | `shLowLevel:shSynthesis:*` |
| `shSynthesis:missingLoveNumbers`, `:badQuantity`, `:heightInvalid` | `shLowLevel:kernelFactors:*` |
| `shSynthesis:badInput` (in shSynthesisGradient) | `shLowLevel:shSynthesisGradient:badInput` |
| `shSynthesis:missingLoveNumbers` (in seaLevelFingerprint) | `shLowLevel:seaLevelFingerprint:missingLoveNumbers` |
| `shReadGFC:*` (4), `shEvalGFCT:*` (3) | `shLowLevel:<fn>:*` |
| `shSpectralCrossover:missingField` | `shLowLevel:shSpectralCrossover:missingField` |
| `shAnalysis:geoMapRequired` | `shLowLevel:requireGeoMap:geoMapRequired` |
| `shCoefficients:toGrid:fullFieldAsMass` | `shLowLevel:gridHandover:fullFieldAsMass` |
| `shLowLevel:writeAnimation:badExtension`, `:mp4Unsupported` | `shLowLevel:writeFrames:*` |

Two of those were wrong in a way worth naming. `gridHandover` is called
by BOTH `shCoefficients.toGrid` and `shSeries.toGrid`, so the old
warning name misattributed it for every series user. `writeFrames`
raised `shLowLevel:writeAnimation:badExtension` next to its own
`shLowLevel:writeFrames:badSize` - inconsistent inside one function.

**One option rename.** `n0` -> `Nmin` on `shDegreeRMS`, and `N0` ->
`Nmin` on `shOrderRMS`, `shCoefficients.degreeRMS` and
`shCoefficients.crossover`. Three spellings for "lowest degree
included" are now one.

**The other option renames break nothing.** `quantity` -> `Quantity`,
`nmin`/`nmax` -> `Nmin`/`Nmax`, `method` -> `Method`, `minOrder` ->
`MinOrder`, `sigmaC` -> `SigmaC`, `ax` -> `Ax` and the rest are
case-only, and MATLAB matches Name-Value names case-insensitively -
measured against R2026a and documented in `nv_casing_audit.py`. Old
call sites keep working; a contract test pins that the old spelling
returns the identical numbers, not merely that it runs.

### Fixed - the gate that could not see the problem

`nv_casing_audit.py` reads ARGUMENTS BLOCKS, so for these six functions
it had nothing to look at: they parsed with `inputParser`, which is
itself case-insensitive, and lowercase names survived v3.33.0's sweep
unnoticed. It now rejects the construct outright, with the line number
read from the real file.

`plotSHSpectrum` was the one non-mechanical conversion: it used
`p.UsingDefaults` to let a legacy `field` option override `Quantity`,
and an arguments block has no equivalent. `Field` keeps its behaviour
through an empty-string sentinel, documented as such.

### Added - `tools/error_id_audit.py`

Three rules, each fault-injected: ownership (no backlog - the sweep made
it true everywhere), raised implies documented, documented implies
raised. 61 files predate the "Error identifiers" convention and sit in a
named backlog the gate reports every run and that only shrinks.

It found three gaps in files this release never touched: `readSHM`
documented 3 of the 5 identifiers it raises, `hydroExtremeIndex` 2 of 3.

Its first version reported five ownership violations of which four were
false - `tvANSFilter` COMPARES against another function's identifier in
a catch, `fetchITSG*` pass their own name as a prefix to a helper. It
now matches only the identifier argument of error/assert/warning, and
both shapes are pinned in its self-test.

### Fixed - the arguments block that was not first (found by CI)

`plotSHSpectrum` normalises a single spectrum into a cell before doing
anything else. WP1 put its `arguments` block where `inputParser` had
been, which is BELOW that guard - and MATLAB requires the block to be
the first statement. The function no longer parsed, so every call to it
raised, and five tests went red on a green `mlint_lite`.

`mlint_lite.py` gains **R6**: an arguments block must be the first
executable statement of its function. It fires on the exact file CI
rejected, stays silent when the same guard sits below the block, and is
pinned by `tools/tests/test_mlint_lite.py` - the first self-test that
tool has had.

### Unchanged - the numerics

No numerical line moved. Each conversion replaced the parsing preamble
and kept the local variable names, so the body diffs to nothing: for
`shGaussianWeights` and `shDestripe` the body is byte-identical from the
first computed line onward, and for the rest the only body change is the
option access itself. 301 -> 304 tests.

## [3.34.1] - 2026-09-08 - A public function nothing could see, and coverage by name

Two instruments were measuring less than their silence suggested. No
numerical behaviour changes; one help block corrected.

### Fixed - a public function was invisible to the API extractor (A17)

`gridHandover` continues its signature across two lines with `...`.
`api_extract.py` matched the signature on a single raw line, so the file
parsed to nothing and the entity never reached `api_data.py`. It
therefore had no reference page - while `apiReference.html` told the
reader the handover bundle was "as built by shLowLevel.gridHandover,
which documents every field", linking nowhere.

`refpages_audit.py`'s COVER check compares the generated pages against
`api_data.py`, so it reported zero findings: the gate's reach was
defined by the bug it should have caught.

Four parsers of "what is a public entity" live in this repository. Two
were blind the same way - `api_extract.parse_function_file` and
`doc_sync_audit.parse_one` - and they agreed with each other. That is
why the new guard checks the FILESYSTEM, not a second parser's opinion:
MATLAB requires a file to define the function it is named after, so
every `+shLowLevel/X.m` owes exactly one entity `shLowLevel.X`.

- both parsers join `...` continuations and read the help block after
  the LAST continuation line. Both skip comment lines inside a
  continuation, as MATLAB does - joining one let a `(base MATLAB only)`
  in a help line supply the closing paren and parse to nonsense. Found
  while fault-injecting, not by review.
- `api_extract.py` refuses to write `api_data.py` when any public file
  produces no entity.
- `doc_sync_audit.py` gains a SURFACE check, fault-injected both ways.
- `tools/tests/test_api_extract.py`: 5 of its 7 tests fail against the
  pre-fix extractor; the 2 that pass cover shapes never broken.

122 package entities (was 121), 200 reference pages (was 199).

### Fixed - `opApply` documented option values it rejects

Its Inputs row offered `'apply' | 'applyT'`; the arguments block accepts
only `'forward' | 'transp'`, which the same help block's syntax lines
had right. A caller following the row got a validation error. Found
while writing the test that now pins both modes.

### Added - `tools/dev/name_coverage.py`, and the 32 tests that satisfy it (A10)

The audit found thirteen package functions no test file mentioned, by
hand. Nothing measured it, so the set could only grow - and it was
larger than recorded: **22 public class methods** were unnamed too
(A18), among them every operator (`plus`, `minus`, `uminus`, `mtimes`,
`times`) and `disp` on all three classes.

The gate strips comments first, so a name in a `% see also` line does
not count. Its claim is deliberately narrow and it says so in its own
output: naming is not exercise. Operators get no exemption - they are
callable by name, and a test that checks `plus(a, b)` against `a + b`
is stronger than one that checks either alone.

New tests assert a property each function's own help states:

- `icgemDate2Year` hand-computed epochs across a leap and a non-leap
  year, and the documented `< 1.8e7` pass-through
- `pctile` against the documented order statistic, the median identity,
  clamping, non-finite handling and empty input
- `gridHandover` reads FieldKind off the C00 identity - the same grid is
  labelled full, anomaly, unknown or mixed by C00 alone
- `shDestripe` annihilates a polynomial in degree, passes `m < MinOrder`
  through bitwise, and leaves a subset with too few degrees alone
- `shGaussianFilter` is exactly the weights applied by degree
- `shSpectralCrossover` finds the first crossing and returns NaN for none
- `vceRescale` is quadratic in the residuals and inverse in the
  covariance - powers of two, so the identities are bitwise
- `opApply` is the true adjoint of its forward operator, dense and
  block-diagonal
- `buildSignalCov` is scale-equivariant
- `plotBasinSeries`, `plotCovariance`, `spectrum`, `triangle` return
  graphics handles; `disp` prints the identifying facts
- `shClimatology.fromCoef` honours its documented row layout, one
  distinct constant per row so a swapped mapping is visible

268/269 -> 300/301 tests, and the self-hosted runner executed **exactly
301** - the prediction matched. 296 passed, 4 filtered (the optional
real-data fixtures), 1 failed: `testCompareDelegatesToCompareSolutions`
gave `compareSeries` 8 epochs where it requires >= 12 common ones. That
guard is an `error` a hundred lines into the function, not part of its
`arguments` block, so reading the signature was not enough. Fixed by
giving the fixture two full years.

### Fixed - `demos.xml` carries the version stamp, and nothing said so

The first push of this release failed CI on `make_demos.py --check`:
`demos.xml` is generated from the demo registry AND stamped with the
toolbox version, so bumping to 3.34.1 made it stale on its own. It was
regenerated by neither of CLAUDE.md's two lists, because `make_demos`
appeared in neither - eleven local gates were green while `gates` was
red.

- `doc_sync_audit.py`'s VERSION check now covers `demos.xml` too, so the
  gate that owns version agreement owns all four stamped artifacts
  (`apiReference.html`, `html/ref/*`, `demos.xml`, the guide PDF).
  Fault-injected both ways: a stale stamp and a missing one.
- CLAUDE.md §3.4's gate list is now stated to equal `ci.yml` and names
  `make_demos --check` and `name_coverage`; §3.9 names all four
  generators.

## [3.34.0] - 2026-09-08 - Struct fields, a correct test count, and reference pages

Second half of the documentation-rot work, and the check that closes the
class of defect v3.33.1 fixed by hand. No numerical behaviour changes.

### Added - `help_audit.py` now checks struct output FIELDS, both ways

v3.33.1 fixed eight help blocks that named struct fields the code does not
produce (`tn.t`, `info.condest` for `condEst`, `out.q16/q50/q84`, ...). It
fixed them by reading; nothing stopped the next one. Now:

- **documented => assigned.** Every field a help block lists must be
  assigned somewhere in that function. Runs where the help gives a field
  LIST (the house form: the struct row ends with `fields`, one field per
  deeper-indented line - the spelling already dominant in the tree).
- **assigned => documented.** Every field the function writes on a
  documented struct output must appear in its Outputs section. Needs no
  parsing, so it runs on prose rows too - and it found **55** fields the
  code returns and `help` never named.

`help_audit.py` reports its own reach rather than implying full
coverage, and that reach is now total: **96 documented struct outputs -
79 with a field list verified against the source, 17 naming the function
that builds them, 0 prose.** A mechanical prose-to-list rewrite was
written, inspected and **discarded** because it produced confident
nonsense (`'full-blocks'` split at a field name, a nested struct array's
subfields hoisted to the top level), so all 79 were converted by hand
against the source, with the gate verifying every name as it went.

That conversion found **three more** help blocks naming fields that do
not exist, on top of the eight v3.33.1 fixed by reading - eleven in all:

| Function | Documented | Reality |
|---|---|---|
| `shReadGFC` | `model.tide` | the tide system is `model.header.tide_system`, which is where `shCoefficients.read` gets it |
| `readSINEX` | `snx.header` | no such field |
| `gravisL2B` | `rep.files` | no such field |

**Five defects in the checker itself**, each caught by reading its output
against the source before trusting it, each now with a regression test:

- MATLAB's `'` is transpose after a value, so
  `struct('areaFraction', w' * mask, ...)` desynchronised the scan and
  hid three of `basinKernel`'s four fields. Converting that row first
  would have made a **correct** help block look wrong.
- `struct()` alternates name and value: the `"zeroField"` in
  `struct(..., 'stoppedBy', "zeroField", ...)` is a VALUE, and counting
  it invented a field `leakageCorrect` does not have.
- the field-row grammar demanded two spaces before the type, so
  `epochStart, epochStop (T x 1 double)` broke the parse.
- the list marker was case-sensitive, so a preamble ending `Fields` was
  not seen.
- a classdef's local functions were excluded from a method's source,
  hiding the struct `shSeries.mean` builds in `meanWindowInfo`.

The delegation marker was tightened as well: a bare "from" or "see"
appears in ordinary prose ("removed from the file", "from the ocean-fit
residual") and had silently excused five rows that were in fact
documented here and verifiable. It now requires an explicit reference to
the function that builds the struct.

### Fixed - 55 struct fields the code returns and the help did not name

Found by the new direction. Among them:

- `shIndex`: the help named `nmax` and `Nmin`. The FIELDS are `Lmax` and
  `minDegree` - the help had copied the option spellings - and `pos`, the
  reverse map, was undocumented. `shIndex` is the toolbox's canonical
  vector ordering, so this one was in everybody's way.
- `trendBreaks`: 15 of its 17 fields were described only in the prose
  paragraph, and the Outputs section called them `shCoefficients` when
  they are plain `(n1 x n1)` doubles.
- `tvANSFilter`: `op.layout`, `op.blocks`, `op.sBlocks`, `op.detLeverage`,
  `op.detResVar`, `info.vce`, `info.sigmaNote` - including which of the
  two operator layouts is filled, which a caller must know.
- `httpFetch.transport` was documented as if always present; it exists
  only on the websave-fallback path. The correction says so.
- `shReadGFC.variableTerms` (documented as two words, "variable terms"),
  `header`, `modelname`; `shOrderRMS`'s `err*` glob spelled out;
  `eofAnalysis`, `eofSeparate`, `fetchDDK`, `fetchGAX`, `fetchICGEM`,
  `fetchITSG`, `fetchITSGBackground`, `basinScaling`, `oceanChain`,
  `kalmanFilter`, `seaLevelFingerprint`,
  `shSynthesisGradientTensor`.

### Added - `tools/dev/count_tests.py`, and a corrected test count

The predicted test count was **wrong**, on a green run. `grep -c '^function
test' tests/*.m` counts the script-based harness entry point (`function
tests = testCorrectness`) as a test, and misses every `bench*` method and
every parameterised expansion. It said 261, and this release predicted 262;
the runner ran **268**.

`count_tests.py` reports methods and runs per class, expands
`TestParameter` blocks, and with `--executed N` exits non-zero on a
mismatch. It reproduces the self-hosted run exactly. CI prints it beside
the run. The corrected figures: Correctness 135, Contract 61, Robustness
53, Science 7, Performance 11 methods / 12 runs - **267 methods, 268 runs**,
of which 3 filter out when the optional real-data fixtures are absent.

### Fixed - three defects in the new checker, found by reviewing its own output

Recorded because each produced confident, wrong findings before it was
caught, and each is the kind of thing a gate is supposed to prevent:

- an `id(src)`-keyed cache returned another file's field set (CPython
  reuses ids after garbage collection) - 6 invented findings;
- a class method was given the WHOLE class file as its source, so a
  variable named `op` or `info` in a sibling method counted - 57 invented
  findings;
- quoted literals inside a call NESTED in `struct(...)` were read as field
  names, so `struct('created', string(datetime('now', 'Format', ...)))`
  looked like three fields - 4 invented findings.

### Added - WP6 stage 1: a reference page per entity

`doc` integration was a monolith: 196 entities had a dedicated page only
inside the 304 KB `apiReference.html`, the 50 hand-written pages used five
heading vocabularies, and each inlined its own `<style>` (A7, A8).

- **`tools/dev/make_refpages.py`** emits `html/ref/<entity>.html` for all
  198 public entities plus an index - 199 pages - in the MathWorks order:
  Syntax, Description, Examples, Input Arguments, Name-Value Arguments,
  Output Arguments, Error Identifiers, Version History, See Also. Every
  page carries every section; a section with nothing to say says so,
  because a missing section and an empty one are different claims. Nothing
  on a page is hand-written: all of it derives from `api_data.py`, which is
  parsed out of the help blocks, so a page cannot drift from its source.
- **`html/shAnalysis.css`**, one stylesheet for the look: system font
  stack, 14 px body, `#0076a8` links, a grey Syntax panel, bordered
  argument tables, collapsible examples in plain HTML `<details>` (no JS).
- **`api_extract.py`** now also captures `Error identifiers` (14 files) and
  `See also` (15), neither of which is derivable. `See Also` is completed
  from the entities a help block actually names - measured, not asserted.
- **`tools/dev/refpages_audit.py`**, the gate: pages match what the
  generator would write now, every entity has a page and no page outlives
  its entity, every section present and in order, no heading outside the
  skeleton, no inline `<style>`, every relative link resolves. Seven
  fault injections in `tools/tests/test_refpages.py`.
- `helptoc.xml` reaches the new index, so the pages are visible in the
  Help browser.

Two of WP6's own premises did not survive measurement, and are recorded
rather than papered over:

- **Per-entity Version History from the changelog** was to be included
  "only if the match rate is > 80 %". A loose name match reaches 81 % but
  matches `filter` against releases that never mention it; a match
  anchored on the qualified name reaches 74 %. Below the bar either way,
  so every page links `CHANGELOG.md` and says why it does not claim a
  per-entity history.
- **"Functions by the existing tag categories"**: there are no tag
  categories in the data. Deriving them from `helptoc.xml` mapped 163 of
  198 entities and put 75 in one catch-all. The index groups by what IS
  derivable - classes, class methods, package functions, root functions,
  plus an A-Z list - and topic categories wait for an editorial decision.

### Added - WP6 stage 2: one look, one vocabulary, an Examples tab

- **The 50 hand-written pages now link `html/shAnalysis.css`.** They had
  carried an inline `<style>` block each - and only **two were distinct**:
  49 were byte-identical and one more sat in the generated
  `apiReference.html`. One stylesheet copied fifty times is exactly what
  A8 described. `make_apiref.py` emits the link instead of the block, so
  the copy cannot come back with the next regeneration.
- **One spelling per structural heading.** 46 headings were renamed:
  `See also` -> `See Also` (34), `Outputs` -> `Output Arguments` (7),
  `Example` -> `Examples` (6), `Inputs` -> `Input Arguments`,
  `Inputs / Outputs` -> `Arguments` (5, where one table genuinely covers
  both). Narrative pages keep their own page-specific headings; only the
  structural ones are pinned.
- **`demos.xml`** (`tools/dev/make_demos.py`), derived from the case
  registry inside `demo_shAnalysis.m` so a case cannot exist in one and
  not the other. 16 cases, each with a `demo_shAnalysis("Dnn")` callback.
- `doc_sync_audit.py` gates all three: no inline `<style>` anywhere in
  `html/`, every page links the stylesheet, structural headings use the
  house spelling, and `demos.xml` matches the registry both ways. Six
  more fault injections.

`setup_shAnalysis(Docs=true)` already ran `builddocsearchdb` on `html/` -
the audit's A7 missed it, so no second option was added; its help now
says the index covers `html/ref/` too and explains why the binary index
is not committed.

### Fixed - A13: the kilometre conversion was a hidden constant

`resolutionMap` turned its half-widths from degrees into kilometres with
a hardcoded `R = 6371`, against the toolbox's own rule that physical
constants are defaults, not literals. It is now the `RadiusKm` option -
default unchanged, so no number moves - documented as the MEAN Earth
radius, which is the right choice for a great-circle distance and is
deliberately not the coefficients' reference radius (6378.1363 km).

`testResolutionMapRadiusIsAChoice` pins both halves metamorphically, so
no tolerance is involved: the angular half-widths do not depend on the
radius, every kilometre figure scales exactly with it, and `anisotropy`
- a ratio of two of them - is invariant. It also asserts the struct's
field names, and it takes `resolutionMap` off A10's list of functions
never named in a test. Declared test count 268 methods / 269 runs.

### Fixed - ten tests whose temp folder a killed run could poison

`runAllTests (self-hosted)` failed on
`testProvenanceSidecarsDoNotBreakTheRoundTrip` with

```
[Warning: Directory already exists.]
[Warning: ...\shx_sidecar_176639289\plain.gfc: 1502 of 1891 coefficient
 records (degrees 0..54) for the header's max_degree 60 - truncated file?]
Error ID: 'shSeries:sizeMismatch'
All epochs must share nmax (epoch 3 has 54, expected 60)
```

Two CI runs had been **cancelled** mid-suite by the next push. A killed
MATLAB process runs no `onCleanup`, so a half-written `plain.gfc` stayed
behind in the runner's temp folder - and the folder name,
`sprintf('shx_sidecar_%d', randi(1e9))`, is reproducible whenever the rng
state at that point is, so the next run walked straight back into it and
read the truncated file as a third epoch.

Ten tests built their temp path that way. They now use `tempname`, which
is the pattern this repo already documents in `tests/rmIfFolder.m` and
uses in eight other places: it returns a path that does not exist, so no
leftover can be found and no two runs can collide. The test was never
skipped, widened or given a tolerance - it isolates itself now, which is
what it should always have done.

To be exact about what this change did and did not do: the leftover had
already cleared itself by the next run, which was green **before** this
fix existed. It is hardening against recurrence, not the cure for a red
build. The failure was intermittent in practice but not a flake - the
mechanism is deterministic given its precondition.

### Fixed - two gates that were not looking where they claimed

- `attribution_sweep.py` globbed `html/*.html`, so it kept reporting 50
  pages while 199 more existed one directory down. Now recursive: 249.
- `doc_sync_audit.py` and `testHelpBrowserTocIsComplete` both compared
  `helptoc.xml` targets against bare filenames, so any target in a
  subfolder read as a dead link. Both resolve targets against `html/` now.

### Added

- `tools/tests/test_help_audit.py` grows to 17 tests; `test_count_tests.py`
  (7) and `test_refpages.py` (14) are new. Every rule fault-injected and
  paired with a clean-tree assertion. Five self-test suites, 81 tests.

## [3.33.1] - 2026-09-08 - Documentation rot, and the gates that missed it

Hygiene release: no numerical behaviour changes. Every finding below was
green on all nine gates for weeks - the gates checked that a section was
present, never that it appeared once, and never that what it claimed was
what the code returns.

### Fixed - 65 help blocks carried two sections of the same kind

`fix_help.py` appended a generated `Outputs`/`Options`/`Inputs` section
below the hand-written one instead of editing it, in every run since
2026-08-12. `help_audit.py` reads the FIRST such section, so the second
was invisible to it - and the two disagreed. Where they disagreed, the
code was consulted and both were often wrong:

- `readTN14`: the help promised a field `tn.t`. There is none; the
  reader returns `epoch`, `epochStart`, `epochStop`.
- `parseGraceFilename`: `center`, `product`, `release`, `year`, `month`,
  `nmax` and "raw tokens" were documented. The parser returns
  `productType`, `epoch`, `epochStart`, `epochStop` and nothing else.
- `resolutionMap`: documented as returning an `(nlat x nlon)` double of
  half-widths. It returns a struct - `psiHalfDeg`, `azDeg`, `kmMean`,
  `kmMin`, `kmMax`, `anisotropy`.
- `shAnalysisGrid`: every documented `info` field name was wrong -
  `condest` for `condEst` (MATLAB is case-sensitive on fields), `nObs`
  for `nPoints`, and a `kaula` field that does not exist. `method`,
  `unobservedDegrees`, `regularized` and `residRMS` were undocumented.
- `basinDeconvolve`: the two `Ridge` descriptions contradicted each
  other and neither matched the code, which solves
  `(A'A + lam^2 I) \ (A' v)` with `lam = Ridge*||A||_2` - relative to
  the spectral norm, which is the whole point of the v2.1 change.
- `buildSignalCov`: `info` was documented as `mode` and `iterations`,
  neither of which exists; it holds `c` (P x NIter+1, one column per
  iteration) and `varMap`.
- `vceRescale`: documented as returning `(nBands x T)`. It returns
  `(T x 1)`; `tvANSFilter` assembles the band matrix itself.
- `mcPropagate`: `q16/q50/q84` percentiles were documented and are not
  computed; `N` was undocumented; `samples` is conditional on
  `KeepSamples`.
- `shSynthesis`: the fourth output `P` is EMPTY in latitude-banded mode
  (`MaxMemGB` exceeded) - undocumented, and a caller passing it back in
  would have been puzzled.
- `readMascon`, `shSynthesisDeformation`, `errorMap`, `rescaleGMR`,
  `buildNoiseCov`, `shCoefficients.analysis` and 35 class methods:
  corrected against the source in the same sweep. `errorMap`'s
  description had been truncated mid-sentence since its first commit.

### Fixed - error identifiers a caller could not catch by owner

`shSynthesisDeformation` raised `shSynthesis:badInput` and
`shSynthesis:missingLoveNumbers`. It now raises
`shLowLevel:shSynthesisDeformation:badInput` and
`:missingLoveNumbers`, documented in its own `Error identifiers` block
and pinned by `testDeformationIDs` (which also checks the identifier
survives the `shCoefficients.deformation` delegation). Not a breaking
change: these identifiers were never documented.

`kernelFactors`, `shSynthesisGradient` and `seaLevelFingerprint` still
raise `shSynthesis:*`; those identifiers ARE documented and pinned by
tests, so renaming them is a major-version change and stays with the
identifier sweep of the next major release.

### Fixed - documentation that had aged

- The shipped workflow guide PDF was stamped v3.28.0 - five releases
  behind, missing the BREAKING `MinDegree`/`MaxDegree` -> `Nmin`/`Nmax`
  rename. Rebuilt, and `doc_sync_audit.py` now reads the PDF's page-1
  running head and fails when it disagrees with `Contents.m` (standard
  library only: reportlab writes ASCII85 + Flate streams).
- `docs/apiReference.html` was a byte-identical copy of
  `html/apiReference.html`. Nothing wrote it, nothing read it, nothing
  compared them. Deleted; `doc_sync_audit.py` now fails on any HTML page
  outside `html/`.
- `README.md` said CI pulls the orphan branch `testdata`. CI has pinned
  the tag `fixtures-YYYY-MM` since v3.26.1. The README now points at
  `ci.yml` rather than naming a tag it would have to keep in step.
- `Contents.m` was 1149 lines, 74 "New in v..." sections out of
  chronological order, printed in full by `help shAnalysis`. Now 78
  lines: product line, classes, quick start, internals, tests, and a
  pointer to this file. Nothing was lost - v2.1, v2.2, v2.3, v2.4,
  v2.4.1 and v2.4.2 existed only in `Contents.m` and are written up
  below in this release.
- Section headings in help blocks now use one vocabulary:
  `Name/value options:` -> `Options` (5 files), `Errors` -> `Error
  identifiers` (2), `Output`/`Examples` -> `Outputs`/`Example` in
  `setup_shAnalysis`.

### Added - the checks that would have caught all of it

- `help_audit.py` (v3.0.2): a house-vocabulary section may appear at
  most once per help block; no section may appear below the provenance
  footer, where the doc builder stops reading; near-miss spellings are
  named with the spelling to use. Prose sub-headings inside a
  description are explicitly not sections.
- `tools/tests/test_help_audit.py`: nine tests, each rule fault-injected
  (fires on the defect) and paired with a clean-tree assertion.
- `fix_help.py` refuses to create a second section of a kind that
  already exists, and says so instead of writing.
- `api_extract.py`: a row in an `Outputs` section starts at the
  section's own indent; anything deeper is a continuation. Six entities
  (`httpFetch`, `obpChain`, `oceanChain`, `poleTideConvert`,
  `readMascon`, `readTN13`) had their struct sub-fields parsed as
  separate outputs, so the generated reference invented outputs the
  functions do not have.
- CI runs `tools/tests/` at last. The three gate self-tests committed in
  v3.32/v3.33 had never run in CI; one of them
  (`test_legacy_name_tolerated`) had been broken since the v3.33.0
  casing sweep drained `LEGACY` to empty, and nothing said so. It now
  asserts the mechanism instead of a member name.

### Changed

- `CLAUDE.md` records the audit findings this release closes, the ones
  it leaves open, and the four it adds (A12-A15).

## [3.33.0] - 2026-09-05 - Name-Value casing, and one real rename

### BREAKING: `MinDegree` and `MaxDegree` are gone

`shLowLevel.shIndex`, `designFilter`, `synthesisPoints`, `vceRescale`
and `shSeries.filter` took `MinDegree`; `readLoveNumbers` took
`MaxDegree`. Three spellings existed side by side for one concept -
`Nmax`/`nmax`, `nmin`, and `MaxDegree`/`MinDegree` - so they are merged
onto `Nmax` and `Nmin`.

This one IS a breaking change, and unlike the rest of this release it
cannot be papered over: MATLAB's case-insensitive Name-Value matching
rescues `nmax` -> `Nmax`, but `MinDegree` and `Nmin` are different
names. Update calls:

```matlab
idx = shLowLevel.shIndex(96, MinDegree = 2);   % before
idx = shLowLevel.shIndex(96, Nmin = 2);        % after
kn  = shLowLevel.readLoveNumbers(f, MaxDegree = 96);   % before
kn  = shLowLevel.readLoveNumbers(f, Nmax = 96);        % after
```

`VCEMinDegree` in `tvANSFilter` is unchanged - a different option, and
already conformant.

### Name-Value casing standardised (not breaking)

Declarations follow the MATLAB Coding Standards rule for Name-Value
arguments, UpperCamelCase: `quantity`, `gravisFolder`, `idx`,
`sigmaC`, `sigmaS`, `ax`, `minOrder`, `polyOrder`, `windowLength`,
`tYears`, `nmax`, `nmin`, `n0` become `Quantity`, `GravisFolder`,
`Idx`, `SigmaC`, `SigmaS`, `Ax`, `MinOrder`, `PolyOrder`,
`WindowLength`, `TYears`, `Nmax`, `Nmin`, `N0`.

Existing code keeps working: Name-Value matching is case-insensitive,
measured on R2026a rather than assumed.

Domain notation stays lowercase and is now documented as a deliberate
exception: `hn`, `kn`, `ln`, `a`, `f`, `omega`, `rho_ave`,
`rho_water`, `lat`, `lon`. `GM` and `R` were already uppercase.

Struct FIELD names are untouched. `info.nmax`, `info.quantity` and the
`n0` returned by `shCoefficients.crossover` are outputs, not arguments.

### New gate: `tools/nv_casing_audit.py`

Two Name-Value names differing only by case compile and run with no
warning, leaving one unreachable - and a casing sweep is exactly the
operation that creates such a pair. The gate also rejects new
non-conformant names and new prefix relations, which partial matching
turns into `AmbiguousInputName` at call time.

### Fixed: the documentation toolchain could not run outside one sandbox

Nine scripts in `tools/dev` carried absolute paths from their authoring
sessions. `make_apiref.py` wrote the regenerated API reference into a
clone from an earlier session while `doc_sync_audit` reported the
untouched page as stale. All paths now derive from `__file__`, with
`SHX_ROOT`, `SHX_API_DATA`, `SHX_GUIDE_OUT`, `SHX_GUIDE_ASSETS` and
`SHX_PORT` as overrides.

## [3.32.3] - 2026-08-23 - review of v3.29-v3.32.2, with fresh eyes

A model change is a review opportunity: everything since v3.28.0 was
re-read for mathematical, implementation and documentation defects,
with the mathematics re-derived rather than re-tested.

### Verified (container, by derivation)
The kernel table against the standard formulas (Wahr 1998 mass kernels,
free-air `n-1`, disturbance `n+1`, Trr `(n+1)(n+2)`), the radial
exponents n+1/n+2/n+3 and their chained identities, the sinc period-mean
derivation (trend and sine terms vanish for a centred T0; whole years
kill annual and semi-annual exactly), the design-matrix column
alignment of the `u` weights in `shSeries.mean`, the cofactor
u'(A'A)^-1 u, the per-coefficient sigma denominator, `select`'s
index/range disambiguation, `flatten` ordering, the FieldKind identity
and the stack-wide colour extremes. **No defect found.**

### Verified (acceptance machine, real data)
- The deferred whole-year check from the v3.28 handover:
  `mean(Range=[2021 2022], Estimator="model")` on 12 ITSG GRACE-FO n96
  months gives attenuation **exactly 0** for the annual and semi-annual
  terms, and agrees with the arithmetic mean to **2.2e-16** - the
  "round-off" claim in the help, measured true (ITSG epochs sit on
  exact twelfths, which is what makes the two estimators coincide).
- The deferred n96 runtime: synthesis 0.04 s, gradient 0.07 s on a
  180x360 grid. Not a concern.
- The gradient against a 5-point finite difference of `synthesis` on
  the real n96 field: north 1.1e-11, east 5.0e-12 relative; the up
  channel against the closed identity at 1.3e-14.
- Physics, not self-consistency: the deflection of the vertical from
  the n=2..96 field is **5.35 arcsec RMS**, where the published
  truncated value sits - a check against knowledge outside the toolbox.

### Fixed
- `html/shSynthesisGradient.html`: the advection note said "with
  Units='perRadian', dphi/dt is dq.north/r directly". Dimensionally the
  /r belongs to the **perMeter** form (v = mu*dq.north in m/s, dphi/dt
  = v/r); the point of perRadian is that an angular mobility needs no
  metric factor at all. The sentence now says so, and says it was
  wrong.
- `README.md` never mentioned the geoMap relationship: a reader calling
  `g.map` met an error the front page never hinted at. Four sentences
  now state who draws, that a gate keeps it that way, and that the
  dependency is checked rather than required.

### Noted, deliberately not changed
- `gradient` documents that geodetic input is converted and the vector
  resolved in the geocentric local frame (up to 0.19 deg of meridian
  convergence) - present and correct in the help since v3.31.0.
- `gravity_anomaly` keeps its `n-1` kernel down to degree 0, where a
  full field produces a large spurious term; unchanged since long
  before this window, out of scope here.

## [3.32.2] - 2026-08-23 - the acceptance run refuted the fix that installed it

v3.32.1 added `acceptance_geomap` and, in the same release, a fix for
the frame-capture defect. Its first run against the **installed**
v3.32.1 failed: `[401 656; 365 640; 365 640]`. The instrument refuted
the repair it shipped alongside.

### Fixed
- **`writeAnimation` frame capture, third attempt.** Under rapid figure
  churn the layout passes through a transient state - 401x656 against a
  target of 640x365, changing **both** dimensions - and `settleFigure`
  watched only the height, so it declared that state settled after three
  polls. It now watches the full `Position` and requires five stable
  polls, and `captureFrame` validates every capture against the **pin**,
  the size each frame of that video must have, rather than against
  whatever the figure reports at the moment of asking.

  Three hypotheses were measured and **refuted** before this one was
  adopted:

  | hypothesis | measurement | verdict |
  |---|---|---|
  | cold-session warm-up | clear geoMap's cache, redraw | refuted - a warm draw failed, cleared ones did not |
  | a geo.map layout difference | figure `Position` over 20 draws | refuted - never left 640 wide |
  | `set(Position)` not sticking | 12 isolated draws | refuted - stuck 12 of 12 |

  In isolation with a longer settle the fault did not appear at all, 12
  of 12. That is precisely why a timing-based repair could not be
  trusted: more waiting makes the symptom rare, not absent.

- `shLowLevel.requireGeoMap`'s message now mentions `savepath`. An
  `addpath` made by a setup script may last only for that session, and
  someone who has installed geoMap and still meets this error deserves
  the next step rather than a restatement of the problem.

### Notes
- **This is the third attempt at one defect, and the evidence behind the
  first two was too thin.** v3.32.0 shipped on four clean draws, v3.32.1
  on three. The base rate is about **1 in 6 exports**, so three runs
  pass by luck more often than not. This release rests on **32 exports
  across 8 acceptance passes, 96 frames, all byte-identical at
  365x640** - and on three refuted hypotheses rather than one confirmed
  guess.
- The instrument earned its place immediately: without
  `acceptance_geomap`, v3.32.1 would have shipped a defect that no
  static gate and no CI run can see, because CI has no geoMap.
- The geoMap path not surviving a MATLAB restart is **not a defect
  here**: `geoMapSetup` currently adds the path for the session only,
  and that is tracked in the Mapping project. The message change above
  is generic and stays correct once it is fixed.

## [3.32.1] - 2026-08-23 - the acceptance run, installed

### Added
- **`tools/dev/acceptance_geomap.m`** - the checks CI structurally
  cannot run, now repeatable instead of living in one session's
  scrollback. It exercises every path where shAnalysis hands work to
  geoMap, then takes geoMap off the path and runs the mirror half.

  Both halves, because **neither machine runs both**. CI has no geoMap,
  so it only sees the refusals. A developer machine has geoMap, so it
  never reaches them - `testNoMapIsDrawnHere` returns early when geoMap
  is present, and a bad `shSeries` call inside that very test once
  survived a 264-test acceptance run and failed CI.

  The frame-geometry check runs the shipped `writeAnimation` three times
  rather than re-implementing its loop. A check that copies the loop
  tests its own copy and drifts from the real one - which is the same
  mistake, one level up, as the two renderers this toolbox just removed.

### Fixed
- **`writeAnimation` was racing geo.map's resize, and v3.32.0's fix was
  luck.** "One fresh figure per frame" was measured over four draws,
  came back 365 px every time, and shipped. The first acceptance run
  produced **365, 340, 365** - 340 being the unresized starting height,
  i.e. `getframe` capturing before the resize landed. A single `drawnow`
  is not a barrier for it.

  The first repair attempt was a settle loop, and it had a hole worth
  recording: **two equal polls of a figure whose resize has not started
  look exactly like a settled one.** Frames are now captured only after
  the height has been stable across three consecutive polls and at least
  four polls have run, and every later frame is **pinned** to the first
  frame's settled size - equal by construction, not by timing. Nine
  consecutive exports of the same data are now byte-identical at
  165770 B, 365x640; before, one in three differed.

- `shLowLevel.writeFrames` records `frameSize` in the provenance
  sidecar. Two exports of the same data differed by 0.4% in bytes and
  nothing on disk could explain it. That difference turned out to BE the
  defect above; the geometry is now a recorded fact rather than
  something to infer from a file size.

### Notes
- Verified on the acceptance machine (R2026a Update 4, geoMap 2.0.541):
  **10 of 10, three passes in a row**, plus the nine byte-identical
  exports. A race deserves more than one green run.
- CI still cannot see any of this, and that remains permanent rather
  than temporary. The split is now written down in the script itself.

## [3.32.0] - 2026-08-23 - geoMap is the single cartographic authority

Matthias's decision, taken on the open question left at the end of
v3.31.0. This toolbox no longer draws maps.

### Removed
- **`shLowLevel.plotSHMap`.** It had its own coastlines, its own colour
  limits and two projections, beside sixteen certified against PROJC in
  geoMap - one fact with two implementations, and no instrument
  comparing them.

  **The scope was measured before anything was deleted, and it was
  smaller than the handover that raised it said.** That document counted
  "693 lines of plotting-ish files" by NAME. By behaviour:
  `shLowLevel.errorMap` and `shLowLevel.resolutionMap` contain **zero
  graphics calls** - they compute formal-error and resolution fields and
  return arrays. The renderer was 114 lines in one file. Both computing
  functions stay untouched.

### Changed
- `shCoefficients.map` synthesizes through `toGrid` and hands the result
  to `geo.map`. It draws nothing. Its `Units`, `Title`, `Projection`,
  `Colormap`, `CLim` and `Coast` options are gone: **geoMap's option
  table is not restated here.** `CRS` picks the projection, `Basemap`
  configures the raster element, and `GeoArgs` forwards verbatim -
  mirroring another toolbox's options is how two renderers drift apart,
  and `geo.map` applies the same rule to its own elements.
- `shLowLevel.writeAnimation` likewise: shAnalysis assembles the stack
  and writes the container, geoMap draws every frame. It now refuses
  **before** synthesizing - a two-minute stack followed by an
  undefined-function error is the wrong order to discover a missing
  dependency in. The fixed stack-wide colour scale is unchanged, still
  the robust 98th percentile, and now recorded in the sidecar beside the
  data's true range.
- `demo_shAnalysis` routes its fourteen map panels through one local
  helper that draws with geoMap or says the panel was skipped. A demo
  that silently degrades to a lesser picture teaches the wrong thing.

### Added
- `shLowLevel.requireGeoMap` - the ONE place that checks for geoMap, so
  the dependency has one spelling and one error message, and a future
  drawing entry point cannot invent a third way of failing. The message
  shows how to draw the numbers without geoMap. The dependency is
  **checked, not required**: shAnalysis still runs on base MATLAB with
  no toolboxes, and only the two drawing entry points need it.
- `shLowLevel.writeFrames` - a video container written from ready-made
  RGB frames, with no graphics at all. This split is why CI still tests
  codec selection, extension validation, frame rate and the provenance
  sidecar: those are the parts that have bitten before, they never
  needed a renderer, and folding them in with the drawing would have
  taken them out of the suite along with it.
- **`tools/dev/no_map_renderer.py`, wired into CI.** Deleting a renderer
  is a one-line commit; keeping it deleted is a gate. The coastline
  check is universal and has no exemptions - run against the retired
  file it fires three times on the `coastlines`/`coastlat`/`coastlon` it
  loaded. The projection check is a secondary signal and cannot tell
  "names a projection" from "computes one", since both are quoted
  strings, so it is skipped for the short list of files that forward a
  name to geoMap; that list is the mechanism and is stated as such.

- `docs/apiExamples.json` - the committed example registry the suite
  executes - lost its `shLowLevel.plotSHMap` entry, and the `g.map` and
  `writeAnimation` entries are marked `run: false` with examples that
  show the current API. They need geoMap, which the CI machine does not
  have. `writeFrames` is registered as a runnable one in their place.
  This file is a second place documentation lives, and only CI saw that
  it had gone stale: the static gates read help text and HTML, not it.
- `tools/dev/mlint_lite.py` gained rule **R5**: a `name = value`
  argument before a `{:}` expansion in the same call. MATLAB requires
  name-value arguments to come last, so `f(a, Name = v, rest{:})` is a
  **parse** error - and a parse error inside a classdef takes the whole
  class down. Both `geo.map` call sites in this release were written
  that way, `shCoefficients.m` stopped loading, and forty unrelated
  tests failed in CI for one line. `mlint_lite` counts brackets and
  blocks; it does not parse MATLAB grammar, so it could not see this
  until it was told to look.

### Verified on hardware
The MATLAB bridge came back and the gap named below was closed. On the
acceptance machine (R2026a Update 4, geoMap 2.0.541), against a shadow
checkout of this branch: the v3.30 gradient identities, the v3.31 bridge
and latitude fix, `requireGeoMap`, `g.map`, `writeAnimation` and
`writeFrames` - **10 of 10**, with `g.map` returning a real geo.map
handle struct and `writeAnimation` writing a 166 kB video whose frames
geoMap drew.

**It found one defect that no static gate could have.** `writeAnimation`
reused one figure across frames, and `geo.map` fits the figure to the
map it drew while `clf` does not undo that, so the figure RATCHETED:
six successive draws of the same three grids came back 365, 387, 407,
424, 439 and 453 pixels tall, and the second frame failed the
preallocated stack. Pinning `Position` at the top of each iteration does
not help - `geo.map` resizes after it, to a different height each time
(364.6, 340, 386.9, 365). A fresh figure per frame is deterministic: 365
every frame, for different data. There is now also a named
`shLowLevel:writeAnimation:frameSizeChanged` instead of MATLAB's
`subsassigndimmismatch`, because frames of different sizes are not a
video and the reason should say so.

**The two runs cover different halves, and neither is redundant.** A bad
`shSeries` constructor call inside `testNoMapIsDrawnHere` itself passed
the 264-test acceptance run and failed CI: that test returns early when
geoMap is present, so everything past the early return executes only on
a machine WITHOUT geoMap. It was then reproduced here by taking geoMap
off the path deliberately, rather than by pushing and waiting.

### Notes
- **This is API-breaking for anyone drawing maps.** `g.map` now needs
  geoMap on the path and no longer takes the display options above;
  `shLowLevel.plotSHMap` is gone. `g.toGrid` needs no geoMap at all and
  hands over everything a figure needs, which is what the error message
  points at.
- **CI still cannot see the drawing**, and that has not changed: the CI
  machine has no geoMap, so it checks only that the entry points raise
  `shAnalysis:geoMapRequired`, that the animation refuses before writing
  anything, that the container mechanics pass and that the renderer
  stays deleted. The drawing itself is covered by the acceptance run
  above and by geoMap's own suite, and that split is now permanent
  rather than temporary.

## [3.31.0] - 2026-08-23 - the cartographic bridge, and a latitude that lied

### Fixed
- **`shCoefficients.synthesis` returned the CONVERTED latitudes.** With
  `LatType="geodetic"` it converted the input to geocentric, evaluated
  there - correctly - and then handed the *converted* values back as its
  `lat` output. A caller who fed that straight into a map drew a field
  against a coastline it no longer matched, and nothing in either
  toolbox could notice, because both sides were internally consistent.

  The size, computed independently and agreeing with the measurement
  made from the map side: **0.1924 deg = 21.4 km** north-south at +-45,
  0.1240 deg = 13.8 km at 70 N. On a global 17 cm sheet that is under a
  fifth of a millimetre and beneath the spherical approximation already
  in use. On a **regional** map 20 deg tall - Greenland, West
  Antarctica, the Amazon, which is what these fields are made for - it
  is **1.6 mm**, a systematic shift of the whole signal relative to the
  coast, in the direction a reader takes for a real geophysical offset.

  `synthesis` now returns the latitudes in the convention that was
  asked for. **This changes a return value**: code that relied on
  getting geocentric latitudes back from a geodetic call must convert
  explicitly with `shLowLevel.geodetic2geocentric`. The field itself is
  unchanged, and a test pins that.
- `shCoefficients.gradient` had the same defect in `info.lat`, freshly
  introduced in v3.30.0. It now reports the latitudes as given plus
  `info.latType`, so a mismatch can be refused downstream instead of
  drawn.

### Added
- **`shCoefficients.toGrid` and `shSeries.toGrid`** - the synthesized
  field together with what it is: `Units`, `LatType`, `Quantity`,
  `ProductType`, `Name`, `Epoch`, `Source`, `FieldKind`, `C00`, `Zmin`,
  `Zmax`, `Zmean`, `History`. Handover is then one line:

  ```matlab
  b = g.toGrid(lat, lon, quantity = "ewh", kn = kn);
  G = geo.grid(b.lon, b.lat, b.Z, Source = b.Source, Units = b.Units);
  ```

  `LatType` defaults to `"geodetic"` here, unlike `synthesis`, because
  coastlines are geodetic and a map is what this output is for. The
  choice is stated in `b.LatType` rather than assumed.

- **`FieldKind` is read off an identity, not guessed.** `C(1,1)` is the
  degree-0 coefficient: exactly 1 for a field normalised by GM/R that
  carries the total mass, 0 for a residual. So `"full"` and `"anomaly"`
  are facts about the coefficients, and anything in between is reported
  as `"unknown"` rather than decided. A **mass** quantity synthesized
  from a full field warns
  (`shCoefficients:toGrid:fullFieldAsMass`): measured, twelve GSM
  solutions meaned and synthesized to EWH give 1.16e7 m, which is the
  static field expressed as water, not a mass change - and which a
  symmetric colour scale renders as one flat colour. `Units = "m"` is
  true of both and distinguishes nothing.

- `Zmin`/`Zmax`/`Zmean` are carried as measured numbers rather than
  turned into a verdict. For `shSeries.toGrid` they span the **whole
  stack**, which is the fixed colour scale an animation needs: a
  per-frame scale shows the scale changing and the signal not.

- `shLowLevel.gridHandover` - the metadata assembly both bridges share,
  so the two cannot describe the same field differently.

### Changed
- `shLowLevel.kernelFactors` gained a third output, the quantity's
  **units**, set in the same `switch` case that sets its kernel. The
  unit belongs to the quantity; retyped by hand at a toolbox boundary it
  was one more thing a user could get wrong silently.

### Notes
- **Not verified on hardware.** The MATLAB MCP bridge was still
  unavailable; static gates, the independent latitude computation and CI
  only.
- The remaining item from the same measurement is **not** a defect in
  any file and is not decided here: `shLowLevel.plotSHMap`,
  `errorMap` and `resolutionMap` are a second cartographic renderer,
  roughly 690 lines, in two projections. Whether it is routed through
  the map toolbox, kept deliberately as a dependency-free quick-look and
  said so in its help, or kept silently, is Matthias's decision. Only
  the third option is certainly wrong.

## [3.30.0] - 2026-08-22 - north/east/up gradient of any quantity

### Added
- `shLowLevel.shSynthesisGradient` and the class method
  `shCoefficients.gradient`: the spatial gradient of any quantity
  `kernelFactors` knows, resolved in the local north-east-up frame, on a
  grid (`Mode="grid"`) or at scattered points (`Mode="points"`).
  The horizontal components come from the exact `dPbar/dphi` of
  `shLowLevel.legendreALFDeriv`; the up component from the quantity's own
  upward-continuation exponent.

  The motivating gap: the only vector field the toolbox could produce was
  elastic load deformation, and that is a vector because horizontal
  displacement carries `l'_n` - not because gradients were available. Any
  scalar quantity has a gradient; only one quantity had a deformation.

- `Units="perRadian"` returns `r` times the gradient in every component
  (`dQ/dphi`, `sec(phi) dQ/dlambda`, `dQ/d(ln r)`), which is what a
  lat/lon advection step consumes without a further metric factor.

### Changed
- `shLowLevel.kernelFactors` gained a second output, the radial exponent
  `p_n` in `f_n(r) = kernel_n (R/r)^p_n`, and its `Height` branch now
  uses it. The exponent was previously written down inside that branch;
  the gradient needs the same number for `d/dr = -(p_n/r) f_n`, and a
  second copy would be the same fact decided in two places.

### Notes
- **`up` is empty, not zero, for surface quantities.** `ewh`, `geoid`,
  `surface_density`, `bottom_pressure`, `deformation_up` and `none` have
  no radial law - an equivalent water height one kilometre up is not a
  smaller equivalent water height, it is nothing. `g.up` is `[]` and
  `info.hasUp` is `false`. Empty fails at the first use; a NaN field
  would be plotted. `Height` is refused for the same quantities and for
  the same reason, by the same test.
- **The declared contract is "exact derivative of `shSynthesis` under
  identical options"**, so the defaults match `shSynthesis` (`quantity`
  `"geoid"`, `nmin` 0) and `testCorrectness` differentiates
  `shSynthesis` itself rather than a second model of it. Arrows drawn
  over a map that was truncated differently are arrows over the wrong
  picture, and no other test would see it.
- `east` is `NaN` at `|lat| = 90`. Without the guard the `cos(phi)`
  division returns a finite, meaningless number - confirmed in the
  Python pre-validation, which printed exactly that.
- Python-validated before implementation
  (`tools/dev/validate_gradient.py`): all three components against
  5-point finite differences of an independent scalar synthesis at
  1e-12, the identities `d(potential)/dr = -gravity_disturbance` and
  `d(gravity_disturbance)/dr = -gravity_gradient_rr` at 4e-16, and
  single-coefficient closed forms at 2e-16. The first run failed at
  2.9e-1 on `north` only - a doubled `sqrt(2)` in the Python model's own
  normalisation, visible only through the m/m+-1 mixing of the
  derivative stencil.
### Fixed (tooling)
- `tools/dev/make_apiref.py` wrote the regenerated API reference to
  `/tmp/shx_git/html/apiReference.html` - a clone location from an
  earlier session, i.e. outside the tree being built. It now derives the
  path from `SRC`, like every other path in that file. Nothing in the
  repository was wrong; the next person to regenerate the reference
  would simply have found it unchanged and not known why.

### Notes (continued)
- **Not verified on hardware.** The MATLAB MCP bridge was unavailable
  this session; everything here rests on the static gates, the Python
  pre-validation and CI.

## [3.29.0] - 2026-08-20 - mean over a user-given period; two sigma/selection fixes

`shSeries.mean` gains `Range=` (decimal years or datetime) and a second
estimator. `Estimator="model"` fits bias/trend/annual/semi-annual
(+`Periods`) inside the window with the reference epoch at the window
centre and returns the exact time integral of that fit, which collapses
to `bias + sum_k s(P_k)*cos_k` with `s(P) = sin(pi*D/P)/(pi*D/P)` - for
a whole number of years `s = 0` and the period mean is the trend line at
the centre. The second output reports coverage, largest gap, centroid
offset and the applied attenuation. Voronoi time-weighting was tested
and rejected (never won; 4x worse across the 2017-2018 gap) -
tools/dev/validate_meanperiod.py holds the measured table.

Two fixes found while reading the code for this:

- `mean` divided the temporal scatter by `nEpochs` instead of by the
  number of VALID epochs per coefficient, understating the sigmas of
  every series holding NaN months (4.3% for 3 of 36). Coefficients with
  fewer than two valid epochs now return NaN rather than the `std` of a
  single sample, which is 0.
- `select([t1 t2])` is resolved as INDICES whenever both values are
  valid indices - true for `[2004 2010]` on any daily series longer than
  2010 samples, i.e. under six years, and silent. `select(Range=[t1 t2])`
  is now the unambiguous form, and the positional shorthand warns
  (`shSeries:ambiguousRange`) when it resolves an index pair that would
  also have been a plausible window.

The old help promised "sigmas RSS/T when present", which was never
implemented; it now describes what the code does.

## [3.28.0] - 2026-08-18 - guide chapter 27 (Kalman/VAR); kalmanChain Structure

Guide gains the self-contained Kalman/VAR chapter with two computed
figures: the measured VAR order/structure holdout table, and a live
run on the acceptance machine (degree-RMS attenuation 0.95->0.52 over
n=2..40, data contribution 0.93->0.63) - plus the honest note that an
11-deg basin average changes 2% RMS only on monthly data (daily is
the target regime). kalmanChain passes Structure= to estimateVAR and
builds the orderblock partition itself. README/kalman.html updated;
references renumbered (28).

## [3.27.1] - 2026-08-18 - fetchITSG accepts Months arrays again

The no-selection gate crashed on 1 x K string Months (array logical in
&&), hit live by the starter level of setup(Download="all"). Two sites carried the pattern (no-selection gate and the
"all"-detection); the first fix missed the second and the machine
rerun caught it before CI ever saw the branch. Both fixed; offline
regression test with a local BaseURL covers the
array path and both loud empty-selection forms. Diagnosed from the
failure label and skip counts of the user's summary struct.

## [3.27.0] - 2026-08-18 - Download="all" (BREAKING: FetchITSG removed)

setup_shAnalysis gains the fifth cumulative download level "all":
starter + the complete ITSG monthly archive at Nmax, resumable. The
misunderstood v3.0.0 FetchITSG option is removed - it was an earlier
request for exactly this, delivered as a bolt-on instead of a level.
Callers using FetchITSG= now get MATLAB:TooManyInputs (measured on
R2026a). DryRun plan, help, setup.html and the contract test updated;
cumulative plan and the error ID verified on the acceptance machine
before commit.

## [3.26.3] - 2026-08-18 - fixtures leave the repository

tests/test_data removed from main; CI consumes the orphan branch
'testdata' (step live since #71), machines use SHX_TESTDATA_FOLDER.
Current-state doc claims updated; historical release notes untouched.

## [3.26.2] - 2026-08-18 - packaged sample-data resolver

The acceptance run with fixtures only on the data drive exposed the
gap in v3.25.0: readDDK's "DDK3" name form and two demo loaders
resolve the shipped samples from toolbox code, which cannot depend on
tests/. New shLowLevel.testDataDir carries the env/pref/fallback
order; readDDK, demo_shAnalysis and tests/shxTestDataDir (now a thin
delegate) share it. One acceptance failure -> zero.

## [3.26.1] - 2026-08-18 - CI fixtures from the orphan branch

Fixtures now live on the orphan branch 'testdata' (20 files, 11 MB,
no history); CI checks it out into tests/test_data before the suite.
The step is idempotent against main still carrying the folder, so the
in-repo copy can be deleted in a later commit without coordination.
Tooling only.

## [3.26.0] - 2026-08-18 - structured VAR estimation

estimateVAR gains Structure="diagonal"|"orderblock" (block-wise
Yule-Walker, structure-consistent Q and Sigma0, loud Blocks
validation). Driven by the first live VAR-order table (ITSG monthly,
36-month holdout): the dense estimate overfits at monthly sample
sizes while order-block (best, 3.268e-12, stationary) and diagonal beat
climatology-only by 21-23%; p >= 2 explodes. Numbers re-measured
through the shipped estimator on the acceptance machine (a first
run through the API also caught a column-vector bug in the Blocks
partition check that the synthetic row-block test had missed). Order=1 and Structure="full" defaults confirmed/kept
for the daily target regime; monthly guidance documented in the help.
Python S1-S3 checks + one MATLAB test covering shape, values, loud
errors, and the short-sample ranking.

## [3.25.0] - 2026-08-18 - relocatable test fixtures

New tests/shxTestDataDir: SHX_TESTDATA_FOLDER env var, then the
TestDataFolder preference, then the in-repo tests/test_data fallback.
All direct fixture paths in the suites route through it; new
setup_shAnalysis option TestDataFolder (env + setpref, like
SeriesFolder). Removing the fixtures from the repository itself
remains a separate decision: CI consumes the in-repo copy until a CI
data source (e.g. a release-asset download step) exists.

## [3.24.1] - 2026-08-18 - gate hardening: mlint_lite R5

New static rule R5 in tools/dev/mlint_lite.py: name-value structs of
arguments blocks must be the last input on the function line
(MismatchBetweenBlockAndLine otherwise). Motivated by the one defect
that escaped this session's gates; the broken v3.24.0 rtsSmoother now
trips the rule (regression-checked against that exact commit). Repo
sweep of all 143 .m files: clean. Tooling only.

## [3.24.0] - 2026-08-18 - fixed-lag smoother

rtsSmoother gains Lag=L: bounded-latency smoothing for NRT-style daily
production (definition-true windowed backward recursion, O(T*L)).
Lag=0 == filter, Lag >= T-1 == full RTS to rounding; identical through
memory and matfile stores (all unit-tested); error-vs-lag decay
Python-measured. Completes this session's Kalman-module program:
QC (3.21), Joseph update (3.22), multi-center (3.23), fixed lag (3.24).

## [3.23.0] - 2026-08-18 - multi-center Kalman chain

kalmanChain neq mode accepts several SINEX folders (one per center),
clusters files into epoch groups and combines each group with
neqCombine (per-epoch VCE, or fixed NeqWeights) before the Kalman
update; rep.sigma2 reports the per-epoch variance factors. New test
with two synthetic centers (identical files -> equal factors) plus a
single-folder run pinning the v3.20 snx.epoch wiring end to end.

## [3.22.0] - 2026-08-18 - Joseph-stabilized solution update

kalmanFilter's solution-mode covariance update moves to the Joseph
form: exact-arithmetic identical (all equivalence tests unchanged),
six orders of magnitude more accurate when R is small against the
prior (measured against a 50-digit mpmath reference; the decision was
made on that A/B, not on textbook habit). New discriminating MATLAB
test: wide-spectrum prior vs harsh R must match the NEQ information
form to 1e-9 - the old update fails at ~1e-6.

## [3.21.0] - 2026-08-18 - innovation-based quality control (Kvas 3.3)

kalmanFilter/kalmanChain gain QC="flag"|"reject": per-epoch chi-square
innovation test (solution and NEQ form, algebraically identical when
N = R^-1); rejected epochs become prediction-only so blunders never
enter the recursive state. New base-MATLAB shLowLevel.chi2Quantile
(Wilson-Hilferty) with measured accuracy map. Python pre-validation
tools/dev/validate_kalman_qc.py Q1-Q4 (statistic calibration E[T]=dof,
NEQ==solution identity, blunder detection); three MATLAB tests with
scipy-pinned quantile references.

## [3.20.0] - 2026-08-17 - neqCombine (NEQ-level VCE combination)

shLowLevel.neqCombine combines normal equations before solving
(COST-G style) with Foerstner variance components and asserted
redundancy invariant; accepts readSINEX NEQ structs directly.
readSINEX gains the +SOLUTION/STATISTICS parse (snx.stats) and finally
delivers the long-promised snx.epoch (decimal year from REF_EPOCH) -
closing a latent kalmanChain NEQ-mode crash. Python pre-validation in
tools/dev/validate_neqcombine.py (5 checks); four new MATLAB tests
including a synthetic-SINEX end-to-end run through neqCombine.

## [3.19.0] - 2026-08-17 - matfile covariance store

kalmanFilter/rtsSmoother/kalmanChain gain StoreCov="matfile": full
covariances stream through a v7.3 MAT with partial I/O instead of RAM,
making long daily Kalman runs (n40, a year: ~16 GB) feasible on
ordinary machines. Bit-identical to the in-RAM path (unit-tested
through filter and smoother, including a gap); explicit file-ownership
contract (filter's caller deletes; the smoother only reads; the chain
cleans up its internal temp in both branches).

## [3.18.0] - 2026-08-17 - buildCondFun (Kvas covariance conditioning)

shLowLevel.buildCondFun builds the estimateVAR CondFun after Kvas
(2019) Sec. 2.4: exact spectral<->EWH round trip on the Gauss-Legendre
grid (identity at psi0=Inf, unit-tested to 1e-10), land/ocean-style
region-block masking (eq. 2.117) and the exp(-psi/psi0) distance taper
(eq. 2.120). PSD preserved by the Schur product theorem; a
rank-deficient empirical Sigma(0) becomes strictly PD (the Yule-Walker
stabilization of his Fig. 2.5). Python pre-validation in
tools/dev/validate_condfun.py (4 checks). Three new MATLAB tests.

## [3.17.0] - 2026-08-17 - Kalman/VAR module (Kurtenbach/Kvas)

Temporal smoothing of SH series after Kurtenbach (DGK C-683, 2012) and
Kvas (TU Graz, 2019): estimateVAR (Yule-Walker VAR(p); p=1 == Kurtenbach
closed form), kalmanFilter (solution and SINEX-NEQ information-form
updates, gap handling, data-contribution diagnostics), rtsSmoother
(exactly the joint least-squares adjustment under the stationary
initialization - unit-tested to machine precision), and the single point
of access kalmanChain. Python pre-validation in
tools/dev/validate_kalman.py (8 tests). New doc page html/kalman.html.

## [3.16.2] - 2026-08-13 - final documentation audit

Guide Part IV input tables gain a description column (881 arguments,
100% coverage after completing demo_shAnalysis).

## [3.16.1] - 2026-08-13 - CoastBufferKm default 300

Author decision on the live 6e table: the 300 km Chambers-style
coastal buffer becomes the oceanChain default (baseline +1.557 mm/yr,
in the published band); CoastBufferKm=0 reproduces the old numbers.

## [3.16.0] - 2026-08-13 - uniform fetch layout (BREAKING)

fetchSINEX -> fetchITSGSINEX; uniform on-disk layout: temporal
products under series/ (series/itsg/*, series/icgem/*, series/GAX/*),
static models under static/. fetchGAX dest now optional. Fetchers
warn once on pre-v3.16 data locations instead of re-downloading
silently - move old folders (itsg_series, itsg_daily, itsg_sinex,
itsg_background, icgem/) into the new layout. run_vdk_series fixed
(fetch rename + a latent version-helper typo caught by the first
bridge run).

## [3.15.1] - 2026-08-13 - guide: complete theory edition

Part I now starts from zero (chapter 0: mission, products, vocabulary)
and covers everything through v3.15 (chapters 21-26: VDK theory,
SINEX/normal equations, ocean chains, coastal leakage incl. the
one-step warning, hydro indices, daily NRT), plus a full reference
list and four computed theory figures from the validated experiments.

## [3.15.0] - 2026-08-13 - coastal-leakage controls

oceanChain gains CoastBufferKm (great-circle mask erosion; 300 km
cuts 54% of the gauss445 coastal leak, measured) and
RemoveLandLeakage (one-step forward modelling of all outside-mask
sources before the filter; >60% leak-bias reduction with 5%
ocean-mean fidelity in the CI experiment). Defaults off until the
machine acceptance re-baselines the published barystatic trend.

## [3.14.0] - 2026-08-13 - flood/drought indices

hydroExtremeIndex: GRACE-DSI with USDM-style categories, WSDI, and
the causal Reager storage deficit (full FPI with a precipitation
grid) - per grid cell or basin. Detrend policy and robust-sigma
behaviour quantified by pre-validation, not assumed.

## [3.13.0] - 2026-08-12 - VDK/VADER decorrelation

vdkApply implements Horvath et al. (2018) on the ITSG monthly SINEX
normals (fetchSINEX/readSINEX), signalVarianceKaula estimates the
cyclostationary signal model with an exact log-chi-square bias
correction, and run_vdk_series.m is the resumable batch driver for
the full-series run on another machine. tvANS relation documented:
same Wiener family, different inputs - formal monthly N vs empirical
stationary structure.

## [3.12.0] - 2026-08-12 - fetch family: SINEX and ITSG background

fetchSINEX (ITSG monthly normals, the only public per-month SINEX;
months required, one month ~460 MB) and fetchITSGBackground (monthly
background-model means, era-dependent palettes verified live; not the
AOD1B GAX split). Consistent naming across the family; one shared
robust download loop (fetchFileSet) and shared month validation.

## [3.11.0] - 2026-08-12 - obpChain, residual circulation separation, fetch fallback

obpChain delivers GravIS-style bottom-pressure fields (GSM + GAD,
GravIS filter order and reference window, land NaN) - one GAA step
apart from the barystatic oceanChain. eofSeparate splits residual
ocean circulation from noise (weighted EOF + North rule,
Python-prevalidated with the Marchenko-Pastur separability limit
stated); oceanChain gains SeparateCirculation=. httpFetch falls back
to websave on transport-level failures only. GAD filter-order note
documented; machine acceptance script shipped for the next bridge
session.

## [3.10.1] - 2026-08-12 - fetch robustness (ICGEM 429)

fetchGAX hardening: consecutive-failure cap, polite inter-download
pause, single capped retry on HTTP 429. Root cause of the bridge
hangs identified: ICGEM rate-limits bursts and httpFetch honoured the
server's Retry-After so faithfully that calls outgrew the tool window.

## [3.10.0] - 2026-08-12 - fetchGAX, full ocean restoration, API completeness

fetchGAX downloads the AOD1B GAA/GAB/GAC/GAD monthly means from the
GFZ ICGEM pages (2002 on, centre-independent). oceanChain gains the
GAAFolder ocean-mean subtraction completing the Chambers & Willis
(2010) restoration, with epoch coverage reported. API tables: blank
argument descriptions 616 -> 0 (convention lexicon as final pass +
26 functions with new help lines); chains_flow now shows all four
lanes including the fetchGAX feed.

## [3.9.0] - 2026-08-12 - oceanChain, Slepian application, gfc dot terms

oceanChain delivers the barystatic ocean-mean series (+1.49 +/- 0.02
mm/yr, +312 Gt/yr on COST-G RL02.1 with the ICE-6G_D ocean-floor GIA
lever of +0.89 mm/yr measured); the ocean mean is filter-invariant to
0.01 mm/yr and sigMon 0.0121 m is the honest post-separation noise
proxy. slepianProject adds the application half of slepianBasis
(cross-validated against an independent Python quadrature). ICGEM
'dot' secular lines are read as 'trnd' synonyms via the line parser.

## [3.8.10] - 2026-08-12 - NV convention, quantity "none", setup preferences

Name-value casing convention codified (Capitalized canonical for
arguments-block options, lowercase for legacy inputParser names and
quantity strings) with a regression test pinning the case-insensitive
tolerance of both mechanisms. quantity "none" gives a dimensionless
passthrough (kernel 1, no GM/R/kn), retiring the GM=R=1 workaround.
setup_shAnalysis now persists SeriesFolder/MasconFile/GravisFolder/
DDKFolder via setpref('shAnalysis', ...) alongside the session SHX_*
env vars.

## [3.8.9] - 2026-08-12 - Retry-After fetchers, API tables, V9 additions

httpFetch/httpRetryDelay give every toolbox download Retry-After-aware
retries with capped exponential backoff (the GravIS 503 case); listing
reads retry with backoff. Opt-in tests accept setpref("shAnalysis",...)
preferences besides SHX_* env vars. Guide V9 gains the standardChain
flow diagram; API reference tables now always carry sizes (n x 1 /
n x m fallback) and merge descriptions from help Inputs/Options
sections (missing descriptions cut from 775 to ~120, rest on the
roadmap).

## [3.8.8] - 2026-08-12 - validated chains as methods

gravisL2B (shared GravIS Level-2B correction core) plus one-call
greenlandChain (-225.6 Gt/yr, 32 s), antarcticaChain (-125.7 + per-basin
table) and twsChain (amplitude ratio 1.001, trend RMS 0.032 cm/yr vs
GravIS) - the executed guide V1-V8 validations with exchangeable inputs,
provenance reports, TrendGrid= re-use for sensitivity studies, and a
user-supplied OceanMask for the sigma_trend policy (must be false over
land: a bare latitude band verifiably shifts the answer by 5 Gt/yr).

## [3.8.7] - 2026-08-12 - Antarctica + TWS validation

Guide chapters V7/V8: the GravIS chain validated against Antarctica
(-125.7 vs AWI -146.9; the 14% is the map-estimator-vs-joint-inversion
method distance, proven by a 0.905 difference-pattern correlation with
the official TUD kernel grid) and terrestrial water storage (eleven
river basins, amplitude ratio 1.001, trend RMS 0.032 cm/yr after GIA -
documenting that the GravIS TWS product carries a GIA correction its
Technical Note omits). evalMask rejects |lat| > 90 polygon vertices
(catches [lon lat] GeoJSON handed to the [lat lon] toolbox convention,
which used to build silent phantom basins).

## [3.8.6] - 2026-08-12 - audit fixes

Twenty findings from an independent adversarial audit, fixed with
regression tests. Highlights: readMascon no longer returns raw days as
decimal years on CSR files (case-insensitive attributes, loud time-unit
errors, name-based grid orientation); 22 shipped-fixture assumes are
verifies; the real-series science test now fails a sign-flipped trend;
shReadGFC warns on truncation/corruption; kernelFactors validates Love
numbers; leakageCorrect names NaN input instead of 'diverged';
fetchLoveNumbers reads headerless GROOPS columns; series names populate
for headers without modelname; sensitivityKernel's 2-16% claim is scoped
to its 1-D validation (2-D: 1-42%, ordering reversed; full-covariance
path confirmed and pinned); doc gate checks HTML structure; the GravIS
span (2002-04..2023-02, n=217) is pinned beside every 2.8%.

All notable changes to shAnalysis. The version line in `Contents.m`
(read by `shLowLevel.version` and MATLAB's `ver`) is the single source of truth.

## [3.8.5] - 2026-08-11

### Fixed
- `html/shAnalysis.html`, the page a user reaches from `doc shAnalysis`,
  announced **v3.0.0** - eight releases stale. Nothing caught it because
  the version gate only compared pages that already carried a version,
  and this one carried an old one in prose. It now has an explicit
  version stamp and `doc_sync_audit` checks it; a negative test confirms
  the gate fires when the two disagree.
- `NOTICE` listed the GFZ TN-13 fixture as `TN-13_GEOC_GFZ_RL06.3.txt`.
  It ships as `RL06_3.txt` - the same underscore/dot confusion that kept
  `testStandardChain` filtered out for four releases.

### Audited, no change needed
- Every `shLowLevel.*` function named in the README exists; every path
  it names exists or is documented as generated output.
- Every fixture listed in NOTICE is present (after the correction
  above).
- No dangling cross-references in the in-file help of the 84 package
  functions and 3 classes.
- Version strings agree across Contents.m, CITATION.cff, CHANGELOG.md,
  apiReference.html, the guide cover and the overview page.

## [3.8.4] - 2026-08-11

### Fixed
- `testStandardChain` had been silently SKIPPING since v3.1.0. It asked
  for `TN-13_GEOC_GFZ_RL06.3.txt`; the shipped GFZ fixture spells the
  release with an underscore (`RL06_3`), unlike the CSR and JPL ones.
  The `assumeTrue` guard turned that typo into a filtered test, which in
  the summary looks exactly like a passing one - so the canonical
  pipeline entry point went unverified through four releases and every
  CI run. The fixture checks are `verifyTrue` now: a missing fixture is
  a failure, not a shrug. An audit of every fixture filename referenced
  in the suite found no other case.
- With the test running for the first time, CI immediately found an
  assertion inside it that had never been exercised: the GIA epoch check
  demanded `RelTol 1e-10` on a value that survives a gfc write/read
  round trip. Epochs are stored as decimal years in text, so the
  observed agreement is 5.3e-10 - the format's precision, not MATLAB's.
  Relaxed to 1e-8, which still catches any real error in the GIA
  scaling (those are of order 1 in relative terms). Nothing wrong with
  `standardChain` itself.

### Checked, not changed
- The workflow guide's demo-gallery figures were carried on the roadmap
  as "Edition-2 placeholders". They are not: all ten are real rendered
  figures from real data (the ITSG month, the DDK3 Wbd binary, the
  GRACE-FO minus GRACE difference), and all ten are present in
  `tools/dev/guide_assets/`. The roadmap entry was stale, like the
  COST-G SINEX fetcher removed in 3.8.1. Removed.

## [3.8.3] - 2026-08-11

### Added
- `setup_shAnalysis` gained `SeriesFolder=` and `MasconFile=`, which
  export `SHX_SERIES_FOLDER` and `SHX_MASCON_FILE` for the session and
  report them in `summary.testData`. Until now those variables were
  mentioned only inside the test files that read them, so nobody would
  have found them.
- The workflow guide gained an **Installation and data** chapter
  covering setup, the download levels, the persistent data folder, and
  both opt-in variables with a table of where the data comes from. Also
  documented on the setup page and in the README.
- `DryRun` reports what it *would* set without calling `setenv`, and a
  path that does not exist warns rather than failing silently.

### Notes
- Both variables are optional. Without them the suite runs complete and
  the two tests report as FILTERED, not as passing - the distinction
  matters, because a silently skipped test looks like a green one.
- `SHX_SERIES_FOLDER` is deliberately NOT wired to the persistent data
  folder: a routine acceptance run must never reach for a network or
  archive drive, so pointing at that data stays an explicit decision.
- MATLAB was unavailable for this change, so it is verified by the
  static gates and CI only.

## [3.8.2] - 2026-08-11

### Added
- Opt-in test of `readMascon` against a REAL mascon product, via
  `SHX_MASCON_FILE`. Verified on the JPL RL06.3Mv04 CRI file (0.5 deg,
  257 months, 46 MB), which reads correctly in 0.8 s.
- The test checks GEOGRAPHY, not dimensions. The synthetic fixture
  writes `lwe_thickness(lon, lat, time)` while the real JPL file writes
  `(time, lat, lon)` - a size check passes either way, and a transposed
  grid would sail through it. Greenland must LOSE mass over the GRACE
  era: measured -124 cm between 2003 and 2024, with the largest change
  at 76 N / 291 E (northwest Greenland), which is the right place.

### Documented
- The verified JPL layout, and that the reader permutes whatever order
  it finds to (lat, lon, time).
- Mascon latitudes are conventionally GEODETIC while this toolbox
  synthesises on GEOCENTRIC ones. The difference peaks near 45 deg at
  0.19 deg - about 21 km, or 0.4 of a 0.5-degree mascon cell. The help
  said "typically geodetic" before; it now says what that costs and
  where to convert.

## [3.8.1] - 2026-08-11

### Changed
- README rewritten. It still described `compat/` and `tests/legacy/`,
  both removed in v3.0.0, and its newest feature section was "New in
  v2.5" - nine releases behind. It now describes the current toolbox,
  the six documentation gates, the GravIS validation result, and a
  table of where each data source actually comes from. Cut from 404 to
  ~175 lines: the per-release history belongs in the CHANGELOG, which
  has it.

### Removed from the roadmap
- **COST-G SINEX fetcher.** There is no such source to fetch from.
  COST-G combines on the normal-equation level internally and publishes
  the combined SOLUTIONS through ICGEM, but does not distribute
  per-month SINEX normal equations or covariance matrices as a public
  product; Dahle et al. (2025) state that the variance-covariance
  information is not available for the combined solutions. The roadmap
  item traced back to a v2.5 note recording an AIUB 503 during a
  download attempt - a retry reminder that had hardened into a planned
  feature. For a full covariance use ITSG, which does publish monthly
  SINEX normal equations, or the GravIS VDK-filtered Level-2B products
  when the filtered result is what is wanted. Documented on the
  readSINEX page.

## [3.8.0] - 2026-08-11

### Added
- `shLowLevel.makeTutorials` (roadmap item 10): writes one Live Script
  per demonstration case into `tutorials/` - set up the path, run the
  case with figures visible, and point at the topic page and workflow
  guide. Open, press Run, change something.
- They are GENERATED from the demo registry, not hand-written.
  `demo_shAnalysis` is the single source of truth for what the toolbox
  demonstrates; a parallel set of curated tutorials would drift from it
  within a release, and `.mlx` is a binary zip, so the drift would not
  even show in a diff. Each tutorial says so in its own footer.
- Conversion to `.mlx` uses `matlab.internal.livecode.FileModel`, an
  internal API that is not in every release. When it is missing the `.m`
  files are still written - they are the useful artefact either way -
  and a warning explains the manual Save As route.
- New topic page `tutorials.html`, reachable from the Help browser.

### Fixed
- CI now sets `timeout-minutes` on the job (20) and on the MATLAB setup
  step (8). That step hung four times in one session, taking 5-10
  minutes against its usual 1.2 and each time needing a manual cancel.
  It now fails fast and visibly instead of sitting pending.

### Note
- Two bugs the acceptance machine caught in the generator:
  `repmat("x", 1, 40)` builds a 1x40 STRING ARRAY rather than a
  40-character string, so the padding trick that works for char produced
  a non-scalar file name; and `demo_shAnalysis("list")` PRINTS the case
  table as well as returning it, which would have spammed every
  generator run and every test.

## [3.7.0] - 2026-08-11

### Added
- `shLowLevel.sensitivityKernel`: a basin kernel that trades leakage
  against propagated GRACE noise explicitly (Swenson & Wahr 2002 - the
  construction behind the ESA CCI and GravIS gridded ice products),
  rather than by choosing a filter radius and hoping. Minimises
  leakage + Alpha * noise SUBJECT TO unit response over the basin,
  closed form via one Lagrange multiplier. No iteration and no stopping
  criterion, which is exactly its advantage over `leakageCorrect`:
  nothing about the answer depends on where you stop.
- Sweep `Alpha`, plot `info.leakage` against `info.noise`, take the
  L-curve corner. `Noise` accepts a full covariance, a sigma vector, or
  falls back to a degree-dependent default; a real covariance is what
  makes the kernel *tailored* rather than merely smoothed.

### Notes on getting it right
- The UNIT-RESPONSE CONSTRAINT is what makes the result an average.
  Without it the cheapest way to cut noise is to shrink the kernel
  towards zero: during development `info.gain` fell to 0.28 at
  Alpha = 0.1 and 0.001 at Alpha = 100, i.e. the "optimal" kernel
  measured almost none of the basin it was averaging - and the
  comparison against a Gaussian came out backwards for that reason.
- Measured benefit over a Gaussian at matched noise AND matched gain:
  **2% to 16%** less leakage across plausible far-field weightings.
  The largest margin comes with a high-degree weighting, which is not
  the intuitive ordering. The help says so rather than quoting a
  headline number.

## [3.6.0] - 2026-08-11

### Added
- `shLowLevel.estimateDegree1`: geocentre coefficients (C10, C11, S11)
  estimated from GRACE itself plus an ocean model, following Swenson,
  Chambers & Wahr (2008) - the method both GravIS and geogravL3 use.
  This removes the dependency on somebody having published a TN-13
  series for your exact Level-2 product and release, and guarantees the
  degree-1 terms are consistent with the solutions actually processed.
  The output struct matches `readTN13` exactly, sigmas included, so it
  drops into `addDegree1` unchanged. `kn` is required: degree-1 load
  Love numbers are frame dependent and are never assumed.
- Python-validated (`tools/dev/validate_degree1.py`): exact recovery of
  a known geocentre from a synthetic land/ocean world, 1.5-4% error at
  2 mm noise, a demonstrable bias when the ocean model is omitted, and
  a rising condition number on a degenerate ocean domain.

### Notes on three things the acceptance machine caught
- A CONSTANT nuisance column is carried beside the three patterns. The
  ocean residual generally has a degree-0 component (the observed field
  is degrees 2+, and any mass imbalance between data and ocean model is
  an offset), and without a constant to absorb it that offset lands on
  C10, which has a large ocean mean: a **153% error** before the fix.
- The design matrix is column-equilibrated before `cond` is reported.
  The constant column has a completely different scale from the basis
  patterns, so an unscaled condition number reports the units rather
  than the geometry - 3.8e7 on a problem whose geometry is fine. After
  equilibration: 1.3 for a global ocean, 58 for a polar-only one.
- `addDegree1` REQUIRES sigma fields, so the first version was not the
  drop-in its own help text claimed. Formal sigmas now come from the
  ocean-fit residual propagated through the least-squares solution.

## [3.5.2] - 2026-08-11

### Fixed
- `leakageCorrect` gained `ResidualRegion=` (default: the `Mask`). The
  discrepancy principle added in 3.5.0 measured the residual GLOBALLY,
  and with a regional mask that can never reach the noise level: the
  model describes one region while the data contains Antarctica,
  Alaska and global hydrology. On the GravIS Greenland case the
  residual was 0.0085 globally against 0.0008 near the mask, with a
  noise level of 0.0024 - so the principle silently never fired and
  every run stopped at `MaxIter`. `info.residualRMSGlobal` now exposes
  the gap; a large one means unmodelled signal elsewhere.

### Measured
- The GravIS Greenland comparison, rerun with a real stopping criterion:
  **-224.6 Gt/yr** against a published -231.1, i.e. **2.8%**. This
  replaces -227.4 (1.6%), which came from stopping at an arbitrary
  iteration count. The closer number was a coincidence of where the
  iteration happened to be; a result that depends on an arbitrary
  choice is not a result.
- The noise level must match the quantity being inverted. The
  open-ocean RMS of a TREND field is 0.0024 m/yr, but most of that is
  real barystatic sea-level rise, not error - using it stops after 4
  iterations and gives -201.0 Gt/yr, 13% low. The trend's noise is the
  monthly noise propagated through the fit, sigma_monthly / sqrt(Sxx) =
  0.0115 / sqrt(8353) = 0.000125 m/yr, nineteen times smaller. That
  stops at 82 iterations and gives the -224.6 above.

## [3.5.1] - 2026-08-11

### Added
- `shLowLevel.oceanRMS`: area-weighted RMS of a field over the OPEN
  ocean - ocean points more than `MinDistanceKm` (default 1000) from the
  nearest non-ocean point. Far from land a GRACE field should contain
  almost no real signal, so what remains is error; this is the standard
  noise metric processing centres quote, and the value `leakageCorrect`
  needs for `NoiseLevel`. Without it, v3.5.0's discrepancy principle had
  no natural input.
- The ocean mask is USER-SUPPLIED, deliberately. Base MATLAB's
  `coastlines` data set is not present in every installation (it is
  absent on the acceptance machine, which is why `plotSHMap` carries a
  fallback), and a wrong mask silently changes the number.
- Area weighting is on by default: an unweighted RMS over a lat/lon grid
  over-counts the polar rows. On white noise the weighted and unweighted
  values agree, which is exactly why the difference goes unnoticed until
  the field has structure - the test pins both cases.
- Python-validated (`tools/dev/validate_oceanrms.py`): the erosion moves
  the boundary by exactly d/R against an analytic spherical cap, and the
  weighted mean of cos^2 over the sphere comes out 0.6666 against 2/3.

## [3.5.0] - 2026-08-11

### Fixed (correctness of a shipped result)
- `leakageCorrect` solves an ill-posed inverse problem and therefore
  SEMICONVERGES: the error against the truth falls, reaches a minimum,
  then rises as the iteration begins to fit noise - while the residual
  keeps shrinking. The previous stopping rule chased a small solution
  step, which is exactly wrong. Measured on the reference problem
  (`tools/dev/validate_stopping.py`): the final solution is **361x**
  worse than the best one, `Tol = 1e-3` stops **89x** past the optimum,
  and the shipped default `Tol = 1e-4` never triggers at all.
- `NoiseLevel=` enables the discrepancy principle (Morozov): stop once
  the residual reaches the noise level of the data, since fitting more
  closely than the noise is fitting noise. It lands within 2% of the
  optimum. `Tau=` (1.2) is the safety factor; 1.2-1.5 is best, 1.0
  slightly overfits. The natural estimate for `NoiseLevel` is the
  open-ocean RMS of the field, which is what processing centres use.
- On a noisy version of the reference disc, verified on the acceptance
  machine: the discrepancy principle stopped after 2 iterations and was
  **4.3x closer to the truth** than the unregularised run, which took
  239.
- `info.stoppedBy` ("discrepancy" | "step" | "maxIter" | "zeroField")
  plus `residualRMS` and `noiseLevel` make the regularisation state
  inspectable. Without `NoiseLevel` a warning states that the result
  depends on `MaxIter`.

## [3.4.1] - 2026-08-11

### Documented
- The GravIS Greenland comparison closes to **1.6%** once the filter is
  declared correctly. Dahle et al. (2025, Sect. 2.2.1) specify the
  basin-average method: spectral masking, then a Wiener optimal filter
  approximately equivalent to a Gaussian of 4 deg latitude half-width,
  then conversion to surface mass, then least-squares adjustment. The
  forward model is filtered IDENTICALLY to the observations. The inputs
  are genuinely unfiltered Level-2B coefficients, so `Filter="none"`
  looked right and was not: declaring `Filter="gauss445"` moved the
  trend from -234.9 to -227.4 Gt/yr against a published -231.1, turning
  a 1.6% overshoot into a 1.6% undershoot. It also drifts less with
  continued iteration (2.0 Gt/yr over 300->900 steps against 2.5),
  because the filter regularises the inverse problem.
- The same paper specifies the mask: 1 until 200 km outside the
  grounding line, tapering to 0 by 600 km - `basinKernel(BufferKm=200,
  TaperKm=400)`, not a hard outline.
- **VDK**: it is DDK with the filter matrix rebuilt from each MONTH's
  formal error covariance, i.e. a per-epoch usage of `designFilter` with
  `Noise=`. What the toolbox lacks is the data, not the method - monthly
  full covariances are not distributed with Level-2 products, and for
  COST-G they are not available at all. Documented on the designFilter
  page with the two practical routes (GravIS VDK-filtered Level-2B
  products, or a SINEX normal-equation covariance). Note the GravIS ice
  basin averages do not use VDK at all.

## [3.4.0] - 2026-08-11

### Added
- `shSeries.removeAlias`: fits a tidal-alias harmonic (S2, 161 days by
  default) jointly with bias, trend, annual and semi-annual and
  subtracts only that harmonic - the correction GravIS applies to its
  Level-2B products. Across the GRACE/GRACE-FO boundary the nodal
  planes are not aligned, so a FIXED 100 degree phase offset applies to
  the later mission (Landerer et al. 2020). The offset adds no free
  parameters and ignoring it mis-estimates the amplitude badly
  (validated in `tools/dev/validate_alias.py`).
- Guide chapter "Validation against GravIS": the complete worked
  comparison against the published Greenland basin averages - the
  reference and why it must be recomputed over the span actually used,
  all four Level-2B corrections, the basin average, the results table,
  and what each step is worth.

### Measured
- Removing the S2 alias moves a twenty-year Greenland trend by
  **0.2 Gt/yr**, i.e. nothing: a 161-day harmonic is very nearly
  orthogonal to a linear trend over two decades. It remains a real
  correction for the monthly series. Recorded because it was expected to
  explain part of the residual gap and did not.

## [3.3.1] - 2026-08-11

### Fixed (documentation)
- `leakageCorrect`: the mask must cover EVERY region that can hold mass,
  not only the one being measured. A target-only mask tells the
  iteration that mass exists nowhere else, so neighbouring signal is
  forced into the target and the result is biased high. Validated
  against the published GravIS Greenland basin-average series (COST-G
  RL02, -231.1 Gt/yr over the matching span, all four GravIS
  corrections applied to the same Level-2 input):

  | mask | Gt/yr | vs published |
  |---|---|---|
  | none (naive grid integral) | -170.3 | -26% |
  | Greenland only | -259.8 | +12% |
  | union with Canadian Arctic, Iceland, Svalbard | -242.5 | +5% |

  The neighbours absorb -112 Gt/yr in the union solution, and it
  converges faster. No API change: `Mask=` already accepts any union -
  the error was in how it was used, which is exactly why it needed
  saying in the help rather than fixing in code.

## [3.3.0] - 2026-08-11

### Added
- `shLowLevel.readSHM`: the GRAVIS/GRACE SHM format - a YAML header
  followed by `GRCOF2` (a field) or `GRDOTA` (a rate in 1/yr) records,
  gzip transparent, GM and the reference radius taken from the header.
  GravIS Level-2B products - monthly solutions, mean fields, the
  ICE-6G_D (VM5a) GIA model - are a major public data source the
  toolbox could not read at all. A `GRDOTA` result feeds
  `standardChain(GIA=)` directly, which is what it always wanted.
  Python-validated first (`tools/dev/validate_shm.py`).
- Fixtures for both record types, and the GravIS Greenland drainage
  basin geometries, under CC-BY-4.0 with attribution in NOTICE.

## [3.2.2] - 2026-08-11

### Fixed
- `standardChain` stopped with "No TN-13 entry within 0.050 yr" whenever
  the correction tables trailed the solutions - which they always do,
  since TN-13/TN-14 are published weeks after the monthly fields. On a
  current 257-month ITSG series the two newest epochs were uncovered and
  the whole chain failed. Uncovered epochs are now dropped and the fact
  recorded in `rep.steps`; `OnMissing="error"` restores the old
  behaviour and `Tolerance=` is settable. Dropping beats the
  alternative of keeping them, which would splice UNCORRECTED months
  onto corrected ones - a step in the series exactly where people look
  for the newest signal.
- `shSeries.read` / `fromFolder` treated `writeGFC`'s
  `<file>.gfc.provenance.json` sidecars as solutions: the read pattern
  has to be loose enough for `.gfc.gz`, so `*.gfc*` matched them and a
  folder written BY the toolbox could not be read back BY the toolbox.
- `shCoefficients.write` gained `Sidecar=`, which only the low-level
  `writeGFC` had, so class-API users could not turn the sidecar off.

### Notes
- All three were found by running the toolbox against a full 24-year
  ITSG series (257 monthly n96 solutions, 2002-2026) rather than against
  fixtures. The suite is fixture-bound by necessity; the failures it
  cannot see are the ones that need real data of real length.

## [3.2.1] - 2026-08-11

### Added
- `tests/testScience.m`: regression against values published OUTSIDE the
  toolbox - WGS84 and GRS80 J2 from the defining constants, the Gegout97
  (PREM) load Love numbers including the CM-frame `k'_1 = 0`, the
  closed-form EWH kernel of Wahr et al. (1998) evaluated with the
  shipped Love numbers, the GRACE-minus-SLR C20 discrepancy, TN-13
  geocenter amplitudes for all three providers, and the Gaussian
  half-weight relation. The existing suites check that the code does
  what the code intends, and stay green if a formula is consistently
  wrong; these have somewhere to fail. Verified that the kernel test
  catches both a missing `rho_water` (factor 1000) and a `k_n` sign
  error.
- The trend regression is opt-in via `SHX_SERIES_FOLDER`, because a
  trend needs a monthly series that is far too large to ship. It
  deliberately does NOT read the persistent data folder, so a routine
  acceptance run never touches a network or archive drive.

### Fixed
- Test cleanups no longer throw from `onCleanup` destructors. `d =
  tempname` invents a NAME, so a test whose code path did not reach the
  `mkdir` left `rmdir` with nothing to remove: every CI log carried a
  destructor warning that MATLAB cannot attach to any test, and which
  can mask the real failure that ended the test early. All 30 sites now
  use `tests/rmIfFolder.m`, and one genuinely dead variable in
  `testRobustness` (a `tempname` that was never used for anything) is
  gone.

## [3.2.0] - 2026-08-11

### Added
- `shLowLevel.leakageCorrect`: iterative forward modelling of filter
  leakage and attenuation. Finds the mass field whose filtered image
  matches the observation, using only the filter - no external signal
  model. `Mask=` confines the solution to where mass can exist, which is
  both better conditioned and the variant that removes leakage rather
  than redistributing it: on a synthetic disc with an exact mask it
  recovers 0.9998 of the truth and leaves exactly zero outside.
- `shLowLevel.gridScaling`: per-pixel scaling factors from a model
  series pushed through the same chain. Amplitude-invariant to 1e-15 -
  the factors describe the model's PATTERN, not its scale.
- Both implemented and validated in Python
  (`tools/dev/validate_leakage.py`, a compact numpy SH port whose
  analysis/synthesis round trip is exact to 4e-16 and whose Gaussian
  weights match `shGaussianWeights` to 2.7e-11) BEFORE the MATLAB port.
  The validation caught two design errors before any MATLAB was written:
  a scaling test that was exact by construction and therefore validated
  nothing, and a test cap so large the filter barely touched it.

### Two contracts that are easy to get wrong
- Convergence is judged on the CHANGE OF THE SOLUTION, not the residual.
  A masked problem is inconsistent - no field confined to the region
  reproduces an observation with energy outside it - so the residual
  plateaus at a nonzero floor while the solution is converged. The first
  implementation stopped on the residual and reported failure on exactly
  the case the mask exists for.
- `gridScaling` returns NaN where the model carries no signal instead of
  a ratio of two numerical zeros, and `info.kMedian` summarises the
  pixels the model gives mass to. Over all finite pixels the median is
  dominated by pure-leakage pixels, whose `k = 0` is correct but is not
  the basin scaling factor anyone is looking for.

## [3.1.4] - 2026-08-11

### Added
- `shLowLevel.safeMove`: the `.part` -> target swap every fetcher ends
  with, now with verification and exponential-backoff retries
  (0.25/0.5/1/2/4 s). Windows antivirus and cloud-sync clients open a
  just-written file to scan it and hold it briefly; a plain `movefile`
  hits that window and reports a download failure for a file that
  downloaded perfectly. Each attempt checks that the destination exists
  and the source is gone rather than trusting the status flag, because
  synced and network volumes have been observed reporting success early.
  All six call sites in fetchICGEM (2), fetchITSG, fetchTN,
  fetchLoveNumbers and fetchDDK go through it.
- `shLowLevel:safeMove:locked` names the usual cause and the two fixes
  (exclude the data folder from on-access scanning, or move it off the
  synced drive) instead of surfacing a bare OS message.

## [3.1.3] - 2026-08-11

### Added
- `tools/doc_sync_audit.py`, a sixth quality gate, wired into CI before
  the MATLAB setup step. The five existing gates were all green while
  the API reference listed 5 of 12 `fetchICGEM` options, eleven help
  pages were unreachable from the Help browser, the v3.1.1 tag reported
  3.1.0 and the guide advertised a call that threw - none of that was
  detectable automatically. The gate checks doc snippets against the
  parsed contracts (including option VALUE types, which is the class a
  name-only check misses), API-reference freshness, `helptoc.xml`
  reachability, version consistency, help placeholders and defaults, and
  a narrative-coverage floor. Every check is verified by deliberately
  breaking the repository and confirming it fires.
- `tools/dev/README.md`: gate order, regeneration order, the SIGPIPE
  trap, and the guide-asset recovery note.

### Fixed
- `fetchITSG` help claimed `Nmax (96)` unconditionally. The default is
  NaN, which resolves to 96 for monthly and 40 for daily solutions, and
  120 is also accepted for monthly - the help listed neither.
- `seaLevelFingerprint` documented `Tol` as `1e-8 * |eustatic|`, mixing
  the option's value with its effect; the default is 1e-8 and the
  tolerance is relative.
- `vceRescale` help wrote `round(2/3*Lmax)` where the arguments block
  says `round(2/3 * idx.Lmax)`.
- `shCoefficients.mtimes`/`uminus` and `shClimatology.withNote`/
  `fromCoef` were documented only in the generated API reference.

## [3.1.2] - 2026-08-11

### Added
- Narrative documentation for the v3.x features that existed only in the
  generated API reference: new help pages `standardChain.html`,
  `designFilter.html` and `icgemSeries.html`, plus sections for
  `poleTideConvert` (referenceSystems), `synthesisPoints` (shSynthesis),
  `listITSG` (fetchITSG) and `fetchLoveNumbers` (readLoveNumbers). All
  reachable from `helptoc.xml` (46/46 pages).
- Workflow guide Edition 5: the ICGEM time-series workflow and why
  `Mode="auto"` fetches one archive rather than 300 files, the standard
  chain and why its order is not negotiable, custom filter design, and a
  section on what real provider files actually contain (FORTRAN
  D-exponents, the ICGEM 2.0 column order, ragged record groups).

### Fixed
- The guide's figures were read from a container path that does not
  survive a session, so the PDF was not reproducible and `make_figs.py`
  could only regenerate 3 of the 10. The assets were recovered from the
  shipped PDF and now live in `tools/dev/guide_assets/` in the repo.
- 58 name-value options across 23 entities were "documented" as `see
  arguments block`: `help` showed nothing while the generated API
  reference showed size, type and default. All replaced with real
  descriptions; pinned to zero by `testHelpHasNoPlaceholders`.
- Four help defaults disagreed textually with their arguments blocks
  (`synthesisMatrix.NLat/NLon`, `tvANSFilter.VCEMinDegree`,
  `vceRescale.MinDegree`).
- `fetchICGEM` Outputs help never mentioned `info.mode`, added in the
  series work, nor that bulk selections concatenate their file lists.

## [3.1.1] - 2026-08-11

### Added
- `fetchICGEM` fetches TIME SERIES: temporal-catalogue rows (from
  `listICGEM(Type="temporal")`) download a whole monthly series into
  `<dataFolder>/icgem/series/<group>_<center>_<series>/` - per file
  (resumable, throttled, each file verified before swap; `Files=`
  filter, `FileList=` injection for subsets/mirrors). DEFAULT is the
  server's whole-series ZIP in ONE request (`Mode="auto"`; the rate
  limiter punishes hundreds of per-file requests), with automatic
  per-file fallback; `Mode="archive"|"files"` force either. `Type=`
  mirrors listICGEM so numeric/name selection works on either
  catalogue; the result folder feeds `shSeries.fromFolder` and
  `standardChain` directly.

### Fixed
- `fetchICGEM` bulk selection of temporal series: the multi-selection
  loop assumed one file per row and crashed assigning a 283-file
  series into `strings(1,K)` - AFTER the download had succeeded. File
  outputs are now collected per selection and concatenated; `info`
  carries a uniform `mode` field ("model"|"archive"|"files") across
  all paths; the summary reports selections and files separately.
- `shSeries.filter("tvANS", ...)` accepts and forwards `Shrinkage`,
  `VCEMinDegree` and `VCEBands`. The workflow guide has advertised
  `ts.filter("tvANS", Blocks="auto", VCEBands=[0 16 33 61])` since
  Edition 2; the class method rejected it (`MATLAB:TooManyInputs`), so
  banded VCE was reachable only through the low-level entry point. The
  defaults stay in `shLowLevel.tvANSFilter` - `[]` means "do not
  override" - so there is exactly one home for each default.
- Documentation metadata brought back in sync with the code: `Contents.m`
  is at 3.1.1 (the v3.1.1 tag shipped a 3.1.0 version line, so
  `ver('shAnalysis')` under-reported), `CITATION.cff` follows, and the
  `[3.1.0]`/`[3.0.1]`/`[2.7.0]` sections are dated instead of
  "Unreleased". `Contents.m` no longer advertises the `compat/` folder
  and the legacy v1 suite, both removed in v3.0.0, and its first line is
  now a short product name (MATLAB's `ver` printed a truncated sentence).
- `apiReference.html` regenerated: it predated the series work and listed
  5 of the 12 `fetchICGEM` options. `make_apiref.py` now parses the
  version from `Contents.m` instead of carrying a hardcoded string.
- `helptoc.xml` reaches all 43 help pages (11 were unreachable from the
  Help browser) and its labels no longer name superseded versions;
  `shAnalysis.html` is a v3 page again instead of describing `compat/`.
- `shCoefficients.disp`, `shSeries.disp` and `shClimatology.disp` have
  help text; `help_audit.py` no longer exempts `disp`.
- `shReadGFC` bulk parser survives ragged record groups: EIGEN-5S/5C
  carry a single gfc line with a trailing epoch among thousands of
  uniform ones, which silently misaligned the rectangular sscanf and
  requested a (date x date) coefficient matrix. Groups are now checked
  for rectangularity (rows out == lines in), split by numeric width
  when ragged, and guarded by an n/m integer/bound sanity net; dirty
  groups still fall back to the line parser.

## [3.1.0] - 2026-08-10

### Fixed
- `shReadGFC` ICGEM 2.0 acos/asin column order corrected to the
  real-world layout `... sigC sigS t0 t1 period` (verified against
  CNES_GRGS.RL05MF). The previous parser assumed period-first and
  MIS-PARSED such files (period = a date code, t1 = 1.0) - a
  correctness bug independent of, and older than, the speed problem.
- `shReadGFC` parses variable-term files (GRGS mean fields, ICGEM 2.0)
  in bulk too: group-wise sscanf per record key, vectorized epoch
  conversion, vectorized variableTerms assembly (the per-element
  struct growth was O(N^2)). `icgemDate2Year` is pure arithmetic now -
  the datetime/calendarDuration construction cost ~1 ms per call and
  was invoked per record. A 73 MB CNES_GRGS mean field verification
  went from tens of minutes (the second reported "stall") to seconds;
  dirty records still fall back to the authoritative line parser,
  which itself now assembles variableTerms vectorized.
- `shReadGFC` fast path accepts FORTRAN D-exponents (EIGEN-6C4 switches
  from e to D serialization at degree 371): normalized to E after the
  key strip, matching str2double semantics. Previously such files fell
  back to the legacy line parser - minutes for a 178 MB model, which
  presented as fetchICGEM "stalling" during download verification.
  CI exposed the deeper bug: str2double returns NaN for D-exponents,
  so the legacy parser had silently corrupted such files to NaN above
  the switch degree - both paths now normalize and agree.
- `fetchICGEM` bulk mode ("all", index vectors) no longer stalls after
  the first file: the ICGEM server rate-limits rapid requests (HTTP
  429 / tarpit). Bulk fetching now throttles between models (`Pause=`,
  3 s), retries 429/timeouts with 30/60/120 s backoff (`Retries=`),
  prints a [k/K] counter with per-file size and timing, continues past
  failed models with a summary instead of aborting, and honours
  `Quiet=`. Interrupted runs resume (present files are skipped).

### Changed
- `shReadGFC` is ~100x faster on large static files: bulk parsing
  replaces the per-line fgetl/str2double loop (28.6 s -> 0.21 s at
  n720 measured on PCWIN64; EGM2008-class n2190 in 1.7 s instead of
  minutes). Variable-term files (gfct/trnd/dot/acos/asin) keep the
  proven line parser; both paths verified struct-identical on all
  fixtures and guarded by an equivalence test.

### Added
- `shLowLevel.standardChain`: the canonical GRACE post-processing chain
  (read folder -> TN-14 C20/C30 -> degree-1 -> optional GIA trend ->
  Gaussian/DDK/custom-W filter) as one correctly ordered call with a
  step-by-step provenance report; explicit-file overrides for
  reproducible pipelines.
- `shLowLevel.designFilter`: DDK-class anisotropic filter
  W = (N + Alpha*inv(S))^-1 N per order block, from formal sigmas +
  Kaula rule or full covariances (buildNoiseCov/buildSignalCov);
  output in the readDDK block format (drops into applyDDK and the
  class methods unchanged). Python-validated with pinned references.
- Workflow guide version stamp is generated from Contents.m (the PDF
  title claimed v2.5 since the beginning).

## [3.0.1] - 2026-08-10

### Added
- `tools/help_audit.py`: documentation completeness gate, run in CI
  before the test suite. Every public function and method must document
  every positional input, every option WITH its default, and every
  output with size/type annotations, plus an example. 328 findings
  fixed across the tree to reach zero; the gate keeps it there.

## [3.0.0] - 2026-08-10 - DOI: 10.5281/zenodo.21876348

### BREAKING
- Namespace renamed `+shx` -> `+shLowLevel`: every call site changes
  from `shx.fun` to `shLowLevel.fun`; error identifiers from `shx:*`
  to `shLowLevel:*`. Mechanical migration: replace `shx.` and `shx:`.
- `compat/` (v1 wrappers) and the legacy v1 suite are removed for good.

### Added
- `shLowLevel.listITSG`: numbered catalogue of the TU Graz server
  (releases x monthly n60/n96/n120 x daily), local-mirror mode.
- `fetchITSG`: `Release=` override (no more silent 2018/operational
  mixing), `months = "all"`, `Catalog=` selection by catalogue row,
  `BaseURL=` mirror, n120.
- `listICGEM` numbered; `fetchICGEM` accepts row indices, name vectors,
  and `"all"`.
- `setup_shAnalysis`: `DataFolder=` (applied before any fetcher) and
  `FetchITSG = "all"`.
- `shLowLevel.fetchLoveNumbers`: load/deformation Love numbers from the
  GROOPS collection (TU Graz), safe-swap + parser.
- `shLowLevel.synthesisPoints`: pointwise potential/disturbance/anomaly
  at arbitrary (lat, lon, r) incl. upward continuation; Python-pinned.
- Generated API reference page `html/apiReference.html` (inputs,
  options with defaults, outputs for every public function/method).

## [2.7.0] - 2026-08-10

### Added
- `shLowLevel.poleTideConvert`: C21/S21 conversion between the IERS2010 and
  IERS2018 (secular pole) mean-pole conventions, solid + ocean pole
  tide, overridable coefficients; raw (C, S, epoch) and object forms.
  Python-validated (identities exact, dS21 trend to < 1% of the
  dominant term).
- `Proxy=` option in all four fetchers and `setup_shAnalysis`:
  per-call proxy via matlab.net.http (base MATLAB) for institutional
  networks; websave path continues to honour MATLAB Web Preferences.
- Provenance JSON sidecars (`<file>.provenance.json`: tool version,
  MATLAB release, metadata) on `writeGFC`, `writeGrid`,
  `writeAnimation`; `Sidecar = false` disables.
- `writeGrid` netCDF output is CF-1.8 complete (standard_name, axis,
  coordinates, long_name, Conventions/title/source/history globals);
  the source stamp is dynamic (was hardcoded "v2.4").

## [2.6.0] - 2026-08-10 - DOI: 10.5281/zenodo.21871299

### Added
- Comparison suite: `shLowLevel.compareSolutions` / `shLowLevel.compareSeries`
  aggregators (also `g.compare` / `ts.compare`) over new standalone
  metrics `diffSpectrum`, `spatialStats`, `nashSutcliffe`,
  `effectiveCorr` (AR(1)-corrected significance), `threeCorneredHat`
  (N >= 3), and `shLowLevel.taylorDiagram`. All numerics Python-validated.
- GitHub Actions CI (`ci/shanalysis-ci.yml`); full suite green on
  Linux and Windows.

### Fixed
- `writeAnimation`: platform-aware VideoWriter profile (.avi portable;
  MPEG-4 unavailable on Linux now errors clearly).
- `shDegreeRMS` help documented fields that did not exist
  (`n`/`amp` -> `degree`/`degAmplitude`/...).
- Demo provenance line now generated from `shLowLevel.version`.

## [2.5.1] - 2026-08-08

### Added
- `Update=` option in all four fetchers (safe, parse-verified swap;
  TN-13/TN-14 grow monthly upstream); `BaseURL=` mirror-folder mode in
  `fetchTN`; forwarded through `setup_shAnalysis(Update=true)`.
- `shLowLevel.version`: toolbox metadata parsed from `Contents.m`.

### Fixed
- `applyDDK` truncates Lmax-120 filter blocks to the field nmax
  (standard n60/n96 use; previously errored).
- `shLowLevel.pctile` accepts vector percentiles.
- `setCoefficient` initializes both sigma stacks (pairing invariant);
  a lone sigmaC used to break shSeries stacking.

## [2.5.0] - 2026-08-07

### Added
- Exact constrained tvANS posterior sigmas (the pre-2.5 formula
  UNDERESTIMATED; documented); basin sigmas include the deterministic
  model contribution.
- Kendall AR(1) correction in `fitDeterministicModel`.
- `shLowLevel.readLoveNumbers` (layouts, frames CE/CF/CM, pchip in log(1+n)).
- `setup_shAnalysis` one-call setup; `shLowLevel.fetchTN`.
- Generated 69-page API reference (Part IV) with executable examples
  (`docs/apiExamples.json`, `testAPIExamplesRun`).
- Real-file validation: CSR/JPL/GFZ TN-13, GSFC TN-14, DDK Wbd
  binaries, ITSG monthly/daily, 460 MB operational SINEX streaming.

## [2.4.2] - 2026-08-07

- MIT LICENSE file (Matthias Weigelt); every help text and doc page
  closes with the attribution statement.
- `plotSHCoeffTriangle` difference mode: sine sectorals S_nn no longer
  blanked (the S wing was one column narrow).
- `shLowLevel.listICGEM(Type="temporal")`: full ~70-series catalogue
  (was 3 release-note rows) + `Series=` listing single downloadable
  files.
- Full-sine-wing triangle difference plots; robust cache-speedup test;
  DDK reader; ICGEM catalogue; persistent data folder.

## [2.4.1] - 2026-08-07

### Added
- Triangle plots without the centre line; spectrum plots on a LINEAR
  degree axis (log y kept).
- `plotSHSpectrum` `Quantity=` amplitude | rms | variance |
  cumamplitude | cumrms | cumvariance; order-domain plots via
  `shLowLevel.shOrderRMS` (the striping axis; marginals tested against
  `shDegreeRMS`); cumulative variance/RMS fields added to
  `shDegreeRMS`.
- `shLowLevel.version` - toolbox metadata (name, version, date, root)
  parsed from `Contents.m`.
- `shLowLevel.fetch*` take `Update=true` for a safe, parse-verified
  refresh of existing files (TN-13/TN-14 grow monthly upstream).

## [2.4] - 2026-08-07

### Added
- Visualization: `shLowLevel.plotSHMap` / `g.map` (divergent map,
  coastlines, Hammer projection; `plotSHMap` was REMOVED again in
  3.32.0), `shLowLevel.plotBasinSeries` (sigma band, gaps, trend),
  triangle difference mode (`RefC`/`RefS`), `shLowLevel.plotCovariance`
  (block boundaries), `plotSHSpectrum` Kaula + crossover overlays,
  `shLowLevel.writeAnimation` (MP4, fixed robust scale).
- `shLowLevel.errorMap` - analytic sigma maps from full covariances
  (Cholesky, cross-checked against `mcPropagate`).
- `shLowLevel.eofAnalysis` - EOF/PCA modes as shCoefficients + unit PCs.
- `shLowLevel.basinScaling` - forward-modelled gain factors
  (struct | matrix | handle operators).
- `shSeries.trendBreaks` - hinge breakpoints with F-test (betainc-based
  p-values, no toolbox; null calibrated at 5.1%/5%).
- `shLowLevel.shFanFilter` / `g.fan` / `ts.fan` - Han degree x order
  Gaussian.
- `shLowLevel.combineCenters` - per-(center, month) VCE combination with
  partial redundancies, robust block-median option, inter-center
  correlation diagnostic, posterior sigmas.
- `shLowLevel.seaLevelFingerprint` - elastic sea-level equation (mass
  exactly conserved; near-field fall / far-field excess validated).
- `shLowLevel.writeGrid` - CF-style netCDF export (roundtrip-tested).
- Reference systems: `shLowLevel.normalFieldCS` (even zonals COMPUTED
  from WGS84/GRS80 defining constants, matching NIMA TR8350.2 to all
  published digits), `g.subtractNormalField` (auto-rescaled),
  `shLowLevel.rescaleGMR` / `g.toReference` (exact (GM, R) conversion;
  field invariance verified); arithmetic guards GM/R mismatches.
- `demo_shAnalysis` - selectable case registry (D01..D16,
  "list"/"core"/"all"/subset, `Visible=` for headless runs); rendered
  gallery with explanations in the workflow guide PDF.
- `shLowLevel.fetchITSG` / `shSeries.fromFolder` - on-demand ITSG
  download (websave, release routing, gap-aware) + folder loading;
  demos D01-D06 use real data when present, D12-D14 stay synthetic by
  design (known-truth recovery).
- `shLowLevel.pctile` - percentile without the Statistics Toolbox (an
  audit found `prctile` had slipped into two plot functions; fixed).

## [2.3] - 2026-08-07

### Added
- New synthesis/analysis quantities in `shLowLevel.kernelFactors`:
  `surface_density` [kg/m^2] R rho_ave/3 (2n+1)/(1+kn),
  `bottom_pressure` [Pa] g0 * surface density (OBP),
  `deformation_up` [m] R hn/(1+kn) elastic vertical,
  `gravity_gradient_rr` [1/s^2] (GM/R^3)(n+1)(n+2) (T_rr).
- `Height` option: upward continuation (R/r)^p to satellite altitude.
- `shLowLevel.shSynthesisDeformation` / `g.deformation` - up/north/east
  elastic load deformation (the GNSS comparison); grid and station-list
  modes; exact dPbar/dphi via `shLowLevel.legendreALFDeriv` (frozen
  validated identity, ~5e-10 against numerical gradients).

## [2.2] - 2026-08-07

All rows Python-validated before the MATLAB implementation.

### Added
- `shLowLevel.basinKernel` - basin kernels from polygons/masks/functions
  (buffering + spectral taper).
- `shLowLevel.slepianBasis` - Slepian localization (regional analysis).
- `shLowLevel.readDDK`, `shLowLevel.applyDDK`, `g.applyDDK`,
  `ts.applyDDK` - DDK anisotropic decorrelation filters (native binary
  Wbd support + Nmax truncation in 2.2.1).
- `ts.removeGIA`, `clim.removeGIA` - GIA correction (user-supplied rate
  models).
- `ts.climatology(ARCorrect=true)` - AR(1)-corrected trend/coefficient
  sigmas.
- `shLowLevel.mcPropagate` - Monte-Carlo sigma propagation (independent
  or full SINEX covariance).
- `shLowLevel.readMascon` - JPL/CSR mascon netCDF reader.
- `shLowLevel.geodetic2geocentric`, `shLowLevel.geocentric2geodetic`,
  and `LatType="geodetic"` in the synthesis/analysis entry points.
- `shLowLevel.shSynthesis(..., MaxMemGB=4)` - latitude-banded streaming
  makes nmax 2190 real on ordinary RAM.
- `shLowLevel.tvANSFilter(..., VCEBands=[0 16 33 61])` - per-order-band
  VCE.
- `shLowLevel.readSINEX(..., Only="estimate")` - streaming estimate
  block of multi-100-MB SINEX in seconds.

## [2.1] - 2026-08-07

### Added
- `shCoefficients.analysis` - SH ANALYSIS: gridded or scattered data ->
  Stokes coefficients (rings: exact fast per-order solver; scattered:
  least squares + Kaula).
- `addDegree1` - TN-13 geocenter insertion (with
  `shLowLevel.readTN13`), completing the GSM + TN-14 + TN-13 chain.
- `filter(..., Blocks="auto")` - block-diagonal tvANS (identical
  results, Lmax ~ 120 tractable) + posterior sigma stacks
  (`tsF.sigmaCs`/`Ss`) and basin-average sigmas.
- `climatology(Periods=[161/365.25, 3.66, 7.48])` - S2/K2/K1 tidal
  alias terms; per-coefficient significance on components.
- `synthesis(..., Method="fft")` - FFT-along-longitude + latitude
  parity trick; Legendre recursion stable to degree 2190.
- `dropNaN` / `select` - GRACE <-> GRACE-FO gap handling.
- ICGEM 2.0 piecewise gfct files; `shLowLevel.readSINEX` covariances /
  normal equations.
