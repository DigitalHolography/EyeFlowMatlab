function [v_video_RGB, v_mean_RGB] = flowMap(v_video, f_video, maskSection, maskArtery, maskVein, xy_barycenter)
% Generate flow map images and videos for blood flow velocity analysis
%
% inputs:
%   v_video: 3D array of blood flow velocity data (X x Y x Frames)
%   maskSection: 2D logical array defining the section of interest
%   maskArtery: 2D logical array defining artery regions
%   maskVein: 2D logical array defining vein regions
%   xy_barycenter: 1x2 array defining the center coordinates [x, y]
%
% outputs:
%   v_video_RGB: 4D uint8 array of RGB flow map video (X x Y x 3 x Frames)
%   v_mean_RGB: 3D uint8 array of RGB flow map image (X x Y x 3)

ToolBox = getGlobalToolBox;
params = ToolBox.getParams;
exportVideos = params.exportVideos;

[numX, numY, numFrames] = size(v_video);

% Display copies only: do not modify cached measurement data.
M0_display = improveDisplayContrast( ...
    f_video, ...
    diameterRatio = 0.90, ...
    gamma = 1, ...
    perFrame = false, ...
    blankOutside = false);

M0_mean_display = mean(f_video, 3, 'omitnan');

% Precompute constants
x_c = xy_barycenter(1) / numX;
y_c = xy_barycenter(2) / numY;
r1 = params.json.SizeOfField.BigRadiusRatio;
r2 = params.json.SizeOfField.SmallRadiusRatio;
w = 0.01;

% Precompute circles
circle1 = diskMask(numX, numY, r1, r1 + w, center = [x_c, y_c]);
circle2 = diskMask(numX, numY, r2 - w, r2, center = [x_c, y_c]);
circles = circle1 | circle2;

% Precompute colormaps
cmapArtery = ToolBox.Cache.cmapArtery;
cmapVein = ToolBox.Cache.cmapVein;
cmapAV = ToolBox.Cache.cmapAV;

% Precompute v_rescaled
v_max = max(v_video(maskSection));
v_min = 0;
v_rescaled = abs(v_video);
v_rescaled = (v_rescaled - v_min) / v_max;

% Precompute v_mean and v_mean_rescaled
v_mean = squeeze(mean(v_video, 3));
v_mean_rescaled = squeeze(mean(v_rescaled, 3));
v_video_RGB = zeros(numX, numY, 3, numFrames, 'uint8');

% Velocity Images
velocityIm(v_mean, maskArtery & maskSection, cmapArtery, 'v_Artery', colorbarOn = true);
velocityIm(v_mean, maskVein & maskSection, cmapVein, 'v_Vein', colorbarOn = true);
velocityIm(v_mean, (maskArtery | maskVein) & maskSection, turbo, 'v_Vessel', colorbarOn = true);

% Precompute masks
maskAV = maskArtery & maskVein;
maskArtery = maskArtery & ~maskAV;
maskVein = maskVein & ~maskAV;

% velocity Colorbars of the gif
velocityColorbar(cmapArtery, v_min, v_max, 'v_Artery');
velocityColorbar(cmapVein, v_min, v_max, 'v_Vein');

% Average Image
v_mean_RGB = flowMapImg( ...
    rescale(v_mean_rescaled), ...
    {maskArtery, maskVein, maskAV}, ...
    {cmapArtery, cmapVein, cmapAV}, ...
    background = rescale(M0_mean_display), ...
    circles = circles);
imwrite(v_mean_RGB, fullfile(ToolBox.path_png, sprintf("%s_%s", ToolBox.folder_name, 'v_map.png')))

% Gif frame generation
if exportVideos

    parfor frameIdx = 1:numFrames
        v_video_RGB(:, :, :, frameIdx) = flowMapImg( ...
            v_rescaled(:, :, frameIdx), ...
            {maskArtery, maskVein, maskAV}, ...
            {cmapArtery, cmapVein, cmapAV}, ...
            background = M0_display(:, :, frameIdx), ...
            circles = circles);
    end

end

if exportVideos
    writeGifOnDisc(v_video_RGB, "flowMap");
end

end
