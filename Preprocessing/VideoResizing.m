function VideoResizing(obj, params)
R = params.json.Preprocess.Resize;
[numX, numY, numFrames] = size(obj.M0);

outH = R.FrameHeight; outW = R.FrameWidth; outT = R.VideoLength;

if outH <= 0 && outW <= 0
    outH = max(numX, numY); outW = outH; % isomorphe spatialement
elseif outH <= 0
    outH = numX; % largeur seule : on garde la hauteur
elseif outW <= 0
    outW = numY; % hauteur seule : on garde la largeur
end

if outT <= 0, outT = numFrames; end

if outH == numX && outW == numY && outT == numFrames, return, end

fprintf('Resizing data cube : %dx%dx%d to %dx%dx%d\n', numX, numY, numFrames, outH, outW, outT);
gx = linspace(1, numX, outH);
gy = linspace(1, numY, outW);
gt = linspace(1, numFrames, outT);
obj.applyToVideos(@(v) resizeCube(v, gx, gy, gt));
end

function out = resizeCube(v, gx, gy, gt)

if ~isreal(v) % f_RMS peut être complexe si M2 < 0
    out = complex(resizeCube(real(v), gx, gy, gt), resizeCube(imag(v), gx, gy, gt));
    return
end

[nx, ny, nt] = size(v);
F = griddedInterpolant({1:nx, 1:ny, 1:nt}, v, 'linear', 'nearest');
out = single(F({gx, gy, gt}));
end
