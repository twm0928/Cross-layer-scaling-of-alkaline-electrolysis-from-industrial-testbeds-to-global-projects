% Run the first plant-layer MILP benchmark using the module P-H2 maps.
%
% This is the minimum closed loop:
%   constant-profile module results -> P-H2 map
%   -> plant integer/MILP dispatch
%   -> comparison with the original theta-rule strategies

cfg = plant_case_config();
addpath(cfg.flow_src_dir);

maps = load_module_ph_map(cfg);
cases = load_plant_power_profiles(cfg);

summary_rows = {};
theta_rows = {};

for ci = 1:numel(cases)
    case_name = cases(ci).name;
    case_cfg = cfg;
    case_cfg.n_modules = cases(ci).n_modules;
    case_cfg.plant_rating_MW = cases(ci).plant_rating_MW;

    P_available = cases(ci).P_available_MW(:);
    P_capped = min(P_available, case_cfg.plant_rating_MW);
    mean_load_raw = mean(P_available) / case_cfg.plant_rating_MW;
    mean_load_capped = mean(P_capped) / case_cfg.plant_rating_MW;
    available_energy_MWh = sum(P_available) * case_cfg.delta_t_hour;
    capped_energy_MWh = sum(P_capped) * case_cfg.delta_t_hour;

    for mi = 1:numel(maps)
        ph_map = maps(mi);

        milp = dispatch_milp_static_map(P_available, ph_map, case_cfg);
        milp_eval = evaluate_static_ph_schedule(milp.Pmodule_MW, ph_map, case_cfg);
        milp_curtailment_MWh = sum(milp.curtailment_MW) * case_cfg.delta_t_hour;

        summary_rows(end + 1, :) = { ...
            case_name, ph_map.topology_label, ph_map.topology_id, ...
            'MILP_static_PH', NaN, case_cfg.n_modules, case_cfg.plant_rating_MW, ...
            mean_load_raw, mean_load_capped, ...
            available_energy_MWh, capped_energy_MWh, milp_eval.energy_MWh, ...
            milp_eval.hydrogen_t, milp_eval.efficiency_LHV, ...
            milp_curtailment_MWh, mean(sum(milp.Pmodule_MW > 1e-9, 2)) ...
            }; %#ok<SAGROW>

        best_theta = NaN;
        best_hydrogen = -inf;
        best_theta_eval = [];
        best_theta_curtailment_MWh = NaN;
        best_theta_active = NaN;

        for theta = cfg.theta_grid
            Ptheta3 = dispatch_theta_rule(P_available', theta, case_cfg);
            Ptheta = squeeze(Ptheta3(1, :, :));
            if isvector(Ptheta)
                Ptheta = Ptheta(:);
            end
            theta_eval = evaluate_static_ph_schedule(Ptheta, ph_map, case_cfg);
            theta_curtailment_MWh = sum(max(P_available - theta_eval.Pused_MW, 0)) * case_cfg.delta_t_hour;
            theta_active = mean(sum(Ptheta > 1e-9, 2));

            theta_rows(end + 1, :) = { ...
                case_name, ph_map.topology_label, ph_map.topology_id, theta, ...
                case_cfg.n_modules, case_cfg.plant_rating_MW, ...
                mean_load_raw, mean_load_capped, theta_eval.energy_MWh, ...
                theta_eval.hydrogen_t, theta_eval.efficiency_LHV, ...
                theta_curtailment_MWh, theta_active ...
                }; %#ok<SAGROW>

            if theta_eval.hydrogen_t > best_hydrogen
                best_hydrogen = theta_eval.hydrogen_t;
                best_theta = theta;
                best_theta_eval = theta_eval;
                best_theta_curtailment_MWh = theta_curtailment_MWh;
                best_theta_active = theta_active;
            end
        end

        summary_rows(end + 1, :) = { ...
            case_name, ph_map.topology_label, ph_map.topology_id, ...
            'Best_theta_static_PH', best_theta, case_cfg.n_modules, case_cfg.plant_rating_MW, ...
            mean_load_raw, mean_load_capped, ...
            available_energy_MWh, capped_energy_MWh, best_theta_eval.energy_MWh, ...
            best_theta_eval.hydrogen_t, best_theta_eval.efficiency_LHV, ...
            best_theta_curtailment_MWh, best_theta_active ...
            }; %#ok<SAGROW>
    end
end

summary = cell2table(summary_rows, 'VariableNames', { ...
    'case_name', 'topology_label', 'topology_id', 'strategy', 'theta', ...
    'n_modules', 'plant_rating_MW', ...
    'mean_load_raw', 'mean_load_capped', ...
    'available_energy_MWh', 'capped_available_energy_MWh', 'used_energy_MWh', ...
    'hydrogen_t', 'efficiency_LHV_used_energy_basis', ...
    'curtailment_MWh', 'mean_active_modules' ...
    });

theta_detail = cell2table(theta_rows, 'VariableNames', { ...
    'case_name', 'topology_label', 'topology_id', 'theta', ...
    'n_modules', 'plant_rating_MW', ...
    'mean_load_raw', 'mean_load_capped', 'used_energy_MWh', ...
    'hydrogen_t', 'efficiency_LHV_used_energy_basis', ...
    'curtailment_MWh', 'mean_active_modules' ...
    });

summary = numeric_table_columns(summary);
theta_detail = numeric_table_columns(theta_detail);

out_xlsx = fullfile(cfg.output_dir, 'plant_milp_static_benchmark.xlsx');
out_summary_csv = fullfile(cfg.output_dir, 'plant_milp_static_benchmark_summary.csv');
out_theta_csv = fullfile(cfg.output_dir, 'plant_theta_static_benchmark_detail.csv');
writetable(summary, out_summary_csv);
writetable(theta_detail, out_theta_csv);
writetable(summary, out_xlsx, 'Sheet', 'summary');
writetable(theta_detail, out_xlsx, 'Sheet', 'theta_grid');

fig_data_xlsx = fullfile(cfg.figure_dir, 'Fig4_R1_MILP_static_benchmark_data.xlsx');
writetable(summary, fig_data_xlsx, 'Sheet', 'summary');
writetable(theta_detail, fig_data_xlsx, 'Sheet', 'theta_grid');

fprintf('Plant MILP static benchmark complete:\n');
fprintf('  %s\n', out_xlsx);
disp(summary);

function T = numeric_table_columns(T)
for j = 1:width(T)
    if iscell(T.(j)) && all(cellfun(@(x) isnumeric(x) && isscalar(x), T.(j)))
        T.(j) = cell2mat(T.(j));
    end
end
end
