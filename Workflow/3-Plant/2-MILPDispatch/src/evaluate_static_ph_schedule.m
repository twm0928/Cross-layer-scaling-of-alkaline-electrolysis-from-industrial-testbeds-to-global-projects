function eval = evaluate_static_ph_schedule(Pmodule_MW, ph_map, cfg)
%EVALUATE_STATIC_PH_SCHEDULE Evaluate a module schedule using P-H2 mapping.

if nargin < 3 || isempty(cfg)
    cfg = plant_case_config();
end

Pmodule_MW = max(Pmodule_MW, 0);
Hmodule_tph = interp1(ph_map.power_MW, ph_map.hydrogen_tph, ...
    min(Pmodule_MW, cfg.module_rating_MW), 'linear', 0);
Hmodule_tph(Pmodule_MW <= 1e-12) = 0;

Pused_MW = sum(Pmodule_MW, 2);
Hplant_tph = sum(Hmodule_tph, 2);
energy_MWh = sum(Pused_MW) * cfg.delta_t_hour;
hydrogen_t = sum(Hplant_tph) * cfg.delta_t_hour;
if energy_MWh > 0
    eta = hydrogen_t * 33.33 / energy_MWh;
else
    eta = 0;
end

eval = struct();
eval.Hmodule_tph = Hmodule_tph;
eval.Pused_MW = Pused_MW;
eval.Hplant_tph = Hplant_tph;
eval.energy_MWh = energy_MWh;
eval.hydrogen_t = hydrogen_t;
eval.efficiency_LHV = eta;
end
