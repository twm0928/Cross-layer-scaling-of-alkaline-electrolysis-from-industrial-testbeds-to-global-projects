function run_project_theta_M1_M7_dynamic_fresh(projectList, thetaGrid)
%RUN_PROJECT_THETA_M1_M7_DYNAMIC Recompute project economics with M1-M7.
%
% Scope of this revised project-side run:
%   - Keep the legacy theta-rule dispatch and project economic objective.
%   - Replace legacy M1-M6 Excel production tables with the revised dynamic
%     efficiency surrogate for M1-M7.
%   - Read topology CAPEX from data/input/topology_capex_M1_M7.xlsx.
%   - Do not include MILP or degradation corrections in this mainline run.

clc;

thisFile = mfilename('fullpath');
branchRoot = fileparts(fileparts(thisFile));
projectRoot = fileparts(branchRoot);
workflowRoot = fileparts(projectRoot);
inputDir = fullfile(projectRoot, 'data', 'input');
outputDir = fullfile(branchRoot, 'outputs');
reportDir = fullfile(branchRoot, 'report');

if ~exist(outputDir, 'dir'); mkdir(outputDir); end
if ~exist(reportDir, 'dir'); mkdir(reportDir); end

featureSrc = fullfile(workflowRoot, '2-Module', '2-DynamicEfficiencySurrogate', 'src');
if exist(featureSrc, 'dir'); addpath(featureSrc); end
projectSrc = fullfile(projectRoot, 'src');
if exist(projectSrc, 'dir'); addpath(projectSrc); end

modelDir = fullfile(workflowRoot, '2-Module', 'data', 'dynamic_models');
capexFile = fullfile(inputDir, 'topology_capex_M1_M7.xlsx');
projectInfoFile = fullfile(inputDir, 'ProjectInfo.xlsx');

profileFile = fullfile(inputDir, 'Project profiles.xlsx');
assert(isfile(capexFile), 'Missing CAPEX input: %s', capexFile);
assert(isfile(projectInfoFile), 'Missing project input: %s', projectInfoFile);
assert(isfile(profileFile), 'Missing profile input: %s', profileFile);

cfg = struct();
cfg.num_project = 24;
cfg.nominal_module_count = 10;
cfg.module_rating_MW = 20;
if nargin < 1 || isempty(projectList)
    projectList = 1:cfg.num_project;
end
if nargin < 2 || isempty(thetaGrid)
    thetaGrid = 0:0.1:1;
end
cfg.theta_grid = thetaGrid(:)';
cfg.theta_code = round(cfg.theta_grid * cfg.module_rating_MW);
cfg.h2_lhv_MWh_per_t = 33.33;
cfg.keep_legacy_electricity_cost_quarter_factor = true;
cfg.workflowRoot = workflowRoot;
cfg.outputDir = outputDir;

capexTable = readtable(capexFile, 'Sheet', 'topology_capex');
capexCases = readtable(capexFile, 'Sheet', 'capex_cases');
revenueCases = readtable(capexFile, 'Sheet', 'opex_revenue_cases');

topologyIds = capexTable.topology_id(:)';
topologyLabels = string(capexTable.topology_label(:))';
nTopologies = numel(topologyIds);
nCapexCases = height(capexCases);
nRevenueCases = height(revenueCases);
nCostCases = nCapexCases * nRevenueCases;

models = cell(1, nTopologies);
for k = 1:nTopologies
    modelFile = fullfile(modelDir, sprintf('eta_model_topo%d.mat', topologyIds(k)));
    assert(isfile(modelFile), 'Missing dynamic efficiency model: %s', modelFile);
    models{k} = loadLearnerForCoder(modelFile);
end

[projectData, profileData, inputCheck] = read_project_inputs_current(projectInfoFile, profileFile, cfg);
writetable(inputCheck, fullfile(outputDir, 'project_input_alignment_check.csv'));

summaryRows = [];
thetaRows = [];
productionRows = [];
featureRows = [];

% Keep this compatibility state to avoid silently changing the historical
% project-side economics. The legacy script overwrites the discount-rate
% variable with the CAPEX-case loop index after the first project.
legacyPriceDiscountState = 0.07;

