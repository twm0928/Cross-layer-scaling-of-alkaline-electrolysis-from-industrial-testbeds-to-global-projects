function out = plot_fig3b_m1_m3_mechanism(output_prefix)
%PLOT_FIG3B_M1_M3_MECHANISM Render a mechanism-oriented Fig. 3b candidate.
%   This figure keeps the full 24 h profile but compresses the message into:
%   (i) shared module power input,
%   (ii) stack-current allocation + temperature envelope for M1-M3,
%   (iii) HTO responses for M1-M3,
%   (iv) three summary metrics across M1-M3.

module_root = fileparts(fileparts(mfilename('fullpath')));
data_dir = fullfile(module_root, 'outputs', 'fig3b_scenario_505_saved_results');

if nargin < 1 || isempty(output_prefix)
    output_prefix = fullfile(data_dir, 'Fig3b_M1_M3_mechanism');
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
dt_h = median(diff(t15));

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
topology_colors = [
    45 94 170;
    22 163 74;
    120 120 120
] / 255;
power_color = [0.16 0.41 0.71];
temp_fill = [0.92 0.92 0.92];
temp_line = [0.45 0.45 0.45];
temp_base = 20;
hto_threshold = 2.0;

metrics = struct([]);
for i = 1:numel(mods)
    tag = mods{i};
    T = S.(tag).stack;
    currents = nan(height(T), 4);
    temps = nan(height(T), 4);
    onflag = nan(height(T), 4);
    for s = 1:4
        currents(:, s) = T.(sprintf('stack%d_current_A', s)) / 1000;
        temps(:, s) = T.(sprintf('stack%d_temp_C', s));
        onflag(:, s) = T.(sprintf('stack%d_on', s));
    end
    active = currents > 0.1;
    spread = zeros(size(t15));
    for r = 1:numel(t15)
        idx = active(r, :);
        if any(idx)
            vals = currents(r, idx);
            spread(r) = max(vals) - min(vals);
        end
    end
    power_on = T.power_command_MW > 0.1;
    if any(power_on)
        mean_spread = mean(spread(power_on));
    else
        mean_spread = 0;
    end

    cooler_vars = T.Properties.VariableNames(startsWith(T.Properties.VariableNames, 'cooler'));
    if isempty(cooler_vars)
        cooler_mwh = 0;
    else
        cooler_mw = zeros(height(T), 1);
        for c = 1:numel(cooler_vars)
            cooler_mw = cooler_mw + T.(cooler_vars{c});
        end
        cooler_mwh = sum(cooler_mw) * dt_h;
    end

    H = S.(tag).hto;
    hto_vars = H.Properties.VariableNames(2:end);
    hto_mat = zeros(height(H), numel(hto_vars));
    for j = 1:numel(hto_vars)
        hto_mat(:, j) = H.(hto_vars{j}) * 100;
    end
    max_hto = max(hto_mat, [], 'all');

    metrics(i).mean_spread_kA = mean_spread;
    metrics(i).max_hto_pct = max_hto;
    metrics(i).cooler_mwh = cooler_mwh;
end

fig = figure('Visible', 'off', 'Color', 'w', 'Position', [80 80 1580 980]);
tlo = tiledlayout(4, 3, 'Padding', 'compact', 'TileSpacing', 'compact');
tlo.Units = 'normalized';
tlo.OuterPosition = [0.05 0.07 0.92 0.88];

% Shared power command.
axP = nexttile(tlo, [1 3]);
plot(axP, t15, S.M1.stack.power_command_MW, 'LineWidth', 2.6, 'Color', power_color);
style_axis(axP);
xlim(axP, [0 24]);
xticks(axP, 0:6:24);
ylabel(axP, 'Power (MW)', 'FontName', 'Arial', 'FontSize', 13);
set(axP, 'XTickLabel', []);

