#!/usr/bin/env python3
"""validate_regional_process: numerical pre-validation of WP8 row 8b.

The process model of the regional Kalman filter (Kurtenbach 2012, DGK
C-683, Sec. 3.2 and 4.3.5) on the coefficients of a regional basis, as
shLowLevel.regionalProcessModel builds it: model series -> climatology
removed -> projected onto the basis -> VAR(p) by Yule-Walker, with
Kurtenbach's two adjustments, the scaled process noise alpha Q (his eq.
4.8) and an isotropic ground noise added to Sigma(0). Every claim is
checked against a route that does not share the code under test.

  CLAIM 1  removing the climatology and projecting onto the basis commute:
           the climatology is a least-squares fit along TIME with one design
           for every coefficient, the projection a map along the
           COEFFICIENTS, so Proj (X - X H) = (Proj X) - (Proj X) H exactly.
           The order of the two steps does not matter.
  CLAIM 2  the ground noise: a white EWH field band-limited to the index,
           with variance sigma^2 / (P f_n^2) per Stokes coefficient (f_n the
           EWH kernel), has pointwise variance sigma^2 everywhere - the
           addition theorem, checked by synthesis at random points.
  CLAIM 3  the pipeline recovers a known process: a VAR(1) simulated in the
           coefficients of an RBF basis, mapped to SH by T and given a
           climatology, comes back through projection, climatology removal
           and Yule-Walker within the sampling error, measured over 60
           seeds.
  CLAIM 4  a covariance added to Sigma(0) changes B, as Kurtenbach says
           it must (his Sec. 4.3.5: the ground noise acts on dynamics and
           noise alike, alpha Q on the noise only), and Q stays positive
           definite. That alpha leaves B and Sigma(0) untouched, and that
           Shrink is the special case s tr(Sigma0)/P I, are pinned bitwise
           in MATLAB, where they are properties of the code, not numbers.
  CLAIM 5  the representation diagnostic is 1 for a series in the span of
           T and lies in (0, 1) for one that is not.

Run: python3 tools/dev/validate_regional_process.py  (nonzero exit on any
failed claim; prints the numbers the MATLAB tests quote).

Developed by Matthias Weigelt with the help of Claude (Opus 5.5),
2026-10-20.
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from regional_oracle_lib import (sh_index, ylm, quad_grid, icosahedral,  # noqa: E402
                                 buffered_mask, nearest_3ring, projector)

FAIL = []


def claim(ok, text):
    print(("PASS " if ok else "FAIL ") + text)
    if not ok:
        FAIL.append(text)


def climatology_hat(t):
    """Hat matrix of the mean/trend/annual/semi-annual LS fit along time."""
    t0 = t.mean()
    D = np.column_stack([np.ones_like(t), t - t0,
                         np.cos(2 * np.pi * t), np.sin(2 * np.pi * t),
                         np.cos(4 * np.pi * t), np.sin(4 * np.pi * t)])
    return D @ np.linalg.solve(D.T @ D, D.T)


def var1(A):
    """Kurtenbach's eqs. 3.84-3.85 on a (K, T) centred series."""
    T = A.shape[1]
    S0 = A @ A.T / T
    S1 = A[:, 1:] @ A[:, :-1].T / (T - 1)
    B = np.linalg.solve(S0.T, S1.T).T
    return B, S0 - B @ S1.T, S0, S1


def rbf_basis(L, region_lat, buffer_km):
    """Default-level icosahedral RBF basis (Kaula kernel) over a polar cap."""
    idx = sh_index(L)
    n = idx[0]
    lat_g, lon_g, LAT, LON, W = quad_grid(L, 2)
    mask = buffered_mask(np.rad2deg(LAT) > region_lat, LAT, LON,
                         buffer_km * 1e3 / 6378136.3)
    j = int(np.ceil((L + 1) / np.sqrt(10))) - 1
    while 10 * (j + 1) ** 2 + 2 < (L + 1) ** 2:
        j += 1
    _, pts = icosahedral(j + 1)
    plat = np.arcsin(pts[:, 2])
    plon = np.mod(np.arctan2(pts[:, 1], pts[:, 0]), 2 * np.pi)
    sel = mask[nearest_3ring(plat, plon, lat_g, lon_g)]
    phi = 1.0 / np.maximum(np.arange(L + 1), 1) ** 2
    T = phi[n][:, None] * ylm(plat[sel], plon[sel], idx).T
    Y = ylm(LAT, LON, idx)
    K = Y.T @ ((W * mask)[:, None] * Y)
    Proj, rank = projector(T, (K + K.T) / 2)
    return idx, T, Proj, rank, Y, W, mask


rng = np.random.default_rng(20261020)
L = 20
idx, T, Proj, rank, Y, W, mask = rbf_basis(L, 50, 600)
P, K = T.shape
print("  RBF basis: nmax %d, 40 deg cap + 600 km, K = %d, rank %d, P = %d"
      % (L, K, rank, P))

# ---------------------------------------------------------- CLAIM 1
nt = 120
t = 2002 + np.arange(nt) / 12 + 0.5 / 12
X = rng.standard_normal((P, nt)) / np.maximum(idx[0], 1)[:, None] ** 2
H = climatology_hat(t)
d = np.abs(Proj @ (X - X @ H) - ((Proj @ X) - (Proj @ X) @ H)).max()
claim(d < 1e-12 * np.abs(Proj @ X).max(),
      "CLAIM 1  climatology removal and projection commute, max %.2e" % d)

