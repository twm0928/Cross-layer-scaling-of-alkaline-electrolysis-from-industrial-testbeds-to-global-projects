function [training_table, comparison_table, best_bundle] = step2_benchmark_daily_degradation_models()
%STEP2_BENCHMARK_DAILY_DEGRADATION_MODELS
% Step 2:
% benchmark candidate input-output models on the clean daily degradation-rate target.

cfg = degradation_model_config();
daily_table = readtable(cfg.step1_daily_target_csv, 'TextType', 'string');

training_table = build_training_table(daily_table, cfg);
writetable(training_table, cfg.step2_training_table_csv);

valid_mask = training_table.valid_for_model > 0;
train_mask = valid_mask & training_table.is_train > 0;
test_mask = valid_mask & training_table.is_test > 0;

X_train = training_table{train_mask, cfg.feature_columns};
y_train = training_table{train_mask, cfg.target_column};
X_test = training_table{test_mask, cfg.feature_columns};
y_test = training_table{test_mask, cfg.target_column};

comparison_rows = cell(numel(cfg.model_families), 1);
prediction_table = training_table(:, {'unit', 'day_index', cfg.target_column, 'is_train', 'is_test'});
prediction_table.Properties.VariableNames{3} = 'target_mV_per_day';

best_rmse = inf;
best_curve_rmse = inf;
best_family = "";
best_test_family = "";
best_model_train_only = [];

for i = 1:numel(cfg.model_families)
    family = cfg.model_families{i};
    model = fit_model_family(X_train, y_train, family, cfg);
    pred_train = predict_model_family(model, X_train, family);
    pred_test = predict_model_family(model, X_test, family);

    train_metrics = compute_metrics(y_train, pred_train);
    test_metrics = compute_metrics(y_test, pred_test);

    model_all_family = fit_model_family(training_table{valid_mask, cfg.feature_columns}, training_table{valid_mask, cfg.target_column}, family, cfg);
    pred_all_family = predict_model_family(model_all_family, training_table{valid_mask, cfg.feature_columns}, family);
    curve_metrics = compute_curve_metrics(training_table(valid_mask, :), pred_all_family);

    comparison_rows{i} = table( ...
        string(family), ...
        train_metrics.rmse, train_metrics.mae, train_metrics.r2, ...
        test_metrics.rmse, test_metrics.mae, test_metrics.r2, ...
        curve_metrics.curve_rmse, curve_metrics.endpoint_mae, ...
        'VariableNames', {'model_family', 'train_rmse', 'train_mae', 'train_r2', 'test_rmse', 'test_mae', 'test_r2', 'refit_curve_rmse', 'refit_endpoint_mae'});

    pred_column = strings(height(training_table), 1);
    pred_all = NaN(height(training_table), 1);
    pred_all(train_mask) = pred_train;
    pred_all(test_mask) = pred_test;
    pred_column_name = matlab.lang.makeValidName("pred_" + string(family));
    prediction_table.(pred_column_name) = pred_all;

    if test_metrics.rmse < best_rmse
        best_rmse = test_metrics.rmse;
        best_test_family = string(family);
        best_model_train_only = model;
    end

    if curve_metrics.curve_rmse < best_curve_rmse
        best_curve_rmse = curve_metrics.curve_rmse;
        best_family = string(family);
    end
end

comparison_table = vertcat(comparison_rows{:});
[~, sort_idx] = sort(comparison_table.refit_curve_rmse, 'ascend');
comparison_table = comparison_table(sort_idx, :);
writetable(comparison_table, cfg.step2_model_comparison_csv);

X_all = training_table{valid_mask, cfg.feature_columns};
y_all = training_table{valid_mask, cfg.target_column};
best_model_all = fit_model_family(X_all, y_all, best_family, cfg);
pred_refit_all = predict_model_family(best_model_all, X_all, best_family);
prediction_table.pred_best_refit_all = NaN(height(training_table), 1);
prediction_table.pred_best_refit_all(valid_mask) = pred_refit_all;
writetable(prediction_table, cfg.step2_daily_predictions_csv);

best_metrics = comparison_table(comparison_table.model_family == best_family, :);
writetable(best_metrics, cfg.step2_best_model_metrics_csv);

best_bundle = struct();
best_bundle.family = char(best_family);
best_bundle.best_test_family = char(best_test_family);
best_bundle.feature_columns = cfg.feature_columns;
best_bundle.target_column = cfg.target_column;
best_bundle.model_train_only = best_model_train_only;
best_bundle.model_all = best_model_all;
save(cfg.step2_best_model_mat, 'best_bundle');

write_step2_summary(cfg, training_table, comparison_table, best_test_family, best_family);
end

function training_table = build_training_table(daily_table, cfg)
training_table = sortrows(daily_table, {'unit', 'day_index'});

training_table.cum_daily_eflh_h = zeros(height(training_table), 1);
training_table.cum_high_load_hours = zeros(height(training_table), 1);
training_table.cum_start_count = zeros(height(training_table), 1);
training_table.cum_stop_count = zeros(height(training_table), 1);
training_table.is_train = zeros(height(training_table), 1);
training_table.is_test = zeros(height(training_table), 1);
training_table.valid_for_model = zeros(height(training_table), 1);

