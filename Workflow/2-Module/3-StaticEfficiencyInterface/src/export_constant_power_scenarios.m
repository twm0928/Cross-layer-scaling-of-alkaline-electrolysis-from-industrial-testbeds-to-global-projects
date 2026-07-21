% Export existing constant-power daily scenarios from the 240-profile set.
%
% This script does not run the module optimisation. It only extracts the
% already-computed dynamic results for the constant-profile scenarios
% embedded in idx_gen, giving a quasi-static interface that remains
% consistent with the original Figure 3a dynamic-result format.

module_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
project_root = fileparts(fileparts(module_root));
figure_root = fullfile(project_root, 'Figure', 'Figure 3a');
static_root = fileparts(fileparts(mfilename('fullpath')));
data_dir = fullfile(static_root, 'outputs');
figure_data_dir = fullfile(figure_root, 'data');
output_dir = fullfile(figure_root, 'output');
if ~exist(data_dir, 'dir'); mkdir(data_dir); end
if ~exist(figure_data_dir, 'dir'); mkdir(figure_data_dir); end
if ~exist(output_dir, 'dir'); mkdir(output_dir); end

addpath(fileparts(mfilename('fullpath')));

input_dir = fullfile(module_root, 'data', 'input');
load(fullfile(input_dir, 'P_command.mat'), 'P_command');

idx_gen = [732:2:770 771:1:830 831:5:876 881:5:926 883:5:928 ...
    931:5:976 932:5:977 933:5:978 934:5:979 981:5:1026 ...
    982:5:1027 983:5:1028 984:5:1029 1031:1080];

delta_t_h = 0.25;
lhv_MWh_per_tH2 = 33.33;
module_rating_MW = 20;

topology_ids = 1:7;
topology_labels = {'M1', 'M2', 'M3', 'M4', 'M5', 'M6', 'M7'};
topology_groups = {'S1', 'S1', 'S1', 'S2', 'S2', 'S3', 'S3-seg'};
num_stacks = [4 4 4 2 2 1 1];

profile_std = std(P_command(idx_gen, :), 0, 2);
profile_mean = mean(P_command(idx_gen, :), 2);
is_constant = profile_std < 1e-9 & profile_mean > 0;
constant_scenario_ids = idx_gen(is_constant);
constant_power_MW = profile_mean(is_constant);

rows = cell(numel(topology_ids) * numel(constant_scenario_ids), 16);
r = 0;

for ti = 1:numel(topology_ids)
    topology_id = topology_ids(ti);
    result_file = module_result_file(module_root, topology_id);
    data = load(result_file, 'result', 'status', 'obj');
    n_st = num_stacks(ti);

    for si = 1:numel(constant_scenario_ids)
        scenario_id = constant_scenario_ids(si);
        p_command_MW = constant_power_MW(si);
        command_energy_MWh = p_command_MW * 24;
        y = data.result{scenario_id, 4};

        has_result = isnumeric(y) && numel(y) > 1;
        hydrogen_t = 0;
        stack_energy_MWh = 0;
        eta_stack_basis = 0;
        eta_command_basis = 0;
        mean_stack_power_MW = 0;
        solver_status = NaN;
        objective = NaN;

        if isfield(data, 'status') && numel(data.status) >= scenario_id
            solver_status = data.status(scenario_id, 4);
        end
        if isfield(data, 'obj') && numel(data.obj) >= scenario_id
            objective = data.obj(scenario_id, 4);
        end

        if has_result
            p_stack_mw = y(:, 1:n_st);
            h2_mol_s = y(:, n_st + 1:2 * n_st);
            hydrogen_t = sum(h2_mol_s(:)) * delta_t_h * 3600 * 2 / 1e6;
            stack_energy_MWh = sum(p_stack_mw(:)) * delta_t_h;
            mean_stack_power_MW = stack_energy_MWh / 24;
            if stack_energy_MWh > 0
                eta_stack_basis = hydrogen_t * lhv_MWh_per_tH2 / stack_energy_MWh;
            end
            if command_energy_MWh > 0
                eta_command_basis = hydrogen_t * lhv_MWh_per_tH2 / command_energy_MWh;
            end
        end

        r = r + 1;
        rows(r, :) = { ...
            scenario_id, p_command_MW, p_command_MW / module_rating_MW, ...
            topology_labels{ti}, topology_id, topology_groups{ti}, ...
            hydrogen_t, hydrogen_t / 24, stack_energy_MWh, command_energy_MWh, ...
            mean_stack_power_MW, eta_stack_basis, eta_command_basis, ...
            has_result && isfinite(eta_stack_basis) && eta_stack_basis > 0, ...
            solver_status, objective ...
            };
    end
end

constant_table = cell2table(rows, 'VariableNames', { ...
    'scenario_id', 'constant_power_MW', 'constant_power_pu', ...
    'topology_label', 'topology_id', 'topology_group', ...
    'hydrogen_t_per_day', 'hydrogen_t_per_h', ...
    'stack_energy_MWh_per_day', 'command_energy_MWh_per_day', ...
    'mean_stack_power_MW', 'efficiency_LHV_stack_basis', ...
    'efficiency_LHV_command_basis', 'has_valid_dynamic_result', ...
    'solver_status', 'objective' ...
    });

