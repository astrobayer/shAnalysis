#!/usr/bin/env python3
"""Oracle for the data-driven leakage correction (WP5 row 5b).

The model-independent alternative to leakageCorrect's forward model:
Vishwakarma's "method of deviation", which repairs a filtered catchment
average using two correction terms built from the FILTERED fields alone -
no hydrological model anywhere.

WHERE THE EQUATIONS COME FROM
  B. D. Vishwakarma (2017), "Understanding and repairing the signal damage
  due to filtering of mass change estimates from the GRACE satellite
  mission", PhD thesis, Institute of Geodesy, University of Stuttgart -
  chapter 3, equations (3.19)-(3.29). Published as
    Vishwakarma, Horwath, Devaraju, Groh & Sneeuw (2017),
    Water Resour. Res. 53, 9824-9844, doi:10.1002/2017WR021150
  and, for the method of scale,
    Vishwakarma, Devaraju & Sneeuw (2016),
    Water Resour. Res. 52, doi:10.1002/2016WR018960.
  The phase step follows Phillips, Nerem, Fox-Kemper, Famiglietti &
  Rajagopalan (2012), Geophys. Res. Lett. 39, L16705,
  doi:10.1029/2012GL052495.

  The authors also publish a MATLAB "DataDrivenCorrection Bundle" under
  GPL-3. shAnalysis is MIT, so NOTHING here is derived from that code:
  this file is written from the thesis equations above, which is also
  what CLAUDE.md section 2 requires ("reuse is by re-implementation").

THE DECOMPOSITION, AND WHY IT IS EXACT
  Write the true field g as its catchment-confined part g*R and the rest
  g*(1-R), R being the catchment function. For a filter that preserves a
  constant (W_0 = 1 - true of the Gaussian), the filtered catchment
  average splits with NO approximation:

      gbar_c = f_c + dF_c + l_c                                     (I)

      f_c    = (1/A) int g R                   the truth we want
      l_c    = (1/A) int filter(g (1-R)) R     leakage IN from outside
      dF_c   = (1/A) int filter(g R - f_c) R   the deviation integral:
                                               what filtering does to the
                                               catchment's own signal
                                               because it is not a
                                               uniform layer

  So f_c = gbar_c - dF_c - l_c exactly. That is checked here to machine
  precision, and it is the whole reason the method exists: the correction
  is not a fit, it is a rearrangement. What is hard is that l_c and dF_c
  need g, which nobody has.

  Equivalently, by self-adjointness of an isotropic filter,
      int filter(X) R  ==  int X Rbar,     Rbar = filter(R)
  which is the form thesis eq. (3.19) is written in. Both are checked.

THE DATA-DRIVEN ESTIMATE
  Only gbar (once filtered) and gbarbar (twice filtered) are available.
  Form the same two integrals one filtering step further out:

      lbar_c    = (1/A) int filter(gbar    (1-R)) R
      lbarbar_c = (1/A) int filter(gbarbar (1-R)) R
      dFbar_c   = (1/A) int (gbar    R - gbar_c)    Rbar
      dFbarbar_c= (1/A) int (gbarbar R - gbarbar_c) Rbar

  then extrapolate ONE step back towards the truth:

    leakage    phase difference dphi between lbar_c and lbarbar_c by the
               Hilbert regression of Phillips et al.; shift lbarbar_c by
               dphi towards lbar_c, take the ratio between the shifted
               series and lbar_c, then shift lbar_c by dphi and scale it
               by that ratio -> lhat_c.
    deviation  amplitude only. The thesis measured the phase differences
               of the deviation integral and found NO consistent
               relation, and therefore applies no phase shift here. That
               asymmetry is deliberate, not an omission.

      fhat_c = gbar_c - dFhat_c - lhat_c                          (3.29)

  A closed-loop run is the only honest test of that extrapolation, so
  CLAIM 3 measures how much of the filtering damage it actually removes.

Run: python3 tools/dev/validate_leakage_datadriven.py
Nonzero exit if any claim fails.

Developed by Matthias Weigelt with the help of Claude (Opus 5), 2026-09-09.
"""
import sys

import numpy as np

# The identity (I) is algebra, so it closes at round-off. 1e-12 is far
# above the observed residual (~1e-16 relative) and far below anything a
# sign or weighting error could produce.
IDENTITY_TOL = 1e-12

