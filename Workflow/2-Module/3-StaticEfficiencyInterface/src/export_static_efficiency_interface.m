% Export the module static voltage-reference interface for M1-M7.
%
% This helper table is retained for the degradation branch only. It stores
% topology-specific fresh-voltage reference points as a function of module
% power, together with the associated static hydrogen-production quantities.
% It intentionally excludes thermal and HTO dynamics; those remain in the
% dynamic-efficiency interface.

static_root = fileparts(fileparts(mfilename('fullpath')));
module_root = fileparts(static_root);
project_root = fileparts(fileparts(module_root));
data_dir = fullfile(static_root, 'outputs');
figure_dir = fullfile(project_root, 'Figure', 'Figure 3a', 'output');
if ~exist(data_dir, 'dir'); mkdir(data_dir); end
if ~exist(figure_dir, 'dir'); mkdir(figure_dir); end

topology_file = fullfile(module_root, 'data', 'input', 'topology.xlsx');
coe = readmatrix(topology_file, 'Sheet', 'Sheet1', 'Range', 'D2:J16')';
N = readmatrix(topology_file, 'Sheet', 'Sheet2', 'Range', 'B2:H8')';

topology_labels = {'M1', 'M2', 'M3', 'M4', 'M5', 'M6', 'M7'};
topology_groups = {'S1', 'S1', 'S1', 'S2', 'S2', 'S3', 'S3-seg'};

% Constants mirror cluster_parameters.m.
CAP_MW = 20;
eta_rectifier = 0.95;
faraday_C_mol = 96500;
lhv_MWh_per_tH2 = 33.33;
r1 = 9.44e-5 / 2;
r2 = -2.5e-7 / 2;
un = 1.509887;
T_nom_C = 70;

P_available_grid_MW = (0:0.25:20)';
rows = {};

for t = 1:7
    n_st = N(t, 1);
    coe_current = coe(t, 2);
    I_LL_A = 1381 * coe(t, 3);
    I_UL_A = 14000 * coe_current;
    N_cell = 200 * coe(t, 4);
    I_shunt_A = 1381 * coe(t, 3);
    stack_rating_MW = CAP_MW / n_st * coe(t, 1);

    k_voltage = (r1 + r2 * T_nom_C) / coe_current;
    p_dc_LL_MW = stack_power_MW(I_LL_A, N_cell, un, k_voltage);
    p_dc_UL_MW = stack_power_MW(I_UL_A, N_cell, un, k_voltage);

    for pidx = 1:numel(P_available_grid_MW)
        P_available_MW = P_available_grid_MW(pidx);
        P_dc_budget_MW = P_available_MW * eta_rectifier;

        best = make_zero_solution();
        for active = 1:n_st
            p_dc_per_stack_MW = min(P_dc_budget_MW / active, p_dc_UL_MW);
            if p_dc_per_stack_MW < p_dc_LL_MW || p_dc_per_stack_MW <= 0
                continue;
            end

            I_A = current_from_power(p_dc_per_stack_MW, N_cell, un, k_voltage);
            if I_A < I_LL_A - 1e-6 || I_A > I_UL_A + 1e-6
                continue;
            end

            h2_mol_s = active * (I_A - I_shunt_A) * N_cell / (2 * faraday_C_mol);
            h2_t_h = h2_mol_s * 3600 * 2 / 1e6;
            P_dc_used_MW = active * p_dc_per_stack_MW;
            P_ac_used_MW = P_dc_used_MW / eta_rectifier;
            eta_dc = safe_efficiency(h2_t_h, P_dc_used_MW, lhv_MWh_per_tH2);
            eta_ac = safe_efficiency(h2_t_h, P_ac_used_MW, lhv_MWh_per_tH2);

            if h2_t_h > best.h2_t_h
                best.active_stack_count = active;
                best.stack_current_A = I_A;
                best.stack_cell_voltage_V = un + k_voltage * I_A;
                best.stack_dc_power_MW = p_dc_per_stack_MW;
                best.module_dc_power_used_MW = P_dc_used_MW;
                best.module_ac_power_used_MW = P_ac_used_MW;
                best.h2_t_h = h2_t_h;
                best.efficiency_LHV_dc_basis = eta_dc;
                best.efficiency_LHV_ac_basis = eta_ac;
            end
        end

        rows(end + 1, :) = { ...
            topology_labels{t}, t, topology_groups{t}, P_available_MW, ...
            P_available_MW / CAP_MW, best.module_ac_power_used_MW, ...
            best.module_ac_power_used_MW / CAP_MW, best.module_dc_power_used_MW, ...
            best.h2_t_h, best.efficiency_LHV_ac_basis, ...
            best.efficiency_LHV_dc_basis, best.active_stack_count, ...
            best.stack_current_A, best.stack_cell_voltage_V, ...
            best.stack_dc_power_MW, stack_rating_MW, I_LL_A, I_UL_A, ...
            I_shunt_A, N_cell, T_nom_C ...
            }; %#ok<AGROW>
    end
