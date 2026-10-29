#!/usr/bin/env node
// Unit tests for src/reference-logic.js, the website's copy of the app's calculators.
// They mirror ios/Tests/ReferenceTests.swift so the two stay in step.  Usage: node tools/test_reference_logic.js
'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const assert = require('assert');

const ROOT = path.resolve(__dirname, '..');
const ctx = { console };
vm.createContext(ctx);
vm.runInContext(fs.readFileSync(path.join(ROOT, 'src/reference-logic.js'), 'utf8'), ctx);
const R = ctx.PSRef;
const bundle = JSON.parse(fs.readFileSync(path.join(ROOT, 'reference.json'), 'utf8'));

let passed = 0, failed = 0;
function test(name, fn) {
  try { fn(); passed++; }
  catch (e) { failed++; console.log('FAIL ' + name + '\n  ' + (e && e.message)); }
}
// Objects made inside the vm context have that context's prototypes: compare their JSON shape.
const plain = (v) => (v !== null && typeof v === 'object') ? JSON.parse(JSON.stringify(v)) : v;
const eq = (a, b, msg) => assert.deepStrictEqual(plain(a), plain(b), msg);
const near = (a, b, tol, msg) => assert.ok(Math.abs(a - b) <= (tol || 1e-9), (msg || '') + ` (${a} vs ${b})`);
const sel = (on, choices) => ({ on: new Set(on || []), choices: choices || {} });

// ---------- scores ----------
test('RCRI', () => {
  const d = R.score('rcri');
  eq(R.scoreMax(d), 6);
  eq(R.scoreTotal(d, sel()), 0);
  assert.ok(R.scoreBand(d, 0).label.startsWith('Class I '));
  eq(R.scoreTotal(d, sel(['surgery', 'insulin'])), 2);
  assert.ok(R.scoreBand(d, 2).label.startsWith('Class III'));
  assert.ok(R.scoreBand(d, 5).label.startsWith('Class IV'));
});
test('ARISCAT', () => {
  const d = R.score('ariscat');
  eq(R.scoreMax(d), 16 + 24 + 17 + 11 + 24 + 23 + 8);
  eq(R.scoreTotal(d, sel([], { age: '> 80', spo2: '≤ 90%', incision: 'Intrathoracic' })), 64);
  eq(R.scoreBand(d, 64).tone, 'high');
  eq(R.scoreTotal(d, sel(['emergency'], { age: '51–80', incision: 'Upper abdominal' })), 26);
  eq(R.scoreBand(d, 26).tone, 'moderate');
  eq(R.scoreBand(d, 25).tone, 'low');
});
test('STOP-Bang and Apfel', () => {
  eq(R.scoreMax(R.score('stopbang')), 8);
  eq(R.scoreTotal(R.score('stopbang'), sel(['snoring', 'tired', 'pressure', 'age', 'gender'])), 5);
  eq(R.scoreBand(R.score('stopbang'), 5).tone, 'high');
  eq(R.scoreBand(R.score('stopbang'), 3).tone, 'moderate');
  eq(R.scoreTotal(R.score('apfel'), sel(['female', 'nonsmoker', 'history', 'opioids'])), 4);
  assert.ok(R.scoreBand(R.score('apfel'), 4).label.includes('79%'));
});
test('Aldrete defaults to 10', () => {
  const d = R.score('aldrete');
  eq(R.scoreTotal(d, sel()), 10);
  eq(R.scoreBand(d, 10).tone, 'low');
  eq(R.scoreTotal(d, sel([], { respiration: 'Apneic' })), 8);
  eq(R.scoreBand(d, 8).tone, 'high');
});
test('every band range is covered', () => {
  for (const d of R.scores) for (let s = 0; s <= R.scoreMax(d); s++) assert.ok(R.scoreBand(d, s), d.id + ' ' + s);
});

// ---------- pediatric ----------
test('weight estimates', () => {
  eq(R.peds.estimatedWeight(5, 0), 18); eq(R.peds.estimatedWeight(0, 6), 7); eq(R.peds.estimatedWeight(10, 0), 37);
  eq(R.peds.estimatedWeight(0, 0), null); eq(R.peds.estimatedWeight(14, 0), null);
});
test('airway sizes', () => {
  const four = R.peds.ettSizes(4, 0);
  eq(four.uncuffed, '5'); eq(four.cuffed, '4.5');
  eq(R.peds.ettDepthOral(4, 0, 5), '14'); eq(R.peds.ettDepthNasal(4, 0), '17');
  eq(R.peds.ettSizes(0, 0).cuffed, '3.0');
  eq(R.peds.lmaSize(18), '2'); eq(R.peds.lmaSize(4), '1'); eq(R.peds.lmaSize(75), '5');
});
test('fluids and blood', () => {
  eq(R.peds.maintenance(25), 65); eq(R.peds.maintenance(8), 32);
  near(R.peds.mabl(1000, 40, 30), 250, 0.01);
  eq(R.peds.mabl(1000, 30, 30), null);
  const rows = [{ group: 'Infant', fromMonths: 1, toMonths: 12, mlPerKgLow: 75, mlPerKgHigh: 80 }, { group: 'Child', fromMonths: 12, toMonths: null, mlPerKgLow: 70, mlPerKgHigh: 75 }];
  const child = R.peds.bloodVolume(20, 60, rows);
  eq(child.row.group, 'Child'); eq(child.low, 1400);
});
test('doses and rounding', () => {
  const la = R.peds.localAnestheticMax(2.5, 20, 0.25); eq(la.mg, 50); eq(la.mL, 20);
  eq(R.fmt(0.123), '0.12'); eq(R.fmt(2.25), '2.3'); eq(R.fmt(12.6), '13'); eq(R.fmt(18), '18');
  const capped = R.peds.doseText(0.01, null, 'mg', 120, null, 1); eq(capped.text, '1 mg'); eq(capped.capped, true);
  const range = R.peds.doseText(2, 3, 'mg', 18, null, null); eq(range.text, '36–54 mg'); eq(range.capped, false);
  const floored = R.peds.doseText(20, null, 'mcg', 3, 100, 500); eq(floored.text, '100 mcg'); eq(floored.capped, true);
  eq(R.range(70, 70), '70'); eq(R.range(70, 75), '70–75');
});

