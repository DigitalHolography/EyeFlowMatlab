function M_clipped = VideoClipOutliers(M0_ff, params)
% Clip extreme intensity values from M0_ff using percentile thresholds.
% params.json.Preprocess.OutlierClipping should contain:
%   - Enable (logical)
%   - LowPercentile  (e.g., 0.1)
%   - HighPercentile (e.g., 99.9)
%   - RescaleOutput  (logical) – whether to rescale to [0,1] after clipping

cfg = params.json.Preprocess.OutlierClipping;

if ~cfg.Enable
    return;
end

tic
fprintf("    - Clipping intensity outliers...\n");

M = M0_ff;
lowPct = cfg.LowPercentile; % e.g., 0.1
highPct = cfg.HighPercentile; % e.g., 99.9

% Compute global percentiles (more stable than per‑frame)
lowVal = prctile(M(:), lowPct);
highVal = prctile(M(:), highPct);

% Clip the data
M_clipped = M;
M_clipped(M < lowVal) = lowVal;
M_clipped(M > highVal) = highVal;

% Optionally rescale to [0,1]
if cfg.RescaleOutput
    M_clipped = (M_clipped - lowVal) / (highVal - lowVal);
end

fprintf("      Clipped to [%.2f, %.2f] (%.1f%% – %.1f%%).\n", ...
    lowVal, highVal, lowPct, highPct);
end
