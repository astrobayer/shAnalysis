#!/usr/bin/env python3
"""Oracle for synthesis ON THE ELLIPSOID (WP3, finding B3).

Until v5.5.0 every synthesis evaluated on a sphere of radius R (+ Height).
WP3 adds Surface="ellipsoid": the series is evaluated at the geocentric
radius of the reference ellipsoid,

    r(phi) = a sqrt((1 - e^2) / (1 - e^2 cos^2 phi)),   e^2 = f (2 - f),

phi the GEOCENTRIC latitude, through the same radial law (R/r)^p_n that
Height already uses. Acceptance is SELF-CONSISTENCY (Matthias, 2026-09-10:
"you can drop the EGM2008 reference. Self-consistency is fine"), so every
claim below is checked against an independent route inside this file, and
the values it prints become the pinned expectations in the MATLAB tests.

CLAIMS
  GEOMETRY   the point (r cos phi, r sin phi) lies on x^2/a^2 + z^2/b^2 = 1
             to round-off; r(0) = a and r(+-90) = b = a (1 - f).
  SPHERE     f = 0 gives r = a everywhere - the sphere is a special case of
             the ellipsoid, not a separate code path.
  LEGENDRE   the 4pi-normalised zonal Pbar_n0(sin phi) equals
             sqrt(2n+1) P_n(sin phi) from numpy's Legendre polynomials - an
             independent check of the Legendre route used for the pins.
  RADIAL     -d(potential)/dr at r(phi), by 5-point finite differences in r,
             equals the gravity_disturbance series at r(phi). This is the
             identity that ties the radial law to the quantity kernels.
  GRADIENT   the north and east components at r(phi) (partials at FIXED r,
             in the local spherical frame) equal finite differences of the
             scalar series in phi and lambda.
  PINS       reference values at named points, printed for the tests.

  It also prints what B3 is about in numbers: the ellipsoid lies INSIDE the
  reference sphere at high latitudes, so the (R/r)^p_n law amplifies high
  degrees there, and the size of the error a geodetic latitude would make.

Run: python3 tools/dev/validate_ellipsoid.py
Nonzero exit if any claim fails.

Developed by Matthias Weigelt with the help of Claude (Opus 5), 2026-09-10.
"""
import sys

import numpy as np

GM = 3.986004415e14
R = 6378136.3                 # the coefficients' reference radius
A_WGS84 = 6378137.0           # the SURFACE's semi-major axis
F_WGS84 = 1.0 / 298.257223563

# The ellipse equation is algebra evaluated in floating point: a residual
# of a few ulp is round-off, anything near 1e-12 would be a wrong formula.
GEOMETRY_TOL = 1e-14
# Legendre: two independent routes to the same polynomial, degree <= 40;
# observed ~1e-14, the bound leaves room for the growth with degree.
LEGENDRE_TOL = 1e-12
# 5-point finite differences: the step error is O(h^4) and the cancellation
# error O(eps / h); at the steps below both are far under 1e-9 relative.
FD_TOL = 1e-9


def ellipsoid_radius(lat_deg, a=A_WGS84, f=F_WGS84):
    e2 = f * (2.0 - f)
    c = np.cos(np.radians(lat_deg))
    c = np.where(np.abs(np.abs(lat_deg) - 90.0) < 1e-15, 0.0, c)
    return a * np.sqrt((1.0 - e2) / (1.0 - e2 * c ** 2))


# ----------------------------------------------------------------- ALFs
def pbar(nmax, phi):
    """4pi-normalised Pbar_nm(sin phi) - textbook recursion, as in
    tools/dev/validate_gradient.py, deliberately NOT MATLAB's
    Holmes-Featherstone scaling."""
    t, u = np.sin(phi), np.cos(phi)
    P = np.zeros((nmax + 1, nmax + 1))
    P[0, 0] = 1.0
    for m in range(1, nmax + 1):
        P[m, m] = np.sqrt((2 * m + 1) / (2 * m)) * u * P[m - 1, m - 1]
    for m in range(0, nmax + 1):
        if m + 1 <= nmax:
            P[m + 1, m] = np.sqrt(2 * m + 3) * t * P[m, m]
        for n in range(m + 2, nmax + 1):
            a = np.sqrt((2 * n - 1) * (2 * n + 1) / ((n - m) * (n + m)))
            b = np.sqrt((2 * n + 1) * (n + m - 1) * (n - m - 1)
                        / ((n - m) * (n + m) * (2 * n - 3)))
            P[n, m] = a * t * P[n - 1, m] - b * P[n - 2, m]
    for m in range(1, nmax + 1):
        P[m:, m] *= np.sqrt(2.0)
    return P


