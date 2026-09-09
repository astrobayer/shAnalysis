function writeFrames(frames, filename, opts)
%WRITEFRAMES Write ready-made RGB frames to a video container.
%
%   shLowLevel.writeFrames(FRAMES, 'out.avi', FrameRate (4)=..., ...)
%   writes an (H x W x 3 x T) uint8 stack to an MPEG-4 or Motion-JPEG AVI
%   file and, by default, a provenance sidecar beside it.
%
%   WHY THIS IS A SEPARATE FUNCTION. It contains no graphics at all - it
%   takes pixels and produces a file. That is deliberate: since v3.32.0
%   the frames themselves are drawn by geoMap, which is not on the CI
%   machine, so a combined function would have taken the container
%   mechanics out of the test suite with it. Codec selection, extension
%   validation, frame rate and the sidecar are exactly the parts that
%   have bitten before, and they stay testable because they never needed
%   a renderer in the first place.
%
%   MPEG-4 IS NOT AVAILABLE IN LINUX VideoWriter. The extension chooses
%   the profile and .mp4 fails with a named error rather than a codec
%   complaint; .avi (Motion JPEG) is the portable choice.
%
%   Inputs
%     frames    (H,W,3,T) uint8   RGB frames, e.g. from getframe().cdata
%     filename  (1,1) string      .mp4 or .avi target path
%
%   Options
%     FrameRate (4)  frames per second
%     Sidecar (true)  write <file>.provenance.json alongside the output
%         (nFrames, frameRate and frameSize are always recorded)
%     SidecarExtra (struct())  extra fields merged into the sidecar
%
%   Outputs
%     none (writes FILENAME, and FILENAME.provenance.json when Sidecar)
%
%   Example
%     F = uint8(zeros(120, 240, 3, 5));
%     shLowLevel.writeFrames(F, fullfile(tempdir, 'demo.avi'), FrameRate = 2);
%
%   See also SHLOWLEVEL/WRITEANIMATION, SHSERIES/TOGRID.
%
%   Error identifiers
%     shLowLevel:writeFrames:badExtension
%         the filename ends in neither .mp4 nor .avi
%     shLowLevel:writeFrames:badSize
%         FRAMES is not H x W x 3 x T
%     shLowLevel:writeFrames:mp4Unsupported
%         MPEG-4 is not available on this platform; use an .avi filename
%     shLowLevel:writeFrames:noFrames
%         FRAMES holds no frame
%
%   Claude (Opus 5), 2026-08-23 (v3.32.0).
%   Developed by Matthias Weigelt with the help of Claude (Opus 5).
arguments
    frames uint8
    filename (1,1) string
    opts.FrameRate (1,1) double {mustBePositive} = 4
    opts.Sidecar (1,1) logical = true
    opts.SidecarExtra (1,1) struct = struct()
end
assert(ndims(frames) == 4 && size(frames, 3) == 3, ...
    'shLowLevel:writeFrames:badSize', ...
    'FRAMES must be H x W x 3 x T uint8 (got %s).', mat2str(size(frames)));
T = size(frames, 4);
assert(T > 0, 'shLowLevel:writeFrames:noFrames', 'FRAMES is empty.');

[~, ~, ext] = fileparts(char(filename));
switch lower(ext)
    case '.mp4'
        profs = VideoWriter.getProfiles;
        if ~any(strcmp({profs.Name}, 'MPEG-4'))
            error('shLowLevel:writeFrames:mp4Unsupported', ...
                ['MPEG-4 is not available on this platform (Linux). ', ...
                 'Use an .avi filename instead.']);
        end
        vw = VideoWriter(char(filename), 'MPEG-4');
    case '.avi'
        vw = VideoWriter(char(filename), 'Motion JPEG AVI');
    otherwise
        error('shLowLevel:writeFrames:badExtension', ...
            'Use an .mp4 or .avi filename (got %s).', ext);
end
vw.FrameRate = opts.FrameRate;
open(vw);
closer = onCleanup(@() close(vw)); %#ok<NASGU>
for k = 1:T
    writeVideo(vw, frames(:, :, :, k));
end
if opts.Sidecar
    extra = opts.SidecarExtra;
    extra.nFrames = T;
    extra.frameRate = opts.FrameRate;
    % the geometry, recorded rather than inferred: two exports of the
    % same data differing by 0.4% in bytes should be explainable from
    % the sidecar alone, not from guessing at the renderer
    extra.frameSize = [size(frames, 1), size(frames, 2)];
    writeSidecar(filename, extra);
end
end

function writeSidecar(target, extra)
% provenance JSON sidecar: <target>.provenance.json (v2.7.0)
v = shLowLevel.version();
p = struct('tool', sprintf('%s %s (%s)', v.Name, v.Version, v.Date), ...
    'provenance', v.Provenance, ...
    'created', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')), ...
    'matlab', sprintf('%s / %s', version, computer), ...
    'file', char(target));
fn = fieldnames(extra);
for k = 1:numel(fn), p.(fn{k}) = extra.(fn{k}); end
fid = fopen(char(string(target) + ".provenance.json"), 'w');
fprintf(fid, '%s\n', jsonencode(p, 'PrettyPrint', true));
fclose(fid);
end
