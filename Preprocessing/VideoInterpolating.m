function VideoInterpolating(obj, params)
% Spatial interpolation of preprocessed videos.
% The temporal dimension is preserved.
%
% M0, M1 and M2 remain on their original grid.
% Derived videos and gaussian_w follow the interpolated grid.

k = params.json.Preprocess.InterpolationFactor;

validateattributes(k, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'integer', 'nonnegative'}, ...
    'VideoInterpolating', 'InterpolationFactor');

if k == 0
    return
end

fprintf('        - Interpolating data cube (factor 2^%d)\n', k);

fields = { ...
              'M0_ff', ...
              'f_AVG', ...
              'f_RMS', ...
              'HF_M0', ...
              'LF_M0', ...
              'bandRatio', ...
          'gaussian_w'};

obj.applyToVideos(@(v) interpFrames(v, k), fields);

end

function out = interpFrames(v, k)

[nx, ny, nt] = size(v);

outNx = (nx - 1) * 2 ^ k + 1;
outNy = (ny - 1) * 2 ^ k + 1;

out = zeros(outNx, outNy, nt, 'like', v);

parfor t = 1:nt
    out(:, :, t) = interp2(v(:, :, t), k);
end

end
