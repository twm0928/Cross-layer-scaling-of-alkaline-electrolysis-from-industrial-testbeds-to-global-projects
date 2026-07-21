function run_stackA_distribution_model_comparison()
%RUN_STACKA_DISTRIBUTION_MODEL_COMPARISON Compare Stack A ECN prediction
% against the rated-current voltage-temperature-inferred current distribution.
%
% This validation-only script does not modify the stack workflow. It uses
% the uploadable local copy of f_stack.m and Stack A experimental outputs.

scriptDir = fileparts(mfilename('fullpath'));
evRoot = fileparts(scriptDir);
stackSrc = fullfile(scriptDir, 'stack_model');
addpath(stackSrc);

out9 = fullfile(evRoot, 'outputs', 'step9_stackA_independent_validation');
out10 = fullfile(evRoot, 'outputs', 'step10_stackA_distribution_model_comparison');
if ~exist(out10, 'dir')
    mkdir(out10);
end

cfgText = fileread(fullfile(evRoot, 'config', 'stackA_independent.json'));
firstBrace = find(cfgText == '{', 1, 'first');
if isempty(firstBrace)
    error('Could not find JSON object start in stackA_independent.json.');
end
cfgText = cfgText(firstBrace:end);
cfg = jsondecode(cfgText);
coeff = readtable(fullfile(out9, 'stackA_voltage_model_coefficients.csv'), 'TextType', 'string');
coeffNames = string(coeff.coefficient);
coeffValues = to_double(coeff.value);
beta0 = coeffValues(coeffNames == "beta0");
betaT = coeffValues(coeffNames == "betaT");
betaJ = coeffValues(coeffNames == "betaJ");
betaJT = coeffValues(coeffNames == "betaJT");

distSummary = read_metric_map(fullfile(out9, 'stackA_cell_distribution_summary.csv'));
currentSummary = read_metric_map(fullfile(out9, 'stackA_voltage_temperature_inferred_current_summary.csv'));
profile = readtable(fullfile(out9, 'stackA_voltage_temperature_inferred_current_distribution_7000A.csv'));

cellId = to_double(profile.cell_id);
validChannel = to_logical(profile.valid_channel);
inferredCurrentA = to_double(profile.inferred_current_A);
inferredPu = to_double(profile.inferred_current_pu_rated);
measuredVoltage = to_double(profile.mean_cell_voltage_V);
interpolatedTemperature = to_double(profile.interpolated_temperature_C);

valid = validChannel & isfinite(inferredCurrentA) & isfinite(measuredVoltage) ...
    & isfinite(interpolatedTemperature) & isfinite(inferredPu);

meanCurrentA = currentSummary.mean_rectifier_current_A;
ratedCurrentA = cfg.rated_current_A;
meanTempC = distSummary.temperature_mean_C;
areaM2 = cfg.electrode_area_m2;
R0 = (betaJ + betaJT * meanTempC) / areaM2;
U0 = beta0 + betaT * meanTempC;

resist = build_stackA_resistances(cfg, meanTempC);
[iEle, iStray] = f_stack(cfg.n_cells, R0, U0, ...
    resist.Rm_l, resist.Rm_u, resist.Rch_l_an, resist.Rch_l_ca, ...
    resist.Rch_u_an, resist.Rch_u_ca, resist.R_end, ratedCurrentA);

iEle = full(iEle);
iStray = full(iStray);
modelCurrentRawA = iEle;
modelCurrentPu = modelCurrentRawA / ratedCurrentA;
modelCurrentA = modelCurrentRawA;
modelVoltageLocalT = beta0 + betaT .* interpolatedTemperature ...
    + (betaJ + betaJT .* interpolatedTemperature) ...
    .* (modelCurrentA ./ areaM2);
modelVoltageMeanT = U0 + R0 .* modelCurrentA;

inferredPuTrend = moving_average_omitnan(inferredPu, valid, 10);
voltageTrend = moving_average_omitnan(measuredVoltage, valid, 10);

