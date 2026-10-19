function A = bandRatioFlatfieldArticleFigures( ...
        M0_ff, M0_LF_flatfield, M0_HF_flatfield, ...
        regionMasks, opt)
% bandRatioFlatfieldArticleFigures
%
% Variante de bandRatioArticleFigures utilisant les bandes
% LF et HF déjà corrigées par flat-field.
%
% Le ratio est recalculé pixel par pixel :
%
%   bandRatioFF = ratioScale * M0_HF_flatfield ./ M0_LF_flatfield
%
% Aucun offset spatial n'est soustrait.
% Aucune correction flat-field supplémentaire n'est appliquée.
%
% INPUTS
%   M0_ff :
%       cube de référence [nRows, nCols, nFrames].
%
%   M0_LF_flatfield, M0_HF_flatfield :
%       cubes LF et HF déjà corrigés et alignés avec M0_ff.
%
%   regionMasks :
%       structure de masques 2D dans les coordonnées des cubes.
%
% OPTIONS
%   maskDomain :
%       domaine/diaphragme de normalisation.
%
%   regionColors :
%       structure contenant les couleurs hexadécimales.
%
%   time :
%       temps en secondes ; si vide, numéro de frame.
%
%   outputDir :
%       dossier spécifique pour ne pas écraser les résultats initiaux.
%
%   ratioScale :
%       facteur multiplicatif explicite du ratio, par défaut 1.
%       Aucune correction automatique de largeur de bande.
%
%   minLF :
%       les pixels où LF <= minLF sont exclus du nouveau ratio.
%
% OUTPUT
%   A :
%       résultats de bandRatioArticleFigures, complétés avec
%       les métadonnées de cette variante flat-field.
%
% DEPENDENCY
%   bandRatioArticleFigures.m
%
% Les suppressions conditionnelles des figures/CSV/MAT sont gérées
% par bandRatioArticleFigures.

arguments
    M0_ff
    M0_LF_flatfield
    M0_HF_flatfield
    regionMasks (1, 1) struct

    opt.maskDomain = []
    opt.regionColors (1, 1) struct = struct()
    opt.time = []

    opt.outputDir (1, 1) string = "band_ratio_article_flatfield"
    opt.prefix (1, 1) string = "article_flatfield"

    opt.lowBandHz (1, 2) double = [3000 9000]
    opt.highBandHz (1, 2) double = [9000 18000]

    opt.ratioScale (1, 1) double ...
        {mustBePositive, mustBeFinite} = 1

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

%% 1) Vérifier la dépendance

if isempty(which('bandRatioArticleFigures'))
    error('bandRatioFlatfieldArticleFigures:missingDependency', ...
        ['bandRatioArticleFigures.m was not found. ', ...
         'Add its folder to the MATLAB path.']);
end

%% 2) Vérifier les cubes

cubes = {M0_ff, M0_LF_flatfield, M0_HF_flatfield};

sz = size(M0_ff);

if isempty(M0_ff) || ndims(M0_ff) > 3 || size(M0_ff, 3) < 2
    error('bandRatioFlatfieldArticleFigures:invalidVideo', ...
        'Expected a spatial video with at least two frames.');
end

for j = 1:numel(cubes)
    X = cubes{j};

    if ~isnumeric(X) || ~isreal(X) || ...
            ~isequal(size(X), sz)

        error('bandRatioFlatfieldArticleFigures:sizeMismatch', ...
            ['M0_ff, M0_LF_flatfield and M0_HF_flatfield ', ...
             'must be real numeric cubes of identical size.']);
    end
end

[nRows, nCols, nt] = size(M0_ff);

%% 3) Préparer le domaine

if isempty(opt.maskDomain)
    domain = true(nRows, nCols);
else
    m = opt.maskDomain;

    if ~(isnumeric(m) || islogical(m)) || ...
            ~isreal(m) || ...
            ~isequal(size(m), [nRows nCols])

        error('bandRatioFlatfieldArticleFigures:invalidDomain', ...
            'maskDomain must match the spatial size of the cubes.');
    end

    domain = isfinite(m) & m ~= 0;
end

