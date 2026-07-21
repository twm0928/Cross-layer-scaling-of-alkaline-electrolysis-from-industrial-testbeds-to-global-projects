function meta = load_module_topology_meta(topology_ids)
%LOAD_MODULE_TOPOLOGY_META Load the shared M1-M7 topology metadata.

if nargin < 1 || isempty(topology_ids)
    topology_ids = 1:7;
end

cfg = degradation_results_config();
CAP = cfg.module_rating_MW;

coe = readmatrix(cfg.topology_file, 'Sheet', 'Sheet1', 'Range', 'D2:J16');
counts = readmatrix(cfg.topology_file, 'Sheet', 'Sheet2', 'Range', 'B2:H8');
coe = coe';
counts = counts';

meta = repmat(struct(), numel(topology_ids), 1);
for k = 1:numel(topology_ids)
    type = topology_ids(k);
    meta(k).topology_id = type;
    meta(k).topology_label = sprintf('M%d', type);
    meta(k).N_st = counts(type, 1);
    meta(k).N_sp = counts(type, 2);
    meta(k).N_pu = counts(type, 3);
    meta(k).N_lyep = counts(type, 4);
    meta(k).N_cl = counts(type, 5);
    meta(k).N_ht = counts(type, 7);
    meta(k).Pn_st_MW = CAP / meta(k).N_st * coe(type, 1);
    meta(k).I_UL_st_A = 14000 * coe(type, 2);
    meta(k).I_LL_coef = coe(type, 3);
    meta(k).N_cell = 200 * coe(type, 4);
    meta(k).A_cell_m2 = pi * 1^2 * coe(type, 5);
end

if isscalar(meta)
    meta = meta(1);
end
end
