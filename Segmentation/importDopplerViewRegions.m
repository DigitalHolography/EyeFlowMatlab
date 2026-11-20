function results = importDopplerViewRegions(ToolBox)
% Import all available non-raw DopplerView regions, orient and measure them.
% Call after preprocessing, while Cache.M0_ff and Cache.t are available.
% Cancellation returns an empty struct and writes nothing.
% Orientation is selected explicitly: no automatic registration or resizing.

results = struct();
cache = ToolBox.Cache;

if isempty(cache.M0_ff)
    error('EyeFlow:NoReferenceVideo', 'Cache.M0_ff is empty.');
end

reference = mean(cache.M0_ff, 3, 'omitnan');
targetSize = [size(reference, 1), size(reference, 2)];
nFrames = size(cache.M0_ff, 3);
time = double(cache.t(:));

if numel(time) ~= nFrames || any(~isfinite(time))
    error('EyeFlow:InvalidTime', 'Cache.t must contain one finite time per frame.');
end

[file, folder] = uigetfile({'*.h5;*.hdf5', 'DopplerView result HDF5'}, ...
    'Select the DopplerView result for this acquisition', ...
    fileparts(char(ToolBox.HD_path)));
if isequal(file, 0), return; end
source = fullfile(folder, file);

% Clean artery/vein regions, union vessel regions and optic disc.
% Raw masks, probability maps and labeled branch maps are excluded.
definitions = {
               'RetinaArtery', '/segmentation/Retina/artery_mask'
               'RetinaVein', '/segmentation/Retina/vein_mask'
               'RetinaVessel', '/segmentation/Retina/vessel_mask'
               'ChoroidArtery', '/segmentation/Choroid/artery_mask'
               'ChoroidAliasedArtery', '/segmentation/Choroid/aliased_artery_mask'
               'ChoroidVein', '/segmentation/Choroid/vein_mask'
               'ChoroidVessel', '/segmentation/Choroid/vessel_mask'
               'OpticDisc', '/segmentation/OpticDisc/mask'
               };
available = collectDatasets(h5info(source));
masks = struct();
paths = struct();
missing = {};
sourceSize = [];

for k = 1:size(definitions, 1)
    name = definitions{k, 1};
    dataset = definitions{k, 2};

    if ~ismember(dataset, available)
        missing{end + 1} = dataset; %#ok<AGROW>
        continue;
    end

    data = readDVBinaryMask(source, dataset);

    if isempty(sourceSize), sourceSize = size(data); end

    if ~isequal(size(data), sourceSize)
        error('EyeFlow:InconsistentRegions', ...
        'DopplerView regions do not share the same spatial size.');
    end

    masks.(name) = data ~= 0;
    paths.(name) = dataset;
end

names = fieldnames(masks);

if isempty(names)
    error('EyeFlow:NoDVRegions', 'No recognized segmentation masks in %s.', source);
end

[oriented, transform, accepted] = orientRegions(reference, masks);
if ~accepted, return; end

% Never use indices from a mask on a different spatial grid.
for k = 1:numel(names)
    regionName = names{k};
    mask = oriented.(regionName);

    if ~islogical(mask) || ~isequal(size(mask), targetSize)
        error('EyeFlow:AlignedMaskSizeMismatch', ...
            ['Region %s has size %s; expected %s. ', ...
         'The accepted mask must use the EyeFlow image grid.'], ...
            regionName, mat2str(size(mask)), mat2str(targetSize));
    end

end

results.SourceFile = source;
results.SourceDatasets = paths;
results.MissingDatasets = missing;
results.Transform = transform;
results.SourceSizeAsReadByMATLAB = sourceSize;
results.TargetSize = targetSize;
results.Masks = oriented;
results.TimeSeconds = time;
results.Regions = struct();
results.Signals = struct();
results.ValidPixelCounts = struct();
results.SignalDefinition = ...
    'Arithmetic spatial mean of finite values, per frame; no unit conversion.';

