function R = bandRatioCorrelation( ...
    M0_ff, f_RMS, bandRatio, regionMasks, opt)
% bandRatioCorrelation
% Corrélation temporelle entre :
%   - le band ratio normalisé de chaque pixel ;
%   - le signal M0_ff normalisé moyen de chaque région.
%
% Normalisation à chaque instant :
%   X_normalized(:,:,t) = X(:,:,t) / mean(X(diaphragm,t))
%
% Chaque grandeur utilise sa propre moyenne diaphragmatique :
%   M0_ff, f_RMS et bandRatio.
%
% Le diaphragme est défini par opt.maskDomain.
% Si maskDomain est vide, toute l'image est utilisée.
%
% regionMasks : structure contenant les masques 2D des régions.
% R           : structure contenant une carte par référence valide.
%
% Les images sont enregistrées dans :
%   ToolBox.path_png / mask / band_ratio
%
% Les pixels constants ou contenant des valeurs non finies sur la
% séquence donnent une corrélation NaN.

arguments
    M0_ff
    f_RMS
    bandRatio
    regionMasks (1, 1) struct
    opt.maskDomain = []
    opt.regionColors (1, 1) struct = struct()
    opt.chunk (1, 1) double ...
        {mustBeInteger, mustBePositive} = 2e5
end

ToolBox = getGlobalToolBox;
R = struct();

%% 0) Validation des vidéos

if isempty(M0_ff) || isempty(f_RMS) || isempty(bandRatio) || ...
        ~isequal(size(M0_ff), size(f_RMS), size(bandRatio))

    error('bandRatioCorrelation:sizeMismatch', ...
        ['M0_ff, f_RMS and bandRatio must be non-empty ', ...
     'and have identical sizes.']);
end

if ~isnumeric(M0_ff) || ~isnumeric(f_RMS) || ...
        ~isnumeric(bandRatio) || ...
        ~isreal(M0_ff) || ~isreal(f_RMS) || ~isreal(bandRatio)

    error('bandRatioCorrelation:invalidInput', ...
    'M0_ff, f_RMS and bandRatio must be real numeric arrays.');
end

if ndims(bandRatio) > 3 || size(bandRatio, 3) < 2
    error('bandRatioCorrelation:invalidVideo', ...
    'Expected spatial videos with at least two frames.');
end

[nx, ny, nt] = size(bandRatio);
nPixels = nx * ny;

%% 1) Domaine et diaphragme de normalisation

if isempty(opt.maskDomain)
    domain = true(nx, ny);
else
    m = opt.maskDomain;

    if ~(islogical(m) || isnumeric(m)) || ...
            ~isreal(m) || ~isequal(size(m), [nx, ny])

        error('bandRatioCorrelation:invalidDomain', ...
        'maskDomain must be a real mask matching the spatial size.');
    end

    domain = isfinite(m) & (m ~= 0);
end

if ~any(domain, 'all')
    warning('bandRatioCorrelation:emptyDomain', ...
    'Empty domain: correlation maps not computed.');
    return
end

% Toujours utiliser le domaine transmis par createMasks.
% Aucun masque externe Diaphragm n'est nécessaire.
diaphragmMask = domain;

%% 2) Préparation des masques régionaux

names = fieldnames(regionMasks);
nMasks = numel(names);
masks = cell(1, nMasks);

% Palette commune à l'image des régions et aux courbes.
colors = lines(nMasks);

for k = 1:nMasks

    if ~isfield(opt.regionColors, names{k})
        continue
    end

    hexColor = opt.regionColors.(names{k});

    if isempty(hexColor)
        continue
    end

    colors(k, :) = hexToRGB(hexColor);
end

for k = 1:nMasks
    masks{k} = false(nx, ny);

    % Le diaphragme sert à la normalisation, pas de référence.
    if strcmpi(names{k}, 'Diaphragm')
        continue
    end

    m = regionMasks.(names{k});

    if ~(islogical(m) || isnumeric(m)) || ...
            ~isreal(m) || ~isequal(size(m), [nx, ny])

        warning('bandRatioCorrelation:invalidMask', ...
            '%s mask invalid or wrong size: skipped.', names{k});
        continue
    end

    masks{k} = isfinite(m) & (m ~= 0) & domain;
