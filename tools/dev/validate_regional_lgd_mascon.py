#!/usr/bin/env python3
"""validate_regional_lgd_mascon: WP8 row 8j, the regional filter on LGD
records in a mascon basis, with the process model from a model series.

lgdToolbox R-048 (HANDOVER F171, F175) measured, in coefficient space and
with Route C's estimator, that an ISOTROPIC prior cannot give a localised
load an honest error bar at any region size, and that variance placed
where the region is - mascons at the right mass scale - can, as long as
the model is right; it named three ways to fail: a mass scale 5x too
small, a footprint that does not fit, and the isotropic prior itself.
lgdToolbox D141 then decided that its handover to a regional filter stays
the LGD records (regionalNEQ kind "lgd"), not a Route C state. This
oracle asks the same question of THIS toolbox's chain - regionalBasis
(Type "mascon"), regionalProcessModel from a model series, regionalNEQ
"lgd" records, regionalKalman's filter and smoother, the basin mean and
the EWH at a point with their sigma from the full smoothed covariance -
in a closed loop written independently of the MATLAB code.

Configuration (fixed before any run): nmax 30, degrees 2..30, synthetic
load Love numbers k'_n = -0.30 n / (n + 3) (testCorrectness's); region
the cap of 1200 km about 51 N, 12 E, grown by 600 km; mascons on the
default icosahedral level with the equal-area radius (1002 global
nodes, 403 km caps). Truth, daily for 30 epochs after a 100-day spin-up:
  a localised load  EWH = A(t) exp(-d^2 / (2 s^2)), s = 300 km, at the
                    region's centre, A an AR(1) with rho = 0.9 per day
                    and stationary sd 0.20 m;
  a broad field     EWH coefficients AR(1), rho 0.9, sd 0.007 m / n,
                    every (n, m) - about 2 cm rms over the sphere.
Observations: 400 LGD records a day (pairs 490 km up, 220 km apart,
random headings, midpoints within 1800 km of the centre), white noise
0.5 x the rms of that seed's true LGD. Model series: an independent
realisation of 400 days of the MODEL's process, from which the process
model is estimated as regionalProcessModel does it (climatology - mean,
trend, annual, semi-annual - removed, projected, VAR(1) by Yule-Walker,
the filter started from Sigma(0)). The models:
  A  right      the truth's process;
  B  isotropic  the broad field alone, scaled so that its EWH variance
                over the region equals the truth's (load + field);
  C  amp / 5    the load's sd 0.04 m, the field unchanged;
  D  footprint  the load with s = 1000 km, same sd;
  E  C with EstimateQScale (one block; Q scaled, Sigma(0) not, as
     regionalKalman does), by maximum likelihood of the innovations.
Outputs: the basin mean of EWH over the 1200 km core and the EWH at the
load's centre; their truth is the band-limited (degrees 2..30) truth.
Statistics pooled over 20 seeds x 30 epochs.

  CLAIM 1  the oracle's filter (information-form update, RTS smoother)
           equals the dense joint posterior of all 30 epochs - states and
           covariances - to 1e-9 relative (model A, seed 0): the
           instrument is right before it measures anything.
  CLAIM 2  model A: z-rms of the basin mean and of the point value in
           [0.8, 1.25] and the share with |z| <= 2 in [0.88, 0.99].
  CLAIM 3  model B: the point value's z-rms above 1.5 - an isotropic
           model's sigma does not cover the load (F171, in the filter).
  CLAIM 4  model C: the point value's z-rms above 1.5 - a mass scale 5x
           too small is overconfident again (F175).
  CLAIM 5  model E: the median estimated alpha above 2, and the point
           value's z-rms below C's - the innovations see the scale.
  CLAIM 6  model D: the point value's error rms above 1.2 x A's - a
           footprint that does not fit costs accuracy (F175).

Printed beside the claims, not claimed: every case's error rms and z-rms
for both outputs, the share of the truth the basis represents, and the
alphas of E.

Run: python3 tools/dev/validate_regional_lgd_mascon.py  (nonzero exit on
any failed claim; prints the numbers the MATLAB test and docs quote).

Developed by Matthias Weigelt with the help of Claude (Opus 5.5),
2026-11-06.
"""
import os
import sys

import numpy as np
from scipy.optimize import minimize_scalar
from scipy.special import eval_legendre

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from regional_oracle_lib import (sh_index, ylm, quad_grid, icosahedral,  # noqa: E402
                                 nearest_3ring, buffered_mask, projector, unit)

