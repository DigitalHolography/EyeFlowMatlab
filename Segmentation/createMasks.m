function createMasks( ...
    M0_ff, VesselSegmentationNet, ...
    AVSegmentationNet, EyeDiaphragmSegmentationNet)
% createMasks
% Crée les masques artériels, veineux et voisins.
% Charge les éventuels masques externes.
% Calcule les corrélations du band ratio normalisé.
%
% Les masques et résultats de segmentation sont enregistrés
% dans le Cache du ToolBox.

arguments
    M0_ff double
    VesselSegmentationNet = []
    AVSegmentationNet = []
    EyeDiaphragmSegmentationNet = []
end

ToolBox = getGlobalToolBox;
params = ToolBox.getParams;

saveFigures = params.saveFigures;
exportVideos = params.exportVideos;

path = ToolBox.EF_path;
folder_steps = fullfile('mask', 'steps');

%% 0) Initialisation

[numX, numY, numFrames] = size(M0_ff);

xy_barycenter = ToolBox.Cache.xy_barycenter;
x_c = xy_barycenter(1);
y_c = xy_barycenter(2);

if ~isfield(params.json, 'Mask')
    error('Mask parameters are missing in the JSON file.');
end

mask_params = params.json.Mask;

diaphragmRadius = mask_params.DiaphragmRadius;
cropChoroidRadius = mask_params.CropChoroidRadius;
forceVesselWidth = mask_params.ForceVesselWidth;
vesselnessMethod = mask_params.VesselSegmentationMethod;

bgWidth = params.json.PulseAnalysis.LocalBackgroundWidth;
r1 = params.json.SizeOfField.SmallRadiusRatio;
r2 = params.json.SizeOfField.BigRadiusRatio;

cArtery = [0, 0, 0; 255, 22, 18] / 255;
cVein = [0, 0, 0; 18, 23, 255] / 255;

cmapArtery = ToolBox.Cache.cmapArtery;
cmapVein = ToolBox.Cache.cmapVein;
cmapAV = ToolBox.Cache.cmapAV;

%% 1) Image moyenne et diaphragme

M0_ff_img = mean(M0_ff, 3);

saveMaskImage( ...
    M0_ff_img, 'all_00_M0.png', isStep = true);

if mask_params.EyeDiaphragmSegmentationNet
    [~, cx, cy, r] = predictDiaphragm( ...
        EyeDiaphragmSegmentationNet, M0_ff_img);

    offset = 0.02;

    maskDiaphragm = diskMask( ...
        numX, numY, (r / 1024) - offset, ...
        'center', [cx / 1024, cy / 1024]);
else
    cx = 512;
    cy = 512;

    maskDiaphragm = diskMask( ...
        numX, numY, diaphragmRadius);
end

maskDiaphragm = logical(maskDiaphragm);

saveMaskImage( ...
    rescale(M0_ff_img) + maskDiaphragm .* 0.5, ...
    'all_01_maskDiaphragm.png', ...
    isStep = true);

maskCircle = diskMask( ...
    numX, numY, cropChoroidRadius, ...
    'center', [x_c / numX, y_c / numY]);

scoreMaskArtery = NaN;
scoreMaskVein = NaN;

%% 2) Préparation de la vidéo pour la détection vasculaire

if any(contains( ...
        string(vesselnessMethod), ["matchedFilter", "frangi"]))

    M0_video = M0_ff;

    videoDomain = repmat( ...
        maskDiaphragm, 1, 1, numFrames);

    M0_video(~videoDomain) = NaN;
    clear videoDomain

    M0_img = mean(M0_video, 3, 'omitnan');
else
    M0_video = M0_ff;
end

%% 3) Détection vasculaire

