classdef CacheClass < handle
% Cache class used to cache small variables through the execution
% Used for the handle

properties (Transient)

    % Main Results
    vRMS single
    Q_results_A
    Q_results_V

    % Display Cache
    v_video_RGB uint8
    v_mean_RGB uint8

    % Preprocessed Data
    M0_ff single
    f_RMS single
    f_AVG single
    displacementField

end

properties

    % Main Results

    % Display Cache
    M0_ff_img single
    M0_RGB double % cached mean image

    % Time Vector
    t double %cached time vector

    % Frequency Vector
    f double

    % Niquist Value
    fN double

    % Masks
    maskArtery logical % cached mask artery
    maskVein logical % cached mask vein
    maskVessel logical
    maskNeighbors logical % cached mask neighbors
    maskBackground logical % cached mask background
    scoreMaskArtery double % cached score mask artery
    scoreMaskVein double % cached score mask vein
    maskChoroid logical % cached mask choroid

    maskCRA2 logical
    maskCRV2 logical

    % Diastolic and systolic indices
    sysIdxList double % cached systolic indices list
    sysIdx double % cached systolic index
    diasIdx double % cached diastolic index

    % Other cached variables
    papillaDiameter double % cached papilla diameter
    pixelSize double % the size of 1 pixel in mm
    eyeSide string

    % Color maps
    cmapArtery double % cached colormap artery
    cmapVein double % cached colormap vein
    cmapAV double % cached colormap AV

    % Barycenter
    xy_barycenter double % cached xy_barycenter
    xy_CRA double % cached xy_CRA
    xy_CRV double % cached xy_CRV
    xy_papilla double

    % Heartbeat
    HeartBeatFFT double % cached heartbeat frequency in Hz
    HeartBeatFFTSTE double % cached heartbeat frequency standard error in Hz
    harmonics double % cached harmonics frequencies

    % Velocity Artery Vein mean signals
    ArterialVelocity
    VeinVelocity

    % Womersley things
    WomersleyOut cell

end

methods

    function obj = CacheClass()
        obj.createColorMaps();
    end

    function createColorMaps(obj)
        obj.cmapArtery = cmapLAB(256, [0 0 0], 0, [1 0 0], 1/3, [1 1 0], 2/3, [1 1 1], 1);
        obj.cmapVein = cmapLAB(256, [0 0 0], 0, [0 0 1], 1/3, [0 1 1], 2/3, [1 1 1], 1);
        obj.cmapAV = cmapLAB(256, [0 0 0], 0, [1/2 0 1/2], 1/3, [1 0 1], 2/3, [1 1 1], 1);
    end

    function createTimeVector(obj, ToolBox, numFrames)
        time_stamps = ToolBox.record_time_stamps_us;
        params = ToolBox.getParams;
        startFrame = params.json.Preprocess.Crop.StartFrame;
        endFrame = params.json.Preprocess.Crop.EndFrame;

        if ~isempty(time_stamps) ...
                && ~isempty(ToolBox.holo_frames) ...
                && params.json.use_time_stamps
            % if record_time_stamps_us
            % was specified in the HD folder from the .holo footer

            % binsize = 64;
            % (ToolBox.holo_frames.last - ToolBox.holo_frames.first + 1) / ToolBox.stride;
            if time_stamps.last <= time_stamps.first
                disp('Invalid time stamps detected, using default fs and stride');
                time_array = getTimeLinear(ToolBox, numFrames);
            else

                try
                    % Create time vector from time stamps
                    time_array = getTimeTimestamp(time_stamps, numFrames);
                catch
                    % If error occurs, use default fs and stride
                    disp('Could not create time vector from time stamps, using default fs and stride');
                    time_array = getTimeLinear(ToolBox, numFrames);
                end

            end

        else
            % Create time vector from fs and stride
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

        arguments
            obj, ToolBox
        end

        [obj.fN, obj.f] = frequency_array(ToolBox);
    end

end

end

function time_array = getTimeTimestamp(time_stamps, numFrames)
t1 = 0;
t2 = (time_stamps.last - time_stamps.first) / 1e6; % in s
time_array = linspace(t1, t2, numFrames);
end

function time_array = getTimeLinear(ToolBox, numFrames)
t1 = 0;
t2 = ToolBox.stride / (ToolBox.fs * 1000) * (numFrames - 1); % in s
time_array = linspace(t1, t2, numFrames);
end

function [fN, f] = frequency_array(ToolBox)

arguments
    ToolBox
end

fN = ((ToolBox.fs * 1000) / ToolBox.stride) / 2;
f = circshift(fftshift(linspace(-fN, fN, size(ToolBox.Cache.t, 2) + 1)), [0, 1]);
f = f(1, 1:(end - 1));
end
