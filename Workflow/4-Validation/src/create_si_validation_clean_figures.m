function create_si_validation_clean_figures()
%CREATE_SI_VALIDATION_CLEAN_FIGURES Generate SI-ready validation figures.
%
% Updated naming:
%   - Stack B: Fangshan 5 MW full-system validation object
%   - Stack A: independent cell-resolved stack diagnostic
%
% Retained SI figures:
%   1) Stack B voltage validation
%   2) Stack B static-interface validation
%   3) Stack B interface replay versus full state-space H2 closure
%   4) Stack A distribution-envelope comparison

scriptDir = fileparts(mfilename('fullpath'));
evRoot = fileparts(scriptDir);
outputs = fullfile(evRoot, 'outputs');
outDir = fullfile(outputs, 'si_validation_clean_figures');
if ~exist(outDir, 'dir')
    mkdir(outDir);
end

make_stackB_voltage_figure(outputs, outDir);
make_stackB_interface_figure(outputs, outDir);
make_stackB_h2_figure(outputs, outDir);
make_stackA_distribution_figure(outputs, outDir);

disp(['SI validation clean figures written to: ' outDir]);
end

function make_stackB_voltage_figure(outputs, outDir)
T = readtable(fullfile(outputs, 'step2_voltage_model_validation', ...
    'stackB_voltage_predictions.csv'), 'TextType', 'string');

fig = new_clean_figure(14.5, 10.2);
ax = axes(fig);
hold(ax, 'on');

isTest = T.set == "test";
hTrain = scatter(ax, T.V_measured_V(~isTest), T.V_predicted_V(~isTest), 28, ...
    'MarkerFaceColor', [0.20 0.46 0.76], 'MarkerEdgeColor', 'none', ...
    'MarkerFaceAlpha', 0.80);
hTest = scatter(ax, T.V_measured_V(isTest), T.V_predicted_V(isTest), 34, ...
    'MarkerFaceColor', [0.84 0.33 0.18], 'MarkerEdgeColor', 'none', ...
    'MarkerFaceAlpha', 0.90);

lo = min([T.V_measured_V; T.V_predicted_V]);
hi = max([T.V_measured_V; T.V_predicted_V]);
pad = 0.04 * (hi - lo);
lo = floor(lo - pad);
hi = ceil(hi + pad);
hIdentity = plot(ax, [lo hi], [lo hi], '--', 'Color', [0.20 0.20 0.20], ...
    'LineWidth', 1.2);

xlabel(ax, 'Measured stack voltage (V)');
ylabel(ax, 'Predicted stack voltage (V)');
xlim(ax, [lo hi]);
ylim(ax, [lo hi]);
style_axes(ax);
axis(ax, 'square');
lgd = legend(ax, [hTrain hTest hIdentity], ...
    {'Training windows', 'Independent test windows', 'Identity'}, ...
    'Location', 'northwest', 'Box', 'off');
style_legend(lgd, 10);

export_clean(fig, fullfile(outDir, 'SX_validation_stackB_voltage.png'));
close(fig);
end

function make_stackB_interface_figure(outputs, outDir)
curveT = readtable(fullfile(outputs, 'step4_stack_efficiency_interface', ...
    'stackB_piecewise_efficiency_curve.csv'));
steadyT = readtable(fullfile(outputs, 'step6_steady_module_validation', ...
    'steady_window_module_validation.csv'));

fig = new_clean_figure(14.5, 8.4);
ax = axes(fig);
hold(ax, 'on');

hMeasured = scatter(ax, steadyT.load_fraction, steadyT.measured_eta_stack_LHV, 24, ...
    'MarkerFaceColor', [0.72 0.72 0.72], 'MarkerEdgeColor', 'none', ...
    'MarkerFaceAlpha', 0.75);
hPredicted = scatter(ax, steadyT.load_fraction, steadyT.predicted_eta_stack_LHV, 26, ...
    'MarkerFaceColor', [0.12 0.42 0.74], 'MarkerEdgeColor', 'none', ...
    'MarkerFaceAlpha', 0.78);

