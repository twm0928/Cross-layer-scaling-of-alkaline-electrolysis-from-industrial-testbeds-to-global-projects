function result = run_m1_m7_degradation_experiment()
%RUN_M1_M7_DEGRADATION_EXPERIMENT
% Execute the full M1-M7 plant-layer degradation benchmark and compute
% annual hydrogen-loss summaries for every case/strategy/topology.

result = run_degradation_experiment_internal(1:7, 'plant_m1_m7_degradation_benchmark', 'm1_m7');
end
