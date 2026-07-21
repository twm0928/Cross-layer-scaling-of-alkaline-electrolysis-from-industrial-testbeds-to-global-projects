function files = plot_fig2b_three_panel_stack_distribution(outDir, loadFraction)
%PLOT_FIG2B_THREE_PANEL_STACK_DISTRIBUTION Reproduce revised Fig. 2b.
%
% This function generates a three-panel Fig. 2b-style plot:
%   panel 1: 5 MW reference stack, one current profile and two voltages
%   panel 2: 10 MW stacks, equal length/equal width/equal V/A
%   panel 3: 20 MW stacks, equal length/equal width/equal V/A/equal V/A kseg=2
%
% The calculation reuses the R1 stack source-code parameters in
% stack_case_library.m and the distributed equivalent circuit solver
% f_stack.m. No Submission-folder or local absolute path is required.
%
% Example:
%   addpath('Workflow/1-Stack/src')
%   plot_fig2b_three_panel_stack_distribution

if nargin < 2 || isempty(loadFraction)
    loadFraction = 1;
end

scriptDir = fileparts(mfilename('fullpath'));
addpath(scriptDir);
cfg = pipeline_config();
projectRoot = fileparts(cfg.workflow_root);

if nargin < 1 || isempty(outDir)
    outDir = fullfile(projectRoot, 'Figure', 'Figure 2b');
end

dataDir = fullfile(outDir, 'data');
outputDir = fullfile(outDir, 'output');
if ~exist(dataDir, 'dir')
    mkdir(dataDir);
end
if ~exist(outputDir, 'dir')
    mkdir(outputDir);
end

areaPolicy = 'total_area_conserved';
caseLibrary = stack_case_library();
panelSpecs = build_panel_specs();

allRows = {};
designTables = {};

for p = 1:numel(panelSpecs)
    specs = panelSpecs{p};
    for d = 1:numel(specs.designs)
        design = specs.designs(d);
        row = caseLibrary(caseLibrary.stack_size_MW == design.stackSizeMW ...
            & strcmp(caseLibrary.geometry, design.geometry), :);
        if height(row) ~= 1
            error('Cannot find unique stack case: %.0f MW, %s.', ...
                design.stackSizeMW, design.geometry);
        end

        stackCase = table2struct(row);
        D = evaluate_distribution_local(stackCase, design.kSeg, ...
            loadFraction, areaPolicy);

        nRows = height(D);
        panelOrder = repmat(p, nRows, 1);
        panelLabel = repmat({specs.panelLabel}, nRows, 1);
        designOrder = repmat(d, nRows, 1);
        designLabel = repmat({design.designLabel}, nRows, 1);
        plotLabel = repmat({design.plotLabel}, nRows, 1);
        geometry = repmat({design.geometry}, nRows, 1);
        kSeg = repmat(design.kSeg, nRows, 1);
        stackSizeMW = repmat(design.stackSizeMW, nRows, 1);

        prefix = table(panelOrder, panelLabel, designOrder, designLabel, ...
            plotLabel, stackSizeMW, geometry, kSeg, ...
            'VariableNames', {'panel_order', 'panel_label', ...
            'design_order', 'design_label', 'plot_label', ...
            'stack_size_MW', 'geometry', 'k_seg'});
        T = [prefix, D]; %#ok<AGROW>
        designTables(end + 1, :) = {design.designLabel, T}; %#ok<AGROW>

        for r = 1:height(T)
            allRows(end + 1, :) = table2cell(T(r, :)); %#ok<AGROW>
        end
    end
end

longTable = cell2table(allRows, ...
    'VariableNames', designTables{1, 2}.Properties.VariableNames);

baseName = sprintf('Fig2b_R1_three_panel_distribution_load_fraction_%g', loadFraction);
baseName = strrep(baseName, '.', 'p');
longCsvPath = fullfile(dataDir, [baseName '_long.csv']);
xlsxPath = fullfile(dataDir, [baseName '.xlsx']);
pngPath = fullfile(outputDir, [baseName '_preview.png']);
figPath = fullfile(outputDir, [baseName '_preview.fig']);

writetable(longTable, longCsvPath);
if exist(xlsxPath, 'file')
    delete(xlsxPath);
