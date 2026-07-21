function dataset = build_dynamic_training_dataset(scenario_ids)
%BUILD_DYNAMIC_TRAINING_DATASET Build dynamic surrogate training data.
%   DATASET = BUILD_DYNAMIC_TRAINING_DATASET(SCENARIO_IDS) reads the
%   module optimisation results for M1-M7 and returns a unified dataset
%   for dynamic-efficiency surrogate training.
%
%   R1 note:
%   The optimiser stores a relaxed stack power variable P_st. In a small
%   number of dynamic cases, especially near low-current corners, P_st can
%   be inconsistent with the saved current-voltage states. To prevent such
%   cases from generating artificial low-efficiency outliers, the dynamic
%   efficiency used here is reconstructed on a physical power basis:
%
%       P_real = N_cell * I_st * U_cell / 1e6
%
%   The original relaxed-energy values are retained as diagnostics so that
%   scenario-level anomalies can still be traced afterwards.
%
%   Final R1 scope note:
%   after the physical-power reconstruction, two isolated retained
%   topology-scenario anomalies (M2-357 and M3-346) are explicitly
%   excluded from the accepted training / envelope dataset so that the
%   surrogate, Fig. 3a, and downstream plant interface share one scope.

if nargin < 1 || isempty(scenario_ids)
    scenario_ids = 1:730;
end

module_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
input_dir = fullfile(module_root, 'data', 'input');
result_dir = fullfile(module_root, 'data', 'results');
topology_file = fullfile(input_dir, 'topology.xlsx');

load(fullfile(input_dir, 'P_command.mat'), 'P_command');

scenario_ids = scenario_ids(:)';
num_selected = numel(scenario_ids);
num_topologies = 7;
fault_id = 4;
delta_t_h = 0.25;
module_rating_mw = 20;
topology_labels = compose("M%d", 1:num_topologies);
topology_groups = {'S1', 'S1', 'S1', 'S2', 'S2', 'S3', 'S3-seg'};
topology_meta = load_topology_meta(topology_file, num_topologies);
exclusion_table = get_r1_dynamic_training_exclusions();

sample_features = compute_dynamic_features(P_command(scenario_ids(1), :), module_rating_mw);
features = zeros(num_selected, numel(sample_features));
features(1, :) = sample_features;
for k = 2:num_selected
    features(k, :) = compute_dynamic_features(P_command(scenario_ids(k), :), module_rating_mw);
end

hydrogen_t = nan(num_topologies, num_selected);
energy_mwh = nan(num_topologies, num_selected);
energy_mwh_relaxed = nan(num_topologies, num_selected);
efficiency_lhv = nan(num_topologies, num_selected);
solver_status = nan(num_topologies, num_selected);
power_gap_mean_frac = nan(num_topologies, num_selected);
power_gap_max_frac = nan(num_topologies, num_selected);
valid_mask = false(num_topologies, num_selected);
excluded_training_outlier = false(num_topologies, num_selected);
exclusion_reason = strings(num_topologies, num_selected);

for t = 1:num_topologies
    meta = topology_meta(t);
    result_file = fullfile(result_dir, sprintf('results_topology_%d.mat', t));
    if ~isfile(result_file)
        error('Missing result file: %s', result_file);
    end

    data = load(result_file, 'result', 'status');

    for k = 1:num_selected
        scenario_id = scenario_ids(k);

        if isfield(data, 'status') && ~isempty(data.status)
            solver_status(t, k) = data.status(scenario_id, fault_id);
        end

        y = data.result{scenario_id, fault_id};
        if ~isnumeric(y) || isempty(y) || size(y, 1) <= 1
            continue;
        end

        parsed = parse_output_matrix_minimal(y, meta);

        hydrogen_t(t, k) = sum(parsed.N_H2_st(:)) * delta_t_h * 3600 * 2 / 1e6;
        energy_mwh_relaxed(t, k) = sum(parsed.P_st(:)) * delta_t_h;
        energy_mwh(t, k) = sum(parsed.P_real(:)) * delta_t_h;

        active_mask = parsed.P_st > 1e-6 | parsed.P_real > 1e-6;
        if any(active_mask(:))
            rel_gap = abs(parsed.P_st(active_mask) - parsed.P_real(active_mask)) ./ max(parsed.P_real(active_mask), 1e-6);
            power_gap_mean_frac(t, k) = mean(rel_gap);
            power_gap_max_frac(t, k) = max(rel_gap);
        end

        if isfinite(energy_mwh(t, k)) && energy_mwh(t, k) > 0
            efficiency_lhv(t, k) = hydrogen_t(t, k) * 33.33 / energy_mwh(t, k);
            valid_mask(t, k) = isfinite(efficiency_lhv(t, k)) && efficiency_lhv(t, k) > 0;
        end

        exclude_idx = find(exclusion_table.scenario_id == scenario_id & exclusion_table.topology_id == t, 1, 'first');
        if ~isempty(exclude_idx)
            valid_mask(t, k) = false;
            excluded_training_outlier(t, k) = true;
            exclusion_reason(t, k) = exclusion_table.reason(exclude_idx);
        end
    end
end

efficiency_lhv(~isfinite(efficiency_lhv)) = NaN;

