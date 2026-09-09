#!/usr/bin/env python3
"""Oracle for the two summations in +shLowLevel/synthesisPoints.m.

The MATLAB function offers Method="direct" (build Pbar_nm, contract it
per point) and Method="clenshaw" (per-ORDER lumped coefficients, Clenshaw
summation over degree, Pbar never formed). Both are re-implemented here
with the SAME recursion coefficients as +shLowLevel/legendreALF.m, so the
numbers are comparable to the toolbox rather than merely to each other.

WHAT THIS ESTABLISHES

  AGREE     clenshaw reproduces direct to a stated relative tolerance.
            It CANNOT be bitwise: it sums the same terms in a different
            order. Anyone who writes a bitwise assertion for it is
            asserting something arithmetic forbids.
  TRUTH     with mpmath present, both paths are compared against the
            same series evaluated in 60-digit arithmetic, at latitudes
            that include the near-pole cases where the u^m factor is
            smallest. The claim is NOT "clenshaw is more accurate" - it
            is that neither dominates and both sit within a few tens of
            eps, which is what a ~n^2/2-term sum with cancellation costs.
  CROSSOVER the point count at which clenshaw overtakes direct. This is
            what synthesisPoints' ClenshawFrom default is set from, and
            it is measured HERE, in numpy - not on MATLAB. It is a
            starting value; tests/perf_baseline.csv budgets both paths so
            the real MATLAB crossover can replace it.

Run: python3 tools/dev/validate_points_clenshaw.py [--bench]
Nonzero exit if AGREE or TRUTH fails.

Developed by Matthias Weigelt with the help of Claude, 2026-09-09.
"""
import sys
import time

import numpy as np

# tolerance on |clenshaw - direct| / max|direct|. Bounds the reordering
# of a sum of (nmax+1)^2/2 terms whose partial sums cancel; measured at
# 7.4e-15 (nmax 60) and 1.7e-14 (nmax 120) on the fixtures below, so this
# is roughly 3x the observed worst case, not a number chosen to pass.
AGREE_TOL = 5e-14
# max acceptable relative error of EITHER path against the 60-digit
# reference, in units of eps. Observed worst case 89 eps (clenshaw, at
# 89.5 deg latitude) and 53 eps (direct); 250 leaves room for a different
# BLAS or point set without hiding a real regression.
TRUTH_EPS = 250.0


def alpha(n, m):
    return np.sqrt((2 * n - 1) * (2 * n + 1) / ((n - m) * (n + m)))


def beta(n, m):
    return np.sqrt((2 * n + 1) * (n + m - 1) * (n - m - 1)
                   / ((n - m) * (n + m) * (2 * n - 3)))


def legendre_alf(N, lat):
    """(N+1, N+1, nlat) - the recursion and 1e-280 scaling of legendreALF.m"""
    lat = np.atleast_1d(lat)
    t, u, nl = np.sin(lat), np.cos(lat), lat.size
    P = np.zeros((N + 1, N + 1, nl))
    P[0, 0, :] = 1.0
    if N == 0:
        return P
    pm2, pm1 = np.ones(nl), np.sqrt(3) * t
    P[1, 0, :] = pm1
    for n in range(2, N + 1):
        p0 = alpha(n, 0) * t * pm1 - beta(n, 0) * pm2
        P[n, 0, :] = p0
        pm2, pm1 = pm1, p0
    scalef = 1e-280
    pmm, rescalem = scalef, np.full(nl, 1 / scalef)
    for m in range(1, N + 1):
        rescalem = rescalem * u
        pmm = pmm * (np.sqrt(3) if m == 1 else np.sqrt((2 * m + 1) / (2 * m)))
        p2 = np.full(nl, pmm)
        P[m, m, :] = p2 * rescalem
        if m == N:
            break
        p1 = np.sqrt(2 * m + 3) * pmm * t
        P[m + 1, m, :] = p1 * rescalem
        for n in range(m + 2, N + 1):
            p0 = alpha(n, m) * t * p1 - beta(n, m) * p2
            P[n, m, :] = p0 * rescalem
            p2, p1 = p1, p0
    return P


def radial(N, GM, R, r, quantity):
    n = np.arange(N + 1)[:, None]
    q = (R / r[None, :]) ** n
    if quantity == "potential":
        return GM / r[None, :] * q
    if quantity == "disturbance":
        return GM / r[None, :] ** 2 * (n + 1) * q
    if quantity == "anomaly":
        return GM / r[None, :] ** 2 * (n - 1) * q
    raise ValueError(quantity)