for k = 1:numel(names)
    name = names{k};
    count = nnz(oriented.(name));
    results.Regions.(name).PixelCount = count;

    if count == 0
        warning('EyeFlow:EmptyDVRegion', '%s is empty; signal will be NaN.', name);
    end

end

% Cache property          Exported quantity
quantities = {
              'f_RMS', 'f_RMS'
              'f_AVG', 'f_AVG'
              'gaussian_w', 'gaussian_w'
              'bandRatio', 'band_ratio'
              'HF_M0', 'HF_M0'
              'LF_M0', 'LF_M0'
              'vRMS', 'vRMS'
              };

results.Signals = struct();
results.ValidPixelCounts = struct();
results.UnavailableQuantities = {};

% Prepare each aligned region once.
regionIndices = cell(numel(names), 1);

for k = 1:numel(names)
    regionIndices{k} = find(oriented.(names{k}));
end

for v = 1:size(quantities, 1)
    cacheField = quantities{v, 1};
    outputName = quantities{v, 2};

    if ~isprop(cache, cacheField) || isempty(cache.(cacheField))
        results.UnavailableQuantities{end + 1} = outputName;
        fprintf('[Regions] %s absent: skipped.\n', outputName);
        continue;
    end

    cube = cache.(cacheField);

    if ~(isnumeric(cube) || islogical(cube)) || ...
            ~isreal(cube) || ndims(cube) > 3
        error('EyeFlow:InvalidRegionalQuantity', ...
            '%s must be a real scalar-valued video.', cacheField);
    end

    if ~isequal([size(cube, 1), size(cube, 2)], targetSize) || ...
            size(cube, 3) ~= nFrames
        error('EyeFlow:RegionalQuantitySizeMismatch', ...
            ['%s size is %s; expected [%d %d %d]. ', ...
         'Do not resize or truncate temporal data silently.'], ...
            cacheField, mat2str(size(cube)), ...
            targetSize(1), targetSize(2), nFrames);
    end

    signals = nan(nFrames, numel(names));
    validCounts = zeros(nFrames, numel(names));

    for t = 1:nFrames
        frame = cube(:, :, t);

        for k = 1:numel(names)
            values = double(frame(regionIndices{k}));
            values = values(isfinite(values));

            validCounts(t, k) = numel(values);

            if ~isempty(values)
                signals(t, k) = mean(values);
            end

        end

    end

    for k = 1:numel(names)
        name = names{k};

        results.Signals.(outputName).(name) = signals(:, k);
        results.ValidPixelCounts.(outputName).(name) = ...
            validCounts(:, k);
    end

end

outDir = fullfile(ToolBox.EF_path, 'dopplerview_regions');

if ~isfolder(outDir)
    mkdir(outDir);
end

prefix = char(ToolBox.folder_name);

% One figure per quantity, with one panel per imported region.
quantityNames = fieldnames(results.Signals);

for v = 1:numel(quantityNames)
    quantity = quantityNames{v};

    figSignals = figure( ...
        'Visible', 'off', ...
        'Color', 'w', ...
        'Position', [100 100 1200 850]);

    figureCleanup = onCleanup(@() delete(figSignals));

    layout = tiledlayout(figSignals, 'flow', ...
        'TileSpacing', 'compact', ...
        'Padding', 'compact');

    title(layout, quantity, 'Interpreter', 'none');

    for k = 1:numel(names)
        regionName = names{k};
        ax = nexttile(layout);

        plot(ax, time, ...
            results.Signals.(quantity).(regionName), ...
            'LineWidth', 1.2);

        grid(ax, 'on');
        xlabel(ax, 'Time (s)');
        ylabel(ax, quantity, 'Interpreter', 'none');
        title(ax, regionName, 'Interpreter', 'none');
    end

    exportgraphics(figSignals, ...
        fullfile(outDir, [prefix '_' quantity '_signals.png']), ...
        'Resolution', 160);

    clear figureCleanup
