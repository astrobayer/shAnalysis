function [yrs, msg] = cfTimeToYears(tRaw, units)
%CFTIMETOYEARS CF "<unit> since <reference>" time values -> decimal years.
%   [YRS, MSG] = cfTimeToYears(TRAW, UNITS) converts the values of a CF
%   time axis to the toolbox's decimal years: year + (t - 1 January) /
%   (length of that year) - the inverse of what shLowLevel.writeGrid
%   stores. UNITS is "days | hours | minutes | seconds since
%   Y-M-D[ h:m[:s]]"; month, day and clock fields may have one or two
%   digits ("days since 2002-4-18 00:00:00" is GravIS's), and a trailing
%   time-zone suffix is read as UTC.
%
%   It never raises: MSG is "" on success and the reason otherwise, so
%   each caller raises under its own identifier. It is the one place the
%   toolbox reads a CF time axis - shLowLevel.readMascon and
%   shLowLevel.readGrid both call it, because two parsers of one fact
%   drift apart (CLAUDE.md, A17). readMascon's own pattern accepted two-
%   digit months only, and so refused GravIS files.
%
%   Inputs
%     tRaw   numeric  the time axis' values
%     units  text     its units attribute
%
%   Outputs
%     yrs  (N,1) double  decimal years; [] when UNITS is not understood
%     msg  (1,1) string  "" on success, else the reason
%
%   Developed by Matthias Weigelt with the help of Claude (Opus 5),
%   2026-09-10 (v5.8.0).
yrs = [];
msg = "";
tok = regexpi(char(units), ['^\s*(days?|hours?|minutes?|seconds?)\s+since\s+' ...
    '(\d{1,4})-(\d{1,2})-(\d{1,2})(?:[ T]+(\d{1,2}):(\d{1,2})' ...
    '(?::(\d{1,2}(?:\.\d*)?))?)?'], 'tokens', 'once');
if isempty(tok)
    msg = sprintf(['time units "%s" are not "<days | hours | minutes | ' ...
        'seconds> since <date>"'], char(units));
    return
end
% MATLAB DROPS the tokens of an optional group that did not take part,
% rather than returning them empty: without a clock time TOK has 4
% elements, so read only as far as it reaches
clock = [0 0 0];
for k = 5:min(7, numel(tok))
    if ~isempty(tok{k}), clock(k - 4) = str2double(tok{k}); end
end
t0 = datetime(str2double(tok{2}), str2double(tok{3}), str2double(tok{4}), ...
    clock(1), clock(2), clock(3));
tRaw = double(tRaw(:));
switch lower(tok{1}(1))
    case 'd', tt = t0 + days(tRaw);
    case 'h', tt = t0 + hours(tRaw);
    case 'm', tt = t0 + minutes(tRaw);
    otherwise, tt = t0 + seconds(tRaw);
end
y0 = dateshift(tt, 'start', 'year');
yrs = year(tt) + days(tt - y0) ./ days(y0 + calyears(1) - y0);
end
