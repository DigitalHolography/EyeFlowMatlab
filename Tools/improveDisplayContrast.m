function Y = improveDisplayContrast(X, opt)
% Improve contrast for display only.
%
% Input:
%   X: grayscale image or X x Y x T cube.
%
% Output:
%   Y: single array in [0, 1], with the same size as X.
%
% Contrast limits are estimated inside a mask or a centered disk.
% Numerical input data are not modified.
%
% Percentiles use the [0, 100] convention.

arguments
    X {mustBeNumeric, mustBeReal}
    opt.mask = []
    opt.diameterRatio (1, 1) double = 0.90
    opt.percentiles (1, 2) double = [0.05 99.95]
    opt.gamma (1, 1) double = 1
    opt.perFrame (1, 1) logical = false
    opt.blankOutside (1, 1) logical = true
end

if isempty(X) || ndims(X) > 3
    error('improveDisplayContrast:InvalidInput', ...
    'X must be a nonempty grayscale image or X x Y x T cube.');
end

if any(~isfinite(opt.percentiles)) || ...
        opt.percentiles(1) < 0 || ...
        opt.percentiles(2) > 100 || ...
        opt.percentiles(1) >= opt.percentiles(2)
    error('improveDisplayContrast:InvalidPercentiles', ...
    'Percentiles must satisfy 0 <= low < high <= 100.');
end

if ~isfinite(opt.gamma) || opt.gamma <= 0
    error('improveDisplayContrast:InvalidGamma', ...
    'gamma must be finite and positive.');
end

X = single(X);

[nRows, nCols, nFrames] = size(X);

if isempty(opt.mask)

    if ~isfinite(opt.diameterRatio) || ...
            opt.diameterRatio <= 0 || opt.diameterRatio > 1
        error('improveDisplayContrast:InvalidDiameterRatio', ...
        'diameterRatio must be in (0, 1].');
    end

    [xx, yy] = meshgrid(1:nCols, 1:nRows);

    cx = (nCols + 1) / 2;
    cy = (nRows + 1) / 2;

    radius = opt.diameterRatio * min(nRows, nCols) / 2;

    mask = (xx - cx) .^ 2 + (yy - cy) .^ 2 <= radius ^ 2;
else

    if ~isequal(size(opt.mask), [nRows nCols])
        error('improveDisplayContrast:MaskSizeMismatch', ...
        'The mask must match the spatial dimensions of X.');
    end

    mask = logical(opt.mask);
end

if ~any(mask, 'all')
    error('improveDisplayContrast:EmptyMask', ...
    'The contrast-estimation mask is empty.');
end

Y = zeros(size(X), 'single');

% Fixed limits across time by default.
if ~opt.perFrame
    reference = X;
    reference(~isfinite(reference)) = NaN;

    values = reference(mask & isfinite(reference));

    if isempty(values)
        error('improveDisplayContrast:NoValidReference', ...
        'No finite reference values inside the contrast mask.');
    end

    limits = prctile(double(values), opt.percentiles);
end

for frameIdx = 1:nFrames
    frame = X(:, :, frameIdx);

    if opt.perFrame
        values = frame(mask & isfinite(frame));

        if isempty(values)
            continue
        end

        limits = prctile(double(values), opt.percentiles);
    end

    if limits(2) <= limits(1)
        continue
    end

    frameDisplay = ...
        (frame - single(limits(1))) ./ ...
        single(limits(2) - limits(1));

    frameDisplay = min(max(frameDisplay, 0), 1);
    frameDisplay = frameDisplay .^ single(opt.gamma);

    frameDisplay(~isfinite(frameDisplay)) = 0;

    if opt.blankOutside
        frameDisplay(~mask) = 0;
    end

    Y(:, :, frameIdx) = frameDisplay;
end

end
