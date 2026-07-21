function daily_table = step1_build_clean_degradation_targets()
%STEP1_BUILD_CLEAN_DEGRADATION_TARGETS
% Step 1:
% 1) fit a per-unit baseline voltage model V = f(I, T),
% 2) correct the raw voltage to a common reference condition,
% 3) extract a clean daily degradation target for later model fitting.

cfg = degradation_model_config();
raw = readtable(cfg.raw_timeseries_csv, 'TextType', 'string');

baseline_rows = {};
selected_rows = {};
hourly_tables = {};
daily_tables = {};

for i = 1:numel(cfg.units)
    unit = cfg.units{i};
    unit_raw = raw(raw.unit == unit, :);
    unit_raw = sortrows(unit_raw, 'time_h');

    [rated_current_a, rated_voltage_v, ref_temperature_c] = infer_reference_conditions(unit_raw, cfg);
    cell_count = cfg.unit_cell_count.(unit);

    baseline_mask = isfinite(unit_raw.current) ...
        & isfinite(unit_raw.temperature) ...
        & isfinite(unit_raw.voltage) ...
        & unit_raw.day_index <= cfg.baseline_days ...
        & unit_raw.current >= cfg.baseline_min_current_frac * rated_current_a;

    baseline_raw = unit_raw(baseline_mask, :);
    [candidate_result, selected_model] = fit_baseline_candidates(baseline_raw, rated_current_a, ref_temperature_c, cfg);

    for j = 1:numel(candidate_result)
        row = candidate_result(j);
        baseline_rows(end+1, 1) = {table( ...
            string(unit), ...
            string(row.name), ...
            row.num_points, ...
            row.num_coeff, ...
            row.cv_rmse_v, ...
            row.cv_mae_v, ...
            row.cv_r2, ...
            'VariableNames', {'unit', 'model_name', 'num_points', 'num_coeff', 'cv_rmse_v', 'cv_mae_v', 'cv_r2'})}; %#ok<AGROW>
    end

    selected_rows(end+1, 1) = {table( ...
        string(unit), ...
        string(selected_model.name), ...
        rated_current_a, ...
        rated_voltage_v, ...
        ref_temperature_c, ...
        selected_model.cv_rmse_v, ...
        selected_model.cv_mae_v, ...
        selected_model.cv_r2, ...
        'VariableNames', {'unit', 'selected_model', 'rated_current_a', 'rated_voltage_v', 'ref_temperature_c', 'cv_rmse_v', 'cv_mae_v', 'cv_r2'})}; %#ok<AGROW>

    hourly_table = build_hourly_equivalent_table(unit_raw, rated_current_a, rated_voltage_v, ref_temperature_c, selected_model, unit);
    hourly_tables{end+1, 1} = hourly_table; %#ok<AGROW>

    daily_table_unit = build_daily_table(hourly_table, cell_count, rated_current_a, rated_voltage_v, ref_temperature_c, unit, cfg);
    daily_tables{end+1, 1} = daily_table_unit; %#ok<AGROW>
end

baseline_table = vertcat(baseline_rows{:});
selected_table = vertcat(selected_rows{:});
hourly_equivalent = vertcat(hourly_tables{:});
daily_table = vertcat(daily_tables{:});

writetable(baseline_table, cfg.step1_baseline_comparison_csv);
writetable(selected_table, cfg.step1_baseline_selected_csv);
writetable(hourly_equivalent, cfg.step1_hourly_equivalent_csv);
writetable(daily_table, cfg.step1_daily_target_csv);

write_step1_summary(cfg, baseline_table, selected_table, daily_table);
end

function [rated_current_a, rated_voltage_v, ref_temperature_c] = infer_reference_conditions(unit_raw, cfg)
rated_mask = isfinite(unit_raw.current) ...
    & isfinite(unit_raw.voltage) ...
    & isfinite(unit_raw.temperature) ...
    & unit_raw.state >= cfg.baseline_state_threshold ...
    & unit_raw.current > 0;

if nnz(rated_mask) < 10
    rated_mask = isfinite(unit_raw.current) ...
        & isfinite(unit_raw.voltage) ...
        & isfinite(unit_raw.temperature) ...
        & unit_raw.current > 0;
