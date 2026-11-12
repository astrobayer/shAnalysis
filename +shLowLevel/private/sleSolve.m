function [S, it, dS, kap, conv] = sleSolve(sigL, O, Y, w, fSD, fNU, rhoW, tol, maxIt)
%SLESOLVE The elastic sea-level equation for K land loads at once.
%   [S, IT, DS, KAP, CONV] = sleSolve(SIGL, O, Y, W, FSD, FNU, RHOW, TOL, MAXIT)
%   iterates S = O (N - U + kappa) for the land loads SIGL (Ngrid x K
%   surface densities, zero over the ocean), N - U from the TOTAL load
%   SIGL + RHOW S, kappa from global mass conservation (Farrell & Clark
%   1976, elastic, no rotation, fixed coastlines). It is the one place the
%   toolbox solves it: shLowLevel.seaLevelFingerprint calls it with one
%   load and shLowLevel.regionalBasis (Ocean) with every basis column -
%   two copies of the loop drifted into existence in v5.30.0 and were
%   merged in v6.0.6 (CLAUDE.md, A17: two parsers of one fact).
%
%   Inputs
%     sigL   (Ngrid,K) double  land loads [kg/m^2] on the quadrature grid
%     O      (Ngrid,1) double  ocean function on the same grid
%     Y      (Ngrid,P0) double  synthesis matrix of degrees 0..Lmax
%     w      (Ngrid,1) double  quadrature weights, sum 1
%     fSD    (P0,1) double  surface density per Stokes coefficient
%     fNU    (P0,1) double  geoid minus uplift per Stokes coefficient,
%            R - R h_n / (1 + k_n)
%     rhoW   (1,1) double  water density [kg/m^3]
%     tol    (1,1) double  stop when max |dS| < tol * max |eustatic|
%     maxIt  (1,1) double  iteration limit
%
%   Outputs
%     S    (Ngrid,K) double  relative sea level [m], zero on land
%     it   (1,1) double  sweeps run
%     dS   (1,1) double  the last sweep's largest change
%     kap  (1,K) double  the last sweep's mass-conserving constants [m]
%     conv (1,1) logical  DS fell below the tolerance
%
%   Developed by Matthias Weigelt with the help of Claude (Opus 5.5),
%   2026-11-12 (v6.0.6).
Aoc = w' * O;
Ml = w' * sigL;
eust = -Ml / (rhoW * Aoc);
S = O .* eust;
kap = eust;
tolAbs = tol * max(max(abs(eust)), realmin);
dS = Inf;
it = 0;
for it = 1:maxIt
    c = (Y' * (w .* (sigL + rhoW * S))) ./ fSD;
    NU = Y * (fNU .* c);
    kap = (-Ml / rhoW - w' * (O .* NU)) / Aoc;
    Snew = O .* (NU + kap);
    dS = max(abs(Snew - S), [], 'all');
    S = Snew;
    if dS < tolAbs, break; end
end
conv = dS < tolAbs;
end
