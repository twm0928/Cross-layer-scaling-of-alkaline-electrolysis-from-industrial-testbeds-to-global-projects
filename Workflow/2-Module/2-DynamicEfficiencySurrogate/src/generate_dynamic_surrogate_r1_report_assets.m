function assets = generate_dynamic_surrogate_r1_report_assets()
%GENERATE_DYNAMIC_SURROGATE_R1_REPORT_ASSETS Build report assets for R1.

src_dir = fileparts(mfilename('fullpath'));
surrogate_root = fileparts(src_dir);
report_dir = fullfile(surrogate_root, 'report');
fig_dir = fullfile(report_dir, 'figures');
table_dir = fullfile(report_dir, 'tables');
output_dir = fullfile(surrogate_root, 'outputs');

if ~exist(fig_dir, 'dir'); mkdir(fig_dir); end
if ~exist(table_dir, 'dir'); mkdir(table_dir); end

ds730 = build_dynamic_training_dataset(get_r1_dynamic_scenario_ids('first730'));
ds240 = build_dynamic_training_dataset(get_r1_dynamic_scenario_ids('legacy240'));
ds970 = build_dynamic_training_dataset(get_r1_dynamic_scenario_ids('combined970'));

scenario_summary = table( ...
    ["first730"; "legacy240"; "combined970"], ...
    [numel(ds730.scenario_ids); numel(ds240.scenario_ids); numel(ds970.scenario_ids)], ...
    'VariableNames', {'dataset_name', 'scenario_count'});
writetable(scenario_summary, fullfile(table_dir, 'scenario_summary.csv'));

feature_names = ["mean_power_pu", "low_load_duration_pu", "average_absolute_ramping_pu", ...
    "high_frequency_ratio", "load_std_pu", "load_range_pu"];
feature_labels = {'Mean power (per unit)', 'Low-load duration (per day)', ...
    'Average absolute ramping (per unit)', 'High-frequency ratio', ...
    'Load standard deviation (per unit)', 'Load range (per unit)'};
datasets = {ds730, ds240, ds970};
dataset_names = ["first730", "legacy240", "combined970"];

feature_rows = cell(numel(datasets) * numel(feature_names), 6);
row = 0;
for d = 1:numel(datasets)
    X = datasets{d}.features;
    for f = 1:numel(feature_names)
        row = row + 1;
        vals = X(:, f);
        feature_rows(row, :) = {dataset_names(d), feature_names(f), ...
            min(vals), max(vals), mean(vals), std(vals)};
    end
end
feature_summary = cell2table(feature_rows, 'VariableNames', ...
    {'dataset_name', 'feature_name', 'min_value', 'max_value', 'mean_value', 'std_value'});
writetable(feature_summary, fullfile(table_dir, 'feature_summary.csv'));

benchmark_csv = fullfile(output_dir, 'eta_model_r1_970_benchmark.csv');
metrics_csv = fullfile(output_dir, 'eta_model_r1_970_metrics.csv');
benchmark = readtable(benchmark_csv, 'TextType', 'string');
final_metrics = readtable(metrics_csv, 'TextType', 'string');

best_rows = cell(7, 9);
for t = 1:7
    sub = benchmark(benchmark.topology_id == t, :);
    [best_rmse, idx] = min(sub.cv5_RMSE);
    best_model = sub.model_family(idx);
    ls = sub(sub.model_family == "LSBoost", :);
    ls_rmse = ls.cv5_RMSE(1);
    ls_r2 = ls.cv5_R2(1);
    ls_mape = ls.cv5_MAPE_percent(1);
    best_rows(t, :) = {t, sprintf('M%d', t), best_model, best_rmse, ...
        ls_rmse, ls_rmse - best_rmse, ls_r2, ls_mape, sub.n_samples(1)};
