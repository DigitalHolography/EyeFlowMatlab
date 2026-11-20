function imported = ImportMasks(ToolBox)
% Alternative to createMasks using the DopplerView importer.
% Requires importDopplerViewRegions.m with the retinal-pair guard.
% Returns false on cancellation or absent retinal artery/vein pair.
% Errors are intentionally propagated: invalid imports must not be hidden.

imported = false;
r = importDopplerViewRegions(ToolBox);

if ~isstruct(r) || isempty(fieldnames(r))
    return;
end

if ~isfield(r, 'Masks') || ...
        ~isfield(r.Masks, 'RetinaArtery') || ...
        ~isfield(r.Masks, 'RetinaVein')
    return;
end

A = logical(r.Masks.RetinaArtery);
V = logical(r.Masks.RetinaVein);
reference = mean(ToolBox.Cache.M0_ff, 3, 'omitnan');

if ~isequal(size(A), size(V), size(reference))
    error('EyeFlow:ImportedMaskSize', ...
    'Imported masks and EyeFlow reference must have identical sizes.');
end

if ~any(A(:)) || ~any(V(:))
    error('EyeFlow:EmptyImportedAVMask', ...
    'Imported artery and vein masks must both contain pixels.');
end

params = ToolBox.getParams;
distance = params.json.PulseAnalysis.LocalBackgroundDist;
width = params.json.PulseAnalysis.LocalBackgroundWidth;
validateattributes(distance, {'numeric'}, ...
    {'scalar', 'finite', 'integer', 'nonnegative'});
validateattributes(width, {'numeric'}, ...
    {'scalar', 'finite', 'integer', 'nonnegative'});
vessel = A | V;
inner = imdilate(vessel, strel('disk', double(distance), 0));
neighbors = imdilate(inner, strel('disk', double(width), 0)) & ~inner;

choroid = false(size(A));

if isfield(r.Masks, 'ChoroidVessel')
    choroid = logical(r.Masks.ChoroidVessel);
end

base = double(reference);
good = isfinite(base);

if any(good(:))
    lo = min(base(good)); hi = max(base(good));
    base(~good) = lo;
    base = (base - lo) / max(hi - lo, eps);
else
    base(:) = 0;
end

rgb = repmat(base, 1, 1, 3);
colors = [1 0 0; 0 0 1; 1 0 1];
regions = {A & ~V, V & ~A, A & V};

for k = 1:3

    for c = 1:3
        channel = rgb(:, :, c);
        channel(regions{k}) = 0.6 * channel(regions{k}) + 0.4 * colors(k, c);
        rgb(:, :, c) = channel;
    end

end

cache = ToolBox.Cache;
cache.maskArtery = A;
cache.maskVein = V;
cache.maskVessel = vessel;
cache.maskBackground = ~vessel;
cache.maskNeighbors = neighbors;
cache.maskChoroid = choroid;
cache.M0_RGB = rgb;
% No EyeFlow model confidence is available for imported masks.
cache.scoreMaskArtery = NaN;
cache.scoreMaskVein = NaN;

if isprop(cache, 'SH_avg_masks')
    cache.SH_avg_masks = r.Masks;
    names = fieldnames(r.Masks);
    palette = lines(numel(names));
    regionColors = struct();

    for k = 1:numel(names)
        regionColors.(names{k}) = palette(k, :);
    end

    cache.SH_avg_colors = regionColors;
    cache.SH_avg_maskDomain = true(size(A));
end

ToolBox.Output.add('ArteryNbPxl', nnz(A), ...
    h5path = '/Artery/Segmentation/NbPxl');
ToolBox.Output.add('VeinNbPxl', nnz(V), ...
    h5path = '/Vein/Segmentation/NbPxl');
ToolBox.Output.add('RemainingNbPxl', nnz(~vessel), ...
    h5path = '/ArteryVein/Segmentation/NbPxl');
imported = true;
fprintf('[EyeFlow] DopplerView masks imported; createMasks bypassed.\n');
end
