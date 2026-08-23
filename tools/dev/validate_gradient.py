#!/usr/bin/env python3
"""validate_gradient: pre-validation for shLowLevel.shSynthesisGradient.

What is being decided here, before any MATLAB is written:

  1. the ASSEMBLY.  north/east/up are metric-scaled spectral sums; the
     factors 1/r, 1/(r cos phi) and the radial exponent are exactly the
     places where a sign or a power goes wrong silently.  Truth is a
     high-order finite difference of an INDEPENDENT scalar synthesis.
  2. the RADIAL LAW.  d/dr is only defined for the quantities that carry
     an upward-continuation exponent p_n.  kernelFactors already encodes
     p_n implicitly in its Height branch; this script pins the values
     (n+1 / n+2 / n+3) against the analytic identities
         d(potential)/dr            = -gravity_disturbance
         d(gravity_disturbance)/dr  = -gravity_gradient_rr
     which turn the up component into a check against kernels that are
     already validated, not into a new claim.
  3. the CLOSED FORMS.  single-coefficient fields whose gradient can be
     written down by hand, so at least one test does not depend on any
     other part of the toolbox being right.

4pi-normalized ALFs (ICGEM), C(n+1,m+1) indexing, geocentric latitude.

Developed by Matthias Weigelt with the help of Claude (Opus 5),
2026-08-22.
"""
import numpy as np

GM = 3.986004415e14
R = 6378136.3


# ----------------------------------------------------------------- ALFs
def pbar(nmax, phi):
    """4pi-normalized associated Legendre functions Pbar_nm(sin phi).

    Deliberately the plain textbook recursion, not the Holmes-Featherstone
    scaling MATLAB uses: an independent route is the whole point.
    """
    t = np.sin(phi)
    u = np.cos(phi)
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
    # 4pi normalization: the recursion above is already 4pi for m=0 and
    # carries the sqrt(2) for m>0 through the sectorial start
    for m in range(1, nmax + 1):
        P[m:, m] *= np.sqrt(2.0)
    return P


def dpbar_dphi(nmax, phi):
    """dPbar_nm/dphi from the exact column stencil (MATLAB's identity)."""
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
def kernel(quantity, nmax, kn=None, rho_ave=5517.0, rho_water=1000.0):
    """(k_n, p_n): the r = R factor and the radial exponent (None = surface)."""
    n = np.arange(nmax + 1, dtype=float)
    q = quantity.lower()
    if q == "none":
        return np.ones(nmax + 1), None
    if q == "geoid":
        return R * np.ones(nmax + 1), None
    if q == "potential":
        return (GM / R) * np.ones(nmax + 1), n + 1
    if q == "gravity_anomaly":
        return (GM / R**2) * (n - 1), n + 2
    if q == "gravity_disturbance":
        return (GM / R**2) * (n + 1), n + 2
    if q == "gravity_gradient_rr":
        return (GM / R**3) * (n + 1) * (n + 2), n + 3
    if q == "ewh":
        return R * rho_ave / (3 * rho_water) * (2 * n + 1) / (1 + kn), None
    if q == "surface_density":
        return R * rho_ave / 3 * (2 * n + 1) / (1 + kn), None
    raise ValueError(quantity)


def fn_at_r(quantity, nmax, r, **kw):
    k, p = kernel(quantity, nmax, **kw)
    if p is None:
        if abs(r - R) > 0:
            raise ValueError("surface quantity has no radial law")
        return k, None
    return k * (R / r) ** p, p


# ------------------------------------------------------------- synthesis
def scalar(C, S, quantity, phi, lam, r, **kw):
    nmax = C.shape[0] - 1
    f, _ = fn_at_r(quantity, nmax, r, **kw)
    P = pbar(nmax, phi)
    m = np.arange(nmax + 1)
    cm, sm = np.cos(m * lam), np.sin(m * lam)
    A = ((f[:, None] * C) * P).sum(axis=0)
    B = ((f[:, None] * S) * P).sum(axis=0)
    return float(A @ cm + B @ sm)