for projectId = reshape(projectList, 1, [])
    [priceEle, priceH2, legacyPriceDiscountUsed] = project_prices(projectData(projectId, :), legacyPriceDiscountState);
    Ptotal = reshape(profileData(projectId, :) * cfg.module_rating_MW * cfg.nominal_module_count, [24, 365])';
    nRealModules = max(1, ceil(max(Ptotal(:)) / cfg.module_rating_MW));

    profitByCostTheta = nan(nCostCases, numel(cfg.theta_grid));
    thetaStore = cell(numel(cfg.theta_grid), 1);
    benchmarkProfit = nan(nCostCases, 1);

    for thetaIndex = 1:numel(cfg.theta_grid)
        theta = cfg.theta_grid(thetaIndex);
        thetaCode = cfg.theta_code(thetaIndex);
        Pmodule = dispatch_theta_project(Ptotal, theta, cfg.module_rating_MW, nRealModules);
        scheduleEval = evaluate_project_schedule(Pmodule, models, topologyIds, topologyLabels, cfg);

        for topoIndex = 1:nTopologies
            productionRows = append_production_rows(productionRows, projectId, theta, thetaCode, ...
                scheduleEval, topoIndex, topologyIds(topoIndex), topologyLabels(topoIndex));
        end
        featureRows = append_feature_rows(featureRows, projectId, theta, thetaCode, scheduleEval);

        optTopologiesByCost = nan(nCostCases, nRealModules);
        optProfitByCostModule = nan(nCostCases, nRealModules);
        optH2ByCostModule = nan(nCostCases, nRealModules);
        plantProfitByCost = nan(nCostCases, 1);
        plantH2ByCost = nan(nCostCases, 1);
        benchmarkAtThetaByCost = nan(nCostCases, 1);

        costCaseId = 0;
        for capexCaseIndex = 1:nCapexCases
            for revenueCaseIndex = 1:nRevenueCases
                costCaseId = costCaseId + 1;
                capexMultiplier = capexCases.capex_multiplier(capexCaseIndex);
                h2RevenueMultiplier = revenueCases.hydrogen_revenue_multiplier(revenueCaseIndex);

                objective = nan(nTopologies, nRealModules);
                for topoIndex = 1:nTopologies
                    for moduleIndex = 1:nRealModules
                        h2_t = scheduleEval.hydrogen_t(topoIndex, moduleIndex);
                        elecCost = scheduleEval.electricity_cost_energy_MWh(moduleIndex) * 1000 * priceEle;
                        capexCost = capexTable.annualised_capex_USD_per_year(topoIndex) * capexMultiplier;
                        objective(topoIndex, moduleIndex) = h2_t * 11.2 * 1000 * priceH2 * h2RevenueMultiplier ...
                            - elecCost - capexCost;
                    end
                end

                if thetaIndex == 1
                    benchmarkProfit(costCaseId) = sum(objective(1, :));
                end
                benchmarkAtThetaByCost(costCaseId) = sum(objective(1, :));

                [optProfitByCostModule(costCaseId, :), optIndex] = max(objective, [], 1);
                optTopologiesByCost(costCaseId, :) = topologyIds(optIndex);
                for moduleIndex = 1:nRealModules
                    optH2ByCostModule(costCaseId, moduleIndex) = scheduleEval.hydrogen_t(optIndex(moduleIndex), moduleIndex);
                end
                plantProfitByCost(costCaseId) = sum(optProfitByCostModule(costCaseId, :));
                plantH2ByCost(costCaseId) = sum(optH2ByCostModule(costCaseId, :));
            end
        end

        profitByCostTheta(:, thetaIndex) = plantProfitByCost;
        thetaStore{thetaIndex} = struct( ...
            'theta', theta, ...
            'thetaCode', thetaCode, ...
            'optTopologiesByCost', optTopologiesByCost, ...
            'optProfitByCostModule', optProfitByCostModule, ...
            'optH2ByCostModule', optH2ByCostModule, ...
            'plantProfitByCost', plantProfitByCost, ...
            'plantH2ByCost', plantH2ByCost, ...
            'benchmarkAtThetaByCost', benchmarkAtThetaByCost, ...
            'scheduleEval', scheduleEval);

        thetaRows = append_theta_rows(thetaRows, projectId, theta, thetaCode, priceEle, priceH2, ...
            nRealModules, capexCases, revenueCases, plantProfitByCost, plantH2ByCost, ...
            benchmarkAtThetaByCost, benchmarkProfit);
    end

    [~, bestThetaIndexByCost] = max(profitByCostTheta, [], 2);
    for costCaseId = 1:nCostCases
        bestThetaIndex = bestThetaIndexByCost(costCaseId);
        best = thetaStore{bestThetaIndex};
        optTopos = best.optTopologiesByCost(costCaseId, :);
        counts = histcounts(optTopos, [topologyIds, max(topologyIds) + 1]) / nRealModules;

        capexCaseIndex = ceil(costCaseId / nRevenueCases);
        revenueCaseIndex = costCaseId - (capexCaseIndex - 1) * nRevenueCases;

        summaryRows = append_summary_row(summaryRows, projectId, costCaseId, capexCaseIndex, revenueCaseIndex, ...
            capexCases, revenueCases, best.theta, best.thetaCode, nRealModules, priceEle, priceH2, ...
            counts, optTopos, best.plantH2ByCost(costCaseId), best.plantProfitByCost(costCaseId), ...
            benchmarkProfit(costCaseId), legacyPriceDiscountUsed, topologyLabels);
    end

    % Preserve the historical state transition after the first project's
    % CAPEX loop. This matches the legacy project-side workbook behaviour.
    legacyPriceDiscountState = nCapexCases;
    fprintf('Project %02d complete: %d modules, best theta range %.1f-%.1f.\n', ...
        projectId, nRealModules, min(summaryRows(summaryRows(:, 1) == projectId, 5)), max(summaryRows(summaryRows(:, 1) == projectId, 5)));
