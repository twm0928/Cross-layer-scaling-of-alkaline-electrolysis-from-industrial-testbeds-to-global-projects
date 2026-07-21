function outputs = plot_fig3b_three_metric_charts(input_csv, output_tag, T_ref_C, hto_limit_pct)
%PLOT_FIG3B_THREE_METRIC_CHARTS
% Export three standalone manuscript-style charts for Fig. 3b:
%   1) current split violin
%   2) temperature split violin
%   3) HTO safety occupancy band-share chart

if nargin < 1 || isempty(input_csv)
    src_dir = fileparts(mfilename('fullpath'));
    module_root = fileparts(src_dir);
    input_csv = fullfile(module_root, 'outputs', 'fig3b_metric_candidates_970', ...
        'fig3b_candidate_metrics_970_scenario_table.csv');
end
if nargin < 2 || isempty(output_tag)
    output_tag = 'fig3b_three_metric_charts';
end
if nargin < 3 || isempty(T_ref_C)
    T_ref_C = 90;
end
if nargin < 4 || isempty(hto_limit_pct)
    hto_limit_pct = 4;
end

src_dir = fileparts(mfilename('fullpath'));
module_root = fileparts(src_dir);
output_dir = fullfile(module_root, 'outputs', output_tag);
if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end

T = readtable(input_csv);
T.temp_level_rel_C = T.temp_mean_C - T_ref_C;
T.hto_limit_util_pu = T.hto_worst_pct / hto_limit_pct;

topology_ids = 1:7;
topology_labels = compose("M%d", topology_ids);
colors = [
    243 163  50   % M1
    243 163  50   % M2
    243 163  50   % M3
      1 138 103   % M4
      1 138 103   % M5
     24 104 178   % M6
    120 120 120] / 255;  % M7

current_files = export_current_split_violin(T, topology_ids, topology_labels, colors, output_dir);
temperature_files = export_temperature_split_violin(T, topology_ids, topology_labels, colors, output_dir);
[hto_files, hto_fraction_csv, hto_count_csv] = export_hto_bandshare(T, topology_ids, topology_labels, hto_limit_pct, output_dir);

outputs = struct();
outputs.current_png = current_files.png;
outputs.current_fig = current_files.fig;
outputs.current_svg = current_files.svg;
outputs.temperature_png = temperature_files.png;
outputs.temperature_fig = temperature_files.fig;
outputs.temperature_svg = temperature_files.svg;
outputs.hto_png = hto_files.png;
outputs.hto_fig = hto_files.fig;
outputs.hto_svg = hto_files.svg;
outputs.hto_fraction_csv = hto_fraction_csv;
outputs.hto_count_csv = hto_count_csv;
outputs.reference_temperature_C = T_ref_C;
outputs.hto_limit_pct = hto_limit_pct;
save(fullfile(output_dir, 'fig3b_three_metric_charts_outputs.mat'), 'outputs');
end

function files = export_current_split_violin(T, topology_ids, topology_labels, colors, output_dir)
f = figure('Visible', 'off', 'Position', [80 80 980 560], 'Color', 'w');
ax = axes(f);
hold(ax, 'on');

for k = 1:numel(topology_ids)
    topo = topology_ids(k);
    left_vals = T.current_mean_pu(T.topology_id == topo);
    right_vals = T.current_spread_mean_pu(T.topology_id == topo);
    draw_split_violin(ax, k, left_vals, right_vals, colors(k, :), 0.26, [0 1], [0 1]);
end

style_common_axis(ax, topology_labels);
ax.YLim = [0 1.0];
ax.YTick = 0:0.2:1.0;
xlabel(ax, 'Module topology', 'FontName', 'Arial', 'FontSize', 20);
ylabel(ax, 'Current metrics (p.u.)', 'FontName', 'Arial', 'FontSize', 20);
text(ax, 0.47, 0.95, 'left: mean stack current utilisation', ...
    'Units', 'normalized', 'FontName', 'Arial', 'FontSize', 18, 'Color', [0.2 0.2 0.2]);
