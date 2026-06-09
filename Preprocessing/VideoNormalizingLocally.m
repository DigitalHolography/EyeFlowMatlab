function VideoNormalizingLocally(obj, params)
% VideoNormalizingLocally performs local normalization on the video data
% using the M0 data. The normalization method is determined by the alpha
% parameter.

M0 = single(obj.M0);
[numX, numY, numFrames] = size(M0);
alpha = params.json.Preprocess.Normalizing.AlphaConvolveNorm;
D = (numY + numX) / 2;

if alpha == 1
    % behaves as if conv_size = alpha*(2*D-1) just faster;
    M0_data_convoluated = mean(M0, [1, 2]);
elseif alpha == 0
    % forces the pixel M0 normaFlisation;
    M0_data_convoluated = M0;
elseif alpha == -1
    diaphragmRadius = params.json.Mask.DiaphragmRadius;
    maskDiaphragm = diskMask(numX, numY, diaphragmRadius);
    M0_data_convoluated = mean(M0(maskDiaphragm)); % normalize by M0 inside the diaphragm
elseif alpha == -2
    diaphragmRadius = params.json.Mask.DiaphragmRadius + 0.2;
    maskDiaphragm = diskMask(numX, numY, diaphragmRadius);
    M0_data_convoluated = mean(M0(~maskDiaphragm)); % normalize by M0 outside the diaphragm
else
    conv_size = round(alpha * (2 * D - 1));
    M0_data_convoluated = zeros([numX, numY, numFrames]);
    conv_kern = ones(conv_size);

    parfor i = 1:numFrames
        M0_data_convoluated(:, :, i) = conv2(M0(:, :, i), conv_kern, 'same');
    end

    S = sum(M0, [1, 2]);
    S2 = sum(M0_data_convoluated, [1, 2]);

    imwrite(rescale(mean(M0_data_convoluated, 3)), fullfile(obj.directory, 'eyeflow', sprintf("%s_alpha=%s_%s", obj.filenames, num2str(alpha), 'M0_Convolution_Norm.png')), 'png');

    M0_data_convoluated = M0_data_convoluated .* S ./ S2; % normalizing to get the average with alpha = 0;
end

if params.json.Preprocess.Normalizing.NormTempMode
    M0_data_convoluated = mean(M0_data_convoluated, 3);
end

f_AVG = single(obj.M1) ./ M0_data_convoluated;
obj.f_AVG = f_AVG;
f_RMS = sqrt(single(obj.M2) ./ M0_data_convoluated);
obj.f_RMS = f_RMS;

% Flat-field correction parameters
gwRatio = params.json.FlatFieldCorrection.GWRatio;
border = params.json.FlatFieldCorrection.Border;

% Apply flat-field correction
M0_ff = flat_field_correction_ef(M0, ceil(gwRatio * numX), border);

% % Compute mean and std per frame (along spatial dimensions)
% mu = mean(M0_ff, 'all');
% sigma = std(M0_ff, 0, 'all');

% % Expand mu and sigma to match video size
% mu = repmat(mu, numX, numY, numFrames);
% sigma = repmat(sigma, numX, numY, numFrames);
%
% % Clip extreme values to ±3σ
% M0_ff(M0_ff > mu + 3 * sigma) = mu(M0_ff > mu + 3 * sigma) + 3 * sigma(M0_ff > mu + 3 * sigma);
% M0_ff(M0_ff < mu - 3 * sigma) = mu(M0_ff < mu - 3 * sigma) - 3 * sigma(M0_ff < mu - 3 * sigma);
%
obj.M0_ff = M0_ff;

end
