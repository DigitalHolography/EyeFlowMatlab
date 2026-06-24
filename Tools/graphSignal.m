function [f] = graphSignal(filename, x, y, style, color, opt)
% Graph Function for Signal display

arguments
    filename {mustBeText}
end

arguments (Repeating)
    x {mustBeNumeric}
    y {mustBeNumeric}
    style
    color
end

arguments
    opt.xlabel {mustBeText} = 'default'
    opt.ylabel {mustBeText} = 'default'
    opt.Title {mustBeText} = 'default'
    opt.LineWidth = 2
    opt.Fontsize = 14
    opt.Legends = {}
    opt.TxtName = {}
    opt.TxtFigX = []
    opt.TxtFigY = []
    opt.TxtFigString = []
    opt.yLines = []
    opt.yLineLabels = {}
    opt.xLines = []
    opt.xLineLabels = {}
    opt.zero_center = false
    opt.parent_folder = [];
    opt.ylim = []  % Added ylim parameter
end

ToolBox = getGlobalToolBox;
params = ToolBox.getParams;

if ~params.saveFigures
    return;
end

f = figure('Visible', 'off');

pbaspect([2.5 1 1]);
box on
hold on

for n = 1:length(y)
    plot(x{n}, y{n}, style{n}, 'Color', color{n}, 'LineWidth', opt.LineWidth)

end

if ~isempty(opt.TxtFigX)

    for n = 1:length(opt.TxtFigX)
        text(opt.TxtFigX(n), opt.TxtFigY(n), opt.TxtFigString{n})
    end

end

if ~isempty(opt.yLines)

    for n = 1:length(opt.yLines)
        % Set common properties
        lineProps = {':', 'LineWidth', opt.LineWidth};

        % Handle label positioning
        if n == length(opt.yLines) && ~isscalar(opt.yLines)
            % Last line gets default vertical alignment
            yline(opt.yLines(n), lineProps{:}, ...
                'Label', opt.yLineLabels{n}, ...
                'LabelVerticalAlignment', 'bottom');
        else
            % Other lines get bottom alignment
            yline(opt.yLines(n), lineProps{:}, ...
                'Label', opt.yLineLabels{n});
        end

    end

end

title(opt.Title)

xlabel(opt.xlabel, 'FontSize', opt.Fontsize);
ylabel(opt.ylabel, 'FontSize', opt.Fontsize);

if ~isempty(opt.Legends)
    legend(opt.Legends)
end

if ~isempty(opt.TxtName)

    for n = 1:length(opt.TxtName)
        plot2txt(x{n}, y{n}, opt.TxtName{n})
    end

end

axis padded
axP = axis;
axis tight
axT = axis;

% Apply custom ylim if provided
if ~isempty(opt.ylim)
    if length(opt.ylim) == 2
        axis([axT(1), axT(2), opt.ylim(1), opt.ylim(2)])
    else
        warning('ylim must be a 2-element vector [ymin ymax]. Using default limits.');
        applyDefaultLimits;
    end
else
    applyDefaultLimits;
end

% Nested function to handle default limits
function applyDefaultLimits
    if opt.zero_center
        axis([axT(1), axT(2), 0, 1.07 * axP(4)])
    else
        axis([axT(1), axT(2), axP(3), axP(4)])
    end
end

set(gca, 'LineWidth', 2)
pbaspect([1.618, 1, 1]);

if ~isempty(opt.parent_folder)
    exportgraphics(gca, fullfile(ToolBox.path_png, opt.parent_folder, ...
        sprintf("%s_%s_graph.png", ToolBox.folder_name, filename)))
    exportgraphics(gca, fullfile(ToolBox.path_eps, opt.parent_folder, ...
        sprintf("%s_%s_graph.eps", ToolBox.folder_name, filename)))
    
end

exportgraphics(gca, fullfile(ToolBox.path_png, ...
    sprintf("%s_%s_graph.png", ToolBox.folder_name, filename)))
exportgraphics(gca, fullfile(ToolBox.path_eps, ...
    sprintf("%s_%s_graph.eps", ToolBox.folder_name, filename)))

end