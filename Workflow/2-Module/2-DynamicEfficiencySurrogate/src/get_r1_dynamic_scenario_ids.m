function scenario_ids = get_r1_dynamic_scenario_ids(mode)
%GET_R1_DYNAMIC_SCENARIO_IDS Scenario sets used by the R1 dynamic surrogate.
%
%   GET_R1_DYNAMIC_SCENARIO_IDS('first730')    -> 1:730
%   GET_R1_DYNAMIC_SCENARIO_IDS('legacy240')   -> original 240 dynamic cases
%   GET_R1_DYNAMIC_SCENARIO_IDS('combined970') -> union of the above two sets

if nargin < 1 || isempty(mode)
    mode = 'combined970';
end

first730 = 1:730;
legacy240 = [732:2:770 771:1:830 831:5:876 881:5:926 883:5:928 ...
    931:5:976 932:5:977 933:5:978 934:5:979 981:5:1026 ...
    982:5:1027 983:5:1028 984:5:1029 1031:1080];

switch lower(string(mode))
    case "first730"
        scenario_ids = first730;
    case "legacy240"
        scenario_ids = legacy240;
    case {"combined970", "r1", "default"}
        scenario_ids = [first730 legacy240];
    otherwise
        error('Unknown scenario mode: %s', mode);
end

scenario_ids = unique(scenario_ids, 'stable');