# Self-adjointness int filter(X) R == int X filter(R) is likewise exact
# for a real isotropic kernel; same reasoning.
ADJOINT_TOL = 1e-12

# The phase round trip is exact up to the Hilbert transform's edge
# behaviour on a finite record (a trend and a non-integer number of
# cycles both leak). Measured worst case over the five angles of CLAIM 0
# is ~1e-13 deg on this fixture; 1e-6 deg is far tighter than any error
# that would matter and far looser than round-off.
PHASE_TOL = 1e-6


# --------------------------------------------------------------- SH core
# Conventions match tools/dev/validate_leakage.py: fully normalised ALFs,
# C[n, m] / S[n, m], colatitude in radians, Gauss-Legendre grid.
def legendre_alf(nmax, theta):
    """Fully normalised associated Legendre functions P[n, m, i]."""
    t = np.atleast_1d(theta).astype(float)
    c, s = np.cos(t), np.sin(t)
    P = np.zeros((nmax + 1, nmax + 1, t.size))
    P[0, 0] = 1.0
    if nmax >= 1:
        P[1, 0] = np.sqrt(3.0) * c
        P[1, 1] = np.sqrt(3.0) * s
    for n in range(2, nmax + 1):
        P[n, n] = np.sqrt((2.0 * n + 1.0) / (2.0 * n)) * s * P[n - 1, n - 1]
        for m in range(0, n):
            a = np.sqrt((2.0 * n - 1.0) * (2.0 * n + 1.0)
                        / ((n - m) * (n + m)))
            b = np.sqrt((2.0 * n + 1.0) * (n + m - 1.0) * (n - m - 1.0)
                        / ((n - m) * (n + m) * (2.0 * n - 3.0)))
            P[n, m] = a * c * P[n - 1, m] - (b * P[n - 2, m] if n - 2 >= m
                                             else 0.0)
    return P


def gauss_grid(nmax):
    """Gauss-Legendre colatitudes/weights and equiangular longitudes."""
    nlat = nmax + 1
    x, w = np.polynomial.legendre.leggauss(nlat)
    theta = np.arccos(x)
    nlon = 2 * nmax + 2
    lam = np.arange(nlon) * (2.0 * np.pi / nlon)
    return theta, w, lam


def synthesis(C, S, theta, lam):
    """Grid (nlat, nlon) from fully normalised coefficients."""
    nmax = C.shape[0] - 1
    P = legendre_alf(nmax, theta)
    m = np.arange(nmax + 1)
    cosm = np.cos(np.outer(m, lam))
    sinm = np.sin(np.outer(m, lam))
    A = np.einsum("nmi,nm->mi", P, C)
    B = np.einsum("nmi,nm->mi", P, S)
    return A.T @ cosm + B.T @ sinm


def analysis(grid, theta, w, lam, nmax):
    """Coefficients from a Gauss grid - exact inverse of synthesis.

    Same pair as tools/dev/validate_leakage.py, deliberately: the Gauss
    weights already carry sin(theta) dtheta, so every order takes the
    SAME factor and m = 0 is not a special case. Getting that wrong is
    how the first draft of this file made smooth(constant) return zero,
    which silently broke the identity the whole oracle rests on.
    """
    nlon = lam.size
    m = np.arange(nmax + 1)
    cosm = np.cos(np.outer(m, lam))
    sinm = np.sin(np.outer(m, lam))
    a = grid @ cosm.T * (2.0 / nlon)
    b = grid @ sinm.T * (2.0 / nlon)
    P = legendre_alf(nmax, theta)
    C = np.einsum("nmi,i,im->nm", P, w, a) * 0.25
    S = np.einsum("nmi,i,im->nm", P, w, b) * 0.25
    tri = np.tril(np.ones((nmax + 1, nmax + 1), dtype=bool))
    return C * tri, S * tri


def gaussian_weights(nmax, radius_km, R_km=6378.1363):
    """Jekeli recursion. W[0] == 1, which is what makes identity (I) hold."""
    b = np.log(2.0) / (1.0 - np.cos(radius_km / R_km))
    W = np.zeros(nmax + 1)
    W[0] = 1.0
    if nmax >= 1:
        W[1] = (1.0 + np.exp(-2.0 * b)) / (1.0 - np.exp(-2.0 * b)) - 1.0 / b
    for n in range(1, nmax):
        W[n + 1] = -(2.0 * n + 1.0) / b * W[n] + W[n - 1]
        if W[n + 1] < 0:
            W[n + 1:] = 0.0     # Jekeli's recursion goes unstable; clamp
            break
    return W


