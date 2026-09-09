#!/usr/bin/env python3
"""Oracle for the GIA rate-uncertainty propagation of shSeries.removeGIA.

Until v5.1.1 the GIA model was subtracted as EXACT. WP5 row 5c propagates
its per-coefficient rate sigma. Two claims are checked here, and the
second is the one that matters scientifically:

  QUADRATURE  per epoch the model contributes sigmaRate * (t_k - T0) in
              quadrature, so the marginal per-epoch sigma is
              sqrt(sigmaIn^2 + (sigmaRate*dt)^2). Checked against a Monte
              Carlo over a synthetic ensemble.

  CORRELATED  the SAME rate error applies to every epoch, so the GIA
              component is perfectly correlated in time. A trend fitted
              while assuming the per-epoch sigmas are independent
              understates the GIA trend error by roughly sqrt(nEpochs);
              the true GIA contribution to a rate is sigmaRate itself.
              Both halves are measured, because the whole point of the
              row is that the per-epoch stacks are NOT enough for a
              trend - and a comment saying so is worth less than a
              number.

Run: python3 tools/dev/validate_gia_sigma.py
Nonzero exit if either claim fails.

Developed by Matthias Weigelt with the help of Claude, 2026-09-09.
"""
import sys

import numpy as np

# Monte-Carlo agreement bound. With N draws the sample std of a Gaussian
# has relative standard error 1/sqrt(2N); at N=20000 that is 0.5%, so 3%
# is ~6 sigma of the estimator - loose enough not to flake, tight enough
# that a factor-sqrt(T) error (the independence mistake, ~3.5x here)
# cannot hide under it.
MC_TOL = 0.03
N = 20000


def main():
    rng = np.random.default_rng(5)
    T = 12
    t = 2008.0 + np.arange(T) / 12.0
    t0 = t.mean()
    dt = t - t0

    sigma_in = 2.0e-11          # per-epoch formal error of one coefficient
    sigma_rate = 4.0e-12        # GIA rate 1-sigma [1/yr]

    analytic = np.sqrt(sigma_in**2 + (sigma_rate * dt) ** 2)

    # ensemble: ONE rate error per realisation, reused at every epoch
    eps_rate = rng.normal(0.0, sigma_rate, size=(N, 1))
    noise = rng.normal(0.0, sigma_in, size=(N, T))
    resid = noise - eps_rate * dt[None, :]     # what removeGIA leaves behind

    empirical = resid.std(axis=0, ddof=1)
    rel = np.abs(empirical - analytic) / analytic
    print("QUADRATURE  per-epoch sigma, analytic vs %d-sample MC" % N)
    print("   %-8s %-14s %-14s %s" % ("dt [yr]", "analytic", "MC", "rel"))
    for k in (0, T // 2, T - 1):
        print("   %+8.4f %14.6e %14.6e %8.2e"
              % (dt[k], analytic[k], empirical[k], rel[k]))
    print("   worst relative difference: %.2e (bound %.0e)"
          % (rel.max(), MC_TOL))
    bad = []
    if rel.max() > MC_TOL:
        bad.append("quadrature: %.3e > %.0e" % (rel.max(), MC_TOL))

    # ---- the correlation claim, measured on a GIA-ONLY ensemble ------
    # The first version of this check used the MIXED ensemble above and
    # FAILED - correctly. There sigma_in (2e-11) swamps the GIA rate
    # error (4e-12), so the fitted-rate sigma is dominated by white noise
    # and the correlated component is invisible. The claim is about the
    # GIA COMPONENT, so the experiment has to isolate it: drop the
    # per-epoch noise and let the rate error be the only thing present.
    resid_gia = -eps_rate * dt[None, :]
    sig_gia = sigma_rate * np.abs(dt)          # the per-epoch stacks

    A = np.vstack([np.ones(T), dt]).T
    rates = resid_gia @ np.linalg.pinv(A).T[:, 1]
    mc_rate_sigma = rates.std(ddof=1)

    # what a fit would predict from those per-epoch sigmas if it believed
    # they were independent
    W = np.diag(1.0 / sig_gia**2)
    indep_rate_sigma = np.sqrt(np.linalg.inv(A.T @ W @ A)[1, 1])

    print("\nCORRELATED  GIA contribution to a fitted RATE (GIA-only "
          "ensemble, T=%d)" % T)
    print("   MC (truth, one rate error reused) : %.6e" % mc_rate_sigma)
    print("   sigmaRate itself                  : %.6e" % sigma_rate)
    print("   assuming INDEPENDENCE             : %.6e" % indep_rate_sigma)
    print("   understatement factor             : %.2fx  (sqrt(T) = %.2f)"
          % (mc_rate_sigma / indep_rate_sigma, np.sqrt(T)))

    rel_rate = abs(mc_rate_sigma - sigma_rate) / sigma_rate
    if rel_rate > MC_TOL:
        bad.append("correlated rate sigma: %.3e vs sigmaRate %.3e (rel %.2e)"
                   % (mc_rate_sigma, sigma_rate, rel_rate))
    if mc_rate_sigma <= 1.5 * indep_rate_sigma:
        bad.append("the independence assumption is NOT visibly worse "
                   "(%.3e vs %.3e) - the fixture cannot demonstrate the "
                   "claim it exists for" % (mc_rate_sigma, indep_rate_sigma))

    if bad:
        print("\nFAIL:", file=sys.stderr)
        for b in bad:
            print("  " + b, file=sys.stderr)
        return 1
    print("\nvalidate_gia_sigma: OK - the per-epoch quadrature matches the "
          "Monte Carlo, and the fitted-rate sigma equals sigmaRate rather "
          "than the %.2fx smaller value an independence assumption gives."
          % (mc_rate_sigma / indep_rate_sigma))
    return 0


if __name__ == "__main__":
    sys.exit(main())
