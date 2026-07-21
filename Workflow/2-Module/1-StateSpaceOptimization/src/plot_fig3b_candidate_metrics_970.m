function outputs = plot_fig3b_candidate_metrics_970(output_tag)
%PLOT_FIG3B_CANDIDATE_METRICS_970
% Build candidate Fig. 3b statistics from the current 970-scenario module
% optimisation results. The figure compares five scenario-level metrics:
%   1) mean active-stack current utilisation (p.u.)
%   2) mean inter-stack current spread (p.u.)
%   3) mean active-stack outlet temperature (deg C)
%   4) mean inter-stack temperature spread (deg C)
%   5) worst separator-side HTO within each daily scenario (%)

if nargin < 1 || isempty(output_tag)
    output_tag = 'fig3b_metric_candidates_970';
end

src_dir = fileparts(mfilename('fullpath'));
module_root = fileparts(src_dir);
data_input_dir = fullfile(module_root, '..', 'data', 'input');
data_result_dir = fullfile(module_root, '..', 'data', 'results');
output_dir = fullfile(module_root, 'outputs', output_tag);
if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end

loaded = load(fullfile(data_input_dir, 'P_command.mat'), 'P_command');
P_command = loaded.P_command;
num_scenarios = size(P_command, 1);
topology_ids = 1:7;
topology_labels = compose("M%d", topology_ids);
topology_colors = [
    244 172 64
    236 196 78
    0 157 122
    60 181 167
    66 133 244
    111 168 220
    150 150 150] / 255;

params = cell(1, numel(topology_ids));
for k = 1:numel(topology_ids)
    params{k} = get_topology_constants(topology_ids(k));
end

