function curve_table = step3_plot_degradation_curves()
%STEP3_PLOT_DEGRADATION_CURVES
% Step 3:
% plot the clean experimental degradation curve, model-reconstructed curve,
% and 365-day extrapolated curve for the six units.

cfg = degradation_model_config();
training_table = readtable(cfg.step2_training_table_csv, 'TextType', 'string');
best_struct = load(cfg.step2_best_model_mat, 'best_bundle');
best_bundle = best_struct.best_bundle;

valid_mask = training_table.valid_for_model > 0;
X_obs = training_table{valid_mask, cfg.feature_columns};
pred_obs = predict(best_bundle.model_all, X_obs);
training_table.pred_daily_rate_mV = NaN(height(training_table), 1);
training_table.pred_daily_rate_mV(valid_mask) = pred_obs;

curve_rows = {};
figure_daily = figure('Visible', 'off', 'Color', 'w', 'Position', [100, 100, 1500, 900]);
figure_cum = figure('Visible', 'off', 'Color', 'w', 'Position', [100, 100, 1500, 900]);

for i = 1:numel(cfg.units)
    unit = cfg.units{i};
    unit_table = training_table(training_table.unit == unit, :);
    unit_table = sortrows(unit_table, 'day_index');
    observed = unit_table(unit_table.valid_for_model > 0, :);

    exp_day = observed.day_index;
    exp_rate = observed.(cfg.target_column);
    fit_rate = observed.pred_daily_rate_mV;
    exp_cum = observed.clean_cum_deg_cell_mV;
    fit_cum = cumsum(max(fit_rate, 0));

    future_day = ((exp_day(end) + 1):(cfg.extrapolation_horizon_days - 1))';
    if isempty(future_day)
        full_day = exp_day;
        full_cum = fit_cum;
    else
        full_day = [exp_day; future_day];
        full_cum = build_profile_extrapolation(exp_day, exp_cum, fit_cum, full_day);
    end

    curve_rows{end+1, 1} = table( ... %#ok<AGROW>
        repmat(string(unit), numel(full_day), 1), ...
        full_day, ...
        [ones(numel(exp_day), 1); zeros(numel(full_day) - numel(exp_day), 1)], ...
        [exp_cum; NaN(numel(full_day) - numel(exp_day), 1)], ...
        [fit_cum; NaN(numel(full_day) - numel(exp_day), 1)], ...
        full_cum, ...
        'VariableNames', {'unit', 'day_index', 'is_observed', 'exp_clean_cum_mV_cell', 'fit_cum_observed_mV_cell', 'fit_cum_with_extrapolation_mV_cell'});

    plot_daily_panel(figure_daily, i, exp_day, exp_rate, fit_rate, unit);
    plot_cumulative_panel(figure_cum, i, exp_day, exp_cum, fit_cum, full_day, full_cum, unit);
end

curve_table = vertcat(curve_rows{:});
writetable(curve_table, cfg.step3_curve_csv);

exportgraphics(figure_daily, cfg.step3_daily_rate_png, 'Resolution', 300);
exportgraphics(figure_cum, cfg.step3_cumulative_png, 'Resolution', 300);
close(figure_daily);
close(figure_cum);

write_step3_summary(cfg, curve_table);
end

function full_cum = build_profile_extrapolation(exp_day, exp_cum, fit_cum, full_day)
obs_t = double(exp_day - exp_day(1));
all_t = double(full_day - exp_day(1));

target = max(exp_cum(:) - exp_cum(1), 0);
fit_end = max(fit_cum(end), 0);

if numel(obs_t) < 6
    prev_idx = max(1, numel(fit_cum) - 1);
    tail_slope = max((fit_cum(end) - fit_cum(prev_idx)) / max(exp_day(end) - exp_day(prev_idx), 1), 0);
    full_cum = fit_end + tail_slope .* max(all_t - obs_t(end), 0);
    full_cum(1:numel(fit_cum)) = fit_cum;
    return;
end

tail_start_idx = max(1, numel(obs_t) - 20);
tail_slope = max((target(end) - target(tail_start_idx)) / max(obs_t(end) - obs_t(tail_start_idx), 1), 0);
tail_slope = max(tail_slope, 1e-3);
overall_slope = max((target(end) - target(1)) / max(obs_t(end) - obs_t(1), 1), 0);
slope_floor = max([0.15 * overall_slope, 0.25 * tail_slope, 1e-2]);

init_a = max([target(end), fit_end, 1e-3]);
init_b = 0.03;
init_c = max(0.5 * tail_slope, slope_floor);
param0 = log([init_a, init_b, init_c]);

obj = @(p) profile_loss(p, obs_t, target, fit_end, tail_slope, slope_floor);
opts = optimset('Display', 'off', 'MaxIter', 500, 'MaxFunEvals', 1500);
param = fminsearch(obj, param0, opts);

