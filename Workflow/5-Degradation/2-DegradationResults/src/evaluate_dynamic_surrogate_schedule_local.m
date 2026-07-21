function eval = evaluate_dynamic_surrogate_schedule_local(Pmodule_MW, topology_id, cfg)
%EVALUATE_DYNAMIC_SURROGATE_SCHEDULE_LOCAL
% Local copy of the fresh module-level dynamic efficiency evaluation.

if nargin < 3 || isempty(cfg)
    cfg = degradation_results_config();
end

if exist(cfg.dynamic_feature_src, 'dir')
    addpath(cfg.dynamic_feature_src);
end

Pmodule_MW = max(double(Pmodule_MW), 0);
if isvector(Pmodule_MW)
    Pmodule_MW = Pmodule_MW(:);
end

n_steps = size(Pmodule_MW, 1);
n_modules = size(Pmodule_MW, 2);
steps_per_day = round(24 / cfg.delta_t_hour);
if mod(n_steps, steps_per_day) ~= 0
    error('Schedule length %d is not divisible by %d steps/day.', n_steps, steps_per_day);
end
n_days = n_steps / steps_per_day;

mdl = load_dynamic_eta_model_local(topology_id, cfg);

feature_dim = numel(compute_dynamic_features(zeros(steps_per_day, 1), cfg.module_rating_MW));
features = zeros(n_days, n_modules, feature_dim);
eta_day_module = zeros(n_days, n_modules);
energy_day_module_MWh = zeros(n_days, n_modules);
hydrogen_day_module_t = zeros(n_days, n_modules);

for d = 1:n_days
    idx = (d - 1) * steps_per_day + (1:steps_per_day);
    for m = 1:n_modules
        x = Pmodule_MW(idx, m);
        features(d, m, :) = compute_dynamic_features(x, cfg.module_rating_MW);
        energy_day_module_MWh(d, m) = sum(x) * cfg.delta_t_hour;
    end
end

feature_matrix = reshape(features, [], feature_dim);
eta_vector = predict(mdl, feature_matrix);
eta_vector = min(max(eta_vector, 0), 1);
eta_day_module = reshape(eta_vector, n_days, n_modules);
hydrogen_day_module_t = eta_day_module .* energy_day_module_MWh / 33.33;

eval = struct();
eval.features = features;
eval.eta_day_module = eta_day_module;
eval.energy_day_module_MWh = energy_day_module_MWh;
eval.hydrogen_day_module_t = hydrogen_day_module_t;
eval.n_days = n_days;
eval.n_modules = n_modules;
eval.mean_eta_day_module = mean(eta_day_module(:), 'omitnan');
end

function mdl = load_dynamic_eta_model_local(topology_id, cfg)
model_file = fullfile(cfg.dynamic_eta_model_dir, sprintf('eta_model_topo%d.mat', topology_id));
if ~isfile(model_file)
    error('Dynamic eta model for topology %d not found: %s', topology_id, model_file);
end
mdl = loadLearnerForCoder(model_file);
end
