function summary = run_module_first730_parfor(topology_ids, scenario_ids, solver_options, run_options)
%RUN_MODULE_FIRST730_PARFOR Recompute module dynamics with task-level parfor.
%
% Default run:
%   M1-M7, scenarios 1:730, fault = 4 (normal operation).
%
% The runner writes one temporary MAT file per (topology, scenario) task
% under Clean, then merges the completed tasks into the shared result files:
%   Workflow/2-Module/data/results/results_topology_*.mat
%
% Existing scenarios outside scenario_ids are preserved during merging.

src_dir = fileparts(mfilename('fullpath'));
state_space_dir = fileparts(src_dir);
module_root = fileparts(state_space_dir);
project_root = fileparts(fileparts(module_root));

input_dir = fullfile(module_root, 'data', 'input');
result_dir = fullfile(module_root, 'data', 'results');
clean_dir = fullfile(project_root, 'Clean');
temp_dir = fullfile(clean_dir, 'module_first730_parfor_tmp');
backup_dir = fullfile(clean_dir, ['module_first730_backup_' datestr(now, 'yyyymmdd_HHMMSS')]);
progress_file = fullfile(clean_dir, 'module_first730_parfor_progress.txt');
summary_file = fullfile(clean_dir, 'module_first730_parfor_summary.csv');
config_file = fullfile(clean_dir, 'module_first730_parfor_config.mat');

if nargin < 1 || isempty(topology_ids)
    topology_ids = 1:7;
end
if nargin < 2 || isempty(scenario_ids)
    scenario_ids = 1:730;
end
if nargin < 3 || isempty(solver_options)
    solver_options = struct();
end
if nargin < 4 || isempty(run_options)
    run_options = struct();
end

topology_ids = topology_ids(:)';
scenario_ids = scenario_ids(:)';
solver_options = set_default(solver_options, 'MIPGap', 0.01);
solver_options = set_default(solver_options, 'TimeLimit', 240);
solver_options = set_default(solver_options, 'Threads', 1);
solver_options = set_default(solver_options, 'ShowProgress', 0);

run_options = set_default(run_options, 'NumWorkers', []);
run_options = set_default(run_options, 'Force', false);
run_options = set_default(run_options, 'MergeAfter', true);
run_options = set_default(run_options, 'BackupExisting', true);
run_options = set_default(run_options, 'ProgressEvery', 1);
run_options = set_default(run_options, 'SkipLicenseCheck', false);
run_options = set_default(run_options, 'LicenseFile', '');

if ~exist(result_dir, 'dir')
    mkdir(result_dir);
end
if ~exist(clean_dir, 'dir')
    mkdir(clean_dir);
end
if ~exist(temp_dir, 'dir')
    mkdir(temp_dir);
end

addpath(src_dir);

load(fullfile(input_dir, 'P_command.mat'), 'P_command');
num_scenarios = size(P_command, 1);
num_faults = 4;
fault = 4;

validate_requested_indices(topology_ids, scenario_ids, num_scenarios);

if ~isempty(run_options.LicenseFile)
    setenv('GRB_LICENSE_FILE', run_options.LicenseFile);
end

if ~run_options.SkipLicenseCheck
    check_gurobi();
end

save(config_file, 'topology_ids', 'scenario_ids', 'solver_options', ...
    'run_options', 'input_dir', 'result_dir', 'temp_dir', 'backup_dir');

pool = gcp('nocreate');
if isempty(pool)
    if isempty(run_options.NumWorkers)
        pool = parpool('local');
    else
        pool = parpool('local', run_options.NumWorkers);
    end
