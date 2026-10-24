#!/usr/bin/env python3
"""validate_kalman_bridge: numerical pre-validation of WP9 row 9a.

kalmanChain gains a second observation group, SecondSeries: a noisier
series of the same field (an HLSST + SLR combination, Swarm) that observes
every coefficient of degree n as
    B = s_n x + o + e,   e ~ N(0, sigma_n^2),
with an offset o per coefficient (reference field, tide system), a scale
s_n per degree (a regularised series is damped) and a noise sigma_n per
degree. All three are calibrated on the epochs both series have (the
overlap, matched within SecondTolerance), against the primary series R
with its own noise variances sR^2, per degree n over all its coefficients:
    dR = R - mean(R), dB = B - mean(B)           (over the overlap)
    s_n = sum(dB dR) / (sum(dR^2) - sum(sR^2))   (errors in variables;
                                                  0 where it is <= 0)
    o   = mean(B) - s_n mean(R)
    sigma_n^2 = mean((dB - s_n dR)^2) - s_n^2 mean(sR^2),
                floored at s_n^2 mean(sR^2)      (never better than R)
SecondScale = false fixes s_n = 1. Each secondary epoch then enters the
filter as a normal equation N = diag(s^2/sigma^2), b = s (B - o - s c)/
sigma^2 (c the climatology removed from R, evaluated at the epoch), added
to the primary's information where both observe the epoch. The default
output grid is the primary's epochs plus every secondary epoch inside
the primary's span that the primary lacks - the months bridgeGaps fills.

  CLAIM 1  with the process model fixed, the chain with secondary records
           (information form, mixed with the primary's solution records)
           equals the dense joint Gaussian posterior of all observations
           under the joint process prior - states and sigmas.
  CLAIM 2  the calibration is consistent: on a long synthetic overlap
           (20000 epochs) it recovers s_n and sigma_n within 4 percent at
           every degree, and the errors-in-variables correction is what
           makes it - the plain regression sum(dB dR)/sum(dR^2) is biased
           low where the primary is noisy. (A first sizing at 4000 epochs
           missed by 4.5 percent at degree 8, where s_n = 0.24: sampling
           error, which is why the claim is stated at a size where it is
           not.)
  CLAIM 3  closed loop (nmax 12, 156 months, an 11-month gap and 8
           scattered missing months, a secondary damped above degree 6
           and 4 x noisier than the primary, its formal sigmas 4 x too
           small; the process model a diagonal VAR(1), Structure =
           "diagonal", since 240 model months cannot identify a full one
           of 165 coefficients), compared at a 750 km Gaussian over degrees 3-12 on the
           gap months: the Kalman chain with the secondary beats
           bridgeGaps' calibrated fill and the chain without the
           secondary in every seed; outside the gap it is within 2
           percent of the chain without it in the median; and in the gap
           its actual error is 0.8-1.25 of its predicted sigma.
  CLAIM 4  the MATLAB closed-loop test's configuration (nmax 6, 72
           months, 8 missing): the gap error with the secondary is below
           0.8 of the error without it in each of 40 seeds.
  CLAIM 1b is CLAIM 1 with the process model estimated from a long model
           series and the calibration's numbers applied - the MATLAB
           identity test's configuration.
  Printed beside the claims: SecondScale = true against false, which sets
  the option's default.

Run: python3 tools/dev/validate_kalman_bridge.py (nonzero exit on any
failed claim; prints the numbers the MATLAB tests and docs quote).

Developed by Matthias Weigelt with the help of Claude (Opus 5.5),
2026-10-23.
"""
import sys

import numpy as np

FAIL = []
REARTH = 6378136.3


def claim(ok, text):
    print(("PASS " if ok else "FAIL ") + text)
    if not ok:
        FAIL.append(text)


def index(L, nmin=2):
    """degree per coefficient, C then S terms, degrees nmin..L."""
    deg = []
    for n in range(nmin, L + 1):
        deg += [n] * (n + 1)           # C, m = 0..n
        deg += [n] * n                 # S, m = 1..n
    return np.array(deg)


