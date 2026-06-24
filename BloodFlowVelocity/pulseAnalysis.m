function [v_RMS_video, v_video_RGB, v_mean_RGB] = pulseAnalysis(f_video, M0_ff)
% pulseAnalysis.m computes the flow velocities from Doppler data
% Inputs:
%       VIDEOS:
%   f_video         Size: numX x numY x numFrames double (Doppler Data)
%   M0_ff     Size: numX x numY x numFrames double (Display Data)
%       IMAGES:
%   maskArtery      Size: numX x numY logical
%   maskBackground  Size: numX x numY logical
%   maskVein        Size: numX x numY logical
%   xy_barycenter   Size: 1 x 2 double
%
% Output:
%   v_RMS_video     Size: numX x numY x numFrames double

tic

% Initial Setup
ToolBox = getGlobalToolBox;
params = ToolBox.getParams;

% Parameters
exportVideos = params.exportVideos;
jsonParams = params.json;
saveFigures = jsonParams.saveFigures;
filterSignals = jsonParams.PulseAnalysis.FilterSignals;
method = jsonParams.PulseAnalysis.DifferenceMethods;
bkgfillmethod = jsonParams.PulseAnalysis.BkgFillMethod;
w = jsonParams.PulseAnalysis.LocalBackgroundWidth;
d = jsonParams.PulseAnalysis.LocalBackgroundDist;
k = jsonParams.Preprocess.InterpolationFactor;
bkg_scaler = jsonParams.PulseAnalysis.bkgScaler;
scalingFactor = 1000 * 1000 * jsonParams.PulseAnalysis.CorrectionCoeff * ...
    2 * jsonParams.PulseAnalysis.Lambda / jsonParams.PulseAnalysis.Phi;
r1 = jsonParams.SizeOfField.SmallRadiusRatio;
r2 = jsonParams.SizeOfField.BigRadiusRatio;

% Load cached data
maskArtery = ToolBox.Cache.maskArtery;
maskVein = ToolBox.Cache.maskVein;
maskVessel = ToolBox.Cache.maskVessel;
% maskChoroid = ToolBox.Cache.maskChoroid;
maskNeighbors = ToolBox.Cache.maskNeighbors;
xy_barycenter = ToolBox.Cache.xy_barycenter;

% Validating inputs
if ~any(maskArtery)
    error("Given Mask Artery is empty.")
end

% Video dimensions
[numX, numY, numFrames] = size(f_video);
dt = ToolBox.stride / ToolBox.fs / 1000;
fs = 1 / dt;

% Create section mask
x_c = xy_barycenter(1) / numX;
y_c = xy_barycenter(2) / numY;
maskSection = diskMask(numX, numY, r1, r2, 'center', [x_c, y_c]);

% Create vessel masks
maskArterySection = maskArtery & maskSection;
maskVeinSection = maskVein & maskSection;
maskVesselSection = (maskVein | maskArtery) & maskSection;

% Validating inputs
if ~any(maskArterySection)
    error("Given Mask Artery has no part within the current section.")
end

if ~any(maskVesselSection)
    error("Given Mask Vein has no part within the current section.")
end

% Section 1: Background Calculation

% Calculate background
% Background is divided between vascular and non-vascular areas
fprintf("  1. Calculating background...\n");

f_bkg = zeros(numX, numY, numFrames, 'like', f_video);

switch bkgfillmethod
    case 'maskedAverage'

        parfor frameIdx = 1:numFrames
            f_bkg(:, :, frameIdx) = single(maskedAverage(f_video(:, :, frameIdx), bkg_scaler * w * 2 ^ k, maskNeighbors, maskVessel));
        end

    case 'inpaintCoherent'
        maskVesselDilated = imdilate(maskVessel, strel('disk', (d)));

        parfor frameIdx = 1:numFrames
            f_bkg(:, :, frameIdx) = single(inpaintCoherent(f_video(:, :, frameIdx), maskVesselDilated));
        end

    otherwise
        error("Unknown background fill method: %s", bkgfillmethod);

end

% Time vector for plotting
t = ToolBox.Cache.t;

