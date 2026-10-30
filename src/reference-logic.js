/* Periop Signal reference logic: the website's copy of the app's calculators (ios/Shared/*.swift).
   Pure functions and data only, no DOM, so tools/test_reference_logic.js can run it under Node.
   Keep in step with the Swift files named in each section; the unit tests mirror ios/Tests/ReferenceTests.swift. */
(function (global) {
  'use strict';
  const R = {};

  // ---------- formatting (PedsCalc.fmt and friends) ----------
  /** Round half away from zero, like Swift's .rounded(). */
  function rnd(x) { return x < 0 ? -Math.round(-x) : Math.round(x); }
  /** Clinical rounding: 2 decimals under 1, 1 decimal under 10, whole numbers from 10. */
  R.fmt = function (v) {
    let r;
    if (v < 1) r = rnd(v * 100) / 100;
    else if (v < 10) r = rnd(v * 10) / 10;
    else r = rnd(v);
    if (r === Math.trunc(r)) return String(Math.trunc(r));
    let s = r.toFixed(2);
    while (s.endsWith('0')) s = s.slice(0, -1);
    if (s.endsWith('.')) s = s.slice(0, -1);
    return s;
  };
  R.range = (lo, hi) => Math.abs(hi - lo) < 0.0001 ? R.fmt(lo) : R.fmt(lo) + '–' + R.fmt(hi);
  R.half = (v) => R.fmt(rnd(v * 2) / 2);
  R.tenth = (v) => R.fmt(rnd(v * 10) / 10);
  /** "2,5" or "2.5" → 2.5; anything not a positive number → null. */
  R.num = function (text) {
    if (text === null || text === undefined) return null;
    const v = parseFloat(String(text).trim().replace(',', '.'));
    return Number.isFinite(v) && v > 0 ? v : null;
  };
  /** Like R.num but keeps zero and negative values (Ar − A, the change in E/A with Valsalva); "−" counts as a minus. */
  R.numSigned = function (text) {
    if (text === null || text === undefined) return null;
    const t = String(text).trim().replace(',', '.').replace(/^[\u2212\u2013]/, '-');
    if (!/^-?(\d+\.?\d*|\.\d+)$/.test(t)) return null;
    const v = parseFloat(t);
    return Number.isFinite(v) ? v : null;
  };

  // ---------- Title Case (TitleCase.swift) ----------
  const SMALL = new Set(['a', 'an', 'and', 'as', 'at', 'but', 'by', 'for', 'from', 'if', 'in', 'into', 'nor', 'of', 'off', 'on', 'or', 'per', 'than', 'the', 'to', 'up', 'vs', 'vs.', 'via', 'with']);
  const KEEP = new Set(['mg', 'mcg', 'kg', 'g', 'ng', 'ml', 'mL', 'dL', 'dl', 'h', 'min', 'ppm', 'mmHg', 'cm', 'mm', 'pH', 'iNO', 'iEPO', 'eGFR', 'e.g.', 'i.e.', 'et', 'al', 'x']);
  const PREFIXES = new Set(['non', 'anti', 'pre', 'post', 're', 'co', 'sub', 'semi', 'multi', 'inter', 'intra', 'peri', 'self']);
  const isLetter = (c) => /\p{L}/u.test(c), isNumber = (c) => /\p{N}/u.test(c), isLower = (c) => /\p{Ll}/u.test(c);
  const TRIM = new Set(['.', ',', ';', ':', '!', '?', ')', ']', '”', '"', '’', "'"]);
  function capPart(word, force) {
    const chars = Array.from(word);
    const i = chars.findIndex(isLetter);
    if (i < 0) return word;
    const lead = chars.slice(0, i).join(''), coreArr = chars.slice(i);
    let a = 0, b = coreArr.length;
    while (a < b && TRIM.has(coreArr[a])) a++;
    while (b > a && TRIM.has(coreArr[b - 1])) b--;
    const bare = coreArr.slice(a, b).join('');
    if (KEEP.has(bare) || Array.from(bare).some(isNumber)) return word;
    const slash = bare.indexOf('/');
    if (slash >= 0 && KEEP.has(bare.slice(0, slash))) return word;
    if (bare.slice(0, -1).includes('.')) return word;
    if (!force && SMALL.has(bare.toLowerCase()) && bare === bare.toLowerCase()) return word;
    const c = coreArr[0];
    if (!c || !isLower(c)) return word;
    return lead + c.toUpperCase() + coreArr.slice(1).join('');
  }
  function capWord(word, force) {
    const parts = word.split('-');
    if (parts.length < 2) return capPart(word, force);
    return parts.map((p, i) => {
      if (i === 0) return capPart(p, force);
      const prev = Array.from(parts[i - 1].toLowerCase()).filter(isLetter).join('');
      return PREFIXES.has(prev) ? p : capPart(p, false);
    }).join('-');
  }
  R.titleCase = function (s) {
    const words = String(s).split(' ');
    let start = true;
    return words.map((w, i) => {
      const out = capWord(w, start || i === words.length - 1);
      const t = w.trim();
      start = t.endsWith(':') || t.endsWith('—') || t === '—' || t === '–';
      return out;
    }).join(' ');
  };

  // ---------- Scores (Scores.swift) ----------
  const toggle = (id, label, detail, points) => ({ id, label, detail: detail || null, kind: 'toggle', points: points === undefined ? 1 : points });
  const choice = (id, label, detail, options) => ({ id, label, detail: detail || null, kind: 'choice', options: options.map(([l, p]) => ({ label: l, points: p })) });
  const band = (lo, hi, label, detail, tone) => ({ lo, hi, label, detail, tone });
  const src = (title, citation, url, doi) => ({ title, citation, url, doi });

  R.scores = [
    {
      id: 'rcri', name: 'Revised Cardiac Risk Index', short: 'RCRI', blurb: 'Risk of major cardiac complications after non-cardiac surgery',
      items: [
        toggle('surgery', 'High-risk surgery', 'Intraperitoneal, intrathoracic or suprainguinal vascular'),
        toggle('ihd', 'Ischemic heart disease', 'Prior MI, positive stress test, current ischemic chest pain, nitrate use, or Q waves'),
        toggle('hf', 'History of heart failure', 'Pulmonary edema, paroxysmal nocturnal dyspnea, S3 or rales, or CXR pulmonary vascular redistribution'),
        toggle('cva', 'Cerebrovascular disease', 'Prior stroke or transient ischemic attack'),
        toggle('insulin', 'Insulin therapy for diabetes'),
        toggle('creatinine', 'Creatinine > 2.0 mg/dL', '> 177 µmol/L preoperatively'),
      ],
      bands: [
        band(0, 0, 'Class I · 0 predictors', '3.9% (95% CI 2.8–5.4) · Lee 1999 validation cohort 0.4%', 'low'),
        band(1, 1, 'Class II · 1 predictor', '6.0% (4.9–7.4) · Lee 0.9%', 'low'),
        band(2, 2, 'Class III · 2 predictors', '10.1% (8.1–12.6) · Lee 6.6%', 'moderate'),
        band(3, 6, 'Class IV · 3 or more', '15.0% (11.1–20.0) · Lee 11.0%', 'high'),
      ],
      readout: 'First figure: pooled 30-day risk of MI, cardiac arrest or death from the 2017 CCS guideline’s external validation studies. Second: Lee’s 1999 validation cohort (in-hospital MI, pulmonary edema, VF or cardiac arrest, complete heart block).',
      source: src('Derivation and prospective validation of a simple index for prediction of cardiac risk of major noncardiac surgery', 'Lee TH, et al. Circulation. 1999;100:1043–1049.', 'https://doi.org/10.1161/01.CIR.100.10.1043', '10.1161/01.CIR.100.10.1043'),
      rateSource: src('Canadian Cardiovascular Society guidelines on perioperative cardiac risk assessment and management for patients who undergo noncardiac surgery', 'Duceppe E, et al. Can J Cardiol. 2017;33:17–32.', 'https://doi.org/10.1016/j.cjca.2016.09.008', '10.1016/j.cjca.2016.09.008'),
      notes: ['Derived in patients ≥ 50 years having elective major non-cardiac surgery; emergency surgery and low-risk procedures were excluded.',
        'The CCS guideline pairs RCRI ≥ 1 (or age ≥ 65, or 45–64 with significant cardiovascular disease) with preoperative NT-proBNP/BNP measurement.'],
      keywords: ['cardiac risk', 'lee index', 'preoperative evaluation', 'noncardiac surgery', 'mace'],
    },
    {
      id: 'ariscat', name: 'ARISCAT', short: 'ARISCAT', blurb: 'Risk of postoperative pulmonary complications',
      items: [
        choice('age', 'Age', null, [['≤ 50', 0], ['51–80', 3], ['> 80', 16]]),
        choice('spo2', 'Preoperative SpO₂', 'Room air, supine', [['≥ 96%', 0], ['91–95%', 8], ['≤ 90%', 24]]),
        toggle('infection', 'Respiratory infection in the last month', 'Upper or lower respiratory infection within the previous month', 17),
        toggle('anemia', 'Preoperative anemia', 'Hemoglobin ≤ 10 g/dL', 11),
        choice('incision', 'Surgical incision', null, [['Peripheral', 0], ['Upper abdominal', 15], ['Intrathoracic', 24]]),
        choice('duration', 'Duration of surgery', null, [['≤ 2 h', 0], ['> 2–3 h', 16], ['> 3 h', 23]]),
        toggle('emergency', 'Emergency procedure', null, 8),
      ],
      bands: [
        band(0, 25, 'Low risk · < 26 points', '1.6% pulmonary complications in the development sample', 'low'),
        band(26, 44, 'Intermediate · 26–44', '13.3%', 'moderate'),
        band(45, 123, 'High · ≥ 45', '42.1%', 'high'),
      ],
      readout: 'In-hospital postoperative pulmonary complications (respiratory infection or failure, bronchospasm, atelectasis, pleural effusion, pneumothorax, aspiration pneumonitis); 5% overall in the 2,464-patient cohort.',
      source: src('Prediction of postoperative pulmonary complications in a population-based surgical cohort', 'Canet J, et al. Anesthesiology. 2010;113:1338–1350.', 'https://doi.org/10.1097/ALN.0b013e3181fc6e0a', '10.1097/ALN.0b013e3181fc6e0a'),
      rateSource: null,
      notes: ['Derived from 2,464 patients in 59 Catalan hospitals having non-obstetric surgery under general, neuraxial or regional anesthesia; AUC 0.90 (development) and 0.88 (validation).',
        'External validation (PERISCOPE, 2014) found higher observed rates in the low and intermediate classes than predicted.'],
      keywords: ['pulmonary complications', 'ppc', 'respiratory risk', 'canet'],
    },
    {
      id: 'stopbang', name: 'STOP-Bang', short: 'STOP-Bang', blurb: 'Screening for obstructive sleep apnea',
      items: [
        toggle('snoring', 'Snoring', 'Loud enough to be heard through a closed door, or a bed partner elbows you'),
        toggle('tired', 'Tired', 'Often tired, fatigued or sleepy during the day'),
        toggle('observed', 'Observed apnea', 'Anyone has seen you stop breathing or choke/gasp during sleep'),
        toggle('pressure', 'Pressure', 'Treated or untreated high blood pressure'),
        toggle('bmi', 'BMI > 35 kg/m²'),
        toggle('age', 'Age > 50 years'),
        toggle('neck', 'Neck circumference > 40 cm', 'About 16 in, measured at the laryngeal prominence (the Toronto form uses ≥ 43 cm for men and ≥ 41 cm for women)'),
        toggle('gender', 'Male'),
      ],
      bands: [
        band(0, 2, 'Low risk · 0–2', 'Moderate-to-severe OSA unlikely', 'low'),
        band(3, 4, 'Intermediate · 3–4', 'A score ≥ 3 is 93% sensitive for AHI > 15 and 100% for AHI > 30; specificity is modest, so weigh BMI, neck size and sex', 'moderate'),
        band(5, 8, 'High risk · 5–8', 'High probability of moderate-to-severe OSA', 'high'),
      ],
      readout: 'Count of yes answers. The 2016 update also classes yes to ≥ 2 of the STOP questions plus male sex, BMI > 35 or neck > 40 cm as high risk.',
      source: src('STOP questionnaire: a tool to screen patients for obstructive sleep apnea', 'Chung F, et al. Anesthesiology. 2008;108:812–821.', 'https://doi.org/10.1097/ALN.0b013e31816d83e4', '10.1097/ALN.0b013e31816d83e4'),
      rateSource: src('STOP-Bang questionnaire: a practical approach to screen for obstructive sleep apnea', 'Chung F, Abdullah HR, Liao P. Chest. 2016;149:631–638.', 'https://doi.org/10.1378/chest.15-0903', '10.1378/chest.15-0903'),
      notes: ['Validated against polysomnography in surgical patients; the probability of moderate-to-severe OSA rises steadily with the score.'],
      keywords: ['osa', 'sleep apnea', 'screening', 'airway'],
    },
    {
      id: 'aldrete', name: 'Modified Aldrete score', short: 'Aldrete', blurb: 'Readiness to leave the recovery room',
      items: [
        choice('activity', 'Activity', 'Voluntary or on command', [['Moves 4 extremities', 2], ['Moves 2 extremities', 1], ['Moves 0 extremities', 0]]),
        choice('respiration', 'Respiration', null, [['Breathes deeply and coughs freely', 2], ['Dyspnea, shallow or limited breathing', 1], ['Apneic', 0]]),
        choice('circulation', 'Circulation', 'Blood pressure versus the pre-anesthetic level', [['Within ± 20%', 2], ['± 20–49%', 1], ['± 50% or more', 0]]),
        choice('consciousness', 'Consciousness', null, [['Fully awake', 2], ['Arousable on calling', 1], ['Not responding', 0]]),
        choice('oxygen', 'Oxygen saturation', null, [['> 92% on room air', 2], ['Needs O₂ to keep > 90%', 1], ['< 90% even with O₂', 0]]),
      ],
      bands: [
        band(0, 8, 'Not ready · < 9', 'Continue phase I recovery', 'high'),
        band(9, 10, 'Ready · 9–10', 'Meets the discharge criterion for phase I recovery', 'low'),
      ],
      readout: 'Total 0–10; a score of 9 or more is the usual criterion for discharge from phase I recovery.',
      source: src('The post-anesthesia recovery score revisited', 'Aldrete JA. J Clin Anesth. 1995;7:89–91.', 'https://doi.org/10.1016/0952-8180(94)00001-K', '10.1016/0952-8180(94)00001-K'),
      rateSource: null,
      notes: ['The 1995 revision replaced the 1970 score’s color criterion (pink / pale or dusky / cyanotic) with pulse oximetry.'],
      keywords: ['pacu', 'recovery', 'discharge criteria', 'phase i'],
    },
    {
      id: 'apfel', name: 'Apfel PONV score', short: 'Apfel', blurb: 'Risk of postoperative nausea and vomiting, with the consensus prophylaxis',
      items: [
        toggle('female', 'Female sex'),
        toggle('nonsmoker', 'Non-smoker'),
        toggle('history', 'History of PONV or motion sickness'),
        toggle('opioids', 'Postoperative opioids expected'),
      ],
      bands: [
        band(0, 0, '0 factors · 10%', 'Low risk. Fifth consensus (2025): two prophylactic interventions for adults at any risk', 'low'),
        band(1, 1, '1 factor · 21%', 'Medium risk: two interventions (e.g. dexamethasone + a 5-HT₃ antagonist)', 'low'),
        band(2, 2, '2 factors · 39%', 'Medium risk: two interventions', 'moderate'),
        band(3, 3, '3 factors · 61%', 'High risk: three to four interventions from different classes, plus risk reduction (TIVA, opioid-sparing, regional)', 'high'),
        band(4, 4, '4 factors · 79%', 'High risk: three to four interventions, plus risk reduction', 'high'),
      ],
      readout: 'Incidence of PONV within 24 h in Apfel’s 1999 cohorts (inhalational anesthesia, no prophylaxis). Rescue uses a class not already given; a same-class repeat within 6 h adds nothing.',
      source: src('A simplified risk score for predicting postoperative nausea and vomiting', 'Apfel CC, et al. Anesthesiology. 1999;91:693–700.', 'https://doi.org/10.1097/00000542-199909000-00022', '10.1097/00000542-199909000-00022'),
      rateSource: src('Fifth Consensus Guidelines for the Management of Postoperative Nausea and Vomiting: Executive Summary', 'Gan TJ, Jin Z, Ayad S, et al. Anesth Analg. 2025; published online ahead of print.', 'https://doi.org/10.1213/ANE.0000000000007816', '10.1213/ANE.0000000000007816'),
      notes: ['See the PONV quick reference for agents, doses and timing.', 'The Fifth consensus (2025) supersedes the 2020 Fourth: it counts 0 factors as low, 1–2 as medium and ≥ 3 as high risk, adds IV aprepitant and IV amisulpride, and no longer recommends metoclopramide for prophylaxis.'],
      keywords: ['ponv', 'nausea', 'vomiting', 'antiemetic', 'prophylaxis'],
      next: { label: 'Prophylaxis plan', quickref: 'ponv-consensus' },
    },
  ];
  R.score = (id) => R.scores.find((s) => s.id === id) || null;
  R.scoreMax = (def) => def.items.reduce((t, it) => t + (it.kind === 'toggle' ? it.points : Math.max(...it.options.map((o) => o.points))), 0);
  /** sel = { on: Set of toggle ids, choices: { itemId: optionLabel } }; an unanswered choice counts its first option. */
  R.scoreTotal = (def, sel) => def.items.reduce((t, it) => {
    if (it.kind === 'toggle') return t + (sel.on.has(it.id) ? it.points : 0);
    const chosen = sel.choices[it.id];
    if (chosen === undefined) return t + (it.options[0] ? it.options[0].points : 0);
    const o = it.options.find((x) => x.label === chosen);
    return t + (o ? o.points : 0);
  }, 0);
  R.scoreBand = (def, score) => def.bands.find((b) => score >= b.lo && score <= b.hi) || null;
  R.scoreSearchText = (def) => [def.name, def.short, def.blurb].concat(def.keywords || [], def.items.map((i) => i.label)).join(' ').toLowerCase();

  // ---------- Pediatric arithmetic (PedsCalc.swift) ----------
  R.peds = {
    /** APLS: (0.5 × months) + 4 under 1 year, (age + 4) × 2 for 1–5 years, (3 × age) + 7 for 6–12 years. */
    estimatedWeight(years, months) {
      const total = years * 12 + months;
      if (total < 1) return null;
      if (total < 12) return 0.5 * total + 4;
      const age = total / 12;
      if (age <= 5) return (age + 4) * 2;
      if (age <= 12) return 3 * age + 7;
      return null;
    },
    ettSizes(years, months) {
      const total = years * 12 + months;
      if (total < 1) return { uncuffed: '3.0–3.5', cuffed: '3.0' };
      if (total < 12) return { uncuffed: '3.5–4.0', cuffed: '3.0–3.5' };
      if (total < 24) return { uncuffed: '4.0–4.5', cuffed: '3.5–4.0' };
      const age = total / 12;
      return { uncuffed: R.half(age / 4 + 4), cuffed: R.half(age / 4 + 3.5) };
    },
    ettDepthOral(years, months, uncuffedID) {
      const total = years * 12 + months;
      if (total >= 24) return R.tenth(total / 12 / 2 + 12);
      if (uncuffedID) return R.tenth(uncuffedID * 3);
      return '—';
    },
    ettDepthNasal(years, months) {
      const total = years * 12 + months;
      return total >= 24 ? R.tenth(total / 12 / 2 + 15) : '—';
    },
    lmaSize(w) {
      if (w < 5) return '1'; if (w < 10) return '1.5'; if (w < 20) return '2'; if (w < 30) return '2.5';
      if (w < 50) return '3'; if (w < 70) return '4'; if (w < 100) return '5'; return '6';
    },
    maintenance(w) {
      if (!(w > 0)) return 0;
      return 4 * Math.min(w, 10) + 2 * Math.min(Math.max(w - 10, 0), 10) + Math.max(w - 20, 0);
    },
    bloodVolume(w, ageMonths, rows) {
      const row = rows.find((r) => (r.fromMonths ?? -1) <= ageMonths && ageMonths < (r.toMonths ?? Infinity)) || rows[rows.length - 1];
      if (!row) return null;
      return { row, low: row.mlPerKgLow * w, high: row.mlPerKgHigh * w };
    },
    mabl(ebv, hs, hm) {
      if (!(ebv > 0) || !(hs > hm) || !(hm > 0)) return null;
      return ebv * (hs - hm) / hs;
    },
    localAnestheticMax(mgPerKg, w, percent) { const mg = mgPerKg * w; return { mg, mL: mg / (percent * 10) }; },
    /** "12–18 mg" for a per-kg dose at a weight, held within min and max. */
    doseText(low, high, unit, w, min, max) {
      let lo = low * w, hi = (high ?? low) * w, capped = false;
      if (min !== null && min !== undefined) { if (lo < min) { lo = min; capped = true; } if (hi < min) { hi = min; capped = true; } }
      if (max !== null && max !== undefined) { if (lo > max) { lo = max; capped = true; } if (hi > max) { hi = max; capped = true; } }
      if (Math.abs(hi - lo) < 0.0001) return { text: R.fmt(lo) + ' ' + unit, capped };
      return { text: R.fmt(lo) + '–' + R.fmt(hi) + ' ' + unit, capped };
    },
  };

  // ---------- Infusions (InfusionCalc) ----------
  R.scaled = function (lo, hi, unit) {
    let l = lo, h = hi, u = unit;
    const hv = () => (h === null || h === undefined ? l : h);
    const div = () => { l /= 1000; if (h !== null && h !== undefined) h /= 1000; };
    if (u === 'ng' && l >= 1000 && hv() >= 1000) { div(); u = 'mcg'; }
    if (u === 'mcg' && l >= 1000 && hv() >= 1000) { div(); u = 'mg'; }
    if (u === 'mg' && l >= 1000 && hv() >= 1000) { div(); u = 'g'; }
    return { lo: l, hi: h, unit: u };
  };
  R.total = function (lo, hi, unit) {
    const s = R.scaled(lo, hi, unit);
    if (s.hi !== null && s.hi !== undefined && Math.abs(s.hi - s.lo) > 0.0001) return R.fmt(s.lo) + '–' + R.fmt(s.hi) + ' ' + s.unit;
    return R.fmt(s.lo) + ' ' + s.unit;
  };
  R.infusionLines = function (d, w) {
    if (d.start === null || d.start === undefined) return { dose: d.range || 'see notes', equivalent: null };
    const unit = d.unit || 'mcg', start = d.start, hiv = d.startHigh ?? null;
    const span = (lo, hi, u) => (hi !== null && hi !== undefined && Math.abs(hi - lo) > 0.0001) ? R.fmt(lo) + '–' + R.fmt(hi) + ' ' + u : R.fmt(lo) + ' ' + u;
    const hasW = w !== null && w !== undefined && w > 0;
    const at = hasW ? ' at ' + R.fmt(w) + ' kg' : '';
    switch (d.form) {
      case 'perKgPerMin': {
        const dose = span(start, hiv, unit + '/kg/min');
        if (!hasW) return { dose, equivalent: null };
        const s = R.scaled(start * w, hiv === null ? null : hiv * w, unit);
        return { dose, equivalent: span(s.lo, s.hi, s.unit + '/min') + at };
      }
      case 'perMin': {
        const dose = span(start, hiv, unit + '/min');
        if (!hasW) return { dose, equivalent: null };
        return { dose, equivalent: span(start / w, hiv === null ? null : hiv / w, unit + '/kg/min') + at };
      }
      case 'perKg': {
        const dose = span(start, hiv, unit + '/kg');
        if (!hasW) return { dose, equivalent: null };
        return { dose, equivalent: R.total(start * w, hiv === null ? null : hiv * w, unit) + at };
      }
      case 'perKgPerHour': {
        const dose = span(start, hiv, unit + '/kg/h');
        if (!hasW) return { dose, equivalent: null };
        const s = R.scaled(start * w, hiv === null ? null : hiv * w, unit);
        return { dose, equivalent: span(s.lo, s.hi, s.unit + '/h') + at };
      }
      case 'perHour': return { dose: span(start, hiv, unit + '/h'), equivalent: null };
      case 'fixed': return { dose: span(start, hiv, unit), equivalent: null };
      default: return { dose: d.range || 'see notes', equivalent: null };
    }
  };
  /** "Dexmedetomidine (Precedex)" → { main: "Dexmedetomidine", alias: "Precedex" }. */
  R.nameParts = function (name) {
    if (!name.endsWith(')')) return { main: name, alias: null };
    const i = name.lastIndexOf(' (');
    if (i < 0) return { main: name, alias: null };
    return { main: name.slice(0, i), alias: name.slice(i + 2, -1) };
  };

  // ---------- Local anesthetic mixtures (LocalAnesthetics.swift) ----------
  R.la = {
    maxMg(agent, w, pediatric, epi, ageYears) {
      if (!(w > 0)) return null;
      const has = (v) => v !== null && v !== undefined;
      if (pediatric) {
        if (has(agent.pedsMinYears) && has(ageYears) && ageYears < agent.pedsMinYears) return null;
        const perKg = (epi && has(agent.pedsEpiMgPerKg)) ? agent.pedsEpiMgPerKg : agent.maxMgPerKg;
        let m = perKg * w;
        const cap = epi ? (agent.pedsMaxMg ?? agent.adultEpiMaxMg ?? agent.adultPlainMaxMg) : (agent.pedsMaxMg ?? agent.adultPlainMaxMg);
        if (has(cap)) m = Math.min(m, cap);
        return m;
      }
      const perKg = epi ? (agent.adultEpiMgPerKg ?? agent.adultPlainMgPerKg) : agent.adultPlainMgPerKg;
      const cap = epi ? (agent.adultEpiMaxMg ?? agent.adultPlainMaxMg) : agent.adultPlainMaxMg;
      if (has(perKg) && has(cap)) return Math.min(perKg * w, cap);
      if (has(perKg)) return perKg * w;
      if (has(cap)) return cap;
      return null;
    },
    /** entries: [{ id, agentID, percent, mL }] */
    evaluate(entries, agents, w, pediatric, epi, ageYears) {
      const byID = Object.fromEntries(agents.map((a) => [a.id, a]));
      const results = [];
      for (const e of entries) {
        const agent = byID[e.agentID]; if (!agent) continue;
        const mg = e.percent * 10 * e.mL;
        const maxMg = R.la.maxMg(agent, w, pediatric, epi, ageYears);
        results.push({ id: e.id, agent, percent: e.percent, mL: e.mL, mg, maxMg, remainingML: null,
          get fraction() { return (this.maxMg || 0) > 0 ? this.mg / this.maxMg : 0; },
          get maxMLAlone() { return this.maxMg === null ? null : this.maxMg / (this.percent * 10); } });
      }
      const combined = results.reduce((t, r) => t + r.fraction, 0);
      const remaining = Math.max(0, 1 - combined);
      for (const r of results) if (r.maxMg !== null && r.percent > 0) r.remainingML = remaining * r.maxMg / (r.percent * 10);
      const warnings = [];
      if (combined > 1) warnings.push('The mixture exceeds the combined maximum (' + rnd(combined * 100) + '% of the additive limit).');
      for (const r of results) {
        if (r.maxMg === null && r.mg > 0) {
          if (pediatric && r.agent.pedsMinYears !== null && r.agent.pedsMinYears !== undefined) warnings.push(r.agent.name + ' is not labeled under ' + r.agent.pedsMinYears + ' years; no pediatric maximum is applied.');
          else warnings.push('No maximum is on file for ' + r.agent.name + ' in this setting.');
        }
      }
      const isLipo = (a) => a.kind === 'liposomal';
      const lipo = results.filter((r) => isLipo(r.agent) && r.mg > 0);
      if (lipo.length) {
        const l = lipo[0];
        const hcl = results.filter((r) => !isLipo(r.agent) && r.agent.id.startsWith('bupivacaine') && r.mg > 0).reduce((t, r) => t + r.mg, 0);
        if (hcl > 0.5 * l.mg + 0.0001) warnings.push('Bupivacaine HCl (' + R.fmt(hcl) + ' mg) exceeds half the Exparel dose (' + R.fmt(l.mg) + ' mg): the label limits the ratio to 1:2.');
        const others = results.filter((r) => !isLipo(r.agent) && !r.agent.id.startsWith('bupivacaine') && r.mg > 0);
        if (others.some((r) => r.agent.id.startsWith('lidocaine'))) warnings.push('Give Exparel at least 20 minutes after lidocaine, which otherwise releases bupivacaine from the liposomes.');
        const nonLido = others.filter((r) => !r.agent.id.startsWith('lidocaine'));
        if (nonLido.length) warnings.push('Exparel is not to be mixed with local anesthetics other than bupivacaine HCl, and no other local anesthetic should follow it for 96 hours.');
        else if (hcl === 0 && others.length === 0) warnings.push('After Exparel, no other local anesthetic for 96 hours.');
      }
      if (epi && results.some((r) => isLipo(r.agent) && r.mg > 0)) warnings.push('Exparel’s maximum does not change with epinephrine.');
      return { agents: results, combined, warnings, percentUsed: rnd(combined * 100) };
    },
  };

  // ---------- Neuraxial timing (NeuraxialCalc) ----------
  R.fmtHours = function (h) {
    if (h >= 48 && h % 24 === 0) return (h / 24) + ' days';
    return h === Math.round(h) ? h + ' h' : h.toFixed(1) + ' h';
  };
  /** Earliest block for a tier: { earliest (ms) | null, hours, rule, avoid }. */
  R.neuraxialAnswer = function (tier, renalIndex, elderly, lastDoseMs) {
    let hours = tier.holdHours ?? null, rule = tier.holdText || '', avoid = false;
    if (tier.renal && tier.renal.length) {
      const r = tier.renal[Math.min(Math.max(renalIndex || 0, 0), tier.renal.length - 1)];
      if (r.hours !== null && r.hours !== undefined) {
        hours = (elderly && r.elderlyHours !== null && r.elderlyHours !== undefined) ? r.elderlyHours : r.hours;
        rule = R.fmtHours(hours) + ' after the last dose (' + R.softLower(r.label) + (elderly && r.elderlyHours !== null && r.elderlyHours !== undefined ? ', elderly' : '') + ')';
      } else {
        hours = null; avoid = true; rule = r.text || 'Avoid the block';
      }
    } else if (hours !== null) {
      if (!rule) rule = R.fmtHours(hours) + ' after the last dose';
      if (hours === 0) rule = tier.holdText || 'No hold required';
    } else {
      avoid = (tier.holdText || '').toLowerCase().includes('against');
      if (!rule) rule = 'No interval specified';
    }
    return { earliest: hours === null ? null : lastDoseMs + hours * 3600000, hours, rule, avoid };
  };
  /** "Normal renal function" → "normal renal function"; "CrCl 30–49 mL/min" stays as written. */
  R.softLower = function (s) {
    const first = s.split(' ')[0];
    if (/\p{Lu}/u.test(first.slice(1))) return s;
    return s.charAt(0).toLowerCase() + s.slice(1);
  };
  R.countdown = function (toMs, fromMs) {
    const secs = (toMs - fromMs) / 1000;
    if (secs <= 0) return 'now';
    const total = Math.trunc(secs / 60), days = Math.trunc(total / 1440), hours = Math.trunc((total % 1440) / 60), minutes = total % 60;
    if (days > 0) return 'in ' + days + ' d ' + hours + ' h';
    if (hours > 0) return 'in ' + hours + ' h ' + minutes + ' min';
    return 'in ' + minutes + ' min';
  };

  // ---------- Fasting (FastingView.swift) ----------
  R.fasting = {
    intakes: [
      { id: 'clear', label: 'Clear liquids', hours: 2, detail: 'Water, pulp-free juice, carbonated drinks, clear tea, black coffee' },
      { id: 'carb', label: 'Carbohydrate drink', hours: 2, detail: 'Adults: encouraged up to 400 mL until 2 h before (2023)' },
      { id: 'breast', label: 'Breast milk', hours: 4, detail: '' },
      { id: 'formula', label: 'Infant formula', hours: 6, detail: '' },
      { id: 'milk', label: 'Non-human milk', hours: 6, detail: 'Empties like a solid; the amount matters' },
      { id: 'light', label: 'Light meal', hours: 6, detail: 'Toast and clear liquids' },
      { id: 'heavy', label: 'Fried or fatty food, meat', hours: 8, detail: 'Additional time, 8 hours or more' },
      { id: 'gum', label: 'Chewing gum', hours: 0, detail: 'Does not delay or cancel; remove before any sedative' },
    ],
    conditions: ['Pregnancy or labor', 'Obesity', 'Diabetes', 'Hiatal hernia or uncontrolled reflux', 'Achalasia, stricture or Zenker diverticulum',
      'Previous gastric surgery', 'Gastroparesis', 'Opioid use', 'Ileus, obstruction or acute abdomen', 'Emergency procedure', 'Enteral tube feeding', 'Potentially difficult airway'],
    /** taken: { intakeId: ms }. Returns { date (ms), because (intake) } or null. */
    earliest(taken) {
      let best = null;
      for (const i of R.fasting.intakes) {
        const t = taken[i.id]; if (t === undefined || t === null) continue;
        const ready = t + i.hours * 3600000;
        if (!best || ready > best.date) best = { date: ready, because: i };
      }
      return best;
    },
  };

  // ---------- PONV (PONVPlan) ----------
  R.ponv = {
    target: (factors, counts) => counts.find((c) => factors >= c.minFactors && factors <= c.maxFactors) || null,
    classes(chosen, agents) { const seen = []; for (const a of agents) if (chosen.has(a.id) && !seen.includes(a.class)) seen.push(a.class); return seen; },
    rescueOptions(chosen, agents) { const used = new Set(R.ponv.classes(chosen, agents)); return agents.filter((a) => a.rescue === true && !used.has(a.class)); },
    longActingGiven: (chosen, agents) => agents.filter((a) => chosen.has(a.id) && a.longActing === true),
  };

  // ---------- ASE valve severity (ValveGrading.swift) ----------
  const GRADE = { 1: 'Mild', 2: 'Moderate', 3: 'Severe' };
  R.gradeLabel = (g) => GRADE[g] || '';
  R.valveLesions = [
    { id: 'as', name: 'Aortic stenosis', short: 'AS', source: 'EACVI/ASE 2017 aortic stenosis focused update, Table 3 and the stepwise low-gradient pathway' },
    { id: 'ar', name: 'Aortic regurgitation', short: 'AR', source: 'ASE 2017 native valvular regurgitation, Table 11' },
    { id: 'mr', name: 'Mitral regurgitation', short: 'MR', source: 'ASE 2017 native valvular regurgitation, Table 8 and Figure 18' },
    { id: 'ms', name: 'Mitral stenosis', short: 'MS', source: 'ASE 2023 rheumatic heart disease, Table 1 (ASE’s current mitral stenosis criteria)' },
    { id: 'tr', name: 'Tricuspid regurgitation', short: 'TR', source: 'ASE 2017 native valvular regurgitation, Table 14' },
  ];
  const num = (id, label, unit, mild, severe, opts) => ({ id, label, unit, kind: 'higher', mild, severe, specific: !!(opts && opts.specific), hint: (opts && opts.hint) || null });
  const inv = (id, label, unit, mild, severe, opts) => ({ id, label, unit, kind: 'lower', mild, severe, specific: !!(opts && opts.specific), hint: (opts && opts.hint) || null });
  const sign = (id, label, grade, hint) => ({ id, label, unit: '', kind: 'sign', grade, specific: true, hint: hint || null });
  const ctx = (id, label, unit, hint) => ({ id, label, unit, kind: 'context', specific: false, hint: hint || null });
  const severeOnly = (id, label, unit, from, hint) => ({ id, label, unit, kind: 'severeFrom', severe: from, specific: false, hint: hint || null });
  R.valveParams = function (lesion) {
    switch (lesion) {
      case 'as': return [
        num('vmax', 'Peak velocity', 'm/s', 3.0, 4.0, { specific: true, hint: 'Mild 2.6–2.9 · moderate 3.0–4.0 · severe ≥ 4.0' }),
        num('mg', 'Mean gradient', 'mmHg', 20, 40, { specific: true, hint: 'Mild < 20 · moderate 20–40 · severe ≥ 40' }),
        inv('ava', 'Aortic valve area', 'cm²', 1.5, 1.0, { hint: 'Mild > 1.5 · moderate 1.0–1.5 · severe < 1.0' }),
        inv('avai', 'Indexed valve area', 'cm²/m²', 0.85, 0.6, { hint: 'Severe < 0.6' }),
        inv('ratio', 'Velocity ratio', '', 0.5, 0.25, { hint: 'LVOT ÷ aortic velocity; severe < 0.25' }),
        ctx('svi', 'Stroke volume index', 'mL/m²', 'Low flow < 35'),
        ctx('lvef', 'LVEF', '%', 'Decides the low-flow, low-gradient pathway'),
      ];
      case 'ar': return [
        num('vc', 'Vena contracta width', 'cm', 0.3, 0.61, { specific: true, hint: 'Mild < 0.3 · moderate 0.3–0.6 · severe > 0.6' }),
        num('jetw', 'Jet width ÷ LVOT width', '%', 25, 65, { hint: 'Central jets; severe ≥ 65' }),
        num('jeta', 'Jet area ÷ LVOT area', '%', 5, 60, { hint: 'Central jets; severe ≥ 60' }),
        inv('pht', 'Pressure half-time', 'ms', 500, 200, { hint: 'Mild > 500 · moderate 200–500 · severe < 200' }),
        num('rvol', 'Regurgitant volume', 'mL', 30, 60, { hint: 'Mild < 30 · moderate 30–59 · severe ≥ 60' }),
        num('rf', 'Regurgitant fraction', '%', 30, 50, { hint: 'Severe ≥ 50' }),
        num('eroa', 'EROA', 'cm²', 0.10, 0.30, { hint: 'Severe ≥ 0.30' }),
        sign('flail', 'Flail leaflet or wide coaptation defect', 3),
        sign('holo', 'Prominent holodiastolic flow reversal in the descending aorta', 3),
        sign('lvdil', 'LV dilated without another cause', 3, 'Supportive; not in acute AR'),
        sign('faint', 'Faint or incomplete CW jet, slow deceleration', 1),
      ];
      case 'mr': return [
        num('vc', 'Vena contracta width', 'cm', 0.3, 0.7, { specific: true, hint: 'Mild < 0.3 · severe ≥ 0.7 (> 0.8 biplane)' }),
        num('eroa', 'EROA by 2D PISA', 'cm²', 0.20, 0.40, { hint: 'Grades I–IV: < 0.20 · 0.20–0.29 · 0.30–0.39 · ≥ 0.40' }),
        num('rvol', 'Regurgitant volume', 'mL', 30, 60, { hint: '< 30 · 30–44 · 45–59 · ≥ 60' }),
        num('rf', 'Regurgitant fraction', '%', 30, 50, { hint: '< 30 · 30–39 · 40–49 · ≥ 50' }),
        num('pisa', 'PISA radius at Nyquist 30–40 cm/s', 'cm', 0.31, 1.0, { specific: true, hint: '≤ 0.3 specific for mild; ≥ 1.0 specific for severe' }),
        sign('flail', 'Flail leaflet', 3),
        sign('bigjet', 'Central jet larger than 50% of the LA', 3),
        sign('pvrev', 'Pulmonary vein systolic flow reversal', 3),
        sign('lvbig', 'Enlarged LV with normal function', 3),
        sign('smalljet', 'Small, narrow central jet', 1),
        sign('awave', 'A-wave dominant mitral inflow', 1),
        sign('softcw', 'Soft or incomplete CW jet', 1),
        sign('normal', 'Normal LV and LA size', 1),
        sign('secondary', 'Secondary (functional) MR', 2, 'Crescentic orifice: PISA underestimates; a grade III EROA may be severe'),
        sign('nonholo', 'Non-holosystolic (mid-to-late) MR', 2, 'Single-frame EROA and vena contracta overestimate; trust the regurgitant volume'),
      ];
      case 'ms': return [
        inv('mva', 'Mitral valve area', 'cm²', 2.51, 1.51, { specific: true, hint: 'Mild > 2.5 · moderate 1.6–2.5 · severe ≤ 1.5 (planimetry preferred)' }),
        num('pht', 'Pressure half-time', 'ms', 100, 150, { hint: 'Mild < 100 · moderate 100–149 · severe ≥ 150' }),
        num('mg', 'Mean gradient at 60–80 bpm', 'mmHg', 5, 10, { hint: 'Supportive; flow and rate dependent' }),
        num('pasp', 'Systolic PA pressure', 'mmHg', 30, 50, { hint: 'Supportive; severe ≥ 50' }),
      ];
      case 'tr': return [
        num('vc', 'Vena contracta width', 'cm', 0.3, 0.7, { specific: true, hint: 'Mild < 0.3 · moderate 0.3–0.69 · severe ≥ 0.7' }),
        num('eroa', 'EROA', 'cm²', 0.20, 0.40, { hint: 'Severe ≥ 0.40' }),
        num('rvol', 'Regurgitant volume by 2D PISA', 'mL', 30, 45, { hint: 'Severe ≥ 45' }),
        num('pisa', 'PISA radius at Nyquist 28 cm/s', 'cm', 0.51, 0.91, { hint: '≤ 0.5 · 0.6–0.9 · > 0.9' }),
        severeOnly('jet', 'Color jet area', 'cm²', 10, '> 10 cm² supports severe; the tables do not grade smaller areas'),
        num('ivc', 'IVC diameter', 'cm', 2.05, 2.55, { hint: 'Normal < 2 · 2.1–2.5 · > 2.5' }),
        sign('flail', 'Flail leaflet, severe retraction or large perforation', 3),
        sign('hvrev', 'Hepatic vein systolic flow reversal', 3),
        sign('ewave', 'Tricuspid E-wave above 1.0 m/s', 3, 'Supportive, nonspecific'),
        sign('dilated', 'RV and RA dilated', 3, 'Supportive; can be normal in acute TR'),
      ];
    }
    return [];
  };
  /** Grade 1–3 of a numeric value, or null for context parameters and severe-only values under threshold. */
  R.valveGrade = function (p, v) {
    switch (p.kind) {
      case 'higher': return v >= p.severe ? 3 : (v < p.mild ? 1 : 2);
      case 'lower': return v < p.severe ? 3 : (v >= p.mild ? 1 : 2);
      case 'severeFrom': return v >= p.severe ? 3 : null;
      default: return null;
    }
  };
  const vfmt = (v, unit) => (R.fmt(v) + (unit ? ' ' + unit : ''));
  const reading = (overall, headline, explanation, lines, cautions) => ({ overall, headline, explanation, lines, cautions });
  const isEmptyInput = (i) => Object.keys(i.numbers).length === 0 && i.signs.size === 0;

  function readAS(i) {
    const lines = [], cautions = [];
    for (const p of R.valveParams('as')) {
      const v = i.numbers[p.id]; if (v === undefined) continue;
      if (p.kind === 'context') lines.push({ id: p.id, label: p.label, text: vfmt(v, p.unit), grade: null });
      else { const g = R.valveGrade(p, v); if (g) lines.push({ id: p.id, label: p.label, text: vfmt(v, p.unit) + ' · ' + GRADE[g].toLowerCase(), grade: g }); }
    }
    const n = i.numbers, vmax = n.vmax, mg = n.mg, ava = n.ava, avai = n.avai, svi = n.svi, lvef = n.lvef;
    const has = (x) => x !== undefined;
    if (!has(vmax) && !has(mg) && !has(ava) && !has(avai))
      return reading(null, 'Enter the measurements', 'Peak velocity and mean gradient first; the valve area, flow and LVEF decide the low-gradient cases.', lines, []);
    const highGradient = (vmax || 0) >= 4.0 || (mg || 0) >= 40;
    const smallArea = (has(ava) && ava < 1.0) || (has(avai) && avai < 0.6);
    if (has(svi) && svi > 58) cautions.push('High flow (SVi > 58 mL/m²) inflates gradients: reassess the area.');
    if (highGradient) {
      if (has(ava) && ava >= 1.0) cautions.push('High gradient with an area of 1.0 cm² or more: check for high flow, measurement error or pressure recovery (ascending aorta under 30 mm).');
      if (has(vmax) && vmax > 5.5) cautions.push('Peak velocity above 5.5 m/s is a prognostic marker in asymptomatic patients.');
      return reading(3, 'Severe, high-gradient AS', 'Peak velocity ≥ 4 m/s or mean gradient ≥ 40 mmHg defines high-gradient AS (Step 1).', lines, cautions);
    }
    if (smallArea) {
      if (has(svi)) {
        if (svi >= 35) return reading(2, 'Normal-flow, low-gradient: severe AS unlikely', 'With a normal stroke volume index (≥ 35 mL/m²) a calculated area under 1.0 cm² does not make severe AS; look for an LVOT under-measurement before calling it more than moderate.', lines, cautions);
        if (has(lvef)) {
          if (lvef < 50) return reading(null, 'Low-flow, low-gradient AS with reduced EF', 'Low-dose dobutamine stress echo: severe if the velocity reaches 4 m/s or the mean gradient 30–40 mmHg while the area stays ≤ 1.0 cm² at any flow; an area rising above 1.0 cm² means not severe (pseudosevere). A stroke volume rise over 20% shows contractile reserve.', lines, cautions);
          return reading(null, 'Paradoxical low-flow, low-gradient AS', 'Confirm the low flow by another technique (3D TEE or CT for the LVOT, CMR) and weigh the likelihood criteria: symptoms without another cause, age over 70, LVH, reduced longitudinal function, mean gradient 30–40 mmHg when normotensive, AVA ≤ 0.8 cm², and the CT calcium score (severe likely at ≥ 2,000 AU in men, ≥ 1,200 in women).', lines, cautions);
        }
        return reading(null, 'Low-flow, low-gradient AS', 'Enter the LVEF: below 50% the next step is dobutamine stress echo; 50% or more is the paradoxical pattern that needs flow confirmation and the likelihood criteria.', lines, cautions);
      }
      return reading(null, 'Low-gradient with a small area', 'An area under 1.0 cm² suggests but does not confirm severe AS. Enter the stroke volume index: normal flow (≥ 35 mL/m²) makes severe AS unlikely; low flow sends you down the dobutamine or paradoxical pathway depending on LVEF.', lines, cautions);
    }
    const grades = [];
    if (has(vmax)) grades.push(vmax < 3.0 ? 1 : 2);
    if (has(mg)) grades.push(mg < 20 ? 1 : 2);
    if (has(ava)) grades.push(ava > 1.5 ? 1 : 2);
    const overall = grades.length ? Math.max(...grades) : 1;
    if (has(vmax) && vmax <= 2.5) return reading(null, 'Aortic sclerosis', 'Peak velocity ≤ 2.5 m/s: thickening without stenosis.', lines, cautions);
    return reading(overall, GRADE[overall] + ' AS', overall === 2 ? 'Velocity 3.0–4.0 m/s, mean gradient 20–40 mmHg or area 1.0–1.5 cm² (Table 3).' : 'Velocity 2.6–2.9 m/s, mean gradient under 20 mmHg, area over 1.5 cm² (Table 3).', lines, cautions);
  }

  function readMR(i) {
    const lines = [], cautions = [];
    for (const p of R.valveParams('mr')) {
      const v = i.numbers[p.id];
      const g = v !== undefined ? R.valveGrade(p, v) : null;
      if (v !== undefined && g) lines.push({ id: p.id, label: p.label, text: vfmt(v, p.unit) + ' · ' + GRADE[g].toLowerCase(), grade: g });
      else if (i.signs.has(p.id) && p.kind === 'sign') lines.push({ id: p.id, label: p.label, text: p.grade === 2 ? 'noted' : 'specific for ' + GRADE[p.grade].toLowerCase(), grade: p.grade === 2 ? null : p.grade });
    }
    if (isEmptyInput(i)) return reading(null, 'Enter the signs and measurements', 'Four specific signs settle mild or severe; otherwise the quantitative values decide (EROA, regurgitant volume and fraction).', [], []);
    let sev = 0, mild = 0;
    const n = i.numbers;
    if (n.vc !== undefined) { if (n.vc >= 0.7) sev++; else if (n.vc <= 0.3) mild++; }
    if (n.pisa !== undefined) { if (n.pisa >= 1.0) sev++; else if (n.pisa <= 0.3) mild++; }
    for (const s of ['flail', 'bigjet', 'pvrev', 'lvbig']) if (i.signs.has(s)) sev++;
    for (const s of ['smalljet', 'awave', 'softcw', 'normal']) if (i.signs.has(s)) mild++;
    const secondary = i.signs.has('secondary');
    if (i.signs.has('nonholo')) cautions.push('Non-holosystolic MR: single-frame EROA and vena contracta overestimate; the regurgitant volume is the better guide.');
    if (secondary) cautions.push('Secondary MR: 2D PISA underestimates a crescentic orifice; 3D vena contracta area can rescue the grade; E velocity and pulmonary-vein blunting are nonspecific.');
    const qGrade = (v, bands) => v === undefined ? null : bands.filter((b) => v >= b).length + 1;
    const q = [qGrade(n.eroa, [0.20, 0.30, 0.40]), qGrade(n.rvol, [30, 45, 60]), qGrade(n.rf, [30, 40, 50])].filter((x) => x !== null);
    if (q.length && Math.max(...q) - Math.min(...q) >= 2) cautions.push('The quantitative measures disagree with each other: check the PISA radius, the LVOT and mitral annulus measurements, or quantify by another method.');
    if (sev >= 4 && mild === 0) return reading(3, 'Definitely severe MR', 'Four or more specific criteria for severe MR (Figure 18).', lines, cautions);
    if (mild >= 4 && sev === 0) return reading(1, 'Definitely mild MR', 'Four or more specific criteria for mild MR (Figure 18).', lines, cautions);
    if (q.length) {
      const qg = Math.max(...q);
      if ((qg >= 3 && mild >= 2) || (qg <= 2 && sev >= 2)) return reading(null, 'Indeterminate: quantify further', 'The quantitative grade and the specific signs point different ways; consider TEE or CMR for quantitation before committing to a grade.', lines, cautions);
      if (qg === 4) return reading(3, 'Severe MR (grade IV)', 'EROA ≥ 0.40 cm², regurgitant volume ≥ 60 mL or fraction ≥ 50%.', lines, cautions);
      if (qg === 3) {
        if (sev >= 3 || secondary) return reading(3, 'Severe MR (grade III with severe signs)', secondary ? 'Grade III values (EROA 0.30–0.39, volume 45–59 mL, fraction 40–49%) read as severe in secondary MR with an elliptical orifice (Figure 18).' : 'Grade III values with three specific criteria for severe MR read as severe (Figure 18).', lines, cautions);
        return reading(2, 'Moderate MR (grade III)', 'EROA 0.30–0.39 cm², volume 45–59 mL or fraction 40–49%: the upper moderate band; severe only with three specific severe signs or an elliptical orifice.', lines, cautions);
      }
      if (qg === 2) return reading(2, 'Moderate MR (grade II)', 'EROA 0.20–0.29 cm², volume 30–44 mL or fraction 30–39%.', lines, cautions);
      return reading(1, 'Mild MR (grade I)', 'EROA under 0.20 cm², volume under 30 mL, fraction under 30%.', lines, cautions);
    }
    if (sev >= 2 && mild === 0) return reading(3, 'Probably severe: quantify', sev + ' specific signs of severe MR and none of mild; quantitative methods confirm it (Figure 18 asks for them whenever possible).', lines, cautions);
    if (mild >= 2 && sev === 0) return reading(1, 'Probably mild', mild + ' specific signs of mild MR and none of severe.', lines, cautions);
    return reading(2, 'Probably moderate: quantify', 'Intermediate or mixed signs; EROA, regurgitant volume and fraction decide (Figure 18).', lines, cautions);
  }

  function readMS(i) {
    const lines = [];
    for (const p of R.valveParams('ms')) {
      const v = i.numbers[p.id];
      if (v !== undefined) { const g = R.valveGrade(p, v); if (g) lines.push({ id: p.id, label: p.label, text: vfmt(v, p.unit) + ' · ' + GRADE[g].toLowerCase(), grade: g }); }
    }
    if (isEmptyInput(i)) return reading(null, 'Enter the measurements', 'Valve area (planimetry preferred) and pressure half-time define the grade; gradient and PA pressure support it.', [], []);
    const cautions = ['Gradients depend on flow and heart rate: report the rhythm and rate, and never grade on the gradient alone.', 'Pressure half-time misleads with severe AR, right after balloon commissurotomy and with altered LA or LV compliance.'];
    const mva = i.numbers.mva, pht = i.numbers.pht;
    const anatomicSevere = (mva !== undefined && mva <= 1.5) || (pht !== undefined && pht >= 150);
    if (anatomicSevere) {
      if (mva !== undefined && mva > 1.5) cautions.unshift('Half-time says severe but the planimetered area does not: planimetry is the anatomic method; recheck both.');
      return reading(3, 'Severe mitral stenosis', 'Valve area ≤ 1.5 cm² or pressure half-time ≥ 150 ms (ASE 2023). A mean gradient ≥ 10 mmHg at 60–80 bpm and PA systolic pressure ≥ 50 mmHg support it.', lines, cautions);
    }
    const primary = [mva !== undefined ? (mva > 2.5 ? 1 : 2) : null, pht !== undefined ? (pht < 100 ? 1 : 2) : null].filter((x) => x !== null);
    const mg = i.numbers.mg, pasp = i.numbers.pasp;
    const supportive = [mg !== undefined ? (mg < 5 ? 1 : (mg < 10 ? 2 : 3)) : null, pasp !== undefined ? (pasp < 30 ? 1 : (pasp < 50 ? 2 : 3)) : null].filter((x) => x !== null);
    if (primary.length) {
      const g = Math.max(...primary);
      if (supportive.includes(3)) cautions.unshift('Gradient or PA pressure in the severe range with a non-severe area: look for high flow, tachycardia or another cause of pulmonary hypertension.');
      return reading(g, GRADE[g] + ' (progressive) mitral stenosis', g === 1 ? 'Area over 2.5 cm², half-time under 100 ms.' : 'Area 1.6–2.5 cm² or half-time 100–149 ms.', lines, cautions);
    }
    const g = supportive.length ? Math.max(...supportive) : 1;
    return reading(null, 'Supportive signs only (' + GRADE[g].toLowerCase() + ' range)', 'Mean gradient and PA pressure are supportive signs; the grade needs the valve area or the pressure half-time.', lines, cautions);
  }

  function readRegurg(lesion, i) {
    const short = lesion === 'ar' ? 'AR' : 'TR';
    const lines = [], quantitative = [], semi = [];
    let specSevere = 0, specMild = 0, suppSevere = 0;
    for (const p of R.valveParams(lesion)) {
      const v = i.numbers[p.id];
      if (v !== undefined) {
        const g = R.valveGrade(p, v);
        if (!g) { lines.push({ id: p.id, label: p.label, text: vfmt(v, p.unit) + ' · not graded', grade: null }); continue; }
        lines.push({ id: p.id, label: p.label, text: vfmt(v, p.unit) + ' · ' + GRADE[g].toLowerCase(), grade: g });
        if (['rvol', 'rf', 'eroa'].includes(p.id)) quantitative.push(g); else semi.push(g);
        if (p.specific) { if (g === 3) specSevere++; else if (g === 1) specMild++; }
      } else if (i.signs.has(p.id) && p.kind === 'sign') {
        const supportive = (p.hint || '').startsWith('Supportive');
        lines.push({ id: p.id, label: p.label, text: supportive ? 'supportive' : 'specific for ' + GRADE[p.grade].toLowerCase(), grade: p.grade });
        if (supportive) suppSevere++;
        else if (p.grade === 3) specSevere++; else if (p.grade === 1) specMild++;
      }
    }
    if (isEmptyInput(i)) return reading(null, 'Enter the signs and measurements', 'Specific signs settle the grade; the quantitative values decide the middle.', [], []);
    const cautions = [];
    if (lesion === 'ar') cautions.push('Pressure half-time shortens with high LV diastolic pressure and lengthens in chronic adaptation; quantitative volumes anchor eccentric jets.');
    if (lesion === 'tr') cautions.push('Hepatic-vein and inflow signs are nonspecific (RV diastolic function, AF, RA pressure); color jet area underestimates eccentric jets.');
    if (quantitative.length) { const hi = Math.max(...quantitative), lo = Math.min(...quantitative); if (hi > lo && hi - lo >= 2) cautions.push('The quantitative measures disagree: check the stroke volume measurements.'); }
    const q = quantitative.length ? Math.max(...quantitative) : null;
    if (specSevere >= 2 && specMild === 0 && (q === null || q === 3))
      return reading(3, 'Severe ' + short, specSevere + ' specific signs of severe regurgitation' + (q === 3 ? ' and severe quantitative values' : '') + '.', lines, cautions);
    if (q !== null) {
      if ((q === 3 && specMild >= 1) || (q === 1 && specSevere >= 1)) return reading(null, 'Indeterminate: signs and numbers disagree', 'Re-measure, or quantify by another method (volumetric Doppler, 3D, CMR) before grading.', lines, cautions);
      return reading(q, GRADE[q] + ' ' + short, q === 2 ? 'Quantitative values in the moderate band; the sub-bands separate upper from lower moderate.' : 'Quantitative values in the ' + GRADE[q].toLowerCase() + ' band' + (specSevere + specMild > 0 ? ', with concordant specific signs.' : '.'), lines, cautions);
    }
    if (specSevere >= 1 && specMild === 0) return reading(3, 'Probably severe ' + short + ': quantify', 'A specific sign of severe regurgitation; quantitative methods confirm it.', lines, cautions);
    if (specMild >= 1 && specSevere === 0 && suppSevere === 0) return reading(1, 'Mild ' + short, 'Specific signs of mild regurgitation without any of severe.', lines, cautions);
    const s = semi.length ? Math.max(...semi) : (suppSevere > 0 ? 2 : 1);
    return reading(s, GRADE[s] + ' ' + short + ', probably: quantify', 'Semiquantitative or supportive signs only; EROA, regurgitant volume and fraction decide.', lines, cautions);
  }

  /** input = { numbers: { id: value }, signs: Set } */
  R.valveRead = function (lesion, input) {
    switch (lesion) {
      case 'as': return readAS(input);
      case 'mr': return readMR(input);
      case 'ms': return readMS(input);
      default: return readRegurg(lesion, input);
    }
  };

  // ---------- Valve intervention, 2020 ACC/AHA (ValveIntervention.swift) ----------
  R.viLesions = [
    { id: 'as', name: 'Aortic stenosis', short: 'AS', severity: 'Severe: Vmax ≥ 4 m/s or mean gradient ≥ 40 mmHg (AVA usually ≤ 1.0 cm²); very severe: Vmax ≥ 5 m/s or mean gradient ≥ 60 mmHg. Low-flow, low-gradient: AVA ≤ 1.0 cm² with Vmax < 4 m/s, confirmed severe by dobutamine stress or calcium scoring.' },
    { id: 'ar', name: 'Aortic regurgitation', short: 'AR', severity: 'Severe: vena contracta > 0.6 cm, regurgitant volume ≥ 60 mL, fraction ≥ 50%, EROA ≥ 0.3 cm², holodiastolic flow reversal.' },
    { id: 'mrPrimary', name: 'Primary mitral regurgitation', short: 'Primary MR', severity: 'Severe: vena contracta ≥ 0.7 cm, regurgitant volume ≥ 60 mL, fraction ≥ 50%, EROA ≥ 0.40 cm²; stages C1 (compensated) and C2 (LVEF ≤ 60% or LVESD ≥ 40 mm) are asymptomatic, D symptomatic.' },
    { id: 'mrSecondary', name: 'Secondary mitral regurgitation', short: 'Secondary MR', severity: 'Severe: EROA ≥ 0.40 cm², regurgitant volume ≥ 60 mL, fraction ≥ 50%; 2D PISA underestimates crescentic orifices and the volume runs lower in low-flow states.' },
    { id: 'ms', name: 'Mitral stenosis', short: 'MS', severity: 'Severe rheumatic MS: planimetered MVA ≤ 1.5 cm² with pressure half-time ≥ 150 ms; the mean gradient is not a severity criterion.' },
    { id: 'tr', name: 'Tricuspid regurgitation', short: 'TR', severity: 'Severe: vena contracta ≥ 0.7 cm, EROA ≥ 0.40 cm², hepatic vein systolic flow reversal; progressive (stage B): moderate TR.' },
  ];
  const Q = (id, label, options, hint) => ({ id, label, options, hint: hint || null });
  const YN = (id, label, hint) => Q(id, label, ['Yes', 'No'], hint);
  const AGE = Q('age', 'Age', ['< 50', '50–64', '65–80', '> 80']);
  const ANTICOAG = YN('anticoag', 'Long-term anticoagulation possible and acceptable', 'Indications for and risks of a vitamin K antagonist, and the patient’s preference');
  R.viQuestions = function (lesion) {
    switch (lesion) {
      case 'as': return [
        Q('sev', 'Severity on echo', ['Moderate', 'Severe', 'Very severe', 'Low-flow, low-gradient'], 'Moderate Vmax 3–3.9 m/s · severe ≥ 4 · very severe ≥ 5 · low-flow, low-gradient: AVA ≤ 1.0 cm² with Vmax < 4'),
        YN('sx', 'Symptoms attributable to the stenosis', 'Exertional dyspnea, heart failure, angina, syncope or presyncope; an exercise test settles doubtful cases, but should not be performed in symptomatic severe AS (class 3: Harm, B-NR)'),
        Q('ef', 'LVEF', ['≥ 60%', '50–59%', '< 50%']),
        YN('surg', 'Other cardiac surgery planned'),
        Q('risk', 'Surgical risk', ['Low', 'Intermediate', 'High or prohibitive'], 'Low: STS < 3%, no frailty, no major organ compromise; high: STS > 8%, ≥ 2 frailty indices or 1–2 uncorrectable organ systems'),
        AGE,
        YN('markers', 'Abnormal exercise test, BNP > 3× normal, or Vmax rising ≥ 0.3 m/s a year', 'Reduced exercise tolerance or a systolic pressure fall ≥ 10 mmHg on exercise testing'),
        YN('effall', 'LVEF fallen below 60% on three or more serial studies'),
        YN('tf', 'Transfemoral anatomy suitable for TAVI'),
        YN('bicuspid', 'Bicuspid valve'),
        YN('aorta', 'Aortic sinuses or ascending aorta ≥ 4.5 cm'),
        YN('cad', 'Complex coronary disease: bifurcation left main and/or multivessel, SYNTAX score > 33', 'Significant stenosis: luminal reduction > 70%, FFR < 0.8 or iFR < 0.89'),
        YN('survival', 'Expected survival after intervention over 12 months with acceptable quality of life'),
        YN('critical', 'Critically ill'),
        ANTICOAG,
      ];
      case 'ar': return [
        Q('sev', 'Severity on echo', ['Moderate', 'Severe']),
        YN('sx', 'Symptoms'),
        Q('ef', 'LVEF', ['> 60%', '56–60%', '≤ 55%']),
        YN('lvesd', 'LVESD > 50 mm, or indexed LVESD > 25 mm/m²'),
        YN('lvedd', 'LVEDD > 65 mm'),
        YN('surg', 'Other cardiac or aortic surgery planned'),
        Q('risk', 'Surgical risk', ['Low', 'Not low']),
        YN('effall', 'LVEF drifting into 55–60% on three or more serial studies'),
        YN('bicuspid', 'Bicuspid valve'),
        YN('aorta', 'Aortic sinuses or ascending aorta ≥ 4.5 cm'),
        YN('candidate', 'Surgical candidate'),
        AGE,
        ANTICOAG,
      ];
      case 'mrPrimary': return [
        Q('sev', 'Severity on echo', ['Moderate', 'Severe']),
        YN('sx', 'Symptoms'),
        Q('nyha', 'NYHA class', ['I–II', 'III–IV']),
        Q('ef', 'LVEF', ['> 60%', '≤ 60%']),
        YN('lvesd', 'LVESD ≥ 40 mm'),
        YN('serial', 'LV enlarging or LVEF falling on three or more serial studies'),
        YN('durable', 'Durable repair without residual MR more than 95% likely, with mortality under 1%', 'At a Primary or Comprehensive Valve Center'),
        Q('risk', 'Surgical risk', ['Low or intermediate', 'High or prohibitive']),
        YN('anatomy', 'Anatomy favorable for edge-to-edge repair, life expectancy at least a year'),
        YN('posterior', 'Pathology limited to less than half of the posterior leaflet'),
        YN('rheumatic', 'Rheumatic valve'),
        YN('replace', 'Repair not possible: mitral valve replacement needed'),
        AGE,
        ANTICOAG,
      ];
      case 'mrSecondary': return [
        Q('sev', 'Severity on echo', ['Moderate', 'Severe']),
        YN('hf', 'Heart failure with reduced LVEF'),
        YN('gdmt', 'On optimal guideline-directed medical therapy, with biventricular pacing if indicated', 'ACE inhibitor, ARB or sacubitril-valsartan; beta-blocker; aldosterone antagonist; led by a heart-failure cardiologist'),
        Q('nyha', 'NYHA class despite that therapy', ['I', 'II', 'III–IV']),
        Q('ef', 'LVEF', ['≥ 50%', '20–49%', '< 20%']),
        YN('lvesd70', 'LVESD ≤ 70 mm'),
        YN('pasp70', 'PA systolic pressure ≤ 70 mmHg'),
        YN('anatomy', 'Anatomy suitable for edge-to-edge repair on TEE'),
        YN('cabg', 'Coronary bypass surgery planned'),
        YN('cad', 'Coronary artery disease'),
        YN('af', 'Atrial fibrillation with annular dilation (atrial MR)'),
      ];
      case 'ms': return [
        Q('sev', 'Severity', ['Severe (MVA ≤ 1.5 cm²)', 'Not severe (MVA > 1.5 cm²)']),
        Q('nyha', 'NYHA class', ['I', 'II', 'III–IV']),
        YN('morph', 'Valve morphology favorable for PMBC', 'Percutaneous mitral balloon commissurotomy'),
        YN('mr', 'Less than moderate (2+) MR'),
        YN('thrombus', 'Left atrial thrombus on TEE', 'TEE should be performed in patients considered for PMBC, to assess left atrial thrombus and the severity of MR (class 1, C-LD)'),
        YN('calcific', 'Calcific stenosis from annular calcification (non-rheumatic)'),
        YN('pasp', 'PA systolic pressure > 50 mmHg'),
        Q('af', 'Atrial fibrillation', ['No', 'New onset', 'Longer standing']),
        YN('embolic', 'Prior embolic event'),
        YN('exercise', 'Exercise wedge pressure > 25 mmHg or mean gradient > 15 mmHg'),
        YN('surg', 'Other cardiac surgery planned, failed PMBC, or no access to PMBC'),
        YN('candidate', 'Surgical candidate at acceptable risk'),
      ];
      case 'tr': return [
        Q('sev', 'Severity on echo', ['Progressive (moderate)', 'Severe']),
        Q('cause', 'Mechanism', ['Primary (leaflet)', 'Secondary (annular dilation)']),
        YN('left', 'Left-sided valve surgery planned'),
        YN('annulus', 'Annular dilation (end-diastolic diameter > 4.0 cm) or prior right-sided heart failure'),
        YN('rhf', 'Right-sided heart failure'),
        YN('ph', 'Pulmonary hypertension or left-sided disease'),
        YN('medical', 'Poorly responsive to medical therapy'),
        YN('rv', 'Progressive RV dilation or dysfunction'),
        YN('prior', 'Previous left-sided valve surgery'),
        YN('severeph', 'Severe pulmonary hypertension or RV dysfunction'),
      ];
    }
    return [];
  };
  const C = (question, ...values) => ({ question, any: values });
  const yes = (q) => C(q, 'Yes'), no = (q) => C(q, 'No');
  const rule = (id, situation, recommendation, cls, level, when, extra) => Object.assign({ id, group: 'Intervention', situation, recommendation, cls, level, when, note: null }, extra || {});
  // Class of recommendation as the guideline prints it; class 3 comes in two kinds, with Table 2's phrases (e37).
  const CLASS_WORD = { '1': 'Recommended', '2a': 'Reasonable', '2b': 'May be considered', '3: No Benefit': 'Not recommended', '3: Harm': 'Potentially harmful' };
  const CLASS_ORDER = { '1': 0, '2a': 1, '2b': 2, '3: No Benefit': 3, '3: Harm': 4 };
  const GROUPS = ['Intervention', 'Which procedure', 'Prosthesis'];
  R.viClassWord = (c) => CLASS_WORD[c];
  /** Class 3, either kind: a recommendation against. */
  R.viAgainst = (c) => c === '3: No Benefit' || c === '3: Harm';
  /** The class number alone (1, 2a, 2b or 3), for the narrow class column. */
  R.viClassNumber = (c) => (R.viAgainst(c) ? '3' : c);
  /** The level of evidence as a recommendation row shows it; a class-3 row names its kind first ("3: Harm, B-NR"). */
  R.viEvidence = (r) => (R.viAgainst(r.cls) ? r.cls + ', ' + r.level : r.level);
  R.viGroups = GROUPS;
  function prosthesisRules(position, also) {
    also = also || [];
    const P = { group: 'Prosthesis' };
    const r = [rule('pr-bio-any', 'Anticoagulation impossible or unwanted', 'Bioprosthesis at any age', '1', 'C-EO', [[no('anticoag')].concat(also)], P)];
    if (position === 'Aortic') {
      r.push(
        rule('pr-ao-young', 'Aortic valve, age under 50, anticoagulation acceptable', 'Mechanical prosthesis is reasonable', '2a', 'B-NR', [[C('age', '< 50'), yes('anticoag')].concat(also)], P),
        rule('pr-ao-ross', 'Aortic valve, age under 50, a bioprosthesis preferred', 'The Ross procedure (pulmonary autograft) may be considered at a Comprehensive Valve Center if the anatomy is appropriate', '2b', 'B-NR', [[C('age', '< 50'), no('anticoag')].concat(also)], P),
        rule('pr-ao-mid', 'Aortic valve, age 50–65', 'Either prosthesis, individualized', '2a', 'B-NR', [[C('age', '50–64'), yes('anticoag')].concat(also)], P),
        rule('pr-ao-old', 'Aortic valve, age over 65', 'Bioprosthesis is reasonable', '2a', 'B-NR', [[C('age', '65–80', '> 80')].concat(also)], Object.assign({ note: 'At age 65 the 50–65 band applies: without a contraindication to anticoagulation, the choice is individualized.' }, P)));
    } else {
      r.push(
        rule('pr-mi-young', 'Mitral valve, age under 65, anticoagulation acceptable, repair not possible', 'Mechanical prosthesis is reasonable', '2a', 'B-NR', [[C('age', '< 50', '50–64'), yes('anticoag')].concat(also)], P),
        rule('pr-mi-old', 'Mitral valve, age 65 or over, repair not possible', 'Bioprosthesis is reasonable', '2a', 'B-NR', [[C('age', '65–80', '> 80')].concat(also)], P));
    }
    return r;
  }
  R.viRules = function (lesion) {
    const severe = C('sev', 'Severe', 'Very severe');
    const operable = C('risk', 'Low', 'Intermediate');
    const anySevere = C('sev', 'Severe', 'Very severe', 'Low-flow, low-gradient');   // AS: severe of any kind (D1–D3)
    const severeMS = C('sev', 'Severe (MVA ≤ 1.5 cm²)');
    const PROC = { group: 'Which procedure' };
    switch (lesion) {
      case 'as': return [
        rule('as-d1', 'Symptomatic severe high-gradient AS (stage D1)', 'Aortic valve replacement', '1', 'A', [[yes('sx'), severe]]),
        rule('as-c2', 'Asymptomatic severe AS with LVEF < 50% (C2)', 'Aortic valve replacement', '1', 'B-NR', [[no('sx'), severe, C('ef', '< 50%')]]),
        rule('as-surg', 'Asymptomatic severe AS having other cardiac surgery (C1)', 'Aortic valve replacement', '1', 'B-NR', [[no('sx'), severe, yes('surg')]]),
        rule('as-d2', 'Symptomatic low-flow, low-gradient AS with LVEF < 50% (D2)', 'Aortic valve replacement', '1', 'B-NR', [[yes('sx'), C('sev', 'Low-flow, low-gradient'), C('ef', '< 50%')]], { note: 'D2 means true severe stenosis on low-dose dobutamine stress echo: Vmax ≥ 4 m/s or mean gradient ≥ 40 mmHg with AVA ≤ 1.0 cm² at any flow.' }),
        rule('as-d3', 'Symptomatic low-flow, low-gradient AS with LVEF ≥ 50% (D3)', 'Aortic valve replacement when the stenosis is the most likely cause of the symptoms', '1', 'B-NR', [[yes('sx'), C('sev', 'Low-flow, low-gradient'), C('ef', '≥ 60%', '50–59%')]], { note: 'Paradoxical low-flow AS: confirm the small stroke volume by another technique and the severity by calcium scoring before attributing the symptoms to the valve.' }),
        rule('as-2a', 'Asymptomatic severe AS, low surgical risk, with an abnormal exercise test, BNP > 3× normal or rapid progression (C1)', 'Aortic valve replacement is reasonable', '2a', 'B-NR', [[no('sx'), severe, C('risk', 'Low'), yes('markers')]]),
        rule('as-vs', 'Asymptomatic very severe AS (Vmax ≥ 5 m/s), low surgical risk', 'Aortic valve replacement is reasonable', '2a', 'B-R', [[no('sx'), C('sev', 'Very severe'), C('risk', 'Low')]]),
        rule('as-2b', 'Asymptomatic severe AS with LVEF fallen below 60% on three or more serial studies', 'Aortic valve replacement may be considered', '2b', 'B-NR', [[no('sx'), severe, yes('effall')]]),
        rule('as-mod', 'Moderate AS having other cardiac surgery (B)', 'Aortic valve replacement may be considered', '2b', 'C-EO', [[C('sev', 'Moderate'), yes('surg')]]),
        rule('as-savr-age', 'Age under 65, or life expectancy over 20 years', 'Surgical AVR', '1', 'A', [[C('age', '< 50', '50–64'), operable]], PROC),
        rule('as-either', 'Symptomatic severe AS, age 65–80, with no anatomic contraindication to transfemoral TAVI', 'Surgical AVR or transfemoral TAVI after shared decision-making (longevity against valve durability)', '1', 'A', [[yes('sx'), anySevere, no('surg'), C('age', '65–80'), yes('tf'), operable]], PROC),
        rule('as-c2-either', 'Asymptomatic severe AS with LVEF < 50%, age 65–80, no anatomic contraindication to transfemoral TAVI: the same choice as when symptomatic', 'Surgical AVR or transfemoral TAVI after shared decision-making (longevity against valve durability)', '1', 'B-NR', [[no('sx'), severe, C('ef', '< 50%'), no('surg'), C('age', '65–80'), yes('tf'), operable]], PROC),
        rule('as-tavi-age', 'Symptomatic severe AS, age over 80, or life expectancy under 10 years', 'Transfemoral TAVI in preference to surgery', '1', 'A', [[yes('sx'), anySevere, no('surg'), C('age', '> 80'), yes('tf'), operable]], PROC),
        rule('as-tavi-risk', 'Symptomatic severe AS, high or prohibitive surgical risk, with predicted survival after TAVI over 12 months', 'TAVI', '1', 'A', [[yes('sx'), anySevere, C('risk', 'High or prohibitive'), yes('survival')]], PROC),
        rule('as-pall', 'Predicted survival under 12 months, or minimal expected benefit', 'Palliative care after shared decision-making', '1', 'C-EO', [[no('survival')]], PROC),
        rule('as-savr-anat', 'Anatomy unsuitable for transfemoral TAVI and a bioprosthesis preferred', 'Surgical AVR', '1', 'A', [[no('tf'), operable]], PROC),
        rule('as-savr-2a', 'Asymptomatic AS operated for a 2a indication (exercise test, very severe stenosis, rapid progression, BNP)', 'Surgical AVR in preference to TAVI', '1', 'B-NR', [[no('sx'), yes('markers'), C('risk', 'Low'), C('ef', '≥ 60%', '50–59%'), no('surg')], [no('sx'), C('sev', 'Very severe'), C('risk', 'Low'), C('ef', '≥ 60%', '50–59%'), no('surg')]], PROC),
        rule('as-bav', 'Bicuspid valve with symptomatic severe AS', 'TAVI may be considered as an alternative to surgery at a Comprehensive Valve Center', '2b', 'B-NR', [[yes('bicuspid'), yes('sx')]], Object.assign({ note: 'A bicuspid valve otherwise favors surgery, as do LVOT calcification, a very small or large annulus, aortic dilation, severe primary MR and coronary disease needing bypass.' }, PROC)),
        rule('as-aorta', 'Bicuspid valve with an indication for surgical AVR and aortic sinuses or ascending aorta ≥ 4.5 cm', 'Replacement of the aortic sinuses and/or ascending aorta is reasonable at a Comprehensive Valve Center', '2a', 'B-NR', [[yes('bicuspid'), yes('aorta'), operable]], PROC),
        rule('as-cabg', 'Severe AS with complex coronary disease (bifurcation left main and/or multivessel, SYNTAX score > 33)', 'Surgical AVR and CABG are reasonable and preferred over TAVI and PCI', '2a', 'C-LD', [[anySevere, yes('cad')]], PROC),
        rule('as-bav-crit', 'Critically ill', 'Balloon aortic valvuloplasty may be considered as a bridge to AVR', '2b', 'C-EO', [[yes('critical')]], PROC),
      ].concat(prosthesisRules('Aortic', [operable]));
      case 'ar': return [
        rule('ar-d', 'Symptomatic severe AR (D)', 'Aortic valve surgery, regardless of LV function', '1', 'B-NR', [[C('sev', 'Severe'), yes('sx')]]),
        rule('ar-c2', 'Asymptomatic severe AR with LVEF ≤ 55% (C2)', 'Aortic valve surgery, if there is no other cause of the LV dysfunction', '1', 'B-NR', [[C('sev', 'Severe'), no('sx'), C('ef', '≤ 55%')]]),
        rule('ar-surg', 'Severe AR having other cardiac surgery', 'Aortic valve surgery', '1', 'C-EO', [[C('sev', 'Severe'), yes('surg')]]),
        rule('ar-c2-dim', 'Asymptomatic severe AR with LVEF > 55% and LVESD > 50 mm or indexed > 25 mm/m² (C2)', 'Aortic valve surgery is reasonable', '2a', 'B-NR', [[C('sev', 'Severe'), no('sx'), C('ef', '> 60%', '56–60%'), yes('lvesd')]]),
        rule('ar-mod', 'Moderate AR having other cardiac or aortic surgery (B)', 'Aortic valve surgery is reasonable', '2a', 'C-EO', [[C('sev', 'Moderate'), yes('surg')]]),
        rule('ar-2b', 'Asymptomatic severe AR at low risk, LVEF drifting into 55–60% on serial studies or LVEDD > 65 mm (C1)', 'Aortic valve surgery may be considered', '2b', 'B-NR', [[C('sev', 'Severe'), no('sx'), C('risk', 'Low'), yes('effall')], [C('sev', 'Severe'), no('sx'), C('risk', 'Low'), yes('lvedd')]]),
        rule('ar-bav', 'Bicuspid valve with severe AR', 'Valve repair may be considered in selected patients at a Comprehensive Valve Center', '2b', 'C-LD', [[yes('bicuspid'), C('sev', 'Severe')]], PROC),
        rule('ar-aorta', 'Bicuspid valve with an indication for surgical AVR and aortic sinuses or ascending aorta ≥ 4.5 cm', 'Replacement of the aortic sinuses and/or ascending aorta is reasonable at a Comprehensive Valve Center', '2a', 'B-NR', [[yes('bicuspid'), yes('aorta')]], PROC),
        rule('ar-tavi', 'Isolated severe AR in a surgical candidate', 'TAVI should not be performed', '3: Harm', 'B-NR', [[C('sev', 'Severe'), yes('candidate')]], PROC),
      ].concat(prosthesisRules('Aortic'));
      case 'mrPrimary': return [
        rule('mr-d', 'Symptomatic severe primary MR (D)', 'Mitral intervention, regardless of LV function', '1', 'B-NR', [[C('sev', 'Severe'), yes('sx')]]),
        rule('mr-c2', 'Asymptomatic severe MR with LVEF ≤ 60% or LVESD ≥ 40 mm (C2)', 'Mitral surgery', '1', 'B-NR', [[C('sev', 'Severe'), no('sx'), C('ef', '≤ 60%')], [C('sev', 'Severe'), no('sx'), yes('lvesd')]]),
        rule('mr-c1', 'Asymptomatic severe MR with LVEF > 60% and LVESD < 40 mm (C1), a durable repair likely', 'Mitral repair is reasonable at a Primary or Comprehensive Valve Center', '2a', 'B-NR', [[C('sev', 'Severe'), no('sx'), C('ef', '> 60%'), no('lvesd'), yes('durable')]]),
        rule('mr-c1-serial', 'C1 with the LV enlarging or LVEF falling on serial studies', 'Mitral surgery may be considered', '2b', 'C-LD', [[C('sev', 'Severe'), no('sx'), C('ef', '> 60%'), no('lvesd'), yes('serial')]]),
        rule('mr-teer', 'Symptomatic severe primary MR, NYHA III–IV, high or prohibitive surgical risk, favorable anatomy, life expectancy at least a year', 'Transcatheter edge-to-edge repair is reasonable', '2a', 'B-NR', [[C('sev', 'Severe'), yes('sx'), C('nyha', 'III–IV'), C('risk', 'High or prohibitive'), yes('anatomy')]]),
        rule('mr-repair', 'Surgery for degenerative disease', 'Repair rather than replacement whenever a durable repair is possible', '1', 'B-NR', [[C('sev', 'Severe'), no('rheumatic')]], PROC),
        rule('mr-posterior', 'Pathology limited to less than half of the posterior leaflet', 'Replacement should not be done unless repair was attempted at a valve center and failed', '3: Harm', 'B-NR', [[yes('posterior')]], PROC),
        rule('mr-rheum', 'Symptomatic rheumatic severe primary MR with surgery indicated', 'Repair may be considered at a Comprehensive Valve Center by an experienced team, if a durable and successful repair is likely', '2b', 'B-NR', [[yes('rheumatic'), C('sev', 'Severe'), yes('sx')]], PROC),
      ].concat(prosthesisRules('Mitral', [yes('replace')]));
      case 'mrSecondary': return [
        rule('smr-gdmt', 'Severe secondary MR with heart failure and reduced LVEF', 'Guideline-directed medical therapy first, led by a heart-failure cardiologist: ACE inhibitor, ARB or sacubitril-valsartan, beta-blocker, aldosterone antagonist, biventricular pacing as indicated', '1', 'A', [[C('sev', 'Severe'), yes('hf')]]),
        rule('smr-teer', 'Persistent NYHA II–IV on optimal therapy, LVEF 20–50%, LVESD ≤ 70 mm, PA systolic pressure ≤ 70 mmHg, suitable anatomy', 'Transcatheter edge-to-edge repair is reasonable', '2a', 'B-R', [[C('sev', 'Severe'), yes('gdmt'), C('nyha', 'II', 'III–IV'), C('ef', '20–49%'), yes('lvesd70'), yes('pasp70'), yes('anatomy')]]),
        rule('smr-cabg', 'Severe secondary MR when coronary bypass surgery is undertaken', 'Concomitant mitral surgery is reasonable', '2a', 'B-NR', [[C('sev', 'Severe'), yes('cabg')]]),
        rule('smr-surg', 'LVEF < 50% with NYHA III–IV despite optimal therapy', 'Mitral surgery may be considered', '2b', 'B-NR', [[C('sev', 'Severe'), yes('gdmt'), C('nyha', 'III–IV'), C('ef', '20–49%', '< 20%')]]),
        rule('smr-cad', 'Surgery with coronary disease', 'Chordal-sparing replacement may be preferred over downsized annuloplasty', '2b', 'B-R', [[C('sev', 'Severe'), yes('gdmt'), C('nyha', 'III–IV'), C('ef', '20–49%', '< 20%'), yes('cad')]], PROC),
        rule('smr-atrial', 'Atrial annular dilation with LVEF ≥ 50% and NYHA III–IV despite therapy for heart failure and atrial fibrillation', 'Mitral surgery may be considered', '2b', 'B-NR', [[C('sev', 'Severe'), yes('gdmt'), C('nyha', 'III–IV'), C('ef', '≥ 50%'), yes('af')]]),
      ];
      // PMBC needs favorable morphology, less than 2+ MR and no LA thrombus (morph, mr, thrombus); every PMBC rule
      // requires "thrombus: No", so a thrombus never leads to PMBC.
      case 'ms': return [
        rule('ms-pmbc', 'Symptomatic (NYHA II–IV) severe rheumatic MS with favorable morphology, less than 2+ MR and no LA thrombus', 'Percutaneous mitral balloon commissurotomy at a Comprehensive Valve Center', '1', 'A', [[severeMS, C('nyha', 'II', 'III–IV'), no('calcific'), yes('morph'), yes('mr'), no('thrombus')]]),
        rule('ms-surg', 'NYHA III–IV severe MS not suitable for PMBC, after a failed PMBC, needing other cardiac surgery, or without access to PMBC', 'Mitral surgery (repair, commissurotomy or replacement)', '1', 'B-NR', [
          [severeMS, C('nyha', 'III–IV'), no('morph'), no('calcific'), yes('candidate')],
          [severeMS, C('nyha', 'III–IV'), no('mr'), no('calcific'), yes('candidate')],
          [severeMS, C('nyha', 'III–IV'), yes('thrombus'), no('calcific'), yes('candidate')],
          [severeMS, C('nyha', 'III–IV'), yes('surg'), no('calcific'), yes('candidate')],
        ]),
        rule('ms-pasp', 'Asymptomatic severe MS with PA systolic pressure > 50 mmHg, PMBC-suitable', 'PMBC is reasonable', '2a', 'B-NR', [[severeMS, C('nyha', 'I'), yes('pasp'), yes('morph'), yes('mr'), no('thrombus')]]),
        rule('ms-af', 'Asymptomatic severe MS with new-onset atrial fibrillation, PMBC-suitable', 'PMBC may be considered', '2b', 'C-LD', [[severeMS, C('nyha', 'I'), C('af', 'New onset'), yes('morph'), yes('mr'), no('thrombus')]]),
        rule('ms-ex', 'Symptomatic with MVA > 1.5 cm² but a wedge pressure > 25 mmHg or mean gradient > 15 mmHg on exercise', 'PMBC may be considered', '2b', 'C-LD', [[C('sev', 'Not severe (MVA > 1.5 cm²)'), C('nyha', 'II', 'III–IV'), yes('exercise'), no('thrombus')]]),
        rule('ms-highrisk', 'NYHA III–IV with suboptimal anatomy, not a surgical candidate or at high risk', 'PMBC may be considered', '2b', 'B-NR', [[severeMS, C('nyha', 'III–IV'), no('morph'), yes('mr'), no('thrombus'), no('candidate'), no('calcific')]]),
        rule('ms-mac', 'Calcific (non-rheumatic) severe MS from annular calcification with NYHA III–IV', 'Intervention only after discussion of its high procedural risk', '2b', 'C-LD', [[yes('calcific'), C('nyha', 'III–IV'), severeMS]]),
        // Medical therapy, in the intervention group as for secondary MR; listed last so a procedure leads when both apply.
        rule('ms-vka', 'Rheumatic MS with atrial fibrillation, a prior embolic event or LA thrombus', 'Anticoagulation with a vitamin K antagonist', '1', 'C-LD', [[no('calcific'), yes('thrombus')], [no('calcific'), C('af', 'New onset', 'Longer standing')], [no('calcific'), yes('embolic')]]),
      ];
      case 'tr': return [
        rule('tr-left', 'Severe TR (C, D) at left-sided valve surgery', 'Tricuspid surgery', '1', 'B-NR', [[C('sev', 'Severe'), yes('left')]]),
        rule('tr-prog', 'Progressive TR (B) at left-sided valve surgery with annular dilation or prior right-sided heart failure', 'Tricuspid surgery can be beneficial', '2a', 'B-NR', [[C('sev', 'Progressive (moderate)'), yes('left'), yes('annulus')]]),
        rule('tr-primary', 'Right-sided heart failure with severe primary TR (D)', 'Isolated tricuspid surgery can be beneficial', '2a', 'B-NR', [[C('sev', 'Severe'), C('cause', 'Primary (leaflet)'), yes('rhf'), no('left')]]),
        rule('tr-secondary', 'Right-sided heart failure with severe isolated secondary TR from annular dilation, no pulmonary hypertension or left-sided disease, poorly responsive to medical therapy', 'Isolated tricuspid surgery can be beneficial', '2a', 'B-NR', [[C('sev', 'Severe'), C('cause', 'Secondary (annular dilation)'), yes('rhf'), no('ph'), yes('medical'), no('left')]]),
        rule('tr-rv', 'Asymptomatic severe primary TR with progressive RV dilation or dysfunction', 'Isolated tricuspid surgery may be considered', '2b', 'C-LD', [[C('sev', 'Severe'), C('cause', 'Primary (leaflet)'), no('rhf'), yes('rv')]]),
        rule('tr-redo', 'Severe TR after previous left-sided valve surgery with right-sided heart failure, no severe pulmonary hypertension or RV dysfunction', 'Reoperation may be considered', '2b', 'B-NR', [[C('sev', 'Severe'), yes('prior'), yes('rhf'), no('severeph')]]),
      ];
    }
    return [];
  };
  /** 'match' | { pending: Set } | 'contradicted' */
  R.viState = function (r, answers) {
    const pending = new Set();
    for (const conj of r.when) {
      let contradicted = false; const missing = [];
      for (const c of conj) {
        const a = answers[c.question];
        if (a !== undefined) { if (!c.any.includes(a)) { contradicted = true; break; } }
        else missing.push(c.question);
      }
      if (contradicted) continue;
      if (!missing.length) return 'match';
      missing.forEach((m) => pending.add(m));
    }
    return pending.size ? { pending } : 'contradicted';
  };
  R.viEvaluate = function (lesion, answers) {
    const all = R.viRules(lesion), order = R.viQuestions(lesion).map((q) => q.id);
    const matched = [], needed = new Set();
    const consider = (r) => { const s = R.viState(r, answers); if (s === 'match') matched.push(r); else if (s !== 'contradicted') s.pending.forEach((q) => needed.add(q)); };
    all.filter((r) => r.group === 'Intervention').forEach(consider);
    if (matched.some((r) => !R.viAgainst(r.cls))) all.filter((r) => r.group !== 'Intervention').forEach(consider);
    matched.sort((a, b) => (GROUPS.indexOf(a.group) - GROUPS.indexOf(b.group)) || (CLASS_ORDER[a.cls] - CLASS_ORDER[b.cls]));
    const neededOrdered = order.filter((q) => needed.has(q));
    const fallback = (!matched.length && !neededOrdered.length) ? R.viSurveillance(lesion, answers) : null;
    return { matched, needed: neededOrdered, fallback };
  };
  R.viSurveillance = function (lesion, answers) {
    const sev = answers.sev || '';
    switch (lesion) {
      case 'as':
        if (sev === 'Moderate') return 'No intervention criterion met: stage B. Echo every 1–2 years for moderate AS (Vmax 3–3.9 m/s); treat hypertension; reassess with any symptom.';
        return 'No intervention criterion met: stage C1. Echo every 6–12 months for severe AS; an exercise test is reasonable to confirm the absence of symptoms; any symptom changes the answer.';
      case 'ar':
        if (sev === 'Moderate') return 'No intervention criterion met: stage B. Echo every 1–2 years for moderate AR; treat hypertension.';
        return 'No intervention criterion met: stage C1. Echo every 6–12 months for severe AR with serial LV dimensions and ejection fraction; a fall into 55–60% or LVESD growth moves the decision.';
      case 'mrPrimary':
        if (sev === 'Moderate') return 'No intervention criterion met: stage B. Echo every 1–2 years for moderate MR.';
        return 'No intervention criterion met: stage C1. Echo every 6–12 months for severe MR with LV dimensions, ejection fraction, PA pressure and rhythm; symptoms, LVEF ≤ 60% or LVESD ≥ 40 mm change the answer.';
      case 'mrSecondary':
        return 'No intervention criterion met: optimize heart-failure therapy (and revascularization or resynchronization where indicated) and reassess the regurgitation once the ventricle has responded.';
      case 'ms':
        return 'No intervention criterion met. Echo every 3–5 years for progressive MS (MVA > 1.5 cm²), every 1–2 years for severe (MVA 1.0–1.5 cm²) and yearly for very severe (MVA < 1.0 cm²); rate control and anticoagulation for AF, and an exercise study when symptoms and the resting findings disagree.';
      case 'tr':
        return 'No intervention criterion met. Treat the cause (left-sided disease, pulmonary hypertension, volume overload) with diuretics for right-sided congestion, and operate before severe RV dysfunction or end-organ damage sets in.';
    }
    return '';
  };

  // ---------- ASE chamber quantification (EchoGrading.swift; values in reference.json "echo") ----------
  /** Body surface area, m²: DuBois & DuBois, or Mosteller. Height in cm, weight in kg. */
  R.bsa = function (heightCm, weightKg, formula) {
    if (!(heightCm > 0) || !(weightKg > 0)) return null;
    if (formula === 'mosteller') return Math.sqrt(heightCm * weightKg / 3600);
    return 0.007184 * Math.pow(heightCm, 0.725) * Math.pow(weightKg, 0.425);
  };
  R.echo = {
    /** A reference value as printed (58.4, 0.42), or a computed one to two decimals below 100 and one above. */
    fmt(v) {
      const d = Math.abs(v) < 100 ? 100 : 10;
      return String(rnd(v * d) / d);
    },
    /** The reference values for this sex and patient: the sex-specific set first, then the shared one. An
        age-table row (the aortic sinuses) builds its upper limit from age, sex and BSA (ctx: { age, bsa }). */
    ref(m, sex, ctx) {
      if (m.byAge) {
        const lim = R.echo.ageLimit(m, sex, ctx);
        return lim ? { normal: null, cuts: [lim.value] } : null;
      }
      return (sex === 'female' ? m.female : m.male) || m.all || null;
    },
    /** Goldstein 2015 Tables 1–2: the age band's upper limit at the reference BSA, moved 0.5 mm per 0.1 m². */
    ageLimit(m, sex, ctx) {
      const t = m.byAge && m.byAge[sex === 'female' ? 'female' : 'male'];
      const age = ctx && ctx.age;
      if (!t || !(age > 0)) return null;
      const a = Math.floor(age);
      const row = t.rows.find((r) => a >= r.from && (r.to === undefined || r.to === null || a <= r.to));
      if (!row) return null;
      const bsa = ctx.bsa > 0 ? ctx.bsa : null;
      const value = bsa ? row.uln + (bsa - t.refBsa) * m.byAge.perM2 : row.uln;
      return { value: rnd(value * 1000) / 1000, base: row.uln, row, refBsa: t.refBsa, adjusted: !!bsa };
    },
    /** Whether the cut value itself belongs to the worse grade (per-cut edges, else the row's edge). */
    inclusive(m, i) { return (m.edges ? m.edges[i] : m.edge) === 'inclusive'; },
    /** -1 outside the normal range on the harmless side, 0 normal, 1–3 mildly/moderately/severely abnormal,
        4 abnormal where the guideline gives a single cutoff. null when no value or no reference. */
    grade(m, sex, v, ctx) {
      const r = R.echo.ref(m, sex, ctx);
      if (!r || v === null || v === undefined || !Number.isFinite(v)) return null;
      const cuts = r.cuts || [];
      let n = 0;
      cuts.forEach((c, i) => {
        const inc = R.echo.inclusive(m, i);
        if (m.dir === 'low' ? (inc ? v <= c : v < c) : (inc ? v >= c : v > c)) n++;
      });
      if (n === 0) {
        if (r.normal && m.dir !== 'low' && v < r.normal[0]) return -1;
        if (r.normal && m.dir === 'low' && v > r.normal[1]) return -1;
        return 0;
      }
      return cuts.length >= 3 ? Math.min(n, 3) : 4;
    },
    /** Words for a grade: "Normal", "Mildly dilated", "Above the normal range"… */
    label(m, g) {
      const word = m.word || 'abnormal';
      switch (g) {
        case -1: return m.dir === 'low' ? 'Above the normal range' : 'Below the normal range';
        case 0: return 'Normal';
        case 1: return 'Mildly ' + word;
        case 2: return 'Moderately ' + word;
        case 3: return 'Severely ' + word;
        case 4: return word.charAt(0).toUpperCase() + word.slice(1);
      }
      return '';
    },
    /** The cutoffs in words, each grade by the limit on its better side: "Normal < 4.1", "mild ≤ 4.4",
        "moderate ≤ 4.9", "severe > 4.9"; a single cutoff reads "Normal 42–58.4", "dilated > 58.4". */
    ranges(m, sex, ctx) {
      const r = R.echo.ref(m, sex, ctx);
      if (!r) return [];
      const f = R.echo.fmt, cuts = r.cuts || [], low = m.dir === 'low', inc = (i) => R.echo.inclusive(m, i);
      const better = (i) => (low ? (inc(i) ? '> ' : '≥ ') : (inc(i) ? '< ' : '≤ ')) + f(cuts[i]);
      const worse = (i) => (low ? (inc(i) ? '≤ ' : '< ') : (inc(i) ? '≥ ' : '> ')) + f(cuts[i]);
      const out = [{ grade: 0, text: 'Normal ' + (r.normal ? f(r.normal[0]) + '–' + f(r.normal[1]) : better(0)) }];
      if (cuts.length >= 3) {
        out.push({ grade: 1, text: 'mild ' + better(1) }, { grade: 2, text: 'moderate ' + better(2) }, { grade: 3, text: 'severe ' + worse(2) });
      } else if (cuts.length) out.push({ grade: 4, text: (m.word || 'abnormal') + ' ' + worse(0) });
      return out;
    },
    /** The row's BSA-indexed cutoffs as a row of their own (direction and words from the parent). */
    indexed(m) {
      const x = m.indexed;
      if (!x) return null;
      return { id: m.id + '-indexed', name: m.name, dir: m.dir, word: m.word, unit: x.unit, edge: x.edge, edges: x.edges, male: x.male, female: x.female, all: x.all };
    },
    /** The value to grade: indexed rows take an indexed entry as is, or a raw entry divided by BSA. Rows marked
        abs (strain) read a negative entry as its magnitude. */
    value(m, text, raw, bsa) {
      let v = R.num(text);
      if (v === null && m.abs) {
        const neg = parseFloat(String(text === null || text === undefined ? '' : text).trim().replace(',', '.'));
        if (Number.isFinite(neg) && neg < 0) v = -neg;
      }
      if (v === null) return null;
      if (m.index === 'bsa' && raw) return bsa ? v / bsa : null;
      return v;
    },
    /** Band edges for drawing: [{ from, to, grade }] across a padded span around the reference values. Without a
        published normal range the normal band is drawn as wide as the abnormal ones together. */
    bands(m, sex, ctx) {
      const r = R.echo.ref(m, sex, ctx);
      if (!r) return [];
      const cuts = (r.cuts || []).slice().sort((a, b) => a - b);
      const lo = r.normal ? r.normal[0] : null, hi = r.normal ? r.normal[1] : null;
      const all = cuts.concat(lo !== null ? [lo] : [], hi !== null ? [hi] : []);
      if (!all.length) return [];
      const min = Math.min(...all), max = Math.max(...all), pad = (max - min || Math.abs(max) || 1) * 0.25;
      const ext = r.normal ? pad : Math.max(pad, max - min);
      const start = Math.max(0, min - (m.dir === 'low' ? pad : ext)), end = max + (m.dir === 'low' ? ext : pad);
      const out = [];
      if (m.dir === 'low') {
        // ascending cuts: severe below the first, then moderate, mild, normal up to the top of the normal range
        const g = cuts.length >= 3 ? [3, 2, 1] : cuts.map(() => 4);
        let x = start;
        for (let i = 0; i < cuts.length; i++) { out.push({ from: x, to: cuts[i], grade: g[i] }); x = cuts[i]; }
        const top = hi !== null && hi > x ? hi : end;
        out.push({ from: x, to: top, grade: 0 });
        if (top < end) out.push({ from: top, to: end, grade: -1 });
      } else {
        let x = start;
        if (lo !== null && lo > start) { out.push({ from: start, to: lo, grade: -1 }); x = lo; }
        const g = cuts.length >= 3 ? [0, 1, 2, 3] : [0, 4];
        for (let i = 0; i < cuts.length; i++) { out.push({ from: x, to: cuts[i], grade: g[i] }); x = cuts[i]; }
        out.push({ from: x, to: end, grade: g[cuts.length] !== undefined ? g[cuts.length] : 4 });
      }
      return out.filter((b) => b.to > b.from);
    },
    /** Right-atrial pressure from IVC diameter (cm): with spontaneous breathing, whether it collapses by 50% or
        more with a sniff (ASE 2025); on positive-pressure ventilation only a small IVC says anything. The
        ventilated cutoff is 1.2 cm (ASE 2010): the 2025 text prints 2.1 cm for the same statement. */
    rap(ivcCm, collapses, cut, ventilated, ventCut) {
      const c = cut || 2.1, vc = ventCut || 1.2;
      if (!(ivcCm > 0)) return null;
      if (ventilated) {
        return ivcCm <= vc
          ? { value: null, range: 'below 10', label: 'Likely below 10 mmHg', detail: `An IVC of ${R.echo.fmt(vc)} cm or less in an intubated patient identifies RA pressure below 10 mmHg.` }
          : { value: null, range: null, label: 'Not estimable', detail: 'On positive-pressure ventilation a larger IVC, and its collapse, do not estimate RA pressure.' };
      }
      if (collapses === null || collapses === undefined) return null;
      if (ivcCm <= c && collapses) return { value: 3, range: '0–5', label: 'Normal', detail: null };
      if (ivcCm > c && !collapses) return { value: 15, range: '10–20', label: 'Elevated', detail: null };
      return { value: 8, range: '5–10', label: 'Indeterminate', detail: 'A normal-size IVC that does not collapse, or a dilated one that does: lower to 3 mmHg without secondary signs of raised RA pressure, raise to 15 with them.' };
    },
    /** TAPSE/PASP, mm/mmHg: the noninvasive index of RV–PA coupling (ASE 2025). Healthy adults generally run
        0.5–0.7; 0.3–0.4 is associated with uncoupling and increased mortality. TAPSE in cm, PASP in mmHg; the
        ratio is read at two decimals, as shown. */
    coupling(tapseCm, pasp, c) {
      if (!(tapseCm > 0) || !(pasp > 0)) return null;
      const h = (c && c.healthy) || [0.5, 0.7], u = (c && c.uncoupled) || [0.3, 0.4], f = R.echo.fmt;
      const ratio = Math.round(((tapseCm * 10) / pasp) * 100) / 100;
      const healthy = `${f(h[0])}–${f(h[1])}`, unc = `${f(u[0])}–${f(u[1])}`;
      if (ratio > h[1]) return { ratio, grade: 0, label: 'Above the usual healthy range', detail: `Healthy adults generally run ${healthy} mm/mmHg; a higher ratio does not suggest uncoupling.` };
      if (ratio >= h[0]) return { ratio, grade: 0, label: 'In the healthy range', detail: `Healthy adults generally run ${healthy} mm/mmHg.` };
      if (ratio > u[1]) return { ratio, grade: null, label: 'Below the healthy range', detail: `Between the healthy range (${healthy}) and the range associated with uncoupling (${unc} mm/mmHg).` };
      if (ratio >= u[0]) return { ratio, grade: 4, label: 'In the uncoupling range', detail: `${unc} mm/mmHg is associated with RV–PA uncoupling and increased mortality.` };
      return { ratio, grade: 4, label: 'Below the uncoupling range', detail: `Lower than ${unc} mm/mmHg, the range associated with RV–PA uncoupling and increased mortality.` };
    },
  };

  // ---------- ASE 2025 diastolic function (DiastolicCalc.swift) ----------
  // Nagueh SF, et al. J Am Soc Echocardiogr 2025;38:537–569. Figure 3 (LAP and grade, sinus rhythm,
  // irrespective of LVEF), Figure 2 (is diastolic dysfunction present), Figure 4 (moderate or severe MAC),
  // Section 15B (heart transplant). Inequalities follow Figure 3 where the document is inconsistent.
  const DD = R.diastolicCutoffs = {
    eSeptal: 6, eLateral: 7, eAverage: 6.5,              // reduced e′ when ≤
    eeSeptal: 15, eeLateral: 13, eeAverage: 14,          // increased E/e′ when ≥ (Figure 2 uses average > 14)
    pasp: 35, tr: 2.8,                                   // increased when ≥
    pvsd: 0.67, lars: 18, lavi: 34, ivrt: 70,            // S/D ≤, LARS ≤, LAVi >, IVRT ≤
    lvefReduced: 50,                                     // LVEF below this lets S/D above 0.67 count as normal (the guideline names no number)
    prEdv: 2, padp: 16, lwave: 50, ara: 30, valsalva: 50, // ≥, ≥, ≥, >, ≥ (% fall in E/A)
    ageE: { '20-39': [7, 10, 9], '40-65': [6, 8, 7], '>65': [6, 7, 6.5] }, // Table 6: abnormal when < septal, lateral, average
  };
  const has = (x) => x !== null && x !== undefined && Number.isFinite(x);
  /** The three main variables and the derived ratios. i: { E, A, eSeptal, eLateral, tr, pasp, lungDisease, ageBand }.
      With both e′ sites measured, the average decides e′ and E/e′; a single site's cutoff applies only when that is
      the one site measured (Figure 3 lists septal, lateral and average joined by "or"). */
  R.diastolicPrimaries = function (i) {
    const E = has(i.E) ? i.E : null, A = has(i.A) ? i.A : null;
    const es = has(i.eSeptal) ? i.eSeptal : null, el = has(i.eLateral) ? i.eLateral : null;
    const ea = es !== null && el !== null ? (es + el) / 2 : null;
    const EA = E !== null && A !== null && A > 0 ? E / A : null;
    const ees = E !== null && es ? E / es : null, eel = E !== null && el ? E / el : null, eea = E !== null && ea ? E / ea : null;
    const age = i.ageBand && DD.ageE[i.ageBand];
    const low = (v, cut, k) => v === null ? null : (age ? v < age[k] : v <= cut);
    const eFlags = [low(es, DD.eSeptal, 0), low(el, DD.eLateral, 1), low(ea, DD.eAverage, 2)];
    const both = es !== null && el !== null;
    const v1 = both ? eFlags[2] : (eFlags[0] ?? eFlags[1] ?? null);
    const rFlags = [ees === null ? null : ees >= DD.eeSeptal, eel === null ? null : eel >= DD.eeLateral, eea === null ? null : eea >= DD.eeAverage];
    const v2 = both ? rFlags[2] : (rFlags[0] ?? rFlags[1] ?? null);
    let v3 = null, v3by = null;
    if (!i.lungDisease) {
      if (has(i.pasp)) { v3 = i.pasp >= DD.pasp; v3by = 'pasp'; }
      else if (has(i.tr)) { v3 = i.tr >= DD.tr; v3by = 'tr'; }
    }
    return { E, A, EA, es, el, ea, ees, eel, eea, v1, v2, v3, v3by, eFlags, rFlags, byAverage: both };
  };
  const pick = (val, test) => (has(val) ? test(val) : null);
  /** Whether LVEF is reduced (below 50%), or null when not entered. */
  R.diastolicReducedEF = (i) => (has(i.lvef) ? i.lvef < DD.lvefReduced : null);
  /** The supplemental signs (S/D, LARS, LAVi, IVRT) and the second-line ones, each true (present), false (absent)
      or null (not entered, or not decisive). A pulmonary vein S/D above 0.67 counts as an absent sign only with a
      reduced LVEF: with a normal LVEF the ratio can exceed 0.67 despite raised filling pressure (2025, p. 554). */
  R.diastolicSigns = function (i) {
    const f = (x) => R.fmt(x);
    const rEF = R.diastolicReducedEF(i);
    const sdText = (x) => f(x) + (x > DD.pvsd ? (rEF === true ? ' · counts as normal with LVEF ' + f(i.lvef) + '%' : rEF === false ? ' · not decisive with LVEF ' + f(i.lvef) + '%' : ' · not decisive unless LVEF is below 50%') : '');
    const first = [
      { id: 'pvsd', label: 'Pulmonary vein S/D ≤ 0.67', v: pick(i.pvsd, (x) => (x <= DD.pvsd ? true : (rEF === true ? false : null))), text: has(i.pvsd) ? sdText(i.pvsd) : null, shown: has(i.pvsd) },
      { id: 'lars', label: 'LA reservoir strain ≤ 18%', v: pick(i.lars, (x) => x <= DD.lars), text: has(i.lars) ? f(i.lars) + '%' : null, shown: has(i.lars) },
      { id: 'lavi', label: 'LA volume index > 34 mL/m²', v: pick(i.lavi, (x) => x > DD.lavi), text: has(i.lavi) ? f(i.lavi) + ' mL/m²' : null, shown: has(i.lavi) },
      { id: 'ivrt', label: 'IVRT ≤ 70 ms', v: pick(i.ivrt, (x) => x <= DD.ivrt), text: has(i.ivrt) ? f(i.ivrt) + ' ms' : null, shown: has(i.ivrt) },
    ];
    const second = [
      { id: 'predv', label: 'PR end-diastolic velocity ≥ 2 m/s', v: pick(i.prEdv, (x) => x >= DD.prEdv), text: has(i.prEdv) ? f(i.prEdv) + ' m/s' : null, shown: has(i.prEdv) },
      { id: 'padp', label: 'PA diastolic pressure ≥ 16 mmHg', v: pick(i.padp, (x) => x >= DD.padp), text: has(i.padp) ? f(i.padp) + ' mmHg' : null, shown: has(i.padp) },
      { id: 'lwave', label: 'Mitral L-wave ≥ 50 cm/s', v: pick(i.lwave, (x) => x >= DD.lwave), text: has(i.lwave) ? f(i.lwave) + ' cm/s' : null, shown: has(i.lwave) },
      { id: 'ara', label: 'Ar − A > 30 ms', v: pick(i.ara, (x) => x > DD.ara), text: has(i.ara) ? f(i.ara) + ' ms' : null, shown: has(i.ara) },
      { id: 'valsalva', label: 'E/A falls ≥ 50% with Valsalva', v: pick(i.valsalva, (x) => x >= DD.valsalva), text: has(i.valsalva) ? f(i.valsalva) + '%' : null, shown: has(i.valsalva) },
    ];
    return { first, second };
  };
  /** Figure 3 for one set of main variables (all three known): { lap, grade, why } with lap 'normal' | 'increased' |
      'lvedp' | 'unknown', grade 0–3 or null, and `why` the reason without the E/A sentence. */
  function ddCore(v1, v2, v3, p, sg, v3name) {
    const abn = [v1, v2, v3].filter(Boolean).length;
    const byEA = (why) => ({ lap: 'increased', grade: p.EA === null ? null : (p.EA >= 2 ? 3 : 2), why, ea: true });
    const supp = (why, eOnly) => {
      const pos = sg.first.filter((x) => x.v === true), neg = sg.first.filter((x) => x.v === false);
      if (pos.length) return byEA(why + ' ' + pos.map((x) => x.label).join(', ') + ': increased LAP.');
      if (neg.length) return { lap: 'normal', grade: null, why: why + ' None of the supplemental signs is present, so LAP is likely normal.' + (eOnly ? ' The guideline assigns no grade on this path (Grade 1 needs E/A ≤ 0.8).' : '') };
      const mp = sg.second.filter((x) => x.v === true), mn = sg.second.filter((x) => x.v === false);
      if (mp.length && mp.every((x) => x.id === 'ara')) return { lap: 'lvedp', grade: null, why: why + ' Ar − A above 30 ms reflects LV end-diastolic pressure rather than mean LAP; report it as an isolated LVEDP increase.' };
      if (mp.length) return byEA(why + ' ' + mp.map((x) => x.label).join(', ') + ': increased LAP.');
      if (mn.length) return { lap: 'normal', grade: null, why: why + ' None of the further signs is present, so LAP is likely normal.' };
      return { lap: 'unknown', grade: null, why: why + ' Enter the supplemental parameters: pulmonary vein S/D, LA reservoir strain, LA volume index or IVRT.' };
    };
    if (abn === 0) return { lap: 'normal', grade: 0, why: 'e′, E/e′ and ' + v3name + ' are all normal: normal LAP and normal diastolic function.' };
    if (abn === 3) return byEA('All three main variables are abnormal.');
    if (v1 && !v2 && !v3) {
      if (p.EA !== null && p.EA <= 0.8) return { lap: 'normal', grade: 1, why: 'Only e′ is reduced and E/A is ' + R.fmt(p.EA) + ' (0.8 or less): impaired relaxation with normal LAP.' };
      return supp(p.EA === null ? 'Only e′ is reduced; E/A is not entered.' : 'Only e′ is reduced, with E/A ' + R.fmt(p.EA) + ' above 0.8.', true);
    }
    const which = [v1 ? 'e′' : null, v2 ? 'E/e′' : null, v3 ? v3name : null].filter(Boolean);
    return supp(which.length === 1 ? 'Only ' + which[0] + ' is abnormal.' : which.join(' and ') + ' are abnormal.', false);
  }
  const DD_HEAD = { 0: 'Normal Diastolic Function', 1: 'Grade 1 Diastolic Dysfunction', 2: 'Grade 2 Diastolic Dysfunction', 3: 'Grade 3 Diastolic Dysfunction' };
  /** Figure 3 for sinus rhythm. Returns { lap, grade, headline, explanation, steps[], cautions[], dysfunction } with
      lap 'normal' | 'increased' | 'lvedp' | 'unknown' and grade 0 (normal) | 1 | 2 | 3 | null. With a main variable
      missing (or PASP/TR set aside for lung disease) the tool reads every way the missing one could fall and
      reports only a reading they all share; the guideline does not cover this case. */
  R.diastolic = function (i) {
    const p = R.diastolicPrimaries(i), sg = R.diastolicSigns(i), steps = [], cautions = [];
    const f = (x) => R.fmt(x);
    const show = (flag) => (flag === null ? 'not entered' : (flag ? 'abnormal' : 'normal'));
    const v3name = p.v3by === 'tr' ? 'TR velocity' : 'PASP';
    const eText = [p.es !== null ? 'septal ' + f(p.es) : null, p.el !== null ? 'lateral ' + f(p.el) : null, p.ea !== null ? 'average ' + f(p.ea) : null].filter(Boolean).join(', ');
    const rText = [p.ees !== null ? 'septal ' + f(p.ees) : null, p.eel !== null ? 'lateral ' + f(p.eel) : null, p.eea !== null ? 'average ' + f(p.eea) : null].filter(Boolean).join(', ');
    const byAvg = p.byAverage ? ' by the average' : '';
    steps.push({ id: 'v1', label: 'e′ reduced', state: p.v1, text: p.v1 === null ? 'Enter septal and lateral e′' : eText + ' cm/s · ' + show(p.v1) + byAvg });
    steps.push({ id: 'v2', label: 'E/e′ increased', state: p.v2, text: p.v2 === null ? 'Needs E and e′' : rText + ' · ' + show(p.v2) + (p.v2 === null ? '' : byAvg) });
    steps.push({ id: 'v3', label: p.v3by === 'tr' ? 'TR velocity increased' : 'PASP increased', state: p.v3,
      text: i.lungDisease ? 'Not used: lung or pulmonary vascular disease' : (p.v3 === null ? 'Enter PASP, or TR velocity when RAP cannot be estimated' : (p.v3by === 'pasp' ? 'PASP ' + f(i.pasp) + ' mmHg' : 'TR ' + f(i.tr) + ' m/s') + ' · ' + show(p.v3)) });
    for (const x of sg.first.concat(sg.second)) if (x.shown) steps.push({ id: x.id, label: x.label, state: x.v, text: x.text + (x.v === null ? '' : ' · ' + (x.v ? 'present' : 'absent')) });
    const finish = (r, extra) => {
      let explanation = r.why;
      if (r.ea && p.EA !== null) {
        steps.push({ id: 'ea', label: 'E/A', state: null, text: f(p.EA) + (p.EA >= 2 ? ' · 2 or more' : ' · below 2') });
        explanation += p.EA >= 2 ? ' E/A ' + f(p.EA) + ' is 2 or more: marked increase in LAP.' : ' E/A ' + f(p.EA) + ' is below 2: mild to moderate increase in LAP.';
      } else if (r.ea) explanation += ' Enter E and A: E/A below 2 is Grade 2, 2 or more is Grade 3.';
      const headline = r.lap === 'unknown' ? 'LAP Not Yet Determined' : r.lap === 'lvedp' ? 'Isolated LVEDP Elevation'
        : r.grade !== null ? DD_HEAD[r.grade] : (r.lap === 'increased' ? 'Increased LAP' : 'Normal LAP');
      return { lap: r.lap, grade: r.grade, headline, explanation: (extra ? extra + ' ' : '') + explanation, steps, cautions, primaries: p, dysfunction: R.diastolicPresence(i, p) };
    };
    const prim = [p.v1, p.v2, p.v3];
    if (prim.every((x) => x === null)) return { lap: 'unknown', grade: null, headline: 'Enter the Measurements', explanation: 'Start with septal and lateral e′, mitral E and A, and PASP or TR velocity.', steps, cautions, primaries: p, dysfunction: R.diastolicPresence(i, p) };
    if (prim.every((x) => x !== null)) return finish(ddCore(p.v1, p.v2, p.v3, p, sg, v3name));
    // a main variable missing: read every way it could fall
    const names = ['e′', 'E/e′', 'PASP or TR velocity'];
    const missing = prim.map((x, k) => (x === null ? k : -1)).filter((k) => k >= 0);
    const results = [];
    for (let mask = 0; mask < (1 << missing.length); mask++) {
      const v = prim.slice();
      missing.forEach((k, j) => { v[k] = !!(mask & (1 << j)); });
      results.push(ddCore(v[0], v[1], v[2], p, sg, 'PASP or TR velocity'));
    }
    const miss = missing.map((k) => names[k]).join(' and ');
    if (i.lungDisease && missing.includes(2)) cautions.push('With lung or pulmonary vascular disease, TR velocity and PASP do not stand in for LAP, so the reading has to hold without them.');
    else cautions.push(miss + (missing.length > 1 ? ' are' : ' is') + ' not entered. The guideline does not cover this case, so the tool reports a reading only when every possible value of the missing one would give it.');
    const known = [p.v1 !== null ? 'e′ ' + (p.v1 ? 'reduced' : 'normal') : null, p.v2 !== null ? 'E/e′ ' + (p.v2 ? 'increased' : 'normal') : null, p.v3 !== null ? v3name + ' ' + (p.v3 ? 'increased' : 'normal') : null].filter(Boolean).join(', ');
    const lap = results[0].lap;
    if (lap !== 'unknown' && results.every((r) => r.lap === lap)) {
      const grade = results.every((r) => r.grade === results[0].grade) ? results[0].grade : null;
      const pos = sg.first.filter((x) => x.v === true).map((x) => x.label), neg = sg.first.some((x) => x.v === false);
      const why = 'With ' + known + ', the reading is the same whichever way ' + miss + ' would fall'
        + (pos.length ? ': ' + pos.join(', ') + ' point' + (pos.length === 1 ? 's' : '') + ' to increased LAP.' : neg ? ': none of the supplemental signs entered is present.' : '.');
      return finish({ lap, grade, why, ea: lap === 'increased' });
    }
    const outcomes = [...new Set(results.map((r) => r.lap === 'unknown' ? 'not determined' : r.lap === 'lvedp' ? 'isolated LVEDP elevation' : r.grade !== null ? DD_HEAD[r.grade].toLowerCase() : r.lap + ' LAP'))];
    return finish({ lap: 'unknown', grade: null, why: 'With ' + known + ', the reading depends on ' + miss + ' (' + outcomes.join(' or ') + '). ' + (i.lungDisease && missing.includes(2) ? 'Add the supplemental signs: LA reservoir strain, pulmonary vein S/D, LA volume index or IVRT.' : 'Measure ' + miss + ', or add the supplemental signs.') });
  };
  /** Figure 2: is diastolic dysfunction present? Reduced e′ with 1 marker, or normal e′ with 2. */
  R.diastolicPresence = function (i, p) {
    p = p || R.diastolicPrimaries(i);
    if (p.v1 === null) return { state: null, markers: [], text: 'Needs e′' };
    const markers = [
      { label: 'average E/e′ > 14', v: p.eea === null ? null : p.eea > DD.eeAverage },
      { label: 'LA reservoir strain ≤ 18%', v: pick(i.lars, (x) => x <= DD.lars) },
      { label: 'E/A ≤ 0.8 or ≥ 2', v: p.EA === null ? null : (p.EA <= 0.8 || p.EA >= 2) },
      { label: 'LA volume index > 34 mL/m²', v: pick(i.lavi, (x) => x > DD.lavi) },
    ];
    const n = markers.filter((m) => m.v === true).length;
    const present = (p.v1 && n >= 1) || (!p.v1 && n >= 2);
    const supportive = has(i.lvmi) && i.sex ? (i.sex === 'female' ? i.lvmi > 95 : i.lvmi > 115) : false;
    return { state: present, markers, count: n, supportive,
      text: present ? 'Present: ' + (p.v1 ? 'reduced e′ with ' : 'normal e′ with ') + n + ' marker' + (n === 1 ? '' : 's')
        : 'Criteria not met (' + (p.v1 ? 'reduced e′, no marker' : 'normal e′, ' + n + ' marker' + (n === 1 ? '' : 's')) + ')' };
  };
  /** Figure 4: moderate or severe mitral annular calcification. */
  R.diastolicMAC = function (i) {
    const EA = has(i.E) && has(i.A) && i.A > 0 ? i.E / i.A : null;
    if (EA === null) return { lap: 'unknown', headline: 'Enter E and A', explanation: 'With annular calcification the grade rests on E/A and IVRT; e′ and E/e′ are not used.' };
    if (EA < 0.8) return { lap: 'normal', EA, headline: 'Normal LAP', explanation: 'E/A ' + R.fmt(EA) + ' is below 0.8.' };
    if (EA > 1.8) return { lap: 'increased', EA, headline: 'Increased LAP', explanation: 'E/A ' + R.fmt(EA) + ' is above 1.8.' };
    if (!has(i.ivrt)) return { lap: 'unknown', EA, headline: 'Enter IVRT', explanation: 'E/A ' + R.fmt(EA) + ' sits between 0.8 and 1.8: IVRT decides (80 ms or more normal, under 80 ms increased).' };
    return i.ivrt >= 80 ? { lap: 'normal', EA, headline: 'Normal LAP', explanation: 'E/A ' + R.fmt(EA) + ' with IVRT ' + R.fmt(i.ivrt) + ' ms (80 ms or more).' }
      : { lap: 'increased', EA, headline: 'Increased LAP', explanation: 'E/A ' + R.fmt(EA) + ' with IVRT ' + R.fmt(i.ivrt) + ' ms (under 80 ms).' };
  };
  /** Section 15B: heart transplant recipients. */
  R.diastolicTransplant = function (i) {
    const p = R.diastolicPrimaries(i);
    const ee = p.eea !== null ? p.eea : null;
    if (ee === null) return { lap: 'unknown', headline: 'Enter E and Both e′', explanation: 'The transplant pathway starts from average E/e′.' };
    if (ee < 7) return { lap: 'normal', headline: 'Normal Filling Pressure', explanation: 'Average E/e′ ' + R.fmt(ee) + ' is below 7.' };
    if (ee > 14) return { lap: 'increased', headline: 'Increased Filling Pressure', explanation: 'Average E/e′ ' + R.fmt(ee) + ' is above 14.' };
    if (has(i.esr)) return i.esr <= 200 ? { lap: 'normal', headline: 'Normal Filling Pressure', explanation: 'Average E/e′ ' + R.fmt(ee) + ' (7–14), E/SRIVR ' + R.fmt(i.esr) + ' cm (200 or less).' }
      : { lap: 'increased', headline: 'Increased Filling Pressure', explanation: 'Average E/e′ ' + R.fmt(ee) + ' (7–14), E/SRIVR ' + R.fmt(i.esr) + ' cm (above 200).' };
    if (has(i.tr)) return i.tr <= 2.8 ? { lap: 'normal', headline: 'Normal Filling Pressure', explanation: 'Average E/e′ ' + R.fmt(ee) + ' (7–14), no E/SRIVR, TR ' + R.fmt(i.tr) + ' m/s (2.8 or less).' }
      : { lap: 'increased', headline: 'Increased Filling Pressure', explanation: 'Average E/e′ ' + R.fmt(ee) + ' (7–14), no E/SRIVR, TR ' + R.fmt(i.tr) + ' m/s (above 2.8).' };
    return { lap: 'unknown', headline: 'Enter E/SRIVR or TR', explanation: 'Average E/e′ ' + R.fmt(ee) + ' sits between 7 and 14: E/SRIVR decides (200 cm or less normal), or TR velocity when SRIVR cannot be measured.' };
  };

  // ---------- ACLS code timer (AclsCalc.swift; content in reference.json "acls") ----------
  // A code is a clock started when the tool opens and a log of what was done, stamped in ms since the start.
  // Counts, the last time of each action, the CPR cycle, the drug timers and the prompts are all read back
  // from that log, so removing a mistaken entry corrects everything that depends on it.
  R.acls = {
    /** A new code: the clock starts at `now` (ms since the epoch). */
    session(now, mode, patient) {
      return { startedAt: now, mode: mode || 'arrest', patient: patient === 'child' ? 'child' : 'adult', weight: null, log: [], path: {} };
    },
    /** 75000 → "1:15"; 3725000 → "1:02:05"; negative values keep their sign. */
    clock(ms) {
      const neg = ms < 0, s = Math.floor(Math.abs(ms) / 1000), h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60;
      const body = h ? `${h}:${String(m).padStart(2, '0')}:${String(sec).padStart(2, '0')}` : `${m}:${String(sec).padStart(2, '0')}`;
      return (neg ? '-' : '') + body;
    },
    /** Adds an entry at t (ms since the start) and keeps the log in time order. */
    add(s, t, id, text, extra) {
      const e = Object.assign({ t: Math.max(0, t), id, text }, extra || {});
      s.log.push(e);
      s.log.sort((a, b) => a.t - b.t);
      return e;
    },
    remove(s, e) { const i = s.log.indexOf(e); if (i >= 0) s.log.splice(i, 1); },
    count(s, id) { return s.log.filter((e) => e.id === id).length; },
    last(s, id) {
      for (let i = s.log.length - 1; i >= 0; i--) if (s.log[i].id === id) return s.log[i].t;
      return null;
    },
    /** The rhythm of the last rhythm check ("shockable", "nonshockable", "rosc"), or null. */
    rhythm(s, data) {
      for (let i = s.log.length - 1; i >= 0; i--) {
        const a = data.actions[s.log[i].id];
        if (a && a.rhythm) return a.rhythm;
      }
      return null;
    },
    /** Weight in kg for the child doses, or null. */
    kg(s) { return s.patient === 'child' && s.weight > 0 ? s.weight : null; },
    /** The spec for this patient: the child entry falls back to nothing, so an adult dose is never shown for a child. */
    spec(a, patient) { return a ? (patient === 'child' ? a.child : a.adult) || null : null; },
    /** The dose for the nth administration (0-based): fixed for adults, per kg with a cap for children. */
    dose(a, s, n) {
      let d = R.acls.spec(a, s.patient);
      if (!d) return null;
      if (Array.isArray(d.doses)) d = Object.assign({}, d, d.doses[Math.min(n || 0, d.doses.length - 1)]);
      const kg = R.acls.kg(s), route = d.route ? ' ' + d.route : '';
      if (d.text && d.dose === undefined && d.perKg === undefined) return { text: d.text, amount: null, unit: d.unit || null };
      if (d.perKg !== undefined) {
        const per = `${R.acls.num(d.perKg)} ${d.unit}/kg`;
        if (!kg) return { text: per + route + (d.max ? ` (max ${R.acls.num(d.max)} ${d.unit})` : ''), amount: null, unit: d.unit, perKg: d.perKg, needsWeight: true };
        let amount = d.perKg * kg, capped = false, floored = false;
        if (d.max !== undefined && amount > d.max) { amount = d.max; capped = true; }
        if (d.min !== undefined && amount < d.min) { amount = d.min; floored = true; }
        amount = R.acls.round(amount);
        let text = `${R.acls.num(amount)} ${d.unit}${route}`;
        const vol = d.conc ? R.acls.round(amount / d.conc.value) : null;
        if (vol !== null) text += ` · ${R.acls.num(vol)} mL of ${R.acls.num(d.conc.value)} ${d.conc.unit}`;
        text += capped ? ' (the maximum)' : floored ? ' (the minimum)' : ` (${per})`;
        return { text, amount, unit: d.unit, volume: vol, capped, floored };
      }
      const amount = d.dose;
      let text = `${R.acls.num(amount)} ${d.unit}${route}`;
      if (d.conc) text += ` · ${R.acls.num(R.acls.round(amount / d.conc.value))} mL of ${R.acls.num(d.conc.value)} ${d.conc.unit}`;
      return { text, amount, unit: d.unit };
    },
    /** How many doses the spec allows (Infinity when it sets no limit). */
    maxDoses(a, s) { const d = R.acls.spec(a, s.patient); return d && d.maxDoses ? d.maxDoses : Infinity; },
    /** Shock energy for the nth shock (0-based): the adult text, or J/kg by shock number for a child. */
    energy(a, s, n) {
      const e = R.acls.spec(a, s.patient);
      if (!e) return null;
      if (e.perKgSeq) {
        const seq = e.perKgSeq, later = n >= seq.length, per = later ? e.thenPerKg : seq[n], kg = R.acls.kg(s);
        const upTo = later && e.maxPerKg ? ` (up to ${R.acls.num(e.maxPerKg)} J/kg${e.capText ? ' ' + e.capText : ''})` : '';
        const atLeast = later && e.thenAtLeast ? '≥ ' : '';
        if (!kg) return { text: `${atLeast}${R.acls.num(per)} J/kg${upTo}`, joules: null, needsWeight: true };
        // maxJ: the adult ceiling ("or the adult dose, whichever is lower"), so a large child never reads above it
        const cap = e.maxJ || null, raw = Math.round(per * kg);
        if (cap && raw > cap) return { text: `${cap} J, the adult dose (${R.acls.num(per)} J/kg would be ${raw} J)`, joules: cap, capped: true };
        let up = later && e.maxPerKg ? Math.round(e.maxPerKg * kg) : null;
        const upCapped = cap && up !== null && up > cap;
        if (upCapped) up = cap;
        return { text: `${atLeast}${raw} J (${R.acls.num(per)} J/kg)${up !== null ? `, up to ${up} J${upCapped ? ' (the adult dose)' : ''}` : ''}`, joules: raw };
      }
      return { text: e.text, joules: e.joules || null };
    },
    /** Rounds a dose sensibly: 2 decimals below 1, 1 below 10, whole above. */
    round(v) {
      const p = v < 1 ? 100 : v < 10 ? 10 : 1;
      return rnd(v * p) / p;
    },
    num(v) { return String(v); },
    /** Seconds since the start of the current CPR cycle (the last cycle-resetting entry, else the start). */
    cycle(s, data, t) {
      let from = 0;
      for (let i = s.log.length - 1; i >= 0; i--) {
        const a = data.actions[s.log[i].id];
        if (a && a.cycleReset && s.log[i].t <= t) { from = s.log[i].t; break; }
      }
      return { from, elapsed: (t - from) / 1000 };
    },
    /** Each repeatable action's state: never given, next in n s, due, or overdue (seconds since the last dose). */
    timer(a, s, id, t) {
      if (!a || !a.repeat) return null;
      const sp = R.acls.spec(a, s.patient);
      if (sp && sp.noRepeat) return null;   // e.g. a child's atropine: "may repeat once", no interval printed
      const last = R.acls.last(s, id);
      if (last === null) return null;
      const since = (t - last) / 1000;
      if (since < a.repeat.min) return { state: 'wait', since, remaining: a.repeat.min - since };
      if (a.repeat.max !== undefined && since >= a.repeat.max) return { state: 'overdue', since, remaining: 0 };
      return { state: 'due', since, remaining: 0 };
    },
    /** Whether every condition of a prompt holds. */
    holds(cond, s, data, t) {
      const c = cond || [];
      for (const k of c) {
        if (k.patient && k.patient !== s.patient) return false;
        if (k.rhythm && R.acls.rhythm(s, data) !== k.rhythm) return false;
        if (k.done && R.acls.count(s, k.done) === 0) return false;
        if (k.not && R.acls.count(s, k.not) > 0) return false;
        if (k.notAny && k.notAny.some((id) => R.acls.count(s, id) > 0)) return false;
        if (k.count) {
          const [id, op, n] = k.count, v = R.acls.count(s, id);
          if (!R.acls.cmp(v, op, n)) return false;
        }
        if (k.countAny) {
          // [[ids], op, n]: the entries of all these actions together
          const [ids, op, n] = k.countAny, v = ids.reduce((sum, id) => sum + R.acls.count(s, id), 0);
          if (!R.acls.cmp(v, op, n)) return false;
        }
        if (k.countSince) {
          // [id, sinceId, op, n]: how many of id were logged after the last sinceId (all of them when none)
          const [id, sinceId, op, n] = k.countSince, from = R.acls.last(s, sinceId);
          const v = s.log.filter((e) => e.id === id && (from === null || e.t > from)).length;
          if (!R.acls.cmp(v, op, n)) return false;
        }
        if (k.since) {
          const [id, op, sec] = k.since, last = R.acls.last(s, id);
          if (last === null || !R.acls.cmp((t - last) / 1000, op, sec)) return false;
        }
        if (k.elapsed) {
          const [op, sec] = k.elapsed;
          if (!R.acls.cmp(t / 1000, op, sec)) return false;
        }
        if (k.cycle) {
          const [op, sec] = k.cycle;
          if (!R.acls.cmp(R.acls.cycle(s, data, t).elapsed, op, sec)) return false;
        }
        if (k.weight === true && !R.acls.kg(s)) return false;
      }
      return true;
    },
    cmp(v, op, n) {
      switch (op) {
        case '>=': return v >= n;
        case '>': return v > n;
        case '<=': return v <= n;
        case '<': return v < n;
        case '==': return v === n;
        default: return false;
      }
    },
    /** Fills {dose:id}, {energy:id} and {count:id} in a prompt's text. */
    fill(text, s, data) {
      return String(text || '').replace(/\{(dose|energy|count|next):([a-z0-9-]+)\}/g, (_, kind, id) => {
        const a = data.actions[id];
        if (!a) return '';
        const n = R.acls.count(s, id);
        if (kind === 'dose') { const d = R.acls.dose(a, s, n); return d ? d.text : ''; }
        if (kind === 'energy') { const e = R.acls.energy(a, s, n); return e ? e.text : ''; }
        if (kind === 'next') return String(n + 1);
        return String(n);
      });
    },
    /** The prompts that apply now, in the mode's order: [{ id, level, text, action, alert }]. */
    prompts(s, data, t) {
      const mode = data.modes.find((m) => m.id === s.mode);
      if (!mode) return [];
      const out = [];
      for (const p of mode.prompts || []) {
        if (p.patient && p.patient !== s.patient) continue;
        if (!R.acls.holds(p.when, s, data, t)) continue;
        const a = p.action ? data.actions[p.action] : null;
        if (a && R.acls.count(s, p.action) >= R.acls.maxDoses(a, s)) continue;
        out.push({ id: p.id, level: p.level || 'info', text: R.acls.fill(p.text, s, data), action: p.action || null, alert: !!p.alert });
      }
      return out;
    },
    /** Deadlines still open: [{ id, label, remaining (s) }] — negative once passed. */
    deadlines(s, data, t) {
      const mode = data.modes.find((m) => m.id === s.mode);
      return ((mode && mode.deadlines) || []).filter((d) => !(d.until && R.acls.count(s, d.until) > 0)).map((d) => ({ id: d.id, label: d.label, remaining: d.sec - t / 1000 }));
    },
    /** The decision path of a tree mode: the node ids chosen so far, the current node, and the patient's tree. */
    tree(s, data) {
      const mode = data.modes.find((m) => m.id === s.mode);
      const tr = mode && mode.tree && (mode.tree[s.patient] || mode.tree.all);
      if (!tr) return null;
      const path = (s.path[mode.id + ':' + s.patient] || []).filter((id) => tr.nodes[id]);
      const cur = path.length ? path[path.length - 1] : tr.start;
      return { tree: tr, path, node: tr.nodes[cur], nodeId: cur };
    },
    choose(s, data, t, nextId, label) {
      const mode = data.modes.find((m) => m.id === s.mode);
      const key = mode.id + ':' + s.patient;
      const tr = R.acls.tree(s, data);
      s.path[key] = (s.path[key] || []).concat([nextId]);
      R.acls.add(s, t, null, `${mode.short || mode.name}: ${tr.node.q} ${label}`, { kind: 'choice' });
    },
    back(s, data) {
      const mode = data.modes.find((m) => m.id === s.mode);
      const key = mode.id + ':' + s.patient;
      if (s.path[key] && s.path[key].length) s.path[key] = s.path[key].slice(0, -1);
    },
    /** The text logged for an action: "Epinephrine 1 mg IV/IO (dose 2)", "Shock 3: 200 J". `joules` is the
        energy typed for this shock; a child's computed energy is used when none is typed. */
    entryText(a, s, n, joules) {
      if (a.kind === 'shock') {
        const e = R.acls.energy(a, s, n), j = joules > 0 ? joules : e && e.joules ? e.joules : null;
        return `${a.label} ${n + 1}${j ? ': ' + j + ' J' : ''}`;
      }
      if (a.kind === 'drug') {
        const d = R.acls.dose(a, s, n), sp = R.acls.spec(a, s.patient);
        const amount = d && d.amount !== null ? ` ${R.acls.num(d.amount)} ${d.unit}${sp && sp.route ? ' ' + sp.route : ''}` : '';
        return `${a.label}${amount}${n ? ` (dose ${n + 1})` : ''}`;
      }
      return a.log || a.label;
    },
    /** The log as text for the record: one line per entry with clock time and code time. */
    logText(s, wall) {
      const who = s.patient === 'child' ? `child${R.acls.kg(s) ? ', ' + R.acls.num(R.acls.kg(s)) + ' kg' : ''}` : 'adult';
      const lines = [`Code log (${who}), started ${wall(s.startedAt)}`];
      for (const e of s.log) lines.push(`${wall(s.startedAt + e.t)}  +${R.acls.clock(e.t)}  ${e.text}`);
      return lines.join('\n');
    },
  };

  // ---------- ABG: acid–base and compensation (AbgCalc.swift; rules in reference.json "abg") ----------
  // pH, PaCO2 (mmHg) and HCO3 (mEq/L) in: the primary disorder, whether the compensation is what the rule
  // expects, and the second disorder when it is not. Each rule is a straight line read from the reference
  // file, expected = slope × x + intercept ± tol, so a review can change a coefficient without touching code.
  // Any two of the three values are enough: the third comes from Henderson–Hasselbalch.
  const ABG_NAME = { metAcid: 'metabolic acidosis', metAlk: 'metabolic alkalosis', respAcid: 'respiratory acidosis', respAlk: 'respiratory alkalosis' };
  const cap = (s) => s.split(' ').map((w) => (w === 'and' ? w : w[0].toUpperCase() + w.slice(1))).join(' ');
  R.abg = {
    /** pH from PaCO2 and HCO3, and the two inverses (Henderson–Hasselbalch with the file's pK and CO2 solubility). */
    ph(d, paco2, hco3) { return d.check.pk + Math.log10(hco3 / (d.check.solubility * paco2)); },
    hco3(d, ph, paco2) { return d.check.solubility * paco2 * Math.pow(10, ph - d.check.pk); },
    paco2(d, ph, hco3) { return hco3 / (d.check.solubility * Math.pow(10, ph - d.check.pk)); },
    /** The band a rule expects at x. */
    expect(rule, x) { const v = rule.slope * x + rule.intercept; return { v, lo: v - (rule.tol || 0), hi: v + (rule.tol || 0) }; },
    /** 24.84 → "24.8"; 31 → "31"; pH to two places. */
    f1(v) { const r = Math.round(v * 10) / 10; return r === Math.trunc(r) ? String(Math.trunc(r)) : r.toFixed(1); },
    fph(v) { return (Math.round(v * 100) / 100).toFixed(2); },
    band(e) { return R.abg.f1(e.lo) + '–' + R.abg.f1(e.hi); },
    /** The two disorders in the order found: "Metabolic and Respiratory Acidosis", "Respiratory Acidosis and Metabolic Alkalosis". */
    title(a, b) {
      if (!b) return cap(ABG_NAME[a]);
      const [ka, ta] = ABG_NAME[a].split(' '), [kb, tb] = ABG_NAME[b].split(' ');
      return ta === tb ? cap(`${ka} and ${kb} ${ta}`) : cap(`${ABG_NAME[a]} and ${ABG_NAME[b]}`);
    },
    /** i: { ph, paco2, hco3 }, d: the "abg" section. Returns { state: 'empty' | 'read', headline, explanation,
        status: 'acidemia' | 'alkalemia' | 'normal', primary, second, phase, disorders[], steps[], cautions[],
        visual, values { ph, paco2, hco3 }, derived: null | 'ph' | 'paco2' | 'hco3', check }. */
    read(i, d) {
      const A = R.abg, N = d.normal, M = d.mid, steps = [], cautions = [];
      let ph = has(i.ph) ? i.ph : null, pc = has(i.paco2) ? i.paco2 : null, hc = has(i.hco3) ? i.hco3 : null;
      const given = [ph, pc, hc].filter((x) => x !== null).length;
      if (given < 2) return { state: 'empty', headline: 'Enter the Gas', explanation: 'Enter pH, PaCO₂ and HCO₃. Any two are enough: the third is worked out from them.', status: null, primary: null, second: null, phase: null, disorders: [], steps, cautions, visual: null, values: { ph, paco2: pc, hco3: hc }, derived: null, check: null };
      let derived = null;
      if (ph === null) { ph = A.ph(d, pc, hc); derived = 'ph'; }
      else if (hc === null) { hc = A.hco3(d, ph, pc); derived = 'hco3'; }
      else if (pc === null) { pc = A.paco2(d, ph, hc); derived = 'paco2'; }
      const P = d.plausible || {};
      if ((P.ph && (ph < P.ph[0] || ph > P.ph[1])) || (P.paco2 && (pc < P.paco2[0] || pc > P.paco2[1])) || (P.hco3 && (hc < P.hco3[0] || hc > P.hco3[1])))
        cautions.push('A value lies outside what a blood gas usually shows. Check the entry and the units (mmHg, not kPa).');
      const status = ph < N.ph[0] ? 'acidemia' : ph > N.ph[1] ? 'alkalemia' : 'normal';
      const pcHi = pc > N.paco2[1], pcLo = pc < N.paco2[0], hcLo = hc < N.hco3[0], hcHi = hc > N.hco3[1];
      steps.push({ id: 'ph', label: 'pH', tone: status === 'normal' ? 'ok' : 'bad', text: `${A.fph(ph)}${derived === 'ph' ? ' (calculated)' : ''} · ${status === 'normal' ? 'normal' : status}` });
      let check = null;
      if (given === 3) {
        const calc = A.ph(d, pc, hc), diff = calc - ph;
        check = { calc, diff, ok: Math.abs(diff) <= d.check.tol };
        if (!check.ok) cautions.push(`The three values do not agree: PaCO₂ ${A.f1(pc)} and HCO₃ ${A.f1(hc)} give pH ${A.fph(calc)}, not ${A.fph(ph)}. Look for a typing error, or an HCO₃ from a separate chemistry sample; the reading below uses the values as entered.`);
      }
      const out = (o) => {
        if (check) steps.push({ id: 'check', label: 'Values agree', tone: check.ok ? 'ok' : 'bad', text: `PaCO₂ and HCO₃ give pH ${A.fph(check.calc)} · ${check.ok ? 'consistent' : 'differs by ' + Math.abs(check.diff).toFixed(2)}` });
        if (derived) steps.push({ id: 'derived', label: 'Calculated', tone: 'info', text: derived === 'hco3' ? `HCO₃ ${A.f1(hc)} mEq/L from pH and PaCO₂` : derived === 'paco2' ? `PaCO₂ ${A.f1(pc)} mmHg from pH and HCO₃` : `pH ${A.fph(ph)} from PaCO₂ and HCO₃` });
        return Object.assign({ state: 'read', status, primary: null, second: null, phase: null, disorders: [], steps, cautions, visual: null, values: { ph, paco2: pc, hco3: hc }, derived, check }, o);
      };
      if (status === 'normal' && !pcHi && !pcLo && !hcLo && !hcHi) {
        steps.push({ id: 'primary', label: 'PaCO₂ and HCO₃', tone: 'ok', text: `${A.f1(pc)} mmHg and ${A.f1(hc)} mEq/L · both normal` });
        return out({ headline: 'Normal Acid–Base Status', explanation: 'pH, PaCO₂ and HCO₃ are all in the normal range. A metabolic acidosis and alkalosis that cancel out can still hide behind a normal gas.' });
      }
      // Which process moves pH the way it went (toward the side of 7.40 it sits on)
      const side = ph < M.ph ? 'acid' : ph > M.ph ? 'alk' : null;
      let resp, met;
      if (side === 'acid') { resp = pc > M.paco2; met = hc < M.hco3; }
      else if (side === 'alk') { resp = pc < M.paco2; met = hc > M.hco3; }
      else { resp = pcHi || pcLo; met = hcHi || hcLo; }
      const respOut = side === 'acid' ? pcHi : side === 'alk' ? pcLo : resp;
      const metOut = side === 'acid' ? hcLo : side === 'alk' ? hcHi : met;
      const respKind = pc > M.paco2 ? 'respAcid' : 'respAlk', metKind = hc < M.hco3 ? 'metAcid' : 'metAlk';
      const pcText = `PaCO₂ ${A.f1(pc)} mmHg${pcHi ? ' (above ' + N.paco2[1] + ')' : pcLo ? ' (below ' + N.paco2[0] + ')' : ''}`;
      const hcText = `HCO₃ ${A.f1(hc)} mEq/L${hcLo ? ' (below ' + N.hco3[0] + ')' : hcHi ? ' (above ' + N.hco3[1] + ')' : ''}`;
      const phText = status === 'normal' ? `pH ${A.fph(ph)} is normal.` : `pH ${A.fph(ph)}: ${status}.`;
      if (!resp && !met) {
        cautions.push('Neither PaCO₂ nor HCO₃ moves pH the way it went, which a blood gas cannot do. Check the values.');
        return out({ headline: 'Check the Values', explanation: `pH ${A.fph(ph)} does not follow from ${pcText} and ${hcText}.` });
      }
      let primary;
      if (resp && met && (respOut === metOut)) {
        if (side === null || respOut) {
          // Both move pH the same way and both are outside their range (or pH sits at 7.40 with both abnormal)
          const both = side === null ? [respKind, metKind] : [respKind, metKind];
          steps.push({ id: 'primary', label: 'Primary', tone: 'bad', text: `${pcText}; ${hcText} · both` });
          const head = A.title(both[0], both[1]);
          return out({ headline: head, primary: both[0], second: both[1], disorders: both,
            explanation: side === null
              ? `pH ${A.fph(ph)} sits at the middle of the range while ${pcText} and ${hcText} are both abnormal: two opposing disorders.`
              : `${phText} ${pcText} and ${hcText} both push pH the same way, so both are primary and there is no compensation to check.` });
        }
        // Neither outside its range: the larger shift, scaled by the width of its normal half-range, leads
        const dr = Math.abs(pc - M.paco2) / Math.max(N.paco2[1] - M.paco2, M.paco2 - N.paco2[0]);
        const dm = Math.abs(hc - M.hco3) / Math.max(N.hco3[1] - M.hco3, M.hco3 - N.hco3[0]);
        primary = dr >= dm ? respKind : metKind;
      } else if (resp && met) primary = respOut ? respKind : metKind;
      else primary = resp ? respKind : metKind;
      const isResp = primary === 'respAcid' || primary === 'respAlk';
      steps.push({ id: 'primary', label: 'Primary', tone: 'bad', text: (isResp ? pcText : hcText) + ' · ' + ABG_NAME[primary] });
      let second = null, phase = null, visual, compText;
      if (!isResp) {
        const rule = d.rules[primary], e = A.expect(rule, hc);
        second = pc > e.hi ? 'respAcid' : pc < e.lo ? 'respAlk' : null;
        visual = { variable: 'PaCO₂', unit: 'mmHg', measured: pc, bands: [{ id: 'expected', label: 'Expected', lo: e.lo, hi: e.hi }] };
        compText = `${rule.label ? rule.label + ' expects' : 'Expected'} PaCO₂ ${A.band(e)} mmHg; ${A.f1(pc)} ${second ? (second === 'respAcid' ? 'is above it' : 'is below it') : 'sits in it'}`;
        steps.push({ id: 'comp', label: 'Respiratory compensation', tone: second ? 'bad' : 'ok', text: `expected ${A.band(e)} · measured ${A.f1(pc)}${second ? ', ' + (second === 'respAcid' ? 'above' : 'below') : ''}` });
      } else {
        const acid = primary === 'respAcid';
        const ra = d.rules[acid ? 'respAcidAcute' : 'respAlkAcute'], rc = d.rules[acid ? 'respAcidChronic' : 'respAlkChronic'];
        const a = A.expect(ra, pc), c = A.expect(rc, pc);
        if (rc.xmax && pc > rc.xmax) cautions.push(`The chronic rule was derived up to PaCO₂ ${rc.xmax} mmHg; read its band with caution above that.`);
        const inA = hc >= a.lo && hc <= a.hi, inC = hc >= c.lo && hc <= c.hi;
        if (hc < Math.min(a.lo, c.lo)) second = 'metAcid';
        else if (hc > Math.max(a.hi, c.hi)) second = 'metAlk';
        else phase = inA && inC ? 'either' : inA ? 'acute' : inC ? 'chronic' : 'between';
        visual = { variable: 'HCO₃', unit: 'mEq/L', measured: hc, bands: [{ id: 'acute', label: 'Acute', lo: a.lo, hi: a.hi }, { id: 'chronic', label: 'Chronic', lo: c.lo, hi: c.hi }] };
        const where = second ? (second === 'metAcid' ? 'is below both' : 'is above both')
          : phase === 'acute' ? 'fits an acute change' : phase === 'chronic' ? 'fits a chronic change' : phase === 'either' ? 'fits either; the change is too small to tell them apart' : 'falls between them: subacute, or acute on chronic';
        compText = `An acute change expects HCO₃ ${A.band(a)} mEq/L and a chronic one ${A.band(c)}; ${A.f1(hc)} ${where}`;
        steps.push({ id: 'comp', label: 'Metabolic compensation', tone: second ? 'bad' : 'ok', text: `acute ${A.band(a)} · chronic ${A.band(c)} · measured ${A.f1(hc)}${second ? ', ' + (second === 'metAcid' ? 'below' : 'above') : ''}` });
      }
      const disorders = second ? [primary, second] : [primary];
      let headline = A.title(primary, second);
      if (!second && isResp) headline = phase === 'acute' ? 'Acute ' + headline : phase === 'chronic' ? 'Chronic ' + headline : phase === 'between' ? headline + ', Partly Compensated' : headline;
      const kind = isResp ? 'respiratory' : 'metabolic';
      const lead = status === 'normal' ? `pH ${A.fph(ph)} is normal, but ${isResp ? pcText : hcText} points to a ${kind} process.` : `${phText} ${isResp ? pcText : hcText} makes it ${kind}.`;
      const tail = second ? `. ${ABG_NAME[second][0].toUpperCase() + ABG_NAME[second].slice(1)} as well.` : isResp ? '.' : ': the respiratory compensation is appropriate.';
      return out({ headline, primary, second, phase, disorders, visual, explanation: `${lead} ${compText}${tail}` });
    },
    /** One line for the record. */
    summary(r) {
      if (r.state !== 'read') return '';
      const v = r.values, A = R.abg;
      return `ABG: pH ${A.fph(v.ph)}, PaCO₂ ${A.f1(v.paco2)} mmHg, HCO₃ ${A.f1(v.hco3)} mEq/L${r.derived ? ' (' + (r.derived === 'hco3' ? 'HCO₃' : r.derived === 'paco2' ? 'PaCO₂' : 'pH') + ' calculated)' : ''}. ${r.headline}. ${r.explanation}`;
    },
  };

  // ---------- Regional technique finder (RegionalCalc.swift; content in reference.json "regional") ----------
  // The figure's regions carry an id and, for paired regions, a side. A selection is a list of "id:side" keys
  // (side R or L for paired regions, M for midline ones). Each region maps to its neuraxial options and blocks.
  const DERM = ['C2', 'C3', 'C4', 'C5', 'C6', 'C7', 'C8', 'T1', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'T8', 'T9', 'T10', 'T11', 'T12', 'L1', 'L2', 'L3', 'L4', 'L5', 'S1', 'S2', 'S3', 'S4', 'S5'];
  R.regional = {
    /** Order of a dermatome, head to foot (C2 = 0); -1 when unknown. "T4–T6" ranks by its first level. */
    rank(level) { const m = String(level || '').toUpperCase().match(/[CTLS]\d{1,2}/); return m ? DERM.indexOf(m[0]) : -1; },
    /** Which side a region's nth polygon is: midline M; paired regions are listed viewer's left first, which is
        the patient's right on the front view and the patient's left on the back. */
    side(view, index, count) { return count < 2 ? 'M' : (view === 'back') === (index === 0) ? 'L' : 'R'; },
    /** "Right knee", "Left and right hip", "Perineum and anus". */
    label(name, sides) {
      const lower = name.charAt(0).toLowerCase() + name.slice(1);
      const s = sides.filter((x) => x !== 'M');
      if (!s.length) return name;
      if (s.length === 2) return 'Both sides: ' + lower;
      return (s[0] === 'R' ? 'Right ' : 'Left ') + lower;
    },
    /** keys: ["knee:R", "hip:L", …]; d: the "regional" section. Returns { items, top } — one item per region (head to
        foot) with its neuraxial options and blocks, and `top`, the most cephalad level any selected region needs. */
    recommend(keys, d) {
      const order = d.figure.regions.map((r) => r.id), byId = new Map();
      for (const k of keys) {
        const [id, side] = String(k).split(':');
        const reg = d.figure.regions.find((r) => r.id === id);
        if (!reg) continue;
        if (!byId.has(id)) byId.set(id, { id, name: reg.name, sides: [] });
        const it = byId.get(id);
        if (side && !it.sides.includes(side)) it.sides.push(side);
      }
      const items = [...byId.values()].sort((a, b) => order.indexOf(a.id) - order.indexOf(b.id)).map((it) => {
        const m = (d.map || {})[it.id] || {};
        const blocks = (m.blocks || []).map((b) => {
          const blk = (d.blocks || []).find((x) => x.id === b.id);
          return blk ? { id: b.id, name: blk.name, role: b.role || 'primary', note: b.note || null } : null;
        }).filter(Boolean);
        it.sides.sort((a, b) => (a === 'R' ? -1 : b === 'R' ? 1 : 0));
        return { id: it.id, name: it.name, sides: it.sides, label: R.regional.label(it.name, it.sides), neuraxial: m.neuraxial || null, blocks, note: m.note || null };
      });
      let top = null;
      for (const it of items) {
        const n = it.neuraxial;
        const lv = n && (n.level || null);
        if (lv && R.regional.rank(lv) >= 0 && (top === null || R.regional.rank(lv) < R.regional.rank(top.level))) top = { level: lv, region: it.name };
      }
      return { items, top };
    },
  };

  global.PSRef = R;
})(typeof window !== 'undefined' ? window : globalThis);
