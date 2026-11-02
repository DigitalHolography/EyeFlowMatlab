classdef CacheClass < handle
% CacheClass
% Shared cache used throughout EyeFlow execution and analysis.
%
% Large data cubes are transient.
%
% f_RMS and gaussian_w are stored independently:
%   f_RMS:
%       Moment-based frequency estimator.
%
%   gaussian_w:
%       Preprocessed Gaussian-width cube.
%       No normalization or unit conversion is performed by this class.
%
% SH_avg:
%   Input spectral cube, stored independently of temporal video data.
%   resizeSHAvg modifies only its spatial dimensions.

properties (Transient)
    % Main results
    vRMS single
    Q_results_A
    Q_results_V

    % Display videos and images
    v_video_RGB uint8
    v_mean_RGB uint8

    % Preprocessed data
    M0_ff single

    f_RMS single
    f_AVG single
    gaussian_w single

    HF_M0 single
    LF_M0 single
    bandRatio single

    displacementField

    % Input spectral data
    SH_avg single
end

properties
    % Display cache
    M0_ff_img single
    bandRatio_img single
    M0_RGB double

    % Time vector
    t double
    firstFrameIdx double
    lastFrameIdx double

    % Frequency vector
    f double

    % Nyquist frequency
    fN double

    % Segmentation masks
    maskArtery logical
    maskVein logical
    maskVessel logical
    maskNeighbors logical
    maskBackground logical
    maskChoroid logical

    % Segmentation scores
    scoreMaskArtery double
    scoreMaskVein double

    % Systolic and diastolic indices
    sysIdxList double
    sysIdx double
    diasIdx double

    % Geometric information
    papillaDiameter double
    pixelSize double
    eyeSide string

    % Color maps
    cmapArtery double
    cmapVein double
    cmapAV double

    % Barycenters and landmarks
    xy_barycenter double
    xy_CRA double
    xy_CRV double
    xy_papilla double

    % Heartbeat information
    HeartBeatFFT double
    HeartBeatFFTSTE double
    harmonics double

    % Mean arterial and venous velocity signals
    ArterialVelocity
    VeinVelocity

    % Womersley analysis
    WomersleyOut cell

    % SH_avg provenance
    SH_avg_sourceFile char = ''
    SH_avg_datasetPath char = ''
    SH_avg_info struct = struct()

    % Spectral analysis regions in the spatial reference of M0_ff
    SH_avg_masks struct = struct()
    SH_avg_colors struct = struct()
    SH_avg_maskDomain logical
end

methods

    function obj = CacheClass()
        obj.createColorMaps();
    end

    function createColorMaps(obj)
        obj.cmapArtery = cmapLAB( ...
            256, ...
            [0 0 0], 0, ...
            [1 0 0], 1/3, ...
            [1 1 0], 2/3, ...
            [1 1 1], 1);

        obj.cmapVein = cmapLAB( ...
            256, ...
            [0 0 0], 0, ...
            [0 0 1], 1/3, ...
            [0 1 1], 2/3, ...
            [1 1 1], 1);

        obj.cmapAV = cmapLAB( ...
            256, ...
            [0 0 0], 0, ...
            [1/2 0 1/2], 1/3, ...
            [1 0 1], 2/3, ...
            [1 1 1], 1);
    end

    function createTimeVector(obj, ToolBox, numFrames)
        % Preserve the existing time-vector construction convention.

        time_stamps = ToolBox.record_time_stamps_us;
        params = ToolBox.getParams;

        startFrame = params.json.Preprocess.Crop.StartFrame;
        endFrame = params.json.Preprocess.Crop.EndFrame;

        if ~isempty(time_stamps) && ...
                ~isempty(ToolBox.holo_frames) && ...
                params.json.use_time_stamps

            if time_stamps.last <= time_stamps.first
                disp(['Invalid time stamps detected, ', ...
                      'using default fs and stride']);

                time_array = getTimeLinear(ToolBox, numFrames);
            else

                try
                    time_array = getTimeTimestamp( ...
                        time_stamps, numFrames);
                catch
                    disp(['Could not create time vector from ', ...
                          'time stamps, using default fs and stride']);

                    time_array = getTimeLinear(ToolBox, numFrames);
                end

            end

        else
            time_array = getTimeLinear(ToolBox, numFrames);
        end

        if startFrame < 1
            startFrame = 1;
        end

        if endFrame > numFrames || endFrame == -1
            endFrame = numFrames;
        end

        obj.t = time_array(startFrame:endFrame);
    end

    function createFreqVector(obj, ToolBox)
        [obj.fN, obj.f] = frequency_array(ToolBox);
    end

    function resizeSHAvg(obj, targetSize)
        % Resize only the two spatial dimensions of SH_avg.
        % Preserve the spectral dimension.
        %
        % Assumes that SH_avg and the target image cover the same
        % field of view with identical orientation and spatial reference.
        %
        % This operation does not perform registration.

        if isempty(obj.SH_avg)
            return
        end

        validateattributes(targetSize, {'numeric'}, ...
            {'vector', 'numel', 2, 'integer', 'positive', 'finite'}, ...
            'CacheClass.resizeSHAvg', 'targetSize');

        targetSize = double(targetSize(:).');

        sourceSize = [ ...
                          size(obj.SH_avg, 1), ...
                          size(obj.SH_avg, 2)];

        if isequal(sourceSize, targetSize)
            fprintf( ...
                '    - SH_avg already at target spatial size: %s\n', ...
                mat2str(targetSize));
            return
        end

        numFreq = size(obj.SH_avg, 3);

        fprintf( ...
            '    - Resizing SH_avg: %s -> %s, %d frequency bins\n', ...
            mat2str(sourceSize), ...
            mat2str(targetSize), ...
            numFreq);

        resized = zeros( ...
            targetSize(1), targetSize(2), numFreq, ...
            'like', obj.SH_avg);

        for k = 1:numFreq
            resized(:, :, k) = imresize( ...
                obj.SH_avg(:, :, k), ...
                targetSize, ...
                'bilinear', ...
                'Antialiasing', true);
        end

        obj.SH_avg = resized;
    end

end

end

function time_array = getTimeTimestamp(time_stamps, numFrames)
% Time vector in seconds from acquisition timestamps.

t1 = 0;
t2 = (time_stamps.last - time_stamps.first) / 1e6;

time_array = linspace(t1, t2, numFrames);

end

function time_array = getTimeLinear(ToolBox, numFrames)
% Time vector in seconds from stride and sampling frequency.
% ToolBox.fs follows the existing kHz convention.

t1 = 0;
t2 = ToolBox.stride / (ToolBox.fs * 1000) * (numFrames - 1);

time_array = linspace(t1, t2, numFrames);

end

function [fN, f] = frequency_array(ToolBox)
% Preserve the existing temporal frequency-vector convention.

fN = ((ToolBox.fs * 1000) / ToolBox.stride) / 2;

f = circshift( ...
    fftshift( ...
    linspace(-fN, fN, size(ToolBox.Cache.t, 2) + 1)), ...
    [0, 1]);

f = f(1, 1:(end - 1));

end