def gauss_weights(L, radius_km):
    """Jekeli's recursion, as shLowLevel.shGaussianWeights."""
    b = np.log(2.0) / (1.0 - np.cos(radius_km * 1e3 / REARTH))
    w = np.zeros(L + 1)
    w[0] = 1.0
    w[1] = (1 + np.exp(-2 * b)) / (1 - np.exp(-2 * b)) - 1.0 / b
    for n in range(1, L):
        w[n + 1] = -(2 * n + 1) / b * w[n] + w[n - 1]
    return w


def clim_design(t):
    return np.column_stack([np.ones_like(t), t - t.mean(), np.cos(2 * np.pi * t),
                            np.sin(2 * np.pi * t), np.cos(4 * np.pi * t),
                            np.sin(4 * np.pi * t)])


def fit_clim(Y, t):
    """least-squares climatology of the columns of Y at epochs t; returns
    a callable c(tt) -> (P x len(tt))."""
    D = clim_design(t)
    coef = np.linalg.solve(D.T @ D, D.T @ Y.T)
    tm = t.mean()

    def ev(tt):
        tt = np.atleast_1d(tt)
        Dt = np.column_stack([np.ones_like(tt), tt - tm, np.cos(2 * np.pi * tt),
                              np.sin(2 * np.pi * tt), np.cos(4 * np.pi * tt),
                              np.sin(4 * np.pi * tt)])
        return (Dt @ coef).T
    return ev


def var1(X, diagonal=False):
    """estimateVAR, Order 1; Structure "diagonal" when asked."""
    nt = X.shape[1]
    S0 = X @ X.T / nt
    S1 = X[:, 1:] @ X[:, :-1].T / (nt - 1)
    if diagonal:
        S0 = np.diag(np.diag(S0))
        S1 = np.diag(np.diag(S1))
    Phi = np.linalg.solve(S0.T, S1.T).T
    Q = S0 - Phi @ S1.T
    return Phi, (Q + Q.T) / 2, (S0 + S0.T) / 2


def smooth(Phi, Q, S0, neqs):
    """kalmanFilter (NEQ form; a gap is N = 0, b = 0) + rtsSmoother:
    smoothed states and their sigmas."""
    K = Phi.shape[0]
    x, P = np.zeros(K), S0.copy()
    out = []
    first = True
    for N, b in neqs:
        if first:
            xm, Pm = x, P
            first = False
        else:
            xm = Phi @ x
            Pm = Phi @ P @ Phi.T + Q
        Pm = (Pm + Pm.T) / 2
        Jm = np.linalg.inv(Pm)
        Pp = np.linalg.inv(Jm + N)
        Pp = (Pp + Pp.T) / 2
        xp = Pp @ (Jm @ xm + b)
        out.append((xm, Pm, xp, Pp))
        x, P = xp, Pp
    nt = len(out)
    xs = [None] * nt
    Ps = [None] * nt
    xs[-1], Ps[-1] = out[-1][2], out[-1][3]
    for t in range(nt - 2, -1, -1):
        _, _, xf, Pf = out[t]
        Pm1 = out[t + 1][1]
        G = np.linalg.solve(Pm1.T, (Pf @ Phi.T).T).T
        xs[t] = xf + G @ (xs[t + 1] - out[t + 1][0])
        Ps[t] = Pf + G @ (Ps[t + 1] - Pm1) @ G.T
    return np.array(xs).T, np.sqrt(np.array([np.diag(p) for p in Ps]).T)


def calibrate(R, sR2, B, deg, L, scale=True):
    """the overlap calibration of the docstring. R, B: (P x M) on the
    overlap; sR2: (P x M) primary noise variances. Returns s, sigma per
    degree (index 0..L) and the offset per coefficient."""
    dR = R - R.mean(axis=1, keepdims=True)
    dB = B - B.mean(axis=1, keepdims=True)
    s = np.zeros(L + 1)
    sig = np.zeros(L + 1)
    for n in range(L + 1):
        k = deg == n
        if not k.any():
            continue
        if scale:
            den = np.sum(dR[k] ** 2) - np.sum(sR2[k])
            s[n] = max(np.sum(dB[k] * dR[k]) / den, 0.0) if den > 0 else 0.0
        else:
            s[n] = 1.0
        floor = s[n] ** 2 * np.mean(sR2[k])
        v = np.mean((dB[k] - s[n] * dR[k]) ** 2) - floor
        sig[n] = np.sqrt(max(v, floor))
    off = B.mean(axis=1) - s[deg] * R.mean(axis=1)
    return s, sig, off