end
writetable(longTable, xlsxPath, 'Sheet', 'long');
for d = 1:size(designTables, 1)
    sheetName = matlab.lang.makeValidName(designTables{d, 1});
    sheetName = sheetName(1:min(numel(sheetName), 31));
    writetable(designTables{d, 2}, xlsxPath, 'Sheet', sheetName);
end

fig = draw_three_panel_figure(longTable, panelSpecs, loadFraction);
savefig(fig, figPath);
export_figure_png(fig, pngPath);

files = struct( ...
    'long_csv', longCsvPath, ...
    'xlsx', xlsxPath, ...
    'preview_png', pngPath, ...
    'preview_fig', figPath);

if nargout == 0
    disp(files);
end
end

function panelSpecs = build_panel_specs()
panelSpecs = cell(1, 3);

panelSpecs{1} = struct( ...
    'panelLabel', '5 MW', ...
    'designs', struct( ...
    'stackSizeMW', 5, ...
    'geometry', 'equal_VA', ...
    'kSeg', 1, ...
    'designLabel', '5MW_reference_k1', ...
    'plotLabel', '5 MW reference', ...
    'colourKey', 'reference'));

panelSpecs{2} = struct( ...
    'panelLabel', '10 MW', ...
    'designs', [ ...
    struct('stackSizeMW', 10, 'geometry', 'equal_length', ...
    'kSeg', 1, 'designLabel', '10MW_equal_length_k1', ...
    'plotLabel', 'Equal length', 'colourKey', 'equal_length'), ...
    struct('stackSizeMW', 10, 'geometry', 'equal_width', ...
    'kSeg', 1, 'designLabel', '10MW_equal_width_k1', ...
    'plotLabel', 'Equal width', 'colourKey', 'equal_width'), ...
    struct('stackSizeMW', 10, 'geometry', 'equal_VA', ...
    'kSeg', 1, 'designLabel', '10MW_equal_VA_k1', ...
    'plotLabel', 'Equal V/A', 'colourKey', 'equal_VA') ...
    ]);

panelSpecs{3} = struct( ...
    'panelLabel', '20 MW', ...
    'designs', [ ...
    struct('stackSizeMW', 20, 'geometry', 'equal_length', ...
    'kSeg', 1, 'designLabel', '20MW_equal_length_k1', ...
    'plotLabel', 'Equal length', 'colourKey', 'equal_length'), ...
    struct('stackSizeMW', 20, 'geometry', 'equal_width', ...
    'kSeg', 1, 'designLabel', '20MW_equal_width_k1', ...
    'plotLabel', 'Equal width', 'colourKey', 'equal_width'), ...
    struct('stackSizeMW', 20, 'geometry', 'equal_VA', ...
    'kSeg', 1, 'designLabel', '20MW_equal_VA_k1', ...
    'plotLabel', 'Equal V/A', 'colourKey', 'equal_VA'), ...
    struct('stackSizeMW', 20, 'geometry', 'equal_VA', ...
    'kSeg', 2, 'designLabel', '20MW_equal_VA_k2', ...
    'plotLabel', 'Equal V/A segmentation', 'colourKey', 'equal_VA_k2') ...
    ]);
end

function fig = draw_three_panel_figure(longTable, panelSpecs, loadFraction)
fig = figure('Color', 'w', 'Units', 'centimeters', ...
    'Position', [2, 2, 34.5, 7.0]);
tiledlayout(fig, 1, 3, 'TileSpacing', 'compact', 'Padding', 'compact');

for p = 1:numel(panelSpecs)
    specs = panelSpecs{p};
    ax = nexttile;
    hold(ax, 'on');
    box(ax, 'on');
    set(ax, 'FontName', 'Arial', 'FontSize', 12, 'LineWidth', 0.8);

    panelRows = longTable(longTable.panel_order == p, :);

    yyaxis(ax, 'left');
    draw_current_region(ax, panelRows, specs.designs);

    ylabel(ax, 'Cell current (per unit)');
    ylim(ax, [0, 1]);
    ax.YColor = [0, 0, 0];

    yyaxis(ax, 'right');
    for d = 1:numel(specs.designs)
        if ~should_plot_voltage(specs.designs(d))
            continue
        end
        designRows = panelRows(panelRows.design_order == d, :);
        colour = design_line_colour(specs.designs(d));
        x = designRows.cell_index_global;
        [xCum, vCum90] = cumulative_voltage_trace(x, ...
            designRows.cell_voltage_external_T90_V);
        [~, vCum60] = cumulative_voltage_trace(x, ...
            designRows.cell_voltage_external_T60_V);
        fill_voltage_down(ax, xCum, max(vCum90, vCum60), colour);
        plot(ax, xCum, vCum90, ...
            '-', 'Color', colour, 'LineWidth', 1.25, ...
            'HandleVisibility', 'off');
        plot(ax, xCum, vCum60, ...
            '--', 'Color', colour, 'LineWidth', 1.0, ...
            'HandleVisibility', 'off');
    end

    ylabel(ax, 'Cumulative cell voltage (V)');
    ylim(ax, [0, 1000]);
    ax.YColor = [0, 0, 0];
    xlim(ax, [0, 800]);
    xticks(ax, 0:200:800);
    xlabel(ax, 'Cell ID');
    grid(ax, 'off');
    format_outer_y_axes(ax, p, numel(panelSpecs));
