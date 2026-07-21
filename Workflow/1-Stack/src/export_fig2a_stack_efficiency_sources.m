function files = export_fig2a_stack_efficiency_sources(outDir)
%EXPORT_FIG2A_STACK_EFFICIENCY_SOURCES Export clean Fig. 2a source tables.
%
% The Fig. 2a plotting axis in the original Origin workbook follows the
% stack load/current fraction. A strict external-power per-unit interface is
% also exported for later pipeline coupling, but it should not be used to
% overlay curves directly on the original Fig. 2a axis.

if nargin < 1 || isempty(outDir)
    cfg = pipeline_config();
    projectRoot = fileparts(cfg.workflow_root);
    outDir = fullfile(projectRoot, 'Figure', 'Figure 2a', 'data');
end

if ~exist(outDir, 'dir')
    mkdir(outDir);
end

areaPolicy = 'total_area_conserved';
caseLibrary = stack_case_library();
modelSpec = fig2a_model_spec();

loadFraction = (0:0.01:1)';
powerPu = (0:0.01:1)';

[loadT90, loadMetaT90] = build_source_table( ...
    caseLibrary, modelSpec, loadFraction, 'load_fraction', 90, areaPolicy);
[loadT60, loadMetaT60] = build_source_table( ...
    caseLibrary, modelSpec, loadFraction, 'load_fraction', 60, areaPolicy);
[powerT90, powerMetaT90] = build_source_table( ...
    caseLibrary, modelSpec, powerPu, 'power_pu', 90, areaPolicy);

files = struct();
files.load_fraction_T90 = write_source_files( ...
    loadT90, loadMetaT90, outDir, 'Fig2a_stack_efficiency_source_load_fraction_T90');
files.load_fraction_T60 = write_source_files( ...
    loadT60, loadMetaT60, outDir, 'Fig2a_stack_efficiency_source_load_fraction_T60');
files.power_pu_T90 = write_source_files( ...
    powerT90, powerMetaT90, outDir, 'Fig2a_stack_efficiency_source_T90');

if nargout == 0
    disp(files);
end
end

function modelSpec = fig2a_model_spec()
% Model order follows the agreed Fig. 2a/SI Table S4b plotting order.
modelSpec = { ...
    '5MW_k1',              5,  'equal_VA',     1; ...
    '10MW_equal_width_k1', 10, 'equal_width',  1; ...
    '10MW_equal_length_k1',10, 'equal_length', 1; ...
    '10MW_equal_VA_k1',    10, 'equal_VA',     1; ...
    '10MW_equal_VA_k2',    10, 'equal_VA',     2; ...
    '20MW_equal_width_k1', 20, 'equal_width',  1; ...
    '20MW_equal_length_k1',20, 'equal_length', 1; ...
    '20MW_equal_VA_k1',    20, 'equal_VA',     1; ...
    '20MW_equal_VA_k2',    20, 'equal_VA',     2; ...
    '20MW_equal_VA_k4',    20, 'equal_VA',     4 ...
    };
end

function [T, M] = build_source_table(caseLibrary, modelSpec, xGrid, axisMode, temperatureC, areaPolicy)
[axisName, axisNote] = axis_metadata(axisMode);
[voltageField, suffix] = temperature_metadata(temperatureC);

T = table(xGrid, 'VariableNames', {axisName});
metadataRows = cell(size(modelSpec, 1), 10);

