function out = plot_fig3b_m1_m3_triptych(output_prefix)
%PLOT_FIG3B_M1_M3_TRIPTYCH Build a cleaner 24 h module-mechanism figure.
%   Uses scenario 505 saved-result exports for M1-M3 and renders a
%   manuscript-style triptych:
%     - shared 24 h module power command
%     - four stack rows (Stack 1-4), each comparing M1/M2/M3
%     - one HTO row comparing M1/M2/M3

module_root = fileparts(fileparts(mfilename('fullpath')));
data_dir = fullfile(module_root, 'outputs', 'fig3b_scenario_505_saved_results');

if nargin < 1 || isempty(output_prefix)
    output_prefix = fullfile(data_dir, 'Fig3b_M1_M3_triptych');
end

mods = {'M1','M2','M3'};
titles = {'M1 (1-in-1)', 'M2 (2-in-1)', 'M3 (4-in-1)'};
S = struct();
for i = 1:numel(mods)
    tag = mods{i};
    S.(tag).stack = readtable(fullfile(data_dir, sprintf('%s_scenario_505_stack_15min.csv', tag)));
    S.(tag).hto = readtable(fullfile(data_dir, sprintf('%s_scenario_505_hto_15min.csv', tag)));
end

t15 = S.M1.stack.time_h;
tH = S.M1.hto.time_h;

stack_colors = [
    230 171 45;
    38 166 154;
    52 120 191;
    124 132 142
] / 255;
hto_colors = [
    52 120 191;
    230 171 45;
    38 166 154;
    124 132 142
] / 255;
power_color = [0.16 0.41 0.71];
temp_base = 20;

fig = figure('Visible', 'off', 'Color', 'w', 'Position', [80 80 1550 980]);
tlo = tiledlayout(6, 3, 'Padding', 'compact', 'TileSpacing', 'compact');
tlo.Units = 'normalized';
tlo.OuterPosition = [0.05 0.07 0.92 0.88];

% Shared power-command panel.
axP = nexttile(tlo, [1 3]);
plot(axP, t15, S.M1.stack.power_command_MW, 'LineWidth', 2.8, 'Color', power_color);
style_axis(axP);
xlim(axP, [0 24]);
ylabel(axP, 'Power (MW)', 'FontName', 'Arial', 'FontSize', 13);
set(axP, 'XTickLabel', []);

% Four stack rows, three columns (M1-M3).
for s = 1:4
    for m = 1:3
        tag = mods{m};
        T = S.(tag).stack;
        ax = nexttile(tlo);
        hold(ax, 'on');

        temp = T.(sprintf('stack%d_temp_C', s));
        curr = T.(sprintf('stack%d_current_A', s)) / 1000;

        yyaxis(ax, 'right');
        patch(ax, [t15; flipud(t15)], [temp_base * ones(size(temp)); flipud(temp)], ...
            0.80 * [1 1 1] + 0.20 * stack_colors(s, :), ...
            'FaceAlpha', 0.35, 'EdgeColor', 'none', 'HandleVisibility', 'off');
        ylim(ax, [20 100]);
        yticks(ax, [20 60 100]);
        ax.YColor = stack_colors(s, :);
        if m == 3
            ylabel(ax, 'T (°C)', 'FontName', 'Arial', 'FontSize', 11);
        else
            set(ax, 'YTickLabel', []);
        end

        yyaxis(ax, 'left');
        plot(ax, t15, curr, 'LineWidth', 2.8, 'Color', stack_colors(s, :));
        ylim(ax, [0 15]);
        yticks(ax, [0 5 10 15]);
        ax.YColor = stack_colors(s, :);
        if m == 1
            ylabel(ax, sprintf('S%d\nI (kA)', s), 'FontName', 'Arial', 'FontSize', 11);
        else
            set(ax, 'YTickLabel', []);
        end

        style_axis(ax);
        xlim(ax, [0 24]);
        if s < 4
            set(ax, 'XTickLabel', []);
        else
            xlabel(ax, 'Time (h)', 'FontName', 'Arial', 'FontSize', 12);
        end
        if s == 1
            title(ax, titles{m}, 'FontName', 'Arial', 'FontSize', 13, 'FontWeight', 'bold');
        end
        hold(ax, 'off');
    end
end

% HTO row.
for m = 1:3
    tag = mods{m};
    H = S.(tag).hto;
    ax = nexttile(tlo);
    hold(ax, 'on');
    vars = H.Properties.VariableNames(2:end);
    for j = 1:numel(vars)
        plot(ax, tH, H.(vars{j}) * 100, 'LineWidth', 2.0, ...
            'Color', hto_colors(j, :), 'DisplayName', sprintf('HTO %d', j));
    end
    hold(ax, 'off');
    style_axis(ax);
    xlim(ax, [0 24]);
    ylim(ax, [0 2]);
    yticks(ax, [0 0.5 1 1.5 2]);
    xlabel(ax, 'Time (h)', 'FontName', 'Arial', 'FontSize', 12);
    if m == 1
        ylabel(ax, 'HTO (%)', 'FontName', 'Arial', 'FontSize', 12);
    else
        set(ax, 'YTickLabel', []);
    end
    legend(ax, 'Location', 'northeast', 'Box', 'off', 'FontName', 'Arial', 'FontSize', 10);
end

set(findall(fig, '-property', 'FontName'), 'FontName', 'Arial');
drawnow;

png_file = [output_prefix '.png'];
fig_file = [output_prefix '.fig'];
exportgraphics(fig, png_file, 'Resolution', 300);
savefig(fig, fig_file);
close(fig);

out = struct('png_file', png_file, 'fig_file', fig_file);
end

function style_axis(ax)
set(ax, 'Box', 'on', ...
    'LineWidth', 1.0, ...
    'FontName', 'Arial', ...
    'FontSize', 10, ...
    'TickDir', 'out', ...
    'XMinorTick', 'off', ...
    'YMinorTick', 'off', ...
    'SortMethod', 'childorder');
grid(ax, 'off');
end