end
benchmark_best = cell2table(best_rows, 'VariableNames', ...
    {'topology_id', 'topology_label', 'best_model_family', 'best_cv5_RMSE', ...
     'lsboost_cv5_RMSE', 'lsboost_rmse_gap', 'lsboost_cv5_R2', ...
     'lsboost_cv5_MAPE_percent', 'n_samples'});
writetable(benchmark_best, fullfile(table_dir, 'benchmark_best_summary.csv'));

oof_rows = {};
metrics_rows = cell(7, 6);
for t = 1:7
    valid = ds970.valid_mask(t, :);
    X = ds970.features(valid, :);
    y = ds970.efficiency_lhv(t, valid)';
    scen = ds970.scenario_ids(valid)';

    rng(20260620 + t, 'twister');
    cvp = cvpartition(size(X, 1), 'KFold', 5);
    templ = templateTree('Reproducible', true, 'MinLeafSize', 5);
    y_oof = nan(size(y));
    fold_id = nan(size(y));
    for fold = 1:5
        tr = training(cvp, fold);
        te = test(cvp, fold);
        mdl = fitrensemble(X(tr, :), y(tr), 'Method', 'LSBoost', ...
            'Learners', templ, 'NumLearningCycles', 150, 'LearnRate', 0.05);
        y_oof(te) = predict(mdl, X(te, :));
        fold_id(te) = fold;
    end

    rmse = sqrt(mean((y - y_oof) .^ 2));
    mae = mean(abs(y - y_oof));
    r2 = 1 - sum((y - y_oof) .^ 2) / max(sum((y - mean(y)) .^ 2), 1e-8);
    mape = mean(abs(y - y_oof) ./ max(abs(y), 1e-8)) * 100;
    metrics_rows(t, :) = {t, sprintf('M%d', t), mae, rmse, r2, mape};

    oof_rows = [oof_rows; ...
        [num2cell(scen(:)), repmat({t}, numel(scen), 1), repmat({sprintf('M%d', t)}, numel(scen), 1), ...
         num2cell(y(:)), num2cell(y_oof(:)), num2cell(fold_id(:))]]; %#ok<AGROW>
end

oof_table = cell2table(oof_rows, 'VariableNames', ...
    {'scenario_id', 'topology_id', 'topology_label', 'true_efficiency', 'predicted_efficiency', 'fold_id'});
writetable(oof_table, fullfile(table_dir, 'lsboost_oof_predictions_970.csv'));

oof_metrics = cell2table(metrics_rows, 'VariableNames', ...
    {'topology_id', 'topology_label', 'oof_MAE', 'oof_RMSE', 'oof_R2', 'oof_MAPE_percent'});
writetable(oof_metrics, fullfile(table_dir, 'lsboost_oof_metrics_970.csv'));

plot_feature_distribution(ds730.features, ds240.features, ds970.features, feature_labels, ...
    fullfile(fig_dir, 'Fig1_feature_distribution_730_240_970.png'));
plot_feature_space(ds730.features, ds240.features, feature_labels, ...
    fullfile(fig_dir, 'Fig2_feature_space_expansion.png'));
plot_benchmark_bars(benchmark, fullfile(fig_dir, 'Fig3_model_family_benchmark_rmse.png'));
plot_oof_parity(oof_table, fullfile(fig_dir, 'Fig4_lsboost_oof_parity_970.png'));
plot_final_metrics(final_metrics, fullfile(fig_dir, 'Fig5_final_lsboost_generalization.png'));

assets = struct();
assets.report_dir = report_dir;
assets.fig_dir = fig_dir;
assets.table_dir = table_dir;
assets.scenario_summary = fullfile(table_dir, 'scenario_summary.csv');
assets.feature_summary = fullfile(table_dir, 'feature_summary.csv');
assets.benchmark_best = fullfile(table_dir, 'benchmark_best_summary.csv');
assets.oof_predictions = fullfile(table_dir, 'lsboost_oof_predictions_970.csv');
assets.oof_metrics = fullfile(table_dir, 'lsboost_oof_metrics_970.csv');
assets.fig1 = fullfile(fig_dir, 'Fig1_feature_distribution_730_240_970.png');
assets.fig2 = fullfile(fig_dir, 'Fig2_feature_space_expansion.png');
assets.fig3 = fullfile(fig_dir, 'Fig3_model_family_benchmark_rmse.png');
assets.fig4 = fullfile(fig_dir, 'Fig4_lsboost_oof_parity_970.png');
assets.fig5 = fullfile(fig_dir, 'Fig5_final_lsboost_generalization.png');