for i = 1:size(modelSpec, 1)
    label = modelSpec{i, 1};
    stackSize = modelSpec{i, 2};
    geometry = modelSpec{i, 3};
    kSeg = modelSpec{i, 4};

    row = caseLibrary(caseLibrary.stack_size_MW == stackSize & strcmp(caseLibrary.geometry, geometry), :);
    if height(row) ~= 1
        error('Cannot find unique stack case for %s.', label);
    end
    stackCase = table2struct(row);

    currentFractions = axis_to_current_fraction(stackCase, xGrid, axisMode, temperatureC);
    positiveIdx = xGrid > 0;
    curve = evaluate_stack_sft_case(stackCase, kSeg, currentFractions(positiveIdx), areaPolicy);

    etaVoltage = 1.48 ./ curve.(voltageField);
    etaCurrent = max(curve.current_efficiency, 0);
    etaTotal = etaVoltage .* etaCurrent;

    etaVoltageGrid = zeros(size(xGrid));
    etaCurrentGrid = zeros(size(xGrid));
    etaTotalGrid = zeros(size(xGrid));
    etaVoltageGrid(~positiveIdx) = 1.48 / stackCase.U0_V;
    etaCurrentGrid(~positiveIdx) = 0;
    etaTotalGrid(~positiveIdx) = 0;
    etaVoltageGrid(positiveIdx) = etaVoltage;
    etaCurrentGrid(positiveIdx) = etaCurrent;
    etaTotalGrid(positiveIdx) = etaTotal;

    T.([label '_eta_voltage_' suffix]) = etaVoltageGrid;
    T.([label '_eta_current']) = etaCurrentGrid;
    T.([label '_eta_total_' suffix]) = etaTotalGrid;

    metadataRows(i, :) = { ...
        i, label, stackSize, geometry, kSeg, ...
        stackCase.n_cell, stackCase.rated_current_A, temperatureC, ...
        areaPolicy, axisNote ...
        };
end

M = cell2table(metadataRows, 'VariableNames', { ...
    'order', 'model', 'stack_size_MW', 'geometry', 'k_segments', ...
    'n_cell', 'rated_current_A', 'temperature_C', ...
    'segmentation_area_policy', 'axis_note' ...
    });
end

function currentFraction = axis_to_current_fraction(stackCase, xGrid, axisMode, temperatureC)
switch axisMode
    case 'load_fraction'
        currentFraction = xGrid;
    case 'power_pu'
        currentFraction = power_pu_to_current_fraction(stackCase, xGrid, temperatureC);
    otherwise
        error('Unsupported axis mode: %s.', axisMode);
end
currentFraction = min(max(currentFraction, 0), 1);
end

function currentFraction = power_pu_to_current_fraction(stackCase, powerPu, temperatureC)
% External stack power obeys P/P_rated = c*(U0 + a*c)/(U0 + a),
% where c is the current fraction and a = R0_voltage(T)*I_rated.
R0VoltageBase = (9.4410 - 0.0250 * temperatureC) * 1e-5 / 2;
R0Voltage = R0VoltageBase / stackCase.cell_area_scale;
a = R0Voltage * stackCase.rated_current_A;
uRated = stackCase.U0_V + a;

currentFraction = zeros(size(powerPu));
positiveIdx = powerPu > 0;
if a == 0
    currentFraction(positiveIdx) = powerPu(positiveIdx);
else
    currentFraction(positiveIdx) = ...
        (-stackCase.U0_V + sqrt(stackCase.U0_V^2 + 4 * a * uRated .* powerPu(positiveIdx))) ./ (2 * a);
end
end

function paths = write_source_files(T, M, outDir, baseName)
csvPath = fullfile(outDir, [baseName '.csv']);
xlsxPath = fullfile(outDir, [baseName '.xlsx']);
metaCsvPath = fullfile(outDir, [baseName '_metadata.csv']);

writetable(T, csvPath);
writetable(T, xlsxPath, 'Sheet', 'efficiency_curves');
writetable(M, xlsxPath, 'Sheet', 'metadata');
writetable(M, metaCsvPath);

paths = struct('csv', csvPath, 'xlsx', xlsxPath, 'metadata_csv', metaCsvPath);
end

function [axisName, axisNote] = axis_metadata(axisMode)
switch axisMode
    case 'load_fraction'
        axisName = 'Load_fraction';
        axisNote = 'Matches the original Origin Fig. 2a load/current-fraction axis.';
    case 'power_pu'
        axisName = 'Power_pu';
        axisNote = 'Strict external-power per-unit interface; not the original Fig. 2a axis.';
    otherwise
        error('Unsupported axis mode: %s.', axisMode);
end
end

function [voltageField, suffix] = temperature_metadata(temperatureC)
switch temperatureC
    case 90
        voltageField = 'average_cell_voltage_external_T90_V';
        suffix = 'T90';
    case 60
        voltageField = 'average_cell_voltage_external_T60_V';
        suffix = 'T60';
    otherwise
        error('Unsupported temperature: %.3g C.', temperatureC);
end
end
