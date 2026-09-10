#!/usr/bin/env python3
"""Oracle for the Earth-rotation excitation of degree-2 coefficients (WP5 5a).

WHERE THE EQUATION COMES FROM
  J. L. Chen and C. R. Wilson (2003), Low degree gravitational changes from
  earth rotation and geophysical models, Geophys. Res. Lett. 30(24), 2257,
  doi:10.1029/2003GL018688 - equation (1), after Eubanks (1993):

      dC21 = -(1 + k2') sqrt(3/5) (C - A) / (1.098 R^2 M) chi1
      dS21 = -(1 + k2') sqrt(3/5) (C - A) / (1.098 R^2 M) chi2
      dC20 = -(1 + k2') 3 / (2 sqrt(5)) C / (0.753 R^2 M) chi3

  M and R are the Earth's mass and mean radius, C and A its principal
  moments of inertia, k2' the degree-2 load Love number (-0.301 in the
  paper). The paper gives no values for M, R, C and A, and neither does
  this file: the constants below are SYNTHETIC round numbers of the
  Earth's order, chosen so the claims can be checked. They are test
  inputs, not the Earth's constants, and nothing here asserts a physical
  magnitude.

  What the paper does NOT give: the conversion of chi3 into a length of
  day, and the relation of chi2 to the IERS pole coordinate y (which
  points to 90 W). chi1 and chi2 are in the frame of the coefficients:
  eq. (1) treats (C21, chi1) and (S21, chi2) alike, and S21 goes with
  sin(lambda), so chi2 points to 90 E.

  v5.11.0 adds two sources. The IERS Conventions (2010), Table 1.1
  (Chapter 1 as updated 16 November 2017), gives G, GM, a_E, J2 and the
  dynamical flattening H, from which M, C and A follow by definition.
  The ESMGFZ EAM Product Description Document (Dobslaw & Dill, rev. 1.1,
  2019) gives dLOD in eq. (2.8), with eqs. (2.3) and (2.13): the axial
  excitation times 2 pi / Omega. The equation prints 2 pi Omega; only
  2 pi / Omega is a time, and that is how it is read.

THE CLAIMS
  CLAIM 0  the inverse pair. The toolbox solves eq. (1) for chi; the
           forward equation as printed, applied to that solution, must
           return the input. Written as two separate functions here.
  CLAIM 1  unit responses for the synthetic constants: chi1 [mas] per
           dC21 = 1e-10 and chi3 per dC20 = 1e-10 - the numbers
           testCorrectness pins against the MATLAB lane.
  CLAIM 2  the mean is removed: a static offset on every epoch (a mean
           field) leaves the excitation unchanged.
  CLAIM 3  the factors enter as the equation says: chi1 scales with the
           1.098, chi3 with the 0.753, both with 1/(1 + k2').
  CLAIM 4  M, C and A from IERS 2010 Table 1.1 by the definitions
           J2 = (C - A)/(M a_E^2) and H = (C - A)/C, with A the mean
           equatorial moment - and they agree with the C and A that
           ESMGFZ tabulates (Table 2.1), a separate publication.
  CLAIM 5  dLOD = (2 pi / Omega) chi3, and its sign: mass moved towards
           the equator lowers C20 and must lengthen the day. Plus the
           IERS 2010 unit responses the tests pin.
  CLAIM 6  opt-in, with SHX_EARTHROTATION_FOLDER: the observed length of
           day (EOP 14 C04) against (2 pi / Omega) chi3 of the ESMGFZ
           atmosphere, ocean, hydrology and sea level, monthly, with a
           25-month running mean removed - slope near one, which is the
           check on reading eq. (2.8) as 2 pi / Omega.
  Reported, not asserted: eq. (1)'s axial 0.753 against ESMGFZ's
  alpha3 alpha4, and its polar 1.098 against alpha1 alpha2.
"""
import datetime
import math
import os
import sys

import numpy as np

MAS = 180.0 / math.pi * 3600.0e3            # milliarcseconds per radian
EARTH = dict(M=6.0e24, R=6.4e6, C=8.0e37, A=7.97e37)   # SYNTHETIC inputs
K2 = -0.301                                 # the paper's value, as an input


