function R = bandRatioCorrelation(M0_ff, bandRatio, maskArtery, maskVein, maskChoroid, opt)
% Corrélation de Pearson (axe temporel) entre le band ratio de chaque pixel et
% trois signaux de référence : artériel, veineux, choroïdien (moyenne de M0_ff
% dans chaque masque). Retourne une structure R.Artery / R.Vein / R.Choroid
% contenant les cartes de corrélation.

arguments
    M0_ff
    bandRatio
    maskArtery
    maskVein
    maskChoroid
    opt.maskDomain = []
    opt.chunk (1, 1) double = 2e5
end

ToolBox = getGlobalToolBox;
[nx, ny, nt] = size(bandRatio);
if isempty(opt.maskDomain), opt.maskDomain = true(nx, ny); end
domain = logical(opt.maskDomain);

names = {'Artery', 'Vein', 'Choroid'};
masks = {logical(maskArtery), logical(maskVein), logical(maskChoroid)};

% 1) Signaux de référence, centrés et normalisés (norme 1)
M0_ff = single(M0_ff);
S = zeros(nt, 0, 'single');
sRaw = zeros(nt, 0, 'single');
valid = false(1, 3);

for k = 1:3
    m = masks{k};

    if ~isequal(size(m), [nx, ny]) || ~any(m, 'all')
        warning('bandRatioCorrelation:emptyMask', '%s mask empty or wrong size: skipped.', names{k});
        continue
    end

    s = squeeze(sum(M0_ff .* m, [1 2], 'omitnan')) / nnz(m);
    s = single(s(:));
    sRaw(:, end + 1) = s; %#ok<AGROW> % <-- ajouté (avant centrage)
    s = s - mean(s, 'omitnan');
    S(:, end + 1) = s / (norm(s) + eps('single')); %#ok<AGROW>
    valid(k) = true;
end

if ~any(valid)
    warning('bandRatioCorrelation:noSignal', 'No valid mask: correlation maps not computed.');
    R = struct();
    return
end

refNames = names(valid);
K = size(S, 2);

% 2) Corrélation de tous les pixels avec les K signaux, par blocs
B = reshape(single(bandRatio), nx * ny, nt);
r = nan(nx * ny, K, 'single');

for i = 1:opt.chunk:nx * ny
    idx = i:min(i + opt.chunk - 1, nx * ny);
    Bc = B(idx, :);
    Bc = Bc - mean(Bc, 2, 'omitnan');
    Bc(isnan(Bc)) = 0;
    r(idx, :) = (Bc * S) ./ (sqrt(sum(Bc .^ 2, 2)) + eps('single'));
end

% 3) Cartes et images : bleu (-1) / blanc (0) / rouge (+1), noir hors diaphragme
cmap = cmapLAB(256, [0 0 1], 0, [1 1 1], 0.5, [1 0 0], 1);
R = struct();

outDir = fullfile(ToolBox.path_png, 'mask');
if ~isfolder(outDir), mkdir(outDir); end

refNames = names(valid);
K = size(S, 2);

B = reshape(single(bandRatio), nx * ny, nt);
plotSignalsCheck(ToolBox, names, masks, valid, sRaw, B, domain, outDir);

for k = 1:K
    img = reshape(r(:, k), nx, ny);
    img(~domain) = NaN;
    R.(refNames{k}) = img;

    disp_img = img; disp_img(isnan(disp_img)) = 0;
    ind = round(1 + 255 * rescale(disp_img, 'InputMin', -1, 'InputMax', 1));
    rgb = ind2rgb(ind, cmap) .* domain;

    % Image brute (sans colorbar)
    tag = sprintf('bandRatio_corr_%sSignal', lower(refNames{k}));
    saveMaskImage(rgb, [tag '.png'], ForceFigure = true);

    % Image avec colorbar
    f = figure('Visible', 'off', 'Color', 'w');
    ax = axes(f);
    imshow(rgb, 'Parent', ax);
    colormap(ax, cmap);
    clim(ax, [-1 1]);
    cb = colorbar(ax);
    cb.Label.String = 'Pearson correlation coefficient r';
    cb.Ticks = -1:0.5:1;
    title(ax, sprintf('Band ratio vs %s signal', lower(refNames{k})));

    try
        exportgraphics(f, fullfile(outDir, sprintf('%s_%s_colorbar.png', ToolBox.folder_name, tag)), ...
            'Resolution', 200);
    catch ME
        warning('bandRatioCorrelation:exportFailed', 'Could not save colorbar figure: %s', ME.message);
    end

    close(f);
