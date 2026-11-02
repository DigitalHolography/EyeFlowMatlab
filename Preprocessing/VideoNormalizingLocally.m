function VideoNormalizingLocally(obj, params)
% VideoNormalizingLocally
% Computes moment-based frequency estimators and flat-field-corrected M0.
%
% Outputs:
%   obj.f_AVG = M1 ./ Mnorm
%   obj.f_RMS = sqrt(M2 ./ Mnorm)
%   obj.M0_ff = flat-field-corrected M0
%
% gaussian_w:
%   Already represents a fitted spectral-width parameter.
%   Remains unchanged by this function.
%   No division by Mnorm, square root or unit conversion is applied.
%
% The existing normalization conventions are preserved.

M0 = single(obj.M0);

if isempty(M0)
    error('VideoNormalizingLocally:MissingM0', ...
    'M0 is empty.');
end

if ~isequal(size(obj.M0), size(obj.M1), size(obj.M2))
    error('VideoNormalizingLocally:MomentSizeMismatch', ...
        ['M0, M1 and M2 must have identical sizes. ', ...
     'M0: %s; M1: %s; M2: %s.'], ...
        mat2str(size(obj.M0)), ...
        mat2str(size(obj.M1)), ...
        mat2str(size(obj.M2)));
end

[numX, numY, numFrames] = size(M0);

normalizing = params.json.Preprocess.Normalizing;
alpha = normalizing.AlphaConvolveNorm;

D = (numX + numY) / 2;

if ~isscalar(alpha) || ~isreal(alpha) || ~isfinite(alpha)
    error('VideoNormalizingLocally:InvalidAlpha', ...
    'AlphaConvolveNorm must be a finite real scalar.');
end

%% Compute normalization reference

if alpha == 1
    % Spatial mean for each frame.
    Mnorm = mean(M0, [1 2]);

elseif alpha == 0
    % Pixel-wise normalization.
    Mnorm = M0;

elseif alpha == -1
    % Single reference averaged over the disk and all frames.
    mask = diskMask( ...
        numX, numY, params.json.Mask.DiaphragmRadius);

    if ~any(mask(:))
        error('VideoNormalizingLocally:EmptyNormalizationMask', ...
        'The normalization disk is empty.');
    end

    maskVideo = repmat(logical(mask), 1, 1, numFrames);
    Mnorm = mean(M0(maskVideo));

elseif alpha == -2
    % Single reference averaged outside the disk and over all frames.
    mask = diskMask( ...
        numX, numY, params.json.Mask.DiaphragmRadius + 0.2);

    outsideMask = ~logical(mask);

    if ~any(outsideMask(:))
        error('VideoNormalizingLocally:EmptyBackgroundMask', ...
        'The region outside the normalization disk is empty.');
    end

    maskVideo = repmat(outsideMask, 1, 1, numFrames);
    Mnorm = mean(M0(maskVideo));

else
    % Spatially smoothed reference, rescaled separately for each frame.
    kernelSize = round(alpha * (2 * D - 1));

    if kernelSize < 1
        error('VideoNormalizingLocally:InvalidKernelSize', ...
            ['AlphaConvolveNorm=%g gives an invalid kernel size (%d). ', ...
             'Use 0, 1, -1, -2, or a positive value giving ', ...
         'a kernel size of at least 1.'], ...
            alpha, kernelSize);
    end

    Mconv = boxSum(M0, kernelSize);

    outDir = fullfile(obj.directory, 'eyeflow');

    if ~isfolder(outDir)
        mkdir(outDir);
    end

    outFile = sprintf( ...
        '%s_alpha=%s_M0_Convolution_Norm.png', ...
        obj.filenames, num2str(alpha));

    imwrite( ...
        rescale(mean(Mconv, 3)), ...
        fullfile(outDir, outFile), ...
    'png');

    convSum = sum(Mconv, [1 2]);

    if any(~isfinite(convSum) | convSum <= 0, 'all')
        error('VideoNormalizingLocally:InvalidConvolutionReference', ...
            ['The spatial sum of convolved M0 must be finite ', ...
         'and strictly positive for every frame.']);
    end

    Mnorm = Mconv .* sum(M0, [1 2]) ./ convSum;
end

%% Optional temporal averaging of the normalization reference

if normalizing.NormTempMode
    Mnorm = mean(Mnorm, 3);
end

if any(~isfinite(Mnorm), 'all')
    error('VideoNormalizingLocally:NonFiniteNormalization', ...
    'The normalization reference contains NaN or Inf.');
end

% Preserve the existing lower bound.
Mnorm = max(Mnorm, eps('single'));

%% Moment-based estimators

obj.f_AVG = single(obj.M1) ./ Mnorm;
obj.f_RMS = sqrt(single(obj.M2) ./ Mnorm);

% Preserve the existing RMS definition.
% Negative M2 values are not silently clipped.
if ~isreal(obj.f_RMS)
    warning('VideoNormalizingLocally:ComplexRMS', ...
        ['f_RMS contains complex values because M2 contains ', ...
         'negative values. The existing square-root convention ', ...
     'has been preserved.']);
end

%% Gaussian width: intentionally unchanged

if isprop(obj, 'gaussian_w') && ~isempty(obj.gaussian_w)

    if ~isequal(size(obj.gaussian_w), size(M0))
        error('VideoNormalizingLocally:GaussianWSizeMismatch', ...
            ['gaussian_w and M0 must have identical sizes. ', ...
         'gaussian_w: %s; M0: %s.'], ...
            mat2str(size(obj.gaussian_w)), ...
            mat2str(size(M0)));
    end

    fprintf(['    - gaussian_w preserved unchanged ', ...
             '(no moment normalization or unit conversion).\n']);
end

%% Flat-field correction for display and segmentation

FF = params.json.FlatFieldCorrection;

obj.M0_ff = flat_field_correction_ef( ...
    M0, ceil(FF.GWRatio * numX), FF.Border);

end

function out = boxSum(M, n)
% Separable equivalent of conv2(M, ones(n), 'same') for each frame.

k = ones(n, 1, 'single');
out = zeros(size(M), 'single');

parfor frameIdx = 1:size(M, 3)
    out(:, :, frameIdx) = conv2( ...
        k, k', M(:, :, frameIdx), 'same');
end

end
