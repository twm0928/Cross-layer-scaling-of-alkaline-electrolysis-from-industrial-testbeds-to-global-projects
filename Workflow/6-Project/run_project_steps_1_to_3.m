function run_project_steps_1_to_3()
%RUN_PROJECT_STEPS_1_TO_3 Recalculate project results in the clean order.
%
% Step 1: fresh project-economy traversal.
% Step 2: degradation-corrected project-economy traversal.
% Step 3: degradation +/-50% uncertainty traversal.

projectRoot = fileparts(mfilename('fullpath'));
logDir = fullfile(projectRoot, 'logs');
if ~exist(logDir, 'dir'); mkdir(logDir); end

stamp = string(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
diaryFile = fullfile(logDir, "project_recalc_1_to_3_" + stamp + ".log");
diary(diaryFile);
cleanupObj = onCleanup(@() diary('off'));

fprintf('Project recalculation started: %s\n', string(datetime('now')));
fprintf('Project root: %s\n\n', projectRoot);

addpath(fullfile(projectRoot, 'src'));

fprintf('[1/3] Fresh project-economy traversal...\n');
addpath(fullfile(projectRoot, '1-FreshProject', 'src'));
run_project_theta_M1_M7_dynamic_fresh();
fprintf('[1/3] Complete.\n\n');

fprintf('[2/3] Degradation-corrected project-economy traversal (scale = 1.0)...\n');
addpath(fullfile(projectRoot, '2-DegradationCorrectedProject', 'src'));
run_project_theta_M1_M7_degradation_corrected([], [], 1.0);
fprintf('[2/3] Complete.\n\n');

fprintf('[3/3] Degradation uncertainty traversal (scale = 0.5 and 1.5)...\n');
addpath(fullfile(projectRoot, '3-DegradationUncertaintyProject', 'src'));
run_degradation_uncertainty_pm50();
fprintf('[3/3] Complete.\n\n');

fprintf('Project recalculation finished: %s\n', string(datetime('now')));
fprintf('Diary: %s\n', diaryFile);
end