end

signalTable = table(time, 'VariableNames', {'TimeSeconds'});
countTable = table(time, 'VariableNames', {'TimeSeconds'});
volumeNames = fieldnames(results.Signals);

for v = 1:numel(volumeNames)
    field = volumeNames{v};

    for k = 1:numel(names)
        name = names{k};
        column = matlab.lang.makeValidName([field '_' name]);
        signalTable.(column) = results.Signals.(field).(name);
        countTable.(column) = results.ValidPixelCounts.(field).(name);
    end

end

writetable(signalTable, fullfile(outDir, [prefix '_signals.csv']));
writetable(countTable, fullfile(outDir, [prefix '_valid_pixels.csv']));

base = double(reference);
finitePixels = isfinite(base);

if any(finitePixels(:))
    lo = min(base(finitePixels));
    hi = max(base(finitePixels));
    base(~finitePixels) = lo;
    base = (base - lo) / max(hi - lo, eps);
else
    base(:) = 0;
end

for k = 1:numel(names)
    name = names{k};
    mask = oriented.(name);
    imwrite(uint8(mask) * 255, fullfile(outDir, [prefix '_' name '_mask.png']));
    overlay = repmat(base, 1, 1, 3);
    color = [1 0.35 0.1];

    for c = 1:3
        channel = overlay(:, :, c);
        channel(mask) = 0.6 * channel(mask) + 0.4 * color(c);
        overlay(:, :, c) = channel;
    end

    imwrite(overlay, fullfile(outDir, [prefix '_' name '_overlay.png']));
end

metadata = rmfield(results, {'Masks', 'Signals', 'ValidPixelCounts', 'TimeSeconds'});
fid = fopen(fullfile(outDir, [prefix '_import.json']), 'w');
if fid < 0, error('EyeFlow:DVMetadataWrite', 'Cannot write import metadata.'); end
cleanup = onCleanup(@() fclose(fid));
fwrite(fid, jsonencode(metadata, 'PrettyPrint', true), 'char');
clear cleanup
save(fullfile(outDir, [prefix '_regions.mat']), 'results', '-v7.3');
fprintf('[EyeFlow] %d DopplerView regions exported to %s\n', numel(names), outDir);
end

function paths = collectDatasets(info)
paths = {};

for k = 1:numel(info.Datasets)
    group = info.Name;
    if strcmp(group, '/'), group = ''; end
    paths{end + 1} = [group '/' info.Datasets(k).Name]; %#ok<AGROW>
end

for k = 1:numel(info.Groups)
    paths = [paths, collectDatasets(info.Groups(k))]; %#ok<AGROW>
end

end

function [oriented, transform, accepted] = orientRegions(reference, masks)
% Eight exact pixel permutations; transform applies to h5read output.
names = fieldnames(masks);
labels = {'Identity', 'Rotate 90 CCW', 'Rotate 180', 'Rotate 270 CCW', ...
              'Flip left-right', 'Flip LR then rotate 90 CCW', ...
              'Flip LR then rotate 180', 'Flip LR then rotate 270 CCW'};
oriented = struct();
transform = struct();
accepted = false;
fig = uifigure('Name', 'DopplerView masks: verify alignment', ...
    'Position', [100 100 1000 780], 'Color', [0.08 0.09 0.12], ...
    'WindowStyle', 'modal');
cleanup = onCleanup(@() deleteIfValid(fig)); %#ok<NASGU>
fig.CloseRequestFcn = @(~, ~) cancel();
grid = uigridlayout(fig, [4 3]);
grid.RowHeight = {36, '1x', 48, 38};
grid.ColumnWidth = {'1x', '1x', 140};
grid.BackgroundColor = fig.Color;
region = uidropdown(grid, 'Items', names, 'ValueChangedFcn', @(~, ~) redraw());
region.Layout.Row = 1; region.Layout.Column = 1;
operation = uidropdown(grid, 'Items', labels, 'ValueChangedFcn', @(~, ~) redraw());
operation.Layout.Row = 1; operation.Layout.Column = [2 3];
ax = uiaxes(grid); ax.Layout.Row = 2; ax.Layout.Column = [1 3];
message = uilabel(grid, 'FontColor', [0.9 0.9 0.95], 'WordWrap', 'on');
message.Layout.Row = 3; message.Layout.Column = [1 3];
button = uibutton(grid, 'Text', 'Apply to ALL masks', ...
    'ButtonPushedFcn', @(~, ~) accept());
