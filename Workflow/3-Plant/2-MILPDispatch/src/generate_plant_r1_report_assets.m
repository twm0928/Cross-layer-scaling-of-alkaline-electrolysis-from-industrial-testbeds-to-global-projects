function generate_plant_r1_report_assets()
%GENERATE_PLANT_R1_REPORT_ASSETS Export report-ready tables and figures.

cfg = plant_case_config();
flow_root = fileparts(fileparts(mfilename('fullpath')));
plant_root = fileparts(flow_root);
report_dir = fullfile(plant_root, 'report');
figure_dir = fullfile(report_dir, 'figures');
table_dir = fullfile(report_dir, 'tables');

if ~exist(report_dir, 'dir'); mkdir(report_dir); end
if ~exist(figure_dir, 'dir'); mkdir(figure_dir); end
if ~exist(table_dir, 'dir'); mkdir(table_dir); end

static_gain = readtable(fullfile(flow_root, 'outputs', 'plant_milp_static_benchmark_gain.csv'));
dynamic_gain = readtable(fullfile(flow_root, 'outputs', 'plant_milp_dynamic_closed_loop_gain.csv'));
theta_summary = readtable(fullfile(flow_root, 'outputs', 'plant_milp_equivalent_theta_summary.csv'));
theta_daily = readtable(fullfile(flow_root, 'outputs', 'plant_milp_equivalent_theta_daily.csv'));
case_profile = readtable(fullfile(flow_root, 'outputs', 'process_milp_dynamic', 'plant_milp_case_profile_summary.csv'));

s = static_gain(:, {'case_name','topology_label','topology_id','best_theta','hydrogen_gain_percent','efficiency_gain_percent'});
s = renamevars(s, {'best_theta','hydrogen_gain_percent','efficiency_gain_percent'}, ...
    {'theta_best_static','hydrogen_gain_static_pct','efficiency_gain_static_pct'});

d = dynamic_gain(:, {'case_name','topology_label','topology_id','best_theta_dynamic','hydrogen_gain_percent','efficiency_gain_percent', ...
    'equivalent_theta_mean','equivalent_theta_std','equivalent_theta_p10','equivalent_theta_median', ...
    'equivalent_theta_p90','equivalent_theta_fit_rmse_MW_mean'});
d = renamevars(d, {'hydrogen_gain_percent','efficiency_gain_percent','equivalent_theta_fit_rmse_MW_mean'}, ...
    {'hydrogen_gain_dynamic_pct','efficiency_gain_dynamic_pct','theta_fit_rmse_MW_mean'});

gain_compare = outerjoin(s, d, ...
    'Keys', {'case_name','topology_label','topology_id'}, ...
    'MergeKeys', true, ...
    'Type', 'left');

writetable(case_profile, fullfile(table_dir, 'plant_case_boundaries.csv'));
writetable(gain_compare, fullfile(table_dir, 'plant_gain_comparison.csv'));
writetable(theta_summary, fullfile(table_dir, 'plant_equivalent_theta_metrics.csv'));

export_gain_comparison_figure(static_gain, dynamic_gain, cfg, fullfile(figure_dir, 'plant_static_vs_dynamic_gain.png'));
export_equivalent_theta_summary_figure(dynamic_gain, theta_summary, cfg, fullfile(figure_dir, 'plant_equivalent_theta_summary.png'));
export_equivalent_theta_daily_figure(theta_daily, cfg, fullfile(figure_dir, 'plant_equivalent_theta_daily.png'));
end

