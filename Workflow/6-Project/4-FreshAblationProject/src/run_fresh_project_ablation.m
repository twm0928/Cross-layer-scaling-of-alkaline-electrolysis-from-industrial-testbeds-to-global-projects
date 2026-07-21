function run_fresh_project_ablation()
%RUN_FRESH_PROJECT_ABLATION Derive fresh project-side ablation cases.
%
% This post-processing script uses the already validated fresh theta sweep:
%   1) baseline: M1 with theta = 0
%   2) scheduling-only: M1 with theta optimized
%   3) topology-only: M1-M7 optimized at theta = 0
%   4) joint optimization: M1-M7 and theta optimized
%
% No degradation correction is included here.

clc;

thisFile = mfilename('fullpath');
branchRoot = fileparts(fileparts(thisFile));
projectRoot = fileparts(branchRoot);
workflowRoot = fileparts(projectRoot);
repoRoot = fileparts(workflowRoot);
freshOutputDir = fullfile(projectRoot, '1-FreshProject', 'outputs');
outputDir = fullfile(branchRoot, 'outputs');
reportDir = fullfile(branchRoot, 'report');

if ~exist(outputDir, 'dir'), mkdir(outputDir); end
if ~exist(reportDir, 'dir'), mkdir(reportDir); end

summaryFile = fullfile(freshOutputDir, 'project_M1_M7_theta_dynamic_summary.csv');
thetaFile = fullfile(freshOutputDir, 'project_M1_M7_theta_dynamic_by_theta.csv');
assert(isfile(summaryFile), 'Missing fresh summary: %s', summaryFile);
assert(isfile(thetaFile), 'Missing fresh theta sweep: %s', thetaFile);

summary = readtable(summaryFile);
thetaSweep = readtable(thetaFile);

% The theta sweep stores joint topology-optimized profit and its relative
% gain against M1 at the same theta. Therefore M1-only profit can be
% reconstructed without re-running the project model.
thetaSweep.M1_same_theta_profit_USD_per_year = thetaSweep.optimal_profit_USD_per_year ./ ...
    (1 + thetaSweep.relative_gain_vs_M1_same_theta);

meta = project_metadata(repoRoot);

rows = {};
for i = 1:height(summary)
    projectId = summary.project_id(i);
    costCaseId = summary.cost_case_id(i);
    idx = thetaSweep.project_id == projectId & thetaSweep.cost_case_id == costCaseId;
    block = thetaSweep(idx, :);
    assert(~isempty(block), 'No theta sweep rows for project %d cost case %d.', projectId, costCaseId);

    baselineProfit = summary.benchmark_profit_USD_per_year(i);

    [schedulingOnlyProfit, kSched] = max(block.M1_same_theta_profit_USD_per_year);
    schedulingOnlyTheta = block.theta(kSched);

    idxTheta0 = abs(block.theta) < 1e-12;
    assert(nnz(idxTheta0) == 1, 'Expected one theta=0 row for project %d cost case %d.', projectId, costCaseId);
    topologyOnlyProfit = block.optimal_profit_USD_per_year(idxTheta0);

    jointProfit = summary.optimal_profit_USD_per_year(i);
    jointTheta = summary.best_theta(i);

    gainSched = schedulingOnlyProfit - baselineProfit;
    gainTopo = topologyOnlyProfit - baselineProfit;
    gainJoint = jointProfit - baselineProfit;
    bestSingleGain = max(gainSched, gainTopo);
    coupledAdvantage = gainJoint - bestSingleGain;
    synergy = gainJoint - gainSched - gainTopo;

    baselineDen = max(abs(baselineProfit), eps);
    m = meta(meta.project_id == projectId, :);

    rows(end + 1, :) = {projectId, costCaseId, summary.capex_case_id(i), summary.revenue_case_id(i), ...
        string(m.resource_group), string(m.region), string(m.country), ...
        summary.capex_multiplier(i), summary.hydrogen_revenue_multiplier(i), ...
        baselineProfit, schedulingOnlyProfit, topologyOnlyProfit, jointProfit, ...
        schedulingOnlyTheta, jointTheta, ...
        gainSched, gainTopo, gainJoint, coupledAdvantage, synergy, ...
        100 * gainSched / baselineDen, 100 * gainTopo / baselineDen, 100 * gainJoint / baselineDen, ...
        100 * coupledAdvantage / baselineDen, 100 * synergy / baselineDen}; %#ok<AGROW>
end

ablation = cell2table(rows, 'VariableNames', { ...
    'project_id', 'cost_case_id', 'capex_case_id', 'revenue_case_id', ...
    'resource_group', 'region', 'country', 'capex_multiplier', 'hydrogen_revenue_multiplier', ...
    'baseline_profit_USD_per_year', 'scheduling_only_profit_USD_per_year', ...
    'topology_only_profit_USD_per_year', 'joint_profit_USD_per_year', ...
    'scheduling_only_best_theta', 'joint_best_theta', ...
    'scheduling_only_gain_USD_per_year', 'topology_only_gain_USD_per_year', ...
    'joint_gain_USD_per_year', 'joint_advantage_over_best_single_USD_per_year', ...
    'synergy_USD_per_year', 'scheduling_only_gain_pct', 'topology_only_gain_pct', ...
    'joint_gain_pct', 'joint_advantage_over_best_single_pct', 'synergy_pct'});