end

% 4) Corrélation moyenne de chaque signal dans chaque région -> sorties
for k = 1:K

    for j = find(valid)
        val = mean(R.(refNames{k})(masks{j}), 'omitnan');
        ToolBox.Output.add(sprintf('BandRatioCorr%sSignalIn%s', refNames{k}, names{j}), val, ...
            h5path = sprintf('/%s/BandRatio/Correlation%sSignal', names{j}, refNames{k}));
    end

end

end

function plotSignalsCheck(ToolBox, names, masks, valid, sRaw, B, domain, outDir)
% Figure de contrôle : signaux de référence, band ratio moyen par région,
% fraction de pixels non finis du band ratio par frame.

nt = size(B, 2);
t = ToolBox.Cache.t;

if numel(t) == nt
    x = t(:); xl = 'Time (s)';
else
    x = (1:nt)'; xl = 'Frame';
end

colors = [1 0.09 0.07; 0.07 0.09 1; 0 0.6 0.2]; % artère, veine, choroïde
idxValid = find(valid);

f = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 900 800]);
tl = tiledlayout(f, 3, 1, 'TileSpacing', 'compact');

% (1) Signaux de référence M0_ff (z-score)
ax1 = nexttile(tl); hold(ax1, 'on');

for q = 1:numel(idxValid)
    k = idxValid(q);
    s = double(sRaw(:, q));
    z = (s - mean(s, 'omitnan')) / (std(s, 0, 'omitnan') + eps);
    plot(ax1, x, z, 'Color', colors(k, :), 'LineWidth', 1.2, 'DisplayName', names{k});
end

ylabel(ax1, 'M_0 signal (z-score)');
title(ax1, 'Reference signals (mean M_0 in each mask)');
legend(ax1, 'Location', 'eastoutside'); grid(ax1, 'on');

% (2) Band ratio moyen dans chaque région
ax2 = nexttile(tl); hold(ax2, 'on');

for q = 1:numel(idxValid)
    k = idxValid(q);
    m = masks{k};
    br = mean(B(m(:), :), 1, 'omitnan');
    plot(ax2, x, br(:), 'Color', colors(k, :), 'LineWidth', 1.2, 'DisplayName', names{k});
end

ylabel(ax2, 'Band ratio (a.u.)');
title(ax2, 'Mean band ratio in each mask');
legend(ax2, 'Location', 'eastoutside'); grid(ax2, 'on');

% (3) Intégrité : % de pixels NaN/Inf du band ratio, dans le domaine
bad = 100 * (1 - sum(isfinite(B) & domain(:), 1) / nnz(domain));
ax3 = nexttile(tl);
plot(ax3, x, bad(:), 'k', 'LineWidth', 1.2);
ylim(ax3, [0 max(1, 1.1 * max(bad))]);
ylabel(ax3, 'Non-finite pixels (%)'); xlabel(ax3, xl);
title(ax3, 'Band ratio integrity (NaN / Inf per frame)');
grid(ax3, 'on');

if max(bad) == 0
    text(ax3, 0.5, 0.5, 'No NaN / Inf', 'Units', 'normalized', ...
        'HorizontalAlignment', 'center', 'Color', [0 0.5 0]);
else
    warning('bandRatioCorrelation:nonFinite', ...
        'Band ratio contains non-finite pixels (max %.2f%% in a frame).', max(bad));
end

try
    exportgraphics(f, fullfile(outDir, sprintf('%s_bandRatio_corr_signals.png', ToolBox.folder_name)), ...
        'Resolution', 200);
catch ME
    warning('bandRatioCorrelation:exportFailed', 'Could not save signals figure: %s', ME.message);
end

close(f);
end