def chain(model, tP, Rob, sR2, tGrid, second=None, clim=True):
    """kalmanChain in solution mode with an optional SecondSeries.
    model: (Phi, Q, S0); Rob (P x TP) primary obs at tP with variances
    sR2; second = (tB, Bob, s, sig, off) or None. Returns smoothed states
    (restored) and sigmas on tGrid."""
    Phi, Q, S0 = model
    deg_s, deg_sig = (second[2], second[3]) if second is not None else (None, None)
    c = fit_clim(Rob, tP) if clim else (lambda tt: np.zeros((Rob.shape[0], np.size(tt))))
    neqs = []
    for tg in tGrid:
        P = Rob.shape[0]
        N = np.zeros((P, P))
        b = np.zeros(P)
        j = np.argmin(np.abs(tP - tg))
        if abs(tP[j] - tg) < 1e-9:
            w = 1.0 / sR2[:, j]
            N += np.diag(w)
            b += w * (Rob[:, j] - c(tg)[:, 0])
        if second is not None:
            tB, Bob, sP, sigP, off = second
            k = np.argmin(np.abs(tB - tg))
            if abs(tB[k] - tg) < 0.05:
                w = sP ** 2 / sigP ** 2
                N += np.diag(w)
                b += sP / sigP ** 2 * (Bob[:, k] - off - sP * c(tg)[:, 0])
        neqs.append((N, b))
    xs, sg = smooth(Phi, Q, S0, neqs)
    return xs + c(tGrid), sg


def bridge_fill(tP, Rob, tB, Bob, deg, L, w):
    """bridgeGaps: smooth both, calibrate (s regresses R on B), fill."""
    Rs = Rob * w[deg][:, None]
    Bs = Bob * w[deg][:, None]
    d = np.abs(tB[:, None] - tP[None, :])
    iB = np.where(d.min(axis=1) < 0.05)[0]
    iR = d.argmin(axis=1)[iB]
    toFill = np.where((d.min(axis=1) >= 0.05) & (tB >= tP.min()) & (tB <= tP.max()))[0]
    R0 = Rs[:, iR].mean(axis=1)
    B0 = Bs[:, iB].mean(axis=1)
    dR = Rs[:, iR] - R0[:, None]
    dB = Bs[:, iB] - B0[:, None]
    s = np.zeros(L + 1)
    for n in range(L + 1):
        k = deg == n
        den = np.sum(dB[k] ** 2)
        if den > 0:
            s[n] = np.sum(dB[k] * dR[k]) / den
    F = R0[:, None] + s[deg][:, None] * (Bs[:, toFill] - B0[:, None])
    return tB[toFill], F


# ---------------------------------------------------------- CLAIM 1
rng = np.random.default_rng(1)
L1 = 3
deg1 = index(L1)
P1 = deg1.size
A = 0.6 * np.eye(P1) + 0.05 * rng.standard_normal((P1, P1))
A *= 0.7 / max(abs(np.linalg.eigvals(A)))
Lq = rng.standard_normal((P1, P1)) / np.sqrt(P1)
Q1 = Lq @ Lq.T + 0.3 * np.eye(P1)
S01 = np.eye(P1)
for _ in range(500):                          # stationary covariance
    S01 = A @ S01 @ A.T + Q1
nt1 = 14
tP1 = np.arange(nt1, dtype=float)
keepP = np.ones(nt1, bool)
keepP[[4, 5, 6, 10]] = False
sR2 = (0.3 + 0.1 * rng.random((P1, nt1)))
Rob1 = rng.standard_normal((P1, nt1))
sB = 0.5 + 0.5 * rng.random(L1 + 1)
sgB = 0.8 + rng.random(L1 + 1)
off1 = 0.1 * rng.standard_normal(P1)
Bob1 = rng.standard_normal((P1, nt1))
tB1 = tP1.copy()
haveB = np.ones(nt1, bool)
haveB[[2, 9]] = False
xs1, sg1 = chain((A, Q1, S01), tP1[keepP], Rob1[:, keepP], sR2[:, keepP], tP1,
                 second=(tB1[haveB], Bob1[:, haveB], sB[deg1], sgB[deg1], off1),
                 clim=False)
