classdef DataLoaderClass < handle
% Handles data loading: .holo, .raw and .h5.
% Automatically resolves a *_HD subfolder containing input data.
%
% SH:
%   Legacy spectral data, loaded independently from SH_avg.
%
% SH_avg:
%   Optional dataset /SH_avg, read without squeeze or transformation.
%   Its frequency axis and spatial reference are not inferred here.

properties
    directory char
    filenames char

    M0 single
    M1 single
    M2 single

    SH single
    SH_avg single

    HF_M0 single
    LF_M0 single

    % Provenance of SH_avg, empty when the dataset is absent.
    SH_avg_sourceFile char = ''
    SH_avg_datasetPath char = ''
    SH_avg_info struct = struct()
end

methods

    function obj = DataLoaderClass(selectedPath)
        obj.directory = obj.cleanPath(selectedPath);
        obj.directory = obj.resolveDataFolder(obj.directory);
        obj.filenames = obj.extractFilename(obj.directory);

        obj.loadData();
    end

    function delete(obj)
        obj.M0 = [];
        obj.M1 = [];
        obj.M2 = [];

        obj.SH = [];
        obj.SH_avg = [];

        obj.HF_M0 = [];
        obj.LF_M0 = [];

        obj.SH_avg_sourceFile = '';
        obj.SH_avg_datasetPath = '';
        obj.SH_avg_info = struct();
    end

end

