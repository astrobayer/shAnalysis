#!/usr/bin/env python3
"""validate_neq_low_degree: numerical pre-validation of WP9 row 9f.

Low-degree coefficients from an independent source - C20 and C30 from
SLR (TN-14), degree 1 from TN-13 - added to a GRACE normal equation as
pseudo-observations of single coefficients, instead of substituted into
the solution. A pseudo-observation value v of coefficient p with 1-sigma
s adds w = 1/s^2 to N(p,p), w v to b(p), w v^2 to l'Pl and one to the
observation count. A coefficient the normal equation does not hold
(degree 1 in a GRACE NEQ) is first added to the index with zero rows and
columns, so it is determined by its pseudo-observations alone.

  CLAIM 1  the result solves the STACKED least-squares problem - the
           GRACE observation equations with the pseudo-observation rows
           x_p = v (weight 1/s^2) appended - solved by an independent
           route (QR of the whitened stacked design).
  CLAIM 2  l'Pl and the observation count stay consistent: with the
           updated ltpl, ltpl - 2 x'b + x'N x equals the stacked weighted
           residual sum of squares, and nobs grows by the number of rows.
  CLAIM 3  degree 1 is SUBSTITUTION: a GRACE NEQ carries no degree-1
           information, so after padding the degree-1 block is uncoupled.
           The estimate of each degree-1 coefficient equals its
           pseudo-observation exactly, and every other coefficient
           equals the solution without them. So adding TN-13 - itself
           derived from GRACE - cannot count GRACE's information twice in
           the other coefficients; it buys nothing beyond substitution
           either.
  CLAIM 4  C20/C30 are JOINT, and how much that buys is set by GRACE's
           correlation of C20/C30 with the other coefficients. Synthetic
           GRACE normal equation from potential values on a polar-gapped
           grid (nmax 10), SLR C20/C30 ten times better than GRACE's.
           4a: the EXACT posterior variance of the other zonals
           (C40..C10,0) under joint estimation, over that under
           substitution (which leaves them at GRACE's), is <= 1 - adding
           information cannot raise a variance - and < 1 where the
           correlation is not zero. 4b: a 40-seed closed loop agrees
           with 4a's exact ratio within 0.05. Printed: the ratio against
           the polar gap, with the largest |correlation| of C20 with the
           other zonals. The first statement of this claim asked the
           40-seed pooled RMS ratio to be below 1; at gap 8 deg it came
           out 1.005, because the correlation there is 0.12 and the
           expected gain (about rho^2 in variance) is far below what 40
           seeds resolve. The claim moved to the exact ratio, the statistic
           the question is about; the Monte Carlo stays as its check.
           All of it describes this synthetic design, not GRACE: on real
           normal equations the gain is as large as their C20/C30
           correlations, which have not been measured.

Run: python3 tools/dev/validate_neq_low_degree.py (nonzero exit on any
failed claim).

Developed by Matthias Weigelt with the help of Claude (Opus 5.5),
2026-10-29 (WP9 9f).
"""
import sys

import numpy as np

FAIL = []


def check(name, ok, detail):
    print(f"{'PASS' if ok else 'FAIL'}  {name}: {detail}")
    if not ok:
        FAIL.append(name)


def sh_index(lmax, nmin=2):
    """Order-major index, C before S per (n, m) - shLowLevel.shIndex."""
    out = []
    for m in range(lmax + 1):
        for n in range(max(m, nmin), lmax + 1):
            out.append((n, m, 0))
            if m > 0:
                out.append((n, m, 1))
    return out


def alf(lmax, theta):
    """Fully normalized associated Legendre functions, P[n, m, k]."""
    t = np.cos(theta)
    u = np.sin(theta)
    P = np.zeros((lmax + 1, lmax + 1, theta.size))
    P[0, 0] = 1.0
    for m in range(1, lmax + 1):
        f = np.sqrt((2 * m + 1) / (2 * m)) if m > 1 else np.sqrt(3.0)
        P[m, m] = f * u * P[m - 1, m - 1]
    for m in range(lmax + 1):
        for n in range(m + 1, lmax + 1):
            a = np.sqrt((2 * n - 1) * (2 * n + 1) / ((n - m) * (n + m)))
            b = np.sqrt((2 * n + 1) * (n + m - 1) * (n - m - 1)
                        / ((n - m) * (n + m) * (2 * n - 3))) if n - 1 > m else 0.0
            P[n, m] = a * t * P[n - 1, m] - (b * P[n - 2, m] if n - 2 >= m else 0.0)
    return P


def design(lmax, idx, lat_deg, lon_deg):
    th = np.radians(90.0 - lat_deg)
    lo = np.radians(lon_deg)
    P = alf(lmax, th)
    A = np.zeros((lat_deg.size, len(idx)))
    for j, (n, m, cs) in enumerate(idx):
        A[:, j] = P[n, m] * (np.cos(m * lo) if cs == 0 else np.sin(m * lo))
    return A


