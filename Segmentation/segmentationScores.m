function [results, log] = segmentationScores(maskArtery, maskVein)
% This function calculates Dice Score, Jaccard Index, Accuracy, and Precision
% for artery and vein masks compared to target masks. The results are saved
% in a log file and also returned for further processing.
%
% Inputs:
%   maskArtery - The predicted artery segmentation mask
%   maskVein - The predicted vein segmentation mask
%
% Outputs:
%   results - A struct containing the calculated metrics for both artery and vein
%   log - A string indicating the status of the logging operation

% Ensure Toolbox is initialized
ToolBox = getGlobalToolBox;

% Check if the target masks exist, otherwise return an error message
targetMaskArteryPath = fullfile(ToolBox.EF_path, 'mask', 'targetMaskArtery.png');
targetMaskVeinPath = fullfile(ToolBox.EF_path, 'mask', 'targetMaskVein.png');

if ~isfile(targetMaskArteryPath) || ~isfile(targetMaskVeinPath)
    return
end

% Read the target masks for artery and vein
targetMaskArtery = imread(targetMaskArteryPath);
targetMaskVein = imread(targetMaskVeinPath);

% Confusion matrix values for artery
TPArtery = nnz(targetMaskArtery & maskArtery);
FPArtery = nnz(~targetMaskArtery & maskArtery);
FNArtery = nnz(targetMaskArtery & ~maskArtery);
TNArtery = nnz(~targetMaskArtery & ~maskArtery);

% Confusion matrix values for vein
TPVein = nnz(targetMaskVein & maskVein);
FPVein = nnz(~targetMaskVein & maskVein);
FNVein = nnz(targetMaskVein & ~maskVein);
TNVein = nnz(~targetMaskVein & ~maskVein);

% Dice Score Calculations (for both Artery and Vein)
DiceArtery = 100 * 2 * TPArtery / (2 * TPArtery + FPArtery + FNArtery);
DiceVein = 100 * 2 * TPVein / (2 * TPVein + FPVein + FNVein);

% Jaccard Index Calculations (for both Artery and Vein)
JaccardArtery = 100 * TPArtery / (TPArtery + FPArtery + FNArtery);
JaccardVein = 100 * TPVein / (TPVein + FPVein + FNVein);

% Accuracy Calculations (for both Artery and Vein)
AccuracyArtery = 100 * (TPArtery + TNArtery) / (TPArtery + FPArtery + FNArtery + TNArtery);
AccuracyVein = 100 * (TPVein + TNVein) / (TPVein + FPVein + FNVein + TNVein);

% Precision Calculations (for both Artery and Vein)
PrecisionArtery = 100 * TPArtery / (TPArtery + FPArtery);
PrecisionVein = 100 * TPVein / (TPVein + FPVein);

% Define the log file path and open for writing
logFilePath = fullfile(ToolBox.path_log, sprintf("%s_confusionMatrix.txt", ToolBox.folder_name));
fileID = fopen(logFilePath, 'w+');

if fileID == -1
    error('Could not open the log file for writing.');
end

% Write results to the log file in a readable format
fprintf(fileID, "Artery and Vein Segmentation Performance Metrics\n");
fprintf(fileID, "----------------------------------\n");

fprintf(fileID, "    Artery Dice Score: %0.2f %%\n", DiceArtery);
fprintf(fileID, "    Vein Dice Score: %0.2f %%\n", DiceVein);

fprintf(fileID, "    Artery Jaccard Index: %0.2f %%\n", JaccardArtery);
fprintf(fileID, "    Vein Jaccard Index: %0.2f %%\n", JaccardVein);

fprintf(fileID, "    Artery Accuracy: %0.2f %%\n", AccuracyArtery);
fprintf(fileID, "    Vein Accuracy: %0.2f %%\n", AccuracyVein);

fprintf(fileID, "    Artery Precision: %0.2f %%\n", PrecisionArtery);
fprintf(fileID, "    Vein Precision: %0.2f %%\n", PrecisionVein);

% Close the log file after writing
fclose(fileID);

% Return results as a struct for further processing
results = struct('DiceArtery', DiceArtery, 'DiceVein', DiceVein, ...
    'JaccardArtery', JaccardArtery, 'JaccardVein', JaccardVein, ...
    'AccuracyArtery', AccuracyArtery, 'AccuracyVein', AccuracyVein, ...
    'PrecisionArtery', PrecisionArtery, 'PrecisionVein', PrecisionVein);

log = 'Results logged successfully.';

ToolBox.Output.add('QualityControlDiceArtery', DiceArtery);
ToolBox.Output.add('QualityControlDiceVein', DiceVein);
ToolBox.Output.add('QualityControlJaccardArtery', JaccardArtery);
ToolBox.Output.add('QualityControlJaccardVein', JaccardVein);
ToolBox.Output.add('QualityControlAccuracyArtery', AccuracyArtery);
ToolBox.Output.add('QualityControlAccuracyVein', AccuracyVein);
ToolBox.Output.add('QualityControlPrecisionArtery', PrecisionArtery);
ToolBox.Output.add('QualityControlPrecisionVein', PrecisionVein);

end