switch vesselnessMethod
    case 'matchedFilter'
        fprintf("Compute vesselness using matched filter\n");

        [~, maskVesselness] = matchedFilterVesselDetection( ...
            M0_img, 'threshold', 0.6);

        saveMaskImage( ...
            maskVesselness, ...
            'all_11_matched_filter_mask.png', ...
            isStep = true);

    case 'frangi'
        fprintf("Compute vesselness using Frangi filter\n");

        [maskVesselness, M0_Frangi] = frangiVesselness( ...
            M0_img, 'range', [4, 6], 'step', 1);

        saveMaskImage( ...
            maskVesselness, ...
            'all_11_frangi_mask.png', ...
            isStep = true);

        saveMaskImage( ...
            M0_Frangi, ...
            'all_11_frangi_img.png', ...
            isStep = true);

    case 'gabor'
        fprintf("Compute vesselness using Gabor filter\n");

        [maskVesselness, M0_Gabor] = gaborVesselness( ...
            M0_ff_img, 'range', [4, 6], 'step', 1);

        saveMaskImage( ...
            maskVesselness, ...
            'all_11_gabor_mask.png', ...
            isStep = true);

        saveMaskImage( ...
            M0_Gabor, ...
            'all_11_gabor_img.png', ...
            isStep = true);

    case 'AI'
        fprintf("Compute vesselness using SegmentationNet\n");

        maskVesselness = getSegmentationNetVesselness( ...
            M0_ff_img, VesselSegmentationNet);

        saveMaskImage( ...
            maskVesselness, ...
            'all_11_maskSegmentationNet.png', ...
            isStep = true);

    otherwise
        error('createMasks:unknownVesselnessMethod', ...
            'Unknown vesselness method: %s', ...
            char(string(vesselnessMethod)));
end

%% 4) Nettoyage de la réponse vasculaire

maskVesselnessClean = ...
    maskVesselness & ...
    bwareafilt(maskVesselness | maskCircle, 1, 8) & ...
    maskDiaphragm;

saveMaskImage( ...
    maskVesselnessClean + maskCircle * 0.5, ...
    'all_12_VesselMask_clear.png', ...
    isStep = true);

%% 5) Pré-masques artériels et veineux

maskCircles = diskMask( ...
    numX, numY, r1, r2, ...
    'center', [cx / 1024, cy / 1024]);

[maskArteryTmp, maskVeinTmp] = preMaskArtery( ...
    M0_ff, maskVesselnessClean .* maskCircles);

saveMaskImage( ...
    maskArteryTmp, ...
    'artery_20_PreMask.png', ...
    isStep = true, cmap = cArtery);

saveMaskImage( ...
    maskVeinTmp, ...
    'vein_20_PreMask.png', ...
    isStep = true, cmap = cVein);

preMasks = zeros(numX, numY, 3);
preMasks(:, :, 1) = maskArteryTmp;
preMasks(:, :, 3) = maskVeinTmp;

saveMaskImage( ...
    preMasks, 'all_20_preMasks.png', isStep = true);

if saveFigures
    t = ToolBox.Cache.t;

    preArterySignal = ...
        sum(M0_ff .* maskArteryTmp, [1 2], 'omitnan') ...
        ./ nnz(maskArteryTmp);

    preVeinSignal = ...
        sum(M0_ff .* maskVeinTmp, [1 2], 'omitnan') ...
        ./ nnz(maskVeinTmp);

    graphSignal( ...
        'artery_20_preArterialSignal', ...
        t, squeeze(preArterySignal), '-', cArtery(2, :), ...
        Title = 'Pre Arterial Signal', ...
        xlabel = 'Time(s)', ...
        ylabel = 'Power Doppler (a.u.)');

    graphSignal( ...
        'vein_20_preVenousSignal', ...
        t, squeeze(preVeinSignal), '-', cVein(2, :), ...
        Title = 'Pre Venous Signal', ...
        xlabel = 'Time(s)', ...
        ylabel = 'Power Doppler (a.u.)');
end

%% 6) Segmentation artères / veines

if mask_params.AVCorrelationSegmentationNet || ...
        mask_params.AVDiasysSegmentationNet

    [maskArtery, maskVein, ...
         scoreMaskArtery, scoreMaskVein] = ...
        createMasksSegmentationNet( ...
        M0_ff, AVSegmentationNet, maskArteryTmp);

    saveMaskImage( ...
        maskArtery, ...
        'artery_21_SegmentationNet.png', ...
        isStep = true, cmap = cArtery);

    saveMaskImage( ...
        maskVein, ...
        'vein_21_SegmentationNet.png', ...
        isStep = true, cmap = cVein);
