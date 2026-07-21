function outputs = plot_temperature_splitviolin_rebased(input_csv, output_tag, T_ref_C)
%PLOT_TEMPERATURE_SPLITVIOLIN_REBASED
% Prototype for rebased temperature metrics:
%   left half  = mean stack outlet temperature relative to T_ref_C
%   right half = mean inter-stack temperature spread

if nargin < 1 || isempty(input_csv)
    src_dir = fileparts(mfilename('fullpath'));
    module_root = fileparts(src_dir);
    input_csv = fullfile(module_root, 'outputs', 'fig3b_metric_candidates_970', ...
        'fig3b_candidate_metrics_970_scenario_table.csv');
end
if nargin < 2 || isempty(output_tag)
    output_tag = 'fig3b_temperature_splitviolin_rebased';
end
if nargin < 3 || isempty(T_ref_C)
    T_ref_C = 90;
end

src_dir = fileparts(mfilename('fullpath'));
module_root = fileparts(src_dir);
output_dir = fullfile(module_root, 'outputs', output_tag);
if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end

T = readtable(input_csv);
T.temp_level_rel_C = T.temp_mean_C - T_ref_C;

topology_ids = 1:7;
topology_labels = compose("M%d", topology_ids);
colors = [
    244 172 64
    236 196 78
    0 157 122
    60 181 167
    66 133 244
    111 168 220
    150 150 150] / 255;

f = figure('Visible', 'off', 'Position', [120 120 1180 620], 'Color', 'w');
ax = axes(f);
hold(ax, 'on');

for k = 1:numel(topology_ids)
    topo = topology_ids(k);
    level_vals = T.temp_level_rel_C(T.topology_id == topo);
    spread_vals = T.temp_spread_mean_C(T.topology_id == topo);
    level_vals = level_vals(isfinite(level_vals));
    spread_vals = spread_vals(isfinite(spread_vals));

    draw_split_violin(ax, k, level_vals, spread_vals, colors(k, :), 0.28);
end

yline(ax, 0, '--', 'Color', [0.35 0.35 0.35], 'LineWidth', 1.2, 'HandleVisibility', 'off');

ax.FontName = 'Arial';
ax.FontSize = 13;
ax.LineWidth = 1.0;
ax.Box = 'on';
ax.XGrid = 'off';
ax.YGrid = 'on';
ax.GridAlpha = 0.14;
ax.GridColor = [0.2 0.2 0.2];
ax.XLim = [0.45 numel(topology_ids) + 0.55];
ax.XTick = 1:numel(topology_ids);
ax.XTickLabel = topology_labels;
ax.YLim = [-8 20];

xlabel(ax, 'Module topology', 'FontName', 'Arial', 'FontSize', 15);
ylabel(ax, sprintf('Thermal metrics relative to T_{ref} = %d °C', T_ref_C), ...
    'FontName', 'Arial', 'FontSize', 15);

text(ax, 0.65, 19.1, 'Left half: mean stack temperature - T_{ref}', ...
    'FontName', 'Arial', 'FontSize', 13, 'Color', [0.15 0.15 0.15]);
text(ax, 0.65, 17.4, 'Right half: mean inter-stack temperature spread', ...
    'FontName', 'Arial', 'FontSize', 13, 'Color', [0.15 0.15 0.15]);
text(ax, 0.65, 15.7, 'Dashed line: T_{ref} baseline', ...
    'FontName', 'Arial', 'FontSize', 13, 'Color', [0.15 0.15 0.15]);

title(ax, 'Rebased temperature split-violin prototype (970 scenarios)', ...
    'FontName', 'Arial', 'FontSize', 18, 'FontWeight', 'bold');

png = fullfile(output_dir, 'temperature_splitviolin_rebased.png');
fig = fullfile(output_dir, 'temperature_splitviolin_rebased.fig');
exportgraphics(f, png, 'Resolution', 300);
savefig(f, fig);
close(f);

outputs = struct();
outputs.figure_png = png;
outputs.figure_fig = fig;
outputs.reference_temperature_C = T_ref_C;
save(fullfile(output_dir, 'temperature_splitviolin_rebased_outputs.mat'), 'outputs');
end

function draw_split_violin(ax, x0, left_vals, right_vals, color, half_width)
if ~isempty(left_vals)
    [fL, yL] = ksdensity(left_vals);
    if max(fL) > 0
        fL = fL ./ max(fL) * half_width;
        patch(ax, [x0 - fL fliplr(x0 * ones(size(yL)))], [yL fliplr(yL)], color, ...
            'FaceAlpha', 0.18, 'EdgeColor', color, 'LineWidth', 1.2, 'HandleVisibility', 'off');
        plot(ax, x0 - fL, yL, '-', 'Color', color, 'LineWidth', 1.6, 'HandleVisibility', 'off');
        draw_iqr(ax, x0 - 0.07, left_vals, color);
    end
end

if ~isempty(right_vals)
    [fR, yR] = ksdensity(right_vals);
    if max(fR) > 0
        fR = fR ./ max(fR) * half_width;
        patch(ax, [x0 * ones(size(yR)) fliplr(x0 + fR)], [yR fliplr(yR)], color, ...
            'FaceAlpha', 0.18, 'EdgeColor', color, 'LineWidth', 1.2, 'HandleVisibility', 'off');
        plot(ax, x0 + fR, yR, '-', 'Color', color, 'LineWidth', 1.6, 'HandleVisibility', 'off');
        draw_iqr(ax, x0 + 0.07, right_vals, color);
    end
end

plot(ax, [x0 x0], ylim(ax), '-', 'Color', [0.82 0.82 0.82], 'LineWidth', 0.7, 'HandleVisibility', 'off');
end

function draw_iqr(ax, x0, vals, color)
q25 = prctile(vals, 25);
q50 = median(vals, 'omitnan');
q75 = prctile(vals, 75);
plot(ax, [x0 x0], [q25 q75], '-', 'Color', color, 'LineWidth', 4.0, 'HandleVisibility', 'off');
plot(ax, x0, q50, 'o', 'MarkerSize', 6.5, 'MarkerFaceColor', color, ...
    'MarkerEdgeColor', [0.15 0.15 0.15], 'LineWidth', 0.8, 'HandleVisibility', 'off');
end
