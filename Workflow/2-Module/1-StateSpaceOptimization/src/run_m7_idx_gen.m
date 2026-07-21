% Recompute M7 (20 MW S3 with segmented stack flow path) for the idx_gen set.
% The output format is intentionally identical to results_topology_1..6.mat:
%   result : cell(num_scenarios, 4)
%   obj    : double(num_scenarios, 4)
%   status : double(num_scenarios, 4)

module_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
input_dir = fullfile(module_root, 'data', 'input');
result_dir = fullfile(module_root, 'data', 'results');
project_root = fileparts(fileparts(module_root));
clean_dir = fullfile(project_root, 'Clean');
if ~exist(result_dir, 'dir'); mkdir(result_dir); end
if ~exist(clean_dir, 'dir'); clean_dir = result_dir; end

% Gurobi should be configured through the MATLAB path or GRB_LICENSE_FILE.
% No machine-specific licence path is set here.

load(fullfile(input_dir, 'P_command.mat'), 'P_command');

num_scenarios = length(P_command);
num_faults = 4;
topology = 7;
fault = 4;

idx_gen = [732:2:770 771:1:830 831:5:876 881:5:926 883:5:928 ...
    931:5:976 932:5:977 933:5:978 934:5:979 981:5:1026 ...
    982:5:1027 983:5:1028 984:5:1029 1031:1080];

result = cell(num_scenarios, num_faults);
obj = zeros(num_scenarios, num_faults);
status = zeros(num_scenarios, num_faults);

out_file = fullfile(result_dir, sprintf('results_topology_%d.mat', topology));
progress_file = fullfile(clean_dir, sprintf('results_topology_%d_progress.txt', topology));
if exist(out_file, 'file')
    delete(out_file);
end
if exist(progress_file, 'file')
    delete(progress_file);
end

fid = fopen(progress_file, 'w');
fprintf(fid, 'M7 run start: %d scenarios\n', numel(idx_gen));
fclose(fid);

tic;
for kk = 1:numel(idx_gen)
    scenario = idx_gen(kk);
    Ptot_command = P_command(scenario, :)';

    [output_matrix, output_obj, output_status] = ...
        cluster_UC_I4(topology, Ptot_command, fault, []);

    result{scenario, fault} = output_matrix;
    obj(scenario, fault) = output_obj;
    status(scenario, fault) = output_status;

    save(out_file, 'result', 'obj', 'status');

    fid = fopen(progress_file, 'a');
    fprintf(fid, 'M7 progress: %d/%d, scenario=%d, status=%g, obj=%.10g, elapsed=%.1f s\n', ...
        kk, numel(idx_gen), scenario, output_status, output_obj, toc);
    fclose(fid);
end

fid = fopen(progress_file, 'a');
fprintf(fid, 'M7 run complete in %.1f s\n', toc);
fclose(fid);
