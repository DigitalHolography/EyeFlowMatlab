function A = bandRatioArticleFigures( ...
    M0_ff, HF_M0, LF_M0, bandRatio, regionMasks, opt)
% bandRatioArticleFigures
% Figures et données pour un article sur le Doppler band ratio.
%
% INPUTS
%   M0_ff, HF_M0, LF_M0, bandRatio :
%       cubes réels de taille [nRows, nCols, nFrames],
%       déjà alignés spatialement ET temporellement.
%
%   regionMasks :
%       structure de masques 2D, dans les coordonnées des cubes.
%
% OPTIONS
%   maskDomain :
%       diaphragme utilisé pour les moyennes globales.
%       Par défaut : toute l'image.
%
%   regionColors :
%       structure, par exemple :
%       struct('RetinaArtery', '#FF1612', ...
%              'RetinaVein',   '#1217FF')
%
%   time :
%       vecteur temporel en secondes. Si vide : numéro de frame.
%
%   outputDir :
%       dossier de sortie.
%
%   prefix :
%       préfixe des noms de fichiers.
%
%   lowBandHz, highBandHz :
%       métadonnées des bandes, utilisées dans les titres.
%       Elles ne recalculent pas les bandes.
%
%   bandValues :
%       "unknown" : convention non spécifiée.
%       "integrated" : HF/LF sont des puissances intégrées.
%       "meanPSD" : HF/LF sont des moyennes spectrales par bande.
%
%   minLF :
%       seuil strict LF > minLF pour le quotient de contrôle.
%       Ne modifie PAS le bandRatio fourni.
%
% OUTPUT
%   A : cartes, signaux, masques, couleurs et métadonnées.
%
% EXPORTS
%   PNG et PDF des figures, CSV des signaux, MAT des résultats.
%
% Important :
%   mean(HF ./ LF) n'est pas identique à mean(HF) ./ mean(LF).
%   Le bandRatio fourni reste distinct du quotient de contrôle.

arguments
    M0_ff
    HF_M0
    LF_M0
    bandRatio
    regionMasks (1, 1) struct

    opt.maskDomain = []
    opt.regionColors (1, 1) struct = struct()
    opt.time = []

    opt.outputDir (1, 1) string = "band_ratio_article"
    opt.prefix (1, 1) string = "article"

    opt.lowBandHz (1, 2) double = [3000 9000]
    opt.highBandHz (1, 2) double = [9000 18000]
    opt.bandValues (1, 1) string ...
        {mustBeMember(opt.bandValues, ...
         ["unknown", "integrated", "meanPSD"])} = "unknown"

    opt.minLF (1, 1) double ...
        {mustBeNonnegative, mustBeFinite} = 0

    opt.overlayAlpha (1, 1) double ...
        {mustBeGreaterThanOrEqual(opt.overlayAlpha, 0), ...
         mustBeLessThanOrEqual(opt.overlayAlpha, 1)} = 0.35

    opt.resolution (1, 1) double ...
        {mustBePositive, mustBeFinite} = 300

    opt.visible (1, 1) string ...
        {mustBeMember(opt.visible, ["on", "off"])} = "off"
end

%% Validation

sz = size(M0_ff);

if isempty(M0_ff) || size(M0_ff, 3) < 2 || ndims(M0_ff) > 3
    error('bandRatioArticleFigures:invalidVideo', ...
    'Expected a non-empty spatial video with at least two frames.');
end

inputs = {M0_ff, HF_M0, LF_M0, bandRatio};

for j = 1:numel(inputs)
    X = inputs{j};

    if ~isnumeric(X) || ~isreal(X) || ~isequal(size(X), sz)
        error('bandRatioArticleFigures:sizeMismatch', ...
        'The four inputs must be real numeric cubes of identical size.');
    end

end

if any(~isfinite([opt.lowBandHz, opt.highBandHz])) || ...
        any(opt.lowBandHz < 0) || any(opt.highBandHz < 0) || ...
        diff(opt.lowBandHz) <= 0 || diff(opt.highBandHz) <= 0

    error('bandRatioArticleFigures:invalidBands', ...
    'Frequency bands must have finite, increasing, nonnegative bounds.');
end

[nRows, nCols, nt] = size(M0_ff);

if isempty(opt.maskDomain)
    domain = true(nRows, nCols);