comparison = table();
comparison.cell_id = cellId;
comparison.valid_channel = valid;
comparison.measured_cell_voltage_V = measuredVoltage;
comparison.measured_cell_voltage_trend_21cell_V = voltageTrend;
comparison.interpolated_temperature_C = interpolatedTemperature;
comparison.inferred_current_voltage_temperature_A = inferredCurrentA;
comparison.inferred_current_voltage_temperature_pu_rated = inferredPu;
comparison.inferred_current_voltage_temperature_trend_21cell_pu_rated = inferredPuTrend;
comparison.model_current_raw_A = modelCurrentRawA;
comparison.model_current_A = modelCurrentA;
comparison.model_current_pu = modelCurrentPu;
comparison.model_stray_current_A = iStray;
comparison.model_voltage_local_temperature_V = modelVoltageLocalT;
comparison.model_voltage_mean_temperature_V = modelVoltageMeanT;
comparison.current_pu_error_raw = modelCurrentPu - inferredPu;
comparison.current_pu_error_trend_21cell = modelCurrentPu - inferredPuTrend;
comparison.voltage_error_raw_V = modelVoltageLocalT - measuredVoltage;
comparison.voltage_error_trend_21cell_V = modelVoltageLocalT - voltageTrend;

writetable(comparison, fullfile(out10, 'stackA_distribution_model_comparison_profile.csv'));

metrics = {};
metrics = add_metric(metrics, 'input', 'n_cells', cfg.n_cells);
metrics = add_metric(metrics, 'input', 'n_valid_cells', sum(valid));
metrics = add_metric(metrics, 'input', 'mean_rectifier_current_A', meanCurrentA);
metrics = add_metric(metrics, 'input', 'rated_current_A', ratedCurrentA);
metrics = add_metric(metrics, 'input', 'mean_temperature_C', meanTempC);
metrics = add_metric(metrics, 'input', 'beta0_V', beta0);
metrics = add_metric(metrics, 'input', 'betaT_V_per_C', betaT);
metrics = add_metric(metrics, 'input', 'betaJ_V_m2_per_A', betaJ);
metrics = add_metric(metrics, 'input', 'betaJT_V_m2_per_A_C', betaJT);
metrics = add_metric(metrics, 'input', 'U0_branch_at_mean_temperature_V', U0);
metrics = add_metric(metrics, 'input', 'R0_ohm_at_mean_temperature', R0);
metrics = add_metric(metrics, 'input', 'electrolyte_resistivity_ohm_m', resist.rho);
metrics = add_metric(metrics, 'input', 'Rm_l_ohm', resist.Rm_l);
metrics = add_metric(metrics, 'input', 'Rm_u_ohm', resist.Rm_u);
metrics = add_metric(metrics, 'input', 'Rch_l_an_ohm', resist.Rch_l_an);
metrics = add_metric(metrics, 'input', 'Rch_l_ca_ohm', resist.Rch_l_ca);
metrics = add_metric(metrics, 'input', 'Rch_u_an_ohm', resist.Rch_u_an);
metrics = add_metric(metrics, 'input', 'Rch_u_ca_ohm', resist.Rch_u_ca);
metrics = add_metric(metrics, 'model_distribution', 'current_std_over_mean', std(modelCurrentPu(valid)));
metrics = add_metric(metrics, 'experimental_inferred_distribution_raw', 'current_std_over_mean', std(inferredPu(valid)));
metrics = add_metric(metrics, 'experimental_inferred_distribution_trend_21cell', 'current_std_over_mean', std(inferredPuTrend(valid)));
metrics = add_metric(metrics, 'comparison_current_raw', 'MAE_pu', mean_omitnan(abs(comparison.current_pu_error_raw(valid))));
metrics = add_metric(metrics, 'comparison_current_raw', 'RMSE_pu', sqrt(mean_omitnan(comparison.current_pu_error_raw(valid).^2)));
metrics = add_metric(metrics, 'comparison_current_raw', 'Pearson_r', pearson_omitnan(modelCurrentPu(valid), inferredPu(valid)));
metrics = add_metric(metrics, 'comparison_current_trend_21cell', 'MAE_pu', mean_omitnan(abs(comparison.current_pu_error_trend_21cell(valid))));
metrics = add_metric(metrics, 'comparison_current_trend_21cell', 'RMSE_pu', sqrt(mean_omitnan(comparison.current_pu_error_trend_21cell(valid).^2)));
metrics = add_metric(metrics, 'comparison_current_trend_21cell', 'Pearson_r', pearson_omitnan(modelCurrentPu(valid), inferredPuTrend(valid)));
metrics = add_metric(metrics, 'comparison_voltage_raw', 'MAE_mV', 1000 * mean_omitnan(abs(comparison.voltage_error_raw_V(valid))));
metrics = add_metric(metrics, 'comparison_voltage_raw', 'RMSE_mV', 1000 * sqrt(mean_omitnan(comparison.voltage_error_raw_V(valid).^2)));
metrics = add_metric(metrics, 'comparison_voltage_raw', 'Pearson_r', pearson_omitnan(modelVoltageLocalT(valid), measuredVoltage(valid)));
metrics = add_metric(metrics, 'comparison_voltage_trend_21cell', 'MAE_mV', 1000 * mean_omitnan(abs(comparison.voltage_error_trend_21cell_V(valid))));
metrics = add_metric(metrics, 'comparison_voltage_trend_21cell', 'RMSE_mV', 1000 * sqrt(mean_omitnan(comparison.voltage_error_trend_21cell_V(valid).^2)));
metrics = add_metric(metrics, 'comparison_voltage_trend_21cell', 'Pearson_r', pearson_omitnan(modelVoltageLocalT(valid), voltageTrend(valid)));
metrics = add_distribution_metrics(metrics, 'model_distribution', modelCurrentPu, valid, cfg.n_cells);
metrics = add_distribution_metrics(metrics, 'experimental_inferred_distribution_raw', inferredPu, valid, cfg.n_cells);
metrics = add_distribution_metrics(metrics, 'experimental_inferred_distribution_trend_21cell', inferredPuTrend, valid, cfg.n_cells);