def dpbar_dphi(nmax, phi):
    """dPbar_nm/dphi, the exact column stencil (validate_gradient.py)."""
    P = pbar(nmax, phi)
    D = np.zeros_like(P)
    for n in range(nmax + 1):
        for m in range(n + 1):
            c1 = np.sqrt(2.0) if m == 0 else 1.0
            c2 = np.sqrt(2.0) if m == 1 else 1.0
            t1 = c1 * np.sqrt((n - m) * (n + m + 1)) * (P[n, m + 1] if m + 1 <= n else 0.0)
            t2 = c2 * np.sqrt((n + m) * (n - m + 1)) * (P[n, m - 1] if m - 1 >= 0 else 0.0)
            D[n, m] = 0.5 * (t1 - t2)
    return D


# -------------------------------------------------------------- kernels
def kernel(quantity, nmax):
    """(k_n at r = R, radial exponent p_n) - kernelFactors' table."""
    n = np.arange(nmax + 1, dtype=float)
    if quantity == "potential":
        return (GM / R) * np.ones(nmax + 1), n + 1
    if quantity == "gravity_disturbance":
        return (GM / R ** 2) * (n + 1), n + 2
    if quantity == "gravity_anomaly":
        return (GM / R ** 2) * (n - 1), n + 2
    if quantity == "gravity_gradient_rr":
        return (GM / R ** 3) * (n + 1) * (n + 2), n + 3
    raise ValueError(quantity)


def coefficients(nmax):
    """Deterministic, so MATLAB rebuilds the same set without an RNG:
    C_nm = 1e-9 cos(0.7n + 1.3m)/(1+n), S_nm = 1e-9 sin(0.4n + 0.9m)/(1+n),
    lower triangle, S_n0 = 0, degrees 0 and 1 zero."""
    n, m = np.meshgrid(np.arange(nmax + 1), np.arange(nmax + 1), indexing="ij")
    C = 1e-9 * np.cos(0.7 * n + 1.3 * m) / (1 + n)
    S = 1e-9 * np.sin(0.4 * n + 0.9 * m) / (1 + n)
    C[m > n] = 0.0
    S[m > n] = 0.0
    S[:, 0] = 0.0
    C[:2, :] = 0.0
    S[:2, :] = 0.0
    return C, S


def series(C, S, quantity, phi, lam, r):
    nmax = C.shape[0] - 1
    k, p = kernel(quantity, nmax)
    f = k * (R / r) ** p
    P = pbar(nmax, phi)
    m = np.arange(nmax + 1)
    A = ((f[:, None] * C) * P).sum(axis=0)
    B = ((f[:, None] * S) * P).sum(axis=0)
    return float(A @ np.cos(m * lam) + B @ np.sin(m * lam))


def gradient(C, S, quantity, phi, lam, r):
    """north, east, up at radius r: partials at FIXED r, spherical frame."""
    nmax = C.shape[0] - 1
    k, p = kernel(quantity, nmax)
    f = k * (R / r) ** p
    P = pbar(nmax, phi)
    D = dpbar_dphi(nmax, phi)
    m = np.arange(nmax + 1)
    cm, sm = np.cos(m * lam), np.sin(m * lam)
    north = ((((f[:, None] * C) * D).sum(0)) @ cm
             + (((f[:, None] * S) * D).sum(0)) @ sm) / r
    east = ((((f[:, None] * C) * P).sum(0)) @ (-m * sm)
            + (((f[:, None] * S) * P).sum(0)) @ (m * cm)) / (r * np.cos(phi))
    up = -((((p * f)[:, None] * C) * P).sum(0) @ cm
           + (((p * f)[:, None] * S) * P).sum(0) @ sm) / r
    return float(north), float(east), float(up)


def fd5(fun, x, h):
    return (-fun(x + 2 * h) + 8 * fun(x + h) - 8 * fun(x - h)
            + fun(x - 2 * h)) / (12 * h)


# ---------------------------------------------------------------- claims
def check_geometry():
    lat = np.linspace(-90, 90, 1001)
    r = ellipsoid_radius(lat)
    b = A_WGS84 * (1 - F_WGS84)
    x, z = r * np.cos(np.radians(lat)), r * np.sin(np.radians(lat))
    res = np.max(np.abs((x / A_WGS84) ** 2 + (z / b) ** 2 - 1))
    eq = abs(ellipsoid_radius(np.array([0.0]))[0] - A_WGS84) / A_WGS84
    po = abs(ellipsoid_radius(np.array([90.0]))[0] - b) / b
    print("  GEOMETRY  ellipse residual %.1e, r(0)-a %.1e, r(90)-b %.1e "
          "(bound %.0e)" % (res, eq, po, GEOMETRY_TOL))
    print("            a - b = %.4f m" % (A_WGS84 - b))
    return max(res, eq, po) < GEOMETRY_TOL


def check_sphere_limit():
    lat = np.linspace(-90, 90, 181)
    d = np.max(np.abs(ellipsoid_radius(lat, f=0.0) - A_WGS84))
    print("  SPHERE    f = 0: max |r - a| = %.1e m" % d)
    return d == 0.0