FAIL = []
GM, R = 3.986004415e14, 6378136.3
RHO_AVE, RHO_W = 5517.0, 1000.0
L = 30
LAT0, LON0 = np.deg2rad(51.0), np.deg2rad(12.0)
CORE_KM, BUF_KM, OBS_KM = 1200.0, 600.0, 1800.0
NEPOCH, SPIN, NMODEL = 30, 100, 400
RHO, SD_LOAD, S_LOAD, S_WIDE = 0.9, 0.20, 300.0, 1000.0
SD_FIELD = 0.007
NREC, NOISE_FRAC = 400, 0.5
SEEDS = 20


def claim(ok, text):
    print(("PASS " if ok else "FAIL ") + text)
    if not ok:
        FAIL.append(text)


IDX = sh_index(L, 2)
NN = IDX[0]
P = NN.size
n_all = np.arange(L + 1)
KN = -0.30 * n_all / (n_all + 3.0)
FN = R * RHO_AVE / (3 * RHO_W) * (2 * n_all + 1) / (1 + KN)   # EWH = sum f_n x_nm Ybar_nm


def dist(lat, lon):
    c = unit(lat, lon) @ unit(np.array([LAT0]), np.array([LON0]))[0]
    return np.arccos(np.clip(c, -1, 1)) * R / 1e3


# ------------------------------------------------------------- basis
lat_g, lon_g, LAT, LON, W = quad_grid(L, 2)
core = dist(LAT, LON) <= CORE_KM
mask = buffered_mask(core, LAT, LON, BUF_KM * 1e3 / R)
j = int(np.ceil((L + 1) / np.sqrt(10))) - 1
while 10 * (j + 1) ** 2 + 2 < (L + 1) ** 2:
    j += 1
_, pts = icosahedral(j + 1)
NGLOBAL = pts.shape[0]
plat = np.arcsin(pts[:, 2])
plon = np.mod(np.arctan2(pts[:, 1], pts[:, 0]), 2 * np.pi)
sel = mask[nearest_3ring(plat, plon, lat_g, lon_g)]
t0 = 1 - 2.0 / NGLOBAL
cn = np.empty(L + 1)
cn[0] = (1 - t0) / 2
cn[1:] = (eval_legendre(n_all[1:] - 1, t0) - eval_legendre(n_all[1:] + 1, t0)) / 2
phi = cn / ((2 * n_all + 1) * FN)
T = phi[NN][:, None] * ylm(plat[sel], plon[sel], IDX).T
K = T.shape[1]
Yg = ylm(LAT, LON, IDX)
Kq = Yg.T @ ((W * mask)[:, None] * Yg)
Proj, rank = projector(T, (Kq + Kq.T) / 2)
# output functionals in SH coefficients: EWH basin mean, EWH at the centre
Fb = (W * core) @ (Yg * FN[NN][None, :]) / (W * core).sum()
Fp = (ylm(np.array([LAT0]), np.array([LON0]), IDX) * FN[NN][None, :])[0]
print("basis: %d of %d mascons (cap %.1f km), rank %d, P %d"
      % (K, NGLOBAL, np.arccos(t0) * R / 1e3, rank, P))

# ------------------------------------------------------------- loads
xq, wq = np.polynomial.legendre.leggauss(400)


def gauss_load(s_km):
    """Stokes coefficients of EWH = exp(-d^2 / 2 s^2) about the centre."""
    psi = np.arccos(xq)
    g = np.exp(-(psi * R / 1e3) ** 2 / (2 * s_km ** 2))
    gn = np.array([0.5 * np.sum(wq * g * eval_legendre(n, xq)) for n in n_all])
    # g(psi) = sum (2n+1) g_n P_n(cos psi), and by the addition theorem
    # its 4pi-normalised EWH coefficients are g_n Ybar_nm(c)
    yc = ylm(np.array([LAT0]), np.array([LON0]), IDX)[0]
    return gn[NN] * yc / FN[NN]


LOAD = gauss_load(S_LOAD)
WIDE = gauss_load(S_WIDE)
FIELD_SD = SD_FIELD / NN / FN[NN]          # Stokes sd of the broad field


def ar1(rng, sd, n, shape=()):
    x = np.zeros((n + SPIN,) + shape)
    x[0] = sd * rng.standard_normal(shape)
    e = sd * np.sqrt(1 - RHO ** 2)
    for k in range(1, n + SPIN):
        x[k] = RHO * x[k - 1] + e * rng.standard_normal(shape)
    return x[SPIN:]


def realise(rng, n, sd_load, load, field_scale):
    a = ar1(rng, sd_load, n)
    f = ar1(rng, 1.0, n, (P,)) * FIELD_SD[None, :] * field_scale
    return (a[:, None] * load[None, :] + f).T          # (P, n)


