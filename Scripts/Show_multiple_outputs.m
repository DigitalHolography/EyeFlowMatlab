% Test and evaluation script

paths = readlines("C:\Users\Vladikavkaz\Documents\data_test_list.txt");

figure(435)
title("Segmentation")

figure(321)
title('Flow Rate')

for ind = 1:length(paths)
    split_path = strsplit(paths(ind), '\');
    folder_name = split_path{end};
    folder_name = strcat(folder_name, '_EF');
    path = fullfile(paths(ind), 'eyeflow');
    list_dir = dir(path);
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

    segmentation_paths{ind} = fullfile(path, last_folder_name, 'png', 'mask', [folder_name, '_arteryVeinSegmentation.png']);
    bvr_paths{ind} = fullfile(path, last_folder_name, 'png', [folder_name, '_volumeRateallradxtime.png']);
end

output_dir = 'D:\EyeFlow_tests_output';
mkdir(output_dir);
figure(435)
montage(segmentation_paths);
exportgraphics(gca, fullfile(output_dir, 'segmentations.png'));
figure(321)
montage(bvr_paths);
exportgraphics(gca, fullfile(output_dir, 'bloodVolumeRate.png'));
