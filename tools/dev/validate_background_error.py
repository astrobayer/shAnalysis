"""validate_background_error: oracle for shLowLevel.backgroundErrorCov (WP9 9i).

The error of a background model (AOD1B, an ocean tide model) that a
GRACE solution has had removed is not in the solution's formal
covariance. With two releases (or two models) of the same product, a
and b, at common epochs, the difference d_t = a_t - b_t holds the two
errors and none of the signal. If the two errors are independent and of
equal size,

    E[(d - mean d)(d - mean d)'] = 2 C,     C_hat = Split * S_d,  Split 1/2,

S_d the sample covariance of the differences (mean removed, T - 1).
Structures: "full" (S_d itself), "diagonal" (its diagonal), "degree"
(per degree the mean of the diagonal over all orders, C and S: the
isotropic form). Shrink lambda: (1 - lambda) C + lambda diag(C).

Claims, bounds written before their run:
  CLAIM 1  consistency: with 4000 epochs of two independent releases of
           an error with known C (Lmax 8), the full estimate's relative
           Frobenius error is below 3 sqrt(P / T) and the diagonal one
           below 3 sqrt(2 / T) per coefficient (max)
  CLAIM 2  the degree form is the per-degree mean of the diagonal: for
           an isotropic C it is unbiased (relative error of every degree
           below 5 sqrt(2 / (T (2n+1))))
  CLAIM 3  the limitation, stated: when the two releases share part of
           their error (correlation rho), the estimate is (1 - rho) C;
           measured within 0.05 of 1 - rho for rho 0.5
  CLAIM 4  closed loop (SH basis, Lmax 12, VAR(1) phi 0.6, 60 epochs,
           20 seeds): observations carry formal noise plus a background
           error C_bg four times the formal variance at the low degrees.
           A filter that knows only the formal noise is overconfident
           (pooled z-rms > 1.3); with C_hat from 60 months of release
           differences added the pooled z-rms is within 0.9..1.15 and
           the error below the formal-only filter's in every seed
  CLAIM 5  (6.0.5) with RemoveMean false no mean is estimated and the
           divisor is T: over 4000 trials of T = 5 epochs of zero-mean
           errors the mean of trace(C_hat) / trace(C) is within 0.02 of 1
           (the former divisor T - 1 gives T / (T - 1) = 1.25)

Run: python3 tools/dev/validate_background_error.py   (numpy)

Developed by Matthias Weigelt with the help of Claude (Opus 5.5),
2026-11-06.
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import regional_oracle_lib as rl  # noqa: E402

FAIL = []


def check(name, ok, msg):
    print(f"{'PASS' if ok else 'FAIL'} {name}: {msg}")
    if not ok:
        FAIL.append(name)


def estimate(a, b, structure="full", split=0.5, shrink=0.0, n=None, remove_mean=True):
    d = a - b
    dof = d.shape[0]
    if remove_mean:
        d = d - d.mean(axis=0, keepdims=True)
        dof -= 1
    S = d.T @ d / dof
    C = split * S
    if structure == "diagonal":
        C = np.diag(np.diag(C))
    elif structure == "degree":
        v = np.diag(C).copy()
        for nn in np.unique(n):
            v[n == nn] = v[n == nn].mean()
        C = np.diag(v)
    if shrink > 0:
        C = (1 - shrink) * C + shrink * np.diag(np.diag(C))
    return C


def error_cov(idx, rng, scale=1.0):
    n = idx[0]
    P = n.size
    G = rng.standard_normal((P, P)) / np.sqrt(P)
    D = np.diag(scale / (n + 1.0) ** 2)
    C = D @ (0.3 * G @ G.T + np.eye(P)) @ D
    return (C + C.T) / 2


# ---------------------------------------------------------------- CLAIM 1
rng = np.random.default_rng(1)
idx = rl.sh_index(8)
n = idx[0]
P = n.size
Ct = error_cov(idx, rng)
Lc = np.linalg.cholesky(Ct)
T = 4000
sig = rng.standard_normal((T, P)) @ np.diag(1 / (n + 1.0))
a = sig + rng.standard_normal((T, P)) @ Lc.T
b = sig + rng.standard_normal((T, P)) @ Lc.T + 0.3      # an offset: mean removed
Cf = estimate(a, b)
ef = np.linalg.norm(Cf - Ct) / np.linalg.norm(Ct)
ed = np.max(np.abs(np.diag(Cf) / np.diag(Ct) - 1))
check("CLAIM 1", ef < 3 * np.sqrt(P / T) and ed < 3 * np.sqrt(2 / T),
      f"P {P}, T {T}: full {ef:.3f} (bound {3 * np.sqrt(P / T):.3f}), "
      f"diagonal {ed:.3f} (bound {3 * np.sqrt(2 / T):.3f}); offset removed")

# ---------------------------------------------------------------- CLAIM 2
v = 1 / (n + 1.0) ** 2
a = rng.standard_normal((T, P)) * np.sqrt(v)
b = rng.standard_normal((T, P)) * np.sqrt(v)
Cd = estimate(a, b, "degree", n=n)
worst = 0.0
ok2 = True
for nn in np.unique(n):
    e = abs(Cd[n == nn, n == nn][0] / v[n == nn][0] - 1)
    bound = 5 * np.sqrt(2 / (T * (2 * nn + 1)))
    ok2 &= e < bound
    worst = max(worst, e / bound)
check("CLAIM 2", ok2, f"degree form: worst error {worst:.2f} of its bound")

# ---------------------------------------------------------------- CLAIM 3
rho = 0.5
e1 = rng.standard_normal((T, P)) @ Lc.T
e2 = rho * e1 + np.sqrt(1 - rho ** 2) * (rng.standard_normal((T, P)) @ Lc.T)
r = np.trace(estimate(e1, e2)) / np.trace(Ct)
check("CLAIM 3", abs(r - (1 - rho)) < 0.05,
      f"shared error rho {rho}: estimate / truth {r:.3f} (expected {1 - rho})")


# ---------------------------------------------------------------- CLAIM 4
def rts(Q, S0, phi, y, R):
    P_ = Q.shape[0]
    x, Pm = np.zeros(P_), S0.copy()
    xf, Pf, xp, Pp = [], [], [], []
    Ri = np.linalg.inv(R)
    for t in range(len(y)):
        if t > 0:
            x, Pm = phi * x, phi ** 2 * Pm + Q
        xp.append(x); Pp.append(Pm)
        Pn = np.linalg.inv(np.linalg.inv(Pm) + Ri)
        x = Pn @ (np.linalg.solve(Pm, x) + Ri @ y[t])
        xf.append(x); Pf.append(Pn)
    xs, Ps = xf[:], Pf[:]
    for t in range(len(y) - 2, -1, -1):
        J = phi * Pf[t] @ np.linalg.inv(Pp[t + 1])
        xs[t] = xf[t] + J @ (xs[t + 1] - xp[t + 1])
        Ps[t] = Pf[t] + J @ (Ps[t + 1] - Pp[t + 1]) @ J.T
    return np.array(xs), np.array([np.diag(p) for p in Ps])


idx = rl.sh_index(12)
n = idx[0]
P = n.size
phi, T = 0.6, 60
Q = np.diag(1 / (n + 1.0) ** 4)
formal = np.diag(0.5 / (n + 1.0) ** 4)
z_f, z_b, g, n_ok = [], [], [], 0
for seed in range(20):
    g_ = np.random.default_rng(100 + seed)
    Cbg = error_cov(idx, g_, scale=2.0) * (n[:, None] <= 4) * (n[None, :] <= 4) \
        + np.diag(1e-6 / (n + 1.0) ** 4)
    Cbg = (Cbg + Cbg.T) / 2
    Lb = np.linalg.cholesky(Cbg)
    x = np.zeros((T, P))
    x[0] = g_.standard_normal(P) * np.sqrt(np.diag(Q) / (1 - phi ** 2))
    for t in range(1, T):
        x[t] = phi * x[t - 1] + g_.standard_normal(P) * np.sqrt(np.diag(Q))
    y = x + g_.standard_normal((T, P)) * np.sqrt(np.diag(formal)) \
        + g_.standard_normal((T, P)) @ Lb.T
    ra = g_.standard_normal((T, P)) @ Lb.T                  # two releases'
    rb = g_.standard_normal((T, P)) @ Lb.T                  # errors, 60 months
    Ch = estimate(ra, rb)
    S0 = Q / (1 - phi ** 2)
    xa, va = rts(Q, S0, phi, y, formal)
    xb, vb = rts(Q, S0, phi, y, formal + Ch)
    ea, eb = xa - x, xb - x
    z_f.append((ea ** 2 / va).mean())
    z_b.append((eb ** 2 / vb).mean())
    n_ok += np.sqrt((eb ** 2).mean()) < np.sqrt((ea ** 2).mean())
zf, zb = np.sqrt(np.mean(z_f)), np.sqrt(np.mean(z_b))
print(f"   pooled z-rms: formal only {zf:.3f}, formal + C_hat {zb:.3f}; "
      f"error lower in {n_ok} of 20 seeds")
check("CLAIM 4", zf > 1.3 and 0.9 <= zb <= 1.15 and n_ok == 20,
      f"z-rms {zf:.3f} -> {zb:.3f}, lower error in {n_ok}/20")

# ---------------------------------------------------------------- CLAIM 5
g5 = np.random.default_rng(5)
idx5 = rl.sh_index(4)
P5 = idx5[0].size
C5 = error_cov(idx5, g5)
L5 = np.linalg.cholesky(C5)
r5 = []
for _ in range(4000):
    a5 = g5.standard_normal((5, P5)) @ L5.T
    b5 = g5.standard_normal((5, P5)) @ L5.T
    r5.append(np.trace(estimate(a5, b5, remove_mean=False)) / np.trace(C5))
m5 = float(np.mean(r5))
check("CLAIM 5", abs(m5 - 1) < 0.02,
      f"RemoveMean false, divisor T: mean trace ratio {m5:.4f} over 4000 trials of T = 5")

print("FAILED: " + ", ".join(FAIL) if FAIL else "ALL CLAIMS PASS")
sys.exit(1 if FAIL else 0)
