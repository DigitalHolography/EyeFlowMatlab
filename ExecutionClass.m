classdef ExecutionClass < handle
% Main controller class for EyeFlow execution and analysis.
% Coordinates between specialized modules.

properties
    % Basic Info
    path char
    directory char
    originalParentPath char
    params_names cell
    param_name char
    filenames char

    % Modules
    Analyzer AnalyzerClass
    Reporter ReporterClass

    % Input Data
    M0 single
    M1 single
    M2 single
    SH single

    % AI Networks
    AINetworks AINetworksClass

    % Processing Flags
    is_preprocessed = false
    is_segmented = false
    is_velocityAnalyzed = false
    is_volumeRateAnalyzed = false
    is_AllAnalyzed = false

    % Checkbox flags
    flag_segmentation logical
    flag_bloodFlowVelocity_analysis logical
    flag_pulseWaveVelocity logical
    flag_crossSection_analysis logical
    flag_crossSection_export logical
    flag_spectral_analysis logical

    % Components
    ToolBoxMaster ToolBoxClass
    Output OutputClass
    Cache CacheClass
end

methods

    function obj = ExecutionClass(dataPath, originalPath)
        % Constructor
        %   dataPath   - folder containing raw data (may be resolved to *_HD)
        %   originalPath - folder originally selected by user (for parameters)
        if nargin < 2
            originalPath = dataPath;
        end

        obj.originalParentPath = originalPath;
        obj.path = originalPath; % for UI display

        tLoading = tic;
        fprintf("\n----------------------------------\n" + ...
            "Video Loading\n" + ...
        "----------------------------------\n");

        % Load data using DataLoader (resolves subfolders automatically)
        DataLoader = DataLoaderClass(dataPath);

        % Copy loaded data
        obj.directory = DataLoader.directory;
        obj.filenames = DataLoader.filenames;
        obj.M0 = DataLoader.M0;
        obj.M1 = DataLoader.M1;
        obj.M2 = DataLoader.M2;
        obj.SH = DataLoader.SH;
        clear DataLoader;

        % Locate parameter JSON files – start from originalPath (user‑selected folder)
        paramSearchDir = originalPath;

        if ~isfolder(fullfile(paramSearchDir, 'eyeflow', 'json'))
            % Fallback: try the parent of the data folder (if dataPath is a subfolder)
            paramSearchDir = fileparts(dataPath);
        end

        obj.params_names = checkEyeFlowParamsFromJson(paramSearchDir);

        if isempty(obj.params_names)
            error('No JSON parameter file found in %s', paramSearchDir);
        end

        obj.param_name = obj.params_names{1};

        % Initialise output, cache, and analyser
        obj.Output = OutputClass();
        obj.Cache = CacheClass();
        obj.Analyzer = AnalyzerClass(obj.Cache);

        % Load the actual parameters (creates global variable)
        Parameters_json(paramSearchDir, obj.param_name);

        fprintf("- Video Loading took : %ds\n", round(toc(tLoading)));
    end

    function preprocessData(obj)
        PreProcessTimer = tic;
        fprintf("\n----------------------------------\nVideo PreProcessing\n----------------------------------\n");

        Preprocessor = PreprocessorClass(obj.directory, obj.filenames, obj.param_name);
        Preprocessor.preprocess(obj);

        obj.Cache.firstFrameIdx = Preprocessor.firstFrameIdx;
        obj.Cache.lastFrameIdx = Preprocessor.lastFrameIdx;
        obj.Cache.M0_ff = Preprocessor.M0_ff;
        obj.Cache.M0_ff_img = squeeze(mean(obj.Cache.M0_ff, 3));
        obj.Cache.f_RMS = Preprocessor.f_RMS;
        obj.Cache.f_AVG = Preprocessor.f_AVG;
        obj.Cache.displacementField = Preprocessor.displacementField;
        obj.is_preprocessed = Preprocessor.is_preprocessed;

        % Free memory
        obj.M0 = [];
        obj.M1 = [];
        obj.M2 = [];
        obj.SH = [];
        clear Preprocessor;

        fprintf("- Preprocess took : %ds\n", round(toc(PreProcessTimer)));
        fprintf("\n----------------------------------\nPreprocessing Complete\n----------------------------------\n");
    end

    function analyzeData(obj, app)
        AnalyzerTimer = tic;

        ToolBox = obj.ToolBoxMaster;
        params = ToolBox.getParams;

        ToolBox.setOutput(obj.Output);
        ToolBox.setCache(obj.Cache);

        obj.Cache.createTimeVector(ToolBox, obj.Cache.lastFrameIdx);
        obj.Cache.createFreqVector(ToolBox);

        obj.Reporter = ReporterClass(obj);

        if params.json.DebugMode
            profile off
            profile on
        end

        obj.AINetworks.updateAINetworks(params);

        if params.json.Mask.EyeSideClassifierNet
            predictEyeSide(obj.AINetworks.EyeSideClassifierNet);
        end

        if obj.flag_segmentation
            obj.Analyzer.performSegmentation(obj, app);
        end

        if obj.flag_bloodFlowVelocity_analysis
            obj.Analyzer.performPulseAnalysis(obj);
        end

        try

            if obj.flag_pulseWaveVelocity
                obj.Analyzer.performPulseVelocityAnalysis(obj);
            end

        catch ME
            MEdisp(ME, '');
            warning("Pulse Wave Velocity Analysis failed");
        end

        try

            if obj.flag_crossSection_analysis
                obj.Analyzer.performCrossSectionAnalysis(obj);
            end

            if obj.flag_crossSection_export
                obj.Analyzer.generateexportCrossSectionResults(obj);
            end

        catch ME
            MEdisp(ME, "", "WARN", "Cross-Section Analysis failed");
        end

        if obj.flag_spectral_analysis && ~isempty(obj.SH)
            obj.Analyzer.performSpectralAnalysis(obj);
        end

        diary off;

        if params.json.DebugMode
            profile off
            profile viewer
        end

        fprintf("- Total Analysis took : %ds\n", round(toc(AnalyzerTimer)));
    end

end

end