# ------------------------------------------------------------- LGD design
def alf_c(Lx, lat):
    t, u = np.sin(lat), np.cos(lat)
    Pc = np.zeros((Lx + 1, Lx + 1, lat.size), dtype=complex)
    Pc[0, 0] = 1.0
    Pc[1, 1] = np.sqrt(3.0) * u
    for mm in range(2, Lx + 1):
        Pc[mm, mm] = np.sqrt((2 * mm + 1) / (2 * mm)) * u * Pc[mm - 1, mm - 1]
    for mm in range(0, Lx + 1):
        for nn in range(mm + 1, Lx + 1):
            a = np.sqrt((2 * nn - 1) * (2 * nn + 1) / ((nn - mm) * (nn + mm)))
            Pc[nn, mm] = a * t * Pc[nn - 1, mm]
            if nn - 2 >= mm:
                b = np.sqrt((2 * nn + 1) * (nn + mm - 1) * (nn - mm - 1)
                            / ((nn - mm) * (nn + mm) * (2 * nn - 3)))
                Pc[nn, mm] -= b * Pc[nn - 2, mm]
    return Pc


def gradient_design(X, d):
    n, m, cs = IDX
    r = np.linalg.norm(X, axis=1)
    lat, lon = np.arcsin(X[:, 2] / r), np.arctan2(X[:, 1], X[:, 0])
    h = 1e-30
    Pc = alf_c(L, lat + 1j * h)
    P0 = Pc.real[n, m, :].T
    dP = (Pc.imag / h)[n, m, :].T
    c, s = np.cos(np.outer(lon, m)), np.sin(np.outer(lon, m))
    trig = np.where(cs == 0, c, s)
    dtrig = np.where(cs == 0, -m * s, m * c)
    p = (n + 1.0)[None, :]
    rad = GM / R * (R / r)[:, None] ** p
    north = rad * dP * trig / r[:, None]
    east = rad * P0 * dtrig / (r * np.cos(lat))[:, None]
    up = -rad * P0 * trig * p / r[:, None]
    sp, cp, sl, cl = np.sin(lat), np.cos(lat), np.sin(lon), np.cos(lon)
    dn = d[:, 0] * (-sp * cl) + d[:, 1] * (-sp * sl) + d[:, 2] * cp
    de = d[:, 0] * (-sl) + d[:, 1] * cl
    du = d[:, 0] * (cp * cl) + d[:, 1] * (cp * sl) + d[:, 2] * sp
    return dn[:, None] * north + de[:, None] * east + du[:, None] * up


def lgd_pairs(rng, M):
    """Midpoints uniform within OBS_KM of the centre, random headings."""
    c0 = unit(np.array([LAT0]), np.array([LON0]))[0]
    e1 = np.cross([0, 0, 1.0], c0); e1 /= np.linalg.norm(e1)
    e2 = np.cross(c0, e1)
    psi = np.arccos(1 - rng.uniform(0, 1, M) * (1 - np.cos(OBS_KM * 1e3 / R)))
    az = rng.uniform(0, 2 * np.pi, M)
    u = (np.cos(psi)[:, None] * c0 + np.sin(psi)[:, None]
         * (np.cos(az)[:, None] * e1 + np.sin(az)[:, None] * e2))
    t = np.cross(u, rng.standard_normal((M, 3)))
    t /= np.linalg.norm(t, axis=1)[:, None]
    r = R + 490e3
    th = 110e3 / r
    rA = r * (np.cos(th) * u - np.sin(th) * t)
    rB = r * (np.cos(th) * u + np.sin(th) * t)
    e = (rB - rA) / np.linalg.norm(rB - rA, axis=1)[:, None]
    return gradient_design(rB, e) - gradient_design(rA, e)


# ------------------------------------------------------------- process model
def process_model(Xm):
    tm = 2010 + (np.arange(Xm.shape[1]) + 0.5) / 365.25
    D = np.column_stack([np.ones_like(tm), tm - tm.mean(), np.cos(2 * np.pi * tm),
                         np.sin(2 * np.pi * tm), np.cos(4 * np.pi * tm),
                         np.sin(4 * np.pi * tm)])
    res = Xm - (Xm @ D) @ np.linalg.solve(D.T @ D, D.T)
    a = Proj @ res
    nt = a.shape[1]
    S0 = a @ a.T / nt
    S1 = a[:, 1:] @ a[:, :-1].T / nt
    S0 = (S0 + S0.T) / 2
    Phi = np.linalg.solve(S0, S1.T).T
    Q = S0 - Phi @ S1.T
    return Phi, (Q + Q.T) / 2, S0


