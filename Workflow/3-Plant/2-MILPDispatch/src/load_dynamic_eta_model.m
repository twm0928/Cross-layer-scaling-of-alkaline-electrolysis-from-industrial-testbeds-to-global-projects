function mdl = load_dynamic_eta_model(topology_id, cfg)
%LOAD_DYNAMIC_ETA_MODEL Load the dynamic module-efficiency surrogate.

if nargin < 2 || isempty(cfg)
    cfg = plant_case_config();
end

model_file = fullfile(cfg.dynamic_eta_model_dir, sprintf('eta_model_topo%d.mat', topology_id));

if ~isfile(model_file)
    error('Missing dynamic eta model for topology %d: %s', topology_id, model_file);
end

mdl = loadLearnerForCoder(model_file);
end
