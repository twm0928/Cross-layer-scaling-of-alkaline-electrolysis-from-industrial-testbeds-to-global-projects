function publish_final_static_interface_r1()
%PUBLISH_FINAL_STATIC_INTERFACE_R1 Lock the accepted static module interface.
%
% This script freezes the current constant-power module P-H2 map and copies
% a canonical plant-facing interface into Workflow/3-Plant so that the MILP
% workflow reads one stable file in all later runs.

src_dir = fileparts(mfilename('fullpath'));
flow_root = fileparts(src_dir);
module_root = fileparts(flow_root);
workflow_root = fileparts(module_root);
project_root = fileparts(workflow_root); %#ok<NASGU>

output_dir = fullfile(flow_root, 'outputs');
final_dir = fullfile(output_dir, 'final_locked');
plant_static_dir = fullfile(workflow_root, '3-Plant', 'data', 'module_static_interface');

if ~exist(final_dir, 'dir'); mkdir(final_dir); end
if ~exist(plant_static_dir, 'dir'); mkdir(plant_static_dir); end

src_csv = fullfile(output_dir, 'Fig3a_R1_constant_power_scenarios_M1_M7.csv');
src_xlsx = fullfile(output_dir, 'Fig3a_R1_constant_power_scenarios_M1_M7.xlsx');
src_mat = fullfile(output_dir, 'Fig3a_R1_constant_power_scenarios_M1_M7.mat');

final_csv = fullfile(final_dir, 'module_static_ph_map_M1_M7_final_locked.csv');
final_xlsx = fullfile(final_dir, 'module_static_ph_map_M1_M7_final_locked.xlsx');
final_mat = fullfile(final_dir, 'module_static_ph_map_M1_M7_final_locked.mat');

copy_with_check(src_csv, final_csv);
copy_with_check(src_xlsx, final_xlsx);
copy_with_check(src_mat, final_mat);

copy_with_check(src_csv, fullfile(plant_static_dir, 'module_static_ph_map_M1_M7_final_locked.csv'));
copy_with_check(src_xlsx, fullfile(plant_static_dir, 'module_static_ph_map_M1_M7_final_locked.xlsx'));
copy_with_check(src_mat, fullfile(plant_static_dir, 'module_static_ph_map_M1_M7_final_locked.mat'));

T = readtable(src_csv, 'TextType', 'string');
scenario_table = unique(T(:, {'scenario_id', 'constant_power_MW', 'constant_power_pu'}), 'rows', 'stable');
catalog_csv = fullfile(final_dir, 'constant_power_scenario_catalog_final_locked.csv');
catalog_xlsx = fullfile(final_dir, 'constant_power_scenario_catalog_final_locked.xlsx');
writetable(scenario_table, catalog_csv);
writetable(scenario_table, catalog_xlsx);

manifest_file = fullfile(final_dir, 'manifest_static_final_locked.txt');
manifest_lines = { ...
    'R1 static module interface final-locked package'; ...
    ['Generated: ' char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'))]; ...
    'Source logic: constant-power daily scenarios extracted from accepted module dynamic results'; ...
    ''; ...
    'Locked files:'; ...
    '  module_static_ph_map_M1_M7_final_locked.csv/.xlsx/.mat'; ...
    '  constant_power_scenario_catalog_final_locked.csv/.xlsx'; ...
    ''; ...
    'Plant-side synced files:'; ...
    '  Workflow/3-Plant/data/module_static_interface/module_static_ph_map_M1_M7_final_locked.csv/.xlsx/.mat'; ...
    ''; ...
    'Purpose:'; ...
    '  1) freeze the accepted static MILP interface'; ...
    '  2) provide one stable file for both theta and MILP plant workflows'; ...
    };
write_text_lines(manifest_file, manifest_lines);

fprintf('Static final-locked package created at:\n  %s\n', final_dir);
fprintf('Plant MILP interface synced to:\n  %s\n', plant_static_dir);
end

function copy_with_check(src, dst)
if ~isfile(src)
    error('Missing source file: %s', src);
end
[ok, msg] = copyfile(src, dst, 'f');
if ~ok
    error('Failed to copy %s -> %s\n%s', src, dst, msg);
end
end

function write_text_lines(filename, lines)
fid = fopen(filename, 'w');
if fid < 0
    error('Failed to open text file for writing: %s', filename);
end
cleanup = onCleanup(@() fclose(fid));
for i = 1:numel(lines)
    fprintf(fid, '%s\n', lines{i});
end
end