else
    [maskArtery, maskVein, ...
         R_ArterialSignal, diasys_diff] = ...
        createMasksSegmentationDeterministic( ...
        M0_video, maskVesselnessClean, maskArteryTmp);

    saveMaskImage( ...
        maskArtery, ...
        'artery_21_SegmentationDeterministic.png', ...
        isStep = true, cmap = cArtery);

    saveMaskImage( ...
        maskVein, ...
        'vein_21_SegmentationDeterministic.png', ...
        isStep = true, cmap = cVein);

    if exportVideos
        RGB_corr_video = labDuoVideo( ...
            rescale(M0_ff), R_ArterialSignal);

        RGB_diasys_video = labDuoVideo( ...
            rescale(M0_ff), diasys_diff);

        writeGifOnDisc(RGB_corr_video, 'correlation.gif');
        writeGifOnDisc(RGB_diasys_video, 'diasys.gif');
    end

end

%% 7) Nettoyage morphologique

maskArtery = maskArtery & maskDiaphragm;
maskVein = maskVein & maskDiaphragm;

[mask_dilated_artery, mask_closed_artery, ...
     mask_opened_artery, mask_widened_artery] = ...
    clearMasks( ...
    maskArtery, ...
    'min_area', mask_params.MinPixelSize, ...
    'imclose_radius', mask_params.ImcloseRadius, ...
    'min_width', mask_params.MinimumVesselWidth, ...
    'imdilate_size', mask_params.FinalDilation);

[mask_dilated_vein, mask_closed_vein, ...
     mask_opened_vein, mask_widened_vein] = ...
    clearMasks( ...
    maskVein, ...
    'min_area', mask_params.MinPixelSize, ...
    'imclose_radius', mask_params.ImcloseRadius, ...
    'min_width', mask_params.MinimumVesselWidth, ...
    'imdilate_size', mask_params.FinalDilation);

if saveFigures
    saveMaskImage( ...
        mask_dilated_artery, 'artery_30_ClearedMask.png', ...
        isStep = true, cmap = cArtery);

    saveMaskImage( ...
        mask_opened_artery, 'artery_30_ClearedMask_opened.png', ...
        isStep = true, cmap = cArtery);

    saveMaskImage( ...
        mask_closed_artery, 'artery_30_ClearedMask_closed.png', ...
        isStep = true, cmap = cArtery);

    saveMaskImage( ...
        mask_widened_artery, 'artery_30_ClearedMask_widened.png', ...
        isStep = true, cmap = cArtery);

    saveMaskImage( ...
        mask_dilated_vein, 'vein_30_ClearedMask.png', ...
        isStep = true, cmap = cVein);

    saveMaskImage( ...
        mask_opened_vein, 'vein_30_ClearedMask_opened.png', ...
        isStep = true, cmap = cVein);

    saveMaskImage( ...
        mask_closed_vein, 'vein_30_ClearedMask_closed.png', ...
        isStep = true, cmap = cVein);

    saveMaskImage( ...
        mask_widened_vein, 'vein_30_ClearedMask_widened.png', ...
        isStep = true, cmap = cVein);
end

maskArtery = mask_dilated_artery;
maskVein = mask_dilated_vein;

%% 8) Masque choroïdien

maskGabor = gaborVesselness( ...
    M0_ff_img, 'range', [4, 6], 'step', 1);

maskFrangi = frangiVesselness( ...
    M0_ff_img, 'range', [4, 6], 'step', 1);

maskChoroid = ...
    (maskGabor & maskFrangi) & ...
    ~maskCircle & maskDiaphragm;

%% 9) Suppression finale des composantes isolées

maskVessel = maskArtery | maskVein;
connectedMask = bwareafilt(maskVessel | maskCircle, 1, 8);

maskArtery = maskArtery & connectedMask;
maskVein = maskVein & connectedMask;

if saveFigures
    saveMaskImage( ...
        maskArtery + maskCircle * 0.5, ...
        'artery_31_VesselMask_clear.png', ...
        isStep = true);

    saveMaskImage( ...
        maskVein + maskCircle * 0.5, ...
        'vein_31_VesselMask_clear.png', ...
        isStep = true);
end

