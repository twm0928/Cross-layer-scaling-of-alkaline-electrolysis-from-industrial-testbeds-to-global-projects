const fs = require('fs');
const path = require('path');

const EV_ROOT = path.resolve(__dirname, '..');
const WORKFLOW_ROOT = path.resolve(EV_ROOT, '..');
const OUTPUT_ROOT = path.join(EV_ROOT, 'outputs', 'step9_stackA_independent_validation');
const DEFAULT_DATA_DIR = path.join(EV_ROOT, 'raw_data', 'stackB_cell_test');
const CONFIG_PATH = path.join(EV_ROOT, 'config', 'stackA_independent.json');

const F = 96485.33212;

function parseArgs(argv) {
  const out = { dataDir: DEFAULT_DATA_DIR };
  for (let i = 2; i < argv.length; i += 1) {
    if (argv[i] === '--data-dir') out.dataDir = path.resolve(argv[++i]);
  }
  return out;
}

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function splitCsvLine(line) {
  return line.split(',');
}

function writeCsv(file, rows, columns) {
  const lines = [columns.join(',')];
  for (const row of rows) {
    lines.push(columns.map((c) => row[c] ?? '').join(','));
  }
  fs.writeFileSync(file, `${lines.join('\n')}\n`, 'utf8');
}

function mean(values) {
  if (!values.length) return NaN;
  return values.reduce((a, b) => a + b, 0) / values.length;
}

function std(values) {
  if (values.length < 2) return 0;
  const m = mean(values);
  return Math.sqrt(values.reduce((s, x) => s + (x - m) ** 2, 0) / values.length);
}

function median(values) {
  if (!values.length) return NaN;
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid] : 0.5 * (sorted[mid - 1] + sorted[mid]);
}

function quantile(values, q) {
  if (!values.length) return NaN;
  const sorted = [...values].sort((a, b) => a - b);
  const idx = (sorted.length - 1) * q;
  const lo = Math.floor(idx);
  const hi = Math.ceil(idx);
  if (lo === hi) return sorted[lo];
  return sorted[lo] * (hi - idx) + sorted[hi] * (idx - lo);
}

function round(x, digits = 6) {
  if (!Number.isFinite(x)) return '';
  return Number(x.toFixed(digits));
}

function windowStart(tsText, minutes = 15) {
  const [datePart, timePart] = tsText.split(' ');
  const [y, m, d] = datePart.split('-').map(Number);
  const [hh, mm, ss] = timePart.split(':').map(Number);
  const floored = Math.floor(mm / minutes) * minutes;
  return `${String(y).padStart(4, '0')}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')} ${String(hh).padStart(2, '0')}:${String(floored).padStart(2, '0')}:00`;
}

function toDateTimeKey(tsText) {
  return tsText.replace('+08', '');
}

function idealH2Nm3h(currentA, nCells, normalMolarVolumeLmol) {
  return nCells * currentA / (2 * F) * normalMolarVolumeLmol * 3.6;
}

function addWindowSample(w, row, idx) {
  const current = Number(row[idx.rectifier_current]);
  const h2 = Number(row[idx.h2_flow]);
  const voltage = Number(row[idx.rectifier_voltage]);
  const power = Number(row[idx.rectifier_power_kw_raw]);
  const stackVoltageSum = Number(row[idx.cell_stack_voltage_sum]);
  const cellVoltageMean = Number(row[idx.cell_voltage_mean]);
  const tempMean = Number(row[idx.cell_temperature_mean]);
  const tempMax = Number(row[idx.cell_temperature_max]);
  const tempMin = Number(row[idx.cell_temperature_min]);
  const pressure = 0.5 * (Number(row[idx.h2_separator_pressure]) + Number(row[idx.o2_separator_pressure]));
  const alkaliFlow = Number(row[idx.alkali_circulation_flow]);
  w.n += 1;
  w.currents.push(current);
  w.h2.push(h2);
  w.voltages.push(voltage);
  w.powers.push(power);
  w.stackVoltageSums.push(stackVoltageSum);
  w.cellVoltageMeans.push(cellVoltageMean);
  w.tempMeans.push(tempMean);
  w.tempMaxes.push(tempMax);
  w.tempMins.push(tempMin);
  w.pressures.push(pressure);
  w.alkaliFlows.push(alkaliFlow);
  if (current > 10) w.running += 1;
}