# dense joint posterior: prior covariance of the stacked states, then the
# stacked observations (primary: x_t; secondary: s x_t + off)
Kd = P1 * nt1
Cx = np.zeros((Kd, Kd))
Ak = [np.linalg.matrix_power(A, k) for k in range(nt1)]
for i in range(nt1):
    for j in range(nt1):
        blk = Ak[i - j] @ S01 if i >= j else S01 @ Ak[j - i].T
        Cx[i * P1:(i + 1) * P1, j * P1:(j + 1) * P1] = blk
rows, ys, vs = [], [], []
for t in range(nt1):
    if keepP[t]:
        H = np.zeros((P1, Kd))
        H[:, t * P1:(t + 1) * P1] = np.eye(P1)
        rows.append(H)
        ys.append(Rob1[:, t])
        vs.append(sR2[:, t])
    if haveB[t]:
        H = np.zeros((P1, Kd))
        H[:, t * P1:(t + 1) * P1] = np.diag(sB[deg1])
        rows.append(H)
        ys.append(Bob1[:, t] - off1)
        vs.append(sgB[deg1] ** 2)
H = np.vstack(rows)
y = np.concatenate(ys)
Rv = np.diag(np.concatenate(vs))
Kg = Cx @ H.T @ np.linalg.inv(H @ Cx @ H.T + Rv)
xd = Kg @ y
Pd = Cx - Kg @ H @ Cx
e_x = np.max(np.abs(xs1.T.reshape(-1) - xd)) / np.max(np.abs(xd))
e_s = np.max(np.abs(sg1.T.reshape(-1) - np.sqrt(np.diag(Pd))) / np.sqrt(np.diag(Pd)))
claim(e_x < 1e-11 and e_s < 1e-11,
      "CLAIM 1  mixed solution + secondary normal-equation records = dense joint "
      "posterior: states %.1e, sigmas %.1e (relative)" % (e_x, e_s))


def dense_posterior(Phi, S0, keepP, Rob, sR2, haveB, Bob, sv, gv, off):
    """the joint Gaussian posterior of all epochs (one grid epoch per
    column), for the MATLAB test's identity."""
    Pd, nt = Rob.shape
    K = Pd * nt
    C = np.zeros((K, K))
    Ak = [np.linalg.matrix_power(Phi, k) for k in range(nt)]
    for i in range(nt):
        for j in range(nt):
            C[i * Pd:(i + 1) * Pd, j * Pd:(j + 1) * Pd] = \
                Ak[i - j] @ S0 if i >= j else S0 @ Ak[j - i].T
    rr, yy, vv = [], [], []
    for t_ in range(nt):
        if keepP[t_]:
            Hh = np.zeros((Pd, K))
            Hh[:, t_ * Pd:(t_ + 1) * Pd] = np.eye(Pd)
            rr.append(Hh)
            yy.append(Rob[:, t_])
            vv.append(sR2[:, t_])
        if haveB[t_]:
            Hh = np.zeros((Pd, K))
            Hh[:, t_ * Pd:(t_ + 1) * Pd] = np.diag(sv)
            rr.append(Hh)
            yy.append(Bob[:, t_] - off)
            vv.append(gv ** 2)
    Hh = np.vstack(rr)
    Kg = C @ Hh.T @ np.linalg.inv(Hh @ C @ Hh.T + np.diag(np.concatenate(vv)))
    return Kg @ np.concatenate(yy), np.sqrt(np.diag(C - Kg @ Hh @ C))


