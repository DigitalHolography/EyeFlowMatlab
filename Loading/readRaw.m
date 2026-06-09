function readRaw(obj)
% READRAW Reads raw video data and associated moment files
%   Improved with better error handling, memory efficiency, and organization

% Validate AVI file existence first
dir_path_avi = fullfile(obj.directory, 'avi');
avi_file = fullfile(dir_path_avi, [obj.filenames, '_moment0.avi']);

if ~isfile(avi_file)
    error('No file found at: %s\nPlease check folder path and filename.', avi_file);
end

% Determine which AVI file to use as reference
base_name = strcat(obj.filenames, '_moment0');
possible_avi_files = {
                      fullfile(dir_path_avi, [base_name, '_raw.avi'])
                      fullfile(dir_path_avi, [base_name, '.avi'])
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

% Read reference video
try
    V = VideoReader(ref_avi_path);
    refvideosize = [V.Height, V.Width, V.NumFrames];
    clear V;

catch ME
    error('Failed to read AVI file: %s\nError: %s', ref_avi_path, ME.message);
end

% Read raw moment files
dir_path_h5 = fullfile(obj.directory, 'h5');
moment_files = {'_moment0', '_moment1', '_moment2'};
output_fields = {'M0', 'M1', 'M2'};

for i = 1:length(moment_files)
    raw_file = fullfile(dir_path_h5, [obj.filenames, moment_files{i}, '.raw']);

    if ~isfile(raw_file)
        error('Raw moment file not found: %s', raw_file);
    end

    fprintf('- Reading: %s\n', raw_file);

    try
        fileID = fopen(raw_file, 'r');
        data = fread(fileID, 'single');
        fclose(fileID);

        if numel(data) ~= prod(refvideosize)
            warning('Size mismatch in %s. Expected %d elements, got %d.', ...
                raw_file, prod(refvideosize), numel(data));
            % Try to reshape with what we have
            closest_dim = floor(numel(data) / prod(refvideosize(1:2))) * refvideosize(1:2);
            data = data(1:prod(closest_dim));
        end

        obj.(output_fields{i}) = reshape(data, refvideosize(1), refvideosize(2), []);
        clear data;

    catch ME
        fclose(fileID); % Ensure file is closed if error occurs
        error('Failed to read raw file %s: %s', raw_file, ME.message);
    end

end

% Import SH data if available
sh_file = fullfile(dir_path_h5, [obj.filenames, '_SH.raw']);

if isfile(sh_file)
    fprintf('- Reading SH data: %s\n', sh_file);

    try
        fileID = fopen(sh_file, 'r');
        SH_data_video = fread(fileID, 'single');
        fclose(fileID);

        [numX, numY, numFrames] = size(obj.M0);
        bin_x = 4; bin_y = 4;
        obj.SH_data_hypervideo = reshape(SH_data_video, ...
            ceil(numX / bin_x), ceil(numY / bin_y), [], numFrames);
        clear SH_data_video;

    catch ME
        fclose all;
        warning('Failed to read SH data: %s\nError: %s', sh_file, ME.message);
    end

else
    fprintf('- Reading: No SH data file found\n');
end

end