def analytic(C, S, quantity, phi, lam, r, **kw):
    """north, east, up = the assembly under test."""
    nmax = C.shape[0] - 1
    f, p = fn_at_r(quantity, nmax, r, **kw)
    P = pbar(nmax, phi)
    D = dpbar_dphi(nmax, phi)
    m = np.arange(nmax + 1)
    cm, sm = np.cos(m * lam), np.sin(m * lam)

    AN = ((f[:, None] * C) * D).sum(axis=0)
    BN = ((f[:, None] * S) * D).sum(axis=0)
    north = (AN @ cm + BN @ sm) / r

    AE = ((f[:, None] * C) * P).sum(axis=0)
    BE = ((f[:, None] * S) * P).sum(axis=0)
    east = (AE @ (-m * sm) + BE @ (m * cm)) / (r * np.cos(phi))

    if p is None:
        up = None
    else:
        AU = (((p * f)[:, None] * C) * P).sum(axis=0)
        BU = (((p * f)[:, None] * S) * P).sum(axis=0)
        up = -(AU @ cm + BU @ sm) / r
    return north, east, up


# --------------------------------------------------------------- checks
def fd(fun, x, h):
    """5-point central difference."""
    return (fun(x - 2 * h) - 8 * fun(x - h) + 8 * fun(x + h) - fun(x + 2 * h)) / (12 * h)


def rel(a, b):
    return abs(a - b) / max(abs(a), abs(b), 1e-300)