text(ax, 0.47, 0.89, 'right: mean inter-stack current spread', ...
    'Units', 'normalized', 'FontName', 'Arial', 'FontSize', 18, 'Color', [0.2 0.2 0.2]);

files = struct();
files.png = fullfile(output_dir, 'fig3b_current_split_violin.png');
files.fig = fullfile(output_dir, 'fig3b_current_split_violin.fig');
files.svg = fullfile(output_dir, 'fig3b_current_split_violin.svg');
exportgraphics(f, files.png, 'Resolution', 300);
export_svg_compat(f, files.svg);
savefig(f, files.fig);
close(f);
end

function files = export_temperature_split_violin(T, topology_ids, topology_labels, colors, output_dir)
f = figure('Visible', 'off', 'Position', [80 80 980 560], 'Color', 'w');
ax = axes(f);
hold(ax, 'on');

for k = 1:numel(topology_ids)
    topo = topology_ids(k);
    left_vals = T.temp_level_rel_C(T.topology_id == topo);
    right_vals = T.temp_spread_mean_C(T.topology_id == topo);
    draw_split_violin(ax, k, left_vals, right_vals, colors(k, :), 0.26, [-8 12], [0 12]);
end

yline(ax, 0, '--', 'Color', [0.45 0.45 0.45], 'LineWidth', 1.1, 'HandleVisibility', 'off');
style_common_axis(ax, topology_labels);
ax.YLim = [-8 12];
ax.YTick = -8:4:12;
xlabel(ax, 'Module topology', 'FontName', 'Arial', 'FontSize', 20);
ylabel(ax, 'Temperature metrics (°C)', 'FontName', 'Arial', 'FontSize', 20);
text(ax, 0.45, 0.95, 'left: mean stack temperature - 90 °C', ...
    'Units', 'normalized', 'FontName', 'Arial', 'FontSize', 18, 'Color', [0.2 0.2 0.2]);
text(ax, 0.45, 0.89, 'right: mean inter-stack temperature spread', ...
    'Units', 'normalized', 'FontName', 'Arial', 'FontSize', 18, 'Color', [0.2 0.2 0.2]);

files = struct();
files.png = fullfile(output_dir, 'fig3b_temperature_split_violin.png');
files.fig = fullfile(output_dir, 'fig3b_temperature_split_violin.fig');
files.svg = fullfile(output_dir, 'fig3b_temperature_split_violin.svg');
exportgraphics(f, files.png, 'Resolution', 300);
export_svg_compat(f, files.svg);
savefig(f, files.fig);
close(f);
end

function [files, fraction_csv, count_csv] = export_hto_bandshare(T, topology_ids, topology_labels, hto_limit_pct, output_dir)
[fraction_table, count_table] = build_bandshare_tables(T, topology_ids);
fraction_csv = fullfile(output_dir, 'fig3b_hto_bandshare_fraction.csv');
count_csv = fullfile(output_dir, 'fig3b_hto_bandshare_count.csv');
writetable(fraction_table, fraction_csv);
writetable(count_table, count_csv);

f = figure('Visible', 'off', 'Position', [80 80 1080 560], 'Color', 'w');
ax = axes(f);
hold(ax, 'on');

fractions = [
    fraction_table.frac_0_25, ...
    fraction_table.frac_25_50, ...
    fraction_table.frac_50_75, ...
    fraction_table.frac_75_100, ...
    fraction_table.frac_gt_100];
palette = [
    222 236 255
    160 205 248
     95 156 233
    255 205 112
    228 104  96] / 255;
bar_half_h = 0.34;

legend_handles = gobjects(1, 5);
for c = 1:5
    legend_handles(c) = patch(ax, nan, nan, palette(c, :), 'EdgeColor', 'none');
end

for r = 1:height(fraction_table)
    x_left = 0;
    for c = 1:5
        w = fractions(r, c);
        patch(ax, [x_left x_left + w x_left + w x_left], ...
            [r - bar_half_h r - bar_half_h r + bar_half_h r + bar_half_h], ...
            palette(c, :), 'EdgeColor', 'none', 'HandleVisibility', 'off');
        x_left = x_left + w;
    end
    rectangle(ax, 'Position', [0, r - bar_half_h, 1.0, 2 * bar_half_h], ...
        'EdgeColor', [0.80 0.80 0.80], 'LineWidth', 0.8);
