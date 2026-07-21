function result = run_degradation_experiment_internal(topology_ids, out_root_name, summary_prefix)
%RUN_DEGRADATION_EXPERIMENT_INTERNAL
% Execute the closed-loop plant-layer degradation benchmark on top of the
% existing plant dispatch workflow for one or more module topologies.

if nargin < 1 || isempty(topology_ids)
    topology_ids = 1:7;
end
if nargin < 2 || isempty(out_root_name)
    out_root_name = 'plant_m1_m7_degradation_benchmark';
end
if nargin < 3 || isempty(summary_prefix)
    summary_prefix = 'm1_m7';
end

cfg = degradation_results_config();

out_root = fullfile(cfg.outputs_dir, out_root_name);
prediction_dir = fullfile(out_root, 'level3_daily_predictions');
interface_dir = fullfile(out_root, 'level4_daily_hydrogen_interface');
summary_dir = fullfile(out_root, 'summaries');

ensure_dir(prediction_dir);
ensure_dir(interface_dir);
ensure_dir(summary_dir);

feature_summary = run_degradation_feature_benchmark_internal(topology_ids, out_root_name, summary_prefix);

module_tables = cell(height(feature_summary), 1);
strategy_tables = cell(height(feature_summary), 1);
trajectory_tables = cell(height(feature_summary), 1);

prediction_rows = cell(height(feature_summary), 13);

for i = 1:height(feature_summary)
    row_i = feature_summary(i, :);
    feature_csv = char(string(row_i.feature_csv_file));
    [~, feature_name] = fileparts(feature_csv);
    prediction_csv = fullfile(prediction_dir, [feature_name '_predictions.csv']);
    interface_csv = fullfile(interface_dir, [feature_name '_hydrogen_interface.csv']);

    Tpred = predict_degradation_daily_inputs(feature_csv, prediction_csv);
    S = load(char(string(row_i.schedule_mat_file)), 'Pmodule_MW');
    topology_id = double(row_i.topology_id);
    Tinterface = build_daily_hydrogen_loss_table(S.Pmodule_MW, Tpred, topology_id, cfg);
    writetable(Tinterface, interface_csv);

    [module_tables{i}, strategy_tables{i}, trajectory_tables{i}] = ...
        summarise_prediction_table(Tinterface, row_i);

    prediction_rows(i, :) = { ...
        char(string(row_i.case_name)), ...
        topology_id, ...
        char(string(row_i.topology_label)), ...
        char(string(row_i.strategy_type)), ...
        numeric_or_nan(row_i.theta), ...
        build_strategy_label(row_i), ...
        double(row_i.n_modules), ...
        double(row_i.plant_rating_MW), ...
        char(string(row_i.schedule_mat_file)), ...
        char(string(row_i.feature_csv_file)), ...
        prediction_csv, ...
        interface_csv, ...
        height(Tpred) ...
        };
end

module_summary = vertcat(module_tables{:});
strategy_summary = vertcat(strategy_tables{:});
trajectory_summary = vertcat(trajectory_tables{:});

ranking_summary = sortrows(strategy_summary, ...
    {'case_name', 'topology_id', 'mean_year_end_degradation_u_cell_mV', 'strategy_type', 'theta'}, ...
    {'ascend', 'ascend', 'ascend', 'ascend', 'ascend'});
ranking_summary.rank_within_case_topology = zeros(height(ranking_summary), 1);
group_key = string(ranking_summary.case_name) + "|" + string(ranking_summary.topology_label);
group_levels = unique(group_key, 'stable');
for i = 1:numel(group_levels)
    mask = group_key == group_levels(i);
    ranking_summary.rank_within_case_topology(mask) = (1:sum(mask)).';
end
ranking_summary = movevars(ranking_summary, 'rank_within_case_topology', 'Before', 1);

loss_summary = sortrows(strategy_summary(:, { ...
    'case_name', 'topology_id', 'topology_label', 'strategy_type', 'theta', 'strategy_label', ...
    'mean_year_end_degradation_u_cell_mV', ...
    'total_fresh_hydrogen_t', 'total_degraded_hydrogen_t', 'total_hydrogen_loss_t', ...
    'hydrogen_loss_ratio', 'mean_annual_relative_h2_factor'}), ...
    {'case_name', 'topology_id', 'strategy_type', 'theta'});

