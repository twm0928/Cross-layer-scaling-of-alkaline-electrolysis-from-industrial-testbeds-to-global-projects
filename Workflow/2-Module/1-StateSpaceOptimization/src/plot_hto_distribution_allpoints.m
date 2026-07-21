function outputs = plot_hto_distribution_allpoints(output_tag)
%PLOT_HTO_DISTRIBUTION_ALLPOINTS
% Build a topology-wise HTO distribution figure using all valid scenarios,
% all 15-min time points, and all separator channels. The plotted quantity is
% the normalised HTO value HTO / HTO_UL (p.u.), so the figure does not expose
% the absolute industrial threshold directly.

if nargin < 1 || isempty(output_tag)
    output_tag = 'fig3b_hto_distribution_allpoints';
end

src_dir = fileparts(mfilename('fullpath'));
module_root = fileparts(src_dir);
data_result_dir = fullfile(module_root, '..', 'data', 'results');
output_dir = fullfile(module_root, 'outputs', output_tag);
if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end

% Read the HTO upper limit from the same parameter file used in optimisation.
type = 1; %#ok<NASGU>
topology = 1; fault = 0; %#ok<NASGU>
Ptot_command = zeros(96, 1); %#ok<NASGU>
cluster_parameters;
hto_limit_pu_ref = HTO_UL;

topology_ids = 1:7;
topology_labels = compose("M%d", topology_ids);
colors = [
    243 163  50
    243 163  50
    243 163  50
      1 138 103
      1 138 103
     24 104 178
    120 120 120] / 255;

all_rows = cell(numel(topology_ids), 1);
summary_rows = cell(numel(topology_ids), 8);

for k = 1:numel(topology_ids)
    topo = topology_ids(k);
    loaded_result = load(fullfile(data_result_dir, sprintf('results_topology_%d.mat', topo)), ...
        'result');
    vals_topo = [];

    for s = 1:size(loaded_result.result, 1)
        output_matrix = loaded_result.result{s, 4};
        if isempty(output_matrix) || (isnumeric(output_matrix) && isscalar(output_matrix) && output_matrix == 0)
            continue;
        end

        hto_cols = get_hto_columns_from_output(output_matrix, topo);
        vals = hto_cols(:) / hto_limit_pu_ref;
        vals = vals(isfinite(vals));
        vals_topo = [vals_topo; vals]; %#ok<AGROW>
    end

    all_rows{k} = vals_topo;
    summary_rows(k, :) = {
        topo, sprintf('M%d', topo), numel(vals_topo), ...
        mean(vals_topo, 'omitnan'), median(vals_topo, 'omitnan'), ...
        prctile(vals_topo, 95), prctile(vals_topo, 99), max(vals_topo)};
end

summary_table = cell2table(summary_rows, 'VariableNames', ...
    {'topology_id','topology_label','sample_count','mean_pu','median_pu','p95_pu','p99_pu','max_pu'});
writetable(summary_table, fullfile(output_dir, 'hto_distribution_allpoints_summary.csv'));

f = figure('Visible', 'off', 'Position', [80 80 900 620], 'Color', 'w');
ax = axes(f);
hold(ax, 'on');

for k = 1:numel(topology_ids)
    vals = all_rows{k};
    draw_full_violin(ax, k, vals, colors(k, :), 0.28, [0 1.02]);
end

ax.FontName = 'Arial';
ax.FontSize = 18;
ax.LineWidth = 1.0;
ax.Box = 'on';
ax.XGrid = 'off';
ax.YGrid = 'on';
ax.GridAlpha = 0.14;
ax.GridColor = [0.2 0.2 0.2];
ax.XLim = [0.45 numel(topology_ids)+0.55];
ax.XTick = 1:numel(topology_ids);
ax.XTickLabel = topology_labels;
ax.YLim = [0 1.02];
ax.YTick = 0:0.2:1.0;

xlabel(ax, 'Module topology', 'FontName', 'Arial', 'FontSize', 20);
ylabel(ax, 'HTO distribution (p.u.)', 'FontName', 'Arial', 'FontSize', 20);

files = struct();
files.png = fullfile(output_dir, 'hto_distribution_allpoints.png');
files.fig = fullfile(output_dir, 'hto_distribution_allpoints.fig');
files.svg = fullfile(output_dir, 'hto_distribution_allpoints.svg');
exportgraphics(f, files.png, 'Resolution', 300);
set(f, 'Renderer', 'painters');
print(f, files.svg, '-dsvg');
savefig(f, files.fig);
close(f);

outputs = struct();
outputs.figure_png = files.png;
outputs.figure_fig = files.fig;
outputs.figure_svg = files.svg;
outputs.summary_csv = fullfile(output_dir, 'hto_distribution_allpoints_summary.csv');
outputs.hto_limit_used_in_model = hto_limit_pu_ref;
save(fullfile(output_dir, 'hto_distribution_allpoints_outputs.mat'), 'outputs');
end

function hto_cols = get_hto_columns_from_output(output_matrix, topology)
type = topology; %#ok<NASGU>
Ptot_command = zeros(96, 1); %#ok<NASGU>
cluster_parameters;

col = 1;
col = col + N_st;   % P_st
col = col + N_st;   % N_H2_st
col = col + N_st;   % delta_I
col = col + N_st;   % I_st
col = col + N_lyep; % delta_lyep
col = col + N_st;   % Qlye_st
col = col + N_cl;   % Q_cl
col = col + N_st;   % U_cell
col = col + N_st;   % T_stout
hto_cols = output_matrix(:, col:(col + N_sp - 1));
end

function draw_full_violin(ax, x0, vals, color, half_width, support_range)
vals = vals(isfinite(vals));
vals = min(max(vals, support_range(1)), support_range(2));
if isempty(vals)
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
else
    y = linspace(support_range(1), support_range(2), 256);
    try
        [f, y] = ksdensity(vals, y, 'Support', support_range, 'BoundaryCorrection', 'reflection');
    catch
        [f, y] = ksdensity(vals, y);
    end
    f(~isfinite(f)) = 0;
    f = max(f, 0);
end

if max(f) <= 0
    return;
end

f = f ./ max(f) * half_width;
patch(ax, [x0 - f fliplr(x0 + f)], [y fliplr(y)], color, ...
    'FaceAlpha', 0.20, 'EdgeColor', color, 'LineWidth', 1.4, 'HandleVisibility', 'off');
plot(ax, x0 - f, y, '-', 'Color', color, 'LineWidth', 1.5, 'HandleVisibility', 'off');
plot(ax, x0 + f, y, '-', 'Color', color, 'LineWidth', 1.5, 'HandleVisibility', 'off');

q25 = prctile(vals, 25);
q50 = median(vals, 'omitnan');
q75 = prctile(vals, 75);
plot(ax, [x0 x0], [q25 q75], '-', 'Color', color, 'LineWidth', 6, 'HandleVisibility', 'off');
plot(ax, x0, q50, 'o', 'MarkerSize', 8, 'MarkerFaceColor', color, ...
    'MarkerEdgeColor', [0.15 0.15 0.15], 'LineWidth', 1.0, 'HandleVisibility', 'off');
end
