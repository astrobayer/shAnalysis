function [files, info] = fetchTN(opts)
%FETCHTN Download the TN-13/TN-14 low-degree completion files on demand.
%
%   FILES = shLowLevel.fetchTN() fetches the GRACE/GRACE-FO technical notes that
%   complete the standard processing chain into <dataFolder>/TN:
%     TN-14  GSFC SLR C20/C30 replacement       (shLowLevel.readTN14/applyTN14)
%     TN-13  geocenter (degree 1) per provider  (shLowLevel.readTN13/addDegree1)
%   Source: the GFZ ISDC open document server (URLs verified 2026-08-07;
%   the CSR/JPL/GFZ RL06.3 files and the GSFC TN-14 also ship as test
%   fixtures, so the toolbox works offline out of the box).
%
%   The technical notes GROW MONTHLY upstream. With Update (false)=true,
%   already-present files are re-downloaded and replaced - but only
%   after the fresh copy has been VERIFIED BY PARSE, so a failed or
%   corrupt download never clobbers a working local file (the existing
%   file is kept, re-verified, and the failure is reported). Without
%   Update (default), existing files are skipped and re-verified only.
%
%   Options
%     Providers (["GFZ","CSR","JPL"])  TN-13 providers to fetch
%     TN14 (true)                       also fetch the GSFC TN-14 file
%     Release ("RL06.3")                TN-13 release tag in the filename
%     Update (false)                    refresh existing files (safe swap)
%     Dest (fullfile(shLowLevel.dataFolder(), "TN"))
%     BaseURL ("")                      override source: an https base or
%                                       a LOCAL MIRROR FOLDER (institute
%                                       mirrors, offline tests)
%     Proxy ("")                        per-call proxy, e.g.
%                                       "http://proxy.uni.de:8080" (websave
%                                       otherwise honours MATLAB Web Preferences)
%     Timeout (60), Quiet (false)
%     MaxTries (httpFetch's, 4)  (1,1) double  attempts httpFetch makes
%                    per download on a transient failure (429, 5xx, a
%                    network error), with exponential backoff between
%                    them; not forwarded when omitted, so httpFetch's
%                    default is the only one. The Proxy path makes one
%                    attempt
%     BaseDelay (httpFetch's, 2)  (1,1) double  [s] first backoff wait;
%                    attempt k waits BaseDelay 2^(k-1) plus up to 25%
%                    jitter. A failing download costs about
%                    BaseDelay (2^MaxTries - 1) seconds of waiting -
%                    15 s at the defaults, which is what offline tests
%                    pay unless they pass MaxTries = 1
%
%   Outputs
%     files  (1,:) string  verified present file paths (new + updated
%                          + kept existing)
%     info   (1,1) struct  fields
%            fetched  (1,:) string  files downloaded now
%            updated  (1,:) string  files replaced by a newer copy
%            skipped  (1,:) string  files already present
%            failed   (1,:) string  files that did not arrive
%            urls     (1,:) string  the URLs used, in the same order
%            dest     (1,1) string  target folder
%
%   Example
%     shLowLevel.fetchTN(Update = true);            % monthly refresh, safe swap
%     tn13 = shLowLevel.readTN13(fullfile(shLowLevel.dataFolder(), "TN", ...
%                "TN-13_GEOC_CSR_RL06.3.txt"));
%     g1 = g.applyTN14(tn14).addDegree1(tn13);
%
%   Error identifiers
%     shLowLevel:fetchTN:failed
%         warning - one or more files failed to download or to parse; the
%         message names them
%     shLowLevel:fetchTN:mirrorMissing
%         Mirror= was given but does not hold the requested file
%
%   Developed by Matthias Weigelt with the help of Claude (Fable 5),
%   2026-08-08 (v2.5.1). MaxTries/BaseDelay: Claude (Opus 5.5),
%   2026-10-21 (A36).
arguments
    opts.Providers (1,:) string ...
        {mustBeMember(opts.Providers, ["GFZ", "CSR", "JPL"])} = ...
        ["GFZ", "CSR", "JPL"]
    opts.TN14 (1,1) logical = true
    opts.Release (1,1) string = "RL06.3"
    opts.Update (1,1) logical = false
    opts.Dest (1,1) string = ""
    opts.BaseURL (1,1) string = ""
    opts.Proxy (1,1) string = ""
    opts.Timeout (1,1) double = 60
    opts.Quiet (1,1) logical = false
    opts.MaxTries (1,1) double {mustBeInteger, mustBePositive}
    opts.BaseDelay (1,1) double {mustBePositive}
end
hopt = retryOptions(opts);
dest = opts.Dest;
if strlength(dest) == 0
    dest = string(fullfile(shLowLevel.dataFolder(), 'TN'));
end
if ~isfolder(dest), mkdir(dest); end
base = opts.BaseURL;
if strlength(base) == 0
    base = "https://isdc-data.gfz.de/grace-fo/DOCUMENTS/TECHNICAL_NOTES";
end
mirror = isfolder(base);                    % local mirror folder mode

names = strings(1, 0); parsers = {};
for p = unique(opts.Providers)
    names(end+1) = sprintf("TN-13_GEOC_%s_%s.txt", p, opts.Release); %#ok<AGROW>
    parsers{end+1} = @shLowLevel.readTN13; %#ok<AGROW>
end
if opts.TN14
    names(end+1) = "TN-14_C30_C20_SLR_GSFC.txt";
    parsers{end+1} = @shLowLevel.readTN14;
end

wo = weboptions('Timeout', opts.Timeout);
files = strings(1, 0); fetched = files; updated = files;
skipped = files; failed = files; urls = strings(1, 0);
for k = 1:numel(names)
    fp = fullfile(dest, names(k));
    url = base + "/" + names(k);
    urls(end+1) = url; %#ok<AGROW>
    present = isfile(fp);
    if present && ~opts.Update
        % skip path: keep and re-verify the existing file
        try
            parsers{k}(fp);
            files(end+1) = string(fp); skipped(end+1) = names(k); %#ok<AGROW>
        catch err
            failed(end+1) = names(k) + " (parse: " + err.message + ")"; %#ok<AGROW>
        end
        continue
    end
    % new download or refresh: fetch to a temp name, verify BEFORE swap
    if ~opts.Quiet
        if present
            fprintf('  updating %s ...\n', names(k));
        else
            fprintf('  fetching %s ...\n', names(k));
        end
    end
    tmpf = fp + ".part";
    ok = false;
    try
        if mirror
            src = fullfile(base, names(k));
            if ~isfile(src)
                error('shLowLevel:fetchTN:mirrorMissing', ...
                    'not in mirror: %s', names(k));
            end
            copyfile(src, tmpf);
        else
            webFetch(url, tmpf, opts.Timeout, opts.Proxy, hopt{:});
        end
        parsers{k}(tmpf);                   % verify the FRESH copy
        ok = true;
    catch err
        if isfile(tmpf), delete(tmpf); end
        failed(end+1) = names(k) + " (" + err.message + ")"; %#ok<AGROW>
    end
    if ok
        shLowLevel.safeMove(tmpf, fp);
        files(end+1) = string(fp); %#ok<AGROW>
        if present
            updated(end+1) = names(k); %#ok<AGROW>
        else
            fetched(end+1) = names(k); %#ok<AGROW>
        end
    elseif present
        % failed refresh: the existing file stays authoritative
        try
            parsers{k}(fp);
            files(end+1) = string(fp); skipped(end+1) = names(k); %#ok<AGROW>
        catch err
            failed(end+1) = names(k) + " (parse: " + err.message + ")"; %#ok<AGROW>
        end
    end
end
if ~opts.Quiet && ~isempty(failed)
    warning('shLowLevel:fetchTN:failed', '%d file(s) failed:\n  %s', ...
        numel(failed), strjoin(failed, newline + "  "));
end
info = struct('fetched', fetched, 'updated', updated, 'skipped', skipped, ...
    'failed', failed, 'urls', urls, 'dest', dest);
end

function c = retryOptions(opts)
%RETRYOPTIONS The retry options the caller gave, as name-value pairs for
%   shLowLevel.httpFetch; an option not given is not forwarded, so
%   httpFetch's own default is the only one.
c = {};
for nm = ["MaxTries", "BaseDelay"]
    if isfield(opts, nm)
        c = [c, {char(nm), opts.(nm)}]; %#ok<AGROW>
    end
end
end