% Calculate and plot artery signals
if saveFigures
    % Colors for plotting
    cBlack = [0 0 0];
    cArtery = [255 22 18] / 255;
    cVein = [18 23 255] / 255;

    % Artery signals
    f_artery = squeeze(sum(f_video .* maskArterySection, [1, 2]) / nnz(maskArterySection));
    f_artery_bkg = squeeze(sum(f_bkg .* maskArterySection, [1, 2]) / nnz(maskArterySection));
    f_vein = squeeze(sum(f_video .* maskVeinSection, [1, 2]) / nnz(maskVeinSection));
    f_vein_bkg = squeeze(sum(f_bkg .* maskVeinSection, [1, 2]) / nnz(maskVeinSection));
    f_vessel_bkg = squeeze(sum(f_bkg .* maskVesselSection, [1, 2]) / nnz(maskVesselSection));

    graphSignal('f_artery', ...
        t, f_artery, '-', cArtery, ...
        t, f_artery_bkg, '--', cBlack, ...
        'xlabel', 'Time(s)', 'ylabel', 'frequency (kHz)', ...
        'Legend', {'arteries', 'background'}, 'ylim', [12.5 15.5]);

    graphSignal('f_vein', ...
        t, f_vein, '-', cVein, ...
        t, f_vein_bkg, '--', cBlack, ...
        'xlabel', 'Time(s)', 'ylabel', 'frequency (kHz)', ...
        'Legend', {'veins', 'background'});

    graphSignal('f_vessel', ...
        t, f_artery, '-', cArtery, ...
        t, f_vein, '-', cVein, ...
        t, f_vessel_bkg, '--', cBlack, ...
        'xlabel', 'Time(s)', 'ylabel', 'frequency (kHz)', ...
        'Legend', {'arteries', 'veins', 'background'});

    LocalBackground_in_vessels = mean(f_bkg, 3);

    % LocalBackground_in_vessels(maskNeighbors) = mean(LocalBackground_in_vessels(maskNeighbors),"all");
    createHeatmap(LocalBackground_in_vessels, 'background in vessels', ...
        'background RMS frequency (kHz)', fullfile(ToolBox.path_png, sprintf("%s_f_bkg_map.png", ToolBox.folder_name)), [7 19], 20);
end

if exportVideos
    f_bkg_rescale = rescale(f_bkg);
    writeGifOnDisc(imresize(f_bkg_rescale, 0.5), "f_bkg");
end

fprintf("    1. Background calculation took %ds\n", round(toc));

% Section 2: Difference Calculation and Velocity Computation

tic;

% Calculate difference based on selected method
switch method
    case 0 % SIGNED DIFFERENCE FIRST
        tmp = f_video .^ 2 - f_bkg .^ 2;
        df = sign(tmp) .* sqrt(abs(tmp));
        clear tmp;
    case 1 % DIFFERENCE FIRST
        tmp = f_video .^ 2 - f_bkg .^ 2;
        tmp = tmp .* (tmp > 0);
        df = sqrt(tmp);
        clear tmp;
    otherwise % DIFFERENCE LAST
        df = f_video - f_bkg;
end

clear f_bkg

% Process artery signals and detect outliers
df_artery = df .* maskArterySection;
df_artery_signal = squeeze(sum(df_artery, [1, 2], 'omitnan') / nnz(maskArterySection))';
outlier_frames_mask = isoutlier(df_artery_signal, "movmedian", 10);

% Process vein signals if enabled
df_vein = df .* maskVeinSection;
df_vein_signal = squeeze(sum(df_vein, [1, 2], 'omitnan') / nnz(maskVeinSection))';
outlier_frames_mask = outlier_frames_mask | isoutlier(df_vein_signal, "movmedian", 10);

