function eval = evaluate_dynamic_surrogate_schedule(Pmodule_MW, topology_id, cfg)
%EVALUATE_DYNAMIC_SURROGATE_SCHEDULE Evaluate a schedule with dynamic eta.
%
% The input schedule is a time-by-module matrix. The function reconstructs
% daily module features used by the LSBoost dynamic interface and converts
% predicted efficiency into hydrogen production.

if nargin < 3 || isempty(cfg)
    cfg = plant_case_config();
end
feature_src = fullfile(cfg.workflow_root, '2-Module', '2-DynamicEfficiencySurrogate', 'src');
if exist(feature_src, 'dir')
    addpath(feature_src);
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

mdl = load_dynamic_eta_model(topology_id, cfg);
sample_features = compute_dynamic_features(zeros(steps_per_day, 1), cfg.module_rating_MW);
n_features = numel(sample_features);

features = zeros(n_days, n_modules, n_features);
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

feature_matrix = reshape(features, [], n_features);
eta_vector = predict(mdl, feature_matrix);
eta_vector = min(max(eta_vector, 0), 1);
eta_day_module = reshape(eta_vector, n_days, n_modules);
hydrogen_day_module_t = eta_day_module .* energy_day_module_MWh / 33.33;

Pused_MW = sum(Pmodule_MW, 2);
energy_MWh = sum(energy_day_module_MWh(:));
hydrogen_t = sum(hydrogen_day_module_t(:));
if energy_MWh > 0
    eta_plant = hydrogen_t * 33.33 / energy_MWh;
else
    eta_plant = 0;
end

eval = struct();
eval.features = features;
eval.eta_day_module = eta_day_module;
eval.energy_day_module_MWh = energy_day_module_MWh;
eval.hydrogen_day_module_t = hydrogen_day_module_t;
eval.Pused_MW = Pused_MW;
eval.energy_MWh = energy_MWh;
eval.hydrogen_t = hydrogen_t;
eval.efficiency_LHV = eta_plant;
eval.mean_eta_day_module = mean(eta_day_module(:));
eval.n_days = n_days;
eval.n_modules = n_modules;
eval.efficiency_basis = "dynamic_surrogate_6feature_interface";
end
