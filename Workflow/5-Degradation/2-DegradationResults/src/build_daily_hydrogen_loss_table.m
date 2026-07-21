function Tout = build_daily_hydrogen_loss_table(Pmodule_MW, Tpred, topology_id, cfg)
%BUILD_DAILY_HYDROGEN_LOSS_TABLE
% Convert cumulative degradation voltage into a relative daily H2 penalty.
%
% The fresh day-level hydrogen is reconstructed by the existing dynamic
% efficiency surrogate. The degradation penalty is then applied as
%   H2_deg = H2_fresh * Uref / (Uref + DeltaU_cum)
% where Uref is obtained from the static voltage interface at the
% topology-specific mean on-state power of that day.

if nargin < 4 || isempty(cfg)
    cfg = degradation_results_config();
end

Pmodule_MW = max(double(Pmodule_MW), 0);
if isvector(Pmodule_MW)
    Pmodule_MW = Pmodule_MW(:);
end

fresh = evaluate_dynamic_surrogate_schedule_local(Pmodule_MW, topology_id, cfg);
iface = load_static_voltage_interface(topology_id, cfg);

steps_per_day = round(24 / cfg.delta_t_hour);
n_steps = size(Pmodule_MW, 1);
n_modules = size(Pmodule_MW, 2);
n_days = n_steps / steps_per_day;

T = sortrows(Tpred, {'module_id', 'day_index'});
if height(T) ~= n_days * n_modules
    error('Prediction table height (%d) does not match schedule shape (%d days x %d modules).', ...
        height(T), n_days, n_modules);
end

ref_power_MW = zeros(height(T), 1);
ref_power_pu = zeros(height(T), 1);
uref_cell_V = zeros(height(T), 1);
fresh_h2_t = zeros(height(T), 1);
degraded_h2_t = zeros(height(T), 1);
h2_loss_t = zeros(height(T), 1);
fresh_eta = zeros(height(T), 1);
degraded_eta = zeros(height(T), 1);
fresh_energy_MWh = zeros(height(T), 1);
relative_h2_factor = ones(height(T), 1);
min_operating_power_MW = repmat(iface.min_operating_power_MW, height(T), 1);
min_operating_power_pu = repmat(iface.min_operating_power_pu, height(T), 1);

for i = 1:height(T)
    module_id = double(T.module_id(i));
    day_id = double(T.day_index(i)) + 1;
    idx = (day_id - 1) * steps_per_day + (1:steps_per_day);
    power_day = Pmodule_MW(idx, module_id);

    on_mask = power_day >= iface.min_operating_power_MW - 1e-9;
    if any(on_mask)
        ref_power_MW(i) = mean(power_day(on_mask), 'omitnan');
        ref_power_pu(i) = ref_power_MW(i) / cfg.module_rating_MW;
        uref_cell_V(i) = interp1(iface.power_MW, iface.cell_voltage_V, ...
            ref_power_MW(i), 'linear', 'extrap');
    else
        ref_power_MW(i) = 0;
        ref_power_pu(i) = 0;
        uref_cell_V(i) = 0;
    end

    fresh_energy_MWh(i) = fresh.energy_day_module_MWh(day_id, module_id);
    fresh_eta(i) = fresh.eta_day_module(day_id, module_id);
    fresh_h2_t(i) = fresh.hydrogen_day_module_t(day_id, module_id);

    if fresh_h2_t(i) > 0 && uref_cell_V(i) > 0
        delta_u_cum_V = double(T.pred_cumulative_u_cell_v(i));
        relative_h2_factor(i) = uref_cell_V(i) / (uref_cell_V(i) + delta_u_cum_V);
        relative_h2_factor(i) = min(max(relative_h2_factor(i), 0), 1);
    else
        relative_h2_factor(i) = 1;
    end

    degraded_h2_t(i) = fresh_h2_t(i) * relative_h2_factor(i);
    h2_loss_t(i) = fresh_h2_t(i) - degraded_h2_t(i);
    degraded_eta(i) = fresh_eta(i) * relative_h2_factor(i);
end

Tout = T;
Tout.min_operating_power_MW = min_operating_power_MW;
Tout.min_operating_power_pu = min_operating_power_pu;
Tout.uref_mean_on_power_MW = ref_power_MW;
Tout.uref_mean_on_power_pu = ref_power_pu;
Tout.uref_cell_v = uref_cell_V;
Tout.fresh_energy_day_MWh = fresh_energy_MWh;
Tout.fresh_eta_day = fresh_eta;
Tout.degraded_eta_day = degraded_eta;
Tout.relative_h2_factor = relative_h2_factor;
Tout.fresh_hydrogen_day_t = fresh_h2_t;
Tout.degraded_hydrogen_day_t = degraded_h2_t;
Tout.hydrogen_loss_day_t = h2_loss_t;
Tout.hydrogen_loss_ratio_day = safe_ratio(h2_loss_t, fresh_h2_t);
end

function r = safe_ratio(num, den)
r = zeros(size(num));
mask = den > 0;
r(mask) = num(mask) ./ den(mask);
r(~isfinite(r)) = 0;
end