// ---------- local anesthetics ----------
const lidocaine = { id: 'lidocaine', name: 'Lidocaine', maxMgPerKg: 4.5, concentrations: [1, 2], kind: 'amide', adultPlainMgPerKg: 4.5, adultPlainMaxMg: 300, adultEpiMgPerKg: 7, adultEpiMaxMg: 500, pedsEpiMgPerKg: 7 };
const bupivacaine = { id: 'bupivacaine', name: 'Bupivacaine', maxMgPerKg: 2.5, concentrations: [0.25, 0.5], kind: 'amide', adultPlainMgPerKg: 2.5, adultPlainMaxMg: 175, adultEpiMaxMg: 225, per24hMaxMg: 400 };
const exparel = { id: 'exparel', name: 'Exparel', maxMgPerKg: 4, concentrations: [1.33], kind: 'liposomal', adultPlainMaxMg: 266, pedsMinYears: 6, pedsMaxMg: 266 };
test('local anesthetic maxima', () => {
  eq(R.la.maxMg(lidocaine, 70, false, false, null), 300);
  eq(R.la.maxMg(lidocaine, 70, false, true, null), 490);
  eq(R.la.maxMg(bupivacaine, 70, false, true, null), 175);
  eq(R.la.maxMg(bupivacaine, 20, true, false, 5), 50);
  eq(R.la.maxMg(lidocaine, 20, true, true, 5), 140);
  eq(R.la.maxMg(lidocaine, 20, true, false, 5), 90);
  eq(R.la.maxMg(exparel, 20, true, false, 5), null);
  eq(R.la.maxMg(exparel, 20, true, false, 8), 80);
  eq(R.la.maxMg(exparel, 90, false, false, null), 266);
});
test('mixture adds fractions', () => {
  const agents = [lidocaine, bupivacaine, exparel];
  const r = R.la.evaluate([{ id: 'a', agentID: 'bupivacaine', percent: 0.5, mL: 20 }, { id: 'b', agentID: 'lidocaine', percent: 1, mL: 15 }], agents, 70, false, false, null);
  eq(r.agents[0].mg, 100); eq(r.agents[1].mg, 150);
  near(r.combined, 100 / 175 + 150 / 300, 0.0001);
  eq(r.percentUsed, 107);
  assert.ok(r.warnings.some((w) => w.includes('exceeds the combined maximum')));
  near(r.agents[0].maxMLAlone, 35, 0.001);
  near(r.agents[0].remainingML, 0, 0.001);
  const half = R.la.evaluate([{ id: 'c', agentID: 'lidocaine', percent: 1, mL: 15 }], agents, 70, false, false, null);
  near(half.agents[0].remainingML, 15, 0.001);
});
test('Exparel rules', () => {
  const agents = [lidocaine, bupivacaine, exparel];
  const ratio = R.la.evaluate([{ id: 'a', agentID: 'exparel', percent: 1.33, mL: 20 }, { id: 'b', agentID: 'bupivacaine', percent: 0.5, mL: 30 }], agents, 80, false, false, null);
  assert.ok(ratio.warnings.some((w) => w.includes('1:2')));
  const fine = R.la.evaluate([{ id: 'a', agentID: 'exparel', percent: 1.33, mL: 20 }, { id: 'b', agentID: 'bupivacaine', percent: 0.5, mL: 20 }], agents, 80, false, false, null);
  assert.ok(!fine.warnings.some((w) => w.includes('1:2')));
  const lido = R.la.evaluate([{ id: 'a', agentID: 'exparel', percent: 1.33, mL: 10 }, { id: 'b', agentID: 'lidocaine', percent: 1, mL: 10 }], agents, 80, false, false, null);
  assert.ok(lido.warnings.some((w) => w.includes('20 minutes')));
});

// ---------- infusions ----------
test('infusion lines', () => {
  const norepi = { form: 'perKgPerMin', start: 0.05, startHigh: 0.1, unit: 'mcg' };
  const a = R.infusionLines(norepi, 70); eq(a.dose, '0.05–0.1 mcg/kg/min'); eq(a.equivalent, '3.5–7 mcg/min at 70 kg');
  eq(R.infusionLines(norepi, null).equivalent, null);
  const b = R.infusionLines({ form: 'perMin', start: 5, unit: 'mcg' }, 100); eq(b.dose, '5 mcg/min'); eq(b.equivalent, '0.05 mcg/kg/min at 100 kg');
  const c = R.infusionLines({ form: 'perKg', start: 30, unit: 'mg' }, 70); eq(c.dose, '30 mg/kg'); eq(c.equivalent, '2.1 g at 70 kg');
  eq(R.total(1500, null, 'mcg'), '1.5 mg'); eq(R.total(250, 500, 'mg'), '250–500 mg');
  eq(R.infusionLines({ form: 'perKgPerMin', start: 50, startHigh: 150, unit: 'mcg' }, 70).equivalent, '3.5–11 mg/min at 70 kg');
  eq(R.infusionLines({ form: 'perKgPerMin', start: 20, unit: 'ng' }, 70).equivalent, '1.4 mcg/min at 70 kg');
  const vaso = R.infusionLines({ form: 'fixed', start: 0.03, unit: 'units/min' }, 70); eq(vaso.dose, '0.03 units/min'); eq(vaso.equivalent, null);
});
test('infusion tabs as reviewed', () => {
  const inf = bundle.infusions;
  const tabs = []; for (const g of inf.groups) { const t = g.tab || g.name; if (!tabs.includes(t)) tabs.push(t); }
  eq(tabs, ['Hemodynamic', 'Single-Dose', 'Anesthetic', 'Blood Products', 'Hematologic']);
  const all = inf.groups.flatMap((g) => g.drugs);
  const norepi = all.find((d) => d.id === 'norepinephrine');
  eq(R.infusionLines(norepi, 80).dose, '4–8 mcg/min');
  eq(R.infusionLines(norepi, 80).equivalent, '0.05–0.1 mcg/kg/min at 80 kg');
  const cryo = all.find((d) => d.id === 'cryoprecipitate');
  eq(R.infusionLines(cryo, 70).equivalent, '7–10 units at 70 kg');
  eq(R.nameParts(norepi.name), { main: 'Norepinephrine', alias: 'Levophed' });
  eq(R.nameParts(all.find((d) => d.id === 'dobutamine').name).alias, null);
  for (const d of all) { assert.ok(R.infusionLines(d, null).dose, d.id); assert.ok(R.infusionLines(d, 70).dose, d.id); }
});

// ---------- title case ----------
test('title case', () => {
  eq(R.titleCase('Blocks on anticoagulants'), 'Blocks on Anticoagulants');
  eq(R.titleCase('Recognize it'), 'Recognize It');
  eq(R.titleCase('Aortic stenosis: low-gradient states'), 'Aortic Stenosis: Low-Gradient States');
  eq(R.titleCase('Cardiac risk for non-cardiac surgery'), 'Cardiac Risk for Non-cardiac Surgery');
  eq(R.titleCase('Doses in mg/kg'), 'Doses in mg/kg');
  eq(R.titleCase('5-HT₃ antagonist'), '5-HT₃ Antagonist');
  eq(R.titleCase('STOP-Bang and the ASA'), 'STOP-Bang and the ASA');
  eq(R.titleCase('a plan for the airway'), 'A Plan for the Airway');
  eq(R.titleCase('Severe, high-gradient AS'), 'Severe, High-Gradient AS');
  eq(R.titleCase('Local Anesthetic Systemic Toxicity (LAST)'), 'Local Anesthetic Systemic Toxicity (LAST)');
});

