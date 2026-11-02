classdef ExecutionClass < handle
% Main controller class for EyeFlow execution and analysis.
% Coordinates loading, preprocessing and analysis.
%
% gaussian_w:
%   Loaded independently of the moments.
%   Passed to PreprocessorClass, then stored in Cache.gaussian_w.
%   Does not replace or overwrite Cache.f_RMS.
%   No unit conversion or normalization is performed here.

properties
    % Basic information
    path char
    directory char
    originalParentPath char
    params_names cell
    param_name char
    filenames char

    % Modules
    Analyzer AnalyzerClass
    Reporter ReporterClass

    % Input data
    M0 single
    M1 single
    M2 single
    SH single
    HF_M0 single
    LF_M0 single
    gaussian_w single

    % AI networks
    AINetworks AINetworksClass

    % Processing flags
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
        % dataPath:
        %   Folder containing input data, possibly a parent of *_HD.
        %
        % originalPath:
        %   Folder originally selected by the user, used for parameters.

        if nargin < 2
            originalPath = dataPath;
        end

        obj.originalParentPath = char(originalPath);
        obj.path = char(originalPath);

        tLoading = tic;

        fprintf("\n----------------------------------\n" + ...
            "Video Loading\n" + ...
        "----------------------------------\n");

        % DataLoader resolves the input folder automatically.
        DataLoader = DataLoaderClass(dataPath);

        % Keep DataLoader alive until SH_avg has been copied to Cache..
        % Keep DataLoader alive until SH_avg has been copied to the Cache.
        obj.directory = DataLoader.directory;
        obj.filenames = DataLoader.filenames;

        obj.M0 = DataLoader.M0;
        obj.M1 = DataLoader.M1;
        obj.M2 = DataLoader.M2;
        obj.SH = DataLoader.SH;

        obj.HF_M0 = DataLoader.HF_M0;
        obj.LF_M0 = DataLoader.LF_M0;

        obj.gaussian_w = DataLoader.gaussian_w;

        if isempty(obj.gaussian_w)
            fprintf(['    - gaussian_w not available: ', ...
                     'Gaussian-width analysis will require this dataset.\n']);
        else

            if ~isequal(size(obj.gaussian_w), size(obj.M0))
                error('ExecutionClass:GaussianWSizeMismatch', ...
                    ['Input gaussian_w and M0 must have identical sizes. ', ...
                 'gaussian_w: %s; M0: %s.'], ...
                    mat2str(size(obj.gaussian_w)), ...
                    mat2str(size(obj.M0)));
            end

            fprintf('    - gaussian_w loaded: %s\n', ...
                mat2str(size(obj.gaussian_w)));

            fprintf('      Source: %s\n', ...
                DataLoader.gaussian_w_sourceFile);

            fprintf('      Dataset: %s\n', ...
                DataLoader.gaussian_w_datasetPath);
        end

        % Locate parameter JSON files from the user-selected folder.
        paramSearchDir = char(originalPath);

        if ~isfolder(fullfile(paramSearchDir, 'eyeflow', 'json'))
            % Preserve the existing fallback policy.
            paramSearchDir = fileparts(char(dataPath));
        end

        obj.params_names = checkEyeFlowParamsFromJson(paramSearchDir);

        if isempty(obj.params_names)
            error('ExecutionClass:MissingParameters', ...
                'No JSON parameter file found in %s', ...
                paramSearchDir);
        end

        obj.param_name = obj.params_names{1};

        % Initialize output and cache.
        obj.Output = OutputClass();
        obj.Cache = CacheClass();

        % Preserve the input spectrum independently of video preprocessing.
        obj.Cache.SH_avg = DataLoader.SH_avg;
        obj.Cache.SH_avg_sourceFile = DataLoader.SH_avg_sourceFile;
        obj.Cache.SH_avg_datasetPath = DataLoader.SH_avg_datasetPath;
        obj.Cache.SH_avg_info = DataLoader.SH_avg_info;

        if isempty(obj.Cache.SH_avg)
            fprintf('    - SH_avg not available: spectral cache is empty\n');
        else
            fprintf('    - SH_avg cached: %s\n', ...
                mat2str(size(obj.Cache.SH_avg)));

            fprintf('      Source: %s\n', ...
                obj.Cache.SH_avg_sourceFile);

            fprintf('      Dataset: %s\n', ...
                obj.Cache.SH_avg_datasetPath);
        end

        clear DataLoader;

        % Initialize analyzer with the populated cache.
        obj.Analyzer = AnalyzerClass(obj.Cache);

        % Load parameters and initialize their global representation.
        Parameters_json(paramSearchDir, obj.param_name);

        fprintf("- Video Loading took : %ds\n", ...
            round(toc(tLoading)));
    end

    function preprocessData(obj)
        PreProcessTimer = tic;

        fprintf("\n----------------------------------\n" + ...
            "Video PreProcessing\n" + ...
        "----------------------------------\n");

        % Fail explicitly if the companion classes have not been updated.
        if ~isprop(obj.Cache, 'gaussian_w')
            error('ExecutionClass:MissingGaussianWCacheProperty', ...
                ['CacheClass must declare the property ', ...
             '"gaussian_w single" before preprocessing.']);
        end

        Preprocessor = PreprocessorClass( ...
            obj.directory, obj.filenames, obj.param_name);

        if ~isprop(Preprocessor, 'gaussian_w')
            error('ExecutionClass:MissingGaussianWPreprocessorProperty', ...
                ['PreprocessorClass must declare gaussian_w and ', ...
             'include it in loadFrom and VideoFields.']);
        end

        hadGaussianW = ~isempty(obj.gaussian_w);

        Preprocessor.preprocess(obj);

        % Validate the processed cube before copying it into Cache.
        if hadGaussianW && isempty(Preprocessor.gaussian_w)
            error('ExecutionClass:GaussianWLostDuringPreprocessing', ...
                ['gaussian_w was loaded but is empty after preprocessing. ', ...
             'Check PreprocessorClass.loadFrom and preprocessing helpers.']);
        end

        if ~isempty(Preprocessor.gaussian_w)

            if ~isequal( ...
                    size(Preprocessor.gaussian_w), ...
                    size(Preprocessor.f_RMS), ...
                    size(Preprocessor.M0_ff))

                error('ExecutionClass:ProcessedGaussianWSizeMismatch', ...
                    ['After preprocessing, gaussian_w, f_RMS and M0_ff ', ...
                     'must have identical sizes. ', ...
                 'gaussian_w: %s; f_RMS: %s; M0_ff: %s.'], ...
                    mat2str(size(Preprocessor.gaussian_w)), ...
                    mat2str(size(Preprocessor.f_RMS)), ...
                    mat2str(size(Preprocessor.M0_ff)));
            end

        end

        % Temporal metadata.
        obj.Cache.firstFrameIdx = Preprocessor.firstFrameIdx;
        obj.Cache.lastFrameIdx = Preprocessor.lastFrameIdx;

        % Display and segmentation data.
        obj.Cache.M0_ff = Preprocessor.M0_ff;
        obj.Cache.M0_ff_img = squeeze(mean(obj.Cache.M0_ff, 3));

        % Keep both frequency estimators independently.
        obj.Cache.f_RMS = Preprocessor.f_RMS;
        obj.Cache.f_AVG = Preprocessor.f_AVG;
        obj.Cache.gaussian_w = Preprocessor.gaussian_w;

        % Band data.
        obj.Cache.HF_M0 = Preprocessor.HF_M0;
        obj.Cache.LF_M0 = Preprocessor.LF_M0;

        % Assign even when empty, to avoid retaining a previous result.
        obj.Cache.bandRatio = Preprocessor.bandRatio;

        if isempty(Preprocessor.bandRatio)
            obj.Cache.bandRatio_img = [];
        else
            obj.Cache.bandRatio_img = squeeze( ...
                mean(Preprocessor.bandRatio, 3, 'omitnan'));
        end

        obj.Cache.displacementField = Preprocessor.displacementField;

        if isempty(obj.Cache.gaussian_w)
            fprintf('    - Preprocessed gaussian_w: unavailable\n');
        else
            fprintf('    - Preprocessed gaussian_w cached: %s\n', ...
                mat2str(size(obj.Cache.gaussian_w)));
        end

        % Match the spatial resolution used by segmentation.
        % This does not perform spatial registration.
        targetSpatialSize = [ ...
                                 size(obj.Cache.M0_ff, 1), ...
                                 size(obj.Cache.M0_ff, 2)];

        obj.Cache.resizeSHAvg(targetSpatialSize);

        obj.is_preprocessed = Preprocessor.is_preprocessed;

        % Free raw input data after successful preprocessing.
        obj.M0 = [];
        obj.M1 = [];
        obj.M2 = [];
        obj.SH = [];

        obj.HF_M0 = [];
        obj.LF_M0 = [];

        obj.gaussian_w = [];

        clear Preprocessor;

        fprintf("- Preprocess took : %ds\n", ...
            round(toc(PreProcessTimer)));

        fprintf("\n----------------------------------\n" + ...
            "Preprocessing Complete\n" + ...
        "----------------------------------\n");
    end

    function analyzeData(obj, app)

        if nargin < 2
            app = [];
        end

        AnalyzerTimer = tic;

        ToolBox = obj.ToolBoxMaster;
        params = ToolBox.getParams;

        ToolBox.setOutput(obj.Output);
        ToolBox.setCache(obj.Cache);

        obj.Cache.createTimeVector( ...
            ToolBox, obj.Cache.lastFrameIdx);

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

        % AnalyzerClass selects f_RMS or gaussian_w for pulseAnalysis.
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
            MEdisp(ME, "", "WARN", ...
            "Cross-Section Analysis failed");
        end

        if obj.flag_spectral_analysis && ~isempty(obj.SH)
            obj.Analyzer.performSpectralAnalysis(obj);
        end

        diary off;

        if params.json.DebugMode
            profile off
            profile viewer
        end

        fprintf("- Total Analysis took : %ds\n", ...
            round(toc(AnalyzerTimer)));
    end

end

end
