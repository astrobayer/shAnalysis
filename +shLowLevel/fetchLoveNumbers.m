function [files, info] = fetchLoveNumbers(names, opts)
%FETCHLOVENUMBERS Download load/deformation Love number files (GROOPS set).
%
%   FILES = shLowLevel.fetchLoveNumbers() downloads the standard load Love
%   number file (Gegout97, kn for degrees 0..1024) from the GROOPS data
%   collection hosted by TU Graz into <dataFolder>/loveNumbers, with the
%   usual safe-swap semantics. The toolbox deliberately never hardcodes
%   Love numbers - this fetcher automates obtaining a PUBLISHED set,
%   which you then pass explicitly (kn = ...) where required.
%
%   Available names (server-verified 2026-08-10):
%     loadLoveNumbers_Gegout97.txt          loadLoveNumbers_ak135.txt
%     loadLoveNumbers_CF_ak135.txt          loadLoveNumbers_CM_ak135.txt
%     deformationLoveNumbers_CE_Gegout97.txt / _CE_ak135 / _CF_ak135 /
%     _CM_Gegout97 / _CM_ak135 (.txt)
%   NAMES may be one name, a string vector, or "all".
%
%   [FILES, INFO] = ... also parses every loadLoveNumbers_* file
%   (single-column GROOPS matrix: kn per degree starting at 0) into
%   INFO.parsed - ready for kn= options after truncation to your nmax.
%
%   Options
%     Dest ("")            target folder; default <dataFolder>/loveNumbers
%     BaseURL ("https://ftp.tugraz.at/pub/ITSG/groops/data/loading") (GROOPS/TU Graz loading folder)  or a local mirror folder
%     Timeout (30), Proxy (""), Update (false), Quiet (false)
%
%   Outputs
%     files      (1,K) string  local paths
%     info  (1,1) struct  fields
%           fetched, updated, skipped  (1,:) string  local PATHS per
%                   outcome (skipped includes a present file kept after a
%                   failed refresh)
%           failed  (1,:) string  "name: message" per file that did not
%                   arrive or did not parse
%           parsed  (1,:) struct  one per loadLoveNumbers_* file, with
%                   name, n (N x 1) and kn (N x 1); deformation files
%                   are omitted
%
%   Example
%     [f, inf] = shLowLevel.fetchLoveNumbers();
%     kn = inf.parsed(1).kn(1:61);        % degrees 0..60 for an n60 field
%
%   Error identifiers
%     shLowLevel:fetchLoveNumbers:badFormat
%         the downloaded file is neither a GROOPS matrix file nor a bare
%         finite numeric table with the expected columns (one for the
%         load Love numbers, two - h' and l' - for a deformation table)
%     shLowLevel:fetchLoveNumbers:unknownName
%         the requested file is not one of the known Love-number files
%
%   Developed by Matthias Weigelt with the help of Claude (Fable 5),
%   2026-08-10 (v3.0.0).
arguments
    names string = "loadLoveNumbers_Gegout97.txt"
    opts.Dest (1,1) string = ""
    opts.BaseURL (1,1) string = ...
        "https://ftp.tugraz.at/pub/ITSG/groops/data/loading"
    opts.Timeout (1,1) double = 30
    opts.Proxy (1,1) string = ""
    opts.Update (1,1) logical = false
    opts.Quiet (1,1) logical = false
end
known = ["loadLoveNumbers_Gegout97.txt", "loadLoveNumbers_ak135.txt", ...
    "loadLoveNumbers_CF_ak135.txt", "loadLoveNumbers_CM_ak135.txt", ...
    "deformationLoveNumbers_CE_Gegout97.txt", ...
    "deformationLoveNumbers_CE_ak135.txt", ...
    "deformationLoveNumbers_CF_ak135.txt", ...
    "deformationLoveNumbers_CM_Gegout97.txt", ...
    "deformationLoveNumbers_CM_ak135.txt"];
if isscalar(names) && names == "all"
    names = known;
end
bad = setdiff(names, known);
if ~isempty(bad)
    error('shLowLevel:fetchLoveNumbers:unknownName', ...
        'Unknown file "%s"; known: %s', bad(1), strjoin(known, ', '));