row_count = num_topologies * num_selected;
scenario_col = zeros(row_count, 1);
topology_id_col = zeros(row_count, 1);
topology_label_col = strings(row_count, 1);
topology_group_col = strings(row_count, 1);
mean_power_col = zeros(row_count, 1);
low_load_col = zeros(row_count, 1);
ramping_col = zeros(row_count, 1);
hf_col = zeros(row_count, 1);
std_power_col = zeros(row_count, 1);
range_power_col = zeros(row_count, 1);
hydrogen_col = nan(row_count, 1);
energy_col = nan(row_count, 1);
energy_relaxed_col = nan(row_count, 1);
efficiency_col = nan(row_count, 1);
status_col = nan(row_count, 1);
power_gap_mean_col = nan(row_count, 1);
power_gap_max_col = nan(row_count, 1);
valid_col = false(row_count, 1);
excluded_col = false(row_count, 1);
reason_col = strings(row_count, 1);

row = 0;
for t = 1:num_topologies
    for k = 1:num_selected
        row = row + 1;
        scenario_col(row) = scenario_ids(k);
        topology_id_col(row) = t;
        topology_label_col(row) = topology_labels(t);
        topology_group_col(row) = string(topology_groups{t});
        mean_power_col(row) = features(k, 1);
        low_load_col(row) = features(k, 2);
        ramping_col(row) = features(k, 3);
        hf_col(row) = features(k, 4);
        std_power_col(row) = features(k, 5);
        range_power_col(row) = features(k, 6);
        hydrogen_col(row) = hydrogen_t(t, k);
        energy_col(row) = energy_mwh(t, k);
        energy_relaxed_col(row) = energy_mwh_relaxed(t, k);
        efficiency_col(row) = efficiency_lhv(t, k);
        status_col(row) = solver_status(t, k);
        power_gap_mean_col(row) = power_gap_mean_frac(t, k);
        power_gap_max_col(row) = power_gap_max_frac(t, k);
        valid_col(row) = valid_mask(t, k);
        excluded_col(row) = excluded_training_outlier(t, k);
        reason_col(row) = exclusion_reason(t, k);
    end
end

long_table = table( ...
    scenario_col, topology_id_col, topology_label_col, topology_group_col, ...
    mean_power_col, low_load_col, ramping_col, hf_col, std_power_col, range_power_col, ...
    hydrogen_col, energy_col, energy_relaxed_col, efficiency_col, status_col, ...
    power_gap_mean_col, power_gap_max_col, valid_col, excluded_col, reason_col, ...
    'VariableNames', { ...
    'scenario_id', 'topology_id', 'topology_label', 'topology_group', ...
    'mean_power_pu', 'low_load_duration_pu', 'average_absolute_ramping_pu', ...
    'high_frequency_ratio', 'load_std_pu', 'load_range_pu', ...
    'hydrogen_t', 'stack_energy_MWh', 'stack_energy_relaxed_MWh', ...
    'module_efficiency_LHV', 'solver_status', ...
    'power_gap_mean_frac', 'power_gap_max_frac', 'has_valid_dynamic_result', ...
    'excluded_training_outlier', 'exclusion_reason'});

dataset = struct();
dataset.scenario_ids = scenario_ids;
dataset.features = features;
dataset.hydrogen_t = hydrogen_t;
dataset.energy_mwh = energy_mwh;
dataset.energy_mwh_relaxed = energy_mwh_relaxed;
dataset.efficiency_lhv = efficiency_lhv;
dataset.solver_status = solver_status;
dataset.power_gap_mean_frac = power_gap_mean_frac;
dataset.power_gap_max_frac = power_gap_max_frac;
dataset.valid_mask = valid_mask;
dataset.excluded_training_outlier = excluded_training_outlier;
dataset.exclusion_reason = exclusion_reason;
dataset.exclusion_table = exclusion_table;
dataset.long_table = long_table;
end

function topology_meta = load_topology_meta(topology_file, num_topologies)
coe = readmatrix(topology_file, 'Sheet', 'Sheet1', 'Range', 'D2:J16');
counts = readmatrix(topology_file, 'Sheet', 'Sheet2', 'Range', 'B2:H8');
coe = coe';
counts = counts';

topology_meta = repmat(struct( ...
    'N_st', [], 'N_sp', [], 'N_lyep', [], 'N_cl', [], 'N_cell', []), num_topologies, 1);
for t = 1:num_topologies
    topology_meta(t).N_st = counts(t, 1);
    topology_meta(t).N_sp = counts(t, 2);
    topology_meta(t).N_lyep = counts(t, 4);
    topology_meta(t).N_cl = counts(t, 5);
    topology_meta(t).N_cell = 200 * coe(t, 4);
end
end

function parsed = parse_output_matrix_minimal(output_matrix, meta)
n_st = meta.N_st;
n_lyep = meta.N_lyep;
n_cl = meta.N_cl;

col = 1;
parsed = struct();
parsed.P_st = output_matrix(:, col:(col + n_st - 1))'; col = col + n_st;
parsed.N_H2_st = output_matrix(:, col:(col + n_st - 1))'; col = col + n_st;
col = col + n_st; % delta_I
parsed.I_st = output_matrix(:, col:(col + n_st - 1))'; col = col + n_st;
col = col + n_lyep; % delta_lyep
col = col + n_st;   % Qlye_st
col = col + n_cl;   % Q_cl
parsed.U_cell = output_matrix(:, col:(col + n_st - 1))';
parsed.P_real = meta.N_cell .* parsed.I_st .* parsed.U_cell / 1e6;
end
