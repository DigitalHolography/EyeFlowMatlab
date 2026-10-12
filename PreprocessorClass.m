classdef PreprocessorClass < handle
% Handles all preprocessing operations

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
    directory char
    filenames char
    param_name char
    displacementField
    firstFrameIdx double
    lastFrameIdx double
end

properties (Constant)
    % Cubes 3D (X,Y,T) qui suivent toutes les transformations
    VideoFields = {'M0', 'M1', 'M2', 'M0_ff', 'f_AVG', 'f_RMS', 'HF_M0', 'LF_M0', 'bandRatio'}
end

methods

    function obj = PreprocessorClass(directory, filenames, param_name)
        obj.directory = directory;
        obj.filenames = filenames;
        obj.param_name = param_name;
    end

    function preprocess(obj, executionObj)

        if any(isnan(executionObj.M0), 'all')
            error('NaN values found in M0 data. Please check the input file.');
        end

        params = Parameters_json(obj.directory, obj.param_name);
        outDir = fullfile(obj.directory, 'eyeflow');
        if ~isfolder(outDir), mkdir(outDir); end

        obj.loadFrom(executionObj);

        obj.register(params);
        obj.crop(params);
        obj.normalizeLocally(params);
        obj.resize(params);
        obj.computeBandRatio(); % après resize : HF/LF ont suivi register/crop/resize
        obj.nonRigidRegister(params);
        obj.interpolate(params);
        obj.removeOutliers(params);

        obj.is_preprocessed = true;
    end

    function applyToVideos(obj, fcn, fields)
        % Applique fcn à chaque cube non vide de la liste (défaut : VideoFields)
        if nargin < 3, fields = obj.VideoFields; end

        for k = 1:numel(fields)
            f = fields{k};

            if ~isempty(obj.(f))
                obj.(f) = fcn(obj.(f));
            end

        end

    end

end

methods (Access = private)

    function loadFrom(obj, src)

        for f = {'M0', 'M1', 'M2', 'SH', 'HF_M0', 'LF_M0'}
            if isprop(src, f{1}), obj.(f{1}) = src.(f{1}); else, obj.(f{1}) = []; end
        end

        for f = {'M0_ff', 'f_AVG', 'f_RMS', 'bandRatio'} % remise à zéro si relance
            obj.(f{1}) = [];
        end

    end

    function computeBandRatio(obj)

        if isempty(obj.HF_M0) || isempty(obj.LF_M0)
            warning('HF_M0 or LF_M0 missing: band ratio not computed.');
            return
        end

        if ~isequal(size(obj.HF_M0), size(obj.LF_M0))
            error('HF_M0 and LF_M0 sizes differ.');
        end

        fprintf("    - Computing band ratio (HF_M0 / LF_M0)\n");
        obj.bandRatio = obj.HF_M0 ./ max(obj.LF_M0, eps('single'));
    end

    function register(obj, params)
        R = params.json.Preprocess.Register;

        if (R.StartFrame == 1 && R.EndFrame == -1) || ~R.Enable
            return
        end

        t = tic; fprintf("    - Video Registering...\n");
        VideoRegistering(obj, R.StartFrame, R.EndFrame);
        fprintf("    - Video Registration took: %.1fs\n", toc(t));
    end

    function crop(obj, params)
        C = params.json.Preprocess.Crop;
        obj.firstFrameIdx = 1;
        obj.lastFrameIdx = size(obj.M0, 3);

        if C.StartFrame == 1 && C.EndFrame == -1
            return
        end

        t = tic; fprintf("    - Video Cropping...\n");
        [obj.firstFrameIdx, obj.lastFrameIdx] = VideoCropping(obj, C.StartFrame, C.EndFrame);
        fprintf("    - Video Cropping took: %.1fs\n", toc(t));
    end

    function normalizeLocally(obj, params)
        t = tic; fprintf("    - Local Normalization...\n");
        VideoNormalizingLocally(obj, params);
        fprintf("    - Local Normalization took: %.1fs\n", toc(t));
    end

    function resize(obj, params)
        t = tic; fprintf("    - Video Resizing...\n");
        VideoResizing(obj, params);
        fprintf("    - Video Resizing took: %.1fs\n", toc(t));
    end

    function nonRigidRegister(obj, params)
        if ~params.json.Preprocess.NonRigidRegisteringFlag, return, end
        t = tic; fprintf("    - Video Non-Rigid Registration...\n");
        VideoNonRigidRegistering(obj, params.json.Preprocess.NonRigidRegisteringApply);
        fprintf("    - Video Non-Rigid Registration took: %.1fs\n", toc(t));
    end

    function interpolate(obj, params)
        if params.json.Preprocess.InterpolationFactor == 0, return, end
        t = tic; fprintf("    - Video Interpolating...\n");
        VideoInterpolating(obj, params);
        fprintf("    - Video Interpolation took: %.1fs\n", toc(t));
    end

    function removeOutliers(obj, params)
        if ~params.json.Preprocess.RemoveOutliersFlag, return, end
        t = tic; fprintf("    - Video Outlier Removal...\n");
        VideoRemoveOutliers(obj, params);
        fprintf("    - Video Outlier Removal took: %.1fs\n", toc(t));
    end

end

end