# CLAIM 1b: the same identity with the model ESTIMATED from a long model
# series (2000 epochs, full VAR(1), nmax 3) and the calibration applied -
# the configuration of the MATLAB test, whose bound is 3 x the worst here
worst = [0.0, 0.0]
for seed in range(10):
    r = np.random.default_rng(40 + seed)
    Pm = P1
    A = 0.6 * np.eye(Pm) + 0.05 * r.standard_normal((Pm, Pm))
    A *= 0.7 / max(abs(np.linalg.eigvals(A)))
    X = np.zeros((Pm, 2000))
    for k in range(1, 2000):
        X[:, k] = A @ X[:, k - 1] + r.standard_normal(Pm)
    Phe, Qe, S0e = var1(X)
    Rb = r.standard_normal((Pm, nt1))
    vR = 0.3 + 0.1 * r.random((Pm, nt1))
    Bb = r.standard_normal((Pm, nt1))
    sv = (0.5 + 0.5 * r.random(L1 + 1))[deg1]
    gv = (0.8 + r.random(L1 + 1))[deg1]
    of = 0.1 * r.standard_normal(Pm)
    xc, sc = chain((Phe, Qe, S0e), tP1[keepP], Rb[:, keepP], vR[:, keepP], tP1,
                   second=(tB1[haveB], Bb[:, haveB], sv, gv, of), clim=False)
    xd, sd = dense_posterior(Phe, S0e, keepP, Rb, vR, haveB, Bb, sv, gv, of)
    worst[0] = max(worst[0], np.max(np.abs(xc.T.reshape(-1) - xd)) / np.max(np.abs(xd)))
    worst[1] = max(worst[1], np.max(np.abs(sc.T.reshape(-1) - sd) / sd))
claim(max(worst) < 1e-11,
      "CLAIM 1b with an estimated model, 10 seeds: worst states %.1e, sigmas %.1e"
      % tuple(worst))

# ---------------------------------------------------------- CLAIM 2
L2 = 8
deg2 = index(L2)
P2 = deg2.size
M2 = 20000
amp2 = (deg2 / 2.0) ** -2.0
sigR2 = 0.3 * amp2 * (deg2 / 4.0) ** 2              # primary noise rising
s_true = 1.0 / (1.0 + (np.arange(L2 + 1) / 6.0) ** 4)
sig_true = np.zeros(L2 + 1)
for n in range(2, L2 + 1):
    sig_true[n] = 0.5 * amp2[deg2 == n][0] * (n / 3.0)
x2 = amp2[:, None] * rng.standard_normal((P2, M2))
R2 = x2 + sigR2[:, None] * rng.standard_normal((P2, M2))
B2 = s_true[deg2][:, None] * x2 + 0.3 * amp2[:, None] \
    + sig_true[deg2][:, None] * rng.standard_normal((P2, M2))
s_hat, sig_hat, _ = calibrate(R2, np.tile(sigR2[:, None] ** 2, (1, M2)), B2, deg2, L2)
dR2 = R2 - R2.mean(axis=1, keepdims=True)
dB2 = B2 - B2.mean(axis=1, keepdims=True)
s_naive = np.array([np.sum(dB2[deg2 == n] * dR2[deg2 == n]) / np.sum(dR2[deg2 == n] ** 2)
                    for n in range(2, L2 + 1)])
ns = np.arange(2, L2 + 1)
es = np.max(np.abs(s_hat[ns] / s_true[ns] - 1))
eg = np.max(np.abs(sig_hat[ns] / sig_true[ns] - 1))
bias = np.min(s_naive / s_true[ns])
claim(es < 0.04 and eg < 0.04 and bias < 0.9,
      "CLAIM 2  calibration on 20000 overlap epochs: s_n within %.1f%%, sigma_n within "
      "%.1f%%; the plain regression reaches only %.2f of s_n at degree %d"
      % (100 * es, 100 * eg, bias, ns[np.argmin(s_naive / s_true[ns])]))

# CLAIM 2b: the MATLAB calibration test's configuration - nmax 4, 6000
# overlap epochs, the same amplitudes - over 20 seeds; its bound is 3 x
# the worst relative error here
L2b = 4
deg2b = index(L2b)
a2b = (deg2b / 2.0) ** -2.0
r2b = 0.3 * a2b * (deg2b / 4.0) ** 2
st2b = 1.0 / (1.0 + (np.arange(L2b + 1) / 3.0) ** 4)
sg2b = np.zeros(L2b + 1)
for n in range(2, L2b + 1):
    sg2b[n] = 0.5 * a2b[deg2b == n][0] * (n / 3.0)