end
pctRunOnAll(['addpath(''' strrep(src_dir, '''', '''''') ''')']);

[topology_grid, scenario_grid] = ndgrid(topology_ids, scenario_ids);
task_topology = topology_grid(:);
task_scenario = scenario_grid(:);
num_tasks = numel(task_topology);
force_run = run_options.Force;
P_command_const = parallel.pool.Constant(P_command);

write_progress_header(progress_file, topology_ids, scenario_ids, solver_options, run_options, pool.NumWorkers);

progress_counter = 0;
run_timer = tic;
q = parallel.pool.DataQueue;
afterEach(q, @update_progress);

parfor task_idx = 1:num_tasks
    topology = task_topology(task_idx);
    scenario = task_scenario(task_idx);
    temp_file = task_file_name(temp_dir, topology, scenario, fault);

    if exist(temp_file, 'file') && ~force_run
        msg = struct('Topology', topology, 'Scenario', scenario, ...
            'Status', NaN, 'Objective', NaN, 'Runtime', 0, ...
            'Skipped', true, 'ErrorMessage', '');
        send(q, msg);
        continue;
    end

    task_timer = tic;

    try
        Ptot_command = P_command_const.Value(scenario, :)';
        [output_matrix, output_obj, output_status] = ...
            cluster_UC_I4(topology, Ptot_command, fault, [], solver_options);
        error_message = '';
    catch ME
        output_status = -999;
        output_obj = NaN;
        output_matrix = [];
        error_message = getReport(ME, 'extended', 'hyperlinks', 'off');
    end

    runtime_s = toc(task_timer);
    task_result = struct();
    task_result.topology = topology;
    task_result.scenario = scenario;
    task_result.fault = fault;
    task_result.output_matrix = output_matrix;
    task_result.output_obj = output_obj;
    task_result.output_status = output_status;
    task_result.runtime_s = runtime_s;
    task_result.error_message = error_message;
    task_result.solver_options = solver_options;

    save_task_result(temp_file, task_result);

    msg = struct('Topology', topology, 'Scenario', scenario, ...
        'Status', output_status, 'Objective', output_obj, ...
        'Runtime', runtime_s, 'Skipped', false, ...
        'ErrorMessage', error_message);
    send(q, msg);
end

if run_options.MergeAfter
    summary = merge_temp_results(topology_ids, scenario_ids, fault, ...
        num_scenarios, num_faults, result_dir, temp_dir, backup_dir, ...
        run_options.BackupExisting, summary_file);
else
    summary = table();
end

    function update_progress(msg)
        progress_counter = progress_counter + 1;
        if mod(progress_counter, run_options.ProgressEvery) ~= 0 && progress_counter ~= num_tasks
            return;
        end
        elapsed_s = toc(run_timer);
        fid = fopen(progress_file, 'a');
        fprintf(fid, ['progress %d/%d | topology=%d | scenario=%d | ', ...
            'status=%g | obj=%.10g | runtime=%.1f s | elapsed=%.1f s | skipped=%d\n'], ...
            progress_counter, num_tasks, msg.Topology, msg.Scenario, ...
            msg.Status, msg.Objective, msg.Runtime, elapsed_s, msg.Skipped);
        if ~isempty(msg.ErrorMessage)
            fprintf(fid, 'error topology=%d scenario=%d:\n%s\n', ...
                msg.Topology, msg.Scenario, msg.ErrorMessage);
        end
        fclose(fid);
    end
end

function save_task_result(temp_file, task_result)
save(temp_file, 'task_result');
end

function options = set_default(options, field_name, default_value)
if ~isfield(options, field_name) || isempty(options.(field_name))
    options.(field_name) = default_value;
end
end

function validate_requested_indices(topology_ids, scenario_ids, num_scenarios)
if any(topology_ids < 1) || any(topology_ids > 7) || any(mod(topology_ids, 1) ~= 0)
    error('Topology IDs must be integers from 1 to 7.');
end
if any(scenario_ids < 1) || any(scenario_ids > num_scenarios) || any(mod(scenario_ids, 1) ~= 0)
    error('Scenario IDs must be integers from 1 to %d.', num_scenarios);
end
end

function check_gurobi()
gurobi_path = which('gurobi');
if isempty(gurobi_path)
    error('Gurobi MATLAB interface is not on the MATLAB path.');
end

model.A = sparse(1, 1);
model.obj = 1;
model.rhs = 1;
model.sense = '<';
model.lb = 0;
model.ub = 1;
model.modelsense = 'max';
params.OutputFlag = 0;

try
    gurobi(model, params);
catch ME
    license_file = getenv('GRB_LICENSE_FILE');
    error(['Gurobi licence check failed before launching parfor.\n', ...
        'MATLAB gurobi path: %s\nGRB_LICENSE_FILE: %s\nOriginal error: %s'], ...
        gurobi_path, license_file, ME.message);
end
end

function write_progress_header(progress_file, topology_ids, scenario_ids, solver_options, run_options, num_workers)
fid = fopen(progress_file, 'w');
fprintf(fid, 'Module first-730 parfor run\n');
fprintf(fid, 'Start time: %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fprintf(fid, 'Topologies: %s\n', mat2str(topology_ids));
fprintf(fid, 'Scenarios: %s\n', compact_index_description(scenario_ids));
fprintf(fid, 'Workers: %d\n', num_workers);
fprintf(fid, 'Solver: Gurobi, MIPGap=%g, TimeLimit=%g, Threads=%g, ShowProgress=%g\n', ...
    solver_options.MIPGap, solver_options.TimeLimit, solver_options.Threads, solver_options.ShowProgress);
fprintf(fid, 'Force=%d, MergeAfter=%d, BackupExisting=%d\n', ...
    run_options.Force, run_options.MergeAfter, run_options.BackupExisting);
if ~isempty(run_options.LicenseFile)
    fprintf(fid, 'GRB_LICENSE_FILE=%s\n', run_options.LicenseFile);
end
fclose(fid);
end

function text = compact_index_description(indices)
if isempty(indices)
    text = '[]';
elseif isequal(indices, indices(1):indices(end))
    text = sprintf('%d:%d', indices(1), indices(end));
else
    text = mat2str(indices);
end
end

function temp_file = task_file_name(temp_dir, topology, scenario, fault)
temp_file = fullfile(temp_dir, sprintf('task_topo%02d_scen%04d_fault%02d.mat', ...
    topology, scenario, fault));
end

function summary = merge_temp_results(topology_ids, scenario_ids, fault, num_scenarios, ...
    num_faults, result_dir, temp_dir, backup_dir, backup_existing, summary_file)

if backup_existing && ~exist(backup_dir, 'dir')
    mkdir(backup_dir);
end

Topology = zeros(numel(topology_ids), 1);
ScenarioCount = zeros(numel(topology_ids), 1);
TempFilesFound = zeros(numel(topology_ids), 1);
MissingTempFiles = zeros(numel(topology_ids), 1);
Status0 = zeros(numel(topology_ids), 1);
Status3 = zeros(numel(topology_ids), 1);
FailedStatus = zeros(numel(topology_ids), 1);
OutputFile = cell(numel(topology_ids), 1);

for idx = 1:numel(topology_ids)
    topology = topology_ids(idx);
    out_file = fullfile(result_dir, sprintf('results_topology_%d.mat', topology));
    [result, obj, status] = load_or_initialise_result(out_file, num_scenarios, num_faults);

    if backup_existing && exist(out_file, 'file')
        copyfile(out_file, fullfile(backup_dir, sprintf('results_topology_%d.mat', topology)));
    end

    found_count = 0;
    missing_count = 0;
    status0_count = 0;
    status3_count = 0;
    failed_count = 0;

    for scenario = scenario_ids
        temp_file = task_file_name(temp_dir, topology, scenario, fault);
        if ~exist(temp_file, 'file')
            missing_count = missing_count + 1;
            continue;
        end

        loaded = load(temp_file, 'task_result');
        task_result = loaded.task_result;
        result{scenario, fault} = task_result.output_matrix;
        obj(scenario, fault) = task_result.output_obj;
        status(scenario, fault) = task_result.output_status;

        found_count = found_count + 1;
        if task_result.output_status == 0
            status0_count = status0_count + 1;
        elseif task_result.output_status == 3
            status3_count = status3_count + 1;
        else
            failed_count = failed_count + 1;
        end
    end

    save(out_file, 'result', 'obj', 'status');

    Topology(idx) = topology;
    ScenarioCount(idx) = numel(scenario_ids);
    TempFilesFound(idx) = found_count;
    MissingTempFiles(idx) = missing_count;
    Status0(idx) = status0_count;
    Status3(idx) = status3_count;
    FailedStatus(idx) = failed_count;
    OutputFile{idx} = out_file;
end

summary = table(Topology, ScenarioCount, TempFilesFound, MissingTempFiles, ...
    Status0, Status3, FailedStatus, OutputFile);
writetable(summary, summary_file);
end

function [result, obj, status] = load_or_initialise_result(out_file, num_scenarios, num_faults)
result = cell(num_scenarios, num_faults);
obj = zeros(num_scenarios, num_faults);
status = zeros(num_scenarios, num_faults);

if ~exist(out_file, 'file')
    return;
end

loaded = load(out_file);
if isfield(loaded, 'result')
    old_result = loaded.result;
    row_count = min(size(old_result, 1), num_scenarios);
    col_count = min(size(old_result, 2), num_faults);
    result(1:row_count, 1:col_count) = old_result(1:row_count, 1:col_count);
end
if isfield(loaded, 'obj')
    old_obj = loaded.obj;
    row_count = min(size(old_obj, 1), num_scenarios);
    col_count = min(size(old_obj, 2), num_faults);
    obj(1:row_count, 1:col_count) = old_obj(1:row_count, 1:col_count);
end
if isfield(loaded, 'status')
    old_status = loaded.status;
    row_count = min(size(old_status, 1), num_scenarios);
    col_count = min(size(old_status, 2), num_faults);
    status(1:row_count, 1:col_count) = old_status(1:row_count, 1:col_count);
end
end
