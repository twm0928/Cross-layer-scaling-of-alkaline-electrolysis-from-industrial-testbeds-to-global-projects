function assets = generate_m1_m7_incremental_report_assets()
%GENERATE_M1_M7_INCREMENTAL_REPORT_ASSETS
% Build compact tables and figures for the current M1-M7 plant-layer
% degradation increment (hydrogen-loss analysis).

cfg = degradation_results_config();
summary_dir = fullfile(cfg.outputs_dir, 'plant_m1_m7_degradation_benchmark', 'summaries');
report_dir = fullfile(cfg.results_root, 'report');
figure_dir = fullfile(report_dir, 'figures');
table_dir = fullfile(report_dir, 'tables');

ensure_dir(figure_dir);
ensure_dir(table_dir);

full_csv = fullfile(summary_dir, 'm1_m7_strategy_hydrogen_loss_summary.csv');
ratio_csv = fullfile(summary_dir, 'm1_m7_case_topology_bestworst_milp_loss_summary.csv');
abs_csv = fullfile(summary_dir, 'm1_m7_case_topology_bestworst_milp_absloss_summary.csv');

Tfull = readtable(full_csv, 'TextType', 'string');
build_bestworst_summary_tables(Tfull, ratio_csv, abs_csv);
Tratio = readtable(ratio_csv, 'TextType', 'string');
Tabs = readtable(abs_csv, 'TextType', 'string');

compact_ratio = table();
compact_ratio.case_name = Tratio.case_name;
compact_ratio.topology_label = Tratio.topology_label;
compact_ratio.best_theta = Tratio.best_theta;
compact_ratio.best_loss_pct = 100 * Tratio.best_loss_ratio;
compact_ratio.worst_theta = Tratio.worst_theta;
compact_ratio.worst_loss_pct = 100 * Tratio.worst_loss_ratio;
compact_ratio.milp_loss_pct = 100 * Tratio.milp_loss_ratio;
compact_ratio.milp_minus_best_pct_point = 100 * Tratio.milp_minus_best_loss_ratio;
compact_ratio.worst_minus_best_pct_point = 100 * Tratio.worst_minus_best_loss_ratio;

compact_abs = table();
compact_abs.case_name = Tabs.case_name;
compact_abs.topology_label = Tabs.topology_label;
compact_abs.best_theta_abs = Tabs.best_theta_abs;
compact_abs.best_loss_t = Tabs.best_loss_t;
compact_abs.worst_theta_abs = Tabs.worst_theta_abs;
compact_abs.worst_loss_t = Tabs.worst_loss_t;
compact_abs.milp_loss_t = Tabs.milp_loss_t;
compact_abs.milp_minus_best_loss_t = Tabs.milp_minus_best_loss_t;
compact_abs.worst_minus_best_loss_t = Tabs.worst_minus_best_loss_t;

ratio_table_file = fullfile(table_dir, 'plant_m1_m7_increment_ratio_table.csv');
abs_table_file = fullfile(table_dir, 'plant_m1_m7_increment_absolute_table.csv');
writetable(compact_ratio, ratio_table_file);
writetable(compact_abs, abs_table_file);

figA = fullfile(figure_dir, 'FigA_theta_loss_ratio_profiles_PV_WT.png');
figB = fullfile(figure_dir, 'FigB_best_milp_worst_loss_summary.png');

plot_theta_profiles(Tfull, figA);
plot_best_milp_worst_summary(Tratio, Tabs, figB);

assets = struct();
assets.full_csv = full_csv;
assets.ratio_csv = ratio_csv;
assets.abs_csv = abs_csv;
assets.ratio_table_file = ratio_table_file;
assets.abs_table_file = abs_table_file;
assets.figA = figA;
assets.figB = figB;

disp(assets);
end

function build_bestworst_summary_tables(Tfull, ratio_csv, abs_csv)
case_names = unique(Tfull.case_name, 'stable');
topology_ids = unique(double(Tfull.topology_id), 'stable');

ratio_rows = {};
abs_rows = {};