end
end

function format_outer_y_axes(ax, panelIndex, panelCount)
% Keep only the outer y axes visible in the three-panel layout.
if numel(ax.YAxis) < 2
    return
end

if panelIndex == 1
    ax.YAxis(1).Visible = 'on';
else
    ax.YAxis(1).Visible = 'on';
    ax.YAxis(1).TickLabels = {};
    ax.YAxis(1).Label.String = '';
end

if panelIndex == panelCount
    ax.YAxis(2).Visible = 'on';
else
    ax.YAxis(2).Visible = 'on';
    ax.YAxis(2).TickLabels = {};
    ax.YAxis(2).Label.String = '';
end
end

function [xCum, vCum] = cumulative_voltage_trace(x, vCell)
xCum = [0; x(:)];
vCum = [0; cumsum(vCell(:))];
end

function yLimits = panel_cumulative_voltage_ylim(panelRows, designs)
vMax = 0;
for d = 1:numel(designs)
    if ~should_plot_voltage(designs(d))
        continue
    end
    designRows = panelRows(panelRows.design_order == d, :);
    vMax = max(vMax, max(cumsum(designRows.cell_voltage_external_T60_V)));
    vMax = max(vMax, max(cumsum(designRows.cell_voltage_external_T90_V)));
end
if vMax <= 0
    yLimits = [0, 1];
    return
end
upper = ceil(vMax / 100) * 100;
yLimits = [0, upper];
end

function draw_current_region(ax, panelRows, designs)
if numel(designs) == 1
    designRows = panelRows(panelRows.design_order == 1, :);
    x = designRows.cell_index_global;
    y = designRows.electrolysis_current_over_input;
    colour = design_fill_colour(designs(1));
    [xPlot, yPlot] = prepend_zero_x(x, y);
    plot(ax, xPlot, yPlot, '-', 'Color', colour, 'LineWidth', 0.9, ...
        'HandleVisibility', 'off');
    add_current_label(ax, x, y, designs(1), 1);
    return
end

baseMask = ~strcmp({designs.colourKey}, 'equal_VA_k2');
baseIdx = find(baseMask);
for i = 1:numel(baseIdx)
    d = baseIdx(i);
    designRows = panelRows(panelRows.design_order == d, :);
    x = designRows.cell_index_global;
    y = designRows.electrolysis_current_over_input;
    colour = design_fill_colour(designs(d));
    [xPlot, yPlot] = prepend_zero_x(x, y);
    plot(ax, xPlot, yPlot, '-', 'Color', colour * 0.72, ...
        'LineWidth', 0.95, 'HandleVisibility', 'off');
    add_current_label(ax, x, y, designs(d), d);
end

k2Idx = find(strcmp({designs.colourKey}, 'equal_VA_k2'), 1);
if ~isempty(k2Idx)
    designRows = panelRows(panelRows.design_order == k2Idx, :);
    x = designRows.cell_index_global;
    y = designRows.electrolysis_current_over_input;
    grey = design_fill_colour(designs(k2Idx));
    [xPlot, yPlot] = prepend_zero_x(x, y);
    plot(ax, xPlot, yPlot, '-', 'Color', grey, 'LineWidth', 1.05, ...
        'HandleVisibility', 'off');
    add_current_label(ax, x, y, designs(k2Idx), k2Idx);
end
end

function [xPlot, yPlot] = prepend_zero_x(x, y)
if isempty(x)
    xPlot = x;
    yPlot = y;
    return
end
xPlot = [0; x(:)];
yPlot = [y(1); y(:)];
end