else
    m = opt.maskDomain;

    if ~(isnumeric(m) || islogical(m)) || ...
            ~isreal(m) || ~isequal(size(m), [nRows nCols])
        error('bandRatioArticleFigures:invalidDomain', ...
        'maskDomain must match the spatial size.');
    end

    domain = isfinite(m) & m ~= 0;
end

if ~any(domain, 'all')
    error('bandRatioArticleFigures:emptyDomain', ...
    'The diaphragm/domain is empty.');
end

if isempty(opt.time)
    x = (1:nt).';
    xLabel = 'Frame';
else
    x = double(opt.time(:));

    if numel(x) ~= nt || any(~isfinite(x)) || any(diff(x) <= 0)
        error('bandRatioArticleFigures:invalidTime', ...
        'time must contain one finite, increasing value per frame.');
    end

    xLabel = 'Time (s)';
end

outDir = char(opt.outputDir);

if ~isfolder(outDir)
    mkdir(outDir);
end

%% Masques et couleurs

allNames = fieldnames(regionMasks);
names = {};
masks = {};
colors = zeros(0, 3);

defaultColors = lines(numel(allNames));

for k = 1:numel(allNames)
    name = allNames{k};

    if strcmpi(name, 'Diaphragm')
        continue
    end

    m = regionMasks.(name);

    if ~(isnumeric(m) || islogical(m)) || ...
            ~isreal(m) || ~isequal(size(m), [nRows nCols])

        warning('bandRatioArticleFigures:invalidMask', ...
            'Invalid mask %s: skipped.', name);
        continue
    end

    m = isfinite(m) & m ~= 0 & domain;

    if ~any(m, 'all')
        warning('bandRatioArticleFigures:emptyMask', ...
            'Mask %s is empty inside the domain: skipped.', name);
        continue
    end

    c = defaultColors(k, :);

    if isfield(opt.regionColors, name)
        value = opt.regionColors.(name);

        if strlength(string(value)) > 0
            c = hexToRGB(value);
        end

    end

    names{end + 1, 1} = name; %#ok<AGROW>
    masks{end + 1, 1} = m; %#ok<AGROW>
    colors(end + 1, :) = c; %#ok<AGROW>
end

K = numel(names);

if K == 0
    error('bandRatioArticleFigures:noRegion', ...
    'No valid regional mask was provided.');
end

%% Préparation des résultats

fields = {'M0', 'LF', 'HF', 'BandRatio'};

% Les cubes d'entrée ne sont pas modifiés.
cubes = {M0_ff, LF_M0, HF_M0, bandRatio};

A = struct();
A.time = x;
A.timeLabel = xLabel;
A.regionNames = names;
A.colors = colors;
A.domain = domain;

for k = 1:K
    A.masks.(names{k}) = masks{k};
end

A.metadata.lowBandHz = opt.lowBandHz;
A.metadata.highBandHz = opt.highBandHz;
A.metadata.bandValues = opt.bandValues;
A.metadata.minLF = opt.minLF;
A.metadata.inputRatio = ...
    'Supplied bandRatio, without additional correction';
A.metadata.diaphragmNormalization = ...
    'Regional mean divided by instantaneous domain mean';
A.metadata.mapDisplay = ...
    'Independent linear display ranges for each quantity';

%% Cartes et signaux régionaux

for j = 1:numel(fields)
    field = fields{j};

    X = reshape(single(cubes{j}), nRows * nCols, nt);
    X(~isfinite(X)) = NaN;

    map = reshape(mean(X, 2, 'omitnan'), nRows, nCols);
    map(~domain) = NaN;

    globalSignal = double( ...
        mean(X(domain(:), :), 1, 'omitnan')).';

    regional = nan(nt, K);

    for k = 1:K
        regional(:, k) = double( ...
            mean(X(masks{k}(:), :), 1, 'omitnan')).';
    end

    normalized = nan(nt, K);
    good = isfinite(globalSignal) & globalSignal ~= 0;

    normalized(good, :) = ...
        regional(good, :) ./ globalSignal(good);

    if any(~good)
        warning('bandRatioArticleFigures:invalidDomainSignal', ...
            ['%s: %d frame(s) cannot be diaphragm-normalized; ', ...
         'the corresponding values are NaN.'], ...
            field, nnz(~good));
    end

    A.maps.(field) = map;
    A.domainSignals.(field) = globalSignal;
    A.raw.(field) = regional;
    A.relative.(field) = relativeVariation(regional);
    A.normalized.(field) = normalized;