// ---------- PONV ----------
test('PONV plan', () => {
  const p = bundle.ponv;
  eq(R.ponv.target(0, p.counts).agents, 2); eq(R.ponv.target(2, p.counts).agents, 2);
  eq(R.ponv.target(3, p.counts).agents, 3); eq(R.ponv.target(4, p.counts).agentsHigh, 4);
  eq(R.ponv.classes(new Set(['ondansetron', 'granisetron', 'dexamethasone']), p.agents), ['5-HT₃ antagonist', 'Corticosteroid']);
  const rescue = R.ponv.rescueOptions(new Set(['ondansetron', 'dexamethasone']), p.agents).map((a) => a.id);
  assert.ok(!rescue.includes('ondansetron')); assert.ok(!rescue.includes('granisetron'));
  assert.ok(rescue.includes('amisulpride')); assert.ok(rescue.includes('propofol'));
  eq(R.ponv.longActingGiven(new Set(['palonosetron', 'dexamethasone']), p.agents).map((a) => a.id), ['palonosetron']);
});

// ---------- neuraxial ----------
test('neuraxial timing', () => {
  const last = 1700000000 * 1000;
  const a = R.neuraxialAnswer({ holdHours: 72, restartHours: 24 }, null, false, last);
  eq(a.earliest, last + 72 * 3600000); eq(a.rule, '3 days after the last dose'); eq(a.avoid, false);
  const dabi = { holdHours: 72, renal: [{ label: 'CrCl 50 or more', hours: 72 }, { label: 'CrCl 30–49', hours: 120 }, { label: 'CrCl below 30', hours: null, text: 'Avoid' }] };
  eq(R.neuraxialAnswer(dabi, 1, false, last).hours, 120);
  eq(R.neuraxialAnswer(dabi, 1, false, last).rule, '5 days after the last dose (CrCl 30–49)');
  eq(R.softLower('Normal renal function'), 'normal renal function');
  const avoid = R.neuraxialAnswer(dabi, 2, false, last); eq(avoid.avoid, true); eq(avoid.earliest, null);
  const fonda = { holdHours: 36, renal: [{ label: 'Normal', hours: 36, elderlyHours: 42 }] };
  eq(R.neuraxialAnswer(fonda, 0, true, last).hours, 42); eq(R.neuraxialAnswer(fonda, 0, false, last).hours, 36);
  eq(R.fmtHours(168), '7 days'); eq(R.fmtHours(36), '36 h');
  eq(R.countdown(last + (3600 * 26 + 300) * 1000, last), 'in 1 d 2 h');
  eq(R.countdown(last, last + 10000), 'now');
});

// ---------- valves ----------
const valve = (l, n, s) => R.valveRead(l, { numbers: n || {}, signs: new Set(s || []) });
test('valve param bands', () => {
  const vc = R.valveParams('mr').find((p) => p.id === 'vc');
  eq(R.valveGrade(vc, 0.2), 1); eq(R.valveGrade(vc, 0.5), 2); eq(R.valveGrade(vc, 0.7), 3);
  const ava = R.valveParams('as').find((p) => p.id === 'ava');
  eq(R.valveGrade(ava, 1.6), 1); eq(R.valveGrade(ava, 1.2), 2); eq(R.valveGrade(ava, 0.8), 3);
  const jet = R.valveParams('tr').find((p) => p.id === 'jet');
  eq(R.valveGrade(jet, 6), null); eq(R.valveGrade(jet, 12), 3);
});
test('aortic stenosis pathways', () => {
  eq(valve('as').overall, null);
  eq(valve('as', { vmax: 4.2, mg: 45, ava: 0.8 }).overall, 3);
  eq(valve('as', { vmax: 4.1, ava: 1.3 }).overall, 3);
  assert.ok(valve('as', { vmax: 4.1, ava: 1.3 }).cautions.length > 0);
  eq(valve('as', { vmax: 3.4, mg: 28, ava: 1.2 }).overall, 2);
  eq(valve('as', { vmax: 2.8, mg: 15, ava: 1.7 }).overall, 1);
  eq(valve('as', { vmax: 2.3 }).headline, 'Aortic sclerosis');
  const lg = valve('as', { vmax: 3.2, mg: 25, ava: 0.9 }); eq(lg.overall, null); assert.ok(lg.explanation.includes('stroke volume index'));
  eq(valve('as', { mg: 25, ava: 0.9, svi: 40 }).overall, 2);
  assert.ok(valve('as', { mg: 25, ava: 0.9, svi: 30, lvef: 35 }).headline.includes('reduced EF'));
  assert.ok(valve('as', { mg: 25, ava: 0.9, svi: 30, lvef: 60 }).headline.includes('Paradoxical'));
});
test('mitral regurgitation integration', () => {
  eq(valve('mr').overall, null);
  eq(valve('mr', { vc: 0.8, pisa: 1.1 }, ['flail', 'pvrev']).headline, 'Definitely severe MR');
  eq(valve('mr', { vc: 0.2, pisa: 0.2 }, ['smalljet', 'awave']).headline, 'Definitely mild MR');
  eq(valve('mr', { eroa: 0.45 }).overall, 3);
  eq(valve('mr', { eroa: 0.25, rvol: 40 }).overall, 2);
  eq(valve('mr', { eroa: 0.15 }).overall, 1);
  eq(valve('mr', { eroa: 0.35 }).overall, 2);
  eq(valve('mr', { eroa: 0.35 }, ['secondary']).overall, 3);
  eq(valve('mr', { eroa: 0.35, vc: 0.8 }, ['flail', 'pvrev']).overall, 3);
  eq(valve('mr', { eroa: 0.45, vc: 0.2 }, ['smalljet']).overall, null);
  eq(valve('mr', {}, ['flail', 'bigjet']).overall, 3);
  assert.ok(valve('mr', {}, ['flail', 'bigjet']).headline.includes('quantify'));
  assert.ok(valve('mr', { eroa: 0.3 }, ['nonholo']).cautions.length > 0);
});
test('mitral stenosis', () => {
  eq(valve('ms', { mva: 1.2 }).overall, 3); eq(valve('ms', { pht: 160 }).overall, 3);
  eq(valve('ms', { mva: 2.0, pht: 120 }).overall, 2); eq(valve('ms', { mva: 2.8, pht: 80 }).overall, 1);
  eq(valve('ms', { mg: 12 }).overall, null);
  assert.ok(valve('ms', { mva: 2.0, mg: 12 }).cautions[0].includes('severe range'));
});
test('aortic and tricuspid regurgitation', () => {
  eq(valve('ar', { vc: 0.7 }, ['holo']).overall, 3);
  eq(valve('ar', { rvol: 65, rf: 55, eroa: 0.35 }).overall, 3);
  eq(valve('ar', { rvol: 40, pht: 350 }).overall, 2);
  eq(valve('ar', {}, ['faint']).overall, 1);
  eq(valve('ar', { pht: 600 }).overall, 1);
  eq(valve('ar', { rvol: 65, vc: 0.2 }).overall, null);
  eq(valve('tr', { vc: 0.8 }, ['hvrev']).overall, 3);
  eq(valve('tr', { eroa: 0.45 }).overall, 3);
  eq(valve('tr', { vc: 0.5, jet: 6 }).overall, 2);
  assert.ok(valve('tr', { jet: 6 }).lines.some((l) => l.id === 'jet' && l.grade === null));
  eq(valve('tr', {}, ['dilated']).overall, 2);
});