end

%% 3) Dossier de sortie et image des régions

outDir = fullfile(ToolBox.path_png, 'mask', 'band_ratio');

if ~isfolder(outDir)
    mkdir(outDir);
end

% Image calculée avant toute normalisation temporelle.
saveRegionsOverlay( ...
    ToolBox, M0_ff, names, masks, domain, colors, outDir);

%% 4) Normalisation par les signaux du diaphragme

M0_ff = normalizeByDiaphragm( ...
    M0_ff, diaphragmMask, 'M0_ff');

f_RMS = normalizeByDiaphragm( ...
    f_RMS, diaphragmMask, 'f_RMS');

bandRatio = normalizeByDiaphragm( ...
    bandRatio, diaphragmMask, 'bandRatio');

%% 5) Références M0 régionales centrées et de norme 1

M0 = reshape(M0_ff, nPixels, nt);

S = zeros(nt, nMasks, 'single');
sRaw = zeros(nt, nMasks, 'single');

valid = false(1, nMasks);
nValid = 0;

for k = 1:nMasks

    if strcmpi(names{k}, 'Diaphragm')
        continue
    end

    m = masks{k};

    if ~any(m, 'all')
        warning('bandRatioCorrelation:emptyMask', ...
            '%s mask empty inside the domain: skipped.', names{k});
        continue
    end

    pixels = M0(m(:), :);
    pixels(~isfinite(pixels)) = NaN;

    s = mean(pixels, 1, 'omitnan').';

    if any(~isfinite(s))
        warning('bandRatioCorrelation:invalidReference', ...
            '%s reference contains non-finite samples: skipped.', ...
            names{k});
        continue
    end

    % Centrage effectué en double pour limiter les erreurs numériques.
    sCentered = double(s);
    sCentered = sCentered - mean(sCentered);
    sNorm = norm(sCentered);

    if ~isfinite(sNorm) || sNorm == 0
        warning('bandRatioCorrelation:constantReference', ...
            '%s reference is constant or invalid: skipped.', names{k});
        continue
    end

    nValid = nValid + 1;

    sRaw(:, nValid) = s;
    S(:, nValid) = single(sCentered / sNorm);
    valid(k) = true;
end

clear M0 pixels

if ~any(valid)
    warning('bandRatioCorrelation:noSignal', ...
    'No valid regional reference: correlation maps not computed.');
    return
end

S = S(:, 1:nValid);
sRaw = sRaw(:, 1:nValid);

refNames = names(valid);
K = nValid;

%% 6) Corrélation temporelle par blocs

B = reshape(bandRatio, nPixels, nt);
FRMS = reshape(f_RMS, nPixels, nt);

r = nan(nPixels, K, 'single');

% Calcul limité aux pixels du domaine.
domainIndices = find(domain(:));
nDomainPixels = numel(domainIndices);

for i = 1:opt.chunk:nDomainPixels
    idx = domainIndices( ...
        i:min(i + opt.chunk - 1, nDomainPixels));

    Bc = B(idx, :);

    % Une corrélation est calculée uniquement pour les séries complètes.
    finiteRows = all(isfinite(Bc), 2);

    if ~any(finiteRows)
        continue
    end

    Bc = Bc(finiteRows, :);
    Bc = Bc - mean(Bc, 2);

    bNorm = sqrt(sum(Bc .^ 2, 2));
    variableRows = isfinite(bNorm) & bNorm > 0;

    if ~any(variableRows)
        continue
    end

    targetIdx = idx(finiteRows);
    targetIdx = targetIdx(variableRows);

    Bc = Bc(variableRows, :) ./ bNorm(variableRows);

    rc = Bc * S;

    % Limiter les petits dépassements numériques de [-1, 1].
    rc = max(-1, min(1, rc));

    r(targetIdx, :) = rc;
end