w2b = [0.0, 0.0]
for seed in range(20):
    r = np.random.default_rng(60 + seed)
    xx = a2b[:, None] * r.standard_normal((deg2b.size, 6000))
    RR = xx + r2b[:, None] * r.standard_normal(xx.shape)
    BB = st2b[deg2b][:, None] * xx + 0.3 * a2b[:, None] \
        + sg2b[deg2b][:, None] * r.standard_normal(xx.shape)
    sh_, gh_, _ = calibrate(RR, np.tile(r2b[:, None] ** 2, (1, 6000)), BB, deg2b, L2b)
    nn_ = np.arange(2, L2b + 1)
    w2b[0] = max(w2b[0], np.max(np.abs(sh_[nn_] / st2b[nn_] - 1)))
    w2b[1] = max(w2b[1], np.max(np.abs(gh_[nn_] / sg2b[nn_] - 1)))
claim(max(w2b) < 0.04,
      "CLAIM 2b the MATLAB calibration test's configuration (nmax 4, 6000 epochs), "
      "20 seeds: worst s_n %.2f%%, sigma_n %.2f%%" % (100 * w2b[0], 100 * w2b[1]))

# ---------------------------------------------------------- CLAIM 3
L = 12
deg = index(L)
P = deg.size
w750 = gauss_weights(L, 750.0)
amp = (deg / 2.0) ** -2.0                            # signal per coefficient
sigR = 0.08 * amp * (deg / 4.0) ** 3                 # GRACE-like noise
s_sec = 1.0 / (1.0 + (deg / 6.0) ** 4)               # damped secondary
sig_sec = 4.0 * sigR + 0.25 * amp * (deg / 6.0) ** 2
nt, ntm = 156, 240
t = 2005 + (np.arange(nt) + 0.5) / 12
tm = 1980 + (np.arange(ntm) + 0.5) / 12
gap = np.zeros(nt, bool)
gap[70:81] = True
phi = 0.8


def process(nn, r):
    a = np.zeros((P, nn))
    for k in range(1, nn):
        a[:, k] = phi * a[:, k - 1] + np.sqrt(1 - phi ** 2) * r.standard_normal(P)
    return amp[:, None] * a


k3 = deg >= 3
wk = w750[deg]
rows = []
for seed in range(20):
    r = np.random.default_rng(300 + seed)
    truth = process(nt, r) + amp[:, None] * np.outer(r.standard_normal(P),
                                                     np.cos(2 * np.pi * t - 0.4))
    miss = gap.copy()
    miss[r.choice(np.where(~gap)[0], 8, replace=False)] = True
    obsP = truth + sigR[:, None] * r.standard_normal((P, nt))
    obsB = s_sec[:, None] * truth + 0.5 * amp[:, None] * r.standard_normal((P, 1)) \
        + sig_sec[:, None] * r.standard_normal((P, nt))
    X = process(ntm, np.random.default_rng(900 + seed))
    Xr = X - fit_clim(X, tm)(tm)
    model = var1(Xr, diagonal=True)
    tP, RP = t[~miss], obsP[:, ~miss]
    sR2 = np.tile(sigR[:, None] ** 2, (1, tP.size))
    ov = np.isin(t, tP)
    res = []
    for scale in (True, False):
        s_c, g_c, o_c = calibrate(obsP[:, ov], np.tile(sigR[:, None] ** 2, (1, ov.sum())),
                                  obsB[:, ov], deg, L, scale)
        xs, sg = chain(model, tP, RP, sR2, t, second=(t, obsB, s_c[deg], g_c[deg], o_c))
        res.append((xs, sg))
    x0, _ = chain(model, tP, RP, sR2, t)
    tf, F = bridge_fill(tP, RP, t, obsB, deg, L, w750)

    def err(est, cols):
        d = (est - truth[:, cols]) * wk[:, None]
        return np.sqrt(np.mean(d[k3] ** 2))
    sigS = np.sqrt(np.mean(((truth - truth.mean(axis=1, keepdims=True)) * wk[:, None])[k3] ** 2))
    gi = np.where(gap)[0]
    fi = [np.argmin(np.abs(tf - tt)) for tt in t[gi]]
    oi = np.where(~miss)[0]
    xsS, sgS = res[0]
    honest = err(xsS[:, gi], gi) / np.sqrt(np.mean((sgS[:, gi] * wk[:, None])[k3] ** 2))
    rows.append([err(xsS[:, gi], gi) / sigS, err(res[1][0][:, gi], gi) / sigS,
                 err(F[:, fi], gi) / sigS, err(x0[:, gi], gi) / sigS,
                 err(xsS[:, oi], oi) / err(x0[:, oi], oi), honest])
