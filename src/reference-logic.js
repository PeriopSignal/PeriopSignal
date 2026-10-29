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
        YN('sx', 'Symptoms attributable to the stenosis', 'Exertional dyspnea, angina, syncope or presyncope; an exercise test settles doubtful cases'),
        Q('ef', 'LVEF', ['≥ 60%', '50–59%', '< 50%']),
        YN('surg', 'Other cardiac surgery planned'),
        Q('risk', 'Surgical risk', ['Low', 'Intermediate', 'High or prohibitive'], 'Low: STS < 3%, no frailty, no major organ compromise; high: STS > 8%, ≥ 2 frailty indices or 1–2 uncorrectable organ systems'),
        AGE,
        YN('markers', 'Abnormal exercise test, BNP > 3× normal, or Vmax rising ≥ 0.3 m/s a year', 'Reduced exercise tolerance or a systolic pressure fall ≥ 10 mmHg on exercise testing'),
        YN('effall', 'LVEF fallen below 60% on three or more serial studies'),
        YN('tf', 'Transfemoral anatomy suitable for TAVI'),
        YN('bicuspid', 'Bicuspid valve'),
        YN('survival', 'Expected survival after intervention over 12 months with acceptable quality of life'),
        YN('critical', 'Critically ill'),
        ANTICOAG,
      ];
      case 'ar': return [
        Q('sev', 'Severity on echo', ['Moderate', 'Severe']),
        YN('sx', 'Symptoms'),
        Q('ef', 'LVEF', ['> 60%', '55–60%', '≤ 55%']),
        YN('lvesd', 'LVESD > 50 mm, or indexed LVESD > 25 mm/m²'),
        YN('lvedd', 'LVEDD > 65 mm'),
        YN('surg', 'Other cardiac or aortic surgery planned'),
        Q('risk', 'Surgical risk', ['Low', 'Not low']),
        YN('effall', 'LVEF drifting into 55–60% on three or more serial studies'),
        YN('bicuspid', 'Bicuspid valve'),
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
        YN('pmbc', 'Favorable morphology, less than 2+ MR and no left atrial thrombus', 'The requirements for percutaneous mitral balloon commissurotomy (PMBC)'),
        YN('calcific', 'Calcific stenosis from annular calcification (non-rheumatic)'),
        YN('pasp', 'PA systolic pressure > 50 mmHg'),
        YN('af', 'New-onset atrial fibrillation'),
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
  const CLASS_WORD = { '1': 'Recommended', '2a': 'Reasonable', '2b': 'May be considered', '3': 'Not recommended' };
  const CLASS_ORDER = { '1': 0, '2a': 1, '2b': 2, '3': 3 };
  const GROUPS = ['Intervention', 'Which procedure', 'Prosthesis'];
  R.viClassWord = (c) => CLASS_WORD[c];
  R.viGroups = GROUPS;
  function prosthesisRules(position, also) {
    also = also || [];
    const P = { group: 'Prosthesis' };
    const r = [rule('pr-bio-any', 'Anticoagulation impossible or unwanted', 'Bioprosthesis at any age', '1', 'C-EO', [[no('anticoag')].concat(also)], P)];
    if (position === 'Aortic') {
      r.push(
        rule('pr-ao-young', 'Aortic valve, age under 50, anticoagulation acceptable', 'Mechanical prosthesis is reasonable; the Ross procedure may be considered at a Comprehensive Valve Center (2b)', '2a', 'B-NR', [[C('age', '< 50'), yes('anticoag')].concat(also)], P),
        rule('pr-ao-mid', 'Aortic valve, age 50–65', 'Either prosthesis, individualized', '2a', 'B-NR', [[C('age', '50–64'), yes('anticoag')].concat(also)], P),
        rule('pr-ao-old', 'Aortic valve, age over 65', 'Bioprosthesis is reasonable', '2a', 'B-NR', [[C('age', '65–80', '> 80')].concat(also)], P));
    } else {
      r.push(
        rule('pr-mi-young', 'Mitral valve, age under 65, anticoagulation acceptable', 'Mechanical prosthesis is reasonable', '2a', 'B-NR', [[C('age', '< 50', '50–64'), yes('anticoag')]], P),
        rule('pr-mi-old', 'Mitral valve, age 65 or over', 'Bioprosthesis is reasonable', '2a', 'B-NR', [[C('age', '65–80', '> 80')]], P));
    }
    return r;
  }
  R.viRules = function (lesion) {
    const severe = C('sev', 'Severe', 'Very severe');
    const operable = C('risk', 'Low', 'Intermediate');
    const PROC = { group: 'Which procedure' };
    switch (lesion) {
      case 'as': return [
        rule('as-d1', 'Symptomatic severe high-gradient AS (stage D1)', 'Aortic valve replacement', '1', 'A', [[yes('sx'), severe]]),
        rule('as-c2', 'Asymptomatic severe AS with LVEF < 50% (C2)', 'Aortic valve replacement', '1', 'B-NR', [[no('sx'), severe, C('ef', '< 50%')]]),
        rule('as-surg', 'Asymptomatic severe AS having other cardiac surgery (C1)', 'Aortic valve replacement', '1', 'B-NR', [[no('sx'), severe, yes('surg')]]),
        rule('as-d2', 'Symptomatic low-flow, low-gradient AS with LVEF < 50% (D2)', 'Aortic valve replacement', '1', 'B-NR', [[yes('sx'), C('sev', 'Low-flow, low-gradient'), C('ef', '< 50%')]], { note: 'D2 means true severe stenosis on low-dose dobutamine stress echo: Vmax ≥ 4 m/s or mean gradient ≥ 40 mmHg with AVA ≤ 1.0 cm² at any flow.' }),
        rule('as-d3', 'Symptomatic low-flow, low-gradient AS with LVEF ≥ 50% (D3)', 'Aortic valve replacement when the stenosis is the most likely cause of the symptoms', '1', 'B-NR', [[yes('sx'), C('sev', 'Low-flow, low-gradient'), C('ef', '≥ 60%', '50–59%')]], { note: 'Paradoxical low-flow AS: confirm the small stroke volume by another technique and the severity by calcium scoring before attributing the symptoms to the valve.' }),
        rule('as-2a', 'Asymptomatic severe AS, low surgical risk, with an abnormal exercise test, BNP > 3× normal or rapid progression (C1)', 'Aortic valve replacement is reasonable', '2a', 'B-NR', [[no('sx'), severe, C('risk', 'Low'), yes('markers')]]),
        rule('as-vs', 'Asymptomatic very severe AS (Vmax ≥ 5 m/s), low surgical risk', 'Aortic valve replacement is reasonable', '2a', 'B-NR', [[no('sx'), C('sev', 'Very severe'), C('risk', 'Low')]]),
        rule('as-2b', 'Asymptomatic severe AS with LVEF fallen below 60% on three or more serial studies', 'Aortic valve replacement may be considered', '2b', 'B-NR', [[no('sx'), severe, yes('effall')]]),
        rule('as-mod', 'Moderate AS having other cardiac surgery (B)', 'Aortic valve replacement may be considered', '2b', 'C-EO', [[C('sev', 'Moderate'), yes('surg')]]),
        rule('as-savr-age', 'Age under 65, or life expectancy over 20 years', 'Surgical AVR', '1', 'A', [[C('age', '< 50', '50–64'), operable]], PROC),
        rule('as-either', 'Age 65–80 with no anatomic contraindication to transfemoral TAVI', 'Surgical AVR or transfemoral TAVI after shared decision-making (longevity against valve durability)', '1', 'A', [[C('age', '65–80'), yes('tf'), operable]], PROC),
        rule('as-tavi-age', 'Age over 80, or life expectancy under 10 years', 'Transfemoral TAVI in preference to surgery', '1', 'A', [[C('age', '> 80'), yes('tf'), operable]], PROC),
        rule('as-tavi-risk', 'High or prohibitive surgical risk with predicted survival after TAVI over 12 months', 'TAVI', '1', 'A', [[C('risk', 'High or prohibitive'), yes('survival')]], PROC),
        rule('as-pall', 'Predicted survival under 12 months, or minimal expected benefit', 'Palliative care after shared decision-making', '1', 'C-EO', [[no('survival')]], PROC),
        rule('as-savr-anat', 'Anatomy unsuitable for transfemoral TAVI and a bioprosthesis preferred', 'Surgical AVR', '1', 'A', [[no('tf'), operable]], PROC),
        rule('as-savr-2a', 'Asymptomatic AS operated for a 2a indication (exercise test, very severe stenosis, rapid progression, BNP)', 'Surgical AVR in preference to TAVI', '1', 'B-NR', [[no('sx'), yes('markers')], [no('sx'), C('sev', 'Very severe')]], PROC),
        rule('as-bav', 'Bicuspid valve with symptomatic severe AS', 'TAVI may be considered as an alternative to surgery at a Comprehensive Valve Center', '2b', 'B-NR', [[yes('bicuspid'), yes('sx')]], Object.assign({ note: 'A bicuspid valve otherwise favors surgery, as do LVOT calcification, a very small or large annulus, aortic dilation, severe primary MR and coronary disease needing bypass.' }, PROC)),
        rule('as-bav-crit', 'Critically ill', 'Balloon aortic valvuloplasty may be considered as a bridge to AVR', '2b', 'C-EO', [[yes('critical')]], PROC),
      ].concat(prosthesisRules('Aortic', [operable]));
      case 'ar': return [
        rule('ar-d', 'Symptomatic severe AR (D)', 'Aortic valve surgery, regardless of LV function', '1', 'B-NR', [[C('sev', 'Severe'), yes('sx')]]),
        rule('ar-c2', 'Asymptomatic severe AR with LVEF ≤ 55% (C2)', 'Aortic valve surgery, if there is no other cause of the LV dysfunction', '1', 'B-NR', [[C('sev', 'Severe'), no('sx'), C('ef', '≤ 55%')]]),
        rule('ar-surg', 'Severe AR having other cardiac surgery', 'Aortic valve surgery', '1', 'C-EO', [[C('sev', 'Severe'), yes('surg')]]),
        rule('ar-c2-dim', 'Asymptomatic severe AR with LVEF > 55% and LVESD > 50 mm or indexed > 25 mm/m² (C2)', 'Aortic valve surgery is reasonable', '2a', 'B-NR', [[C('sev', 'Severe'), no('sx'), C('ef', '> 60%', '55–60%'), yes('lvesd')]]),
        rule('ar-mod', 'Moderate AR having other cardiac or aortic surgery (B)', 'Aortic valve surgery is reasonable', '2a', 'C-EO', [[C('sev', 'Moderate'), yes('surg')]]),
        rule('ar-2b', 'Asymptomatic severe AR at low risk, LVEF drifting into 55–60% on serial studies or LVEDD > 65 mm (C1)', 'Aortic valve surgery may be considered', '2b', 'B-NR', [[C('sev', 'Severe'), no('sx'), C('risk', 'Low'), yes('effall')], [C('sev', 'Severe'), no('sx'), C('risk', 'Low'), yes('lvedd')]]),
        rule('ar-bav', 'Bicuspid valve with severe AR', 'Valve repair may be considered in selected patients at a Comprehensive Valve Center', '2b', 'C-LD', [[yes('bicuspid'), C('sev', 'Severe')]], PROC),
        rule('ar-tavi', 'Isolated severe AR in a surgical candidate', 'TAVI should not be performed', '3', 'Harm', [[C('sev', 'Severe'), yes('candidate')]], PROC),
      ].concat(prosthesisRules('Aortic'));
      case 'mrPrimary': return [
        rule('mr-d', 'Symptomatic severe primary MR (D)', 'Mitral intervention, regardless of LV function', '1', 'B-NR', [[C('sev', 'Severe'), yes('sx')]]),
        rule('mr-c2', 'Asymptomatic severe MR with LVEF ≤ 60% or LVESD ≥ 40 mm (C2)', 'Mitral surgery', '1', 'B-NR', [[C('sev', 'Severe'), no('sx'), C('ef', '≤ 60%')], [C('sev', 'Severe'), no('sx'), yes('lvesd')]]),
        rule('mr-c1', 'Asymptomatic severe MR with LVEF > 60% and LVESD < 40 mm (C1), a durable repair likely', 'Mitral repair is reasonable at a Primary or Comprehensive Valve Center', '2a', 'B-NR', [[C('sev', 'Severe'), no('sx'), C('ef', '> 60%'), no('lvesd'), yes('durable')]]),
        rule('mr-c1-serial', 'C1 with the LV enlarging or LVEF falling on serial studies', 'Mitral surgery may be considered', '2b', 'C-LD', [[C('sev', 'Severe'), no('sx'), C('ef', '> 60%'), no('lvesd'), yes('serial')]]),
        rule('mr-teer', 'Symptomatic severe primary MR, NYHA III–IV, high or prohibitive surgical risk, favorable anatomy, life expectancy at least a year', 'Transcatheter edge-to-edge repair is reasonable', '2a', 'B-NR', [[C('sev', 'Severe'), yes('sx'), C('nyha', 'III–IV'), C('risk', 'High or prohibitive'), yes('anatomy')]]),
        rule('mr-repair', 'Surgery for degenerative disease', 'Repair rather than replacement whenever a durable repair is possible', '1', 'B-NR', [[C('sev', 'Severe'), no('rheumatic')]], PROC),
        rule('mr-posterior', 'Pathology limited to less than half of the posterior leaflet', 'Replacement should not be done unless repair was attempted at a valve center and failed', '3', 'Harm', [[yes('posterior')]], PROC),
        rule('mr-rheum', 'Rheumatic severe primary MR with surgery indicated', 'Repair may be considered at a Comprehensive Valve Center', '2b', 'B-NR', [[yes('rheumatic'), C('sev', 'Severe')]], PROC),
      ].concat(prosthesisRules('Mitral'));
      case 'mrSecondary': return [
        rule('smr-gdmt', 'Severe secondary MR with heart failure and reduced LVEF', 'Guideline-directed medical therapy first, led by a heart-failure cardiologist: ACE inhibitor, ARB or sacubitril-valsartan, beta-blocker, aldosterone antagonist, biventricular pacing as indicated', '1', 'A', [[C('sev', 'Severe'), yes('hf')]]),
        rule('smr-teer', 'Persistent NYHA II–IV on optimal therapy, LVEF 20–50%, LVESD ≤ 70 mm, PA systolic pressure ≤ 70 mmHg, suitable anatomy', 'Transcatheter edge-to-edge repair is reasonable', '2a', 'B-R', [[C('sev', 'Severe'), yes('gdmt'), C('nyha', 'II', 'III–IV'), C('ef', '20–49%'), yes('lvesd70'), yes('pasp70'), yes('anatomy')]]),
        rule('smr-cabg', 'Severe secondary MR when coronary bypass surgery is undertaken', 'Concomitant mitral surgery is reasonable', '2a', 'B-NR', [[C('sev', 'Severe'), yes('cabg')]]),
        rule('smr-surg', 'LVEF < 50% with NYHA III–IV despite optimal therapy', 'Mitral surgery may be considered', '2b', 'B-NR', [[C('sev', 'Severe'), yes('gdmt'), C('nyha', 'III–IV'), C('ef', '20–49%', '< 20%')]]),
        rule('smr-cad', 'Surgery with coronary disease', 'Chordal-sparing replacement may be preferred over downsized annuloplasty', '2b', 'B-R', [[C('sev', 'Severe'), yes('gdmt'), C('nyha', 'III–IV'), C('ef', '20–49%', '< 20%'), yes('cad')]], PROC),
        rule('smr-atrial', 'Atrial annular dilation with LVEF ≥ 50% and NYHA III–IV despite therapy for heart failure and atrial fibrillation', 'Mitral surgery may be considered', '2b', 'B-NR', [[C('sev', 'Severe'), yes('gdmt'), C('nyha', 'III–IV'), C('ef', '≥ 50%'), yes('af')]]),
      ];
      case 'ms': return [
        rule('ms-pmbc', 'Symptomatic (NYHA II–IV) severe rheumatic MS with favorable morphology, less than 2+ MR and no LA thrombus', 'Percutaneous mitral balloon commissurotomy at a Comprehensive Valve Center', '1', 'A', [[C('sev', 'Severe (MVA ≤ 1.5 cm²)'), C('nyha', 'II', 'III–IV'), yes('pmbc'), no('calcific')]]),
        rule('ms-surg', 'NYHA III–IV severe MS not suitable for PMBC, after a failed PMBC, needing other cardiac surgery, or without access to PMBC', 'Mitral surgery (repair, commissurotomy or replacement)', '1', 'B-NR', [[C('sev', 'Severe (MVA ≤ 1.5 cm²)'), C('nyha', 'III–IV'), no('pmbc'), no('calcific'), yes('candidate')], [C('sev', 'Severe (MVA ≤ 1.5 cm²)'), C('nyha', 'III–IV'), yes('surg'), no('calcific'), yes('candidate')]]),
        rule('ms-pasp', 'Asymptomatic severe MS with PA systolic pressure > 50 mmHg, PMBC-suitable', 'PMBC is reasonable', '2a', 'B-NR', [[C('sev', 'Severe (MVA ≤ 1.5 cm²)'), C('nyha', 'I'), yes('pasp'), yes('pmbc')]]),
        rule('ms-af', 'Asymptomatic severe MS with new-onset atrial fibrillation, PMBC-suitable', 'PMBC may be considered', '2b', 'C-LD', [[C('sev', 'Severe (MVA ≤ 1.5 cm²)'), C('nyha', 'I'), yes('af'), yes('pmbc')]]),
        rule('ms-ex', 'Symptomatic with MVA > 1.5 cm² but a wedge pressure > 25 mmHg or mean gradient > 15 mmHg on exercise', 'PMBC may be considered', '2b', 'C-LD', [[C('sev', 'Not severe (MVA > 1.5 cm²)'), C('nyha', 'II', 'III–IV'), yes('exercise')]]),
        rule('ms-highrisk', 'NYHA III–IV with suboptimal anatomy, not a surgical candidate or at high risk', 'PMBC may be considered', '2b', 'B-NR', [[C('sev', 'Severe (MVA ≤ 1.5 cm²)'), C('nyha', 'III–IV'), no('pmbc'), no('candidate'), no('calcific')]]),
        rule('ms-mac', 'Calcific (non-rheumatic) severe MS from annular calcification with NYHA III–IV', 'Intervention only after discussion of its high procedural risk', '2b', 'C-LD', [[yes('calcific'), C('nyha', 'III–IV')]]),
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
    if (matched.some((r) => r.cls !== '3')) all.filter((r) => r.group !== 'Intervention').forEach(consider);
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
    /** The reference values that apply to this sex (sex-specific first, then the shared set). */
    ref(m, sex) { return (sex === 'female' ? m.female : m.male) || m.all || null; },
    /** -1 outside the normal range on the harmless side, 0 normal, 1–3 mildly/moderately/severely abnormal,
        4 abnormal where the guideline gives a single cutoff. null when no value or no reference. */
    grade(m, sex, v) {
      const r = R.echo.ref(m, sex);
      if (!r || v === null || v === undefined || !Number.isFinite(v)) return null;
      const cuts = r.cuts || [];
      const n = m.dir === 'low'
        ? cuts.filter((c) => (m.edge === 'inclusive' ? v <= c : v < c)).length
        : cuts.filter((c) => (m.edge === 'inclusive' ? v >= c : v > c)).length;
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
    /** The value to grade: indexed measures take an indexed entry as is, or a raw entry divided by BSA. */
    value(m, text, raw, bsa) {
      const v = R.num(text);
      if (v === null) return null;
      if (m.index === 'bsa' && raw) return bsa ? v / bsa : null;
      return v;
    },
    /** Band edges for drawing: [{ from, to, grade }] across a padded span around the reference values. */
    bands(m, sex) {
      const r = R.echo.ref(m, sex);
      if (!r) return [];
      const cuts = (r.cuts || []).slice().sort((a, b) => a - b);
      const lo = r.normal ? r.normal[0] : null, hi = r.normal ? r.normal[1] : null;
      const all = cuts.concat(lo !== null ? [lo] : [], hi !== null ? [hi] : []);
      const min = Math.min(...all), max = Math.max(...all), pad = (max - min || Math.abs(max) || 1) * 0.25;
      const start = Math.max(0, min - pad), end = max + pad;
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
    /** Right-atrial pressure from IVC diameter (cm) and whether it collapses by more than half with a sniff. */
    rap(ivcCm, collapses, cut) {
      const c = cut || 2.1;
      if (!(ivcCm > 0) || collapses === null || collapses === undefined) return null;
      if (ivcCm <= c && collapses) return { value: 3, range: '0–5', label: 'Normal' };
      if (ivcCm > c && !collapses) return { value: 15, range: '10–20', label: 'High' };
      return { value: 8, range: '5–10', label: 'Intermediate' };
    },
  };

  global.PSRef = R;
})(typeof window !== 'undefined' ? window : globalThis);
