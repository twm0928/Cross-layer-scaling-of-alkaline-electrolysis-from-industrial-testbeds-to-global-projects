function cfg = pipeline_config()
% Central configuration for the R1 pipeline rebuild.

cfg = struct();

cfg.root = fileparts(fileparts(mfilename('fullpath')));
cfg.workflow_root = fileparts(cfg.root);

% All R1 code must be self-contained inside Workflow. Do not depend on any
% external manuscript-submission folder or user-specific absolute path.
cfg.stack_model_dir = fullfile(cfg.root, 'src');
cfg.plant_model_dir = fullfile(cfg.workflow_root, '3-Plant', 'src');
cfg.project_model_dir = fullfile(cfg.workflow_root, '4-Project', 'src');
cfg.module_model_dir = fullfile(cfg.workflow_root, '2-Module', 'src');

cfg.output_dir = fullfile(cfg.root, 'outputs');
cfg.data_dir = fullfile(cfg.root, 'data');

cfg.Pmax_module_MW = 20;
cfg.LHV_kWh_per_kg = 33.33;
cfg.default_delta_t_hour = 0.25;

cfg.stack_sizes_MW = [5, 10, 20];
cfg.stack_geometries = {'equal_width', 'equal_length', 'equal_VA'};
cfg.flow_segmentation_k = [1, 2, 4];
cfg.flow_segmentation_pipe_k = 4;
cfg.flow_segmentation_area_policy = 'total_area_conserved';

cfg.module_topologies = 1:6;
cfg.theta_grid = 0:0.1:1;

cfg.static_power_grid_pu = 0:0.1:1;
end
