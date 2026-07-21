function summary = run_m1_m7_degradation_feature_benchmark()
%RUN_M1_M7_DEGRADATION_FEATURE_BENCHMARK
% Export Level-1 schedules and Level-2 degradation feature tables for the
% full M1-M7 plant-layer degradation benchmark.

summary = run_degradation_feature_benchmark_internal(1:7, 'plant_m1_m7_degradation_benchmark', 'm1_m7');
end
