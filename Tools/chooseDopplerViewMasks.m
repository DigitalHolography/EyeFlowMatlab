function maskParams = chooseDopplerViewMasks( ...
    maskParams, hdPath, imageSize)
% Select an existing DopplerView retinal artery/vein mask pair.
% Cancel preserves the current mask configuration.

hdPath = char(hdPath);

while numel(hdPath) > 1 && ...
        any(hdPath(end) == ['/' char(92)])

    if ispc && numel(hdPath) == 3 && hdPath(2) == ':'
        break;
    end

    hdPath(end) = [];
end

% HD and DV outputs are searched within this acquisition's parent.
measurementRoot = fileparts(hdPath);

arteryName = 'retinal_artery_mask_clean.png';
veinName = 'retinal_vein_mask_clean.png';

candidates = dir(fullfile( ...
    measurementRoot, '**', arteryName));

if isempty(candidates)
    return;
end

% Only offer results containing both masks.
hasPair = false(numel(candidates), 1);

for k = 1:numel(candidates)
    hasPair(k) = isfile(fullfile( ...
        candidates(k).folder, veinName));
end

candidates = candidates(hasPair);

if isempty(candidates)
    return;
end

% Start in the most recently modified candidate.
[~, order] = sort([candidates.datenum], 'descend');
candidates = candidates(order);

initialFile = fullfile( ...
    candidates(1).folder, arteryName);

[file, folder] = uigetfile( ...
    {arteryName, 'DopplerView retinal artery mask'}, ...
    'Choose DopplerView masks — Cancel keeps current settings', ...
    initialFile);

if isequal(file, 0)
    return;
end

arteryFile = fullfile(folder, file);
veinFile = fullfile(folder, veinName);

if ~strcmpi(file, arteryName) || ~isfile(veinFile)
    error('EyeFlow:InvalidDopplerViewMaskPair', ...
        ['Select %s from a folder also containing %s.'], ...
        arteryName, veinName);
end

% Do not silently resize masks from a different image geometry.
files = {arteryFile, veinFile};
targetSize = double(imageSize(1:2));

for k = 1:numel(files)
    info = imfinfo(files{k});
    maskSize = double([info(1).Height, info(1).Width]);

    if ~isequal(maskSize, targetSize)
        error('EyeFlow:DopplerViewMaskSizeMismatch', ...
            ['Mask size is %s; EyeFlow image size is %s.\n', ...
             'File: %s\n', ...
         'Check cropping, resizing and orientation before import.'], ...
            mat2str(maskSize), mat2str(targetSize), files{k});
    end

end

maskParams.ExtraMaskFolder = folder;
maskParams.ForcedMasks = 1;

fprintf('[EyeFlow] Selected DopplerView masks:\n');
fprintf('  Artery: %s\n', arteryFile);
fprintf('  Vein:   %s\n', veinFile);
end
