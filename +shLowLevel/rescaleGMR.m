function [C2, S2, sig] = rescaleGMR(C, S, GM1, R1, GM2, R2, sigmaC, sigmaS)
%RESCALEGMR Convert Stokes coefficients between (GM, R) reference values.
%
%   [C2, S2] = shLowLevel.rescaleGMR(C, S, GM1, R1, GM2, R2) re-expresses
%   coefficients given w.r.t. (GM1, R1) in the reference (GM2, R2):
%
%       C2_nm = C_nm * (GM1/GM2) * (R1/R2)^n
%
%   The physical field is invariant: synthesizing the potential from
%   (C, GM1, R1) and from (C2, GM2, R2) at the same points agrees
%   exactly (Python-validated, rel 0). Needed whenever fields from
%   different conventions meet: normal-field subtraction (WGS84 GM/a
%   differ from the ICGEM values!), cross-center combination, mixing
%   model releases.
%
%   Inputs
%     C, S      (n1,n1) double  coefficients w.r.t. (GM1, R1)
%     GM1, R1   (1,1) double  current reference [m^3/s^2], [m]
%     GM2, R2   (1,1) double  target reference [m^3/s^2], [m]
%     sigmaC, sigmaS  (n1,n1) double, optional  formal errors, rescaled by
%               the same positive factors and returned in sig.C / sig.S
%
%   Outputs
%     C2, S2    (n1,n1) double  coefficients w.r.t. (GM2, R2)
%     sig  (1,1) struct  fields
%          C  (n1,n1) double or []  rescaled cosine sigmas, empty when
%             sigmaC was not supplied
%          S  (n1,n1) double or []  rescaled sine sigmas, empty when
%             sigmaS was not supplied
%
%   Claude (Fable 5), 2026-08-07 (v2.4).
%   Developed by Matthias Weigelt with the help of Claude (Fable 5).
arguments
    C double
    S double
    GM1 (1,1) double {mustBePositive}
    R1 (1,1) double {mustBePositive}
    GM2 (1,1) double {mustBePositive}
    R2 (1,1) double {mustBePositive}
    sigmaC double = []
    sigmaS double = []
end
n1 = size(C, 1);
fac = (GM1/GM2) * (R1/R2).^((0:n1-1)');
C2 = C .* fac;
S2 = S .* fac;
sig = struct('C', [], 'S', []);
if ~isempty(sigmaC), sig.C = sigmaC .* fac; end
if ~isempty(sigmaS), sig.S = sigmaS .* fac; end
end
