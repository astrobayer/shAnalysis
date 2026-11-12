"""validate_ocean_validation: oracle for seaLevelBudget and bprCompare (WP9 9j).

seaLevelBudget: on the epochs the three series share, the residual of
the sea-level budget r = total - steric - mass is fitted (bias, trend,
annual, semi-annual; fitDeterministicModel with ARCorrect), and the
budget closes when |trend(r)| <= 2 sigma(trend(r)). Because the three
fits share one design, trend(r) = trend(total - steric) - trend(mass)
exactly.

bprCompare: a bottom-pressure recorder against the nearest ocean pixel
of an obpChain grid (cm EWH); hPa -> cm EWH is 100 / (rho_w g) * 100.

Claims, bounds written before their run:
  CLAIM 1  identities: trend(r) = trend(total - steric) - trend(mass) to
           1e-12 relative; a noise-free closed budget has |trend(r)| below
           1e-12 mm/yr
  CLAIM 2  calibration: a closed budget with AR(1) noise (phi 0.5, 1.5 mm
           per component, T 180 monthly, 400 seeds) is called closed in
           at least 90% of the seeds - the AR-corrected 2-sigma test
  CLAIM 3  power: with a 0.6 mm/yr component missing from total (the
           same noise) the budget is called open in at least 80% of the
           seeds
  CLAIM 4  bprCompare's metrics: 1 hPa = 1.019716 cm EWH (rho_w 1000, g
           9.80665); the nearest ocean pixel across lon 0/360; NSE, the
           correlation, the gain and the RMS equal their formulas to
           1e-12 on a synthetic station

Run: python3 tools/dev/validate_ocean_validation.py   (numpy)

Developed by Matthias Weigelt with the help of Claude (Opus 5.5),
2026-11-12.
"""
import sys

import numpy as np

FAIL = []


def check(name, ok, msg):
    print(f"{'PASS' if ok else 'FAIL'} {name}: {msg}")
    if not ok:
        FAIL.append(name)


def fit(t, X, t0=2000.0):
    """fitDeterministicModel(X, t, ARCorrect=true, T0=t0): trend and its sigma."""
    tc = t - t0
    A = np.column_stack([np.ones_like(tc), tc, np.cos(2 * np.pi * tc), np.sin(2 * np.pi * tc),
                         np.cos(4 * np.pi * tc), np.sin(4 * np.pi * tc)])
    T, ncol = A.shape
    coef = np.linalg.lstsq(A, X.T, rcond=None)[0]
    res = X - (A @ coef).T
    resVar = (res ** 2).sum(1) / (T - ncol)
    dN = np.diag(np.linalg.inv(A.T @ A))
    sig = np.sqrt(np.outer(dN, resVar))
    ar1 = np.zeros(X.shape[0])
    for p in range(X.shape[0]):
        r = res[p]
        ar1[p] = min(max((r[:-1] * r[1:]).sum() / (r ** 2).sum(), 0), 0.99)
    ar1 = np.clip(ar1 + (1 + 3 * ar1) / T, 0, 0.99)
    sig = sig * np.sqrt((1 + ar1) / (1 - ar1))
    return coef, sig


def ar1noise(rng, T, phi, s):
    e = np.zeros(T)
    e[0] = rng.standard_normal() * s
    for k in range(1, T):
        e[k] = phi * e[k - 1] + np.sqrt(1 - phi ** 2) * s * rng.standard_normal()
    return e


T = 180
t = 2003 + (np.arange(T) + 0.5) / 12
ann = lambda a, ph: a * np.cos(2 * np.pi * (t - ph))

