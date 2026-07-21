function T = build_stack_sft_table_s4_parameters()
% Table-S4-style input parameters for the selected SFT stack cases.
%
% Values follow the submitted Table S3/S4 parameter convention. For
% segmented cases, this table separates the full physical stack rating from
% the representative ECN segment. Each segment carries the same stack current
% as the parent stack; segment voltages and hydrogen-production currents are
% aggregated afterwards to reconstruct the full stack.

baseChannelArea = 10 / 10^3 * 2.2 / 10^3 * 14;
baseManifoldArea = 0.0126;

cases = {
    make_case('5 MW baseline', 5, 1, '200', 200, baseManifoldArea, 70, 380, 14000, 5, 1.000, 4, baseChannelArea, 31.62, 0.0067)
    make_case('10 MW equal V/A', 10, 1, '280', 280, baseManifoldArea*2, 140, 560, 20000, 10, 1.189, 5, baseChannelArea*1.414, 63.24, 0.0045)
    make_case('10 MW equal V/A, kseg=2', 10, 2, '140+140', 140, baseManifoldArea, 140/2, 560, 20000, 10, 1.189, 5, baseChannelArea*1.414, 63.24, 0.0045)
    make_case('20 MW equal V/A', 20, 1, '400', 400, baseManifoldArea*4, 280, 760, 28000, 20, 1.414, 6, baseChannelArea*2, 126.48, 0.0024)
    make_case('20 MW equal V/A, kseg=2', 20, 2, '200+200', 200, baseManifoldArea*2, 280/2, 760, 28000, 20, 1.414, 6, baseChannelArea*2, 126.48, 0.0024)
    make_case('20 MW equal V/A, kseg=4', 20, 4, '100+100+100+100', 100, baseManifoldArea, 280/4, 760, 28000, 20, 1.414, 6, baseChannelArea*2, 126.48, 0.0024)
};

columns = cellfun(@(x) x.label, cases, 'UniformOutput', false);
rows = {
    'Electrical parameters', 'Current density', '0.5 A/cm2'
    'Electrical parameters', 'Rated current through each segment', 'A'
    'Electrical parameters', 'Rated voltage of full stack', 'V'
    'Electrical parameters', 'Rated power of full stack', 'MW'
    'Electrical parameters', 'Rated voltage contribution of representative segment', 'V'
    'Electrical parameters', 'Rated power contribution of representative segment', 'MW'
    'Mechanical parameters', 'Flow-path segmentation kseg', '-'
    'Mechanical parameters', 'Number of cells (total)', '-'
    'Mechanical parameters', 'Segment vector', 'cells'
    'Mechanical parameters', 'Cells per segment used in ECN', 'cells'
    'Mechanical parameters', 'Radius', 'm'
    'Mechanical parameters', 'Length', 'm'
    'Channel parameters', 'Single cell longitudinal flow channel length', 'm'
    'Channel parameters', 'Area of hydrogen side of longitudinal flow channel of single cell', 'm2'
    'Channel parameters', 'Area of oxygen side of longitudinal flow channel of single cell', 'm2'
    'Channel parameters', 'Single cell transverse manifold length', 'm'
    'Channel parameters', 'Area of single cell transverse manifold used in each segment', 'm2'
    'Channel parameters', 'Rated alkali flow rate (total stack)', 'm3/h'
    'Channel parameters', 'Rated alkali flow rate represented in each segment', 'm3/h'
    'Heat transfer parameters', 'Heat capacity (total stack, unchanged for module model)', 'MJ/K'
    'Heat transfer parameters', 'Thermal resistance (unchanged for module model)', 'K/W'
};

values = cell(size(rows, 1), numel(cases));
for c = 1:numel(cases)
    s = cases{c};
    values(:, c) = {
        '0.5'
        fmt(s.ratedCurrent)
        fmt(s.ratedVoltage)
        fmt(s.ratedPower)
        fmt(s.ratedVoltage / s.kseg)
        fmt(s.ratedPower / s.kseg)
        fmt(s.kseg)
        fmt(s.nTotal)
        s.segmentVector
        fmt(s.nPerSegment)
        fmt(s.radius, 3)
        fmt(s.length)
        '0.03'
        fmt(s.channelArea, 6)
        fmt(s.channelArea, 6)
        '0.0105'
        fmt(s.manifoldAreaPerSegment, 6)
        fmt(s.totalFlow)
        fmt(s.flowPerSegment)
        fmt(s.heatCapacity, 2)
        fmt(s.thermalResistance, 4)
    };
end

T = cell2table([rows, values], 'VariableNames', ...
    [{'Category', 'Parameter', 'Unit'}, matlab.lang.makeValidName(columns(:)')]);
end

function s = make_case(label, stackSizeMW, kseg, segmentVector, nPerSegment, ...
    manifoldAreaPerSegment, flowPerSegment, ratedVoltage, ratedCurrent, ...
    ratedPower, radius, length, channelArea, heatCapacity, thermalResistance)
s = struct();
s.label = label;
s.stackSizeMW = stackSizeMW;
s.kseg = kseg;
s.segmentVector = segmentVector;
s.nPerSegment = nPerSegment;
s.nTotal = nPerSegment * kseg;
s.manifoldAreaPerSegment = manifoldAreaPerSegment;
s.flowPerSegment = flowPerSegment;
s.ratedVoltage = ratedVoltage;
s.ratedCurrent = ratedCurrent;
s.ratedPower = ratedPower;
s.radius = radius;
s.length = length;
s.channelArea = channelArea;
s.totalFlow = flowPerSegment * kseg;
s.heatCapacity = heatCapacity;
s.thermalResistance = thermalResistance;
end

function txt = fmt(x, digits)
if nargin < 2
    digits = 0;
end
if abs(x - round(x)) < 1e-12 && digits == 0
    txt = sprintf('%d', round(x));
else
    txt = sprintf(['%.', num2str(digits), 'f'], x);
end
end
