"""validate_sea_level_basis: oracle for regionalBasis(..., Ocean = ...) (WP9 9h).

A regional basis of land mass with the elastic sea-level fingerprint of
each function inside T. For basis column k (Stokes coefficients x_k):

    sigma_k   = sum_n fSD_n x_k,nm Ybar_nm            surface density
    sigmaL_k  = (1 - O) sigma_k                      its land part
    S_k       = sea-level equation (Farrell & Clark 1976, elastic):
                S = O (N - U + kappa), N - U from the TOTAL load
                sigmaL + rho_w S, kappa from global mass conservation
    T2(:, k)  = Stokes coefficients of sigmaL_k + rho_w S_k

fSD_n = R rho_e / 3 (2n+1) / (1 + k_n), N = R x, U = R h_n / (1 + k_n) x
- the equations of shLowLevel.seaLevelFingerprint, applied to K columns
at once. Every column's total mass is zero by construction.

Claims, bounds written before their run unless stated:
  CLAIM 1  the iterated column solve equals the DENSE solve of the same
           linear sea-level equation (no iteration) to 1e-9 relative
  CLAIM 2  every column conserves mass: |integral of sigmaL + rho_w S|
           below 1e-12 of |integral of sigmaL|
  CLAIM 3  the solve is linear: T2 a equals the solve of the combined
           land load to 1e-9 relative (guards the vectorisation)
  CLAIM 4  closed loop with leakage across the coast (Lmax 30, a
           Greenland-like box whose edge is the coast, a second
           continent, rbf Kaula basis at the default level, buffers 300
           and 600 km, truth a -100 kg/m^2 land loss plus its sea-level
           response). With the land mass the coefficients carry, against
           the FLOOR - the masked basis on a truth without ocean response,
           the error of representation alone: the masked basis without
           the fingerprint is shifted from the floor by >= 4% (the ocean
           response it ignores), the fingerprint basis is within 1% of the
           floor, and the unmasked land-only basis recovers <= 0.85 of the
           truth (the leakage across the coast).
           AMENDED after its first run: the claim was first written as
           "the fingerprint basis within 2% of the TRUTH, the masked basis
           biased >= 3%" for one buffer, with bounds from an exploratory
           run on a coarser node selection. At 300 km it is refuted - the
           basis' own representation error (-6.1%) is larger than the
           bias and cancels it in the masked basis. CLAIM 4R keeps the
           refuted form and fails if it ever holds.
  CLAIM 5  with 5% white noise on the coefficients the fingerprint basis
           at 600 km (the regionalBasis default) stays within 2% of the
           truth (20 seeds, worst case)
  CLAIM 6  the projector of the fingerprint basis reproduces its own
           coefficients: Proj T2 = I to 1e-8 where the rank is full

Run: python3 tools/dev/validate_sea_level_basis.py   (numpy)

Developed by Matthias Weigelt with the help of Claude (Opus 5.5),
2026-11-06.
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import regional_oracle_lib as rl  # noqa: E402

R, RHO_W, RHO_E, OS = 6378136.3, 1000.0, 5517.0, 2
FAIL = []


def check(name, ok, msg):
    print(f"{'PASS' if ok else 'FAIL'} {name}: {msg}")
    if not ok:
        FAIL.append(name)


def love(L):
    n = np.arange(L + 1)
    return -0.30 * n / (n + 3.0), -0.90 * n / (n + 2.0) - 0.1


class Setup:
    def __init__(self, L, region, landfun):
        self.L = L
        self.kn, self.hn = love(L)
        self.idx0, self.idx = rl.sh_index(L, 0), rl.sh_index(L, 2)
        self.lat, self.lon, LAT, LON, self.W = rl.quad_grid(L, OS)
        self.LAT, self.LON = LAT, LON
        latd, lond = np.degrees(LAT), np.degrees(LON)
        self.Y0 = rl.ylm(LAT, LON, self.idx0)
        self.reg = region(latd, lond)
        self.O = (~landfun(latd, lond)).astype(float)
        n0 = self.idx0[0]
        self.fSD = R * RHO_E / 3 * (2 * n0 + 1) / (1 + self.kn[n0])
        self.fNU = R - R * self.hn[n0] / (1 + self.kn[n0])
        self.keep = n0 >= 2
        self.Aoc = self.W @ self.O

    def pad(self, X):
        X0 = np.zeros((self.idx0[0].size, X.shape[1]))
        X0[self.keep] = X
        return X0

    def density(self, X):
        return self.Y0 @ (self.fSD[:, None] * self.pad(X))

    def stokes(self, sig):
        return ((self.Y0.T @ (self.W[:, None] * sig)) / self.fSD[:, None])[self.keep]

    def sle(self, sigL, tol=1e-13, maxit=500):
        W, O, Y0 = self.W, self.O, self.Y0
        Ml = W @ sigL
        S = (-Ml / (RHO_W * self.Aoc)) * O[:, None]
        ref = np.abs(Ml / (RHO_W * self.Aoc)).max()
        for it in range(maxit):
            c = Y0.T @ (W[:, None] * (sigL + RHO_W * S)) / self.fSD[:, None]
            NU = Y0 @ (self.fNU[:, None] * c)
            kap = (-Ml / RHO_W - W @ (O[:, None] * NU)) / self.Aoc
            Sn = O[:, None] * (NU + kap)
            d = np.abs(Sn - S).max()
            S = Sn
            if d < tol * ref:
                break
        return S, it

    def fingerprint(self, T):
        sigL = (1 - self.O)[:, None] * self.density(T)
        S, it = self.sle(sigL)
        return self.stokes(sigL + RHO_W * S), sigL, S, it


# ---------------------------------------------------------------- CLAIM 1-3
box = lambda la, lo: (la > 60) & (lo > 300) & (lo < 340)
landf = lambda la, lo: box(la, lo) | ((la > 10) & (la < 50) & (lo < 100))
s = Setup(16, box, landf)
rng = np.random.default_rng(3)
T = rng.standard_normal((s.idx[0].size, 3)) / (1 + s.idx[0][:, None]) ** 2 * 1e-9
T2, sigL, S, it = s.fingerprint(T)
# the dense route: S = O (A (sigL + rho_w S) + kappa), kappa linear in S
W, O = s.W, s.O
A = s.Y0 @ (s.fNU[:, None] / s.fSD[:, None] * s.Y0.T) * W[None, :]   # grid -> N - U
G = len(W)
proj = np.eye(G) - np.outer(np.ones(G), W * O) / s.Aoc               # removes the mean over ocean
Mop = np.diag(O) @ proj @ A                                          # S part of O (A sig) minus its ocean mean
rhs = np.diag(O) @ (proj @ (A @ sigL)) + np.outer(O, -(W @ sigL) / (RHO_W * s.Aoc))
Sd = np.linalg.solve(np.eye(G) - RHO_W * Mop, rhs)
e1 = np.abs(S - Sd).max() / np.abs(Sd).max()
check("CLAIM 1", e1 < 1e-9, f"iterated ({it} sweeps) vs dense solve: {e1:.1e}")
m = np.abs(W @ (sigL + RHO_W * S)) / np.abs(W @ sigL)
check("CLAIM 2", m.max() < 1e-12, f"column mass residual {m.max():.1e} of the land mass")
a = np.array([0.7, -1.3, 2.1])
T2a, _, _, _ = s.fingerprint((T @ a)[:, None])
e3 = np.abs(T2 @ a - T2a[:, 0]).max() / np.abs(T2a).max()
check("CLAIM 3", e3 < 1e-9, f"linear: combined load vs combined columns {e3:.1e}")

# ---------------------------------------------------------------- CLAIM 4-6
L = 30
s = Setup(L, box, landf)
W = s.W
idx = s.idx
n = idx[0]
core = s.reg.astype(float)
sigTruth = (-100.0 * s.reg)[:, None]
St, _ = s.sle(sigTruth)
x_sle = s.stokes(sigTruth + RHO_W * St)[:, 0]
x_land = s.stokes(sigTruth)[:, 0]
truth = (W @ (core * sigTruth[:, 0]))
Y = rl.ylm(s.LAT, s.LON, idx)


def basis(buffer_km):
    mask = rl.buffered_mask(s.reg, s.LAT, s.LON, buffer_km * 1e3 / R)
    j = int(np.ceil((L + 1) / np.sqrt(10))) - 1
    while 10 * (j + 1) ** 2 + 2 < (L + 1) ** 2:
        j += 1
    _, pts = rl.icosahedral(j + 1)
    plat = np.arcsin(pts[:, 2])
    plon = np.mod(np.arctan2(pts[:, 1], pts[:, 0]), 2 * np.pi)
    sel = mask[rl.nearest_3ring(plat, plon, s.lat, s.lon)]
    phi = 1.0 / np.maximum(np.arange(L + 1), 1) ** 2
    Tl = phi[n][:, None] * rl.ylm(plat[sel], plon[sel], idx).T
    Tf, sigLk, _, _ = s.fingerprint(Tl)
    Tm = s.stokes(sigLk)                   # masked, no fingerprint
    mland = W @ (core[:, None] * sigLk)    # land mass of each column in the core
    return Tl, Tm, Tf, mland, mask, j


def coeff_mass(T_, mland, x):
    a_ = np.linalg.lstsq(T_, x, rcond=1e-10)[0]
    return (mland @ a_) / truth


def field_mass(T_, x):
    a_ = np.linalg.lstsq(T_, x, rcond=1e-10)[0]
    return (W @ (core * s.density((T_ @ a_)[:, None])[:, 0])) / truth


ok4, msg4 = True, []
for buf in (300, 600):
    Tl, Tm, Tf, mland, mask, j = basis(buf)
    rm = coeff_mass(Tm, mland, x_sle)
    rf = coeff_mass(Tf, mland, x_sle)
    r0 = coeff_mass(Tm, mland, x_land)
    ru = field_mass(Tl, x_sle)
    print(f"   buffer {buf} km (level {j}, K {Tl.shape[1]}): masked {rm:.4f}, fingerprint "
          f"{rf:.4f}, floor (masked on a truth without ocean response) {r0:.4f}, "
          f"unmasked land-only {ru:.4f}")
    ok4 &= abs(rm - r0) >= 0.04 and abs(rf - r0) <= 0.01 and ru <= 0.85
    msg4.append(f"{buf} km: ocean bias {100 * (rm - r0):+.2f}% -> {100 * (rf - r0):+.2f}% "
                f"against the floor, unmasked {ru:.3f}")
    if buf == 300:
        refuted = abs(rf - 1) <= 0.02
        check("CLAIM 4R (refuted, recorded)", not refuted,
              f"the first form, 'within 2% of the truth' at 300 km, does not hold: "
              f"{100 * (rf - 1):+.2f}% - the floor {100 * (r0 - 1):+.2f}% is larger than the bias")
    if buf == 600:
        Tf6, mland6, mask6 = Tf, mland, mask
check("CLAIM 4", ok4, "; ".join(msg4))
worst = 0.0
for seed in range(20):
    g = np.random.default_rng(seed)
    y = x_sle + 0.05 * np.std(x_sle) * g.standard_normal(x_sle.size)
    worst = max(worst, abs(coeff_mass(Tf6, mland6, y) - 1))
check("CLAIM 5", worst <= 0.02, f"600 km, 5% noise, 20 seeds: worst {100 * worst:.2f}% from the truth")
Kq = Y.T @ ((W * mask6)[:, None] * Y)
Proj, rank = rl.projector(Tf6, (Kq + Kq.T) / 2)
e6 = np.abs(Proj @ Tf6 - np.eye(Tf6.shape[1])).max()
check("CLAIM 6", rank == Tf6.shape[1] and e6 < 1e-8,
      f"rank {rank} of {Tf6.shape[1]}, Proj T - I {e6:.1e}")
print(f"   for the MATLAB test: truth land mass (sphere mean) {truth:.6e} kg/m^2")

print("FAILED: " + ", ".join(FAIL) if FAIL else "ALL CLAIMS PASS")
sys.exit(1 if FAIL else 0)
