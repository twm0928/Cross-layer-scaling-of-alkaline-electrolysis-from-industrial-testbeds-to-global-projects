function out = plot_fig3b_template(diagnostics_mat_file, output_prefix)
%PLOT_FIG3B_TEMPLATE Plot manuscript-style module daily-operation template.
%   out = PLOT_FIG3B_TEMPLATE() uses the current M1 representative-day
%   full-rerun result under outputs/fig3b_scenario_505_full_rerun and
%   exports a manuscript-style PNG/FIG pair for quick figure design.

if nargin < 1 || isempty(diagnostics_mat_file)
    diagnostics_mat_file = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
        'outputs', 'fig3b_scenario_505_full_rerun', 'M1_scenario_505_diagnostics.mat');
end
if nargin < 2 || isempty(output_prefix)
    [out_dir, out_name] = fileparts(diagnostics_mat_file);
    output_prefix = fullfile(out_dir, [out_name '_fig3b_template']);
end

S = load(diagnostics_mat_file);
if ~isfield(S, 'diag_out')
    error('Expected diag_out in %s.', diagnostics_mat_file);
end
d = S.diag_out;

time15_h = (0:d.t_command-1)' * d.delta_t;
time1_h = (0:d.t_HTO-1)' * d.delta_t_HTO;
nStacks = d.N_st;
nSep = d.N_sp;
x_window = [5 20];
temp_base = 20;

layout = choose_stack_layout(nStacks);
colors = get_plot_colors(max(nStacks, nSep));

fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100 40 900 1650]);
tlo = tiledlayout(layout.totalRows, layout.totalCols, 'Padding', 'compact', 'TileSpacing', 'compact');
tlo.Units = 'normalized';
tlo.OuterPosition = [0.12 0.055 0.84 0.90];

% Top: daily power command.
axTop = nexttile(tlo, [layout.topSpan layout.totalCols]);
plot(axTop, time15_h, d.Ptot_command(:), 'LineWidth', 2.3, 'Color', colors.power);
style_axis(axTop);
xlim(axTop, x_window);
ylabel(axTop, 'Power (MW)', 'FontName', 'Times New Roman', 'FontSize', 12);

% Middle: one panel per stack, with current as line and temperature as fill.
for s = 1:nStacks
    ax = nexttile(tlo, [layout.stackSpan layout.totalCols]);
    hold(ax, 'on');

    yyaxis(ax, 'right');
    t_curve = d.T_stout(s, :)';
    x_patch = [time15_h; flipud(time15_h)];
    y_patch = [temp_base * ones(size(t_curve)); flipud(t_curve)];
    patch(ax, x_patch, y_patch, colors.stackFill(s, :), ...
        'FaceAlpha', 0.24, 'EdgeColor', 'none', 'HandleVisibility', 'off');
    ax.YColor = colors.stackLine(s, :);
    ylabel(ax, ['T (' char(176) 'C)'], 'FontName', 'Times New Roman', 'FontSize', 11);
    ylim(ax, [temp_base 100]);
    yticks(ax, [20 60 100]);

    yyaxis(ax, 'left');
    plot(ax, time15_h, d.I_st(s, :)' / 1000, 'LineWidth', 3.0, 'Color', colors.stackLine(s, :));
    ax.YColor = colors.stackLine(s, :);
    ylabel(ax, 'I (kA)', 'FontName', 'Times New Roman', 'FontSize', 11);
    style_axis(ax);
    xlim(ax, x_window);
    ylim(ax, [0 15]);
    yticks(ax, [0 5 10 15]);
    if s < nStacks
        set(ax, 'XTickLabel', []);
    else
        xlabel(ax, 'Time (h)', 'FontName', 'Times New Roman', 'FontSize', 12);
    end
    text(ax, 0.02, 0.84, sprintf('Stack %d', s), 'Units', 'normalized', ...
        'FontName', 'Times New Roman', 'FontSize', 12, 'FontWeight', 'bold', ...
        'Color', [0.15 0.15 0.15], 'BackgroundColor', 'w', 'Margin', 1.5);
    hold(ax, 'off');
end

% Bottom: separator-side HTO traces.
axHTO = nexttile(tlo, [layout.bottomSpan layout.totalCols]);
hold(axHTO, 'on');
for g = 1:nSep
    plot(axHTO, time1_h, d.HTO_sp_1min(g, :)' * 100, 'LineWidth', 1.7, ...
        'Color', colors.htoLines(g, :), 'DisplayName', sprintf('HTO %d', g));
end
hold(axHTO, 'off');
style_axis(axHTO);
xlim(axHTO, x_window);
ylim(axHTO, [0 2]);
yticks(axHTO, 0:0.5:2);
xlabel(axHTO, 'Time (h)', 'FontName', 'Times New Roman', 'FontSize', 12);
ylabel(axHTO, 'HTO (%)', 'FontName', 'Times New Roman', 'FontSize', 12);
legend(axHTO, 'Location', 'northeast', 'Box', 'off', ...
    'NumColumns', min(2, nSep), ...
    'FontName', 'Times New Roman', 'FontSize', 10);

set(findall(fig, '-property', 'FontName'), 'FontName', 'Times New Roman');
set(findall(fig, 'Type', 'axes'), 'Clipping', 'off');
drawnow;

png_file = [output_prefix '.png'];
fig_file = [output_prefix '.fig'];
exportgraphics(fig, png_file, 'Resolution', 300);
savefig(fig, fig_file);
close(fig);

out = struct();
out.diagnostics_mat_file = diagnostics_mat_file;
out.png_file = png_file;
out.fig_file = fig_file;
out.nStacks = nStacks;
out.nSep = nSep;
end

function layout = choose_stack_layout(nStacks)
layout.totalCols = 1;
layout.topSpan = 2;
layout.stackSpan = 2;
layout.bottomSpan = 2;
layout.totalRows = layout.topSpan + nStacks * layout.stackSpan + layout.bottomSpan;
end

function colors = get_plot_colors(nLines)
colors.power = [0.16 0.41 0.71];
yellow = [230 171 45] / 255;
green = [38 166 154] / 255;
blue = [52 120 191] / 255;
grey = [124 132 142] / 255;
colors.stackLine = [yellow; green; blue; grey];
colors.stackFill = 0.78 * ones(size(colors.stackLine)) + 0.22 * colors.stackLine;

seed = [
    blue;
    yellow;
    green;
    grey;
    0.26 0.54 0.96;
    0.13 0.78 0.65;
    0.85 0.52 0.19
];
colors.htoLines = seed(1:nLines, :);
end

function style_axis(ax)
set(ax, 'Box', 'on', ...
    'LineWidth', 1.0, ...
    'FontName', 'Times New Roman', ...
    'FontSize', 10, ...
    'TickDir', 'out', ...
    'XMinorTick', 'off', ...
    'YMinorTick', 'off', ...
    'SortMethod', 'childorder');
grid(ax, 'off');
end
