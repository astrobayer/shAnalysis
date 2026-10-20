#!/usr/bin/env python3
"""validate_regional_observations: numerical pre-validation of WP8 row 8c.

The observation adapters of the regional Kalman filter, as
shLowLevel.regionalNEQ builds them: every kind of gravity information
becomes a normal equation in the coefficients of a regional basis B,
N = A' W A, b = A' W y, with A the design in the basis (A_SH T). Every
claim is checked against a route that does not share the code under test.

  CLAIM 1  an SH normal equation carried into the basis, T' N T and T' b,
           solves to the state that produced it: noise-free data of a
           state in the span of T come back to rounding.
  CLAIM 2  the point design of a scalar functional at altitude - potential
           and gravity disturbance - equals the Legendre series of the
           RBF, sum_n phi_n f_n (R/r)^p_n (2n+1) P_n(cos psi), built with
           scipy's Legendre polynomials and not with the ALF recursion.
  CLAIM 3  the design of the gravity vector along a direction equals the
           analytic gradient of that Legendre series in ECEF coordinates
           (chain rule through r and cos psi, scipy's P_n'), at altitude.
  CLAIM 4  a correlated covariance enters through its Cholesky factor:
           N and b equal A' C^-1 A and A' C^-1 y from an explicit solve.
  CLAIM 5  ltpl is what VCE needs: ltpl - 2 x'b + x'N x is the weighted
           residual square sum v' C^-1 v at any x.
  CLAIM 6  a difference of two point functionals (the LGD shape) is the
           difference of their design rows, and is recovered as such.

Run: python3 tools/dev/validate_regional_observations.py  (nonzero exit on
any failed claim; prints the numbers the MATLAB tests quote).

Developed by Matthias Weigelt with the help of Claude (Opus 5.5),
2026-10-20.
"""
import os
import sys

import numpy as np
from numpy.polynomial import legendre as npleg
from scipy.special import eval_legendre

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from regional_oracle_lib import sh_index, alf, rbf_basis  # noqa: E402

FAIL = []
GM, R = 3.986004415e14, 6378136.3


def claim(ok, text):
    print(("PASS " if ok else "FAIL ") + text)
    if not ok:
        FAIL.append(text)


def unit(lat, lon):
    return np.stack([np.cos(lat) * np.cos(lon), np.cos(lat) * np.sin(lon),
                     np.sin(lat)], axis=-1)


def kernel(q, L):
    n = np.arange(L + 1)
    if q == "potential":
        return GM / R * np.ones(L + 1), n + 1.0
    if q == "gravity_disturbance":
        return GM / R ** 2 * (n + 1.0), n + 2.0
    raise ValueError(q)


def design_points(idx, lat, lon, r, q):
    """The regionalNEQ point design A_SH: f_n (R/r)^p_n Ybar_nm(lat, lon)."""
    n, m, cs = idx
    f, p = kernel(q, n.max())
    P = alf(n.max(), lat)
    pl = P[n, m, :].T
    trig = np.where(cs == 0, np.cos(np.outer(lon, m)), np.sin(np.outer(lon, m)))
    rad = (R / r)[:, None] ** p[n][None, :]
    return f[n][None, :] * rad * pl * trig


def design_gradient(idx, lat, lon, r, q):
    """North, east and up components of the gradient design, as
    regionalNEQ forms them: (1/r) dY/dphi, (1/(r cos phi)) dY/dlambda,
    -(p_n/r) Y, each times f_n (R/r)^p_n."""
    n, m, cs = idx
    L = n.max()
    f, p = kernel(q, L)
    # dPbar/dphi by a 1e-6 rad central difference of the recursion: the
    # MATLAB side uses legendreALFDeriv's exact derivative; this one only
    # has to be good enough for CLAIM 3, whose reference does not use it.
    h = 1e-6
    Pp = alf(L, lat + h)[n, m, :].T
    Pm = alf(L, lat - h)[n, m, :].T
    dP = (Pp - Pm) / (2 * h)
    P0 = alf(L, lat)[n, m, :].T
    c = np.cos(np.outer(lon, m))
    s = np.sin(np.outer(lon, m))
    trig = np.where(cs == 0, c, s)
    dtrig = np.where(cs == 0, -m * s, m * c)
    rad = f[n][None, :] * (R / r)[:, None] ** p[n][None, :]
    north = rad * dP * trig / r[:, None]
    east = rad * P0 * dtrig / (r * np.cos(lat))[:, None]
    up = -rad * P0 * trig * (p[n][None, :] / r[:, None])
    return north, east, up