%% 10) Image systole / diastole

[M0_Systole_img, M0_Diastole_img] = compute_diasys( ...
    M0_ff, maskArtery, 'mask');

diasys_diff = M0_Systole_img - M0_Diastole_img;

RGBdiasys = labDuoImage( ...
    rescale(M0_ff_img), diasys_diff);

saveMaskImage(RGBdiasys, 'diasys_diff.png');

%% 11) Recalage de masques existants

if mask_params.RegisteredMasks == -1 || ...
        mask_params.RegisteredMasks == 1

    fileSimilarM0 = fullfile(path, 'mask', 'similarM0.png');
    fileSimilarArtery = fullfile( ...
        path, 'mask', 'similarMaskArtery.png');
    fileSimilarVein = fullfile( ...
        path, 'mask', 'similarMaskVein.png');

    hasSimilarM0 = isfile(fileSimilarM0);
    hasSimilarArtery = isfile(fileSimilarArtery);
    hasSimilarVein = isfile(fileSimilarVein);

    if hasSimilarM0 && (hasSimilarArtery || hasSimilarVein)
        M0_ff_img = mean(M0_ff, 3);

        similarM0 = mat2gray( ...
            mean(imread(fileSimilarM0), 3));

        [ux, uy] = nonrigidregistration( ...
            similarM0, M0_ff_img, ...
            fullfile(ToolBox.path_png, folder_steps), ...
        'Reg');

        [Xq, Yq] = meshgrid(1:numY, 1:numX);

        if hasSimilarArtery
            similarMaskArtery = readMaskFile( ...
                fileSimilarArtery, numX, numY);

            maskArtery = interp2( ...
                single(similarMaskArtery), ...
                Xq + ux, Yq + uy, 'linear', 0) > 0;
        end

        if hasSimilarVein
            similarMaskVein = readMaskFile( ...
                fileSimilarVein, numX, numY);

            maskVein = interp2( ...
                single(similarMaskVein), ...
                Xq + ux, Yq + uy, 'linear', 0) > 0;
        end

    end

end

%% 12) Dossiers de recherche des masques externes
% Priorité :
%   1. Mask.ExtraMaskFolder
%   2. <EF_path>/mask
%   3. <dossier parent>/eyeflow/mask

maskFolders = {};

if isfield(mask_params, 'ExtraMaskFolder') && ...
        ~isempty(mask_params.ExtraMaskFolder)

    maskFolders{end + 1} = char(mask_params.ExtraMaskFolder);
end

maskFolders{end + 1} = fullfile(path, 'mask');

rootDir = fileparts( ...
    regexprep(char(path), '[\\/]+$', ''));

maskFolders{end + 1} = fullfile( ...
    rootDir, 'eyeflow', 'mask');

artery_names = { ...
                    'forceMaskArtery.png', ...
                'retinal_artery_mask_clean.png'};

vein_names = { ...
                  'forceMaskVein.png', ...
              'retinal_vein_mask_clean.png'};

choroid_names = { ...
                     'maskChoroid.png', ...
                 'choroidal_vessel_mask.png'};

%% 13) Chargement des masques forcés

if mask_params.ForcedMasks == -1 || ...
        mask_params.ForcedMasks == 1

    fileArtery = findMaskFile(maskFolders, artery_names);

    if ~isempty(fileArtery)
        fprintf("Forced artery mask: %s\n", fileArtery);

        maskArtery = readMaskFile( ...
            fileArtery, numX, numY);

    elseif mask_params.ForcedMasks == 1
        error('createMasks:missingForcedArtery', ...
            ['Cannot force Artery Mask because none found. ', ...
             'Looked for %s in: %s. ', ...
         'Set ForcedMasks to -1 to use the automatic mask.'], ...
            strjoin(artery_names, ', '), ...
            strjoin(maskFolders, ' | '));
    end

    fileVein = findMaskFile(maskFolders, vein_names);

    if ~isempty(fileVein)
        fprintf("Forced vein mask: %s\n", fileVein);

        maskVein = readMaskFile( ...
            fileVein, numX, numY);

    elseif mask_params.ForcedMasks == 1
        error('createMasks:missingForcedVein', ...
            ['Cannot force Vein Mask because none found. ', ...
             'Looked for %s in: %s. ', ...
         'Set ForcedMasks to -1 to use the automatic mask.'], ...
            strjoin(vein_names, ', '), ...
            strjoin(maskFolders, ' | '));
    end

