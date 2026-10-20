function A = spectrum_masks(SH_avg, regionMasks, opt)
% spectrum_masks
% Figures et données des spectres moyens par région.
%
% INPUTS
%   SH_avg :
%       Cube réel de PSD, [nRows, nCols, nFreq].
%       Déjà moyenné temporellement, sans transformation supplémentaire.
%
%   regionMasks :
%       Structure de masques 2D dans le même repère spatial que SH_avg.
%
% OPTIONS
%   frequency :
%       Fréquences correspondant aux tranches de SH_avg, dans leur ordre
%       actuel. Obligatoire : aucune convention FFT n'est supposée.
%
%   frequencyUnit :
%       Unité du vecteur frequency : "Hz" ou "kHz".
%
%   analysisBandHz :
%       Bande d'analyse sur abs(f), en Hz.
%       Vide : tous les bins disponibles.
%
%   maskDomain :
%       Domaine spatial utilisé, par défaut toute l'image.
%
%   regionColors :
%       Couleurs hexadécimales ou triplets RGB par région.
%
%   referenceImage :
%       Image 2D facultative pour afficher les contours des régions.
%
% OUTPUT
%   A :
%       Spectres, effectifs valides, moments, masques et métadonnées.
%
% EXPORTS
%   PNG/PDF, CSV des spectres et moments, MAT des résultats.
%
% Aucun accès au ToolBox global.
% Aucun recalage, redimensionnement, fftshift ou carré implicite.

arguments
    SH_avg
    regionMasks (1, 1) struct

    opt.frequency double = []
    opt.frequencyUnit (1, 1) string ...
        {mustBeMember(opt.frequencyUnit, ["Hz", "kHz"])} = "Hz"

    opt.analysisBandHz double = []

    opt.maskDomain = []
    opt.regionColors (1, 1) struct = struct()
    opt.referenceImage = []

    opt.outputDir (1, 1) string = "spectral_analysis"
    opt.prefix (1, 1) string = "SH_avg"

    opt.sourceFile (1, 1) string = ""
    opt.datasetPath (1, 1) string = ""

    opt.resolution (1, 1) double ...
        {mustBePositive, mustBeFinite} = 300

    opt.visible (1, 1) string ...
        {mustBeMember(opt.visible, ["on", "off"])} = "off"
end

%% Validation du cube et des fréquences

if ~isnumeric(SH_avg) || ~isreal(SH_avg) || ...
        isempty(SH_avg) || ndims(SH_avg) > 3
    error('spectrum_masks:invalidCube', ...
    'SH_avg must be a nonempty real numeric spatial-spectral cube.');
end

[nRows, nCols, nFreq] = size(SH_avg);

if nFreq < 2
    error('spectrum_masks:insufficientFrequencies', ...
    'At least two frequency bins are required.');
end

if isempty(opt.frequency) || ~isvector(opt.frequency) || ...
        numel(opt.frequency) ~= nFreq || ...
        ~isreal(opt.frequency) || any(~isfinite(opt.frequency(:)))
    error('spectrum_masks:invalidFrequency', ...
    'frequency must contain one finite real value per spectral bin.');
end

frequencyHz = double(opt.frequency(:));

if opt.frequencyUnit == "kHz"
    frequencyHz = 1000 * frequencyHz;
end

[frequencyHz, frequencyOrder] = sort(frequencyHz);

if any(diff(frequencyHz) <= 0)
    error('spectrum_masks:duplicateFrequency', ...
    'Frequency values must be distinct.');
end

if isempty(opt.analysisBandHz)
    band = true(nFreq, 1);
else
    b = opt.analysisBandHz;

    if ~isreal(b) || numel(b) ~= 2 || ...
            any(~isfinite(b(:))) || ...
            any(b(:) < 0) || b(2) <= b(1)
        error('spectrum_masks:invalidBand', ...
        'analysisBandHz must contain increasing nonnegative bounds.');
    end

    band = abs(frequencyHz) >= b(1) & ...
        abs(frequencyHz) <= b(2);
end

if ~any(band)
    error('spectrum_masks:emptyBand', ...
    'No frequency bin lies inside the analysis band.');
end

% Bin widths inferred from midpoint edges.
% Each selected bin contributes its full width.
edges = [
         frequencyHz(1) - (frequencyHz(2) - frequencyHz(1)) / 2
         (frequencyHz(1:end - 1) + frequencyHz(2:end)) / 2
         frequencyHz(end) + (frequencyHz(end) - frequencyHz(end - 1)) / 2
         ];

