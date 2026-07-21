function outputs = plot_hto_histogram_smallmultiples(output_tag)
%PLOT_HTO_HISTOGRAM_SMALLMULTIPLES
% Traditional small-multiple histogram view of all HTO samples.
% Uses all valid scenarios, all 15-min time points, and all separator
% channels. The plotted quantity is HTO / HTO_UL (p.u.).

if nargin < 1 || isempty(output_tag)
    output_tag = 'fig3b_hto_histogram_smallmultiples';
end

src_dir = fileparts(mfilename('fullpath'));
module_root = fileparts(src_dir);
data_result_dir = fullfile(module_root, '..', 'data', 'results');
output_dir = fullfile(module_root, 'outputs', output_tag);
if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end

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
end

edges = linspace(0, 1.0, 26);
max_prob = 0;
for k = 1:numel(all_rows)
    counts = histcounts(min(max(all_rows{k}, edges(1)), edges(end)), edges, ...
        'Normalization', 'probability');
    max_prob = max(max_prob, max(counts));
end
max_prob = ceil(max_prob / 0.02) * 0.02;

f = figure('Visible', 'off', 'Position', [80 80 1120 760], 'Color', 'w');
tiledlayout(f, 2, 4, 'TileSpacing', 'compact', 'Padding', 'compact');

for k = 1:numel(topology_ids)
    ax = nexttile;
    vals = min(max(all_rows{k}, edges(1)), edges(end));
    histogram(ax, vals, edges, ...
        'Normalization', 'probability', ...
        'FaceColor', colors(k, :), ...
        'EdgeColor', 'w', ...
        'LineWidth', 0.6, ...
        'FaceAlpha', 0.88);

    hold(ax, 'on');
    xline(ax, median(vals, 'omitnan'), '-', 'Color', [0.15 0.15 0.15], 'LineWidth', 1.3);

    ax.FontName = 'Arial';
    ax.FontSize = 14;
    ax.LineWidth = 1.0;
    ax.Box = 'on';
    ax.XGrid = 'off';
    ax.YGrid = 'on';
    ax.GridAlpha = 0.12;
    ax.GridColor = [0.2 0.2 0.2];
    ax.XLim = [0 1.0];
    ax.YLim = [0 max_prob];
    title(ax, topology_labels(k), 'FontName', 'Arial', 'FontSize', 16, 'FontWeight', 'bold');

    if k > 4
        xlabel(ax, 'HTO (p.u.)', 'FontName', 'Arial', 'FontSize', 16);
    end
    if ismember(k, [1 5])
        ylabel(ax, 'Probability', 'FontName', 'Arial', 'FontSize', 16);
    end
end

nexttile(8);
axis off;
text(0.02, 0.82, 'All valid scenarios', 'FontName', 'Arial', 'FontSize', 16);
text(0.02, 0.62, 'All 15-min windows', 'FontName', 'Arial', 'FontSize', 16);
text(0.02, 0.42, 'All separator channels', 'FontName', 'Arial', 'FontSize', 16);
text(0.02, 0.22, 'Median marked by black line', 'FontName', 'Arial', 'FontSize', 16);

files = struct();
files.png = fullfile(output_dir, 'hto_histogram_smallmultiples.png');
files.fig = fullfile(output_dir, 'hto_histogram_smallmultiples.fig');
files.svg = fullfile(output_dir, 'hto_histogram_smallmultiples.svg');
exportgraphics(f, files.png, 'Resolution', 300);
set(f, 'Renderer', 'painters');
print(f, files.svg, '-dsvg');
savefig(f, files.fig);
close(f);

outputs = struct();
outputs.figure_png = files.png;
outputs.figure_fig = files.fig;
outputs.figure_svg = files.svg;
outputs.hto_limit_used_in_model = hto_limit_pu_ref;
save(fullfile(output_dir, 'hto_histogram_smallmultiples_outputs.mat'), 'outputs');
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
