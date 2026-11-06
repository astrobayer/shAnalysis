"""validate_matern_prior: oracle for shLowLevel.maternCovariance (WP9 9g).

The SPDE Matern prior of Lindgren, Rue and Lindstroem (2011, JRSS-B 73,
423-498, Sec. 3.1-3.2), alpha = 2 (nu = 1 on a surface), on the sphere:

    (kappa(x)^2 - Laplace) (tau(x) u(x)) = W(x),

W white noise. Discretised by Galerkin in the 4pi-normalised SH of degrees
0..L (the FEM of Lindgren et al. replaced by the band-limited basis the
toolbox already uses), with the multiplications by kappa^2 and by 1/tau
as quadrature Gram matrices on an over-sampled Gauss-Legendre grid:

    A = Y' W diag(kappa~^2) Y + diag(n (n+1)),   M = Y' W diag(1/tau) Y,
    Cov(x) = M A^-1 A^-1 M / (4 pi),

kappa~ = sqrt(8) R / rho, rho the local practical range (correlation
about 0.13 at distance rho in the plane), and 1/tau(x) = sigma(x) /
sqrt(s(kappa~(x))), s(k) = sum_{n = Nmin..L} (2n+1) / (4 pi (k^2 +
n(n+1))^2): with constant fields the pointwise standard deviation over
the index' degrees is exactly sigma. The index' degrees are then a
sub-matrix of the 0..L covariance (marginalisation).

Claims, each bound written before its run:
  CLAIM 1  the stationary covariance's Legendre series equals the closed
           form d/dlambda [P_nu(-cos psi) / (4 sin(pi nu))], nu (nu + 1)
           = -lambda (the Green function of lambda - Laplace on the unit
           sphere, differentiated once: alpha = 2), to 1e-10 of C(0)
  CLAIM 2  constant fields: the Galerkin covariance is the diagonal of
           the Matern degree variances to 1e-12 (relative), and the
           pointwise standard deviation is sigma to 1e-12
  CLAIM 3  the band-limited covariance between two points, Y_p C Y_q',
           is the truncated Legendre series at their distance (addition
           theorem) to 1e-12 of C(0)
  CLAIM 4  non-stationary fields (range 1500 / 3000 km, sigma 2 / 1 in
           the eastern / western hemisphere, tanh transition): deep in
           each half the pointwise std is within 1 percent of the local
           sigma and the 0.139-correlation distance within 2 percent of
           the stationary covariance's with the local parameters - the
           prior IS local. Bounds set after one exploratory run at the
           same configuration (0.2 and 0.7 percent), recorded as such
  CLAIM 5  symmetric to machine precision and positive definite
  CLAIM 6  closed loop (SH basis, L 12, VAR(1) phi 0.6, 60 epochs, noise
           variance = mean process-noise variance, RTS smoother, 20
           seeds): with the TRUE non-stationary prior as Q the smoothed
           errors are honest (z-rms in 0.95..1.05 in every seed); its
           error is below that of a diagonal Q from a 60-epoch model
           series of a stationary process in every seed, and below that
           of the stationary prior of the mean parameters in every seed

Run: python3 tools/dev/validate_matern_prior.py   (numpy, mpmath)

Developed by Matthias Weigelt with the help of Claude (Opus 5.5),
2026-11-06.
"""
import os
import sys

import mpmath as mp
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import regional_oracle_lib as rl  # noqa: E402

RKM = 6378.1363
FAIL = []


def check(name, ok, msg):
    print(f"{'PASS' if ok else 'FAIL'} {name}: {msg}")
    if not ok:
        FAIL.append(name)


def legendre_series(lam, psi, N, alpha=2):
    """sum_n (2n+1)/(4 pi) (lam + n(n+1))^-alpha P_n(cos psi), n = 0..N."""
    x = np.cos(psi)
    p0, p1 = 1.0, x
    s = 1.0 / lam ** alpha + 3 * x / (lam + 2) ** alpha
    for n in range(2, N + 1):
        p0, p1 = p1, ((2 * n - 1) * x * p1 - (n - 1) * p0) / n
        s += (2 * n + 1) * p1 / (lam + n * (n + 1)) ** alpha
    return s / (4 * np.pi)


def closed_form(lam, psi):
    mp.mp.dps = 30

    def g(l):
        nu = -mp.mpf(1) / 2 + mp.sqrt(mp.mpf(1) / 4 - l)
        return mp.re(mp.legenp(nu, 0, -mp.cos(psi)) / (4 * mp.sin(mp.pi * nu)))
    return float(mp.diff(g, mp.mpf(lam)))