end

rated_current_a = median(unit_raw.current(rated_mask));
rated_voltage_v = median(unit_raw.voltage(rated_mask));
ref_temperature_c = median(unit_raw.temperature(rated_mask));
end

function [results, selected_model] = fit_baseline_candidates(baseline_raw, rated_current_a, ref_temperature_c, cfg)
Ipu = baseline_raw.current ./ rated_current_a;
Tc = baseline_raw.temperature - ref_temperature_c;
y = baseline_raw.voltage;

design_builders = { ...
    @(i, t) [ones(size(i)), i, t], ...
    @(i, t) [ones(size(i)), i, i.^2, t], ...
    @(i, t) [ones(size(i)), i, i.^2, t, t.^2, i .* t]};

results = repmat(struct( ...
    'name', "", ...
    'num_points', 0, ...
    'num_coeff', 0, ...
    'cv_rmse_v', NaN, ...
    'cv_mae_v', NaN, ...
    'cv_r2', NaN, ...
    'beta', []), numel(design_builders), 1);

best_rmse = inf;
selected_model = struct();

for k = 1:numel(design_builders)
    X = design_builders{k}(Ipu, Tc);
    [rmse_v, mae_v, r2] = cross_validate_linear_model(X, y);
    beta = X \ y;

    results(k).name = cfg.baseline_candidate_names{k};
    results(k).num_points = numel(y);
    results(k).num_coeff = size(X, 2);
    results(k).cv_rmse_v = rmse_v;
    results(k).cv_mae_v = mae_v;
    results(k).cv_r2 = r2;
    results(k).beta = beta;

    if rmse_v < best_rmse
        best_rmse = rmse_v;
        selected_model = results(k);
        selected_model.design_builder = design_builders{k};
    end
end
end

function [rmse_v, mae_v, r2] = cross_validate_linear_model(X, y)
n = numel(y);
if n < 12
    y_hat = X * (X \ y);
    residual = y - y_hat;
else
    kfold = min(5, n);
    cvp = cvpartition(n, 'KFold', kfold);
    y_hat = NaN(n, 1);
    for fold = 1:cvp.NumTestSets
        train_idx = training(cvp, fold);
        test_idx = test(cvp, fold);
        beta = X(train_idx, :) \ y(train_idx);
        y_hat(test_idx) = X(test_idx, :) * beta;
    end
    residual = y - y_hat;
end

rmse_v = sqrt(mean(residual .^ 2, 'omitnan'));
mae_v = mean(abs(residual), 'omitnan');
sst = sum((y - mean(y, 'omitnan')) .^ 2, 'omitnan');
sse = sum(residual .^ 2, 'omitnan');
r2 = 1 - sse / max(sst, eps);
end

function hourly_table = build_hourly_equivalent_table(unit_raw, rated_current_a, rated_voltage_v, ref_temperature_c, selected_model, unit)
Ipu = unit_raw.current ./ rated_current_a;
Tc = unit_raw.temperature - ref_temperature_c;
X_all = selected_model.design_builder(Ipu, Tc);
X_ref = selected_model.design_builder(ones(size(Ipu)), zeros(size(Tc)));

voltage_dynamic_v = X_all * selected_model.beta;
voltage_ref_v = X_ref * selected_model.beta;
equivalent_voltage_v = unit_raw.voltage - (voltage_dynamic_v - voltage_ref_v);

power_frac = (unit_raw.current .* unit_raw.voltage) ./ max(rated_current_a * rated_voltage_v, eps);
power_frac = max(power_frac, 0);

hourly_table = table( ...
    repmat(string(unit), height(unit_raw), 1), ...
    unit_raw.time_h, ...
    unit_raw.day_index, ...
    unit_raw.dt_h, ...
    unit_raw.temperature, ...
    unit_raw.current, ...
    unit_raw.voltage, ...
    unit_raw.state, ...
    Ipu, ...
    Tc, ...
    voltage_dynamic_v, ...
    voltage_ref_v, ...
    equivalent_voltage_v, ...
    power_frac, ...
    'VariableNames', { ...
    'unit', 'time_h', 'day_index', 'dt_h', 'temperature', 'current', 'voltage', 'state', ...
    'current_frac', 'temperature_centered_c', 'baseline_voltage_v', 'reference_voltage_v', ...
    'equivalent_voltage_v', 'power_frac'});
