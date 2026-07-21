function result = dispatch_milp_static_map(P_available_MW, ph_map, cfg)
%DISPATCH_MILP_STATIC_MAP Local copy for the degradation branch.

if nargin < 3 || isempty(cfg)
    cfg = plant_case_config();
end

P_available_MW = P_available_MW(:);
n_steps = numel(P_available_MW);
n_modules = cfg.n_modules;

step_MW = cfg.milp_power_step_MW;
power_levels = (0:step_MW:cfg.module_rating_MW)';
h2_levels = interp1(ph_map.power_MW(:), ph_map.hydrogen_tph(:), ...
    power_levels, 'linear', 'extrap');
h2_levels(power_levels <= 1e-12) = 0;
h2_levels = max(h2_levels, 0);

power_units = round(power_levels / step_MW);
capacity_units = round(cfg.plant_rating_MW / step_MW);

dp = -inf(n_modules + 1, capacity_units + 1);
choice_level = zeros(n_modules + 1, capacity_units + 1);
choice_prev = zeros(n_modules + 1, capacity_units + 1);
dp(1, 1) = 0;

for m = 1:n_modules
    for cap = 0:capacity_units
        best_val = -inf;
        best_level = 0;
        best_prev = 0;
        for k = 1:numel(power_units)
            prev = cap - power_units(k);
            if prev < 0
                continue;
            end
            cand = dp(m, prev + 1) + h2_levels(k);
            if cand > best_val + 1e-12
                best_val = cand;
                best_level = k;
                best_prev = prev;
            end
        end
        dp(m + 1, cap + 1) = best_val;
        choice_level(m + 1, cap + 1) = best_level;
        choice_prev(m + 1, cap + 1) = best_prev;
    end
end

Pmodule = zeros(n_steps, n_modules);
Hmodule_tph = zeros(n_steps, n_modules);
Pused_MW = zeros(n_steps, 1);
Hplant_tph = zeros(n_steps, 1);
curtailment_MW = zeros(n_steps, 1);

for t = 1:n_steps
    available_units = min(capacity_units, floor(P_available_MW(t) / step_MW + 1e-9));
    [best_h, cap_idx] = max(dp(n_modules + 1, 1:(available_units + 1)));
    if ~isfinite(best_h)
        cap_idx = 1;
    end
    cap = cap_idx - 1;
    module_idx = 0;
    for m = n_modules:-1:1
        level = choice_level(m + 1, cap + 1);
        prev = choice_prev(m + 1, cap + 1);
        if power_levels(level) > 0
            module_idx = module_idx + 1;
            Pmodule(t, module_idx) = power_levels(level);
            Hmodule_tph(t, module_idx) = h2_levels(level);
        end
        cap = prev;
    end
    Pused_MW(t) = sum(Pmodule(t, :));
    Hplant_tph(t) = sum(Hmodule_tph(t, :));
    curtailment_MW(t) = max(P_available_MW(t) - Pused_MW(t), 0);
end

result = struct();
result.Pmodule_MW = Pmodule;
result.Hmodule_tph = Hmodule_tph;
result.Pused_MW = Pused_MW;
result.Hplant_tph = Hplant_tph;
result.curtailment_MW = curtailment_MW;
result.power_step_MW = step_MW;
result.formulation = "bounded-integer MILP over discretised module loading levels";
end
