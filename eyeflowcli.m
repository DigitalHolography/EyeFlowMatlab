function eyeflowcli(varargin)
% Initialize Application
appRoot = fileparts(mfilename('fullpath'));
versionFile = fullfile(appRoot, "version.txt");

if isfile(versionFile)
    version_tag = readlines(versionFile);
    fprintf("EyeFlow version : %s\n", version_tag);
else
    fprintf("EyeFlow version : Unknown (version.txt not found at %s)\n", versionFile);
end

beginComputerTime = datetime('now', 'Format', 'yyyy/MM/dd HH:mm:ss');
fprintf("Begin Computer Time: %s\n", beginComputerTime);

if ~isdeployed
    % In Development: Add all subfolders to path
    fprintf("Running in Development Mode\n");
    addpath(fullfile(appRoot, "BloodFlowVelocity"));
    addpath(fullfile(appRoot, "BloodFlowVelocity", "Elastography"));
    addpath(fullfile(appRoot, "CrossSection"));
    addpath(fullfile(appRoot, "Loading"));
    addpath(fullfile(appRoot, "Parameters"));
    addpath(fullfile(appRoot, "Preprocessing"));
    addpath(fullfile(appRoot, "Scripts"));
    addpath(fullfile(appRoot, "Segmentation"));
    addpath(fullfile(appRoot, "SHAnalysis"));
    addpath(fullfile(appRoot, "Tools"));
    addpath(fullfile(appRoot, "Outputs"));
else
    fprintf("Running in Deployed Mode.\n");
end

fprintf("Application root is %s\n", appRoot);

% --- ARGUMENT PARSING ---
mode = 'single';
inputPath = "";
customConfigPath = "";
useSafeMode = false;

idx = 1;

while idx <= nargin
    arg = string(varargin{idx});

    switch arg
        case "-batch"
            mode = 'batch';
        case "-safe"
            useSafeMode = true;
        case "-config"
            % Check if next argument exists and isn't another flag
            if idx < nargin && ~startsWith(string(varargin{idx + 1}), "-")
                customConfigPath = string(varargin{idx + 1});
                idx = idx + 1; % Skip next arg as it was the path
            else
                % Open file explorer for config
                [cfg_name, cfg_path] = uigetfile('*.json', 'Select Custom EyeFlow Parameters JSON');

                if isequal(cfg_name, 0)
                    fprintf("No config selected, using defaults.\n");
                else
                    customConfigPath = fullfile(cfg_path, cfg_name);
                end

            end

        otherwise
            % Assume this is the input path (data folder or batch file)
            inputPath = arg;
    end

    idx = idx + 1;
end

% --- CONFIG SELECTION ---
% Priority: 1. Custom (-config) | 2. Safe (-safe) | 3. Default
if customConfigPath ~= "" && isfile(customConfigPath)
    selectedJson = customConfigPath;
    fprintf("Using Custom Config: %s\n", selectedJson);
elseif useSafeMode
    selectedJson = fullfile(appRoot, "Parameters", "DefaultEyeFlowParamsBatchSafeMode.json");
    fprintf("Using Safe Mode Config.\n");
else
    selectedJson = fullfile(appRoot, "Parameters", "DefaultEyeFlowParamsBatch.json");
    fprintf("Using Standard Config.\n");
end

if ~isfile(selectedJson)
    error("CRITICAL: Configuration file not found: %s", selectedJson);
end

% --- PATH SELECTION ---

try

    if strcmp(mode, 'batch')

        if inputPath == ""
            [txt_name, txt_path] = uigetfile('*.txt', 'Select the list of HoloDoppler processed folders');
            if isequal(txt_name, 0), return; end
            fullInputPath = fullfile(txt_path, txt_name);
        else
            fullInputPath = inputPath;
            if ~isfile(fullInputPath), error("Batch file not found: %s", fullInputPath); end
        end

        fprintf("Running in Batch Mode: %s\n", fullInputPath);
        rawInputs = strtrim(readlines(fullInputPath));
        rawInputs = rawInputs(rawInputs ~= "");
    else

        if inputPath == ""
            [holo_name, holo_path] = uigetfile('*.holo', 'Select the .holo file');
            if isequal(holo_name, 0), return; end
            fullInputPath = fullfile(holo_path, holo_name);
        else
            fullInputPath = inputPath;
        end

        fprintf("Running in Single Mode: %s\n", fullInputPath);
        rawInputs = string(fullInputPath);
    end

catch ME
    fprintf("Error during path selection: %s\n", ME.message);
    return;
end

% Resolve .holo files to HD folders
paths = string.empty;

for k = 1:length(rawInputs)
    currentInput = rawInputs(k);
    if currentInput == "" || ismissing(currentInput); continue; end

    if endsWith(currentInput, ".holo", 'IgnoreCase', true)
        latestHD = findLatestHDFolder(currentInput);

        if ~ismissing(latestHD)
            paths(end + 1, 1) = latestHD;
        end

    elseif isfolder(currentInput)
        paths(end + 1, 1) = currentInput;
    end