def galerkin(L, rho_fun, sig_fun, nmin=2, os_=2):
    """Cov of the index' (nmin..L) coefficients of the SPDE field."""
    idx0 = rl.sh_index(L, 0)
    _, _, LAT, LON, W = rl.quad_grid(L, os_)
    Y = rl.ylm(LAT, LON, idx0)
    n0 = idx0[0]
    latd, lond = np.degrees(LAT), np.degrees(LON)
    kap = np.sqrt(8) * RKM / rho_fun(latd, lond)
    nn = np.arange(nmin, L + 1)
    s = ((2 * nn + 1)[None, :] / (kap[:, None] ** 2
                                  + (nn * (nn + 1))[None, :]) ** 2).sum(1) / (4 * np.pi)
    itau = sig_fun(latd, lond) / np.sqrt(s)
    A = Y.T @ ((W * kap ** 2)[:, None] * Y) + np.diag(n0 * (n0 + 1.0))
    M = Y.T @ ((W * itau)[:, None] * Y)
    X = np.linalg.solve(A, M)
    C = X.T @ X / (4 * np.pi)
    keep = n0 >= nmin
    return C[np.ix_(keep, keep)], rl.sh_index(L, nmin)


def tr(lo):
    return np.tanh(np.sin(np.radians(lo)) / 0.3)


def rho_ns(la, lo):            # 1500 km east (lon 90), 3000 km west (270)
    return 1500 * np.sqrt(2) * np.exp(-0.5 * np.log(2) * tr(lo))


def sig_ns(la, lo):            # 2 east, 1 west
    return np.sqrt(2) * np.exp(0.5 * np.log(2) * tr(lo))


def point_std(C, idx, latd, lond):
    Y = rl.ylm(np.radians(np.atleast_1d(latd)), np.radians(np.atleast_1d(lond)), idx)
    return np.sqrt(np.einsum('ij,jk,ik->i', Y, C, Y))


def corr_distance(C, idx, lat0, lon0, level=0.139):
    d = np.linspace(0, 6000, 1201)
    lats = lat0 + np.degrees(d / RKM)
    Y0 = rl.ylm(np.radians([lat0]), np.radians([lon0]), idx)
    Yl = rl.ylm(np.radians(lats), np.radians(lon0) + 0 * lats, idx)
    cov = (Yl @ C @ Y0.T).ravel()
    var = np.einsum('ij,jk,ik->i', Yl, C, Yl)
    r = cov / np.sqrt(var * var[0])
    j = int(np.argmax(r < level))
    # linear interpolation between the bracketing samples
    return d[j - 1] + (r[j - 1] - level) / (r[j - 1] - r[j]) * (d[j] - d[j - 1])


# ---------------------------------------------------------------- CLAIM 1
worst = 0.0
for lam in (2.0, 50.0, 800.0):
    c0 = legendre_series(lam, 0.0, 100000)
    for psi in (0.3, 1.0, 2.5):
        e = abs(legendre_series(lam, psi, 100000) - closed_form(lam, psi)) / c0
        worst = max(worst, e)
check("CLAIM 1", worst < 1e-10,
      f"series vs closed form, worst {worst:.1e} of C(0) (lambda 2, 50, 800)")

# ---------------------------------------------------------------- CLAIM 2
L = 30
rho0, sig0 = 1500.0, 2.0
C, idx = galerkin(L, lambda a, b: rho0 + 0 * a, lambda a, b: sig0 + 0 * a)
n = idx[0]
k = np.sqrt(8) * RKM / rho0
nn = np.arange(2, L + 1)
tau2 = ((2 * nn + 1) / (k ** 2 + nn * (nn + 1)) ** 2).sum() / (4 * np.pi) / sig0 ** 2
D = 1 / (k ** 2 + n * (n + 1.0)) ** 2 / (4 * np.pi * tau2)
e2 = np.abs(C - np.diag(D)).max() / D.max()
sd = point_std(C, idx, [10.0, -40.0, 70.0, 89.0], [30.0, 200.0, 300.0, 0.0])
e2b = np.abs(sd / sig0 - 1).max()
check("CLAIM 2", e2 < 1e-12 and e2b < 1e-12,
      f"constant fields: diagonal to {e2:.1e}, pointwise std to {e2b:.1e}")

# ---------------------------------------------------------------- CLAIM 3
p, q = (10.0, 30.0), (35.0, 80.0)
Yp = rl.ylm(np.radians([p[0]]), np.radians([p[1]]), idx)
Yq = rl.ylm(np.radians([q[0]]), np.radians([q[1]]), idx)
cpq = float((Yp @ C @ Yq.T)[0, 0])
up, uq = rl.unit(np.radians(p[0]), np.radians(p[1])), rl.unit(np.radians(q[0]), np.radians(q[1]))
psi = np.arccos(np.clip(up @ uq, -1, 1))
x = np.cos(psi)
P = [1.0, x]
for m in range(2, L + 1):
    P.append(((2 * m - 1) * x * P[-1] - (m - 1) * P[-2]) / m)
ser = sum((2 * m + 1) * P[m] * D[np.where(n == m)[0][0]] for m in range(2, L + 1))
e3 = abs(cpq - ser) / sig0 ** 2
check("CLAIM 3", e3 < 1e-12, f"pair covariance = truncated series to {e3:.1e} of C(0)")

