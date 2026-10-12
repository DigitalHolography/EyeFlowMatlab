function VideoNonRigidRegistering(obj, apply)
ToolBox = getGlobalToolBox;
exportVideos = ToolBox.getParams.exportVideos;

v = obj.M0;
[numX, numY, numFrames] = size(v);
ref_img = mean(v, 3);
ref_img = ref_img ./ imgaussfilt(ref_img, 100);
ref_img = (ref_img - min(ref_img(:))) / (max(ref_img(:)) - min(ref_img(:)));

M0_stab = zeros(numX, numY, numFrames, 'single');
field = zeros(numX, numY, 2, numFrames, 'single');
frameDiff = zeros(numX, numY, numFrames, 'single'); % ne masque plus diff()

parfor k = 1:numFrames
    tgt = safeConvertFrame(v(:, :, k));
    [f, s] = diffeomorphicDemon(tgt, ref_img, tgt);
    field(:, :, :, k) = f;
    M0_stab(:, :, k) = s;
    frameDiff(:, :, k) = tgt - s;
end

D.diff = frameDiff;
D.stabilized = M0_stab;
D.field = field;

AA = complex(squeeze(field(:, :, 1, :)), squeeze(field(:, :, 2, :))); % X x Y x T
[~, ~, D.mag_temporal_derivative] = gradient(abs(AA));
[~, ~, D.phase_temporal_derivative] = gradient(angle(AA));

if exportVideos, saveAsGifs(D); end
obj.displacementField = D;

if apply
    warning_s("NonRigidRegisteringApply is experimental (warps f_RMS, f_AVG, bandRatio).");
    obj.applyToVideos(@(c) warpFrames(c, field), {'f_RMS', 'f_AVG', 'bandRatio'});
end

end

function out = warpFrames(c, field)
out = c;

parfor ff = 1:size(c, 3)
    out(:, :, ff) = imwarp(c(:, :, ff), field(:, :, :, ff), 'nearest');
end

end
