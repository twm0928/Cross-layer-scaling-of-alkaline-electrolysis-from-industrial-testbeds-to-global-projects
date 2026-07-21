function cfg = degradation_results_config()
%DEGRADATION_RESULTS_CONFIG Configuration for the current-version result-side workflow.

src_dir = fileparts(mfilename('fullpath'));
results_root = fileparts(src_dir);
degradation_root = fileparts(results_root);
workflow_root = fileparts(degradation_root);
model_root = fullfile(degradation_root, '1-DegradationModel');

cfg = struct();
cfg.src_dir = src_dir;
cfg.results_root = results_root;
cfg.degradation_root = degradation_root;
cfg.workflow_root = workflow_root;
cfg.model_root = model_root;

cfg.outputs_dir = fullfile(results_root, 'outputs');
cfg.feature_output_dir = fullfile(cfg.outputs_dir, 'daily_feature_tables');
cfg.prediction_output_dir = fullfile(cfg.outputs_dir, 'daily_predictions');
cfg.hydrogen_interface_output_dir = fullfile(cfg.outputs_dir, 'daily_hydrogen_interface');
cfg.summary_output_dir = fullfile(cfg.outputs_dir, 'summaries');

cfg.module_root = fullfile(workflow_root, '2-Module');
cfg.dynamic_feature_src = fullfile(cfg.module_root, '2-DynamicEfficiencySurrogate', 'src');
cfg.topology_file = fullfile(cfg.module_root, 'data', 'input', 'topology.xlsx');
cfg.static_voltage_reference_csv = fullfile(cfg.module_root, '3-StaticEfficiencyInterface', ...
    'outputs', 'static_voltage_reference_M1_M7.csv');

cfg.plant_root = fullfile(workflow_root, '3-Plant');
% Use the current shared 6-feature LSBoost models from the module workflow.
cfg.dynamic_eta_model_dir = fullfile(cfg.module_root, 'data', 'dynamic_models');

cfg.current_version_dir = fullfile(model_root, 'current_version');
cfg.current_model_dir = fullfile(cfg.current_version_dir, 'step2_model_benchmark');
cfg.active_model_file = fullfile(cfg.current_model_dir, 'best_model_refit.mat');
cfg.active_metrics_csv = fullfile(cfg.current_model_dir, 'best_model_metrics.csv');

cfg.feature_columns = { ...
    'elapsed_day', ...
    'sqrt_elapsed_day', ...
    'log1p_elapsed_day', ...
    'daily_eflh_h', ...
    'mean_power_frac_all', ...
    'mean_power_frac_on', ...
    'p90_power_frac_on', ...
    'high_load_hours', ...
    'ramp_abs_mean_frac', ...
    'ramp_abs_max_frac', ...
    'rated_hours', ...
    'transition_hours', ...
    'stop_hours', ...
    'start_count', ...
    'stop_count', ...
    'cum_daily_eflh_h', ...
    'cum_high_load_hours', ...
    'cum_start_count', ...
    'cum_stop_count'};

cfg.delta_t_hour = 0.25;
cfg.module_rating_MW = 20;
cfg.on_power_fraction = 0.02;
cfg.high_load_power_fraction = 0.80;
cfg.rated_power_fraction = 0.90;
cfg.transition_state_value = 0.5;

cfg.topology_ids = 1:7;
cfg.topology_labels = {'M1', 'M2', 'M3', 'M4', 'M5', 'M6', 'M7'};

ensure_dir(cfg.outputs_dir);
ensure_dir(cfg.feature_output_dir);
ensure_dir(cfg.prediction_output_dir);
ensure_dir(cfg.hydrogen_interface_output_dir);
ensure_dir(cfg.summary_output_dir);
end

function ensure_dir(path_str)
if ~exist(path_str, 'dir')
    mkdir(path_str);
end
end
