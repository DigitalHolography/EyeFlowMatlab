function VideoNormalizingLocally(obj, params)
M0 = single(obj.M0);
[numX, numY, ~] = size(M0);
alpha = params.json.Preprocess.Normalizing.AlphaConvolveNorm;
D = (numX + numY) / 2;

if alpha == 1
    Mnorm = mean(M0, [1, 2]);
elseif alpha == 0
    Mnorm = M0;
elseif alpha == -1
    mask = diskMask(numX, numY, params.json.Mask.DiaphragmRadius);
    Mnorm = mean(M0(repmat(mask, 1, 1, size(M0, 3))));
elseif alpha == -2
    mask = diskMask(numX, numY, params.json.Mask.DiaphragmRadius + 0.2);
    Mnorm = mean(M0(repmat(~mask, 1, 1, size(M0, 3))));
else
    Mconv = boxSum(M0, round(alpha * (2 * D - 1)));
    outFile = sprintf('%s_alpha=%s_M0_Convolution_Norm.png', obj.filenames, num2str(alpha));
    imwrite(rescale(mean(Mconv, 3)), fullfile(obj.directory, 'eyeflow', outFile), 'png');
    Mnorm = Mconv .* sum(M0, [1, 2]) ./ sum(Mconv, [1, 2]);
end

if params.json.Preprocess.Normalizing.NormTempMode
    Mnorm = mean(Mnorm, 3);
end

Mnorm = max(Mnorm, eps('single'));

obj.f_AVG = single(obj.M1) ./ Mnorm;
obj.f_RMS = sqrt(single(obj.M2) ./ Mnorm);

FF = params.json.FlatFieldCorrection;
obj.M0_ff = flat_field_correction_ef(M0, ceil(FF.GWRatio * numX), FF.Border);
end

function out = boxSum(M, n)
% Équivalent de conv2(M, ones(n), 'same') mais séparable : O(n) au lieu de O(n^2)
k = ones(n, 1, 'single');
out = zeros(size(M), 'single');

parfor i = 1:size(M, 3)
    out(:, :, i) = conv2(k, k', M(:, :, i), 'same');
end

end