end

if isempty(paths)
    fprintf("No valid paths to process. Exiting.\n");
    return;
end

% --- PRE-PROCESSING (JSON & MASKS) ---
for ind = 1:length(paths)
    targetPath = paths(ind);
    efPath = fullfile(targetPath, 'eyeflow');
    jsonDir = fullfile(efPath, 'json');
    maskDir = fullfile(efPath, 'mask');

    if ~isfolder(jsonDir), mkdir(jsonDir); end

    % Setup Config JSON
    delete(fullfile(jsonDir, '*.json'));
    copyfile(selectedJson, fullfile(jsonDir, 'input_EF_params.json'));

    % Handle Masks
    if isfile(fullfile(maskDir, 'forceMaskArtery.png'))
        movefile(fullfile(maskDir, 'forceMaskArtery.png'), fullfile(maskDir, 'oldForceMaskArtery.png'));
    end

    if isfile(fullfile(maskDir, 'forceMaskVein.png'))
        movefile(fullfile(maskDir, 'forceMaskVein.png'), fullfile(maskDir, 'oldForceMaskVein.png'));
    end

end

% --- SETUP PARPOOL ---
% maxWorkers = parcluster("local").NumWorkers;
%
% params_names = checkEyeFlowParamsFromJson(rawInputs(1)); % checks compatibility between found EF params and Default EF params of this version of EF.
% params = Parameters_json(rawInputs(1), params_names{1});
%
% if params.json.NumberOfWorkers > 0 && params.json.NumberOfWorkers < maxWorkers
%     fprintf("Using nb of workers stored inside the parameters.json (%i)", params.json.NumberOfWorkers);
%     setupParpool(params.json.NumberOfWorkers);
% end

% --- AI LOADING & EXECUTION ---
fprintf("Loading AI Models...\n");
AIModels = AINetworksClass();

for ind = 1:length(paths)
    p = paths(ind);
    if p == "" || ismissing(p); continue; end
    if isfolder(p) && ~endsWith(p, filesep), p = strcat(p, filesep); end

    fprintf("Processing: %s\n", p);
    runAnalysisBlock(p, AIModels);
end

endComputerTime = datetime('now', 'Format', 'yyyy/MM/dd HH:mm:ss');
fprintf("All done! Total time elapsed: %s\n", string(endComputerTime - beginComputerTime));
end

function runAnalysisBlock(path, AIModels)
totalTime = tic;
ME = [];

try
    ExecClass = ExecutionClass(path);

    ExecClass.AINetworks = AIModels;

    % Ensure ExecutionClass uses the directory passed to it
    ExecClass.ToolBoxMaster = ToolBoxClass(ExecClass.directory, ExecClass.param_name);

    ExecClass.preprocessData();

    ExecClass.flag_segmentation = 1;
    ExecClass.flag_spectral_analysis = 0;
    ExecClass.flag_bloodFlowVelocity_analysis = 1;
    ExecClass.flag_pulseWaveVelocity = 0;
    ExecClass.flag_crossSection_analysis = 0;
    ExecClass.flag_crossSection_export = 0;

    ExecClass.analyzeData([]);
catch e
    ME = e;
    % Check if MEdisp exists, otherwise use disp
    if exist('MEdisp', 'file')
        MEdisp(e, path);
    else
        disp(e.message);
    end

end

try
    ExecClass.Reporter.getA4Report(ME);
    ExecClass.Reporter.saveOutputs();
    ExecClass.Reporter.displayFinalSummary(totalTime);
catch e

    if exist('MEdisp', 'file')
        MEdisp(e, path);
    else
        disp(e.message);
    end

end

end

function latestHDPath = findLatestHDFolder(holoPath)
% Finds the HD folder with the highest render number in the same directory as the holo file
% Naming convention: [holo_filename]_HD_[RENDER_NUMBER]

latestHDPath = string(missing);

[parentDir, fname, ~] = fileparts(holoPath);

% Get list of folders in parent directory
contents = dir(parentDir);
dirFlags = [contents.isdir];
subFolders = contents(dirFlags);

maxRenderNum = -1;

% Escaped pattern for regex (escape special regex characters in filename)
escapedName = regexptranslate('escape', fname);
pattern = "^" + escapedName + "_HD_(\d+)$";

for k = 1:length(subFolders)
    thisName = string(subFolders(k).name);

    tokens = regexp(thisName, pattern, 'tokens');

    if ~isempty(tokens)
        % Extract the number
        renderNum = str2double(tokens{1}{1});

        if renderNum > maxRenderNum
            maxRenderNum = renderNum;
            latestHDPath = fullfile(parentDir, thisName);
        end

    end

end

end
