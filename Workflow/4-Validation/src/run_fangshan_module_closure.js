const fs = require('fs');
const path = require('path');

const SCRIPT_DIR = __dirname;
const VALIDATION_ROOT = path.resolve(SCRIPT_DIR, '..');
const OUTPUT_ROOT = path.join(VALIDATION_ROOT, 'outputs');
const STEP1 = path.join(OUTPUT_ROOT, 'step1_stack_object');
const STEP4 = path.join(OUTPUT_ROOT, 'step4_stack_efficiency_interface');
const STEP5 = path.join(OUTPUT_ROOT, 'step5_module_interface_preparation');
const STEP6 = path.join(OUTPUT_ROOT, 'step6_steady_module_validation');
const STEP7 = path.join(OUTPUT_ROOT, 'step7_dynamic_module_validation');

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function parseArgs(argv) {
  const args = {};
  for (let i = 2; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token.startsWith('--')) continue;
    const key = token.slice(2);
    const next = argv[i + 1];
    if (!next || next.startsWith('--')) args[key] = true;
    else {
      args[key] = next;
      i += 1;
    }
  }
  return args;
}

function parseCsv(text) {
  const lines = text.trim().split(/\r?\n/).filter(Boolean);
  if (!lines.length) return [];
  const headers = splitCsvLine(lines[0]);
  return lines.slice(1).map((line) => {
    const cells = splitCsvLine(line);
    const row = {};
    headers.forEach((header, index) => {
      const value = cells[index] ?? '';
      const numberValue = Number(value);
      row[header] = value !== '' && Number.isFinite(numberValue) ? numberValue : value;
    });
    return row;
  });
}

function splitCsvLine(line) {
  const cells = [];
  let current = '';
  let inQuotes = false;
  for (let i = 0; i < line.length; i += 1) {
    const ch = line[i];
    if (ch === '"') {
      if (inQuotes && line[i + 1] === '"') {
        current += '"';
        i += 1;
      } else {
        inQuotes = !inQuotes;
      }
    } else if (ch === ',' && !inQuotes) {
      cells.push(current);
      current = '';
    } else {
      current += ch;
    }
  }
  cells.push(current);
  return cells;
}