function solveLinear(a, b) {
  const n = a.length;
  const m = a.map((row, i) => [...row, b[i]]);
  for (let col = 0; col < n; col += 1) {
    let pivot = col;
    for (let r = col + 1; r < n; r += 1) {
      if (Math.abs(m[r][col]) > Math.abs(m[pivot][col])) pivot = r;
    }
    if (pivot !== col) [m[pivot], m[col]] = [m[col], m[pivot]];
    const div = m[col][col];
    if (Math.abs(div) < 1e-12) throw new Error('Singular linear system in voltage fit.');
    for (let c = col; c < n + 1; c += 1) m[col][c] /= div;
    for (let r = 0; r < n; r += 1) {
      if (r === col) continue;
      const factor = m[r][col];
      for (let c = col; c < n + 1; c += 1) m[r][c] -= factor * m[col][c];
    }
  }
  return m.map((row) => row[n]);
}

function fitVoltageModel(rows, stack) {
  const nParam = 4;
  const xtx = Array.from({ length: nParam }, () => Array(nParam).fill(0));
  const xty = Array(nParam).fill(0);
  for (const row of rows) {
    const j = row.mean_effective_electrolysis_current_A / stack.electrode_area_m2;
    const t = row.cell_temperature_mean_C;
    const x = [1, t, j, j * t];
    const y = row.mean_valid_cell_voltage_V;
    for (let i = 0; i < nParam; i += 1) {
      xty[i] += x[i] * y;
      for (let k = 0; k < nParam; k += 1) xtx[i][k] += x[i] * x[k];
    }
  }
  return solveLinear(xtx, xty);
}

function predictCellVoltage(coeffs, row, stack) {
  const j = row.mean_effective_electrolysis_current_A / stack.electrode_area_m2;
  const t = row.cell_temperature_mean_C;
  return coeffs[0] + coeffs[1] * t + coeffs[2] * j + coeffs[3] * j * t;
}