end

fileChoroid = findMaskFile(maskFolders, choroid_names);

if ~isempty(fileChoroid)
    fprintf("Choroid mask: %s\n", fileChoroid);

    maskChoroid = readMaskFile( ...
        fileChoroid, numX, numY);
end

%% 14) Scores de segmentation

segmentationScores(maskArtery, maskVein);

%% 15) Largeur vasculaire imposée

if forceVesselWidth > 0
    dilationSE = strel('disk', forceVesselWidth);

    maskArtery = imdilate(bwskel(maskArtery), dilationSE);
    maskVein = imdilate(bwskel(maskVein), dilationSE);

    maskArtery = imdilate(bwskel(maskArtery), dilationSE);
    maskVein = imdilate(bwskel(maskVein), dilationSE);
end

%% 16) Masques finaux

maskArtery = maskArtery & maskDiaphragm;
maskVein = maskVein & maskDiaphragm;

maskVessel = maskArtery | maskVein;
maskAV = maskArtery & maskVein;
maskBackground = ~maskVessel;

%% 17) Masque des voisins

bgDist = params.json.PulseAnalysis.LocalBackgroundDist;

maskVessel_tmp = imdilate( ...
    maskVessel, strel('disk', bgDist));

maskNeighbors = ...
    imdilate(maskVessel_tmp, strel('disk', bgWidth)) & ...
    ~maskVessel_tmp;

maskNeighbors = maskNeighbors & maskDiaphragm;

%% 18) Figures finales

M0_ff_img = rescale(M0_ff_img);

M0_Artery = setcmap( ...
    M0_ff_img, maskArtery, cmapArtery);

M0_Vein = setcmap( ...
    M0_ff_img, maskVein, cmapVein);

M0_AV = setcmap( ...
    M0_ff_img, maskAV, cmapAV);

M0_bkg = M0_ff_img .* maskBackground;

M0_RGB = M0_Artery + M0_Vein + M0_AV + M0_bkg;

saveMaskImage( ...
    M0_Artery + M0_ff_img .* ~maskArtery, ...
    'M0_Artery.png', ForceFigure = true);

saveMaskImage( ...
    M0_Vein + M0_ff_img .* ~maskVein, ...
    'M0_Vein.png', ForceFigure = true);

saveMaskImage( ...
    M0_RGB, 'M0_RGB.png', ForceFigure = true);

if saveFigures
    cmapNeighbors = cmapLAB( ...
        256, [0 1 0], 0, [1 1 1], 1);

    M0_Neighbors = setcmap( ...
        M0_ff_img, maskNeighbors, cmapNeighbors);

    neighborsMaskSeg = ...
        M0_Artery + M0_Vein + M0_AV + M0_Neighbors + ...
        M0_ff_img .* ~(maskArtery | maskVein | maskNeighbors);

    saveMaskImage(neighborsMaskSeg, 'neighbors_img.png');

    saveMaskImage(maskArtery, 'maskArtery.png');
    saveMaskImage(maskVein, 'maskVein.png');
    saveMaskImage(maskVessel, 'maskVessel.png');
    saveMaskImage(maskNeighbors, 'maskNeighbors.png');
    saveMaskImage(maskBackground, 'maskBackground.png');

    saveMaskImage( ...
        bwskel(maskArtery), 'skeletonArtery.png');

    saveMaskImage( ...
        bwskel(maskVein), 'skeletonVein.png');

    createMaskSection( ...
        ToolBox, M0_ff_img, r1, r2, xy_barycenter, ...
        'vessel_map_artery', maskArtery, ...
        thin = 0.01);

    createMaskSection( ...
        ToolBox, M0_ff_img, r1, r2, xy_barycenter, ...
        'vessel_map_vein', [], maskVein, ...
        thin = 0.01);

    createMaskSection( ...
        ToolBox, M0_ff_img, r1, r2, xy_barycenter, ...
        'vessel_map', maskArtery, maskVein, ...
        thin = 0.01);
