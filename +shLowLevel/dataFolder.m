function folder = dataFolder(newFolder, opts)
%DATAFOLDER Get or set the data folder of the toolbox, in the data pool.
%
%   F = shLowLevel.dataFolder()          returns the current data folder
%                                 (created on demand), resolved in this
%                                 order (the data-pool contract, v6.0.0):
%                                   1. the stored preference
%                                      getpref('shAnalysis','dataFolder'),
%                                      set by PATH below or by
%                                      setup_shAnalysis(DataFolder = PATH)
%                                   2. <getenv("DATAPOOL")>/GravityField
%                                   3. <getenv("READING_DATA_POOL")>/GravityField
%                                      (the older name, still honoured)
%                                   4. otherwise it REFUSES with
%                                      shLowLevel:dataFolder:noDataPool.
%                                 There is no <toolbox root>/data default
%                                 any more: nothing downloaded lands in
%                                 the toolbox folder.
%   F = shLowLevel.dataFolder(PATH)      sets and persists a user folder
%                                 (MATLAB preference, survives sessions:
%                                 setpref('shAnalysis','dataFolder')).
%   F = shLowLevel.dataFolder("reset")   removes the preference and returns
%                                 what the pool resolves to now ("" when
%                                 neither variable is set); it neither
%                                 refuses nor creates a folder.
%   F = shLowLevel.dataFolder(Probe = true)  the same lookup with no side
%                                 effect: no folder is created, and ""
%                                 is returned instead of either refusal.
%                                 For lookups that have a fallback
%                                 (readDDK's "DDK<n>", twsChain, the
%                                 demos, setup_shAnalysis' summary).
%
%   Layout since v3.16: series/itsg/{monthly,daily,sinex,background},
%   series/<icgem-name>, series/GAX/<product> for temporal products;
%   static/ for static models; DDK/, TN/ and loveNumbers/ for
%   auxiliaries. Folder names are case-exact: readers use the spelling
%   the fetchers write. The fetchers warn once when they find data in a
%   pre-v3.16 location. Consumers: shLowLevel.fetchITSG (series/itsg/),
%   shLowLevel.fetchDDK (DDK/), shLowLevel.fetchTN (TN/),
%   shLowLevel.fetchICGEM (static/ and series/), shLowLevel.readDDK("DDK<n>")
%   name resolution, standardChain's TN defaults, and the demo's
%   real-data discovery. Files committed to the repository (data/gravis,
%   shLowLevel.gravisDataFolder) and the test fixtures
%   (shLowLevel.testDataDir) are not looked up here.
%
%   Claude (Fable 5), 2026-08-07 (v2.4.1); the data-pool resolution by
%   Claude (Opus 5.5), 2026-11-08 (v6.0.0).
%
%   Inputs
%     newFolder  char/string  new persistent data folder, or "reset" (omit to query the current one)
%   Options
%     Probe (false)  true: look up only - create nothing, return "" instead of refusing
%   Outputs
%     folder     (1 x 1) string   current data folder (created on demand unless Probe)
%
%   Example
%     setenv("DATAPOOL", "D:/DATAPOOL");      % normally done by startup.m
%     f = shLowLevel.dataFolder()             % -> D:/DATAPOOL/GravityField
%
%   Error identifiers
%     shLowLevel:dataFolder:noDataPool
%         no preference is stored and neither DATAPOOL nor
%         READING_DATA_POOL is set: set DATAPOOL, or give the folder with
%         setup_shAnalysis(DataFolder = PATH) / shLowLevel.dataFolder(PATH)
%     shLowLevel:dataFolder:insideToolbox
%         the folder given or stored lies inside the toolbox folder;
%         downloads belong to the data pool
%
%   Developed by Matthias Weigelt with the help of Claude (Fable 5).
arguments
    newFolder (1,1) string = ""
    opts.Probe (1,1) logical = false
end
group = 'shAnalysis'; prefName = 'dataFolder';
if newFolder == "reset"
    if ispref(group, prefName), rmpref(group, prefName); end
    newFolder = "";
    opts.Probe = true;      % reset reports the fallback; it requires none
end
if strlength(newFolder) > 0
    refuseInsideToolbox(newFolder);
    setpref(group, prefName, char(newFolder));
end
folder = "";
if ispref(group, prefName)
    folder = string(getpref(group, prefName));
end
% the pool root: DATAPOOL, then the older READING_DATA_POOL; shAnalysis'
% root in the pool is GravityField (the installer's docs/DATA_POOL.md)
for var = ["DATAPOOL", "READING_DATA_POOL"]
    if strlength(folder) > 0, break; end
    pool = string(getenv(var));
    if strlength(pool) > 0
        folder = string(fullfile(char(pool), 'GravityField'));
    end
end
if strlength(folder) == 0
    if opts.Probe, return; end
    error('shLowLevel:dataFolder:noDataPool', ...
        ['No data folder. Set the DATAPOOL environment variable to the ' ...
         'data pool (shAnalysis uses <DATAPOOL>/GravityField), or give ' ...
         'the folder with setup_shAnalysis(DataFolder = PATH) or ' ...
         'shLowLevel.dataFolder(PATH). READING_DATA_POOL is honoured too. ' ...
         'Nothing is written into the toolbox folder.']);
end
if opts.Probe
    if insideToolbox(folder), folder = ""; end   % a lookup does not refuse
    return
end
refuseInsideToolbox(folder);
if ~isfolder(folder), mkdir(folder); end
end

function refuseInsideToolbox(f)
% downloads never land in the toolbox: refuse its root and anything below
if insideToolbox(f)
    rootDir = fileparts(fileparts(mfilename('fullpath')));
    error('shLowLevel:dataFolder:insideToolbox', ...
        ['The data folder %s lies inside the toolbox folder %s. ' ...
         'Downloads belong to the data pool: set DATAPOOL or give a ' ...
         'folder outside the toolbox.'], char(f), rootDir);
end
end

function tf = insideToolbox(f)
rootDir = fileparts(fileparts(mfilename('fullpath')));   % .../+shLowLevel -> root
r = normPath(rootDir);
p = normPath(f);
tf = p == r || startsWith(p, r + "/");
end

function p = normPath(f)
% one spelling for the comparison: forward slashes, no trailing one, and
% case-folded where the file system ignores case
p = strip(replace(string(f), "\", "/"), "right", "/");
if ispc, p = lower(p); end
end