button.Layout.Row = 4; button.Layout.Column = [1 2];
cancelButton = uibutton(grid, 'Text', 'Cancel', 'ButtonPushedFcn', @(~, ~) cancel());
cancelButton.Layout.Row = 4; cancelButton.Layout.Column = 3;

redraw();

if isgraphics(fig)
    uiwait(fig);
end

if isgraphics(fig)
    delete(fig);
end

function redraw()
    index = find(strcmp(operation.Value, labels), 1);
    mask = transformMask(masks.(region.Value), index);

    try
        mask = fitMaskToEyeFlowGrid( ...
            mask, [size(reference, 1), size(reference, 2)]);
    catch ME
        cla(ax);
        imagesc(ax, reference);
        colormap(ax, gray(256));
        axis(ax, 'image');
        axis(ax, 'off');

        message.Text = ME.message;
        button.Enable = 'off';
        return;
    end

    cla(ax);
    imagesc(ax, reference);
    colormap(ax, gray(256));
    axis(ax, 'image'); axis(ax, 'off');
    ax.YDir = 'reverse';
    match = isequal(size(mask), size(reference));

    if match
        hold(ax, 'on');
        rgb = zeros([size(mask), 3]);
        rgb(:, :, 1) = 1; rgb(:, :, 2) = 0.3;
        image(ax, rgb, 'AlphaData', 0.35 * double(mask));
        hold(ax, 'off');
        message.Text = ['Check vascular alignment, not just image size. ' ...
                        'The same operation will apply to every imported region.'];
        button.Enable = 'on';
    else
        message.Text = sprintf(['Size mismatch: mask %s, image %s. ' ...
                                'Try a quarter-turn. No resizing is applied.'], ...
            mat2str(size(mask)), mat2str(size(reference)));
        button.Enable = 'off';
    end

end

function accept()
    index = find(strcmp(operation.Value, labels), 1);
    imageSize = [size(reference, 1), size(reference, 2)];

    % Build all validated masks before accepting the import.
    validatedMasks = struct();

    for j = 1:numel(names)
        mask = transformMask(masks.(names{j}), index);

        validatedMasks.(names{j}) = ...
            fitMaskToEyeFlowGrid(mask, imageSize);
    end

    oriented = validatedMasks;

    transform.Label = labels{index};
    transform.FlipLeftRightBeforeRotation = index > 4;
    transform.QuarterTurnsCounterclockwise = mod(index - 1, 4);

    firstMask = transformMask(masks.(names{1}), index);

    transform.OrientedSourceSize = ...
        [size(firstMask, 1), size(firstMask, 2)];

    transform.TargetSize = imageSize;
    transform.Resampling = 'nearest';
    transform.GridMapping = ...
        'Endpoint-aligned: target = (source - 1) * 2^k + 1';

    transform.AppliesTo = ...
        'MATLAB h5read array: orientation first, then grid mapping';

    accepted = true;

    if isgraphics(fig)
        delete(fig);
    end

end

function cancel()
    accepted = false;
    oriented = struct();
    transform = struct();

    if isgraphics(fig)
        delete(fig);
    end

end

end

function mask = transformMask(mask, index)
if index > 4, mask = fliplr(mask); end
mask = rot90(mask, mod(index - 1, 4));
end

function deleteIfValid(fig)
if isgraphics(fig), delete(fig); end
end

