#!/usr/bin/env python3
"""validate_regional_basis: numerical pre-validation of WP8 row 8a.

Independent numpy/scipy port of the regional basis that
shLowLevel.regionalBasis, shLowLevel.regionalProject and
shLowLevel.readBasin implement, written BEFORE the MATLAB code
(CLAUDE.md section 2). Every claim is checked against a route that does
not share the code under test:

  CLAIM 0  node grids. The icosahedral grid of frequency f = j + 1 has
           exactly 10 f^2 + 2 distinct nodes (Woehnke et al. 2025, eq. 8),
           all on the unit sphere; the Reuter grid has one node per pole,
           rings symmetric about the equator and about 4 gamma^2 / pi
           nodes in all (5 on the first ring: the integer part of
           2 pi / arccos(cos(dth) / (1 + cos(dth))) is 5, not 6).
  CLAIM 1  the RBF column T(:,k) = phi_n Ybar(x_k)' synthesises to the
           Legendre series sum_n phi_n (2n+1) P_n(cos psi) - the addition
           theorem, checked against scipy's eval_legendre, not against the
           ALF recursion used to build T.
  CLAIM 2  node selection: the 3-ring nearest-point search returns the
           same nearest quadrature point as a brute-force search.
  CLAIM 3  the projector Proj = (T'KT)^+ T'K satisfies the normal
           equations T'K (x - T Proj x) = 0 and reproduces every field in
           the span of T over the region.
  CLAIM 4  for a Slepian basis the general projector IS G' (the routes
           agree to rounding), so regionalProject generalises
           slepianProject rather than competing with it.
  CLAIM 5  region handles from GeoJSON rings: the Elbe's quadrature area
           approaches its exact spherical-polygon area as the grid is
           refined; a basin crossing lon 0 (Loire) and a ring around the
           south pole are inside where they should be.

Run: python3 tools/dev/validate_regional_basis.py   (nonzero exit on any
failed claim; prints the numbers the MATLAB tests quote).

Developed by Matthias Weigelt with the help of Claude (Opus 5.5),
2026-10-20.
"""
import json
import os
import sys

import numpy as np
from scipy.special import eval_legendre

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
FAIL = []


def claim(ok, text):
    print(("PASS " if ok else "FAIL ") + text)
    if not ok:
        FAIL.append(text)


# ------------------------------------------------------------- SH basics
def sh_index(L, nmin=2):
    """Order-major, C before S per (n, m): the shLowLevel.shIndex order."""
    n, m, cs = [], [], []
    for mm in range(L + 1):
        for nn in range(max(mm, nmin), L + 1):
            n.append(nn); m.append(mm); cs.append(0)
            if mm > 0:
                n.append(nn); m.append(mm); cs.append(1)
    return np.array(n), np.array(m), np.array(cs)


def alf(L, lat):
    """4pi-normalised Pbar_nm(sin lat), shape (L+1, L+1, npts)."""
    t, u = np.sin(lat), np.cos(lat)
    P = np.zeros((L + 1, L + 1, lat.size))
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


def ylm(lat, lon, idx):
    n, m, cs = idx
    P = alf(n.max(), lat)
    pl = P[n, m, :].T
    trig = np.where(cs == 0, np.cos(np.outer(lon, m)), np.sin(np.outer(lon, m)))
    return pl * trig


def quad_grid(L, os_):
    nlat, nlon = os_ * (L + 1), os_ * (2 * L + 2)
    t, w = np.polynomial.legendre.leggauss(nlat)
    lat = np.arcsin(t)
    lon = np.arange(nlon) * 2 * np.pi / nlon
    LAT = np.repeat(lat, nlon)
    LON = np.tile(lon, nlat)
    W = np.repeat(w / (2 * nlon), nlon)
    return lat, lon, LAT, LON, W


def unit(lat, lon):
    return np.stack([np.cos(lat) * np.cos(lon), np.cos(lat) * np.sin(lon),
                     np.sin(lat)], axis=-1)