function export_gain_comparison_figure(static_gain, dynamic_gain, cfg, out_png)
cases_to_plot = {'PV', 'WT'};
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 1180 520]);
tiledlayout(1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

for ci = 1:numel(cases_to_plot)
    nexttile; hold on; box on;
    case_name = cases_to_plot{ci};
    s = static_gain(strcmp(string(static_gain.case_name), case_name), :);
    d = dynamic_gain(strcmp(string(dynamic_gain.case_name), case_name), :);
    s = sortrows(s, 'topology_id');
    d = sortrows(d, 'topology_id');
    y = [s.hydrogen_gain_percent, d.hydrogen_gain_percent];
    b = bar(y, 'grouped', 'BarWidth', 0.82);
    b(1).FaceColor = [0.65 0.79 0.94];
    b(2).FaceColor = [0.13 0.44 0.71];
    yline(0, 'k-', 'LineWidth', 0.9);
    ax = gca;
    ax.XTick = 1:numel(cfg.topology_labels);
    ax.XTickLabel = cfg.topology_labels;
    ax.FontName = 'Times New Roman';
    ax.FontSize = 11;
    ax.LineWidth = 0.9;
    ylabel('Hydrogen gain (%)', 'FontName', 'Times New Roman', 'FontSize', 13);
    xlabel('Topology', 'FontName', 'Times New Roman', 'FontSize', 13);
    title(case_name, 'FontName', 'Times New Roman', 'FontSize', 14, 'FontWeight', 'bold');
    ylim([min(min(y)) - 0.1, max(max(y)) + 0.1]);
    if ci == 1
        legend({'Static benchmark', 'Dynamic re-evaluation'}, ...
            'Location', 'southoutside', 'Orientation', 'horizontal', 'Box', 'off', ...
            'FontName', 'Times New Roman', 'FontSize', 11);
    end
end

exportgraphics(fig, out_png, 'Resolution', 300);
close(fig);
end

function export_equivalent_theta_summary_figure(dynamic_gain, theta_summary, cfg, out_png)
cases_to_plot = {'PV', 'WT'};
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 1180 520]);
tiledlayout(1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

for ci = 1:numel(cases_to_plot)
    nexttile; hold on; box on;
    case_name = cases_to_plot{ci};
    d = dynamic_gain(strcmp(string(dynamic_gain.case_name), case_name), :);
    t = theta_summary(strcmp(string(theta_summary.case_name), case_name), :);
    d = sortrows(d, 'topology_id');
    t = sortrows(t, 'topology_id');

    mean_theta = t.equivalent_theta_mean;
    lower = mean_theta - t.equivalent_theta_p10;
    upper = t.equivalent_theta_p90 - mean_theta;

    bh = bar(mean_theta, 0.72, 'FaceColor', [0.67 0.84 0.90], 'EdgeColor', [0.17 0.39 0.56], 'LineWidth', 0.9);
    errorbar(1:numel(mean_theta), mean_theta, lower, upper, 'k.', 'LineWidth', 1.0, 'CapSize', 10);
    lh = plot(1:numel(mean_theta), d.best_theta_dynamic, 'o-', ...
        'Color', [0.80 0.24 0.05], 'MarkerFaceColor', [0.80 0.24 0.05], ...
        'LineWidth', 1.2, 'MarkerSize', 5);

    ax = gca;
    ax.XTick = 1:numel(cfg.topology_labels);
    ax.XTickLabel = cfg.topology_labels;
    ax.FontName = 'Times New Roman';
    ax.FontSize = 11;
    ax.LineWidth = 0.9;
    ylim([0 1.05]);
    ylabel('Equivalent \theta', 'FontName', 'Times New Roman', 'FontSize', 13);
    xlabel('Topology', 'FontName', 'Times New Roman', 'FontSize', 13);
    title(case_name, 'FontName', 'Times New Roman', 'FontSize', 14, 'FontWeight', 'bold');
    if ci == 1
        legend([bh, lh], {'MILP daily mean', 'Best \theta in sweep'}, 'Location', 'northwest', ...
            'Box', 'off', 'FontName', 'Times New Roman', 'FontSize', 11);
    end
end

exportgraphics(fig, out_png, 'Resolution', 300);
close(fig);
end

function export_equivalent_theta_daily_figure(theta_daily, cfg, out_png)
cases_to_plot = ["PV", "WT"];
case_vec = string(theta_daily.case_name);
topo_vec = string(theta_daily.topology_label);
colors = lines(numel(cfg.topology_ids));

fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 1180 700]);
tiledlayout(numel(cases_to_plot), 1, 'TileSpacing', 'compact', 'Padding', 'compact');

for ci = 1:numel(cases_to_plot)
    nexttile; hold on; box on;
    for ti = 1:numel(cfg.topology_labels)
        idx = case_vec == cases_to_plot(ci) & topo_vec == string(cfg.topology_labels{ti});
        if any(idx)
            plot(theta_daily.day_id(idx), theta_daily.equivalent_theta_daily_mean(idx), ...
                'LineWidth', 1.2, 'Color', colors(ti, :), ...
                'DisplayName', cfg.topology_labels{ti});
        end
    end
    ylim([0 1]);
    xlim([1 365]);
    ax = gca;
    ax.FontName = 'Times New Roman';
    ax.FontSize = 11;
    ax.LineWidth = 0.9;
    ylabel('Equivalent \theta', 'FontName', 'Times New Roman', 'FontSize', 13);
    title(char(cases_to_plot(ci)), 'FontName', 'Times New Roman', 'FontSize', 14, 'FontWeight', 'bold');
    if ci == numel(cases_to_plot)
        xlabel('Day', 'FontName', 'Times New Roman', 'FontSize', 13);
    end
    if ci == 1
        legend('Location', 'eastoutside', 'Box', 'off', ...
            'FontName', 'Times New Roman', 'FontSize', 11);
    end
end

exportgraphics(fig, out_png, 'Resolution', 300);
close(fig);
end