[smoothX, smoothY] = smooth_static_interface(curveT);
hSmooth = plot(ax, smoothX, smoothY, '-', 'Color', [0.82 0.33 0.17], ...
    'LineWidth', 2.1);
hBins = plot(ax, curveT.load_mean, curveT.eta_stack_LHV_mean, 'o', ...
    'Color', [0.82 0.33 0.17], 'MarkerFaceColor', [0.82 0.33 0.17], ...
    'MarkerSize', 4.4, 'LineStyle', 'none');

xlabel(ax, 'Load fraction (-)');
ylabel(ax, 'Stack LHV efficiency (-)');
xlim(ax, [0.25 1.00]);
ylim(ax, [0.48 0.64]);
style_axes(ax);
lgd = legend(ax, [hMeasured hPredicted hBins hSmooth], ...
    {'Measured steady windows', 'Predicted steady windows', ...
    'Field-derived bin means', 'Smoothed static interface'}, ...
    'Location', 'eastoutside', 'Box', 'off');
style_legend(lgd, 10);
ax.Position = [0.10 0.16 0.60 0.78];

export_clean(fig, fullfile(outDir, 'SX_validation_stackB_interfaces.png'));
close(fig);
end

function make_stackB_h2_figure(outputs, outDir)
T = readtable(fullfile(outputs, 'step8_full_statespace_single5MW_validation', ...
    'fangshan_single5MW_full_statespace_validation_profile.csv'));
dynamicT = readtable(fullfile(outputs, 'step7_dynamic_module_validation', ...
    'dynamic_day_2023-11-05_module_validation_profile.csv'));

% Exclude the first 15 min point in the figure because it is explicitly
% reported as initialisation-sensitive in the SI table.
idx = T.time_h > 0;

fig = new_clean_figure(14.5, 8.4);
ax = axes(fig);
hold(ax, 'on');
hMeasured = plot(ax, T.time_h(idx), T.H2_rate_measured_Nm3h(idx), '-', ...
    'Color', [0.10 0.45 0.20], 'LineWidth', 2.0);
hReplay = plot(ax, dynamicT.time_h(dynamicT.time_h > 0), ...
    dynamicT.predicted_H2_rate_Nm3h(dynamicT.time_h > 0), '--', ...
    'Color', [0.12 0.42 0.74], 'LineWidth', 2.0);
hState = plot(ax, T.time_h(idx), T.H2_rate_model_Nm3h(idx), '-', ...
    'Color', [0.78 0.18 0.16], 'LineWidth', 2.0);

xlabel(ax, 'Time (h)');
ylabel(ax, 'Hydrogen production rate (Nm^3 h^{-1})');
xlim(ax, [0 24]);
style_axes(ax);
lgd = legend(ax, [hMeasured hReplay hState], ...
    {'Measured', 'Interface-only replay', 'Full state-space model'}, ...
    'Location', 'southoutside', 'Orientation', 'horizontal', 'Box', 'off');
style_legend(lgd, 10);
ax.Position = [0.10 0.28 0.84 0.62];

export_clean(fig, fullfile(outDir, 'SX_validation_stackB_full_state_H2.png'));
close(fig);
end

function [xGrid, ySmooth] = smooth_static_interface(curveT)
x = curveT.load_mean(:);
y = curveT.eta_stack_LHV_mean(:);
if ismember('n', curveT.Properties.VariableNames)
    n = curveT.n(:);
else
    n = ones(size(x));
end
[x, order] = sort(x);
y = y(order);
n = n(order);
xGrid = linspace(min(x), max(x), 240);
bandwidth = 0.085;
ySmooth = zeros(size(xGrid));
for k = 1:numel(xGrid)
    w = n .* exp(-0.5 * ((xGrid(k) - x) ./ bandwidth) .^ 2);
    ySmooth(k) = sum(w .* y) / sum(w);
end
end

function make_stackA_distribution_figure(outputs, outDir)
T = readtable(fullfile(outputs, 'step10_stackA_distribution_model_comparison', ...
    'stackA_distribution_model_comparison_profile.csv'));
