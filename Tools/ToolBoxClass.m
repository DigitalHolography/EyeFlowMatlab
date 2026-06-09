classdef ToolBoxClass < handle
% ToolBoxClass holds useful variables for eyeflow processing.
% Receives an HD folder path and derives the data name, EF path, etc.

properties
    % Input Paths
    HD_path char % '...\XXX_HD\'
    param_name char % 'input_EF_params.json'

    % Intermediary
    data_name char % 'XXX'
    folder_name char % 'XXX_EF'

    % Created folder paths
    EF_path char % '...\XXX_EF\'
    path_png char
    path_eps char
    path_pdf char
    path_gif char
    path_txt char
    path_avi char
    path_mp4 char
    path_json char
    path_h5 char
    path_log char

    % Parameters
    stride double
    fs double
    f1 double
    f2 double
    record_time_stamps_us
    holo_frames

    % Results
    Cache
    Output
    params
end

methods

    function obj = ToolBoxClass(path, param_name)
        obj.HD_path = path;
        obj.param_name = param_name;

        obj.extractDataNameAndEFPath();
        obj.initializePaths();
        obj.loadParameters();
        obj.setupLogging();
        obj.copyInputParameters();
        obj.setGlobalToolBox();
    end

    function Params = getParams(obj)

        if isempty(obj.params)
            obj.params = Parameters_json(obj.HD_path, obj.param_name);
        end

        Params = obj.params;
    end

    function setCache(obj, Cache)
        obj.Cache = Cache;
    end

    function setOutput(obj, Output)
        obj.Output = Output;
    end

end