[profile_obs, profile_all] = evaluate_profile(param, obs_t, all_t, slope_floor);

% Anchor the extrapolated curve to the model-reconstructed endpoint.
shift = fit_end - profile_obs(end);
profile_all = profile_all + shift;
profile_all = cummax(max(profile_all, 0));
profile_all(1:numel(fit_cum)) = fit_cum;

full_cum = profile_all;
end

function loss = profile_loss(param, obs_t, target, fit_end, tail_slope, slope_floor)
[profile_obs, ~] = evaluate_profile(param, obs_t, obs_t, slope_floor);

curve_rmse = sqrt(mean((profile_obs - target) .^ 2, 'omitnan'));
endpoint_penalty = abs(profile_obs(end) - target(end));
fit_penalty = abs(profile_obs(end) - fit_end);

if numel(obs_t) > 1
    pred_tail_slope = max((profile_obs(end) - profile_obs(end - 1)) / max(obs_t(end) - obs_t(end - 1), 1), 0);
else
    pred_tail_slope = tail_slope;
end
tail_penalty = abs(pred_tail_slope - tail_slope);

loss = curve_rmse + 0.35 * endpoint_penalty + 0.20 * fit_penalty + 0.20 * tail_penalty;
end

function [profile_obs, profile_all] = evaluate_profile(param, obs_t, all_t, slope_floor)
a = exp(param(1));
b = exp(param(2));
c = max(exp(param(3)), slope_floor);

profile_obs = a .* log1p(b .* obs_t) + c .* obs_t;
profile_all = a .* log1p(b .* all_t) + c .* all_t;

profile_obs = profile_obs - profile_obs(1);
profile_all = profile_all - profile_all(1);
profile_obs = cummax(max(profile_obs, 0));
profile_all = cummax(max(profile_all, 0));
end

function plot_daily_panel(fig_handle, panel_idx, day_index, exp_rate, fit_rate, unit)
figure(fig_handle);
subplot(3, 2, panel_idx);
hold on;
plot(day_index, exp_rate, 'o', 'Color', [0.65, 0.65, 0.65], 'MarkerSize', 4, 'LineWidth', 0.8);
plot(day_index, fit_rate, '-', 'Color', [0.00, 0.35, 0.80], 'LineWidth', 1.8);
hold off;
box on;
set(gca, 'FontName', 'Times New Roman', 'FontSize', 11, 'LineWidth', 1);
xlabel('Elapsed day', 'FontName', 'Times New Roman', 'FontSize', 12);
ylabel('Daily degradation rate (mV cell^{-1} d^{-1})', 'FontName', 'Times New Roman', 'FontSize', 12);
title(unit, 'FontName', 'Times New Roman', 'FontSize', 13, 'FontWeight', 'bold');
end

function plot_cumulative_panel(fig_handle, panel_idx, exp_day, exp_cum, fit_cum, full_day, full_cum, unit)
figure(fig_handle);
subplot(3, 2, panel_idx);
hold on;
plot(exp_day, exp_cum, 'o', 'Color', [0.65, 0.65, 0.65], 'MarkerSize', 4, 'LineWidth', 0.8);
plot(exp_day, fit_cum, '-', 'Color', [0.90, 0.45, 0.05], 'LineWidth', 2.0);
plot(full_day, full_cum, '--', 'Color', [0.00, 0.35, 0.80], 'LineWidth', 2.0);
hold off;
box on;
set(gca, 'FontName', 'Times New Roman', 'FontSize', 11, 'LineWidth', 1);
xlabel('Elapsed day', 'FontName', 'Times New Roman', 'FontSize', 12);
ylabel('Cumulative degradation (mV cell^{-1})', 'FontName', 'Times New Roman', 'FontSize', 12);
title(unit, 'FontName', 'Times New Roman', 'FontSize', 13, 'FontWeight', 'bold');
end

function write_step3_summary(cfg, curve_table)
fid = fopen(cfg.step3_summary_txt, 'w');
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, 'Step 3 summary: clean experimental curve, model reconstruction, and 365-day extrapolation\n');
fprintf(fid, 'Best-model curve table: %s\n\n', cfg.step3_curve_csv);

units = unique(curve_table.unit);
for i = 1:numel(units)
    mask = curve_table.unit == units(i);
    unit_rows = curve_table(mask, :);
    year_end_row = unit_rows(end, :);
    fprintf(fid, '- %s: 365-day extrapolated cumulative degradation = %.6f mV cell^-1\n', ...
        units(i), year_end_row.fit_cum_with_extrapolation_mV_cell);
end

fprintf(fid, '\nFigures:\n');
fprintf(fid, '- %s\n', cfg.step3_daily_rate_png);
fprintf(fid, '- %s\n', cfg.step3_cumulative_png);
end
