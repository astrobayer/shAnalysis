#!/usr/bin/env python3
"""validate_regional_adaptive: numerical pre-validation of WP8 row 8i.

Kurtenbach (2012, DGK C-683, Sec. 4.3.5) scales the process noise by a
hand-tuned alpha (Q -> 10 Q in his simulation) and notes that for real
data "eine solche Vorabbestimmung eines Anpassungsfaktors natuerlich nicht
zu bewerkstelligen" ist. Row 8i estimates it from the data: Q(alpha) =
D Q0 D, D = diag(sqrt(alpha_k)) on block k of the state - one alpha per
block, the correlations of Q0 kept, Kurtenbach's alpha the one-block case -
by maximum likelihood of the innovations, which the filter delivers epoch
by epoch. In the normal-equation form of shLowLevel.kalmanFilter, with
predicted state m and covariance P- (physical block), the -2 log
likelihood of one epoch is, up to log|R| + l'R^-1 l (free of alpha),

    log|I + P- N| + m'N m - 2 m'b - u'(P-^-1 + N)^-1 u,   u = b - N m.

  CLAIM 1  the sum of the per-epoch terms plus the constants is the dense
           Gaussian -2 log likelihood of all observations under the joint
           prior of the VAR(1) states (the same initialisation as
           kalmanFilter: x0 ~ N(0, Sigma0)) - gaps included, to rounding.
           And the solution-mode term exceeds the neq-mode term of the same
           data (N = R^-1, b = R^-1 l) by exactly log|R| + l'R^-1 l.
  CLAIM 2  for one block, the maximum found by a 1-D search of that
           likelihood is the fixed point of EM (Shumway and Stoffer 1982):
           alpha = sum_t tr(Q0^-1 E[w_t w_t' | y]) / (K T), w_t = x_t -
           Phi x_(t-1), from the RTS smoother and its lag-one covariance
           P_(t,t-1|T) = P_(t|T) G_(t-1)'. Two routes, one stationary point.
  CLAIM 3  closed loop: data simulated with alpha_true = (4, 0.5) on two
           blocks; the estimate scatters around the truth (mean within 3
           standard errors over 30 seeds), and the estimated alphas lower
           the state error against alpha = 1 in most seeds.
  CLAIM 4  a VAR(2) truth: the order-2 model has the lower -2 log
           likelihood than the order-1 model in every seed, and for VAR(2)
           the information-form filter equals the gain form (kalmanChain's)
           in companion space to rounding.
  CLAIM 4b the same identity in the MATLAB test's configuration: four
           coefficients, a 3000-epoch model series, direct observations
           with gaps, kalmanFilter's own update formulas and the RTS
           smoother - the numbers the VAR(2) test's bounds come from.
  CLAIM 5  space-domain conditioning in a basis: a conditioner cf of SH
           covariances becomes one of basis covariances as
           Proj cf(T S T') Proj'; Proj T = I makes it the identity when cf
           is, and congruence keeps it positive semidefinite.

Run: python3 tools/dev/validate_regional_adaptive.py  (nonzero exit on any
failed claim; prints the numbers the MATLAB tests quote).

Developed by Matthias Weigelt with the help of Claude (Opus 5.5),
2026-10-21.
"""
import os
import sys

import numpy as np
from scipy.linalg import solve_discrete_lyapunov
from scipy.optimize import minimize, minimize_scalar

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from regional_oracle_lib import rbf_basis  # noqa: E402

FAIL = []


def claim(ok, text):
    print(("PASS " if ok else "FAIL ") + text)
    if not ok:
        FAIL.append(text)


def model(rng, K=6, rho=0.8):
    Phi = rng.standard_normal((K, K)) * 0.15 + rho * np.eye(K)
    Phi *= 0.85 / max(abs(np.linalg.eigvals(Phi)))
    L = rng.standard_normal((K, K))
    Q0 = L @ L.T / K + 0.3 * np.eye(K)
    S0 = solve_discrete_lyapunov(Phi, Q0)
    return Phi, Q0, (S0 + S0.T) / 2


def scaled(Q0, alpha, blocks):
    d = np.sqrt(np.asarray(alpha, float)[blocks])
    return d[:, None] * Q0 * d[None, :]