end

static_table = cell2table(rows, 'VariableNames', { ...
    'topology_label', 'topology_id', 'topology_group', ...
    'available_module_power_MW', 'available_module_power_pu', ...
    'used_module_ac_power_MW', 'used_module_ac_power_pu', ...
    'used_module_dc_power_MW', 'hydrogen_t_per_h', ...
    'efficiency_LHV_ac_basis', 'efficiency_LHV_dc_basis', ...
    'active_stack_count', 'stack_current_A', 'stack_cell_voltage_V', ...
    'stack_dc_power_MW', 'stack_rating_MW', 'I_LL_A', 'I_UL_A', ...
    'I_shunt_A', 'N_cell', 'T_nom_C' ...
    });

numeric_vars = setdiff(static_table.Properties.VariableNames, ...
    {'topology_label', 'topology_group'});
for i = 1:numel(numeric_vars)
    static_table.(numeric_vars{i}) = ensure_numeric(static_table.(numeric_vars{i}));
end

csv_file = fullfile(data_dir, 'static_voltage_reference_M1_M7.csv');
xlsx_file = fullfile(data_dir, 'static_voltage_reference_M1_M7.xlsx');
writetable(static_table, csv_file);
writetable(static_table, xlsx_file, 'Sheet', 'static_interface');

plot_static_interface(static_table, figure_dir);

fprintf('Static voltage-reference interface export complete:\n');
fprintf('  %s\n', xlsx_file);

function p = stack_power_MW(I_A, N_cell, un, k_voltage)
p = N_cell * I_A * (un + k_voltage * I_A) / 1e6;
end

function I_A = current_from_power(P_MW, N_cell, un, k_voltage)
target = P_MW * 1e6 / N_cell;
if abs(k_voltage) < 1e-12
    I_A = target / un;
else
    disc = un^2 + 4 * k_voltage * target;
    I_A = (-un + sqrt(max(disc, 0))) / (2 * k_voltage);
end
end

function eta = safe_efficiency(h2_t_h, power_MW, lhv_MWh_per_tH2)
if power_MW <= 0
    eta = 0;
else
    eta = h2_t_h * lhv_MWh_per_tH2 / power_MW;
end
end

function s = make_zero_solution()
s = struct( ...
    'active_stack_count', 0, ...
    'stack_current_A', 0, ...
    'stack_cell_voltage_V', 0, ...
    'stack_dc_power_MW', 0, ...
    'module_dc_power_used_MW', 0, ...
    'module_ac_power_used_MW', 0, ...
    'h2_t_h', 0, ...
    'efficiency_LHV_dc_basis', 0, ...
    'efficiency_LHV_ac_basis', 0 ...
    );
end

function y = ensure_numeric(x)
if iscell(x)
    y = cell2mat(x);
else
    y = x;
end
end

function plot_static_interface(static_table, figure_dir)
hex2rgb = @(h) [hex2dec(h(2:3)) hex2dec(h(4:5)) hex2dec(h(6:7))] / 255;
group_colors = [
    hex2rgb('#F3A332')
    hex2rgb('#018A67')
    hex2rgb('#1868B2')
    ];
line_styles = {'-', '--', ':', '-', '--', '-', '--'};

fig = figure('Color', 'w', 'Units', 'centimeters', 'Position', [2 2 12 7]);
hold on;
for t = 1:7
    rows = static_table(static_table.topology_id == t, :);
    if t <= 3
        c = group_colors(1, :);
    elseif t <= 5
        c = group_colors(2, :);
    else
        c = group_colors(3, :);
    end
    plot(rows.used_module_ac_power_pu, rows.efficiency_LHV_ac_basis, ...
        line_styles{t}, 'Color', c, 'LineWidth', 1.8, ...
        'DisplayName', sprintf('M%d', t));
end
xlabel('Used module power (per unit)');
ylabel('Static efficiency');
box on;
grid off;
legend('Location', 'best', 'Box', 'off');
set(gca, 'FontName', 'Arial', 'FontSize', 9, 'LineWidth', 0.8);

exportgraphics(fig, fullfile(figure_dir, 'Static_efficiency_interface_M1_M7.png'), ...
    'Resolution', 600);
exportgraphics(fig, fullfile(figure_dir, 'Static_efficiency_interface_M1_M7.pdf'), ...
    'ContentType', 'vector');
savefig(fig, fullfile(figure_dir, 'Static_efficiency_interface_M1_M7.fig'));
close(fig);
end
