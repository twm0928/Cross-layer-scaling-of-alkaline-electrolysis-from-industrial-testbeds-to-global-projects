function iface = load_static_voltage_interface(topology_id, cfg)
%LOAD_STATIC_VOLTAGE_INTERFACE Load the topology-specific static Uref map.
%
% The reference voltage map is extracted from the exported static interface.
% Only physically valid operating points (used module AC power > 0) are kept.

if nargin < 2 || isempty(cfg)
    cfg = degradation_results_config();
end

csv_file = cfg.static_voltage_reference_csv;
if ~isfile(csv_file)
    error('Static voltage-reference CSV not found: %s', csv_file);
end

T = readtable(csv_file, 'TextType', 'string');
rows = T(double(T.topology_id) == double(topology_id), :);
if isempty(rows)
    error('Topology %d not found in static voltage-reference table: %s', topology_id, csv_file);
end

rows = rows(double(rows.used_module_ac_power_MW) > 0 & double(rows.stack_cell_voltage_V) > 0, :);
rows = sortrows(rows, 'used_module_ac_power_MW');
if isempty(rows)
    error('Topology %d has no valid operating rows in static voltage-reference table.', topology_id);
end

power_MW = double(rows.used_module_ac_power_MW);
power_pu = double(rows.used_module_ac_power_pu);
cell_voltage_V = double(rows.stack_cell_voltage_V);

[power_MW, ia] = unique(power_MW, 'stable');
power_pu = power_pu(ia);
cell_voltage_V = cell_voltage_V(ia);

iface = struct();
iface.topology_id = double(topology_id);
iface.topology_label = char(string(rows.topology_label(1)));
iface.power_MW = power_MW(:);
iface.power_pu = power_pu(:);
iface.cell_voltage_V = cell_voltage_V(:);
iface.min_operating_power_MW = power_MW(1);
iface.min_operating_power_pu = power_pu(1);
iface.max_operating_power_MW = power_MW(end);
iface.max_operating_power_pu = power_pu(end);
end