rows = cell(num_scenarios * numel(topology_ids), 10);
row_idx = 0;
for k = 1:numel(topology_ids)
    topology = topology_ids(k);
    loaded_result = load(fullfile(data_result_dir, sprintf('results_topology_%d.mat', topology)), ...
        'result', 'status', 'obj');
    topo_param = params{k};

    for s = 1:num_scenarios
        output_matrix = loaded_result.result{s, 4};
        if isempty(output_matrix) || (isnumeric(output_matrix) && isscalar(output_matrix) && output_matrix == 0)
            continue;
        end

        parsed = parse_output_matrix(P_command(s, :)', output_matrix, topo_param);
        metric = compute_scenario_metrics(parsed);

        row_idx = row_idx + 1;
        rows(row_idx, :) = {
            topology, sprintf('M%d', topology), s, loaded_result.status(s, 4), loaded_result.obj(s, 4), ...
            metric.current_mean_pu, metric.current_spread_mean_pu, ...
            metric.temp_mean_C, metric.temp_spread_mean_C, metric.hto_worst_pct};
    end
end

rows = rows(1:row_idx, :);
scenario_metrics = cell2table(rows, 'VariableNames', {
    'topology_id', 'topology_label', 'scenario_id', 'solver_status', 'objective_value', ...
    'current_mean_pu', 'current_spread_mean_pu', 'temp_mean_C', 'temp_spread_mean_C', 'hto_worst_pct'});
writetable(scenario_metrics, fullfile(output_dir, 'fig3b_candidate_metrics_970_scenario_table.csv'));

summary_metrics = summarise_metrics_by_topology(scenario_metrics, topology_ids);
writetable(summary_metrics, fullfile(output_dir, 'fig3b_candidate_metrics_970_summary.csv'));

f = figure('Visible', 'off', 'Position', [80 80 1480 940], 'Color', 'w');
tlo = tiledlayout(f, 3, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

plot_metric_panel(nexttile(tlo, 1), scenario_metrics, topology_ids, topology_labels, topology_colors, ...
    'current_mean_pu', 'Mean stack current utilisation (p.u.)', [0 1.05]);
plot_metric_panel(nexttile(tlo, 2), scenario_metrics, topology_ids, topology_labels, topology_colors, ...
    'current_spread_mean_pu', 'Mean inter-stack current spread (p.u.)', [0 1.05]);
plot_metric_panel(nexttile(tlo, 3), scenario_metrics, topology_ids, topology_labels, topology_colors, ...
    'temp_mean_C', 'Mean stack outlet temperature (°C)', []);
plot_metric_panel(nexttile(tlo, 4), scenario_metrics, topology_ids, topology_labels, topology_colors, ...
    'temp_spread_mean_C', 'Mean inter-stack temperature spread (°C)', []);
plot_metric_panel(nexttile(tlo, 5), scenario_metrics, topology_ids, topology_labels, topology_colors, ...
    'hto_worst_pct', 'Worst separator-side HTO in one day (%)', []);

ax_note = nexttile(tlo, 6);
axis(ax_note, 'off');
text(ax_note, 0.00, 0.92, 'Candidate metrics for Fig. 3b (970 scenarios)', ...
    'FontName', 'Arial', 'FontSize', 16, 'FontWeight', 'bold');
note_lines = {
    'Current utilisation: daily mean of active-stack I / I_{rated}'
    'Current spread: daily mean of max(I_{pu}) - min(I_{pu}) across active stacks'
    'Temperature: daily mean of active-stack outlet temperatures'
    'Temperature spread: daily mean of max(T) - min(T) across active stacks'
    'Worst HTO: daily maximum of max_g HTO_g(t) within each module'
    ''
    'Each box summarises one daily scenario; whiskers follow MATLAB defaults.'
    'This figure is for metric screening before final manuscript styling.'};
for i = 1:numel(note_lines)
    text(ax_note, 0.00, 0.84 - 0.09 * (i - 1), note_lines{i}, ...
        'FontName', 'Arial', 'FontSize', 12);
end

exportgraphics(f, fullfile(output_dir, 'fig3b_candidate_metrics_970.png'), 'Resolution', 300);
savefig(f, fullfile(output_dir, 'fig3b_candidate_metrics_970.fig'));
close(f);

outputs = struct();
outputs.output_dir = output_dir;
outputs.scenario_table = fullfile(output_dir, 'fig3b_candidate_metrics_970_scenario_table.csv');
outputs.summary_table = fullfile(output_dir, 'fig3b_candidate_metrics_970_summary.csv');
outputs.figure_png = fullfile(output_dir, 'fig3b_candidate_metrics_970.png');
outputs.figure_fig = fullfile(output_dir, 'fig3b_candidate_metrics_970.fig');

save(fullfile(output_dir, 'fig3b_candidate_metrics_970_outputs.mat'), 'outputs');
end

function topo_param = get_topology_constants(topology)
type = topology; %#ok<NASGU>
Ptot_command = zeros(96, 1); %#ok<NASGU>
cluster_parameters;
topo_param = struct( ...
    'topology', topology, ...
    'N_st', N_st, ...
    'N_sp', N_sp, ...
    'N_lyep', N_lyep, ...
    'N_cl', N_cl, ...
    'delta_t', delta_t, ...
    't_command', t_command, ...
    'I_UL_st', I_UL_st);
end

function parsed = parse_output_matrix(Ptot_command, output_matrix, topo_param)
col = 1;
parsed = struct();
parsed.Ptot_command = Ptot_command(:);
parsed.delta_t = topo_param.delta_t;
parsed.t_command = topo_param.t_command;
parsed.N_st = topo_param.N_st;
parsed.N_sp = topo_param.N_sp;
parsed.N_lyep = topo_param.N_lyep;
parsed.N_cl = topo_param.N_cl;
parsed.I_UL_st = topo_param.I_UL_st;

N_st = topo_param.N_st;
N_lyep = topo_param.N_lyep;
N_cl = topo_param.N_cl;
N_sp = topo_param.N_sp;

parsed.P_st = output_matrix(:, col:(col + N_st - 1))'; col = col + N_st;
parsed.N_H2_st = output_matrix(:, col:(col + N_st - 1))'; col = col + N_st; %#ok<NASGU>
parsed.delta_I = output_matrix(:, col:(col + N_st - 1))'; col = col + N_st;
parsed.I_st = output_matrix(:, col:(col + N_st - 1))'; col = col + N_st;
parsed.delta_lyep = output_matrix(:, col:(col + N_lyep - 1))'; col = col + N_lyep; %#ok<NASGU>
parsed.Qlye_st = output_matrix(:, col:(col + N_st - 1))'; col = col + N_st; %#ok<NASGU>
parsed.Q_cl = output_matrix(:, col:(col + N_cl - 1))'; col = col + N_cl; %#ok<NASGU>
parsed.U_cell = output_matrix(:, col:(col + N_st - 1))'; col = col + N_st; %#ok<NASGU>
parsed.T_stout = output_matrix(:, col:(col + N_st - 1))'; col = col + N_st;
parsed.HTO_sp15 = output_matrix(:, col:(col + N_sp - 1))';
end

function metric = compute_scenario_metrics(parsed)
active = parsed.delta_I > 0.5;
current_pu = parsed.I_st / parsed.I_UL_st;

current_mean_t = nan(1, parsed.t_command);
current_spread_t = nan(1, parsed.t_command);
temp_mean_t = nan(1, parsed.t_command);
temp_spread_t = nan(1, parsed.t_command);

for t = 1:parsed.t_command
    idx = active(:, t);
    if ~any(idx)
        continue;
    end

    current_vals = current_pu(idx, t);
    temp_vals = parsed.T_stout(idx, t);

    current_mean_t(t) = mean(current_vals, 'omitnan');
    current_spread_t(t) = max(current_vals) - min(current_vals);
    temp_mean_t(t) = mean(temp_vals, 'omitnan');
    temp_spread_t(t) = max(temp_vals) - min(temp_vals);
end

metric = struct();
metric.current_mean_pu = mean(current_mean_t, 'omitnan');
metric.current_spread_mean_pu = mean(current_spread_t, 'omitnan');
metric.temp_mean_C = mean(temp_mean_t, 'omitnan');
metric.temp_spread_mean_C = mean(temp_spread_t, 'omitnan');
metric.hto_worst_pct = max(parsed.HTO_sp15, [], 'all') * 100;
end

function summary_metrics = summarise_metrics_by_topology(scenario_metrics, topology_ids)
rows = cell(numel(topology_ids), 16);
for k = 1:numel(topology_ids)
    topology = topology_ids(k);
    T = scenario_metrics(scenario_metrics.topology_id == topology, :);

    rows(k, :) = {
        topology, sprintf('M%d', topology), height(T), ...
        mean(T.current_mean_pu, 'omitnan'), prctile(T.current_mean_pu, 25), median(T.current_mean_pu, 'omitnan'), prctile(T.current_mean_pu, 75), ...
        mean(T.current_spread_mean_pu, 'omitnan'), ...
        mean(T.temp_mean_C, 'omitnan'), ...
        mean(T.temp_spread_mean_C, 'omitnan'), ...
        mean(T.hto_worst_pct, 'omitnan'), prctile(T.hto_worst_pct, 25), median(T.hto_worst_pct, 'omitnan'), prctile(T.hto_worst_pct, 75), ...
        min(T.hto_worst_pct), max(T.hto_worst_pct)};
    %#ok<AGROW>
end

summary_metrics = cell2table(rows, 'VariableNames', {
    'topology_id', 'topology_label', 'valid_scenario_count', ...
    'current_mean_mean_pu', 'current_mean_p25_pu', 'current_mean_median_pu', 'current_mean_p75_pu', ...
    'current_spread_mean_pu', ...
    'temp_mean_mean_C', ...
    'temp_spread_mean_C', ...
    'hto_worst_mean_pct', 'hto_worst_p25_pct', 'hto_worst_median_pct', 'hto_worst_p75_pct', ...
    'hto_worst_min_pct', 'hto_worst_max_pct'});
end

function plot_metric_panel(ax, T, topology_ids, topology_labels, topology_colors, metric_name, ylabel_text, y_limits)
hold(ax, 'on');
for k = 1:numel(topology_ids)
    topology = topology_ids(k);
    vals = T{T.topology_id == topology, metric_name};
    vals = vals(~isnan(vals));
    if isempty(vals)
        continue;
    end
    x = repmat(k, size(vals));
    boxchart(ax, x, vals, ...
        'BoxFaceColor', topology_colors(k, :), ...
        'MarkerStyle', 'none', ...
        'LineWidth', 1.2);
end

ax.FontName = 'Arial';
ax.FontSize = 12;
ax.LineWidth = 1.0;
ax.Box = 'on';
ax.XGrid = 'off';
ax.YGrid = 'on';
ax.GridAlpha = 0.15;
ax.GridColor = [0.2 0.2 0.2];
ax.XLim = [0.5, numel(topology_ids) + 0.5];
ax.XTick = 1:numel(topology_ids);
ax.XTickLabel = topology_labels;
xtickangle(ax, 0);
ylabel(ax, ylabel_text, 'FontName', 'Arial', 'FontSize', 13);
if ~isempty(y_limits)
    ylim(ax, y_limits);
end
hold(ax, 'off');
end