prediction_summary = cell2table(prediction_rows, 'VariableNames', { ...
    'case_name', 'topology_id', 'topology_label', 'strategy_type', 'theta', 'strategy_label', ...
    'n_modules', 'plant_rating_MW', ...
    'schedule_mat_file', 'feature_csv_file', 'prediction_csv_file', 'hydrogen_interface_csv_file', 'n_prediction_rows'});

prediction_summary_file = fullfile(summary_dir, sprintf('%s_prediction_export_summary.csv', summary_prefix));
module_summary_file = fullfile(summary_dir, sprintf('%s_module_annual_degradation_summary.csv', summary_prefix));
strategy_summary_file = fullfile(summary_dir, sprintf('%s_strategy_annual_degradation_summary.csv', summary_prefix));
trajectory_summary_file = fullfile(summary_dir, sprintf('%s_strategy_daily_cumulative_trajectory.csv', summary_prefix));
ranking_summary_file = fullfile(summary_dir, sprintf('%s_strategy_degradation_ranking.csv', summary_prefix));
loss_summary_file = fullfile(summary_dir, sprintf('%s_strategy_hydrogen_loss_summary.csv', summary_prefix));

writetable(prediction_summary, prediction_summary_file);
writetable(module_summary, module_summary_file);
writetable(strategy_summary, strategy_summary_file);
writetable(trajectory_summary, trajectory_summary_file);
writetable(ranking_summary, ranking_summary_file);
writetable(loss_summary, loss_summary_file);

result = struct();
result.prediction_summary_file = prediction_summary_file;
result.module_summary_file = module_summary_file;
result.strategy_summary_file = strategy_summary_file;
result.trajectory_summary_file = trajectory_summary_file;
result.ranking_summary_file = ranking_summary_file;
result.loss_summary_file = loss_summary_file;
result.n_schedule_sets = height(feature_summary);
result.n_module_year_rows = height(module_summary);
result.n_strategy_rows = height(strategy_summary);
result.n_trajectory_rows = height(trajectory_summary);

fprintf('Degradation experiment completed.\n');
fprintf('Prediction summary:\n  %s\n', prediction_summary_file);
fprintf('Module annual summary:\n  %s\n', module_summary_file);
fprintf('Strategy annual summary:\n  %s\n', strategy_summary_file);
fprintf('Trajectory summary:\n  %s\n', trajectory_summary_file);
fprintf('Ranking summary:\n  %s\n', ranking_summary_file);
fprintf('Hydrogen-loss summary:\n  %s\n', loss_summary_file);
end

function [module_summary, strategy_summary, trajectory_summary] = summarise_prediction_table(Tday, row_i)
Tday = sortrows(Tday, {'module_id', 'day_index'});

case_name = repmat(string(row_i.case_name), height(Tday), 1);
strategy_type = repmat(string(row_i.strategy_type), height(Tday), 1);
theta = repmat(numeric_or_nan(row_i.theta), height(Tday), 1);
strategy_label = repmat(string(build_strategy_label(row_i)), height(Tday), 1);
topology_id = repmat(double_or_zero(row_i, 'topology_id', 1), height(Tday), 1);
if ismember('topology_label', Tday.Properties.VariableNames)
    topology_label = string(Tday.topology_label);
else
    topology_label = repmat(string(row_i.topology_label), height(Tday), 1);
end
plant_rating_MW = repmat(double(row_i.plant_rating_MW), height(Tday), 1);
schedule_modules = repmat(double(row_i.n_modules), height(Tday), 1);

Tday.case_name = case_name;
Tday.strategy_type = strategy_type;
Tday.theta = theta;
Tday.strategy_label = strategy_label;
Tday.topology_id = topology_id;
Tday.topology_label = topology_label;
Tday.plant_rating_MW = plant_rating_MW;
Tday.n_modules = schedule_modules;