def direct(C, S, GM, R, lat, lon, r, n0=2, quantity="potential", chunk=256):
    """Pbar per CHUNK of points, reduction per point - the MATLAB path."""
    N, P = C.shape[0] - 1, lat.size
    mvec = np.arange(N + 1)
    out = np.zeros(P)
    for s in range(0, P, chunk):
        e = min(s + chunk, P)
        Pblk = legendre_alf(N, lat[s:e])
        for k in range(s, e):
            Pnm = Pblk[:, :, k - s]
            cm, sm = np.cos(mvec * lon[k]), np.sin(mvec * lon[k])
            f = radial(N, GM, R, r[k:k + 1], quantity)[:, 0]
            inner = np.sum(Pnm * (C * cm + S * sm), axis=1)
            out[k] = f[n0:] @ inner[n0:]
    return out


def clenshaw(C, S, GM, R, lat, lon, r, n0=2, quantity="potential"):
    """Per-order lumped coefficients, Clenshaw over degree, vectorised
    across points. Pbar is never formed."""
    N = C.shape[0] - 1
    t, u = np.sin(lat), np.cos(lat)
    f = radial(N, GM, R, r, quantity).copy()
    f[:n0, :] = 0.0
    out = np.zeros(lat.size)
    scalef = 1e-280
    pmm, rescalem = scalef, np.full(lat.size, 1 / scalef)
    for m in range(0, N + 1):
        if m >= 1:
            rescalem = rescalem * u
            pmm = pmm * (np.sqrt(3) if m == 1
                         else np.sqrt((2 * m + 1) / (2 * m)))
        bc1 = np.zeros_like(t); bc2 = np.zeros_like(t)
        bs1 = np.zeros_like(t); bs2 = np.zeros_like(t)
        for n in range(N, m - 1, -1):
            a1 = alpha(n + 1, m) * t if n + 1 <= N else 0.0
            b2 = beta(n + 2, m) if n + 2 <= N else 0.0
            bcn = f[n] * C[n, m] + a1 * bc1 - b2 * bc2
            bsn = f[n] * S[n, m] + a1 * bs1 - b2 * bs2
            bc2, bc1 = bc1, bcn
            bs2, bs1 = bs1, bsn
        pbarmm = pmm * rescalem
        out += np.cos(m * lon) * (bc1 * pbarmm) + np.sin(m * lon) * (bs1 * pbarmm)
    return out


def field(N, seed=7):
    rng = np.random.default_rng(seed)
    C = np.tril(rng.standard_normal((N + 1, N + 1))) * 1e-9
    S = np.tril(rng.standard_normal((N + 1, N + 1)), -1) * 1e-9
    return C, S


GM, R = 3.986004415e14, 6378136.3


def check_agree():
    bad = []
    for N, P in ((0, 3), (1, 3), (5, 4), (60, 200), (120, 50)):
        C, S = field(N)
        rng = np.random.default_rng(11)
        lat = np.deg2rad(np.concatenate(([89.9, -89.9, 0.0],
                                         (rng.random(max(P - 3, 0)) - .5) * 178)))
        lon = np.deg2rad(rng.random(lat.size) * 360)
        r = R + rng.random(lat.size) * 1000
        for q in ("potential", "disturbance", "anomaly"):
            for n0 in (0, 2):
                d = direct(C, S, GM, R, lat, lon, r, n0, q)
                c = clenshaw(C, S, GM, R, lat, lon, r, n0, q)
                sc = max(np.max(np.abs(d)), 1e-300)
                rel = np.max(np.abs(c - d)) / sc
                if not rel <= AGREE_TOL:
                    bad.append("nmax=%d %s Nmin=%d: %.3e > %.1e"
                               % (N, q, n0, rel, AGREE_TOL))
                print("  AGREE nmax=%-4d %-11s Nmin=%d  %.3e" % (N, q, n0, rel))
    return bad