valid = logical(T.valid_channel) ...
    & isfinite(T.model_current_pu) ...
    & isfinite(T.inferred_current_voltage_temperature_pu_rated);
cellId = T.cell_id;

modelCurrent = T.model_current_pu;
experimentRaw = T.inferred_current_voltage_temperature_pu_rated;
[experimentTrend, bandLow, bandHigh] = adaptive_stack_envelope(cellId, experimentRaw, valid);

metrics = stack_distribution_metrics(cellId, valid, modelCurrent, experimentRaw, ...
    experimentTrend, bandLow, bandHigh);
writetable(metrics, fullfile(outDir, 'SX_validation_stackA_theory_experiment_metrics.csv'));

fig = new_clean_figure(14.5, 8.4);
ax = axes(fig);
hold(ax, 'on');

bandIdx = valid & isfinite(bandLow) & isfinite(bandHigh);
hBand = fill(ax, [cellId(bandIdx); flipud(cellId(bandIdx))], ...
    [bandLow(bandIdx); flipud(bandHigh(bandIdx))], [0.75 0.80 0.86], ...
    'EdgeColor', 'none', 'FaceAlpha', 0.35);
hTrend = plot(ax, cellId(valid), experimentTrend(valid), '-', ...
    'Color', [0.12 0.42 0.74], 'LineWidth', 2.0);
hModel = plot(ax, cellId(valid), modelCurrent(valid), '-', ...
    'Color', [0.78 0.18 0.16], 'LineWidth', 2.0);
hRated = plot(ax, [min(cellId(valid)) max(cellId(valid))], [1 1], '--', ...
    'Color', [0.35 0.35 0.35], 'LineWidth', 1.0);

xlabel(ax, 'Cell ID');
ylabel(ax, 'Cell current (p.u.)');
xlim(ax, [1 max(cellId)]);
ylim(ax, [0 1.5]);
lgd = legend(ax, [hBand hTrend hModel hRated], ...
    {'Experiment, local IQR band', ...
    'Experiment, adaptive local average', ...
    'Distributed-circuit model', ...
    'Rated input current'}, ...
    'Location', 'southoutside', 'Orientation', 'horizontal', 'Box', 'off');
style_axes(ax);
lgd.Location = 'southoutside';
lgd.Orientation = 'horizontal';
ax.Position(2) = 0.28;
ax.Position(4) = 0.58;

export_clean(fig, fullfile(outDir, 'SX_validation_stackA_current_distribution_envelope.png'));
close(fig);
end

function fig = new_clean_figure(widthCm, heightCm)
fig = figure('Visible', 'off', 'Color', 'w', 'Units', 'centimeters', ...
    'Position', [2 2 widthCm heightCm], 'PaperUnits', 'centimeters', ...
    'PaperPosition', [0 0 widthCm heightCm]);
end

function style_axes(ax)
set(ax, 'FontName', 'Times New Roman', 'FontSize', 10, 'LineWidth', 1.1, ...
    'TickDir', 'out', 'Box', 'off', 'Layer', 'top');
ax.XLabel.FontName = 'Times New Roman';
ax.YLabel.FontName = 'Times New Roman';
ax.XLabel.FontSize = 12;
ax.YLabel.FontSize = 12;
ax.XLabel.FontWeight = 'normal';
ax.YLabel.FontWeight = 'normal';
ax.Title.String = '';
ax.XColor = [0 0 0];
ax.YColor = [0 0 0];
grid(ax, 'off');
ax.Units = 'normalized';
if numel(ax.Position) == 4
    ax.Position(1) = max(ax.Position(1), 0.11);
    ax.Position(2) = max(ax.Position(2), 0.16);
end
end

function style_legend(lgd, fontSize)
lgd.FontName = 'Times New Roman';
lgd.FontSize = fontSize;
lgd.Box = 'off';
end

function export_clean(fig, pngPath)
try
    exportgraphics(fig, pngPath, 'Resolution', 600);
