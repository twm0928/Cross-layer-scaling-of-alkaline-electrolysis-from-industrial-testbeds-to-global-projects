# Cross-layer scaling of alkaline electrolysis from industrial testbeds to global projects

This repository contains the MATLAB workflow accompanying the study. It connects stack, module, plant, degradation, validation, and project-level calculations in a single inspectable package.

## Workflow structure

1. `Workflow/1-Stack`: stack model, scaling search region, and stack-efficiency interface.
2. `Workflow/2-Module`: module state-space model, dynamic-efficiency surrogate, and static-efficiency interface.
3. `Workflow/3-Plant`: theta-rule-based and optimisation-based scheduling with dynamic evaluation.
4. `Workflow/4-Validation`: industrial stack and 5 MW 1-in-1 module validation data and scripts.
5. `Workflow/5-Degradation`: daily degradation-voltage model and plant-level degradation correction.
6. `Workflow/6-Project`: project-level economic evaluation, coupled optimisation, and degradation uncertainty.

## Reuse

Start with [`Workflow/README.md`](Workflow/README.md), which maps Datasets A-E to their repository locations and explains the layer execution order. Every layer and major subdirectory contains a dedicated README describing its inputs, outputs, and scripts.

The complete offline module label-generation calculation is computationally intensive. Locked intermediate interfaces and final tabular outputs are retained so that downstream plant and project calculations can be inspected or reproduced without repeating the full offline calculation.
