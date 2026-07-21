function cases = load_plant_power_profiles(cfg)
%LOAD_PLANT_POWER_PROFILES Load PV, WT and constant plant power profiles.
%
% Each case carries its own module count. This follows the original plant
% workflow: P_total = P_command * N_module, with N_module = 20, and then
% N_real_module = ceil(max(P_total) / 20 MW).

if nargin < 1 || isempty(cfg)
    cfg = plant_case_config();
end

pv_raw = readmatrix(cfg.profile_file, 'Sheet', 'PV');
wt_raw = readmatrix(cfg.profile_file, 'Sheet', 'WT');
pv_raw = pv_raw(:);
wt_raw = wt_raw(:);

cases = struct('name', {}, 'P_available_MW', {}, 'raw_profile', {}, ...
    'n_modules', {}, 'plant_rating_MW', {}, 'source_note', {});
cases(1).name = 'PV';
cases(1).raw_profile = pv_raw;
cases(1).P_available_MW = pv_raw * cfg.profile_scale_MW;
cases(1).n_modules = ceil(max(cases(1).P_available_MW) / cfg.module_rating_MW);
cases(1).plant_rating_MW = cases(1).n_modules * cfg.module_rating_MW;
cases(1).source_note = 'Plant profiles.xlsx/PV; original N_real_module logic';

cases(2).name = 'WT';
cases(2).raw_profile = wt_raw;
cases(2).P_available_MW = wt_raw * cfg.profile_scale_MW;
cases(2).n_modules = ceil(max(cases(2).P_available_MW) / cfg.module_rating_MW);
cases(2).plant_rating_MW = cases(2).n_modules * cfg.module_rating_MW;
cases(2).source_note = 'Plant profiles.xlsx/WT; original N_real_module logic';

cases(3).name = 'Constant';
cases(3).n_modules = cfg.scale_N_module;
cases(3).plant_rating_MW = cases(3).n_modules * cfg.module_rating_MW;
cases(3).raw_profile = cases(3).n_modules * ones(cfg.constant_profile_steps, 1);
cases(3).P_available_MW = cases(3).plant_rating_MW * ones(cfg.constant_profile_steps, 1);
cases(3).source_note = 'Full-load constant plant case at original N_module scale';
end
