% Preview quasi-static module efficiency curves for M1-M7.
%
% Each point is obtained by running the original module optimisation model
% under a one-step constant-power command. This is an instantaneous static
% preview for judging the curve shape before running expensive full-day
% constant-profile simulations.

static_root = fileparts(fileparts(mfilename('fullpath')));
module_root = fileparts(static_root);
project_root = fileparts(fileparts(module_root));
dynamic_dir = fullfile(module_root, '1-StateSpaceOptimization', 'src');
data_dir = fullfile(static_root, 'outputs');
figure_dir = fullfile(project_root, 'Figure', 'Figure 3a', 'output');
clean_dir = fullfile(project_root, 'Clean');
if ~exist(data_dir, 'dir'); mkdir(data_dir); end
if ~exist(figure_dir, 'dir'); mkdir(figure_dir); end
if ~exist(clean_dir, 'dir'); mkdir(clean_dir); end
addpath(dynamic_dir);

% Gurobi should be configured through the MATLAB path or GRB_LICENSE_FILE.
% No machine-specific licence path is set here.

power_grid_MW = 0:1:20;
horizon_steps = 1;
topology_ids = 1:7;
topology_labels = {'M1', 'M2', 'M3', 'M4', 'M5', 'M6', 'M7'};
topology_groups = {'S1', 'S1', 'S1', 'S2', 'S2', 'S3', 'S3-seg'};
num_stacks = [4 4 4 2 2 1 1];

delta_t_h = 0.25;
eta_rectifier = 0.95;
lhv_MWh_per_tH2 = 33.33;
result_file = fullfile(data_dir, 'quasi_static_instant_preview_M1_M7.mat');
csv_file = fullfile(data_dir, 'quasi_static_instant_preview_M1_M7.csv');
xlsx_file = fullfile(data_dir, 'quasi_static_instant_preview_M1_M7.xlsx');
progress_file = fullfile(clean_dir, 'quasi_static_instant_preview_M1_M7_progress.txt');

rows = {};
tic;
write_progress(progress_file, sprintf('Instantaneous quasi-static preview start: %d topologies x %d power points, horizon_steps=%d\n', ...
    numel(topology_ids), numel(power_grid_MW), horizon_steps), 'w');

for ti = 1:numel(topology_ids)
    topology = topology_ids(ti);
    n_st = num_stacks(ti);
    for pi = 1:numel(power_grid_MW)
        P_available_MW = power_grid_MW(pi);

        if P_available_MW == 0
            y = [];
            obj = 0;
            status = 0;
            H_t_day = 0;
            P_dc_MWh = 0;
            P_ac_MWh = 0;
            eta_dc = 0;
            eta_ac = 0;
            active_fraction = 0;
        else
            Ptot_command = P_available_MW * ones(horizon_steps, 1);
            point_timer = tic;
            [y, obj, status] = cluster_UC_I4(topology, Ptot_command, 4, []);
            solve_s = toc(point_timer);

            if isnumeric(y) && numel(y) > 1 && (status == 0 || status == 3)
                h2_mol_s = y(:, n_st + 1:2 * n_st);
                p_stack_mw = y(:, 1:n_st);
                delta_i = y(:, 2 * n_st + 1:3 * n_st);
                horizon_h = size(y, 1) * delta_t_h;
                H_t_total = sum(h2_mol_s(:)) * delta_t_h * 3600 * 2 / 1e6;
                P_dc_MWh = sum(p_stack_mw(:)) * delta_t_h;
                P_ac_MWh = P_dc_MWh / eta_rectifier;
                H_t_day = H_t_total / horizon_h * 24;
                eta_dc = safe_efficiency(H_t_total, P_dc_MWh, lhv_MWh_per_tH2);
                eta_ac = safe_efficiency(H_t_total, P_ac_MWh, lhv_MWh_per_tH2);
                active_fraction = mean(delta_i(:));
            else
                H_t_day = 0;
                P_dc_MWh = 0;
                P_ac_MWh = 0;
                eta_dc = 0;
                eta_ac = 0;
                active_fraction = 0;
                solve_s = toc(point_timer);
            end

            write_progress(progress_file, sprintf( ...
                'M%d P=%.1f MW status=%g obj=%.10g eta_dc=%.5f eta_ac=%.5f solve=%.1f s elapsed=%.1f s\n', ...
                topology, P_available_MW, status, obj, eta_dc, eta_ac, solve_s, toc), 'a');
        end

        rows(end + 1, :) = { ...
            topology_labels{topology}, topology, topology_groups{topology}, ...
            P_available_MW, P_available_MW / 20, P_dc_MWh / max(horizon_steps * delta_t_h, eps), P_ac_MWh / max(horizon_steps * delta_t_h, eps), ...
            H_t_day / 24, H_t_day, P_dc_MWh, P_ac_MWh, eta_dc, eta_ac, ...
            active_fraction, status, obj ...
            }; %#ok<AGROW>

        preview_table = build_table(rows);
        save(result_file, 'preview_table', 'power_grid_MW');
        writetable(preview_table, csv_file);
        writetable(preview_table, xlsx_file, 'Sheet', 'preview');
    end