function readProcessWindows(dataDir, stack) {
  const file = path.join(dataDir, 'process.csv');
  const fd = fs.openSync(file, 'r');
  const content = fs.readFileSync(fd, 'utf8');
  fs.closeSync(fd);
  const lines = content.split(/\r?\n/).filter(Boolean);
  const header = splitCsvLine(lines[0]).map((h) => h.replace(/^\uFEFF/, '').trim());
  const idx = Object.fromEntries(header.map((h, i) => [h, i]));
  const windows = new Map();

  for (let i = 1; i < lines.length; i += 1) {
    const row = splitCsvLine(lines[i]);
    if (row[idx.experiment_id] !== '20250915') continue;
    const key = windowStart(row[idx.timestamp], 15);
    if (!windows.has(key)) {
      windows.set(key, {
        window_start: key,
        n: 0,
        running: 0,
        currents: [],
        h2: [],
        voltages: [],
        powers: [],
        stackVoltageSums: [],
        cellVoltageMeans: [],
        tempMeans: [],
        tempMaxes: [],
        tempMins: [],
        pressures: [],
        alkaliFlows: [],
      });
    }
    addWindowSample(windows.get(key), row, idx);
  }

  const rows = [];
  for (const w of [...windows.values()].sort((a, b) => a.window_start.localeCompare(b.window_start))) {
    if (w.n < 600) continue;
    const meanCurrent = mean(w.currents);
    const meanH2 = mean(w.h2);
    const idealH2 = idealH2Nm3h(meanCurrent, stack.n_cells, stack.normal_molar_volume_L_mol);
    const cellVoltageMean = mean(w.cellVoltageMeans);
    const validVoltageChannelCount = stack.valid_voltage_channel_count || stack.n_cells;
    const validCellVoltageMean = mean(w.stackVoltageSums) / validVoltageChannelCount;
    const voltageEfficiency = stack.thermoneutral_voltage_V / validCellVoltageMean;
    const etaCurrent = idealH2 > 0 ? meanH2 / idealH2 : NaN;
    const meanEffectiveElectrolysisCurrent = meanCurrent * etaCurrent;
    const row = {
      window_start: w.window_start,
      n_samples: w.n,
      run_fraction: w.running / w.n,
      mean_current_A: meanCurrent,
      mean_effective_electrolysis_current_A: meanEffectiveElectrolysisCurrent,
      std_current_A: std(w.currents),
      mean_h2_flow_Nm3h: meanH2,
      std_h2_flow_Nm3h: std(w.h2),
      mean_rectifier_voltage_V: mean(w.voltages),
      mean_power_kW: mean(w.powers),
      mean_cell_voltage_V: cellVoltageMean,
      mean_valid_cell_voltage_V: validCellVoltageMean,
      mean_cell_stack_voltage_sum_V: mean(w.stackVoltageSums),
      cell_temperature_mean_C: mean(w.tempMeans),
      cell_temperature_max_C: mean(w.tempMaxes),
      cell_temperature_min_C: mean(w.tempMins),
      mean_pressure_MPa: mean(w.pressures),
      mean_alkali_flow_m3h: mean(w.alkaliFlows),
      load_fraction: meanCurrent / stack.rated_current_A,
      ideal_h2_flow_Nm3h: idealH2,
      eta_current_measured: etaCurrent,
      voltage_efficiency_thermoneutral: voltageEfficiency,
      eta_stack_thermoneutral: etaCurrent * voltageEfficiency,
    };
    row.accepted_for_current_efficiency =
      row.mean_current_A >= 1000 &&
      row.mean_h2_flow_Nm3h >= 50 &&
      row.run_fraction >= 0.95 &&
      row.std_current_A / row.mean_current_A <= 0.01 &&
      row.std_h2_flow_Nm3h / row.mean_h2_flow_Nm3h <= 0.15 &&
      row.eta_current_measured >= 0.55 &&
      row.eta_current_measured <= 1.0;
    rows.push(row);
  }
  return rows;
}

function readCellDistribution(dataDir, startInclusive, endExclusive, prefix, count) {
  const file = path.join(dataDir, `${prefix === 'voltage' ? 'cellV' : 'cellT'}_20250915.csv`);
  const content = fs.readFileSync(file, 'utf8');
  const lines = content.split(/\r?\n/).filter(Boolean);
  const sums = Array(count).fill(0);
  const sums2 = Array(count).fill(0);
  let n = 0;
  for (let i = 1; i < lines.length; i += 1) {
    const row = splitCsvLine(lines[i]);
    const t = toDateTimeKey(row[0]);
    if (t < startInclusive || t >= endExclusive) continue;
    n += 1;
    for (let c = 0; c < count; c += 1) {
      const value = Number(row[c + 1]);
      sums[c] += value;
      sums2[c] += value * value;
    }
  }
  return sums.map((s, i) => {
    const m = s / n;
    return {
      channel: i + 1,
      mean: m,
      std: Math.sqrt(Math.max(0, sums2[i] / n - m * m)),
      n_samples: n,
    };
  });
}