end

function daily_table = build_daily_table(hourly_table, cell_count, rated_current_a, rated_voltage_v, ref_temperature_c, unit, cfg)
days = unique(hourly_table.day_index);
n_days = numel(days);

daily_table = table('Size', [n_days, 28], ...
    'VariableTypes', [repmat("string", 1, 1), repmat("double", 1, 27)], ...
    'VariableNames', { ...
    'unit', 'day_index', 'num_valid_points', 'rated_current_a', 'rated_voltage_v', 'ref_temperature_c', ...
    'eq_voltage_median_v', 'raw_cum_deg_cell_mV', 'clean_cum_deg_cell_mV', 'daily_deg_rate_cell_mV', ...
    'elapsed_day', 'sqrt_elapsed_day', 'log1p_elapsed_day', 'daily_eflh_h', 'mean_power_frac_all', ...
    'mean_power_frac_on', 'p90_power_frac_on', 'high_load_hours', 'ramp_abs_mean_frac', 'ramp_abs_max_frac', ...
    'rated_hours', 'transition_hours', 'stop_hours', 'start_count', 'stop_count', ...
    'T_on_median', 'T_on_p90', 'valid_target'});

daily_table.unit(:) = string(unit);
daily_table.day_index = days;
daily_table.rated_current_a(:) = rated_current_a;
daily_table.rated_voltage_v(:) = rated_voltage_v;
daily_table.ref_temperature_c(:) = ref_temperature_c;
daily_table.elapsed_day = days;
daily_table.sqrt_elapsed_day = sqrt(days);
daily_table.log1p_elapsed_day = log1p(days);

for i = 1:n_days
    day_mask = hourly_table.day_index == days(i);
    day_rows = hourly_table(day_mask, :);

    valid_on_mask = isfinite(day_rows.equivalent_voltage_v) & day_rows.current > 0;
    target_mask = valid_on_mask & day_rows.current_frac >= cfg.target_min_current_frac;
    power_frac = day_rows.power_frac;
    dt_h = day_rows.dt_h;

    daily_table.num_valid_points(i) = nnz(target_mask);
    daily_table.eq_voltage_median_v(i) = median(day_rows.equivalent_voltage_v(target_mask), 'omitnan');
    daily_table.daily_eflh_h(i) = sum(power_frac .* dt_h, 'omitnan');
    daily_table.mean_power_frac_all(i) = mean(power_frac, 'omitnan');
    daily_table.mean_power_frac_on(i) = mean(power_frac(valid_on_mask), 'omitnan');
    daily_table.p90_power_frac_on(i) = percentile_or_nan(power_frac(valid_on_mask), 90);
    daily_table.high_load_hours(i) = sum(dt_h(power_frac >= 0.8), 'omitnan');

    ramp = abs(diff(power_frac));
    daily_table.ramp_abs_mean_frac(i) = mean(ramp, 'omitnan');
    daily_table.ramp_abs_max_frac(i) = max_or_zero(ramp);

    rated_mask = day_rows.state >= cfg.baseline_state_threshold;
    transition_mask = day_rows.state > 0 & day_rows.state < cfg.baseline_state_threshold;
    stop_mask = day_rows.state <= 0;

    daily_table.rated_hours(i) = sum(dt_h(rated_mask), 'omitnan');
    daily_table.transition_hours(i) = sum(dt_h(transition_mask), 'omitnan');
    daily_table.stop_hours(i) = sum(dt_h(stop_mask), 'omitnan');
    daily_table.start_count(i) = count_start_stop(day_rows.current, true, rated_current_a);
    daily_table.stop_count(i) = count_start_stop(day_rows.current, false, rated_current_a);
    daily_table.T_on_median(i) = median(day_rows.temperature(valid_on_mask), 'omitnan');
    daily_table.T_on_p90(i) = percentile_or_nan(day_rows.temperature(valid_on_mask), 90);
    daily_table.valid_target(i) = double(nnz(target_mask) > 0);
