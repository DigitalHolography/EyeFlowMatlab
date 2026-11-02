function [v_video_RGB, v_mean_RGB] = bloodFlowVelocity(v_RMS_video, maskArtery, maskVein, f_video, xy_barycenter)

close all
ToolBox = getGlobalToolBox;
params = ToolBox.getParams;
exportVideos = params.exportVideos;
saveFigures = params.saveFigures;

% Rescale once
[numX, numY, numFrames] = size(v_RMS_video);
x_c = xy_barycenter(1) / numX;
y_c = xy_barycenter(2) / numY;
r1 = params.json.SizeOfField.SmallRadiusRatio;
r2 = params.json.SizeOfField.BigRadiusRatio;
maskSection = diskMask(numX, numY, r1, r2, center = [x_c, y_c]);

% Precompute masks
maskAV = maskArtery & maskVein;
maskArterySection = maskArtery & maskSection & ~maskAV;
maskVeinSection = maskVein & maskSection & ~maskAV;

ArterySection_pxl = sum(maskArterySection(:));
VeinSection_pxl = sum(maskVeinSection(:));
RemainingSection_pxl = sum(maskSection & ~maskAV, 'all');

ToolBox.Output.add('ArterySelNbPxl', ArterySection_pxl, h5path = '/Artery/Segmentation/NumberOfPixelsInSection');
ToolBox.Output.add('VeinSelNbPxl', VeinSection_pxl, h5path = '/Vein/Segmentation/NumberOfPixelsInSection');
ToolBox.Output.add('RemainingSelNbPxl', RemainingSection_pxl, h5path = '/ArteryVein/Segmentation/RemainingSelNbPxl');

if saveFigures
    % 1) VELOCITY VIDEO
    tVelocityVideo = tic;

    [v_video_RGB, v_mean_RGB] = flowMap(v_RMS_video, f_video, maskSection, maskArtery, maskVein, xy_barycenter, ToolBox);

    fprintf("- Velocity Map Timing : %ds\n", round(toc(tVelocityVideo)))

    % 2) HISTOGRAM

    histoVideoArtery = VelocityHistogram(v_RMS_video, maskArterySection, 'artery');
    histoVideoVein = VelocityHistogram(v_RMS_video, maskVeinSection, 'vein');

    % 3) COMBINED

    [numX_fig, ~, ~, ~] = size(histoVideoArtery);

    v_mean_RGB4Gif = rescale(imresize3(v_mean_RGB, [numX_fig * 2 numX_fig * 2 3]));

    if exportVideos

        imwrite(cat(2, v_mean_RGB4Gif, ...
            cat(1, mat2gray(histoVideoArtery(:, :, :, end)), mat2gray(histoVideoVein(:, :, :, end)))), ...
            fullfile(ToolBox.path_png, sprintf("%s_%s", ToolBox.folder_name, 'AVGflowVideoCombined.png')))

        v_video_RGB4Gif(:, :, 1, :) = mat2gray(imresize3(squeeze(v_video_RGB(:, :, 1, :)), [numX_fig * 2 numX_fig * 2 numFrames]));
        v_video_RGB4Gif(:, :, 2, :) = mat2gray(imresize3(squeeze(v_video_RGB(:, :, 2, :)), [numX_fig * 2 numX_fig * 2 numFrames]));
        v_video_RGB4Gif(:, :, 3, :) = mat2gray(imresize3(squeeze(v_video_RGB(:, :, 3, :)), [numX_fig * 2 numX_fig * 2 numFrames]));

        combinedGifs = cat(2, v_video_RGB4Gif, cat(1, mat2gray(histoVideoArtery), mat2gray(histoVideoVein)));
        writeGifOnDisc(mat2gray(combinedGifs), "velocityHistogramCombined", 0.04);

    else

        imwrite(cat(2, v_mean_RGB4Gif, cat(1, mat2gray(histoVideoArtery), mat2gray(histoVideoVein))), fullfile(ToolBox.path_png, sprintf("%s_%s", ToolBox.folder_name, 'AVGflowVideoCombined.png')))

    end

    close all

else
    v_video_RGB = [];
    v_mean_RGB = [];
end

end
