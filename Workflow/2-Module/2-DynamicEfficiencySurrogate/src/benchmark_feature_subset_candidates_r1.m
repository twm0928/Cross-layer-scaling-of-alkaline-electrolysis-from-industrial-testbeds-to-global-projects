function result = benchmark_feature_subset_candidates_r1()
%BENCHMARK_FEATURE_SUBSET_CANDIDATES_R1 Compare modest feature expansions.

src_dir = fileparts(mfilename('fullpath'));
root_dir = fileparts(src_dir);
module_root = fileparts(root_dir);
input_dir = fullfile(module_root, 'data', 'input');
output_dir = fullfile(root_dir, 'outputs');
if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end

load(fullfile(input_dir, 'P_command.mat'), 'P_command');
scenario_ids = get_r1_dynamic_scenario_ids('combined970');
dataset = build_dynamic_training_dataset(scenario_ids);

PmaxMW = 20;
num_selected = numel(scenario_ids);
X8 = zeros(num_selected, 8);
for k = 1:num_selected
    X8(k, :) = compute_dynamic_features_richer(P_command(scenario_ids(k), :), PmaxMW);
end

feature_sets = {
    'baseline4',     1:4;
    'operational6',  1:6;
    'statistical6',  [1:4 7 8];
    'richer8',       1:8
};

rows = {};
row = 0;
for fs = 1:size(feature_sets, 1)
    feature_name = feature_sets{fs, 1};
    cols = feature_sets{fs, 2};
    Xfull = X8(:, cols);
    for t = 1:7
        valid = dataset.valid_mask(t, :);
        X = Xfull(valid, :);
        y = dataset.efficiency_lhv(t, valid)';
        scen = dataset.scenario_ids(valid)';

        rng(20260621 + 100 * fs + t, 'twister');
        cvp = cvpartition(size(X, 1), 'KFold', 5);
        y_cv = nan(size(y));

        for fold = 1:5
            tr = training(cvp, fold);
            te = test(cvp, fold);
            templ = templateTree('Reproducible', true, 'MinLeafSize', 5);
            mdl = fitrensemble(X(tr, :), y(tr), ...
                'Method', 'LSBoost', ...
                'Learners', templ, ...
                'NumLearningCycles', 150, ...
                'LearnRate', 0.05);
            y_cv(te) = predict(mdl, X(te, :));
        end

        metrics_all = regression_metrics(y, y_cv);
        idx730 = scen <= 730;
        metrics_730 = regression_metrics(y(idx730), y_cv(idx730));

        row = row + 1;
        rows(row, :) = { ...
            feature_name, t, compose("M%d", t), numel(cols), ...
            sum(valid), metrics_all.RMSE, metrics_all.R2, ...
            sum(idx730), metrics_730.RMSE, metrics_730.R2 ...
            };
    end
end

summary = cell2table(rows, 'VariableNames', { ...
    'feature_set', 'topology_id', 'topology_label', 'num_features', ...
    'n_all970', 'rmse_all970', 'r2_all970', ...
    'n_natural730', 'rmse_natural730', 'r2_natural730'});

summary_file = fullfile(output_dir, 'feature_subset_candidates_r1.csv');
writetable(summary, summary_file);

result = struct();
result.summary = summary;
result.summary_file = summary_file;
disp(summary);
fprintf('Feature subset candidate benchmark exported to:\n  %s\n', summary_file);
end

function metrics = regression_metrics(y_true, y_pred)
res = y_true - y_pred;
eps0 = 1e-8;
metrics = struct();
metrics.RMSE = sqrt(mean(res .^ 2));
metrics.R2 = 1 - sum(res .^ 2) / max(sum((y_true - mean(y_true)) .^ 2), eps0);
end
