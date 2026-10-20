"""regional_oracle_lib: numpy routines shared by the WP8 oracles.

The 4pi-normalised SH basis in shLowLevel.shIndex order, the Gauss-Legendre
quadrature grid of shLowLevel.synthesisMatrix, the node grids and the
region-weighted projector of shLowLevel.regionalBasis - written
independently of the MATLAB code, and imported by
validate_regional_basis.py and validate_regional_process.py so that the
two oracles cannot disagree about the basis they check.

Developed by Matthias Weigelt with the help of Claude (Opus 5.5),
2026-10-20.
"""
import numpy as np


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


def projector(T, K, rtol=1e-10):
    M = T.T @ K @ T
    M = (M + M.T) / 2
    mu, V = np.linalg.eigh(M)
    keep = mu > rtol * mu.max()
    Mi = (V[:, keep] / mu[keep]) @ V[:, keep].T
    return Mi @ T.T @ K, int(keep.sum())


def rbf_basis(L, region_lat, buffer_km):
    """Default-level icosahedral RBF basis (Kaula kernel) over a polar cap."""
    idx = sh_index(L)
    n = idx[0]
    lat_g, lon_g, LAT, LON, W = quad_grid(L, 2)
    mask = buffered_mask(np.rad2deg(LAT) > region_lat, LAT, LON,
                         buffer_km * 1e3 / 6378136.3)
    j = int(np.ceil((L + 1) / np.sqrt(10))) - 1
    while 10 * (j + 1) ** 2 + 2 < (L + 1) ** 2:
        j += 1
    _, pts = icosahedral(j + 1)
    plat = np.arcsin(pts[:, 2])
    plon = np.mod(np.arctan2(pts[:, 1], pts[:, 0]), 2 * np.pi)
    sel = mask[nearest_3ring(plat, plon, lat_g, lon_g)]
    phi = 1.0 / np.maximum(np.arange(L + 1), 1) ** 2
    T = phi[n][:, None] * ylm(plat[sel], plon[sel], idx).T
    Y = ylm(LAT, LON, idx)
    K = Y.T @ ((W * mask)[:, None] * Y)
    Proj, rank = projector(T, (K + K.T) / 2)
    return idx, T, Proj, rank, Y, W, mask
