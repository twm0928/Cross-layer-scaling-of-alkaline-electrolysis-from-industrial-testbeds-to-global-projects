function summary = export_saved_scenario_results(scenario_id, topology_ids, output_tag)
%EXPORT_SAVED_SCENARIO_RESULTS Export one scenario from stored result mats.
%   This fallback does not rerun the optimiser. It extracts the saved
%   15-minute trajectories already present in `results_topology_*.mat`.
%   It is useful when solver access is temporarily unavailable.

if nargin < 1 || isempty(scenario_id)
    scenario_id = 505;
end
if nargin < 2 || isempty(topology_ids)
    topology_ids = 1:7;
end
if nargin < 3 || isempty(output_tag)
    output_tag = sprintf('fig3b_scenario_%d_saved_results', scenario_id);
end

module_root = fileparts(fileparts(mfilename('fullpath')));
input_file = fullfile(module_root, '..', 'data', 'input', 'P_command.mat');
result_dir = fullfile(module_root, '..', 'data', 'results');
output_dir = fullfile(module_root, 'outputs', output_tag);
if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end

loaded = load(input_file, 'P_command');
P_command = loaded.P_command;
if scenario_id < 1 || scenario_id > size(P_command, 1)
    error('Scenario ID %d is outside 1:%d.', scenario_id, size(P_command, 1));
end

Ptot_command = P_command(scenario_id, :)';
t15 = (0:numel(Ptot_command)-1)' * 0.25;
writetable(table(t15, Ptot_command, 'VariableNames', {'time_h', 'power_command_MW'}), ...
    fullfile(output_dir, sprintf('scenario_%d_power_profile.csv', scenario_id)));
f = figure('Visible', 'off', 'Position', [100 100 900 320]);
plot(t15, Ptot_command, 'LineWidth', 2.0, 'Color', [0.05 0.35 0.75]);
xlim([0 24]);
xlabel('Time (h)');
ylabel('Commanded module power (MW)');
box on;
grid off;
exportgraphics(f, fullfile(output_dir, sprintf('scenario_%d_power_profile.png', scenario_id)), 'Resolution', 300);
close(f);

summary_rows = cell(numel(topology_ids), 8);
for k = 1:numel(topology_ids)
    topology = topology_ids(k);
    topology_label = sprintf('M%d', topology);
    result_file = fullfile(result_dir, sprintf('results_topology_%d.mat', topology));
    loaded_result = load(result_file, 'result', 'obj', 'status');

    output_matrix = loaded_result.result{scenario_id, 4};
    output_status = loaded_result.status(scenario_id, 4);
    output_obj = loaded_result.obj(scenario_id, 4);

    if isempty(output_matrix) || (isnumeric(output_matrix) && isscalar(output_matrix) && output_matrix == 0)
        summary_rows(k, :) = {topology, topology_label, scenario_id, output_status, output_obj, 0, 0, false};
        continue;
    end

    parsed = parse_saved_output_matrix(topology, Ptot_command, output_matrix);
    save(fullfile(output_dir, sprintf('%s_scenario_%d_saved_result.mat', topology_label, scenario_id)), ...
        'parsed', 'output_matrix', 'output_status', 'output_obj', 'scenario_id', 'topology', '-v7.3');

    stack_table = build_saved_stack_table(parsed);
    writetable(stack_table, fullfile(output_dir, sprintf('%s_scenario_%d_stack_15min.csv', topology_label, scenario_id)));

    hto15_table = build_saved_hto15_table(parsed);
    writetable(hto15_table, fullfile(output_dir, sprintf('%s_scenario_%d_hto_15min.csv', topology_label, scenario_id)));

    summary_rows(k, :) = {topology, topology_label, scenario_id, output_status, output_obj, parsed.N_st, parsed.N_sp, true};
end

summary = cell2table(summary_rows, 'VariableNames', ...
    {'topology_id', 'topology_label', 'scenario_id', 'solver_status', 'objective_value', 'num_stacks', 'num_separator_groups', 'has_saved_result'});
writetable(summary, fullfile(output_dir, sprintf('scenario_%d_saved_summary.csv', scenario_id)));
save(fullfile(output_dir, sprintf('scenario_%d_saved_summary.mat', scenario_id)), 'summary', 'scenario_id', 'topology_ids');

end

function parsed = parse_saved_output_matrix(topology, Ptot_command, output_matrix)
type = topology; %#ok<NASGU>
cluster_parameters;

col = 1;
parsed = struct();
parsed.topology = topology;
parsed.topology_label = sprintf('M%d', topology);
parsed.Ptot_command = Ptot_command(:);
parsed.delta_t = delta_t;
parsed.t_command = t_command;
parsed.N_st = N_st;
parsed.N_sp = N_sp;
parsed.N_lyep = N_lyep;
parsed.N_cl = N_cl;
parsed.Qlye_nominal = Qlye_st;

parsed.P_st = output_matrix(:, col:(col+N_st-1))'; col = col + N_st;
parsed.N_H2_st = output_matrix(:, col:(col+N_st-1))'; col = col + N_st;
parsed.delta_I = output_matrix(:, col:(col+N_st-1))'; col = col + N_st;
parsed.I_st = output_matrix(:, col:(col+N_st-1))'; col = col + N_st;
parsed.delta_lyep = output_matrix(:, col:(col+N_lyep-1))'; col = col + N_lyep;
parsed.Qlye_st = output_matrix(:, col:(col+N_st-1))'; col = col + N_st;
parsed.Q_cl = output_matrix(:, col:(col+N_cl-1))'; col = col + N_cl;
parsed.U_cell = output_matrix(:, col:(col+N_st-1))'; col = col + N_st;
parsed.T_stout = output_matrix(:, col:(col+N_st-1))'; col = col + N_st;
parsed.HTO_sp15 = output_matrix(:, col:(col+N_sp-1))';
end

function T = build_saved_stack_table(parsed)
t15 = (0:parsed.t_command-1)' * parsed.delta_t;
T = table(t15, parsed.Ptot_command, 'VariableNames', {'time_h', 'power_command_MW'});

for s = 1:parsed.N_st
    T.(sprintf('stack%d_on', s)) = parsed.delta_I(s, :)';
    T.(sprintf('stack%d_power_MW', s)) = parsed.P_st(s, :)';
    T.(sprintf('stack%d_current_A', s)) = parsed.I_st(s, :)';
    T.(sprintf('stack%d_temp_C', s)) = parsed.T_stout(s, :)';
    T.(sprintf('stack%d_u_cell_V', s)) = parsed.U_cell(s, :)';
    T.(sprintf('stack%d_h2_Nm3s_proxy', s)) = parsed.N_H2_st(s, :)';
end

for p = 1:parsed.N_lyep
    T.(sprintf('loop%d_on', p)) = parsed.delta_lyep(p, :)';
end

for q = 1:parsed.N_cl
    T.(sprintf('cooler%d_MW', q)) = parsed.Q_cl(q, :)';
end
end

function T = build_saved_hto15_table(parsed)
t15 = (0:parsed.t_command-1)' * parsed.delta_t;
T = table(t15, 'VariableNames', {'time_h'});
for g = 1:parsed.N_sp
    T.(sprintf('sep%d_hto_frac', g)) = parsed.HTO_sp15(g, :)';
end
end