for ci = 1:numel(case_names)
    case_name = case_names(ci);
    for ti = 1:numel(topology_ids)
        topology_id = topology_ids(ti);
        rows = Tfull(Tfull.case_name == case_name & double(Tfull.topology_id) == topology_id, :);
        if isempty(rows)
            continue;
        end

        theta_rows = rows(rows.strategy_type == "theta", :);
        milp_row = rows(rows.strategy_type == "milp", :);
        if isempty(theta_rows) || isempty(milp_row)
            continue;
        end

        [~, idx_best_ratio] = min(theta_rows.hydrogen_loss_ratio);
        [~, idx_worst_ratio] = max(theta_rows.hydrogen_loss_ratio);
        best_ratio = theta_rows(idx_best_ratio, :);
        worst_ratio = theta_rows(idx_worst_ratio, :);

        [~, idx_best_abs] = min(theta_rows.total_hydrogen_loss_t);
        [~, idx_worst_abs] = max(theta_rows.total_hydrogen_loss_t);
        best_abs = theta_rows(idx_best_abs, :);
        worst_abs = theta_rows(idx_worst_abs, :);

        topo_label = rows.topology_label(1);

        ratio_rows(end + 1, :) = { ...
            case_name, topology_id, topo_label, ...
            best_ratio.theta, best_ratio.total_hydrogen_loss_t, best_ratio.hydrogen_loss_ratio, ...
            worst_ratio.theta, worst_ratio.total_hydrogen_loss_t, worst_ratio.hydrogen_loss_ratio, ...
            milp_row.total_hydrogen_loss_t, milp_row.hydrogen_loss_ratio, ...
            milp_row.total_hydrogen_loss_t - best_ratio.total_hydrogen_loss_t, ...
            milp_row.hydrogen_loss_ratio - best_ratio.hydrogen_loss_ratio, ...
            worst_ratio.total_hydrogen_loss_t - best_ratio.total_hydrogen_loss_t, ...
            worst_ratio.hydrogen_loss_ratio - best_ratio.hydrogen_loss_ratio};

        abs_rows(end + 1, :) = { ...
            case_name, topology_id, topo_label, ...
            best_abs.theta, best_abs.total_hydrogen_loss_t, best_abs.hydrogen_loss_ratio, ...
            worst_abs.theta, worst_abs.total_hydrogen_loss_t, worst_abs.hydrogen_loss_ratio, ...
            milp_row.total_hydrogen_loss_t, milp_row.hydrogen_loss_ratio, ...
            milp_row.total_hydrogen_loss_t - best_abs.total_hydrogen_loss_t, ...
            milp_row.hydrogen_loss_ratio - best_abs.hydrogen_loss_ratio, ...
            worst_abs.total_hydrogen_loss_t - best_abs.total_hydrogen_loss_t, ...
            worst_abs.hydrogen_loss_ratio - best_abs.hydrogen_loss_ratio};
    end
end

ratio_table = cell2table(ratio_rows, 'VariableNames', { ...
    'case_name', 'topology_id', 'topology_label', ...
    'best_theta', 'best_loss_t', 'best_loss_ratio', ...
    'worst_theta', 'worst_loss_t', 'worst_loss_ratio', ...
    'milp_loss_t', 'milp_loss_ratio', ...
    'milp_minus_best_loss_t', 'milp_minus_best_loss_ratio', ...
    'worst_minus_best_loss_t', 'worst_minus_best_loss_ratio'});

abs_table = cell2table(abs_rows, 'VariableNames', { ...
    'case_name', 'topology_id', 'topology_label', ...
    'best_theta_abs', 'best_loss_t', 'best_loss_ratio', ...
    'worst_theta_abs', 'worst_loss_t', 'worst_loss_ratio', ...
    'milp_loss_t', 'milp_loss_ratio', ...
    'milp_minus_best_loss_t', 'milp_minus_best_loss_ratio', ...
    'worst_minus_best_loss_t', 'worst_minus_best_loss_ratio'});

writetable(ratio_table, ratio_csv);
writetable(abs_table, abs_csv);
end

function plot_theta_profiles(Tfull, out_file)
topo_order = "M" + string(1:7);
theta_vals = 0:0.1:1;
cases = ["PV", "WT"];
colors = lines(numel(topo_order));