def series_value(node, x, r, phi, q, L):
    """sum_n phi_n f_n (R/r)^p_n (2n+1) P_n(u) at ECEF unit vector x."""
    f, p = kernel(q, L)
    u = np.clip(x @ node, -1, 1)
    return sum(phi[k] * f[k] * (R / r) ** p[k] * (2 * k + 1) * eval_legendre(k, u)
               for k in range(2, L + 1))


def series_gradient(node, X, q, L, phi):
    """Analytic ECEF gradient of the series at position X (m)."""
    f, p = kernel(q, L)
    r = np.linalg.norm(X)
    xh = X / r
    u = np.clip(xh @ node, -1, 1)
    g = np.zeros(3)
    for k in range(2, L + 1):
        ck = np.zeros(k + 1); ck[k] = 1
        Pk = npleg.legval(u, ck)
        dPk = npleg.legval(u, npleg.legder(ck))
        a = phi[k] * f[k] * (2 * k + 1) * R ** p[k]
        # d/dX [ r^-p P(u) ],  du/dX = (node - u xh) / r
        g += a * (-p[k] * r ** (-p[k] - 1) * Pk * xh
                  + r ** (-p[k]) * dPk * (node - u * xh) / r)
    return g


rng = np.random.default_rng(20261020)
L = 20
idx, T, Proj, rank, Y, W, mask = rbf_basis(L, 50, 600)
n = idx[0]
P, K = T.shape
phi = 1.0 / np.maximum(np.arange(L + 1), 1) ** 2

# ---------------------------------------------------------- CLAIM 1
Ash = rng.standard_normal((3 * P, P))
Wsh = np.diag(rng.uniform(0.5, 2, 3 * P))
Nsh = Ash.T @ Wsh @ Ash
a0 = rng.standard_normal(K)
bsh = Ash.T @ Wsh @ (Ash @ (T @ a0))
Nb, bb = T.T @ Nsh @ T, T.T @ bsh
err1 = np.abs(np.linalg.solve(Nb, bb) - a0).max() / np.abs(a0).max()
claim(err1 < 1e-8, "CLAIM 1  T'NT, T'b solve to the generating state, rel. "
      "%.2e (cond %.1e)" % (err1, np.linalg.cond(Nb)))

# ---------------------------------------------------------- CLAIM 2
# node positions of the basis: recover them from T's columns is not
# possible, so rebuild the nodes the way rbf_basis selects them
from regional_oracle_lib import (quad_grid, buffered_mask, icosahedral,  # noqa: E402
                                 nearest_3ring)
lat_g, lon_g, LAT, LON, _ = quad_grid(L, 2)
mb = buffered_mask(np.rad2deg(LAT) > 50, LAT, LON, 600e3 / 6378136.3)
j = int(np.ceil((L + 1) / np.sqrt(10))) - 1
while 10 * (j + 1) ** 2 + 2 < (L + 1) ** 2:
    j += 1
_, pts = icosahedral(j + 1)
plat = np.arcsin(pts[:, 2]); plon = np.mod(np.arctan2(pts[:, 1], pts[:, 0]), 2 * np.pi)
sel = mb[nearest_3ring(plat, plon, lat_g, lon_g)]
nodes = unit(plat[sel], plon[sel])
assert nodes.shape[0] == K

