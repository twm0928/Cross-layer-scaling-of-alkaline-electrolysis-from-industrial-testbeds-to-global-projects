function outputs = plot_hto_limit_bars(input_csv, output_tag, hto_limit_pct)
%PLOT_HTO_LIMIT_BARS
% Plot non-violin prototypes for HTO safety utilisation:
%   1) progress-style bar chart using median / P95 / max occupancy
%   2) stacked count chart of scenario-days by occupancy band

if nargin < 1 || isempty(input_csv)
    src_dir = fileparts(mfilename('fullpath'));
    module_root = fileparts(src_dir);
    input_csv = fullfile(module_root, 'outputs', 'fig3b_metric_candidates_970', ...
        'fig3b_candidate_metrics_970_scenario_table.csv');
end
if nargin < 2 || isempty(output_tag)
    output_tag = 'fig3b_hto_limit_bars';
end
if nargin < 3 || isempty(hto_limit_pct)
    hto_limit_pct = 4;
end

src_dir = fileparts(mfilename('fullpath'));
module_root = fileparts(src_dir);
output_dir = fullfile(module_root, 'outputs', output_tag);
if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end

T = readtable(input_csv);
T.hto_limit_util_pu = T.hto_worst_pct / hto_limit_pct;

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

summary = summarise_hto_limit(T, topology_ids);
writetable(summary, fullfile(output_dir, 'hto_limit_summary.csv'));

