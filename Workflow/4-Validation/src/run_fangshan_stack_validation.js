const fs = require('fs');
const path = require('path');
const { TextDecoder } = require('util');

const SCRIPT_DIR = __dirname;
const VALIDATION_ROOT = path.resolve(SCRIPT_DIR, '..');
const DEFAULT_CONFIG = path.join(VALIDATION_ROOT, 'config', 'stackA_fangshan.json');
const DEFAULT_OUTPUT = path.join(VALIDATION_ROOT, 'outputs');
const DEFAULT_DATA_DIR = path.join(VALIDATION_ROOT, 'raw_data', 'stackA_fangshan');
const DEFAULT_BIN_MINUTES = 15;
const STEP_DIRS = {
  step1: 'step1_stack_object',
  step2: 'step2_voltage_model_validation',
  step3: 'step3_current_efficiency_validation',
  step4: 'step4_stack_efficiency_interface',
  step5: 'step5_module_interface_preparation',
  step6: 'step6_steady_module_validation',
  step7: 'step7_dynamic_module_validation',
};

function parseArgs(argv) {
  const args = {};
  for (let i = 2; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token.startsWith('--')) continue;
    const key = token.slice(2);
    const next = argv[i + 1];
    if (!next || next.startsWith('--')) {
      args[key] = true;
    } else {
      args[key] = next;
      i += 1;
    }
  }
  return args;
}

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function cleanCell(value) {
  return String(value ?? '').trim().replace(/^"|"$/g, '');
}

function parseNumber(value) {
  const s = cleanCell(value).replace(/,/g, '');
  if (!s) return NaN;
  const x = Number(s);
  return Number.isFinite(x) ? x : NaN;
}

function parseTime(value) {
  const s = cleanCell(value);
  let m = s.match(/^(\d{4})\/(\d{1,2})\/(\d{1,2}) (\d{1,2}):(\d{2})(?::(\d{2}))?$/);
  if (!m) m = s.match(/^(\d{4})-(\d{1,2})-(\d{1,2})[ T](\d{1,2}):(\d{2})(?::(\d{2}))?$/);
  if (!m) return null;
  return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]), Number(m[4]), Number(m[5]), Number(m[6] || 0));
}

