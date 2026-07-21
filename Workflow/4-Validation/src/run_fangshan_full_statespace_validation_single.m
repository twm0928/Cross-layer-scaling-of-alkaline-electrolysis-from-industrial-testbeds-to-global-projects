% Run strict single-5MW Fangshan/Stack A full state-space validation.
%
% This is the formal full module validation for the available field data:
% one Stack A electrolyser and one-to-one BOP. It uses a copied validation-only
% state-space model under src/full_state_space_single, leaving the main module
% workflow untouched.

script_dir = fileparts(mfilename('fullpath'));
ev_root = fileparts(script_dir);
workflow_root = fileparts(ev_root);
project_root = fileparts(workflow_root);

single_src = fullfile(ev_root, 'src', 'full_state_space_single');
addpath(single_src);

license_file = 'C:\gurobi1003\win64\bin\gurobi.lic';
if exist(license_file, 'file') == 2
    setenv('GRB_LICENSE_FILE', license_file);
end

day_to_run = '2023-11-05';
eta_rectifier = 0.95;
delta_t_h = 0.25;
Nm3_per_mol = 22.4 / 1000;

out_dir = fullfile(ev_root, 'outputs', 'step8_full_statespace_single5MW_validation');
if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end

profile_file = fullfile(ev_root, 'outputs', 'step1_stack_object', ...
    'fangshan_module_aligned_15min_profiles.csv');
profile = readtable(profile_file, 'TextType', 'string');
day_profile = profile(profile.day == string(day_to_run), :);
day_profile = sortrows(day_profile, 'slot');

if height(day_profile) ~= 96
    error('Expected 96 aligned 15 min points for %s, got %d.', ...
        day_to_run, height(day_profile));
end

P_dc_meas = max(day_profile.power_MW, 0);
Ptot_command = P_dc_meas / eta_rectifier;

solver_options = struct( ...
    'ShowProgress', 0, ...
    'MIPGap', 0.02, ...
    'TimeLimit', 600, ...
    'Threads', 1);

fprintf('Running strict single-5MW Stack A state-space validation for %s...\n', day_to_run);
fprintf('Input points: %d, measured DC power range: %.3f-%.3f MW.\n', ...
    numel(Ptot_command), min(P_dc_meas), max(P_dc_meas));

[output_matrix, output_obj, output_status] = cluster_UC_I4_fangshan_single( ...
    1, Ptot_command, 4, [], solver_options);

save(fullfile(out_dir, 'fangshan_single5MW_full_statespace_raw_result.mat'), ...
    'output_matrix', 'output_obj', 'output_status', 'Ptot_command', ...
    'P_dc_meas', 'day_profile', 'solver_options', 'day_to_run');

if ~(output_status == 0 || output_status == 3)
    error('single-5MW state-space model did not return a usable solution. status=%g', output_status);
end

P_st = output_matrix(:, 1);
NH2_mol_s = output_matrix(:, 2);
delta_I = output_matrix(:, 3);
I_st = output_matrix(:, 4);
delta_lye = output_matrix(:, 5);
Qlye = output_matrix(:, 6);
Qcl = output_matrix(:, 7);
U_cell = output_matrix(:, 8);
T_stout = output_matrix(:, 9);
HTO = output_matrix(:, 10);

H2_rate_pred_Nm3h = NH2_mol_s * Nm3_per_mol * 3600;
H2_step_pred_Nm3 = H2_rate_pred_Nm3h * delta_t_h;
H2_rate_meas_Nm3h = day_profile.H2_rate_Nm3h;
H2_step_meas_Nm3 = day_profile.H2_step_Nm3;

result = table();
result.day = day_profile.day;
result.slot = day_profile.slot;
result.time_h = day_profile.time_h;
result.P_dc_measured_MW = P_dc_meas;
result.P_command_model_MW = Ptot_command;
result.P_dc_model_MW = P_st;
result.delta_I_model = delta_I;
result.I_model_A = I_st;
result.delta_lye_model = delta_lye;
result.Qlye_model_m3h = Qlye;
result.Qcl_model_MW = Qcl;
result.U_cell_model_V = U_cell;
result.T_stout_model_C = T_stout;
result.HTO_model = HTO;
result.H2_rate_measured_Nm3h = H2_rate_meas_Nm3h;
result.H2_rate_model_Nm3h = H2_rate_pred_Nm3h;
result.H2_step_measured_Nm3 = H2_step_meas_Nm3;
result.H2_step_model_Nm3 = H2_step_pred_Nm3;
result.H2_rate_error_Nm3h = H2_rate_pred_Nm3h - H2_rate_meas_Nm3h;
result.H2_step_error_Nm3 = H2_step_pred_Nm3 - H2_step_meas_Nm3;
result.Tin_measured_C = day_profile.Tin_C;
result.ToutH_measured_C = day_profile.ToutH_C;
result.ToutO_measured_C = day_profile.ToutO_C;
result.Tout_mean_measured_C = mean([day_profile.ToutH_C, day_profile.ToutO_C], 2, 'omitnan');
result.Tout_error_C = result.T_stout_model_C - result.Tout_mean_measured_C;