# ------------------------------------------------------------ node grids
def icosahedral(f):
    g = (1 + 5 ** 0.5) / 2
    V = np.array([[0, 1, g], [0, -1, g], [0, 1, -g], [0, -1, -g],
                  [1, g, 0], [-1, g, 0], [1, -g, 0], [-1, -g, 0],
                  [g, 0, 1], [-g, 0, 1], [g, 0, -1], [-g, 0, -1]], float)
    V /= np.linalg.norm(V, axis=1, keepdims=True)
    # the 20 faces: triples of mutually adjacent vertices (edge = min dist)
    D = np.linalg.norm(V[:, None] - V[None], axis=2)
    e = D[D > 1e-9].min()
    adj = np.abs(D - e) < 1e-9
    F = [(a, b, c) for a in range(12) for b in range(a + 1, 12)
         for c in range(b + 1, 12) if adj[a, b] and adj[b, c] and adj[a, c]]
    pts = []
    for a, b, c in F:
        for i in range(f + 1):
            for j in range(f + 1 - i):
                k = f - i - j
                p = (i * V[a] + j * V[b] + k * V[c]) / f
                pts.append(p / np.linalg.norm(p))
    pts = np.unique(np.round(np.array(pts), 10), axis=0)
    return len(F), pts


def reuter(gam):
    dth = np.pi / gam
    lat, lon, ring = [np.pi / 2], [0.0], [1]
    for i in range(1, gam):
        th = i * dth
        arg = (np.cos(dth) - np.cos(th) ** 2) / np.sin(th) ** 2
        gi = int(np.floor(2 * np.pi / np.arccos(np.clip(arg, -1, 1))))
        ring.append(gi)
        for j in range(gi):
            lat.append(np.pi / 2 - th); lon.append((j + 0.5) * 2 * np.pi / gi)
    lat.append(-np.pi / 2); lon.append(0.0); ring.append(1)
    return np.array(lat), np.array(lon), ring


ok0 = True
for f in range(1, 8):
    nf, pts = icosahedral(f)
    ok0 &= nf == 20 and len(pts) == 10 * f * f + 2
    ok0 &= np.allclose(np.linalg.norm(pts, axis=1), 1, atol=1e-9)
claim(ok0, "CLAIM 0a icosahedral grid: 20 faces, 10 f^2 + 2 nodes for "
      "f = 1..7, all unit vectors")
la, lo, ring = reuter(40)
claim(ring[1] == ring[-2] and ring[0] == ring[-1] == 1 and
      abs(la.size / (4 * 40 ** 2 / np.pi) - 1) < 0.05,
      "CLAIM 0b Reuter grid gamma=40: one node per pole, symmetric rings "
      "(%d on the first), %d nodes against 4 gamma^2/pi = %.0f"
      % (ring[1], la.size, 4 * 1600 / np.pi))
# the default level rule: smallest j with 10(j+1)^2 + 2 >= (L+1)^2
for L, jexp in ((96, 30), (60, 19)):
    j = int(np.ceil((L + 1) / np.sqrt(10))) - 1
    while 10 * (j + 1) ** 2 + 2 < (L + 1) ** 2:
        j += 1
    print("  default icosahedral level at nmax %d: j = %d (%d nodes, "
          "(nmax+1)^2 = %d)" % (L, j, 10 * (j + 1) ** 2 + 2, (L + 1) ** 2))
    claim(j == jexp, "CLAIM 0c default level at nmax %d is j = %d" % (L, jexp))

