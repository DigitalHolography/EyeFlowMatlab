classdef eyeflow < matlab.apps.AppBase

% Properties that correspond to app components – now PRIVATE
properties (Access = private)
    EyeFlowUIFigure matlab.ui.Figure
    RootGrid matlab.ui.container.GridLayout

    ReferenceDirectory matlab.ui.control.TextArea
    statusLamp matlab.ui.control.Lamp

    % Top Buttons
    LoadFolderButton matlab.ui.control.Button
    LoadHoloButton matlab.ui.control.Button
    ClearButton matlab.ui.control.Button
    FolderManagementButton matlab.ui.control.Button

    % Third Row Buttons
    EditMasksButton matlab.ui.control.Button
    EditParametersButton matlab.ui.control.Button
    PlayMomentsButton matlab.ui.control.Button

    % Fourth Row Buttons
    OpenDirectoryButton matlab.ui.control.Button
    ReProcessButton matlab.ui.control.Button

    % Checkboxes
    segmentationCheckBox matlab.ui.control.CheckBox
    bloodFlowAnalysisCheckBox matlab.ui.control.CheckBox
    pulseVelocityCheckBox matlab.ui.control.CheckBox
    generateCrossSectionSignalsCheckBox matlab.ui.control.CheckBox
    exportCrossSectionResultsCheckBox matlab.ui.control.CheckBox
    spectralAnalysisCheckBox matlab.ui.control.CheckBox

    % Execute
    NumberofWorkersSpinner matlab.ui.control.Spinner
    NumberofWorkersSpinnerLabel matlab.ui.control.Label
    ExecuteButton matlab.ui.control.Button
    ImageDisplay matlab.ui.control.Image
end

% Public data (kept as originally)
properties (Access = public)
    file ExecutionClass
    AINetworks
    drawer_list = {}
end