def main():
    rng = np.random.default_rng(20260822)
    nmax = 12
    C = np.tril(rng.standard_normal((nmax + 1, nmax + 1))) * 1e-10
    S = np.tril(rng.standard_normal((nmax + 1, nmax + 1))) * 1e-10
    S[:, 0] = 0.0
    kn = -0.3 * (1 - np.exp(-np.arange(nmax + 1) / 3.0))

    print("=" * 68)
    print("1. ALF normalization against closed forms")
    P = pbar(4, 0.7)
    ref = {(0, 0): 1.0, (1, 0): np.sqrt(3) * np.sin(0.7),
           (1, 1): np.sqrt(3) * np.cos(0.7),
           (2, 0): np.sqrt(5) * (3 * np.sin(0.7) ** 2 - 1) / 2,
           (2, 2): np.sqrt(15 / 4) * np.cos(0.7) ** 2}
    for (n, m), v in ref.items():
        print(f"   Pbar_{n}{m}: {P[n, m]: .12f} vs {v: .12f}   rel {rel(P[n, m], v):.1e}")
    # frozen MATLAB reference (tools/audit/audit_alf_ref.json, colatitude)
    print(f"   Pbar_22(equator) = {pbar(2, 0.0)[2, 2]:.12f}  (MATLAB frozen 1.936491673103709)")
    print(f"   Pbar_20(pole)    = {pbar(2, np.pi/2)[2, 0]:.12f}  (MATLAB frozen 2.236067977499756)")

    print("=" * 68)
    print("2. dPbar/dphi stencil against finite differences")
    phi = 0.41
    Dn = dpbar_dphi(6, phi)
    worst = 0.0
    for n in range(7):
        for m in range(n + 1):
            num = fd(lambda x: pbar(6, x)[n, m], phi, 1e-4)
            worst = max(worst, rel(Dn[n, m], num) if abs(num) > 1e-12 else 0.0)
    print(f"   worst relative error over n<=6: {worst:.2e}")

    print("=" * 68)
    print("3. assembly vs finite differences of the scalar synthesis")
    quantities = [("none", {}), ("geoid", {}), ("potential", {}),
                  ("gravity_anomaly", {}), ("gravity_disturbance", {}),
                  ("gravity_gradient_rr", {}), ("ewh", dict(kn=kn))]
    for phi, lam in [(0.41, 1.1), (-1.20, 4.7), (0.02, 0.0)]:
        print(f"   --- phi = {phi:+.2f} rad, lambda = {lam:.2f} rad")
        for q, kw in quantities:
            r = R
            an, ae, au = analytic(C, S, q, phi, lam, r, **kw)
            fn_ = fd(lambda x: scalar(C, S, q, x, lam, r, **kw), phi, 1e-4) / r
            fe_ = fd(lambda x: scalar(C, S, q, phi, x, r, **kw), lam, 1e-4) / (r * np.cos(phi))
            msg = f"      {q:22s} N {rel(an, fn_):.2e}  E {rel(ae, fe_):.2e}"
            if au is not None:
                fu_ = fd(lambda x: scalar(C, S, q, phi, lam, x, **kw), r, 50.0)
                msg += f"  U {rel(au, fu_):.2e}"
            else:
                msg += "  U  (surface - no radial law)"
            print(msg)

    print("=" * 68)
    print("4. radial identities against already-validated kernels")
    phi, lam = 0.41, 1.1
    _, _, upT = analytic(C, S, "potential", phi, lam, R)
    dg = scalar(C, S, "gravity_disturbance", phi, lam, R)
    print(f"   d(potential)/dr           = {upT: .6e}")
    print(f"   -gravity_disturbance      = {-dg: .6e}   rel {rel(upT, -dg):.2e}")
    _, _, upD = analytic(C, S, "gravity_disturbance", phi, lam, R)
    trr = scalar(C, S, "gravity_gradient_rr", phi, lam, R)
    print(f"   d(gravity_disturbance)/dr = {upD: .6e}")
    print(f"   -gravity_gradient_rr      = {-trr: .6e}   rel {rel(upD, -trr):.2e}")

    print("=" * 68)
    print("5. closed forms (quantity 'none', r = R, single coefficient)")
    for (n, m, kind, expect, name) in [
        (1, 0, "C", lambda p, l: (np.sqrt(3) * np.cos(p) / R, 0.0), "C10 -> N=sqrt3 cos(phi)/R, E=0"),
        (1, 1, "C", lambda p, l: (-np.sqrt(3) * np.sin(p) * np.cos(l) / R,
                                  -np.sqrt(3) * np.sin(l) / R), "C11"),
        (1, 1, "S", lambda p, l: (-np.sqrt(3) * np.sin(p) * np.sin(l) / R,
                                  np.sqrt(3) * np.cos(l) / R), "S11"),
    ]:
        C1 = np.zeros((2, 2)); S1 = np.zeros((2, 2))
        (C1 if kind == "C" else S1)[n, m] = 1.0
        for phi, lam in [(0.41, 1.1), (-1.2, 4.7)]:
            an, ae, _ = analytic(C1, S1, "none", phi, lam, R)
            en, ee = expect(phi, lam)
            print(f"   {name:12s} phi={phi:+.2f} lam={lam:.2f}: "
                  f"N rel {rel(an, en):.2e}  E {'rel %.2e' % rel(ae, ee) if abs(ee) > 0 else 'abs %.2e' % abs(ae - ee)}")

    print("=" * 68)
    print("6. Height: assembly at r = R + h")
    h = 250e3
    r = R + h
    for q in ["potential", "gravity_disturbance", "gravity_gradient_rr"]:
        an, ae, au = analytic(C, S, q, 0.41, 1.1, r)
        fn_ = fd(lambda x: scalar(C, S, q, x, 1.1, r), 0.41, 1e-4) / r
        fu_ = fd(lambda x: scalar(C, S, q, 0.41, 1.1, x), r, 50.0)
        print(f"   {q:22s} N {rel(an, fn_):.2e}   U {rel(au, fu_):.2e}")

    print("=" * 68)
    print("7. the pole: east is undefined, north is not")
    for phi in [np.pi / 2 - 1e-9, np.pi / 2]:
        try:
            an, ae, _ = analytic(C, S, "geoid", phi, 1.1, R)
            print(f"   phi = {phi:.12f}: north {an: .6e}   east {ae: .6e}")
        except Exception as e:  # noqa: BLE001
            print(f"   phi = {phi:.12f}: {e}")


if __name__ == "__main__":
    main()