% ---- non‑static private methods ----
methods (Access = private)

    function setGlobalToolBox(obj)
        global ToolBoxGlobal
        ToolBoxGlobal = obj;
    end

    function extractDataNameAndEFPath(obj)
        % HD_path is always the _HD folder (e.g., ...\XXX_HD\)
        cleanPath = strtrim(obj.HD_path);

        if endsWith(cleanPath, filesep)
            cleanPath = cleanPath(1:end - 1);
        end

        [parentDir, folderName] = fileparts(cleanPath);

        % Remove trailing _HD or _HD_XX
        baseName = regexprep(folderName, '_HD(_\d+)?$', '', 'ignorecase');
        % Also clean if already _EF (unlikely)
        baseName = regexprep(baseName, '_EF(_\d+)?$', '', 'ignorecase');

        obj.data_name = baseName;
        obj.EF_path = fullfile(parentDir, [baseName, '_EF'], filesep);
    end

    function initializePaths(obj)
        obj.folder_name = [obj.data_name, '_EF'];

        obj.path_png = fullfile(obj.EF_path, 'png');
        obj.path_eps = fullfile(obj.EF_path, 'eps');
        obj.path_pdf = fullfile(obj.EF_path, 'pdf');
        obj.path_gif = fullfile(obj.EF_path, 'gif');
        obj.path_txt = fullfile(obj.EF_path, 'txt');
        obj.path_avi = fullfile(obj.EF_path, 'avi');
        obj.path_mp4 = fullfile(obj.EF_path, 'mp4');
        obj.path_json = fullfile(obj.EF_path, 'json');
        obj.path_h5 = fullfile(obj.EF_path, 'h5');
        obj.path_log = fullfile(obj.EF_path, 'log');

        % Create all required directories
        dirs = {obj.EF_path, obj.path_png, obj.path_eps, obj.path_gif, ...
                    obj.path_txt, obj.path_avi, obj.path_mp4, obj.path_json, ...
                    obj.path_log, obj.path_pdf, obj.path_h5};

        for d = dirs

            if ~isfolder(d{1})
                mkdir(d{1});
            end

        end

    end

    function loadParameters(obj)
        % Try RenderingParameters*.json
        fname = obj.getFirstFileMatch(obj.HD_path, '*RenderingParameters*.json');

        if ~isempty(fname)
            fprintf('Reading parameters from: %s\n', fname);
            data = jsondecode(fileread(fname));
            obj.stride = data.batch_stride;
            obj.fs = data.fs;
            obj.f1 = data.time_range(1);
            obj.f2 = data.time_range(2);
            return;
        end

        % Try input_HD_params*.json
        fname = obj.getFirstFileMatch(obj.HD_path, '*input_HD_params*.json');

        if ~isempty(fname)
            fprintf('Reading parameters from: %s\n', fname);
            data = jsondecode(fileread(fname));

            if isfield(data, 'batch_stride') % Version 2.9
                obj.stride = data.batch_stride;
                obj.fs = data.fs;
                obj.f1 = data.time_range(1);

                if isfield(data, 'record_time_stamps_us')
                    obj.record_time_stamps_us = data.record_time_stamps_us;
                end

                if isfield(data, 'num_frames')
                    obj.holo_frames.first = data.first_frame;
                    obj.holo_frames.last = data.end_frame;
                end

            else % Version 3.0+
                obj.stride = data.batchStride;
                obj.fs = data.fs;
                obj.f1 = data.frequencyRange1;
                obj.f2 = data.frequencyRange2;

                if isfield(data, 'record_time_stamps_us')
                    obj.record_time_stamps_us = data.record_time_stamps_us;
                end

                if isfield(data, 'first_frame')
                    obj.holo_frames.first = data.first_frame;
                end

                if isfield(data, 'end_frame')
                    obj.holo_frames.last = data.end_frame;
                end
            end

            return;
        end

        % Try .mat cache file
        matFile = fullfile(obj.HD_path, 'mat', [obj.folder_name, '.mat']);

        if isfile(matFile)
            fprintf('Reading parameters from: %s\n', matFile);
            S = load(matFile, 'cache');
            obj.stride = S.cache.batch_stride;
            obj.fs = S.cache.Fs / 1000; % Hz -> kHz
            obj.f1 = S.cache.time_transform.f1;
            obj.f2 = S.cache.time_transform.f2;
            return;
        end

        % Try Holovibes_rendering_parameters.json
        hvFile = fullfile(obj.HD_path, 'Holovibes_rendering_parameters.json');

        if isfile(hvFile)
            fprintf('Reading parameters from: %s\n', hvFile);
            data = jsondecode(fileread(hvFile));
            obj.stride = data.compute_settings.image_rendering.time_transformation_stride;
            obj.fs = data.info.camera_fps / 1000;
            obj.f1 = data.compute_settings.view.z.start / ...
                data.compute_settings.image_rendering.time_transformation_size * obj.fs;
            obj.f2 = obj.fs / 2;
            return;
        end

        % Fallback defaults
        warning('No parameter file found. Using default values.');
        obj.stride = 512;
        obj.fs = 36;
        obj.f1 = 6;
        obj.f2 = obj.fs / 2;
    end

    function setupLogging(obj)
        diary off
        diaryFile = fullfile(obj.path_log, sprintf('%s_log.txt', obj.folder_name));
        set(0, 'DiaryFile', diaryFile);
        diary on

        fprintf('==================================\n');
        fprintf('HD Folder: %s\n', obj.HD_path);
        fprintf('EF Folder: %s\n', obj.EF_path);
        fprintf('Data Name: %s\n', obj.data_name);
        fprintf('Start Time: %s\n', datetime('now', 'Format', 'yyyy/MM/dd HH:mm:ss'));
        fprintf('==================================\n');
    end

    function copyInputParameters(obj)
        src = fullfile(obj.HD_path, 'eyeflow', 'json', obj.param_name);
        dst = fullfile(obj.path_json, sprintf('%s_Input_EF_Params.json', obj.folder_name));

        if ~isfile(src)
            warning('Source parameter file not found: %s', src);
        else

            try
                copyfile(src, dst);
            catch ME
                warning('Failed to copy parameter file: %s\nError: %s', src, ME.message);
            end

        end

        % Copy version.txt to EF_path root
        [currentPath, ~, ~] = fileparts(mfilename('fullpath'));
        [appRoot, ~, ~] = fileparts(currentPath);
        versionSrc = fullfile(appRoot, 'version.txt');
        versionDst = fullfile(obj.EF_path, sprintf('%s_version.txt', obj.folder_name));

        if isfile(versionSrc)
            copyfile(versionSrc, versionDst);
        else
            warning('version.txt not found at: %s', versionSrc);
        end

        obj.saveGit();
    end

    function saveGit(obj)
        [statusBranch, branch] = system('git symbolic-ref --short HEAD');

        if statusBranch == 0
            branch = strtrim(branch);
            msgBranch = 'Current branch : %s \r';
        else
            vers = readlines('version.txt');
            msgBranch = sprintf('EyeFlow GitHub version %s\r', char(vers));
        end

        [statusHash, hash] = system('git rev-parse HEAD');

        if statusHash == 0
            hash = strtrim(hash);
            msgHash = 'Latest Commit Hash : %s \r';
        else
            msgHash = '';
        end

        [statusTag, tag] = system('git describe --tags');

        if statusTag == 0
            tag = strtrim(tag);
            msgTag = 'Most recent tag : %s \r';
        else
            msgTag = '';
        end

        fprintf('----------------------------------\rGIT VERSION :\r');
        fprintf(msgBranch, branch);
        fprintf(msgHash, hash);
        fprintf(msgTag, tag);
        fprintf('----------------------------------\r');

        logFile = fullfile(obj.path_log, sprintf('%s_git_version.txt', obj.folder_name));
        fid = fopen(logFile, 'w');

        if fid == -1
            error('Cannot open file: %s', logFile);
        end

        fprintf(fid, '----------------------------------\rGIT VERSION :\r');
        fprintf(fid, msgBranch, branch);
        fprintf(fid, msgHash, hash);
        fprintf(fid, msgTag, tag);
        fprintf(fid, '----------------------------------\r');
        fclose(fid);
    end

end

% ---- static private utility methods ----
methods (Access = private, Static)

    function fname = getFirstFileMatch(folder, pattern)
        d = dir(fullfile(folder, pattern));

        if isempty(d)
            fname = '';
        else
            fname = fullfile(d(1).folder, d(1).name);
        end

    end

    function hdFolder = findHDSubfolder(parentPath)
        d = dir(fullfile(parentPath, '*_HD*'));
        d = d([d.isdir] & ~ismember({d.name}, {'.', '..'}));

        if isempty(d)
            hdFolder = '';
        else
            hdFolder = d(1).name;
        end

    end

end

end