%% 7) Courbes des signaux régionaux normalisés

plotSignalsCheck( ...
    ToolBox, names, masks, valid, sRaw, ...
    FRMS, B, domain, colors, outDir);

%% 8) Cartes de corrélation

cmap = cmapLAB( ...
    256, [0 0 1], 0, [1 1 1], 0.5, [1 0 0], 1);

for k = 1:K
    img = reshape(r(:, k), nx, ny);
    img(~domain) = NaN;

    R.(refNames{k}) = img;

    % Conversion RGB pour l'image brute.
    % Les valeurs invalides dans le domaine sont affichées au neutre.
    displayImage = img;
    displayImage(~isfinite(displayImage)) = 0;
    displayImage = max(-1, min(1, displayImage));

    ind = round(1 + 255 * (displayImage + 1) / 2);
    rgb = ind2rgb(ind, cmap);
    rgb = rgb .* domain;

    tag = sprintf( ...
        'bandRatio_corr_%sSignal', lower(refNames{k}));

    file = fullfile(outDir, sprintf( ...
        '%s_%s.png', ToolBox.folder_name, tag));

    deleteIfExists(file);
    imwrite(rgb, file);

    % Image avec colorbar.
    saveCorrelationFigure( ...
        ToolBox, rgb, cmap, refNames{k}, tag, outDir);
end

%% 9) Corrélation moyenne dans chaque région valide

for k = 1:K
    img = R.(refNames{k});

    for j = find(valid)
        val = mean(img(masks{j}), 'omitnan');

        ToolBox.Output.add( ...
            sprintf('BandRatioCorr%sSignalIn%s', ...
            refNames{k}, names{j}), ...
            val, ...
            h5path = sprintf( ...
            '/%s/BandRatio/Correlation%sSignal', ...
            names{j}, refNames{k}));
    end

end

end

function X = normalizeByDiaphragm(X, diaphragmMask, signalName)
% Divise chaque image par sa moyenne dans le diaphragme.

[nx, ny, nt] = size(X);

X = reshape(single(X), nx * ny, nt);
X(~isfinite(X)) = NaN;

diaphragmSignal = mean( ...
    X(diaphragmMask(:), :), 1, 'omitnan');

badFrames = ~isfinite(diaphragmSignal) | diaphragmSignal == 0;

if any(badFrames)
    error('bandRatioCorrelation:invalidDiaphragmSignal', ...
        ['Cannot normalize %s: diaphragm mean is zero ', ...
     'or non-finite in %d frame(s).'], ...
        signalName, nnz(badFrames));
end

X = X ./ diaphragmSignal;
X = reshape(X, nx, ny, nt);

end

function plotSignalsCheck( ...
    ToolBox, names, masks, valid, sRaw, ...
    FRMS, B, domain, colors, outDir)
% Affiche les moyennes régionales après normalisation diaphragmatique.
% Aucune standardisation supplémentaire n'est appliquée.

nt = size(B, 2);
t = ToolBox.Cache.t;

if numel(t) == nt && all(isfinite(t(:))) && ...
        all(diff(t(:)) > 0)

    x = t(:);
    xLabel = 'Time (s)';
else
    x = (1:nt).';
    xLabel = 'Frame';
end

idxValid = find(valid);

f = figure( ...
    'Visible', 'off', ...
    'Color', 'w', ...
    'Position', [100 100 1100 900]);

cleanupFigure = onCleanup(@() close(f));

tl = tiledlayout(f, 3, 1, 'TileSpacing', 'compact');

ax0 = nexttile(tl);
hold(ax0, 'on');

ax1 = nexttile(tl);
hold(ax1, 'on');

ax2 = nexttile(tl);
hold(ax2, 'on');