def forward(chi1_mas, chi2_mas, chi3, E=EARTH, k2=K2, fp=1.098, fa=0.753):
    """Eq. (1) as printed: coefficient changes from excitations."""
    r2m = E["R"] ** 2 * E["M"]
    polar = -(1.0 + k2) * math.sqrt(3.0 / 5.0) * (E["C"] - E["A"]) / (fp * r2m)
    axial = -(1.0 + k2) * 3.0 / (2.0 * math.sqrt(5.0)) * E["C"] / (fa * r2m)
    return (polar * np.asarray(chi1_mas, float) / MAS,
            polar * np.asarray(chi2_mas, float) / MAS,
            axial * np.asarray(chi3, float))


def inverse(c21, s21, c20, E=EARTH, k2=K2, fp=1.098, fa=0.753,
            reference="mean"):
    """Eq. (1) solved for chi - what the MATLAB lane computes, written
    here from the equation, not from the MATLAB code."""
    c21 = np.asarray(c21, float)
    s21 = np.asarray(s21, float)
    c20 = np.asarray(c20, float)
    if reference == "mean":
        c21 = c21 - c21.mean()
        s21 = s21 - s21.mean()
        c20 = c20 - c20.mean()
    r2m = E["R"] ** 2 * E["M"]
    polar = -fp * r2m / ((1.0 + k2) * math.sqrt(3.0 / 5.0) * (E["C"] - E["A"]))
    axial = -fa * r2m * 2.0 * math.sqrt(5.0) / ((1.0 + k2) * 3.0 * E["C"])
    return polar * c21 * MAS, polar * s21 * MAS, axial * c20


def series(T=24):
    t = np.arange(T) / 12.0
    return (30.0 * np.cos(2 * np.pi * t),
            20.0 * np.sin(2 * np.pi * t + 0.4),
            5e-10 * np.cos(4 * np.pi * t))


def rel(a, b):
    return float(np.max(np.abs(np.asarray(a) - np.asarray(b)))
                 / np.max(np.abs(np.asarray(b))))


def check_pair():
    """CLAIM 0: forward(inverse(dC)) = dC, and inverse(forward(chi)) = chi."""
    chi = series()
    dc = forward(*chi)
    back = inverse(*dc, reference="none")
    again = forward(*back)
    e1 = max(rel(b, c) for b, c in zip(back, chi))
    e2 = max(rel(a, d) for a, d in zip(again, dc))
    print("  PAIR      inverse(forward(chi)) - chi: worst relative %.2e; "
          "forward(inverse(dC)) - dC: %.2e (bound 1e-14)" % (e1, e2))
    return e1 < 1e-14 and e2 < 1e-14


def check_units():
    """CLAIM 1: the unit responses the MATLAB test pins."""
    chi1, chi2, chi3 = inverse([1e-10], [1e-10], [1e-10], reference="none")
    print("  UNITS     chi1 per dC21 = 1e-10: %.17g mas" % chi1[0])
    print("            chi2 per dS21 = 1e-10: %.17g mas" % chi2[0])
    print("            chi3 per dC20 = 1e-10: %.17g" % chi3[0])
    # the sign follows from eq. (1): -(1 + k2') < 0 with k2' = -0.301,
    # so a positive coefficient change is a negative excitation
    return chi1[0] < 0 and chi3[0] < 0 and chi1[0] == chi2[0]


def check_mean():
    """CLAIM 2: a static offset (a mean field) leaves chi unchanged."""
    dc = forward(*series())
    plain = inverse(*dc)
    shifted = inverse(dc[0] + 1e-9, dc[1] - 3e-9, dc[2] - 4.8e-4)
    e = max(rel(a, b) for a, b in zip(shifted, plain))
    print("  MEAN      offsets 1e-9, -3e-9, -4.8e-4 removed: worst relative "
          "%.2e (bound 1e-9; the C20 offset is 1e6 times its changes)" % e)
    return e < 1e-9


def check_factors():
    """CLAIM 3: 1.098, 0.753 and 1/(1 + k2') enter as printed."""
    dc = forward(*series())
    base = inverse(*dc)
    fp2 = inverse(*dc, fp=2 * 1.098)
    fa2 = inverse(*dc, fa=2 * 0.753)
    k2b = inverse(*dc, k2=-0.2)
    e_fp = rel(fp2[0], 2 * base[0])
    e_fa = rel(fa2[2], 2 * base[2])
    ratio = (1.0 + K2) / (1.0 - 0.2)
    e_k2 = max(rel(k2b[0], ratio * base[0]), rel(k2b[2], ratio * base[2]))
    print("  FACTORS   doubling 1.098 doubles chi1 (%.1e), doubling 0.753 "
          "doubles chi3 (%.1e), k2' -0.301 -> -0.2 scales by "
          "0.699/0.8 (%.1e)" % (e_fp, e_fa, e_k2))
    return max(e_fp, e_fa, e_k2) < 1e-14


