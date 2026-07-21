function result = benchmark_dynamic_surrogates_r1(config)
%BENCHMARK_DYNAMIC_SURROGATES_R1 Compare dynamic-surrogate model families.
%   RESULT = BENCHMARK_DYNAMIC_SURROGATES_R1() benchmarks several model
%   families on the combined R1 scenario set (730 + 240 = 970).

if nargin < 1
    config = struct();
end

config = set_default(config, 'ScenarioMode', 'combined970');
config = set_default(config, 'KFold', 5);
config = set_default(config, 'RandomSeed', 20260620);

src_dir = fileparts(mfilename('fullpath'));
surrogate_root = fileparts(src_dir);
output_dir = fullfile(surrogate_root, 'outputs');
if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end

scenario_ids = get_r1_dynamic_scenario_ids(config.ScenarioMode);
dataset = build_dynamic_training_dataset(scenario_ids);

model_names = ["Linear" "Tree" "BaggedTree" "LSBoost" "SVMRBF"];
topology_ids = 1:7;
rows = cell(numel(topology_ids) * numel(model_names), 8);
row = 0;

for t = topology_ids
    valid = dataset.valid_mask(t, :);
    X = dataset.features(valid, :);
    y = dataset.efficiency_lhv(t, valid)';

    rng(config.RandomSeed + t, 'twister');
    cvp = cvpartition(size(X, 1), 'KFold', config.KFold);

    for m = 1:numel(model_names)
        model_name = model_names(m);
        y_cv = nan(size(y));

        for fold = 1:config.KFold
            train_idx = training(cvp, fold);
            test_idx = test(cvp, fold);
            mdl = fit_model(model_name, X(train_idx, :), y(train_idx, :), config.RandomSeed + 100*t + fold);
            y_cv(test_idx) = predict_model(mdl, model_name, X(test_idx, :));
        end

        metrics = regression_metrics(y, y_cv);
        row = row + 1;
        rows(row, :) = { ...
            t, compose("M%d", t), char(model_name), size(X, 1), ...
            metrics.MAE, metrics.RMSE, metrics.R2, metrics.MAPE_percent ...
            };
    end
end

benchmark_table = cell2table(rows, 'VariableNames', { ...
    'topology_id', 'topology_label', 'model_family', 'n_samples', ...
    'cv5_MAE', 'cv5_RMSE', 'cv5_R2', 'cv5_MAPE_percent'});

csv_file = fullfile(output_dir, 'eta_model_r1_970_benchmark.csv');
writetable(benchmark_table, csv_file);

result = struct();
result.benchmark_table = benchmark_table;
result.csv_file = csv_file;

disp(benchmark_table);
fprintf('Dynamic surrogate benchmark complete.\n');
fprintf('  %s\n', csv_file);
end

function config = set_default(config, field_name, default_value)
if ~isfield(config, field_name) || isempty(config.(field_name))
    config.(field_name) = default_value;
end
end

function mdl = fit_model(model_name, X, y, seed)
rng(seed, 'twister');
switch char(model_name)
    case 'Linear'
        mdl = fitlm(X, y);
    case 'Tree'
        mdl = fitrtree(X, y, 'MinLeafSize', 10);
    case 'BaggedTree'
        templ = templateTree('Reproducible', true, 'MinLeafSize', 5);
        mdl = fitrensemble(X, y, 'Method', 'Bag', 'Learners', templ, 'NumLearningCycles', 100);
    case 'LSBoost'
        templ = templateTree('Reproducible', true, 'MinLeafSize', 5);
        mdl = fitrensemble(X, y, 'Method', 'LSBoost', 'Learners', templ, ...
            'NumLearningCycles', 150, 'LearnRate', 0.05);
    case 'SVMRBF'
        mdl = fitrsvm(X, y, 'KernelFunction', 'gaussian', 'KernelScale', 'auto', 'Standardize', true);
    otherwise
        error('Unknown model family: %s', model_name);
end
end

function y_pred = predict_model(mdl, model_name, X)
switch char(model_name)
    case 'Linear'
        y_pred = predict(mdl, X);
    otherwise
        y_pred = predict(mdl, X);
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
