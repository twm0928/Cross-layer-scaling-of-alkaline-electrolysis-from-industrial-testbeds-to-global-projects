function maps = load_module_ph_map(cfg)
%LOAD_MODULE_PH_MAP Local copy for the degradation branch.

if nargin < 1 || isempty(cfg)
    cfg = plant_case_config();
end

map_file = cfg.module_static_map_file;
if ~isfile(map_file)
    error('Missing constant P-H2 map file: %s', map_file);
end

T = readtable(map_file, 'TextType', 'string');
maps = repmat(struct( ...
    'topology_id', [], ...
    'topology_label', "", ...
    'power_MW', [], ...
    'hydrogen_tph', [], ...
    'efficiency', []), numel(cfg.topology_ids), 1);

for i = 1:numel(cfg.topology_ids)
    topology_id = cfg.topology_ids(i);
    rows = T(T.topology_id == topology_id, :);
    rows = sortrows(rows, 'constant_power_MW');

    power = rows.constant_power_MW(:);
    hydrogen_tph = rows.hydrogen_t_per_h(:);
    eta = rows.efficiency_LHV_command_basis(:);

    power = [0; power];
    hydrogen_tph = [0; hydrogen_tph];
    eta = [0; eta];

    [power, ia] = unique(power, 'stable');
    hydrogen_tph = hydrogen_tph(ia);
    eta = eta(ia);

    maps(i).topology_id = topology_id;
    maps(i).topology_label = cfg.topology_labels{i};
    maps(i).power_MW = power;
    maps(i).hydrogen_tph = hydrogen_tph;
    maps(i).efficiency = eta;
end
end
