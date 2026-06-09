classdef DataLoaderClass < handle
% Handles data loading – supports .holo, .raw, .h5.
% Automatically resolves to a *_HD subfolder if it contains the raw data.

properties
    directory char
    filenames char
    M0 single
    M1 single
    M2 single
    SH single
end

methods

    function obj = DataLoaderClass(selectedPath)
        % selectedPath is the user-chosen folder (may be parent or HD folder)
        obj.directory = obj.cleanPath(selectedPath);
        % Resolve to the actual data folder (e.g., *_HD subfolder)
        obj.directory = obj.resolveDataFolder(obj.directory);
        obj.filenames = obj.extractFilename(obj.directory);
        obj.loadData();
    end

    function delete(obj)
        obj.M0 = []; obj.M1 = []; obj.M2 = []; obj.SH = [];
    end

end

methods (Access = private)

    function out = cleanPath(~, in)
        % Normalize separators and remove trailing slash
        out = strrep(in, '/', filesep);
        out = strrep(out, '\', filesep);

        if endsWith(out, filesep)
            out = out(1:end - 1);
        end

    end

    function filename = extractFilename(~, folder)
        [~, last] = fileparts(folder);
        filename = last;
    end

    function dataFolder = resolveDataFolder(obj, startPath)
        % Look for a subfolder ending with '_HD' that contains raw data.
        if obj.containsRawData(startPath)
            dataFolder = startPath;
            return;
        end

        hdDirs = dir(fullfile(startPath, '*_HD'));
        hdDirs = hdDirs([hdDirs.isdir]);

        for i = 1:length(hdDirs)
            candidate = fullfile(startPath, hdDirs(i).name);

            if obj.containsRawData(candidate)
                dataFolder = candidate;
                return;
            end

        end

        dataFolder = startPath; % fallback
    end

    function hasData = containsRawData(~, folder)
        rawSub = fullfile(folder, 'h5');

        if isfolder(rawSub)
            h5 = dir(fullfile(rawSub, '*.h5'));
            raw = dir(fullfile(rawSub, '*.raw'));

            if ~isempty(h5) || ~isempty(raw)
                hasData = true;
                return;
            end

        end

        h5 = dir(fullfile(folder, '*.h5'));
        raw = dir(fullfile(folder, '*.raw'));
        hasData = ~isempty(h5) || ~isempty(raw);
    end

    function loadData(obj)
        % Check for .holo file first (legacy)
        holoFile = [obj.directory, '.holo'];

        if isfile(holoFile)
            obj.loadHoloFile();
            return;
        end

        % Then look for HDF5 / raw data
        rawDir = fullfile(obj.directory, 'h5');

        if isfolder(rawDir)
            h5 = dir(fullfile(rawDir, '*.h5'));
            raw = dir(fullfile(rawDir, '*.raw'));

            if ~isempty(h5)
                obj.readHDF5(rawDir);
                return;
            elseif ~isempty(raw)
                obj.readRaw(rawDir);
                return;
            end

        end

        % Fallback: look directly in obj.directory
        h5 = dir(fullfile(obj.directory, '*.h5'));
        raw = dir(fullfile(obj.directory, '*.raw'));

        if ~isempty(h5)
            obj.readHDF5(obj.directory);
        elseif ~isempty(raw)
            obj.readRaw(obj.directory);
        else
            error('No data file (.holo, .h5, .raw) found in %s or its "raw" subfolder', obj.directory);
        end

    end

    function loadHoloFile(obj)
        fprintf('Reading .holo file: %s.holo\n', obj.directory);
        [videoM0, videoM1, videoM2] = readMoments([obj.directory, '.holo']);
        readMomentsFooter(obj.directory);
        obj.M0 = pagetranspose(videoM0);
        obj.M1 = pagetranspose(videoM1 / 1e3);
        obj.M2 = pagetranspose(videoM2 / 1e6);
    end

    function readRaw(obj, rawFolder)
        % rawFolder is the folder containing .raw files (may be the 'raw' subfolder or main folder)
        % AVI files are expected in obj.directory/avi
        dir_avi = fullfile(obj.directory, 'avi');
        avi_file = fullfile(dir_avi, [obj.filenames, '_moment0.avi']);

        if ~isfile(avi_file)
            error('AVI file not found: %s', avi_file);
        end

        base_name = [obj.filenames, '_moment0'];
        possible_avi_files = {
                              fullfile(dir_avi, [base_name, '_raw.avi'])
                              fullfile(dir_avi, [base_name, '.avi'])
                              };
        ref_avi_path = '';

        for i = 1:length(possible_avi_files)

            if isfile(possible_avi_files{i})
                ref_avi_path = possible_avi_files{i};
                break;
            end

        end

        if isempty(ref_avi_path)
            error('No suitable AVI reference file found for: %s', base_name);
        end

        fprintf('- Reading reference video: %s\n', ref_avi_path);

        try
            V = VideoReader(ref_avi_path);
            refvideosize = [V.Height, V.Width, V.NumFrames];
            clear V;
        catch ME
            error('Failed to read AVI file: %s\nError: %s', ref_avi_path, ME.message);
        end

        % Read raw moment files from rawFolder
        moment_files = {'_moment0', '_moment1', '_moment2'};
        output_fields = {'M0', 'M1', 'M2'};

        for i = 1:length(moment_files)
            raw_file = fullfile(rawFolder, [obj.filenames, moment_files{i}, '.raw']);

            if ~isfile(raw_file)
                error('Raw moment file not found: %s', raw_file);
            end

            fprintf('- Reading: %s\n', raw_file);

            try
                fid = fopen(raw_file, 'r');
                data = fread(fid, 'single');
                fclose(fid);

                if numel(data) ~= prod(refvideosize)
                    warning('Size mismatch in %s. Expected %d, got %d.', raw_file, prod(refvideosize), numel(data));
                    closest_dim = floor(numel(data) / prod(refvideosize(1:2))) * refvideosize(1:2);
                    data = data(1:closest_dim);
                end

                obj.(output_fields{i}) = reshape(data, refvideosize(1), refvideosize(2), []);
                clear data;
            catch ME
                fclose all;
                error('Failed to read raw file %s: %s', raw_file, ME.message);
            end

        end

        % SH file (if any)
        sh_file = fullfile(rawFolder, [obj.filenames, '_SH.raw']);

        if isfile(sh_file)
            fprintf('- Reading SH data: %s\n', sh_file);

            try
                fid = fopen(sh_file, 'r');
                SH_data = fread(fid, 'single');
                fclose(fid);
                [numX, numY, numFrames] = size(obj.M0);
                bin_x = 4; bin_y = 4;
                obj.SH = reshape(SH_data, ceil(numX / bin_x), ceil(numY / bin_y), [], numFrames);
                clear SH_data;
            catch ME
                fclose all;
                warning('Failed to read SH data: %s\nError: %s', sh_file, ME.message);
            end

        else
            fprintf('- No SH data file found\n');
        end

    end

    function readHDF5(obj, h5Folder)
        % h5Folder is the folder containing the .h5 file (may be 'raw' subfolder or main folder)
        h5_list = dir(fullfile(h5Folder, '*.h5'));

        if isempty(h5_list)
            error('No .h5 file in %s', h5Folder);
        end

        filepath = fullfile(h5Folder, h5_list(1).name);
        fprintf('    - Reading HDF5: %s\n', h5_list(1).name);
        info = h5info(filepath, '/');
        names = {info.Datasets.Name};

        if ismember('moment0', names) || ismember('M0', names)
            ds = intersect(names, {'moment0', 'M0'});
            obj.M0 = squeeze(h5read(filepath, ['/' ds{1}]));
        else
            warning('M0 dataset not found');
        end

        if ismember('moment1', names) || ismember('M1', names)
            ds = intersect(names, {'moment1', 'M1'});
            obj.M1 = squeeze(h5read(filepath, ['/' ds{1}]));
        else
            warning('M1 dataset not found');
        end

        if ismember('moment2', names) || ismember('M2', names)
            ds = intersect(names, {'moment2', 'M2'});
            obj.M2 = squeeze(h5read(filepath, ['/' ds{1}]));
        else
            warning('M2 dataset not found');
        end

        if ismember('SH', names)
            obj.SH = squeeze(h5read(filepath, '/SH'));
        else
            fprintf('SH dataset not found');
        end

    end

end

end
