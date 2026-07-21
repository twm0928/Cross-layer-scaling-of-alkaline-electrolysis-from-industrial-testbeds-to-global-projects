function files = export_fig2b_stack_distribution_sources(outDir, loadFraction)
%EXPORT_FIG2B_STACK_DISTRIBUTION_SOURCES Export 1D stack distributions.
%
% The exported data are intended for Fig. 2b-style plots at the 20 MW stack
% layer. The x-axis is the one-dimensional cell position along the stack.
% The current distribution is solved with the ECN model. The two temperature
% columns use the local external cell-voltage relation U_cell,i(T).

if nargin < 1 || isempty(outDir)
    cfg = pipeline_config();
    projectRoot = fileparts(cfg.workflow_root);
    outDir = fullfile(projectRoot, 'Figure', 'Figure 2b', 'data');
end
if nargin < 2 || isempty(loadFraction)
    loadFraction = 1;
end

if ~exist(outDir, 'dir')
    mkdir(outDir);
end

caseLibrary = stack_case_library();
areaPolicy = 'total_area_conserved';

designs = { ...
    '20MW_equal_length_k1', 20, 'equal_length', 1; ...
    '20MW_equal_width_k1',  20, 'equal_width',  1; ...
    '20MW_equal_VA_k1',     20, 'equal_VA',     1; ...
    '20MW_equal_VA_k2',     20, 'equal_VA',     2 ...
    };

allRows = {};
metaRows = cell(size(designs, 1), 11);
designTables = cell(size(designs, 1), 2);

for d = 1:size(designs, 1)
    label = designs{d, 1};
    stackSize = designs{d, 2};
    geometry = designs{d, 3};
    kSeg = designs{d, 4};

    row = caseLibrary(caseLibrary.stack_size_MW == stackSize & strcmp(caseLibrary.geometry, geometry), :);
    if height(row) ~= 1
        error('Cannot find unique stack case for %s.', label);
    end
    stackCase = table2struct(row);
    D = evaluate_distribution(stackCase, kSeg, loadFraction, areaPolicy);

    nRows = height(D);
    designColumn = repmat({label}, nRows, 1);
    stackSizeColumn = repmat(stackSize, nRows, 1);
    geometryColumn = repmat({geometry}, nRows, 1);
    kColumn = repmat(kSeg, nRows, 1);

    T = table(designColumn, stackSizeColumn, geometryColumn, kColumn, ...
        'VariableNames', {'design_label', 'stack_size_MW', 'geometry', 'k_seg'});
    T = [T, D]; %#ok<AGROW>

    for r = 1:height(T)
        allRows(end + 1, :) = table2cell(T(r, :)); %#ok<AGROW>
    end
    designTables{d, 1} = label;
    designTables{d, 2} = T;

    metaRows(d, :) = { ...
        d, label, stackSize, geometry, kSeg, stackCase.n_cell, ...
        stackCase.rated_current_A, stackCase.cell_area_scale, ...
        stackCase.channel_area_m2, stackCase.manifold_area_m2, areaPolicy ...
        };
end

longTable = cell2table(allRows, 'VariableNames', designTables{1, 2}.Properties.VariableNames);
metadata = cell2table(metaRows, 'VariableNames', { ...
    'order', 'design_label', 'stack_size_MW', 'geometry', 'k_seg', ...
    'n_cell_total', 'rated_current_A', 'cell_area_scale', ...
    'channel_area_m2', 'manifold_area_m2_parent', 'segmentation_area_policy' ...
    });
metadata.load_fraction(:) = loadFraction;
metadata.temperature_columns = repmat({'cell_voltage_external_T90_V and cell_voltage_external_T60_V'}, height(metadata), 1);

baseName = sprintf('Fig2b_stack_1D_distribution_load_fraction_%g', loadFraction);
baseName = strrep(baseName, '.', 'p');

csvPath = fullfile(outDir, [baseName '_long.csv']);
xlsxPath = fullfile(outDir, [baseName '.xlsx']);
metaCsvPath = fullfile(outDir, [baseName '_metadata.csv']);

writetable(longTable, csvPath);
writetable(longTable, xlsxPath, 'Sheet', 'long');
writetable(metadata, xlsxPath, 'Sheet', 'metadata');
writetable(metadata, metaCsvPath);

for d = 1:size(designTables, 1)
    sheetName = matlab.lang.makeValidName(designTables{d, 1});
    sheetName = sheetName(1:min(numel(sheetName), 31));
    writetable(designTables{d, 2}, xlsxPath, 'Sheet', sheetName);
end

files = struct('long_csv', csvPath, 'xlsx', xlsxPath, 'metadata_csv', metaCsvPath);

if nargout == 0
    disp(files);
end
end

function T = evaluate_distribution(stackCase, kSeg, loadFraction, areaPolicy)
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
