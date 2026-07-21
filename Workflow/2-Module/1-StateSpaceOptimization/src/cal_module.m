module_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
input_dir = fullfile(module_root, 'data', 'input');
result_dir = fullfile(module_root, 'data');
load(fullfile(input_dir, 'P_command.mat'));
% load fault_scenarios_data.mat

% 初始化
num_topologies = 7; % M7 is segmented S3 under the same BOP architecture as M6.
num_scenarios = length(P_command);
num_faults = 4; % 1-电路；2-液路；3-温路；4-无故障
save_interval = 1; % 保存间隔
idx_gen=[732:2:770 771:1:830 831:5:876 881:5:926 883:5:928 931:5:976 932:5:977 933:5:978 934:5:979 981:5:1026 982:5:1027 983:5:1028 984:5:1029 1031:1080];

parfor topology = 1:num_topologies
    temp_result = cell(num_scenarios, num_faults);
    temp_obj = zeros(num_scenarios, num_faults);
    temp_status = zeros(num_scenarios, num_faults);

    for fault = 4 %1:num_faults
        % 为当前拓扑创建临时存储       
        counter=0;
        for scenario = idx_gen  % 1:num_scenarios
            Ptot_command = P_command(scenario, :)';
            if fault < 4
%                 fault_command = all_scenarios{topology,fault}(scenario, :, :);
            else
                fault_command=[];
            end
            [output_matrix, output_obj, output_status] = cluster_UC_I4(topology, Ptot_command, fault, fault_command);

            temp_result{scenario,fault} = output_matrix;
            temp_obj(scenario,fault) = output_obj;
            temp_status(scenario,fault) = output_status;

            % 更新计数器
            counter=counter+1;

            % 定期保存
            if mod(counter, save_interval) == 0
                % 创建临时结构体保存当前拓扑的结果
                s = struct();
                s.result = temp_result;
                s.obj = temp_obj;
                s.status = temp_status;

                % 使用不同的临时文件名避免冲突
                temp_file = fullfile(result_dir, sprintf('results_topology_%d.mat', topology));
                save(temp_file, '-fromstruct', s);
            end
        end
    end
end