end

%% 19) Surfaces en pixels

ArteryArea_pxl = nnz(maskArtery);
VeinArea_pxl = nnz(maskVein);
RemainingArea_pxl = nnz(maskBackground);

ToolBox.Output.add( ...
    'ArteryNbPxl', ArteryArea_pxl, ...
    h5path = '/Artery/Segmentation/NbPxl');

ToolBox.Output.add( ...
    'VeinNbPxl', VeinArea_pxl, ...
    h5path = '/Vein/Segmentation/NbPxl');

ToolBox.Output.add( ...
    'RemainingNbPxl', RemainingArea_pxl, ...
    h5path = '/ArteryVein/Segmentation/NbPxl');

%% 20) Enregistrement dans le Cache

ToolBox.Cache.maskArtery = maskArtery;
ToolBox.Cache.maskVein = maskVein;
ToolBox.Cache.maskVessel = maskVessel;
ToolBox.Cache.maskNeighbors = maskNeighbors;
ToolBox.Cache.maskBackground = maskBackground;
ToolBox.Cache.maskChoroid = maskChoroid;

ToolBox.Cache.xy_barycenter = xy_barycenter;
ToolBox.Cache.M0_RGB = M0_RGB;

ToolBox.Cache.scoreMaskArtery = scoreMaskArtery;
ToolBox.Cache.scoreMaskVein = scoreMaskVein;

%% 21) Chargement des régions externes
% Ces régions sont communes aux analyses de bandes et aux spectres SH_avg.
% Leur chargement ne dépend pas de la disponibilité des données de bandes.

maskDefinitions = {
                   'choroidal_aliased_artery_mask_clean', 'ChoroidAliasedArtery', '#ff6600'
                   'choroidal_artery_mask_clean', 'ChoroidPapilaries', '#FF8080'
                   'choroidal_vein_mask_clean', 'ChoroidVein', '#0040bb'
                   'choroidal_vessel_mask', 'ChoroidVessel', '#861c1c'
                   'optic_disc_mask', 'OpticDisc', '#37c937'
                   'retinal_artery_mask_clean', 'RetinaArtery', '#FF0000'
                   'retinal_vein_mask_clean', 'RetinaVein', '#0080FF'
                   'anticor', 'AntiCorrelation', '#1a1818'
                   };

correlationMasks = struct();
correlationColors = struct();

for k = 1:size(maskDefinitions, 1)
    fileName = maskDefinitions{k, 1};
    name = maskDefinitions{k, 2};
    hexColor = maskDefinitions{k, 3};

    file = findMaskFile(maskFolders, {[fileName '.png']});

    if isempty(file)
        warning('createMasks:missingAnalysisMask', ...
            'Analysis mask not found: %s.png', fileName);
        continue
    end

    m = readMaskFile(file, numX, numY);
    m = m & maskDiaphragm;

    if ~any(m, 'all')
        warning('createMasks:emptyAnalysisMask', ...
            'Mask %s is empty inside the diaphragm: skipped.', ...
            name);
        continue
    end

    correlationMasks.(name) = m;
    correlationColors.(name) = hexColor;
end

hasAnalysisMasks = ~isempty(fieldnames(correlationMasks));

if ~hasAnalysisMasks
    warning('createMasks:noAnalysisMasks', ...
    'No valid external analysis mask was found.');
end

%% 22) Préparation des régions pour SH_avg
% Les masques restent ici dans le repère de M0_ff.
% Aucune transformation vers le repère de SH_avg n'est encore appliquée.

spectralMasks = correlationMasks;
spectralColors = correlationColors;

% Conserver les régions pour l'étape d'analyse spectrale.
ToolBox.Cache.SH_avg_masks = spectralMasks;
ToolBox.Cache.SH_avg_colors = spectralColors;
ToolBox.Cache.SH_avg_maskDomain = maskDiaphragm;

if isempty(ToolBox.Cache.SH_avg)
    fprintf('    - SH_avg absent: spectral analysis not available\n');
else
    fprintf('    - SH_avg available: %s\n', ...
        mat2str(size(ToolBox.Cache.SH_avg)));

    fprintf('    - Spectral regions prepared: %d\n', ...
        numel(fieldnames(spectralMasks)));
