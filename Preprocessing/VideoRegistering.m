function VideoRegistering(obj, firstFrame, lastFrame)
[numX, numY, numFrames] = size(obj.M0);
firstFrame = max(firstFrame, 1);
if lastFrame == -1, lastFrame = numFrames; end
lastFrame = min(lastFrame, numFrames);
assert(firstFrame <= lastFrame, 'Invalid registration reference range.');

disc = diskMask(numX, numY, 0.35);
v = obj.M0 .* disc;
v = v - disc .* sum(v, [1, 2]) / nnz(disc); % moyenne nulle dans le disque
v = v ./ max(max(abs(v), [], [1, 2]), eps('single')); % rescale par frame
v = reshape(v, numX, numY, 1, numFrames);

image_ref = mean(v(:, :, 1, firstFrame:lastFrame), 4);
[~, shifts, scores] = register_video_from_reference(v, image_ref);

outDir = fullfile(obj.directory, 'eyeflow');
f1 = figure('Visible', 'off');
plot(scores / mean(scores), 'k'); ylim([0 max(0.1, 1.2 * max(scores) / mean(scores))]);
title('Registration Correlation Score (1 is good) (u.a.)');
saveas(f1, fullfile(outDir, sprintf('%s_RegistrationCorrelationScore.png', obj.filenames)));
close(f1);

f2 = figure('Visible', 'off');
plot(shifts(1, :)); hold on; plot(shifts(2, :)); legend('x', 'y');
title('Registration shifts (px)');
saveas(f2, fullfile(outDir, sprintf('%s_RegistrationShiftsXY.png', obj.filenames)));
close(f2);

obj.applyToVideos(@(c) register_video_from_shifts(c, shifts)); % M0, M1, M2, HF, LF
end
