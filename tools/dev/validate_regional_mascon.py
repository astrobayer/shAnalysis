#!/usr/bin/env python3
"""validate_regional_mascon: numerical pre-validation of WP9 row 9c.

Independent numpy/scipy port of the mascon basis that
shLowLevel.regionalBasis(..., Type = "mascon") implements, written
BEFORE the MATLAB code (CLAUDE.md section 2).

A mascon k is a spherical cap of angular radius psi0 centred on the node
x_k, carrying a uniform layer of 1 m equivalent water height. Its
indicator chi(psi) = 1 for psi <= psi0 expands in Legendre polynomials,

    chi(psi) = sum_n c_n P_n(cos psi),
    c_0 = (1 - t0) / 2,   c_n = (P_{n-1}(t0) - P_{n+1}(t0)) / 2,
    t0 = cos psi0,

(from (2n+1) P_n = P'_{n+1} - P'_{n-1}), and by the addition theorem its
4pi-normalised EWH coefficients are c_n / (2n+1) Ybar_nm(x_k). Dividing
by the EWH kernel f_n = R rho_ave / (3 rho_w) (2n+1) / (1 + k'_n) of
shLowLevel.kernelFactors gives the Stokes coefficients, so

    T(:, k) = c_n / ((2n+1) f_n) .* Ybar(x_k)'

and a mascon basis is an RBF basis with the cap kernel phi_n =
c_n / ((2n+1) f_n). Its coefficients a are the caps' EWH in metres.

  CLAIM 0  the closed form of c_n equals (2n+1)/2 times the integral of
           P_n over [t0, 1]: against 40-digit mpmath values to n = 720 for
           four cap radii, and against Gauss-Legendre quadrature (whose
           own rounding is the larger of the two).
  CLAIM 1  telescoping: the band-limited cap's value at its centre is
           sum_{n=0}^{L} c_n = 1 - (P_L(t0) + P_{L+1}(t0)) / 2, exactly;
           the printed values say how far a cap band-limited at nmax is
           from a cap (the help quotes them).
  CLAIM 2  a column of T, synthesised as EWH (f_n Ybar T), is the
           truncated series sum_{n=nmin}^{L} c_n P_n(cos psi), checked
           against scipy's eval_legendre - not the ALF recursion that
           built T.
  CLAIM 3  with nmin = 0 the global mean of the synthesised cap is its
           area fraction (1 - t0) / 2, on the Gauss-Legendre grid.
  CLAIM 4  the equal-area default radius, cos psi0 = 1 - 2 / N for the N
           nodes of the global grid, makes the N cap areas sum to 4 pi;
           the radius at nmax 30 and 60 is printed.
  CLAIM 5  projector over a polar-cap region (nmax 30, coarse level so
           the caps are resolvable): full rank, Proj T = I, the normal
           equations hold, and a field built of caps is recovered.
  CLAIM 6  a uniform 1 m layer over the region, projected, gives cap
           EWH near 1 in the interior - measured, so that the help can
           say what a mascon coefficient means for a smooth load.

Run: python3 tools/dev/validate_regional_mascon.py   (nonzero exit on any
failed claim; prints the numbers the MATLAB tests quote).

Developed by Matthias Weigelt with the help of Claude (Opus 5.5),
2026-10-23.
"""
import os
import sys

import numpy as np
from scipy.special import eval_legendre

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import regional_oracle_lib as rl  # noqa: E402

R = 6378136.3
RHO_AVE, RHO_W = 5517.0, 1000.0
FAILED = []


def check(name, ok, msg):
    print(("PASS " if ok else "FAIL ") + name + ": " + msg)
    if not ok:
        FAILED.append(name)


def cap_coeffs(L, t0):
    """c_n for n = 0..L, the closed form."""
    n = np.arange(L + 1)
    c = np.empty(L + 1)
    c[0] = (1 - t0) / 2
    c[1:] = (eval_legendre(n[1:] - 1, t0) - eval_legendre(n[1:] + 1, t0)) / 2
    return c


def love(L):
    n = np.arange(L + 1)
    return -0.30 * n / (n + 3.0)   # synthetic, as testCorrectness uses


def ewh_kernel(L, kn):
    n = np.arange(L + 1)
    return R * RHO_AVE / (3 * RHO_W) * (2 * n + 1) / (1 + kn)