binWidthHz = diff(edges);

%% Domaine et image de référence

if isempty(opt.maskDomain)
    domain = true(nRows, nCols);
else
    domain = validateMask(opt.maskDomain, [nRows nCols], 'maskDomain');
end

if ~any(domain, 'all')
    error('spectrum_masks:emptyDomain', ...
    'The spatial domain is empty.');
end

if ~isempty(opt.referenceImage)

    if ~isnumeric(opt.referenceImage) || ...
            ~isreal(opt.referenceImage) || ...
            ~isequal(size(opt.referenceImage), [nRows nCols])
        error('spectrum_masks:invalidReferenceImage', ...
        'referenceImage must match the spatial size of SH_avg.');
    end

end

%% Régions et couleurs

allNames = fieldnames(regionMasks);
defaultColors = lines(numel(allNames));

names = cell(0, 1);
masks = cell(0, 1);
colors = zeros(0, 3);

for k = 1:numel(allNames)
    name = allNames{k};

    m = validateMask(regionMasks.(name), [nRows nCols], name);
    m = m & domain;

    if ~any(m, 'all')
        warning('spectrum_masks:emptyMask', ...
            'Mask %s is empty inside the domain: skipped.', name);
        continue
    end

    c = defaultColors(k, :);

    if isfield(opt.regionColors, name)
        c = parseColor(opt.regionColors.(name));
    end

    names{end + 1, 1} = name;
    masks{end + 1, 1} = m;
    colors(end + 1, :) = c;
end

K = numel(names);

if K == 0
    error('spectrum_masks:noRegion', ...
    'No nonempty regional mask was provided.');
end

%% Spectres régionaux
% Calcul fréquence par fréquence pour limiter les tableaux temporaires.
% Valeurs non finies : exclues et comptées.
% Valeurs négatives : erreur, car l'entrée est déclarée comme une PSD.

regional = nan(nFreq, K);
validCounts = zeros(nFreq, K);
domainSpectrum = nan(nFreq, 1);
domainValidCounts = zeros(nFreq, 1);

for j = 1:nFreq
    frame = double(SH_avg(:, :, frequencyOrder(j)));
    finiteDomain = domain & isfinite(frame);

    if any(frame(finiteDomain) < 0)
        error('spectrum_masks:negativePSD', ...
            'Negative PSD values found in the domain at input bin %d.', ...
            frequencyOrder(j));
    end

    values = frame(domain);
    good = isfinite(values);

    domainValidCounts(j) = nnz(good);

    if any(good)
        domainSpectrum(j) = mean(values(good));
    end

    for k = 1:K
        values = frame(masks{k});
        good = isfinite(values);

        validCounts(j, k) = nnz(good);

        if any(good)
            regional(j, k) = mean(values(good));
        end

    end

end

pixelCount = cellfun(@nnz, masks);

if any(domainValidCounts < nnz(domain))
    warning('spectrum_masks:nonFinitePSD', ...
        ['Nonfinite PSD values were excluded. ', ...
     'Valid pixel counts are exported for every frequency.']);
end

%% Moments et normalisation
% Ne pas intégrer à travers une lacune de fréquence :
% somme pondérée par la largeur de chaque bin.
%
% M1 utilise f signé.
% MeanAbsFrequency utilise abs(f).
% Les moments d'une région restent NaN si un bin sélectionné est manquant.

M0 = nan(K, 1);
M1 = nan(K, 1);
M2 = nan(K, 1);

meanFrequencyHz = nan(K, 1);
meanAbsFrequencyHz = nan(K, 1);
rmsFrequencyHz = nan(K, 1);

normalized = nan(nFreq, K);

weights = binWidthHz(band);
f = frequencyHz(band);

for k = 1:K
    S = regional(band, k);

    if any(~isfinite(S))
        warning('spectrum_masks:incompleteSpectrum', ...
            'Region %s has missing bins in the analysis band.', names{k});
        continue
    end

    weightedPSD = S .* weights;

    M0(k) = sum(weightedPSD);
    M1(k) = sum(f .* weightedPSD);
    M2(k) = sum(f .^ 2 .* weightedPSD);

    if isfinite(M0(k)) && M0(k) > 0
        meanFrequencyHz(k) = M1(k) / M0(k);

        meanAbsFrequencyHz(k) = ...
            sum(abs(f) .* weightedPSD) / M0(k);

        rmsFrequencyHz(k) = sqrt(M2(k) / M0(k));

        normalized(:, k) = regional(:, k) / M0(k);
    end

