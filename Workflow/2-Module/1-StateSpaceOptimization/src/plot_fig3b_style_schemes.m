function outputs = plot_fig3b_style_schemes(input_csv, output_tag)
%PLOT_FIG3B_STYLE_SCHEMES
% Create two manuscript-style draft schemes for the module-layer Fig. 3b:
%   Scheme A: current joint trade-off map + half-violin T/HTO
%   Scheme B: unified half-violin distribution panels

if nargin < 1 || isempty(input_csv)
    src_dir = fileparts(mfilename('fullpath'));
    module_root = fileparts(src_dir);
    input_csv = fullfile(module_root, 'outputs', 'fig3b_metric_candidates_970', ...
        'fig3b_candidate_metrics_970_scenario_table.csv');
end
if nargin < 2 || isempty(output_tag)
    output_tag = 'fig3b_style_schemes';
end

src_dir = fileparts(mfilename('fullpath'));
module_root = fileparts(src_dir);
output_dir = fullfile(module_root, 'outputs', output_tag);
if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end

T = readtable(input_csv);
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

schemeA = plot_scheme_a(T, topology_ids, topology_labels, colors, output_dir);
schemeB = plot_scheme_b(T, topology_ids, topology_labels, colors, output_dir);

outputs = struct();
outputs.schemeA_png = schemeA.png;
outputs.schemeA_fig = schemeA.fig;
outputs.schemeB_png = schemeB.png;
outputs.schemeB_fig = schemeB.fig;
outputs.input_csv = input_csv;
save(fullfile(output_dir, 'fig3b_style_schemes_outputs.mat'), 'outputs');
end

function out = plot_scheme_a(T, topology_ids, topology_labels, colors, output_dir)
f = figure('Visible', 'off', 'Position', [80 80 1520 920], 'Color', 'w');
tlo = tiledlayout(f, 2, 3, 'TileSpacing', 'compact', 'Padding', 'compact');

axJ = nexttile(tlo, [2 2]);
plot_current_joint_map(axJ, T, topology_ids, topology_labels, colors);
title(axJ, 'Current-dispatch trade-off', 'FontName', 'Arial', 'FontSize', 17, 'FontWeight', 'bold');

axT = nexttile(tlo, 3);
plot_half_violin_panel(axT, T, topology_ids, topology_labels, colors, ...
    'temp_mean_C', 'Mean stack outlet temperature (°C)', [76 96], []);
title(axT, 'Thermal behaviour', 'FontName', 'Arial', 'FontSize', 16, 'FontWeight', 'bold');

axH = nexttile(tlo, 6);
plot_half_violin_panel(axH, T, topology_ids, topology_labels, colors, ...
    'hto_worst_pct', 'Worst separator-side HTO in one day (%)', [0 8], []);
title(axH, 'Safety-related impurity behaviour', 'FontName', 'Arial', 'FontSize', 16, 'FontWeight', 'bold');

annotation(f, 'textbox', [0.06 0.95 0.88 0.035], ...
    'String', 'Scheme A: current joint-map plus half-violin physical constraints (970 scenarios)', ...
    'FontName', 'Arial', 'FontSize', 18, 'FontWeight', 'bold', ...
    'LineStyle', 'none', 'HorizontalAlignment', 'center');

png = fullfile(output_dir, 'schemeA_current_jointmap_T_HTO.png');
fig = fullfile(output_dir, 'schemeA_current_jointmap_T_HTO.fig');
exportgraphics(f, png, 'Resolution', 300);
savefig(f, fig);
close(f);

out = struct('png', png, 'fig', fig);
end