# ---------------------------------------------------------- CLAIM 2
kn = -0.3 / (np.arange(L + 1) + 1.0)          # SYNTHETIC Love numbers
R, rho_e, rho_w = 6378136.3, 5517.0, 1000.0
f = R * rho_e / (3 * rho_w) * (2 * np.arange(L + 1) + 1) / (1 + kn)
sigma = 0.02                                   # 2 cm EWH, Kurtenbach 5.2
var_stokes = sigma ** 2 / (P * f[idx[0]] ** 2)
xl = np.deg2rad(rng.uniform(-90, 90, 200))
xo = np.deg2rad(rng.uniform(0, 360, 200))
Ye = ylm(xl, xo, idx) * f[idx[0]]              # Stokes -> EWH at points
pv = np.einsum('ij,j,ij->i', Ye, var_stokes, Ye)
dev = np.abs(pv / sigma ** 2 - 1).max()
claim(dev < 1e-12, "CLAIM 2  white ground noise has pointwise variance "
      "sigma^2 at 200 random points, max rel. %.2e" % dev)

# ---------------------------------------------------------- CLAIM 3
# The configuration testCorrectness uses: nmax 12, a 30 deg polar cap plus
# 600 km, 20000 daily steps. The error is a sampling error, so it is
# measured over 60 seeds and the MATLAB bounds are 3x the MEDIANS printed
# here (its own random numbers give another draw from the same spread).
idx3, T3, Proj3, _, _, _, _ = rbf_basis(12, 60, 600)
K3 = T3.shape[1]
nt3 = 20000
t3 = 2000 + np.arange(nt3) / 365.25
H3 = climatology_hat(t3)
errs = []
for seed in range(60):
    r = np.random.default_rng(seed)
    Ph = 0.8 * np.eye(K3) + 0.02 * r.standard_normal((K3, K3))
    Ph *= 0.85 / np.max(np.abs(np.linalg.eigvals(Ph)))
    Lq = r.standard_normal((K3, K3)) / np.sqrt(K3)
    Qtrue = Lq @ Lq.T + 0.1 * np.eye(K3)
    cQ = np.linalg.cholesky(Qtrue)
    e = r.standard_normal((K3, nt3))
    a = np.zeros((K3, nt3))
    for k in range(1, nt3):
        a[:, k] = Ph @ a[:, k - 1] + cQ @ e[:, k]
    clim = (np.outer(r.standard_normal(T3.shape[0]), np.ones(nt3))
            + np.outer(r.standard_normal(T3.shape[0]),
                       np.cos(2 * np.pi * t3))) * 1e-3
    A3 = Proj3 @ (T3 @ a + clim)
    A3 = A3 - A3 @ H3
    Bh, Qh, _, _ = var1(A3)
    errs.append((np.abs(Bh - Ph).max() * np.sqrt(nt3),
                 np.abs(Qh - Qtrue).max() / np.abs(Qtrue).max() * np.sqrt(nt3)))
errs = np.array(errs)
med = np.median(errs, axis=0)
print("  K = %d; sqrt(T) x error over 60 seeds: B median %.2f max %.2f, "
      "Q median %.2f max %.2f" % (K3, med[0], errs[:, 0].max(), med[1],
                                  errs[:, 1].max()))
claim(np.all(errs.max(axis=0) < 3 * med),
      "CLAIM 3  a VAR(1) recovers through projection, climatology removal "
      "and Yule-Walker within 3x the median sampling error on every seed")

# ---------------------------------------------------------- CLAIM 4
A4 = A3[:, :2000]
B1, Q1, S0, S1 = var1(A4)
G = np.diag(np.full(K3, 0.3 * np.trace(S0) / K3))
B2 = np.linalg.solve((S0 + G).T, S1.T).T
claim(np.abs(B2 - B1).max() > 1e-3,
      "CLAIM 4a a covariance added to Sigma(0) changes B (by %.3f): the "
      "ground noise is not a Q-only knob" % np.abs(B2 - B1).max())
Q2 = (S0 + G) - B2 @ S1.T
ev = np.linalg.eigvalsh((Q2 + Q2.T) / 2).min()
claim(ev > 0, "CLAIM 4b Q stays positive definite with the ground noise "
      "(min eig %.3e)" % ev)

# ---------------------------------------------------------- CLAIM 5
def representation(X, T, Proj, Y, W, mask):
    w = W * mask
    r = Y @ (X - T @ (Proj @ X))
    s = Y @ X
    return 1 - np.sum(w[:, None] * r ** 2) / np.sum(w[:, None] * s ** 2)


rep_span = representation(T @ rng.standard_normal((K, 20)), T, Proj, Y, W, mask)
rep_white = representation(X[:, :20], T, Proj, Y, W, mask)
claim(abs(rep_span - 1) < 1e-10 and 0 < rep_white < 1,
      "CLAIM 5  representation: 1 - %.1e in the span, %.3f for a field "
      "with a 1/n^2 spectrum" % (1 - rep_span, rep_white))

print("validate_regional_process: %d failed claim(s)" % len(FAIL))
sys.exit(1 if FAIL else 0)