end

%% Quotient HF/LF indépendant, sans soustraction d'offset

% Ce contrôle n'écrase jamais le bandRatio fourni.
quotientRegional = nan(nt, K);
quotientDomain = nan(nt, 1);
quotientMap = nan(nRows, nCols, 'single');

ratioSum = zeros(nRows, nCols, 'double');
ratioCount = zeros(nRows, nCols, 'double');

for it = 1:nt
    h = double(HF_M0(:, :, it));
    l = double(LF_M0(:, :, it));

    good = domain & isfinite(h) & isfinite(l) & ...
        l > opt.minLF;

    q = nan(nRows, nCols);
    q(good) = h(good) ./ l(good);

    % Contrôler également un éventuel dépassement numérique.
    good = good & isfinite(q);
    q(~good) = NaN;

    ratioSum(good) = ratioSum(good) + q(good);
    ratioCount(good) = ratioCount(good) + 1;

    quotientDomain(it) = mean(q(domain), 'omitnan');

    for k = 1:K
        quotientRegional(it, k) = ...
            mean(q(masks{k}), 'omitnan');
    end

end

good = ratioCount > 0;
quotientMap(good) = single(ratioSum(good) ./ ratioCount(good));

A.quotientHFoverLF.regional = quotientRegional;
A.quotientHFoverLF.domain = quotientDomain;
A.quotientHFoverLF.map = quotientMap;

% Conversion optionnelle vers le rapport des densités moyennes.
if opt.bandValues == "integrated"
    factor = diff(opt.lowBandHz) / diff(opt.highBandHz);
elseif opt.bandValues == "meanPSD"
    factor = 1;
else
    factor = NaN;
end

A.metadata.meanPSDRatioFactor = factor;

if isfinite(factor)
    A.meanPSDRatio.regional = factor * quotientRegional;
    A.meanPSDRatio.domain = factor * quotientDomain;
    A.meanPSDRatio.map = factor * quotientMap;
end

%% Figure 1 : quatre cartes

f = newFigure(opt, [100 100 1200 950]);
cleanup = onCleanup(@() close(f));

tl = tiledlayout(f, 2, 2, ...
    'TileSpacing', 'compact', 'Padding', 'compact');

mapFields = {'M0', 'BandRatio', 'LF', 'HF'};

mapTitles = {
             '(a) Mean M0 ff'
             '(b) Mean supplied band ratio'
             sprintf('(c) Mean LF: %.1f-%.1f kHz', opt.lowBandHz / 1000)
             sprintf('(d) Mean HF: %.1f-%.1f kHz', opt.highBandHz / 1000)
             };

for j = 1:4
    ax = nexttile(tl);

    imageHandle = imagesc(ax, A.maps.(mapFields{j}));
    imageHandle.AlphaData = ...
        domain & isfinite(A.maps.(mapFields{j}));

    axis(ax, 'image');
    axis(ax, 'off');
    set(ax, 'Color', 'k');
    colormap(ax, gray(256));
    colorbar(ax);

    hold(ax, 'on');

    for k = 1:K
        contour(ax, double(masks{k}), [0.5 0.5], ...
            'Color', colors(k, :), 'LineWidth', 0.65);
    end

    title(ax, mapTitles{j}, 'Interpreter', 'none');
end

exportFigure(f, outDir, opt.prefix + "_maps", opt.resolution);
clear cleanup

%% Figure 2 : régions colorées

rgb = makeOverlay( ...
    A.maps.M0, domain, masks, colors, opt.overlayAlpha);

file = fullfile(outDir, char(opt.prefix + "_regions.png"));
deleteIfExists(file);
imwrite(rgb, file);

f = newFigure(opt, [100 100 1100 850]);
cleanup = onCleanup(@() close(f));

ax = axes(f);
image(ax, rgb);
axis(ax, 'image');
axis(ax, 'off');
hold(ax, 'on');

handles = gobjects(K, 1);

for k = 1:K
    handles(k) = plot(ax, NaN, NaN, 's', ...
        'MarkerFaceColor', colors(k, :), ...
        'MarkerEdgeColor', colors(k, :), ...
        'MarkerSize', 8);
end