function out = plot_scheme_b(T, topology_ids, topology_labels, colors, output_dir)
f = figure('Visible', 'off', 'Position', [90 90 1220 1240], 'Color', 'w');
tlo = tiledlayout(f, 4, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

ax1 = nexttile(tlo, 1);
plot_half_violin_panel(ax1, T, topology_ids, topology_labels, colors, ...
    'current_mean_pu', 'Mean stack current utilisation (p.u.)', [0 1.02], []);

ax2 = nexttile(tlo, 2);
plot_half_violin_panel(ax2, T, topology_ids, topology_labels, colors, ...
    'current_spread_mean_pu', 'Mean inter-stack current spread (p.u.)', [0 0.32], []);

ax3 = nexttile(tlo, 3);
plot_half_violin_panel(ax3, T, topology_ids, topology_labels, colors, ...
    'temp_mean_C', 'Mean stack outlet temperature (°C)', [76 96], []);

ax4 = nexttile(tlo, 4);
plot_half_violin_panel(ax4, T, topology_ids, topology_labels, colors, ...
    'hto_worst_pct', 'Worst separator-side HTO in one day (%)', [0 8], []);

annotation(f, 'textbox', [0.09 0.965 0.82 0.03], ...
    'String', 'Scheme B: unified half-violin distributions for key module-layer physics (970 scenarios)', ...
    'FontName', 'Arial', 'FontSize', 18, 'FontWeight', 'bold', ...
    'LineStyle', 'none', 'HorizontalAlignment', 'center');

png = fullfile(output_dir, 'schemeB_unified_halfviolins.png');
fig = fullfile(output_dir, 'schemeB_unified_halfviolins.fig');
exportgraphics(f, png, 'Resolution', 300);
savefig(f, fig);
close(f);

out = struct('png', png, 'fig', fig);
end

function plot_current_joint_map(ax, T, topology_ids, topology_labels, colors)
hold(ax, 'on');

main_ids = 1:5;
for k = main_ids
    S = T(T.topology_id == k, :);
    x = S.current_mean_pu;
    y = S.current_spread_mean_pu;

    scatter(ax, x, y, 14, ...
        'MarkerFaceColor', colors(k, :), ...
        'MarkerEdgeColor', 'none', ...
        'MarkerFaceAlpha', 0.10, ...
        'HandleVisibility', 'off');

    draw_cov_ellipse(ax, x, y, colors(k, :), 1.40, 2.00);
    plot(ax, mean(x, 'omitnan'), mean(y, 'omitnan'), 'o', ...
        'MarkerSize', 10, ...
        'MarkerFaceColor', colors(k, :), ...
        'MarkerEdgeColor', [0.2 0.2 0.2], ...
        'LineWidth', 1.0, ...
        'DisplayName', topology_labels(k));
end

xlabel(ax, 'Mean stack current utilisation (p.u.)', 'FontName', 'Arial', 'FontSize', 15);
ylabel(ax, 'Mean inter-stack current spread (p.u.)', 'FontName', 'Arial', 'FontSize', 15);
style_axis(ax);
xlim(ax, [0.08 1.02]);
ylim(ax, [0 0.32]);
legend(ax, 'Location', 'northeast', 'Box', 'off', 'FontName', 'Arial', 'FontSize', 11);

text(ax, 0.11, 0.294, 'One point = one daily scenario', 'FontName', 'Arial', 'FontSize', 12);
text(ax, 0.11, 0.278, 'Ellipse = distribution envelope; circle = centroid', 'FontName', 'Arial', 'FontSize', 12);

% Inset for single-stack topologies.
inset = axes('Parent', ancestor(ax, 'figure'), 'Position', [0.40 0.18 0.23 0.16]);
hold(inset, 'on');
for k = 6:7
    vals = T.current_mean_pu(T.topology_id == k);
    vals = vals(isfinite(vals));
    x0 = k - 5;
    draw_half_violin_vertical(inset, x0, vals, colors(k, :), 0.18);
    draw_iqr_marker(inset, x0, vals, colors(k, :));
end
style_axis(inset);
inset.XTick = [1 2];
inset.XTickLabel = {'M6', 'M7'};
inset.YLim = [0 1.02];
inset.YTick = [0 0.5 1.0];
ylabel(inset, 'Utilisation (p.u.)', 'FontName', 'Arial', 'FontSize', 10);
title(inset, 'Single-stack topologies', 'FontName', 'Arial', 'FontSize', 11, 'FontWeight', 'bold');
box(inset, 'on');
hold(inset, 'off');
end

function plot_half_violin_panel(ax, T, topology_ids, topology_labels, colors, metric_name, ylabel_text, y_limits, threshold)
hold(ax, 'on');
for k = 1:numel(topology_ids)
    vals = T{T.topology_id == topology_ids(k), metric_name};
    vals = vals(isfinite(vals));
    draw_half_violin_vertical(ax, k, vals, colors(k, :), 0.30);
    draw_iqr_marker(ax, k, vals, colors(k, :));
end

if ~isempty(threshold)
    yline(ax, threshold, '--', 'Color', [0.35 0.35 0.35], 'LineWidth', 1.2, ...
        'HandleVisibility', 'off');
end

style_axis(ax);
ax.XLim = [0.4 numel(topology_ids) + 0.6];
ax.XTick = 1:numel(topology_ids);
ax.XTickLabel = topology_labels;
ax.YLim = y_limits;
ylabel(ax, ylabel_text, 'FontName', 'Arial', 'FontSize', 14);
hold(ax, 'off');
end

function draw_half_violin_vertical(ax, x0, vals, color, half_width)
if isempty(vals)
    return;
end

[f, yi] = ksdensity(vals);
if max(f) <= 0
    return;
end
f = f ./ max(f) * half_width;

patch(ax, [x0 * ones(size(yi)) fliplr(x0 + f)], [yi fliplr(yi)], color, ...
    'FaceAlpha', 0.18, 'EdgeColor', color, 'LineWidth', 1.2, 'HandleVisibility', 'off');
plot(ax, x0 + f, yi, '-', 'Color', color, 'LineWidth', 1.5, 'HandleVisibility', 'off');
end

function draw_iqr_marker(ax, x0, vals, color)
q25 = prctile(vals, 25);
q50 = median(vals, 'omitnan');
q75 = prctile(vals, 75);

plot(ax, [x0 x0], [q25 q75], '-', 'Color', color, 'LineWidth', 4.0, 'HandleVisibility', 'off');
plot(ax, x0, q50, 'o', ...
    'MarkerSize', 6.5, ...
    'MarkerFaceColor', color, ...
    'MarkerEdgeColor', [0.15 0.15 0.15], ...
    'LineWidth', 0.8, ...
    'HandleVisibility', 'off');
end

function draw_cov_ellipse(ax, x, y, color, n_std_outer, n_std_inner)
x = x(:);
y = y(:);
good = isfinite(x) & isfinite(y);
x = x(good);
y = y(good);
if numel(x) < 3
    return;
end

mu = [mean(x), mean(y)];
C = cov(x, y);
if rank(C) < 2
    return;
end

[V, D] = eig(C);
angles = linspace(0, 2 * pi, 240);
circle = [cos(angles); sin(angles)];

outer = (V * sqrt(D) * (n_std_outer * circle))';
inner = (V * sqrt(D) * (n_std_inner * circle))';

patch(ax, mu(1) + outer(:, 1), mu(2) + outer(:, 2), color, ...
    'FaceAlpha', 0.05, 'EdgeColor', color, 'LineWidth', 1.0, 'HandleVisibility', 'off');
plot(ax, mu(1) + inner(:, 1), mu(2) + inner(:, 2), '-', ...
    'Color', color, 'LineWidth', 1.7, 'HandleVisibility', 'off');
end

function style_axis(ax)
ax.FontName = 'Arial';
ax.FontSize = 12;
ax.LineWidth = 1.0;
ax.Box = 'on';
ax.XGrid = 'off';
ax.YGrid = 'on';
ax.GridAlpha = 0.14;
ax.GridColor = [0.2 0.2 0.2];
end
