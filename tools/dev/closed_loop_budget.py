#!/usr/bin/env python3
"""closed_loop_budget: the prediction WP9 row 9d's measurement checks.

Row 9d asks whether the closed loop of WP8 row 8f (Woehnke et al. 2025 /
Steffen et al. 2026: monthly full-covariance noise, the regional Kalman
filter on a local basis) fits the CI machine A8. The opt-in test
testRegionalClosedLoopAtFullSize (tests/testRobustness.m) runs a
synthetic version of that loop at full size and logs what it measured;
this script states, BEFORE that run, what the measurement should find.

The loop never holds more than one month's SH normal matrix. Per month
it builds N_t = D + V_t V_t' (P x P, the formal diagonal plus a rank-r
stripe pattern that changes from month to month), draws the month's
noise through N_t's Cholesky factor, and carries the normal equation into
the basis with shLowLevel.regionalNEQ(B, "neq") - T' N_t T, K x K - after
which the P x P matrices are released. The filter itself works in K
dimensions only. So the memory peak is a few P x P matrices, not a
stack over months:

    while N_t is built:  V_t V_t' (temporary) + D + V_t V_t' + N_t   3 P^2
    after chol:          N_t and its factor R                        2 P^2

and the work per month is chol (P^3 / 3 flops), the rank-r update
(2 r P^2) and the basis transformation (2 K P^2 + 2 K^2 P).

P = (nmax + 1)^2 - 4 coefficients for shLowLevel.shIndex's default
Nmin = 2. The A8 wall time is predicted from an assumed sustained
double-precision rate; the measurement replaces the assumption.

Run: python3 tools/dev/closed_loop_budget.py   (prints the table the
test's log is read against; exits 0).

Developed by Matthias Weigelt with the help of Claude (Opus 5.5),
2026-10-24.
"""

RANK = 20          # stripe-pattern rank r of the synthetic monthly NEQ
K_GUESS = 60       # basis size used only for the transformation flops
GFLOPS = 100.0     # assumed sustained rate on A8 (16 threads) - a guess


def row(nmax):
    P = (nmax + 1) ** 2 - 4
    mat_gb = 8.0 * P * P / 2 ** 30
    peak_gb = 3 * mat_gb
    flops = P ** 3 / 3 + 2 * RANK * P ** 2 + 2 * K_GUESS * P ** 2
    return P, mat_gb, peak_gb, flops / (GFLOPS * 1e9)


def main():
    print("nmax      P   one PxP [GB]   peak 3PxP [GB]   s/month at %g GFLOP/s"
          % GFLOPS)
    for nmax in (30, 60, 96, 120, 180):
        P, m, pk, s = row(nmax)
        print("%4d %6d %13.3f %16.3f %14.2f" % (nmax, P, m, pk, s))
    print()
    print("The filter adds K x K matrices only (K = basis size, tens to a "
          "few hundred for a river basin), so the peak does not grow with "
          "the number of months: no stack of monthly P x P matrices is "
          "formed. 8f was postponed on 2026-10-21 because A8's memory was "
          "doubted for these covariances (RECORD.md 1); the peak column is "
          "the claim the test's measurement on A8 confirms or refutes.")


if __name__ == "__main__":
    main()