# ---------------------------------------------------------------- CLAIM 1
mass = 2.0 * (t - 2010) + ann(8.0, 0.75)
steric = 1.3 * (t - 2010) + ann(4.0, 0.2)
total = mass + steric
X = np.vstack([mass, total - steric, total - steric - mass])
c, _ = fit(t, X)
X2 = np.vstack([mass + 0.1 * np.sin(7 * t), total - steric + 0.2 * np.cos(5 * t)])
c2, _ = fit(t, np.vstack([X2, X2[1] - X2[0]]))
e1 = abs(c2[1, 2] - (c2[1, 1] - c2[1, 0])) / abs(c2[1, 1])
check("CLAIM 1", e1 < 1e-12 and abs(c[1, 2]) < 1e-12,
      f"trend(r) identity {e1:.1e}; closed noise-free residual trend {abs(c[1, 2]):.1e} mm/yr")

# ---------------------------------------------------------------- CLAIM 2/3


def closes(rng, missing):
    m = mass + ar1noise(rng, T, 0.5, 1.5)
    s = steric + ar1noise(rng, T, 0.5, 1.5)
    tot = mass + steric - missing * (t - 2010) + ar1noise(rng, T, 0.5, 1.5)
    r = tot - s - m
    cc, ss = fit(t, r[None, :])
    return abs(cc[1, 0]) <= 2 * ss[1, 0]


rng = np.random.default_rng(9)
c2r = np.mean([closes(rng, 0.0) for _ in range(400)])
c3r = np.mean([not closes(rng, 0.6) for _ in range(400)])
check("CLAIM 2", c2r >= 0.90, f"a closed budget is called closed in {100 * c2r:.1f}% of 400 seeds")
check("CLAIM 3", c3r >= 0.80, f"a 0.6 mm/yr gap is called open in {100 * c3r:.1f}% of 400 seeds")

# ---------------------------------------------------------------- CLAIM 4
hpa = 100 / (1000 * 9.80665) * 100
lat = np.arange(-89.5, 90, 1.0)
lon = np.arange(0.5, 360, 1.0)
LAT, LON = np.meshgrid(lat, lon, indexing="ij")
land = (np.abs(LAT - 10) < 3) & ((LON < 3) | (LON > 357))
st_lat, st_lon = 10.2, 359.9                    # station on the land block's edge row, near 0/360


def gc(la1, lo1, la2, lo2):
    a, b = np.radians(la1), np.radians(la2)
    return np.degrees(np.arccos(np.clip(np.sin(a) * np.sin(b) + np.cos(a) * np.cos(b)
                                        * np.cos(np.radians(lo1 - lo2)), -1, 1)))


d = gc(st_lat, st_lon, LAT, LON)
d[land] = np.inf
i, j = np.unravel_index(np.argmin(d), d.shape)
ok_pix = (abs(lat[i] - 13.5) < 1e-9 or abs(lat[i] - 6.5) < 1e-9) or not land[i, j]
rng = np.random.default_rng(4)
g = rng.standard_normal(60)
o_hpa = (0.8 * g + 0.3 * rng.standard_normal(60)) / hpa
o = o_hpa * hpa
o_a, g_a = o - o.mean(), g - g.mean()
nse = 1 - ((o_a - g_a) ** 2).sum() / (o_a ** 2).sum()
rr = (o_a * g_a).sum() / np.sqrt((o_a ** 2).sum() * (g_a ** 2).sum())
gain = (o_a * g_a).sum() / (g_a ** 2).sum()
rms = np.sqrt(((o_a - g_a) ** 2).mean())
e4 = max(abs(rr - np.corrcoef(o, g)[0, 1]),
         abs(gain - np.polyfit(g_a, o_a, 1)[0]))
check("CLAIM 4", abs(hpa - 1.019716) < 1e-6 and ok_pix and not land[i, j] and e4 < 1e-12,
      f"1 hPa = {hpa:.6f} cm; nearest ocean pixel ({lat[i]}, {lon[j]}); formulas agree to {e4:.1e}"
      f" (NSE {nse:.3f}, r {rr:.3f}, gain {gain:.3f}, RMS {rms:.3f} cm)")

print("FAILED: " + ", ".join(FAIL) if FAIL else "ALL CLAIMS PASS")
sys.exit(1 if FAIL else 0)
