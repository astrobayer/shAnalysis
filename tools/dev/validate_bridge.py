#!/usr/bin/env python3
"""Oracle for bridging a series' gaps with a second series (WP5 row 5d).

THE METHOD, as Matthias set it on 2026-09-10: a 750 km Gaussian, the
overlapping periods for the calibration, every month the reference lacks
filled and flagged, and the Kalman-filtered QuantumFrontiers
HLSST_SLR_COMB2023s series as the bridge; the calibration is an offset, a
per-degree scale and a per-degree noise.

  On the months both series have, per coefficient, R0 and B0 are the
  means of the reference and of the bridge, dR and dB the anomalies. Per
  degree n, over all its orders and months M:

      s_n     = sum(dB dR) / sum(dB^2)              (0 where sum(dB^2) = 0)
      sigma_n = sqrt( sum((dR - s_n dB)^2) / ((2n + 1) M) )

  and a month the reference lacks is filled with R0 + s_n (B - B0), with
  sigma_n for every coefficient of degree n. The Gaussian smoothing is a
  per-degree factor on both series; it commutes with all of the above and
  is left out here.

THE CLAIMS
  CLAIM 0  a small case written out - nmax 2, six reference months, eight
           bridge months - whose numbers testCorrectness pins.
  CLAIM 1  identity: a bridge equal to the reference on the overlap gives
           s_n = 1 and fills with the bridge's own values.
  CLAIM 2  the scaling pays: on a synthetic series with a noisy bridge,
           the fill error on months held out of the reference is smaller
           with s_n than with the offset alone.
  CLAIM 3  the sigma is honest: the predicted sigma_n matches the actual
           error on the held-out months.
"""
import math
import sys

import numpy as np


def calibrate(RC, RS, BC, BS):
    """(M, n1, n1) stacks of the matched months -> offsets, s_n, sigma_n."""
    R0C, R0S = RC.mean(0), RS.mean(0)
    B0C, B0S = BC.mean(0), BS.mean(0)
    dRC, dRS = RC - R0C, RS - R0S
    dBC, dBS = BC - B0C, BS - B0S
    num = (dBC * dRC + dBS * dRS).sum(axis=(0, 2))
    den = (dBC ** 2 + dBS ** 2).sum(axis=(0, 2))
    s = np.where(den > 0, num / np.where(den > 0, den, 1.0), 0.0)
    resC = dRC - s[None, :, None] * dBC
    resS = dRS - s[None, :, None] * dBS
    n = np.arange(RC.shape[1])
    sigma = np.sqrt((resC ** 2 + resS ** 2).sum(axis=(0, 2))
                    / ((2 * n + 1) * RC.shape[0]))
    return dict(R0C=R0C, R0S=R0S, B0C=B0C, B0S=B0S, s=s, sigma=sigma)


def fill(cal, BC, BS, scale=True):
    s = cal["s"] if scale else np.ones_like(cal["s"])
    s = s[None, :, None]
    return cal["R0C"] + s * (BC - cal["B0C"]), cal["R0S"] + s * (BS - cal["B0S"])


def masks(nmax):
    n = np.arange(nmax + 1)[:, None]
    m = np.arange(nmax + 1)[None, :]
    return (m <= n).astype(float), ((m <= n) & (m >= 1)).astype(float)


def small_case():
    """nmax 2; truth T(t); the reference is T at months 1 2 3 5 6 8, the
    bridge 0.8 T + an offset + a deterministic wobble at months 1..8.
    Written the same way in testCorrectness."""
    mc, ms = masks(2)
    n = np.arange(3)[:, None]
    m = np.arange(3)[None, :]
    def truth(t):
        return ((n + 1 + m) * np.sin(t + n - m) * 1e-10 * mc,
                (n + 2 - m) * np.cos(t - n + m) * 1e-10 * ms)
    def bridge(t):
        c, s = truth(t)
        return (0.8 * c + (1e-11 * (n + m + 1) + 2e-11 * np.cos(3 * t + n * m)) * mc,
                0.8 * s + (-1e-11 * (n - m + 1) + 2e-11 * np.sin(2 * t + n + m)) * ms)
    ref_months = [1, 2, 3, 5, 6, 8]
    RC = np.array([truth(t)[0] for t in ref_months])
    RS = np.array([truth(t)[1] for t in ref_months])
    BC = np.array([bridge(t)[0] for t in ref_months])
    BS = np.array([bridge(t)[1] for t in ref_months])
    cal = calibrate(RC, RS, BC, BS)
    b4 = bridge(4)
    f4 = fill(cal, b4[0][None], b4[1][None])
    return cal, f4


