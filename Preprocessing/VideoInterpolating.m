function VideoInterpolating(obj, params)
k = params.json.Preprocess.InterpolationFactor;
fprintf('        - Interpolating data cube (factor 2^%d)\n', k);
obj.applyToVideos(@(v) interpFrames(v, k), {'M0_ff', 'f_AVG', 'f_RMS', 'bandRatio'});
end

function out = interpFrames(v, k)
[nx, ny, nt] = size(v);
out = zeros((nx - 1) * 2 ^ k + 1, (ny - 1) * 2 ^ k + 1, nt, 'like', v);

parfor t = 1:nt
    out(:, :, t) = interp2(v(:, :, t), k);
end

end
