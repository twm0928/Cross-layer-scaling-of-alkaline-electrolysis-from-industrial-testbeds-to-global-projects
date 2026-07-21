function summary = run_fig3b_representative_scenario(scenario_id, topology_ids, solver_options, output_tag)
%RUN_FIG3B_REPRESENTATIVE_SCENARIO Recompute one representative day for Fig. 3b.
%   summary = RUN_FIG3B_REPRESENTATIVE_SCENARIO() reruns the default
%   representative PV-like day (scenario 477) for M1-M7 and exports
%   reusable 15-min stack tables, 1-min HTO tables, MAT diagnostics, and
%   a compact summary under:
%     Workflow/2-Module/1-StateSpaceOptimization/outputs/fig3b_scenario_477
%
%   This script is intentionally isolated from the annual production runs.
%   It is used to generate one clean, fully comparable operating day for
%   manuscript figure design and mechanism inspection.

if nargin < 1 || isempty(scenario_id)
    scenario_id = 477;
end
if nargin < 2 || isempty(topology_ids)
    topology_ids = 1:7;
end
if nargin < 3 || isempty(solver_options)
    solver_options = struct();
end
if ~isfield(solver_options, 'TimeLimit')
    solver_options.TimeLimit = 900;
end
if ~isfield(solver_options, 'MIPGap')
    solver_options.MIPGap = 1e-4;
end
if nargin < 4 || isempty(output_tag)
    output_tag = sprintf('fig3b_scenario_%d', scenario_id);
end

module_root = fileparts(fileparts(mfilename('fullpath')));
input_file = fullfile(module_root, '..', 'data', 'input', 'P_command.mat');
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

summary_rows = cell(numel(topology_ids), 7);
for k = 1:numel(topology_ids)
    topology = topology_ids(k);
    topology_label = sprintf('M%d', topology);
    [output_matrix, output_obj, output_status, diag_out] = ...
        cluster_UC_I4(topology, Ptot_command, 4, [], solver_options);

    save(fullfile(output_dir, sprintf('%s_scenario_%d_diagnostics.mat', topology_label, scenario_id)), ...
        'output_matrix', 'output_obj', 'output_status', 'diag_out', 'scenario_id', 'topology', 'solver_options', '-v7.3');

    if isnumeric(output_matrix) && isscalar(output_matrix) && output_matrix == 0
        summary_rows{k} = {topology, topology_label, scenario_id, output_status, output_obj, 0, 0};
        continue;
    end

    stack_table = build_stack_table(diag_out);
    writetable(stack_table, fullfile(output_dir, sprintf('%s_scenario_%d_stack_15min.csv', topology_label, scenario_id)));

    hto_table = build_hto_table(diag_out);
    writetable(hto_table, fullfile(output_dir, sprintf('%s_scenario_%d_hto_1min.csv', topology_label, scenario_id)));

    summary_rows{k} = {topology, topology_label, scenario_id, output_status, output_obj, diag_out.N_st, diag_out.N_sp};
end

summary = cell2table(summary_rows, 'VariableNames', ...
    {'topology_id', 'topology_label', 'scenario_id', 'solver_status', 'objective_value', 'num_stacks', 'num_separator_groups'});
writetable(summary, fullfile(output_dir, sprintf('scenario_%d_summary.csv', scenario_id)));
save(fullfile(output_dir, sprintf('scenario_%d_summary.mat', scenario_id)), 'summary', 'scenario_id', 'topology_ids', 'solver_options');

end

function T = build_stack_table(diag_out)
t15 = (0:diag_out.t_command-1)' * diag_out.delta_t;
T = table(t15, diag_out.Ptot_command(:), 'VariableNames', {'time_h', 'power_command_MW'});

for s = 1:diag_out.N_st
    T.(sprintf('stack%d_on', s)) = diag_out.delta_I(s, :)';
    T.(sprintf('stack%d_power_MW', s)) = diag_out.P_st(s, :)';
    T.(sprintf('stack%d_current_A', s)) = diag_out.I_st(s, :)';
    T.(sprintf('stack%d_temp_C', s)) = diag_out.T_stout(s, :)';
    T.(sprintf('stack%d_u_cell_V', s)) = diag_out.U_cell(s, :)';
end

for p = 1:diag_out.N_lyep
    T.(sprintf('loop%d_on', p)) = diag_out.delta_lyep(p, :)';
end

for q = 1:size(diag_out.Q_cl, 1)
    T.(sprintf('cooler%d_MW', q)) = diag_out.Q_cl(q, :)';
end

for g = 1:diag_out.N_sp
    T.(sprintf('sep%d_hto_15min_frac', g)) = diag_out.HTO_sp15(g, :)';
end
end

function T = build_hto_table(diag_out)
t1 = (0:diag_out.t_HTO-1)' * diag_out.delta_t_HTO;
T = table(t1, 'VariableNames', {'time_h'});
for g = 1:diag_out.N_sp
    T.(sprintf('sep%d_hto_frac', g)) = diag_out.HTO_sp_1min(g, :)';
end
end
