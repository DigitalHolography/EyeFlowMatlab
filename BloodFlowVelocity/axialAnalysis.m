function axialAnalysis(f_AVG)
% Initial Setup
ToolBox = getGlobalToolBox;
params = ToolBox.getParams;
saveFigures = params.saveFigures;

if ~isfolder(fullfile(ToolBox.path_png, "axialAnalysis")) && saveFigures
    mkdir(fullfile(ToolBox.path_png, "axialAnalysis"));
end

if ~isfolder(fullfile(ToolBox.path_eps, "axialAnalysis")) && saveFigures
    mkdir(fullfile(ToolBox.path_eps, "axialAnalysis"));
end

%% CHANGE THIS
% scalingFactor = 1000 * 1000 * 2 * params.json.PulseAnalysis.Lambda / sin(params.json.PulseAnalysis.Phi);
[numX, numY, numFrames] = size(f_AVG);

%% Section 1: Background Calculation

tic

% Get masks from ToolBox
maskArtery = ToolBox.Cache.maskArtery;
maskVein = ToolBox.Cache.maskVein;
maskVessel = ToolBox.Cache.maskVessel;
maskNeighbors = ToolBox.Cache.maskNeighbors;
maskCRA = ToolBox.Cache.maskCRA2;
maskCRV = ToolBox.Cache.maskCRV2;

% Create section mask
x_c = ToolBox.Cache.xy_barycenter(1) / numX;
y_c = ToolBox.Cache.xy_barycenter(2) / numY;
r1 = params.json.SizeOfField.SmallRadiusRatio;
r2 = params.json.SizeOfField.BigRadiusRatio;
maskSection = diskMask(numX, numY, r1, r2, 'center', [x_c, y_c]);

% Create vessel masks
maskArterySection = maskArtery & maskSection;
maskVeinSection = maskVein & maskSection;
maskVesselSection = maskVessel & maskSection;

% Validating inputs
if ~any(maskArterySection)
    error("Given Mask Artery has no part within the current section.")
end

if ~any(maskVesselSection)
    error("Given Mask Vein has no part within the current section.")
end

% Time vector for plotting
t = ToolBox.Cache.t;

% Colors for plotting
cBlack = [0 0 0];
cArtery = [255 22 18] / 255;
cVein = [18 23 255] / 255;
cCRA = [1 0 1];
cCRV = [1 0 1];

f_bkg = zeros(numX, numY, numFrames, 'single');

% Background calculation parameters
w = params.json.PulseAnalysis.LocalBackgroundWidth;
k = params.json.Preprocess.InterpolationFactor;
bkg_scaler = params.json.PulseAnalysis.bkgScaler;

% Calculate background
parfor frameIdx = 1:numFrames
    f_bkg(:, :, frameIdx) = single(maskedAverage(f_AVG(:, :, frameIdx), bkg_scaler * w * 2 ^ k, maskNeighbors, maskVessel));
end

% Calculate difference based on selected method
switch 315
    case 0 % SIGNED DIFFERENCE FIRST
        tmp = f_AVG .^ 2 - f_bkg .^ 2;
        df = sign(tmp) .* sqrt(abs(tmp));
    case 1 % DIFFERENCE FIRST
        tmp = f_AVG .^ 2 - f_bkg .^ 2;
        tmp = tmp .* (tmp > 0);
        df = sqrt(tmp);
    otherwise % DIFFERENCE LAST
        df = f_AVG - f_bkg;
end

% Calculate and plot artery signals
f_artery = squeeze(sum(f_AVG .* maskArterySection, [1, 2]) / nnz(maskArterySection));
f_artery_bkg = squeeze(sum(f_bkg .* maskArterySection, [1, 2]) / nnz(maskArterySection));
f_vein = squeeze(sum(f_AVG .* maskVeinSection, [1, 2]) / nnz(maskVeinSection));
f_vein_bkg = squeeze(sum(f_bkg .* maskVeinSection, [1, 2]) / nnz(maskVeinSection));
f_vessel_bkg = squeeze(sum(f_bkg .* maskVesselSection, [1, 2]) / nnz(maskVesselSection));

f_CRA = squeeze(sum(f_AVG .* maskCRA, [1, 2]) / nnz(maskCRA));
f_CRV =  squeeze(sum(f_AVG .* maskCRV, [1, 2]) / nnz(maskCRV));

graphSignal('f_axial_artery', ...
    t, f_artery, '-', cArtery, ...
    t, f_artery_bkg, '--', cBlack, ...
    'xlabel', 'Time(s)', 'ylabel', 'frequency (kHz)', ...
    'Legend', {'arteries', 'background'}, 'parent_folder', "axialAnalysis", 'ylim', [-10,10]);

graphSignal('f_axial_CRA_artery', ...
    t, f_CRA, '-', cCRA, ...
    t, f_artery, '-', cArtery, ...
    t, f_artery_bkg, '--', cBlack, ...
    'xlabel', 'Time(s)', 'ylabel', 'frequency (kHz)', ...
    'Legend', {'CRA', 'arteries', 'background'}, 'parent_folder', "axialAnalysis");

graphSignal('f_axial_vein', ...
    t, f_vein, '-', cVein, ...
    t, f_vein_bkg, '--', cBlack, ...
    'xlabel', 'Time(s)', 'ylabel', 'frequency (kHz)', ...
    'Legend', {'veins', 'background'}, 'parent_folder', "axialAnalysis");

graphSignal('f_axial_CRV_vein', ...
    t, f_CRV, '-', cCRV, ...
    t, f_vein, '-', cVein, ...
    t, f_vein_bkg, '--', cBlack, ...
    'xlabel', 'Time(s)', 'ylabel', 'frequency (kHz)', ...
    'Legend', {'CRV', 'veins', 'background'}, 'parent_folder', "axialAnalysis");

graphSignal('f_axial_vessel', ...
    t, f_artery, '-', cArtery, ...
    t, f_vein, '-', cVein, ...
    t, f_vessel_bkg, '--', cBlack, ...
    'xlabel', 'Time(s)', 'ylabel', 'frequency (kHz)', ...
    'Legend', {'arteries', 'veins', 'background'}, 'parent_folder', "axialAnalysis");

% Calculate velocity
% v_axial_video = scalingFactor * df;
df_artery = df .* maskArterySection;
df_artery_signal = squeeze(sum(df_artery, [1, 2], 'omitnan') / nnz(maskArterySection))';
df_vein = df .* maskVeinSection;
df_vein_signal = squeeze(sum(df_vein, [1, 2], 'omitnan') / nnz(maskVeinSection))';

graphSignal('df_axial_vessel', ...
    t, df_artery_signal, '-', cArtery, ...
    t, df_vein_signal, '-', cVein, ...
    'xlabel', 'Time(s)', 'ylabel', 'frequency (kHz)', 'parent_folder', "axialAnalysis");

ft_v = fftshift(fft(f_AVG, [], 3), 3);

f = fft_freq_vector(ToolBox.fs * 1000 / ToolBox.stride, numFrames);

cardiac_frequency = ToolBox.Cache.HeartBeatFFT; % in Hz

[~, cardiac_idx] = min(abs(f - cardiac_frequency));

img = log1p(abs(ft_v(:, :, cardiac_idx)));

if saveFigures
    % Save cardiac component image
    fi = figure('Visible', 'off');
    imshow(rescale(img));
    ax = gca;

    if isvalid(ax)
        exportgraphics(gca, fullfile(ToolBox.path_png, "axialAnalysis", sprintf("%s_axial_cardiac_component.png", ToolBox.folder_name)), 'Resolution', 300);
    end

    close(fi);
end

end