# IERS Conventions (2010), Table 1.1, Chapter 1 as updated 16 Nov 2017
IERS2010 = dict(G=6.67428e-11, GM=3.986004418e14, aE=6378136.6,
                J2=1.0826359e-3, H=3273795e-9)
# ESMGFZ EAM Product Description Document (Dobslaw & Dill 2019), Table 2.1
PDD = dict(C=8.0365e37, A=8.0102e37, Omega=7.292115e-5)


def iers2010_earth():
    """M, R, C, A from Table 1.1: M = GM/G, C - A = J2 M aE^2 (A the mean
    of the equatorial moments), C = (C - A)/H, R = aE."""
    t = IERS2010
    m = t["GM"] / t["G"]
    cma = t["J2"] * m * t["aE"] ** 2
    c = cma / t["H"]
    return dict(M=m, R=t["aE"], C=c, A=c - cma)


def check_iers():
    """CLAIM 4: the IERS 2010 constants, checked against a second
    publication's."""
    E = iers2010_earth()
    rc = E["C"] / PDD["C"] - 1.0
    ra = E["A"] / PDD["A"] - 1.0
    print("  IERS2010  M = %.17g kg, R = %.17g m" % (E["M"], E["R"]))
    print("            C = %.17g, A = %.17g kg m^2" % (E["C"], E["A"]))
    print("            C - A = %.17g kg m^2" % (E["C"] - E["A"]))
    print("            against ESMGFZ Table 2.1: C %+.3e, A %+.3e relative "
          "(bound 1e-3)" % (rc, ra))
    return abs(rc) < 1e-3 and abs(ra) < 1e-3


def check_lod():
    """CLAIM 5: dLOD = (2 pi / Omega) chi3, its sign, and the IERS 2010
    unit responses."""
    E = iers2010_earth()
    scale = 2.0 * math.pi / PDD["Omega"] * 1e3        # ms per unit chi3
    c1, _, c3 = inverse([1e-10], [0.0], [1e-10], E=E, reference="none")
    _, _, down = inverse([0.0], [0.0], [-1e-10], E=E, reference="none")
    print("  LOD       2 pi / Omega = %.17g ms per unit chi3" % scale)
    print("            IERS2010: chi1 per dC21 = 1e-10: %.17g mas" % c1[0])
    print("            IERS2010: chi3 per dC20 = 1e-10: %.17g" % c3[0])
    print("            IERS2010: dLOD per dC20 = 1e-10: %.17g ms"
          % (scale * c3[0]))
    print("            dC20 = -1e-10, mass towards the equator: dLOD %+.5f ms"
          % (scale * down[0]))
    return scale * down[0] > 0 and c3[0] < 0


def report_factors():
    """Reported, not asserted: eq. (1)'s factors against ESMGFZ's."""
    polar = 1.610 * 0.684
    axial = 1.125 * 0.750
    print("  FACTORS   polar: ESMGFZ alpha1 alpha2 = %.4f, eq. (1) 1.098 "
          "(ratio %.4f)" % (polar, polar / 1.098))
    print("            axial: ESMGFZ alpha3 alpha4 = %.4f, eq. (1) 0.753 "
          "(ratio %.4f; C/Cm = 1.129)" % (axial, axial / 0.753))
    return True


def read_eam(folder, ncol):
    """ESMGFZ effective angular momentum functions: MJD and the ncol value
    columns that follow YYYY MM DD HH MJD on every data line."""
    mjd, rows = [], []
    for name in sorted(os.listdir(folder)):
        if not name.endswith(".asc") or "_mean_" in name:
            continue
        with open(os.path.join(folder, name), encoding="latin-1") as fh:
            for line in fh:
                tok = line.split()
                if (len(tok) == 5 + ncol and len(tok[0]) == 4
                        and tok[0].isdigit()):
                    mjd.append(float(tok[4]))
                    rows.append([float(v) for v in tok[5:]])
    return np.array(mjd), np.array(rows)