# ------------------------------------------------------- CLAIM 1: kernel
L = 30
idx = sh_index(L)
n = idx[0]
rng = np.random.default_rng(20261020)
nodes_lat = np.deg2rad(np.array([52.0, -89.5, 0.0, 89.9]))
nodes_lon = np.deg2rad(np.array([12.0, 200.0, 359.0, 45.0]))
# deterministic evaluation points, the same as testCorrectness uses:
# 50 latitudes pole to pole, golden-angle longitudes
xl = np.deg2rad(np.linspace(-89.9, 89.9, 50))
xo = np.deg2rad(np.mod(137.508 * np.arange(50), 360))
worst = 0.0
for kern in ("kaula", "shannon"):
    phi_full = np.ones(L + 1) if kern == "shannon" else \
        1.0 / np.maximum(np.arange(L + 1), 1) ** 2
    T = (phi_full[n][:, None] * ylm(nodes_lat, nodes_lon, idx).T)
    f_sh = ylm(xl, xo, idx) @ T
    cpsi = unit(xl, xo) @ unit(nodes_lat, nodes_lon).T
    f_ref = sum(phi_full[k] * (2 * k + 1) * eval_legendre(k, cpsi)
                for k in range(2, L + 1))
    worst = max(worst, np.abs(f_sh - f_ref).max() / np.abs(f_ref).max())
claim(worst < 1e-12, "CLAIM 1  RBF via SH = Legendre series, worst rel. "
      "%.2e (poles, lon 359 included)" % worst)

# ---------------------------------------------- region and node selection
def ring_handle(rings):
    """Wrap-safe point-in-polygon for [lat lon] degree rings (the readBasin
    rule): unwrap each ring's longitudes; a ring that winds 360 deg
    encircles a pole and is closed through it; a query longitude is tried
    at lon, lon - 360 and lon + 360."""
    from matplotlib.path import Path
    paths = []
    for r in rings:
        lat, lon = r[:, 0], r[:, 1]
        d = np.diff(lon)
        d = (d + 180) % 360 - 180
        lu = np.concatenate([[lon[0]], lon[0] + np.cumsum(d)])
        if abs(lu[-1] - lu[0]) > 180:          # winds around a pole
            pole = 90.0 if lat.mean() > 0 else -90.0
            lu = np.concatenate([lu, [lu[-1], lu[0]]])
            lat = np.concatenate([lat, [pole, pole]])
        paths.append(Path(np.column_stack([lu, lat])))

    def f(qlat, qlon):
        inside = np.zeros(qlat.size, bool)
        for p in paths:
            for s in (0.0, -360.0, 360.0):
                inside |= p.contains_points(np.column_stack([qlon + s, qlat]))
        return inside
    return f


def buffered_mask(inside, LAT, LON, buf_rad):
    m = inside.copy()
    if buf_rad > 0:
        U = unit(LAT, LON)
        src = U[inside]
        for i0 in range(0, U.shape[0], 4000):
            c = U[i0:i0 + 4000] @ src.T
            m[i0:i0 + 4000] |= (np.arccos(np.clip(c, -1, 1)) <= buf_rad).any(1)
    return m


def nearest_brute(qlat, qlon, LAT, LON):
    return np.argmax(unit(qlat, qlon) @ unit(LAT, LON).T, axis=1)