function csvEscape(value) {
  if (typeof value === 'number') return Number.isFinite(value) ? String(value) : '';
  const s = String(value ?? '');
  return /[",\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

function writeCsv(file, columns, rows) {
  ensureDir(path.dirname(file));
  const lines = [columns.join(',')];
  for (const row of rows) lines.push(columns.map((column) => csvEscape(row[column])).join(','));
  fs.writeFileSync(file, `${lines.join('\n')}\n`, 'utf8');
}

function readCsv(file) {
  return parseCsv(fs.readFileSync(file, 'utf8'));
}

function mean(values) {
  const finite = values.filter(Number.isFinite);
  return finite.length ? finite.reduce((sum, value) => sum + value, 0) / finite.length : NaN;
}

function sum(values) {
  return values.filter(Number.isFinite).reduce((total, value) => total + value, 0);
}

function rmse(values) {
  const finite = values.filter(Number.isFinite);
  return finite.length ? Math.sqrt(finite.reduce((total, value) => total + value * value, 0) / finite.length) : NaN;
}

function mae(values) {
  const finite = values.filter(Number.isFinite);
  return finite.length ? finite.reduce((total, value) => total + Math.abs(value), 0) / finite.length : NaN;
}

function mape(actual, predicted) {
  const errors = [];
  for (let i = 0; i < actual.length; i += 1) {
    if (Number.isFinite(actual[i]) && Math.abs(actual[i]) > 1e-9 && Number.isFinite(predicted[i])) {
      errors.push(Math.abs(predicted[i] - actual[i]) / Math.abs(actual[i]));
    }
  }
  return mean(errors);
}

function fmt(value, digits = 4) {
  return Number.isFinite(value) ? value.toFixed(digits) : 'NA';
}

function buildInterpolator(points, xKey, yKey) {
  const sorted = points
    .map((row) => ({ x: Number(row[xKey]), y: Number(row[yKey]) }))
    .filter((row) => Number.isFinite(row.x) && Number.isFinite(row.y))
    .sort((a, b) => a.x - b.x);
  const withAnchor = [{ x: 0, y: 0 }, ...sorted];
  return (x) => {
    if (!Number.isFinite(x) || x <= 0) return 0;
    if (x <= withAnchor[0].x) return withAnchor[0].y;
    for (let i = 1; i < withAnchor.length; i += 1) {
      const left = withAnchor[i - 1];
      const right = withAnchor[i];
      if (x <= right.x) {
        const ratio = (x - left.x) / (right.x - left.x);
        return left.y + ratio * (right.y - left.y);
      }
    }
    const last = withAnchor[withAnchor.length - 1];
    return last.y;
  };
}

function evaluateInterface(row, predictors) {
  const load = Number(row.load_fraction);
  const h2Rate = predictors.h2Rate(load);
  const etaStack = predictors.etaStack(load);
  const etaCurrent = predictors.etaCurrent(load);
  const etaVoltage = predictors.etaVoltage(load);
  return {
    predicted_H2_rate_Nm3h: h2Rate,
    predicted_H2_step_Nm3: h2Rate * 0.25,
    predicted_eta_stack_LHV: etaStack,
    predicted_eta_current: etaCurrent,
    predicted_eta_voltage_LHV: etaVoltage,
  };
}

function metricsFromRows(rows, actualKey, predKey) {
  const actual = rows.map((row) => Number(row[actualKey]));
  const predicted = rows.map((row) => Number(row[predKey]));
  const errors = predicted.map((value, index) => value - actual[index]);
  return {
    n: rows.length,
    MAE: mae(errors),
    RMSE: rmse(errors),
    MAPE: mape(actual, predicted),
    actual_sum: sum(actual),
    predicted_sum: sum(predicted),
    relative_sum_error: (sum(predicted) - sum(actual)) / sum(actual),
  };
}

function groupBy(rows, keyFn) {
  const groups = new Map();
  for (const row of rows) {
    const key = keyFn(row);
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(row);
  }
  return groups;
}

function firstOrderLag(values, tauHours, dtHours) {
  if (tauHours <= 0) return [...values];
  const alpha = Math.exp(-dtHours / tauHours);
  const out = [];
  let y = values[0] || 0;
  for (let i = 0; i < values.length; i += 1) {
    y = alpha * y + (1 - alpha) * (values[i] || 0);
    out.push(y);
  }
  return out;
}

function metricRowsFromSummary(prefix, metrics, unit) {
  return [
    { scope: prefix, metric: `MAE_${unit}`, value: metrics.MAE },
    { scope: prefix, metric: `RMSE_${unit}`, value: metrics.RMSE },
    { scope: prefix, metric: 'MAPE', value: metrics.MAPE },
    { scope: prefix, metric: `actual_sum_${unit}`, value: metrics.actual_sum },
    { scope: prefix, metric: `predicted_sum_${unit}`, value: metrics.predicted_sum },
    { scope: prefix, metric: 'relative_sum_error', value: metrics.relative_sum_error },
    { scope: prefix, metric: 'n', value: metrics.n },
  ];
}

function metricRowsErrorOnly(prefix, metrics, unit) {
  return [
    { scope: prefix, metric: `MAE_${unit}`, value: metrics.MAE },
    { scope: prefix, metric: `RMSE_${unit}`, value: metrics.RMSE },
    { scope: prefix, metric: 'MAPE', value: metrics.MAPE },
    { scope: prefix, metric: 'n', value: metrics.n },
  ];
}

function mdMetricTable(rows) {
  return [
    '| Scope | Metric | Value |',
    '|---|---|---:|',
    ...rows.map((row) => `| ${row.scope} | ${row.metric} | ${fmt(Number(row.value), 6)} |`),
  ];
}

function main() {
  const args = parseArgs(process.argv);
  const day = args.day || '2023-11-05';
  ensureDir(STEP5);
  ensureDir(STEP6);
  ensureDir(STEP7);

  const profileFile = path.join(STEP1, 'fangshan_module_aligned_15min_profiles.csv');
  const selectedWindowFile = path.join(OUTPUT_ROOT, 'step3_current_efficiency_validation', 'fangshan_selected_h2_windows.csv');
  const interfaceFile = path.join(STEP4, 'stackA_piecewise_efficiency_curve.csv');

  const profiles = readCsv(profileFile);
  const selectedWindows = readCsv(selectedWindowFile);
  const piecewise = readCsv(interfaceFile);

  const predictors = {
    h2Rate: buildInterpolator(piecewise, 'load_mean', 'H2_mean_Nm3h'),
    etaStack: buildInterpolator(piecewise, 'load_mean', 'eta_stack_LHV_mean'),
    etaCurrent: buildInterpolator(piecewise, 'load_mean', 'eta_current_mean'),
    etaVoltage: buildInterpolator(piecewise, 'load_mean', 'eta_voltage_LHV_mean'),
  };

  const moduleInterfaceRows = piecewise.map((row) => ({
    load_fraction: row.load_mean,
    stack_power_MW: row.power_MW_mean,
    H2_rate_Nm3h: row.H2_mean_Nm3h,
    H2_step_Nm3_per_15min: Number(row.H2_mean_Nm3h) * 0.25,
    eta_current: row.eta_current_mean,
    eta_voltage_LHV: row.eta_voltage_LHV_mean,
    eta_stack_LHV: row.eta_stack_LHV_mean,
    n_windows: row.n,
    note: 'Field Stack A interface used as measured stack-to-module boundary.',
  }));
  writeCsv(
    path.join(STEP5, 'module_input_stackA_interface.csv'),
    ['load_fraction', 'stack_power_MW', 'H2_rate_Nm3h', 'H2_step_Nm3_per_15min', 'eta_current', 'eta_voltage_LHV', 'eta_stack_LHV', 'n_windows', 'note'],
    moduleInterfaceRows,
  );

  const mappingRows = [
    { module_quantity: 'Power input', plc_or_model_source: 'IA6001 * IV6001', unit: 'MW', role: 'Measured stack DC/module boundary power at 15 min resolution.' },
    { module_quantity: 'Hydrogen output', plc_or_model_source: 'FT1005', unit: 'Nm3 h-1', role: 'Measured module outlet hydrogen flow for validation.' },
    { module_quantity: 'Hydrogen per time step', plc_or_model_source: 'FT1005 * 0.25 h', unit: 'Nm3 per 15 min', role: 'Measured dynamic validation target.' },
    { module_quantity: 'Stack inlet temperature', plc_or_model_source: 'TT1002', unit: 'degC', role: 'Thermal-state validation/supporting condition.' },
    { module_quantity: 'Stack outlet temperature', plc_or_model_source: 'TT1007/TT1008', unit: 'degC', role: 'Thermal-state validation/supporting condition.' },
    { module_quantity: 'Pressure', plc_or_model_source: 'PT1012/PT1013', unit: 'MPa', role: 'Pressure stability filter and BOP operating condition.' },
  ];
  writeCsv(path.join(STEP5, 'fangshan_module_boundary_mapping.csv'), ['module_quantity', 'plc_or_model_source', 'unit', 'role'], mappingRows);

  const steadyRows = selectedWindows.map((row) => {
    const prediction = evaluateInterface(row, predictors);
    const measuredStep = Number(row.H2_mean_Nm3h) * 0.25;
    return {
      source_file: row.source_file,
      start: row.start,
      load_fraction: row.load_fraction,
      measured_power_MW: row.power_MW,
      measured_H2_rate_Nm3h: row.H2_mean_Nm3h,
      measured_H2_step_Nm3: measuredStep,
      measured_eta_stack_LHV: row.eta_stack_LHV_measured,
      ...prediction,
      error_H2_rate_Nm3h: prediction.predicted_H2_rate_Nm3h - Number(row.H2_mean_Nm3h),
      error_H2_step_Nm3: prediction.predicted_H2_step_Nm3 - measuredStep,
      error_eta_stack_LHV: prediction.predicted_eta_stack_LHV - Number(row.eta_stack_LHV_measured),
    };
  });
  writeCsv(
    path.join(STEP6, 'steady_window_module_validation.csv'),
    [
      'source_file', 'start', 'load_fraction', 'measured_power_MW',
      'measured_H2_rate_Nm3h', 'measured_H2_step_Nm3', 'measured_eta_stack_LHV',
      'predicted_H2_rate_Nm3h', 'predicted_H2_step_Nm3', 'predicted_eta_stack_LHV',
      'predicted_eta_current', 'predicted_eta_voltage_LHV',
      'error_H2_rate_Nm3h', 'error_H2_step_Nm3', 'error_eta_stack_LHV',
    ],
    steadyRows,
  );

  const steadyMetrics = metricsFromRows(steadyRows, 'measured_H2_rate_Nm3h', 'predicted_H2_rate_Nm3h');
  const steadyStepMetrics = metricsFromRows(steadyRows, 'measured_H2_step_Nm3', 'predicted_H2_step_Nm3');
  const etaMetrics = metricsFromRows(steadyRows, 'measured_eta_stack_LHV', 'predicted_eta_stack_LHV');
  const steadyMetricRows = [
    ...metricRowsErrorOnly('steady_windows_H2_rate_profile', steadyMetrics, 'Nm3h'),
    ...metricRowsFromSummary('steady_windows_H2_step_total', steadyStepMetrics, 'Nm3'),
    ...metricRowsErrorOnly('steady_windows_eta_stack_profile', etaMetrics, 'fraction'),
  ];

  const dayGroups = groupBy(steadyRows, (row) => String(row.start).slice(0, 10));
  for (const [groupDay, groupRows] of [...dayGroups.entries()].sort()) {
    const m = metricsFromRows(groupRows, 'measured_H2_step_Nm3', 'predicted_H2_step_Nm3');
    steadyMetricRows.push(...metricRowsFromSummary(`steady_windows_H2_step_total_${groupDay}`, m, 'Nm3'));
  }
  writeCsv(path.join(STEP6, 'steady_window_validation_metrics.csv'), ['scope', 'metric', 'value'], steadyMetricRows);

  const dynamicRows = profiles
    .filter((row) => row.day === day)
    .sort((a, b) => Number(a.slot) - Number(b.slot))
    .map((row) => {
      const prediction = evaluateInterface(row, predictors);
      return {
        day: row.day,
        slot: row.slot,
        time_h: row.time_h,
        measured_power_MW: row.power_MW,
        measured_load_fraction: row.load_fraction,
        measured_H2_rate_Nm3h: row.H2_rate_Nm3h,
        measured_H2_step_Nm3: row.H2_step_Nm3,
        measured_eta_stack_LHV: row.eta_stack_LHV_measured,
        ...prediction,
        error_H2_rate_Nm3h: prediction.predicted_H2_rate_Nm3h - Number(row.H2_rate_Nm3h),
        error_H2_step_Nm3: prediction.predicted_H2_step_Nm3 - Number(row.H2_step_Nm3),
      };
    });

  const rawPredicted = dynamicRows.map((row) => row.predicted_H2_rate_Nm3h);
  const measuredRate = dynamicRows.map((row) => Number(row.measured_H2_rate_Nm3h));
  const lagCandidates = [0, 0.25, 0.5, 1, 2];
  const lagRows = lagCandidates.map((tau) => {
    const lagged = firstOrderLag(rawPredicted, tau, 0.25);
    return {
      tau_h: tau,
      MAE_Nm3h: mae(lagged.map((value, index) => value - measuredRate[index])),
      RMSE_Nm3h: rmse(lagged.map((value, index) => value - measuredRate[index])),
      MAPE: mape(measuredRate, lagged),
      predicted_daily_H2_Nm3: sum(lagged.map((value) => value * 0.25)),
      measured_daily_H2_Nm3: sum(dynamicRows.map((row) => Number(row.measured_H2_step_Nm3))),
    };
  });
  for (const row of lagRows) row.relative_daily_error = (row.predicted_daily_H2_Nm3 - row.measured_daily_H2_Nm3) / row.measured_daily_H2_Nm3;
  const bestLag = lagRows.reduce((best, row) => (row.RMSE_Nm3h < best.RMSE_Nm3h ? row : best), lagRows[0]);
  const bestLaggedRate = firstOrderLag(rawPredicted, bestLag.tau_h, 0.25);
  dynamicRows.forEach((row, index) => {
    row.lagged_H2_rate_Nm3h = bestLaggedRate[index];
    row.lagged_H2_step_Nm3 = bestLaggedRate[index] * 0.25;
    row.lagged_error_H2_rate_Nm3h = bestLaggedRate[index] - Number(row.measured_H2_rate_Nm3h);
  });

  writeCsv(
    path.join(STEP7, `dynamic_day_${day}_module_validation_profile.csv`),
    [
      'day', 'slot', 'time_h', 'measured_power_MW', 'measured_load_fraction',
      'measured_H2_rate_Nm3h', 'measured_H2_step_Nm3', 'measured_eta_stack_LHV',
      'predicted_H2_rate_Nm3h', 'predicted_H2_step_Nm3', 'predicted_eta_stack_LHV',
      'error_H2_rate_Nm3h', 'error_H2_step_Nm3',
      'lagged_H2_rate_Nm3h', 'lagged_H2_step_Nm3', 'lagged_error_H2_rate_Nm3h',
    ],
    dynamicRows,
  );
  writeCsv(path.join(STEP7, `dynamic_day_${day}_lag_sensitivity.csv`), ['tau_h', 'MAE_Nm3h', 'RMSE_Nm3h', 'MAPE', 'predicted_daily_H2_Nm3', 'measured_daily_H2_Nm3', 'relative_daily_error'], lagRows);

  const dynamicRateMetrics = metricsFromRows(dynamicRows, 'measured_H2_rate_Nm3h', 'predicted_H2_rate_Nm3h');
  const dynamicStepMetrics = metricsFromRows(dynamicRows, 'measured_H2_step_Nm3', 'predicted_H2_step_Nm3');
  const laggedRows = dynamicRows.map((row) => ({
    measured_H2_step_Nm3: row.measured_H2_step_Nm3,
    lagged_H2_step_Nm3: row.lagged_H2_step_Nm3,
    measured_H2_rate_Nm3h: row.measured_H2_rate_Nm3h,
    lagged_H2_rate_Nm3h: row.lagged_H2_rate_Nm3h,
  }));
  const dynamicLagRateMetrics = metricsFromRows(laggedRows, 'measured_H2_rate_Nm3h', 'lagged_H2_rate_Nm3h');
  const dynamicLagStepMetrics = metricsFromRows(laggedRows, 'measured_H2_step_Nm3', 'lagged_H2_step_Nm3');
  const dynamicLagMetrics = {
    n: dynamicRows.length,
    MAE: bestLag.MAE_Nm3h,
    RMSE: bestLag.RMSE_Nm3h,
    MAPE: bestLag.MAPE,
    actual_sum: bestLag.measured_daily_H2_Nm3,
    predicted_sum: bestLag.predicted_daily_H2_Nm3,
    relative_sum_error: bestLag.relative_daily_error,
  };
  const dynamicMetricRows = [
    ...metricRowsErrorOnly(`dynamic_${day}_raw_H2_rate_profile`, dynamicRateMetrics, 'Nm3h'),
    ...metricRowsFromSummary(`dynamic_${day}_raw_H2_step_total`, dynamicStepMetrics, 'Nm3'),
    ...metricRowsErrorOnly(`dynamic_${day}_lagged_H2_rate_profile_tau_${bestLag.tau_h}h`, dynamicLagRateMetrics, 'Nm3h'),
    ...metricRowsFromSummary(`dynamic_${day}_lagged_H2_step_total_tau_${bestLag.tau_h}h`, dynamicLagStepMetrics, 'Nm3'),
  ];
  writeCsv(path.join(STEP7, `dynamic_day_${day}_validation_metrics.csv`), ['scope', 'metric', 'value'], dynamicMetricRows);

  const step5Readme = [
    '# Step 5 Module Interface Preparation',
    '',
    'Purpose: convert the experimentally validated Stack A efficiency curve into the module-boundary interface used by the Fangshan validation case.',
    '',
    'Parameter lineage:',
    '',
    '- Stack A physical parameters are used in Steps 1-4, not re-fitted here: 400 cells, 1.54 m2 electrode area, 6600 A rated current, 720 V rated voltage and 4.752 MW rated power.',
    '- These parameters determine the measured load fraction, current density, per-cell voltage, theoretical Faradaic hydrogen production and voltage/current-efficiency decomposition.',
    '- Step 5 therefore uses the Stack A parameterised interface generated in Step 4, rather than the generic Table S4 search-region stack parameters.',
    '',
    'Data used:',
    '',
    '- `../step4_stack_efficiency_interface/stackA_piecewise_efficiency_curve.csv`.',
    '- PLC boundary definitions from the 15 min module-aligned profile.',
    '',
    'Model/interface:',
    '',
    '- The module input is a piecewise linear map from measured stack load fraction to hydrogen production and stack efficiency.',
    '- Power is treated at the measured stack DC/module boundary (`IA6001 * IV6001`). Auxiliary power is not inferred here because pump/fan electrical power is not yet fully available from the PLC extract.',
    '- This step validates the field Stack A interface at the Fangshan module boundary. It does not replace the M1-M7 design-search interfaces and does not yet rerun the full state-space optimisation model with Stack A parameters.',
    '',
    'Outputs:',
    '',
    '- `module_input_stackA_interface.csv`.',
    '- `fangshan_module_boundary_mapping.csv`.',
    '',
  ].join('\n');
  fs.writeFileSync(path.join(STEP5, 'README.md'), step5Readme, 'utf8');

  const step6Readme = [
    '# Step 6 Steady Module Validation',
    '',
    'Purpose: check whether the module-boundary interface reconstructs measured hydrogen production under quasi-steady windows.',
    '',
    'Data used:',
    '',
    '- `../step3_current_efficiency_validation/fangshan_selected_h2_windows.csv`.',
    '- `../step5_module_interface_preparation/module_input_stackA_interface.csv`.',
    '',
    'Validated model/interface:',
    '',
    '- Piecewise Stack A hydrogen-production interface at the Fangshan module boundary.',
    '- This is an interface-level module closure: measured power is passed through the Stack A parameterised interface and compared with measured outlet hydrogen flow.',
    '- It is not yet a full BOP thermal/HTO state-space simulation with all Stack A parameters embedded into `cluster_UC_I4.m`.',
    '- Quasi-steady stack-to-module conversion from measured power to measured outlet hydrogen flow.',
    '',
    'Quantitative results:',
    '',
    ...mdMetricTable(steadyMetricRows),
    '',
    'Outputs:',
    '',
    '- `steady_window_module_validation.csv`.',
    '- `steady_window_validation_metrics.csv`.',
    '',
  ].join('\n');
  fs.writeFileSync(path.join(STEP6, 'README.md'), step6Readme, 'utf8');

  const step7Readme = [
    '# Step 7 Dynamic Module Validation',
    '',
    `Purpose: perform a full-day dynamic stack-to-module validation using the ${day} 96-point measured power profile.`,
    '',
    'Data used:',
    '',
    '- `../step1_stack_object/fangshan_module_aligned_15min_profiles.csv`.',
    '- `../step5_module_interface_preparation/module_input_stackA_interface.csv`.',
    '',
    'Validated model/interface:',
    '',
    '- Dynamic daily closure from measured power profile to measured hydrogen-production profile using the Stack A parameterised interface.',
    '- The raw interface gives instantaneous stack hydrogen production. A first-order lag sensitivity is also reported to diagnose BOP gas-line/flow-meter buffering.',
    '- This validates the dynamic stack-to-module boundary at the measured DC-power/H2-flow level; full thermal and HTO state validation would require running the complete Fangshan BOP state-space model with Stack A parameters.',
    '',
    `Best lag candidate by profile RMSE: tau = ${bestLag.tau_h} h.`,
    '',
    'Quantitative results:',
    '',
    ...mdMetricTable(dynamicMetricRows),
    '',
    'Outputs:',
    '',
    `- dynamic_day_${day}_module_validation_profile.csv.`,
    `- dynamic_day_${day}_validation_metrics.csv.`,
    `- dynamic_day_${day}_lag_sensitivity.csv.`,
    '',
  ].join('\n');
  fs.writeFileSync(path.join(STEP7, 'README.md'), step7Readme, 'utf8');

  const closureReport = [
    '# Fangshan Module Closure Validation Report',
    '',
    'This report extends Steps 1-4 of the experimental validation to the module boundary. The calculation uses the experimentally derived Stack A parameterised interface and measured 15 min Fangshan profiles.',
    '',
    'Important boundary statement: Stack A physical parameters are used in Steps 1-4 to build the interface: cell number, electrode area, rated power/current, per-cell voltage, current density and Faradaic hydrogen conversion. Steps 5-7 do not ignore Stack A; they use the resulting Stack A interface. What is not yet done is rerunning the complete BOP state-space optimisation model (`cluster_UC_I4.m`) with Stack A parameters embedded as a new topology.',
    '',
    '## Step 5 Module Interface Preparation',
    '',
    'The Stack A piecewise curve is converted into a module-boundary input table. The boundary power is the measured rectifier DC power from `IA6001 * IV6001`, and the validation target is the measured outlet hydrogen flow from `FT1005`. In other words, the check is `measured P(t) -> Stack A parameterised interface -> predicted H2(t)`, compared with measured H2(t).',
    '',
    '## Step 6 Steady Module Validation',
    '',
    'Steady validation uses the selected pressure/flow-stable hydrogen windows from Step 3.',
    '',
    ...mdMetricTable(steadyMetricRows),
    '',
    '## Step 7 Full-Day Dynamic Module Validation',
    '',
    `Dynamic validation uses the full ${day} profile. This is the preferred end-to-end experimental check within the available 5 MW testbed because it preserves the original 96-point 15 min time scale used in the paper.`,
    '',
    ...mdMetricTable(dynamicMetricRows),
    '',
    '## Interpretation',
    '',
    '- Step 6 quantifies whether the stack-to-module interface reconstructs quasi-steady measured hydrogen flow.',
    '- Step 7 quantifies whether the same interface reproduces a complete day of measured hydrogen production.',
    '- The lag sensitivity does not change the stack model; it diagnoses the effect of gas-line buffering and flow-meter delay at the BOP/module boundary.',
    '',
  ].join('\n');
  fs.writeFileSync(path.join(OUTPUT_ROOT, 'experimental_validation_report_module_closure.md'), closureReport, 'utf8');

  console.log(`steady_windows=${steadyRows.length}`);
  console.log(`steady_H2_RMSE=${steadyMetrics.RMSE.toFixed(3)} Nm3/h, MAPE=${(steadyMetrics.MAPE * 100).toFixed(3)}%`);
  console.log(`dynamic_day=${day}, points=${dynamicRows.length}`);
  console.log(`dynamic_raw_daily_error=${(dynamicStepMetrics.relative_sum_error * 100).toFixed(3)}%`);
  console.log(`dynamic_best_lag_tau=${bestLag.tau_h} h, lagged_daily_error=${(dynamicLagMetrics.relative_sum_error * 100).toFixed(3)}%`);
}

main();
