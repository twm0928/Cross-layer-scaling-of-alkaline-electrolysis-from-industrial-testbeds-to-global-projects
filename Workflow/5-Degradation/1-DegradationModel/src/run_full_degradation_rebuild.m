function run_full_degradation_rebuild()
%RUN_FULL_DEGRADATION_REBUILD Run the rebuilt three-step degradation workflow.

fprintf('Step 1/3: build clean degradation targets...\n');
step1_build_clean_degradation_targets();

fprintf('Step 2/3: benchmark daily degradation models...\n');
step2_benchmark_daily_degradation_models();

fprintf('Step 3/3: plot degradation curves and extrapolation...\n');
step3_plot_degradation_curves();

fprintf('Degradation rebuild completed.\n');
end