def smooth(Phi, Q, S0, recs, need_ll=False):
    """Information-form forward filter (start 0, S0) and RTS smoother."""
    x, Pp = np.zeros(K), S0.copy()
    xs_m, Ps_m, xs_p, Ps_p = [], [], [], []
    nll = 0.0
    for k, (N, b, H, y, sig) in enumerate(recs):
        if k == 0:
            xm, Pm = x, Pp
        else:
            xm = Phi @ x
            Pm = Phi @ Pp @ Phi.T + Q
        Pm = (Pm + Pm.T) / 2
        if need_ll:
            v = y - H @ xm
            Sv = H @ Pm @ H.T + sig ** 2 * np.eye(y.size)
            cS = np.linalg.cholesky(Sv)
            z = np.linalg.solve(cS, v)
            nll += z @ z + 2 * np.log(np.diag(cS)).sum()
        Jm = np.linalg.inv(Pm)
        Pp = np.linalg.inv(Jm + N)
        Pp = (Pp + Pp.T) / 2
        x = Pp @ (Jm @ xm + b)
        xs_m.append(xm); Ps_m.append(Pm); xs_p.append(x); Ps_p.append(Pp)
    xs, Ps = [None] * len(recs), [None] * len(recs)
    xs[-1], Ps[-1] = xs_p[-1], Ps_p[-1]
    for k in range(len(recs) - 2, -1, -1):
        G = Ps_p[k] @ Phi.T @ np.linalg.inv(Ps_m[k + 1])
        xs[k] = xs_p[k] + G @ (xs[k + 1] - xs_m[k + 1])
        Ps[k] = Ps_p[k] + G @ (Ps[k + 1] - Ps_m[k + 1]) @ G.T
        Ps[k] = (Ps[k] + Ps[k].T) / 2
    return xs, Ps, nll


def dense(Phi, Q, S0, recs):
    """The joint Gaussian posterior of all epochs, built as one matrix."""
    E = len(recs)
    C = np.zeros((E * K, E * K))
    C[:K, :K] = S0
    for k in range(1, E):
        for i in range(k):
            C[k * K:(k + 1) * K, i * K:(i + 1) * K] = Phi @ C[(k - 1) * K:k * K, i * K:(i + 1) * K]
        C[k * K:(k + 1) * K, k * K:(k + 1) * K] = (Phi @ C[(k - 1) * K:k * K, (k - 1) * K:k * K]
                                                    @ Phi.T + Q)
        for i in range(k):
            C[i * K:(i + 1) * K, k * K:(k + 1) * K] = C[k * K:(k + 1) * K, i * K:(i + 1) * K].T
    N = np.zeros_like(C)
    b = np.zeros(E * K)
    for k, (Nk, bk, *_rest) in enumerate(recs):
        N[k * K:(k + 1) * K, k * K:(k + 1) * K] = Nk
        b[k * K:(k + 1) * K] = bk
    Pd = np.linalg.inv(np.linalg.inv(C) + N)
    return Pd @ b, Pd