f = figure('Visible', 'off', 'Position', [90 90 1460 820], 'Color', 'w');
tlo = tiledlayout(f, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

ax1 = nexttile(tlo, 1);
plot_progress_style(ax1, summary, topology_labels, colors);
title(ax1, 'HTO limit occupancy (progress-style summary)', ...
    'FontName', 'Arial', 'FontSize', 18, 'FontWeight', 'bold');

ax2 = nexttile(tlo, 2);
plot_count_style(ax2, summary, topology_labels);
title(ax2, 'Scenario-day count by HTO limit-occupancy band', ...
    'FontName', 'Arial', 'FontSize', 18, 'FontWeight', 'bold');

annotation(f, 'textbox', [0.08 0.95 0.84 0.035], ...
    'String', sprintf('HTO reformulated as worst daily separator-side impurity / limit (limit = %.1f%%)', hto_limit_pct), ...
    'FontName', 'Arial', 'FontSize', 17, 'FontWeight', 'bold', ...
    'LineStyle', 'none', 'HorizontalAlignment', 'center');

png = fullfile(output_dir, 'hto_limit_bars.png');
fig = fullfile(output_dir, 'hto_limit_bars.fig');
exportgraphics(f, png, 'Resolution', 300);
savefig(f, fig);
close(f);

outputs = struct();
outputs.figure_png = png;
outputs.figure_fig = fig;
outputs.summary_csv = fullfile(output_dir, 'hto_limit_summary.csv');
save(fullfile(output_dir, 'hto_limit_bars_outputs.mat'), 'outputs');
end

function summary = summarise_hto_limit(T, topology_ids)
rows = cell(numel(topology_ids), 12);
bands = [0 0.25 0.5 0.75 1.0 inf];

for k = 1:numel(topology_ids)
    topo = topology_ids(k);
    vals = T.hto_limit_util_pu(T.topology_id == topo);
    vals = vals(isfinite(vals));

    counts = zeros(1, 5);
    for b = 1:5
        counts(b) = sum(vals >= bands(b) & vals < bands(b + 1));
    end
    counts(end) = counts(end) + sum(vals == inf); %#ok<AGROW>

    rows(k, :) = {
        topo, sprintf('M%d', topo), numel(vals), ...
        median(vals, 'omitnan'), prctile(vals, 95), max(vals), ...
        counts(1), counts(2), counts(3), counts(4), counts(5), ...
        mean(vals >= 0.75)};
end

summary = cell2table(rows, 'VariableNames', {
    'topology_id', 'topology_label', 'scenario_count', ...
    'median_util_pu', 'p95_util_pu', 'max_util_pu', ...
    'count_0_25', 'count_25_50', 'count_50_75', 'count_75_100', 'count_gt_100', ...
    'frac_ge_75'});
end

function plot_progress_style(ax, S, labels, colors)
hold(ax, 'on');
n = height(S);
y = n:-1:1;

for i = 1:n
    bg = rectangle(ax, 'Position', [0, y(i) - 0.30, 1.00, 0.60], ...
        'FaceColor', [0.95 0.95 0.95], 'EdgeColor', [0.82 0.82 0.82], ...
        'LineWidth', 1.0);
    %#ok<NASGU>

    fill_w = min(S.median_util_pu(i), 1.0);
    patch(ax, [0 fill_w fill_w 0], [y(i)-0.30 y(i)-0.30 y(i)+0.30 y(i)+0.30], colors(i, :), ...
        'EdgeColor', 'none', 'HandleVisibility', 'off');

    p95x = min(S.p95_util_pu(i), 1.05);
    maxx = min(S.max_util_pu(i), 1.05);

    plot(ax, [p95x p95x], [y(i) - 0.36, y(i) + 0.36], '-', ...
        'Color', [0.2 0.2 0.2], 'LineWidth', 2.2, 'HandleVisibility', 'off');
    plot(ax, maxx, y(i), 'o', ...
        'MarkerSize', 7.5, ...
        'MarkerFaceColor', [1 1 1], ...
        'MarkerEdgeColor', [0.15 0.15 0.15], ...
        'LineWidth', 1.2, ...
        'HandleVisibility', 'off');

    text(ax, -0.05, y(i), labels(i), ...
        'HorizontalAlignment', 'right', 'VerticalAlignment', 'middle', ...
        'FontName', 'Arial', 'FontSize', 13, 'FontWeight', 'bold');
    text(ax, 1.085, y(i), sprintf('med %.2f | P95 %.2f | max %.2f', ...
        S.median_util_pu(i), S.p95_util_pu(i), S.max_util_pu(i)), ...
        'HorizontalAlignment', 'left', 'VerticalAlignment', 'middle', ...
        'FontName', 'Arial', 'FontSize', 11);
end

xline(ax, 0.25, ':', 'Color', [0.65 0.65 0.65], 'LineWidth', 1.0, 'HandleVisibility', 'off');
xline(ax, 0.50, ':', 'Color', [0.65 0.65 0.65], 'LineWidth', 1.0, 'HandleVisibility', 'off');
xline(ax, 0.75, ':', 'Color', [0.65 0.65 0.65], 'LineWidth', 1.0, 'HandleVisibility', 'off');
xline(ax, 1.00, '--', 'Color', [0.75 0.15 0.15], 'LineWidth', 1.6, 'HandleVisibility', 'off');

text(ax, 0.25, n + 0.7, '25%', 'FontName', 'Arial', 'FontSize', 11, 'HorizontalAlignment', 'center');
text(ax, 0.50, n + 0.7, '50%', 'FontName', 'Arial', 'FontSize', 11, 'HorizontalAlignment', 'center');
text(ax, 0.75, n + 0.7, '75%', 'FontName', 'Arial', 'FontSize', 11, 'HorizontalAlignment', 'center');
text(ax, 1.00, n + 0.7, 'limit', 'FontName', 'Arial', 'FontSize', 11, 'HorizontalAlignment', 'center', 'Color', [0.7 0.1 0.1]);

ax.FontName = 'Arial';
ax.FontSize = 12;
ax.LineWidth = 1.0;
ax.Box = 'on';
ax.XGrid = 'on';
ax.YGrid = 'off';
ax.GridAlpha = 0.14;
ax.GridColor = [0.2 0.2 0.2];
ax.XLim = [-0.10 1.42];
ax.YLim = [0.3 n + 0.9];
ax.YTick = [];
xlabel(ax, 'Worst daily HTO / HTO limit (p.u.)', 'FontName', 'Arial', 'FontSize', 14);
hold(ax, 'off');
end

function plot_count_style(ax, S, labels)
counts = [S.count_0_25, S.count_25_50, S.count_50_75, S.count_75_100, S.count_gt_100];
fractions = counts ./ sum(counts, 2);

bar(ax, fractions, 'stacked', 'LineStyle', 'none');
palette = [
    221 238 255
    168 214 255
    103 171 255
    255 205 112
    228 104 96] / 255;
for i = 1:5
    ax.Children(6 - i).FaceColor = palette(i, :);
end

ax.FontName = 'Arial';
ax.FontSize = 12;
ax.LineWidth = 1.0;
ax.Box = 'on';
ax.XGrid = 'off';
ax.YGrid = 'on';
ax.GridAlpha = 0.14;
ax.GridColor = [0.2 0.2 0.2];
ax.YLim = [0 1];
ax.XTick = 1:numel(labels);
ax.XTickLabel = labels;
ylabel(ax, 'Fraction of scenario-days', 'FontName', 'Arial', 'FontSize', 14);

legend(ax, {'0-25%', '25-50%', '50-75%', '75-100%', '>100%'}, ...
    'Location', 'southoutside', 'Orientation', 'horizontal', ...
    'Box', 'off', 'FontName', 'Arial', 'FontSize', 11);

for i = 1:height(S)
    text(ax, i, min(0.98, fractions(i,1)+fractions(i,2)+fractions(i,3)+fractions(i,4)+0.03), ...
        sprintf('>=75%%: %.1f%%', 100 * S.frac_ge_75(i)), ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
        'FontName', 'Arial', 'FontSize', 10);
end
end