end

valid_day_mask = daily_table.valid_target > 0 & isfinite(daily_table.eq_voltage_median_v);
valid_idx = find(valid_day_mask);

if ~isempty(valid_idx)
    base_ref_count = min(3, numel(valid_idx));
    base_ref_v = median(daily_table.eq_voltage_median_v(valid_idx(1:base_ref_count)), 'omitnan');
    raw_cum = (daily_table.eq_voltage_median_v(valid_day_mask) - base_ref_v) ./ cell_count .* 1000;
    raw_cum = raw_cum(:);
    smooth_cum = smoothdata(raw_cum, 'movmedian', cfg.daily_smooth_window_days);
    clean_cum = cummax(smooth_cum);
    raw_cum = raw_cum - raw_cum(1);
    clean_cum = clean_cum - clean_cum(1);
    daily_rate = local_monotone_slope(clean_cum, daily_table.day_index(valid_day_mask), cfg.daily_rate_half_window_days);

    daily_table.raw_cum_deg_cell_mV(valid_day_mask) = raw_cum;
    daily_table.clean_cum_deg_cell_mV(valid_day_mask) = clean_cum;
    daily_table.daily_deg_rate_cell_mV(valid_day_mask) = daily_rate;
end

daily_table = movevars(daily_table, {'unit', 'day_index'}, 'Before', 1);
end

function q = percentile_or_nan(x, p)
if isempty(x) || all(isnan(x))
    q = NaN;
else
    q = prctile(x, p);
end
end

function value = max_or_zero(x)
if isempty(x) || all(isnan(x))
    value = 0;
else
    value = max(x);
end
end

function count = count_start_stop(current_a, is_start, rated_current_a)
if isempty(current_a)
    count = 0;
    return;
end

on_mask = current_a > max(0.05 * rated_current_a, eps);
prev_mask = [false; on_mask(1:end-1)];
if is_start
    count = sum(~prev_mask & on_mask);
else
    count = sum(prev_mask & ~on_mask);
end
end

function daily_rate = local_monotone_slope(clean_cum, day_index, half_window)
n = numel(clean_cum);
daily_rate = zeros(n, 1);
for i = 1:n
    left = max(1, i - half_window);
    right = min(n, i + half_window);
    span = max(day_index(right) - day_index(left), 1);
    daily_rate(i) = max((clean_cum(right) - clean_cum(left)) / span, 0);
end
end

function write_step1_summary(cfg, baseline_table, selected_table, daily_table)
fid = fopen(cfg.step1_summary_txt, 'w');
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, 'Step 1 summary: baseline voltage fitting and clean degradation-target extraction\n');
fprintf(fid, 'Canonical raw table: %s\n\n', cfg.raw_timeseries_csv);

fprintf(fid, 'Selected baseline models by unit:\n');
for i = 1:height(selected_table)
    fprintf(fid, '- %s: %s | I_rated = %.3f A | V_rated = %.3f V | T_ref = %.3f C | CV RMSE = %.6f V\n', ...
        selected_table.unit(i), ...
        selected_table.selected_model(i), ...
        selected_table.rated_current_a(i), ...
        selected_table.rated_voltage_v(i), ...
        selected_table.ref_temperature_c(i), ...
        selected_table.cv_rmse_v(i));
end

fprintf(fid, '\nValid daily targets by unit:\n');
units = unique(daily_table.unit);
for i = 1:numel(units)
    mask = daily_table.unit == units(i) & daily_table.valid_target > 0;
    fprintf(fid, '- %s: %d valid daily points\n', units(i), nnz(mask));
end

fprintf(fid, '\nOutput files:\n');
fprintf(fid, '- %s\n', cfg.step1_baseline_comparison_csv);
fprintf(fid, '- %s\n', cfg.step1_baseline_selected_csv);
fprintf(fid, '- %s\n', cfg.step1_hourly_equivalent_csv);
fprintf(fid, '- %s\n', cfg.step1_daily_target_csv);
end