legend(ax, handles, names, ...
    'Interpreter', 'none', 'Location', 'eastoutside');

title(ax, 'Regions on mean M0 ff', 'Interpreter', 'none');

exportFigure(f, outDir, ...
    opt.prefix + "_regions_legend", opt.resolution);
clear cleanup

%% Figure 3 : signaux régionaux, sans division diaphragmatique

f = newFigure(opt, [100 100 1250 1050]);
cleanup = onCleanup(@() close(f));

tl = tiledlayout(f, 4, 1, ...
    'TileSpacing', 'compact', 'Padding', 'compact');

axesList = gobjects(4, 1);

for j = 1:4
    ax = nexttile(tl);
    axesList(j) = ax;

    plotRegions(ax, x, A.raw.(fields{j}), colors, names);

    ylabel(ax, fields{j}, 'Interpreter', 'none');
    title(ax, ['Regional mean: ' fields{j}], ...
        'Interpreter', 'none');

    if j == 1
        legend(ax, 'Interpreter', 'none', ...
            'Location', 'eastoutside');
    end

end

xlabel(axesList(end), xLabel);
linkaxes(axesList, 'x');

exportFigure(f, outDir, ...
    opt.prefix + "_regional_signals", opt.resolution);
clear cleanup

%% Figure 4 : contributions LF/HF/ratio, région par région

for k = 1:K
    f = newFigure(opt, [100 100 1100 750]);
    cleanup = onCleanup(@() close(f));

    tl = tiledlayout(f, 2, 1, ...
        'TileSpacing', 'compact', 'Padding', 'compact');

    ax1 = nexttile(tl);
    hold(ax1, 'on');

    plot(ax1, x, 100 * A.relative.LF(:, k), ...
        'Color', [0.15 0.45 0.85], ...
        'LineWidth', 1.3, 'DisplayName', 'LF');

    plot(ax1, x, 100 * A.relative.HF(:, k), ...
        'Color', [0.90 0.35 0.10], ...
        'LineWidth', 1.3, 'DisplayName', 'HF');

    ylabel(ax1, 'Change from temporal mean (%)');
    title(ax1, ['Band contributions: ' names{k}], ...
        'Interpreter', 'none');

    legend(ax1, 'Location', 'best');
    grid(ax1, 'on');
    box(ax1, 'on');

    ax2 = nexttile(tl);
    hold(ax2, 'on');

    plot(ax2, x, 100 * A.relative.BandRatio(:, k), ...
        'Color', colors(k, :), ...
        'LineWidth', 1.3, ...
        'DisplayName', 'Supplied band ratio');

    qRelative = relativeVariation(quotientRegional(:, k));

    plot(ax2, x, 100 * qRelative, '--', ...
        'Color', [0.25 0.25 0.25], ...
        'LineWidth', 1, ...
        'DisplayName', 'Mean pixelwise HF/LF');

    ylabel(ax2, 'Change from temporal mean (%)');
    xlabel(ax2, xLabel);

    legend(ax2, 'Location', 'best');
    grid(ax2, 'on');
    box(ax2, 'on');

    linkaxes([ax1 ax2], 'x');

    exportFigure(f, outDir, ...
        opt.prefix + "_bands_" + string(names{k}), ...
        opt.resolution);
    clear cleanup
end

%% Figure 5 : contrôle de la normalisation diaphragmatique

f = newFigure(opt, [100 100 1250 950]);
cleanup = onCleanup(@() close(f));

tl = tiledlayout(f, 3, 1, ...
    'TileSpacing', 'compact', 'Padding', 'compact');

ax1 = nexttile(tl);
plotRegions(ax1, x, A.raw.BandRatio, colors, names);
ylabel(ax1, 'Band ratio');
title(ax1, 'Regional band ratio before diaphragm normalization');

legend(ax1, 'Interpreter', 'none', ...
    'Location', 'eastoutside');

ax2 = nexttile(tl);
plot(ax2, x, A.domainSignals.BandRatio, ...
    'k', 'LineWidth', 1.3);
grid(ax2, 'on');
box(ax2, 'on');
ylabel(ax2, 'Domain mean');
title(ax2, 'Instantaneous mean band ratio in the diaphragm');

