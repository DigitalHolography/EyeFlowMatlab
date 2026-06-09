classdef FolderManagementUI < handle
% FolderManagementUI   Batch folder manager for EyeFlow
%
%   FM = FolderManagementUI(APP) creates a non-modal figure that allows
%   managing a list of EyeFlow measurement folders and running batch
%   analysis.
%
%   The list contains **parent folders** (e.g. 'X:\Data\mouse123') that
%   hold the '_HD' and '_EF' sub‑folders.

properties (Access = private)
    MainApp % Reference to the main EyeFlow app
    TextArea % uitextarea displaying the folder list
    WorkerSpinner % uispinner for number of parallel workers
    WorkersLabel % Label for the worker spinner
    Figure % uifigure handle
end

methods

    function obj = FolderManagementUI(mainApp)

        arguments
            mainApp
        end

        obj.MainApp = mainApp;
        obj.createUI();
        fontname(obj.Figure, 'Arial');
        fontsize(obj.Figure, 12, "points");
    end

    function bringToFront(obj)
        % Bring the existing UI figure to the front
        if ~isempty(obj.Figure) && isvalid(obj.Figure)
            figure(obj.Figure);
        end

    end

end

methods (Access = private)

    function createUI(obj)
        app = obj.MainApp;
        nFolders = max(length(app.drawer_list), 1);
        initialHeight = 222 + nFolders * 18;

        % Position next to main app if possible
        if ismethod(app, 'getMainFigure')
            mainFig = app.getMainFigure();

            if isvalid(mainFig)
                mainPos = mainFig.Position;
                xPos = mainPos(1) + mainPos(3) + 20;
                yPos = mainPos(2);
            else
                xPos = 300; yPos = 300;
            end

        else
            xPos = 300; yPos = 300;
        end

        obj.Figure = uifigure('Position', [xPos, yPos, 650, initialHeight], ...
            'Color', [0.2, 0.2, 0.2], ...
            'Name', 'Folder Management - EyeFlow', ...
            'Resize', 'on', ...
            'WindowStyle', 'normal', ...
            'CloseRequestFcn', @(~, ~) obj.closeFigure());

        % Main grid: text area (top) + button panel (bottom)
        mainGrid = uigridlayout(obj.Figure, [2, 1], ...
            'ColumnWidth', {'1x'}, ...
            'RowHeight', {'1x', 'fit'}, ...
            'Padding', [10, 10, 10, 10], ...
            'BackgroundColor', [0.2, 0.2, 0.2], ...
            'RowSpacing', 10);

        % Text area for folder list
        if isempty(app.drawer_list)
            displayValue = {''};
        else
            displayValue = app.drawer_list;
        end

        obj.TextArea = uitextarea('Parent', mainGrid, ...
            'BackgroundColor', [0.2, 0.2, 0.2], ...
            'FontColor', [0.8, 0.8, 0.8], ...
            'Value', displayValue, ...
            'Editable', 'off');
        obj.TextArea.Layout.Row = 1;
        obj.TextArea.Layout.Column = 1;

        % Button panel grid (3 columns)
        btnGrid = uigridlayout(mainGrid, [5, 3], ...
            'ColumnWidth', {200, 200, 200}, ...
            'RowHeight', repmat({'fit'}, 1, 5), ...
            'Padding', [5, 5, 5, 5], ...
            'BackgroundColor', [0.2, 0.2, 0.2]);
        btnGrid.Layout.Row = 2;
        btnGrid.Layout.Column = 1;

        % Spinner label and spinner
        obj.WorkersLabel = uilabel(btnGrid, 'Text', 'Parallel workers:', ...
            'FontColor', [1 1 1], ...
            'HorizontalAlignment', 'right');
        obj.WorkersLabel.Layout.Row = 1;
        obj.WorkersLabel.Layout.Column = 2;

        % The spinner allows selecting the number of parallel workers to use during rendering.
        obj.WorkerSpinner = uispinner(btnGrid, ...
            'Limits', [0, parcluster('local').NumWorkers], ...
            'Value', min(10, floor(parcluster('local').NumWorkers / 2)), ...
            'FontColor', [1 1 1], ...
            'BackgroundColor', [0.3 0.3 0.3]);
        obj.WorkerSpinner.Layout.Row = 1;
        obj.WorkerSpinner.Layout.Column = 3;

        % Common button styles
        bkgColor = [0.5, 0.5, 0.5];
        fontColor = [1, 1, 1];
        renderColor = [0.2, 0.6, 0.2];

        % ---- Column 1 ----
        obj.makeButton(btnGrid, 2, 2, 'Select HD folder', ...
            @(~, ~) obj.selectFolder(), bkgColor, fontColor, ...
        'Pick a single measurement folder (parent folder containing _HD and _EF)');
        obj.makeButton(btnGrid, 3, 2, 'Select every HD folder', ...
            @(~, ~) obj.selectAllFromSession(), bkgColor, fontColor, ...
        'Scan a session folder and add all measurement folders (those having a _HD sub‑folder)');
        obj.makeButton(btnGrid, 4, 2, 'Clear List', ...
            @(~, ~) obj.clearList(), bkgColor, fontColor, 'Remove all entries');

        % ---- Column 2 ----
        obj.makeButton(btnGrid, 1, 1, 'Load from txt', ...
            @(~, ~) obj.loadFromTxt(), bkgColor, fontColor, 'Load folder paths from a text file');
        obj.makeButton(btnGrid, 2, 1, 'Save to txt', ...
            @(~, ~) obj.saveToTxt(), bkgColor, fontColor, 'Save current folder list to a text file');
        obj.makeButton(btnGrid, 3, 1, 'Clear Parameters', ...
            @(~, ~) obj.clearParameters(), bkgColor, fontColor, 'Delete all JSON param files from listed folders');
        obj.makeButton(btnGrid, 4, 1, 'Import Parameter', ...
            @(~, ~) obj.importParameter(), bkgColor, fontColor, 'Copy a JSON parameter file to every listed folder');

        % ---- Column 3 ----
        obj.makeButton(btnGrid, 2, 3, 'Render', ...
            @(~, ~) obj.render(), renderColor, fontColor, 'Run EyeFlow analysis on all listed folders');
        obj.makeButton(btnGrid, 3, 3, 'Show Results', ...
            @(~, ~) obj.showResults(), bkgColor, fontColor, 'Generate combined report for all listed folders');
    end

    function btn = makeButton(~, parent, row, col, label, cb, bgColor, fontColor, tooltip)
        % Helper to create a push button with optional tooltip
        btn = uibutton(parent, 'push', ...
            'BackgroundColor', bgColor, ...
            'FontColor', fontColor, ...
            'Text', label, ...
            'ButtonPushedFcn', cb);
        btn.Layout.Row = row;
        btn.Layout.Column = col;

        if nargin > 7
            btn.Tooltip = tooltip;
        end

    end

    function updateDisplay(obj)
        app = obj.MainApp;

        if isempty(app.drawer_list)
            obj.TextArea.Value = {''};
        else
            obj.TextArea.Value = app.drawer_list;
        end

        n = max(length(app.drawer_list), 1);
        obj.Figure.Position(4) = 222 + n * 18;
    end

    function closeFigure(obj)
        delete(obj.Figure);
        delete(obj);
    end

    % ---------------------------------------------------------------------
    % Callback methods
    % ---------------------------------------------------------------------

    function selectFolder(obj)
        % Unified selection: pick a folder or a .holo file.
        % Always adds the corresponding _HD folder to the list.
        app = obj.MainApp;
        startPath = pwd;

        if ~isempty(app.drawer_list)
            startPath = app.drawer_list{end};
        end

        % --- Try folder selection first ---
        selPath = uigetdir(startPath, 'Select a measurement folder or cancel to pick a .holo file');

        if selPath == 0
            % User cancelled folder selection → try file selection
            [file, fpath] = uigetfile('*.holo', 'Select a .holo file', startPath);

            if isequal(file, 0)
                return; % user cancelled both
            end

            selPath = fullfile(fpath, file); % full path to the .holo file
        end

        % --- Resolve the _HD folder from the selected path ---
        hdFolder = obj.resolveHDFolder(selPath);

        if isempty(hdFolder)
            uialert(obj.Figure, 'No corresponding _HD folder found.', 'Invalid Selection');
            return;
        end

        app.drawer_list{end + 1} = hdFolder;
        fprintf('Added HD folder: %s\n', hdFolder);
        obj.updateDisplay();
    end

    function hdPath = resolveHDFolder(~, selectedPath)
        % Given a folder or .holo file, return the _HD subfolder path.
        % Returns empty if no appropriate _HD folder can be found.
        hdPath = '';

        if isfolder(selectedPath)
            % If it's already an _HD folder, use it directly
            [~, fname] = fileparts(selectedPath);

            if endsWith(fname, '_HD')
                hdPath = selectedPath;
            else
                % Assume it's the parent folder; look for fname_HD inside
                candidate = fullfile(selectedPath, [fname, '_HD']);

                if isfolder(candidate)
                    hdPath = candidate;
                end

            end

        elseif isfile(selectedPath)
            % It's a .holo file; look in its parent folder for <basename>_HD
            [pDir, fname] = fileparts(selectedPath);
            candidate = fullfile(pDir, [fname, '_HD']);

            if isfolder(candidate)
                hdPath = candidate;
            end

        end

    end

    function selectAllFromSession(obj)
        % Pick a super‑folder and add every X_HD sub‑folder that exists inside a child X.
        app = obj.MainApp;
        startPath = pwd;

        if ~isempty(app.drawer_list)
            startPath = app.drawer_list{end};
        end

        superFolder = uigetdir(startPath, 'Select the super‑folder (parent of measurement folders)');
        if superFolder == 0, return; end

        d = dir(superFolder);
        d = d([d.isdir] & ~ismember({d.name}, {'.', '..'}));

        added = 0;

        for i = 1:length(d)
            folderName = d(i).name; % e.g. '260113_FIY0713_3'
            hdCandidate = fullfile(superFolder, folderName, [folderName, '_HD']);

            if isfolder(hdCandidate)
                app.drawer_list{end + 1} = hdCandidate; % <-- add the _HD folder itself
                added = added + 1;
            end

        end

        fprintf('Added %d HD folder(s) from "%s".\n', added, superFolder);
        obj.updateDisplay();
    end

    function clearList(obj)
        obj.MainApp.drawer_list = {};
        obj.updateDisplay();
    end

    function loadFromTxt(obj)
        app = obj.MainApp;
        [file, path] = uigetfile('*.txt', 'Load folder list');
        if isequal(file, 0), return; end
        lines = readlines(fullfile(path, file));

        for i = 1:numel(lines)
            candidate = strtrim(char(lines(i)));

            if ~isempty(candidate) && isfolder(candidate)
                app.drawer_list{end + 1} = candidate;
            end

        end

        obj.updateDisplay();
    end

    function saveToTxt(obj)
        app = obj.MainApp;

        if isempty(app.drawer_list)
            uialert(obj.Figure, 'List is empty.', 'Nothing to save');
            return;
        end

        [file, path] = uiputfile('*.txt', 'Save folder list as');
        if isequal(file, 0), return; end
        writelines(app.drawer_list, fullfile(path, file));
    end

    function clearParameters(obj)
        app = obj.MainApp;

        if isempty(app.drawer_list)
            uialert(obj.Figure, 'List is empty.', 'No folders');
            return;
        end

        choice = uiconfirm(obj.Figure, ...
            'Delete all JSON parameter files from the listed folders?', ...
            'Confirm Clear', 'Options', {'Yes', 'Cancel'}, ...
            'DefaultOption', 2, 'CancelOption', 2);
        if ~strcmp(choice, 'Yes'), return; end

        nDeleted = 0;

        for i = 1:length(app.drawer_list)
            jsonDir = fullfile(app.drawer_list{i}, 'eyeflow', 'json');

            if isfolder(jsonDir)
                files = dir(fullfile(jsonDir, '*.json'));

                for j = 1:length(files)
                    delete(fullfile(jsonDir, files(j).name));
                    nDeleted = nDeleted + 1;
                end

            end

        end

        fprintf('Deleted %d JSON parameter files.\n', nDeleted);
    end

    function importParameter(obj)
        app = obj.MainApp;

        if isempty(app.drawer_list)
            uialert(obj.Figure, 'List is empty.', 'No folders');
            return;
        end

        [file, path] = uigetfile('*.json', 'Select parameter JSON file to copy');
        if isequal(file, 0), return; end
        srcFile = fullfile(path, file);

        for i = 1:length(app.drawer_list)
            jsonDir = fullfile(app.drawer_list{i}, 'eyeflow', 'json');

            if ~isfolder(jsonDir)
                mkdir(jsonDir);
            end

            % Determine next available index
            existing = dir(fullfile(jsonDir, 'input_EF_params_*.json'));
            maxIdx = 0;

            for k = 1:length(existing)
                tok = regexp(existing(k).name, 'input_EF_params_(\d+)\.json', 'tokens');

                if ~isempty(tok)
                    idx = str2double(tok{1}{1});
                    if idx > maxIdx, maxIdx = idx; end
                end

            end

            destFile = fullfile(jsonDir, sprintf('input_EF_params_%d.json', maxIdx + 1));
            copyfile(srcFile, destFile);
        end

        fprintf('Parameter file imported to %d folders.\n', length(app.drawer_list));
    end

    function render(obj)
        app = obj.MainApp;
        folders = app.drawer_list;

        if isempty(folders)
            uialert(obj.Figure, 'No folders in list.', 'Empty List');
            return;
        end

        % Save current UI state
        savedSeg = app.getWidgetValue('segmentationCheckBox');
        savedBFA = app.getWidgetValue('bloodFlowAnalysisCheckBox');
        savedPWV = app.getWidgetValue('pulseVelocityCheckBox');
        savedCSA = app.getWidgetValue('generateCrossSectionSignalsCheckBox');
        savedExp = app.getWidgetValue('exportCrossSectionResultsCheckBox');
        savedSpec = app.getWidgetValue('spectralAnalysisCheckBox');

        % Apply workers
        app.setWidgetValue('NumberofWorkersSpinner', obj.WorkerSpinner.Value);

        fprintf('\n========== BATCH PROCESSING STARTED ==========\n');
        errors = cell(numel(folders), 1);
        errFolders = cell(numel(folders), 1);

        for i = 1:length(folders)
            folder = folders{i};
            fprintf('\n--- Processing folder %d/%d: %s ---\n', i, length(folders), folder);
            tStart = tic;

            try
                app.Load(folder);
                err = app.ExecuteButtonPushed();

                if ~isempty(err)
                    errors{i} = err;
                    errFolders{i} = folder;
                end

            catch ME
                errors{i} = ME;
                errFolders{i} = folder;
            end

            app.ClearButtonPushed();
            fprintf('  Elapsed: %.1f s\n', toc(tStart));
        end

        % Restore checkboxes
        app.setWidgetValue('segmentationCheckBox', savedSeg);
        app.setWidgetValue('bloodFlowAnalysisCheckBox', savedBFA);
        app.setWidgetValue('pulseVelocityCheckBox', savedPWV);
        app.setWidgetValue('generateCrossSectionSignalsCheckBox', savedCSA);
        app.setWidgetValue('exportCrossSectionResultsCheckBox', savedExp);
        app.setWidgetValue('spectralAnalysisCheckBox', savedSpec);

        fprintf('\n========== BATCH PROCESSING COMPLETED ==========\n');
        errorIndices = find(~cellfun(@isempty, errors));

        if isempty(errorIndices)
            fprintf('All %d folders processed successfully.\n', length(folders));
        else
            fprintf(2, 'Errors occurred in %d folder(s):\n', length(errorIndices));

            for e = 1:length(errorIndices)
                idx = errorIndices(e);
                fprintf(2, '  [%d] %s\n', idx, errFolders{idx});

                if isa(errors{idx}, 'MException')
                    fprintf(2, '      %s\n', errors{idx}.message);
                elseif ischar(errors{idx}) || isstring(errors{idx})
                    fprintf(2, '      %s\n', char(errors{idx}));
                end

            end

        end

    end

    function showResults(obj)
        app = obj.MainApp;

        if isempty(app.drawer_list)
            uialert(obj.Figure, 'List is empty.', 'No folders');
            return;
        end

        outDir = fullfile(app.drawer_list{1}, 'Multiple_Results');

        if ~isfolder(outDir)
            mkdir(outDir);
        end

        fprintf('Generating multi-folder report in: %s\n', outDir);

        try
            ShowOutputs(app.drawer_list, outDir);
            fprintf('Report generation complete.\n');
        catch ME
            uialert(obj.Figure, sprintf('Error generating report:\n%s', ME.message), 'Report Error');
        end

    end

end

end