end

summaryTable = build_summary_table(summaryRows, nTopologies, cfg.nominal_module_count);
thetaTable = build_theta_table(thetaRows);
productionTable = build_production_table(productionRows);
featureTable = build_feature_table(featureRows);

outXlsx = fullfile(outputDir, 'project_M1_M7_theta_dynamic_results.xlsx');
outMat = fullfile(outputDir, 'project_M1_M7_theta_dynamic_results.mat');
outSummaryCsv = fullfile(outputDir, 'project_M1_M7_theta_dynamic_summary.csv');
outThetaCsv = fullfile(outputDir, 'project_M1_M7_theta_dynamic_by_theta.csv');

if exist(outXlsx, 'file')
    delete(outXlsx);
end
writetable(summaryTable, outXlsx, 'Sheet', 'project_summary', 'WriteMode', 'overwritesheet');
writetable(thetaTable, outXlsx, 'Sheet', 'theta_sweep', 'WriteMode', 'overwritesheet');
writetable(productionTable, outXlsx, 'Sheet', 'production_by_topology', 'WriteMode', 'overwritesheet');
writetable(featureTable, outXlsx, 'Sheet', 'module_features', 'WriteMode', 'overwritesheet');
writetable(capexTable, outXlsx, 'Sheet', 'capex_input', 'WriteMode', 'overwritesheet');

writetable(summaryTable, outSummaryCsv);
writetable(thetaTable, outThetaCsv);
save(outMat, 'summaryTable', 'thetaTable', 'productionTable', 'featureTable', 'capexTable', 'capexCases', 'revenueCases', 'cfg');

write_project_report(reportDir, summaryTable, thetaTable, capexTable, cfg, outXlsx);

fprintf('Revised project M1-M7 theta-rule run complete.\n');
fprintf('Excel: %s\n', outXlsx);
fprintf('Summary rows: %d\n', height(summaryTable));
end

function [priceEle, priceH2, discountUsed] = project_prices(projectRow, legacyDiscountState)
projectType = projectRow(4);
discountUsed = legacyDiscountState;
opex = 0.03;
if projectType == 1
    priceEle = projectRow(5) * 7;
