function saveMaskImage(I, suffix, opt)

arguments
    I
    suffix
    opt.cmap = []
    opt.isStep = false
    opt.ForceFigure = false
end

ToolBox = getGlobalToolBox;
params = ToolBox.getParams;
folder_name = ToolBox.folder_name;

if ~params.saveFigures && ~opt.ForceFigure
    return;
end

if opt.isStep
    folderPath = fullfile(ToolBox.path_png, 'mask', 'steps', sprintf("%s_%s", folder_name, suffix));
else
    folderPath = fullfile(ToolBox.path_png, 'mask', sprintf("%s_%s", folder_name, suffix));
end

% Crée le dossier de destination s'il n'existe pas
outDir = fileparts(folderPath);

if ~isfolder(outDir)
    mkdir(outDir);
end

% Supprime l'ancien fichier avant de le remplacer
if isfile(folderPath)
    fileattrib(folderPath, '+w'); % retire la lecture seule
    delete(folderPath);

    if isfile(folderPath) % toujours là : verrouillé par un autre programme
        warning('saveMaskImage:fileLocked', ...
            'Cannot overwrite %s (file locked or read-only). Image skipped.', folderPath);
        return;
    end

end

if isempty(opt.cmap)

    if size(I, 3) == 1 && isa(I, 'numeric')
        I = rescale(I);
    end

    imwrite(I, folderPath, 'png');
else

    if size(I, 3) == 1 && ~islogical(I)
        I = (size(opt.cmap, 1) - 1) * rescale(I);
    end

    imwrite(I, opt.cmap, folderPath, 'png');
end

end