% Interpolate outlier frames
df = interpolateOutlierFrames(df, outlier_frames_mask');

if saveFigures

    graphSignal('df_vessel', ...
        t, df_artery_signal, '-', cArtery, ...
        t, df_vein_signal, '-', cVein, ...
        'xlabel', 'Time(s)', 'ylabel', 'frequency (kHz)');

end

% background in vessels
if saveFigures

    % Delta f in vessels
    in_vessels = mean(df, 3) .* maskVesselSection;
    createHeatmap(in_vessels, 'Delta f in vessels', ...
        'Delta Doppler RMS frequency (kHz)', fullfile(ToolBox.path_png, sprintf("%s_df_map_vessel.png", ToolBox.folder_name)));

    % Delta f
    in_vessels = mean(df, 3) .* maskVesselSection + (mean(f_video, 3) - mean(f_video, 'all')) .* ~maskVesselSection;
    createHeatmap(in_vessels, 'Delta f in vessels', ...
        'Delta Doppler RMS frequency (kHz)', fullfile(ToolBox.path_png, sprintf("%s_df_map.png", ToolBox.folder_name)));

    velocityIm(mean(df, 3) .* maskVesselSection, maskArtery | maskVein, turbo, 'df_vessel', colorbarOn = true, LabelName = 'kHz');

    % Raw RMS frequency map
    raw_map = squeeze(mean(f_video, 3));
    createHeatmap(raw_map, 'RMS frequency map RAW', ...
        'RMS frequency (kHz)', fullfile(ToolBox.path_png, sprintf("%s_f_map.png", ToolBox.folder_name)), [7 19], 20);

end

% Export videos if enabled
if exportVideos
    f_video_rescale = rescale(f_video);
    writeGifOnDisc(imresize(f_video_rescale, 0.5), "f");
end

% Calculate velocity
v_RMS_video = scalingFactor * df;

% COMMENT
% v_negative_velocity = v_RMS_video < 0;
% writeGifOnDisc(v_negative_velocity, "v_negative_velocity", 0.04);

clear df

VelocityStatisticalOutputs(v_RMS_video, maskArtery, maskVein, maskArterySection, maskVeinSection);

% Process artery velocity signals
v_artery = v_RMS_video .* maskArterySection;
v_artery(~maskArterySection) = NaN;
v_artery_signal = squeeze(sum(v_artery, [1, 2], 'omitnan') / nnz(maskArterySection))';

% Process vein velocity signals
v_vein = v_RMS_video .* maskVeinSection;
v_vein(~maskVeinSection) = NaN;
v_vein_signal = squeeze(sum(v_vein, [1, 2], 'omitnan') / nnz(maskVeinSection))';

% Filter signals
if filterSignals
    [b, a] = butter(4, 15 / (fs / 2), 'low');
    v_artery_signal = filtfilt(b, a, v_artery_signal);
    %v_vein_signal = filtfilt(b, a, v_vein_signal);

end

if saveFigures
    % Plot velocity signals
    graphSignal('v_vessel', ...
        t, v_artery_signal, '-', cArtery, ...
        t, v_vein_signal, '-', cVein, ...
        'Title', 'average velocity in arteries and veins', 'xlabel', 'Time(s)', 'ylabel', 'Velocity (mm/s)', 'ylim', [-1.5 46]);
    graphSignal('v_artery', ...
        t, v_artery_signal, '-', cArtery, ...
        'Title', 'average velocity in arteries', 'xlabel', 'Time(s)', 'ylabel', 'Velocity (mm/s)', 'ylim', [-1.5 46]);
end

ToolBox.Output.add('Time', t, 's', h5path = '/Meta/Time');
ToolBox.Output.add('ArterialVelocity', v_artery_signal, 'mm/s', h5path = '/Artery/Velocity/VelocitySignal');
ToolBox.Output.add('VenousVelocity', v_vein_signal, 'mm/s', h5path = '/Vein/Velocity/VelocitySignal');

ToolBox.Cache.ArterialVelocity = v_artery_signal;
ToolBox.Cache.VeinVelocity = v_vein_signal;

fprintf("    2. Difference calculation and velocity computation took %ds\n", round(toc));

% Section 3: Systole/Diastole Analysis

tic;

% Find systole indices

[sys_idx_list, pulse_artery, sys_max_list, sys_min_list] = find_systole_index(v_artery_signal);

[M0_Systole_img, M0_Diastole_img, sys_idx, dias_idx] = compute_diasys(v_RMS_video, maskArterySection);

ToolBox.Output.add("sysIdxList", sys_idx_list,       h5path = "/Artery/Velocity/SystolicAccelerationPeakIndexes");

% ToolBox.Output.add("M0_ff_img_systole",M0_Systole_img);
% ToolBox.Output.add("M0_ff_img_diastole",M0_Diastole_img);

if saveFigures
    v_RMS_img = mean(v_RMS_video, 3, 'omitnan');
    diasys_diff = M0_Systole_img - M0_Diastole_img;
    RGBdiasys = labDuoImage(rescale(v_RMS_img), diasys_diff);
    try
    saveMaskImage(RGBdiasys, 'vessel_21_diasys_diff.png', isStep = true);
    end
end

% Process heart beat data if enough cycles detected
if numel(sys_idx_list) >= 2 && numel(sys_max_list) >= 2 && numel(sys_min_list) >= 2
    heartRates = 60 ./ (diff(sys_idx_list) * dt);

    % Calculate statistics
    HeartBeat = mean(heartRates);
    HeartBeatSTE = std(heartRates);
    TimeToPeakSystole = mean((sys_max_list - sys_idx_list'), "omitnan") * dt;
    TimeToPeakSystoleSTE = std((sys_max_list - sys_idx_list'), "omitnan") * dt;
    TimeToMinimumDiastole = mean((sys_min_list - sys_idx_list'), "omitnan") * dt;
    TimeToMinimumDiastoleSTE = std((sys_min_list - sys_idx_list'), "omitnan") * dt;
    TimeToPeakSystoleFromMinimumDiastole = abs(TimeToMinimumDiastole) + TimeToPeakSystole;
    TimeToPeakSystoleFromMinimumDiastoleSTE = (TimeToPeakSystoleSTE + TimeToMinimumDiastoleSTE) / 2;

    % Interpolate full pulse for additional analysis
    Ninterp = 1000;
    interpFullPulse = interpSignal(pulse_artery, sys_idx_list, Ninterp);
    pMax = max(interpFullPulse);
    pMin = min(interpFullPulse);
    pRange = pMax - pMin;

    % Find descent time
    firstIndex = find(interpFullPulse - (pMin + 0.05 * pRange) < 0, 1);
    TimePeakToDescent = firstIndex / Ninterp * mean(diff(sys_idx_list')) * dt;

    % Store output
    ToolBox.Output.add('HeartBeat', HeartBeat, 'bpm', HeartBeatSTE, h5path = '/Artery/WaveformAnalysis/HeartBeat');
    ToolBox.Output.add('SystoleIndices', sys_idx_list, '', h5path = '/Artery/WaveformAnalysis/SystoleIndices');
    ToolBox.Output.add('ArterySystoleMaxIndices', sys_max_list, '', h5path = '/Artery/WaveformAnalysis/ArterySystoleMaxIndices');
    ToolBox.Output.add('ArteryDiastoleMinIndices', sys_min_list, '', h5path = '/Artery/WaveformAnalysis/ArteryDiastoleMinIndices');
    ToolBox.Output.add('ArteryTimeToMaxIncrease', 0, 's', 0, h5path = '/Artery/WaveformAnalysis/ArteryTimeToMaxIncrease');
    ToolBox.Output.add('ArteryTimeToPeakSystole', TimeToPeakSystole, 's', TimeToPeakSystoleSTE, h5path = '/Artery/WaveformAnalysis/ArteryTimeToPeakSystole');
    ToolBox.Output.add('ArteryTimeToMinDiastole', TimeToMinimumDiastole, 's', TimeToMinimumDiastoleSTE, h5path = '/Artery/WaveformAnalysis/ArteryTimeToMinDiastole');
    ToolBox.Output.add('ArteryTimeToPeakSystoleFromDiastole', TimeToPeakSystoleFromMinimumDiastole, 's', TimeToPeakSystoleFromMinimumDiastoleSTE, h5path = '/Artery/WaveformAnalysis/TimeToPeakSystoleFromMinimumDiastole');
    ToolBox.Output.add('ArteryTimeToDescent', TimePeakToDescent, 's', h5path = '/Artery/WaveformAnalysis/TimeToDescent');
    ToolBox.Output.add('ArteryTimePeakToDescent', TimePeakToDescent + TimeToPeakSystole, 's', h5path = '/Artery/WaveformAnalysis/TimePeakToDescent');

    % Log detailed results
    logDetailedResults(ToolBox, HeartBeat, sys_idx_list, sys_max_list, sys_min_list, ...
        TimeToMinimumDiastole, TimeToPeakSystoleFromMinimumDiastole);
else
    warning('There isn''t enough systoles for analysis.');
end

fprintf("    3. Systole/diastole analysis took %ds\n", round(toc));

% Section 4: Resistivity Index and Waveform Analysis
tic;

% Calculate resistivity index
ArterialResistivityIndex(v_artery_signal, sys_idx_list, 'v_artery', ForceFigure = true);
try
ArterialResistivityIndex(v_vein_signal, sys_idx_list, 'v_vein', ForceFigure = true);
end
% Perform waveform analysis
v_artery_interp = ArterialWaveformAnalysis(v_artery_signal, sys_idx_list, 128, 'v_artery');
try
v_vein_interp = VenousWaveformAnalysis(v_vein_signal, sys_idx_list, 128, 'v_vein');
end
% Correlation analysis
try
arterial_venous_correlation(v_artery_signal, -v_vein_signal);

% Delay analysis
arterial_venous_delay(v_artery_interp, v_vein_interp);
end
fprintf("    4. Resistivity and waveform analysis took %ds\n", round(toc()));

% Section 5: Visualization and Output Generation

tic;

v_video_RGB = zeros(numX, numY, 3, numFrames, 'uint8');
v_mean_RGB = zeros(numX, numY, 3, 'uint8');

if saveFigures
    % Precompute masks for visualization
    maskAV = maskArtery & maskVein;
    maskArterySection = maskArtery & maskSection & ~maskAV;
    maskVeinSection = maskVein & maskSection & ~maskAV;

    % Generate flow maps
    [v_video_RGB, v_mean_RGB] = flowMap(v_RMS_video, maskSection, maskArtery, maskVein, M0_ff, xy_barycenter);

    % Generate histograms
    histoVideoArtery = VelocityHistogram(v_RMS_video, maskArterySection, 'artery');
    try
    histoVideoVein = VelocityHistogram(v_RMS_video, maskVeinSection, 'vein');
    
    % Generate combined visualizations
    createCombinedVisualizations(v_mean_RGB, histoVideoArtery, histoVideoVein, ...
        v_video_RGB, numFrames, exportVideos, ToolBox);
    end
end

fprintf("    5. Visualization and output generation took %ds\n", round(toc));

close all

% Save Intermediate Results in cache
ToolBox.Cache.sysIdxList = sys_idx_list;
ToolBox.Cache.sysIdx = sys_idx;
ToolBox.Cache.diasIdx = dias_idx;

end

function logDetailedResults(ToolBox, HeartBeat, sysIdxList, sysMaxList, sysMinList, ...
    TimeToMinimumDiastole, TimeToPeakSystoleFromMinimumDiastole)
% Helper function to log detailed results
fileID = fopen(fullfile(ToolBox.path_txt, strcat(ToolBox.folder_name, '_main_outputs.txt')), 'a');
fprintf(fileID, 'Heart beat: %f (bpm) \r\n', HeartBeat);
fprintf(fileID, 'Systole Indices: %s \r\n', strcat('[', sprintf("%d,", sysIdxList), ']'));
fprintf(fileID, 'Number of Cycles: %d \r\n', numel(sysIdxList) - 1);
fprintf(fileID, 'Max Systole Indices: %s \r\n', strcat('[', sprintf("%d,", sysMaxList), ']'));
fprintf(fileID, 'Min Systole Indices: %s \r\n', strcat('[', sprintf("%d,", sysMinList), ']'));
fprintf(fileID, 'Time diastolic min to systolic max derivative (ms): %f \r\n', -TimeToMinimumDiastole);
fprintf(fileID, 'Time diastolic min to systolic max (ms): %f \r\n', TimeToPeakSystoleFromMinimumDiastole);
fclose(fileID);
end

function createHeatmap(data, titleStr, cbarStr, filename, climVals, cbarFontSize)
% createHeatmap
%
% climVals:
%   Optional [min max] values to force color scaling.
%   Pass [] to use automatic scaling.
%
% cbarFontSize:
%   Optional font size for colorbar text/title.
%   Default = 12.

    if nargin < 5 || isempty(climVals)
        climVals = [];
    end
    if nargin < 6 || isempty(cbarFontSize)
        cbarFontSize = 12;
    end

    % Main heatmap
    % ---------------------------------------------------------------------
    f = figure("Visible", "off");
    f.Position = [1100 485 350 420];
    imagesc(data);
    colormap gray
    if ~isempty(climVals)
        clim(climVals);
    end
    title(titleStr);

    fontsize(gca, 12, "points");
    set(gca, 'LineWidth', 2);
    c = colorbar('southoutside');
    c.Label.String = cbarStr;
    c.Label.FontSize = cbarFontSize;
    axis off
    axis image
    rangeVals = clim;
    imwrite(rescale(data), filename);
    % ---------------------------------------------------------------------
    % Colorbar-only figure
    % ---------------------------------------------------------------------
    colorfig = figure("Visible", "off");
    colorfig.Units = 'normalized';

    colormap gray

    cbar = colorbar('north');
    clim(rangeVals);
    set(gca, 'Visible', false);
    set(gca, 'LineWidth', 3);
    cbar.Position = [0.10 0.3 0.81 0.35];
    colorfig.Position(4) = 0.1000;
    fontsize(gca, cbarFontSize, "points");
    colorTitleHandle = get(cbar, 'Title');
    set(colorTitleHandle, ...
        'String', cbarStr, ...
        'FontSize', cbarFontSize);
    % Optional: also scale tick labels
    cbar.FontSize = cbarFontSize;
    [pathstr, name, ext] = fileparts(filename);
    exportgraphics( ...
        gca, ...
        fullfile(pathstr, strrep(name, '_map', '_colorBar') + ext) ...
    );
    exportgraphics( ...
        gca, ...
        fullfile( ...
            strrep(pathstr, 'png', 'eps'), ...
            strrep(name, '_map', '_colorBar') + ".eps" ...
        ) ...
    );
    close([f, colorfig]);
end

function createCombinedVisualizations(v_mean_RGB, histoVideoArtery, histoVideoVein, ...
    v_video_RGB, numFrames, exportVideos, ToolBox)
% Helper function to create combined visualizations

% Determine sizes
[numX_fig, ~, ~, ~] = size(histoVideoArtery);

% Create averaged visualization
v_mean_RGB4Gif = rescale(imresize3(v_mean_RGB, [numX_fig * 2 numX_fig * 2 3]));
combinedImg = cat(2, v_mean_RGB4Gif, cat(1, histoVideoArtery(:, :, :, end), histoVideoVein(:, :, :, end)));

imwrite(combinedImg, fullfile(ToolBox.path_png, sprintf("%s_%s", ToolBox.folder_name, 'AVGflowVideoCombined.png')));

% Create video visualization if exporting
if exportVideos

    v_video_RGB4Gif = zeros(numX_fig * 2, numX_fig * 2, 3, numFrames, 'like', v_video_RGB);
    v_video_RGB4Gif(:, :, 1, :) = imresize3(squeeze(v_video_RGB(:, :, 1, :)), [numX_fig * 2 numX_fig * 2 numFrames]);
    v_video_RGB4Gif(:, :, 2, :) = imresize3(squeeze(v_video_RGB(:, :, 2, :)), [numX_fig * 2 numX_fig * 2 numFrames]);
    v_video_RGB4Gif(:, :, 3, :) = imresize3(squeeze(v_video_RGB(:, :, 3, :)), [numX_fig * 2 numX_fig * 2 numFrames]);
    combinedGifs = cat(2, v_video_RGB4Gif, cat(1, uint8(rescale(histoVideoArtery, 0, 255)), uint8(rescale(histoVideoVein, 0, 255))));

    writeGifOnDisc(combinedGifs, "velocityHistogramCombined", 0.04);
end

end
