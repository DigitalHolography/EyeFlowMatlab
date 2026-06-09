classdef AnalyzerClass < handle
% Handles all analysis operations

properties
    Cache CacheClass
end

methods

    function obj = AnalyzerClass(Cache)
        obj.Cache = Cache;
    end

    function performSegmentation(~, executionObj, app)
        fprintf("\n----------------------------------\n" + ...
            "Segmentation\n" + ...
        "----------------------------------\n");
        createMasksTimer = tic;

        ToolBox = getGlobalToolBox;

        if ~isfolder(fullfile(ToolBox.path_png, 'mask'))
            mkdir(ToolBox.path_png, 'mask')
        end

        if ~isfolder(fullfile(ToolBox.path_eps, 'mask'))
            mkdir(ToolBox.path_eps, 'mask')
        end

        if ~isfolder(fullfile(ToolBox.path_png, 'mask', 'steps'))
            mkdir(fullfile(ToolBox.path_png, 'mask'), 'steps')
        end

        if ~isfolder(fullfile(ToolBox.path_eps, 'mask', 'steps'))
            mkdir(fullfile(ToolBox.path_eps, 'mask'), 'steps')
        end

        ToolBox.Cache.xy_barycenter = getBarycenter(executionObj.Cache.f_AVG);
        M0_ff_img = rescale(mean(executionObj.Cache.M0_ff, 3));

        ToolBox.Cache.M0_ff_img = M0_ff_img;

        ToolBox.Output.add("M0_ff_img", M0_ff_img, h5path = "/Maps/M0_ff_img");

        % Optic disk
        try % papilla detection

            if ToolBox.getParams.json.Mask.OpticDiskSegmentationNet
                % New model
                [~, center_x, center_y, diameter_x, diameter_y] = predictOpticDisk(executionObj.AINetworks.OpticDiskSegmentationNet, M0_ff_img);
            elseif ToolBox.getParams.json.Mask.OpticDiskDetectorNet
                [~, diameter_x, diameter_y, center_x, center_y] = findPapilla(M0_ff_img, executionObj.AINetworks.OpticDiskDetectorNet);
            else
                center_x = NaN;
                center_y = NaN;
                diameter_x = NaN;
                diameter_y = NaN;
            end

            xy_papilla = [center_x, center_y];
            ToolBox.Cache.xy_papilla = xy_papilla;

            ToolBox.Output.add("PapillaRatio", (diameter_x + diameter_y) / 2 / size(executionObj.Cache.M0_ff, 1), h5path = '/OpticDisc/Ratio');
            ToolBox.Output.add("PapillaXY", xy_papilla, h5path = '/OpticDisc/XYCenter', unit = 'px');
        catch ME
            warning("Error while finding papilla : ")
            MEdisp(ME, ToolBox.EF_path);
            diameter_x = NaN;
            diameter_y = NaN;
        end

        params = ToolBox.getParams;
        papillaDiameter = mean([diameter_x, diameter_y]);
        ToolBox.Cache.papillaDiameter = papillaDiameter;

        if isnan(papillaDiameter) % if is nan return to default
            pixelSize = params.json.generateCrossSectionSignals.DefaultPixelSize / (2 ^ params.json.Preprocess.InterpolationFactor);
        else
            pixelSize = params.json.generateCrossSectionSignals.RefPapillaSize / mean([diameter_x, diameter_y]);
        end

        fprintf("Using pixel size : %f mm/pix \n", pixelSize);

        ToolBox.Cache.pixelSize = pixelSize;

        createMasks(executionObj.Cache.M0_ff, executionObj.AINetworks.VesselSegmentationNet, executionObj.AINetworks.AVSegmentationNet, executionObj.AINetworks.EyeDiaphragmSegmentationNet);

        % Artery score
        scoreA = ToolBox.Cache.scoreMaskArtery;

        ToolBox.Output.add("QualityControlScoreMaskArtery", scoreA, '', h5path = '/Artery/Segmentation/QualityScore');

        if isempty(scoreA) || isnan(scoreA)
        else
            fprintf("- Mask artery quality score: %.2f\n", scoreA);

            if scoreA < 0.5
                warning("AnalyzerClass:LowMaskScore", "Mask artery quality score too low (%.2f < 0.5). Dangerous segmentation.", scoreA);
            end

        end

        ToolBox.Output.add("maskArtery", ToolBox.Cache.maskArtery, h5path = '/Artery/Segmentation/Mask');

        % Vein score (if veins analysis enabled)
        scoreV = ToolBox.Cache.scoreMaskVein;

        ToolBox.Output.add("QualityControlScoreMaskVein", scoreV, '', h5path = '/Vein/Segmentation/QualityScore');

        if isempty(scoreV) || isnan(scoreV)
        else
            fprintf("- Mask vein quality score: %.2f\n", scoreV);

            if scoreV < 0.5
                warning("AnalyzerClass:LowMaskScore", "Mask vein quality score too low (%.2f < 0.5). Dangerous segmentation.", scoreV);
            end

        end

        ToolBox.Output.add("maskVein", ToolBox.Cache.maskVein, h5path = '/Vein/Segmentation/Mask');

        % Visualize the segmentation result
        M0_RGB = ToolBox.Cache.M0_RGB;

        % Display the mask on the app if available
        if ~isempty(app)
            app.setImageSource(M0_RGB);
            app.setAxisEqual();
        end

        executionObj.is_segmented = true;
        fprintf("- Mask Creation took: %ds\n", round(toc(createMasksTimer)));
    end

    function performPulseAnalysis(~, executionObj)
        fprintf("\n----------------------------------\n" + ...
            "Blood Flow Velocity Analysis\n" + ...
        "----------------------------------\n");
        pulseAnalysisTimer = tic;

        [executionObj.Cache.vRMS, executionObj.Cache.v_video_RGB, executionObj.Cache.v_mean_RGB] = pulseAnalysis(executionObj.Cache.f_RMS, executionObj.Cache.M0_ff);

        perBeatAnalysis();

        axialAnalysis(executionObj.Cache.f_AVG);

        executionObj.is_velocityAnalyzed = true;
        fprintf("- Blood Flow Velocity Analysis took: %ds\n", round(toc(pulseAnalysisTimer)));
    end

    function performPulseVelocityAnalysis(~, executionObj)
        fprintf("\n----------------------------------\n" + ...
            "Pulse Velocity Calculation\n" + ...
        "----------------------------------\n");
        pulseVelocityTimer = tic;

        ToolBox = getGlobalToolBox;
        maskArtery = ToolBox.Cache.maskArtery;
        maskVein = ToolBox.Cache.maskVein;
        pulseVelocity(executionObj.Cache.M0_ff, executionObj.Cache.displacementField, maskArtery, 'artery');
        pulseVelocity(executionObj.Cache.M0_ff, executionObj.Cache.displacementField, maskVein, 'vein');

        time_pulsevelocity = toc(pulseVelocityTimer);
        fprintf("- Pulse Velocity Calculations took : %ds\n", round(time_pulsevelocity))
    end

    function performCrossSectionAnalysis(~, executionObj)
        fprintf("\n----------------------------------\n" + ...
            "Generate Cross-Section Signals\n" + ...
        "----------------------------------\n");
        crossSectionAnalysisTimer = tic;

        ToolBox = getGlobalToolBox;
        maskArtery = ToolBox.Cache.maskArtery;
        maskVein = ToolBox.Cache.maskVein;
        [executionObj.Cache.Q_results_A] = generateCrossSectionSignals(maskArtery, 'artery', executionObj.Cache.vRMS, executionObj.Cache.M0_ff, executionObj.Cache.displacementField);
        [executionObj.Cache.Q_results_V] = generateCrossSectionSignals(maskVein, 'vein', executionObj.Cache.vRMS, executionObj.Cache.M0_ff, executionObj.Cache.displacementField);

        executionObj.is_volumeRateAnalyzed = true;
        fprintf("- Cross-Section Signals Generation took: %ds\n", round(toc(crossSectionAnalysisTimer)));
    end

    function generateexportCrossSectionResults(~, executionObj)
        fprintf("\n----------------------------------\n" + ...
            "Export Cross-Section Results\n" + ...
        "----------------------------------\n");
        exportCrossSectionResultsTimer = tic;

        ToolBox = getGlobalToolBox;
        exportCrossSectionResults(executionObj.Cache.Q_results_A, 'artery', executionObj.Cache.M0_ff, executionObj.Cache.v_video_RGB, executionObj.Cache.v_mean_RGB, executionObj.Cache.displacementField);
        exportCrossSectionResults(executionObj.Cache.Q_results_V, 'vein', executionObj.Cache.M0_ff, executionObj.Cache.v_video_RGB, executionObj.Cache.v_mean_RGB, executionObj.Cache.displacementField);

        maskVessel = ToolBox.Cache.maskVessel;
        sectionImageAdvanced(executionObj.Cache.M0_ff_img, executionObj.Cache.Q_results_A.maskLabel, executionObj.Cache.Q_results_V.maskLabel, executionObj.Cache.Q_results_A.rejected_mask, executionObj.Cache.Q_results_V.rejected_mask, maskVessel);

        try
            combinedCrossSectionAnalysis(executionObj.Cache.Q_results_A, executionObj.Cache.Q_results_V, executionObj.Cache.M0_ff)
        catch ME
            MEdisp(ME, ToolBox.EF_path);
        end

        executionObj.is_AllAnalyzed = true;
        fprintf("- Cross-Section Results Export took: %ds\n", round(toc(exportCrossSectionResultsTimer)));
    end

    function performSpectralAnalysis(~, executionObj)
        fprintf("\n----------------------------------\n" + ...
            "Spectral Analysis\n" + ...
        "----------------------------------\n");
        timeSpectralAnalysis = tic;

        ToolBox = getGlobalToolBox;

        if ~isfolder(fullfile(ToolBox.path_png, 'spectralAnalysis'))
            mkdir(fullfile(ToolBox.path_png), 'spectralAnalysis');
            mkdir(fullfile(ToolBox.path_eps), 'spectralAnalysis');
        end

        % Spectrum Analysis
        fprintf("\n----------------------------------\n" + ...
            "Spectrum Analysis\n" + ...
        "----------------------------------\n");
        spectrumAnalysisTimer = tic;

        spectrum_analysis(executionObj.SH, executionObj.Cache.M0_ff);
        fprintf("- Spectrum Analysis took : %ds\n", round(toc(spectrumAnalysisTimer)))

        % Spectrogram
        fprintf("\n----------------------------------\n" + ...
            "Spectrogram\n" + ...
        "----------------------------------\n");
        spectrogramTimer = tic;

        maskArtery = ToolBox.Cache.maskArtery;
        maskNeighbors = ToolBox.Cache.maskNeighbors;
        spectrum_video(executionObj.SH, executionObj.Cache.f_RMS, maskArtery, maskNeighbors);

        fprintf("- Spectrogram took: %ds\n", round(toc(spectrogramTimer)));
        fprintf("\n----------------------------------\n" + ...
            "Spectral Analysis Complete\n" + ...
        "----------------------------------\n");
        fprintf("Spectral Analysis timing: %ds\n", round(toc(timeSpectralAnalysis)));
    end

end

end