// ---------- valve intervention ----------
const vi = (l, a) => R.viEvaluate(l, a);
const ids = (r) => r.matched.map((x) => x.id);
test('intervention rules refer to real questions', () => {
  for (const l of R.viLesions.map((x) => x.id)) {
    const qs = R.viQuestions(l), qids = new Set(qs.map((q) => q.id));
    eq(qids.size, qs.length, l + ' question ids unique');
    const rules = R.viRules(l);
    eq(new Set(rules.map((r) => r.id)).size, rules.length, l + ' rule ids unique');
    for (const r of rules) for (const conj of r.when) for (const c of conj) {
      const q = qs.find((x) => x.id === c.question);
      assert.ok(q, l + ' ' + r.id + ' unknown question ' + c.question);
      for (const v of c.any) assert.ok(q.options.includes(v), l + ' ' + r.id + ': ' + v + ' not an option of ' + q.id);
    }
  }
});
test('aortic stenosis intervention', () => {
  eq(vi('as', {}).fallback, null);
  assert.ok(vi('as', {}).needed.length > 0);
  const d1 = vi('as', { sev: 'Severe', sx: 'Yes' }); eq(d1.matched[0].id, 'as-d1'); assert.ok(d1.needed.includes('age'));
  eq(ids(vi('as', { sev: 'Severe', sx: 'Yes', age: '< 50', risk: 'Low', anticoag: 'Yes' })), ['as-d1', 'as-savr-age', 'pr-ao-young']);
  assert.ok(ids(vi('as', { sev: 'Severe', sx: 'Yes', age: '> 80', risk: 'Low', tf: 'Yes' })).includes('as-tavi-age'));
  assert.ok(ids(vi('as', { sev: 'Severe', sx: 'Yes', age: '50–64', risk: 'High or prohibitive', survival: 'Yes' })).includes('as-tavi-risk'));
  assert.ok(!ids(vi('as', { sev: 'Severe', sx: 'Yes', age: '50–64', risk: 'High or prohibitive', survival: 'Yes' })).includes('as-savr-age'));
  assert.ok(ids(vi('as', { sev: 'Severe', sx: 'Yes', survival: 'No' })).includes('as-pall'));
  eq(vi('as', { sev: 'Severe', sx: 'No', ef: '< 50%' }).matched[0].id, 'as-c2');
  eq(vi('as', { sev: 'Low-flow, low-gradient', sx: 'Yes', ef: '< 50%' }).matched[0].id, 'as-d2');
  eq(vi('as', { sev: 'Low-flow, low-gradient', sx: 'Yes', ef: '≥ 60%' }).matched[0].id, 'as-d3');
  eq(vi('as', { sev: 'Very severe', sx: 'No', risk: 'Low' }).matched[0].cls, '2a');
  eq(vi('as', { sev: 'Moderate', surg: 'Yes' }).matched[0].cls, '2b');
  const watch = vi('as', { sev: 'Moderate', sx: 'No', surg: 'No', ef: '≥ 60%', risk: 'Low', markers: 'No', effall: 'No' });
  eq(watch.matched.length, 0); assert.ok(watch.fallback && watch.fallback.includes('1–2 years'));
});
test('regurgitation and stenosis intervention', () => {
  eq(vi('ar', { sev: 'Severe', sx: 'Yes' }).matched[0].id, 'ar-d');
  eq(vi('ar', { sev: 'Severe', sx: 'No', ef: '≤ 55%' }).matched[0].id, 'ar-c2');
  eq(vi('ar', { sev: 'Severe', sx: 'No', ef: '> 60%', lvesd: 'Yes' }).matched[0].id, 'ar-c2-dim');
  eq(vi('ar', { sev: 'Severe', sx: 'No', ef: '> 60%', lvesd: 'No', risk: 'Low', lvedd: 'Yes' }).matched[0].id, 'ar-2b');
  assert.ok(ids(vi('ar', { sev: 'Severe', sx: 'Yes', candidate: 'Yes' })).includes('ar-tavi'));
  assert.ok(!ids(vi('ar', { sev: 'Moderate', sx: 'No', surg: 'No', candidate: 'Yes' })).includes('ar-tavi'));
  eq(vi('mrPrimary', { sev: 'Severe', sx: 'Yes' }).matched[0].id, 'mr-d');
  eq(vi('mrPrimary', { sev: 'Severe', sx: 'No', lvesd: 'Yes' }).matched[0].id, 'mr-c2');
  eq(vi('mrPrimary', { sev: 'Severe', sx: 'No', ef: '> 60%', lvesd: 'No', durable: 'Yes' }).matched[0].id, 'mr-c1');
  const teer = vi('mrPrimary', { sev: 'Severe', sx: 'Yes', nyha: 'III–IV', risk: 'High or prohibitive', anatomy: 'Yes', rheumatic: 'No' });
  eq(ids(teer).slice(0, 2), ['mr-d', 'mr-teer']); assert.ok(ids(teer).includes('mr-repair'));
  assert.ok(ids(vi('mrPrimary', { sev: 'Severe', sx: 'Yes', posterior: 'Yes' })).includes('mr-posterior'));
  eq(vi('mrSecondary', { sev: 'Severe', hf: 'Yes' }).matched[0].id, 'smr-gdmt');
  const smr = vi('mrSecondary', { sev: 'Severe', hf: 'Yes', gdmt: 'Yes', nyha: 'III–IV', ef: '20–49%', lvesd70: 'Yes', pasp70: 'Yes', anatomy: 'Yes' });
  assert.ok(ids(smr).includes('smr-teer')); assert.ok(ids(smr).includes('smr-surg')); eq(ids(smr)[0], 'smr-gdmt');
  eq(vi('mrSecondary', { sev: 'Severe', hf: 'No', gdmt: 'Yes', nyha: 'III–IV', ef: '≥ 50%', af: 'Yes' }).matched[0].id, 'smr-atrial');
  eq(vi('ms', { sev: 'Severe (MVA ≤ 1.5 cm²)', nyha: 'II', pmbc: 'Yes', calcific: 'No' }).matched[0].id, 'ms-pmbc');
  eq(vi('ms', { sev: 'Severe (MVA ≤ 1.5 cm²)', nyha: 'III–IV', pmbc: 'No', calcific: 'No', candidate: 'Yes' }).matched[0].id, 'ms-surg');
  eq(vi('ms', { sev: 'Severe (MVA ≤ 1.5 cm²)', nyha: 'III–IV', pmbc: 'No', calcific: 'No', candidate: 'No' }).matched[0].id, 'ms-highrisk');
  eq(vi('ms', { sev: 'Severe (MVA ≤ 1.5 cm²)', nyha: 'I', pasp: 'Yes', pmbc: 'Yes' }).matched[0].id, 'ms-pasp');
  eq(vi('ms', { sev: 'Not severe (MVA > 1.5 cm²)', nyha: 'II', exercise: 'Yes' }).matched[0].id, 'ms-ex');
  eq(vi('ms', { calcific: 'Yes', nyha: 'III–IV', sev: 'Severe (MVA ≤ 1.5 cm²)', pmbc: 'Yes' }).matched[0].id, 'ms-mac');
  eq(vi('tr', { sev: 'Severe', left: 'Yes' }).matched[0].id, 'tr-left');
  eq(vi('tr', { sev: 'Progressive (moderate)', left: 'Yes', annulus: 'Yes' }).matched[0].id, 'tr-prog');
  eq(vi('tr', { sev: 'Severe', cause: 'Primary (leaflet)', rhf: 'Yes', left: 'No' }).matched[0].id, 'tr-primary');
  eq(vi('tr', { sev: 'Severe', cause: 'Secondary (annular dilation)', rhf: 'Yes', left: 'No', ph: 'No', medical: 'Yes' }).matched[0].id, 'tr-secondary');
  eq(vi('tr', { sev: 'Severe', prior: 'Yes', rhf: 'Yes', severeph: 'No' }).matched[0].id, 'tr-redo');
  const trw = vi('tr', { sev: 'Progressive (moderate)', left: 'No', cause: 'Secondary (annular dilation)', rhf: 'No', prior: 'No' });
  eq(trw.matched.length, 0); assert.ok(trw.fallback);
});

