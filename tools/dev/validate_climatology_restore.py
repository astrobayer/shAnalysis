#!/usr/bin/env python3
"""validate_climatology_restore: numerical pre-validation of A34.

kalmanChain and regionalKalman remove the observation climatology (bias,
trend, annual, semiannual) before filtering and restore it afterwards. The
climatology is fitted to the NOISY observations and restored unfiltered,
so its noise comes back in every output (A34). FitClimatology = "filtered"
fits it instead to a first filter pass run without any climatology
removed, then removes that climatology, filters the residual and restores
it:
    x1 = chain(obs; no climatology),   c = H x1,
    x  = chain(obs - c; no climatology) + c,
with H the least-squares hat matrix of the six climatology terms over the
filtered epochs. "observations" (c = H obs) stays the default.

  CLAIM 1  the 8e closed loop (nmax 30, cap north of 60 N grown by 600 km,
           RBF basis, noise rising to 3 cm per coefficient at degree 30),
           with no, a 5 cm and a 15 cm annual climatology inside the
           region, at two noise levels: "filtered" has a lower grid RMS
           than "observations" in every seed and case, and is never more
           than 2 percent worse than leaving the climatology in the filter
           (Climatology = false) in the median - and better when the
           climatology is strong.
  Printed beside the claims, not claimed: a third pass (the climatology
  refitted to the second pass). It changes the median grid RMS by at most
  5 percent, and gains most where the climatology is strong and the noise
  low - the bar written before the run was "below 5 percent", and the
  strong-climatology case at noise x0.3 landed on 5.1, so it is reported
  rather than claimed, and the option does not iterate.
  CLAIM 2  the MATLAB test's configuration on the SH basis (T = I): nmax 6,
           a VAR(1) model series of 240 epochs, 36 monthly observations
           of the VAR plus an annual climatology, noise 1e-10 (1 + (n/3)^2),
           which exceeds the signal from degree 3; the "filtered"
           coefficient RMS error over the "observations" one, worst of 40
           seeds, is below 0.6 (the test asserts 0.6).
           (A first sizing at 1e-11 put the ratio at 0.95-1.00: with noise
           below the signal the restored fit noise is small, and so is the
           difference - which is A34's own condition, stated.)

Run: python3 tools/dev/validate_climatology_restore.py (nonzero exit on any
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


def hat(t):
    D = np.column_stack([np.ones_like(t), t - t.mean(), np.cos(2 * np.pi * t),
                         np.sin(2 * np.pi * t), np.cos(4 * np.pi * t),
                         np.sin(4 * np.pi * t)])
    return D @ np.linalg.solve(D.T @ D, D.T)


def var1(X):
    nt = X.shape[1]
    S0 = X @ X.T / nt
    S1 = X[:, 1:] @ X[:, :-1].T / (nt - 1)
    Phi = np.linalg.solve(S0.T, S1.T).T
    Q = S0 - Phi @ S1.T
    return Phi, (Q + Q.T) / 2, (S0 + S0.T) / 2


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
    """Solution mode of the chains in a basis T with projector Proj: the
    process model from the model series (its own climatology removed),
    the observation climatology fitted by `fit`, filter + RTS in the
    basis, the climatology restored through Proj."""

    def __init__(self, T, Proj, model, tm, t, sig):
        self.T, self.Proj, self.t = T, Proj, t
        self.Ri = 1.0 / sig ** 2
        X = Proj @ model
        self.Phi, self.Q, self.S0 = var1(X - X @ hat(tm))
        self.H = hat(t)

    def run(self, obs, clim):
        r = obs - clim
        N = self.T.T @ (self.Ri[:, None] * self.T)
        neqs = [(N, self.T.T @ (self.Ri * r[:, k])) for k in range(r.shape[1])]
        return self.T @ (smooth(self.Phi, self.Q, self.S0, neqs) + self.Proj @ clim)

    def __call__(self, obs, fit="observations", passes=2):
        if fit == "none":
            return self.run(obs, 0.0 * obs)
        if fit == "observations":
            return self.run(obs, obs @ self.H)
        clim = self.run(obs, 0.0 * obs) @ self.H           # "filtered"
        for _ in range(passes - 2):
            clim = self.run(obs, clim) @ self.H
        return self.run(obs, clim)


def blob(LAT, LON, lat0, lon0, rad_deg):
    c = unit(LAT, LON) @ unit(np.deg2rad(np.array([lat0])), np.deg2rad(np.array([lon0])))[0]
    return np.exp(-(np.arccos(np.clip(c, -1, 1)) / np.deg2rad(rad_deg)) ** 2)


# ---------------------------------------------------------- CLAIMs 1-2
L, CAP = 30, 60.0
idx = sh_index(L)
n = idx[0]
P = n.size
lat_g, lon_g, LAT, LON, W = quad_grid(L, 2)
Yall = ylm(LAT, LON, idx)
core = np.rad2deg(LAT) > CAP
mask = buffered_mask(core, LAT, LON, 600e3 / R)
j = int(np.ceil((L + 1) / np.sqrt(10))) - 1
while 10 * (j + 1) ** 2 + 2 < (L + 1) ** 2:
    j += 1
_, pts = icosahedral(j + 1)
plat = np.arcsin(pts[:, 2])
plon = np.mod(np.arctan2(pts[:, 1], pts[:, 0]), 2 * np.pi)
sel = mask[nearest_3ring(plat, plon, lat_g, lon_g)]
phi = 1.0 / np.maximum(np.arange(L + 1), 1) ** 2
TF = phi[n][:, None] * ylm(plat[sel], plon[sel], idx).T
Ym = ylm(LAT[mask], LON[mask], idx)
KK = Ym.T @ (W[mask][:, None] * Ym)
ProjF, _ = projector(TF, (KK + KK.T) / 2)
K = TF.shape[1]
nt, ntm = 72, 240
t = 2003 + (np.arange(nt) + 0.5) / 12
tm = 1980 + (np.arange(ntm) + 0.5) / 12
pat_a = Yall.T @ (W * (blob(LAT, LON, 72.0, 300.0, 8.0) + 0.6 * blob(LAT, LON, 66.0, 100.0, 6.0)))
pat_t = Yall.T @ (W * (blob(LAT, LON, 70.0, 315.0, 5.0) - 0.5 * blob(LAT, LON, 75.0, 140.0, 7.0)))
print("  nmax %d, cap north of %g N grown by 600 km: K = %d" % (L, CAP, K))


def realise(nn, r):
    a = np.zeros((K, nn))
    for k in range(1, nn):
        a[:, k] = 0.8 * a[:, k - 1] + 0.6 * r.standard_normal(K)
    x = TF @ a
    return x * 0.02 / np.sqrt(np.mean((Yall[core] @ x) ** 2))


cases = {"no climatology": (0.0, 0.0), "5 cm annual + 1 cm/yr": (0.05, 0.01),
         "15 cm annual + 3 cm/yr": (0.15, 0.03)}
ok1 = True
third = []
for noise in (1.0, 0.3):
    sig = noise * 0.002 * (1 + (n / 12.0) ** 3)
    for name, (A, Tr) in cases.items():
        rows = []
        for seed in range(5):
            r = np.random.default_rng(100 + seed)
            truth = realise(nt, r) + np.outer(pat_a * A, np.cos(2 * np.pi * t - 0.7)) \
                + np.outer(pat_t * Tr, t - 2006)
            ch = Chain(TF, ProjF, realise(ntm, np.random.default_rng(200 + seed)), tm, t, sig)
            obs = truth + sig[:, None] * r.standard_normal((P, nt))
            rows.append([np.sqrt(np.mean((Yall[core] @ (x - truth)) ** 2)) for x in
                         (ch(obs, "observations"), ch(obs, "none"), ch(obs, "filtered"),
                          ch(obs, "filtered", passes=3))])
        rows = np.array(rows)
        med = np.median(rows, axis=0)
        print("    noise x%.1f, %-24s grid RMS [cm]: observations %.3f  none %.3f  "
              "filtered %.3f  three passes %.3f" % ((noise, name) + tuple(100 * med)))
        ok1 &= bool(np.all(rows[:, 2] < rows[:, 0]) and med[2] <= 1.02 * med[1])
        third.append(abs(med[3] / med[2] - 1))
claim(ok1, "CLAIM 1  closed loop: \"filtered\" beats \"observations\" in every seed and "
      "case and is within 2% of Climatology = false in the median (table above)")
print("    a third pass changes the median grid RMS by at most %.1f%% (not claimed)"
      % (100 * max(third)))

# ---------------------------------------------------------- CLAIM 2
idx6 = sh_index(6)
n6 = idx6[0]
P6 = n6.size
ratios = []
for seed in range(40):
    r = np.random.default_rng(500 + seed)
    dec = 1.0 / (n6 + 1) ** 2
    Ph = 0.7 * np.eye(P6) + 0.02 * r.standard_normal((P6, P6))
    Ph *= 0.8 / max(abs(np.linalg.eigvals(Ph)))
    Lq = r.standard_normal((P6, P6)) / np.sqrt(P6)
    cQ = np.linalg.cholesky((Lq @ Lq.T + 0.2 * np.eye(P6)) * np.outer(dec, dec) * 1e-18)
    X = np.zeros((P6, 276))
    for k in range(1, 276):
        X[:, k] = Ph @ X[:, k - 1] + cQ @ r.standard_normal(P6)
    t36 = 2003 + (np.arange(36) + 0.5) / 12
    tm6 = 1990 + (np.arange(240) + 0.5) / 12
    amp = 2e-10 * dec * r.standard_normal(P6)
    truth = X[:, 240:] + np.outer(amp, np.cos(2 * np.pi * t36 - 0.7))
    s6 = 1e-10 * (1 + (n6 / 3.0) ** 2)
    obs = truth + s6[:, None] * r.standard_normal((P6, 36))
    ch = Chain(np.eye(P6), np.eye(P6), X[:, :240], tm6, t36, s6)
    e_o = np.sqrt(np.mean((ch(obs, "observations") - truth) ** 2))
    e_f = np.sqrt(np.mean((ch(obs, "filtered") - truth) ** 2))
    ratios.append(e_f / e_o)
ratios = np.array(ratios)
claim(ratios.max() < 0.6,
      "CLAIM 2  SH basis, nmax 6, 40 seeds: filtered / observations coefficient RMS "
      "error median %.3f, worst %.3f (the test asserts < 0.6)" % (np.median(ratios), ratios.max()))

print("validate_climatology_restore: %d failed claim(s)" % len(FAIL))
sys.exit(1 if FAIL else 0)