projectMean = groupsummary(ablation, {'project_id', 'resource_group', 'region', 'country'}, 'mean', ...
    {'scheduling_only_gain_pct', 'topology_only_gain_pct', 'joint_gain_pct', ...
    'joint_advantage_over_best_single_pct', 'synergy_pct', ...
    'scheduling_only_best_theta', 'joint_best_theta'});

grouped = groupsummary(ablation, {'resource_group', 'region', 'cost_case_id'}, 'mean', ...
    {'scheduling_only_gain_pct', 'topology_only_gain_pct', 'joint_gain_pct', ...
    'joint_advantage_over_best_single_pct', 'synergy_pct', ...
    'scheduling_only_best_theta', 'joint_best_theta'});

writetable(ablation, fullfile(outputDir, 'fresh_project_ablation_by_project_case.csv'));
writetable(projectMean, fullfile(outputDir, 'fresh_project_ablation_by_project_mean.csv'));
writetable(grouped, fullfile(outputDir, 'fresh_project_ablation_by_group_cost_case.csv'));

write_report(reportDir, ablation, projectMean, grouped, summaryFile, thetaFile);

fprintf('Fresh project ablation completed.\n');
fprintf('Project-case rows: %d\n', height(ablation));
fprintf('Output folder: %s\n', outputDir);
end

function meta = project_metadata(repoRoot)
mappingFile = fullfile(repoRoot, 'Figure', 'Figure 5a', 'data', ...
    'Fig5a_project_matrix_style_project_group_mapping.csv');
assert(isfile(mappingFile), 'Missing project mapping: %s', mappingFile);
mapping = readtable(mappingFile);
meta = mapping(:, {'project_id', 'resource_group', 'region'});
meta.country = strings(height(meta), 1);

inputFile = fullfile(repoRoot, 'Workflow', '6-Project', 'data', 'input', 'ProjectInfo.xlsx');
if isfile(inputFile)
    info = readcell(inputFile, 'Sheet', 'Sheet1');
    for i = 1:height(meta)
        pid = meta.project_id(i);
        if pid + 1 <= size(info, 1)
            value = info{pid + 1, 2};
            if ischar(value) || isstring(value)
                meta.country(i) = string(value);
            end
        end
    end
end
end

function write_report(reportDir, ablation, projectMean, grouped, summaryFile, thetaFile)
reportFile = fullfile(reportDir, 'fresh_project_ablation_report.md');
fid = fopen(reportFile, 'w');
assert(fid > 0, 'Cannot write report: %s', reportFile);
c = onCleanup(@() fclose(fid));

fprintf(fid, '# Fresh project-side ablation for Fig. 5b\n\n');
fprintf(fid, '## Scope\n\n');
fprintf(fid, 'This run uses fresh project economics only. Degradation correction and degradation uncertainty are intentionally excluded.\n\n');
fprintf(fid, '## Inputs\n\n');
if isempty(summaryFile) || isempty(thetaFile); end
fprintf(fid, '- Fresh summary: `../1-FreshProject/outputs/project_M1_M7_theta_dynamic_summary.csv`\n');
fprintf(fid, '- Fresh theta sweep: `../1-FreshProject/outputs/project_M1_M7_theta_dynamic_by_theta.csv`\n\n');
fprintf(fid, '## Definitions\n\n');
fprintf(fid, '- Baseline: M1 topology with theta = 0.\n');
fprintf(fid, '- Scheduling-only: M1 topology with theta swept over 0:0.1:1.\n');
fprintf(fid, '- Topology-only: M1-M7 topology optimized at theta = 0.\n');
fprintf(fid, '- Joint optimization: M1-M7 topology and theta jointly optimized.\n\n');
fprintf(fid, 'The M1-only profit at each theta is reconstructed from the stored theta sweep as:\n\n');
fprintf(fid, '`P_M1(theta) = P_joint_at_theta / (1 + gain_vs_M1_same_theta)`.\n\n');
fprintf(fid, '## Output tables\n\n');
fprintf(fid, '- `fresh_project_ablation_by_project_case.csv`: 96 rows, one per project and economic scenario.\n');
fprintf(fid, '- `fresh_project_ablation_by_project_mean.csv`: project-level means across four economic scenarios.\n');
fprintf(fid, '- `fresh_project_ablation_by_group_cost_case.csv`: grouped means for Fig. 5-style region/source categories.\n\n');
fprintf(fid, '## Quick numeric summary\n\n');
fprintf(fid, '- Project-case rows: %d\n', height(ablation));
fprintf(fid, '- Mean scheduling-only gain: %.4g%%\n', mean(ablation.scheduling_only_gain_pct, 'omitnan'));
fprintf(fid, '- Mean topology-only gain: %.4g%%\n', mean(ablation.topology_only_gain_pct, 'omitnan'));
fprintf(fid, '- Mean joint gain: %.4g%%\n', mean(ablation.joint_gain_pct, 'omitnan'));
fprintf(fid, '- Mean joint advantage over best single lever: %.4g%%\n', mean(ablation.joint_advantage_over_best_single_pct, 'omitnan'));
fprintf(fid, '- Mean strict synergy: %.4g%%\n', mean(ablation.synergy_pct, 'omitnan'));
fprintf(fid, '\n## Notes\n\n');
fprintf(fid, 'A positive joint advantage means the jointly optimized strategy is better than either scheduling-only or topology-only optimization. A positive strict synergy means the joint gain exceeds the arithmetic sum of the two single-lever gains.\n');
if isempty(projectMean) || isempty(grouped); end
end
