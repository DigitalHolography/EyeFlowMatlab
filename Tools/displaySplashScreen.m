function displaySplashScreen()
% Optional splash screen: never block EyeFlow startup.

if ~usejava('jvm')
    fprintf('[EyeFlow] Splash screen skipped: Java unavailable.\n');
    return;
end

try
    toolsDir = fileparts(mfilename('fullpath'));
    appRoot = fileparts(toolsDir);

    logoPath = fullfile(appRoot, 'eyeflow_logo.png');

    if ~isfile(logoPath)
        logoPath = fullfile(toolsDir, 'eyeflow_logo.png');
    end

    if ~isfile(logoPath)
        fprintf('[EyeFlow] Splash screen skipped: logo not found.\n');
        return;
    end

    s = SplashScreen( ...
        'Splashscreen', logoPath, ...
        'ProgressBar', 'on', ...
        'ProgressPosition', 5, ...
        'ProgressRatio', 0.4);

    cleanup = onCleanup(@() closeSplash(s));
    pause(3);

catch ME
    warning('EyeFlow:SplashScreenSkipped', ...
        'Splash screen skipped: %s', ME.message);
end

end

function closeSplash(s)

try
    delete(s);
catch
    % The splash may already have been closed.
end

end
