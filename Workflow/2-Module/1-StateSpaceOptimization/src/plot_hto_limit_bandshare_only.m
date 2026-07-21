function outputs = plot_hto_limit_bandshare_only(input_csv, output_tag, hto_limit_pct)
%PLOT_HTO_LIMIT_BANDSHARE_ONLY
% Standalone manuscript-style chart for HTO safety occupancy.
% It shows the percentage of scenario-days falling into five occupancy
% bands of worst daily HTO / HTO limit.

if nargin < 1 || isempty(input_csv)
    src_dir = fileparts(mfilename('fullpath'));
    module_root = fileparts(src_dir);
    input_csv = fullfile(module_root, 'outputs', 'fig3b_metric_candidates_970', ...
        'fig3b_candidate_metrics_970_scenario_table.csv');
end
if nargin < 2 || isempty(output_tag)
    output_tag = 'fig3b_hto_limit_bandshare_only';
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

[fraction_table, count_table] = build_bandshare_tables(T, topology_ids);
writetable(fraction_table, fullfile(output_dir, 'hto_limit_bandshare_fraction.csv'));
writetable(count_table, fullfile(output_dir, 'hto_limit_bandshare_count.csv'));

f = figure('Visible', 'off', 'Position', [100 100 1260 720], 'Color', 'w');
ax = axes(f);
hold(ax, 'on');

fractions = [ ...
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
    228 104 96] / 255;
bar_half_h = 0.36;
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
        'EdgeColor', [0.82 0.82 0.82], 'LineWidth', 0.8);
end

for r = 1:height(fraction_table)
    cum_left = 0;
    vals = fractions(r, :);
    for c = 1:size(vals, 2)
        w = vals(c);
        if w >= 0.07
            text(ax, cum_left + w / 2, r, sprintf('%.0f%%', 100 * w), ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
                'FontName', 'Arial', 'FontSize', 11, 'Color', [0.15 0.15 0.15], ...
                'FontWeight', 'bold');
        end
        cum_left = cum_left + w;
    end

    risky_50 = vals(3) + vals(4) + vals(5);
    risky_75 = vals(4) + vals(5);
    text(ax, 1.015, r, sprintf('>=50%%: %.1f%% | >=75%%: %.1f%%', ...
        100 * risky_50, 100 * risky_75), ...
        'HorizontalAlignment', 'left', 'VerticalAlignment', 'middle', ...
        'FontName', 'Arial', 'FontSize', 11);
end

ax.FontName = 'Arial';
ax.FontSize = 13;
ax.LineWidth = 1.0;
ax.Box = 'on';
ax.XGrid = 'on';
ax.YGrid = 'off';
ax.GridAlpha = 0.14;
ax.GridColor = [0.2 0.2 0.2];
ax.XLim = [0 1.22];
ax.XTick = 0:0.2:1.0;
ax.XTickLabel = compose('%.0f%%', 100 * (0:0.2:1.0));
ax.YTick = 1:numel(topology_labels);
ax.YTickLabel = topology_labels;
ax.YDir = 'reverse';

xlabel(ax, 'Share of scenario-days', 'FontName', 'Arial', 'FontSize', 15);
ylabel(ax, 'Module topology', 'FontName', 'Arial', 'FontSize', 15);
title(ax, 'HTO safety occupancy by worst daily separator-side impurity', ...
    'FontName', 'Arial', 'FontSize', 20, 'FontWeight', 'bold');

subtitle_text = sprintf('Occupancy bands are defined by worst daily HTO / HTO limit (limit = %.1f%%)', hto_limit_pct);
text(ax, 0.00, 0.20, subtitle_text, ...
    'Units', 'normalized', 'FontName', 'Arial', 'FontSize', 12);

legend(ax, {'0-25% limit', '25-50% limit', '50-75% limit', '75-100% limit', '>100% limit'}, ...
    'Location', 'southoutside', 'Orientation', 'horizontal', ...
    'Box', 'off', 'FontName', 'Arial', 'FontSize', 11);

png = fullfile(output_dir, 'hto_limit_bandshare_only.png');
fig = fullfile(output_dir, 'hto_limit_bandshare_only.fig');
exportgraphics(f, png, 'Resolution', 300);
savefig(f, fig);
close(f);

outputs = struct();
outputs.figure_png = png;
outputs.figure_fig = fig;
outputs.fraction_csv = fullfile(output_dir, 'hto_limit_bandshare_fraction.csv');
outputs.count_csv = fullfile(output_dir, 'hto_limit_bandshare_count.csv');
save(fullfile(output_dir, 'hto_limit_bandshare_only_outputs.mat'), 'outputs');
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