writetable(result, fullfile(out_dir, ...
    'fangshan_single5MW_full_statespace_validation_profile.csv'));

metrics = table(strings(0, 1), strings(0, 1), zeros(0, 1), ...
    'VariableNames', {'scope', 'metric', 'value'});
metrics = append_metric(metrics, 'solver', 'status', output_status);
metrics = append_metric(metrics, 'solver', 'objective', output_obj);
metrics = append_metric(metrics, 'power_profile', 'n_points', height(result));
metrics = append_metric(metrics, 'power_profile', 'measured_dc_min_MW', min(P_dc_meas));
metrics = append_metric(metrics, 'power_profile', 'measured_dc_max_MW', max(P_dc_meas));
metrics = append_metric(metrics, 'power_profile', 'model_dc_rmse_MW', rmse(P_st, P_dc_meas));
metrics = append_metric(metrics, 'H2_rate_profile', 'MAE_Nm3h', mae(H2_rate_pred_Nm3h, H2_rate_meas_Nm3h));
metrics = append_metric(metrics, 'H2_rate_profile', 'RMSE_Nm3h', rmse(H2_rate_pred_Nm3h, H2_rate_meas_Nm3h));
metrics = append_metric(metrics, 'H2_rate_profile', 'MAPE', mape(H2_rate_pred_Nm3h, H2_rate_meas_Nm3h));
metrics = append_metric(metrics, 'H2_step_total', 'actual_sum_Nm3', sum(H2_step_meas_Nm3, 'omitnan'));
metrics = append_metric(metrics, 'H2_step_total', 'model_sum_Nm3', sum(H2_step_pred_Nm3, 'omitnan'));
metrics = append_metric(metrics, 'H2_step_total', 'relative_sum_error', ...
    (sum(H2_step_pred_Nm3, 'omitnan') - sum(H2_step_meas_Nm3, 'omitnan')) / ...
    sum(H2_step_meas_Nm3, 'omitnan'));
metrics = append_metric(metrics, 'temperature_profile', 'Tout_MAE_C', ...
    mae(result.T_stout_model_C, result.Tout_mean_measured_C));
metrics = append_metric(metrics, 'temperature_profile', 'Tout_RMSE_C', ...
    rmse(result.T_stout_model_C, result.Tout_mean_measured_C));
metrics = append_metric(metrics, 'operation_profile', 'on_fraction', mean(delta_I > 0.5, 'omitnan'));
metrics = append_metric(metrics, 'operation_profile', 'mean_model_current_A', mean(I_st, 'omitnan'));

warmup_mask = result.slot > 1;
metrics = append_metric(metrics, 'after_first_15min_warmup', 'n_points', sum(warmup_mask));
metrics = append_metric(metrics, 'after_first_15min_warmup', 'power_model_dc_rmse_MW', ...
    rmse(result.P_dc_model_MW(warmup_mask), result.P_dc_measured_MW(warmup_mask)));
metrics = append_metric(metrics, 'after_first_15min_warmup', 'H2_rate_MAE_Nm3h', ...
    mae(result.H2_rate_model_Nm3h(warmup_mask), result.H2_rate_measured_Nm3h(warmup_mask)));
metrics = append_metric(metrics, 'after_first_15min_warmup', 'H2_rate_RMSE_Nm3h', ...
    rmse(result.H2_rate_model_Nm3h(warmup_mask), result.H2_rate_measured_Nm3h(warmup_mask)));
metrics = append_metric(metrics, 'after_first_15min_warmup', 'H2_rate_MAPE', ...
    mape(result.H2_rate_model_Nm3h(warmup_mask), result.H2_rate_measured_Nm3h(warmup_mask)));
