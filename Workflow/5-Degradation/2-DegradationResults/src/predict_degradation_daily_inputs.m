function Tout = predict_degradation_daily_inputs(input_csv, output_csv)
%PREDICT_DEGRADATION_DAILY_INPUTS
% Run the current-version MATLAB degradation model on a current-version daily
% feature CSV and write prediction results.
%
% Important: the fitted target is the day-level cell-voltage degradation
% rate in mV/day. The cumulative long-term degradation term used by the
% voltage model is obtained by integrating that daily mV increment along
% the service-day index d.

cfg = degradation_results_config();
if nargin < 1 || isempty(input_csv)
    error('An input CSV path is required.');
end
if nargin < 2 || isempty(output_csv)
    [in_dir, in_name] = fileparts(char(string(input_csv)));
    if isempty(in_dir)
        in_dir = cfg.prediction_output_dir;
    end
    output_csv = fullfile(in_dir, [in_name '_predictions.csv']);
end

if ~isfile(cfg.active_model_file)
    error(['Active MATLAB model not found:\n  %s\n' ...
        'Run 1-DegradationModel/src/step2_benchmark_daily_degradation_models.m first.'], ...
        cfg.active_model_file);
end

loaded = load(cfg.active_model_file, 'best_bundle');
mdl = loaded.best_bundle.model_all;
T = readtable(input_csv, 'TextType', 'string');

missing = cfg.feature_columns(~ismember(cfg.feature_columns, T.Properties.VariableNames));
if ~isempty(missing)
    error('Missing required feature columns in input CSV:\n%s', strjoin(missing, ', '));
end

X = T{:, cfg.feature_columns};
pred_mV = predict(mdl, X);
pred_mV = max(pred_mV, 0);

Tout = T;
Tout.pred_daily_increment_u_cell_mV = pred_mV;
Tout.pred_daily_increment_u_cell_v = pred_mV / 1000;
Tout.pred_cumulative_u_cell_mV = grouped_cumsum(string(Tout.unit), pred_mV);
Tout.pred_cumulative_u_cell_v = Tout.pred_cumulative_u_cell_mV / 1000;
Tout.pred_increment_from_previous_day_u_cell_v = Tout.pred_daily_increment_u_cell_v;
Tout.pred_increment_from_previous_day_u_cell_mV = Tout.pred_daily_increment_u_cell_mV;

writetable(Tout, output_csv);
fprintf('Saved current-version MATLAB degradation predictions to:\n  %s\n', output_csv);

if isfield(loaded, 'best_bundle') && isfield(loaded.best_bundle, 'family')
    fprintf('Active model: %s\n', loaded.best_bundle.family);
end
end

function y = grouped_cumsum(group_id, x)
y = zeros(size(x));
u = unique(group_id, 'stable');
for i = 1:numel(u)
    mask = group_id == u(i);
    xv = x(mask);
    if isempty(xv)
        continue;
    end
    y(mask) = cumsum(xv);
end
end