end
dest = opts.Dest;
if strlength(dest) == 0
    dest = string(fullfile(shLowLevel.dataFolder(), 'loveNumbers'));
end
if ~isfolder(dest), mkdir(dest); end
localBase = isfolder(opts.BaseURL);
files = strings(1, 0);
info = struct('fetched', strings(1, 0), 'updated', strings(1, 0), ...
    'skipped', strings(1, 0), 'failed', strings(1, 0), 'parsed', []);
parsed = struct('name', {}, 'n', {}, 'kn', {});
for nm = names(:)'
    fp = fullfile(dest, char(nm));
    present = isfile(fp);
    if present && ~opts.Update
        info.skipped(end+1) = string(fp);
        files(end+1) = string(fp); %#ok<AGROW>
    else
        tmpf = string(fp) + ".part";
        try
            if localBase
                copyfile(fullfile(char(opts.BaseURL), char(nm)), char(tmpf));
            else
                webFetch(opts.BaseURL + "/" + nm, tmpf, ...
                    opts.Timeout, opts.Proxy);
            end
            % verify BEFORE swap; a deformation table holds h' and l' in
            % two columns, which the one-column check refused, so every
            % deformation fetch failed before v5.23.4
            parseGroopsMatrix(tmpf, 1 + startsWith(nm, "deformation"));
            shLowLevel.safeMove(tmpf, fp);
            files(end+1) = string(fp); %#ok<AGROW>
            if present, info.updated(end+1) = string(fp);
            else, info.fetched(end+1) = string(fp); end
            if ~opts.Quiet, fprintf('  fetched %s\n', nm); end
        catch err
            if isfile(tmpf), delete(char(tmpf)); end
            if present
                info.skipped(end+1) = string(fp);
                files(end+1) = string(fp); %#ok<AGROW>
            else
                info.failed(end+1) = nm + ": " + err.message;
                continue
            end
        end
    end
    if startsWith(nm, "loadLoveNumbers") && nargout > 1
        kn = parseGroopsMatrix(fp, 1);
        parsed(end+1) = struct('name', nm, ...
            'n', (0:numel(kn)-1)', 'kn', kn); %#ok<AGROW>
    end
end
info.parsed = parsed;
end

function v = parseGroopsMatrix(fp, ncol)
% N x NCOL GROOPS matrix: 'groops matrix version=...' header,
% 'Matrix( N x NCOL )', then N rows; NCOL is 1 for the load Love numbers
% and 2 (h', l') for the deformation tables
txt = fileread(char(fp));
lines = strsplit(strtrim(txt), '\n');
if numel(lines) < 3 || ~contains(lines{1}, 'groops matrix')
    % the GROOPS loading folder itself ships BOTH layouts: Gegout97
    % carries the two-line matrix header, the ak135 variants are bare
    % single-column numeric (audit F-12). Accept the bare form when it
    % parses cleanly as NCOL finite columns.
    v = sscanf(txt, '%f');
    nRows = nnz(~cellfun(@(s) isempty(strtrim(s)), lines));
    ok = numel(v) >= 100 * ncol && all(isfinite(v)) && ...
        numel(v) == ncol * nRows;
    assert(ok, 'shLowLevel:fetchLoveNumbers:badFormat', ...
        'Neither a GROOPS matrix file nor a bare numeric table.');
    v = reshape(v, ncol, []).';
    return
end
tok = regexp(lines{2}, 'Matrix\(\s*(\d+)\s*x\s*(\d+)\s*\)', 'tokens', 'once');
assert(~isempty(tok) && str2double(tok{2}) == ncol, ...
    'shLowLevel:fetchLoveNumbers:badFormat', ...
    'Expected an N x %d GROOPS matrix.', ncol);
N = str2double(tok{1});
assert(numel(lines) >= 2 + N, 'shLowLevel:fetchLoveNumbers:badFormat', ...
    'Matrix body parse failed.');
v = sscanf(strjoin(lines(3:2+N), ' '), '%f');
assert(all(isfinite(v)) && numel(v) == N * ncol, ...
    'shLowLevel:fetchLoveNumbers:badFormat', 'Matrix body parse failed.');
v = reshape(v, ncol, N).';
end