metrics = append_metric(metrics, 'after_first_15min_warmup', 'H2_actual_sum_Nm3', ...
    sum(result.H2_step_measured_Nm3(warmup_mask), 'omitnan'));
metrics = append_metric(metrics, 'after_first_15min_warmup', 'H2_model_sum_Nm3', ...
    sum(result.H2_step_model_Nm3(warmup_mask), 'omitnan'));
metrics = append_metric(metrics, 'after_first_15min_warmup', 'H2_relative_sum_error', ...
    (sum(result.H2_step_model_Nm3(warmup_mask), 'omitnan') - ...
    sum(result.H2_step_measured_Nm3(warmup_mask), 'omitnan')) / ...
    sum(result.H2_step_measured_Nm3(warmup_mask), 'omitnan'));
metrics = append_metric(metrics, 'after_first_15min_warmup', 'Tout_MAE_C', ...
    mae(result.T_stout_model_C(warmup_mask), result.Tout_mean_measured_C(warmup_mask)));
metrics = append_metric(metrics, 'after_first_15min_warmup', 'Tout_RMSE_C', ...
    rmse(result.T_stout_model_C(warmup_mask), result.Tout_mean_measured_C(warmup_mask)));

writetable(metrics, fullfile(out_dir, ...
    'fangshan_single5MW_full_statespace_validation_metrics.csv'));

write_readme(out_dir, day_to_run, output_status, output_obj, metrics);

fprintf('Strict single-5MW validation finished. status=%g, obj=%.6g.\n', ...
    output_status, output_obj);
fprintf('Results written to %s\n', out_dir);

function y = rmse(pred, obs)
mask = isfinite(pred) & isfinite(obs);
y = sqrt(mean((pred(mask) - obs(mask)).^2));
end

function y = mae(pred, obs)
mask = isfinite(pred) & isfinite(obs);
y = mean(abs(pred(mask) - obs(mask)));
end

function y = mape(pred, obs)
mask = isfinite(pred) & isfinite(obs) & abs(obs) > 1e-9;
y = mean(abs((pred(mask) - obs(mask)) ./ obs(mask)));
end

function metrics = append_metric(metrics, scope, metric, value)
new_row = table(string(scope), string(metric), value, ...
    'VariableNames', {'scope', 'metric', 'value'});
metrics = [metrics; new_row];
end

function write_readme(out_dir, day_to_run, output_status, output_obj, metrics)
readme_file = fullfile(out_dir, 'README.md');
fid = fopen(readme_file, 'w');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '# Step 8 Strict Single-5MW Full State-Space Validation\n\n');
fprintf(fid, 'Validation day: `%s`.\n\n', day_to_run);
fprintf(fid, 'This step uses the validation-only function `cluster_UC_I4_fangshan_single.m`, which is copied from the main module model but forced to represent one Stack A electrolyser and one-to-one Fangshan BOP. The main module workflow is not modified.\n\n');
fprintf(fid, 'Stack A settings include 400 cells, 1.54 m2 electrode area, 6600 A rated current, 4.752 MW rated DC power and 100 m3 h-1 lye flow. The voltage relation uses the Step 2 fitted Stack A voltage coefficients.\n\n');
fprintf(fid, 'The field power is the measured DC stack-side power (`IA6001 * IV6001`). Because the module optimisation compares `P_st / eta_rectifier` against `Ptot_command`, this script uses `Ptot_command = P_DC / 0.95` to keep the optimised DC stack power on the same boundary as the measured DC power.\n\n');
fprintf(fid, 'Solver status: `%g`; objective: `%.6g`.\n\n', output_status, output_obj);
fprintf(fid, 'Generated files:\n\n');
fprintf(fid, '- `fangshan_single5MW_full_statespace_raw_result.mat`: raw MATLAB optimisation output.\n');
fprintf(fid, '- `fangshan_single5MW_full_statespace_validation_profile.csv`: time-series validation profile.\n');
fprintf(fid, '- `fangshan_single5MW_full_statespace_validation_metrics.csv`: quantitative validation metrics.\n\n');
fprintf(fid, 'Key metrics:\n\n');
fprintf(fid, '| Scope | Metric | Value |\n');
fprintf(fid, '|---|---|---:|\n');
for i = 1:height(metrics)
    fprintf(fid, '| %s | %s | %.6g |\n', ...
        metrics.scope(i), metrics.metric(i), metrics.value(i));
end
end