def simulate(Phi, Q, S0, T, rng):
    K = Phi.shape[0]
    x = np.linalg.cholesky(S0) @ rng.standard_normal(K)
    cQ = np.linalg.cholesky(Q)
    X = np.zeros((K, T))
    for t in range(T):
        x = Phi @ x + cQ @ rng.standard_normal(K)
        X[:, t] = x
    return X


def observations(X, rng, nobs=4, gaps=()):
    K, T = X.shape
    recs = []
    for t in range(T):
        if t in gaps:
            recs.append(None)
            continue
        A = rng.standard_normal((nobs, K))
        r = 0.3 + rng.random(nobs)
        y = A @ X[:, t] + np.sqrt(r) * rng.standard_normal(nobs)
        N = A.T @ (A / r[:, None])
        b = A.T @ (y / r)
        recs.append(dict(A=A, r=r, y=y, N=N, b=b, ltpl=y @ (y / r),
                         logdetR=np.sum(np.log(r))))
    return recs


def kalman_info(Phi, Q, S0, recs, smooth=False):
    """kalmanFilter's neq mode (information update) and its -2 log
    likelihood term per epoch; optionally the RTS smoother from x0."""
    K = Phi.shape[0]
    x, P = np.zeros(K), S0.copy()
    xs0, Ps0 = x.copy(), P.copy()
    nll, out = [], []
    for rec in recs:
        m = Phi @ x
        Pm = Phi @ P @ Phi.T + Q
        Pm = (Pm + Pm.T) / 2
        if rec is None:
            xp, Pp = m, Pm
            nll.append(0.0)
        else:
            N, b = rec["N"], rec["b"]
            Lp = np.linalg.cholesky(Pm)
            M = np.eye(K) + Lp.T @ N @ Lp
            Lm = np.linalg.cholesky(M)
            u = b - N @ m
            z = np.linalg.solve(Lm, Lp.T @ u)
            nll.append(2 * np.sum(np.log(np.diag(Lm))) + m @ N @ m - 2 * m @ b - z @ z)
            Pp = np.linalg.inv(np.linalg.inv(Pm) + N)
            Pp = (Pp + Pp.T) / 2
            xp = Pp @ (np.linalg.solve(Pm, m) + b)
        out.append((m, Pm, xp, Pp))
        x, P = xp, Pp
    if not smooth:
        return np.array(nll)
    T = len(out)
    xs = [None] * (T + 1); Ps = [None] * (T + 1); Pc = [None] * (T + 1)
    xs[T], Ps[T] = out[-1][2], out[-1][3]
    for t in range(T - 1, -1, -1):          # t = 0 is x0
        xf, Pf = (xs0, Ps0) if t == 0 else (out[t - 1][2], out[t - 1][3])
        m, Pm = out[t][0], out[t][1]
        G = Pf @ Phi.T @ np.linalg.inv(Pm)
        xs[t] = xf + G @ (xs[t + 1] - m)
        Ps[t] = Pf + G @ (Ps[t + 1] - Pm) @ G.T
        Pc[t + 1] = Ps[t + 1] @ G.T           # Cov(x_(t+1), x_t | y)
    return np.array(nll), xs, Ps, Pc


def dense_nll(Phi, Q, S0, recs):
    K = Phi.shape[0]
    T = len(recs)
    V = [None] * (T + 1)
    V[0] = S0
    for t in range(1, T + 1):
        V[t] = Phi @ V[t - 1] @ Phi.T + Q
    Sig = np.zeros((K * T, K * T))
    for s in range(T):
        for t in range(s + 1):
            C = np.linalg.matrix_power(Phi, s - t) @ V[t + 1]
            Sig[s * K:(s + 1) * K, t * K:(t + 1) * K] = C
            Sig[t * K:(t + 1) * K, s * K:(s + 1) * K] = C.T
    rows, ys, rs = [], [], []
    for t, rec in enumerate(recs):
        if rec is None:
            continue
        A = np.zeros((rec["A"].shape[0], K * T))
        A[:, t * K:(t + 1) * K] = rec["A"]
        rows.append(A); ys.append(rec["y"]); rs.append(rec["r"])
    A = np.vstack(rows); y = np.concatenate(ys); r = np.concatenate(rs)
    C = A @ Sig @ A.T + np.diag(r)
    sign, logdet = np.linalg.slogdet(C)
    return logdet + y @ np.linalg.solve(C, y)