units = unique(training_table.unit);
for i = 1:numel(units)
    mask = training_table.unit == units(i);
    idx = find(mask);

    training_table.cum_daily_eflh_h(idx) = cumsum(fillmissing(training_table.daily_eflh_h(idx), 'constant', 0));
    training_table.cum_high_load_hours(idx) = cumsum(fillmissing(training_table.high_load_hours(idx), 'constant', 0));
    training_table.cum_start_count(idx) = cumsum(fillmissing(training_table.start_count(idx), 'constant', 0));
    training_table.cum_stop_count(idx) = cumsum(fillmissing(training_table.stop_count(idx), 'constant', 0));

    valid_idx = idx(training_table.valid_target(idx) > 0 ...
        & isfinite(training_table.(cfg.target_column)(idx)));
    training_table.valid_for_model(valid_idx) = 1;

    n_valid = numel(valid_idx);
    if n_valid < 6
        continue;
    end

    n_train = floor(cfg.train_ratio * n_valid);
    n_train = max(n_train, 4);
    n_train = min(n_train, n_valid - 1);

    training_table.is_train(valid_idx(1:n_train)) = 1;
    training_table.is_test(valid_idx(n_train + 1:end)) = 1;
end
end

function model = fit_model_family(X, y, family, cfg)
rng(cfg.random_seed);

switch string(family)
    case "Linear Regression"
        model = fitrlinear(X, y, 'Learner', 'leastsquares', 'Regularization', 'ridge', 'Lambda', 1e-4);

    case "Regression Tree"
        model = fitrtree(X, y, 'MinLeafSize', 4);

    case "Bagged Trees"
        t = templateTree('MinLeafSize', 4);
        model = fitrensemble(X, y, 'Method', 'Bag', 'NumLearningCycles', 300, 'Learners', t);

    case "Gradient Boosting"
        t = templateTree('MinLeafSize', 4, 'MaxNumSplits', 8);
        model = fitrensemble(X, y, 'Method', 'LSBoost', 'NumLearningCycles', 300, 'LearnRate', 0.05, 'Learners', t);

    case "Gaussian Process"
        model = fitrgp(X, y, 'KernelFunction', 'ardsquaredexponential', 'Standardize', true);

    case "Support Vector Regression"
        model = fitrsvm(X, y, 'KernelFunction', 'gaussian', 'Standardize', true);

    otherwise
        error('Unsupported model family: %s', family);
end
end

function y_hat = predict_model_family(model, X, family)
switch string(family)
    case {"Linear Regression", "Regression Tree", "Bagged Trees", "Gradient Boosting", "Gaussian Process", "Support Vector Regression"}
        y_hat = predict(model, X);
    otherwise
        error('Unsupported model family: %s', family);
end
end

function metrics = compute_metrics(y_true, y_hat)
residual = y_true - y_hat;
metrics = struct();
metrics.rmse = sqrt(mean(residual .^ 2, 'omitnan'));
metrics.mae = mean(abs(residual), 'omitnan');
sst = sum((y_true - mean(y_true, 'omitnan')) .^ 2, 'omitnan');
sse = sum(residual .^ 2, 'omitnan');
metrics.r2 = 1 - sse / max(sst, eps);
end

function curve_metrics = compute_curve_metrics(valid_table, pred_daily_rate)
curve_metrics = struct('curve_rmse', NaN, 'endpoint_mae', NaN);

units = unique(valid_table.unit);
curve_rmse_list = NaN(numel(units), 1);
endpoint_mae_list = NaN(numel(units), 1);

for i = 1:numel(units)
    mask = valid_table.unit == units(i);
    unit_table = valid_table(mask, :);
    unit_table = sortrows(unit_table, 'day_index');
    unit_pred = pred_daily_rate(mask);
    unit_pred = unit_pred(:);
    pred_cum = cumsum(max(unit_pred, 0));
    exp_cum = unit_table.clean_cum_deg_cell_mV;
    curve_rmse_list(i) = sqrt(mean((pred_cum - exp_cum) .^ 2, 'omitnan'));
    endpoint_mae_list(i) = abs(pred_cum(end) - exp_cum(end));
end

curve_metrics.curve_rmse = mean(curve_rmse_list, 'omitnan');
curve_metrics.endpoint_mae = mean(endpoint_mae_list, 'omitnan');
end

function write_step2_summary(cfg, training_table, comparison_table, best_test_family, best_family)
fid = fopen(cfg.step2_summary_txt, 'w');
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, 'Step 2 summary: daily degradation-rate model benchmark\n');
fprintf(fid, 'Lowest time-ordered test RMSE: %s\n', best_test_family);
fprintf(fid, 'Active family selected by observed-curve reconstruction RMSE: %s\n\n', best_family);

fprintf(fid, 'Training/test rows by unit:\n');
units = unique(training_table.unit);
for i = 1:numel(units)
    mask = training_table.unit == units(i);
    fprintf(fid, '- %s: train = %d, test = %d, valid = %d\n', ...
        units(i), ...
        nnz(mask & training_table.is_train > 0), ...
        nnz(mask & training_table.is_test > 0), ...
        nnz(mask & training_table.valid_for_model > 0));
end

fprintf(fid, '\nModel-family ranking:\n');
for i = 1:height(comparison_table)
    fprintf(fid, '%d) %s | Curve RMSE = %.6f | Endpoint MAE = %.6f | Test RMSE = %.6f | Test R2 = %.6f\n', ...
        i, comparison_table.model_family(i), comparison_table.refit_curve_rmse(i), comparison_table.refit_endpoint_mae(i), comparison_table.test_rmse(i), comparison_table.test_r2(i));
end

fprintf(fid, '\nOutput files:\n');
fprintf(fid, '- %s\n', cfg.step2_training_table_csv);
fprintf(fid, '- %s\n', cfg.step2_model_comparison_csv);
fprintf(fid, '- %s\n', cfg.step2_best_model_metrics_csv);
fprintf(fid, '- %s\n', cfg.step2_daily_predictions_csv);
fprintf(fid, '- %s\n', cfg.step2_best_model_mat);
end
