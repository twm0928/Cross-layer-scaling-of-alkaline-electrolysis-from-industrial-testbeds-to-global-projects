function plot_equivalent_theta_preview(theta_daily, gain, cfg)
%PLOT_EQUIVALENT_THETA_PREVIEW Quick diagnostic plots for the closed loop.

if nargin < 3 || isempty(cfg)
    cfg = plant_case_config();
end

if isempty(theta_daily)
    return;
end

out_dir = cfg.figure_output_dir;
if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end

case_vec = string(theta_daily.case_name);
topo_vec = string(theta_daily.topology_label);
cases_to_plot = ["PV", "WT"];
colors = lines(numel(cfg.topology_ids));

fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 980 560]);
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
    ylabel('Equivalent theta');
    title(sprintf('%s: daily mean equivalent theta of MILP dispatch', cases_to_plot(ci)), ...
        'FontWeight', 'normal');
    if ci == numel(cases_to_plot)
        xlabel('Day');
    end
    if ci == 1
        legend('Location', 'eastoutside', 'Box', 'off');
    end
end

saveas(fig, fullfile(out_dir, 'Fig4_R1_MILP_equivalent_theta_daily_preview.fig'));
print(fig, fullfile(out_dir, 'Fig4_R1_MILP_equivalent_theta_daily_preview.png'), '-dpng', '-r300');
print(fig, fullfile(out_dir, 'Fig4_R1_MILP_equivalent_theta_daily_preview.pdf'), '-dpdf', '-bestfit');
close(fig);

if ~isempty(gain)
    fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 980 360]);
    hold on; box on;
    g_case = string(gain.case_name);
    g_topo = string(gain.topology_label);
    valid = g_case ~= "Constant";
    labels = strcat(g_case(valid), "-", g_topo(valid));
    bar(categorical(labels), gain.hydrogen_gain_percent(valid));
    ylabel('Hydrogen gain (%)');
    title('MILP static-dispatch schedule evaluated by dynamic surrogate', ...
        'FontWeight', 'normal');
    xtickangle(45);
    saveas(fig, fullfile(out_dir, 'Fig4_R1_MILP_dynamic_gain_preview.fig'));
    print(fig, fullfile(out_dir, 'Fig4_R1_MILP_dynamic_gain_preview.png'), '-dpng', '-r300');
    print(fig, fullfile(out_dir, 'Fig4_R1_MILP_dynamic_gain_preview.pdf'), '-dpdf', '-bestfit');
    close(fig);
end
end
