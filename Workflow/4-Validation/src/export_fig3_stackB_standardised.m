function export_fig3_stackB_standardised()
%EXPORT_FIG3_STACKB_STANDARDISED Export only Fig. 3 with the standardised style.

scriptDir = fileparts(mfilename('fullpath'));
evRoot = fileparts(scriptDir);
outputs = fullfile(evRoot, 'outputs');
outDir = fullfile(outputs, 'si_validation_clean_figures');
if ~exist(outDir, 'dir')
    mkdir(outDir);
end

fullCsv = fullfile(outputs, 'step8_full_statespace_single5MW_validation', ...
    'fangshan_single5MW_full_statespace_validation_profile.csv');
dynamicCsv = fullfile(outputs, 'step7_dynamic_module_validation', ...
    'dynamic_day_2023-11-05_module_validation_profile.csv');

T = readtable(fullCsv);
dynamicT = readtable(dynamicCsv);
T = T(T.time_h > 0, :);
dynamicT = dynamicT(dynamicT.time_h > 0, :);

fig = figure('Visible', 'off', 'Color', 'w', 'Units', 'centimeters', ...
    'Position', [2 2 14.5 8.4], 'PaperUnits', 'centimeters', ...
    'PaperPosition', [0 0 14.5 8.4]);
ax = axes(fig);
hold(ax, 'on');

hMeasured = plot(ax, T.time_h, T.H2_rate_measured_Nm3h, '-', ...
    'Color', [0.10 0.45 0.20], 'LineWidth', 2.0);
hReplay = plot(ax, dynamicT.time_h, dynamicT.predicted_H2_rate_Nm3h, '--', ...
    'Color', [0.12 0.42 0.74], 'LineWidth', 2.0);
hState = plot(ax, T.time_h, T.H2_rate_model_Nm3h, '-', ...
    'Color', [0.78 0.18 0.16], 'LineWidth', 2.0);

xlabel(ax, 'Time (h)');
ylabel(ax, 'Hydrogen production rate (Nm^3 h^{-1})');
xlim(ax, [0 24]);
ylim(ax, [0 1200]);

style_axes_local(ax);
lgd = legend(ax, [hMeasured hReplay hState], ...
    {'Measured', 'Interface-only replay', 'Full state-space model'}, ...
    'Location', 'southoutside', 'Orientation', 'horizontal', 'Box', 'off');
style_legend_local(lgd, 10);
ax.Position = [0.10 0.28 0.84 0.62];

pngPath = fullfile(outDir, 'Fig3_stackB_overlay_export.png');
try
    exportgraphics(fig, pngPath, 'Resolution', 600);
catch
    print(fig, pngPath, '-dpng', '-r600');
end
close(fig);

disp(pngPath);
end

function style_axes_local(ax)
set(ax, 'FontName', 'Times New Roman', 'FontSize', 10, 'LineWidth', 1.1, ...
    'TickDir', 'out', 'Box', 'off', 'Layer', 'top');
ax.XLabel.FontName = 'Times New Roman';
ax.YLabel.FontName = 'Times New Roman';
ax.XLabel.FontSize = 12;
ax.YLabel.FontSize = 12;
ax.XLabel.FontWeight = 'normal';
ax.YLabel.FontWeight = 'normal';
ax.Title.String = '';
ax.XColor = [0 0 0];
ax.YColor = [0 0 0];
grid(ax, 'off');
ax.Units = 'normalized';
if numel(ax.Position) == 4
    ax.Position(1) = max(ax.Position(1), 0.11);
    ax.Position(2) = max(ax.Position(2), 0.16);
end
end

function style_legend_local(lgd, fontSize)
lgd.FontName = 'Times New Roman';
lgd.FontSize = fontSize;
lgd.Box = 'off';
end