end

for r = 1:height(fraction_table)
    vals = fractions(r, :);
    cum_left = 0;
    for c = 1:numel(vals)
        w = vals(c);
        if w >= 0.075
            text(ax, cum_left + w / 2, r, sprintf('%.0f%%', 100 * w), ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
                'FontName', 'Arial', 'FontSize', 11, 'Color', [0.15 0.15 0.15], ...
                'FontWeight', 'bold');
        end
        cum_left = cum_left + w;
    end

    risky_50 = vals(3) + vals(4) + vals(5);
    text(ax, 1.015, r, sprintf('>=50%%: %.1f%%', 100 * risky_50), ...
        'HorizontalAlignment', 'left', 'VerticalAlignment', 'middle', ...
        'FontName', 'Arial', 'FontSize', 11, 'Color', [0.15 0.15 0.15]);
end

ax.FontName = 'Arial';
ax.FontSize = 18;
ax.LineWidth = 1.0;
ax.Box = 'on';
ax.XGrid = 'on';
ax.YGrid = 'off';
ax.GridAlpha = 0.14;
ax.GridColor = [0.2 0.2 0.2];
ax.XLim = [0 1.18];
ax.XTick = 0:0.2:1.0;
ax.XTickLabel = compose('%.0f%%', 100 * (0:0.2:1.0));
ax.YTick = 1:numel(topology_labels);
ax.YTickLabel = topology_labels;
ax.YDir = 'reverse';

xlabel(ax, 'Share of scenario-days', 'FontName', 'Arial', 'FontSize', 16);
ylabel(ax, 'Module topology', 'FontName', 'Arial', 'FontSize', 16);
legend(ax, legend_handles, {'0-25%', '25-50%', '50-75%', '75-100%', '>100%'}, ...
    'Location', 'southoutside', 'Orientation', 'horizontal', ...
    'Box', 'off', 'FontName', 'Arial', 'FontSize', 11);
text(ax, 0.62, 0.95, sprintf('banded by worst daily HTO / %.1f%% limit', hto_limit_pct), ...
    'Units', 'normalized', 'FontName', 'Arial', 'FontSize', 11, 'Color', [0.2 0.2 0.2]);

files = struct();
files.png = fullfile(output_dir, 'fig3b_hto_bandshare.png');
files.fig = fullfile(output_dir, 'fig3b_hto_bandshare.fig');
files.svg = fullfile(output_dir, 'fig3b_hto_bandshare.svg');
exportgraphics(f, files.png, 'Resolution', 300);
export_svg_compat(f, files.svg);
savefig(f, files.fig);
close(f);
end

function export_svg_compat(fig_handle, svg_path)
set(fig_handle, 'Renderer', 'painters');
print(fig_handle, svg_path, '-dsvg');
end

function style_common_axis(ax, topology_labels)
ax.FontName = 'Arial';
ax.FontSize = 13;
ax.LineWidth = 1.0;
ax.Box = 'on';
ax.XGrid = 'off';
ax.YGrid = 'on';
ax.GridAlpha = 0.14;
ax.GridColor = [0.2 0.2 0.2];
ax.XLim = [0.45 numel(topology_labels) + 0.55];
ax.XTick = 1:numel(topology_labels);
ax.XTickLabel = topology_labels;
end

function draw_split_violin(ax, x0, left_vals, right_vals, color, half_width, left_support, right_support)
left_vals = left_vals(isfinite(left_vals));
right_vals = right_vals(isfinite(right_vals));

if ~isempty(left_vals)
    [fL, yL] = bounded_density(left_vals, left_support);
    if ~isempty(fL) && max(fL) > 0
        fL = fL ./ max(fL) * half_width;
        patch(ax, [x0 - fL fliplr(x0 * ones(size(yL)))], [yL fliplr(yL)], color, ...
            'FaceAlpha', 0.20, 'EdgeColor', color, 'LineWidth', 1.2, 'HandleVisibility', 'off');
        plot(ax, x0 - fL, yL, '-', 'Color', color, 'LineWidth', 1.8, 'HandleVisibility', 'off');
        draw_iqr(ax, x0 - 0.07, left_vals, color);
    end