# ------------------------------------------------------------- machinery
class Sphere:
    """One grid, one filter, and the integrals the method needs."""

    def __init__(self, nmax=30, radius_km=500.0):
        self.nmax = nmax
        self.theta, self.w, self.lam = gauss_grid(nmax)
        self.W = gaussian_weights(nmax, radius_km)
        # dOmega = sin(theta) dtheta dlam, and the Gauss weights already
        # carry sin(theta) dtheta, so the quadrature weight per cell is
        # w_i * dlam. Areas cancel in every ratio below, so the sphere
        # radius never appears.
        self.cell = np.outer(self.w, np.full(self.lam.size,
                                             2.0 * np.pi / self.lam.size))

    def integral(self, field):
        return float(np.sum(field * self.cell))

    def smooth(self, field):
        C, S = analysis(field, self.theta, self.w, self.lam, self.nmax)
        return synthesis(self.W[:, None] * C, self.W[:, None] * S,
                         self.theta, self.lam)

    def cap(self, lat0, lon0, radius_deg):
        """Hard 0/1 spherical cap - the catchment function R."""
        la = 90.0 - np.degrees(self.theta)
        lo = np.degrees(self.lam)
        LA, LO = np.meshgrid(la, lo, indexing="ij")
        cosd = (np.sin(np.radians(LA)) * np.sin(np.radians(lat0))
                + np.cos(np.radians(LA)) * np.cos(np.radians(lat0))
                * np.cos(np.radians(LO - lon0)))
        return (cosd >= np.cos(np.radians(radius_deg))).astype(float)


def catchment_average(sph, field, R, area):
    return sph.integral(field * R) / area


def leakage_integral(sph, field, R, area):
    """(1/A) int filter(field * (1-R)) R - signal leaking IN."""
    return sph.integral(sph.smooth(field * (1.0 - R)) * R) / area


def deviation_integral(sph, field, R, area):
    """(1/A) int filter(field*R - mean) R, thesis eq. (3.19) adjoint form."""
    mean = catchment_average(sph, field, R, area)
    return sph.integral(sph.smooth(field * R - mean) * R) / area


def deviation_integral_rbar(sph, field, R, Rbar, area):
    """The same quantity written as in eq. (3.19): weight by Rbar."""
    mean = catchment_average(sph, field, R, area)
    return sph.integral((field * R - mean) * Rbar) / area