methods (Access = public)

    % Set the ImageDisplay image source with the same pre‑processing as Load()
    function setDisplayImage(app, imageMatrix)

        if ndims(imageMatrix) == 3
            grayImg = mean(imageMatrix, 3);
        else
            grayImg = imageMatrix;
        end

        rgbImg = repmat(rescale(grayImg), [1 1 3]);
        [numX, numY] = size(rgbImg);
        app.ImageDisplay.ImageSource = imresize(rgbImg, [max(numX, numY) max(numX, numY)]);
    end

    function fig = getMainFigure(app)
        fig = app.EyeFlowUIFigure;
    end

    function value = getWidgetValue(app, widgetName)
        w = app.(widgetName);

        if isempty(w)
            value = [];
        elseif isa(w, 'matlab.ui.control.CheckBox')
            value = logical(w.Value);
        elseif isa(w, 'matlab.ui.control.DropDown')
            value = w.Value;
        elseif isa(w, 'matlab.ui.control.ListBox')
            value = w.Value;
        elseif isa(w, 'matlab.ui.control.NumericEditField') || isa(w, 'matlab.ui.control.Spinner')
            value = double(w.Value);
        else
            value = w.Value;
        end

    end

    function setWidgetValue(app, widgetName, value)
        w = app.(widgetName);
        if isempty(w), return; end

        if isa(w, 'matlab.ui.control.CheckBox')
            w.Value = logical(value);
        elseif isa(w, 'matlab.ui.control.DropDown')

            if ismember(value, w.Items)
                w.Value = value;
            else
                w.Value = w.Items{1};
            end

        elseif isa(w, 'matlab.ui.control.ListBox')
            allItems = w.Items;

            if iscell(value)
                w.Value = intersect(value, allItems, 'stable');
            else
                w.Value = {};
            end

        elseif isa(w, 'matlab.ui.control.NumericEditField') || isa(w, 'matlab.ui.control.Spinner')
            w.Value = double(value(1));
        else
            w.Value = value;
        end

    end

    function setImageSource(app, rgbImage)
        % Directly set the ImageDisplay image source (no rescaling)
        app.ImageDisplay.ImageSource = rgbImage;
    end

    function setAxisEqual(app)
        % Make the axes holding the image have equal scaling
        ax = ancestor(app.ImageDisplay, 'axes');
        if ~isempty(ax)
            axis(ax, 'equal');
        end
    end

    % ---------------------------------------------------------------------
    % Corrected Load method – no trailing backslash, proper path cleaning
    % ---------------------------------------------------------------------
    function Load(app, path)
        app.statusLamp.Color = [1, 1/2, 0]; % Orange
        drawnow;

        % Normalise path: remove trailing slash/backslash
        path = strrep(path, '/', filesep);
        path = strrep(path, '\', filesep);

        if endsWith(path, filesep)
            path = path(1:end - 1);
        end

        totalLoadingTime = tic;

        try
            rawDataPath = app.resolveDataFolder(path);
            app.file = ExecutionClass(rawDataPath, path);
            app.file.AINetworks = app.AINetworks;

            mean_M0 = mean(app.file.M0, 3);
            img = repmat(rescale(mean_M0), [1 1 3]);
            [numX, numY] = size(img);
            app.ImageDisplay.ImageSource = imresize(img, [max(numX, numY) max(numX, numY)]);

            % Enable buttons
            app.ExecuteButton.Enable = true;
            app.ClearButton.Enable = true;
            app.EditParametersButton.Enable = true;
            app.EditMasksButton.Enable = true;
            app.PlayMomentsButton.Enable = true;
            app.OpenDirectoryButton.Enable = true;
            app.ReProcessButton.Enable = true;
            app.ReferenceDirectory.Value = path;

            app.statusLamp.Color = [0, 1, 0]; % Green
        catch ME
            MEdisp(ME, path);
            diary off
            app.statusLamp.Color = [1, 0, 0]; % Red
        end

        app.CheckboxValueChanged();
        fprintf("----------------------------------\n");
        fprintf("- Total Load timing took : %ds\n", round(toc(totalLoadingTime)));
    end

end

% Callbacks that handle component events
methods (Access = public)

    function startupFcn(app)
        delete(gcp('nocreate'))

        if exist("version.txt", 'file')
            v = readlines('version.txt');
            fprintf("==================================\n " + ...
                "Welcome to EyeFlow %s\n" + ...
                "----------------------------------\n" + ...
                "Developed by the DigitalHolographyFoundation\n" + ...
                "==================================\n", v(1));
        end

        addpath("BloodFlowVelocity\", "BloodFlowVelocity\Elastography\", "CrossSection\", ...
            "Loading\", "Parameters\", "Preprocessing\", "Outputs\", ...
            "Scripts\", "Segmentation\", "SHAnalysis\", "Tools\");
        app.EyeFlowUIFigure.Name = ['EyeFlow ', char(v(1))];
        displaySplashScreen();
        app.CheckboxValueChanged();
        set(groot, 'defaultFigureColor', 'w');
        set(groot, 'defaultAxesFontSize', 14);
        set(groot, 'DefaultTextFontSize', 10);
        app.AINetworks = AINetworksClass();
    end

    function LoadFromTxt(app)
        [selected_file, path] = uigetfile('*.txt');

        if selected_file
            files_lines = readlines(fullfile(path, selected_file));

            for nn = 1:length(files_lines)

                if ~isempty(files_lines(nn))
                    app.drawer_list{end + 1} = files_lines(nn);
                end

            end

        end

    end

    function LoadfolderButtonPushed(app, ~)

        if ~isempty(app.file)
            last_dir = app.file.directory;
        else
            last_dir = [];
        end

        selected_dir = uigetdir(last_dir);

        if selected_dir == 0
            fprintf(2, 'No folder selected\n');
            return
        else
            ClearButtonPushed(app);
            app.Load(selected_dir);
        end

    end

    function LoadHoloButtonPushed(app, ~)
        [selected_holo, path_holo] = uigetfile('*.holo');

        if selected_holo == 0
            fprintf(2, 'No file selected\n');
        else
            ClearButtonPushed(app);
            app.Load(fullfile(path_holo, selected_holo));
        end

    end

    function err = ExecuteButtonPushed(app, ~)
        err = [];

        if isempty(app.file)
            fprintf(2, "No input loaded.\n")
            return
        end

        app.statusLamp.Color = [1, 1/2, 0];
        drawnow;
        fprintf("\n==================================\n");
        fclose all;

        app.file.params_names = checkEyeFlowParamsFromJson(app.file.directory);
        params = Parameters_json(app.file.directory, app.file.params_names{1});

        if params.json.NumberOfWorkers > 0 && params.json.NumberOfWorkers < app.NumberofWorkersSpinner.Limits(2)
            app.NumberofWorkersSpinner.Value = params.json.NumberOfWorkers;
        end

        for i = 1:length(app.file.params_names)
            app.file.param_name = app.file.params_names{i};
            totalTime = tic;
            fprintf("\n==================================\n")
            app.file.flag_segmentation = app.segmentationCheckBox.Value;
            app.file.flag_bloodFlowVelocity_analysis = app.bloodFlowAnalysisCheckBox.Value;
            app.file.flag_pulseWaveVelocity = app.pulseVelocityCheckBox.Value;
            app.file.flag_crossSection_analysis = app.generateCrossSectionSignalsCheckBox.Value;
            app.file.flag_crossSection_export = app.exportCrossSectionResultsCheckBox.Value;
            app.file.flag_spectral_analysis = app.spectralAnalysisCheckBox.Value;
            err = [];

            try
                app.file.ToolBoxMaster = ToolBoxClass(app.file.directory, app.file.param_name);

                if ~app.file.is_preprocessed
                    parfor_arg = app.NumberofWorkersSpinner.Value;
                    setupParpool(parfor_arg);
                    app.file.preprocessData();
                end

                app.file.analyzeData(app);
                app.statusLamp.Color = [0, 1, 0];
            catch ME
                err = ME;
                MEdisp(ME, app.file.directory);
                app.statusLamp.Color = [1, 0, 0];
                diary off
            end

            ReporterTimer = tic;
            fprintf("\n----------------------------------\nGenerating Reports\n----------------------------------\n");
            app.file.Reporter.getA4Report(err);
            app.file.Reporter.saveOutputs();
            fprintf("- Reporting took : %ds\n", round(toc(ReporterTimer)))
            app.file.Reporter.displayFinalSummary(totalTime);
        end

        app.CheckboxValueChanged();
    end

    function PlayMomentsButtonPushed(app, ~)

        try

            if app.file.is_preprocessed
                disp('inputs after preprocess.')
            else
                disp('inputs before preprocess.')
            end

            implay(rescale(app.file.M0));
            implay(rescale(app.file.M1));
            implay(rescale(app.file.M2));
        catch
            disp('Input not well loaded')
        end

    end

    function ClearButtonPushed(app, ~)

        if ~isempty(app.file)
            clear app.file;
        end

        close all;
        app.ReferenceDirectory.Value = "";
        app.ExecuteButton.Enable = false;
        app.ClearButton.Enable = false;
        app.EditParametersButton.Enable = false;
        app.OpenDirectoryButton.Enable = false;
        app.ReProcessButton.Enable = false;
        app.EditMasksButton.Enable = false;
        app.PlayMomentsButton.Enable = false;
        app.CheckboxValueChanged();
    end

    function OpenDirectoryButtonPushed(app, ~)

        try
            winopen(fullfile(app.file.directory, 'eyeflow'));
        catch
            fprintf(2, "No valid directory loaded.\n");
        end

    end

    % ---------------------------------------------------------------------
    % Corrected ReProcessButtonPushed – passes both data and original folder
    % ---------------------------------------------------------------------
    function ReProcessButtonPushed(app, ~)
        app.statusLamp.Color = [1, 1/2, 0];
        drawnow;

        try
            parfor_arg = app.NumberofWorkersSpinner.Value;
            setupParpool(parfor_arg);
            % Use stored original and data paths
            dataPath = app.file.directory;
            originalPath = app.file.originalParentPath;
            app.file = ExecutionClass(dataPath, originalPath);
            app.file.AINetworks = app.AINetworks;
            app.file.preprocessData();
            app.statusLamp.Color = [0, 1, 0];
            drawnow;
        catch ME
            MEdisp(ME, app.file.directory);
            app.statusLamp.Color = [1, 0, 0];
            drawnow;
            diary off
        end

    end

    function FolderManagementButtonPushed(app, ~)
        persistent fmUI

        if isempty(fmUI) || ~isvalid(fmUI)
            fmUI = FolderManagementUI(app);
        else
            fmUI.bringToFront();
        end

    end

    function EditParametersButtonPushed(app, ~)

        try
            main_path = fullfile(app.file.directory, 'eyeflow');

            if isfile(fullfile(main_path, 'json', app.file.param_name))
                disp(['opening : ', fullfile(main_path, 'json', app.file.param_name)])
                winopen(fullfile(main_path, 'json', app.file.param_name));
            else
                disp(['couldn''t open : ', fullfile(main_path, 'json', app.file.param_name)])
            end

        catch
            fprintf(2, "no input loaded\n")
        end

    end

    function EditMasksButtonPushed(app, ~)
        ToolBox = getGlobalToolBox;

        if isempty(ToolBox) || ~strcmp(app.file.directory, ToolBox.EF_path)
            ToolBox = ToolBoxClass(app.file.directory, app.file.param_name);
        end

        if ~isempty(app.file)

            if ~isfolder(fullfile(ToolBox.EF_path, 'mask'))
                mkdir(fullfile(ToolBox.EF_path, 'mask'))
            end

            try
                winopen(fullfile(ToolBox.EF_path, 'mask'));
            catch
                disp("opening failed.")
            end

            if ~app.file.is_preprocessed
                parfor_arg = app.NumberofWorkersSpinner.Value;
                setupParpool(parfor_arg);
                app.file = app.file.preprocessData();
            end

            try
                list_dir = dir(ToolBox.EF_path);

                for i = 1:length(list_dir)

                    if contains(list_dir(i).name, ToolBox.folder_name)
                        match = regexp(list_dir(i).name, '\d+$', 'match');

                        if ~isempty(match) && str2double(match{1}) >= idx
                            idx = str2double(match{1});
                        end

                    end

                end

                path_dir = fullfile(ToolBox.EF_path, ToolBox.folder_name);
                disp(['Copying from : ', fullfile(path_dir, 'png', 'mask')])
                copyfile(fullfile(path_dir, 'png', 'mask', sprintf("%s_maskArtery.png", ToolBox.folder_name)), fullfile(ToolBox.EF_path, 'mask', 'MaskArtery.png'));
                copyfile(fullfile(path_dir, 'png', 'mask', sprintf("%s_maskVein.png", ToolBox.folder_name)), fullfile(ToolBox.EF_path, 'mask', 'MaskVein.png'));
            catch
                disp("last auto mask copying failed.")
            end

            try
                copyfile(fullfile(ToolBox.EF_path, 'png', sprintf("%s_M0.png", ToolBox.folder_name)), fullfile(ToolBox.EF_path, 'mask', 'M0.png'));
                folder_name = ToolBox.folder_name;
                list_dir = dir(ToolBox.EF_path);
                idx = 0;

                for i = 1:length(list_dir)

                    if contains(list_dir(i).name, folder_name)
                        match = regexp(list_dir(i).name, '\d+$', 'match');

                        if ~isempty(match) && str2double(match{1}) >= idx
                            idx = str2double(match{1});
                        end

                    end

                end

                folder_name = sprintf('%s_%d', ToolBox.folder_name, idx);
                copyfile(fullfile(ToolBox.EF_path, folder_name, 'gif', sprintf("%s_M0.gif", folder_name)), fullfile(ToolBox.EF_path, 'mask', 'M0.gif'));
            catch
                disp("last M0 png and gif copying failed")
            end

            try
                copyfile(fullfile(ToolBox.EF_path, 'png', sprintf("%s_M0.png", ToolBox.folder_name)), fullfile(ToolBox.EF_path, 'mask', 'M0.png'));
                folder_name = ToolBox.folder_name;
                list_dir = dir(ToolBox.EF_path);
                idx = 0;

                for i = 1:length(list_dir)

                    if contains(list_dir(i).name, folder_name)
                        match = regexp(list_dir(i).name, '\d+$', 'match');

                        if ~isempty(match) && str2double(match{1}) >= idx
                            idx = str2double(match{1});
                        end

                    end

                end

                folder_name = sprintf('%s_%d', ToolBox.folder_name, idx);
                copyfile(fullfile(ToolBox.EF_path, folder_name, 'png', 'mask', sprintf("%s_DiaSysRGB.png", folder_name)), fullfile(ToolBox.EF_path, 'mask', 'DiaSysRGB.png'));
            catch
                disp("Diasys png failed")
            end

        else
            fprintf(2, "no input loaded\n")
        end

    end

    function CheckboxValueChanged(app, ~)
        app.segmentationCheckBox.Enable = true;
        is_segmented = false;
        is_velocityAnalyzed = false;
        is_volumeRateAnalyzed = false;

        if ~isempty(app.file)
            is_segmented = app.file.is_segmented;
            is_velocityAnalyzed = app.file.is_velocityAnalyzed;
            is_volumeRateAnalyzed = app.file.is_volumeRateAnalyzed;
        end

        if app.segmentationCheckBox.Value || is_segmented
            app.bloodFlowAnalysisCheckBox.Enable = true;
            app.spectralAnalysisCheckBox.Enable = true;
        else
            app.bloodFlowAnalysisCheckBox.Enable = false;
            app.spectralAnalysisCheckBox.Enable = false;
            app.bloodFlowAnalysisCheckBox.Value = false;
            app.spectralAnalysisCheckBox.Value = false;
        end

        if app.bloodFlowAnalysisCheckBox.Value || is_velocityAnalyzed
            app.generateCrossSectionSignalsCheckBox.Enable = true;
            app.pulseVelocityCheckBox.Enable = true;
        else
            app.pulseVelocityCheckBox.Enable = false;
            app.generateCrossSectionSignalsCheckBox.Enable = false;
            app.pulseVelocityCheckBox.Value = false;
            app.generateCrossSectionSignalsCheckBox.Value = false;
        end

        if app.generateCrossSectionSignalsCheckBox.Value || is_volumeRateAnalyzed
            app.exportCrossSectionResultsCheckBox.Enable = true;
        else
            app.exportCrossSectionResultsCheckBox.Enable = false;
            app.exportCrossSectionResultsCheckBox.Value = false;
        end

    end

end

methods (Access = private)

    function dataFolder = resolveDataFolder(app, selectedPath)

        if app.containsRawData(selectedPath)
            dataFolder = selectedPath;
            return;
        end

        hdDirs = dir(fullfile(selectedPath, '*_HD'));
        hdDirs = hdDirs([hdDirs.isdir]);

        for i = 1:length(hdDirs)
            candidate = fullfile(selectedPath, hdDirs(i).name);

            if app.containsRawData(candidate)
                dataFolder = candidate;
                return;
            end

        end

        dataFolder = selectedPath;
    end

    function hasData = containsRawData(~, folder)
        rawSub = fullfile(folder, 'raw');

        if isfolder(rawSub)
            h5 = dir(fullfile(rawSub, '*.h5'));
            raw = dir(fullfile(rawSub, '*.raw'));

            if ~isempty(h5) || ~isempty(raw)
                hasData = true;
                return;
            end

        end

        h5 = dir(fullfile(folder, '*.h5'));
        raw = dir(fullfile(folder, '*.raw'));
        hasData = ~isempty(h5) || ~isempty(raw);
    end

end

% =========================================================================
% Component initialisation
% =========================================================================
methods (Access = private)

    function createComponents(app)
        pathToMLAPP = fileparts(mfilename('fullpath'));
        app.createFigure(pathToMLAPP);
        app.createRootGrid();
        app.createFileSelectionPanel();
        app.createProcessingOptionsPanel();
        app.createExecutionToolsPanel();
        app.createImageDisplay();
        fontname(app.EyeFlowUIFigure, 'Arial');
        fontsize(app.EyeFlowUIFigure, 12, "points");
        app.EyeFlowUIFigure.Visible = 'on';
    end

    function createFigure(app, pathToMLAPP)
        screenSize = get(0, 'ScreenSize');
        appWidth = 1050;
        appHeight = 500;
        appX = (screenSize(3) - appWidth) / 2;
        appY = (screenSize(4) - appHeight) / 2;
        app.EyeFlowUIFigure = uifigure('Visible', 'off', ...
            'Position', [appX, appY, appWidth, appHeight], ...
            'Color', [0.2 0.2 0.2], ...
            'Name', 'EyeFlow', ...
            'Icon', fullfile(pathToMLAPP, 'eyeflow_logo.png'), ...
            'WindowStyle', 'normal');
    end

    function createRootGrid(app)
        app.RootGrid = uigridlayout(app.EyeFlowUIFigure, [3, 2], ...
            'ColumnWidth', {'fit', '1x'}, ...
            'RowHeight', {'1x', 'fit', 'fit'}, ...
            'Padding', [10 10 10 10], ...
            'RowSpacing', 10, ...
            'ColumnSpacing', 10, ...
            'BackgroundColor', [0.2 0.2 0.2]);
    end

    function createFileSelectionPanel(app)
        import matlab.ui.container.Panel
        import matlab.ui.container.GridLayout
        import matlab.ui.control.*

        backgroundColor = [0.2 0.2 0.2];
        darkBackgroundColor = [0.15 0.15 0.15];
        fontColor = [1 1 1];
        grayButtonColor = [0.5 0.5 0.5];

        panel = uipanel(app.RootGrid, ...
            'Title', 'File Selection', ...
            'BackgroundColor', backgroundColor, ...
            'ForegroundColor', fontColor, ...
            'BorderType', 'line', ...
            'FontWeight', 'bold');
        panel.Layout.Row = 1;
        panel.Layout.Column = 1;

        grid = uigridlayout(panel, [3, 4], ...
            'ColumnWidth', {'fit', 'fit', 'fit', 'fit'}, ...
            'RowHeight', {'fit', '1x', 'fit'}, ...
            'Padding', [10 10 10 10], ...
            'RowSpacing', 5, ...
            'ColumnSpacing', 5, ...
            'BackgroundColor', backgroundColor);

        app.LoadFolderButton = uibutton(grid, 'push', ...
            'Text', 'Load Folder', ...
            'BackgroundColor', [0.5 0.5 0.5], ...
            'FontColor', [1 1 1], ...
            'ButtonPushedFcn', @(~, ~) app.LoadfolderButtonPushed());
        app.LoadFolderButton.Layout.Row = 1;
        app.LoadFolderButton.Layout.Column = 1;

        app.LoadHoloButton = uibutton(grid, 'push', ...
            'Text', 'Load Holo', ...
            'BackgroundColor', grayButtonColor, ...
            'FontColor', [1 1 1], ...
            'ButtonPushedFcn', @(~, ~) app.LoadHoloButtonPushed());
        app.LoadHoloButton.Layout.Row = 1;
        app.LoadHoloButton.Layout.Column = 2;

        app.ClearButton = uibutton(grid, 'push', ...
            'Text', 'Clear', ...
            'BackgroundColor', grayButtonColor, ...
            'FontColor', [1 1 1], ...
            'Enable', 'off', ...
            'ButtonPushedFcn', @(~, ~) app.ClearButtonPushed());
        app.ClearButton.Layout.Row = 1;
        app.ClearButton.Layout.Column = 3;

        app.FolderManagementButton = uibutton(grid, 'push', ...
            'Text', 'Folder Management', ...
            'BackgroundColor', grayButtonColor, ...
            'FontColor', [1 1 1], ...
            'ButtonPushedFcn', @(~, ~) app.FolderManagementButtonPushed());
        app.FolderManagementButton.Layout.Row = 1;
        app.FolderManagementButton.Layout.Column = 4;

        app.ReferenceDirectory = uitextarea(grid, ...
            'Value', '', ...
            'Editable', 'off', ...
            'BackgroundColor', darkBackgroundColor, ...
            'FontColor', [1 1 1]);
        app.ReferenceDirectory.Layout.Row = 2;
        app.ReferenceDirectory.Layout.Column = [1 4];

        app.EditParametersButton = uibutton(grid, 'push', ...
            'Text', 'Edit Parameters', ...
            'BackgroundColor', grayButtonColor, ...
            'FontColor', [1 1 1], ...
            'Enable', 'off', ...
            'Tooltip', 'Open the JSON parameter file', ...
            'ButtonPushedFcn', @(~, ~) app.EditParametersButtonPushed());
        app.EditParametersButton.Layout.Row = 3;
        app.EditParametersButton.Layout.Column = 1;

        app.EditMasksButton = uibutton(grid, 'push', ...
            'Text', 'Edit Masks', ...
            'BackgroundColor', grayButtonColor, ...
            'FontColor', [1 1 1], ...
            'Enable', 'off', ...
            'Tooltip', 'Open mask folder for manual editing', ...
            'ButtonPushedFcn', @(~, ~) app.EditMasksButtonPushed());
        app.EditMasksButton.Layout.Row = 3;
        app.EditMasksButton.Layout.Column = 2;

        app.PlayMomentsButton = uibutton(grid, 'push', ...
            'Text', 'Play Moments', ...
            'BackgroundColor', grayButtonColor, ...
            'FontColor', [1 1 1], ...
            'Enable', 'off', ...
            'Tooltip', 'Play M0/M1/M2 videos', ...
            'ButtonPushedFcn', @(~, ~) app.PlayMomentsButtonPushed());
        app.PlayMomentsButton.Layout.Row = 3;
        app.PlayMomentsButton.Layout.Column = 3;
    end

    function createProcessingOptionsPanel(app)
        panel = uipanel(app.RootGrid, ...
            'Title', 'Processing Options', ...
            'BackgroundColor', [0.2 0.2 0.2], ...
            'ForegroundColor', [1 1 1], ...
            'BorderType', 'line', ...
            'FontWeight', 'bold');
        panel.Layout.Row = 2;
        panel.Layout.Column = 1;

        grid = uigridlayout(panel, [6, 2], ...
            'ColumnWidth', {'1x', '1x'}, ...
            'RowHeight', repmat({'fit'}, 1, 6), ...
            'Padding', [10 10 10 10], ...
            'RowSpacing', 8, ...
            'BackgroundColor', [0.2 0.2 0.2]);

        app.segmentationCheckBox = uicheckbox(grid, ...
            'Text', 'Segmentation', ...
            'Value', true, ...
            'FontColor', [1 1 1], ...
            'Tooltip', 'Segment vessels using U-Net', ...
            'ValueChangedFcn', @(~, ~) app.CheckboxValueChanged());
        app.segmentationCheckBox.Layout.Row = 1;
        app.segmentationCheckBox.Layout.Column = [1 2];

        app.bloodFlowAnalysisCheckBox = uicheckbox(grid, ...
            'Text', 'Blood Flow Analysis', ...
            'Value', true, ...
            'FontColor', [1 1 1], ...
            'Tooltip', 'Compute blood flow velocity', ...
            'ValueChangedFcn', @(~, ~) app.CheckboxValueChanged());
        app.bloodFlowAnalysisCheckBox.Layout.Row = 2;
        app.bloodFlowAnalysisCheckBox.Layout.Column = 1;

        app.pulseVelocityCheckBox = uicheckbox(grid, ...
            'Text', 'Pulse Analysis', ...
            'Value', false, ...
            'FontColor', [1 1 1], ...
            'Tooltip', 'Flexural pulse wave velocity', ...
            'ValueChangedFcn', @(~, ~) app.CheckboxValueChanged());
        app.pulseVelocityCheckBox.Layout.Row = 2;
        app.pulseVelocityCheckBox.Layout.Column = 2;

        app.generateCrossSectionSignalsCheckBox = uicheckbox(grid, ...
            'Text', 'Generate Cross Section Signals', ...
            'Value', false, ...
            'FontColor', [1 1 1], ...
            'Tooltip', 'Blood flow profiles across vessels', ...
            'ValueChangedFcn', @(~, ~) app.CheckboxValueChanged());
        app.generateCrossSectionSignalsCheckBox.Layout.Row = 3;
        app.generateCrossSectionSignalsCheckBox.Layout.Column = 1;

        app.exportCrossSectionResultsCheckBox = uicheckbox(grid, ...
            'Text', 'Export Cross Section Results', ...
            'Value', false, ...
            'FontColor', [1 1 1], ...
            'Tooltip', 'Export cross-section analysis', ...
            'ValueChangedFcn', @(~, ~) app.CheckboxValueChanged());
        app.exportCrossSectionResultsCheckBox.Layout.Row = 3;
        app.exportCrossSectionResultsCheckBox.Layout.Column = 2;

        app.spectralAnalysisCheckBox = uicheckbox(grid, ...
            'Text', 'Spectral Analysis', ...
            'Value', false, ...
            'FontColor', [1 1 1], ...
            'Tooltip', 'Spectral analysis of blood flow', ...
            'ValueChangedFcn', @(~, ~) app.CheckboxValueChanged());
        app.spectralAnalysisCheckBox.Layout.Row = 4;
        app.spectralAnalysisCheckBox.Layout.Column = [1 2];

    end

    function createExecutionToolsPanel(app)
        panel = uipanel(app.RootGrid, ...
            'Title', 'Execution & Tools', ...
            'BackgroundColor', [0.2 0.2 0.2], ...
            'ForegroundColor', [1 1 1], ...
            'BorderType', 'line', ...
            'FontWeight', 'bold');
        panel.Layout.Row = 3;
        panel.Layout.Column = 1;

        grid = uigridlayout(panel, [2, 4], ...
            'ColumnWidth', {'1x', 'fit', 'fit', 'fit'}, ...
            'RowHeight', {'fit', 'fit'}, ...
            'Padding', [10 10 10 10], ...
            'RowSpacing', 8, ...
            'ColumnSpacing', 8, ...
            'BackgroundColor', [0.2 0.2 0.2]);

        app.ExecuteButton = uibutton(grid, 'push', ...
            'Text', 'Execute', ...
            'BackgroundColor', [0.2 0.6 0.2], ...
            'FontColor', [1 1 1], ...
            'Enable', 'off', ...
            'ButtonPushedFcn', @(~, ~) app.ExecuteButtonPushed());
        app.ExecuteButton.Layout.Row = 1;
        app.ExecuteButton.Layout.Column = 1;

        app.OpenDirectoryButton = uibutton(grid, 'push', ...
            'Text', 'Open Directory', ...
            'BackgroundColor', [0.5 0.5 0.5], ...
            'FontColor', [1 1 1], ...
            'Enable', 'off', ...
            'ButtonPushedFcn', @(~, ~) app.OpenDirectoryButtonPushed());
        app.OpenDirectoryButton.Layout.Row = 1;
        app.OpenDirectoryButton.Layout.Column = 2;

        app.ReProcessButton = uibutton(grid, 'push', ...
            'Text', 'Preprocess', ...
            'BackgroundColor', [0.5 0.5 0.5], ...
            'FontColor', [1 1 1], ...
            'Enable', 'off', ...
            'ButtonPushedFcn', @(~, ~) app.ReProcessButtonPushed());
        app.ReProcessButton.Layout.Row = 1;
        app.ReProcessButton.Layout.Column = 3;

        app.NumberofWorkersSpinnerLabel = uilabel(grid, ...
            'Text', 'Workers:', ...
            'HorizontalAlignment', 'right', ...
            'FontColor', [1 1 1]);
        app.NumberofWorkersSpinnerLabel.Layout.Row = 1;
        app.NumberofWorkersSpinnerLabel.Layout.Column = 4;

        app.NumberofWorkersSpinner = uispinner(grid, ...
            'Limits', [0 parcluster('local').NumWorkers], ...
            'Value', min(10, floor(parcluster('local').NumWorkers / 2)), ...
            'BackgroundColor', [0.15 0.15 0.15], ...
            'FontColor', [1 1 1]);
        app.NumberofWorkersSpinner.Layout.Row = 2;
        app.NumberofWorkersSpinner.Layout.Column = 4;

        app.statusLamp = uilamp(grid, 'Color', [0 1 0]);
        app.statusLamp.Layout.Row = 2;
        app.statusLamp.Layout.Column = 1;
    end

    function createImageDisplay(app)
        app.ImageDisplay = uiimage(app.RootGrid);
        app.ImageDisplay.Layout.Row = [1 3];
        app.ImageDisplay.Layout.Column = 2;
        app.ImageDisplay.ScaleMethod = 'fit';
        app.ImageDisplay.BackgroundColor = [0.15 0.15 0.15];
    end

end

methods (Access = public)

    function app = eyeflow
        createComponents(app)
        registerApp(app, app.EyeFlowUIFigure)
        runStartupFcn(app, @startupFcn)

        if nargout == 0
            clear app
        end

    end

    function delete(app)
        delete(app.EyeFlowUIFigure)
    end

end

end