units = unique(string(Tday.unit), 'stable');
module_rows = cell(numel(units), 29);
for i = 1:numel(units)
    mask = string(Tday.unit) == units(i);
    Tu = Tday(mask, :);
    [~, order] = sort(double(Tu.day_index));
    Tu = Tu(order, :);

    total_fresh_h2_t = sum(double(Tu.fresh_hydrogen_day_t), 'omitnan');
    total_degraded_h2_t = sum(double(Tu.degraded_hydrogen_day_t), 'omitnan');
    total_h2_loss_t = sum(double(Tu.hydrogen_loss_day_t), 'omitnan');
    if total_fresh_h2_t > 0
        annual_relative_h2_factor = total_degraded_h2_t / total_fresh_h2_t;
    else
        annual_relative_h2_factor = 1;
    end

    module_rows(i, :) = { ...
        char(string(row_i.case_name)), ...
        char(string(row_i.strategy_type)), ...
        numeric_or_nan(row_i.theta), ...
        build_strategy_label(row_i), ...
        double(row_i.n_modules), ...
        double(row_i.plant_rating_MW), ...
        double_or_zero(row_i, 'topology_id', 1), ...
        char(string(Tu.topology_label(1))), ...
        double(Tu.module_id(1)), ...
        char(units(i)), ...
        height(Tu), ...
        double(Tu.pred_cumulative_u_cell_v(end)), ...
        double(Tu.pred_cumulative_u_cell_mV(end)), ...
        max(double(Tu.pred_cumulative_u_cell_v), [], 'omitnan'), ...
        max(double(Tu.pred_cumulative_u_cell_mV), [], 'omitnan'), ...
        min(double(Tu.pred_cumulative_u_cell_v), [], 'omitnan'), ...
        min(double(Tu.pred_cumulative_u_cell_mV), [], 'omitnan'), ...
        double(Tu.cum_daily_eflh_h(end)), ...
        double(Tu.cum_high_load_hours(end)), ...
        double(Tu.cum_start_count(end)), ...
        double(Tu.cum_stop_count(end)), ...
        mean(double(Tu.uref_cell_v), 'omitnan'), ...
        mean(double(Tu.uref_mean_on_power_MW), 'omitnan'), ...
        double(Tu.min_operating_power_MW(1)), ...
        total_fresh_h2_t, ...
        total_degraded_h2_t, ...
        total_h2_loss_t, ...
        safe_ratio_scalar(total_h2_loss_t, total_fresh_h2_t), ...
        annual_relative_h2_factor ...
        };
end

module_summary = cell2table(module_rows, 'VariableNames', { ...
    'case_name', 'strategy_type', 'theta', 'strategy_label', ...
    'n_modules', 'plant_rating_MW', 'topology_id', 'topology_label', ...
    'module_id', 'unit', 'n_days', ...
    'year_end_degradation_u_cell_v', 'year_end_degradation_u_cell_mV', ...
    'max_predicted_degradation_u_cell_v', 'max_predicted_degradation_u_cell_mV', ...
    'min_predicted_degradation_u_cell_v', 'min_predicted_degradation_u_cell_mV', ...
    'total_cum_daily_eflh_h', 'total_cum_high_load_hours', ...
    'total_start_count', 'total_stop_count', ...
    'mean_uref_cell_v', 'mean_uref_mean_on_power_MW', 'min_operating_power_MW', ...
    'fresh_hydrogen_t', 'degraded_hydrogen_t', 'hydrogen_loss_t', ...
    'hydrogen_loss_ratio', 'annual_relative_h2_factor'});

strategy_summary = table();
strategy_summary.case_name = string(row_i.case_name);
strategy_summary.strategy_type = string(row_i.strategy_type);
strategy_summary.theta = numeric_or_nan(row_i.theta);
strategy_summary.strategy_label = string(build_strategy_label(row_i));
strategy_summary.n_modules = double(row_i.n_modules);
strategy_summary.plant_rating_MW = double(row_i.plant_rating_MW);
strategy_summary.topology_id = double_or_zero(row_i, 'topology_id', 1);
strategy_summary.topology_label = string(module_summary.topology_label(1));
strategy_summary.mean_year_end_degradation_u_cell_mV = mean(module_summary.year_end_degradation_u_cell_mV, 'omitnan');
strategy_summary.worst_module_year_end_degradation_u_cell_mV = max(module_summary.year_end_degradation_u_cell_mV, [], 'omitnan');
strategy_summary.best_module_year_end_degradation_u_cell_mV = min(module_summary.year_end_degradation_u_cell_mV, [], 'omitnan');
strategy_summary.module_spread_year_end_degradation_u_cell_mV = ...
    strategy_summary.worst_module_year_end_degradation_u_cell_mV - strategy_summary.best_module_year_end_degradation_u_cell_mV;