catch
    print(fig, pngPath, '-dpng', '-r600');
end
end

function [trend, bandLow, bandHigh] = adaptive_stack_envelope(cellId, raw, valid)
% Keep the edge effect visible with a narrow window near the stack ends,
% while suppressing channel-to-channel voltage artefacts in the core.
n = numel(raw);
trend = nan(n, 1);
bandLow = nan(n, 1);
bandHigh = nan(n, 1);
maxCell = max(cellId);
for i = 1:n
    if ~valid(i)
        continue
    end
    distanceToEdge = min(cellId(i) - 1, maxCell - cellId(i));
    halfWindow = round(6 + min(distanceToEdge, 120) / 120 * 94);
    idx = max(1, i - halfWindow):min(n, i + halfWindow);
    idx = idx(valid(idx) & isfinite(raw(idx)));
    values = sort(raw(idx));
    if isempty(values)
        continue
    end
    bandLow(i) = local_quantile(values, 0.25);
    bandHigh(i) = local_quantile(values, 0.75);
    trend(i) = mean(values, 'omitnan');
end
end

function q = local_quantile(values, p)
values = values(isfinite(values));
if isempty(values)
    q = NaN;
    return
end
if numel(values) == 1
    q = values(1);
    return
end
pos = 1 + (numel(values) - 1) * p;
lo = floor(pos);
hi = ceil(pos);
if lo == hi
    q = values(lo);
else
    q = values(lo) + (values(hi) - values(lo)) * (pos - lo);
end
end

function T = stack_distribution_metrics(cellId, valid, modelCurrent, experimentRaw, ...
    experimentTrend, bandLow, bandHigh)
valid = valid & isfinite(modelCurrent) & isfinite(experimentRaw) & isfinite(experimentTrend);
edge = valid & (cellId <= 10 | cellId > max(cellId) - 10);
core = valid & (cellId >= 51 & cellId <= max(cellId) - 50);

rows = {
    'n_valid_cells', sum(valid);
    'model_mean_current_pu', mean(modelCurrent(valid));
    'model_min_current_pu', min(modelCurrent(valid));
    'model_max_current_pu', max(modelCurrent(valid));
    'model_core_mean_current_pu', mean(modelCurrent(core));
    'model_edge_mean_current_pu', mean(modelCurrent(edge));
    'model_edge_minus_core_pu', mean(modelCurrent(edge)) - mean(modelCurrent(core));
    'experiment_raw_mean_current_pu', mean(experimentRaw(valid));
    'experiment_raw_min_current_pu', min(experimentRaw(valid));
    'experiment_raw_max_current_pu', max(experimentRaw(valid));
    'experiment_raw_core_mean_current_pu', mean(experimentRaw(core));
    'experiment_raw_edge_mean_current_pu', mean(experimentRaw(edge));
    'experiment_raw_edge_minus_core_pu', mean(experimentRaw(edge)) - mean(experimentRaw(core));
    'experiment_adaptive_trend_mean_current_pu', mean(experimentTrend(valid));
    'experiment_adaptive_trend_min_current_pu', min(experimentTrend(valid));
    'experiment_adaptive_trend_max_current_pu', max(experimentTrend(valid));
    'experiment_adaptive_trend_core_mean_current_pu', mean(experimentTrend(core));
    'experiment_adaptive_trend_edge_mean_current_pu', mean(experimentTrend(edge));
    'experiment_adaptive_trend_edge_minus_core_pu', mean(experimentTrend(edge)) - mean(experimentTrend(core));
    'experiment_local_IQR_mean_width_pu', mean(bandHigh(valid) - bandLow(valid), 'omitnan');
    'model_vs_experiment_adaptive_trend_MAE_pu', mean(abs(modelCurrent(valid) - experimentTrend(valid)));
    'model_vs_experiment_adaptive_trend_RMSE_pu', sqrt(mean((modelCurrent(valid) - experimentTrend(valid)).^2));
    };
T = cell2table(rows, 'VariableNames', {'metric', 'value'});
end