function fill_voltage_down(ax, x, y, colour)
baseline = zeros(size(y));
patch(ax, [x; flipud(x)], [y; flipud(baseline)], colour, ...
    'FaceAlpha', 0.08, 'EdgeColor', 'none', ...
    'HandleVisibility', 'off');
end

function T = evaluate_distribution_local(stackCase, kSeg, loadFraction, areaPolicy)
I0 = stackCase.rated_current_A * loadFraction;
segments = split_segments_local(stackCase.n_cell, kSeg);
rows = {};
globalIndex = 0;

for s = 1:numel(segments)
    nSegCell = segments(s);
    segScale = nSegCell / stackCase.n_cell;
    resist = build_resistances_local(stackCase, segScale, areaPolicy);
    [iEle, iStray] = f_stack(nSegCell, stackCase.R0_ohm, stackCase.U0_V, ...
        resist.Rm_l, resist.Rm_u, resist.Rch_l_an, resist.Rch_l_ca, ...
        resist.Rch_u_an, resist.Rch_u_ca, resist.R_end, I0);

    iEle = full(iEle);
    iStray = full(iStray);
    meanCurrent = mean(iEle);
    segmentManifoldArea = stackCase.manifold_area_m2 * segScale;

    for c = 1:nSegCell
        globalIndex = globalIndex + 1;
        cellCurrent = iEle(c);
        rows(end + 1, :) = { ...
            globalIndex, ...
            (globalIndex - 0.5) / stackCase.n_cell, ...
            s, c, (c - 0.5) / nSegCell, ...
            nSegCell, I0, loadFraction, ...
            cellCurrent, cellCurrent / I0, cellCurrent / meanCurrent, ...
            iStray(c), ...
            local_external_voltage(stackCase, cellCurrent, 90), ...
            local_external_voltage(stackCase, cellCurrent, 60), ...
            stackCase.U0_V + stackCase.R0_ohm * cellCurrent, ...
            stackCase.channel_area_m2, segmentManifoldArea ...
            }; %#ok<AGROW>
    end
end

T = cell2table(rows, 'VariableNames', { ...
    'cell_index_global', 'position_global_pu', ...
    'segment_id', 'cell_index_in_segment', 'position_segment_pu', ...
    'n_cell_segment', 'input_current_A', 'load_fraction', ...
    'electrolysis_current_A', 'electrolysis_current_over_input', ...
    'electrolysis_current_over_segment_mean', 'stray_current_A', ...
    'cell_voltage_external_T90_V', 'cell_voltage_external_T60_V', ...
    'cell_voltage_ECN_branch_V', ...
    'channel_area_m2', 'segment_manifold_area_m2' ...
    });
end

function U = local_external_voltage(stackCase, cellCurrent, temperatureC)
R0VoltageBase = (9.4410 - 0.0250 * temperatureC) * 1e-5 / 2;
R0Voltage = R0VoltageBase / stackCase.cell_area_scale;
U = stackCase.U0_V + R0Voltage * cellCurrent;
end

function resist = build_resistances_local(stackCase, segmentScale, areaPolicy)
m = 0.31;
T = 84 + 273;
alpha = 0;
n_l = 2;

lc = stackCase.channel_length_m;
lm = stackCase.manifold_length_m;
lmEnd = lm;
Sch = stackCase.channel_area_m2;
SmBase = stackCase.manifold_area_m2;

switch areaPolicy
    case 'total_area_conserved'
        Sm = SmBase * segmentScale;
    case 'branch_area_preserved'
        Sm = SmBase;
    otherwise
        error('Unsupported SFT manifold-area policy: %s.', areaPolicy);
end

sigma = 2800*m - 0.9241*T - 0.01497*T^2 - 9.052*T*m ...
    + 0.02591*T^2*m^(0.1765) + 0.06966*T*m^(-1) - 289800*m*T^(-1);
rho = 1 / sigma;

resist.Rm_l = rho * lm / (Sm * n_l);
resist.Rch_l_ca = rho * lc / (Sch * n_l);
resist.Rch_l_an = resist.Rch_l_ca;
resist.Rm_u = rho * lm / Sm / (1 - alpha)^1.5;
resist.Rch_u_an = rho * lc / Sch / (1 - alpha)^1.5;
resist.Rch_u_ca = resist.Rch_u_an;
resist.Rm_end = rho * lmEnd / (Sm * n_l);
resist.Rch_l_end = rho * lc / (Sch * n_l);
resist.R_end = resist.Rm_end + resist.Rch_l_end;
end