methods (Access = private)

    function out = cleanPath(~, in)
        out = char(in);

        out = strrep(out, '/', filesep);
        out = strrep(out, '\', filesep);

        % Preserve filesystem roots.
        while numel(out) > 1 && endsWith(out, filesep)

            if ispc && numel(out) == 3 && out(2) == ':'
                break
            end

            out = out(1:end - 1);
        end

    end

    function filename = extractFilename(~, folder)
        [~, filename] = fileparts(folder);
    end

    function dataFolder = resolveDataFolder(obj, startPath)

        if obj.containsRawData(startPath)
            dataFolder = startPath;
            return
        end

        hdDirs = dir(fullfile(startPath, '*_HD'));
        hdDirs = hdDirs([hdDirs.isdir]);

        for i = 1:numel(hdDirs)
            candidate = fullfile(startPath, hdDirs(i).name);

            if obj.containsRawData(candidate)
                dataFolder = candidate;
                return
            end

        end

        dataFolder = startPath;
    end

    function hasData = containsRawData(~, folder)
        h5Folder = fullfile(folder, 'h5');

        if isfolder(h5Folder)
            h5Files = dir(fullfile(h5Folder, '*.h5'));
            rawFiles = dir(fullfile(h5Folder, '*.raw'));

            if ~isempty(h5Files) || ~isempty(rawFiles)
                hasData = true;
                return
            end

        end

        h5Files = dir(fullfile(folder, '*.h5'));
        rawFiles = dir(fullfile(folder, '*.raw'));

        hasData = ~isempty(h5Files) || ~isempty(rawFiles);
    end

    function loadData(obj)
        % Legacy .holo input has priority.
        holoFile = [obj.directory, '.holo'];

        if isfile(holoFile)
            obj.loadHoloFile();
            return
        end

        % First search in the h5 subfolder.
        h5Folder = fullfile(obj.directory, 'h5');

        if isfolder(h5Folder)
            h5Files = dir(fullfile(h5Folder, '*.h5'));
            rawFiles = dir(fullfile(h5Folder, '*.raw'));

            if ~isempty(h5Files)
                obj.readHDF5(h5Folder);
                return
            elseif ~isempty(rawFiles)
                obj.readRaw(h5Folder);
                return
            end

        end

        % Otherwise search directly in the resolved data folder.
        h5Files = dir(fullfile(obj.directory, '*.h5'));
        rawFiles = dir(fullfile(obj.directory, '*.raw'));

        if ~isempty(h5Files)
            obj.readHDF5(obj.directory);
        elseif ~isempty(rawFiles)
            obj.readRaw(obj.directory);
        else
            error('DataLoaderClass:NoDataFile', ...
                ['No data file (.holo, .h5, .raw) found in ', ...
             '%s or its "h5" subfolder.'], ...
                obj.directory);
        end

    end

    function loadHoloFile(obj)
        fprintf('Reading .holo file: %s.holo\n', obj.directory);

        [videoM0, videoM1, videoM2] = ...
            readMoments([obj.directory, '.holo']);

        readMomentsFooter(obj.directory);

        obj.M0 = pagetranspose(videoM0);
        obj.M1 = pagetranspose(videoM1 / 1e3);
        obj.M2 = pagetranspose(videoM2 / 1e6);
    end

    function readRaw(obj, rawFolder)
        aviFolder = fullfile(obj.directory, 'avi');
        baseName = [obj.filenames, '_moment0'];

        possibleAVI = {
                       fullfile(aviFolder, [baseName, '_raw.avi'])
                       fullfile(aviFolder, [baseName, '.avi'])
                       };

        referenceAVI = '';

        for i = 1:numel(possibleAVI)

            if isfile(possibleAVI{i})
                referenceAVI = possibleAVI{i};
                break
            end

        end

        if isempty(referenceAVI)
            error('DataLoaderClass:MissingReferenceAVI', ...
                'No suitable AVI reference file found for: %s', ...
                baseName);
        end

        fprintf('- Reading reference video: %s\n', referenceAVI);

        try
            video = VideoReader(referenceAVI);

            referenceSize = [
                             video.Height, video.Width, video.NumFrames
                             ];

            clear video
        catch ME
            error('DataLoaderClass:ReferenceAVIReadFailed', ...
                'Failed to read AVI file: %s\nError: %s', ...
                referenceAVI, ME.message);
        end

        momentSuffixes = {'_moment0', '_moment1', '_moment2'};
        outputFields = {'M0', 'M1', 'M2'};

        pixelsPerFrame = prod(referenceSize(1:2));

        for i = 1:numel(momentSuffixes)
            rawFile = fullfile(rawFolder, ...
                [obj.filenames, momentSuffixes{i}, '.raw']);

            if ~isfile(rawFile)
                error('DataLoaderClass:MissingRawMoment', ...
                    'Raw moment file not found: %s', rawFile);
            end

            fprintf('- Reading: %s\n', rawFile);

            data = obj.readSingleRawFile(rawFile);

            if numel(data) ~= prod(referenceSize)
                warning('DataLoaderClass:RawSizeMismatch', ...
                    ['Size mismatch in %s. ', ...
                 'Expected %d values, got %d.'], ...
                    rawFile, prod(referenceSize), numel(data));
            end

            completeFrames = floor(numel(data) / pixelsPerFrame);

            if completeFrames < 1
                error('DataLoaderClass:IncompleteRawFrame', ...
                    'No complete frame found in: %s', rawFile);
            end

            usableValues = completeFrames * pixelsPerFrame;

            obj.(outputFields{i}) = reshape( ...
                data(1:usableValues), ...
                referenceSize(1), referenceSize(2), completeFrames);
        end

        if ~isequal(size(obj.M0), size(obj.M1), size(obj.M2))
            error('DataLoaderClass:RawMomentSizeMismatch', ...
            'Raw M0, M1 and M2 must have identical sizes.');
        end

        % Legacy SH raw input.
        shFile = fullfile(rawFolder, ...
            [obj.filenames, '_SH.raw']);

        if isfile(shFile)
            fprintf('- Reading SH data: %s\n', shFile);

            try
                shData = obj.readSingleRawFile(shFile);

                [numX, numY, numFrames] = size(obj.M0);

                binX = 4;
                binY = 4;

                obj.SH = reshape( ...
                    shData, ...
                    ceil(numX / binX), ...
                    ceil(numY / binY), ...
                    [], numFrames);
            catch ME
                warning('DataLoaderClass:RawSHReadFailed', ...
                    'Failed to read SH data: %s\nError: %s', ...
                    shFile, ME.message);
            end

        else
            fprintf('- No SH data file found\n');
        end

        % No SH_avg raw format is assumed.
    end

    function data = readSingleRawFile(~, filepath)
        fid = fopen(filepath, 'rb');

        if fid == -1
            error('DataLoaderClass:RawOpenFailed', ...
                'Cannot open raw file: %s', filepath);
        end

        closeFile = onCleanup(@() fclose(fid));

        data = fread(fid, Inf, '*single');
    end

    function readHDF5(obj, h5Folder)
        h5Files = dir(fullfile(h5Folder, '*.h5'));

        if isempty(h5Files)
            error('DataLoaderClass:MissingHDF5', ...
                'No .h5 file in %s', h5Folder);
        end

        % Preserve the existing first-file selection policy.
        if numel(h5Files) > 1
            warning('DataLoaderClass:MultipleHDF5Files', ...
                ['Several .h5 files found in %s. ', ...
             'Reading the first file: %s'], ...
                h5Folder, h5Files(1).name);
        end

        filepath = fullfile(h5Folder, h5Files(1).name);

        fprintf('    - Reading HDF5: %s\n', h5Files(1).name);

        info = h5info(filepath, '/');
        names = {info.Datasets.Name};

        obj.M0 = obj.readDataset( ...
            filepath, names, {'moment0', 'M0'});

        obj.M1 = obj.readDataset( ...
            filepath, names, {'moment1', 'M1'});

        obj.M2 = obj.readDataset( ...
            filepath, names, {'moment2', 'M2'});

        obj.HF_M0 = obj.readDataset( ...
            filepath, names, {'HF_M0'});

        obj.LF_M0 = obj.readDataset( ...
            filepath, names, {'LF_M0'});

        obj.SH = obj.readDataset( ...
            filepath, names, {'SH'}, true);

        % SH_avg is independent of legacy SH.
        obj.readSHAvg(filepath, names);
    end

    function readSHAvg(obj, filepath, names)
        obj.SH_avg = single([]);
        obj.SH_avg_sourceFile = '';
        obj.SH_avg_datasetPath = '';
        obj.SH_avg_info = struct();

        datasetName = 'SH_avg';

        if ~ismember(datasetName, names)
            fprintf('    - Optional /SH_avg dataset not found\n');
            return
        end

        datasetPath = ['/', datasetName];
        datasetInfo = h5info(filepath, datasetPath);

        fprintf('    - Reading %s\n', datasetPath);

        % Deliberately do not squeeze, permute, average or square.
        data = h5read(filepath, datasetPath);

        if ~isnumeric(data) || ~isreal(data)
            error('DataLoaderClass:InvalidSHAvgType', ...
                '%s must contain a real numeric array.', ...
                datasetPath);
        end

        if isempty(data)
            error('DataLoaderClass:EmptySHAvg', ...
                '%s exists but contains no data.', datasetPath);
        end

        % Expected logical layout: two spatial axes + frequency.
        % Trailing singleton dimensions are accepted.
        if ndims(data) > 3
            error('DataLoaderClass:InvalidSHAvgDimensions', ...
                ['%s must have at most three nontrailing dimensions ', ...
                 '(two spatial axes and one frequency axis). ', ...
             'Received size: %s'], ...
                datasetPath, mat2str(size(data)));
        end

        obj.SH_avg = single(data);
        obj.SH_avg_sourceFile = filepath;
        obj.SH_avg_datasetPath = datasetPath;
        obj.SH_avg_info = datasetInfo;

        fprintf('      SH_avg size: %s\n', ...
            mat2str(size(obj.SH_avg)));
    end

    function data = readDataset(~, filepath, names, candidates, silent)

        if nargin < 5
            silent = false;
        end

        % Candidate order defines priority.
        datasetName = '';

        for i = 1:numel(candidates)

            if ismember(candidates{i}, names)
                datasetName = candidates{i};
                break
            end

        end

        if isempty(datasetName)
            data = single([]);

            if ~silent
                warning('DataLoaderClass:MissingDataset', ...
                    'Dataset not found (tried: %s)', ...
                    strjoin(candidates, ', '));
            end

            return
        end

        data = single(squeeze( ...
            h5read(filepath, ['/', datasetName])));
    end

end

end
