% Summarise MILP-static benchmark gains over the best theta-grid strategy.

cfg = plant_case_config();
summary_file = fullfile(cfg.output_dir, 'plant_milp_static_benchmark_summary.csv');
T = readtable(summary_file, 'TextType', 'string');

rows = {};
for ci = 1:numel(cfg.case_names)
    case_name = cfg.case_names{ci};
    for ti = 1:numel(cfg.topology_ids)
        topology_id = cfg.topology_ids(ti);
        idx_milp = T.case_name == case_name & T.topology_id == topology_id & ...
            T.strategy == "MILP_static_PH";
        idx_theta = T.case_name == case_name & T.topology_id == topology_id & ...
            T.strategy == "Best_theta_static_PH";
        if ~any(idx_milp) || ~any(idx_theta)
            continue;
        end
        A = T(idx_milp, :);
        B = T(idx_theta, :);
        h_gain = 100 * (A.hydrogen_t - B.hydrogen_t) / max(B.hydrogen_t, eps);
        eta_gain = 100 * (A.efficiency_LHV_used_energy_basis - B.efficiency_LHV_used_energy_basis) / ...
            max(B.efficiency_LHV_used_energy_basis, eps);
        rows(end + 1, :) = { ...
            case_name, A.topology_label, topology_id, B.theta, ...
            B.hydrogen_t, A.hydrogen_t, h_gain, ...
            B.efficiency_LHV_used_energy_basis, A.efficiency_LHV_used_energy_basis, eta_gain, ...
            B.mean_active_modules, A.mean_active_modules, ...
            B.curtailment_MWh, A.curtailment_MWh ...
            }; %#ok<SAGROW>
    end
end

gain_table = cell2table(rows, 'VariableNames', { ...
    'case_name', 'topology_label', 'topology_id', 'best_theta', ...
    'hydrogen_theta_t', 'hydrogen_milp_t', 'hydrogen_gain_percent', ...
    'efficiency_theta', 'efficiency_milp', 'efficiency_gain_percent', ...
    'active_modules_theta', 'active_modules_milp', ...
    'curtailment_theta_MWh', 'curtailment_milp_MWh' ...
    });
gain_table = numeric_table_columns(gain_table);

out_csv = fullfile(cfg.output_dir, 'plant_milp_static_benchmark_gain.csv');
out_xlsx = fullfile(cfg.output_dir, 'plant_milp_static_benchmark.xlsx');
writetable(gain_table, out_csv);
writetable(gain_table, out_xlsx, 'Sheet', 'milp_vs_theta_gain');

disp(gain_table);

function T = numeric_table_columns(T)
for j = 1:width(T)
    if iscell(T.(j)) && all(cellfun(@(x) isnumeric(x) && isscalar(x), T.(j)))
        T.(j) = cell2mat(T.(j));
    end
end
end