metricsTable = cell2table(metrics, 'VariableNames', {'scope', 'metric', 'value'});
writetable(metricsTable, fullfile(out10, 'stackA_distribution_model_comparison_metrics.csv'));

write_readme(out10);
disp(['Stack A distribution-model comparison outputs written to: ' out10]);
end

function metricMap = read_metric_map(filePath)
T = readtable(filePath, 'TextType', 'string');
metricMap = struct();
for i = 1:height(T)
    name = matlab.lang.makeValidName(T.metric(i));
    value = str2double(T.value(i));
    if isnan(value)
        metricMap.(name) = T.value(i);
    else
        metricMap.(name) = value;
    end
end
end

function x = to_double(x)
if isnumeric(x)
    x = double(x);
elseif islogical(x)
    x = double(x);
elseif iscell(x)
    x = str2double(string(x));
else
    x = str2double(string(x));
end
x = x(:);
end

function y = to_logical(x)
if islogical(x)
    y = x;
elseif isnumeric(x)
    y = x ~= 0;
else
    s = lower(strtrim(string(x)));
    y = (s == "true") | (s == "1") | (s == "yes");
end
y = y(:);
end

function resist = build_stackA_resistances(cfg, temperatureC)
m = 0.31;
T = temperatureC + 273.15;
n_l = 2;
alpha = 0;

sigma = 2800*m - 0.9241*T - 0.01497*T^2 - 9.052*T*m ...
    + 0.02591*T^2*m^(0.1765) + 0.06966*T*m^(-1) - 289800*m*T^(-1);
rho = 1 / sigma;

lm = cfg.chamber_thickness_cm * 1e-2;
lc = cfg.channel_length_cm * 1e-2;
areaInManifold = mean([cfg.cathode_inlet_manifold_area_cm2, cfg.anode_inlet_manifold_area_cm2]) * 1e-4;
areaOutManifold = mean([cfg.cathode_outlet_manifold_area_cm2, cfg.anode_outlet_manifold_area_cm2]) * 1e-4;
areaInAn = cfg.anode_inlet_channel_area_cm2 * 1e-4;
areaInCa = cfg.cathode_inlet_channel_area_cm2 * 1e-4;
areaOutAn = cfg.anode_outlet_channel_area_cm2 * 1e-4;
areaOutCa = cfg.cathode_outlet_channel_area_cm2 * 1e-4;

resist = struct();
resist.rho = rho;
resist.Rm_l = rho * lm / (areaInManifold * n_l);
resist.Rm_u = rho * lm / areaOutManifold / (1 - alpha)^1.5;
resist.Rch_l_an = rho * lc / (areaInAn * n_l);
resist.Rch_l_ca = rho * lc / (areaInCa * n_l);
resist.Rch_u_an = rho * lc / areaOutAn / (1 - alpha)^1.5;
resist.Rch_u_ca = rho * lc / areaOutCa / (1 - alpha)^1.5;
resist.Rm_end = resist.Rm_l;
resist.Rch_l_end = mean([resist.Rch_l_an, resist.Rch_l_ca]);
resist.R_end = resist.Rm_end + resist.Rch_l_end;
end