def check_legendre():
    worst = 0.0
    for phi in np.radians([-83.0, -30.0, 0.0, 12.5, 57.0, 89.0]):
        P = pbar(40, phi)
        for n in range(41):
            coef = np.zeros(n + 1)
            coef[n] = 1.0
            ref = np.sqrt(2 * n + 1) * np.polynomial.legendre.legval(np.sin(phi), coef)
            worst = max(worst, abs(P[n, 0] - ref) / max(abs(ref), 1e-300))
    print("  LEGENDRE  zonal Pbar vs sqrt(2n+1) P_n: worst relative %.1e "
          "(bound %.0e)" % (worst, LEGENDRE_TOL))
    return worst < LEGENDRE_TOL


def check_radial(C, S):
    worst = 0.0
    for lat, lon in ((-63.5, 33.0), (17.25, 121.5), (72.0, 250.0)):
        phi, lam = np.radians(lat), np.radians(lon)
        r0 = ellipsoid_radius(np.array([lat]))[0]
        dVdr = fd5(lambda rr: series(C, S, "potential", phi, lam, rr), r0, 50.0)
        gd = series(C, S, "gravity_disturbance", phi, lam, r0)
        worst = max(worst, abs(-dVdr - gd) / abs(gd))
    print("  RADIAL    -dV/dr (5-pt FD) vs gravity_disturbance on the "
          "ellipsoid: worst relative %.1e (bound %.0e)" % (worst, FD_TOL))
    return worst < FD_TOL


def check_gradient(C, S):
    worst = 0.0
    for lat, lon in ((-63.5, 33.0), (17.25, 121.5), (72.0, 250.0)):
        phi, lam = np.radians(lat), np.radians(lon)
        r0 = ellipsoid_radius(np.array([lat]))[0]
        n, e, _ = gradient(C, S, "potential", phi, lam, r0)
        nfd = fd5(lambda p: series(C, S, "potential", p, lam, r0), phi, 1e-4) / r0
        efd = fd5(lambda l: series(C, S, "potential", phi, l, r0), lam, 1e-4) \
            / (r0 * np.cos(phi))
        worst = max(worst, abs(n - nfd) / abs(nfd), abs(e - efd) / abs(efd))
    print("  GRADIENT  north/east vs FD at fixed r on the ellipsoid: worst "
          "relative %.1e (bound %.0e)" % (worst, FD_TOL))
    return worst < FD_TOL


def print_b3():
    b = A_WGS84 * (1 - F_WGS84)
    for n in (60, 96, 180):
        print("  B3        at the poles (R/b)^(n+2) = %.4f for n = %d"
              % ((R / b) ** (n + 2), n))
    # a geodetic latitude used as if geocentric, at 45 deg
    gd = 45.0
    gc = np.degrees(np.arctan((1 - F_WGS84) ** 2 * np.tan(np.radians(gd))))
    dr = ellipsoid_radius(np.array([gd]))[0] - ellipsoid_radius(np.array([gc]))[0]
    print("  B3        a geodetic 45 deg taken as geocentric misplaces r by "
          "%.2f m (lat difference %.4f deg)" % (abs(dr), gd - gc))


def print_pins(C, S):
    print("\n  PINS (nmax %d; geocentric lat, lon in degrees)" % (C.shape[0] - 1))
    pts = ((-90.0, 0.0), (-63.5, 33.0), (0.0, 121.5), (45.0, 250.0),
           (89.5, 33.0))
    for q in ("potential", "gravity_disturbance", "gravity_anomaly",
              "gravity_gradient_rr"):
        for lat, lon in pts:
            r0 = ellipsoid_radius(np.array([lat]))[0]
            v = series(C, S, q, np.radians(lat), np.radians(lon), r0)
            print("PIN,%s,%.2f,%.2f,0,%.17g" % (q, lat, lon, v))
    for lat, lon in ((-63.5, 33.0), (45.0, 250.0)):
        r0 = ellipsoid_radius(np.array([lat]))[0] + 1500.0
        v = series(C, S, "gravity_disturbance", np.radians(lat),
                   np.radians(lon), r0)
        print("PIN,gravity_disturbance,%.2f,%.2f,1500,%.17g" % (lat, lon, v))
    for lat, lon in ((-63.5, 33.0), (0.0, 121.5), (45.0, 250.0)):
        r0 = ellipsoid_radius(np.array([lat]))[0]
        n, e, u = gradient(C, S, "potential", np.radians(lat),
                           np.radians(lon), r0)
        print("GRAD,potential,%.2f,%.2f,%.17g,%.17g,%.17g" % (lat, lon, n, e, u))


def main():
    C, S = coefficients(40)
    print("validate_ellipsoid: synthesis on the WGS84 ellipsoid (WP3)")
    ok = [check_geometry(), check_sphere_limit(), check_legendre(),
          check_radial(C, S), check_gradient(C, S)]
    print_b3()
    print_pins(C, S)
    if all(ok):
        print("\nvalidate_ellipsoid: OK - all claims hold")
        return 0
    print("\nvalidate_ellipsoid: FAILED")
    return 1


if __name__ == "__main__":
    sys.exit(main())
