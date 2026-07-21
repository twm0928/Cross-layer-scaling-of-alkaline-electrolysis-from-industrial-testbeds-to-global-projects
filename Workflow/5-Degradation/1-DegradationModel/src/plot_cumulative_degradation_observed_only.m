function plot_cumulative_degradation_observed_only()
%PLOT_CUMULATIVE_DEGRADATION_OBSERVED_ONLY
% Plot only the observed clean cumulative degradation curve and the
% model-reconstructed curve over the observed period, without any 365-day
% extrapolation.

cfg = degradation_model_config();
curve_table = readtable(cfg.step3_curve_csv, 'TextType', 'string');

output_png = fullfile(cfg.step3_dir, 'cumulative_degradation_curves_6units_observed_only.png');

figure_handle = figure('Visible', 'off', 'Color', 'w', 'Position', [100, 100, 1500, 900]);

for i = 1:numel(cfg.units)
    unit = cfg.units{i};
    unit_table = curve_table(curve_table.unit == unit & curve_table.is_observed > 0, :);
    unit_table = sortrows(unit_table, 'day_index');

    subplot(3, 2, i);
    hold on;
    plot(unit_table.day_index, unit_table.exp_clean_cum_mV_cell, ...
        'o', 'Color', [0.65, 0.65, 0.65], 'MarkerSize', 4, 'LineWidth', 0.8);
    plot(unit_table.day_index, unit_table.fit_cum_observed_mV_cell, ...
        '-', 'Color', [0.90, 0.45, 0.05], 'LineWidth', 2.0);
    hold off;

    box on;
    set(gca, 'FontName', 'Times New Roman', 'FontSize', 11, 'LineWidth', 1);
    xlabel('Elapsed day', 'FontName', 'Times New Roman', 'FontSize', 12);
    ylabel('Cumulative degradation (mV cell^{-1})', 'FontName', 'Times New Roman', 'FontSize', 12);
    title(unit, 'FontName', 'Times New Roman', 'FontSize', 13, 'FontWeight', 'bold');
end

exportgraphics(figure_handle, output_png, 'Resolution', 300);
close(figure_handle);

fprintf('Observed-only cumulative degradation figure saved to:\n%s\n', output_png);
end
