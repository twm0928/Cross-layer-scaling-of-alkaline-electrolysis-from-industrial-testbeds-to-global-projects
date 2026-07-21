% Export Fig. 3a source data with the R1 M7 module candidate included.
%
% Current R1 Fig. 3a convention:
% - use the formal combined970 scenario scope (730 natural + 240 legacy)
% - build dynamic efficiency intervals on the same mean-power grid as the
%   constant-power static reference points, i.e. 0.1:0.1:1.0 p.u.
% - do not apply any extra ramping-screen filter here; the interval should
%   reflect the full retained dynamic scenario space at each mean-power bin
% - the accepted retained scope already excludes the two formal
%   topology-scenario anomalies through build_dynamic_training_dataset, so
%   no figure-only outlier repair is applied here
%
% M1-M7 are read from the unified module result directory. The output is
% written to Figure/Figure 3a.

module_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
project_root = fileparts(fileparts(module_root));
figure_root = fullfile(project_root, 'Figure', 'Figure 3a');
data_dir = fullfile(figure_root, 'data');
output_dir = fullfile(figure_root, 'output');
if ~exist(data_dir, 'dir'); mkdir(data_dir); end
if ~exist(output_dir, 'dir'); mkdir(output_dir); end

addpath(fileparts(mfilename('fullpath')));
scenario_ids = get_r1_dynamic_scenario_ids('combined970');
dataset = build_dynamic_training_dataset(scenario_ids);
long_table = dataset.long_table;

num_topologies = 7;
topology_labels = {'M1', 'M2', 'M3', 'M4', 'M5', 'M6', 'M7'};
topology_groups = {'S1', 'S1', 'S1', 'S2', 'S2', 'S3', 'S3-seg'};

% Binned Fig. 3a dynamic curves: retain the original 0.05:0.1:0.95 mean-
% power grid so the full dynamic envelope is not distorted by mixing the
% far-left 0.05 and 0.15 p.u. profiles into one coarse 0.1-centred bin.
% The static reference line is overlaid separately at 0.1:0.1:1.0 p.u.
mean_centers = (0.05:0.1:0.95)';
mean_edges = [0.0; (mean_centers(1:end-1) + mean_centers(2:end)) / 2; 1.0];
bin_rows = cell(num_topologies * numel(mean_centers), 18);
r = 0;
for t = 1:num_topologies
    topo_rows = long_table(long_table.topology_id == t & long_table.has_valid_dynamic_result == 1, :);
    for b = 1:numel(mean_centers)
        lo_edge = mean_edges(b);
        hi_edge = mean_edges(b + 1);
        if b < numel(mean_centers)
            idx = topo_rows.mean_power_pu >= lo_edge & topo_rows.mean_power_pu < hi_edge;
        else
            idx = topo_rows.mean_power_pu >= lo_edge & topo_rows.mean_power_pu <= hi_edge;
        end
        bin_rows_raw = topo_rows(idx, :);
        vals = bin_rows_raw.module_efficiency_LHV;
        vals = vals(isfinite(vals) & vals > 0);
        [vals_clean, n_quasi_removed, n_outlier_removed] = clean_dynamic_envelope(vals);
        r = r + 1;
        bin_rows(r, :) = { ...
            topology_labels{t}, t, topology_groups{t}, b, ...
            mean_centers(b), sum(idx), ...
            safe_mean(vals), safe_min(vals), safe_max(vals), safe_std(vals), ...
            safe_prctile(vals, 10), safe_prctile(vals, 50), safe_prctile(vals, 90), ...
            safe_min(vals_clean), safe_max(vals_clean), numel(vals_clean), ...
            n_quasi_removed, n_outlier_removed ...
            };
    end
end
bin_table = cell2table(bin_rows, 'VariableNames', { ...
    'topology_label', 'topology_id', 'topology_group', 'bin_id', ...
    'mean_power_center_pu', 'sample_count', 'efficiency_mean', ...
    'efficiency_min', 'efficiency_max', 'efficiency_std', ...
    'efficiency_p10', 'efficiency_p50', 'efficiency_p90', ...
    'efficiency_min_clean', 'efficiency_max_clean', 'sample_count_clean', ...
    'removed_quasi_static', 'removed_low_outlier' ...
    });
bin_table.topology_id = ensure_numeric(bin_table.topology_id);
bin_table.bin_id = ensure_numeric(bin_table.bin_id);
bin_table.mean_power_center_pu = ensure_numeric(bin_table.mean_power_center_pu);
bin_table.sample_count = ensure_numeric(bin_table.sample_count);
bin_table.efficiency_mean = ensure_numeric(bin_table.efficiency_mean);
bin_table.efficiency_min = ensure_numeric(bin_table.efficiency_min);
bin_table.efficiency_max = ensure_numeric(bin_table.efficiency_max);
bin_table.efficiency_std = ensure_numeric(bin_table.efficiency_std);
bin_table.efficiency_p10 = ensure_numeric(bin_table.efficiency_p10);
bin_table.efficiency_p50 = ensure_numeric(bin_table.efficiency_p50);
bin_table.efficiency_p90 = ensure_numeric(bin_table.efficiency_p90);
bin_table.efficiency_min_clean = ensure_numeric(bin_table.efficiency_min_clean);
bin_table.efficiency_max_clean = ensure_numeric(bin_table.efficiency_max_clean);
bin_table.sample_count_clean = ensure_numeric(bin_table.sample_count_clean);
bin_table.removed_quasi_static = ensure_numeric(bin_table.removed_quasi_static);
bin_table.removed_low_outlier = ensure_numeric(bin_table.removed_low_outlier);