end

preview_table = build_table(rows);
plot_preview(preview_table, figure_dir);
write_progress(progress_file, sprintf('Instantaneous quasi-static preview complete in %.1f s\n', toc), 'a');

fprintf('Instantaneous quasi-static preview complete:\n');
fprintf('  %s\n', xlsx_file);
fprintf('  %s\n', fullfile(figure_dir, 'Quasi_static_instant_preview_M1_M7.png'));

function t = build_table(rows)
t = cell2table(rows, 'VariableNames', { ...
    'topology_label', 'topology_id', 'topology_group', ...
    'available_module_power_MW', 'available_module_power_pu', ...
    'used_dc_power_MW_mean', 'used_ac_power_MW_mean', ...
    'hydrogen_t_per_h', 'hydrogen_t_per_day', ...
    'used_dc_energy_MWh_day', 'used_ac_energy_MWh_day', ...
    'efficiency_LHV_dc_basis', 'efficiency_LHV_ac_basis', ...
    'active_fraction', 'status', 'objective' ...
    });
numeric_vars = setdiff(t.Properties.VariableNames, {'topology_label', 'topology_group'});
for k = 1:numel(numeric_vars)
    if iscell(t.(numeric_vars{k}))
        t.(numeric_vars{k}) = cell2mat(t.(numeric_vars{k}));
    end
end
end

function eta = safe_efficiency(h2_t, energy_MWh, lhv_MWh_per_tH2)
if energy_MWh <= 0
    eta = 0;
else
    eta = h2_t * lhv_MWh_per_tH2 / energy_MWh;
end
end

function write_progress(file, text, mode)
fid = fopen(file, mode);
fprintf(fid, '%s', text);
fclose(fid);
end

function plot_preview(t, figure_dir)
hex2rgb = @(h) [hex2dec(h(2:3)) hex2dec(h(4:5)) hex2dec(h(6:7))] / 255;
group_colors = [
    hex2rgb('#F3A332')
    hex2rgb('#018A67')
    hex2rgb('#1868B2')
    ];
line_styles = {'-', '--', ':', '-', '--', '-', '--'};

fig = figure('Color', 'w', 'Units', 'centimeters', 'Position', [2 2 12 7]);
hold on;
for topology = 1:7
    rows = t(t.topology_id == topology, :);
    if topology <= 3
        c = group_colors(1, :);
    elseif topology <= 5
        c = group_colors(2, :);
    else
        c = group_colors(3, :);
    end
    plot(rows.available_module_power_pu, rows.efficiency_LHV_dc_basis, ...
        line_styles{topology}, 'Color', c, 'LineWidth', 1.8, ...
        'DisplayName', sprintf('M%d', topology));
end
xlabel('Constant module input power (per unit)');
ylabel('Quasi-static efficiency');
box on;
grid off;
legend('Location', 'best', 'Box', 'off');
set(gca, 'FontName', 'Arial', 'FontSize', 9, 'LineWidth', 0.8);

exportgraphics(fig, fullfile(figure_dir, 'Quasi_static_instant_preview_M1_M7.png'), ...
    'Resolution', 600);
exportgraphics(fig, fullfile(figure_dir, 'Quasi_static_instant_preview_M1_M7.pdf'), ...
    'ContentType', 'vector');
savefig(fig, fullfile(figure_dir, 'Quasi_static_instant_preview_M1_M7.fig'));
close(fig);
end