disp(assets);
end

function plot_feature_distribution(X730, X240, X970, feature_labels, output_file)
num_features = size(X970, 2);
fig = figure('Color', 'w', 'Units', 'centimeters', 'Position', [2 2 18 16]);
colors = [0.20 0.45 0.85; 0.90 0.45 0.10; 0.20 0.65 0.35];
for f = 1:num_features
    subplot(2, 3, f); hold on;
    histogram(X730(:, f), 25, 'Normalization', 'probability', 'FaceColor', colors(1, :), 'FaceAlpha', 0.35, 'EdgeColor', 'none');
    histogram(X240(:, f), 25, 'Normalization', 'probability', 'FaceColor', colors(2, :), 'FaceAlpha', 0.35, 'EdgeColor', 'none');
    histogram(X970(:, f), 25, 'Normalization', 'probability', 'FaceColor', colors(3, :), 'FaceAlpha', 0.30, 'EdgeColor', 'none');
    xlabel(feature_labels{f});
    ylabel('Probability');
    title(sprintf('Feature %d', f));
    box on; grid off;
    set(gca, 'FontName', 'Times New Roman', 'FontSize', 10, 'LineWidth', 0.8);
end
legend({'first730', 'legacy240', 'combined970'}, 'Location', 'best', 'Box', 'off');
exportgraphics(fig, output_file, 'Resolution', 400);
close(fig);
end

function plot_feature_space(X730, X240, feature_labels, output_file)
fig = figure('Color', 'w', 'Units', 'centimeters', 'Position', [2 2 18 7.5]);
added730 = X730;
legacy240 = X240;
colors = [0.90 0.45 0.10; 0.20 0.45 0.85];

subplot(1, 2, 1); hold on;
scatter(added730(:,1), added730(:,3), 12, 'MarkerEdgeColor', colors(2,:), 'MarkerFaceColor', colors(2,:), 'MarkerFaceAlpha', 0.15, 'MarkerEdgeAlpha', 0.15);
scatter(legacy240(:,1), legacy240(:,3), 16, 'MarkerEdgeColor', colors(1,:), 'MarkerFaceColor', colors(1,:), 'MarkerFaceAlpha', 0.45, 'MarkerEdgeAlpha', 0.45);
xlabel(feature_labels{1}); ylabel(feature_labels{3});
title('Mean power vs ramping');
box on; grid off; legend({'first730', 'legacy240'}, 'Location', 'best', 'Box', 'off');
set(gca, 'FontName', 'Times New Roman', 'FontSize', 10, 'LineWidth', 0.8);

subplot(1, 2, 2); hold on;
scatter(added730(:,5), added730(:,6), 12, 'MarkerEdgeColor', colors(2,:), 'MarkerFaceColor', colors(2,:), 'MarkerFaceAlpha', 0.15, 'MarkerEdgeAlpha', 0.15);
scatter(legacy240(:,5), legacy240(:,6), 16, 'MarkerEdgeColor', colors(1,:), 'MarkerFaceColor', colors(1,:), 'MarkerFaceAlpha', 0.45, 'MarkerEdgeAlpha', 0.45);
xlabel(feature_labels{5}); ylabel(feature_labels{6});
title('Load standard deviation vs range');
box on; grid off; legend({'first730', 'legacy240'}, 'Location', 'best', 'Box', 'off');
set(gca, 'FontName', 'Times New Roman', 'FontSize', 10, 'LineWidth', 0.8);