# ---------------------------------------------------------------- CLAIM 4
Cn, _ = galerkin(L, rho_ns, sig_ns)
rows = []
for lon0 in (90.0, 270.0):
    r_loc, s_loc = float(rho_ns(0, lon0)), float(sig_ns(0, lon0))
    Cl, _ = galerkin(L, lambda a, b, r=r_loc: r + 0 * a, lambda a, b, s=s_loc: s + 0 * a)
    sd_n = float(point_std(Cn, idx, 0.0, lon0)[0])
    dn, dl = corr_distance(Cn, idx, 0.0, lon0), corr_distance(Cl, idx, 0.0, lon0)
    rows.append((lon0, r_loc, s_loc, sd_n, dn, dl))
    print(f"   lon {lon0:5.1f}: range {r_loc:6.1f} km sigma {s_loc:.3f} | std {sd_n:.4f}, "
          f"0.139-distance {dn:7.1f} km (stationary local {dl:7.1f} km)")
e4s = max(abs(r[3] / r[2] - 1) for r in rows)
e4d = max(abs(r[4] / r[5] - 1) for r in rows)
check("CLAIM 4", e4s < 0.01 and e4d < 0.02,
      f"local std within {100 * e4s:.2f}%, local correlation distance within {100 * e4d:.2f}%")

# ---------------------------------------------------------------- CLAIM 5
ev = np.linalg.eigvalsh(Cn)
check("CLAIM 5", np.abs(Cn - Cn.T).max() == 0 and ev.min() > 0,
      f"symmetric, eigenvalues {ev.min():.2e}..{ev.max():.2e}")


# ---------------------------------------------------------------- CLAIM 6
def rts(Q, S0, Phi, y, Rv):
    P_ = Q.shape[0]
    x, Pm = np.zeros(P_), S0.copy()
    xf, Pf, xp, Pp = [], [], [], []
    for t in range(len(y)):
        if t > 0:
            x, Pm = Phi @ x, Phi @ Pm @ Phi.T + Q
        xp.append(x); Pp.append(Pm)
        G = Pm @ np.linalg.inv(Pm + Rv * np.eye(P_))
        x, Pm = x + G @ (y[t] - x), (np.eye(P_) - G) @ Pm
        xf.append(x); Pf.append(Pm)
    xs, Ps = xf[:], Pf[:]
    for t in range(len(y) - 2, -1, -1):
        J = Pf[t] @ Phi.T @ np.linalg.inv(Pp[t + 1])
        xs[t] = xf[t] + J @ (xs[t + 1] - xp[t + 1])
        Ps[t] = Pf[t] + J @ (Ps[t + 1] - Pp[t + 1]) @ J.T
    return np.array(xs), np.array([np.diag(v) for v in Ps])


L6, phi, T, Tm = 12, 0.6, 60, 60
Ct, _ = galerkin(L6, rho_ns, sig_ns)
Cs, _ = galerkin(L6, lambda a, b: 1500 * np.sqrt(2) + 0 * a,
                 lambda a, b: np.sqrt(2) + 0 * a)
P6 = Ct.shape[0]
Phi = phi * np.eye(P6)
Lt, Ls = np.linalg.cholesky(Ct), np.linalg.cholesky(Cs)
res = []
for seed in range(20):
    rng = np.random.default_rng(seed)

    def sim(Lc, nt):
        xx = np.zeros((nt, P6))
        xx[0] = Lc @ rng.standard_normal(P6) / np.sqrt(1 - phi ** 2)
        for t in range(1, nt):
            xx[t] = phi * xx[t - 1] + Lc @ rng.standard_normal(P6)
        return xx
    xt = sim(Lt, T)
    Rv = float(np.mean(np.diag(Ct)))
    y = xt + np.sqrt(Rv) * rng.standard_normal((T, P6))
    xm = sim(Ls, Tm)                                  # a stationary model series
    Qd = np.diag(np.var(xm, axis=0) * (1 - phi ** 2))
    row = []
    for Q in (Qd, Cs, Ct):
        xe, ve = rts(Q, Q / (1 - phi ** 2), Phi, y, Rv)
        e = xe - xt
        row.append((np.sqrt((e ** 2).mean()), np.sqrt((e ** 2 / ve).mean())))
    res.append(row)
r = np.array(res)
z = r[:, 2, 1]
gd, gs = r[:, 2, 0] / r[:, 0, 0], r[:, 2, 0] / r[:, 1, 0]
print(f"   z-rms diagonal/stationary/true: {r[:, 0, 1].mean():.3f} / "
      f"{r[:, 1, 1].mean():.3f} / {z.mean():.3f}")
print(f"   error ratio true/diagonal mean {gd.mean():.3f} worst {gd.max():.3f}; "
      f"true/stationary mean {gs.mean():.3f} worst {gs.max():.3f}")
check("CLAIM 6", z.min() >= 0.95 and z.max() <= 1.05 and gd.max() < 1 and gs.max() < 1,
      f"true prior z-rms {z.min():.3f}..{z.max():.3f}; below diagonal Q and "
      f"stationary prior in {np.sum(gd < 1)} and {np.sum(gs < 1)} of 20 seeds")

print("FAILED: " + ", ".join(FAIL) if FAIL else "ALL CLAIMS PASS")
sys.exit(1 if FAIL else 0)