function mask = readDVBinaryMask(source, dataset)
% Read binary masks stored as logical, numeric or HDF5 boolean enums.

raw = h5read(source, dataset);

originalClass = class(raw);
originalSize = size(raw);

if isempty(raw)
    error('EyeFlow:EmptyRegion', ...
        'Empty dataset: %s.', dataset);
end

if islogical(raw)
    mask = raw;

elseif isnumeric(raw)

    if ~isreal(raw)
        error('EyeFlow:ComplexRegion', ...
            'Complex-valued mask: %s.', dataset);
    end

    values = double(raw);

    if any(~isfinite(values(:))) || ...
            any(~ismember(values(:), [0 1 255]))
        error('EyeFlow:NonBinaryRegion', ...
            ['%s must contain only 0/1 or 0/255. ', ...
         'Received class=%s, size=%s.'], ...
            dataset, originalClass, mat2str(originalSize));
    end

    mask = raw ~= 0;

elseif isstring(raw) || iscellstr(raw)
    % h5read can return enum member names rather than numeric values.
    labels = upper(strtrim(string(raw)));

    trueValues = ["TRUE", "H5_TRUE", "1", "255"];
    falseValues = ["FALSE", "H5_FALSE", "0"];

    known = ~ismissing(labels) & ...
        (ismember(labels, trueValues) | ...
        ismember(labels, falseValues));

    if ~all(known(:))
        error('EyeFlow:UnknownMaskEnum', ...
            ['Unsupported enum labels in %s. ', ...
         'Expected TRUE/FALSE, H5_TRUE/H5_FALSE or 0/1/255.'], ...
            dataset);
    end

    mask = ismember(labels, trueValues);

else
    error('EyeFlow:UnsupportedMaskType', ...
        'Unsupported mask type in %s: class=%s, size=%s.', ...
        dataset, originalClass, mat2str(originalSize));
end

% Accept redundant singleton dimensions, not genuine 3-D volumes.
if ndims(mask) > 2
    mask = squeeze(mask);
end

if ~ismatrix(mask) || isempty(mask)
    error('EyeFlow:InvalidRegionDimensions', ...
        ['%s is not a 2-D mask after removing singleton axes. ', ...
     'Original class=%s, original size=%s, decoded size=%s.'], ...
        dataset, originalClass, ...
        mat2str(originalSize), mat2str(size(mask)));
end

mask = logical(mask);
end

function mask = fitMaskToEyeFlowGrid(mask, targetSize)
% Match EyeFlow's endpoint-aligned interpolation grid.
% Orientation must already have been applied.
% Nearest-neighbor preserves binary mask values.

mask = logical(mask);
sourceSize = [size(mask, 1), size(mask, 2)];
targetSize = double(targetSize(:).');

if isequal(sourceSize, targetSize)
    return;
end

if any(sourceSize < 2) || any(targetSize < sourceSize)
    error('EyeFlow:UnsupportedMaskGrid', ...
        'Cannot map mask %s onto image %s.', ...
        mat2str(sourceSize), mat2str(targetSize));
end

% EyeFlow interpolation: target = (source - 1) * 2^k + 1.
scale = (targetSize - 1) ./ (sourceSize - 1);
k = round(log2(scale));

if any(k < 0) || ...
        any(abs(scale - 2 .^ k) > 1e-10) || ...
        k(1) ~= k(2)
    error('EyeFlow:UnsupportedMaskGrid', ...
        ['Mask %s and image %s do not match EyeFlow''s ', ...
         'uniform 2^k interpolation grid. ', ...
     'Check cropping and field of view.'], ...
        mat2str(sourceSize), mat2str(targetSize));
end

% Match interp2's original pixel-center coordinates exactly.
xq = linspace(1, sourceSize(2), targetSize(2));
yq = linspace(1, sourceSize(1), targetSize(1));
[Xq, Yq] = meshgrid(xq, yq);

mask = interp2( ...
    double(mask), Xq, Yq, 'nearest') > 0.5;
end
