classdef PreprocessorClass < handle
% Handles preprocessing operations.
%
% gaussian_w:
%   Input cube loaded from ExecutionClass.
%   Expected layout: X x Y x T, identical to M0.
%   Included in VideoFields for shared preprocessing operations.
%   No moment normalization, square root or unit conversion is applied.
%
% f_RMS:
%   Still computed independently by VideoNormalizingLocally.
%
% Important:
%   Preprocessing helpers must use applyToVideos / VideoFields, or
%   explicitly include gaussian_w in their own field lists.

properties
    is_preprocessed = false

    M0_ff single
    M0 single
    M1 single
    M2 single

    SH single

    HF_M0 single
    LF_M0 single
    bandRatio single

    f_RMS single
    f_AVG single

    gaussian_w single

    directory char
    filenames char
    param_name char

    displacementField

    firstFrameIdx double
    lastFrameIdx double
end

properties (Constant)
    % X x Y x T cubes processed by applyToVideos.
    VideoFields = { ...
                       'M0', ...
                       'M1', ...
                       'M2', ...
                       'M0_ff', ...
                       'f_AVG', ...
                       'f_RMS', ...
                       'HF_M0', ...
                       'LF_M0', ...
                       'bandRatio', ...
                   'gaussian_w'}
end

methods

    function obj = PreprocessorClass(directory, filenames, param_name)
        obj.directory = directory;
        obj.filenames = filenames;
        obj.param_name = param_name;
    end

    function preprocess(obj, executionObj)
        obj.is_preprocessed = false;

        if isempty(executionObj.M0)
            error('PreprocessorClass:MissingM0', ...
            'M0 input data are empty.');
        end

        if any(isnan(executionObj.M0), 'all')
            error('PreprocessorClass:NaNInM0', ...
            'NaN values found in M0 data. Please check the input file.');
        end

        params = Parameters_json(obj.directory, obj.param_name);

        outDir = fullfile(obj.directory, 'eyeflow');

        if ~isfolder(outDir)
            mkdir(outDir);
        end

        obj.loadFrom(executionObj);
        obj.validateGaussianW('input');

        if isempty(obj.gaussian_w)
            fprintf('    - gaussian_w not available: preprocessing moments only.\n');
        else
            fprintf('    - gaussian_w input size: %s\n', ...
                mat2str(size(obj.gaussian_w)));

            obj.reportGaussianWValidity();
        end

        obj.register(params);
        obj.validateGaussianW('registration');

        obj.crop(params);
        obj.validateGaussianW('cropping');

        % Computes f_AVG, f_RMS and M0_ff from the moments.
        % gaussian_w must remain unchanged by this normalization.
        obj.normalizeLocally(params);
        obj.validateGaussianW('local normalization');

        obj.resize(params);
        obj.validateGaussianW('resizing');

        % HF_M0 and LF_M0 have followed register/crop/resize.
        obj.computeBandRatio();

        obj.nonRigidRegister(params);
        obj.validateGaussianW('non-rigid registration');

        obj.interpolate(params);
        obj.validateGaussianW('interpolation');

        obj.removeOutliers(params);
        obj.validateGaussianW('outlier removal');

        if ~isempty(obj.gaussian_w)
            fprintf('    - gaussian_w output size: %s\n', ...
                mat2str(size(obj.gaussian_w)));
        end

        obj.is_preprocessed = true;
    end

    function applyToVideos(obj, fcn, fields)
        % Apply the same operation to each nonempty video cube.
        %
        % Default:
        %   Process every field listed in VideoFields.

        if nargin < 3
            fields = obj.VideoFields;
        end

        for k = 1:numel(fields)
            fieldName = fields{k};

            if ~isempty(obj.(fieldName))
                obj.(fieldName) = fcn(obj.(fieldName));
            end

        end

    end

end

