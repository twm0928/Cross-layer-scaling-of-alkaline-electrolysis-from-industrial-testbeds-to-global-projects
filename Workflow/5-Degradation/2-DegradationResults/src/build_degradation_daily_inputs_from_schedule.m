function T = build_degradation_daily_inputs_from_schedule(Pmodule_MW, topology_id, output_csv, case_name)
%BUILD_DEGRADATION_DAILY_INPUTS_FROM_SCHEDULE
% Build the current-version degradation input table directly from a
% plant-level module power schedule.
%
% This function is aligned to the current R1 degradation report
% (退化研究报告_当前版本_v3): it uses only power-derived daily descriptors
% and does not depend on the legacy Qinghui temperature-based package.

cfg = degradation_results_config();
if nargin < 3
    output_csv = '';
end
if nargin < 4 || isempty(case_name)
    case_name = sprintf('Topo%dSchedule', topology_id);
end
case_name = char(string(case_name));

if exist(cfg.dynamic_feature_src, 'dir')
    addpath(cfg.dynamic_feature_src);
end

meta = load_module_topology_meta(topology_id);

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

rows = cell(n_days * n_modules, 1);
row_idx = 0;

for m = 1:n_modules
    cum_daily_eflh_h = 0;
    cum_high_load_hours = 0;
    cum_start_count = 0;
    cum_stop_count = 0;
    unit_label = sprintf('%s_Mod%02d', case_name, m);

    for d = 1:n_days
        idx = (d - 1) * steps_per_day + (1:steps_per_day);
        power_MW = Pmodule_MW(idx, m);
        time_h_day = ((idx - 1) * cfg.delta_t_hour)';

        power_frac = max(power_MW / cfg.module_rating_MW, 0);
        is_on = power_frac >= cfg.on_power_fraction;
        is_rated = power_frac >= cfg.rated_power_fraction;
        is_transition = is_on & ~is_rated;
        is_stop = ~is_on;

        prev_on = [false; is_on(1:end - 1)];
        start_events = (~prev_on) & is_on;
        stop_events = prev_on & (~is_on);

        rated_hours = sum(is_rated) * cfg.delta_t_hour;
        transition_hours = sum(is_transition) * cfg.delta_t_hour;
        stop_hours = sum(is_stop) * cfg.delta_t_hour;
        start_count = sum(start_events);
        stop_count = sum(stop_events);
        daily_eflh_h = sum(power_frac) * cfg.delta_t_hour;
        high_load_hours = sum(power_frac >= cfg.high_load_power_fraction) * cfg.delta_t_hour;
        elapsed_day = d - 1;

        cum_daily_eflh_h = cum_daily_eflh_h + daily_eflh_h;
        cum_high_load_hours = cum_high_load_hours + high_load_hours;
        cum_start_count = cum_start_count + start_count;
        cum_stop_count = cum_stop_count + stop_count;

        features = compute_dynamic_features(power_MW, cfg.module_rating_MW);
        on_power_frac = power_frac(is_on);

        row_idx = row_idx + 1;
        rows{row_idx} = { ...
            char(unit_label), ...
            d - 1, ...
            median(time_h_day) / 24, ...
            daily_eflh_h, ...
            features(1), ...
            mean_or_zero(on_power_frac), ...
            quantile_or_zero(on_power_frac, 0.90), ...
            high_load_hours, ...
            features(3), ...
            ramp_abs_max_frac(power_frac), ...
            rated_hours, ...
            transition_hours, ...
            stop_hours, ...
            start_count, ...
            stop_count, ...
            cum_daily_eflh_h, ...
            cum_high_load_hours, ...
            cum_start_count, ...
            cum_stop_count, ...
            elapsed_day, ...
            sqrt(max(elapsed_day, 0)), ...
            log1p(max(elapsed_day, 0)), ...
            topology_id, ...
            char(meta.topology_label), ...
            m, ...
            features(2), ...
            features(4) ...
            };
    end
end

row_matrix = vertcat(rows{1:row_idx});
T = cell2table(row_matrix, 'VariableNames', { ...
    'unit', 'day_index', 'time_day', ...
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
    'cum_stop_count', ...
    'elapsed_day', ...
    'sqrt_elapsed_day', ...
    'log1p_elapsed_day', ...
    'topology_id', ...
    'topology_label', ...
    'module_id', ...
    'longest_low_load_frac', ...
    'high_freq_ratio' ...
    });

if ~isempty(output_csv)
    writetable(T, output_csv);
    fprintf('Current-version degradation daily-input table written to:\n  %s\n', output_csv);
end
end

function y = mean_or_zero(x)
if isempty(x)
    y = 0;
else
    y = mean(x, 'omitnan');
    if ~isfinite(y)
        y = 0;
    end
end
end

function y = quantile_or_zero(x, q)
if isempty(x)
    y = 0;
else
    x = x(isfinite(x));
    if isempty(x)
        y = 0;
    else
        y = prctile(x, q * 100);
    end
end
end

function y = ramp_abs_max_frac(power_frac)
if numel(power_frac) <= 1
    y = 0;
else
    y = max(abs(diff(power_frac)));
    if ~isfinite(y)
        y = 0;
    end
end
end