rng = np.random.default_rng(20261021)

# ---------------------------------------------------------- CLAIM 1
Phi, Q0, S0 = model(rng)
X = simulate(Phi, Q0, S0, 20, rng)
recs = observations(X, rng, gaps=(4, 5, 13))
nll = kalman_info(Phi, Q0, S0, recs)
const = sum(r["logdetR"] + r["ltpl"] for r in recs if r is not None)
dense = dense_nll(Phi, Q0, S0, recs)
e1 = abs(nll.sum() + const - dense) / abs(dense)
# solution mode on the same data: R = N^-1 on an identity design (A = I)
Xs = observations(X, rng, nobs=6, gaps=(4,))
rec = Xs[0]
A = rec["A"]
# a square A: the solution l = A^-1 y has R = A^-1 diag(r) A^-T
l = np.linalg.solve(A, rec["y"])
Rl = np.linalg.solve(A, np.diag(rec["r"])) @ np.linalg.inv(A).T
Rl = (Rl + Rl.T) / 2
m = Phi @ np.zeros(6)
Pm = Phi @ S0 @ Phi.T + Q0
S = Pm + Rl
d = l - m
sol = np.linalg.slogdet(S)[1] + d @ np.linalg.solve(S, d)
Nl = np.linalg.inv(Rl); bl = Nl @ l
Lp = np.linalg.cholesky(Pm)
Lm = np.linalg.cholesky(np.eye(6) + Lp.T @ Nl @ Lp)
u = bl - Nl @ m
z = np.linalg.solve(Lm, Lp.T @ u)
neq = 2 * np.sum(np.log(np.diag(Lm))) + m @ Nl @ m - 2 * m @ bl - z @ z
e1b = abs(sol - neq - (np.linalg.slogdet(Rl)[1] + l @ Nl @ l)) / abs(sol)
claim(e1 < 1e-12 and e1b < 1e-12,
      "CLAIM 1  NEQ-form innovation likelihood = dense joint likelihood %.1e "
      "(20 epochs, 3 gaps); solution - neq = log|R| + l'R^-1 l, %.1e" % (e1, e1b))

# ---------------------------------------------------------- CLAIM 2
Phi, Q0, S0 = model(rng)
X = simulate(Phi, 3.0 * Q0, S0, 120, rng)
recs = observations(X, rng, gaps=(10, 11, 50))
blocks1 = np.zeros(6, int)


def f1(th):
    return kalman_info(Phi, scaled(Q0, [np.exp(th)], blocks1), S0, recs).sum()


ml = np.exp(minimize_scalar(f1, bounds=(np.log(1e-3), np.log(1e3)), method="bounded",
                            options=dict(xatol=1e-10)).x)
a = 1.0
for it in range(500):
    _, xs, Ps, Pc = kalman_info(Phi, a * Q0, S0, recs, smooth=True)
    Qi = np.linalg.inv(Q0)
    acc = 0.0
    for t in range(1, len(recs) + 1):
        w = xs[t] - Phi @ xs[t - 1]
        E = (np.outer(w, w) + Ps[t] - Pc[t] @ Phi.T - Phi @ Pc[t].T
             + Phi @ Ps[t - 1] @ Phi.T)
        acc += np.trace(Qi @ E)
    a_new = acc / (6 * len(recs))
    if abs(a_new - a) < 1e-12 * a:
        a = a_new
        break
    a = a_new
e2 = abs(ml - a) / a
claim(e2 < 1e-6, "CLAIM 2  one block: likelihood maximum %.6f = EM fixed point %.6f "
      "(%.1e, %d EM iterations; truth 3)" % (ml, a, e2, it + 1))

