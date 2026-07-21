function result = retrain_dynamic_surrogates_r1(config)
%RETRAIN_DYNAMIC_SURROGATES_R1 Retrain M1-M7 models on the R1 970-scenario set.
%   RESULT = RETRAIN_DYNAMIC_SURROGATES_R1() uses the combined scenario set
%   (730 + legacy 240 = 970) and overwrites eta_model_topo1..7.mat.

if nargin < 1
    config = struct();
end

config = set_default(config, 'ScenarioMode', 'combined970');
config = set_default(config, 'HoldOut', 0.2);
config = set_default(config, 'RandomSeed', 20260620);
config = set_default(config, 'UseParallel', false);
config = set_default(config, 'KFold', 5);
config = set_default(config, 'UseHyperOpt', false);
config = set_default(config, 'NumLearningCycles', 150);
config = set_default(config, 'LearnRate', 0.05);
config = set_default(config, 'MinLeafSize', 5);

src_dir = fileparts(mfilename('fullpath'));
surrogate_root = fileparts(src_dir);
module_root = fileparts(surrogate_root);
output_dir = fullfile(surrogate_root, 'outputs');
model_dir = fullfile(module_root, 'data', 'dynamic_models');

if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end
if ~exist(model_dir, 'dir')
    mkdir(model_dir);
end

scenario_ids = get_r1_dynamic_scenario_ids(config.ScenarioMode);
dataset = build_dynamic_training_dataset(scenario_ids);
writetable(dataset.long_table, fullfile(output_dir, 'eta_model_r1_970_training_data.csv'));

topology_ids = 1:7;
topology_labels = compose("M%d", topology_ids);
metrics_rows = cell(numel(topology_ids), 16);

for t = topology_ids
    valid = dataset.valid_mask(t, :);
    X = dataset.features(valid, :);
    y = dataset.efficiency_lhv(t, valid)';

    if size(X, 1) < 20
        error('Topology %d has too few valid samples for retraining.', t);
    end

    rng(config.RandomSeed + t, 'twister');
    mdl = train_lsboost_model(X, y, config, config.RandomSeed + t);

    model_file = fullfile(model_dir, sprintf('eta_model_topo%d', t));
    saveLearnerForCoder(mdl, model_file);

    y_fit = predict(mdl, X);
    fit_metrics = regression_metrics(y, y_fit);

    cv_mdl = crossval(mdl, 'KFold', config.KFold);
    y_cv = kfoldPredict(cv_mdl);
    cv_metrics = regression_metrics(y, y_cv);

    cvp = cvpartition(size(X, 1), 'HoldOut', config.HoldOut);
    train_idx = training(cvp);
    test_idx = test(cvp);
    X_train = X(train_idx, :);
    y_train = y(train_idx, :);
    X_test = X(test_idx, :);
    y_test = y(test_idx, :);

    rng(config.RandomSeed + 100 + t, 'twister');
    mdl_holdout = train_lsboost_model(X_train, y_train, config, config.RandomSeed + 100 + t);
    y_holdout = predict(mdl_holdout, X_test);
    holdout_metrics = regression_metrics(y_test, y_holdout);

    metrics_rows(t, :) = { ...
        t, topology_labels(t), size(X, 1), ...
        fit_metrics.MAE, fit_metrics.RMSE, fit_metrics.R2, fit_metrics.MAPE_percent, ...
        cv_metrics.MAE, cv_metrics.RMSE, cv_metrics.R2, cv_metrics.MAPE_percent, ...
        holdout_metrics.MAE, holdout_metrics.RMSE, holdout_metrics.R2, holdout_metrics.MAPE_percent, ...
        model_file ...
        };
end

metrics_table = cell2table(metrics_rows, 'VariableNames', { ...
    'topology_id', 'topology_label', 'n_samples', ...
    'fit_MAE', 'fit_RMSE', 'fit_R2', 'fit_MAPE_percent', ...
    'cv5_MAE', 'cv5_RMSE', 'cv5_R2', 'cv5_MAPE_percent', ...
    'holdout_MAE', 'holdout_RMSE', 'holdout_R2', 'holdout_MAPE_percent', ...
    'model_file'});

metrics_csv = fullfile(output_dir, 'eta_model_r1_970_metrics.csv');
writetable(metrics_table, metrics_csv);

result = struct();
result.metrics_table = metrics_table;
result.metrics_csv = metrics_csv;
result.training_csv = fullfile(output_dir, 'eta_model_r1_970_training_data.csv');
result.model_dir = model_dir;

disp(metrics_table);
fprintf('Dynamic surrogate R1 retraining complete.\n');
fprintf('  metrics: %s\n', metrics_csv);
fprintf('  training data: %s\n', result.training_csv);
fprintf('  models: %s\n', model_dir);
end

function mdl = train_lsboost_model(X, y, config, seed)
rng(seed, 'twister');
templ = templateTree('Reproducible', true, 'MinLeafSize', config.MinLeafSize);
if config.UseHyperOpt
    mdl = fitrensemble(X, y, ...
        'Method', 'LSBoost', ...
        'Learners', templ, ...
        'OptimizeHyperparameters', {'NumLearningCycles', 'LearnRate', 'MinLeafSize', 'MaxNumSplits'}, ...
        'HyperparameterOptimizationOptions', struct( ...
            'KFold', config.KFold, ...
            'AcquisitionFunctionName', 'expected-improvement-plus', ...
            'MaxObjectiveEvaluations', 10, ...
            'ShowPlots', false, ...
            'Verbose', 0, ...
            'UseParallel', config.UseParallel));
else
    mdl = fitrensemble(X, y, ...
        'Method', 'LSBoost', ...
        'Learners', templ, ...
        'NumLearningCycles', config.NumLearningCycles, ...
        'LearnRate', config.LearnRate);
end
end

function config = set_default(config, field_name, default_value)
if ~isfield(config, field_name) || isempty(config.(field_name))
    config.(field_name) = default_value;
end
end

function metrics = regression_metrics(y_true, y_pred)
res = y_true - y_pred;
eps0 = 1e-8;

metrics = struct();
metrics.MAE = mean(abs(res));
metrics.RMSE = sqrt(mean(res .^ 2));
metrics.R2 = 1 - sum(res .^ 2) / max(sum((y_true - mean(y_true)) .^ 2), eps0);
metrics.MAPE_percent = mean(abs(res) ./ max(abs(y_true), eps0)) * 100;
end
