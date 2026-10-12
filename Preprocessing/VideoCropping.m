function [firstFrame, lastFrame] = VideoCropping(obj, firstFrame, lastFrame)
numFrames = size(obj.M0, 3);
if firstFrame == -1, firstFrame = 1; end
if lastFrame == -1, lastFrame = numFrames; end

if firstFrame < 1 || firstFrame > numFrames
    error('First frame (%d) is out of bounds. It should be between 1 and %d.', firstFrame, numFrames);
elseif lastFrame < 1 || lastFrame > numFrames
    error('Last frame (%d) is out of bounds. It should be between 1 and %d.', lastFrame, numFrames);
elseif firstFrame >= lastFrame
    error('First frame (%d) should be less than last frame (%d).', firstFrame, lastFrame);
end

idx = firstFrame:lastFrame;
obj.applyToVideos(@(v) v(:, :, idx));
if ~isempty(obj.SH), obj.SH = obj.SH(:, :, :, idx); end
fprintf('Data cube frame: %d/%d to %d/%d\n', firstFrame, numFrames, lastFrame, numFrames);
end
