function VideoRemoveOutliers(obj, params)
[numX, numY, ~] = size(obj.f_RMS);
mask = diskMask(numX, numY, params.json.Mask.DiaphragmRadius);
frame_means = squeeze(sum(obj.f_RMS .* mask, [1, 2]) / nnz(mask));

outliers = isoutlier(real(frame_means), 'movmedian', 5, 'ThresholdFactor', 2);
if ~any(outliers), return, end

obj.applyToVideos(@(v) interpolateOutlierFrames(v, outliers));
end
