function run_theta_dynamic_baseline()
%RUN_THETA_DYNAMIC_BASELINE Evaluate the original theta-rule plant pipe.
%
% This is the baseline plant workflow: theta-rule dispatch first, then
% dynamic module-efficiency surrogate evaluation using the same daily
% feature interface as the original manuscript pipeline.

cfg = plant_case_config();
addpath(cfg.flow_src_dir);

cases = load_plant_power_profiles(cfg);
summary_rows = {};
theta_rows = {};
profile_rows = {};
process_dir = fullfile(cfg.output_dir, 'process_theta_dynamic');
if ~exist(process_dir, 'dir')
    mkdir(process_dir);
end

for ci = 1:numel(cases)
    case_name = string(cases(ci).name);
    case_cfg = cfg;
    case_cfg.n_modules = cases(ci).n_modules;
    case_cfg.plant_rating_MW = cases(ci).plant_rating_MW;

    P_available = cases(ci).P_available_MW(:);
    P_capped = min(P_available, case_cfg.plant_rating_MW);
    mean_load_raw = mean(P_available) / case_cfg.plant_rating_MW;
    mean_load_capped = mean(P_capped) / case_cfg.plant_rating_MW;
    available_energy_MWh = sum(P_available) * case_cfg.delta_t_hour;
    capped_energy_MWh = sum(P_capped) * case_cfg.delta_t_hour;
    steps_per_day = round(24 / case_cfg.delta_t_hour);
    n_days = numel(P_available) / steps_per_day;

    profile_rows(end + 1, :) = { ...
        case_name, case_cfg.n_modules, case_cfg.plant_rating_MW, ...
        mean_load_raw, mean_load_capped, available_energy_MWh, capped_energy_MWh, ...
        min(P_available), max(P_available), n_days ...
        }; %#ok<AGROW>

    for ti = 1:numel(cfg.topology_ids)
        topology_id = cfg.topology_ids(ti);
        topology_label = string(cfg.topology_labels{ti});

        best_theta = NaN;
        best_dyn = [];
        best_hydrogen = -inf;
        best_curtailment_MWh = NaN;
        best_active = NaN;
        best_schedule = [];
        theta_daily_rows = {};
        theta_process = struct([]);

        for th = 1:numel(cfg.theta_grid)
            theta = cfg.theta_grid(th);
            Ptheta3 = dispatch_theta_rule(P_available', theta, case_cfg);
            Ptheta = squeeze(Ptheta3(1, :, :));
            if isvector(Ptheta)
                Ptheta = Ptheta(:);
            end

            theta_dyn = evaluate_dynamic_surrogate_schedule(Ptheta, topology_id, case_cfg);
            theta_curtailment_MWh = sum(max(P_available - theta_dyn.Pused_MW, 0)) * case_cfg.delta_t_hour;
            theta_active = mean(sum(Ptheta > 1e-9, 2));
            used_energy_day = sum(theta_dyn.energy_day_module_MWh, 2);
            hydrogen_day = sum(theta_dyn.hydrogen_day_module_t, 2);
            curtailment_day = reshape(max(P_available - theta_dyn.Pused_MW, 0), steps_per_day, [])';
            curtailment_day_MWh = sum(curtailment_day, 2) * case_cfg.delta_t_hour;
            active_day = reshape(sum(Ptheta > 1e-9, 2), steps_per_day, [])';
            active_day_mean = mean(active_day, 2);
            eta_day_mean = mean(theta_dyn.eta_day_module, 2);

            for d = 1:n_days
                theta_daily_rows(end + 1, :) = { ...
                    case_name, topology_label, topology_id, theta, d, ...
                    used_energy_day(d), hydrogen_day(d), eta_day_mean(d), ...
                    curtailment_day_MWh(d), active_day_mean(d) ...
                    }; %#ok<AGROW>
            end

            theta_process(th).theta = theta;
            theta_process(th).Pmodule_MW = Ptheta;
            theta_process(th).Pused_MW = theta_dyn.Pused_MW;
            theta_process(th).features = theta_dyn.features;
            theta_process(th).eta_day_module = theta_dyn.eta_day_module;
            theta_process(th).energy_day_module_MWh = theta_dyn.energy_day_module_MWh;
            theta_process(th).hydrogen_day_module_t = theta_dyn.hydrogen_day_module_t;
            theta_process(th).used_energy_day_MWh = used_energy_day;
            theta_process(th).hydrogen_day_t = hydrogen_day;
            theta_process(th).curtailment_day_MWh = curtailment_day_MWh;
            theta_process(th).active_modules_day_mean = active_day_mean;

            theta_rows(end + 1, :) = { ...
                case_name, topology_label, topology_id, theta, ...
                case_cfg.n_modules, case_cfg.plant_rating_MW, ...
                mean_load_raw, mean_load_capped, theta_dyn.energy_MWh, ...
                theta_dyn.hydrogen_t, theta_dyn.efficiency_LHV, ...
                theta_curtailment_MWh, theta_active ...
                }; %#ok<AGROW>

            if theta_dyn.hydrogen_t > best_hydrogen
                best_hydrogen = theta_dyn.hydrogen_t;
                best_theta = theta;
                best_dyn = theta_dyn;
                best_curtailment_MWh = theta_curtailment_MWh;
                best_active = theta_active;
                best_schedule = Ptheta;
            end
        end

        summary_rows(end + 1, :) = { ...
            case_name, topology_label, topology_id, best_theta, ...
            case_cfg.n_modules, case_cfg.plant_rating_MW, ...
            mean_load_raw, mean_load_capped, ...
            available_energy_MWh, capped_energy_MWh, best_dyn.energy_MWh, ...
            best_dyn.hydrogen_t, best_dyn.efficiency_LHV, ...
            best_curtailment_MWh, best_active ...
            }; %#ok<AGROW>

        theta_daily = cell2table(theta_daily_rows, 'VariableNames', { ...
            'case_name', 'topology_label', 'topology_id', 'theta', 'day_id', ...
            'used_energy_day_MWh', 'hydrogen_day_t', 'eta_day_mean', ...
            'curtailment_day_MWh', 'active_modules_day_mean' ...
            });
        theta_daily = numeric_table_columns(theta_daily);
        case_key = char(matlab.lang.makeValidName(sprintf('%s_%s', case_name, topology_label)));
        daily_csv = fullfile(process_dir, sprintf('%s_theta_daily.csv', case_key));
        archive_mat = fullfile(process_dir, sprintf('%s_theta_process.mat', case_key));
        writetable(theta_daily, daily_csv);
        save(archive_mat, 'case_name', 'topology_label', 'topology_id', 'P_available', ...
            'P_capped', 'best_theta', 'best_schedule', 'best_dyn', 'theta_process', '-v7.3');
    end
end

summary = cell2table(summary_rows, 'VariableNames', { ...
    'case_name', 'topology_label', 'topology_id', 'best_theta', ...
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
profile_summary = cell2table(profile_rows, 'VariableNames', { ...
    'case_name', 'n_modules', 'plant_rating_MW', ...
    'mean_load_raw', 'mean_load_capped', ...
    'available_energy_MWh', 'capped_available_energy_MWh', ...
    'min_power_MW', 'max_power_MW', 'n_days' ...
    });
profile_summary = numeric_table_columns(profile_summary);

out_summary_csv = fullfile(cfg.output_dir, 'plant_theta_dynamic_closed_loop_summary.csv');
out_detail_csv = fullfile(cfg.output_dir, 'plant_theta_dynamic_closed_loop_detail.csv');
out_xlsx = fullfile(cfg.output_dir, 'plant_theta_dynamic_closed_loop.xlsx');
out_profile_csv = fullfile(process_dir, 'plant_theta_case_profile_summary.csv');

writetable(summary, out_summary_csv);
writetable(theta_detail, out_detail_csv);
writetable(summary, out_xlsx, 'Sheet', 'best_theta');
writetable(theta_detail, out_xlsx, 'Sheet', 'theta_grid');
writetable(profile_summary, out_profile_csv);

fprintf('Theta dynamic baseline complete:\n');
fprintf('  %s\n', out_xlsx);
disp(summary);

function T = numeric_table_columns(T)
for j = 1:width(T)
    if iscell(T.(j)) && all(cellfun(@(x) isnumeric(x) && isscalar(x), T.(j)))
        T.(j) = cell2mat(T.(j));
    end
end
end

end
