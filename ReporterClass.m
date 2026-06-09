classdef ReporterClass < handle
% Handles output generation and reporting

properties
    executionObj % store the ExecutionClass object
end

methods

    function obj = ReporterClass(executionObj)
        obj.executionObj = executionObj;
        ToolBox = getGlobalToolBox;

        if isempty(executionObj)
            error("ExecutionClass object is required to initialize ReporterClass.");
        end

        if isempty(ToolBox)
            error("ToolBoxMaster is not initialized in ExecutionClass.");
        end

        output = executionObj.Output;

        if isempty(output)
            error("Output is not initialized in ExecutionClass.");
        end

        if ~isempty(executionObj.M0)
            ToolBox.Output.add('NumFrames', size(executionObj.M0, 3), h5path = '/Meta/NumFrames');
        elseif ~isempty(executionObj.Cache) && isprop(executionObj.Cache, 'M0_ff') && ~isempty(executionObj.Cache.M0_ff)
            ToolBox.Output.add('NumFrames', size(executionObj.Cache.M0_ff, 3), h5path = '/Meta/NumFrames');
        else
            warning('No video frames found – cannot determine NumFrames');
        end

        ToolBox.Output.add('FrameRate', ToolBox.fs * 1000 / ToolBox.stride, 'Hz', h5path = '/Meta/FrameRate');
        ToolBox.Output.add('InterFramePeriod', ToolBox.stride / ToolBox.fs / 1000, 's', h5path = '/Meta/InterFramePeriod');

        if ~isempty(ToolBox.record_time_stamps_us)
            tmp = ToolBox.record_time_stamps_us;
            ToolBox.Output.add('UnixTimestampFirst', tmp.first, 'µs', h5path = '/Meta/UnixTimestampFirst');
            ToolBox.Output.add('UnixTimestampLast', tmp.last, 'µs', h5path = '/Meta/UnixTimestampLast');
        end

    end

    function saveOutputs(obj, ~)
        tic
        fprintf("Saving Outputs...\n");
        ToolBox = getGlobalToolBox;

        if ~isempty(ToolBox.Output)
            ToolBox.Output.writeJson(fullfile(ToolBox.path_json, sprintf("%s_output.json", ToolBox.folder_name)));
            disp("JSON output is done");
            ToolBox.Output.writeHdf5(fullfile(ToolBox.path_h5, sprintf("%s_output.h5", ToolBox.folder_name)));
            disp("H5 output is done");
        else
            DummyOutput = OutputClass();
            DummyOutput.writeJson(fullfile(ToolBox.path_json, sprintf("%s_output.json", ToolBox.folder_name)));
            DummyOutput.writeHdf5(fullfile(ToolBox.path_h5, sprintf("%s_output.h5", ToolBox.folder_name)));
        end

        fprintf("Saving Outputs took %ds\n", round(toc));
    end

    function getA4Report(obj, ME)

        if nargin < 2
            ME = [];
        end

        if ~isempty(ME)
            ToolBox = getGlobalToolBox;
            str = MEdisp(ME, ToolBox.EF_path);
            fid = fopen(fullfile(ToolBox.path_log, sprintf("%s_error_log.txt", ToolBox.folder_name)), 'w');
            fprintf(fid, "%s", str);
            fclose(fid);
        end

        tic
        fprintf("Generating A4 Report...\n");
        ToolBox = getGlobalToolBox;
        params = ToolBox.getParams;

        % Use stored executionObj to access data
        exec = obj.executionObj;

        % Determine which video to use for GIFs
        if exec.is_preprocessed && ~isempty(exec.Cache) && isprop(exec.Cache, 'M0_ff') && ~isempty(exec.Cache.M0_ff)
            videoData = exec.Cache.M0_ff;
        elseif ~isempty(exec.M0)
            videoData = exec.M0;
        else
            warning('No video data available for GIF generation');
            videoData = [];
        end

        if ~isempty(videoData) && params.saveFigures && ~isfile(fullfile(ToolBox.path_gif, sprintf("%s_M0.gif", ToolBox.folder_name)))
            writeGifOnDisc(imresize(rescale(videoData), 0.5), "M0")
        end

        if ~isempty(ToolBox.Output)
            ToolBox.Output.writeJson(fullfile(ToolBox.path_json, sprintf("%s_output.json", ToolBox.folder_name)));
            % ToolBox.Output.writeHdf5(fullfile(ToolBox.path_h5, sprintf("%s_output.h5", ToolBox.folder_name)));
        else
            ToolBox.Output = OutputClass();
        end

        try
            generateA4Report(ME);
        catch ME
            MEdisp(ME, ToolBox.EF_path);
        end

        fprintf("Generating A4 Report took %ds\n", round(toc));
    end

    function displayFinalSummary(~, totalTime)
        tTotal = toc(totalTime);
        fprintf("\n----------------------------------\nTotal EyeFlow timing: %ds\n", round(tTotal));
        fprintf("End Computer Time: %s\n", datetime('now', 'Format', 'yyyy/MM/dd HH:mm:ss'));
        displaySuccessMsg(1);
    end

    function generateReport(obj, executionObj)
        totalTime = tic;
        obj.getA4Report();
        obj.saveOutputs();
        obj.displayFinalSummary(totalTime);
    end

end

end
