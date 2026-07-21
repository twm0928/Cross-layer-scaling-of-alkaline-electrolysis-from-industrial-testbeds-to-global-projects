# Clean upload workflow

This folder is the clean upload package for the revised cross-layer electrolysis scale-up workflow.

## Scope

Retained contents include executable MATLAB/JavaScript/PowerShell code, required CSV/XLSX/MAT/JSON input data, reusable model and interface files, and final tabular outputs needed to reproduce or inspect the workflow.

Excluded contents include manuscript drafts, reports, figures, logs, presentations, HTML documents, intermediate plotting products, and large regenerable process MAT files from plant-level daily scheduling calculations.

## Layer order

1. 1-Stack: stack model and stack efficiency interface.
2. 2-Module: module state-space model, dynamic efficiency surrogate, and static efficiency interface.
3. 3-Plant: theta-rule-based scheduling and optimisation-based scheduling, both evaluated through the dynamic module efficiency interface.
4. 4-Validation: industrial stack and 5 MW 1-in-1 module validation data and scripts.
5. 5-Degradation: daily degradation-voltage model and plant-level degradation correction.
6. 6-Project: project-level economic evaluation and degradation sensitivity.

## Dataset mapping for the Supplementary Information

The Supplementary Information describes five datasets, Dataset A to Dataset E. In this upload package, these datasets are organised by workflow layer rather than by a separate Dataset A-E folder. The mapping is as follows.

### Dataset A: physical input library

Role: model-interface inputs for stack and module calculations.

Locations:

- `1-Stack/outputs/stack_sft/`
- `2-Module/data/input/`
- `2-Module/data/results/`
- `2-Module/data/dynamic_models/`
- `2-Module/2-DynamicEfficiencySurrogate/outputs/final_locked/`
- `2-Module/3-StaticEfficiencyInterface/outputs/final_locked/`
- `3-Plant/data/module_dynamic_models/`
- `3-Plant/data/module_static_interface/`

### Dataset B: global project data

Role: project-level metadata, renewable profiles, and topology CAPEX inputs.

Locations:

- `6-Project/data/input/ProjectInfo.xlsx`
- `6-Project/data/input/Project profiles.xlsx`
- `6-Project/data/input/topology_capex_M1_M7.xlsx`
- `6-Project/data/input/topology_capex_M1_M7.csv`

### Dataset C: independent stack-test validation data

Role: independent industrial stack-test data for stack-layer validation.

Locations:

- `4-Validation/raw_data/stackA_cell_test/`
- `4-Validation/outputs/step9_stackA_independent_validation/`
- `4-Validation/outputs/step10_stackA_distribution_model_comparison/`

### Dataset D: 5 MW 1-in-1 module-test validation data

Role: Fangshan testbed data for stack-to-module validation.

Locations:

- `4-Validation/raw_data/stackB_fangshan/`
- `4-Validation/outputs/step1_stack_object/`
- `4-Validation/outputs/step2_voltage_model_validation/`
- `4-Validation/outputs/step3_current_efficiency_validation/`
- `4-Validation/outputs/step4_stack_efficiency_interface/`
- `4-Validation/outputs/step6_steady_module_validation/`
- `4-Validation/outputs/step7_dynamic_module_validation/`
- `4-Validation/outputs/step8_full_statespace_single5MW_validation/`

### Dataset E: PV/WT-driven long-term degradation data

Role: six-unit operating data for degradation modelling and plant-level degradation correction.

Locations:

- `5-Degradation/1-DegradationModel/raw_data/`
- `5-Degradation/1-DegradationModel/current_version/`
- `5-Degradation/2-DegradationResults/outputs/plant_m1_m7_degradation_benchmark/`
- `6-Project/2-DegradationCorrectedProject/`
- `6-Project/3-DegradationUncertaintyProject/`

Some interface files are intentionally duplicated across layers. For example, the final dynamic module-efficiency models and static module power-hydrogen maps are generated in `2-Module` and copied to `3-Plant` for downstream plant scheduling. These copies are retained so that each layer can be inspected or rerun without manually tracing files from the upstream layer.

## Notes for reuse

- Each directory contains its own README.md.
- upload_manifest.csv records every retained non-README file and its size.
- MATLAB scripts assume paths relative to the layer directories unless otherwise stated in the script.
- Code variable names may retain historical file or folder names for reproducibility; README descriptions use the current manuscript terminology.