def mascon_T(L, nodes_lat, nodes_lon, t0, idx):
    c = cap_coeffs(L, t0)
    n = np.arange(L + 1)
    phi = c / ((2 * n + 1) * ewh_kernel(L, love(L)))
    return phi[idx[0]][:, None] * rl.ylm(nodes_lat, nodes_lon, idx).T, phi


# ---- CLAIM 0: closed form against 40-digit references and quadrature
# The quadrature carries its own rounding: 1200 terms times (2n+1)/2 up
# to 720, so its error grows with the cap radius (2.8e-13 absolute at
# 10 deg). The mpmath values are the reference the closed form is held
# to; the quadrature confirms the formula, not the digits.
import mpmath as mp
mp.mp.dps = 40
worst_mp, worst_q = 0.0, 0.0
for psi0 in (0.5, 1.5, 3.0, 10.0):
    t0 = np.cos(np.deg2rad(psi0))
    T0 = mp.mpf(t0)
    c = cap_coeffs(720, t0)
    ks = np.arange(0, 721, 20)
    ex = np.array([float((1 - T0) / 2) if k == 0 else
                   float((mp.legendre(k - 1, T0) - mp.legendre(k + 1, T0)) / 2)
                   for k in ks])
    worst_mp = max(worst_mp, np.max(np.abs(c[ks] - ex)))
    x, w = np.polynomial.legendre.leggauss(1200)
    t = t0 + (1 - t0) * (x + 1) / 2
    wt = w * (1 - t0) / 2
    q = np.array([(2 * k + 1) / 2 * wt @ eval_legendre(k, t) for k in ks])
    worst_q = max(worst_q, np.max(np.abs(q - ex)))
check("CLAIM 0", worst_mp < 1e-15 and worst_q < 1e-12,
      "closed form = 40-digit reference to %.1e, quadrature to %.1e (absolute)"
      % (worst_mp, worst_q))

# ---- CLAIM 1: telescoping centre value
worst = 0.0
for psi0 in (0.5, 1.81, 3.0):
    t0 = np.cos(np.deg2rad(psi0))
    for L in (30, 60, 96, 720):
        s = cap_coeffs(L, t0).sum()
        closed = 1 - (eval_legendre(L, t0) + eval_legendre(L + 1, t0)) / 2
        worst = max(worst, abs(s - closed))
check("CLAIM 1", worst < 1e-13, "sum c_n = 1 - (P_L + P_L+1)/2 to %.1e" % worst)
for psi0, L in ((3.62, 30), (1.81, 60), (3.0, 60), (1.5, 96)):
    t0 = np.cos(np.deg2rad(psi0))
    v = 1 - (eval_legendre(L, t0) + eval_legendre(L + 1, t0)) / 2
    print("      centre of a %.2f deg cap band-limited at nmax %d: %.3f"
          % (psi0, L, v))

# ---- CLAIM 2: a column synthesises to the truncated Legendre series
L = 30
idx = rl.sh_index(L)
t0 = np.cos(np.deg2rad(4.0))
nl = np.deg2rad(np.array([90.0, -90.0, 37.0, -12.5]))
no = np.deg2rad(np.array([0.0, 0.0, 211.0, 15.0]))
T, phi = mascon_T(L, nl, no, t0, idx)
lat = np.deg2rad(np.linspace(-89.9, 89.9, 50))
lon = np.deg2rad(np.mod(137.508 * np.arange(50), 360))
fk = ewh_kernel(L, love(L))
Yp = rl.ylm(lat, lon, idx)
F = (Yp * fk[idx[0]]) @ T
c = cap_coeffs(L, t0)
worst = 0.0
for k in range(4):
    cpsi = np.clip(np.sin(lat) * np.sin(nl[k]) + np.cos(lat) * np.cos(nl[k])
                   * np.cos(lon - no[k]), -1, 1)
    ref = sum(c[n] * eval_legendre(n, cpsi) for n in range(2, L + 1))
    worst = max(worst, np.max(np.abs(F[:, k] - ref)) / np.max(np.abs(ref)))
check("CLAIM 2", worst < 1e-12,
      "EWH synthesis of T = truncated cap series to %.2e" % worst)
CLAIM2 = worst

