function [projectData, profileData, inputCheck] = read_project_inputs_current(projectInfoFile, profileFile, cfg)
%READ_PROJECT_INPUTS_CURRENT Read and validate the current Figure 5 inputs.
%
% The project economic scripts keep the legacy 9-column project-data layout:
% [capacity, n20MW, n10MW, projectType, gridPrice, windCapex, solarCapex,
%  windFLH, solarFLH].

infoRaw = readmatrix(projectInfoFile, 'Sheet', 'Sheet1');
infoRaw = infoRaw(~isnan(infoRaw(:, 1)), :);
assert(size(infoRaw, 1) >= cfg.num_project, ...
    'ProjectInfo.xlsx has %d numeric project rows, expected at least %d.', ...
    size(infoRaw, 1), cfg.num_project);
infoRaw = infoRaw(1:cfg.num_project, :);

profileRaw = readmatrix(profileFile, 'Sheet', 'WS24');
profileRaw = profileRaw(~all(isnan(profileRaw), 2), :);
assert(size(profileRaw, 1) >= cfg.num_project, ...
    'Project profiles.xlsx has %d numeric project rows, expected at least %d.', ...
    size(profileRaw, 1), cfg.num_project);
profileRaw = profileRaw(1:cfg.num_project, :);

projectNo = infoRaw(:, 1);
profileNo = profileRaw(:, 1);
expectedNo = (1:cfg.num_project)';
assert(isequal(projectNo, expectedNo), 'ProjectInfo project order must be 1:24.');
assert(isequal(profileNo, expectedNo), 'Project profile order must be 1:24.');

projectData = [infoRaw(:, 7:9), infoRaw(:, 11:16)];
profileData = profileRaw(:, 3:end);
assert(size(profileData, 2) == 8760, ...
    'Project profiles.xlsx must contain 8760 hourly points, got %d.', size(profileData, 2));

profileFLH = profileRaw(:, 2);
infoFLH = nan(cfg.num_project, 1);
isWind = projectData(:, 4) == 2;
isSolar = projectData(:, 4) == 3;
infoFLH(isWind) = projectData(isWind, 8);
infoFLH(isSolar) = projectData(isSolar, 9);
assert(all(~isnan(infoFLH)), 'Project type must be 2 (wind) or 3 (solar) for all 24 projects.');

flhMismatch = max(abs(infoFLH - profileFLH));
assert(flhMismatch < 1e-6, ...
    'ProjectInfo/profile FLH mismatch is %.6g h. Check row ordering before recalculation.', ...
    flhMismatch);

inputCheck = table(projectNo, projectData(:, 4), infoFLH, profileFLH, ...
    abs(infoFLH - profileFLH), ...
    'VariableNames', {'project_id', 'project_type', 'info_FLH', 'profile_FLH', 'abs_FLH_mismatch'});
end
