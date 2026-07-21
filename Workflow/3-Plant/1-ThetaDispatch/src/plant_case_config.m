function cfg = plant_case_config()
%PLANT_CASE_CONFIG Central settings for the R1 plant-layer benchmark.
%
% The annual PV/WT profiles are stored as per-module MW commands. The
% original plant code uses N_module = 20 as the plant-scale multiplier, then
% sets the actual module count as ceil(max(P_total) / 20 MW). This gives
% 16 modules for PV and 20 modules for WT.

cfg = struct();
cfg.module_rating_MW = 20;
cfg.scale_N_module = 20;
cfg.n_modules = cfg.scale_N_module; % default only; case-specific cfg overrides this.
cfg.delta_t_hour = 0.25;
cfg.profile_scale_MW = cfg.module_rating_MW;
cfg.plant_rating_MW = cfg.n_modules * cfg.module_rating_MW;
cfg.theta_grid = 0:0.1:1;
cfg.milp_power_step_MW = 0.1;
cfg.topology_ids = 1:7;
cfg.topology_labels = {'M1', 'M2', 'M3', 'M4', 'M5', 'M6', 'M7'};
cfg.case_names = {'PV', 'WT', 'Constant'};

flow_root = fileparts(fileparts(mfilename('fullpath')));
plant_root = fileparts(flow_root);
workflow_root = fileparts(plant_root);
project_root = fileparts(workflow_root);

cfg.flow_root = flow_root;
cfg.flow_src_dir = fullfile(flow_root, 'src');
cfg.plant_root = plant_root;
cfg.workflow_root = workflow_root;
cfg.project_root = project_root;
cfg.module_root = fullfile(workflow_root, '2-Module');
cfg.profile_file = fullfile(plant_root, 'data', 'input', 'Plant profiles.xlsx');
cfg.dynamic_eta_model_dir = fullfile(cfg.module_root, 'data', 'dynamic_models');
cfg.module_static_map_file = fullfile(plant_root, 'data', 'module_static_interface', ...
    'module_static_ph_map_M1_M7_final_locked.csv');
cfg.constant_profile_steps = 35040;
cfg.output_dir = fullfile(flow_root, 'outputs');
cfg.figure_dir = fullfile(project_root, 'Figure', 'Figure 4', 'data');
cfg.figure_output_dir = fullfile(project_root, 'Figure', 'Figure 4', 'output');

if ~exist(cfg.output_dir, 'dir'); mkdir(cfg.output_dir); end
if ~exist(cfg.figure_dir, 'dir'); mkdir(cfg.figure_dir); end
if ~exist(cfg.figure_output_dir, 'dir'); mkdir(cfg.figure_output_dir); end
end