# ------------------------------------------------------------- the loop
cases = ["A", "B", "C", "D", "E"]
zb = {c: [] for c in cases}; zp = {c: [] for c in cases}
eb = {c: [] for c in cases}; ep = {c: [] for c in cases}
alphas, represent = [], []
for seed in range(SEEDS):
    rng = np.random.default_rng(20261106 + seed)
    X = realise(rng, NEPOCH, SD_LOAD, LOAD, 1.0)
    Hs = [lgd_pairs(rng, NREC) for _ in range(NEPOCH)]
    ytrue = [H @ X[:, k] for k, H in enumerate(Hs)]
    sig = NOISE_FRAC * np.sqrt(np.mean(np.concatenate(ytrue) ** 2))
    ys = [y + sig * rng.standard_normal(y.size) for y in ytrue]
    recs = []
    for H, y in zip(Hs, ys):
        HT = H @ T
        recs.append((HT.T @ HT / sig ** 2, HT.T @ y / sig ** 2, HT, y, sig))
    reg = mask
    res = X - T @ (Proj @ X)
    Er = np.sum(W[reg][:, None] * (Yg[reg] @ (FN[NN][:, None] * res)) ** 2)
    Es = np.sum(W[reg][:, None] * (Yg[reg] @ (FN[NN][:, None] * X)) ** 2)
    represent.append(1 - Er / Es)
    tb, tp = Fb @ X, Fp @ X
    # model series, one per model
    XmA = realise(rng, NMODEL, SD_LOAD, LOAD, 1.0)
    rms_true = np.sqrt(np.mean((Yg[core] @ (FN[NN][:, None] * XmA)) ** 2))
    XmF = realise(rng, NMODEL, 0.0, LOAD, 1.0)
    rms_f = np.sqrt(np.mean((Yg[core] @ (FN[NN][:, None] * XmF)) ** 2))
    models = {"A": XmA, "B": XmF * (rms_true / rms_f),
              "C": realise(rng, NMODEL, SD_LOAD / 5, LOAD, 1.0),
              "D": realise(rng, NMODEL, SD_LOAD, WIDE, 1.0)}
    for c in cases:
        Phi, Q, S0 = process_model(models["C" if c == "E" else c])
        al = 1.0
        if c == "E":
            f = lambda la: smooth(Phi, np.exp(la) * Q, S0, recs, True)[2]  # noqa: E731
            r = minimize_scalar(f, bounds=(np.log(1e-4), np.log(1e4)), method="bounded",
                                options={"xatol": 1e-4})
            al = float(np.exp(r.x))
            alphas.append(al)
        xs, Ps, _ = smooth(Phi, al * Q, S0, recs)
        if c == "A" and seed == 0:
            xd, Pd = dense(Phi, Q, S0, recs)
            xsv = np.concatenate(xs)
            Psd = np.array([Ps[k] for k in range(NEPOCH)])
            Pdd = np.array([Pd[k * K:(k + 1) * K, k * K:(k + 1) * K] for k in range(NEPOCH)])
            e1 = np.abs(xsv - xd).max() / np.abs(xd).max()
            e2 = np.abs(Psd - Pdd).max() / np.abs(Pdd).max()
            claim(e1 < 1e-9 and e2 < 1e-9, "CLAIM 1  filter + RTS = dense joint posterior: "
                  "states %.1e, covariances %.1e relative" % (e1, e2))
        for k in range(NEPOCH):
            mb, mp = Fb @ T @ xs[k], Fp @ T @ xs[k]
            sb = np.sqrt((Fb @ T) @ Ps[k] @ (Fb @ T))
            sp_ = np.sqrt((Fp @ T) @ Ps[k] @ (Fp @ T))
            eb[c].append(mb - tb[k]); ep[c].append(mp - tp[k])
            zb[c].append((mb - tb[k]) / sb); zp[c].append((mp - tp[k]) / sp_)


def zrms(v):
    return float(np.sqrt(np.mean(np.square(v))))


def cov2(v):
    return float(np.mean(np.abs(v) <= 2))


print("representation (share of the truth's energy over the buffered region): "
      "median %.3f, %.3f..%.3f" % (np.median(represent), min(represent), max(represent)))
print("case   basin: err rms [cm]  z-rms  |z|<=2    point: err rms [cm]  z-rms  |z|<=2")
for c in cases:
    print("  %s          %7.3f        %5.2f  %5.3f            %7.3f        %5.2f  %5.3f"
          % (c, 100 * zrms(eb[c]), zrms(zb[c]), cov2(zb[c]),
             100 * zrms(ep[c]), zrms(zp[c]), cov2(zp[c])))
print("E: alpha median %.2f, range %.2f..%.2f" % (np.median(alphas), min(alphas), max(alphas)))

claim(0.8 <= zrms(zb["A"]) <= 1.25 and 0.8 <= zrms(zp["A"]) <= 1.25
      and 0.88 <= cov2(zb["A"]) <= 0.99 and 0.88 <= cov2(zp["A"]) <= 0.99,
      "CLAIM 2  model A: z-rms basin %.2f, point %.2f; |z| <= 2 basin %.3f, point %.3f"
      % (zrms(zb["A"]), zrms(zp["A"]), cov2(zb["A"]), cov2(zp["A"])))
claim(zrms(zp["B"]) > 1.5, "CLAIM 3  model B (isotropic): point z-rms %.2f > 1.5" % zrms(zp["B"]))
claim(zrms(zp["C"]) > 1.5, "CLAIM 4  model C (amp / 5): point z-rms %.2f > 1.5" % zrms(zp["C"]))
claim(np.median(alphas) > 2 and zrms(zp["E"]) < zrms(zp["C"]),
      "CLAIM 5  model E: alpha median %.2f > 2, point z-rms %.2f < C's %.2f"
      % (np.median(alphas), zrms(zp["E"]), zrms(zp["C"])))
claim(zrms(ep["D"]) > 1.2 * zrms(ep["A"]),
      "CLAIM 6  model D (footprint 1000 km): point error %.3f cm > 1.2 x A's %.3f cm"
      % (100 * zrms(ep["D"]), 100 * zrms(ep["A"])))

if FAIL:
    print("%d claim(s) FAILED" % len(FAIL))
    sys.exit(1)
print("all claims pass")