def check_small():
    """CLAIM 0: the numbers testCorrectness pins."""
    cal, f4 = small_case()
    print("  SMALL     s     = %s" % "  ".join("%.17g" % v for v in cal["s"]))
    print("            sigma = %s" % "  ".join("%.17g" % v for v in cal["sigma"]))
    print("            filled month 4: C(3,2) = %.17g, S(3,3) = %.17g"
          % (f4[0][0, 2, 1], f4[1][0, 2, 2]))
    return np.all(np.isfinite(cal["s"])) and np.all(cal["sigma"] > 0)


def check_identity():
    """CLAIM 1: a bridge equal to the reference."""
    rng = np.random.default_rng(3)
    mc, ms = masks(6)
    RC = rng.standard_normal((30, 7, 7)) * mc
    RS = rng.standard_normal((30, 7, 7)) * ms
    cal = calibrate(RC, RS, RC.copy(), RS.copy())
    newC = rng.standard_normal((1, 7, 7)) * mc
    newS = rng.standard_normal((1, 7, 7)) * ms
    fC, fS = fill(cal, newC, newS)
    e = max(abs(cal["s"] - 1).max(), abs(fC - newC).max(), abs(fS - newS).max())
    print("  IDENTITY  |s - 1| and |fill - bridge|: worst %.2e (bound 1e-12)" % e)
    return e < 1e-12


def synthetic(seed=11, nmax=20, T=180, held=30):
    """A truth with a falling spectrum, a reference with small noise, a
    bridge with an offset and noise that grows with degree."""
    rng = np.random.default_rng(seed)
    mc, ms = masks(nmax)
    n = np.arange(nmax + 1)
    amp = 1e-10 * (n + 1.0) ** -1.5
    sG = 0.1 * amp
    sB = amp * (0.2 + (n / 8.0) ** 2)
    shape = (T, nmax + 1, nmax + 1)
    trC = rng.standard_normal(shape) * amp[None, :, None] * mc
    trS = rng.standard_normal(shape) * amp[None, :, None] * ms
    gC = trC + rng.standard_normal(shape) * sG[None, :, None] * mc
    gS = trS + rng.standard_normal(shape) * sG[None, :, None] * ms
    offC = rng.standard_normal((nmax + 1, nmax + 1)) * 5e-11 * mc
    offS = rng.standard_normal((nmax + 1, nmax + 1)) * 5e-11 * ms
    bC = trC + offC + rng.standard_normal(shape) * sB[None, :, None] * mc
    bS = trS + offS + rng.standard_normal(shape) * sB[None, :, None] * ms
    out = rng.permutation(T)[:held]
    keep = np.setdiff1d(np.arange(T), out)
    return gC, gS, bC, bS, keep, out


def degree_rms(C, S):
    """(K, n1, n1) -> per-degree RMS over months and the 2n+1 coefficients"""
    n = np.arange(C.shape[1])
    return np.sqrt((C ** 2 + S ** 2).sum(axis=(0, 2)) / ((2 * n + 1) * C.shape[0]))


def check_scaling_and_sigma():
    """CLAIMs 2 and 3 on held-out months."""
    gC, gS, bC, bS, keep, out = synthetic()
    cal = calibrate(gC[keep], gS[keep], bC[keep], bS[keep])
    fC, fS = fill(cal, bC[out], bS[out])
    oC, oS = fill(cal, bC[out], bS[out], scale=False)
    e_s = degree_rms(fC - gC[out], fS - gS[out])
    e_o = degree_rms(oC - gC[out], oS - gS[out])
    k = np.arange(2, e_s.size)
    acc_s = math.sqrt((e_s[k] ** 2).sum())
    acc_o = math.sqrt((e_o[k] ** 2).sum())
    ratio = e_s[k] / cal["sigma"][k]
    acc_ratio = acc_s / math.sqrt((cal["sigma"][k] ** 2).sum())
    print("  SCALING   held-out error, degrees 2-20: with s_n %.3e, offset only "
          "%.3e (ratio %.3f)" % (acc_s, acc_o, acc_s / acc_o))
    print("  SIGMA     actual / predicted: accumulated %.3f, per degree %.2f .. "
          "%.2f" % (acc_ratio, ratio.min(), ratio.max()))
    return acc_s < acc_o and 0.85 < acc_ratio < 1.15 and \
        ratio.min() > 0.6 and ratio.max() < 1.6


def main():
    print("validate_bridge: gap filling by offset, per-degree scale and noise")
    ok = [check_small(), check_identity(), check_scaling_and_sigma()]
    if all(ok):
        print("validate_bridge: OK - all claims hold")
        return 0
    print("validate_bridge: FAILED")
    return 1


if __name__ == "__main__":
    sys.exit(main())