if ~any(domain, 'all')
    error('bandRatioFlatfieldArticleFigures:emptyDomain', ...
        'The diaphragm/domain is empty.');
end

%% 4) Recalculer le ratio à partir des bandes flat-field
% Calcul frame par frame pour limiter la mémoire temporaire.
% Le résultat final est conservé en single.

bandRatioFF = nan(nRows, nCols, nt, 'single');

validFraction = zeros(nt, 1);
nDomain = nnz(domain);

for it = 1:nt
    LF = double(M0_LF_flatfield(:, :, it));
    HF = double(M0_HF_flatfield(:, :, it));

    good = domain & ...
        isfinite(LF) & ...
        isfinite(HF) & ...
        LF > opt.minLF;

    ratioFrame = nan(nRows, nCols);

    ratioFrame(good) = ...
        opt.ratioScale .* (HF(good) ./ LF(good));

    % Vérifier aussi les dépassements lors du stockage en single.
    ratioFrame = single(ratioFrame);
    ratioFrame(~isfinite(ratioFrame)) = NaN;

    bandRatioFF(:, :, it) = ratioFrame;

    validFraction(it) = ...
        nnz(isfinite(ratioFrame) & domain) / nDomain;
end

if ~any(validFraction > 0)
    error('bandRatioFlatfieldArticleFigures:noValidRatio', ...
        ['No valid flat-field ratio could be computed. ', ...
         'Check LF values and minLF.']);
end

if any(validFraction < 1)
    warning('bandRatioFlatfieldArticleFigures:excludedPixels', ...
        ['Some pixels were excluded from the flat-field ratio. ', ...
         'Maximum excluded fraction in a frame: %.2f%%.'], ...
        100 * max(1 - validFraction));
end

%% 5) Produire les mêmes figures que la fonction article
% Ordre attendu par la fonction originale : M0, HF, LF, ratio.

A = bandRatioArticleFigures( ...
    M0_ff, ...
    M0_HF_flatfield, ...
    M0_LF_flatfield, ...
    bandRatioFF, ...
    regionMasks, ...
    maskDomain = domain, ...
    regionColors = opt.regionColors, ...
    time = opt.time, ...
    outputDir = opt.outputDir, ...
    prefix = opt.prefix, ...
    lowBandHz = opt.lowBandHz, ...
    highBandHz = opt.highBandHz, ...
    bandValues = "unknown", ...
    minLF = opt.minLF, ...
    overlayAlpha = opt.overlayAlpha, ...
    resolution = opt.resolution, ...
    visible = opt.visible);

%% 6) Compléter la provenance des résultats

A.metadata.analysisVariant = ...
    'Ratio recomputed from separately flat-field-corrected bands';

A.metadata.inputLF = 'M0_LF_flatfield';
A.metadata.inputHF = 'M0_HF_flatfield';

A.metadata.inputRatio = ...
    'ratioScale * M0_HF_flatfield / M0_LF_flatfield, pixelwise';

A.metadata.ratioScale = opt.ratioScale;
A.metadata.ratioOffsetSubtracted = false;
A.metadata.additionalFlatfieldApplied = false;

A.metadata.bandValues = ...
    'Already flat-field-corrected bands; original convention unspecified';

A.ratioQuality.validFractionPerFrame = validFraction;
A.ratioQuality.excludedFractionPerFrame = 1 - validFraction;

%% 7) Exporter le contrôle de validité

qualityTable = table( ...
    A.time, ...
    validFraction, ...
    1 - validFraction, ...
    'VariableNames', { ...
        'TimeOrFrame', ...
        'ValidFraction', ...
        'ExcludedFraction'});

qualityFile = fullfile( ...
    char(opt.outputDir), ...
    char(opt.prefix + "_ratio_quality.csv"));

deleteIfExists(qualityFile);
writetable(qualityTable, qualityFile);

%% 8) Mettre à jour le MAT avec les métadonnées de cette variante

resultFile = fullfile( ...
    char(opt.outputDir), ...
    char(opt.prefix + "_results.mat"));

deleteIfExists(resultFile);
save(resultFile, 'A', '-v7.3');

end


function deleteIfExists(file)
% Supprime uniquement les fichiers existants.

if isfile(file)
    delete(file);
end

end