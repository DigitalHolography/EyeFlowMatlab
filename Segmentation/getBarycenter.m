function [xy_barycenter, xy_CRA, xy_CRV] = getBarycenter(f_AVG)

ToolBox = getGlobalToolBox;
params = ToolBox.getParams;
CRACRV_Threshold = params.json.Mask.CRACRVThreshold;
forceBarycenter = params.json.Mask.ForceBarycenter;
blur = params.json.Mask.Blur;
diaphragmRadius = params.json.Mask.DiaphragmRadius;

[numX, numY, ~] = size(f_AVG);

if size(f_AVG, 3) > 1
    f_AVG_mean = mean(f_AVG, 3);
else
    f_AVG_mean = f_AVG;
end

ToolBox.Output.add("f_AVG_mean", f_AVG_mean, h5path = "/Maps/f_AVG_mean");

if max(f_AVG_mean, [], 'all') <= 0
    figure;
    imshow(rescale(f_AVG_mean));
    error("Measurement error from the Moment 1 input. Check the input or re-do the measurement.")
end

% Compute the barycenters and the circle mask
if ~isempty(forceBarycenter)
    y_CRA = forceBarycenter(1);
    x_CRA = forceBarycenter(2);
    x_CRV = forceBarycenter(1);
    y_CRV = forceBarycenter(2);
else

    if ~isfolder(fullfile(ToolBox.path_png, 'mask'))
        mkdir(ToolBox.path_png, 'mask')
        mkdir(ToolBox.path_eps, 'mask')
        mkdir(fullfile(ToolBox.path_png, 'mask'), 'steps')
        mkdir(fullfile(ToolBox.path_eps, 'mask'), 'steps')
    end

    saveMaskImage(f_AVG_mean, 'all_10_fAVG.png', isStep = true)

    maskDiaphragm = diskMask(numX, numY, diaphragmRadius);

    if blur ~= 0
        averaged_fAVG = imgaussfilt(f_AVG_mean, blur, 'Padding', 0) .* maskDiaphragm;
    else
        averaged_fAVG = f_AVG_mean;
    end

    [y_CRA, x_CRA] = find(averaged_fAVG == max(averaged_fAVG, [], 'all'));
    [y_CRV, x_CRV] = find(averaged_fAVG == min(averaged_fAVG, [], 'all'));
end

f_AVG_std = std2(f_AVG_mean);
maskCRA = f_AVG_mean > (CRACRV_Threshold * f_AVG_std);
maskCRV = f_AVG_mean < (-CRACRV_Threshold * f_AVG_std);

saveMaskImage(maskCRA, 'maskCRA.png')
saveMaskImage(maskCRV, 'maskCRV.png')

maskCRA2 = diskMask(numX, numY, 0.01, "center", [x_CRA/numX, y_CRA/numY] );
maskCRV2 = diskMask(numX, numY, 0.01, "center", [x_CRV/numX, y_CRV/numY]  );

saveMaskImage(maskCRA2, 'maskCRA2.png')
saveMaskImage(maskCRV2, 'maskCRV2.png')

ToolBox.Cache.maskCRA2 = maskCRA2;
ToolBox.Cache.maskCRV2 = maskCRV2;

xy_barycenter = round([x_CRV + x_CRA, y_CRV + y_CRA] / 2);
xy_CRA = [x_CRA, y_CRA];
xy_CRV = [x_CRV, y_CRV];
ToolBox.Cache.xy_barycenter = xy_barycenter;
ToolBox.Cache.xy_CRA = xy_CRA;
ToolBox.Cache.xy_CRV = xy_CRV;

end