elseif projectType == 2
    ann = opex + 1 / (1 / legacyDiscountState - 1 / legacyDiscountState / (1 + legacyDiscountState)^20);
    priceEle = projectRow(6) * 7 * ann / projectRow(8);
else
    ann = opex + 1 / (1 / legacyDiscountState - 1 / legacyDiscountState / (1 + legacyDiscountState)^20);
    priceEle = projectRow(7) * 7 * ann / projectRow(9);
end
priceH2 = priceEle * 60 / 11.2;
end

function Pmodule = dispatch_theta_project(Ptotal, theta, Pmax, nModules)
Pbase = theta * Pmax;
[days, steps] = size(Ptotal);
Pmodule = zeros(days, steps, nModules);

for d = 1:days
    for t = 1:steps
        remaining = min(Ptotal(d, t), nModules * Pmax);
        for m = 1:nModules
            if remaining >= Pbase
                Pmodule(d, t, m) = Pbase;
                remaining = remaining - Pbase;
            else
                Pmodule(d, t, m) = remaining;
                remaining = 0;
                break;
            end
        end
        if remaining > 0
            room = squeeze(Pmax - Pmodule(d, t, :));
            room = max(room, 0);
            totalRoom = sum(room);
            if totalRoom > 0
                Pmodule(d, t, :) = squeeze(Pmodule(d, t, :)) + remaining * room / totalRoom;
            end
        end
    end
end
end

function eval = evaluate_project_schedule(Pmodule, models, topologyIds, topologyLabels, cfg)
[nDays, nSteps, nModules] = size(Pmodule);
nTopologies = numel(topologyIds);
nFeatures = 6;
features = zeros(nDays, nModules, nFeatures);
energyDayModule = zeros(nDays, nModules);

for d = 1:nDays
    for m = 1:nModules
        x = squeeze(Pmodule(d, :, m));
        features(d, m, :) = compute_dynamic_features(x, cfg.module_rating_MW);
        energyDayModule(d, m) = sum(x); % Project profile is hourly: 24 points per day.
    end
end

featureMatrix = reshape(features, [], nFeatures);
energyAnnualModule = squeeze(sum(energyDayModule, 1))';
electricityCostEnergy = squeeze(sum(Pmodule, [1 2]))' / 4; % Preserve legacy economic objective.
hydrogen = zeros(nTopologies, nModules);
etaAnnual = zeros(nTopologies, nModules);
etaDayModule = zeros(nDays, nModules, nTopologies);

for topoIndex = 1:nTopologies
    etaVector = predict(models{topoIndex}, featureMatrix);
    etaVector = min(max(etaVector, 0), 1);
    eta = reshape(etaVector, nDays, nModules);
    etaDayModule(:, :, topoIndex) = eta;
    h2DayModule = eta .* energyDayModule / cfg.h2_lhv_MWh_per_t;
    hydrogen(topoIndex, :) = squeeze(sum(h2DayModule, 1));
    for m = 1:nModules
        if energyAnnualModule(m) > 0
            etaAnnual(topoIndex, m) = hydrogen(topoIndex, m) * cfg.h2_lhv_MWh_per_t / energyAnnualModule(m);
        else
            etaAnnual(topoIndex, m) = 0;
        end
    end
end

eval = struct();
eval.Pmodule = Pmodule;
eval.features = features;
eval.energy_day_module_MWh = energyDayModule;
eval.energy_annual_module_MWh = energyAnnualModule;
eval.electricity_cost_energy_MWh = electricityCostEnergy;
eval.hydrogen_t = hydrogen;
eval.eta_annual = etaAnnual;
eval.eta_day_module = etaDayModule;
eval.topology_ids = topologyIds;
eval.topology_labels = topologyLabels;
eval.n_days = nDays;
eval.n_steps = nSteps;
eval.n_modules = nModules;
end