# ---------------------------------------------------------- CLAIM 3
truth = np.array([4.0, 0.5])
blocks2 = np.array([0, 0, 0, 1, 1, 1])
est, gain = [], []
for seed in range(30):
    r = np.random.default_rng(1000 + seed)
    Phi, Q0, S0 = model(r)
    X = simulate(Phi, scaled(Q0, truth, blocks2), S0, 150, r)
    recs = observations(X, r, nobs=3)

    def f2(th):
        return kalman_info(Phi, scaled(Q0, np.exp(th), blocks2), S0, recs).sum()

    res = minimize(f2, np.zeros(2), method="Nelder-Mead",
                   options=dict(xatol=1e-6, fatol=1e-8, maxiter=2000))
    ah = np.exp(res.x)
    est.append(ah)

    def rms(alpha):
        _, xs, _, _ = kalman_info(Phi, scaled(Q0, alpha, blocks2), S0, recs, smooth=True)
        return np.sqrt(np.mean((np.array(xs[1:]).T - X) ** 2))

    gain.append(rms(ah) < rms([1.0, 1.0]))
est = np.array(est)
mean, se = est.mean(0), est.std(0, ddof=1) / np.sqrt(len(est))
ok3 = np.all(np.abs(mean - truth) < 3 * se) and np.mean(gain) > 0.7
claim(ok3, "CLAIM 3  two blocks, truth (4, 0.5): mean estimate (%.2f, %.2f), spread "
      "(%.2f, %.2f), within 3 SE; estimated alphas beat alpha = 1 in %d of 30 seeds"
      % (mean[0], mean[1], est.std(0)[0], est.std(0)[1], int(np.sum(gain))))
print("    relative spread of one estimate: (%.2f, %.2f)" % tuple(est.std(0) / truth))

# ---------------------------------------------------------- CLAIM 4
wins = 0
worst = worstP = 0.0
for seed in range(10):
    r = np.random.default_rng(2000 + seed)
    K = 4
    P1 = 0.9 * np.eye(K) + 0.05 * r.standard_normal((K, K))
    P2 = -0.5 * np.eye(K) + 0.05 * r.standard_normal((K, K))
    Bc = np.block([[P1, P2], [np.eye(K), np.zeros((K, K))]])
    if max(abs(np.linalg.eigvals(Bc))) > 0.97:
        Bc[:K] *= 0.97 / max(abs(np.linalg.eigvals(Bc)))
    L = r.standard_normal((K, K))
    Qt = L @ L.T / K + 0.3 * np.eye(K)
    # a long realisation, as the model series, and a short one observed
    def var2(T):
        z = np.zeros(2 * K); Z = np.zeros((K, T))
        cQ = np.linalg.cholesky(Qt)
        for t in range(T + 200):
            z = Bc @ z
            z[:K] += cQ @ r.standard_normal(K)
            if t >= 200:
                Z[:, t - 200] = z[:K]
        return Z
    Xm = var2(3000)
    Xo = var2(150)
    recs = observations(Xo, r, nobs=6)    # N regular: the gain form needs R = N^-1
    # Yule-Walker of order 1 and 2 (estimateVAR)
    T = Xm.shape[1]
    G = [Xm[:, k:] @ Xm[:, :T - k].T / (T - k) for k in range(3)]
    G0 = (G[0] + G[0].T) / 2
    Ph1 = G[1] @ np.linalg.inv(G0)
    Q1 = G0 - Ph1 @ G[1].T
    Big = np.block([[G0, G[1]], [G[1].T, G0]])     # E[(x_t-1; x_t-2)(x_t-1; x_t-2)']
    Ph = np.hstack([G[1], G[2]]) @ np.linalg.inv(Big)
    Q2 = G0 - Ph @ np.hstack([G[1], G[2]]).T
    nll1 = kalman_info(Ph1, (Q1 + Q1.T) / 2, G0, recs).sum()
    # order 2 in companion space, physical block observed
    B2 = np.block([[Ph], [np.eye(K), np.zeros((K, K))]])
    Q2c = np.zeros((2 * K, 2 * K)); Q2c[:K, :K] = (Q2 + Q2.T) / 2
    S2 = np.kron(np.eye(2), G0)
    recs2 = [None if q is None else dict(q, N=np.pad(q["N"], ((0, K), (0, K))),
                                         b=np.pad(q["b"], (0, K))) for q in recs]

    def info2(B, Q, S0, recs2):
        n = B.shape[0]
        x, P = np.zeros(n), S0.copy()
        nll, xs, ps = 0.0, [], []
        for q in recs2:
            m = B @ x
            Pm = B @ P @ B.T + Q
            Pm = (Pm + Pm.T) / 2
            if q is not None:
                N, bb = q["N"][:K, :K], q["b"][:K]
                P11 = Pm[:K, :K]
                Lp = np.linalg.cholesky(P11)
                Lm = np.linalg.cholesky(np.eye(K) + Lp.T @ N @ Lp)
                u = bb - N @ m[:K]
                z = np.linalg.solve(Lm, Lp.T @ u)
                nll += 2 * np.sum(np.log(np.diag(Lm))) + m[:K] @ N @ m[:K] - 2 * m[:K] @ bb - z @ z
                P = np.linalg.inv(np.linalg.inv(Pm) + q["N"])
                P = (P + P.T) / 2
                x = P @ (np.linalg.solve(Pm, m) + q["b"])
            else:
                x, P = m, Pm
            xs.append(x.copy())
            ps.append(np.diag(P).copy())
        return nll, np.array(xs), np.array(ps)

    def gain2(B, Q, S0, recs):
        n = B.shape[0]
        x, P = np.zeros(n), S0.copy()
        xs, ps = [], []
        for q in recs:
            m = B @ x
            Pm = B @ P @ B.T + Q
            Pm = (Pm + Pm.T) / 2
            if q is not None:
                Rl = np.linalg.inv(q["N"])
                l = Rl @ q["b"]
                Kg = Pm[:, :K] @ np.linalg.inv(Pm[:K, :K] + Rl)
                x = m + Kg @ (l - m[:K])
                IKH = np.eye(n); IKH[:, :K] -= Kg
                P = IKH @ Pm @ IKH.T + Kg @ Rl @ Kg.T
            else:
                x, P = m, Pm
            xs.append(x.copy())
            ps.append(np.diag(P).copy())
        return np.array(xs), np.array(ps)

    nll2, xi, pi_ = info2(B2, Q2c, S2, recs2)
    xg, pg = gain2(B2, Q2c, S2, recs)
    worst = max(worst, np.abs(xi - xg).max() / np.abs(xg).max())
    worstP = max(worstP, np.abs(np.sqrt(pi_ / pg) - 1).max())
    wins += nll2 < nll1
