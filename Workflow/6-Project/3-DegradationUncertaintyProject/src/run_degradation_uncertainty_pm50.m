function run_degradation_uncertainty_pm50()
%RUN_DEGRADATION_UNCERTAINTY_PM50 Run degradation +/-50% uncertainty cases.

thisFile = mfilename('fullpath');
branchRoot = fileparts(fileparts(thisFile));
projectRoot = fileparts(branchRoot);
degradationBranchRoot = fullfile(projectRoot, '2-DegradationCorrectedProject');
degradationSrc = fullfile(degradationBranchRoot, 'src');
degradationOutputDir = fullfile(degradationBranchRoot, 'outputs');
outputDir = fullfile(branchRoot, 'outputs');
reportDir = fullfile(branchRoot, 'report');

if ~exist(outputDir, 'dir'); mkdir(outputDir); end
if ~exist(reportDir, 'dir'); mkdir(reportDir); end
addpath(degradationSrc);

scales = [0.5, 1.5];
allSummary = table();
allTheta = table();

for k = 1:numel(scales)
    scale = scales(k);
    suffix = sprintf('degscale_%03d', round(scale * 100));
    fprintf('Running degradation uncertainty scale %.2f...\n', scale);
    run_project_theta_M1_M7_degradation_corrected([], [], scale);

    baseStem = "project_M1_M7_theta_dynamic_degradation_corrected_" + suffix;
    srcSummary = fullfile(degradationOutputDir, baseStem + "_summary.csv");
    srcTheta = fullfile(degradationOutputDir, baseStem + "_by_theta.csv");
    srcXlsx = fullfile(degradationOutputDir, baseStem + "_results.xlsx");
    srcMat = fullfile(degradationOutputDir, baseStem + "_results.mat");

    assert(isfile(srcSummary), 'Missing uncertainty summary: %s', srcSummary);
    assert(isfile(srcTheta), 'Missing uncertainty theta table: %s', srcTheta);

    dstStem = "uncertainty_" + suffix;
    copyfile(srcSummary, fullfile(outputDir, dstStem + "_summary.csv"));
    copyfile(srcTheta, fullfile(outputDir, dstStem + "_by_theta.csv"));
    if isfile(srcXlsx); copyfile(srcXlsx, fullfile(outputDir, dstStem + "_results.xlsx")); end
    if isfile(srcMat); copyfile(srcMat, fullfile(outputDir, dstStem + "_results.mat")); end

    Tsummary = readtable(srcSummary);
    Ttheta = readtable(srcTheta);
    Tsummary.uncertainty_scale = repmat(scale, height(Tsummary), 1);
    Ttheta.uncertainty_scale = repmat(scale, height(Ttheta), 1);
    allSummary = [allSummary; Tsummary]; %#ok<AGROW>
    allTheta = [allTheta; Ttheta]; %#ok<AGROW>
end

writetable(allSummary, fullfile(outputDir, 'degradation_uncertainty_pm50_all_summary.csv'));
writetable(allTheta, fullfile(outputDir, 'degradation_uncertainty_pm50_all_theta.csv'));

robustness = build_robustness_summary(allSummary);
writetable(robustness, fullfile(outputDir, 'degradation_uncertainty_pm50_robustness_summary.csv'));
write_uncertainty_report(reportDir, scales, allSummary, robustness);
end

function robustness = build_robustness_summary(allSummary)
[G, projectId, costCaseId] = findgroups(allSummary.project_id, allSummary.cost_case_id);

bestThetaMin = splitapply(@min, allSummary.best_theta, G);
bestThetaMax = splitapply(@max, allSummary.best_theta, G);
profitMin = splitapply(@min, allSummary.optimal_profit_USD_per_year, G);
profitMax = splitapply(@max, allSummary.optimal_profit_USD_per_year, G);
improvementMin = splitapply(@min, allSummary.relative_gain_vs_M1_theta0, G);
improvementMax = splitapply(@max, allSummary.relative_gain_vs_M1_theta0, G);

robustness = table(projectId, costCaseId, bestThetaMin, bestThetaMax, ...
    profitMin, profitMax, improvementMin, improvementMax, ...
    'VariableNames', {'project_id', 'cost_case_id', 'best_theta_min', ...
    'best_theta_max', 'best_profit_USD_min', 'best_profit_USD_max', ...
    'improvement_ratio_min', 'improvement_ratio_max'});
end

function write_uncertainty_report(reportDir, scales, allSummary, robustness)
reportFile = fullfile(reportDir, 'degradation_uncertainty_pm50_report.md');
fid = fopen(reportFile, 'w');
assert(fid > 0, 'Cannot write report: %s', reportFile);
cleaner = onCleanup(@() fclose(fid));

fprintf(fid, '# Degradation uncertainty project run\n\n');
fprintf(fid, '## Scope\n\n');
fprintf(fid, '- Degradation voltage increment scale factors: %.2f and %.2f.\n', scales(1), scales(2));
fprintf(fid, '- Base calculation: `2-DegradationCorrectedProject/src/run_project_theta_M1_M7_degradation_corrected.m`.\n');
fprintf(fid, '- Outputs are copied and summarized in this uncertainty branch.\n\n');
fprintf(fid, '## Output tables\n\n');
fprintf(fid, '- `outputs/uncertainty_degscale_050_*`.\n');
fprintf(fid, '- `outputs/uncertainty_degscale_150_*`.\n');
fprintf(fid, '- `outputs/degradation_uncertainty_pm50_all_summary.csv`.\n');
fprintf(fid, '- `outputs/degradation_uncertainty_pm50_robustness_summary.csv`.\n\n');
fprintf(fid, '## Quick audit\n\n');
fprintf(fid, '- Summary rows: %d.\n', height(allSummary));
fprintf(fid, '- Robustness rows: %d.\n', height(robustness));
fprintf(fid, '- Best theta range under uncertainty: %.1f to %.1f.\n', ...
    min(allSummary.best_theta), max(allSummary.best_theta));
fprintf(fid, '- Improvement range under uncertainty: %.4f to %.4f.\n', ...
    min(allSummary.relative_gain_vs_M1_theta0), max(allSummary.relative_gain_vs_M1_theta0));
end
