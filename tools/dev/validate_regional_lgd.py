#!/usr/bin/env python3
"""validate_regional_lgd: numerical pre-validation of WP8 row 8h.

Line-of-sight gravity differences (LGD) as observations of the regional
Kalman filter: shLowLevel.regionalNEQ(B, "lgd", ...) builds the design of
    LGD = e . (gB - gA),   e = (rB - rA) / |rB - rA|,
the lgdToolbox definition (its HANDOVER D1), from the positions of the two
satellites in the Earth-fixed frame of the field. The along-track operator
(band limitation, edge prediction) is lgdToolbox's and is passed in; the
design columns go through the SAME call as the data, data first, because
lgd.spectralOperator fits its predictor on that first column
(PredictionColumn) and applies the fitted map to every column.

The references are lgdToolbox's own forward models, re-implemented here:

  CLAIM 1  degrees 0 and 2 of the design, with C00 = 1 and
           C20 = -J2 / sqrt(5), reproduce lgdReferenceJ2 (point mass + J2
           in closed form, lgdToolbox realdata/lgdReferenceJ2.m): the total
           LGD to rounding, and the J2 part - three orders of magnitude
           smaller - to rounding of its own size.
  CLAIM 2  degree 0 reproduces lgdToolbox's oracle O2 (two Kepler orbits,
           LGD from mpmath at 50 digits, tests/refdata/kepler_pair.json):
           five of its rows, copied with full precision below.
  CLAIM 3  for a field of degrees 2..30 the design equals e . (gB - gA) with
           g from central differences of the potential in Cartesian
           coordinates - a route that never forms a north, east or up
           derivative - to the difference floor.
  CLAIM 4  the operator rule. (a) A linear band-pass applied to [y A]
           keeps the noise-free data on the design: W y = (W A) a. (b) An
           operator fitted on its first column (as lgd.spectralOperator's
           predictor is) does so only when the data are that column; the
           same operator called on the design alone misfits by the
           measured amount.

Run: python3 tools/dev/validate_regional_lgd.py  (nonzero exit on any
failed claim; prints the numbers the MATLAB tests quote).

Developed by Matthias Weigelt with the help of Claude (Opus 5.5),
2026-10-21.
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from regional_oracle_lib import sh_index, alf, rbf_basis  # noqa: E402


def alf_c(L, lat):
    """regional_oracle_lib.alf in complex arithmetic, for the complex step."""
    t, u = np.sin(lat), np.cos(lat)
    P = np.zeros((L + 1, L + 1, lat.size), dtype=complex)
    P[0, 0] = 1.0
    if L >= 1:
        P[1, 1] = np.sqrt(3.0) * u
    for mm in range(2, L + 1):
        P[mm, mm] = np.sqrt((2 * mm + 1) / (2 * mm)) * u * P[mm - 1, mm - 1]
    for mm in range(0, L + 1):
        for nn in range(mm + 1, L + 1):
            a = np.sqrt((2 * nn - 1) * (2 * nn + 1) / ((nn - mm) * (nn + mm)))
            P[nn, mm] = a * t * P[nn - 1, mm]
            if nn - 2 >= mm:
                b = np.sqrt((2 * nn + 1) * (nn + mm - 1) * (nn - mm - 1)
                            / ((nn - mm) * (nn + mm) * (2 * nn - 3)))
                P[nn, mm] -= b * P[nn - 2, mm]
    return P

FAIL = []
GM, R = 3.986004415e14, 6378136.3
J2 = 1.0826359e-3            # lgdReferenceJ2's default, = -sqrt(5) C20


def claim(ok, text):
    print(("PASS " if ok else "FAIL ") + text)
    if not ok:
        FAIL.append(text)


def geo(X):
    r = np.linalg.norm(X, axis=1)
    return np.arcsin(X[:, 2] / r), np.arctan2(X[:, 1], X[:, 0]), r


def gradient_design(idx, X, d):
    """d . grad of the potential design at ECEF positions X (M x 3): north,
    east and up rows as regionalNEQ forms them, with dPbar/dphi by a
    complex step (exact to rounding, no shared code with MATLAB's
    legendreALFDeriv)."""
    n, m, cs = idx
    L = n.max()
    lat, lon, r = geo(X)
    h = 1e-30
    Pc = alf_c(L, lat + 1j * h)
    P0 = Pc.real[n, m, :].T
    dP = (Pc.imag / h)[n, m, :].T
    c = np.cos(np.outer(lon, m))
    s = np.sin(np.outer(lon, m))
    trig = np.where(cs == 0, c, s)
    dtrig = np.where(cs == 0, -m * s, m * c)
    p = (n + 1.0)[None, :]
    rad = GM / R * (R / r)[:, None] ** p
    north = rad * dP * trig / r[:, None]
    east = rad * P0 * dtrig / (r * np.cos(lat))[:, None]
    up = -rad * P0 * trig * p / r[:, None]
    sp, cp = np.sin(lat), np.cos(lat)
    sl, cl = np.sin(lon), np.cos(lon)
    dn = d[:, 0] * (-sp * cl) + d[:, 1] * (-sp * sl) + d[:, 2] * cp
    de = d[:, 0] * (-sl) + d[:, 1] * cl
    du = d[:, 0] * (cp * cl) + d[:, 1] * (cp * sl) + d[:, 2] * sp
    return dn[:, None] * north + de[:, None] * east + du[:, None] * up


def lgd_design(idx, rA, rB):
    e = rB - rA
    e = e / np.linalg.norm(e, axis=1)[:, None]
    return gradient_design(idx, rB, e) - gradient_design(idx, rA, e)


def lgd_reference_j2(rA, rB, j2=J2):
    """lgdToolbox realdata/lgdReferenceJ2.m, line for line."""
    def g(r):
        rr = np.linalg.norm(r, axis=1)
        z2 = (r[:, 2] / rr) ** 2
        f = 1.5 * j2 * (R / rr) ** 2
        k = -GM / rr ** 3
        return k[:, None] * np.column_stack([r[:, 0] * (1 - f * (5 * z2 - 1)),
                                             r[:, 1] * (1 - f * (5 * z2 - 1)),
                                             r[:, 2] * (1 - f * (5 * z2 - 3))])
    d = rB - rA
    e = d / np.linalg.norm(d, axis=1)[:, None]
    return np.sum(e * (g(rB) - g(rA)), axis=1)


def pairs(rng, M, height=490e3, sep=220e3, maxlat=85):
    """M pairs at random places and headings, satellite B ahead of A."""
    lat = np.deg2rad(rng.uniform(-maxlat, maxlat, M))
    lon = rng.uniform(-np.pi, np.pi, M)
    r = R + height + rng.uniform(-20e3, 20e3, M)
    u = np.column_stack([np.cos(lat) * np.cos(lon), np.cos(lat) * np.sin(lon), np.sin(lat)])
    t = np.cross(u, rng.standard_normal((M, 3)))
    t /= np.linalg.norm(t, axis=1)[:, None]
    th = sep / r
    rA = r[:, None] * u
    rB = r[:, None] * (np.cos(th)[:, None] * u + np.sin(th)[:, None] * t)
    return rA, rB


rng = np.random.default_rng(20261021)

# ---------------------------------------------------------- CLAIM 1
idx02 = sh_index(2, 0)
rA, rB = pairs(rng, 200)
A02 = lgd_design(idx02, rA, rB)
x = np.zeros(idx02[0].size)
x[(idx02[0] == 0) & (idx02[1] == 0)] = 1.0
total = A02 @ x
x[(idx02[0] == 2) & (idx02[1] == 0) & (idx02[2] == 0)] = -J2 / np.sqrt(5)
total = A02 @ x
ref = lgd_reference_j2(rA, rB)
gsat = GM / (R + 490e3) ** 2          # |g| at the satellites, the scale of the rounding
e_tot = np.abs(total - ref).max() / gsat
j2part = total - A02[:, (idx02[0] == 0)] @ np.ones(1)
refj2 = ref - lgd_reference_j2(rA, rB, 0.0)
e_j2 = np.abs(j2part - refj2).max() / gsat
# rounding scales with |g| (each satellite's projection is O(|g|) before the
# difference), so both are quoted in units of |g|: a few eps is rounding
claim(e_tot < 2e-14 and e_j2 < 2e-14,
      "CLAIM 1  point mass + J2 = lgdReferenceJ2, 200 pairs: total %.1e |g|, J2 part "
      "%.1e |g| (|LGD| <= %.2f, J2 part <= %.1e m/s^2)" % (e_tot, e_j2, np.abs(ref).max(),
                                                        np.abs(refj2).max()))
print("    J2 part relative to the total: %.1e" % (np.abs(refj2).max() / np.abs(ref).max()))

# ---------------------------------------------------------- CLAIM 2
KEPLER = [  # (t, rA, rB, lgd) from lgdToolbox tests/refdata/kepler_pair.json (O2)
    (0.0, [4512997.478287725, 2694451.3364104237, 4409297.116052281],
     [4385663.580707991, 2623495.5872420436, 4576796.38841529], -0.2741007674070423),
    (1695.0, [-5070483.813394559, -2853662.7653212734, 3660682.922583132],
     [-5168144.096511687, -2916462.981551038, 3471124.4759983197], -0.2727220827822083),
    (3390.0, [-1462898.200822358, -978647.053148104, -6650454.147907468],
     [-1279284.0957959588, -871319.9938125537, -6703759.152552041], -0.26838615696227075),
    (5085.0, [5932954.93395928, 3432291.694546043, 342269.3481886636],
     [5917750.75935825, 3429061.7307759067, 560361.235087979], -0.2696566435557386),
    (6667.0, [-1455906.161136149, -706070.4417370488, 6673028.238021222],
     [-1638482.2633512663, -815622.220504692, 6618209.754707613], -0.2706971398324607),
]
kA = np.array([k[1] for k in KEPLER])
kB = np.array([k[2] for k in KEPLER])
klgd = np.array([k[3] for k in KEPLER])
idx0 = sh_index(0, 0)
k0 = lgd_design(idx0, kA, kB)[:, 0]
e_k = np.abs(k0 - klgd).max() / gsat
claim(e_k < 2e-14, "CLAIM 2  degree 0 = lgdToolbox O2 (mpmath, 50 digits), five rows: "
      "%.1e |g| (%.1e relative to the LGD)" % (e_k, e_k * gsat / np.abs(klgd).max()))

# ---------------------------------------------------------- CLAIM 3
L = 30
idx = sh_index(L, 2)
nn = idx[0]
xs = rng.standard_normal(nn.size) * 1e-9 / np.maximum(nn, 1) ** 2
rA, rB = pairs(rng, 40)
A = lgd_design(idx, rA, rB)


def potential(X):
    lat, lon, r = geo(X)
    n, m, cs = idx
    P = alf(L, lat)[n, m, :].T
    trig = np.where(cs == 0, np.cos(np.outer(lon, m)), np.sin(np.outer(lon, m)))
    return (GM / R * (R / r)[:, None] ** (n + 1.0)[None, :] * P * trig) @ xs


def grad_fd(X, hstep=1.0):
    g = np.zeros_like(X)
    for k in range(3):
        dX = np.zeros(3); dX[k] = hstep
        g[:, k] = (potential(X + dX) - potential(X - dX)) / (2 * hstep)
    return g


d = rB - rA
e = d / np.linalg.norm(d, axis=1)[:, None]
fd = np.sum(e * (grad_fd(rB) - grad_fd(rA)), axis=1)
e3 = np.abs(A @ xs - fd).max() / np.abs(fd).max()
claim(e3 < 1e-6, "CLAIM 3  degrees 2..30 against Cartesian differences of the potential: "
      "%.2e (difference floor, 1 m step)" % e3)

# ---------------------------------------------------------- CLAIM 4
Lb = 20
idxb, T, Proj, rank, Y, W, mask = rbf_basis(Lb, 50, 600)
K = T.shape[1]
a0 = rng.standard_normal(K) * 1e-10
# one along-track arc: M epochs on a polar circle at 490 km, B 220 km ahead
M = 1024
r0 = R + 490e3
th = np.linspace(0.6, 0.6 + 2 * np.pi * 0.9, M)
lam = 0.3 - 0.0004 * np.arange(M)
uA = np.column_stack([np.cos(th) * np.cos(lam), np.cos(th) * np.sin(lam), np.sin(th)])
th2 = th + 220e3 / r0
uB = np.column_stack([np.cos(th2) * np.cos(lam), np.cos(th2) * np.sin(lam), np.sin(th2)])
Ab = lgd_design(idxb, r0 * uA, r0 * uB) @ T
y = Ab @ a0
f = np.fft.rfftfreq(M, 5.0)
w = np.where((f > 1e-3) & (f < 2e-2), 1.0, 0.0)


def bandpass(X):
    return np.fft.irfft(w[:, None] * np.fft.rfft(X, axis=0), n=M, axis=0)


Z = bandpass(np.column_stack([y, Ab]))
e4a = np.abs(Z[:, 0] - Z[:, 1:] @ a0).max() / np.abs(Z[:, 0]).max()


def fitted_on_first(X):
    """A stand-in for a map fitted on column 1: remove from every column the
    least-squares multiple of column 1's own band-limited part, scaled by
    column 1's rms - linear in columns 2.., data-dependent through column 1."""
    s = np.sqrt(np.mean(X[:, 0] ** 2))
    return bandpass(X) / s


Zj = fitted_on_first(np.column_stack([y, Ab]))
e4b = np.abs(Zj[:, 0] - Zj[:, 1:] @ a0).max() / np.abs(Zj[:, 0]).max()
Za = fitted_on_first(Ab)
e4c = np.abs(Zj[:, 0] - Za @ a0).max() / np.abs(Zj[:, 0]).max()
claim(e4a < 1e-12 and e4b < 1e-12 and e4c > 1e-3,
      "CLAIM 4  operator rule: band-pass on [y A] %.1e; fitted on column 1, "
      "called on [y A] %.1e, called on A alone misfits by %.1f%%" % (e4a, e4b, 100 * e4c))

print("validate_regional_lgd: %d failed claim(s)" % len(FAIL))
sys.exit(1 if FAIL else 0)