methods (Access = private)

    function loadFrom(obj, src)
        % Input data, including the already fitted Gaussian width.
        inputFields = { ...
                           'M0', ...
                           'M1', ...
                           'M2', ...
                           'SH', ...
                           'HF_M0', ...
                           'LF_M0', ...
                       'gaussian_w'};

        for k = 1:numel(inputFields)
            fieldName = inputFields{k};

            if isprop(src, fieldName)
                obj.(fieldName) = src.(fieldName);
            else
                obj.(fieldName) = [];
            end

        end

        % Derived data must be recomputed on every run.
        derivedFields = { ...
                             'M0_ff', ...
                             'f_AVG', ...
                             'f_RMS', ...
                         'bandRatio'};

        for k = 1:numel(derivedFields)
            obj.(derivedFields{k}) = [];
        end

        obj.displacementField = [];
        obj.firstFrameIdx = [];
        obj.lastFrameIdx = [];
    end

    function validateGaussianW(obj, stage)
        % Missing gaussian_w is allowed for conventional RMS processing.
        if isempty(obj.gaussian_w)
            return
        end

        if ~isreal(obj.gaussian_w)
            error('PreprocessorClass:ComplexGaussianW', ...
                'gaussian_w must be real after %s.', ...
                stage);
        end

        if ndims(obj.gaussian_w) > 3
            error('PreprocessorClass:InvalidGaussianWDimensions', ...
                ['gaussian_w must have layout X x Y x T after %s. ', ...
             'Received size: %s.'], ...
                stage, mat2str(size(obj.gaussian_w)));
        end

        if ~isempty(obj.f_RMS)

            if ~isequal(size(obj.gaussian_w), size(obj.f_RMS))
                error('PreprocessorClass:GaussianWRMSSizeMismatch', ...
                    ['After %s, gaussian_w and f_RMS must have ', ...
                 'identical sizes. gaussian_w: %s; f_RMS: %s.'], ...
                    stage, ...
                    mat2str(size(obj.gaussian_w)), ...
                    mat2str(size(obj.f_RMS)));
            end

        end

        if ~isempty(obj.M0_ff)

            if ~isequal(size(obj.gaussian_w), size(obj.M0_ff))
                error('PreprocessorClass:GaussianWM0FFSizeMismatch', ...
                    ['After %s, gaussian_w and M0_ff must have ', ...
                 'identical sizes. gaussian_w: %s; M0_ff: %s.'], ...
                    stage, ...
                    mat2str(size(obj.gaussian_w)), ...
                    mat2str(size(obj.M0_ff)));
            end

        end

    end

    function reportGaussianWValidity(obj)
        invalidCount = nnz(~isfinite(obj.gaussian_w));

        negativeCount = nnz( ...
            isfinite(obj.gaussian_w) & obj.gaussian_w < 0);

        if invalidCount > 0
            warning('PreprocessorClass:NonFiniteGaussianW', ...
                ['gaussian_w contains %d nonfinite values (NaN or Inf). ', ...
                 'No automatic replacement is applied. ', ...
                 'Handle invalid fits before using this cube for analysis; ', ...
             'interpolation or filtering may propagate these values.'], ...
                invalidCount);
        end

        if negativeCount > 0
            warning('PreprocessorClass:NegativeGaussianW', ...
                ['gaussian_w contains %d finite negative values. ', ...
                 'No clipping or absolute value is applied. ', ...
             'Check fit validity and the width convention.'], ...
                negativeCount);
        end

    end

    function computeBandRatio(obj)

        if isempty(obj.HF_M0) || isempty(obj.LF_M0)
            warning('PreprocessorClass:MissingBandData', ...
            'HF_M0 or LF_M0 missing: band ratio not computed.');
            return
        end

        if ~isequal(size(obj.HF_M0), size(obj.LF_M0))
            error('PreprocessorClass:BandDataSizeMismatch', ...
            'HF_M0 and LF_M0 sizes differ.');
        end

        fprintf("    - Computing band ratio (HoloDoppler convention)\n");

        % Preserve the existing HF/LF convention.
        ratio = obj.HF_M0 ./ obj.LF_M0;

        [nRows, nCols, ~] = size(ratio);

        [X, Y] = meshgrid( ...
            linspace(0, 1, nCols), ...
            linspace(0, 1, nRows));

        disk = 4 .* ((X - 0.5) .^ 2 + (Y - 0.5) .^ 2) <= 1;

        % Spatial offset computed separately for each frame.
        % Mean over all pixels, with zeros inside the disk.
        R0 = mean((~disk) .* ratio, [1 2]);

        obj.bandRatio = ratio - R0;
    end

    function register(obj, params)
        R = params.json.Preprocess.Register;

        if (R.StartFrame == 1 && R.EndFrame == -1) || ~R.Enable
            return
        end

        timer = tic;

        fprintf("    - Video Registering...\n");

        VideoRegistering(obj, R.StartFrame, R.EndFrame);

        fprintf("    - Video Registration took: %.1fs\n", ...
            toc(timer));
    end

    function crop(obj, params)
        C = params.json.Preprocess.Crop;

        obj.firstFrameIdx = 1;
        obj.lastFrameIdx = size(obj.M0, 3);

        if C.StartFrame == 1 && C.EndFrame == -1
            return
        end

        timer = tic;

        fprintf("    - Video Cropping...\n");

        [obj.firstFrameIdx, obj.lastFrameIdx] = ...
            VideoCropping(obj, C.StartFrame, C.EndFrame);

        fprintf("    - Video Cropping took: %.1fs\n", ...
            toc(timer));
    end

    function normalizeLocally(obj, params)
        timer = tic;

        fprintf("    - Local Normalization...\n");

        % Existing helper computes f_RMS from M2 / Mnorm.
        % gaussian_w is already a fitted width and is not normalized here.
        VideoNormalizingLocally(obj, params);

        fprintf("    - Local Normalization took: %.1fs\n", ...
            toc(timer));
    end

    function resize(obj, params)
        timer = tic;

        fprintf("    - Video Resizing...\n");

        VideoResizing(obj, params);

        fprintf("    - Video Resizing took: %.1fs\n", ...
            toc(timer));
    end

    function nonRigidRegister(obj, params)

        if ~params.json.Preprocess.NonRigidRegisteringFlag
            return
        end

        timer = tic;

        fprintf("    - Video Non-Rigid Registration...\n");

        VideoNonRigidRegistering( ...
            obj, params.json.Preprocess.NonRigidRegisteringApply);

        fprintf("    - Video Non-Rigid Registration took: %.1fs\n", ...
            toc(timer));
    end

    function interpolate(obj, params)

        if params.json.Preprocess.InterpolationFactor == 0
            return
        end

        timer = tic;

        fprintf("    - Video Interpolating...\n");

        VideoInterpolating(obj, params);

        fprintf("    - Video Interpolation took: %.1fs\n", ...
            toc(timer));
    end

    function removeOutliers(obj, params)

        if ~params.json.Preprocess.RemoveOutliersFlag
            return
        end

        timer = tic;

        fprintf("    - Video Outlier Removal...\n");

        VideoRemoveOutliers(obj, params);

        fprintf("    - Video Outlier Removal took: %.1fs\n", ...
            toc(timer));
    end

end

end
