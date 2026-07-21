function result = plot_six_unit_voltage_curves()
%PLOT_SIX_UNIT_VOLTAGE_CURVES
% Plot raw stack-voltage trajectories for the six-unit degradation dataset.

cfg = degradation_model_config();
raw = readtable(cfg.raw_timeseries_csv, 'TextType', 'string');
raw = sortrows(raw, {'unit', 'time_h'});

units = ["PV1", "PV2", "PV3", "PV4", "PV5", "WIND1"];
out_dir = fullfile(cfg.model_artifacts_dir, 'unit_raw_quality');
ensure_dir(out_dir);

fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 1500 900]);
t = tiledlayout(fig, 3, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
set(findall(fig, '-property', 'FontName'), 'FontName', 'Times New Roman');

colors = [ ...
    0.85 0.33 0.10; ...
    0.93 0.69 0.13; ...
    0.47 0.67 0.19; ...
    0.00 0.45 0.74; ...
    0.49 0.18 0.56; ...
    0.30 0.30 0.30];

summary_rows = cell(numel(units), 9);

for i = 1:numel(units)
    unit_i = units(i);
    Tu = raw(raw.unit == unit_i, :);
    x_day = double(Tu.time_h) / 24;
    y_v = double(Tu.voltage);

    y_smooth = movmean(y_v, 24, 'omitnan', 'Endpoints', 'shrink');

    ax = nexttile(t, i);
    hold(ax, 'on');
    plot(ax, x_day, y_v, '-', ...
        'Color', [0.75 0.75 0.75], ...
        'LineWidth', 0.8, ...
        'DisplayName', 'Raw voltage');
    plot(ax, x_day, y_smooth, '-', ...
        'Color', colors(i, :), ...
        'LineWidth', 2.0, ...
        'DisplayName', '24-h moving mean');
    hold(ax, 'off');

    box(ax, 'on');
    grid(ax, 'off');
    xlabel(ax, 'Elapsed day', 'FontSize', 11);
    ylabel(ax, 'Stack voltage (V)', 'FontSize', 11);
    title(ax, char(unit_i), 'FontSize', 12, 'FontWeight', 'bold');
    set(ax, 'FontName', 'Times New Roman', 'FontSize', 10);

    summary_rows(i, :) = { ...
        char(unit_i), ...
        height(Tu), ...
        round(min(x_day), 3), ...
        round(max(x_day), 3), ...
        round(min(y_v), 4), ...
        round(max(y_v), 4), ...
        round(mean(y_v, 'omitnan'), 4), ...
        round(mean(y_v(y_v > 0), 'omitnan'), 4), ...
        char(join(unique(Tu.source_unit), ',')) ...
        };
end

lgd = legend({'Raw voltage', '24-h moving mean'}, ...
    'Orientation', 'horizontal', 'Location', 'southoutside');
lgd.FontName = 'Times New Roman';
lgd.FontSize = 10;

title(t, 'Six-unit raw stack-voltage curves', ...
    'FontName', 'Times New Roman', 'FontSize', 13, 'FontWeight', 'bold');

summary_tbl = cell2table(summary_rows, 'VariableNames', { ...
    'unit', 'n_rows', 'start_day', 'end_day', ...
    'voltage_min_v', 'voltage_max_v', 'voltage_mean_v', ...
    'voltage_mean_positive_v', 'source_unit'});

png_file = fullfile(out_dir, 'six_unit_voltage_curves.png');
fig_file = fullfile(out_dir, 'six_unit_voltage_curves.fig');
summary_csv = fullfile(out_dir, 'six_unit_voltage_curves_summary.csv');

writetable(summary_tbl, summary_csv);
exportgraphics(fig, png_file, 'Resolution', 300);
savefig(fig, fig_file);
close(fig);

result = struct();
result.png_file = png_file;
result.fig_file = fig_file;
result.summary_csv = summary_csv;

fprintf('Saved six-unit voltage figure to:\n  %s\n', png_file);
fprintf('Saved six-unit voltage summary to:\n  %s\n', summary_csv);
end

function ensure_dir(path_str)
if ~exist(path_str, 'dir')
    mkdir(path_str);
end
end
