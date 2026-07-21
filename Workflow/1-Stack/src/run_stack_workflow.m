function outputs = run_stack_workflow()
%RUN_STACK_WORKFLOW Regenerate all stack-layer R1 outputs.
%
% This is the top-level stack-layer entry point. It keeps the SI model-data
% generation and Fig. 2a source-data export callable as separate functions,
% but provides one command when both outputs need to be refreshed.

cfg = pipeline_config();
addpath(cfg.stack_model_dir);

outputs = struct();
outputs.si = run_stack_sft_si();

projectRoot = fileparts(cfg.workflow_root);
fig2aOutDir = fullfile(projectRoot, 'Figure', 'Figure 2a', 'data');
fig2bOutDir = fullfile(projectRoot, 'Figure', 'Figure 2b', 'data');
outputs.fig2a = export_fig2a_stack_efficiency_sources(fig2aOutDir);
outputs.fig2b = export_fig2b_stack_distribution_sources(fig2bOutDir);

disp('Stack workflow completed.');
disp(outputs.si.output_dir);
disp(fig2aOutDir);
disp(fig2bOutDir);
end