for q = 1:numel(idxValid)
    k = idxValid(q);
    m = masks{k};

    % M0 normalisé moyen.
    m0Signal = double(sRaw(:, q));

    plot(ax0, x, m0Signal, ...
        'Color', colors(k, :), ...
        'LineWidth', 1.2, ...
        'DisplayName', names{k});

    % f_RMS normalisé moyen.
    rmsPixels = FRMS(m(:), :);
    rmsPixels(~isfinite(rmsPixels)) = NaN;

    rmsSignal = double( ...
        mean(rmsPixels, 1, 'omitnan')).';

    plot(ax1, x, rmsSignal, ...
        'Color', colors(k, :), ...
        'LineWidth', 1.2, ...
        'DisplayName', names{k});

    % Band ratio normalisé moyen.
    brPixels = B(m(:), :);
    brPixels(~isfinite(brPixels)) = NaN;

    brSignal = double( ...
        mean(brPixels, 1, 'omitnan')).';

    plot(ax2, x, brSignal, ...
        'Color', colors(k, :), ...
        'LineWidth', 1.2, ...
        'DisplayName', names{k});
end

ylabel(ax0, 'M_0 / diaphragm M_0');
title(ax0, 'Mean normalized M_0 in each mask');

ylabel(ax1, 'f_{RMS} / diaphragm f_{RMS}');
title(ax1, 'Mean normalized f_{RMS} in each mask');

ylabel(ax2, 'Band ratio / diaphragm band ratio');
title(ax2, 'Mean normalized band ratio in each mask');
xlabel(ax2, xLabel);

axesList = [ax0, ax1, ax2];

for ax = axesList
    grid(ax, 'on');
    box(ax, 'on');
    axis(ax, 'padded');
    xlim(ax, [x(1), x(end)]);

    legend(ax, ...
        'Location', 'eastoutside', ...
        'Interpreter', 'none');
end

linkaxes(axesList, 'x');

% Diagnostic des valeurs non finies dans le domaine, par blocs.
badCount = zeros(1, nt);
domainIndices = find(domain(:));
diagnosticChunk = 2e5;

for i = 1:diagnosticChunk:numel(domainIndices)
    idx = domainIndices( ...
        i:min(i + diagnosticChunk - 1, numel(domainIndices)));

    badCount = badCount + sum(~isfinite(B(idx, :)), 1);
end

badPercent = 100 * badCount / numel(domainIndices);

if any(badPercent > 0)
    warning('bandRatioCorrelation:nonFinite', ...
        ['Normalized band ratio contains non-finite pixels ', ...
         '(max %.2f%% in a frame). ', ...
     'Affected pixel time series are excluded from correlations.'], ...
        max(badPercent));
end

file = fullfile(outDir, sprintf( ...
    '%s_bandRatio_corr_signals.png', ToolBox.folder_name));

try
    deleteIfExists(file);
    exportgraphics(f, file, 'Resolution', 200);
catch ME
    warning('bandRatioCorrelation:exportFailed', ...
        'Could not save signals figure: %s', ME.message);
end

end

function saveCorrelationFigure( ...
    ToolBox, rgb, cmap, referenceName, tag, outDir)
% Enregistre une carte RGB avec sa colorbar.

f = figure('Visible', 'off', 'Color', 'w');
cleanupFigure = onCleanup(@() close(f));

ax = axes(f);
imshow(rgb, 'Parent', ax);

colormap(ax, cmap);
clim(ax, [-1 1]);

cb = colorbar(ax);
cb.Label.String = 'Pearson correlation coefficient r';
cb.Ticks = -1:0.5:1;

title(ax, sprintf( ...
    'Normalized band ratio vs normalized %s M0 signal', ...
    referenceName), ...
    'Interpreter', 'none');

file = fullfile(outDir, sprintf( ...
    '%s_%s_colorbar.png', ToolBox.folder_name, tag));

try
    deleteIfExists(file);
    exportgraphics(f, file, 'Resolution', 200);
catch ME
    warning('bandRatioCorrelation:exportFailed', ...
        'Could not save colorbar figure: %s', ME.message);
end

end

function saveRegionsOverlay( ...
    ToolBox, M0_ff, names, masks, domain, colors, outDir)
% Superpose les régions au M0 moyen original.
% Les zones de recouvrement utilisent la moyenne des couleurs.
% Le diaphragme n'est pas colorié.