def check_truth():
    try:
        import mpmath as mp
    except ImportError:
        print("  TRUTH skipped - mpmath not installed (pip install mpmath)")
        return []
    mp.mp.dps = 60
    N = 60
    C, S = field(N)
    lat_d = np.array([0.5, -37.0, 62.0, 89.5, -89.9, 12.3])
    lon_d = np.array([10.0, 200.0, 355.0, 45.0, 123.0, 271.0])
    lat, lon = np.deg2rad(lat_d), np.deg2rad(lon_d)
    r = R + np.array([0.0, 500.0, 1000.0, 250.0, 750.0, 100.0])
    vd = direct(C, S, GM, R, lat, lon, r)
    vc = clenshaw(C, S, GM, R, lat, lon, r)
    eps = float(np.finfo(float).eps)
    ed, ec, bad = [], [], []
    for k in range(lat.size):
        t, u = mp.sin(mp.mpf(lat[k])), mp.cos(mp.mpf(lat[k]))
        Pm = [[mp.mpf(0)] * (N + 1) for _ in range(N + 1)]
        Pm[0][0] = mp.mpf(1)
        Pm[1][0] = mp.sqrt(3) * t
        for n in range(2, N + 1):
            Pm[n][0] = (mp.mpf(alpha(n, 0)) * t * Pm[n - 1][0]
                        - mp.mpf(beta(n, 0)) * Pm[n - 2][0])
        pmm = mp.mpf(1)
        for m in range(1, N + 1):
            pmm = pmm * u * (mp.sqrt(3) if m == 1
                             else mp.sqrt(mp.mpf(2 * m + 1) / (2 * m)))
            Pm[m][m] = pmm
            if m == N:
                break
            Pm[m + 1][m] = mp.sqrt(mp.mpf(2 * m + 3)) * t * pmm
            for n in range(m + 2, N + 1):
                Pm[n][m] = (mp.sqrt(mp.mpf((2*n-1)*(2*n+1)) / mp.mpf((n-m)*(n+m)))
                            * t * Pm[n-1][m]
                            - mp.sqrt(mp.mpf((2*n+1)*(n+m-1)*(n-m-1))
                                      / mp.mpf((n-m)*(n+m)*(2*n-3))) * Pm[n-2][m])
        tot = mp.mpf(0)
        for n in range(2, N + 1):
            fn = mp.mpf(GM) / mp.mpf(r[k]) * (mp.mpf(R) / mp.mpf(r[k])) ** n
            inner = mp.mpf(0)
            for m in range(0, n + 1):
                inner += Pm[n][m] * (mp.mpf(C[n, m]) * mp.cos(m * mp.mpf(lon[k]))
                                     + mp.mpf(S[n, m]) * mp.sin(m * mp.mpf(lon[k])))
            tot += fn * inner
        rd = float(abs((mp.mpf(float(vd[k])) - tot) / tot)) / eps
        rc = float(abs((mp.mpf(float(vc[k])) - tot) / tot)) / eps
        ed.append(rd); ec.append(rc)
        print("  TRUTH lat %6.1f  direct %6.1f eps   clenshaw %6.1f eps"
              % (lat_d[k], rd, rc))
    print("  TRUTH worst: direct %.1f eps, clenshaw %.1f eps (bound %.0f)"
          % (max(ed), max(ec), TRUTH_EPS))
    for name, e in (("direct", ed), ("clenshaw", ec)):
        if max(e) > TRUTH_EPS:
            bad.append("%s worst %.1f eps > %.0f" % (name, max(e), TRUTH_EPS))
    return bad


def bench_crossover():
    print("\n  CROSSOVER (numpy; the MATLAB crossover is not this number)")
    for N in (60, 120):
        C, S = field(N)
        print("    nmax=%d   %8s %10s %10s" % (N, "P", "direct", "clenshaw"))
        for P in (10, 50, 100, 200, 400):
            rng = np.random.default_rng(3)
            lat = np.deg2rad((rng.random(P) - .5) * 178)
            lon = np.deg2rad(rng.random(P) * 360)
            r = R + rng.random(P) * 1000
            def tm(fn):
                fn(C, S, GM, R, lat, lon, r)
                ts = [(lambda t0: (fn(C, S, GM, R, lat, lon, r),
                                   time.perf_counter() - t0)[1])(time.perf_counter())
                      for _ in range(3)]
                return float(np.median(ts))
            tb, tc = tm(direct), tm(clenshaw)
            print("             %8d %10.5f %10.5f  %s"
                  % (P, tb, tc, "clenshaw" if tc < tb else "direct"))


def main():
    print("validate_points_clenshaw: direct vs clenshaw in synthesisPoints")
    bad = check_agree() + check_truth()
    if "--bench" in sys.argv:
        bench_crossover()
    if bad:
        print("\nFAIL:", file=sys.stderr)
        for b in bad:
            print("  " + b, file=sys.stderr)
        return 1
    print("\nvalidate_points_clenshaw: OK - clenshaw agrees with direct to "
          "%.0e and neither path dominates the other against 60-digit truth. "
          "Bitwise agreement is NOT claimed and is not achievable: the two "
          "sum the same terms in a different order." % AGREE_TOL)
    return 0


if __name__ == "__main__":
    sys.exit(main())
