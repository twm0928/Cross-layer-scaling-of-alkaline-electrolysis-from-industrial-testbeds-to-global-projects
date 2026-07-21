function T = stack_case_library()
% Stack design cases using the original source-code parameters.
%
% The 5 MW cases share the same physical parameters because the original
% scaling strategies collapse to the same reference stack at the base scale.

rows = {};
idx = 0;

for capacityMW = [5, 10, 20]
    for geometry = {'equal_width', 'equal_length', 'equal_VA'}
        idx = idx + 1;
        s = make_stack_case(idx, capacityMW, geometry{1});
        rows(idx, :) = { ...
            s.case_id, s.stack_size_MW, s.capacity_Nm3h, s.geometry, ...
            s.n_cell, s.rated_current_A, s.R0_ohm, s.U0_V, ...
            s.cell_area_scale, s.channel_area_scale, s.manifold_area_scale, ...
            s.channel_length_m, s.channel_area_m2, ...
            s.manifold_length_m, s.manifold_area_m2, ...
            s.rated_alkali_flow_m3_h, ...
            s.is_original_geometry, s.is_pipe_geometry ...
            }; %#ok<AGROW>
    end
end

T = cell2table(rows, 'VariableNames', { ...
    'case_id', 'stack_size_MW', 'capacity_Nm3h', 'geometry', ...
    'n_cell', 'rated_current_A', 'R0_ohm', 'U0_V', ...
    'cell_area_scale', 'channel_area_scale', 'manifold_area_scale', ...
    'channel_length_m', 'channel_area_m2', ...
    'manifold_length_m', 'manifold_area_m2', ...
    'rated_alkali_flow_m3_h', ...
    'is_original_geometry', 'is_pipe_geometry' ...
    });
end

function s = make_stack_case(caseId, capacityMW, geometry)
baseR0 = 7.19104e-5;
baseI = 14000;
baseN = 200;
baseU0 = 1.509887;

switch capacityMW
    case 5
        capacityNm3h = 1000;
        scale = 1;
    case 10
        capacityNm3h = 2000;
        scale = 2;
    case 20
        capacityNm3h = 4000;
        scale = 4;
    otherwise
        error('Unsupported nominal stack size: %.3g MW.', capacityMW);
end

switch geometry
    case 'equal_width'
        nCell = baseN * scale;
        areaScale = 1;
        currentScale = 1;
    case 'equal_length'
        nCell = baseN;
        areaScale = scale;
        currentScale = scale;
    case 'equal_VA'
        if scale == 1
            nCell = 200;
            areaScale = 1;
            currentScale = 1;
        elseif scale == 2
            nCell = 280;
            areaScale = 1.414;
            currentScale = 20000 / baseI;
        elseif scale == 4
            nCell = 400;
            areaScale = 2;
            currentScale = 2;
        else
            areaScale = sqrt(scale);
            currentScale = areaScale;
            nCell = round(baseN * areaScale);
        end
    otherwise
        error('Unsupported stack geometry: %s.', geometry);
end

s = struct();
s.case_id = caseId;
s.stack_size_MW = capacityMW;
s.capacity_Nm3h = capacityNm3h;
s.geometry = geometry;
s.n_cell = nCell;
s.rated_current_A = baseI * currentScale;
s.R0_ohm = baseR0 / areaScale;
s.U0_V = baseU0;
s.cell_area_scale = areaScale;
s.channel_area_scale = areaScale;
s.manifold_area_scale = scale;
s.channel_length_m = 0.03;
s.channel_area_m2 = 10 / 10^3 * 2.2 / 10^3 * 14 * areaScale;
s.manifold_length_m = 0.0105;
s.manifold_area_m2 = table_s4_manifold_area(capacityMW);
s.rated_alkali_flow_m3_h = 70 * scale;
s.is_original_geometry = true;
s.is_pipe_geometry = strcmp(geometry, 'equal_VA');
end

function area = table_s4_manifold_area(capacityMW)
switch capacityMW
    case 5
        area = 0.0126;
    case 10
        area = 0.0126 * 2;
    case 20
        area = 0.0126 * 4;
    otherwise
        error('Unsupported nominal stack size: %.3g MW.', capacityMW);
end
end