ax3 = nexttile(tl);
plotRegions(ax3, x, A.normalized.BandRatio, colors, names);
ylabel(ax3, 'Regional / diaphragm');
xlabel(ax3, xLabel);
title(ax3, 'Regional band ratio after diaphragm normalization');

linkaxes([ax1 ax2 ax3], 'x');

exportFigure(f, outDir, ...
    opt.prefix + "_diaphragm_control", opt.resolution);
clear cleanup

%% Export CSV

T = table(x, 'VariableNames', {'TimeOrFrame'});

for j = 1:numel(fields)
    field = fields{j};

    T.(['Domain_' field]) = A.domainSignals.(field);

    for k = 1:K
        name = names{k};

        T.(['Raw_' field '_' name]) = A.raw.(field)(:, k);
        T.(['Normalized_' field '_' name]) = ...
            A.normalized.(field)(:, k);
    end

end

for k = 1:K
    T.(['QuotientHFoverLF_' names{k}]) = quotientRegional(:, k);
end

file = fullfile(outDir, char(opt.prefix + "_signals.csv"));
deleteIfExists(file);
writetable(T, file);

file = fullfile(outDir, char(opt.prefix + "_results.mat"));
deleteIfExists(file);
save(file, 'A', '-v7.3');

end

function Y = relativeVariation(X)
% Variation fractionnelle par rapport à la moyenne temporelle.

mu = mean(X, 1, 'omitnan');
Y = nan(size(X));

good = isfinite(mu) & mu ~= 0;
Y(:, good) = X(:, good) ./ mu(good) - 1;

end

function plotRegions(ax, x, signals, colors, names)

hold(ax, 'on');

for k = 1:numel(names)
    plot(ax, x, signals(:, k), ...
        'Color', colors(k, :), ...
        'LineWidth', 1.2, ...
        'DisplayName', names{k});
end

grid(ax, 'on');
box(ax, 'on');
xlim(ax, [x(1), x(end)]);

end

function f = newFigure(opt, position)

f = figure( ...
    'Visible', char(opt.visible), ...
    'Color', 'w', ...
    'Position', position);

end

function exportFigure(f, outDir, stem, resolution)
% Suppression conditionnelle avant chaque écriture.

pngFile = fullfile(outDir, char(stem + ".png"));
pdfFile = fullfile(outDir, char(stem + ".pdf"));

deleteIfExists(pngFile);
exportgraphics(f, pngFile, 'Resolution', resolution);

deleteIfExists(pdfFile);
exportgraphics(f, pdfFile, 'ContentType', 'vector');

end

function deleteIfExists(file)

if isfile(file)
    delete(file);
end

end

function rgb = makeOverlay(base, domain, masks, colors, alpha)

grayImage = zeros(size(base), 'single');
good = domain & isfinite(base);

if any(good, 'all')
    lo = min(base(good));
    hi = max(base(good));

    if hi > lo
        grayImage(good) = (base(good) - lo) ./ (hi - lo);
    end

end

rgb = repmat(grayImage, 1, 1, 3);
colorSum = zeros(size(rgb), 'single');
count = zeros(size(base), 'single');

for k = 1:numel(masks)
    m = single(masks{k});
    count = count + m;

    for c = 1:3
        colorSum(:, :, c) = colorSum(:, :, c) + ...
            m .* single(colors(k, c));
    end

end

covered = count > 0;
denominator = max(count, 1);

for c = 1:3
    channel = rgb(:, :, c);
    regionColor = colorSum(:, :, c) ./ denominator;

    channel(covered) = ...
        (1 - alpha) .* channel(covered) + ...
        alpha .* regionColor(covered);

    channel(~domain) = 0;
    rgb(:, :, c) = channel;
end

end

function rgb = hexToRGB(value)

if isstring(value) && isscalar(value)
    value = char(value);
end

if ~ischar(value) || ~isrow(value)
    error('bandRatioArticleFigures:invalidColor', ...
    'Expected a hexadecimal color such as #FF1612.');
end

value = strtrim(value);

if startsWith(value, '#')
    value = value(2:end);
end

if isempty(regexp(value, '^[0-9A-Fa-f]{6}$', 'once'))
    error('bandRatioArticleFigures:invalidColor', ...
        'Invalid hexadecimal color: %s', value);
end

rgb = [ ...
           hex2dec(value(1:2)), ...
           hex2dec(value(3:4)), ...
           hex2dec(value(5:6))] / 255;

end