strategy_summary.std_module_year_end_degradation_u_cell_mV = std(module_summary.year_end_degradation_u_cell_mV, 0, 'omitnan');
strategy_summary.mean_total_cum_daily_eflh_h = mean(module_summary.total_cum_daily_eflh_h, 'omitnan');
strategy_summary.mean_total_cum_high_load_hours = mean(module_summary.total_cum_high_load_hours, 'omitnan');
strategy_summary.mean_total_start_count = mean(module_summary.total_start_count, 'omitnan');
strategy_summary.mean_total_stop_count = mean(module_summary.total_stop_count, 'omitnan');
strategy_summary.total_fresh_hydrogen_t = sum(module_summary.fresh_hydrogen_t, 'omitnan');
strategy_summary.total_degraded_hydrogen_t = sum(module_summary.degraded_hydrogen_t, 'omitnan');
strategy_summary.total_hydrogen_loss_t = sum(module_summary.hydrogen_loss_t, 'omitnan');
strategy_summary.hydrogen_loss_ratio = safe_ratio_scalar( ...
    strategy_summary.total_hydrogen_loss_t, strategy_summary.total_fresh_hydrogen_t);
strategy_summary.mean_annual_relative_h2_factor = mean(module_summary.annual_relative_h2_factor, 'omitnan');
strategy_summary.mean_uref_cell_v = mean(module_summary.mean_uref_cell_v, 'omitnan');

day_levels = unique(double(Tday.day_index), 'stable');
trajectory_rows = cell(numel(day_levels), 17);
for i = 1:numel(day_levels)
    mask = double(Tday.day_index) == day_levels(i);
    Td = Tday(mask, :);
    trajectory_rows(i, :) = { ...
        char(string(row_i.case_name)), ...
        char(string(row_i.strategy_type)), ...
        numeric_or_nan(row_i.theta), ...
        build_strategy_label(row_i), ...
        day_levels(i), ...
        mean(double(Td.elapsed_day), 'omitnan'), ...
        mean(double(Td.pred_daily_increment_u_cell_mV), 'omitnan'), ...
        max(double(Td.pred_daily_increment_u_cell_mV), [], 'omitnan'), ...
        min(double(Td.pred_daily_increment_u_cell_mV), [], 'omitnan'), ...
        mean(double(Td.pred_cumulative_u_cell_mV), 'omitnan'), ...
        max(double(Td.pred_cumulative_u_cell_mV), [], 'omitnan'), ...
        min(double(Td.pred_cumulative_u_cell_mV), [], 'omitnan'), ...
        std(double(Td.pred_cumulative_u_cell_mV), 0, 'omitnan'), ...
        sum(double(Td.fresh_hydrogen_day_t), 'omitnan'), ...
        sum(double(Td.degraded_hydrogen_day_t), 'omitnan'), ...
        sum(double(Td.hydrogen_loss_day_t), 'omitnan'), ...
        mean(double(Td.relative_h2_factor), 'omitnan') ...
        };
end

trajectory_summary = cell2table(trajectory_rows, 'VariableNames', { ...
    'case_name', 'strategy_type', 'theta', 'strategy_label', ...
    'day_index', 'elapsed_day', ...
    'mean_predicted_daily_increment_u_cell_mV', 'worst_predicted_daily_increment_u_cell_mV', 'best_predicted_daily_increment_u_cell_mV', ...
    'mean_year_to_date_degradation_u_cell_mV', 'worst_year_to_date_degradation_u_cell_mV', 'best_year_to_date_degradation_u_cell_mV', ...
    'std_year_to_date_degradation_u_cell_mV', ...
    'fresh_hydrogen_day_t', 'degraded_hydrogen_day_t', 'hydrogen_loss_day_t', ...
    'mean_relative_h2_factor'});

trajectory_summary.cumulative_hydrogen_loss_t = cumsum(double(trajectory_summary.hydrogen_loss_day_t));
end

function label = build_strategy_label(row_i)
strategy_type = string(row_i.strategy_type);
if strategy_type == "theta"
    label = sprintf('theta=%.1f', numeric_or_nan(row_i.theta));
else
    label = char(upper(strategy_type));
end
end

function val = numeric_or_nan(x)
val = double(x);
if isempty(val) || ~isfinite(val)
    val = NaN;
end
end

function val = double_or_zero(row_i, var_name, fallback)
if nargin < 3
    fallback = 0;
end
if ismember(var_name, row_i.Properties.VariableNames)
    val = double(row_i.(var_name));
else
    val = fallback;
end
if isempty(val) || ~isfinite(val)
    val = fallback;
end
end

function r = safe_ratio_scalar(num, den)
if den > 0 && isfinite(num) && isfinite(den)
    r = num / den;
else
    r = 0;
end
end

function ensure_dir(path_str)
if ~exist(path_str, 'dir')
    mkdir(path_str);
end
end
