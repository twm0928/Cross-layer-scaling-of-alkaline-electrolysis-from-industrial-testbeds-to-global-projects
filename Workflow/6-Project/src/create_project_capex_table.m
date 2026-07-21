function create_project_capex_table()
%CREATE_PROJECT_CAPEX_TABLE Write the revised project-layer CAPEX input.
%
% The legacy project calculation hard-coded topology CAPEX values for M1-M6.
% This script turns those values into an explicit input workbook and appends
% M7 with the current revision assumption: M7 uses the same base CAPEX as M6.

clc;

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
inputDir = fullfile(projectRoot, 'data', 'input');
backupDir = fullfile(inputDir, 'backup');

if ~exist(inputDir, 'dir'); mkdir(inputDir); end
if ~exist(backupDir, 'dir'); mkdir(backupDir); end

outFile = fullfile(inputDir, 'topology_capex_M1_M7.xlsx');
if exist(outFile, 'file')
    stamp = datestr(now, 'yyyymmdd_HHMMSS');
    movefile(outFile, fullfile(backupDir, ['topology_capex_M1_M7_' stamp '.xlsx']));
end

topologyId = (1:7)';
topologyLabel = compose("M%d", topologyId);
stackInterface = ["S1"; "S1"; "S1"; "S2"; "S2"; "S3"; "S4"];
moduleFamily = [
    "4-in-1";
    "4-in-1";
    "4-in-1";
    "2-in-1";
    "2-in-1";
    "1-in-1";
    "1-in-1 segmented"
    ];

capex_1e4_USD = [2800; 2738; 2688; 2662; 2488; 2272; 2272];
capex_USD = capex_1e4_USD * 1e4;

opexFraction = 0.03;
lifetimeYear = 15;
discountRate = 0.07;
capitalRecoveryFactor = 1 / (1 / discountRate - 1 / discountRate / (1 + discountRate)^lifetimeYear);
annualisationFactor = opexFraction + capitalRecoveryFactor;
annualisedCapex_USD_per_year = capex_USD * annualisationFactor;

assumptionType = [
    repmat("legacy hard-coded value from cal_plant_pro.m", 6, 1);
    "revision assumption: same base CAPEX as M6"
    ];
notes = [
    repmat("legacy project-side economic model input", 6, 1);
    "M7 represents the S4 segmented-stack extension; cost is provisionally set equal to M6 to isolate the efficiency effect until vendor-level CAPEX evidence is available."
    ];

capexTable = table( ...
    topologyId, topologyLabel, stackInterface, moduleFamily, ...
    capex_1e4_USD, capex_USD, ...
    opexFraction * ones(7, 1), lifetimeYear * ones(7, 1), discountRate * ones(7, 1), ...
    capitalRecoveryFactor * ones(7, 1), annualisationFactor * ones(7, 1), ...
    annualisedCapex_USD_per_year, assumptionType, notes, ...
    'VariableNames', { ...
    'topology_id', 'topology_label', 'stack_interface', 'module_family', ...
    'base_capex_1e4_USD', 'base_capex_USD', ...
    'opex_fraction', 'lifetime_year', 'discount_rate', ...
    'capital_recovery_factor', 'annualisation_factor', ...
    'annualised_capex_USD_per_year', 'assumption_type', 'notes'});

caseName = ["base"; "high_CAPEX"];
capexMultiplier = [1; 10];
costCaseTable = table(caseName, capexMultiplier, ...
    'VariableNames', {'capex_case', 'capex_multiplier'});

opexCaseName = ["base"; "high_H2_price_OPEX_multiplier"];
opexRevenueMultiplier = [1; 4];
opexCaseTable = table(opexCaseName, opexRevenueMultiplier, ...
    'VariableNames', {'opex_or_revenue_case', 'hydrogen_revenue_multiplier'});

readmeKey = [
    "purpose";
    "legacy_source";
    "m7_assumption";
    "annualisation";
    "next_step"
    ];
readmeValue = [
    "Project-layer topology CAPEX input table for the revised M1-M7 economic calculation.";
    "M1-M6 values are copied from the legacy MATLAB hard-coded vector [2800 2738 2688 2662 2488 2272] * 1e4.";
    "M7 is currently set equal to M6. This is a conservative neutral-cost assumption for the segmented-stack extension.";
    "annualised_CAPEX = base_CAPEX * (OPEX_fraction + capital_recovery_factor), matching the legacy project code.";
    "Revised project scripts should read this workbook rather than hard-coding topology CAPEX."
    ];
readmeTable = table(readmeKey, readmeValue, 'VariableNames', {'key', 'value'});

writetable(capexTable, outFile, 'Sheet', 'topology_capex', 'WriteMode', 'overwritesheet');
writetable(costCaseTable, outFile, 'Sheet', 'capex_cases', 'WriteMode', 'overwritesheet');
writetable(opexCaseTable, outFile, 'Sheet', 'opex_revenue_cases', 'WriteMode', 'overwritesheet');
writetable(readmeTable, outFile, 'Sheet', 'readme', 'WriteMode', 'overwritesheet');

writetable(capexTable, fullfile(inputDir, 'topology_capex_M1_M7.csv'));

fprintf('Wrote CAPEX table: %s\n', outFile);
fprintf('M7 base CAPEX = %.0f x 1e4 USD, same as M6.\n', capex_1e4_USD(end));
end
