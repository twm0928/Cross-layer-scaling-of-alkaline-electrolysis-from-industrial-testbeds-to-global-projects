function T = build_stack_sft_search_region(caseTable, kValues, pipeK)
% Build the stack search region used for the R1 SFT extension.
%
% Original geometrical scaling cases are retained at k_seg = 1. The
% flow-path segmentation dimension is applied only to equal_VA, because this
% is the practical stack interface propagated to the module layer.

if nargin < 1 || isempty(caseTable)
    caseTable = stack_case_library();
end
if nargin < 2 || isempty(kValues)
    kValues = [1, 2, 3, 4];
end
if nargin < 3 || isempty(pipeK)
    pipeK = 4;
end

rows = {};
idx = 0;
for i = 1:height(caseTable)
    geom = caseTable.geometry{i};
    if strcmp(geom, 'equal_VA')
        localK = intersect(kValues, default_k_for_capacity(caseTable.stack_size_MW(i)), 'stable');
    else
        localK = 1;
    end

    for k = localK
        idx = idx + 1;
        isOriginal = (k == 1);
        isPipe = strcmp(geom, 'equal_VA');
        designLabel = sprintf('%dMW_%s_k%d', ...
            caseTable.stack_size_MW(i), geom, k);
        rows(idx, :) = { ...
            idx, caseTable.case_id(i), designLabel, ...
            caseTable.stack_size_MW(i), caseTable.capacity_Nm3h(i), ...
            geom, caseTable.n_cell(i), k, ...
            describe_segments(caseTable.n_cell(i), k), ...
            isOriginal, isPipe ...
            }; %#ok<AGROW>
    end
end

T = cell2table(rows, 'VariableNames', { ...
    'design_id', 'base_case_id', 'design_label', ...
    'stack_size_MW', 'capacity_Nm3h', 'geometry', 'n_cell_total', ...
    'k_seg', 'segment_vector', 'is_original_case', 'is_pipe_interface' ...
    });
end

function kValues = default_k_for_capacity(stackSizeMW)
% R1 practical SFT scheme:
% 5 MW remains unchanged; 10 MW adds two segments; 20 MW adds two and four.
if stackSizeMW == 5
    kValues = 1;
elseif stackSizeMW == 10
    kValues = [1, 2];
elseif stackSizeMW == 20
    kValues = [1, 2, 4];
else
    kValues = 1;
end
end

function txt = describe_segments(nCell, kSeg)
segments = split_segments(nCell, kSeg);
txt = sprintf('%d+', segments);
txt = txt(1:end-1);
end

function segments = split_segments(nCell, kSeg)
base = floor(nCell / kSeg);
segments = base * ones(1, kSeg);
remainder = nCell - base * kSeg;
if remainder > 0
    segments(1:remainder) = segments(1:remainder) + 1;
end
end