function segments = split_segments_local(nCell, kSeg)
base = floor(nCell / kSeg);
segments = base * ones(1, kSeg);
remainder = nCell - base * kSeg;
if remainder > 0
    segments(1:remainder) = segments(1:remainder) + 1;
end
end

function colour = design_fill_colour(design)
if strcmp(design.colourKey, 'equal_VA_k2')
    colour = [120, 120, 120] / 255;
    return
end

switch design.stackSizeMW
    case 5
        colour = [245, 166, 35] / 255;
    case 10
        colour = [0, 145, 117] / 255;
    case 20
        colour = [36, 126, 194] / 255;
    otherwise
        colour = [0, 0, 0];
end
end

function colour = design_line_colour(design)
colour = design_fill_colour(design);
end

function order = current_draw_order(designs)
maxCells = zeros(1, numel(designs));
for i = 1:numel(designs)
    switch designs(i).stackSizeMW
        case 5
            maxCells(i) = 200;
        case 10
            switch designs(i).geometry
                case 'equal_length'
                    maxCells(i) = 200;
                case 'equal_VA'
                    maxCells(i) = 280;
                otherwise
                    maxCells(i) = 400;
            end
        case 20
            switch designs(i).geometry
                case 'equal_length'
                    maxCells(i) = 200;
                case 'equal_VA'
                    maxCells(i) = 400;
                otherwise
                    maxCells(i) = 800;
            end
        otherwise
            maxCells(i) = 0;
    end
end
[~, order] = sort(maxCells, 'descend');
end

function tf = should_plot_voltage(design)
tf = strcmp(design.geometry, 'equal_VA') || design.stackSizeMW == 5;
end

function add_current_label(ax, x, y, design, designOrder)
if isempty(x)
    return
end
% Figure annotations are intentionally omitted here so labels can be added
% manually during final figure polishing without touching the data workflow.
return
if strcmp(design.colourKey, 'reference')
    return
end
colour = design_fill_colour(design);
[xTarget, yOffset] = label_position(design, designOrder);

if strcmp(design.colourKey, 'equal_VA_k2')
    text(ax, 610, 0.88, design.plotLabel, ...
        'Color', colour, 'FontName', 'Arial', 'FontSize', 10, ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
        'BackgroundColor', 'w', 'Margin', 0.5, 'Clipping', 'on');
    return
end

xTarget = min(max(xTarget, min(x) + 15), max(x) - 15);
[~, idx] = min(abs(x - xTarget));
yTarget = y(idx);

text(ax, x(idx), min(max(yTarget + yOffset, 0.08), 0.96), ...
    design.plotLabel, ...
    'Color', colour, 'FontName', 'Arial', 'FontSize', 10, ...
    'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
    'BackgroundColor', 'w', 'Margin', 0.5, 'Clipping', 'on');
end

function [xTarget, yOffset] = label_position(design, designOrder)
switch design.colourKey
    case 'reference'
        xTarget = 105;
        yOffset = 0.045;
    case 'equal_length'
        xTarget = 130;
        yOffset = 0.095;
    case 'equal_width'
        xTarget = 0.84 * max_cell_count_for_design(design);
        yOffset = -0.075;
    case 'equal_VA'
        xTarget = 0.68 * max_cell_count_for_design(design);
        yOffset = 0.085;
    case 'equal_VA_k2'
        xTarget = 0.58 * max_cell_count_for_design(design);
        yOffset = 0.075;
    otherwise
        xTarget = 0.75 * max_cell_count_for_design(design);
        yOffset = 0.035 + 0.012 * designOrder;
end
end

function n = max_cell_count_for_design(design)
switch design.stackSizeMW
    case 5
        n = 200;
    case 10
        switch design.geometry
            case 'equal_length'
                n = 200;
            case 'equal_VA'
                n = 280;
            otherwise
                n = 400;
        end
    case 20
        switch design.geometry
            case 'equal_length'
                n = 200;
            case 'equal_VA'
                n = 400;
            otherwise
                n = 800;
        end
    otherwise
        n = 800;
end
end

function export_figure_png(fig, pngPath)
try
    exportgraphics(fig, pngPath, 'Resolution', 600);
catch
    print(fig, pngPath, '-dpng', '-r600');
end
end