function formatTime(date) {
  const pad = (n) => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`;
}

function csvEscape(value) {
  if (value instanceof Date) return formatTime(value);
  if (typeof value === 'number') return Number.isFinite(value) ? String(value) : '';
  const s = String(value ?? '');
  return /[",\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

function csvLine(values) {
  return values.map(csvEscape).join(',');
}

function writeCsv(file, columns, rows) {
  const lines = [columns.join(',')];
  for (const row of rows) lines.push(csvLine(columns.map((column) => row[column])));
  fs.writeFileSync(file, `${lines.join('\n')}\n`, 'utf8');
}

function writeKeyValueCsv(file, data) {
  const rows = Object.entries(data).map(([key, value]) => ({ key, value }));
  writeCsv(file, ['key', 'value'], rows);
}

function median(values) {
  const finite = values.filter(Number.isFinite).sort((a, b) => a - b);
  if (!finite.length) return NaN;
  const mid = Math.floor(finite.length / 2);
  return finite.length % 2 ? finite[mid] : (finite[mid - 1] + finite[mid]) / 2;
}

function findColumn(headers, tag) {
  const index = headers.findIndex((header) => header.includes(tag));
  if (index < 0) throw new Error(`Missing PLC column containing tag ${tag}`);
  return index;
}

function makeStats() {
  return {
    n: 0,
    sumI: 0, sumI2: 0,
    sumV: 0, sumV2: 0,
    sumH2: 0, sumH22: 0,
    sumLye: 0, sumLye2: 0,
    sumTin: 0, sumTin2: 0,
    sumToutH: 0, sumToutH2: 0,
    sumToutO: 0, sumToutO2: 0,
    sumPIn: 0, sumPIn2: 0,
    sumPH: 0, sumPH2: 0,
    sumPO: 0, sumPO2: 0,
    sumO2InH2: 0, sumO2InH22: 0,
    sumH2InO2: 0, sumH2InO22: 0,
  };
}

function add(stats, row) {
  stats.n += 1;
  for (const [key, value] of Object.entries({
    I: row.I,
    V: row.V,
    H2: row.H2,
    Lye: row.Lye,
    Tin: row.Tin,
    ToutH: row.ToutH,
    ToutO: row.ToutO,
    PIn: row.PIn,
    PH: row.PH,
    PO: row.PO,
    O2InH2: row.O2InH2,
    H2InO2: row.H2InO2,
  })) {
    if (!Number.isFinite(value)) continue;
    stats[`sum${key}`] += value;
    stats[`sum${key}2`] += value * value;
  }
}

function mean(stats, key) {
  return stats.n ? stats[`sum${key}`] / stats.n : NaN;
}

function std(stats, key) {
  if (stats.n <= 1) return 0;
  const sum = stats[`sum${key}`];
  const sum2 = stats[`sum${key}2`];
  const variance = Math.max(0, (sum2 - (sum * sum) / stats.n) / (stats.n - 1));
  return Math.sqrt(variance);
}

function theoreticalH2Nm3h(currentA, stack) {
  return currentA * stack.nCells / (2 * stack.faradayConstantCmol) * stack.molarVolumeNm3mol * 3600;
}

function summariseBin(sourceFile, start, end, stats, stack) {
  const I = mean(stats, 'I');
  const V = mean(stats, 'V');
  const H2 = mean(stats, 'H2');
  const powerMW = I * V / 1e6;
  const powerKW = powerMW * 1000;
  const h2Theory = theoreticalH2Nm3h(I, stack);
  const lhvKWhNm3 = stack.lhvKWhKg / stack.hydrogenNm3PerKg;
  const vCell = V / stack.nCells;
  return {
    source_file: sourceFile,
    start,
    end,
    n: stats.n,
    I_mean_A: I,
    I_std_A: std(stats, 'I'),
    V_mean_V: V,
    V_std_V: std(stats, 'V'),
    H2_mean_Nm3h: H2,
    H2_std_Nm3h: std(stats, 'H2'),
    Lye_mean_m3h: mean(stats, 'Lye'),
    Lye_std_m3h: std(stats, 'Lye'),
    Tin_C: mean(stats, 'Tin'),
    Tin_std_C: std(stats, 'Tin'),
    ToutH_C: mean(stats, 'ToutH'),
    ToutH_std_C: std(stats, 'ToutH'),
    ToutO_C: mean(stats, 'ToutO'),
    ToutO_std_C: std(stats, 'ToutO'),
    PIn_MPa: mean(stats, 'PIn'),
    PIn_std_MPa: std(stats, 'PIn'),
    PH_MPa: mean(stats, 'PH'),
    PH_std_MPa: std(stats, 'PH'),
    PO_MPa: mean(stats, 'PO'),
    PO_std_MPa: std(stats, 'PO'),
    O2_in_H2_pct: mean(stats, 'O2InH2'),
    O2_in_H2_std_pct: std(stats, 'O2InH2'),
    H2_in_O2_pct: mean(stats, 'H2InO2'),
    H2_in_O2_std_pct: std(stats, 'H2InO2'),
    power_MW: powerMW,
    load_fraction: powerMW / stack.ratedPowerMW,
    H2_theory_Nm3h: h2Theory,
    eta_current_measured: H2 / h2Theory,
    eta_voltage_LHV: stack.vlhvV / vCell,
    eta_voltage_thermoneutral: stack.vThermoneutralV / vCell,
    eta_stack_LHV_measured: H2 * lhvKWhNm3 / powerKW,
  };
}

function readPlcFile(file, binMinutes, stack) {
  const text = new TextDecoder('utf-16le').decode(fs.readFileSync(file));
  const lines = text.split(/\r?\n/).filter(Boolean);
  if (lines.length < 2) return [];

  const delimiter = lines[0].includes(';') ? ';' : '\t';
  const headers = lines[0].split(delimiter).map(cleanCell);
  const idx = {
    time: 0,
    V: findColumn(headers, 'IV6001'),
    I: findColumn(headers, 'IA6001'),
    H2: findColumn(headers, 'FT1005'),
    Lye: findColumn(headers, 'FT1002'),
    O2InH2: findColumn(headers, 'AT1002'),
    H2InO2: findColumn(headers, 'AT1003'),
    Tin: findColumn(headers, 'TT1002'),
    ToutH: findColumn(headers, 'TT1007'),
    ToutO: findColumn(headers, 'TT1008'),
    PIn: findColumn(headers, 'PT1011'),
    PH: findColumn(headers, 'PT1012'),
    PO: findColumn(headers, 'PT1013'),
  };

  const bins = new Map();
  for (let lineIndex = 1; lineIndex < lines.length; lineIndex += 1) {
    const parts = lines[lineIndex].split(delimiter).map(cleanCell);
    const time = parseTime(parts[idx.time]);
    if (!time) continue;
    const row = {
      I: parseNumber(parts[idx.I]),
      V: parseNumber(parts[idx.V]),
      H2: parseNumber(parts[idx.H2]),
      Lye: parseNumber(parts[idx.Lye]),
      Tin: parseNumber(parts[idx.Tin]),
      ToutH: parseNumber(parts[idx.ToutH]),
      ToutO: parseNumber(parts[idx.ToutO]),
      PIn: parseNumber(parts[idx.PIn]),
      PH: parseNumber(parts[idx.PH]),
      PO: parseNumber(parts[idx.PO]),
      O2InH2: parseNumber(parts[idx.O2InH2]),
      H2InO2: parseNumber(parts[idx.H2InO2]),
    };
    if (!Number.isFinite(row.I) || !Number.isFinite(row.V) || !Number.isFinite(row.H2)) continue;
    const start = new Date(time);
    start.setMinutes(Math.floor(start.getMinutes() / binMinutes) * binMinutes, 0, 0);
    const key = start.getTime();
    if (!bins.has(key)) bins.set(key, makeStats());
    add(bins.get(key), row);
  }

  const rows = [];
  for (const [key, stats] of [...bins.entries()].sort((a, b) => a[0] - b[0])) {
    const start = new Date(Number(key));
    const end = new Date(start.getTime() + binMinutes * 60 * 1000 - 1000);
    rows.push(summariseBin(path.basename(file), start, end, stats, stack));
  }
  return rows;
}

function solveLinear(A, b) {
  const n = b.length;
  const M = A.map((row, i) => [...row, b[i]]);
  for (let col = 0; col < n; col += 1) {
    let pivot = col;
    for (let r = col + 1; r < n; r += 1) {
      if (Math.abs(M[r][col]) > Math.abs(M[pivot][col])) pivot = r;
    }
    [M[col], M[pivot]] = [M[pivot], M[col]];
    const div = M[col][col];
    if (Math.abs(div) < 1e-12) throw new Error('Singular matrix in least-squares fit.');
    for (let c = col; c <= n; c += 1) M[col][c] /= div;
    for (let r = 0; r < n; r += 1) {
      if (r === col) continue;
      const factor = M[r][col];
      for (let c = col; c <= n; c += 1) M[r][c] -= factor * M[col][c];
    }
  }
  return M.map((row) => row[n]);
}

function ols(rows, xFn, yFn, p) {
  const XtX = Array.from({ length: p }, () => Array(p).fill(0));
  const Xty = Array(p).fill(0);
  for (const row of rows) {
    const x = xFn(row);
    const y = yFn(row);
    for (let i = 0; i < p; i += 1) {
      Xty[i] += x[i] * y;
      for (let j = 0; j < p; j += 1) XtX[i][j] += x[i] * x[j];
    }
  }
  return solveLinear(XtX, Xty);
}

function voltageFeatures(row, stack) {
  const T = (row.Tin_C + row.ToutH_C + row.ToutO_C) / 3;
  const J = row.I_mean_A / stack.electrodeAreaM2;
  return [1, J, J * T];
}

function predictVoltage(row, stack, beta) {
  const x = voltageFeatures(row, stack);
  const vCell = beta.reduce((sum, value, index) => sum + value * x[index], 0);
  return vCell * stack.nCells;
}

function metrics(rows, actualFn, predFn) {
  const errors = rows.map((row) => predFn(row) - actualFn(row));
  const absErrors = errors.map(Math.abs);
  const mae = absErrors.reduce((a, b) => a + b, 0) / rows.length;
  const rmse = Math.sqrt(errors.reduce((a, b) => a + b * b, 0) / rows.length);
  const mape = absErrors.reduce((sum, e, index) => sum + e / Math.abs(actualFn(rows[index])), 0) / rows.length;
  const maxAbs = Math.max(...absErrors);
  return { n: rows.length, MAE: mae, RMSE: rmse, MAPE: mape, MaxAbs: maxAbs };
}

function quantile(values, q) {
  const sorted = values.filter(Number.isFinite).sort((a, b) => a - b);
  if (!sorted.length) return NaN;
  const pos = (sorted.length - 1) * q;
  const lo = Math.floor(pos);
  const hi = Math.ceil(pos);
  if (lo === hi) return sorted[lo];
  return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo);
}

function meanValue(values) {
  const finite = values.filter(Number.isFinite);
  if (!finite.length) return NaN;
  return finite.reduce((a, b) => a + b, 0) / finite.length;
}

function minValue(values) {
  const finite = values.filter(Number.isFinite);
  return finite.length ? Math.min(...finite) : NaN;
}

function maxValue(values) {
  const finite = values.filter(Number.isFinite);
  return finite.length ? Math.max(...finite) : NaN;
}

function stdValue(values) {
  const finite = values.filter(Number.isFinite);
  if (finite.length <= 1) return 0;
  const avg = meanValue(finite);
  return Math.sqrt(finite.reduce((sum, value) => sum + (value - avg) ** 2, 0) / (finite.length - 1));
}

function buildPiecewiseCurve(rows, binWidth) {
  const groups = new Map();
  for (const row of rows) {
    const bin = Math.round(row.load_fraction / binWidth) * binWidth;
    const key = bin.toFixed(3);
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(row);
  }
  return [...groups.entries()]
    .sort((a, b) => Number(a[0]) - Number(b[0]))
    .map(([key, group]) => ({
      load_bin: Number(key),
      n: group.length,
      load_mean: meanValue(group.map((r) => r.load_fraction)),
      power_MW_mean: meanValue(group.map((r) => r.power_MW)),
      I_mean_A: meanValue(group.map((r) => r.I_mean_A)),
      V_mean_V: meanValue(group.map((r) => r.V_mean_V)),
      H2_mean_Nm3h: meanValue(group.map((r) => r.H2_mean_Nm3h)),
      eta_current_mean: meanValue(group.map((r) => r.eta_current_measured)),
      eta_current_p25: quantile(group.map((r) => r.eta_current_measured), 0.25),
      eta_current_p75: quantile(group.map((r) => r.eta_current_measured), 0.75),
      eta_voltage_LHV_mean: meanValue(group.map((r) => r.eta_voltage_LHV)),
      eta_voltage_thermoneutral_mean: meanValue(group.map((r) => r.eta_voltage_thermoneutral)),
      eta_stack_LHV_mean: meanValue(group.map((r) => r.eta_stack_LHV_measured)),
      eta_stack_LHV_p25: quantile(group.map((r) => r.eta_stack_LHV_measured), 0.25),
      eta_stack_LHV_p75: quantile(group.map((r) => r.eta_stack_LHV_measured), 0.75),
    }));
}

function buildModuleAlignedProfiles(rows, binMinutes) {
  return rows.map((row) => {
    const start = row.start instanceof Date ? row.start : parseTime(row.start);
    const slot = start ? (start.getHours() * 60 + start.getMinutes()) / binMinutes + 1 : NaN;
    return {
      source_file: row.source_file,
      day: start ? formatTime(start).slice(0, 10) : '',
      slot,
      time_h: Number.isFinite(slot) ? (slot - 1) * binMinutes / 60 : NaN,
      start: row.start,
      end: row.end,
      n: row.n,
      power_MW: row.power_MW,
      load_fraction: row.load_fraction,
      I_mean_A: row.I_mean_A,
      V_mean_V: row.V_mean_V,
      H2_rate_Nm3h: row.H2_mean_Nm3h,
      H2_step_Nm3: row.H2_mean_Nm3h * binMinutes / 60,
      H2_theory_rate_Nm3h: row.H2_theory_Nm3h,
      H2_theory_step_Nm3: row.H2_theory_Nm3h * binMinutes / 60,
      eta_current_measured: row.eta_current_measured,
      eta_stack_LHV_measured: row.eta_stack_LHV_measured,
      Tin_C: row.Tin_C,
      ToutH_C: row.ToutH_C,
      ToutO_C: row.ToutO_C,
      PH_MPa: row.PH_MPa,
      PO_MPa: row.PO_MPa,
      sample_coverage_ok: row.sample_coverage_ok,
      is_voltage_window: row.is_voltage_window,
      is_h2_window: row.is_h2_window,
    };
  });
}

function writeStepPlaceholders(outDir) {
  const placeholders = {
    step5: [
      '# Step 5 Module Interface Preparation',
      '',
      'Status: pending stack-to-module coupling implementation.',
      '',
      'Input from Step 4:',
      '',
      '- `../step4_stack_efficiency_interface/stackA_piecewise_efficiency_curve.csv`',
      '',
      'Planned output:',
      '',
      '- Field-stack efficiency table converted to the module model input format.',
      '- Fangshan BOP/module parameter mapping table.',
    ].join('\n'),
    step6: [
      '# Step 6 Steady Module Validation',
      '',
      'Status: pending module model execution.',
      '',
      'Planned validation:',
      '',
      '- Select quasi-steady load windows from Step 3.',
      '- Run the module model with the Step 5 interface.',
      '- Compare measured and simulated hydrogen production, module efficiency and thermal states.',
    ].join('\n'),
    step7: [
      '# Step 7 Dynamic Module Validation',
      '',
      'Status: pending module model execution.',
      '',
      'Planned validation:',
      '',
      '- Use measured daily power trajectories from the PLC data.',
      '- Run dynamic module simulation.',
      '- Compare cumulative hydrogen production and efficiency trends.',
    ].join('\n'),
  };
  for (const [step, text] of Object.entries(placeholders)) {
    const dir = path.join(outDir, STEP_DIRS[step]);
    ensureDir(dir);
    const readme = path.join(dir, 'README.md');
    if (!fs.existsSync(readme)) fs.writeFileSync(readme, `${text}\n`, 'utf8');
  }
}

function fmt(value, digits = 4) {
  return Number.isFinite(value) ? value.toFixed(digits) : 'NA';
}

function mdDailyTable(dailyRows) {
  const lines = [
    '| Day | 15 min bins | Voltage windows | H2/current windows | Load range | Mean current efficiency | Mean LHV stack efficiency |',
    '|---|---:|---:|---:|---:|---:|---:|',
  ];
  for (const row of dailyRows) {
    lines.push(`| ${row.day} | ${row.bins_total} | ${row.bins_voltage_window} | ${row.bins_h2_window} | ${fmt(row.load_min, 3)}-${fmt(row.load_max, 3)} | ${fmt(row.eta_current_h2_window_mean, 4)} | ${fmt(row.eta_stack_LHV_h2_window_mean, 4)} |`);
  }
  return lines;
}

function mdMetricsTable(trainMetrics, testMetrics, allMetrics, stack) {
  const rows = [
    ['Train', trainMetrics],
    ['Test', testMetrics],
    ['All', allMetrics],
  ];
  return [
    '| Set | Windows | MAE (V) | RMSE (V) | MAPE (%) | RMSE (mV cell-1) | Max abs. error (V) |',
    '|---|---:|---:|---:|---:|---:|---:|',
    ...rows.map(([name, m]) => `| ${name} | ${m.n} | ${fmt(m.MAE, 3)} | ${fmt(m.RMSE, 3)} | ${fmt(m.MAPE * 100, 3)} | ${fmt(m.RMSE / stack.nCells * 1000, 2)} | ${fmt(m.MaxAbs, 3)} |`),
  ];
}

function mdPiecewiseTable(piecewiseRows) {
  const lines = [
    '| Load bin | Windows | Mean load | Power (MW) | H2 (Nm3 h-1) | Current eff. | Voltage eff. (LHV) | Stack eff. (LHV) |',
    '|---:|---:|---:|---:|---:|---:|---:|---:|',
  ];
  for (const row of piecewiseRows) {
    lines.push(`| ${fmt(row.load_bin, 2)} | ${row.n} | ${fmt(row.load_mean, 3)} | ${fmt(row.power_MW_mean, 3)} | ${fmt(row.H2_mean_Nm3h, 1)} | ${fmt(row.eta_current_mean, 4)} | ${fmt(row.eta_voltage_LHV_mean, 4)} | ${fmt(row.eta_stack_LHV_mean, 4)} |`);
  }
  return lines;
}

function buildReport({
  outDir,
  dataDir,
  files,
  stack,
  rows,
  voltageRows,
  h2Rows,
  trainMetrics,
  testMetrics,
  allMetrics,
  splitLabel,
  piecewiseRows,
  binMinutes,
  dailyRows,
  beta,
}) {
  const h2EtaCurrent = h2Rows.map((row) => row.eta_current_measured);
  const h2EtaStack = h2Rows.map((row) => row.eta_stack_LHV_measured);
  const h2Loads = h2Rows.map((row) => row.load_fraction);
  const lines = [
    '# Fangshan Experimental Validation Report',
    '',
    'This report is generated step by step to document which parts of the cross-layer pipeline are experimentally covered.',
    '',
    'The validation is intentionally decomposed into the same objects and interfaces used in the manuscript pipeline. Steps 1-4 validate and prepare the field stack interface. Steps 5-7 are the planned stack-to-module closure using the same Fangshan BOP/module model.',
    '',
    '## Overall Coverage',
    '',
    '| Pipeline step | Validation status | Main output |',
    '|---:|---|---|',
    '| 1 | completed | Stack A field object and parameters |',
    '| 2 | completed | Stack voltage model validation |',
    '| 3 | completed | Stack current-efficiency validation windows |',
    '| 4 | completed | Piecewise stack-efficiency interface |',
    '| 5 | prepared | Module interface input from Step 4 |',
    '| 6 | pending | Steady module validation |',
    '| 7 | pending | Dynamic module validation |',
    '',
    '## Step 1 Stack Object Definition',
    '',
    'Data folder: `Workflow/4-ExperimentalValidation/raw_data/stackA_fangshan` by default; an external Fangshan PLC folder can still be supplied through `--data-dir`.',
    '',
    `PLC files scanned: ${files.length}`,
    '',
    `Aligned time step: ${binMinutes} min, matching the 0.25 h module/plant time step used in the paper.`,
    '',
    `Stack A uses ${stack.nCells} cells, ${stack.electrodeAreaM2} m2 electrode area, ${stack.ratedCurrentA} A rated current, ${stack.ratedVoltageV} V rated voltage and ${stack.ratedHydrogenNm3h} Nm3 h-1 rated hydrogen production.`,
    '',
    'Data processing:',
    '',
    '- PLC files are read directly from the external Fangshan data folder.',
    '- Semicolon- and tab-delimited files are both supported because the 2023-11-03 PLC file uses a different delimiter.',
    `- Raw second/minute-level signals are aggregated to ${binMinutes} min windows so that validation profiles are aligned with the module and plant time grid in the manuscript.`,
    '- The module-ready profile reports power, current, voltage, measured hydrogen flow rate and measured hydrogen production per 15 min step.',
    '',
    'Daily data availability:',
    '',
    ...mdDailyTable(dailyRows),
    '',
    'Output folder: `step1_stack_object`.',
    '',
    '## Step 2 Stack Voltage Model Validation',
    '',
    'Model/interface validated: the Stack A voltage relation that maps measured current density and stack temperature to stack voltage. This is the first part of the stack efficiency interface, because voltage efficiency is determined from the predicted/observed cell voltage.',
    '',
    'Data used:',
    '',
    '- Inputs: 15 min mean current, measured stack voltage, stack inlet/outlet temperatures.',
    '- Stable-window filters: sufficient sample coverage in the 15 min bin, current > 1200 A, voltage > 500 V, relative current standard deviation < 1.5%, voltage standard deviation < 2.5 V, and inlet-temperature standard deviation < 2.5 degC.',
    '- Training/testing split: chronological date split over the selected validation days, so later days are retained for independent testing.',
    '',
    'Fitted compact validation equation:',
    '',
    '`V_stack = N_cell * (beta0 + beta1 * J + beta2 * J * T)`',
    '',
    `where J = I / A_cell, and the fitted coefficients are beta0 = ${fmt(beta[0], 6)}, beta1 = ${beta[1].toExponential(6)}, beta2 = ${beta[2].toExponential(6)}.`,
    '',
    `Voltage validation windows: ${voltageRows.length}. Train/test split: ${splitLabel}.`,
    '',
    `All-window voltage RMSE is ${fmt(allMetrics.RMSE, 3)} V, corresponding to ${fmt(allMetrics.RMSE / stack.nCells * 1000, 2)} mV per cell. The all-window MAPE is ${fmt(allMetrics.MAPE * 100, 3)}%.`,
    '',
    `Independent test-window voltage RMSE is ${fmt(testMetrics.RMSE, 3)} V and MAPE is ${fmt(testMetrics.MAPE * 100, 3)}%.`,
    '',
    'Voltage validation metrics:',
    '',
    ...mdMetricsTable(trainMetrics, testMetrics, allMetrics, stack),
    '',
    'Output folder: `step2_voltage_model_validation`.',
    '',
    '## Step 3 Current-Efficiency Validation',
    '',
    'Model/interface validated: the current-to-hydrogen conversion part of the stack interface. This checks whether measured stack current and measured hydrogen flow give physically reasonable current efficiency under quasi-steady operating windows.',
    '',
    'Data used:',
    '',
    '- Inputs: 15 min mean current, hydrogen flow, voltage and pressure signals.',
    '- Theoretical hydrogen production rate is computed from Faraday conversion: `H2_theory = I * N_cell / (2F) * Vm * 3600`.',
    '- Measured current efficiency is computed as `eta_current = H2_measured / H2_theory`.',
    '- Additional hydrogen-window filters: hydrogen flow > 100 Nm3 h-1, hydrogen-flow standard deviation < 40 Nm3 h-1, H2-side and O2-side pressure standard deviation < 0.006 MPa, and 0.55 < measured current efficiency < 1.02.',
    '',
    `Hydrogen/current-efficiency validation windows: ${h2Rows.length}.`,
    '',
    `The selected windows cover load fractions from ${fmt(minValue(h2Loads), 3)} to ${fmt(maxValue(h2Loads), 3)}.`,
    '',
    `Measured stack current efficiency has mean ${fmt(meanValue(h2EtaCurrent), 4)} and standard deviation ${fmt(stdValue(h2EtaCurrent), 4)} after pressure/flow stability filtering.`,
    '',
    `Measured LHV stack efficiency has mean ${fmt(meanValue(h2EtaStack), 4)} and standard deviation ${fmt(stdValue(h2EtaStack), 4)}.`,
    '',
    `The interquartile range of measured current efficiency is ${fmt(quantile(h2EtaCurrent, 0.25), 4)}-${fmt(quantile(h2EtaCurrent, 0.75), 4)}.`,
    '',
    'Output folder: `step3_current_efficiency_validation`.',
    '',
    '## Step 4 Piecewise Stack-Efficiency Interface',
    '',
    'Interface generated: a piecewise field-stack efficiency curve for Stack A. This curve combines measured current efficiency with measured voltage efficiency and is the direct input for the following Fangshan module validation.',
    '',
    'Data used:',
    '',
    '- Inputs: the hydrogen/current-efficiency validation windows from Step 3.',
    '- Load bins: selected windows are grouped by stack load fraction with a 0.05 bin width.',
    '- Outputs per bin: mean load, mean power, mean hydrogen flow, mean current efficiency, mean voltage efficiency and mean LHV stack efficiency. P25/P75 values are stored to represent the observed spread.',
    '',
    `The piecewise interface contains ${piecewiseRows.length} load bins using the selected hydrogen-validation windows.`,
    '',
    'This interface is the field Stack A curve used for the following module validation, not the search-region stack curve used for Fig. 2.',
    '',
    'Piecewise Stack A interface:',
    '',
    ...mdPiecewiseTable(piecewiseRows),
    '',
    'Output folder: `step4_stack_efficiency_interface`.',
    '',
    '## Step 5 Module Interface Preparation',
    '',
    'Prepared but not yet executed in this script. The next script should convert the Step 4 curve to the Fangshan module-model input format and document the BOP parameter mapping. This step should verify that the stack object differs from the manuscript search-region stack, while the BOP/module object remains the Fangshan testbed object.',
    '',
    'Planned data input: `step4_stack_efficiency_interface/stackA_piecewise_efficiency_curve.csv`.',
    '',
    'Planned output: a module-input table mapping load fraction or power to Stack A hydrogen production and stack efficiency.',
    '',
    '## Step 6 Steady Module Validation',
    '',
    'Pending. This step will compare measured and simulated hydrogen production, module efficiency and thermal states under quasi-steady windows. Based on the daily window summary, the most useful steady validation windows are concentrated on 2023-11-05, with supplementary windows on 2023-11-03 and 2023-11-04.',
    '',
    'Planned quantitative outputs: steady-window errors for hydrogen production, system efficiency and available thermal states.',
    '',
    '## Step 7 Dynamic Module Validation',
    '',
    'Pending. This step will compare cumulative hydrogen production and efficiency trends under measured daily power trajectories. The preferred dynamic validation day is 2023-11-05 because it has a full 96-point profile and the largest number of accepted hydrogen/current-efficiency windows.',
    '',
    'Planned quantitative outputs: daily cumulative hydrogen error, daily average efficiency error, and 15 min profile error/trend comparison.',
    '',
  ];
  fs.writeFileSync(path.join(outDir, 'experimental_validation_report.md'), `${lines.join('\n')}\n`, 'utf8');
}

function writeStepReports({
  stepDirs,
  files,
  stack,
  rows,
  voltageRows,
  h2Rows,
  trainMetrics,
  testMetrics,
  allMetrics,
  splitLabel,
  piecewiseRows,
  binMinutes,
  dailyRows,
  beta,
}) {
  const h2EtaCurrent = h2Rows.map((row) => row.eta_current_measured);
  const h2EtaStack = h2Rows.map((row) => row.eta_stack_LHV_measured);
  const h2Loads = h2Rows.map((row) => row.load_fraction);

  fs.writeFileSync(path.join(stepDirs.step1, 'README.md'), [
    '# Step 1 Stack Object Definition',
    '',
    'Purpose: define the field Stack A object and convert raw PLC records into module-aligned time windows.',
    '',
    'Inputs:',
    '',
    '- Fangshan PLC files in `Workflow/4-ExperimentalValidation/raw_data/stackA_fangshan` by default; this can be overridden through `--data-dir`.',
    '- `../../config/stackA_fangshan.json`.',
    '',
    'Method:',
    '',
    '- Read all `PLC_YYYYMMDD.csv` files.',
    '- Detect semicolon or tab delimiters automatically.',
    `- Aggregate second/minute PLC records into ${binMinutes} min windows, matching the 0.25 h module/plant time step in the paper.`,
    '',
    'Key results:',
    '',
    `- PLC files scanned: ${files.length}.`,
    `- Total ${binMinutes} min windows: ${rows.length}.`,
    `- Stack A: ${stack.nCells} cells, ${stack.electrodeAreaM2} m2 electrode area, ${stack.ratedCurrentA} A, ${stack.ratedVoltageV} V.`,
    `- Best dynamic validation candidate: 2023-11-05, because it provides a complete 96-point profile and the largest number of accepted hydrogen/current-efficiency windows.`,
    '',
    'Daily data availability:',
    '',
    ...mdDailyTable(dailyRows),
    '',
    'Outputs:',
    '',
    '- `stackA_parameters.csv`.',
    '- `fangshan_module_aligned_15min_bins_all.csv`.',
    '- `fangshan_module_aligned_15min_profiles.csv`.',
    '- `fangshan_daily_window_summary.csv`.',
    '',
  ].join('\n'), 'utf8');

  fs.writeFileSync(path.join(stepDirs.step2, 'README.md'), [
    '# Step 2 Stack Voltage Model Validation',
    '',
    'Purpose: validate the field stack voltage model against measured current, voltage and temperature.',
    '',
    'Inputs:',
    '',
    '- `../step1_stack_object/fangshan_module_aligned_15min_bins_all.csv`.',
    '- Stack A parameters from Step 1.',
    '',
    'Method:',
    '',
    '- Select stable windows using current, voltage and temperature stability filters.',
    '- Fit a compact Stack A voltage relation on the training set.',
    '- Evaluate measured versus predicted stack voltage on train/test/all windows.',
    '',
    'Equation:',
    '',
    '`V_stack = N_cell * (beta0 + beta1 * J + beta2 * J * T)`',
    '',
    `Fitted coefficients: beta0 = ${fmt(beta[0], 6)}, beta1 = ${beta[1].toExponential(6)}, beta2 = ${beta[2].toExponential(6)}.`,
    '',
    'Key results:',
    '',
    `- Voltage validation windows: ${voltageRows.length}.`,
    `- Train/test split: ${splitLabel}.`,
    `- All-window RMSE: ${fmt(allMetrics.RMSE, 3)} V (${fmt(allMetrics.RMSE / stack.nCells * 1000, 2)} mV per cell).`,
    `- All-window MAPE: ${fmt(allMetrics.MAPE * 100, 3)}%.`,
    `- Test-window RMSE: ${fmt(testMetrics.RMSE, 3)} V.`,
    `- Test-window MAPE: ${fmt(testMetrics.MAPE * 100, 3)}%.`,
    '',
    ...mdMetricsTable(trainMetrics, testMetrics, allMetrics, stack),
    '',
    'Outputs:',
    '',
    '- `fangshan_selected_voltage_windows.csv`.',
    '- `stackA_voltage_model_coefficients.csv`.',
    '- `stackA_voltage_predictions.csv`.',
    '- `stackA_voltage_validation_metrics.csv`.',
    '',
  ].join('\n'), 'utf8');

  fs.writeFileSync(path.join(stepDirs.step3, 'README.md'), [
    '# Step 3 Current-Efficiency Validation',
    '',
    'Purpose: validate the current-to-hydrogen-production interface using measured current and hydrogen flow.',
    '',
    'Inputs:',
    '',
    '- `../step1_stack_object/fangshan_module_aligned_15min_bins_all.csv`.',
    '',
    'Method:',
    '',
    '- Apply stricter current, voltage, pressure and hydrogen-flow stability filters.',
    '- Compute theoretical hydrogen production from `N_cell * I / (2F)`.',
    '- Compute measured current efficiency as measured hydrogen flow divided by theoretical hydrogen flow.',
    '- Reject windows with unstable hydrogen flow, unstable pressure, or physically implausible apparent current efficiency.',
    '',
    'Key results:',
    '',
    `- Hydrogen/current-efficiency validation windows: ${h2Rows.length}.`,
    `- Load-fraction coverage: ${fmt(minValue(h2Loads), 3)} to ${fmt(maxValue(h2Loads), 3)}.`,
    `- Mean measured current efficiency: ${fmt(meanValue(h2EtaCurrent), 4)}.`,
    `- Current-efficiency standard deviation: ${fmt(stdValue(h2EtaCurrent), 4)}.`,
    `- Mean measured LHV stack efficiency: ${fmt(meanValue(h2EtaStack), 4)}.`,
    `- Current-efficiency interquartile range: ${fmt(quantile(h2EtaCurrent, 0.25), 4)}-${fmt(quantile(h2EtaCurrent, 0.75), 4)}.`,
    '',
    'Outputs:',
    '',
    '- `fangshan_selected_h2_windows.csv`.',
    '- `current_efficiency_summary.csv`.',
    '',
  ].join('\n'), 'utf8');

  fs.writeFileSync(path.join(stepDirs.step4, 'README.md'), [
    '# Step 4 Stack Efficiency Interface',
    '',
    'Purpose: build the field Stack A piecewise efficiency curve that will be passed to the Fangshan module model.',
    '',
    'Inputs:',
    '',
    '- `../step3_current_efficiency_validation/fangshan_selected_h2_windows.csv`.',
    '',
    'Method:',
    '',
    '- Bin selected validation windows by stack load fraction.',
    '- Average measured current efficiency, voltage efficiency and total LHV stack efficiency within each bin.',
    '- Export p25/p75 ranges as uncertainty bands for the interface.',
    '',
    'Key results:',
    '',
    `- Piecewise load bins: ${piecewiseRows.length}.`,
    `- First bin load: ${piecewiseRows.length ? fmt(piecewiseRows[0].load_mean, 3) : 'NA'}.`,
    `- Last bin load: ${piecewiseRows.length ? fmt(piecewiseRows[piecewiseRows.length - 1].load_mean, 3) : 'NA'}.`,
    '',
    ...mdPiecewiseTable(piecewiseRows),
    '',
    'Outputs:',
    '',
    '- `stackA_piecewise_efficiency_curve.csv`.',
    '',
  ].join('\n'), 'utf8');
}

function flagRows(rows) {
  const samplesBySource = new Map();
  for (const row of rows) {
    if (row.I_mean_A > 1000 && row.V_mean_V > 100 && row.n > 0) {
      if (!samplesBySource.has(row.source_file)) samplesBySource.set(row.source_file, []);
      samplesBySource.get(row.source_file).push(row.n);
    }
  }
  const minSamplesBySource = new Map();
  for (const [source, values] of samplesBySource.entries()) {
    minSamplesBySource.set(source, Math.max(3, Math.floor(median(values) * 0.85)));
  }

  for (const row of rows) {
    row.sample_coverage_ok = row.n >= (minSamplesBySource.get(row.source_file) || 3) ? 1 : 0;
    row.is_voltage_window = (
      row.sample_coverage_ok &&
      row.I_mean_A > 1200 &&
      row.V_mean_V > 500 &&
      row.I_std_A / row.I_mean_A < 0.015 &&
      row.V_std_V < 2.5 &&
      row.Tin_std_C < 2.5
    ) ? 1 : 0;

    row.is_h2_window = (
      row.is_voltage_window &&
      row.H2_mean_Nm3h > 100 &&
      row.H2_std_Nm3h < 40 &&
      row.PH_std_MPa < 0.006 &&
      row.PO_std_MPa < 0.006 &&
      row.eta_current_measured > 0.55 &&
      row.eta_current_measured < 1.02
    ) ? 1 : 0;
  }
}

function trainTestSplit(rows) {
  const dates = [...new Set(rows.map((row) => formatTime(row.start).slice(0, 10)))].sort();
  const splitIndex = Math.max(1, Math.ceil(dates.length * 0.6));
  const trainDates = new Set(dates.slice(0, splitIndex));
  const train = rows.filter((row) => trainDates.has(formatTime(row.start).slice(0, 10)));
  const test = rows.filter((row) => !trainDates.has(formatTime(row.start).slice(0, 10)));
  if (test.length < 5) {
    const cut = Math.max(1, Math.floor(rows.length * 0.7));
    return { train: rows.slice(0, cut), test: rows.slice(cut), splitLabel: 'chronological_70_30' };
  }
  return { train, test, splitLabel: `date_split_first_${splitIndex}_of_${dates.length}_days` };
}

function run() {
  const args = parseArgs(process.argv);
  const dataDir = path.resolve(args['data-dir'] || DEFAULT_DATA_DIR);
  const outDir = path.resolve(args['out-dir'] || DEFAULT_OUTPUT);
  const configFile = path.resolve(args.config || DEFAULT_CONFIG);
  const binMinutes = Number(args['bin-minutes'] || DEFAULT_BIN_MINUTES);
  const stack = JSON.parse(fs.readFileSync(configFile, 'utf8'));
  ensureDir(outDir);
  const stepDirs = {};
  for (const [key, folder] of Object.entries(STEP_DIRS)) {
    stepDirs[key] = path.join(outDir, folder);
    ensureDir(stepDirs[key]);
  }
  writeStepPlaceholders(outDir);

  const files = fs.readdirSync(dataDir)
    .filter((name) => /^PLC_\d{8}\.csv$/i.test(name))
    .sort()
    .map((name) => path.join(dataDir, name));
  if (!files.length) throw new Error(`No PLC_YYYYMMDD.csv files found under ${dataDir}`);

  const rows = [];
  for (const file of files) {
    const fileRows = readPlcFile(file, binMinutes, stack);
    rows.push(...fileRows);
    console.log(`read ${path.basename(file)} -> ${fileRows.length} bins`);
  }
  flagRows(rows);

  const binColumns = [
    'source_file', 'start', 'end', 'n',
    'I_mean_A', 'I_std_A', 'V_mean_V', 'V_std_V',
    'H2_mean_Nm3h', 'H2_std_Nm3h', 'Lye_mean_m3h', 'Lye_std_m3h',
    'Tin_C', 'Tin_std_C', 'ToutH_C', 'ToutH_std_C', 'ToutO_C', 'ToutO_std_C',
    'PIn_MPa', 'PIn_std_MPa', 'PH_MPa', 'PH_std_MPa', 'PO_MPa', 'PO_std_MPa',
    'O2_in_H2_pct', 'O2_in_H2_std_pct', 'H2_in_O2_pct', 'H2_in_O2_std_pct',
    'power_MW', 'load_fraction', 'H2_theory_Nm3h',
    'eta_current_measured', 'eta_voltage_LHV', 'eta_voltage_thermoneutral',
    'eta_stack_LHV_measured', 'sample_coverage_ok', 'is_voltage_window', 'is_h2_window',
  ];
  writeCsv(path.join(stepDirs.step1, 'fangshan_module_aligned_15min_bins_all.csv'), binColumns, rows);
  writeCsv(
    path.join(stepDirs.step1, 'fangshan_module_aligned_15min_profiles.csv'),
    [
      'source_file', 'day', 'slot', 'time_h', 'start', 'end', 'n',
      'power_MW', 'load_fraction', 'I_mean_A', 'V_mean_V',
      'H2_rate_Nm3h', 'H2_step_Nm3', 'H2_theory_rate_Nm3h', 'H2_theory_step_Nm3',
      'eta_current_measured', 'eta_stack_LHV_measured',
      'Tin_C', 'ToutH_C', 'ToutO_C', 'PH_MPa', 'PO_MPa',
      'sample_coverage_ok', 'is_voltage_window', 'is_h2_window',
    ],
    buildModuleAlignedProfiles(rows, binMinutes),
  );
  writeKeyValueCsv(path.join(stepDirs.step1, 'stackA_parameters.csv'), stack);

  const voltageRows = rows.filter((row) => row.is_voltage_window).sort((a, b) => a.start - b.start);
  const h2Rows = rows.filter((row) => row.is_h2_window).sort((a, b) => a.start - b.start);
  writeCsv(path.join(stepDirs.step2, 'fangshan_selected_voltage_windows.csv'), binColumns, voltageRows);
  writeCsv(path.join(stepDirs.step3, 'fangshan_selected_h2_windows.csv'), binColumns, h2Rows);

  if (voltageRows.length < 10) throw new Error('Too few voltage validation windows after filtering.');
  const { train, test, splitLabel } = trainTestSplit(voltageRows);
  const beta = ols(
    train,
    (row) => voltageFeatures(row, stack),
    (row) => row.V_mean_V / stack.nCells,
    3,
  );

  const voltagePredictionRows = voltageRows.map((row) => {
    const predicted = predictVoltage(row, stack, beta);
    return {
      source_file: row.source_file,
      start: row.start,
      set: train.includes(row) ? 'train' : 'test',
      I_mean_A: row.I_mean_A,
      temperature_mean_C: (row.Tin_C + row.ToutH_C + row.ToutO_C) / 3,
      V_measured_V: row.V_mean_V,
      V_predicted_V: predicted,
      error_V: predicted - row.V_mean_V,
      error_mV_per_cell: (predicted - row.V_mean_V) / stack.nCells * 1000,
    };
  });
  writeCsv(
    path.join(stepDirs.step2, 'stackA_voltage_predictions.csv'),
    ['source_file', 'start', 'set', 'I_mean_A', 'temperature_mean_C', 'V_measured_V', 'V_predicted_V', 'error_V', 'error_mV_per_cell'],
    voltagePredictionRows,
  );

  const trainMetrics = metrics(train, (row) => row.V_mean_V, (row) => predictVoltage(row, stack, beta));
  const testMetrics = metrics(test, (row) => row.V_mean_V, (row) => predictVoltage(row, stack, beta));
  const allMetrics = metrics(voltageRows, (row) => row.V_mean_V, (row) => predictVoltage(row, stack, beta));
  const metricRows = [
    {
      item: 'voltage_train',
      split: splitLabel,
      n: trainMetrics.n,
      MAE_V: trainMetrics.MAE,
      RMSE_V: trainMetrics.RMSE,
      MAPE: trainMetrics.MAPE,
      MaxAbs_V: trainMetrics.MaxAbs,
      MAE_mV_per_cell: trainMetrics.MAE / stack.nCells * 1000,
      RMSE_mV_per_cell: trainMetrics.RMSE / stack.nCells * 1000,
    },
    {
      item: 'voltage_test',
      split: splitLabel,
      n: testMetrics.n,
      MAE_V: testMetrics.MAE,
      RMSE_V: testMetrics.RMSE,
      MAPE: testMetrics.MAPE,
      MaxAbs_V: testMetrics.MaxAbs,
      MAE_mV_per_cell: testMetrics.MAE / stack.nCells * 1000,
      RMSE_mV_per_cell: testMetrics.RMSE / stack.nCells * 1000,
    },
    {
      item: 'voltage_all',
      split: splitLabel,
      n: allMetrics.n,
      MAE_V: allMetrics.MAE,
      RMSE_V: allMetrics.RMSE,
      MAPE: allMetrics.MAPE,
      MaxAbs_V: allMetrics.MaxAbs,
      MAE_mV_per_cell: allMetrics.MAE / stack.nCells * 1000,
      RMSE_mV_per_cell: allMetrics.RMSE / stack.nCells * 1000,
    },
  ];
  writeCsv(
    path.join(stepDirs.step2, 'stackA_voltage_validation_metrics.csv'),
    ['item', 'split', 'n', 'MAE_V', 'RMSE_V', 'MAPE', 'MaxAbs_V', 'MAE_mV_per_cell', 'RMSE_mV_per_cell'],
    metricRows,
  );

  const coefficientRows = [
    { coefficient: 'beta0_cell_intercept_V', value: beta[0] },
    { coefficient: 'beta1_cell_J_V_per_A_m2', value: beta[1] },
    { coefficient: 'beta2_cell_JT_V_per_A_m2_C', value: beta[2] },
  ];
  writeCsv(path.join(stepDirs.step2, 'stackA_voltage_model_coefficients.csv'), ['coefficient', 'value'], coefficientRows);

  const currentEfficiencySummary = [
    { metric: 'n_windows', value: h2Rows.length },
    { metric: 'load_fraction_min', value: minValue(h2Rows.map((r) => r.load_fraction)) },
    { metric: 'load_fraction_max', value: maxValue(h2Rows.map((r) => r.load_fraction)) },
    { metric: 'eta_current_mean', value: meanValue(h2Rows.map((r) => r.eta_current_measured)) },
    { metric: 'eta_current_std', value: stdValue(h2Rows.map((r) => r.eta_current_measured)) },
    { metric: 'eta_current_p25', value: quantile(h2Rows.map((r) => r.eta_current_measured), 0.25) },
    { metric: 'eta_current_p75', value: quantile(h2Rows.map((r) => r.eta_current_measured), 0.75) },
    { metric: 'eta_stack_LHV_mean', value: meanValue(h2Rows.map((r) => r.eta_stack_LHV_measured)) },
    { metric: 'eta_stack_LHV_std', value: stdValue(h2Rows.map((r) => r.eta_stack_LHV_measured)) },
  ];
  writeCsv(path.join(stepDirs.step3, 'current_efficiency_summary.csv'), ['metric', 'value'], currentEfficiencySummary);

  const piecewiseRows = buildPiecewiseCurve(h2Rows, 0.05);
  writeCsv(
    path.join(stepDirs.step4, 'stackA_piecewise_efficiency_curve.csv'),
    [
      'load_bin', 'n', 'load_mean', 'power_MW_mean', 'I_mean_A', 'V_mean_V', 'H2_mean_Nm3h',
      'eta_current_mean', 'eta_current_p25', 'eta_current_p75',
      'eta_voltage_LHV_mean', 'eta_voltage_thermoneutral_mean',
      'eta_stack_LHV_mean', 'eta_stack_LHV_p25', 'eta_stack_LHV_p75',
    ],
    piecewiseRows,
  );

  const dailyRows = [];
  const byDay = new Map();
  for (const row of rows) {
    const day = formatTime(row.start).slice(0, 10);
    if (!byDay.has(day)) byDay.set(day, []);
    byDay.get(day).push(row);
  }
  for (const [day, dayRows] of [...byDay.entries()].sort()) {
    dailyRows.push({
      day,
      bins_total: dayRows.length,
      bins_voltage_window: dayRows.filter((r) => r.is_voltage_window).length,
      bins_h2_window: dayRows.filter((r) => r.is_h2_window).length,
      load_min: Math.min(...dayRows.map((r) => r.load_fraction).filter(Number.isFinite)),
      load_max: Math.max(...dayRows.map((r) => r.load_fraction).filter(Number.isFinite)),
      eta_current_h2_window_mean: meanValue(dayRows.filter((r) => r.is_h2_window).map((r) => r.eta_current_measured)),
      eta_stack_LHV_h2_window_mean: meanValue(dayRows.filter((r) => r.is_h2_window).map((r) => r.eta_stack_LHV_measured)),
    });
  }
  writeCsv(
    path.join(stepDirs.step1, 'fangshan_daily_window_summary.csv'),
    ['day', 'bins_total', 'bins_voltage_window', 'bins_h2_window', 'load_min', 'load_max', 'eta_current_h2_window_mean', 'eta_stack_LHV_h2_window_mean'],
    dailyRows,
  );

  const summary = [
    `data_dir,${csvEscape(dataDir)}`,
    `files,${files.length}`,
    `bin_minutes,${binMinutes}`,
    `bins_total,${rows.length}`,
    `voltage_windows,${voltageRows.length}`,
    `h2_windows,${h2Rows.length}`,
    `voltage_all_RMSE_V,${allMetrics.RMSE}`,
    `voltage_all_MAPE,${allMetrics.MAPE}`,
    `voltage_test_RMSE_V,${testMetrics.RMSE}`,
    `voltage_test_MAPE,${testMetrics.MAPE}`,
    `piecewise_bins,${piecewiseRows.length}`,
  ];
  fs.writeFileSync(path.join(outDir, 'validation_run_summary.csv'), `${summary.join('\n')}\n`, 'utf8');
  buildReport({
    outDir,
    dataDir,
    files,
    stack,
    rows,
    voltageRows,
    h2Rows,
    trainMetrics,
    testMetrics,
    allMetrics,
    splitLabel,
    piecewiseRows,
    binMinutes,
    dailyRows,
    beta,
  });
  writeStepReports({
    stepDirs,
    files,
    stack,
    rows,
    voltageRows,
    h2Rows,
    trainMetrics,
    testMetrics,
    allMetrics,
    splitLabel,
    piecewiseRows,
    binMinutes,
    dailyRows,
    beta,
  });

  console.log(`bins_total=${rows.length}`);
  console.log(`voltage_windows=${voltageRows.length}`);
  console.log(`h2_windows=${h2Rows.length}`);
  console.log(`voltage_all_RMSE=${allMetrics.RMSE.toFixed(3)} V, MAPE=${(allMetrics.MAPE * 100).toFixed(3)}%`);
  console.log(`voltage_test_RMSE=${testMetrics.RMSE.toFixed(3)} V, MAPE=${(testMetrics.MAPE * 100).toFixed(3)}%`);
  console.log(`piecewise_bins=${piecewiseRows.length}`);
  console.log(`out_dir=${outDir}`);
}

run();