f = figure('Color', 'w', 'Position', [100, 100, 1200, 460]);
tiledlayout(1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

for ci = 1:numel(cases)
    nexttile;
    hold on;
    case_name = cases(ci);
    for ti = 1:numel(topo_order)
        topo = topo_order(ti);
        rows_theta = Tfull(Tfull.case_name == case_name & Tfull.topology_label == topo & Tfull.strategy_type == "theta", :);
        rows_theta = sortrows(rows_theta, 'theta');
        plot(double(rows_theta.theta), 100 * double(rows_theta.hydrogen_loss_ratio), '-o', ...
            'Color', colors(ti, :), 'LineWidth', 1.3, 'MarkerSize', 4, ...
            'DisplayName', char(topo));

        rows_milp = Tfull(Tfull.case_name == case_name & Tfull.topology_label == topo & Tfull.strategy_type == "milp", :);
        scatter(1.03, 100 * double(rows_milp.hydrogen_loss_ratio), 32, ...
            'MarkerEdgeColor', colors(ti, :), 'MarkerFaceColor', colors(ti, :), ...
            'Marker', 'diamond', 'HandleVisibility', 'off');
    end

    xline(1.03, ':', 'Color', [0.4 0.4 0.4], 'LineWidth', 0.8, 'HandleVisibility', 'off');
    text(1.03, ylim_value(100 * double(Tfull.hydrogen_loss_ratio)), 'MILP', ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
        'FontName', 'Times New Roman', 'FontSize', 10);

    hold off;
    box on;
    grid on;
    set(gca, 'FontName', 'Times New Roman', 'FontSize', 11, 'LineWidth', 0.8);
    xlabel('\theta', 'FontName', 'Times New Roman', 'FontSize', 12);
    ylabel('Hydrogen loss ratio (%)', 'FontName', 'Times New Roman', 'FontSize', 12);
    title(char(case_name), 'FontName', 'Times New Roman', 'FontSize', 13, 'FontWeight', 'bold');
    xlim([0, 1.08]);
    xticks([theta_vals, 1.03]);
    xticklabels([compose('%.1f', theta_vals), "MILP"]);
end

lgd = legend(topo_order, 'Location', 'southoutside', 'Orientation', 'horizontal', 'NumColumns', 4);
set(lgd, 'FontName', 'Times New Roman', 'FontSize', 10, 'Box', 'off');
exportgraphics(f, out_file, 'Resolution', 300);
close(f);
end

function plot_best_milp_worst_summary(Tratio, Tabs, out_file)
topo_order = "M" + string(1:7);
cases = ["PV", "WT"];
series_labels = {'Best \theta', 'MILP', 'Worst \theta'};
series_colors = [0.20 0.52 0.82; 0.15 0.15 0.15; 0.86 0.40 0.20];

f = figure('Color', 'w', 'Position', [100, 100, 1250, 840]);
tiledlayout(2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

for ci = 1:numel(cases)
    case_name = cases(ci);

    nexttile;
    Y_ratio = nan(numel(topo_order), 3);
    for ti = 1:numel(topo_order)
        topo = topo_order(ti);
        r = Tratio(Tratio.case_name == case_name & Tratio.topology_label == topo, :);
        Y_ratio(ti, :) = [100 * r.best_loss_ratio, 100 * r.milp_loss_ratio, 100 * r.worst_loss_ratio];
    end
    b1 = bar(categorical(cellstr(topo_order)), Y_ratio, 'grouped');
    style_bars(b1, series_colors);
    box on; grid on;
    set(gca, 'FontName', 'Times New Roman', 'FontSize', 11, 'LineWidth', 0.8);
    ylabel('Hydrogen loss ratio (%)', 'FontName', 'Times New Roman', 'FontSize', 12);
    title(sprintf('%s: ratio-based summary', case_name), 'FontName', 'Times New Roman', 'FontSize', 12, 'FontWeight', 'bold');

    nexttile;
    Y_abs = nan(numel(topo_order), 3);
    for ti = 1:numel(topo_order)
        topo = topo_order(ti);
        r = Tabs(Tabs.case_name == case_name & Tabs.topology_label == topo, :);
        Y_abs(ti, :) = [r.best_loss_t, r.milp_loss_t, r.worst_loss_t];
    end
    b2 = bar(categorical(cellstr(topo_order)), Y_abs, 'grouped');
    style_bars(b2, series_colors);
    box on; grid on;
    set(gca, 'FontName', 'Times New Roman', 'FontSize', 11, 'LineWidth', 0.8);
    ylabel('Annual hydrogen loss (t)', 'FontName', 'Times New Roman', 'FontSize', 12);
    title(sprintf('%s: absolute-loss summary', case_name), 'FontName', 'Times New Roman', 'FontSize', 12, 'FontWeight', 'bold');
end

lgd = legend(series_labels, 'Location', 'southoutside', 'Orientation', 'horizontal', 'NumColumns', 3);
set(lgd, 'FontName', 'Times New Roman', 'FontSize', 10, 'Box', 'off');
exportgraphics(f, out_file, 'Resolution', 300);
close(f);
end

function style_bars(bars, colors)
for i = 1:numel(bars)
    bars(i).FaceColor = colors(i, :);
    bars(i).EdgeColor = 'none';
end
end

function y = ylim_value(x)
x = x(isfinite(x));
if isempty(x)
    y = 1;
else
    y = max(x) + 0.05 * max(x);
end
end

function ensure_dir(path_str)
if ~exist(path_str, 'dir')
    mkdir(path_str);
end
end