claim(wins == 10 and worst < 1e-11 and worstP < 1e-11,
      "CLAIM 4  VAR(2) truth: order 2 has the lower -2 log likelihood in %d of 10 "
      "seeds; information = gain form in companion space, states %.1e, filtered "
      "sigmas %.1e" % (wins, worst, worstP))

# ---------------------------------------------------------- CLAIM 4b
# The MATLAB test's configuration (testRegionalKalmanOrderTwoOnTheSHBasis-
# IsKalmanChain): four coefficients (nmax 1), a stationary VAR(2) truth, a
# 3000-epoch model series for the Yule-Walker estimate, 30 monthly epochs
# observed directly (H = I, diagonal sigmas, every fourth missing), and the
# SMOOTHED output the chains return. The information form against the gain
# form, then the same RTS pass over each.


def rts(B, out, x0, P0):
    T = len(out)
    xs, ps = [None] * T, [None] * T
    xs[-1], Pn = out[-1][2], out[-1][3]
    ps[-1] = np.diag(Pn).copy()
    for t in range(T - 2, -1, -1):
        xf, Pf = out[t][2], out[t][3]
        m, Pm = out[t + 1][0], out[t + 1][1]
        G = Pf @ B.T @ np.linalg.inv(Pm)
        xs[t] = xf + G @ (xs[t + 1] - m)
        Pn = Pf + G @ (Pn - Pm) @ G.T
        ps[t] = np.diag(Pn).copy()
    return np.array(xs), np.array(ps)


