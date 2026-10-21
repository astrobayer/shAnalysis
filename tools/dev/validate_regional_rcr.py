#!/usr/bin/env python3
"""validate_regional_rcr: numerical pre-validation of WP8 row 8e.

Remove-compute-restore for the regional Kalman filter: a global background
b(t) is removed from the observations before they become normal equations
in the basis and restored afterwards, x = b + T a. Neither Woehnke et al.
(2025) nor Steffen et al. (2026) apply it - Steffen et al. name it as the
way to treat long wavelengths and signal outside the region - so it is
checked here on its own terms: what it does exactly, and what it buys in a
closed loop with signal outside the region.

  CLAIM 1  the restore algebra is exact. With the process model held
           fixed, the chain is linear in its data, so a background c z
           (a fraction c of an outside signal z) gives
             x(obs; c z) = c z + x(obs_in) + (1 - c) (x(obs_in + z) - x(obs_in)):
           the leakage of z is scaled by exactly 1 - c. Checked to
           rounding, the observation climatology removed and restored as
           the chain does.
  CLAIM 2  in a closed loop (nmax 30, region = cap north of 60 N, basis
           grown by 600 km, 2 cm EWH of signal inside, a 30 cm seasonal
           neighbour at 52 N and a degree-2..4 random walk; the
           observation climatology is NOT removed, Climatology = false, so
           that only the background differs between the cases), the outside
           signal raises the grid RMS over the region in every one of five
           seeds, and with a background holding 80% of it the grid and
           basin-mean RMS are within 5% of the error the same data give
           without any outside signal.
  CLAIM 3  what a background must not be: the observation's own
           unfiltered low degrees, restored as they are, put their noise
           back and do worse than no background at all.
  CLAIM 4  the process model need not come from the reduced model series:
           estimated from the full one it is no worse (at most 2% in grid
           RMS) - an overestimated process variance costs little.
  CLAIM 5  Woehnke's observation area (EWH on the region grown by 300 km,
           covariance propagated plus kappa I, kappa = 1e-12) helps in the
           median when no background is removed, and costs in every seed
           when one is: SH-coefficient
           observations carry more than their synthesis on an area. Hence
           it is not a chain option; point records (regionalNEQ "points")
           already give it to whoever has gridded data.

Printed beside the claims, not claimed: the same loop with the
observation climatology removed and restored (the chain's default). The
climatology fitted to noisy observations is restored through T Proj c
unfiltered, so its noise comes back - with this fixture's noise, which
rises to 3 cm per coefficient at degree 30, it dominates the error.

Run: python3 tools/dev/validate_regional_rcr.py  (nonzero exit on any
failed claim; prints the numbers the MATLAB tests and docs quote).

Developed by Matthias Weigelt with the help of Claude (Opus 5.5),
2026-10-21.
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from regional_oracle_lib import (sh_index, ylm, quad_grid, icosahedral,  # noqa: E402
                                 nearest_3ring, buffered_mask, projector, unit)

FAIL = []
R = 6378136.3


def claim(ok, text):
    print(("PASS " if ok else "FAIL ") + text)
    if not ok:
        FAIL.append(text)


def basis(L, cap, nmin, buf_km=600):
    """Default-level icosahedral Kaula RBF over a polar cap, Nmin = nmin."""
    idx = sh_index(L, nmin)
    lat_g, lon_g, LAT, LON, W = quad_grid(L, 2)
    mask = buffered_mask(np.rad2deg(LAT) > cap, LAT, LON, buf_km * 1e3 / R)
    j = int(np.ceil((L + 1) / np.sqrt(10))) - 1
    while 10 * (j + 1) ** 2 + 2 < (L + 1) ** 2:
        j += 1
    _, pts = icosahedral(j + 1)
    plat = np.arcsin(pts[:, 2])
    plon = np.mod(np.arctan2(pts[:, 1], pts[:, 0]), 2 * np.pi)
    sel = mask[nearest_3ring(plat, plon, lat_g, lon_g)]
    phi = 1.0 / np.maximum(np.arange(L + 1), 1) ** 2
    T = phi[idx[0]][:, None] * ylm(plat[sel], plon[sel], idx).T
    Y = ylm(LAT[mask], LON[mask], idx)
    K = Y.T @ (W[mask][:, None] * Y)
    Proj, _ = projector(T, (K + K.T) / 2)
    return idx, T, Proj


def var1(X):
    nt = X.shape[1]
    S0 = X @ X.T / nt
    S1 = X[:, 1:] @ X[:, :-1].T / (nt - 1)
    Phi = np.linalg.solve(S0.T, S1.T).T
    Q = S0 - Phi @ S1.T
    return Phi, (Q + Q.T) / 2, (S0 + S0.T) / 2


def hat(t):
    D = np.column_stack([np.ones_like(t), t - t.mean(), np.cos(2 * np.pi * t),
                         np.sin(2 * np.pi * t), np.cos(4 * np.pi * t),
                         np.sin(4 * np.pi * t)])
    return D @ np.linalg.solve(D.T @ D, D.T)


def smooth(Phi, Q, S0, neqs):
    """kalmanFilter (NEQ form) + rtsSmoother, states only."""
    K = Phi.shape[0]
    x, P = np.zeros(K), S0.copy()
    out = []
    for N, b in neqs:
        xm = Phi @ x
        Pm = Phi @ P @ Phi.T + Q
        Pm = (Pm + Pm.T) / 2
        Jm = np.linalg.inv(Pm)
        Pp = np.linalg.inv(Jm + N)
        xp = Pp @ (Jm @ xm + b)
        Pp = (Pp + Pp.T) / 2
        out.append((xm, Pm, xp, Pp))
        x, P = xp, Pp
    nt = len(out)
    xs = [None] * nt
    xs[-1] = out[-1][2]
    for t in range(nt - 2, -1, -1):
        _, _, xf, Pf = out[t]
        G = np.linalg.solve(out[t + 1][1].T, (Pf @ Phi.T).T).T
        xs[t] = xf + G @ (xs[t + 1] - out[t + 1][0])
    return np.array(xs).T


class Chain:
    """The regionalKalman solution mode with a background: obs - b, the
    observation climatology removed, filter + RTS in the basis, the
    climatology restored through Proj, then x = T a + b."""

    def __init__(self, idx_full, idxB, T, Proj, model, tm, t, sig):
        n, m, cs = idx_full
        key = {(a, b, c): k for k, (a, b, c) in enumerate(zip(n, m, cs))}
        self.sel = np.array([key[k] for k in zip(*idxB)])
        self.T, self.Proj, self.t, self.P = T, Proj, t, n.size
        self.Ri = 1.0 / sig[self.sel] ** 2
        X = Proj @ model[self.sel]
        self.Phi, self.Q, self.S0 = var1(X - X @ hat(tm))

    def __call__(self, obs, bg=0.0, climatology=True):
        res = (obs - bg)[self.sel]
        H = hat(self.t)
        clim = res @ H if climatology else 0.0 * res
        r = res - clim
        neqs = [(self.T.T @ (self.Ri[:, None] * self.T), self.T.T @ (self.Ri * r[:, k]))
                for k in range(r.shape[1])]
        a = smooth(self.Phi, self.Q, self.S0, neqs) + self.Proj @ clim
        x = np.zeros((self.P, r.shape[1]))
        x[self.sel] = self.T @ a
        return x + bg


def blob(LAT, LON, lat0, lon0, rad_deg):
    c = unit(LAT, LON) @ unit(np.deg2rad(np.array([lat0])), np.deg2rad(np.array([lon0])))[0]
    return np.exp(-(np.arccos(np.clip(c, -1, 1)) / np.deg2rad(rad_deg)) ** 2)


# ---------------------------------------------------------------- set-up
L, CAP = 30, 60.0
idx = sh_index(L)
n = idx[0]
P = n.size
lat_g, lon_g, LAT, LON, W = quad_grid(L, 2)
Yall = ylm(LAT, LON, idx)                      # EWH-coefficient space
core = np.rad2deg(LAT) > CAP
wcore = W[core]
idxF, TF, ProjF = basis(L, CAP, 2)
K = TF.shape[1]
bl = Yall.T @ (W * blob(LAT, LON, 52.0, 20.0, 6.0))     # W sums to 1
sig = 0.002 * (1 + (n / 12.0) ** 3)             # noise rising with degree [m]
nt, ntm = 72, 240
t = 2003 + (np.arange(nt) + 0.5) / 12
tm = 1980 + (np.arange(ntm) + 0.5) / 12
low = n <= 4
print("  nmax %d, P = %d, cap north of %g N grown by 600 km: K = %d" % (L, P, CAP, K))


def realise(nn, tt, r):
    a = np.zeros((K, nn))
    for k in range(1, nn):
        a[:, k] = 0.8 * a[:, k - 1] + 0.6 * r.standard_normal(K)
    xin = TF @ a
    xin *= 0.02 / np.sqrt(np.mean((Yall[core] @ xin) ** 2))   # 2 cm inside
    xout = np.outer(bl, 0.30 * (np.sin(2 * np.pi * tt) + 0.3 * r.standard_normal(nn)))
    xlow = np.zeros((P, nn))
    xlow[low] = 0.004 * np.cumsum(r.standard_normal((low.sum(), nn)), axis=1) / np.sqrt(nn)
    return xin, xout + xlow


def errors(x, truth):
    e = Yall[core] @ (x - truth)
    bm = (wcore @ e) / wcore.sum()
    return np.sqrt(np.mean(e ** 2)), np.sqrt(np.mean(bm ** 2))


# ---------------------------------------------------------- CLAIM 1
r1 = np.random.default_rng(11)
xin, z = realise(nt, t, r1)
min_, mz = realise(ntm, tm, np.random.default_rng(12))
chain = Chain(idx, idxF, TF, ProjF, min_ + mz, tm, t, sig)
obs_in = xin + sig[:, None] * r1.standard_normal((P, nt))
x_in = chain(obs_in)
x_full = chain(obs_in + z)
worst1 = 0.0
for c in (0.8, 0.5, 1.0):
    lhs = chain(obs_in + z, c * z)
    rhs = c * z + x_in + (1 - c) * (x_full - x_in)
    worst1 = max(worst1, np.abs(lhs - rhs).max() / np.abs(lhs).max())
claim(worst1 < 1e-12, "CLAIM 1  restore algebra: x(obs; c z) = c z + x_in + (1-c)"
      "(x_full - x_in), worst relative %.2e (c = 0.8, 0.5, 1)" % worst1)

# the MATLAB test's configuration: nmax 10, cap north of 55 N, 24 monthly
# epochs, a random field z outside, 20 seeds - the bound the test quotes
idx10 = sh_index(10)
i10, T10, P10 = basis(10, 55.0, 2)
t24 = 2051 + (np.arange(24) + 0.5) / 12
tm10 = 2000 + (np.arange(600) + 0.5) / 12
worst1b = 0.0
for seed in range(20):
    r = np.random.default_rng(300 + seed)
    k10 = T10.shape[1]
    am = np.zeros((k10, 624))
    for k in range(1, 624):
        am[:, k] = 0.8 * am[:, k - 1] + r.standard_normal(k10)
    model = T10 @ am[:, :600] * 1e-10
    s10 = np.full(idx10[0].size, 2e-11)
    ch = Chain(idx10, i10, T10, P10, model, tm10, t24, s10)
    ob = T10 @ am[:, 600:] * 1e-10 + s10[:, None] * r.standard_normal((idx10[0].size, 24))
    zz = r.standard_normal((idx10[0].size, 24)) * 1e-10
    xi, xf = ch(ob), ch(ob + zz)
    for c in (0.8, 0.5):
        lhs = ch(ob + zz, c * zz)
        rhs = c * zz + xi + (1 - c) * (xf - xi)
        worst1b = max(worst1b, np.abs(lhs - rhs).max() / np.abs(lhs).max())
claim(worst1b < 1e-12, "CLAIM 1b the same identity at nmax 10 (the MATLAB "
      "test's configuration), 20 seeds: worst relative %.2e" % worst1b)

# ---------------------------------------------------------- CLAIMs 2-5
obs_mask = buffered_mask(core, LAT, LON, 300e3 / R)
YO = Yall[obs_mask]
CO = YO @ (sig[:, None] ** 2 * YO.T) + 1e-12 * np.eye(YO.shape[0])
LcO = np.linalg.cholesky(CO)
AwO = np.linalg.solve(LcO, YO @ TF)
NO = AwO.T @ AwO
idxL, TL, ProjL = basis(L, CAP, 7)             # low-degree RCR: Nmin = 7
lowL = n <= 6

rows = []
for seed in range(5):
    r = np.random.default_rng(100 + seed)
    xin, z = realise(nt, t, r)
    min_, mz = realise(ntm, tm, np.random.default_rng(200 + seed))
    obs = xin + z + sig[:, None] * r.standard_normal((P, nt))
    truth = xin + z
    full = Chain(idx, idxF, TF, ProjF, min_ + mz, tm, t, sig)
    resid = Chain(idx, idxF, TF, ProjF, min_ + 0.2 * mz, tm, t, sig)
    lowc = Chain(idx, idxL, TL, ProjL, min_ + mz, tm, t, sig)
    e_none = errors(full(obs, climatology=False), truth)
    e_in = errors(full(obs - z, climatology=False), xin)   # same data, no outside signal
    e_80 = errors(resid(obs, 0.8 * z, climatology=False), truth)
    e_80f = errors(full(obs, 0.8 * z, climatology=False), truth)
    e_low = errors(lowc(obs, np.where(lowL[:, None], obs, 0.0), climatology=False), truth)
    e_clim = errors(full(obs), truth)

    def area(bg):
        Phi, Q, S0 = var1((lambda X: X - X @ hat(tm))(ProjF @ (min_ + mz)))
        neqs = [(NO, AwO.T @ np.linalg.solve(LcO, YO @ (obs[:, k] - bg[:, k])))
                for k in range(nt)]
        return TF @ smooth(Phi, Q, S0, neqs) + bg
    e_area = errors(area(0.0 * z), truth)
    e_area80 = errors(area(0.8 * z), truth)
    rows.append([e_none, e_in, e_80, e_80f, e_low, e_area, e_area80, e_clim])
rows = np.array(rows)                            # seeds x cases x (grid, basin)
names = ["no background", "no outside signal", "80% background",
         "80% bg, full model series", "observed low degrees (n<=6)",
         "observation area, no bg", "observation area + 80% bg",
         "no bg, observed climatology restored"]
med = np.median(rows, axis=0)
for k, nm in enumerate(names):
    print("    %-30s grid RMS %.3f cm   basin-mean RMS %.3f cm (median of 5)"
          % (nm, 100 * med[k, 0], 100 * med[k, 1]))
excess = rows[:, 0, 0] / rows[:, 1, 0]
back = rows[:, 2] / rows[:, 1]                   # 80% background / no outside signal
claim(np.all(excess > 1) and np.all(back <= 1.05),
      "CLAIM 2  the outside signal raises the grid RMS in every seed (median "
      "+%.0f%%); with an 80%% background grid and basin-mean RMS are within "
      "%.1f%% of the error without any outside signal (worst seed)"
      % (100 * (np.median(excess) - 1), 100 * (back.max() - 1)))
claim(np.all(rows[:, 4, 0] > rows[:, 0, 0]),
      "CLAIM 3  the observed low degrees as background are worse than none: "
      "grid RMS %.2f against %.2f cm (median)" % (100 * med[4, 0], 100 * med[0, 0]))
claim(np.all(rows[:, 3, 0] <= 1.02 * rows[:, 2, 0]),
      "CLAIM 4  the full model series is no worse: %.3f against %.3f cm (worst "
      "ratio %.3f)" % (100 * med[3, 0], 100 * med[2, 0], (rows[:, 3, 0] / rows[:, 2, 0]).max()))
claim(med[5, 0] < med[0, 0] and np.all(rows[:, 6, 0] > rows[:, 2, 0]),
      "CLAIM 5  observation area: %.3f against %.3f cm without a background "
      "(median; better in %d of 5 seeds), %.3f against %.3f cm with one "
      "(worse in every seed)" %
      (100 * med[5, 0], 100 * med[0, 0], int(np.sum(rows[:, 5, 0] < rows[:, 0, 0])),
       100 * med[6, 0], 100 * med[2, 0]))

print("validate_regional_rcr: %d failed claim(s)" % len(FAIL))
sys.exit(1 if FAIL else 0)