end

if ~isempty(right_vals)
    [fR, yR] = bounded_density(right_vals, right_support);
    if ~isempty(fR) && max(fR) > 0
        fR = fR ./ max(fR) * half_width;
        patch(ax, [x0 * ones(size(yR)) fliplr(x0 + fR)], [yR fliplr(yR)], color, ...
            'FaceAlpha', 0.20, 'EdgeColor', color, 'LineWidth', 1.2, 'HandleVisibility', 'off');
        plot(ax, x0 + fR, yR, '-', 'Color', color, 'LineWidth', 1.8, 'HandleVisibility', 'off');
        draw_iqr(ax, x0 + 0.07, right_vals, color);
    end
end

plot(ax, [x0 x0], ylim(ax), '-', 'Color', [0.82 0.82 0.82], 'LineWidth', 0.7, 'HandleVisibility', 'off');
end

function [f, y] = bounded_density(vals, support_range)
vals = vals(isfinite(vals));
vals = min(max(vals, support_range(1)), support_range(2));

if isempty(vals)
    f = [];
    y = [];
    return;
end

support_span = support_range(2) - support_range(1);
vmin = min(vals);
vmax = max(vals);

if vmax - vmin < max(1e-6, 0.002 * support_span)
    mu = median(vals, 'omitnan');
    local_span = max(0.03 * support_span, 1e-3);
    y = linspace(max(support_range(1), mu - local_span), ...
                 min(support_range(2), mu + local_span), 81);
    sigma = max(local_span / 3.0, 1e-4);
    f = exp(-0.5 * ((y - mu) / sigma).^2);
    return;
end

y = linspace(support_range(1), support_range(2), 256);
try
    [f, y] = ksdensity(vals, y, 'Support', support_range, 'BoundaryCorrection', 'reflection');
catch
    [f, y] = ksdensity(vals, y);
end
f(~isfinite(f)) = 0;
f = max(f, 0);
end

function draw_iqr(ax, x0, vals, color)
q25 = prctile(vals, 25);
q50 = median(vals, 'omitnan');
q75 = prctile(vals, 75);
plot(ax, [x0 x0], [q25 q75], '-', 'Color', color, 'LineWidth', 4.0, 'HandleVisibility', 'off');
plot(ax, x0, q50, 'o', 'MarkerSize', 6.5, 'MarkerFaceColor', color, ...
    'MarkerEdgeColor', [0.15 0.15 0.15], 'LineWidth', 0.8, 'HandleVisibility', 'off');
end

function [fraction_table, count_table] = build_bandshare_tables(T, topology_ids)
bands = [0 0.25 0.5 0.75 1.0 inf];

frac_rows = cell(numel(topology_ids), 8);
count_rows = cell(numel(topology_ids), 8);
for k = 1:numel(topology_ids)
    topo = topology_ids(k);
    vals = T.hto_limit_util_pu(T.topology_id == topo);
    vals = vals(isfinite(vals));
    n = numel(vals);

    counts = zeros(1, 5);
    for b = 1:5
        counts(b) = sum(vals >= bands(b) & vals < bands(b + 1));
    end
    fracs = counts / n;

    frac_rows(k, :) = {topo, sprintf('M%d', topo), n, fracs(1), fracs(2), fracs(3), fracs(4), fracs(5)};
    count_rows(k, :) = {topo, sprintf('M%d', topo), n, counts(1), counts(2), counts(3), counts(4), counts(5)};
end

fraction_table = cell2table(frac_rows, 'VariableNames', ...
    {'topology_id', 'topology_label', 'scenario_count', 'frac_0_25', 'frac_25_50', 'frac_50_75', 'frac_75_100', 'frac_gt_100'});
count_table = cell2table(count_rows, 'VariableNames', ...
    {'topology_id', 'topology_label', 'scenario_count', 'count_0_25', 'count_25_50', 'count_50_75', 'count_75_100', 'count_gt_100'});
end