exportgraphics(fig, output_file, 'Resolution', 400);
close(fig);
end

function plot_benchmark_bars(benchmark, output_file)
model_order = ["Linear", "Tree", "BaggedTree", "LSBoost", "SVMRBF"];
fig = figure('Color', 'w', 'Units', 'centimeters', 'Position', [2 2 20 13]);
for t = 1:7
    subplot(2, 4, t);
    sub = benchmark(benchmark.topology_id == t, :);
    vals = zeros(1, numel(model_order));
    for m = 1:numel(model_order)
        vals(m) = sub.cv5_RMSE(sub.model_family == model_order(m));
    end
    bar(vals, 'FaceColor', [0.25 0.55 0.85]); hold on;
    [best_val, best_idx] = min(vals);
    bar(best_idx, best_val, 'FaceColor', [0.90 0.45 0.10]);
    set(gca, 'XTick', 1:numel(model_order), 'XTickLabel', model_order, 'XTickLabelRotation', 30);
    ylabel('cv5 RMSE');
    title(sprintf('M%d', t));
    box on; grid off;
    set(gca, 'FontName', 'Times New Roman', 'FontSize', 9, 'LineWidth', 0.8);
end
exportgraphics(fig, output_file, 'Resolution', 400);
close(fig);
end

function plot_oof_parity(oof_table, output_file)
fig = figure('Color', 'w', 'Units', 'centimeters', 'Position', [2 2 20 13]);
for t = 1:7
    subplot(2, 4, t); hold on;
    sub = oof_table(oof_table.topology_id == t, :);
    scatter(sub.true_efficiency, sub.predicted_efficiency, 12, ...
        'MarkerEdgeColor', [0.2 0.45 0.85], 'MarkerFaceColor', [0.2 0.45 0.85], ...
        'MarkerFaceAlpha', 0.20, 'MarkerEdgeAlpha', 0.20);
    lo = min([sub.true_efficiency; sub.predicted_efficiency]);
    hi = max([sub.true_efficiency; sub.predicted_efficiency]);
    plot([lo hi], [lo hi], 'k--', 'LineWidth', 1.0);
    xlabel('Full module model');
    ylabel('LSBoost OOF prediction');
    title(sprintf('M%d', t));
    box on; grid off;
    axis tight;
    set(gca, 'FontName', 'Times New Roman', 'FontSize', 9, 'LineWidth', 0.8);
end
exportgraphics(fig, output_file, 'Resolution', 400);
close(fig);
end

function plot_final_metrics(final_metrics, output_file)
fig = figure('Color', 'w', 'Units', 'centimeters', 'Position', [2 2 18 7.5]);
t = tiledlayout(1,2, 'Padding', 'compact', 'TileSpacing', 'compact');

nexttile; hold on;
bar(categorical(final_metrics.topology_label), [final_metrics.cv5_R2, final_metrics.holdout_R2], 'grouped');
ylabel('R^2');
legend({'cv5', 'holdout'}, 'Location', 'best', 'Box', 'off');
box on; grid off;
set(gca, 'FontName', 'Times New Roman', 'FontSize', 10, 'LineWidth', 0.8);
title('Generalisation R^2');

nexttile; hold on;
bar(categorical(final_metrics.topology_label), [final_metrics.cv5_RMSE, final_metrics.holdout_RMSE], 'grouped');
ylabel('RMSE');
legend({'cv5', 'holdout'}, 'Location', 'best', 'Box', 'off');
box on; grid off;
set(gca, 'FontName', 'Times New Roman', 'FontSize', 10, 'LineWidth', 0.8);
title('Generalisation RMSE');

title(t, 'Final LSBoost metrics on the 970-scenario dataset', 'FontName', 'Times New Roman', 'FontSize', 12);
exportgraphics(fig, output_file, 'Resolution', 400);
close(fig);
end