function distributionSummary(voltageRows, tempRows) {
  const validVoltageRows = voltageRows.filter((r) => r.mean > 1.0);
  const invalidVoltageRows = voltageRows.filter((r) => r.mean <= 1.0);
  const v = validVoltageRows.map((r) => r.mean);
  const first10 = validVoltageRows.filter((r) => r.channel <= 10).map((r) => r.mean);
  const last10 = validVoltageRows.filter((r) => r.channel > 356).map((r) => r.mean);
  const edge = [...first10, ...last10];
  const core = validVoltageRows.filter((r) => r.channel >= 51 && r.channel <= 316).map((r) => r.mean);
  const odd = validVoltageRows.filter((r) => r.channel % 2 === 1).map((r) => r.mean);
  const even = validVoltageRows.filter((r) => r.channel % 2 === 0).map((r) => r.mean);
  const t = tempRows.map((r) => r.mean);
  return {
    n_voltage_channels: voltageRows.length,
    n_valid_voltage_channels: validVoltageRows.length,
    invalid_voltage_channels: invalidVoltageRows.map((r) => r.channel).join(';'),
    n_temperature_channels: tempRows.length,
    n_samples: voltageRows[0]?.n_samples || 0,
    voltage_mean_V: mean(v),
    voltage_min_V: Math.min(...v),
    voltage_max_V: Math.max(...v),
    voltage_spread_mV: (Math.max(...v) - Math.min(...v)) * 1000,
    voltage_spatial_std_mV: std(v) * 1000,
    edge_mean_V: mean(edge),
    core_mean_V: mean(core),
    edge_minus_core_mV: (mean(edge) - mean(core)) * 1000,
    odd_mean_V: mean(odd),
    even_mean_V: mean(even),
    odd_even_difference_mV: (mean(odd) - mean(even)) * 1000,
    temperature_mean_C: mean(t),
    temperature_min_C: Math.min(...t),
    temperature_max_C: Math.max(...t),
    temperature_spread_C: Math.max(...t) - Math.min(...t),
  };
}

function interpolateCellTemperatures(tempRows, nCells) {
  const positions = tempRows.map((r) => 1 + (r.channel - 1) * (nCells - 1) / (tempRows.length - 1));
  const values = tempRows.map((r) => r.mean);
  const out = [];
  for (let cell = 1; cell <= nCells; cell += 1) {
    if (cell <= positions[0]) {
      out.push(values[0]);
      continue;
    }
    if (cell >= positions[positions.length - 1]) {
      out.push(values[values.length - 1]);
      continue;
    }
    let j = 0;
    while (j < positions.length - 2 && positions[j + 1] < cell) j += 1;
    const x0 = positions[j];
    const x1 = positions[j + 1];
    const y0 = values[j];
    const y1 = values[j + 1];
    out.push(y0 + (y1 - y0) * (cell - x0) / (x1 - x0));
  }
  return out;
}

function reconstructCurrentDistribution(voltageRows, tempRows, coeffs, stack, meanRectifierCurrentA) {
  const cellTemperatures = interpolateCellTemperatures(tempRows, stack.n_cells);
  const rows = voltageRows.map((vRow, i) => {
    const tempC = cellTemperatures[i];
    const valid = vRow.mean > 1.0 && Number.isFinite(vRow.mean) && Number.isFinite(tempC);
    const denom = coeffs[2] + coeffs[3] * tempC;
    const inferredCurrentRaw = valid && Math.abs(denom) > 1e-12
      ? stack.electrode_area_m2 * (vRow.mean - coeffs[0] - coeffs[1] * tempC) / denom
      : NaN;
    return {
      cell_id: vRow.channel,
      valid_channel: valid,
      mean_cell_voltage_V: vRow.mean,
      std_cell_voltage_V: vRow.std,
      interpolated_temperature_C: tempC,
      inferred_current_A: inferredCurrentRaw,
      inferred_current_pu_rated: inferredCurrentRaw / stack.rated_current_A,
      inferred_current_pu_rectifier_mean: inferredCurrentRaw / meanRectifierCurrentA,
    };
  });
  return rows;
}