# ------------------------------------------------------- the phase step
def hilbert(x):
    """Analytic signal (scipy-free): zero the negative frequencies."""
    n = x.size
    X = np.fft.fft(x)
    h = np.zeros(n)
    h[0] = 1.0
    if n % 2 == 0:
        h[n // 2] = 1.0
        h[1:n // 2] = 2.0
    else:
        h[1:(n + 1) // 2] = 2.0
    return np.fft.ifft(X * h)


def phase_difference(a, b):
    """Phase of series a relative to b, in DEGREES (Phillips et al. 2012).

    Returns the angle d for which a ~= shift_series(b, d): measuring and
    shifting are defined as mutual inverses, and CLAIM 0 asserts it.

    Express a in terms of b and its quadrature,
        a = p + q*b + r*Im{H(b)},
    solve for (p, q, r) by least squares, then d = atan2(-r, q).
    """
    hb = hilbert(b)
    A = np.column_stack([np.ones(b.size), np.real(hb), np.imag(hb)])
    coef, *_ = np.linalg.lstsq(A, a, rcond=None)
    # Re{H(b)} is b itself, so the fit is a = p + q b + r H(b), while
    # shift_series(b, d) = cos(d) b - sin(d) H(b). Matching them gives
    # q = cos d and r = -sin d, hence the MINUS. Without it the estimator
    # shifts the wrong way and still looks plausible - which is what
    # CLAIM 0 caught, at 80 deg on a -40 deg input.
    return float(np.degrees(np.arctan2(-coef[2], coef[1])))


def shift_series(x, degrees):
    """Shift a series in phase by `degrees`, in the frequency domain.

    This is the INVERSE of phase_difference, and deliberately the same
    model: a real series shifted by theta is
        cos(theta) * x  -  sin(theta) * H(x),
    which is Re{exp(i theta) * analytic(x)}. Phillips et al. measure the
    phase by regressing onto exactly that pair, so measuring and shifting
    have to agree or the estimator is chasing its own convention. That is
    asserted in CLAIM 0 rather than assumed.

    Note this is a phase rotation, not a time shift: every frequency
    component turns by the same angle, which is what the thesis
    prescribes ("multiply each frequency component by the complex
    exponential of the phase difference").
    """
    th = np.radians(degrees)
    return np.cos(th) * x - np.sin(th) * np.imag(hilbert(x))


def amplitude_ratio(target, source):
    """Least-squares slope of target on source, intercept absorbed."""
    A = np.column_stack([np.ones(source.size), source])
    coef, *_ = np.linalg.lstsq(A, target, rcond=None)
    return float(coef[1])


# --------------------------------------------------------- the estimator
def data_driven(sph, gbar_series, R, Rbar, area):
    """Method of deviation from the FILTERED series alone.

    gbar_series is (T, nlat, nlon), already once filtered - which is what
    a user has. Returns fhat, and the pieces, so a test can pin them.
    """
    T = len(gbar_series)
    gbarbar = [sph.smooth(g) for g in gbar_series]

    gbar_c = np.array([catchment_average(sph, g, R, area)
                       for g in gbar_series])
    gbarbar_c = np.array([catchment_average(sph, g, R, area)
                          for g in gbarbar])

    lbar = np.array([leakage_integral(sph, g, R, area) for g in gbar_series])
    lbarbar = np.array([leakage_integral(sph, g, R, area) for g in gbarbar])

    dFbar = np.array([deviation_integral_rbar(sph, g, R, Rbar, area)
                      for g in gbar_series])
    dFbarbar = np.array([deviation_integral_rbar(sph, g, R, Rbar, area)
                         for g in gbarbar])

    # leakage: phase, then amplitude
    dphi = phase_difference(lbar, lbarbar)
    lbarbar_shifted = shift_series(lbarbar, dphi)
    ratio = amplitude_ratio(lbar, lbarbar_shifted)
    lhat = shift_series(lbar, dphi) * ratio

    # deviation: amplitude only - no consistent phase relation exists
    dFhat = dFbar * amplitude_ratio(dFbar, dFbarbar)

    fhat = gbar_c - dFhat - lhat
    return dict(fhat=fhat, gbar_c=gbar_c, gbarbar_c=gbarbar_c,
                lbar=lbar, lbarbar=lbarbar, lhat=lhat,
                dFbar=dFbar, dFbarbar=dFbarbar, dFhat=dFhat,
                dphi=dphi, ratio=ratio, T=T)


# ------------------------------------------------------------- the world
def synthetic_series(sph, R, T=48, seed=7):
    """A catchment signal plus OUT-OF-PHASE outside signal.

    The phase step only matters when what leaks in is not in phase with
    what is inside - that is the case the thesis is about, so it is the
    case the oracle builds.
    """
    rng = np.random.default_rng(seed)
    t = np.arange(T) / 12.0
    inside = 0.20 * np.sin(2 * np.pi * t) + 0.05 * t          # m, + trend
    outside = 0.30 * np.sin(2 * np.pi * t + 2.1)              # ~120 deg out

    neigh = sph.cap(5.0, 55.0, 12.0) * (1.0 - R)   # a neighbour catchment
    far = sph.cap(-40.0, 200.0, 20.0)              # and something far off

    fields = []
    for k in range(T):
        f = (inside[k] * R
             + outside[k] * neigh
             + 0.10 * np.sin(2 * np.pi * t[k] + 0.7) * far)
        f = f + 0.002 * rng.standard_normal(f.shape)   # small roughness
        fields.append(f)
    return fields, inside


def rms(x):
    return float(np.sqrt(np.mean(np.asarray(x) ** 2)))


# ------------------------------------------------------------- the claims
def check_phase_roundtrip():
    """CLAIM 0: measuring a phase and applying it are mutual inverses.

    Without this the estimator could be internally consistent and still
    shift the wrong way - a sign error here would quietly make the
    correction worse while every other claim still passed.
    """
    t = np.arange(120) / 12.0
    base = (0.2 * np.sin(2 * np.pi * t) + 0.05 * np.sin(4 * np.pi * t)
            + 0.01 * t)
    worst = 0.0
    for truth in (-40.0, -12.5, 0.0, 7.5, 33.0):
        shifted = shift_series(base, truth)
        got = phase_difference(shifted, base)
        worst = max(worst, abs(got - truth))
    print("  PHASE     measure(shift(x, d)) - d: worst %.3e deg (bound "
          "%.0e)" % (worst, PHASE_TOL))
    return worst < PHASE_TOL


def check_identity(sph, R, area):
    """CLAIM 1: gbar_c = f_c + dF_c + l_c, exactly."""
    fields, _ = synthetic_series(sph, R, T=3)
    worst = 0.0
    for g in fields:
        gbar = sph.smooth(g)
        f_c = catchment_average(sph, g, R, area)
        gbar_c = catchment_average(sph, gbar, R, area)
        l_c = leakage_integral(sph, g, R, area)
        dF_c = deviation_integral(sph, g, R, area)
        res = abs(gbar_c - (f_c + dF_c + l_c)) / max(abs(gbar_c), 1e-30)
        worst = max(worst, res)
    print("  IDENTITY  gbar_c - (f_c + dF_c + l_c): worst relative %.2e "
          "(bound %.0e)" % (worst, IDENTITY_TOL))
    return worst < IDENTITY_TOL


def check_adjoint(sph, R, Rbar, area):
    """CLAIM 2: int filter(X) R == int X Rbar, so eq. (3.19) is the same."""
    fields, _ = synthetic_series(sph, R, T=3)
    worst = 0.0
    for g in fields:
        gbar = sph.smooth(g)
        a = deviation_integral(sph, gbar, R, area)
        b = deviation_integral_rbar(sph, gbar, R, Rbar, area)
        worst = max(worst, abs(a - b) / max(abs(a), 1e-30))
    print("  ADJOINT   two forms of the deviation integral: worst relative "
          "%.2e (bound %.0e)" % (worst, ADJOINT_TOL))
    return worst < ADJOINT_TOL


def check_recovery(sph, R, area):
    """CLAIM 3: the data-driven estimate beats doing nothing."""
    fields, truth = synthetic_series(sph, R, T=48)
    gbar_series = [sph.smooth(g) for g in fields]
    out = data_driven(sph, gbar_series, R, sph.smooth(R), area)

    err_filtered = rms(out["gbar_c"] - truth)
    err_corrected = rms(out["fhat"] - truth)
    # what the correction could be if the truth were known (identity):
    exact = np.array([catchment_average(sph, g, R, area) for g in fields])
    err_exact = rms(exact - truth)

    print("  RECOVERY  T=%d, phase %.1f deg, amplitude ratio %.3f"
          % (out["T"], out["dphi"], out["ratio"]))
    print("            RMS filtered   %.5f m" % err_filtered)
    print("            RMS corrected  %.5f m   (%.1f%% of the damage "
          "removed)" % (err_corrected,
                        100.0 * (1.0 - err_corrected / err_filtered)))
    print("            RMS of the exact catchment average vs truth %.2e m "
          "(should be ~0)" % err_exact)
    # The claim is directional and deliberately loose: a closed loop with
    # one synthetic basin cannot pin a percentage that would transfer to a
    # real catchment. What must hold is that the correction MOVES TOWARDS
    # the truth, and by a margin far outside round-off.
    return err_corrected < 0.5 * err_filtered


def main():
    sph = Sphere(nmax=30, radius_km=500.0)
    R = sph.cap(0.0, 30.0, 15.0)
    Rbar = sph.smooth(R)
    area = sph.integral(R)
    print("validate_leakage_datadriven: Vishwakarma method of deviation")
    print("  grid nmax=%d, Gaussian 500 km, cap radius 15 deg, "
          "A/4pi = %.4f" % (sph.nmax, area / (4 * np.pi)))
    ok = [
        check_phase_roundtrip(),
        check_identity(sph, R, area),
        check_adjoint(sph, R, Rbar, area),
        check_recovery(sph, R, area),
    ]
    if all(ok):
        print("validate_leakage_datadriven: OK - all claims hold")
        return 0
    print("validate_leakage_datadriven: FAILED")
    return 1


if __name__ == "__main__":
    sys.exit(main())
