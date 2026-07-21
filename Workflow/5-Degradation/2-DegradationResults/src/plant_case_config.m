function cfg = plant_case_config()
%PLANT_CASE_CONFIG Local plant settings copied into the degradation branch.
%
% This local copy keeps the degradation workflow self-contained at the
% code level while preserving the same plant-side benchmark boundary.

src_dir = fileparts(mfilename('fullpath'));
results_root = fileparts(src_dir);
degradation_root = fileparts(results_root);
workflow_root = fileparts(degradation_root);
plant_root = fullfile(workflow_root, '3-Plant');
project_root = fileparts(workflow_root);

cfg = struct();
cfg.module_rating_MW = 20;
cfg.scale_N_module = 20;
cfg.n_modules = cfg.scale_N_module;
cfg.delta_t_hour = 0.25;
cfg.profile_scale_MW = cfg.module_rating_MW;
cfg.plant_rating_MW = cfg.n_modules * cfg.module_rating_MW;
cfg.theta_grid = 0:0.1:1;
cfg.milp_power_step_MW = 0.1;
cfg.topology_ids = 1:7;
cfg.topology_labels = {'M1', 'M2', 'M3', 'M4', 'M5', 'M6', 'M7'};
cfg.case_names = {'PV', 'WT', 'Constant'};

cfg.src_dir = src_dir;
cfg.results_root = results_root;
cfg.degradation_root = degradation_root;
cfg.workflow_root = workflow_root;
cfg.plant_root = plant_root;
cfg.project_root = project_root;

cfg.profile_file = fullfile(plant_root, 'data', 'input', 'Plant profiles.xlsx');
cfg.module_static_map_file = fullfile(plant_root, 'data', 'module_static_interface', ...
    'module_static_ph_map_M1_M7_final_locked.csv');
cfg.constant_profile_steps = 35040;
end
