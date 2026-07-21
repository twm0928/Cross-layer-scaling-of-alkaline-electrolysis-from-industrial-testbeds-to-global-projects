function summary = run_degradation_feature_benchmark_internal(topology_ids, out_root_name, summary_prefix)
%RUN_DEGRADATION_FEATURE_BENCHMARK_INTERNAL
% Export Level-1 raw schedules and Level-2 daily feature tables for the
% plant-layer degradation branch.

if nargin < 1 || isempty(topology_ids)
    topology_ids = 1:7;
end
if nargin < 2 || isempty(out_root_name)
    out_root_name = 'plant_m1_m7_degradation_benchmark';
end
if nargin < 3 || isempty(summary_prefix)
    summary_prefix = 'm1_m7';
end

cfg = degradation_results_config();
plant_cfg = plant_case_config();

cases = load_plant_power_profiles(plant_cfg);
maps = load_module_ph_map(plant_cfg);
out_root = fullfile(cfg.outputs_dir, out_root_name);
schedule_dir = fullfile(out_root, 'level1_raw_schedules');
feature_dir = fullfile(out_root, 'level2_daily_features');
summary_dir = fullfile(out_root, 'summaries');

ensure_dir(out_root);
ensure_dir(schedule_dir);
ensure_dir(feature_dir);
ensure_dir(summary_dir);

summary_rows = {};

for ci = 1:numel(cases)
    case_name = char(string(cases(ci).name));
    case_cfg = plant_cfg;
    case_cfg.n_modules = cases(ci).n_modules;
    case_cfg.plant_rating_MW = cases(ci).plant_rating_MW;
    P_available = cases(ci).P_available_MW(:);

    for ti = 1:numel(topology_ids)
        topology_id = double(topology_ids(ti));
        topology_label = sprintf('M%d', topology_id);
        ph_map = maps([maps.topology_id] == topology_id);
        if isempty(ph_map)
            error('Static map for topology %d not found.', topology_id);
        end

        for theta = plant_cfg.theta_grid
            Ptheta3 = dispatch_theta_rule(P_available', theta, case_cfg);
            Ptheta = squeeze(Ptheta3(1, :, :));
            if isvector(Ptheta)
                Ptheta = Ptheta(:);
            end

            strategy_tag = sprintf('theta_%0.1f', theta);
            [schedule_file, feature_file] = export_one_schedule( ...
                Ptheta, topology_id, case_name, strategy_tag, schedule_dir, feature_dir);

            summary_rows(end + 1, :) = { ...
                case_name, topology_id, topology_label, "theta", theta, ...
                case_cfg.n_modules, case_cfg.plant_rating_MW, ...
                schedule_file, feature_file, size(Ptheta, 1), size(Ptheta, 2) ...
                }; %#ok<AGROW>
        end

        milp = dispatch_milp_static_map(P_available, ph_map, case_cfg);
        strategy_tag = 'milp';
        [schedule_file, feature_file] = export_one_schedule( ...
            milp.Pmodule_MW, topology_id, case_name, strategy_tag, schedule_dir, feature_dir);

        summary_rows(end + 1, :) = { ...
            case_name, topology_id, topology_label, "milp", NaN, ...
            case_cfg.n_modules, case_cfg.plant_rating_MW, ...
            schedule_file, feature_file, size(milp.Pmodule_MW, 1), size(milp.Pmodule_MW, 2) ...
            }; %#ok<AGROW>
    end
end

summary = cell2table(summary_rows, 'VariableNames', { ...
    'case_name', 'topology_id', 'topology_label', 'strategy_type', 'theta', ...
    'n_modules', 'plant_rating_MW', ...
    'schedule_mat_file', 'feature_csv_file', 'n_steps', 'n_schedule_modules' ...
    });

summary_file = fullfile(summary_dir, sprintf('%s_degradation_feature_export_summary.csv', summary_prefix));
writetable(summary, summary_file);
fprintf('Degradation feature benchmark exported:\n  %s\n', summary_file);
end

function [schedule_file, feature_file] = export_one_schedule(Pmodule_MW, topology_id, case_name, strategy_tag, schedule_dir, feature_dir)
base_name = sprintf('%s_%s_topo%d', case_name, strategy_tag, topology_id);
schedule_file = fullfile(schedule_dir, [base_name '.mat']);
feature_file = fullfile(feature_dir, [base_name '.csv']);

safe_save_schedule(schedule_file, Pmodule_MW);
build_degradation_daily_inputs_from_schedule(Pmodule_MW, topology_id, feature_file, base_name);
end

function safe_save_schedule(schedule_file, Pmodule_MW)
try
    save(schedule_file, 'Pmodule_MW', '-v7.3');
catch
    save(schedule_file, 'Pmodule_MW', '-v7');
end
end

function ensure_dir(path_str)
if ~exist(path_str, 'dir')
    mkdir(path_str);
end
end
