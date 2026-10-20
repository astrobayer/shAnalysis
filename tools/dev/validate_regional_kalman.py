#!/usr/bin/env python3
"""validate_regional_kalman: numerical pre-validation of WP8 row 8d.

The regional Kalman chain, shLowLevel.regionalKalman: the process model of
row 8b and the basis normal equations of row 8c drive the existing
kalmanFilter (normal-equation mode) and rtsSmoother, and the smoothed basis
coefficients a are carried to SH coefficients, EWH grid values and a basin
mean through linear functionals F a, whose variances diag(F Ps F') come
from the full smoothed covariance. Every claim is checked against a route
that does not share the code under test.

  CLAIM 1  on the SH basis (T = I) the chain - solution observations turned
           into normal equations N = R^-1, b = R^-1 l and applied in the
           filter's information form - reproduces the gain-form filter of
           kalmanChain's solution mode (Joseph update) and its smoother.
           The two are the same estimator in exact arithmetic; the printed
           worst relative differences of the smoothed states and sigmas,
           over 40 seeds with gaps, are what the MATLAB test bounds (3x).
  CLAIM 2  on an RBF basis the filter followed by the RTS smoother is the
           joint least-squares adjustment over all epochs (Kvas 2019,
           Sec. 2.3): the block-tridiagonal normal system of the prior on
           a_1, the process a_t - Phi a_(t-1) ~ N(0, Q) and the per-epoch
           basis normal equations, solved densely. States and marginal
           covariances agree; gaps included.
  CLAIM 3  the sigma of a linear functional through T is honest: in a
           closed loop (truth simulated from the same VAR(1), noisy point
           observations of EWH), the basin-mean error divided by its
           predicted sigma has RMS 1 within the sampling spread, over 60
           seeds.
  CLAIM 4  the functional variances by the smoother's rule,
           sum((F Ps) .* F, 2), equal the diagonal of F Ps F' formed
           explicitly, and are exactly diag(Ps) for F = I.

Run: python3 tools/dev/validate_regional_kalman.py  (nonzero exit on any
failed claim; prints the numbers the MATLAB tests quote).

Developed by Matthias Weigelt with the help of Claude (Opus 5.5),
2026-10-21.
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from regional_oracle_lib import sh_index, ylm, quad_grid, rbf_basis  # noqa: E402

FAIL = []


def claim(ok, text):
    print(("PASS " if ok else "FAIL ") + text)
    if not ok:
        FAIL.append(text)


def var1(X):
    """estimateVAR, Order 1, Structure "full": Yule-Walker."""
    T = X.shape[1]
    S0 = X @ X.T / T
    S1 = X[:, 1:] @ X[:, :-1].T / (T - 1)
    Phi = np.linalg.solve(S0.T, S1.T).T
    Q = S0 - Phi @ S1.T
    return Phi, (Q + Q.T) / 2, (S0 + S0.T) / 2


def simulate(Phi, Q, nt, rng):
    K = Phi.shape[0]
    cQ = np.linalg.cholesky(Q)
    a = np.zeros((K, nt))
    for k in range(1, nt):
        a[:, k] = Phi @ a[:, k - 1] + cQ @ rng.standard_normal(K)
    return a


def filter_gain(Phi, Q, S0, obs):
    """kalmanFilter solution mode: l = x + v, Joseph update."""
    K = Phi.shape[0]
    x, P = np.zeros(K), S0.copy()
    out = []
    for o in obs:
        xm = Phi @ x
        Pm = Phi @ P @ Phi.T + Q
        Pm = (Pm + Pm.T) / 2
        if o is None:
            xp, Pp = xm, Pm
        else:
            l, R = o
            G = np.linalg.solve((Pm + R).T, Pm.T).T
            xp = xm + G @ (l - xm)
            IK = np.eye(K) - G
            Pp = IK @ Pm @ IK.T + G @ R @ G.T
        Pp = (Pp + Pp.T) / 2
        out.append((xm, Pm, xp, Pp))
        x, P = xp, Pp
    return out


def filter_neq(Phi, Q, S0, obs):
    """kalmanFilter neq mode: information-form update."""
    K = Phi.shape[0]
    x, P = np.zeros(K), S0.copy()
    out = []
    for o in obs:
        xm = Phi @ x
        Pm = Phi @ P @ Phi.T + Q
        Pm = (Pm + Pm.T) / 2
        if o is None:
            xp, Pp = xm, Pm
        else:
            N, b = o
            Jm = np.linalg.inv(Pm)
            Pp = np.linalg.inv(Jm + N)
            xp = Pp @ (Jm @ xm + b)
        Pp = (Pp + Pp.T) / 2
        out.append((xm, Pm, xp, Pp))
        x, P = xp, Pp
    return out


def rts(Phi, filt):
    T = len(filt)
    xs = [None] * T
    Ps = [None] * T
    xs[-1], Ps[-1] = filt[-1][2], filt[-1][3]
    for t in range(T - 2, -1, -1):
        _, _, xf, Pf = filt[t]
        xpN, PpN = filt[t + 1][0], filt[t + 1][1]
        G = np.linalg.solve(PpN.T, (Pf @ Phi.T).T).T
        xs[t] = xf + G @ (xs[t + 1] - xpN)
        P_ = Pf + G @ (Ps[t + 1] - PpN) @ G.T
        Ps[t] = (P_ + P_.T) / 2
    return np.array(xs).T, Ps


def joint_ls(Phi, Q, S0, neqs):
    """Dense joint adjustment: prior on a_1, process steps, epoch NEQs."""
    K = Phi.shape[0]
    T = len(neqs)
    Pm1 = Phi @ S0 @ Phi.T + Q
    Qi = np.linalg.inv(Q)
    M = np.zeros((K * T, K * T))
    r = np.zeros(K * T)
    blk = lambda t: slice(t * K, (t + 1) * K)
    M[blk(0), blk(0)] += np.linalg.inv(Pm1)
    for t in range(1, T):
        # (a_t - Phi a_(t-1))' Qi (a_t - Phi a_(t-1))
        M[blk(t), blk(t)] += Qi
        M[blk(t - 1), blk(t - 1)] += Phi.T @ Qi @ Phi
        M[blk(t), blk(t - 1)] -= Qi @ Phi
        M[blk(t - 1), blk(t)] -= Phi.T @ Qi
    for t, o in enumerate(neqs):
        if o is not None:
            M[blk(t), blk(t)] += o[0]
            r[blk(t)] += o[1]
    Ci = np.linalg.inv(M)
    x = Ci @ r
    return x.reshape(T, K).T, [Ci[blk(t), blk(t)] for t in range(T)]


# ---------------------------------------------------------- CLAIM 1
# The MATLAB fixture: nmax 6 (P = 45), 30 monthly epochs with every fourth
# a gap, a VAR(1) model from 240 model epochs, sigma 1e-11 per coefficient
# against a 1/(n+1)^2 signal of 1e-9.
idx6 = sh_index(6)
P6 = idx6[0].size
worst_x = worst_s = 0.0
for seed in range(40):
    rng = np.random.default_rng(seed)
    dec = 1.0 / (idx6[0] + 1.0) ** 2
    Ph = 0.7 * np.eye(P6) + 0.02 * rng.standard_normal((P6, P6))
    Ph *= 0.8 / np.max(np.abs(np.linalg.eigvals(Ph)))
    Lq = rng.standard_normal((P6, P6)) / np.sqrt(P6)
    Qt = (Lq @ Lq.T + 0.2 * np.eye(P6)) * np.outer(dec, dec) * 1e-18
    Xm = simulate(Ph, Qt, 240, rng)
    Phi, Q, S0 = var1(Xm)
    truth = simulate(Ph, Qt, 30, rng)
    sig = 1e-11 * (1 + rng.uniform(0, 1, P6))
    gain_obs, neq_obs = [], []
    for t in range(30):
        if t % 4 == 3:
            gain_obs.append(None)
            neq_obs.append(None)
            continue
        l = truth[:, t] + sig * rng.standard_normal(P6)
        gain_obs.append((l, np.diag(sig ** 2)))
        w = 1.0 / np.sqrt(sig ** 2)            # regionalNEQ: 1/sqrt of a diagonal
        Aw = np.eye(P6) * w[:, None]
        neq_obs.append((Aw.T @ Aw, Aw.T @ (w * l)))
    xg, Pg = rts(Phi, filter_gain(Phi, Q, S0, gain_obs))
    xn, Pn = rts(Phi, filter_neq(Phi, Q, S0, neq_obs))
    sg = np.sqrt(np.array([np.diag(p) for p in Pg]).T)
    sn = np.sqrt(np.array([np.diag(p) for p in Pn]).T)
    worst_x = max(worst_x, np.abs(xn - xg).max() / np.abs(xg).max())
    worst_s = max(worst_s, np.abs(sn / sg - 1).max())
claim(worst_x < 1e-10 and worst_s < 1e-10,
      "CLAIM 1  SH basis: information form = gain form, worst relative "
      "state %.2e, sigma %.2e over 40 seeds" % (worst_x, worst_s))

# ---------------------------------------------------------- CLAIM 2
idx, T, Proj, rank, Y, W, mask = rbf_basis(10, 55, 600)
P, K = T.shape


def claim2_case(rng):
    Ph = 0.75 * np.eye(K) + 0.02 * rng.standard_normal((K, K))
    Ph *= 0.8 / np.max(np.abs(np.linalg.eigvals(Ph)))
    Lq = rng.standard_normal((K, K)) / np.sqrt(K)
    Qt = Lq @ Lq.T + 0.1 * np.eye(K)
    Phi, Q, S0 = var1(simulate(Ph, Qt, 600, rng))
    truth = simulate(Ph, Qt, 12, rng)
    neqs = []
    for t in range(12):
        if t in (3, 7, 8):
            neqs.append(None)
            continue
        A = rng.standard_normal((3 * K, K))
        c = rng.uniform(0.5, 2, 3 * K)
        y = A @ truth[:, t] + np.sqrt(c) * rng.standard_normal(3 * K)
        Aw = A / np.sqrt(c)[:, None]
        neqs.append((Aw.T @ Aw, Aw.T @ (y / np.sqrt(c))))
    xs, Ps = rts(Phi, filter_neq(Phi, Q, S0, neqs))
    xj, Pj = joint_ls(Phi, Q, S0, neqs)
    ex = np.abs(xs - xj).max() / np.abs(xj).max()
    es = max(np.abs(np.sqrt(np.diag(Ps[t])) / np.sqrt(np.diag(Pj[t])) - 1).max()
             for t in range(12))
    ec = max(np.abs(Ps[t] - Pj[t]).max() / np.abs(Pj[t]).max() for t in range(12))
    return ex, es, ec, Ph, Qt, Phi, Q, S0, Ps


worst2 = np.zeros(3)
for seed in range(20):
    r2 = claim2_case(np.random.default_rng(20261021 + seed))
    worst2 = np.maximum(worst2, r2[:3])
    if seed == 0:
        _, _, _, Ph, Qt, Phi, Q, S0, Ps = r2
claim(np.all(worst2 < 1e-9),
      "CLAIM 2  RBF basis (K = %d), 12 epochs with 3 gaps, 20 seeds: filter + "
      "RTS = joint LS, worst states %.2e, sigmas %.2e, covariances %.2e"
      % (K, worst2[0], worst2[1], worst2[2]))

# ---------------------------------------------------------- CLAIM 3
# basin mean of EWH over the unbuffered cap through T; synthetic kn.
L = 10
n = idx[0]
kn = -0.3 / (np.arange(L + 1) + 1.0)
R, rho_e, rho_w = 6378136.3, 5517.0, 1000.0
f = R * rho_e / (3 * rho_w) * (2 * np.arange(L + 1) + 1) / (1 + kn)
lat_g, lon_g, LAT, LON, Wq = quad_grid(L, 2)
core = (np.rad2deg(LAT) > 55).astype(float)
ic = core > 0
Fg = (Y[ic] * f[n]) @ T                        # EWH at the core points
fb = (Wq[ic] * core[ic]) @ Fg / np.sum(Wq[ic] * core[ic])
pts = np.random.default_rng(7).integers(0, ic.sum(), 60)
z = []
for seed in range(60):
    r = np.random.default_rng(1000 + seed)
    tr = simulate(Ph, Qt, 18, r) * 1e-11
    ob = []
    for t in range(18):
        if t % 5 == 4:
            ob.append(None)
            continue
        yv = Fg[pts] @ tr[:, t] + 0.01 * r.standard_normal(pts.size)
        Aw = Fg[pts] / 0.01
        ob.append((Aw.T @ Aw, Aw.T @ (yv / 0.01)))
    xs3, Ps3 = rts(Phi, filter_neq(Phi, Q * 1e-22, S0 * 1e-22, ob))
    for t in range(18):
        z.append((fb @ xs3[:, t] - fb @ tr[:, t]) / np.sqrt(fb @ Ps3[t] @ fb))
z = np.array(z)
rmsz = np.sqrt(np.mean(z ** 2))
# the model is the Yule-Walker estimate of the true one from 600 epochs,
# not the truth: RMS 1 holds to its estimation error, ~ a few percent
claim(0.85 < rmsz < 1.15,
      "CLAIM 3  closed loop, basin-mean error / predicted sigma: RMS %.3f "
      "over %d epochs (60 seeds)" % (rmsz, z.size))

# ---------------------------------------------------------- CLAIM 4
# the regional functionals above, and 200 random (F 8 x 6, Ps SPD 6 x 6) -
# the rtsSmoother test's shape; relative to the largest variance.
F = np.vstack([T, fb[None, :], Fg])
Pl = Ps[-1]
e4 = np.abs(np.sum((F @ Pl) * F, axis=1) - np.diag(F @ Pl @ F.T)).max() \
    / np.abs(np.diag(F @ Pl @ F.T)).max()
r4 = np.random.default_rng(44)
for _ in range(200):
    Fr = r4.standard_normal((8, 6))
    Lr = r4.standard_normal((6, 6))
    Pr = Lr @ Lr.T + 0.2 * np.eye(6)
    dx = np.diag(Fr @ Pr @ Fr.T)
    # as the MATLAB test reads it: the sigma squared back, against dx
    sF = np.sqrt(np.maximum(np.sum((Fr @ Pr) * Fr, axis=1), 0))
    e4 = max(e4, np.abs(sF ** 2 - dx).max() / dx.max())
I = np.eye(K)
same = np.array_equal(np.sum((I @ Pl) * I, axis=1), np.diag(Pl))
claim(e4 < 1e-13 and same,
      "CLAIM 4  sum((F Ps) .* F, 2) = diag(F Ps F'), worst rel. %.2e (201 "
      "cases); exact diag(Ps) for F = I" % e4)

print("validate_regional_kalman: %d failed claim(s)" % len(FAIL))
sys.exit(1 if FAIL else 0)