end

%% 23) Corrélations du band ratio normalisé

if hasAnalysisMasks

    if ~isempty(ToolBox.Cache.bandRatio) && ...
            ~isempty(ToolBox.Cache.f_RMS)

        bandRatioCorrelation( ...
            M0_ff, ...
            ToolBox.Cache.f_RMS, ...
            ToolBox.Cache.bandRatio, ...
            correlationMasks, ...
            maskDomain = maskDiaphragm, ...
            regionColors = correlationColors);
    else
        warning('createMasks:missingBandRatioData', ...
            ['Band ratio or f_RMS not available: ', ...
         'correlation maps skipped.']);
    end

end

articleResults = bandRatioArticleFigures( ...
    M0_ff, ...
    ToolBox.Cache.HF_M0, ...
    ToolBox.Cache.LF_M0, ...
    ToolBox.Cache.bandRatio, ...
    correlationMasks, ...
    maskDomain = maskDiaphragm, ...
    regionColors = correlationColors, ...
    time = ToolBox.Cache.t, ...
    outputDir = fullfile( ...
    ToolBox.path_png, 'mask', 'band_ratio', 'article'), ...
    prefix = string(ToolBox.folder_name), ...
    lowBandHz = [3000 9000], ...
    highBandHz = [9000 18000], ...
    bandValues = "unknown");

% Vérifier que les bandes prétraitées ont été conservées.
if ~isprop(ToolBox.Cache, 'LF_M0') || ...
        ~isprop(ToolBox.Cache, 'HF_M0')

    error('createMasks:missingBandCacheProperties', ...
        ['Add LF_M0 and HF_M0 to CacheClass, then copy the ', ...
     'preprocessed bands into the Cache in ExecutionClass.']);
end

LF_M0 = ToolBox.Cache.LF_M0;
HF_M0 = ToolBox.Cache.HF_M0;

if isempty(LF_M0) || isempty(HF_M0)
    error('createMasks:missingBandData', ...
        ['LF_M0 or HF_M0 is empty in the Cache. ', ...
     'Preserve the preprocessed bands and rerun preprocessing.']);
end

if ~isequal(size(M0_ff), size(LF_M0), size(HF_M0))
    error('createMasks:bandSizeMismatch', ...
        ['M0_ff, LF_M0 and HF_M0 must have identical sizes ', ...
     'and follow the same preprocessing transformations.']);
end

% Paramètres identiques à ceux utilisés pour la correction de M0.
FF = params.json.FlatFieldCorrection;

gaussianWidth = ceil(FF.GWRatio * size(M0_ff, 1));
borderAmount = FF.Border;

% Créer effectivement les deux variables avant leur utilisation.
M0_LF_flatfield = flatfieldBandForArticle( ...
    LF_M0, gaussianWidth, borderAmount, 'LF_M0');

M0_HF_flatfield = flatfieldBandForArticle( ...
    HF_M0, gaussianWidth, borderAmount, 'HF_M0');

% Recalculer HF_flatfield / LF_flatfield et produire les figures.
articleFlatfieldResults = bandRatioFlatfieldArticleFigures( ...
    M0_ff, ...
    M0_LF_flatfield, ...
    M0_HF_flatfield, ...
    correlationMasks, ...
    maskDomain = maskDiaphragm, ...
    regionColors = correlationColors, ...
    time = ToolBox.Cache.t, ...
    outputDir = fullfile( ...
    ToolBox.path_png, ...
    'mask', 'band_ratio', 'article_flatfield'), ...
    prefix = string(ToolBox.folder_name) + "_flatfield", ...
    lowBandHz = [3000 9000], ...
    highBandHz = [9000 18000], ...
    ratioScale = 1, ...
    minLF = 0);

%% Analyse spectrale régionale de SH_avg