% Current allocation + temperature envelope, one panel per topology.
for i = 1:numel(mods)
    tag = mods{i};
    T = S.(tag).stack;
    ax = nexttile(tlo);
    hold(ax, 'on');

    currents = nan(height(T), 4);
    temps = nan(height(T), 4);
    for s = 1:4
        currents(:, s) = T.(sprintf('stack%d_current_A', s)) / 1000;
        temps(:, s) = T.(sprintf('stack%d_temp_C', s));
    end
    temp_min = min(temps, [], 2);
    temp_max = max(temps, [], 2);
    temp_mean = mean(temps, 2);

    yyaxis(ax, 'right');
    patch(ax, [t15; flipud(t15)], [temp_min; flipud(temp_max)], temp_fill, ...
        'FaceAlpha', 0.75, 'EdgeColor', 'none', 'HandleVisibility', 'off');
    plot(ax, t15, temp_mean, '--', 'LineWidth', 1.2, 'Color', temp_line, ...
        'HandleVisibility', 'off');
    ylim(ax, [20 100]);
    yticks(ax, [20 60 100]);
    if i == numel(mods)
        ylabel(ax, 'T (°C)', 'FontName', 'Arial', 'FontSize', 11);
    else
        set(ax, 'YTickLabel', []);
    end
    ax.YColor = [0.35 0.35 0.35];

    yyaxis(ax, 'left');
    for s = 1:4
        plot(ax, t15, currents(:, s), 'LineWidth', 2.0, 'Color', stack_colors(s, :), ...
            'DisplayName', sprintf('S%d', s));
    end
    ylim(ax, [0 15]);
    yticks(ax, [0 5 10 15]);
    if i == 1
        ylabel(ax, 'I (kA)', 'FontName', 'Arial', 'FontSize', 11);
    else
        set(ax, 'YTickLabel', []);
    end
    ax.YColor = [0.15 0.15 0.15];

    style_axis(ax);
    xlim(ax, [0 24]);
    xticks(ax, 0:6:24);
    xlabel(ax, 'Time (h)', 'FontName', 'Arial', 'FontSize', 12);
    title(ax, titles{i}, 'FontName', 'Arial', 'FontSize', 13, 'FontWeight', 'bold');
    text(ax, 0.02, 0.86, sprintf('mean spread = %.2f kA', metrics(i).mean_spread_kA), ...
        'Units', 'normalized', 'FontName', 'Arial', 'FontSize', 10, ...
        'BackgroundColor', 'w', 'Margin', 1.0, 'Color', [0.2 0.2 0.2]);
    if i == 1
        legend(ax, 'Location', 'northwest', 'Box', 'off', 'NumColumns', 4, ...
            'FontName', 'Arial', 'FontSize', 10);
    end
    hold(ax, 'off');
end

% HTO panels.
for i = 1:numel(mods)
    tag = mods{i};
    H = S.(tag).hto;
    ax = nexttile(tlo);
    hold(ax, 'on');
    vars = H.Properties.VariableNames(2:end);
    for j = 1:numel(vars)
        plot(ax, tH, H.(vars{j}) * 100, 'LineWidth', 2.0, ...
            'Color', hto_colors(j, :), 'DisplayName', sprintf('HTO %d', j));
    end
    yline(ax, hto_threshold, '--', 'Color', [0.35 0.35 0.35], 'LineWidth', 1.2, ...
        'DisplayName', 'Threshold');
    hold(ax, 'off');
    style_axis(ax);
    xlim(ax, [0 24]);
    xticks(ax, 0:6:24);
    ylim(ax, [0 2.2]);
    yticks(ax, [0 0.5 1.0 1.5 2.0]);
    xlabel(ax, 'Time (h)', 'FontName', 'Arial', 'FontSize', 12);
    if i == 1
        ylabel(ax, 'HTO (%)', 'FontName', 'Arial', 'FontSize', 11);
    else
        set(ax, 'YTickLabel', []);
    end
    text(ax, 0.02, 0.84, sprintf('max HTO = %.2f%%', metrics(i).max_hto_pct), ...
        'Units', 'normalized', 'FontName', 'Arial', 'FontSize', 10, ...
        'BackgroundColor', 'w', 'Margin', 1.0, 'Color', [0.2 0.2 0.2]);
    legend(ax, 'Location', 'southeast', 'Box', 'off', 'FontName', 'Arial', 'FontSize', 9);
end

% Summary metrics across topologies.
metric_names = {'Mean current spread (kA)', 'Max HTO (%)', 'Cooler duty (MWh d^{-1})'};
metric_values = [
    [metrics.mean_spread_kA];
    [metrics.max_hto_pct];
    [metrics.cooler_mwh]
];

for k = 1:3
    ax = nexttile(tlo);
    hb = bar(ax, 1:3, metric_values(k, :)', 0.62, 'FaceColor', 'flat');
    hb.CData = topology_colors;
    style_axis(ax);
    xlim(ax, [0.4 3.6]);
    xticks(ax, 1:3);
    xticklabels(ax, {'M1','M2','M3'});
    ylabel(ax, metric_names{k}, 'FontName', 'Arial', 'FontSize', 11);
    for i = 1:3
        text(ax, i, metric_values(k, i), sprintf('%.2f', metric_values(k, i)), ...
            'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
            'FontName', 'Arial', 'FontSize', 10);
    end
end

set(findall(fig, '-property', 'FontName'), 'FontName', 'Arial');
drawnow;

png_file = [output_prefix '.png'];
fig_file = [output_prefix '.fig'];
exportgraphics(fig, png_file, 'Resolution', 220);
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