def nearest_3ring(qlat, qlon, lat, lon):
    nlon = lon.size
    out = np.empty(qlat.size, int)
    for q in range(qlat.size):
        i = np.argmin(np.abs(lat - qlat[q]))
        rings = [r for r in (i - 1, i, i + 1) if 0 <= r < lat.size]
        cand = np.array([r * nlon + jj for r in rings for jj in range(nlon)])
        c = unit(lat[cand // nlon], lon[cand % nlon]) @ unit(qlat[q:q + 1], qlon[q:q + 1])[0]
        out[q] = cand[np.argmax(c)]
    return out


L = 24
lat_g, lon_g, LAT, LON, W = quad_grid(L, 2)
ql = np.deg2rad(np.concatenate([rng.uniform(-90, 90, 400), [89.99, -89.99]]))
qo = np.deg2rad(np.concatenate([rng.uniform(0, 360, 400), [10.0, 300.0]]))
same = np.array_equal(nearest_brute(ql, qo, LAT, LON), nearest_3ring(ql, qo, lat_g, lon_g))
claim(same, "CLAIM 2  3-ring nearest quadrature point = brute force on 402 "
      "points incl. 89.99 deg")

# ------------------------------------------------- CLAIM 3/4: projectors
def projector(T, K, rtol=1e-10):
    M = T.T @ K @ T
    M = (M + M.T) / 2
    mu, V = np.linalg.eigh(M)
    keep = mu > rtol * mu.max()
    Mi = (V[:, keep] / mu[keep]) @ V[:, keep].T
    return Mi @ T.T @ K, int(keep.sum())


L = 30
idx = sh_index(L)
n = idx[0]
lat_g, lon_g, LAT, LON, W = quad_grid(L, 2)
Y = ylm(LAT, LON, idx)
cap = np.rad2deg(LAT) > 50                           # 40 deg polar cap
mask_b = buffered_mask(cap, LAT, LON, 600e3 / 6378136.3)
K = Y.T @ ((W * mask_b)[:, None] * Y)
K = (K + K.T) / 2
# RBF nodes: icosahedral default level, nearest grid point inside mask_b
j = int(np.ceil((L + 1) / np.sqrt(10))) - 1
while 10 * (j + 1) ** 2 + 2 < (L + 1) ** 2:
    j += 1
_, pts = icosahedral(j + 1)
plat, plon = np.arcsin(pts[:, 2]), np.mod(np.arctan2(pts[:, 1], pts[:, 0]), 2 * np.pi)
sel = mask_b[nearest_3ring(plat, plon, lat_g, lon_g)]
phi = 1.0 / np.maximum(np.arange(L + 1), 1) ** 2
T = phi[n][:, None] * ylm(plat[sel], plon[sel], idx).T
Proj, rank = projector(T, K)
x = rng.standard_normal(T.shape[0]) / np.maximum(n, 1) ** 2
ne = np.abs(T.T @ K @ (x - T @ (Proj @ x))).max() / np.abs(T.T @ K @ x).max()
a0 = rng.standard_normal(T.shape[1])
span = np.abs(T @ (Proj @ (T @ a0)) - T @ a0)
fld = Y @ (T @ (Proj @ (T @ a0)) - T @ a0)
reg = np.sqrt(np.sum(W * mask_b * fld ** 2) / np.sum(W * mask_b * (Y @ (T @ a0)) ** 2))
print("  RBF basis on a 40 deg cap + 600 km at nmax 30: %d of %d nodes, "
      "rank %d" % (sel.sum(), len(pts), rank))
claim(ne < 1e-10, "CLAIM 3a normal equations T'K(x - T Proj x) = 0, rel. %.2e" % ne)
claim(reg < 1e-8, "CLAIM 3b a field in span(T) is reproduced over the "
      "region, rel. RMS %.2e" % reg)

mu, G = np.linalg.eigh(K)
G = G[:, ::-1]; mu = mu[::-1]
Ns = int(round(np.sum(W * mask_b) * len(n)))
Gk = G[:, :Ns]
ProjS, _ = projector(Gk, K)
dS = np.abs(ProjS - Gk.T).max()
claim(dS < 1e-10, "CLAIM 4  Slepian: general projector = G' to %.2e "
      "(N = %d tapers, lambda_min %.3f)" % (dS, Ns, mu[Ns - 1]))

# --------------------------------------------- CLAIM 5: GeoJSON regions
def spherical_polygon_area(lat, lon):
    """Exact area (unit sphere) of a ring with great-circle edges, as a fan
    of triangles from the ring's centroid (Eriksson's formula)."""
    P = unit(np.deg2rad(lat), np.deg2rad(lon))
    c = P.mean(0); c /= np.linalg.norm(c)
    A = 0.0
    for i in range(len(P) - 1):
        a, b = P[i], P[i + 1]
        num = np.dot(c, np.cross(a, b))
        den = 1 + np.dot(c, a) + np.dot(a, b) + np.dot(b, c)
        A += 2 * np.arctan2(num, den)
    return abs(A)


bas = json.load(open(os.path.join(ROOT, "data", "gravis", "basins_rivbas.json")))
feat = {f["properties"]["name"]: f for f in bas["features"]}


def rings_of(name):
    c = np.array(feat[name]["geometry"]["coordinates"][0], float)
    return [np.column_stack([c[:, 1], c[:, 0]])]


r = rings_of("Elbe River")[0]
exact = spherical_polygon_area(r[:, 0], r[:, 1]) / (4 * np.pi)
hE = ring_handle([r])
res = {}
for Lq, os_ in ((60, 2), (60, 4), (96, 4)):
    _, _, LAT, LON, W = quad_grid(Lq, os_)
    res[(Lq, os_)] = W[hE(np.rad2deg(LAT), np.rad2deg(LON))].sum()
    print("  Elbe area fraction, quadrature nmax %d OverSample %d: %.10e "
          "(rel. %+.2e against the exact polygon %.6e, %.0f km^2 on R = "
          "6378.1363 km)" % (Lq, os_, res[(Lq, os_)], res[(Lq, os_)] / exact - 1,
                             exact, exact * 4 * np.pi * 6378.1363 ** 2))
e60 = abs(res[(60, 2)] / exact - 1)
claim(abs(res[(96, 4)] / exact - 1) < 0.02 and e60 < 0.1,
      "CLAIM 5a Elbe quadrature area converges to the polygon area")
hL = ring_handle(rings_of("Loire"))
claim(bool(hL(np.array([47.3]), np.array([359.0]))[0]) and
      bool(hL(np.array([47.3]), np.array([1.0]))[0]) and
      not hL(np.array([47.3]), np.array([180.0]))[0],
      "CLAIM 5b Loire (crosses lon 0): inside at 359 and 1 deg, not at 180")
lon_r = np.arange(0, 361, 10.0)
pole_ring = np.column_stack([np.full(lon_r.size, -70.0), lon_r])
hP = ring_handle([pole_ring])
claim(bool(hP(np.array([-89.0]), np.array([123.0]))[0]) and
      bool(hP(np.array([-75.0]), np.array([359.0]))[0]) and
      not hP(np.array([-60.0]), np.array([10.0]))[0],
      "CLAIM 5c ring at -70 deg encircling the south pole: pole side inside")
_, _, LAT, LON, W = quad_grid(60, 2)
cap_frac = W[hP(np.rad2deg(LAT), np.rad2deg(LON))].sum()
cap_exact = (1 - np.sin(np.deg2rad(70))) / 2
print("  south cap from the ring: %.6e against (1 - sin 70)/2 = %.6e" %
      (cap_frac, cap_exact))
# staircase bound: the quadrature moves the cap edge by at most one gap
# between rings; d(area fraction)/d(lat) = cos(lat) / 2 at the edge
gap = np.diff(np.sort(np.arcsin(np.polynomial.legendre.leggauss(122)[0]))).max()
bound = (np.cos(np.deg2rad(70)) * gap / 2) / cap_exact
claim(abs(cap_frac / cap_exact - 1) <= bound,
      "CLAIM 5d polar ring area within the ring-gap bound: rel. %.2e <= %.2e"
      % (abs(cap_frac / cap_exact - 1), bound))
# The ring IS the cap lat < -70, so the handle must select exactly those
# grid points. readBasin (inpolygon) counts points ON a ring as inside;
# matplotlib's contains_points does not, and the ring starts and ends on
# lon 0, so the handle here misses that one meridian column - 1/244 of the
# cap. testCorrectness pins the MATLAB handle to the rule itself; this
# check pins the explanation of the difference (found on A8, v5.14.0).
LATd, LONd = np.rad2deg(LAT), np.rad2deg(LON)
rule = W[LATd < -70].sum()
column = W[(LATd < -70) & (np.abs(LONd) < 1e-9)].sum()
print("  the cap rule lat < -70 on this grid: %.16f" % rule)
claim(abs(rule - column - cap_frac) < 1e-15,
      "CLAIM 5e the handle = the cap rule minus the lon-0 column matplotlib "
      "leaves out (%.3e)" % abs(rule - column - cap_frac))

print("validate_regional_basis: %d failed claim(s)" % len(FAIL))
sys.exit(1 if FAIL else 0)