function y = moving_average_omitnan(x, valid, halfWindow)
x = double(x);
y = nan(size(x));
for i = 1:numel(x)
    lo = max(1, i - halfWindow);
    hi = min(numel(x), i + halfWindow);
    idx = lo:hi;
    idx = idx(valid(idx) & isfinite(x(idx)));
    if ~isempty(idx)
        y(i) = mean(x(idx));
    end
end
end

function metrics = add_distribution_metrics(metrics, scope, x, valid, nCells)
first10 = valid & ((1:nCells)' <= 10);
last10 = valid & ((1:nCells)' > nCells - 10);
edge = first10 | last10;
core = valid & ((1:nCells)' >= 51) & ((1:nCells)' <= nCells - 50);
odd = valid & (mod((1:nCells)', 2) == 1);
even = valid & (mod((1:nCells)', 2) == 0);
metrics = add_metric(metrics, scope, 'min', min_omitnan(x(valid)));
metrics = add_metric(metrics, scope, 'max', max_omitnan(x(valid)));
metrics = add_metric(metrics, scope, 'spread', max_omitnan(x(valid)) - min_omitnan(x(valid)));
metrics = add_metric(metrics, scope, 'edge_mean', mean_omitnan(x(edge)));
metrics = add_metric(metrics, scope, 'core_mean', mean_omitnan(x(core)));
metrics = add_metric(metrics, scope, 'edge_minus_core', mean_omitnan(x(edge)) - mean_omitnan(x(core)));
metrics = add_metric(metrics, scope, 'odd_mean', mean_omitnan(x(odd)));
metrics = add_metric(metrics, scope, 'even_mean', mean_omitnan(x(even)));
metrics = add_metric(metrics, scope, 'odd_minus_even', mean_omitnan(x(odd)) - mean_omitnan(x(even)));
end

function metrics = add_metric(metrics, scope, metric, value)
metrics(end + 1, :) = {char(scope), char(metric), value};
end

function m = mean_omitnan(x)
x = x(isfinite(x));
if isempty(x)
    m = NaN;
else
    m = mean(x);
end
end

function m = min_omitnan(x)
x = x(isfinite(x));
if isempty(x)
    m = NaN;
else
    m = min(x);
end
end

function m = max_omitnan(x)
x = x(isfinite(x));
if isempty(x)
    m = NaN;
else
    m = max(x);
end
end

function r = pearson_omitnan(x, y)
idx = isfinite(x) & isfinite(y);
x = x(idx);
y = y(idx);
if numel(x) < 2 || std(x) == 0 || std(y) == 0
    r = NaN;
else
    x = x - mean(x);
    y = y - mean(y);
    r = sum(x .* y) / sqrt(sum(x .^ 2) * sum(y .^ 2));
end
end

function write_readme(outDir)
text = [
"# Step 10: Stack A Distribution-Model Comparison" newline newline ...
"This folder compares the distributed equivalent-circuit stack model against the Stack A voltage-temperature-inferred current distribution at the rated-current operating point." newline newline ...
"## Logic" newline newline ...
"1. The compact Stack A voltage relation fitted in Step 9 is converted to the f_stack branch-voltage form at the measured mean temperature: U0 = beta0 + betaT*T_mean and R0 = (betaJ + betaJT*T_mean)/A_cell." newline ...
"2. Stack A geometric parameters are converted to manifold and channel resistances using the same electrolyte-conductivity expression as the stack workflow." newline ...
"3. The distributed equivalent-circuit model predicts the cell-wise electrolysis current distribution at the rated 7000 A input-current operating point, matching the full-load convention used in the manuscript current-distribution figure." newline ...
"4. The experimental current distribution is reconstructed from measured cell voltage and interpolated local temperature without forcing the mean to equal the rectifier current. The raw inferred points and a 21-cell local trend are both reported in per unit using the 7000 A rated current as the base value." newline newline ...
"## Main outputs" newline newline ...
"- `stackA_distribution_model_comparison_profile.csv`: cell-wise measured voltage, voltage-temperature-inferred current, model current and model voltage." newline ...
"- `stackA_distribution_model_comparison_metrics.csv`: current-distribution and voltage-distribution comparison metrics." newline newline ...
"## Claim boundary" newline newline ...
"This comparison supports the rated-current edge-to-core current-distribution envelope. It should not be claimed as a point-by-point validation of every individual cell current because Stack A does not include direct per-cell current sensors and the cell-voltage measurements contain high-frequency channel-specific artefacts." newline ...
];
fid = fopen(fullfile(outDir, 'README.md'), 'w');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s', text);
end
