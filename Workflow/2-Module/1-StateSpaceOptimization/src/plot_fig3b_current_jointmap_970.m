function outputs = plot_fig3b_current_jointmap_970(input_csv, output_tag)
%PLOT_FIG3B_CURRENT_JOINTMAP_970
% Build a manuscript-style 2D joint map for the two current-related
% candidate metrics:
%   x = mean active-stack current utilisation (p.u.)
%   y = mean inter-stack current spread (p.u.)

if nargin < 1 || isempty(input_csv)
    src_dir = fileparts(mfilename('fullpath'));
    module_root = fileparts(src_dir);
    input_csv = fullfile(module_root, 'outputs', 'fig3b_metric_candidates_970', ...
        'fig3b_candidate_metrics_970_scenario_table.csv');
end
if nargin < 2 || isempty(output_tag)
    output_tag = 'fig3b_current_jointmap_970';
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

f = figure('Visible', 'off', 'Position', [100 100 1240 860], 'Color', 'w');
ax = axes(f);
hold(ax, 'on');

legend_handles = gobjects(numel(topology_ids), 1);
legend_labels = strings(numel(topology_ids), 1);

for k = 1:numel(topology_ids)
    topo = topology_ids(k);
    S = T(T.topology_id == topo, :);
    x = S.current_mean_pu;
    y = S.current_spread_mean_pu;
    x = x(:);
    y = y(:);

    if topo >= 6
        y_vis = y + ((rand(size(y)) - 0.5) * 0.004);
        sc = scatter(ax, x, y_vis, 18, ...
            'MarkerFaceColor', colors(k, :), ...
            'MarkerEdgeColor', 'none', ...
            'MarkerFaceAlpha', 0.18, ...
            'DisplayName', sprintf('%s (single-stack)', topology_labels(k)));
        legend_handles(k) = sc;
        legend_labels(k) = sprintf('%s (single-stack)', topology_labels(k));

        plot(ax, [min(x) max(x)], [0 0], '-', 'Color', colors(k, :), 'LineWidth', 2.0, ...
            'HandleVisibility', 'off');
        plot(ax, mean(x, 'omitnan'), 0, 'o', ...
            'MarkerSize', 9, ...
            'MarkerFaceColor', colors(k, :), ...
            'MarkerEdgeColor', [0.2 0.2 0.2], ...
            'LineWidth', 1.0, ...
            'HandleVisibility', 'off');
    else
        sc = scatter(ax, x, y, 16, ...
            'MarkerFaceColor', colors(k, :), ...
            'MarkerEdgeColor', 'none', ...
            'MarkerFaceAlpha', 0.14, ...
            'DisplayName', topology_labels(k));
        legend_handles(k) = sc;
        legend_labels(k) = topology_labels(k);

        draw_cov_ellipse(ax, x, y, colors(k, :), 1.35, 2.1);
        plot(ax, mean(x, 'omitnan'), mean(y, 'omitnan'), 'o', ...
            'MarkerSize', 9, ...
            'MarkerFaceColor', colors(k, :), ...
            'MarkerEdgeColor', [0.2 0.2 0.2], ...
            'LineWidth', 1.0, ...
            'HandleVisibility', 'off');
    end
end

xlabel(ax, 'Mean stack current utilisation (p.u.)', 'FontName', 'Arial', 'FontSize', 16);
ylabel(ax, 'Mean inter-stack current spread (p.u.)', 'FontName', 'Arial', 'FontSize', 16);
ax.FontName = 'Arial';
ax.FontSize = 13;
ax.LineWidth = 1.1;
ax.Box = 'on';
ax.XGrid = 'on';
ax.YGrid = 'on';
ax.GridAlpha = 0.15;
ax.GridColor = [0.2 0.2 0.2];
xlim(ax, [0.08 1.02]);
ylim(ax, [-0.01 0.32]);

text(ax, 0.11, 0.305, 'Current-operating trade-off map across 970 scenarios', ...
    'FontName', 'Arial', 'FontSize', 17, 'FontWeight', 'bold');
text(ax, 0.11, 0.287, 'Points: one daily scenario; ellipse: distribution envelope; dot: centroid', ...
    'FontName', 'Arial', 'FontSize', 12);
text(ax, 0.11, 0.269, 'M6-M7 are single-stack topologies, so their spread collapses to 0 by definition.', ...
    'FontName', 'Arial', 'FontSize', 12);

legend(ax, legend_handles, cellstr(legend_labels), ...
    'Location', 'eastoutside', 'Box', 'off', 'FontName', 'Arial', 'FontSize', 11);

exportgraphics(f, fullfile(output_dir, 'fig3b_current_jointmap_970.png'), 'Resolution', 300);
savefig(f, fullfile(output_dir, 'fig3b_current_jointmap_970.fig'));
close(f);

outputs = struct();
outputs.figure_png = fullfile(output_dir, 'fig3b_current_jointmap_970.png');
outputs.figure_fig = fullfile(output_dir, 'fig3b_current_jointmap_970.fig');
outputs.input_csv = input_csv;
save(fullfile(output_dir, 'fig3b_current_jointmap_970_outputs.mat'), 'outputs');
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
angles = linspace(0, 2*pi, 240);
circle = [cos(angles); sin(angles)];

outer = (V * sqrt(D) * (n_std_outer * circle))';
inner = (V * sqrt(D) * (n_std_inner * circle))';

patch(ax, mu(1) + outer(:,1), mu(2) + outer(:,2), color, ...
    'FaceAlpha', 0.06, 'EdgeColor', color, 'LineWidth', 1.1, ...
    'HandleVisibility', 'off');
plot(ax, mu(1) + inner(:,1), mu(2) + inner(:,2), '-', ...
    'Color', color, 'LineWidth', 1.8, 'HandleVisibility', 'off');
end