if ~isempty(ToolBox.Cache.SH_avg)

    % Convention explicite :
    % SH_avg contient la FFT complète, non fftshiftée.
    numFreq = size(ToolBox.Cache.SH_avg, 3);
    fsHz = double(ToolBox.fs) * 1000;

    if ~isscalar(fsHz) || ~isfinite(fsHz) || fsHz <= 0
        error('createMasks:invalidSamplingFrequency', ...
            ['ToolBox.fs must be a finite positive ', ...
         'sampling frequency in kHz.']);
    end

    if numFreq < 2
        error('createMasks:invalidSpectralSize', ...
        'SH_avg must contain at least two frequency bins.');
    end

    frequencyBins = (0:numFreq - 1).';

    negativeBins = frequencyBins >= ceil(numFreq / 2);
    frequencyBins(negativeBins) = ...
        frequencyBins(negativeBins) - numFreq;

    frequencyHz = frequencyBins * (fsHz / numFreq);

    fprintf('    - SH_avg: %d spectral bins, fs = %.3f kHz\n', ...
        numFreq, fsHz / 1000);

    spectralResults = spectrum_masks( ...
        ToolBox.Cache.SH_avg, ...
        spectralMasks, ...
        frequency = frequencyHz, ...
        frequencyUnit = "Hz", ...
        maskDomain = maskDiaphragm, ...
        regionColors = spectralColors, ...
        referenceImage = M0_ff_img, ...
        outputDir = fullfile( ...
        ToolBox.path_png, 'mask', 'spectral_analysis'), ...
        prefix = string(ToolBox.folder_name) + "_SH_avg", ...
        sourceFile = string(ToolBox.Cache.SH_avg_sourceFile), ...
        datasetPath = string(ToolBox.Cache.SH_avg_datasetPath));

else
    fprintf('    - SH_avg absent: spectral figures skipped\n');
end

% Libérer les cubes temporaires après
close all

end

function file = findMaskFile(folders, names)
% Retourne le premier fichier existant.
% Priorité : dossiers, puis noms.

file = '';

for i = 1:numel(folders)

    for j = 1:numel(names)
        candidate = fullfile(folders{i}, names{j});

        if isfile(candidate)
            file = candidate;
            return
        end

    end

end

end

function m = readMaskFile(file, numX, numY)
% Lit un masque PNG binaire ou RGB.
% Convention : fond nul, région définie par les pixels non nuls.
% Aucun rééchelonnement des intensités n'est appliqué.

img = imread(file);

m = any(isfinite(img) & img ~= 0, 3);

if ~isequal(size(m), [numX, numY])
    m = imresize(m, [numX, numY], 'nearest');
end

m = logical(m);

end

function Y = flatfieldBandForArticle(X, gaussianWidth, borderAmount, name)
% Applique la correction flat-field EyeFlow séparément à chaque frame.
%
% Cette fonction attend un cube avant correction flat-field.
% Ne pas l'utiliser sur une bande déjà corrigée.

if isempty(which('flat_field_correction_ef'))
    error('createMasks:missingFlatfieldFunction', ...
    'flat_field_correction_ef.m is not on the MATLAB path.');
end

if ~isscalar(gaussianWidth) || ...
        ~isfinite(gaussianWidth) || gaussianWidth <= 0

    error('createMasks:invalidFlatfieldWidth', ...
    'The Gaussian width must be finite and strictly positive.');
end

if ~isscalar(borderAmount) || ...
        ~isfinite(borderAmount) || ...
        borderAmount < 0 || borderAmount >= 0.5

    error('createMasks:invalidFlatfieldBorder', ...
    'The flat-field border fraction must be in [0, 0.5).');
end

[nRows, nCols, nt] = size(X);
Y = nan(nRows, nCols, nt, 'single');

fprintf('    - Flat-field correction of %s (%d frames)\n', ...
    name, nt);

for it = 1:nt
    frame = single(X(:, :, it));

    if any(~isfinite(frame), 'all')
        error('createMasks:nonFiniteBandFrame', ...
            ['%s contains non-finite values in frame %d. ', ...
             'Correct or explicitly handle missing data ', ...
         'before applying flat-field correction.'], ...
            name, it);
    end

    corrected = flat_field_correction_ef( ...
        frame, gaussianWidth, borderAmount);

    corrected = single(corrected);

    % Les éventuelles divisions invalides de la correction
    % restent des données manquantes.
    corrected(~isfinite(corrected)) = NaN;

    Y(:, :, it) = corrected;
end

end