end

%% Résultats

A = struct();

A.frequencyHz = frequencyHz;
A.binWidthHz = binWidthHz;
A.analysisBinMask = band;

A.regionNames = names;
A.colors = colors;
A.domain = domain;

A.spectra = regional;
A.normalizedSpectra = normalized;
A.domainSpectrum = domainSpectrum;

A.validPixelCounts = validCounts;
A.domainValidPixelCounts = domainValidCounts;

for k = 1:K
    A.masks.(names{k}) = masks{k};
end

A.moments = table( ...
    string(names), pixelCount, M0, M1, M2, ...
    meanFrequencyHz, meanAbsFrequencyHz, rmsFrequencyHz, ...
    'VariableNames', { ...
       'Region', 'PixelCount', 'M0', 'M1', 'M2', ...
       'MeanFrequencyHz', 'MeanAbsFrequencyHz', 'RMSFrequencyHz'});

A.metadata.sourceFile = opt.sourceFile;
A.metadata.datasetPath = opt.datasetPath;
A.metadata.inputFrequencyUnit = opt.frequencyUnit;
A.metadata.inputFrequency = opt.frequency(:);
A.metadata.frequencyOrder = frequencyOrder;
A.metadata.analysisBandHz = opt.analysisBandHz;

A.metadata.inputQuantity = ...
    'Supplied temporally averaged PSD, without additional transformation';

A.metadata.spatialReference = ...
    'Masks and cube must already share the same spatial reference';

A.metadata.integration = ...
    'Full selected bin widths inferred from frequency midpoint edges';

A.metadata.normalization = ...
    'Regional PSD divided by its integrated analysis-band power';

A.metadata.missingData = ...
    'Finite-pixel mean per bin; moments require all selected bins';

A.metadata.powerUnits = ...
    'Input PSD unit multiplied by Hz; input amplitude calibration unspecified';

%% Préparation des exports

outDir = char(opt.outputDir);

if ~isfolder(outDir)
    mkdir(outDir);
end

x = frequencyHz / 1000;

%% Figure 1 : spectres bruts linéaires et logarithmiques

fig = newFigure(opt, [100 100 1200 850]);
cleanup = onCleanup(@() close(fig));

tl = tiledlayout(fig, 2, 1, ...
    'TileSpacing', 'compact', 'Padding', 'compact');

ax1 = nexttile(tl);
plotSpectra(ax1, x, regional, colors, names);

ylabel(ax1, 'Mean PSD (input units)');
title(ax1, 'Regional mean spectra', 'Interpreter', 'none');

legend(ax1, 'Interpreter', 'none', 'Location', 'eastoutside');

ax2 = nexttile(tl);

positivePSD = regional;
positivePSD(positivePSD <= 0) = NaN;

plotSpectra(ax2, x, positivePSD, colors, names);
set(ax2, 'YScale', 'log');

ylabel(ax2, 'Mean PSD (input units, log scale)');
xlabel(ax2, 'Frequency (kHz)');

title(ax2, 'Positive PSD values only', 'Interpreter', 'none');

linkaxes([ax1 ax2], 'x');

exportFigure(fig, outDir, ...
    opt.prefix + "_spectra", opt.resolution);

clear cleanup

%% Figure 2 : spectres normalisés par la puissance de bande

fig = newFigure(opt, [100 100 1200 650]);
cleanup = onCleanup(@() close(fig));

ax = axes(fig);
plotSpectra(ax, x, normalized, colors, names);

xlabel(ax, 'Frequency (kHz)');
ylabel(ax, 'PSD / analysis-band power (Hz^{-1})');

title(ax, 'Band-power-normalized regional spectra', ...
    'Interpreter', 'none');

legend(ax, 'Interpreter', 'none', 'Location', 'eastoutside');

exportFigure(fig, outDir, ...
    opt.prefix + "_normalized_spectra", opt.resolution);

clear cleanup

%% Figure 3 : localisation des régions, si une référence est fournie