function rows = append_production_rows(rows, projectId, theta, thetaCode, eval, topoIndex, topoId, topoLabel)
nModules = eval.n_modules;
newRows = nan(nModules, 9);
for m = 1:nModules
    newRows(m, :) = [projectId, theta, thetaCode, topoId, m, ...
        eval.energy_annual_module_MWh(m), eval.electricity_cost_energy_MWh(m), ...
        eval.hydrogen_t(topoIndex, m), eval.eta_annual(topoIndex, m)];
end
rows = [rows; newRows]; %#ok<AGROW>
% Keep label only in table builder; numeric rows stay compact for speed.
if strlength(topoLabel) == 0; end
end

function rows = append_feature_rows(rows, projectId, theta, thetaCode, eval)
nModules = eval.n_modules;
featureMean = squeeze(mean(eval.features, 1));
newRows = nan(nModules, 10);
for m = 1:nModules
    newRows(m, :) = [projectId, theta, thetaCode, m, featureMean(m, :)];
end
rows = [rows; newRows]; %#ok<AGROW>
end

function rows = append_theta_rows(rows, projectId, theta, thetaCode, priceEle, priceH2, nRealModules, ...
    capexCases, revenueCases, plantProfitByCost, plantH2ByCost, benchmarkAtThetaByCost, benchmarkProfit)
nRevenueCases = height(revenueCases);
nCostCases = height(capexCases) * height(revenueCases);
newRows = nan(nCostCases, 13);
for costCaseId = 1:nCostCases
    capexCaseIndex = ceil(costCaseId / nRevenueCases);
    revenueCaseIndex = costCaseId - (capexCaseIndex - 1) * nRevenueCases;
    relGainVsBenchmark = (plantProfitByCost(costCaseId) - benchmarkProfit(costCaseId)) / benchmarkProfit(costCaseId);
    relGainVsThetaBenchmark = (plantProfitByCost(costCaseId) - benchmarkAtThetaByCost(costCaseId)) / benchmarkAtThetaByCost(costCaseId);
    newRows(costCaseId, :) = [projectId, costCaseId, capexCaseIndex, revenueCaseIndex, theta, thetaCode, ...
        nRealModules, priceEle, priceH2, plantH2ByCost(costCaseId), plantProfitByCost(costCaseId), ...
        relGainVsBenchmark, relGainVsThetaBenchmark];
end
rows = [rows; newRows]; %#ok<AGROW>
end

function rows = append_summary_row(rows, projectId, costCaseId, capexCaseIndex, revenueCaseIndex, ...
    capexCases, revenueCases, theta, thetaCode, nRealModules, priceEle, priceH2, ...
    counts, optTopos, plantH2, plantProfit, benchmarkProfit, legacyPriceDiscountUsed, topologyLabels)
nTopologies = numel(counts);
nModuleCols = 10;
moduleTopo = nan(1, nModuleCols);
moduleTopo(1:numel(optTopos)) = optTopos;
relativeGain = (plantProfit - benchmarkProfit) / benchmarkProfit;
selectedM7Share = counts(end);
% Treat M6 and M7 as the same 1-in-1 family in the compactness-style score.
familyScoreVector = [0 1 2 3 4 5 5] / 5;
familyScore = counts * familyScoreVector(:);