% Summary table for quick checking.
summary_rows = cell(num_topologies, 8);
for t = 1:num_topologies
    topo_rows = long_table(long_table.topology_id == t & long_table.has_valid_dynamic_result == 1, :);
    vals = topo_rows.module_efficiency_LHV;
    summary_rows(t, :) = { ...
        topology_labels{t}, t, topology_groups{t}, numel(vals), ...
        safe_mean(vals), safe_min(vals), safe_max(vals), safe_std(vals) ...
        };
end
summary_table = cell2table(summary_rows, 'VariableNames', { ...
    'topology_label', 'topology_id', 'topology_group', 'valid_scenarios', ...
    'efficiency_mean', 'efficiency_min', 'efficiency_max', 'efficiency_std' ...
    });
summary_table.topology_id = ensure_numeric(summary_table.topology_id);
summary_table.valid_scenarios = ensure_numeric(summary_table.valid_scenarios);
summary_table.efficiency_mean = ensure_numeric(summary_table.efficiency_mean);
summary_table.efficiency_min = ensure_numeric(summary_table.efficiency_min);
summary_table.efficiency_max = ensure_numeric(summary_table.efficiency_max);
summary_table.efficiency_std = ensure_numeric(summary_table.efficiency_std);

xlsx_file = fullfile(data_dir, 'Fig3a_R1_dynamic_efficiency_M1_M7.xlsx');
csv_long = fullfile(data_dir, 'Fig3a_R1_dynamic_efficiency_long.csv');
csv_bins = fullfile(data_dir, 'Fig3a_R1_dynamic_efficiency_binned.csv');
csv_summary = fullfile(data_dir, 'Fig3a_R1_dynamic_efficiency_summary.csv');
writetable(long_table, csv_long);
writetable(bin_table, csv_bins);
writetable(summary_table, csv_summary);
writetable(long_table, xlsx_file, 'Sheet', 'long');
writetable(bin_table, xlsx_file, 'Sheet', 'binned');
writetable(summary_table, xlsx_file, 'Sheet', 'summary');

plot_fig3a(bin_table, output_dir);

fprintf('Fig. 3a export complete:\n');
fprintf('  %s\n', xlsx_file);
fprintf('  %s\n', fullfile(output_dir, 'Fig3a_R1_dynamic_efficiency_M1_M7.png'));

function y = safe_mean(x)
if isempty(x); y = NaN; else; y = mean(x); end
end

function y = safe_min(x)
if isempty(x); y = NaN; else; y = min(x); end
end

function y = safe_max(x)
if isempty(x); y = NaN; else; y = max(x); end
end

function y = safe_std(x)
if numel(x) < 2; y = 0; else; y = std(x); end
end

function y = safe_prctile(x, p)
if isempty(x)
    y = NaN;
else
    y = prctile(x, p);
end
end

function [vals_clean, n_quasi_removed, n_outlier_removed] = clean_dynamic_envelope(vals_raw)
vals_clean = vals_raw;
n_quasi_removed = 0;
n_outlier_removed = 0;
end

function y = ensure_numeric(x)
if iscell(x)
    y = cell2mat(x);
else
    y = x;
end
end

function plot_fig3a(bin_table, output_dir)
hex2rgb = @(h) [hex2dec(h(2:3)) hex2dec(h(4:5)) hex2dec(h(6:7))] / 255;
group_colors = [
    hex2rgb('#F3A332')
    hex2rgb('#018A67')
    hex2rgb('#1868B2')
    ];
line_styles = {'-', '--', ':', '-', '--', '-', '--'};

fig = figure('Color', 'w', 'Units', 'centimeters', 'Position', [2 2 12 7]);
hold on;
for t = 1:7
    rows = bin_table(bin_table.topology_id == t, :);
    x = rows.mean_power_center_pu;
    y = rows.efficiency_p50;
    lo = rows.efficiency_min_clean;
    hi = rows.efficiency_max_clean;
    valid = isfinite(x) & isfinite(y);
    if t <= 3
        c = group_colors(1, :);
    elseif t <= 5
        c = group_colors(2, :);
    else
        c = group_colors(3, :);
    end
    fill([x(valid); flipud(x(valid))], [lo(valid); flipud(hi(valid))], ...
        c, 'FaceAlpha', 0.12, 'EdgeColor', 'none', 'HandleVisibility', 'off');
    plot(x(valid), y(valid), line_styles{t}, 'Color', c, ...
        'LineWidth', 1.8, 'DisplayName', sprintf('M%d', t));
end
xlabel('Mean power (per unit)');
ylabel('Module efficiency');
box on;
grid off;
legend('Location', 'best', 'Box', 'off');
set(gca, 'FontName', 'Arial', 'FontSize', 9, 'LineWidth', 0.8);

png_file = fullfile(output_dir, 'Fig3a_R1_dynamic_efficiency_M1_M7.png');
fig_file = fullfile(output_dir, 'Fig3a_R1_dynamic_efficiency_M1_M7.fig');
pdf_file = fullfile(output_dir, 'Fig3a_R1_dynamic_efficiency_M1_M7.pdf');
exportgraphics(fig, png_file, 'Resolution', 600);
exportgraphics(fig, pdf_file, 'ContentType', 'vector');
savefig(fig, fig_file);
close(fig);
end