if ~isempty(opt.referenceImage)
    fig = newFigure(opt, [100 100 1100 850]);
    cleanup = onCleanup(@() close(fig));

    ax = axes(fig);

    base = double(opt.referenceImage);
    base(~domain | ~isfinite(base)) = NaN;

    imageHandle = imagesc(ax, base);
    imageHandle.AlphaData = isfinite(base);

    axis(ax, 'image');
    axis(ax, 'off');
    colormap(ax, gray(256));
    set(ax, 'Color', 'k');

    hold(ax, 'on');
    handles = gobjects(K, 1);

    for k = 1:K

        if any(masks{k}(:)) && any(~masks{k}(:))
            contour(ax, double(masks{k}), [0.5 0.5], ...
                'Color', colors(k, :), 'LineWidth', 0.8);
        end

        handles(k) = plot(ax, NaN, NaN, '-', ...
            'Color', colors(k, :), 'LineWidth', 1.5);
    end

    legend(ax, handles, names, ...
        'Interpreter', 'none', 'Location', 'eastoutside');

    title(ax, 'Spectral analysis regions', 'Interpreter', 'none');

    exportFigure(fig, outDir, ...
        opt.prefix + "_regions", opt.resolution);

    clear cleanup
end

%% CSV et MAT

T = table( ...
    frequencyHz, binWidthHz, band, ...
    domainSpectrum, domainValidCounts, ...
    'VariableNames', { ...
       'FrequencyHz', 'BinWidthHz', 'InAnalysisBand', ...
       'DomainPSD', 'DomainValidPixels'});

for k = 1:K
    name = names{k};

    T.(['PSD_' name]) = regional(:, k);
    T.(['Normalized_' name]) = normalized(:, k);
    T.(['ValidPixels_' name]) = validCounts(:, k);
end

writetable(T, ...
    fullfile(outDir, char(opt.prefix + "_spectra.csv")));

writetable(A.moments, ...
    fullfile(outDir, char(opt.prefix + "_moments.csv")));

save(fullfile(outDir, char(opt.prefix + "_results.mat")), ...
    'A', '-v7.3');

end

function m = validateMask(value, spatialSize, name)

if ~(isnumeric(value) || islogical(value)) || ...
        ~isreal(value) || ~isequal(size(value), spatialSize)
    error('spectrum_masks:invalidMask', ...
        ['Mask %s must match the spatial size of SH_avg. ', ...
     'No automatic resizing is performed.'], ...
        name);
end

m = isfinite(value) & value ~= 0;

end

function rgb = parseColor(value)

if isnumeric(value)

    if ~isreal(value) || numel(value) ~= 3 || ...
            any(~isfinite(value(:))) || ...
            any(value(:) < 0 | value(:) > 1)
        error('spectrum_masks:invalidColor', ...
        'RGB colors must contain three finite values in [0, 1].');
    end

    rgb = reshape(double(value), 1, 3);
    return
end

if isstring(value) && isscalar(value)
    value = char(value);
end

if ~ischar(value) || ~isrow(value)
    error('spectrum_masks:invalidColor', ...
    'Expected a hexadecimal color or an RGB triplet.');
end

value = strtrim(value);

if startsWith(value, '#')
    value = value(2:end);
end

if isempty(regexp(value, '^[0-9A-Fa-f]{6}$', 'once'))
    error('spectrum_masks:invalidColor', ...
        'Invalid hexadecimal color: %s', value);
end

rgb = [
       hex2dec(value(1:2)), ...
           hex2dec(value(3:4)), ...
           hex2dec(value(5:6))
       ] / 255;

end

function fig = newFigure(opt, position)

fig = figure( ...
    'Visible', char(opt.visible), ...
    'Color', 'w', ...
    'Position', position);

end

function plotSpectra(ax, frequency, spectra, colors, names)

hold(ax, 'on');

for k = 1:numel(names)
    plot(ax, frequency, spectra(:, k), ...
        'Color', colors(k, :), ...
        'LineWidth', 1.3, ...
        'DisplayName', names{k});
end

grid(ax, 'on');
box(ax, 'on');

xlim(ax, [frequency(1), frequency(end)]);

end

function exportFigure(fig, outDir, stem, resolution)

pngFile = fullfile(outDir, char(stem + ".png"));
pdfFile = fullfile(outDir, char(stem + ".pdf"));

if isfile(pngFile)
    delete(pngFile);
end

exportgraphics(fig, pngFile, 'Resolution', resolution);

if isfile(pdfFile)
    delete(pdfFile);
end

exportgraphics(fig, pdfFile, 'ContentType', 'vector');

end