# ---- CLAIM 3: global mean = area fraction (nmin 0)
idx0 = rl.sh_index(L, nmin=0)
T0, _ = mascon_T(L, nl[2:3], no[2:3], t0, idx0)
_, _, LAT, LON, W = rl.quad_grid(L, 2)
Y0 = rl.ylm(LAT, LON, idx0)
field = (Y0 * fk[idx0[0]]) @ T0[:, 0]
mean = W @ field     # W sums to 1 (w/(2 nlon), leggauss weights sum to 2)
err3 = abs(mean - (1 - t0) / 2) / ((1 - t0) / 2)
check("CLAIM 3", err3 < 1e-12,
      "global mean %.6e = area fraction %.6e (rel %.1e)"
      % (mean, (1 - t0) / 2, err3))

# ---- CLAIM 4: equal-area default
for LL in (30, 60):
    j = int(np.ceil((LL + 1) / np.sqrt(10))) - 1
    while 10 * (j + 1) ** 2 + 2 < (LL + 1) ** 2:
        j += 1
    N = 10 * (j + 1) ** 2 + 2
    psi0 = np.arccos(1 - 2 / N)
    tot = N * 2 * np.pi * (1 - np.cos(psi0))
    check("CLAIM 4 nmax %d" % LL, abs(tot - 4 * np.pi) < 1e-12,
          "level %d, %d nodes, cap radius %.4f deg = %.1f km, total area / 4pi = %.15f"
          % (j, N, np.rad2deg(psi0), psi0 * R / 1e3, tot / (4 * np.pi)))

# ---- CLAIM 5: projector over a polar cap at a coarse level
L = 30
idx = rl.sh_index(L)
lat_g, lon_g, LAT, LON, W = rl.quad_grid(L, 2)
mask = rl.buffered_mask(np.rad2deg(LAT) > 50, LAT, LON, 600e3 / R)
f = 7                                     # level 6: 492 nodes globally
_, pts = rl.icosahedral(f)
N = pts.shape[0]
plat = np.arcsin(pts[:, 2])
plon = np.mod(np.arctan2(pts[:, 1], pts[:, 0]), 2 * np.pi)
sel = mask[rl.nearest_3ring(plat, plon, lat_g, lon_g)]
t0 = 1 - 2 / N
T, phi = mascon_T(L, plat[sel], plon[sel], t0, idx)
Y = rl.ylm(LAT, LON, idx)
Kq = Y.T @ ((W * mask)[:, None] * Y)
Proj, rank = rl.projector(T, (Kq + Kq.T) / 2)
K = T.shape[1]
idn = np.max(np.abs(Proj @ T - np.eye(K)))
rng = np.random.default_rng(9)
x = rng.standard_normal(idx[0].size) / np.maximum(idx[0], 1) ** 2
ne = np.max(np.abs(T.T @ Kq @ (x - T @ (Proj @ x)))) / np.max(np.abs(T.T @ Kq @ x))
a0 = rng.standard_normal(K) * 0.1
rec = np.max(np.abs(Proj @ (T @ a0) - a0)) / np.max(np.abs(a0))
check("CLAIM 5", rank == K and idn < 1e-9 and ne < 1e-10 and rec < 1e-9,
      "%d of %d nodes, rank %d, |Proj T - I| %.1e, normal eqs %.1e, "
      "recovery %.1e, cap radius %.3f deg"
      % (K, N, rank, idn, ne, rec, np.rad2deg(np.arccos(t0))))
print("      cond(T'KT) = %.2e" % np.linalg.cond(T.T @ Kq @ T))

# ---- CLAIM 6: a uniform 1 m layer over the buffered region
fk = ewh_kernel(L, love(L))
# a 1 m layer over the whole sphere has only degree 0; restrict to the
# buffered region's quadrature points instead and analyse it to SH (EWH)
layer = mask.astype(float)
ewh_c = Y.T @ (W * layer)    # 4pi-normalised Ybar: mean(Ybar^2) = 1, W sums to 1
x_layer = ewh_c / fk[idx[0]]
a = Proj @ x_layer
# interior nodes: 1500 km inside the buffered edge, which lies at 50 deg - 600 km
interior = np.rad2deg(plat[sel]) > 50 + np.rad2deg(900e3 / R)
ai = a[interior]
check("CLAIM 6", ai.size > 5 and abs(np.median(ai) - 1) < 0.1,
      "%d interior caps: median EWH %.3f, range %.3f .. %.3f (all %d: %.3f .. %.3f)"
      % (ai.size, np.median(ai), ai.min(), ai.max(), a.size, a.min(), a.max()))

print()
print("CLAIM2 worst = %.3e (MATLAB bound 3x)" % CLAIM2)
if FAILED:
    print("FAILED: " + ", ".join(FAILED))
    sys.exit(1)
print("all claims pass")