// ---------- fasting ----------
test('fasting earliest start', () => {
  const t0 = Date.UTC(2026, 9, 29, 6, 0);
  const e = R.fasting.earliest({ clear: t0, light: t0 - 3600000 });
  eq(e.because.id, 'light'); eq(e.date, t0 - 3600000 + 6 * 3600000);
  eq(R.fasting.earliest({}), null);
});

// ---------- echo: grading rules on fixed examples, then the shipped values ----------
test('echo grading', () => {
  const lv = { dir: 'high', word: 'dilated', male: { normal: [42, 58.4], cuts: [58.4, 63, 68] } };
  eq([40, 50, 58.4, 58.5, 63, 63.1, 68, 70].map((v) => R.echo.grade(lv, 'male', v)), [-1, 0, 0, 1, 1, 2, 2, 3]);
  eq(R.echo.label(lv, 2), 'Moderately dilated');
  eq(R.echo.grade(lv, 'female', 60), null, 'no female values in this example');
  const ef = { dir: 'low', word: 'reduced', male: { normal: [52, 72], cuts: [52, 41, 30] } };
  eq([75, 60, 52, 51.5, 41, 40, 30, 29].map((v) => R.echo.grade(ef, 'male', v)), [-1, 0, 0, 1, 1, 2, 2, 3]);
  eq(R.echo.label(ef, -1), 'Above the normal range');
  const ta = { dir: 'high', edge: 'inclusive', word: 'dilated', all: { cuts: [40] } };
  eq([39.9, 40, 41].map((v) => R.echo.grade(ta, 'female', v)), [0, 4, 4]);
  eq(R.echo.label(ta, 4), 'Dilated');
  eq(R.echo.value({ index: 'bsa' }, '50', true, 2), 25);
  eq(R.echo.value({ index: 'bsa' }, '50', true, null), null);
  eq(R.echo.bands(ef, 'male').map((b) => b.grade), [3, 2, 1, 0, -1]);
  eq(R.echo.bands(lv, 'male').map((b) => b.grade), [-1, 0, 1, 2, 3]);
  near(R.bsa(175, 70), 1.848, 0.001); near(R.bsa(175, 70, 'mosteller'), 1.845, 0.001);
  eq(R.echo.rap(1.8, true).value, 3); eq(R.echo.rap(2.4, false).value, 15); eq(R.echo.rap(1.8, false).value, 8); eq(R.echo.rap(2.4, true).value, 8);
});
test('echo: per-cut edges, ranges, indexed rows, age tables, ventilated RAP', () => {
  // ASE 2025 RV basal diameter: normal < 4.1, mild ≥ 4.1 to ≤ 4.4, moderate > 4.4 to ≤ 4.9, severe > 4.9
  const rvb = { dir: 'high', word: 'dilated', all: { cuts: [4.1, 4.4, 4.9] }, edges: ['inclusive', 'exclusive', 'exclusive'],
    indexed: { unit: 'cm/m²', all: { cuts: [2.4, 2.6, 2.9] }, edges: ['inclusive', 'exclusive', 'exclusive'] } };
  eq([4.0, 4.1, 4.4, 4.41, 4.9, 4.91].map((v) => R.echo.grade(rvb, 'male', v)), [0, 1, 1, 2, 2, 3]);
  eq(R.echo.ranges(rvb, 'male').map((x) => x.text).join(' · '), 'Normal < 4.1 · mild ≤ 4.4 · moderate ≤ 4.9 · severe > 4.9');
  const ix = R.echo.indexed(rvb);
  eq([ix.unit, R.echo.grade(ix, 'female', 2.4), R.echo.grade(ix, 'female', 2.39)], ['cm/m²', 1, 0]);
  // TAPSE: normal > 1.7, mild ≤ 1.7 to > 1.3, moderate ≤ 1.3 to > 1.0, severe ≤ 1.0
  const tapse = { dir: 'low', word: 'reduced', all: { cuts: [1.7, 1.3, 1.0] }, edges: ['inclusive', 'inclusive', 'inclusive'] };
  eq([1.8, 1.7, 1.31, 1.3, 1.01, 1.0].map((v) => R.echo.grade(tapse, 'male', v)), [0, 1, 1, 2, 2, 3]);
  eq(R.echo.ranges(tapse, 'male').map((x) => x.text).join(' · '), 'Normal > 1.7 · mild > 1.3 · moderate > 1 · severe ≤ 1');
  // 3D RVEF: moderate ≤ 39 to ≥ 32, severe < 32
  const rvef = { dir: 'low', word: 'reduced', all: { cuts: [45, 39, 32] }, edges: ['inclusive', 'inclusive', 'exclusive'] };
  eq([46, 45, 39, 32, 31.9].map((v) => R.echo.grade(rvef, 'male', v)), [0, 1, 2, 2, 3]);
  eq(R.echo.ranges(rvef, 'male').map((x) => x.text).join(' · '), 'Normal > 45 · mild > 39 · moderate ≥ 32 · severe < 32');
  // Lang 2015 LVEF (printed integers): normal 52–72, mild 41–51, moderate 30–40, severe < 30
  const ef = { dir: 'low', word: 'reduced', male: { normal: [52, 72], cuts: [52, 41, 30] } };
  eq(R.echo.ranges(ef, 'male').map((x) => x.text).join(' · '), 'Normal 52–72 · mild ≥ 41 · moderate ≥ 30 · severe < 30');
  const lvidd = { dir: 'high', word: 'dilated', male: { normal: [42, 58.4], cuts: [58.4] } };
  eq(R.echo.ranges(lvidd, 'male').map((x) => x.text).join(' · '), 'Normal 42–58.4 · dilated > 58.4');
  const ta = { dir: 'high', edge: 'inclusive', word: 'dilated', all: { cuts: [40] }, indexed: { unit: 'mm/m²', all: { cuts: [21] } } };
  eq(R.echo.ranges(ta, 'male').map((x) => x.text).join(' · '), 'Normal < 40 · dilated ≥ 40');
  eq(R.echo.ranges(R.echo.indexed(ta), 'male').map((x) => x.text).join(' · '), 'Normal ≤ 21 · dilated > 21', 'the indexed cut keeps its own edge');
  eq(R.echo.bands(ta, 'male').map((b) => [b.from, b.to, b.grade]), [[30, 40, 0], [40, 50, 4]]);
  const bb = R.echo.bands(rvb, 'male');
  near(bb[0].from, 3.3, 1e-9); eq(bb.map((b) => b.grade), [0, 1, 2, 3]);
  const tb = R.echo.bands(tapse, 'male');
  near(tb[tb.length - 1].to, 2.4, 1e-9); eq(tb.map((b) => b.grade), [3, 2, 1, 0]);
  // strain is tabulated as magnitude
  eq(R.echo.value({ abs: true }, '-22', false, null), 22);
  eq(R.echo.value({}, '-22', false, null), null);
  // Goldstein 2015 aortic sinuses: men 50–59 4.0 cm at BSA 2.0, ± 0.5 mm per 0.1 m²; z ≥ 2 is dilated
  const sov = { dir: 'high', edge: 'inclusive', word: 'dilated', byAge: { perM2: 0.5,
    male: { refBsa: 2.0, rows: [{ from: 15, to: 29, uln: 3.7 }, { from: 50, to: 59, uln: 4.0 }, { from: 70, uln: 4.2 }] },
    female: { refBsa: 1.7, rows: [{ from: 50, to: 59, uln: 3.6 }] } } };
  eq(R.echo.ageLimit(sov, 'male', { age: 55, bsa: 2.2 }).value, 4.1);
  eq(R.echo.ageLimit(sov, 'male', { age: 55 }).value, 4.0, 'no BSA: the reference-BSA limit');
  eq(R.echo.ageLimit(sov, 'female', { age: 59.9, bsa: 1.5 }).value, 3.5);
  eq(R.echo.ageLimit(sov, 'male', { age: 88, bsa: 2.0 }).value, 4.2, 'open-ended top band');
  eq(R.echo.ageLimit(sov, 'male', { age: 12, bsa: 2.0 }), null, 'the adult tables start at 15');
  eq([4.05, 4.1].map((v) => R.echo.grade(sov, 'male', v, { age: 55, bsa: 2.2 })), [0, 4]);
  eq(R.echo.grade(sov, 'male', 4.1), null, 'no age, no grade');
  // RA pressure from the IVC
  eq(R.echo.rap(2.4, null, 2.1, true).label, 'Not estimable');
  eq(R.echo.rap(1.9, null, 2.1, true).label, 'Likely below 10 mmHg');
  eq(R.echo.rap(1.9, null, 2.1, false), null, 'spontaneous breathing needs the sniff');
  eq(R.echo.fmt(58.4), '58.4'); eq(R.echo.fmt(3.85000001), '3.85'); eq(R.echo.fmt(145.26), '145.3');
});
test('echo values in reference.json', () => {
  const e = bundle.echo;
  if (!e) return;
  const ids = new Set();
  const ctx = { age: 50, bsa: 1.9 };
  const find = (id) => e.groups.flatMap((g) => g.measures).find((m) => m.id === id);
  for (const g of e.groups) for (const m of g.measures) {
    assert.ok(!ids.has(m.id), 'duplicate ' + m.id); ids.add(m.id);
    for (const row of [m, R.echo.indexed(m)].filter(Boolean)) for (const sex of ['male', 'female']) {
      const r = R.echo.ref(row, sex, ctx);
      assert.ok(r, m.id + ' has values for ' + sex);
      const b = R.echo.bands(row, sex, ctx);
      assert.ok(b.length >= 2, m.id + ' draws bands');
      for (let i = 1; i < b.length; i++) assert.ok(Math.abs(b[i].from - b[i - 1].to) < 1e-9, m.id + ' bands are contiguous');
      assert.ok(R.echo.ranges(row, sex, ctx).length >= 2, m.id + ' states its ranges');
    }
  }
  // spot checks against the printed tables
  const gr = (id, sex, v, c) => R.echo.grade(find(id), sex, v, c);
  eq([4.0, 4.1, 4.4, 4.45, 4.9, 4.95].map((v) => gr('rvb', 'male', v)), [0, 1, 1, 2, 2, 3], 'ASE 2025 RV basal diameter');
  eq([1.75, 1.7, 1.3, 1.0].map((v) => gr('tapse', 'female', v)), [0, 1, 2, 3], 'ASE 2025 TAPSE');
  eq([34, 34.5, 41, 48, 48.5].map((v) => gr('lavi', 'male', v)), [0, 1, 1, 2, 3], 'Lang 2015 LA volume index');
  eq([54, 53, 41, 40, 29].map((v) => gr('lvef', 'female', v)), [0, 1, 1, 2, 3], 'Lang 2015 LVEF, women');
  eq([39, 40].map((v) => gr('ta', 'male', v)), [0, 4], 'tricuspid annulus ≥ 40 mm');
  eq([21, 21.5].map((v) => R.echo.grade(R.echo.indexed(find('ta')), 'male', v)), [0, 4], 'tricuspid annulus > 21 mm/m²');
  eq(R.echo.ageLimit(find('sov'), 'female', { age: 45, bsa: 1.7 }).value, 3.6, 'Goldstein 2015 women 40–49');
});

