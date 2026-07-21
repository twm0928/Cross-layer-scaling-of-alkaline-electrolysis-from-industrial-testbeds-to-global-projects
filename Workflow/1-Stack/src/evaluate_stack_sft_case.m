function R = evaluate_stack_sft_case(stackCase, kSeg, currentFractions, areaPolicy)
% Evaluate a stack design with optional segmented flow topology (SFT).
%
% kSeg = 1 reproduces the original continuous flow topology. For kSeg > 1,
% the stack is split into adjacent-cell segments. Each segment is evaluated
% with the original ECN routine and the same terminal current, then the
% segment voltages and effective electrolysis currents are summed.

if nargin < 3 || isempty(currentFractions)
    currentFractions = [0.02, 0.05, 0.1:0.1:1];
end
if nargin < 4 || isempty(areaPolicy)
    areaPolicy = 'total_area_conserved';
end

F = 96485;
V_thermoneutral = 1.48;
voltageTempsC = [90, 60];

segments = split_segments(stackCase.n_cell, kSeg);
rows = {};

for a = 1:numel(currentFractions)
    currentFraction = currentFractions(a);
    I0 = stackCase.rated_current_A * currentFraction;

    iEleAll = [];
    iStrayAll = [];

    for s = 1:numel(segments)
        nSegCell = segments(s);
        segScale = nSegCell / stackCase.n_cell;
        resist = build_resistances(stackCase, segScale, areaPolicy);
        [iEle, iStray] = f_stack(nSegCell, stackCase.R0_ohm, stackCase.U0_V, ...
            resist.Rm_l, resist.Rm_u, resist.Rch_l_an, resist.Rch_l_ca, ...
            resist.Rch_u_an, resist.Rch_u_ca, resist.R_end, I0);

        iEle = full(iEle);
        iStray = full(iStray);
        iEleAll = [iEleAll; iEle]; %#ok<AGROW>
        iStrayAll = [iStrayAll; iStray]; %#ok<AGROW>
    end

    H2MolS = sum(iEleAll) / (2 * F);
    etaCurrent = sum(iEleAll) / (I0 * stackCase.n_cell);
    [UStackT90, UAvgCellT90, powerT90MW, etaStackT90] = ...
        stack_external_voltage_efficiency(stackCase, I0, voltageTempsC(1), ...
        etaCurrent, V_thermoneutral);
    [UStackT60, UAvgCellT60, powerT60MW, etaStackT60] = ...
        stack_external_voltage_efficiency(stackCase, I0, voltageTempsC(2), ...
        etaCurrent, V_thermoneutral);
    H2Nm3h = H2MolS * 22.414e-3 * 3600;

    rows(end+1, :) = { ...
        currentFraction, I0, powerT90MW, UStackT90, UAvgCellT90, ...
        etaCurrent, etaStackT90, ...
        UStackT90, UAvgCellT90, powerT90MW, etaStackT90, ...
        UStackT60, UAvgCellT60, powerT60MW, etaStackT60, ...
        H2MolS, H2Nm3h, ...
        min(iEleAll), max(iEleAll), min(iEleAll) / max(iEleAll), ...
        std(iEleAll) / mean(iEleAll), sum(abs(iStrayAll)) / (I0 * stackCase.n_cell) ...
        }; %#ok<AGROW>
end

R = cell2table(rows, 'VariableNames', { ...
    'current_fraction', 'input_current_A', 'stack_power_MW', ...
    'stack_voltage_V', 'average_cell_voltage_V', ...
    'current_efficiency', 'stack_efficiency_LHV', ...
    'stack_voltage_external_T90_V', 'average_cell_voltage_external_T90_V', ...
    'stack_power_external_T90_MW', 'stack_efficiency_thermoneutral_T90', ...
    'stack_voltage_external_T60_V', 'average_cell_voltage_external_T60_V', ...
    'stack_power_external_T60_MW', 'stack_efficiency_thermoneutral_T60', ...
    'H2_mol_s', 'H2_Nm3_h', ...
    'cell_current_min_A', 'cell_current_max_A', ...
    'cell_current_min_over_max', 'cell_current_std_over_mean', ...
    'absolute_stray_current_ratio' ...
    });

if ~isempty(R.stack_power_MW)
    ratedPower = R.stack_power_MW(end);
    if ratedPower > 0
        R.stack_power_pu = R.stack_power_MW ./ ratedPower;
    else
        R.stack_power_pu = zeros(height(R), 1);
    end
end
end

function [UStack, UAvgCell, powerMW, etaStack] = stack_external_voltage_efficiency( ...
    stackCase, I0, temperatureC, etaCurrent, V_thermoneutral)
% Fig. 2a uses the semi-empirical external cell-voltage equation,
% not the distributed-circuit branch-voltage proxy used to solve shunt
% currents. The /2 term follows the SI cell-layer parameterisation.
R0VoltageBase = (9.4410 - 0.0250 * temperatureC) * 1e-5 / 2;
R0Voltage = R0VoltageBase / stackCase.cell_area_scale;
UAvgCell = stackCase.U0_V + R0Voltage * I0;
UStack = stackCase.n_cell * UAvgCell;
powerMW = I0 * UStack / 1e6;
etaStack = etaCurrent * V_thermoneutral / UAvgCell;
end

function resist = build_resistances(stackCase, segmentScale, areaPolicy)
m = 0.31;
T = 84 + 273;
alpha = 0;
n_l = 2;

if isfield(stackCase, 'channel_length_m')
    lc = stackCase.channel_length_m;
else
    lc = 30 / 10^3;
end
if isfield(stackCase, 'manifold_length_m')
    lm = stackCase.manifold_length_m;
else
    lm = 0.0105;
end
lmEnd = lm;

if isfield(stackCase, 'channel_area_m2')
    Sch = stackCase.channel_area_m2;
else
    Sch = 10/10^3 * 2.2/10^3 * 14 * stackCase.channel_area_scale;
end
if isfield(stackCase, 'manifold_area_m2')
    SmBase = stackCase.manifold_area_m2;
else
    SmBase = 12600/10^6 * stackCase.manifold_area_scale;
end

switch areaPolicy
    case 'total_area_conserved'
        Sm = SmBase * segmentScale;
    case 'branch_area_preserved'
        Sm = SmBase;
    otherwise
        error('Unsupported SFT manifold-area policy: %s.', areaPolicy);
end

sigma = 2800*m - 0.9241*T - 0.01497*T^2 - 9.052*T*m ...
    + 0.02591*T^2*m^(0.1765) + 0.06966*T*m^(-1) - 289800*m*T^(-1);
rho = 1 / sigma;

resist.Rm_l = rho * lm / (Sm * n_l);
resist.Rch_l_ca = rho * lc / (Sch * n_l);
resist.Rch_l_an = resist.Rch_l_ca;
resist.Rm_u = rho * lm / Sm / (1 - alpha)^1.5;
resist.Rch_u_an = rho * lc / Sch / (1 - alpha)^1.5;
resist.Rch_u_ca = resist.Rch_u_an;
resist.Rm_end = rho * lmEnd / (Sm * n_l);
resist.Rch_l_end = rho * lc / (Sch * n_l);
resist.R_end = resist.Rm_end + resist.Rch_l_end;
end

function segments = split_segments(nCell, kSeg)
base = floor(nCell / kSeg);
segments = base * ones(1, kSeg);
remainder = nCell - base * kSeg;
if remainder > 0
    segments(1:remainder) = segments(1:remainder) + 1;
end
end