def daily(mjd, values):
    """Daily means, keyed by the integer MJD."""
    day = np.floor(mjd).astype(int)
    u, inv = np.unique(day, return_inverse=True)
    return u, np.bincount(inv, values) / np.bincount(inv)


def running_residual(x, half=12):
    """x minus its centred running mean over 2 half + 1 samples, shrinking
    at the ends - removes the decadal core signal from monthly LOD."""
    out = np.empty_like(x)
    for i in range(x.size):
        lo, hi = max(0, i - half), min(x.size, i + half + 1)
        out[i] = x[i] - x[lo:hi].mean()
    return out


def check_lod_against_eop():
    """CLAIM 6 (opt-in): the observed length of day against
    dLOD = (2 pi / Omega) chi3, chi3 the ESMGFZ total of atmosphere, ocean,
    hydrology (mass and motion) and barystatic sea level. A slope near one
    is the check on reading eq. (2.8) as 2 pi / Omega."""
    folder = os.environ.get("SHX_EARTHROTATION_FOLDER", "")
    eopf = os.path.join(folder, "EOP14C04.mat")
    if not folder or not os.path.isfile(eopf):
        print("  EOP       SKIP - set SHX_EARTHROTATION_FOLDER to a folder "
              "holding EOP14C04.mat and ESMGFZ/{AAM,OAM,HAM,SLAM}")
        return True
    import scipy.io as sio
    eop = sio.loadmat(eopf)["EOP"]
    scale = 2.0 * math.pi / PDD["Omega"] * 1e3
    parts = []
    for prod, ncol, cols in (("AAM", 6, [2, 5]), ("OAM", 6, [2, 5]),
                             ("HAM", 6, [2, 5]), ("SLAM", 3, [2])):
        mjd, x = read_eam(os.path.join(folder, "ESMGFZ", prod), ncol)
        parts.append(daily(mjd, x[:, cols].sum(axis=1)))
    days = eop[:, 0].astype(int)
    common = days
    for d, _ in parts:
        common = np.intersect1d(common, d)
    chi3 = sum(v[np.searchsorted(d, common)] for d, v in parts)
    model = scale * chi3
    obs = 1e3 * eop[np.searchsorted(days, common), 7]
    dates = [datetime.date(1858, 11, 17) + datetime.timedelta(days=int(m))
             for m in common]
    key = np.array([dt.year * 12 + dt.month - 1 for dt in dates])
    _, inv = np.unique(key, return_inverse=True)
    om = np.bincount(inv, obs) / np.bincount(inv)
    mm = np.bincount(inv, model) / np.bincount(inv)
    oh, mh = running_residual(om), running_residual(mm)
    corr = float(oh @ mh / math.sqrt((oh @ oh) * (mh @ mh)))
    slope = float(mh @ oh / (mh @ mh))
    print("  EOP       %d days, %s .. %s, %d months" % (
        common.size, dates[0], dates[-1], om.size))
    print("            observed LOD against (2 pi / Omega) chi3, a 25-month "
          "running mean removed: corr %.3f, slope %.3f, RMS obs %.4f ms, "
          "model %.4f ms" % (corr, slope, oh.std(), mh.std()))
    print("            read as printed, 2 pi Omega, the slope would be %.3g"
          % (slope / PDD["Omega"] ** 2))
    # measured: corr 0.943, slope 1.097 over 2002-2022 (241 months). The
    # models explain the length of day to about ten percent, so the bounds
    # check the sign and the scale of the conversion, not the models -
    # read as printed, the slope would be 2e8
    return corr > 0.9 and 0.8 < slope < 1.25


def main():
    print("validate_excitation: Chen & Wilson (2003) eq. (1)")
    print("  synthetic constants M=%.1e R=%.1e C=%.3e A=%.3e, k2'=%.3f"
          % (EARTH["M"], EARTH["R"], EARTH["C"], EARTH["A"], K2))
    ok = [check_pair(), check_units(), check_mean(), check_factors(),
          check_iers(), check_lod(), report_factors(),
          check_lod_against_eop()]
    if all(ok):
        print("validate_excitation: OK - all claims hold")
        return 0
    print("validate_excitation: FAILED")
    return 1


if __name__ == "__main__":
    sys.exit(main())
