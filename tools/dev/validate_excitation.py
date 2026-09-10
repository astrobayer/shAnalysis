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

  What the paper does NOT give, so this file does not test it: the
  conversion of chi3 into a length-of-day change, and the relation of
  chi2 to the IERS pole coordinate y (which points to 90 W). chi1 and
  chi2 are in the frame of the coefficients: eq. (1) treats (C21, chi1)
  and (S21, chi2) alike, and S21 goes with sin(lambda), so chi2 points
  to 90 E.

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
"""
import math
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


def main():
    print("validate_excitation: Chen & Wilson (2003) eq. (1)")
    print("  synthetic constants M=%.1e R=%.1e C=%.3e A=%.3e, k2'=%.3f"
          % (EARTH["M"], EARTH["R"], EARTH["C"], EARTH["A"], K2))
    ok = [check_pair(), check_units(), check_mean(), check_factors()]
    if all(ok):
        print("validate_excitation: OK - all claims hold")
        return 0
    print("validate_excitation: FAILED")
    return 1


if __name__ == "__main__":
    sys.exit(main())