// ---------- ASE 2025 diastolic function ----------
const dd = (i) => R.diastolic(i);
test('diastolic: the main algorithm (Figure 3)', () => {
  // all normal
  let r = dd({ E: 80, A: 60, eSeptal: 9, eLateral: 12, tr: 2.3 });
  eq([r.lap, r.grade], ['normal', 0]);
  // all abnormal: grade by E/A
  r = dd({ E: 100, A: 80, eSeptal: 5, eLateral: 6, tr: 3.0 });
  eq([r.lap, r.grade], ['increased', 2], 'E/A 1.25 → Grade 2');
  r = dd({ E: 120, A: 50, eSeptal: 5, eLateral: 6, tr: 3.0 });
  eq([r.lap, r.grade], ['increased', 3], 'E/A 2.4 → Grade 3');
  // e′ only, E/A ≤ 0.8 → Grade 1
  r = dd({ E: 50, A: 80, eSeptal: 5, eLateral: 6.5, tr: 2.2 });
  eq([r.lap, r.grade], ['normal', 1]);
  // e′ only, E/A > 0.8 → supplemental; none present → normal LAP without grade
  r = dd({ E: 70, A: 70, eSeptal: 5, eLateral: 6.5, tr: 2.2, lars: 30, lavi: 28 });
  eq([r.lap, r.grade], ['normal', null]);
  assert.ok(r.explanation.includes('no grade'));
  // e′ only, E/A > 0.8, LARS ≤ 18 → increased LAP, grade by E/A
  r = dd({ E: 70, A: 70, eSeptal: 5, eLateral: 6.5, tr: 2.2, lars: 16 });
  eq([r.lap, r.grade], ['increased', 2]);
  // TR only abnormal → supplemental; LAVi 40 → increased
  r = dd({ E: 80, A: 60, eSeptal: 9, eLateral: 12, tr: 3.0, lavi: 40 });
  eq([r.lap, r.grade], ['increased', 2]);
  // two abnormal, supplemental negative → normal LAP
  r = dd({ E: 90, A: 70, eSeptal: 5, eLateral: 6, tr: 2.2, pvsd: 1.2, lars: 25 });
  eq(r.lap, 'normal', 'e′ and E/e′ abnormal, S/D and LARS normal');
  // PASP is preferred over TR when entered
  r = dd({ E: 80, A: 60, eSeptal: 9, eLateral: 12, tr: 3.0, pasp: 30 });
  eq([r.lap, r.grade], ['normal', 0], 'PASP 30 overrides TR 3.0');
  // lung disease: TR/PASP not used → missing variable → supplemental
  r = dd({ E: 80, A: 60, eSeptal: 9, eLateral: 12, tr: 3.0, lungDisease: true });
  eq(r.lap, 'unknown');
  assert.ok(r.cautions.length > 0);
  // second-line signs when the supplemental four are missing
  r = dd({ E: 80, A: 60, eSeptal: 9, eLateral: 12, tr: 3.0, ara: 40 });
  eq(r.lap, 'lvedp', 'Ar − A alone is an LVEDP marker');
  r = dd({ E: 80, A: 60, eSeptal: 9, eLateral: 12, tr: 3.0, padp: 18 });
  eq([r.lap, r.grade], ['increased', 2]);
  // cutoffs: ≤ for e′, ≥ for E/e′ and TR
  eq(R.diastolicPrimaries({ eSeptal: 6, eLateral: 8 }).v1, true, 'septal 6 is reduced');
  eq(R.diastolicPrimaries({ eSeptal: 6.1, eLateral: 7.1 }).v1, false);
  eq(R.diastolicPrimaries({ E: 98, eSeptal: 7, eLateral: 7 }).v2, true, 'average E/e′ 14 counts (Figure 3: ≥ 14)');
  eq(R.diastolicPrimaries({ tr: 2.8 }).v3, true, 'TR 2.8 counts');
  // age-specific e′ (Table 6, strict <)
  eq(R.diastolicPrimaries({ eSeptal: 6.5, eLateral: 9.5, ageBand: '20-39' }).v1, true, 'septal 6.5 < 7 at 20–39 y');
  eq(R.diastolicPrimaries({ eSeptal: 6, eLateral: 7, ageBand: '>65' }).v1, false, 'strict < at > 65 y');
});
test('diastolic: presence (Figure 2), MAC (Figure 4) and transplant', () => {
  let pr = R.diastolicPresence({ E: 50, A: 80, eSeptal: 5, eLateral: 6 });
  eq(pr.state, true, 'reduced e′ with E/A ≤ 0.8');
  pr = R.diastolicPresence({ E: 80, A: 60, eSeptal: 9, eLateral: 12, lavi: 40 });
  eq(pr.state, false, 'normal e′ needs two markers');
  pr = R.diastolicPresence({ E: 80, A: 60, eSeptal: 9, eLateral: 12, lavi: 40, lars: 15 });
  eq(pr.state, true);
  eq(R.diastolicMAC({ E: 50, A: 80 }).lap, 'normal');
  eq(R.diastolicMAC({ E: 120, A: 60 }).lap, 'increased');
  eq(R.diastolicMAC({ E: 80, A: 80, ivrt: 90 }).lap, 'normal');
  eq(R.diastolicMAC({ E: 80, A: 80, ivrt: 70 }).lap, 'increased');
  eq(R.diastolicMAC({ E: 80, A: 80 }).lap, 'unknown');
  eq(R.diastolicTransplant({ E: 60, eSeptal: 10, eLateral: 12 }).lap, 'normal', 'E/e′ 5.5');
  eq(R.diastolicTransplant({ E: 120, eSeptal: 7, eLateral: 8 }).lap, 'increased', 'E/e′ 16');
  eq(R.diastolicTransplant({ E: 100, eSeptal: 9, eLateral: 11, esr: 250 }).lap, 'increased', 'E/e′ 10, E/SRIVR 250');
  eq(R.diastolicTransplant({ E: 100, eSeptal: 9, eLateral: 11, tr: 2.5 }).lap, 'normal', 'E/e′ 10, no SRIVR, TR 2.5');
});

