paths = readlines("X:\250117\AUZ_L\aaa.txt");

%% ensure set default parameters and no forced mask

Ndilation = 9;

ratio = 2 * 512;

for ind = 1:length(paths)
    ef_path = fullfile(paths(ind), 'eyeflow');
    jsonFiles = dir(fullfile(ef_path, 'json', '*.json'));

    for i = 1:length(jsonFiles)
        filePath = fullfile(fullfile(ef_path, 'json'), jsonFiles(i).name);
        delete(filePath);
    end

    copyfile(fullfile('Parameters', 'DefaultEyeFlowParams.json'), fullfile(ef_path, 'json', 'input_EF_params.json'));

    for j = 0:Ndilation

        fileID = fopen(fullfile(ef_path, 'json', 'input_EF_params.json'), 'r');
        jsonData = fread(fileID, inf, 'uint8')';
        fclose(fileID);
        jsonData = char(jsonData);
        decodedData = jsondecode(jsonData);

        decodedData.Mask.ForceVesselWidth = j;

        jsonStr = jsonencode(decodedData, "PrettyPrint", true);
        fileID = fopen(fullfile(ef_path, 'json', sprintf('input_EF_params_%d.json', j)), 'w');
        fprintf(fileID, '%s', jsonStr);
        fclose(fileID);
    end

end

%% launch

for ind = 1:length(paths)
    path = paths(ind);

    if isfolder(path)
        path = strcat(path, '\');
    end

    ExecClass = ExecutionClass(path);

    ExecClass = ExecClass.preprocessData();

    ExecClass.flag_SH_analysis = 0;
    ExecClass.flag_Segmentation = 1;
    ExecClass.flag_Pulse_analysis = 1;
    ExecClass.flag_velocity_analysis = 0;
    ExecClass.flag_bloodVolumeRate_analysis = 0;

    for i = 1:length(ExecClass.params_names)
        ExecClass.param_name = ExecClass.params_names{i};
        ExecClass.analyzeData();
    end

end

%% Show
figure("Visible", "off");
hold on;

for ind = 1:length(paths)
    split_path = strsplit(paths(ind), '\');
    folder_name = split_path{end};
    folder_name = strcat(folder_name, '_EF');
    ef_path = fullfile(paths(ind), 'eyeflow');
    list_dir = dir(ef_path);
    idx = 0;

    for i = 1:length(list_dir)

        if contains(list_dir(i).name, folder_name)
            match = regexp(list_dir(i).name, '\d+$', 'match');

            if ~isempty(match) && str2double(match{1}) >= idx
                idx = str2double(match{1}); %suffix
            end

        end

    end

    last_folder_name = sprintf('%s_%d', folder_name, idx);

    diffRMS = {};

    for j = 0:Ndilation

        fileID = fopen(fullfile(ef_path, sprintf('%s_%d', folder_name, idx - (Ndilation - j)), 'txt', sprintf("%s_advanced_outputs.txt", sprintf('%s', folder_name))), 'r');

        if fileID >= 0
            tline = fgetl(fileID);

            while ischar(tline)

                if contains(tline, 'Mean fRMS difference artery ')
                    tmp = regexp(tline, '\d+(\.\d+)?', 'match');
                    diffRMS{j + 1} = str2double(tmp{1});
                end

                tline = fgetl(fileID);
            end

            fclose(fileID);
        else
            disp('error opening file')
        end

    end

    plot((2 * (1:Ndilation) + 1) / ratio, cell2mat(diffRMS(2:end)), 'LineWidth', 2);
    %findpeaks(cell2mat(diffRMS(2:end)));
end

ylabel('Mean difference \sigma_f');
xlabel('width on max dimension ratio');