constant_table.scenario_id = ensure_numeric(constant_table.scenario_id);
constant_table.constant_power_MW = ensure_numeric(constant_table.constant_power_MW);
constant_table.constant_power_pu = ensure_numeric(constant_table.constant_power_pu);
constant_table.topology_id = ensure_numeric(constant_table.topology_id);
constant_table.hydrogen_t_per_day = ensure_numeric(constant_table.hydrogen_t_per_day);
constant_table.hydrogen_t_per_h = ensure_numeric(constant_table.hydrogen_t_per_h);
constant_table.stack_energy_MWh_per_day = ensure_numeric(constant_table.stack_energy_MWh_per_day);
constant_table.command_energy_MWh_per_day = ensure_numeric(constant_table.command_energy_MWh_per_day);
constant_table.mean_stack_power_MW = ensure_numeric(constant_table.mean_stack_power_MW);
constant_table.efficiency_LHV_stack_basis = ensure_numeric(constant_table.efficiency_LHV_stack_basis);
constant_table.efficiency_LHV_command_basis = ensure_numeric(constant_table.efficiency_LHV_command_basis);
constant_table.has_valid_dynamic_result = ensure_numeric(constant_table.has_valid_dynamic_result);
constant_table.solver_status = ensure_numeric(constant_table.solver_status);
constant_table.objective = ensure_numeric(constant_table.objective);

scenario_table = table(constant_scenario_ids(:), constant_power_MW(:), ...
    constant_power_MW(:) / module_rating_MW, ...
    'VariableNames', {'scenario_id', 'constant_power_MW', 'constant_power_pu'});

csv_file = fullfile(data_dir, 'Fig3a_R1_constant_power_scenarios_M1_M7.csv');
xlsx_file = fullfile(data_dir, 'Fig3a_R1_constant_power_scenarios_M1_M7.xlsx');
mat_file = fullfile(data_dir, 'Fig3a_R1_constant_power_scenarios_M1_M7.mat');
figure_csv_file = fullfile(figure_data_dir, 'Fig3a_R1_constant_power_scenarios_M1_M7.csv');
figure_xlsx_file = fullfile(figure_data_dir, 'Fig3a_R1_constant_power_scenarios_M1_M7.xlsx');
figure_mat_file = fullfile(figure_data_dir, 'Fig3a_R1_constant_power_scenarios_M1_M7.mat');
writetable(constant_table, csv_file);
writetable(scenario_table, xlsx_file, 'Sheet', 'constant_scenarios');
writetable(constant_table, xlsx_file, 'Sheet', 'topology_results');
save(mat_file, 'constant_table', 'scenario_table');
writetable(constant_table, figure_csv_file);
writetable(scenario_table, figure_xlsx_file, 'Sheet', 'constant_scenarios');
writetable(constant_table, figure_xlsx_file, 'Sheet', 'topology_results');
save(figure_mat_file, 'constant_table', 'scenario_table');

plot_constant_efficiency(constant_table, output_dir);

fprintf('Constant-power scenarios extracted:\n');
disp(scenario_table);
fprintf('Outputs:\n');
fprintf('  %s\n', xlsx_file);
fprintf('  %s\n', fullfile(output_dir, 'Fig3a_R1_constant_power_scenarios_M1_M7.png'));

function file = module_result_file(module_root, topology_id)
file = fullfile(module_root, 'data', 'results', sprintf('results_topology_%d.mat', topology_id));
if ~isfile(file)
    error('Missing result file: %s', file);
end
end

function x = ensure_numeric(x)
if iscell(x)
    x = cell2mat(x);
end
end

function plot_constant_efficiency(tbl, output_dir)
colors = [
    0.93 0.49 0.13
    0.76 0.54 0.18
    0.49 0.70 0.23
    0.16 0.62 0.56
    0.10 0.45 0.70
    0.27 0.27 0.27
    0.55 0.55 0.55
    ];

fig = figure('Color', 'w', 'Position', [100 100 760 430]);
hold on;
for topology_id = 1:7
    rows = tbl(tbl.topology_id == topology_id & tbl.has_valid_dynamic_result == 1, :);
    plot(rows.constant_power_pu, rows.efficiency_LHV_command_basis, ...
        '-o', 'LineWidth', 1.6, 'MarkerSize', 4.5, ...
        'Color', colors(topology_id, :), ...
        'DisplayName', rows.topology_label{1});
end
box on;
set(gca, 'FontName', 'Arial', 'FontSize', 10, 'LineWidth', 0.8);
xlabel('Constant module input power (per unit)');
ylabel('Module efficiency (LHV, command basis)');
xlim([0 1]);
ylim([0 0.75]);
legend('Location', 'southeast', 'Box', 'off', 'NumColumns', 2);

png_file = fullfile(output_dir, 'Fig3a_R1_constant_power_scenarios_M1_M7.png');
pdf_file = fullfile(output_dir, 'Fig3a_R1_constant_power_scenarios_M1_M7.pdf');
fig_file = fullfile(output_dir, 'Fig3a_R1_constant_power_scenarios_M1_M7.fig');
saveas(fig, png_file);
saveas(fig, pdf_file);
savefig(fig, fig_file);
close(fig);
end