M0 = single(M0_ff);
M0(~isfinite(M0)) = NaN;

base = mean(M0, 3, 'omitnan');
clear M0

finitePixels = isfinite(base) & domain;
gray = zeros(size(base), 'single');

if any(finitePixels, 'all')
    lo = min(base(finitePixels));
    hi = max(base(finitePixels));

    if hi > lo
        gray(finitePixels) = ...
            (base(finitePixels) - lo) ./ (hi - lo);
    end

end

rgb = repmat(gray, 1, 1, 3);

colorSum = zeros(size(rgb), 'single');
count = zeros(size(base), 'single');
shown = false(1, numel(names));

for k = 1:numel(names)

    if strcmpi(names{k}, 'Diaphragm')
        continue
    end

    m = masks{k} & domain;

    if ~any(m, 'all')
        continue
    end

    shown(k) = true;
    count = count + single(m);

    for c = 1:3
        colorSum(:, :, c) = colorSum(:, :, c) + ...
            single(m) .* single(colors(k, c));
    end

end

covered = count > 0;
denom = max(count, 1);
alpha = 0.45;

for c = 1:3
    channel = rgb(:, :, c);
    regionColor = colorSum(:, :, c) ./ denom;

    channel(covered) = ...
        (1 - alpha) .* channel(covered) + ...
        alpha .* regionColor(covered);

    channel(~domain) = 0;
    rgb(:, :, c) = channel;
end

file = fullfile(outDir, sprintf( ...
    '%s_bandRatio_regions.png', ToolBox.folder_name));

deleteIfExists(file);
imwrite(rgb, file);

% Image avec légende.
f = figure( ...
    'Visible', 'off', ...
    'Color', 'w', ...
    'Position', [100 100 1100 850]);

cleanupFigure = onCleanup(@() close(f));

ax = axes(f);
imshow(rgb, 'Parent', ax);
hold(ax, 'on');

for k = find(shown)
    plot(ax, NaN, NaN, 's', ...
        'MarkerFaceColor', colors(k, :), ...
        'MarkerEdgeColor', colors(k, :), ...
        'MarkerSize', 9, ...
        'DisplayName', names{k});
end

title(ax, 'Mean original M0 with correlation regions', ...
    'Interpreter', 'none');

if any(shown)
    legend(ax, ...
        'Location', 'eastoutside', ...
        'Interpreter', 'none');
end

file = fullfile(outDir, sprintf( ...
    '%s_bandRatio_regions_legend.png', ToolBox.folder_name));

try
    deleteIfExists(file);
    exportgraphics(f, file, 'Resolution', 200);
catch ME
    warning('bandRatioCorrelation:exportFailed', ...
        'Could not save regions figure: %s', ME.message);
end

end

function rgb = hexToRGB(hexColor)
% Convertit une couleur hexadécimale RRGGBB en triplet RGB [0, 1].

if isstring(hexColor)

    if ~isscalar(hexColor)
        error('bandRatioCorrelation:invalidHexColor', ...
        'Hex color must be a scalar string or a character row vector.');
    end

    hexColor = char(hexColor);
end

if ~ischar(hexColor) || ~isrow(hexColor)
    error('bandRatioCorrelation:invalidHexColor', ...
    'Hex color must be a scalar string or a character row vector.');
end

hexColor = strtrim(hexColor);

if startsWith(hexColor, '#')
    hexColor = hexColor(2:end);
end

if numel(hexColor) ~= 6 || ...
        isempty(regexp(hexColor, '^[0-9A-Fa-f]{6}$', 'once'))

    error('bandRatioCorrelation:invalidHexColor', ...
        'Invalid hex color "%s": expected #RRGGBB or RRGGBB.', ...
        hexColor);
end

rgb = [ ...
           hex2dec(hexColor(1:2)), ...
           hex2dec(hexColor(3:4)), ...
           hex2dec(hexColor(5:6))] / 255;

end

function deleteIfExists(file)
% Supprime le fichier uniquement s'il existe.

if isfile(file)
    delete(file);
end

end