worst4b = worstP4b = 0.0
for seed in range(40):
    r = np.random.default_rng(4000 + seed)
    K = 4
    P1 = 0.9 * np.eye(K) + 0.05 * r.standard_normal((K, K))
    P2 = -0.5 * np.eye(K) + 0.05 * r.standard_normal((K, K))
    Bc = np.block([[P1, P2], [np.eye(K), np.zeros((K, K))]])
    rho = max(abs(np.linalg.eigvals(Bc)))
    if rho > 0.97:
        Bc[:K] *= 0.97 / rho
    L = r.standard_normal((K, K))
    cQ = np.linalg.cholesky(L @ L.T / K + 0.3 * np.eye(K))
    z = np.zeros(2 * K)
    Z = np.zeros((K, 3030))
    for t in range(3230):
        z = Bc @ z
        z[:K] += cQ @ r.standard_normal(K)
        if t >= 200:
            Z[:, t - 200] = z[:K]
    Xm, Xo = Z[:, :3000], Z[:, 3000:]
    T = Xm.shape[1]
    G = [Xm[:, k:] @ Xm[:, :T - k].T / (T - k) for k in range(3)]
    G0 = (G[0] + G[0].T) / 2
    Big = np.block([[G0, G[1]], [G[1].T, G0]])
    Ph = np.hstack([G[1], G[2]]) @ np.linalg.inv(Big)
    Q2 = G0 - Ph @ np.hstack([G[1], G[2]]).T
    B2 = np.block([[Ph], [np.eye(K), np.zeros((K, K))]])
    Q2c = np.zeros((2 * K, 2 * K)); Q2c[:K, :K] = (Q2 + Q2.T) / 2
    S0 = (Big + Big.T) / 2
    sig = 0.5 * np.sqrt(np.diag(G0)) * (1 + r.random(K))
    obs = [None if t % 4 == 3 else Xo[:, t] + sig * r.standard_normal(K)
           for t in range(30)]
    outs = {}
    for form in ("info", "gain"):
        x, P = np.zeros(2 * K), S0.copy()
        out = []
        for y in obs:
            m = B2 @ x
            Pm = B2 @ P @ B2.T + Q2c
            Pm = (Pm + Pm.T) / 2
            if y is None:
                xp, Pp = m, Pm
            elif form == "info":
                N = np.zeros((2 * K, 2 * K)); N[:K, :K] = np.diag(1 / sig ** 2)
                b = np.zeros(2 * K); b[:K] = y / sig ** 2
                Jm = np.linalg.inv(Pm)               # kalmanFilter's neq form
                Pp = np.linalg.inv(Jm + N)
                xp = Pp @ (Jm @ m + b)
            else:
                Rl = np.diag(sig ** 2)               # its gain form, Joseph
                Kg = np.linalg.solve((Pm[:K, :K] + Rl), Pm[:, :K].T).T
                xp = m + Kg @ (y - m[:K])
                IKH = np.eye(2 * K); IKH[:, :K] -= Kg
                Pp = IKH @ Pm @ IKH.T + Kg @ Rl @ Kg.T
            Pp = (Pp + Pp.T) / 2
            out.append((m, Pm, xp, Pp))
            x, P = xp, Pp
        outs[form] = rts(B2, out, np.zeros(2 * K), S0)
    xi, pi_ = outs["info"]
    xg, pg = outs["gain"]
    worst4b = max(worst4b, np.abs(xi[:, :K] - xg[:, :K]).max() / np.abs(xg[:, :K]).max())
    worstP4b = max(worstP4b, np.abs(np.sqrt(pi_[:, :K] / pg[:, :K]) - 1).max())
claim(worst4b < 1e-11 and worstP4b < 1e-11,
      "CLAIM 4b VAR(2), the MATLAB test's configuration, smoothed: information = "
      "gain form to %.2e in the states and %.2e in the sigmas over 40 seeds"
      % (worst4b, worstP4b))

# ---------------------------------------------------------- CLAIM 5
idx, T, Proj, rank, Y, W, mask = rbf_basis(16, 50, 600)
K = T.shape[1]
Lk = rng.standard_normal((K, K))
S = Lk @ Lk.T / K
e5a = np.abs(Proj @ (T @ S @ T.T) @ Proj.T - S).max() / np.abs(S).max()
n = idx[0]
taper = np.exp(-np.abs(n[:, None] - n[None, :]) / 3.0)   # a PD Hadamard kernel
Sc = Proj @ (taper * (T @ S @ T.T)) @ Proj.T
e5b = np.linalg.eigvalsh((Sc + Sc.T) / 2).min() / np.linalg.eigvalsh(Sc).max()
claim(e5a < 1e-9 and e5b > -1e-12,
      "CLAIM 5  basis conditioner Proj cf(T S T') Proj': identity %.1e (Proj T = I), "
      "smallest eigenvalue with a taper %.1e of the largest" % (e5a, e5b))

print("validate_regional_adaptive: %d failed claim(s)" % len(FAIL))
sys.exit(1 if FAIL else 0)