// ---------- ACLS code timer ----------
const ACLS = {
  cycleSec: 120,
  actions: {
    vf: { label: 'VF / pVT', kind: 'rhythm', rhythm: 'shockable', cycleReset: true, log: 'Rhythm: VF/pVT' },
    nonsh: { label: 'Asystole / PEA', kind: 'rhythm', rhythm: 'nonshockable', cycleReset: true, log: 'Rhythm: asystole/PEA' },
    rosc: { label: 'ROSC', kind: 'rhythm', rhythm: 'rosc', log: 'ROSC', goto: 'rosc' },
    shock: { label: 'Shock', kind: 'shock', adult: { text: 'device dose' }, child: { perKgSeq: [2, 4], thenPerKg: 4, thenAtLeast: true, maxPerKg: 10 } },
    epi: { label: 'Epinephrine', kind: 'drug', adult: { dose: 1, unit: 'mg', route: 'IV/IO' }, child: { perKg: 0.01, unit: 'mg', max: 1, route: 'IV/IO', conc: { value: 0.1, unit: 'mg/mL' } }, repeat: { min: 180, max: 300 } },
    amio: { label: 'Amiodarone', kind: 'drug', adult: { unit: 'mg', route: 'IV/IO', doses: [{ dose: 300 }, { dose: 150 }], maxDoses: 2 }, child: { perKg: 5, unit: 'mg', max: 300, route: 'IV/IO', maxDoses: 3 } },
    cpr: { label: 'CPR started', kind: 'event', cycleReset: true, log: 'CPR started' },
    reopen: { label: 'Resternotomy', kind: 'event' },
  },
  modes: [
    { id: 'arrest', name: 'Cardiac arrest', short: 'Arrest', cycle: true, prompts: [
      { id: 'shock-now', level: 'now', alert: true, action: 'shock', text: 'Shock now: {energy:shock}', when: [{ rhythm: 'shockable' }, { countSince: ['shock', 'vf', '==', 0] }] },
      { id: 'epi-ns', level: 'now', alert: true, action: 'epi', text: 'Epi {dose:epi}', when: [{ rhythm: 'nonshockable' }, { count: ['epi', '==', 0] }] },
      { id: 'epi-s', level: 'now', alert: true, action: 'epi', text: 'Epi after shock 2: {dose:epi}', when: [{ rhythm: 'shockable' }, { count: ['shock', '>=', 2] }, { count: ['epi', '==', 0] }] },
      { id: 'epi-due', level: 'now', alert: true, action: 'epi', text: 'Epi due', when: [{ count: ['epi', '>=', 1] }, { since: ['epi', '>=', 180] }] },
      { id: 'anti', level: 'now', action: 'amio', text: 'Amio {dose:amio}', when: [{ rhythm: 'shockable' }, { count: ['shock', '>=', 3] }, { notAny: ['amio'] }] },
      { id: 'child-only', patient: 'child', level: 'info', text: 'Child note', when: [] },
    ] },
    { id: 'cals', name: 'After cardiac surgery', short: 'CALS', deadlines: [{ id: 'reopen', label: 'Resternotomy', sec: 300, until: 'reopen' }] },
    { id: 'brady', name: 'Bradycardia', short: 'Brady', tree: { adult: { start: 'q', nodes: { q: { q: 'Poor perfusion?', options: [{ label: 'Yes', next: 'y' }, { label: 'No', next: 'n' }] }, y: { text: 'Atropine', actions: ['epi'] }, n: { text: 'Observe' } } } } },
  ],
};
test('acls: clock, log, counts and doses', () => {
  const A = R.acls;
  eq([A.clock(0), A.clock(75000), A.clock(3725000), A.clock(-5000)], ['0:00', '1:15', '1:02:05', '-0:05']);
  const s = A.session(1000, 'arrest', 'adult');
  A.add(s, 30000, 'epi', 'Epinephrine 1 mg');
  A.add(s, 10000, 'cpr', 'CPR started');
  eq(s.log.map((e) => e.id), ['cpr', 'epi'], 'kept in time order');
  eq([A.count(s, 'epi'), A.last(s, 'epi'), A.last(s, 'amio')], [1, 30000, null]);
  eq(A.dose(ACLS.actions.epi, s, 0).text, '1 mg IV/IO');
  eq(A.dose(ACLS.actions.amio, s, 0).text, '300 mg IV/IO');
  eq(A.dose(ACLS.actions.amio, s, 1).text, '150 mg IV/IO', 'second amiodarone dose');
  eq(A.maxDoses(ACLS.actions.amio, s), 2);
  const c = A.session(0, 'arrest', 'child');
  eq(A.dose(ACLS.actions.epi, c, 0).text, '0.01 mg/kg IV/IO (max 1 mg)', 'no weight yet');
  c.weight = 18;
  eq(A.dose(ACLS.actions.epi, c, 0).text, '0.18 mg IV/IO · 1.8 mL of 0.1 mg/mL (0.01 mg/kg)');
  c.weight = 120;
  eq(A.dose(ACLS.actions.epi, c, 0).text, '1 mg IV/IO · 10 mL of 0.1 mg/mL (the maximum)', 'capped at 1 mg');
  c.weight = 18;
  eq(A.dose(ACLS.actions.amio, c, 0).text, '90 mg IV/IO (5 mg/kg)');
  eq([0, 1, 2].map((n) => A.energy(ACLS.actions.shock, c, n).text), ['36 J (2 J/kg)', '72 J (4 J/kg)', '≥ 72 J (4 J/kg), up to 180 J']);
  eq(A.entryText(ACLS.actions.shock, c, 1), 'Shock 2: 72 J');
  eq(A.entryText(ACLS.actions.shock, s, 0, 200), 'Shock 1: 200 J', 'the typed energy is logged');
  eq(A.entryText(ACLS.actions.epi, c, 1), 'Epinephrine 0.18 mg IV/IO (dose 2)');
  eq(A.round(0.1834), 0.18); eq(A.round(4.56), 4.6); eq(A.round(72.4), 72);
});
test('acls: cycle, prompts and timers follow the log', () => {
  const A = R.acls, s = A.session(0, 'arrest', 'adult'), ids = (t) => A.prompts(s, ACLS, t).map((p) => p.id);
  eq(A.cycle(s, ACLS, 90000).elapsed, 90, 'the first cycle runs from the start');
  A.add(s, 20000, 'cpr', 'CPR started');
  eq(A.cycle(s, ACLS, 90000).elapsed, 70, 'CPR started resets it');
  A.add(s, 140000, 'vf', 'Rhythm: VF/pVT');
  eq(ids(141000), ['shock-now']);
  A.add(s, 150000, 'shock', 'Shock 1');
  eq(ids(151000), [], 'shock given: nothing due');
  A.add(s, 260000, 'vf', 'Rhythm: VF/pVT');
  A.add(s, 265000, 'shock', 'Shock 2');
  eq(ids(266000), ['epi-s'], 'epinephrine after the second shock');
  A.add(s, 280000, 'epi', 'Epinephrine 1 mg');
  eq(A.timer(ACLS.actions.epi, s, 'epi', 400000).state, 'wait');
  near(A.timer(ACLS.actions.epi, s, 'epi', 400000).remaining, 60, 1e-9);
  eq(ids(460000), ['epi-due'], 'due 3 minutes after the last dose');
  eq(A.timer(ACLS.actions.epi, s, 'epi', 580000).state, 'overdue');
  A.add(s, 380000, 'vf', 'Rhythm: VF/pVT');
  A.add(s, 385000, 'shock', 'Shock 3');
  eq(ids(390000), ['anti']);
  eq(A.prompts(s, ACLS, 390000)[0].text, 'Amio 300 mg IV/IO');
  A.add(s, 395000, 'amio', 'Amiodarone 300 mg');
  eq(A.prompts(s, ACLS, 396000).length, 0);
  // removing the mistaken amiodarone brings the prompt back
  A.remove(s, s.log.find((e) => e.id === 'amio'));
  eq(ids(396000), ['anti']);
  // non-shockable: epinephrine as soon as possible, once
  const n = A.session(0, 'arrest', 'adult');
  A.add(n, 5000, 'nonsh', 'Rhythm: asystole/PEA');
  eq(A.prompts(n, ACLS, 6000).map((p) => [p.id, p.text]), [['epi-ns', 'Epi 1 mg IV/IO']]);
  eq(A.rhythm(n, ACLS), 'nonshockable');
  const c = A.session(0, 'arrest', 'child');
  eq(A.prompts(c, ACLS, 1000).map((p) => p.id), ['child-only'], 'a child prompt shows only for a child');
});
test('acls: deadlines, trees and the copied log', () => {
  const A = R.acls, s = A.session(0, 'cals', 'adult');
  eq(A.deadlines(s, ACLS, 60000).map((d) => [d.id, d.remaining]), [['reopen', 240]]);
  eq(A.deadlines(s, ACLS, 330000)[0].remaining, -30, 'negative once passed');
  A.add(s, 200000, 'reopen', 'Resternotomy');
  eq(A.deadlines(s, ACLS, 330000), [], 'done before the deadline: gone');
  const b = A.session(0, 'brady', 'adult');
  let tr = A.tree(b, ACLS);
  eq([tr.nodeId, tr.node.q], ['q', 'Poor perfusion?']);
  A.choose(b, ACLS, 5000, 'y', 'Yes');
  tr = A.tree(b, ACLS);
  eq([tr.nodeId, tr.path], ['y', ['y']]);
  eq(b.log.at(-1).text, 'Brady: Poor perfusion? Yes');
  A.back(b, ACLS);
  eq(A.tree(b, ACLS).nodeId, 'q');
  eq(A.tree(A.session(0, 'brady', 'child'), ACLS), null, 'no child tree in this example');
  const l = A.session(Date.UTC(2026, 9, 29, 12, 0, 0), 'arrest', 'child');
  l.weight = 18;
  A.add(l, 0, 'start', 'Code clock started');
  A.add(l, 75000, 'epi', 'Epinephrine 0.18 mg IV/IO');
  const wall = (ms) => new Date(ms).toISOString().slice(11, 19);
  eq(A.logText(l, wall), 'Code log (child, 18 kg), started 12:00:00\n12:00:00  +0:00  Code clock started\n12:01:15  +1:15  Epinephrine 0.18 mg IV/IO');
});

console.log(`${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