row = [projectId, costCaseId, capexCaseIndex, revenueCaseIndex, theta, thetaCode, ...
    nRealModules, priceEle, priceH2, capexCases.capex_multiplier(capexCaseIndex), ...
    revenueCases.hydrogen_revenue_multiplier(revenueCaseIndex), legacyPriceDiscountUsed, ...
    counts(:)', moduleTopo, plantH2, plantProfit, benchmarkProfit, relativeGain, selectedM7Share, familyScore];
rows = [rows; row]; %#ok<AGROW>
if isempty(topologyLabels); end
end

function T = build_summary_table(rows, nTopologies, nModuleCols)
names = [{'project_id','cost_case_id','capex_case_id','revenue_case_id','best_theta','best_theta_code', ...
    'n_real_modules','price_ele_USD_per_kWh','price_H2_USD_per_Nm3','capex_multiplier', ...
    'hydrogen_revenue_multiplier','legacy_price_discount_state'}, ...
    compose('share_M%d', 1:nTopologies), compose('module_%02d_topology', 1:nModuleCols), ...
    {'annual_H2_t','optimal_profit_USD_per_year','benchmark_profit_USD_per_year', ...
    'relative_gain_vs_M1_theta0','selected_M7_share','family_compactness_score'}];
T = array2table(rows, 'VariableNames', names);
end

function T = build_theta_table(rows)
names = {'project_id','cost_case_id','capex_case_id','revenue_case_id','theta','theta_code', ...
    'n_real_modules','price_ele_USD_per_kWh','price_H2_USD_per_Nm3','annual_H2_t', ...
    'optimal_profit_USD_per_year','relative_gain_vs_M1_theta0','relative_gain_vs_M1_same_theta'};
T = array2table(rows, 'VariableNames', names);
end

function T = build_production_table(rows)
names = {'project_id','theta','theta_code','topology_id','module_index', ...
    'annual_energy_MWh','legacy_cost_energy_MWh','annual_H2_t','annual_efficiency_LHV'};
T = array2table(rows, 'VariableNames', names);
end

function T = build_feature_table(rows)
names = {'project_id','theta','theta_code','module_index', ...
    'mean_power_pu','low_load_duration_pu','average_absolute_ramping_pu', ...
    'high_frequency_ratio','load_std_pu','load_range_pu'};
T = array2table(rows, 'VariableNames', names);
end

function write_project_report(reportDir, summaryTable, thetaTable, capexTable, cfg, outXlsx)
reportFile = fullfile(reportDir, 'project_M1_M7_theta_dynamic_report.md');
fid = fopen(reportFile, 'w');
cleanupObj = onCleanup(@() fclose(fid));

fprintf(fid, '# Revised Project M1-M7 Theta-Rule Dynamic-Efficiency Run\n\n');
fprintf(fid, '## Scope\n\n');
fprintf(fid, '- Dispatch: legacy theta-rule (`theta = 0:0.1:1`).\n');
fprintf(fid, '- Topologies: M1-M7.\n');
fprintf(fid, '- Efficiency: revised six-feature dynamic surrogate.\n');
fprintf(fid, '- Project economics: legacy objective retained; MILP and degradation are not included in this mainline run.\n\n');

fprintf(fid, '## CAPEX Input\n\n');
fprintf(fid, '- CAPEX workbook: `data/input/topology_capex_M1_M7.xlsx`.\n');
fprintf(fid, '- M7 base CAPEX: %.0f x 1e4 USD, same as M6.\n\n', capexTable.base_capex_1e4_USD(end));

fprintf(fid, '## Time and Energy Convention\n\n');
fprintf(fid, '- Project profiles contain 8760 hourly points per project and are reshaped to `365 x 24`.\n');
fprintf(fid, '- Hydrogen production uses hourly energy (`sum(P_module)`), consistent with legacy production magnitudes.\n');
fprintf(fid, '- Electricity-cost energy keeps the legacy `/4` factor in the economic objective, so the project-side account remains comparable with the original workbook.\n\n');

fprintf(fid, '## Output Files\n\n');
fprintf(fid, '- Excel workbook: `outputs/project_M1_M7_theta_dynamic_results.xlsx`.\n');
fprintf(fid, '- Main CSV: `outputs/project_M1_M7_theta_dynamic_summary.csv`.\n');
fprintf(fid, '- Theta sweep CSV: `outputs/project_M1_M7_theta_dynamic_by_theta.csv`.\n\n');

fprintf(fid, '## Quick Checks\n\n');
fprintf(fid, '- Summary rows: %d projects/cost cases.\n', height(summaryTable));
fprintf(fid, '- Theta rows: %d project/cost/theta rows.\n', height(thetaTable));
fprintf(fid, '- Best theta range: %.1f to %.1f.\n', min(summaryTable.best_theta), max(summaryTable.best_theta));
fprintf(fid, '- M7 selected share range: %.3f to %.3f.\n', min(summaryTable.share_M7), max(summaryTable.share_M7));

if isempty(cfg); end
end