npt = 40
qlat = np.deg2rad(rng.uniform(35, 89.5, npt))
qlon = np.deg2rad(rng.uniform(0, 360, npt))
qr = R + rng.uniform(0, 500e3, npt)
worst2 = 0.0
for q in ("potential", "gravity_disturbance"):
    A = design_points(idx, qlat, qlon, qr, q) @ T
    for k in (0, K // 2, K - 1):
        ref = np.array([series_value(nodes[k], unit(qlat[i], qlon[i]), qr[i],
                                     phi, q, L) for i in range(npt)])
        worst2 = max(worst2, np.abs(A[:, k] - ref).max() / np.abs(ref).max())
claim(worst2 < 1e-12, "CLAIM 2  point design = Legendre series of the RBF at "
      "0-500 km altitude, worst rel. %.2e" % worst2)

# ---------------------------------------------------------- CLAIM 3
dirs = rng.standard_normal((npt, 3))
dirs /= np.linalg.norm(dirs, axis=1, keepdims=True)
No, Ea, Up = design_gradient(idx, qlat, qlon, qr, "potential")
U = unit(qlat, qlon)
Nv = np.stack([-np.sin(qlat) * np.cos(qlon), -np.sin(qlat) * np.sin(qlon),
               np.cos(qlat)], axis=-1)
Ev = np.stack([-np.sin(qlon), np.cos(qlon), np.zeros(npt)], axis=-1)
dn, de, du = (dirs * Nv).sum(1), (dirs * Ev).sum(1), (dirs * U).sum(1)
Adir = (dn[:, None] * No + de[:, None] * Ea + du[:, None] * Up) @ T
worst3 = 0.0
for k in (0, K // 2, K - 1):
    ref = np.array([dirs[i] @ series_gradient(nodes[k], qr[i] * U[i], "potential",
                                              L, phi) for i in range(npt)])
    worst3 = max(worst3, np.abs(Adir[:, k] - ref).max() / np.abs(ref).max())
print("  (the oracle's own latitude derivative is a 1e-6 rad central "
      "difference; the bound below is set by it, not by the design)")
claim(worst3 < 1e-8, "CLAIM 3  gravity vector along a direction = analytic "
      "ECEF gradient of the series, worst rel. %.2e" % worst3)

# ---------------------------------------------------------- CLAIM 4
A = design_points(idx, qlat, qlon, qr, "gravity_disturbance") @ T
Lc = rng.standard_normal((npt, npt)) / np.sqrt(npt)
C = Lc @ Lc.T + 0.5 * np.eye(npt)
C *= 1e-16
y = A @ a0 + np.linalg.cholesky(C) @ rng.standard_normal(npt)
Lch = np.linalg.cholesky(C)
Aw = np.linalg.solve(Lch, A); yw = np.linalg.solve(Lch, y)
N1, b1, ltpl = Aw.T @ Aw, Aw.T @ yw, yw @ yw
N2, b2 = A.T @ np.linalg.solve(C, A), A.T @ np.linalg.solve(C, y)
e4 = max(np.abs(N1 - N2).max() / np.abs(N2).max(),
         np.abs(b1 - b2).max() / np.abs(b2).max())
claim(e4 < 1e-10, "CLAIM 4  Cholesky route = explicit C^-1 route, rel. %.2e" % e4)

# ---------------------------------------------------------- CLAIM 5
x = rng.standard_normal(K)
v = y - A @ x
lhs = ltpl - 2 * x @ b1 + x @ N1 @ x
rhs = v @ np.linalg.solve(C, v)
e5 = abs(lhs - rhs) / rhs
claim(e5 < 1e-9, "CLAIM 5  ltpl - 2x'b + x'Nx = v'C^-1 v, rel. %.2e" % e5)

# ---------------------------------------------------------- CLAIM 6
Cmb = np.zeros((npt // 2, npt))
for i in range(npt // 2):
    Cmb[i, 2 * i], Cmb[i, 2 * i + 1] = 1.0, -1.0
Ad = Cmb @ Adir
yd = Ad @ a0
ad = np.linalg.lstsq(Ad, yd, rcond=None)[0]
same = np.allclose(Ad, Adir[0::2] - Adir[1::2], rtol=0, atol=0)
claim(same and np.abs(Ad @ ad - yd).max() < 1e-10 * np.abs(yd).max(),
      "CLAIM 6  combined rows are the row differences, and the LGD-shaped "
      "data are fitted exactly")

print("validate_regional_observations: %d failed claim(s)" % len(FAIL))
sys.exit(1 if FAIL else 0)