function currentDistributionSummary(currentRows, meanRectifierCurrentA, meanH2FlowNm3h, stack) {
  const validRows = currentRows.filter((r) => r.valid_channel && Number.isFinite(r.inferred_current_A));
  const currents = validRows.map((r) => r.inferred_current_A);
  const currentPuRated = validRows.map((r) => r.inferred_current_pu_rated);
  const first10 = validRows.filter((r) => r.cell_id <= 10).map((r) => r.inferred_current_A);
  const last10 = validRows.filter((r) => r.cell_id > stack.n_cells - 10).map((r) => r.inferred_current_A);
  const edge = [...first10, ...last10];
  const core = validRows.filter((r) => r.cell_id >= 51 && r.cell_id <= stack.n_cells - 50)
    .map((r) => r.inferred_current_A);
  const odd = validRows.filter((r) => r.cell_id % 2 === 1).map((r) => r.inferred_current_A);
  const even = validRows.filter((r) => r.cell_id % 2 === 0).map((r) => r.inferred_current_A);
  const idealH2 = idealH2Nm3h(meanRectifierCurrentA, stack.n_cells, stack.normal_molar_volume_L_mol);
  return {
    n_valid_cells: validRows.length,
    mean_rectifier_current_A: meanRectifierCurrentA,
    mean_h2_flow_Nm3h: meanH2FlowNm3h,
    voltage_temperature_inferred_current_mean_A: mean(currents),
    voltage_temperature_inferred_current_efficiency_mean: mean(currents) / stack.rated_current_A,
    voltage_temperature_inferred_current_min_pu_rated: Math.min(...currentPuRated),
    voltage_temperature_inferred_current_max_pu_rated: Math.max(...currentPuRated),
    voltage_temperature_inferred_current_spread_pu_rated: Math.max(...currentPuRated) - Math.min(...currentPuRated),
    voltage_temperature_inferred_current_std_pu_rated: std(currentPuRated),
    voltage_temperature_inferred_current_std_over_mean: std(currents) / mean(currents),
    edge_mean_current_A: mean(edge),
    core_mean_current_A: mean(core),
    edge_minus_core_current_A: mean(edge) - mean(core),
    odd_mean_current_A: mean(odd),
    even_mean_current_A: mean(even),
    odd_even_current_difference_A: mean(odd) - mean(even),
    measured_h2_to_rectifier_ideal_eta: meanH2FlowNm3h / idealH2,
  };
}

function writeReadme(outDir) {
  const text = `# Step 9: Stack B Independent Stack-Layer Validation

This folder contains the independent Stack B validation case added for the R1 response. Stack B is not used to replace the Stack A/Fangshan stack-to-module validation. Instead, it provides a separate cell-resolved industrial stack test for validating the stack-layer voltage relation and the voltage-temperature-inferred current-distribution interface.

The raw data do not include direct per-cell current sensors. Therefore, the current-distribution output should be described as a voltage-temperature-inferred equivalent current distribution reconstructed from cell-resolved voltage and temperature measurements, not as a directly measured per-cell current distribution. The fitted voltage relation uses hydrogen-closure-based effective electrolysis current, rather than rectifier terminal current, to avoid mixing leakage current into the local cell polarisation model.

## Inputs

- Raw data: \`Workflow/4-ExperimentalValidation/raw_data/stackB_cell_test/process.csv\`
- Cell voltage: \`Workflow/4-ExperimentalValidation/raw_data/stackB_cell_test/cellV_20250915.csv\`
- Cell temperature: \`Workflow/4-ExperimentalValidation/raw_data/stackB_cell_test/cellT_20250915.csv\`
- Parameter file: \`Workflow/4-ExperimentalValidation/config/stackA_independent.json\`

## Key logic

1. Process data are aggregated into 15 min windows, consistent with the manuscript module/plant time step.
2. Hydrogen-flow and rectifier-current measurements are used as an integral hydrogen-production closure check.
3. Only stable windows are accepted for model fitting and closure checks: run fraction >= 0.95, current standard deviation <= 1% of mean current, hydrogen-flow standard deviation <= 15% of mean flow, and 0.55 <= current efficiency <= 1.00.
4. A compact stack-voltage relation is fitted to the accepted windows for diagnostic validation: U_cell = beta0 + betaT T + betaJ J_eff + betaJT J_eff T, where J_eff = eta_current,H2 I_rectifier/A_cell.
5. Cell-voltage and cell-temperature distributions are averaged over the 7000 A steady segment from 2025-09-14 20:30:00 to 2025-09-14 21:45:00.
6. The 50 temperature channels are interpolated to 366 cell positions. For each valid voltage channel, the equivalent current density is reconstructed as J_cell,inf = (U_cell - beta0 - betaT T_cell)/(betaJ + betaJT T_cell). The inferred cell currents are reported against the rated 7000 A current without forcing their mean to equal the rectifier current.

## Outputs

- \`stackA_parameters.csv\`: Stack A parameters transcribed from Table 2.1.
- \`stackA_process_15min_windows.csv\`: all 15 min process windows for experiment 20250915.
- \`stackA_stable_current_efficiency_windows.csv\`: accepted windows used for voltage fitting and hydrogen-production closure.
- \`stackA_current_efficiency_summary.csv\`: summary statistics for accepted windows.
- \`stackA_voltage_model_coefficients.csv\`: compact voltage-model coefficients fitted for Stack A.
- \`stackA_voltage_model_predictions.csv\`: measured and fitted cell/stack voltage values.
- \`stackA_voltage_model_metrics.csv\`: voltage-model error metrics.
- \`stackA_cell_voltage_distribution_7000A.csv\`: 366-channel cell-voltage distribution.
- \`stackA_cell_temperature_distribution_7000A.csv\`: 50-channel temperature distribution.
- \`stackA_cell_distribution_summary.csv\`: spatial voltage and temperature summary.
- \`stackA_voltage_temperature_inferred_current_distribution_7000A.csv\`: voltage-temperature-inferred equivalent current distribution.
- \`stackA_voltage_temperature_inferred_current_summary.csv\`: summary of the inferred equivalent current distribution and 7000 A hydrogen-production closure.
`;
  fs.writeFileSync(path.join(outDir, 'README.md'), text, 'utf8');
}