def add_coefficients(N, b, ltpl, nobs, idx, obs):
    """The function under test, written from the help text."""
    idx = list(idx)
    nmin_obs = min(o[0] for o in obs)
    nmin = min(n for n, _, _ in idx)
    if nmin_obs < nmin:
        lmax = max(n for n, _, _ in idx)
        new = sh_index(lmax, nmin_obs)
        pos = {k: i for i, k in enumerate(new)}
        mp = [pos[k] for k in idx]
        N2 = np.zeros((len(new), len(new)))
        b2 = np.zeros(len(new))
        N2[np.ix_(mp, mp)] = N
        b2[mp] = b
        N, b, idx = N2, b2, new
    pos = {k: i for i, k in enumerate(idx)}
    N = N.copy()
    b = b.copy()
    for (n, m, cs, v, s) in obs:
        p = pos[(n, m, cs)]
        w = 1.0 / s ** 2
        N[p, p] += w
        b[p] += w * v
        ltpl += w * v * v
        nobs += 1
    return N, b, ltpl, nobs, idx


def main():
    rng = np.random.default_rng(9)
    lmax = 6
    idx = sh_index(lmax)
    P = len(idx)

    # ---- CLAIM 1 / 2: a random well-posed GRACE system
    A = rng.standard_normal((80, P))
    sig = 0.3
    l = rng.standard_normal(80)
    Wg = 1.0 / sig ** 2
    N = Wg * A.T @ A
    b = Wg * A.T @ l
    ltpl = Wg * l @ l
    nobs = 80
    obs = [(2, 0, 0, 0.7, 0.05), (3, 0, 0, -0.4, 0.08)]
    N1, b1, lt1, no1, idx1 = add_coefficients(N, b, ltpl, nobs, idx, obs)
    x = np.linalg.solve(N1, b1)
    pos = {k: i for i, k in enumerate(idx1)}
    rows = np.zeros((len(obs), P))
    lo = np.zeros(len(obs))
    for k, (n, m, cs, v, s) in enumerate(obs):
        rows[k, pos[(n, m, cs)]] = 1.0 / s
        lo[k] = v / s
    As = np.vstack([A / sig, rows])
    ls = np.concatenate([l / sig, lo])
    Q, R = np.linalg.qr(As)
    xs = np.linalg.solve(R, Q.T @ ls)
    rel = np.max(np.abs(x - xs)) / np.max(np.abs(xs))
    check("CLAIM 1 stacked LS", rel < 1e-12, f"max rel diff {rel:.1e}")
    rss = np.sum((As @ xs - ls) ** 2)
    om = lt1 - 2 * x @ b1 + x @ N1 @ x
    check("CLAIM 2 l'Pl", abs(om - rss) / rss < 1e-10 and no1 == nobs + 2,
          f"rel diff {abs(om - rss) / rss:.1e}, nobs {nobs} -> {no1}")

    # ---- CLAIM 3: degree 1 padding is substitution
    obs1 = [(1, 0, 0, 1.1e-10, 3e-11), (1, 1, 0, -2.0e-10, 3e-11),
            (1, 1, 1, 0.5e-10, 3e-11)]
    N3, b3, _, _, idx3 = add_coefficients(N, b, ltpl, nobs, idx, obs1)
    x3 = np.linalg.solve(N3, b3)
    pos3 = {k: i for i, k in enumerate(idx3)}
    x0 = np.linalg.solve(N, b)
    d1 = max(abs(x3[pos3[(n, m, cs)]] - v) / abs(v) for n, m, cs, v, _ in obs1)
    oth = np.array([x3[pos3[k]] for k in idx])
    d2 = np.max(np.abs(oth - x0)) / np.max(np.abs(x0))
    check("CLAIM 3 degree 1 = substitution",
          d1 < 1e-14 and d2 < 1e-13 and len(idx3) == P + 3,
          f"degree 1 vs its value {d1:.1e}, the rest vs no-degree-1 {d2:.1e}")

    # ---- the MATLAB tests' configuration, measured over 10 seeds
    # (testNeqAddCoefficients*: nmax 4, A of 2P rows, sigma 0.3, C20/C30
    # observed, then degree 1): the bounds there are 3x these maxima.
    idx4 = sh_index(4)
    P4 = len(idx4)
    m1 = m2 = m3a = m3b = 0.0
    for seed in range(10):
        r = np.random.default_rng(200 + seed)
        A4 = r.standard_normal((2 * P4, P4))
        l4 = r.standard_normal(2 * P4)
        N4 = A4.T @ A4 / 0.09
        b4 = A4.T @ l4 / 0.09
        lt4 = l4 @ l4 / 0.09
        o4 = [(2, 0, 0, 0.7, 0.05), (3, 0, 0, -0.4, 0.08)]
        Na, ba, lta, _, ia = add_coefficients(N4, b4, lt4, 2 * P4, idx4, o4)
        xa = np.linalg.solve(Na, ba)
        pa = {k: i for i, k in enumerate(ia)}
        R4 = np.zeros((2, P4))
        R4[0, pa[(2, 0, 0)]] = 1 / 0.05
        R4[1, pa[(3, 0, 0)]] = 1 / 0.08
        As4 = np.vstack([A4 / 0.3, R4])
        ls4 = np.concatenate([l4 / 0.3, [0.7 / 0.05, -0.4 / 0.08]])
        xs4 = np.linalg.lstsq(As4, ls4, rcond=None)[0]
        m1 = max(m1, np.max(np.abs(xa - xs4)) / np.max(np.abs(xs4)))
        rs = np.sum((As4 @ xs4 - ls4) ** 2)
        m2 = max(m2, abs(lta - 2 * xa @ ba + xa @ Na @ xa - rs) / rs)
        o1 = [(1, 0, 0, 0.11, 0.05), (1, 1, 0, -0.2, 0.05),
              (1, 1, 1, 0.05, 0.05)]                # the scale of N4
        Nb, bb_, _, _, ib = add_coefficients(N4, b4, lt4, 2 * P4, idx4, o1)
        xb = np.linalg.solve(Nb, bb_)
        pb = {k: i for i, k in enumerate(ib)}
        x0 = np.linalg.solve(N4, b4)
        m3a = max(m3a, max(abs(xb[pb[(n, m, c)]] - v) / abs(v)
                           for n, m, c, v, _ in o1))
        m3b = max(m3b, np.max(np.abs(np.array([xb[pb[k]] for k in idx4]) - x0))
                  / np.max(np.abs(x0)))
    print(f"      MATLAB configuration, 10 seeds: stacked {m1:.1e}, "
          f"l'Pl {m2:.1e}, degree 1 {m3a:.1e}, the rest {m3b:.1e}")

    # ---- CLAIM 4: exact ratio per polar gap, Monte Carlo at one
    L = 10
    idxL = sh_index(L)
    PL = len(idxL)
    zon = [i for i, (n, m, cs) in enumerate(idxL) if m == 0 and n >= 4]
    i20 = idxL.index((2, 0, 0))
    i30 = idxL.index((3, 0, 0))
    sg = 1e-2

    def gracer(gap):
        lats = np.arange(-90 + gap + 0.5, 90 - gap, 2.0)
        lons = np.arange(0.5, 360, 4.0)
        LA, LO = np.meshgrid(lats, lons, indexing="ij")
        AL = design(L, idxL, LA.ravel(), LO.ravel())
        ws = np.cos(np.radians(LA.ravel()))
        NG = (AL.T * ws) @ AL / sg ** 2
        Cg = np.linalg.inv(NG)
        s_slr = 0.1 * np.sqrt(np.array([Cg[i20, i20], Cg[i30, i30]]))
        o = [(2, 0, 0, 0.0, s_slr[0]), (3, 0, 0, 0.0, s_slr[1])]
        Nj = add_coefficients(NG, np.zeros(PL), 0.0, 0, idxL, o)[0]
        Cj = np.linalg.inv(Nj)
        exact = np.sqrt(np.trace(Cj[np.ix_(zon, zon)])
                        / np.trace(Cg[np.ix_(zon, zon)]))
        corr = Cg[i20, zon] / np.sqrt(Cg[i20, i20] * np.diag(Cg)[zon])
        return AL, ws, NG, s_slr, exact, np.max(np.abs(corr))

    table = []
    ok4a = True
    for gap in (2.0, 8.0, 15.0, 20.0, 25.0):
        _, _, _, _, ex, rho = gracer(gap)
        table.append((gap, rho, ex))
        ok4a = ok4a and ex <= 1 + 1e-12 and (rho < 1e-6 or ex < 1)
    for gap, rho, ex in table:
        print(f"      gap {gap:4.1f} deg  max|rho(C20, zonal)| {rho:.2f}  "
              f"joint/substitution (exact) {ex:.3f}")
    check("CLAIM 4a exact ratio <= 1", ok4a,
          f"{min(t[2] for t in table):.3f}-{max(t[2] for t in table):.3f}"
          " over the gaps")

    AL, ws, NG, s_slr, exact, rho = gracer(20.0)
    es, ej = [], []
    for seed in range(40):
        r = np.random.default_rng(100 + seed)
        xt = r.standard_normal(PL) / np.array([n for n, _, _ in idxL]) ** 2
        lg = AL @ xt + sg / np.sqrt(ws) * r.standard_normal(AL.shape[0])
        bG = (AL.T * ws) @ lg / sg ** 2
        xg = np.linalg.solve(NG, bG)
        v = xt[[i20, i30]] + s_slr * r.standard_normal(2)
        xsub = xg.copy()
        xsub[[i20, i30]] = v
        o = [(2, 0, 0, v[0], s_slr[0]), (3, 0, 0, v[1], s_slr[1])]
        Nj, bj, _, _, _ = add_coefficients(NG, bG, 0.0, 0, idxL, o)
        xj = np.linalg.solve(Nj, bj)
        es.append(xsub[zon] - xt[zon])
        ej.append(xj[zon] - xt[zon])
    mc = np.sqrt(np.mean(np.array(ej) ** 2)) / np.sqrt(np.mean(np.array(es) ** 2))
    check("CLAIM 4b Monte Carlo agrees", abs(mc - exact) < 0.05,
          f"gap 20 deg: 40 seeds {mc:.3f} against exact {exact:.3f}")

    print(f"{len(FAIL)} claim(s) failed" if FAIL else "all claims hold")
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