rows = np.array(rows)
med = np.median(rows, axis=0)
print("  gap months, error / signal at 750 km, degrees 3-12 (median of 20 seeds):")
print("    Kalman + secondary, scaled %.3f   unscaled %.3f   bridgeGaps fill %.3f   "
      "Kalman alone %.3f" % tuple(med[:4]))
print("    outside the gap, Kalman + secondary over Kalman alone: median %.3f, worst %.3f"
      % (med[4], rows[:, 4].max()))
print("    gap: actual over predicted sigma, median %.2f, range %.2f-%.2f"
      % (med[5], rows[:, 5].min(), rows[:, 5].max()))
ok3 = bool(np.all(rows[:, 0] < rows[:, 2]) and np.all(rows[:, 0] < rows[:, 3])
           and med[4] <= 1.02 and rows[:, 5].min() >= 0.8 and rows[:, 5].max() <= 1.25)
claim(ok3, "CLAIM 3  closed loop: the chain with the secondary beats the calibrated fill "
      "and the chain alone in every seed, is within 2%% of the chain alone outside the "
      "gap, and its gap sigma is honest (table above)")
print("    SecondScale: scaled wins in %d of 20 seeds" % np.sum(rows[:, 0] < rows[:, 1]))


# ---------------------------------------------------------- CLAIM 4
# the MATLAB closed-loop test's configuration: nmax 6, 72 months, months
# 31-38 missing, a secondary damped above degree 4 and 4 x noisier
L4 = 6
deg4 = index(L4)
P4 = deg4.size
amp4 = 1.0 / (deg4 + 1.0) ** 2
sR4 = 0.1 * amp4 * (deg4 / 2.0) ** 2
ss4 = 1.0 / (1.0 + (deg4 / 4.0) ** 4)
sg4 = 4.0 * sR4
nt4 = 72
t4 = 2005 + (np.arange(nt4) + 0.5) / 12
gap4 = np.zeros(nt4, bool)
gap4[30:38] = True
ratios = []
for seed in range(40):
    r = np.random.default_rng(700 + seed)

    def proc(nn, rr):
        a = np.zeros((P4, nn))
        for k in range(1, nn):
            a[:, k] = 0.8 * a[:, k - 1] + 0.6 * rr.standard_normal(P4)
        return amp4[:, None] * a
    truth = proc(nt4, r) + amp4[:, None] * np.outer(r.standard_normal(P4),
                                                    np.cos(2 * np.pi * t4))
    oP = truth + sR4[:, None] * r.standard_normal((P4, nt4))
    oB = ss4[:, None] * truth + 0.5 * amp4[:, None] * r.standard_normal((P4, 1)) \
        + sg4[:, None] * r.standard_normal((P4, nt4))
    Xm = proc(240, np.random.default_rng(800 + seed))
    mdl = var1(Xm - fit_clim(Xm, tm)(tm), diagonal=True)
    tP4, RP4 = t4[~gap4], oP[:, ~gap4]
    v4 = np.tile(sR4[:, None] ** 2, (1, tP4.size))
    s_c, g_c, o_c = calibrate(RP4, v4, oB[:, ~gap4], deg4, L4)
    x2, _ = chain(mdl, tP4, RP4, v4, t4, second=(t4, oB, s_c[deg4], g_c[deg4], o_c))
    x1, _ = chain(mdl, tP4, RP4, v4, t4)
    gi = np.where(gap4)[0]
    ratios.append(np.sqrt(np.mean((x2[:, gi] - truth[:, gi]) ** 2))
                  / np.sqrt(np.mean((x1[:, gi] - truth[:, gi]) ** 2)))
ratios = np.array(ratios)
claim(ratios.max() < 0.8,
      "CLAIM 4  the MATLAB test configuration, 40 seeds: gap coefficient error with "
      "the secondary over without it, median %.3f, worst %.3f (the test asserts < 0.8)"
      % (np.median(ratios), ratios.max()))

print("validate_kalman_bridge: %d failed claim(s)" % len(FAIL))
sys.exit(1 if FAIL else 0)