function main() {
  const args = parseArgs(process.argv);
  const stack = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8').replace(/^\uFEFF/, ''));
  ensureDir(OUTPUT_ROOT);

  const paramRows = Object.entries(stack).map(([parameter, value]) => ({ parameter, value }));
  writeCsv(path.join(OUTPUT_ROOT, 'stackA_parameters.csv'), paramRows, ['parameter', 'value']);

  const windows = readProcessWindows(args.dataDir, stack);
  const roundedWindows = windows.map((r) => Object.fromEntries(Object.entries(r).map(([k, v]) => [k, typeof v === 'number' ? round(v, 6) : v])));
  writeCsv(path.join(OUTPUT_ROOT, 'stackA_process_15min_windows.csv'), roundedWindows, Object.keys(roundedWindows[0]));

  const accepted = windows.filter((r) => r.accepted_for_current_efficiency);
  const roundedAccepted = accepted.map((r) => Object.fromEntries(Object.entries(r).map(([k, v]) => [k, typeof v === 'number' ? round(v, 6) : v])));
  writeCsv(path.join(OUTPUT_ROOT, 'stackA_stable_current_efficiency_windows.csv'), roundedAccepted, Object.keys(roundedAccepted[0]));

  const eta = accepted.map((r) => r.eta_current_measured);
  const stackEta = accepted.map((r) => r.eta_stack_thermoneutral);
  const loads = accepted.map((r) => r.load_fraction);
  const summary = [
    { metric: 'n_windows', value: accepted.length },
    { metric: 'mean_current_A', value: round(mean(accepted.map((r) => r.mean_current_A)), 3) },
    { metric: 'current_min_A', value: round(Math.min(...accepted.map((r) => r.mean_current_A)), 3) },
    { metric: 'current_max_A', value: round(Math.max(...accepted.map((r) => r.mean_current_A)), 3) },
    { metric: 'load_fraction_min', value: round(Math.min(...loads), 6) },
    { metric: 'load_fraction_max', value: round(Math.max(...loads), 6) },
    { metric: 'mean_h2_flow_Nm3h', value: round(mean(accepted.map((r) => r.mean_h2_flow_Nm3h)), 3) },
    { metric: 'eta_current_mean', value: round(mean(eta), 6) },
    { metric: 'eta_current_median', value: round(median(eta), 6) },
    { metric: 'eta_current_std', value: round(std(eta), 6) },
    { metric: 'eta_current_p25', value: round(quantile(eta, 0.25), 6) },
    { metric: 'eta_current_p75', value: round(quantile(eta, 0.75), 6) },
    { metric: 'eta_current_min', value: round(Math.min(...eta), 6) },
    { metric: 'eta_current_max', value: round(Math.max(...eta), 6) },
    { metric: 'eta_stack_thermoneutral_mean', value: round(mean(stackEta), 6) },
    { metric: 'eta_stack_thermoneutral_min', value: round(Math.min(...stackEta), 6) },
    { metric: 'eta_stack_thermoneutral_max', value: round(Math.max(...stackEta), 6) },
  ];
  writeCsv(path.join(OUTPUT_ROOT, 'stackA_current_efficiency_summary.csv'), summary, ['metric', 'value']);

  const trainRows = accepted.filter((_, i) => i % 2 === 0);
  const testRows = accepted.filter((_, i) => i % 2 === 1);
  const coeffs = fitVoltageModel(trainRows, stack);
  writeCsv(
    path.join(OUTPUT_ROOT, 'stackA_voltage_model_coefficients.csv'),
    [
      { coefficient: 'beta0', value: coeffs[0] },
      { coefficient: 'betaT', value: coeffs[1] },
      { coefficient: 'betaJ', value: coeffs[2] },
      { coefficient: 'betaJT', value: coeffs[3] },
      { coefficient: 'model_form', value: 'U_cell = beta0 + betaT*T + betaJ*J_eff + betaJT*J_eff*T' },
      { coefficient: 'current_density_basis', value: 'J_eff = eta_current_from_H2 * I_rectifier / electrode_area' },
      { coefficient: 'voltage_basis', value: 'mean_valid_cell_voltage = cell_stack_voltage_sum / valid_voltage_channel_count' },
    ],
    ['coefficient', 'value'],
  );

  const predictions = accepted.map((r, i) => {
    const predCell = predictCellVoltage(coeffs, r, stack);
    return {
      subset: i % 2 === 0 ? 'train' : 'test',
      window_start: r.window_start,
      mean_current_A: round(r.mean_current_A, 3),
      mean_effective_electrolysis_current_A: round(r.mean_effective_electrolysis_current_A, 3),
      eta_current_measured: round(r.eta_current_measured, 6),
      cell_temperature_mean_C: round(r.cell_temperature_mean_C, 3),
      measured_cell_voltage_V: round(r.mean_cell_voltage_V, 6),
      measured_valid_cell_voltage_V: round(r.mean_valid_cell_voltage_V, 6),
      predicted_cell_voltage_V: round(predCell, 6),
      cell_voltage_error_mV: round((predCell - r.mean_valid_cell_voltage_V) * 1000, 3),
      measured_stack_voltage_V: round(r.mean_cell_stack_voltage_sum_V, 3),
      predicted_stack_voltage_V: round(predCell * (stack.valid_voltage_channel_count || stack.n_cells), 3),
      stack_voltage_error_V: round(predCell * (stack.valid_voltage_channel_count || stack.n_cells) - r.mean_cell_stack_voltage_sum_V, 3),
    };
  });
  writeCsv(path.join(OUTPUT_ROOT, 'stackA_voltage_model_predictions.csv'), predictions, Object.keys(predictions[0]));
  const metricRows = [];
  for (const scope of ['train', 'test', 'all']) {
    const scoped = scope === 'all' ? predictions : predictions.filter((r) => r.subset === scope);
    const cellErr = scoped.map((r) => r.cell_voltage_error_mV);
    const stackErr = scoped.map((r) => r.stack_voltage_error_V);
    metricRows.push(
      { scope, metric: 'n_windows', value: scoped.length },
      { scope, metric: 'cell_voltage_MAE_mV', value: round(mean(cellErr.map(Math.abs)), 3) },
      { scope, metric: 'cell_voltage_RMSE_mV', value: round(Math.sqrt(mean(cellErr.map((x) => x * x))), 3) },
      { scope, metric: 'stack_voltage_MAE_V', value: round(mean(stackErr.map(Math.abs)), 3) },
      { scope, metric: 'stack_voltage_RMSE_V', value: round(Math.sqrt(mean(stackErr.map((x) => x * x))), 3) },
    );
  }
  writeCsv(
    path.join(OUTPUT_ROOT, 'stackA_voltage_model_metrics.csv'),
    metricRows,
    ['scope', 'metric', 'value'],
  );

  const distStart = '2025-09-14 20:30:00';
  const distEnd = '2025-09-14 21:45:00';
  const voltageDist = readCellDistribution(args.dataDir, distStart, distEnd, 'voltage', stack.n_cells);
  const tempDist = readCellDistribution(args.dataDir, distStart, distEnd, 'temperature', 50);
  const distWindows = windows.filter((r) => r.window_start >= distStart && r.window_start < distEnd);
  const distMeanCurrent = mean(distWindows.map((r) => r.mean_current_A));
  const distMeanH2 = mean(distWindows.map((r) => r.mean_h2_flow_Nm3h));
  const inferredCurrentDist = reconstructCurrentDistribution(voltageDist, tempDist, coeffs, stack, distMeanCurrent);
  writeCsv(
    path.join(OUTPUT_ROOT, 'stackA_cell_voltage_distribution_7000A.csv'),
    voltageDist.map((r) => ({
      cell_id: r.channel,
      valid_channel: r.mean > 1.0,
      mean_cell_voltage_V: round(r.mean, 6),
      std_cell_voltage_V: round(r.std, 6),
      n_samples: r.n_samples,
    })),
    ['cell_id', 'valid_channel', 'mean_cell_voltage_V', 'std_cell_voltage_V', 'n_samples'],
  );
  writeCsv(
    path.join(OUTPUT_ROOT, 'stackA_cell_temperature_distribution_7000A.csv'),
    tempDist.map((r) => ({
      temperature_channel: r.channel,
      mean_temperature_C: round(r.mean, 6),
      std_temperature_C: round(r.std, 6),
      n_samples: r.n_samples,
    })),
    ['temperature_channel', 'mean_temperature_C', 'std_temperature_C', 'n_samples'],
  );
  const distSummary = distributionSummary(voltageDist, tempDist);
  writeCsv(
    path.join(OUTPUT_ROOT, 'stackA_cell_distribution_summary.csv'),
    Object.entries(distSummary).map(([metric, value]) => ({
      metric,
      value: typeof value === 'number' ? round(value, 6) : value,
    })),
    ['metric', 'value'],
  );
  writeCsv(
    path.join(OUTPUT_ROOT, 'stackA_voltage_temperature_inferred_current_distribution_7000A.csv'),
    inferredCurrentDist.map((r) => ({
      cell_id: r.cell_id,
      valid_channel: r.valid_channel,
      mean_cell_voltage_V: round(r.mean_cell_voltage_V, 6),
      std_cell_voltage_V: round(r.std_cell_voltage_V, 6),
      interpolated_temperature_C: round(r.interpolated_temperature_C, 6),
      inferred_current_A: round(r.inferred_current_A, 6),
      inferred_current_pu_rated: round(r.inferred_current_pu_rated, 6),
      inferred_current_pu_rectifier_mean: round(r.inferred_current_pu_rectifier_mean, 6),
    })),
    [
      'cell_id',
      'valid_channel',
      'mean_cell_voltage_V',
      'std_cell_voltage_V',
      'interpolated_temperature_C',
      'inferred_current_A',
      'inferred_current_pu_rated',
      'inferred_current_pu_rectifier_mean',
    ],
  );
  const currentDistSummary = currentDistributionSummary(inferredCurrentDist, distMeanCurrent, distMeanH2, stack);
  writeCsv(
    path.join(OUTPUT_ROOT, 'stackA_voltage_temperature_inferred_current_summary.csv'),
    Object.entries(currentDistSummary).map(([metric, value]) => ({
      metric,
      value: typeof value === 'number' ? round(value, 6) : value,
    })),
    ['metric', 'value'],
  );

  writeReadme(OUTPUT_ROOT);
  console.log(`Stack A independent validation outputs written to: ${OUTPUT_ROOT}`);
}

main();
