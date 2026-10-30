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
test('intervention classes and levels of evidence', () => {
  const LOE = ['A', 'B-R', 'B-NR', 'C-LD', 'C-EO'];
  for (const l of R.viLesions.map((x) => x.id)) for (const r of R.viRules(l)) {
    assert.ok(LOE.includes(r.level), l + ' ' + r.id + ' level ' + r.level);
    assert.ok(R.viClassWord(r.cls), l + ' ' + r.id + ' class ' + r.cls);
  }
  const tavi = R.viRules('ar').find((r) => r.id === 'ar-tavi'), post = R.viRules('mrPrimary').find((r) => r.id === 'mr-posterior');
  eq([tavi.cls, tavi.level, R.viEvidence(tavi), R.viClassNumber(tavi.cls)], ['3: Harm', 'B-NR', '3: Harm, B-NR', '3']);
  eq([post.cls, post.level], ['3: Harm', 'B-NR']);
  eq(R.viClassWord('3: Harm'), 'Potentially harmful'); eq(R.viClassWord('3: No Benefit'), 'Not recommended');
  eq(R.viEvidence(R.viRules('as').find((r) => r.id === 'as-d1')), 'A');
  eq(R.viRules('as').find((r) => r.id === 'as-vs').level, 'B-R');
  const ex = R.viQuestions('as').find((q) => q.id === 'sx').hint;
  assert.ok(ex.includes('heart failure') && ex.includes('class 3: Harm, B-NR'), 'no exercise testing in symptomatic severe AS');
});
test('aortic stenosis intervention', () => {
  eq(vi('as', {}).fallback, null);
  assert.ok(vi('as', {}).needed.length > 0);
  const d1 = vi('as', { sev: 'Severe', sx: 'Yes' }); eq(d1.matched[0].id, 'as-d1'); assert.ok(d1.needed.includes('age'));
  eq(ids(vi('as', { sev: 'Severe', sx: 'Yes', age: '< 50', risk: 'Low', anticoag: 'Yes' })), ['as-d1', 'as-savr-age', 'pr-ao-young']);
  assert.ok(ids(vi('as', { sev: 'Severe', sx: 'Yes', age: '> 80', risk: 'Low', tf: 'Yes', surg: 'No' })).includes('as-tavi-age'));
  assert.ok(ids(vi('as', { sev: 'Severe', sx: 'Yes', age: '50–64', risk: 'High or prohibitive', survival: 'Yes' })).includes('as-tavi-risk'));
  assert.ok(!ids(vi('as', { sev: 'Severe', sx: 'Yes', age: '50–64', risk: 'High or prohibitive', survival: 'Yes' })).includes('as-savr-age'));
  assert.ok(ids(vi('as', { sev: 'Severe', sx: 'Yes', survival: 'No' })).includes('as-pall'));
  eq(vi('as', { sev: 'Severe', sx: 'No', ef: '< 50%' }).matched[0].id, 'as-c2');
  eq(vi('as', { sev: 'Low-flow, low-gradient', sx: 'Yes', ef: '< 50%' }).matched[0].id, 'as-d2');
  eq(vi('as', { sev: 'Low-flow, low-gradient', sx: 'Yes', ef: '≥ 60%' }).matched[0].id, 'as-d3');
  const vs = vi('as', { sev: 'Very severe', sx: 'No', risk: 'Low' }).matched[0];
  eq([vs.id, vs.cls, vs.level], ['as-vs', '2a', 'B-R']);
  eq(vi('as', { sev: 'Moderate', surg: 'Yes' }).matched[0].cls, '2b');
  const watch = vi('as', { sev: 'Moderate', sx: 'No', surg: 'No', ef: '≥ 60%', risk: 'Low', markers: 'No', effall: 'No' });
  eq(watch.matched.length, 0); assert.ok(watch.fallback && watch.fallback.includes('1–2 years'));
});
test('aortic stenosis: SAVR or TAVI for the patients the guideline names', () => {
  const sx70 = { sev: 'Severe', sx: 'Yes', age: '65–80', tf: 'Yes', risk: 'Low', surg: 'No' };
  assert.ok(ids(vi('as', sx70)).includes('as-either'));
  assert.ok(vi('as', Object.assign({}, sx70, { surg: undefined })).needed.includes('surg'), 'other cardiac surgery decides');
  assert.ok(!ids(vi('as', Object.assign({}, sx70, { surg: 'Yes' }))).includes('as-either'), 'not when operated for another indication');
  // asymptomatic: only recommendation 4 (LVEF < 50%, age ≤ 80), 1 B-NR
  const c2 = vi('as', { sev: 'Severe', sx: 'No', ef: '< 50%', age: '65–80', tf: 'Yes', risk: 'Low', surg: 'No' });
  assert.ok(!ids(c2).includes('as-either'));
  const r4 = c2.matched.find((r) => r.id === 'as-c2-either'); eq([r4.cls, r4.level, r4.group], ['1', 'B-NR', 'Which procedure']);
  const old = ids(vi('as', { sev: 'Severe', sx: 'No', ef: '< 50%', age: '> 80', tf: 'Yes', risk: 'Low', surg: 'No', survival: 'Yes' }));
  for (const x of ['as-tavi-age', 'as-tavi-risk', 'as-either', 'as-c2-either']) assert.ok(!old.includes(x), 'asymptomatic 84-year-old: no ' + x);
  const ex = ids(vi('as', { sev: 'Severe', sx: 'No', ef: '≥ 60%', markers: 'Yes', age: '65–80', tf: 'Yes', risk: 'Low', surg: 'No' }));
  assert.ok(ex.includes('as-savr-2a') && !ex.includes('as-either') && !ex.includes('as-c2-either'), 'a 2a indication: SAVR in preference to TAVI only');
  assert.ok(!ids(vi('as', { sev: 'Severe', sx: 'No', ef: '< 50%', markers: 'Yes', age: '65–80', tf: 'Yes', risk: 'Low', surg: 'No' })).includes('as-savr-2a'), 'LVEF < 50% is a class 1 indication');
  const hi = ids(vi('as', { sev: 'Very severe', sx: 'No', ef: '< 50%', risk: 'High or prohibitive', survival: 'Yes', surg: 'No' }));
  assert.ok(!hi.includes('as-tavi-risk') && !hi.includes('as-savr-2a'), 'asymptomatic at high risk: no TAVI 1 A');
  assert.ok(!ids(vi('as', { sev: 'Moderate', surg: 'Yes', sx: 'Yes', risk: 'High or prohibitive', survival: 'Yes' })).includes('as-tavi-risk'), 'moderate AS is not severe');
  // bicuspid valve with an aorta ≥ 4.5 cm (2a B-NR); complex coronary disease (2a C-LD)
  const bav = vi('as', { sev: 'Severe', sx: 'Yes', bicuspid: 'Yes', aorta: 'Yes', risk: 'Low', cad: 'Yes' });
  const ao = bav.matched.find((r) => r.id === 'as-aorta'), cabg = bav.matched.find((r) => r.id === 'as-cabg');
  eq([ao.cls, ao.level, cabg.cls, cabg.level], ['2a', 'B-NR', '2a', 'C-LD']);
  assert.ok(!ids(vi('as', { sev: 'Severe', sx: 'Yes', bicuspid: 'No', aorta: 'Yes', risk: 'Low' })).includes('as-aorta'));
  assert.ok(!ids(vi('as', { sev: 'Severe', sx: 'Yes', bicuspid: 'Yes', aorta: 'Yes', risk: 'High or prohibitive' })).includes('as-aorta'), 'with an indication for SAVR');
  assert.ok(!ids(vi('as', { sev: 'Moderate', surg: 'Yes', cad: 'Yes' })).includes('as-cabg'));
});
test('prosthesis choice', () => {
  const young = vi('as', { sev: 'Severe', sx: 'Yes', age: '< 50', risk: 'Low', anticoag: 'No' });
  assert.ok(ids(young).includes('pr-bio-any'));
  const ross = young.matched.find((r) => r.id === 'pr-ao-ross'); eq([ross.cls, ross.level], ['2b', 'B-NR']);
  assert.ok(!ids(vi('as', { sev: 'Severe', sx: 'Yes', age: '< 50', risk: 'Low', anticoag: 'Yes' })).includes('pr-ao-ross'), 'Ross: a bioprosthesis preferred');
  assert.ok(!R.viRules('as').find((r) => r.id === 'pr-ao-young').recommendation.includes('Ross'));
  assert.ok(ids(vi('ar', { sev: 'Severe', sx: 'Yes', age: '< 50', anticoag: 'No' })).includes('pr-ao-ross'));
  const old = vi('as', { sev: 'Severe', sx: 'Yes', age: '65–80', risk: 'Low', anticoag: 'Yes' }).matched.find((r) => r.id === 'pr-ao-old');
  assert.ok(old.note && old.note.includes('At age 65 the 50–65 band applies'));
  // mitral: only when repair is not possible
  const teer = vi('mrPrimary', { sev: 'Severe', sx: 'Yes', nyha: 'III–IV', risk: 'High or prohibitive', anatomy: 'Yes', rheumatic: 'No', age: '50–64', anticoag: 'Yes' });
  assert.ok(!ids(teer).some((x) => x.startsWith('pr-')) && teer.needed.includes('replace'));
  const base = { sev: 'Severe', sx: 'Yes', rheumatic: 'No' };
  assert.ok(!ids(vi('mrPrimary', Object.assign({ age: '50–64', anticoag: 'Yes', replace: 'No' }, base))).some((x) => x.startsWith('pr-')));
  assert.ok(!ids(vi('mrPrimary', Object.assign({ age: '65–80', anticoag: 'No', replace: 'No' }, base))).some((x) => x.startsWith('pr-')));
  assert.ok(ids(vi('mrPrimary', Object.assign({ age: '50–64', anticoag: 'Yes', replace: 'Yes' }, base))).includes('pr-mi-young'));
  const mo = ids(vi('mrPrimary', Object.assign({ age: '65–80', anticoag: 'No', replace: 'Yes' }, base)));
  assert.ok(mo.includes('pr-mi-old') && mo.includes('pr-bio-any'));
});
test('regurgitation and stenosis intervention', () => {
  eq(vi('ar', { sev: 'Severe', sx: 'Yes' }).matched[0].id, 'ar-d');
  eq(vi('ar', { sev: 'Severe', sx: 'No', ef: '≤ 55%' }).matched[0].id, 'ar-c2');
  eq(vi('ar', { sev: 'Severe', sx: 'No', ef: '> 60%', lvesd: 'Yes' }).matched[0].id, 'ar-c2-dim');
  eq(vi('ar', { sev: 'Severe', sx: 'No', ef: '56–60%', lvesd: 'Yes' }).matched[0].id, 'ar-c2-dim');
  eq(R.viQuestions('ar').find((q) => q.id === 'ef').options, ['> 60%', '56–60%', '≤ 55%'], 'an LVEF of 55% has one answer');
  const arAo = vi('ar', { sev: 'Severe', sx: 'Yes', bicuspid: 'Yes', aorta: 'Yes' }).matched.find((r) => r.id === 'ar-aorta');
  eq([arAo.cls, arAo.level], ['2a', 'B-NR']);
  eq(vi('ar', { sev: 'Severe', sx: 'No', ef: '> 60%', lvesd: 'No', risk: 'Low', lvedd: 'Yes' }).matched[0].id, 'ar-2b');
  assert.ok(ids(vi('ar', { sev: 'Severe', sx: 'Yes', candidate: 'Yes' })).includes('ar-tavi'));
  assert.ok(!ids(vi('ar', { sev: 'Moderate', sx: 'No', surg: 'No', candidate: 'Yes' })).includes('ar-tavi'));
  eq(vi('mrPrimary', { sev: 'Severe', sx: 'Yes' }).matched[0].id, 'mr-d');
  eq(vi('mrPrimary', { sev: 'Severe', sx: 'No', lvesd: 'Yes' }).matched[0].id, 'mr-c2');
  eq(vi('mrPrimary', { sev: 'Severe', sx: 'No', ef: '> 60%', lvesd: 'No', durable: 'Yes' }).matched[0].id, 'mr-c1');
  const teer = vi('mrPrimary', { sev: 'Severe', sx: 'Yes', nyha: 'III–IV', risk: 'High or prohibitive', anatomy: 'Yes', rheumatic: 'No' });
  eq(ids(teer).slice(0, 2), ['mr-d', 'mr-teer']); assert.ok(ids(teer).includes('mr-repair'));
  assert.ok(ids(vi('mrPrimary', { sev: 'Severe', sx: 'Yes', posterior: 'Yes' })).includes('mr-posterior'));
  assert.ok(ids(vi('mrPrimary', { sev: 'Severe', sx: 'Yes', rheumatic: 'Yes' })).includes('mr-rheum'));
  assert.ok(!ids(vi('mrPrimary', { sev: 'Severe', sx: 'No', lvesd: 'Yes', rheumatic: 'Yes' })).includes('mr-rheum'), 'rheumatic repair is for symptomatic patients');
  assert.ok(R.viRules('mrPrimary').find((r) => r.id === 'mr-rheum').recommendation.includes('if a durable and successful repair is likely'));
  eq(vi('mrSecondary', { sev: 'Severe', hf: 'Yes' }).matched[0].id, 'smr-gdmt');
  const smr = vi('mrSecondary', { sev: 'Severe', hf: 'Yes', gdmt: 'Yes', nyha: 'III–IV', ef: '20–49%', lvesd70: 'Yes', pasp70: 'Yes', anatomy: 'Yes' });
  assert.ok(ids(smr).includes('smr-teer')); assert.ok(ids(smr).includes('smr-surg')); eq(ids(smr)[0], 'smr-gdmt');
  eq(vi('mrSecondary', { sev: 'Severe', hf: 'No', gdmt: 'Yes', nyha: 'III–IV', ef: '≥ 50%', af: 'Yes' }).matched[0].id, 'smr-atrial');
  const pmbcOK = { morph: 'Yes', mr: 'Yes', thrombus: 'No' };
  eq(vi('ms', Object.assign({ sev: 'Severe (MVA ≤ 1.5 cm²)', nyha: 'II', calcific: 'No' }, pmbcOK)).matched[0].id, 'ms-pmbc');
  eq(vi('ms', { sev: 'Severe (MVA ≤ 1.5 cm²)', nyha: 'II' }).needed.slice(0, 3), ['morph', 'mr', 'thrombus']);
  eq(vi('ms', { sev: 'Severe (MVA ≤ 1.5 cm²)', nyha: 'III–IV', morph: 'No', calcific: 'No', candidate: 'Yes' }).matched[0].id, 'ms-surg');
  eq(vi('ms', { sev: 'Severe (MVA ≤ 1.5 cm²)', nyha: 'III–IV', thrombus: 'Yes', calcific: 'No', candidate: 'Yes' }).matched[0].id, 'ms-surg');
  eq(vi('ms', { sev: 'Severe (MVA ≤ 1.5 cm²)', nyha: 'III–IV', morph: 'No', mr: 'Yes', thrombus: 'No', calcific: 'No', candidate: 'No' }).matched[0].id, 'ms-highrisk');
  eq(ids(vi('ms', { sev: 'Severe (MVA ≤ 1.5 cm²)', nyha: 'III–IV', morph: 'Yes', mr: 'No', thrombus: 'No', calcific: 'No', candidate: 'No' })), [], 'MR ≥ 2+ is not suboptimal anatomy');
  eq(ids(vi('ms', { sev: 'Severe (MVA ≤ 1.5 cm²)', nyha: 'III–IV', morph: 'No', mr: 'Yes', thrombus: 'Yes', calcific: 'No', candidate: 'No' })), [], 'LA thrombus: no PMBC');
  eq(vi('ms', Object.assign({ sev: 'Severe (MVA ≤ 1.5 cm²)', nyha: 'I', pasp: 'Yes' }, pmbcOK)).matched[0].id, 'ms-pasp');
  eq(vi('ms', { sev: 'Not severe (MVA > 1.5 cm²)', nyha: 'II', exercise: 'Yes', thrombus: 'No' }).matched[0].id, 'ms-ex');
  eq(vi('ms', Object.assign({ calcific: 'Yes', nyha: 'III–IV', sev: 'Severe (MVA ≤ 1.5 cm²)' }, pmbcOK)).matched[0].id, 'ms-mac');
  assert.ok(!ids(vi('ms', { calcific: 'Yes', nyha: 'III–IV', sev: 'Not severe (MVA > 1.5 cm²)', exercise: 'No' })).includes('ms-mac'), 'MAC: severe MS only');
  assert.ok(R.viQuestions('ms').find((q) => q.id === 'thrombus').hint.includes('class 1, C-LD'), 'TEE before PMBC');
  eq(vi('tr', { sev: 'Severe', left: 'Yes' }).matched[0].id, 'tr-left');
  eq(vi('tr', { sev: 'Progressive (moderate)', left: 'Yes', annulus: 'Yes' }).matched[0].id, 'tr-prog');
  eq(vi('tr', { sev: 'Severe', cause: 'Primary (leaflet)', rhf: 'Yes', left: 'No' }).matched[0].id, 'tr-primary');
  eq(vi('tr', { sev: 'Severe', cause: 'Secondary (annular dilation)', rhf: 'Yes', left: 'No', ph: 'No', medical: 'Yes' }).matched[0].id, 'tr-secondary');
  eq(vi('tr', { sev: 'Severe', prior: 'Yes', rhf: 'Yes', severeph: 'No' }).matched[0].id, 'tr-redo');
  const trw = vi('tr', { sev: 'Progressive (moderate)', left: 'No', cause: 'Secondary (annular dilation)', rhf: 'No', prior: 'No' });
  eq(trw.matched.length, 0); assert.ok(trw.fallback);
});
test('mitral stenosis: a left atrial thrombus never leads to PMBC', () => {
  let combos = [{}];
  for (const q of R.viQuestions('ms')) combos = combos.flatMap((c) => q.options.map((o) => Object.assign({}, c, { [q.id]: o })));
  eq(combos.length, 3072);
  let pmbcSeen = 0;
  for (const a of combos) {
    const m = ids(vi('ms', a)), pmbc = vi('ms', a).matched.filter((x) => /PMBC|balloon/.test(x.recommendation));
    pmbcSeen += pmbc.length ? 1 : 0;
    if (a.thrombus === 'Yes') assert.ok(!pmbc.length, 'thrombus led to ' + pmbc.map((x) => x.id) + ' for ' + JSON.stringify(a));
    if (a.mr === 'No') assert.ok(!m.includes('ms-highrisk'), 'MR ≥ 2+ led to ms-highrisk for ' + JSON.stringify(a));
    if (m.includes('ms-highrisk')) eq([a.morph, a.mr, a.thrombus], ['No', 'Yes', 'No'], 'ms-highrisk is for suboptimal anatomy only');
  }
  assert.ok(pmbcSeen > 0);
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
  const cp = { healthy: [0.5, 0.7], uncoupled: [0.3, 0.4] };
  eq([[2.4, 30], [2.4, 40], [1.98, 40], [1.8, 40], [1.6, 40], [1.2, 40], [1.0, 45]].map(([t, p]) => [R.echo.coupling(t, p, cp).ratio, R.echo.coupling(t, p, cp).grade]),
    [[0.8, 0], [0.6, 0], [0.5, 0], [0.45, null], [0.4, 4], [0.3, 4], [0.22, 4]], 'TAPSE/PASP: healthy 0.5–0.7, uncoupling 0.3–0.4 (ASE 2025), read at two decimals');
  eq(R.echo.coupling(1.0, 45, cp).label, 'Below the uncoupling range');
  eq(R.echo.coupling(2.4, 30, cp).label, 'Above the usual healthy range');
  eq(R.echo.coupling(null, 40, cp), null); eq(R.echo.coupling(2, 0, cp), null);
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
  eq(R.echo.rap(1.9, null, 2.1, true, 1.2).label, 'Not estimable', 'ventilated: 1.2 cm (ASE 2010), not 2.1');
  eq(R.echo.rap(1.2, null, 2.1, true, 1.2).label, 'Likely below 10 mmHg');
  eq(R.echo.rap(1.1, null, 2.1, true).label, 'Likely below 10 mmHg', 'defaults to 1.2 cm');
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
  eq([35, 35.5].map((v) => gr('ma', 'female', v)), [0, 4], 'mitral annulus > 35 mm (EACVI 2013)');
  eq([1.3, 1.35].map((v) => gr('maratio', 'male', v)), [0, 4], 'annulus to anterior leaflet > 1.3');
  eq(R.echo.indexed(find('ma')), null, 'no society cutoff indexes the mitral annulus');
  eq(e.groups.find((g) => g.id === 'annuli').measures.map((m) => m.id), ['ma', 'maratio', 'ta'], 'both annuli on one tab');
  eq(R.echo.ageLimit(find('sov'), 'female', { age: 45, bsa: 1.7 }).value, 3.6, 'Goldstein 2015 women 40–49');
  // Lang 2015 Supplemental Table 3: mild, moderate and severe for LV size, wall thickness and mass
  eq([58.4, 58.5, 63, 64, 68, 69].map((v) => gr('lvidd', 'male', v)), [0, 1, 1, 2, 2, 3], 'LV end-diastolic diameter, men (mm)');
  eq([52.2, 53, 56, 57, 61, 62].map((v) => gr('lvidd', 'female', v)), [0, 1, 1, 2, 2, 3], 'LV end-diastolic diameter, women (mm)');
  eq([1.0, 1.05, 1.3, 1.4, 1.6, 1.7].map((v) => gr('ivsd', 'male', v)), [0, 1, 1, 2, 2, 3], 'septum, men');
  eq([0.9, 1.0, 1.2, 1.3, 1.5, 1.6].map((v) => gr('pwd', 'female', v)), [0, 1, 1, 2, 2, 3], 'posterior wall, women');
  eq([115, 116, 131, 132, 148, 149].map((v) => gr('lvmi', 'male', v)), [0, 1, 1, 2, 2, 3], 'LV mass index (linear), men');
  eq([88, 89, 100, 101, 112, 113].map((v) => gr('lvmi2d', 'female', v)), [0, 1, 1, 2, 2, 3], 'LV mass index (2D), women');
  eq([74, 75, 89, 90, 100, 101].map((v) => gr('lvedvi', 'male', v)), [0, 1, 1, 2, 2, 3], 'LV end-diastolic volume index, men');
  eq(R.echo.ranges(find('lvids'), 'female').map((x) => x.text).join(' · '), 'Normal 21.6–34.8 · mild ≤ 38 · moderate ≤ 41 · severe > 41');
  // RV free-wall strain: normal limit by sex (2025 strain consensus); the limit itself is normal
  eq([20, 19.9, 15, 14.9, 11, 10.9].map((v) => gr('rvfws', 'male', v)), [0, 1, 1, 2, 2, 3], 'free-wall strain, men');
  eq([21, 20.5, 15, 11, 10.9].map((v) => gr('rvfws', 'female', v)), [0, 1, 1, 2, 3], 'free-wall strain, women');
  // main PA diameter (ASE 2025 Table 1, May 2025 file)
  eq([2.5, 2.6, 3.0, 3.1, 3.5, 3.6].map((v) => gr('pa', 'male', v)), [0, 1, 1, 2, 2, 3], 'PA diameter');
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
  // lung disease: TR/PASP set aside → read both ways; normal function vs not determined → not determined
  r = dd({ E: 80, A: 60, eSeptal: 9, eLateral: 12, tr: 3.0, lungDisease: true });
  eq(r.lap, 'unknown');
  assert.ok(r.cautions.length > 0);
  // review finding: TR missing, e′ and E/e′ normal, LAVi 40 must not read as Grade 2
  r = dd({ E: 80, A: 60, eSeptal: 9, eLateral: 12, lavi: 40 });
  eq([r.lap, r.grade], ['unknown', null], 'depends on TR');
  // TR missing but every way gives Grade 2: e′ and E/e′ abnormal with LARS ≤ 18%
  r = dd({ E: 100, A: 80, eSeptal: 5, eLateral: 6, lars: 15 });
  eq([r.lap, r.grade], ['increased', 2]);
  assert.ok(r.explanation.includes('whichever way'));
  // TR missing, e′ and E/e′ normal, supplemental normal: normal LAP either way, but no grade
  r = dd({ E: 80, A: 60, eSeptal: 9, eLateral: 12, lars: 30 });
  eq([r.lap, r.grade, r.headline], ['normal', null, 'Normal LAP']);
  // a pulmonary vein S/D above 0.67 does not settle it (normal LVEF)
  r = dd({ E: 90, A: 70, eSeptal: 5, eLateral: 6, tr: 2.2, pvsd: 1.0 });
  eq(r.lap, 'unknown', 'S/D above 0.67 alone is not evidence of normal LAP');
  r = dd({ E: 90, A: 70, eSeptal: 5, eLateral: 6, tr: 2.2, pvsd: 0.5 });
  eq(r.lap, 'increased', 'S/D 0.67 or less still counts');
  // with a reduced LVEF an S/D above 0.67 is an absent sign; with 50% or more it still settles nothing
  r = dd({ E: 90, A: 70, eSeptal: 5, eLateral: 6, tr: 2.2, pvsd: 1.0, lvef: 35 });
  eq([r.lap, r.grade], ['normal', null], 'S/D 1.0 with LVEF 35%');
  assert.ok(r.steps.find((s) => s.id === 'pvsd').text.includes('counts as normal'));
  eq(dd({ E: 90, A: 70, eSeptal: 5, eLateral: 6, tr: 2.2, pvsd: 1.0, lvef: 50 }).lap, 'unknown', 'LVEF 50% is not reduced');
  eq(dd({ E: 90, A: 70, eSeptal: 5, eLateral: 6, tr: 2.2, pvsd: 0.6, lvef: 35 }).lap, 'increased');
  // second-line signs when the supplemental four are missing
  r = dd({ E: 80, A: 60, eSeptal: 9, eLateral: 12, tr: 3.0, ara: 40 });
  eq(r.lap, 'lvedp', 'Ar − A alone is an LVEDP marker');
  r = dd({ E: 80, A: 60, eSeptal: 9, eLateral: 12, tr: 3.0, padp: 18 });
  eq([r.lap, r.grade], ['increased', 2]);
  // signed second-line inputs: Ar shorter than A, or no fall in E/A, are absent signs rather than missing ones
  eq([R.numSigned('−20'), R.numSigned('-5.5'), R.numSigned('0'), R.numSigned(''), R.numSigned('12a'), R.numSigned('-')], [-20, -5.5, 0, null, null, null]);
  r = dd({ E: 80, A: 60, eSeptal: 9, eLateral: 12, tr: 3.0, ara: -20 });
  eq([r.lap, r.grade], ['normal', null], 'Ar − A of −20 ms is an absent sign');
  r = dd({ E: 80, A: 60, eSeptal: 9, eLateral: 12, tr: 3.0, valsalva: 0 });
  eq(r.lap, 'normal', 'no fall with Valsalva is an absent sign');
  // cutoffs: ≤ for e′, ≥ for E/e′ and TR
  eq(R.diastolicPrimaries({ eSeptal: 6 }).v1, true, 'septal 6 alone is reduced');
  eq(R.diastolicPrimaries({ eLateral: 7 }).v1, true, 'lateral 7 alone is reduced');
  eq(R.diastolicPrimaries({ eSeptal: 6.1, eLateral: 7.1 }).v1, false);
  // both sites measured: the average decides (septal 6 with lateral 8 averages 7)
  eq(R.diastolicPrimaries({ eSeptal: 6, eLateral: 8 }).v1, false, 'average 7 is not reduced');
  eq(R.diastolicPrimaries({ eSeptal: 5, eLateral: 8 }).v1, true, 'average 6.5 is reduced');
  eq(R.diastolicPrimaries({ E: 100, eSeptal: 6.5, eLateral: 9 }).v2, false, 'septal E/e′ 15.4 but average 12.9');
  eq(R.diastolicPrimaries({ E: 100, eSeptal: 6.5 }).v2, true, 'septal E/e′ 15.4 alone counts');
  assert.ok(dd({ E: 100, A: 80, eSeptal: 6, eLateral: 8, tr: 2.2 }).steps[0].text.endsWith('by the average'));
  eq(R.diastolicPrimaries({ E: 98, eSeptal: 7, eLateral: 7 }).v2, true, 'average E/e′ 14 counts (Figure 3: ≥ 14)');
  eq(R.diastolicPrimaries({ tr: 2.8 }).v3, true, 'TR 2.8 counts');
  // age-specific e′ (Table 6, strict <)
  eq(R.diastolicPrimaries({ eSeptal: 6.5, eLateral: 9.5, ageBand: '20-39' }).v1, true, 'average 8 < 9 at 20–39 y');
  eq(R.diastolicPrimaries({ eSeptal: 6.5, ageBand: '20-39' }).v1, true, 'septal 6.5 < 7 at 20–39 y');
  eq(R.diastolicPrimaries({ eSeptal: 6, eLateral: 7, ageBand: '>65' }).v1, false, 'strict < at > 65 y');
});
test('diastolic: the shipped content carries the intraoperative warning', () => {
  assert.ok(/intraoperative/.test(bundle.diastolic.readingWarning || ''));
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

// ---------- ACLS content in reference.json: a walk through each mode ----------
test('acls content: an adult VF code prompts the printed sequence', () => {
  const A = R.acls, d = bundle.acls;
  assert.ok(d && d.modes.length === 6, 'six modes');
  const ids = (ps) => ps.map((p) => p.id);
  const s = A.session(0, 'arrest', 'adult');
  eq(ids(A.prompts(s, d, 0)), ['first-adult'], 'before the first rhythm');
  A.add(s, 10000, 'vf', 'Rhythm: VF/pVT');
  let ps = A.prompts(s, d, 11000);
  eq(ids(ps), ['shock-now']);
  eq(ps[0].text, 'Shock now: the device’s recommended biphasic dose (e.g. 120–200 J), or its maximum if unknown; later shocks equal or higher; monophasic 360 J. Resume compressions straight after; the next rhythm check is in 2 minutes.');
  A.add(s, 12000, 'shock', A.entryText(d.actions.shock, s, 0, 200));
  eq(s.log.at(-1).text, 'Shock 1: 200 J');
  eq(ids(A.prompts(s, d, 20000)), [], 'nothing between shocks');
  A.add(s, 130000, 'vf', 'Rhythm: VF/pVT'); A.add(s, 131000, 'shock', 'Shock 2: 200 J');
  ps = A.prompts(s, d, 132000);
  eq(ids(ps), ['epi-s', 'airway']);
  eq(ps[0].text, 'Two shocks have not worked: epinephrine 1 mg IV/IO.');
  A.add(s, 140000, 'epi', A.entryText(d.actions.epi, s, 0));
  eq(s.log.at(-1).text, 'Epinephrine 1 mg IV/IO');
  A.add(s, 250000, 'vf', 'Rhythm: VF/pVT'); A.add(s, 251000, 'shock', 'Shock 3: 200 J');
  ps = A.prompts(s, d, 252000);
  eq(ids(ps), ['anti', 'airway', 'causes']);
  eq(ps[0].text, 'Three shocks have not worked: amiodarone 300 mg IV/IO, or lidocaine 1–1.5 mg/kg.');
  A.add(s, 260000, 'amio', A.entryText(d.actions.amio, s, 0));
  eq(ids(A.prompts(s, d, 330000)), ['epi-due', 'airway', 'causes'], 'epinephrine due 3 min after the first dose');
  A.add(s, 331000, 'epi', A.entryText(d.actions.epi, s, 1));
  eq(s.log.at(-1).text, 'Epinephrine 1 mg IV/IO (dose 2)');
  A.add(s, 370000, 'vf', 'Rhythm: VF/pVT'); A.add(s, 371000, 'shock', 'Shock 4: 200 J');
  ps = A.prompts(s, d, 372000);
  eq(ids(ps), ['anti-2a', 'airway', 'causes']);
  eq(ps[0].text, 'If VF/pVT persists, a second amiodarone dose: 150 mg IV/IO. The algorithm prints no interval for it.');
  A.add(s, 380000, 'airway', 'Advanced airway placed');
  eq(ids(A.prompts(s, d, 381000)), ['anti-2a', 'vent-adult', 'causes']);
  // lidocaine first: the second lidocaine dose is offered, not a switch to amiodarone
  const l = A.session(0, 'arrest', 'adult');
  for (const [t0, id] of [[1000, 'vf'], [2000, 'shock'], [125000, 'vf'], [126000, 'shock'], [130000, 'epi'], [250000, 'vf'], [251000, 'shock'], [255000, 'lido'], [370000, 'vf'], [371000, 'shock']]) A.add(l, t0, id, id);
  ps = A.prompts(l, d, 372000);
  eq(ids(ps).filter((x) => x.startsWith('anti')), ['anti-2b']);
  eq(ps.find((p) => p.id === 'anti-2b').text, 'If VF/pVT persists, a second lidocaine dose: 0.5–0.75 mg/kg. The algorithm prints no interval for it.');
  // the cycle clock resets at each rhythm check
  eq(A.cycle(s, d, 400000).from, 370000);
  // ROSC switches to post-arrest care
  eq(d.actions.rosc.goto, 'rosc');
  const rosc = d.modes.find((m) => m.id === 'rosc');
  eq(rosc.lists.map((l) => [l.patient, l.items.length]), [['adult', 12], ['child', 12]]);
});
test('acls content: a child code, asystole first, with weight-based doses', () => {
  const A = R.acls, d = bundle.acls;
  const s = A.session(0, 'arrest', 'child');
  s.weight = 18;
  eq(A.prompts(s, d, 0).map((p) => p.id), ['first-child']);
  A.add(s, 5000, 'nonsh', 'Rhythm: asystole/PEA');
  const ps = A.prompts(s, d, 6000);
  eq(ps.map((p) => p.id), ['epi-ns']);
  eq(ps[0].text, 'Epinephrine as soon as possible: 0.18 mg IV/IO · 1.8 mL of 0.1 mg/mL = 100 mcg/mL (0.01 mg/kg).');
  eq(A.energy(d.actions.shock, s, 0).text, '36 J (2 J/kg)');
  eq(A.energy(d.actions.shock, s, 1).text, '72 J (4 J/kg)');
  eq(A.energy(d.actions.shock, s, 2).text, '≥ 72 J (4 J/kg), up to 180 J');
  eq(A.dose(d.actions.amio, s, 0).text, '90 mg IV/IO (5 mg/kg)');
  eq(A.dose(d.actions.amio, s, 1).text, '90 mg IV/IO (5 mg/kg)');
  eq(A.maxDoses(d.actions.amio, s), 3);
  const big = A.session(0, 'arrest', 'child'); big.weight = 70;
  eq(A.dose(d.actions.amio, big, 0).text, '300 mg IV/IO (the maximum)');
  eq(A.dose(d.actions.amio, big, 1).text, '150 mg IV/IO (the maximum)', 'later doses are capped at 150 mg');
  eq(A.dose(d.actions.epi, big, 0).text, '0.7 mg IV/IO · 7 mL of 0.1 mg/mL = 100 mcg/mL (0.01 mg/kg)');
  // a large child's shocks stop at the adult dose (10 J/kg or the adult dose, whichever is lower)
  eq([0, 1, 2].map((n) => A.energy(d.actions.shock, big, n).text), ['140 J (2 J/kg)', '200 J, the adult dose (4 J/kg would be 280 J)', '200 J, the adult dose (4 J/kg would be 280 J)']);
  const forty = A.session(0, 'arrest', 'child'); forty.weight = 40;
  eq(A.energy(d.actions.shock, forty, 2).text, '≥ 160 J (4 J/kg), up to 200 J (the adult dose)');
  eq(A.energy(d.actions.shock, forty, 2).joules, 160);
  eq(A.energy(d.actions.shock, A.session(0, 'arrest', 'child'), 2).text, '≥ 4 J/kg (up to 10 J/kg or the adult dose, whichever is lower)');
  eq(A.dose(d.actions.lido, s, 0).text, '18 mg IV/IO (1 mg/kg)');
  // the child lists carry hypoglycemia
  const arrest = d.modes.find((m) => m.id === 'arrest');
  eq(arrest.lists.find((l) => l.patient === 'child').items.map((x) => x.id).includes('hypoglycemia'), true);
  // bradycardia: atropine floor and ceiling
  const b = A.session(0, 'brady', 'child'); b.weight = 3;
  eq(A.dose(d.actions.atropine, b, 0).text, '0.1 mg IV/IO (the minimum)');
  b.weight = 40;
  eq(A.dose(d.actions.atropine, b, 0).text, '0.5 mg IV/IO (the maximum)');
  eq(A.maxDoses(d.actions.atropine, b), 2);
  // a child's atropine "may repeat once" with no printed interval: no countdown; an adult's runs every 3–5 min
  A.add(b, 1000, 'atropine', 'Atropine');
  eq(A.timer(d.actions.atropine, b, 'atropine', 400000), null);
  const ba = A.session(0, 'brady', 'adult'); A.add(ba, 1000, 'atropine', 'Atropine');
  eq(A.timer(d.actions.atropine, ba, 'atropine', 200000).state, 'due');
  // tachyarrhythmia: adenosine by weight, cardioversion as text
  const t = A.session(0, 'tachy', 'child'); t.weight = 18;
  eq(A.dose(d.actions['adenosine-child'], t, 0).text, '1.8 mg IV/IO rapid push, then flush (0.1 mg/kg)');
  eq(A.dose(d.actions['adenosine-child'], t, 1).text, '3.6 mg IV/IO rapid push, then flush (0.2 mg/kg)');
  eq(A.energy(d.actions['cardiovert-child'], t, 0).text, '0.5–1 J/kg; if not effective, 2 J/kg. Sedate if needed, but do not delay');
  // anaphylaxis: child doses
  const an = A.session(0, 'anaphylaxis', 'child'); an.weight = 18;
  eq(A.dose(d.actions['ana-epi-2'], an, 0).text, '20 mcg IV · 1 mL of 20 mcg/mL (the maximum)', 'capped at the adult grade II dose');
  eq(A.dose(d.actions['ana-epi-2'], an, 1).text, '36 mcg IV · 1.8 mL of 20 mcg/mL (2 mcg/kg)');
  eq(A.dose(d.actions['ana-epi-3'], an, 0).text, '50 mcg IV · 2.5 mL of 20 mcg/mL (the maximum)');
  eq(A.dose(d.actions['ana-epi-3'], an, 1).text, '180 mcg IV · 9 mL of 20 mcg/mL (10 mcg/kg)', 'escalates: ANZAAG 4–10 mcg/kg');
  const small = A.session(0, 'anaphylaxis', 'child'); small.weight = 8;
  eq(A.dose(d.actions['ana-epi-2'], small, 0).text, '16 mcg IV · 0.8 mL of 20 mcg/mL (2 mcg/kg)');
  eq(A.dose(d.actions['ana-epi-3'], small, 0).text, '32 mcg IV · 1.6 mL of 20 mcg/mL (4 mcg/kg)');
  const teen = A.session(0, 'anaphylaxis', 'child'); teen.weight = 70;
  eq([A.dose(d.actions['ana-epi-2'], teen, 0).amount, A.dose(d.actions['ana-epi-3'], teen, 1).amount, A.dose(d.actions['ana-fluid'], teen, 0).amount], [20, 200, 1000], 'never above the adult doses');
  eq(A.dose(d.actions['ana-epi-im'], an, 0).text, '180 mcg IM, lateral thigh (10 mcg/kg)');
  eq(A.dose(d.actions['ana-fluid'], an, 0).text, '360 mL IV/IO rapid bolus, repeat as needed (20 mL/kg)');
  eq(A.dose(d.actions['ana-glucagon'], an, 0).text, '0.72 mg IV (0.04 mg/kg)');
});
test('acls content: CALS deadlines, the trees and the anaphylaxis grades', () => {
  const A = R.acls, d = bundle.acls;
  const s = A.session(0, 'cals', 'adult');
  eq(A.deadlines(s, d, 0).map((x) => [x.id, x.remaining]), [['ecm', 60], ['reopen', 300]]);
  eq(A.prompts(s, d, 0).map((p) => p.id), ['start', 'airway']);
  A.add(s, 5000, 'vf', 'Rhythm: VF/pVT');
  eq(A.prompts(s, d, 6000).map((p) => p.id), ['vf-shock', 'airway']);
  A.add(s, 10000, 'cshock', 'Shock 1'); A.add(s, 20000, 'cshock', 'Shock 2'); A.add(s, 30000, 'cshock', 'Shock 3');
  let ps = A.prompts(s, d, 40000);
  eq(ps.map((p) => p.id), ['vf-fail', 'airway', 'infusions']);
  assert.ok(ps[0].text.includes('Amiodarone 300 mg IV/IO'), ps[0].text);
  ps = A.prompts(s, d, 61000);
  eq(ps.map((p) => p.id), ['vf-fail', 'ecm-rule', 'airway', 'infusions'], 'one minute: compressions');
  A.add(s, 62000, 'ecm', 'External compressions started');
  eq(A.deadlines(s, d, 62000).map((x) => x.id), ['reopen']);
  ps = A.prompts(s, d, 301000);
  eq(ps.map((p) => p.id), ['vf-fail', 'under-60', 'reopen-rule', 'airway', 'infusions'], 'five minutes: reopen');
  A.add(s, 302000, 'reopen', 'Emergency resternotomy');
  eq(A.deadlines(s, d, 303000), []);
  eq(A.prompts(s, d, 303000).map((p) => p.id), ['open', 'airway', 'infusions']);
  // asystole path
  const a = A.session(0, 'cals', 'adult');
  A.add(a, 5000, 'asys', 'Rhythm: asystole');
  eq(A.prompts(a, d, 6000).map((p) => p.id), ['asys-pace', 'airway']);
  // no CALS tree; the brady and tachy trees exist per patient; anaphylaxis for all
  eq(A.tree(a, d), null);
  for (const [mode, who, start] of [['brady', 'adult', 'q1'], ['brady', 'child', 'q1'], ['tachy', 'adult', 'q1'], ['tachy', 'child', 'q1'], ['anaphylaxis', 'adult', 'grade'], ['anaphylaxis', 'child', 'grade']]) {
    const t = A.session(0, mode, who);
    eq(A.tree(t, d).nodeId, start, mode + ' ' + who);
  }
  // every tree node is reachable from its start and every option leads somewhere
  for (const m of d.modes) for (const [who, tr] of Object.entries(m.tree || {})) {
    const seen = new Set([tr.start]); const todo = [tr.start];
    while (todo.length) { const n = tr.nodes[todo.pop()]; for (const o of n.options || []) { assert.ok(tr.nodes[o.next], `${m.id}/${who}: ${o.next}`); if (!seen.has(o.next)) { seen.add(o.next); todo.push(o.next); } } }
    eq([...seen].sort(), Object.keys(tr.nodes).sort(), `${m.id}/${who}: every node reachable`);
  }
  // walking the adult tachy tree logs the choices
  const t = A.session(0, 'tachy', 'adult');
  A.choose(t, d, 1000, 'q2', 'No: stable');
  A.choose(t, d, 2000, 'wide', 'Wide');
  eq(A.tree(t, d).node.title, 'Stable, wide complex');
  eq(t.log.map((e) => e.text), ['Tachy: Heart rate typically 150/min or more. Oxygen if hypoxemic, IV access, a 12-lead ECG if available. Is the tachyarrhythmia causing hypotension, acutely altered mental status, signs of shock, ischemic chest discomfort or acute heart failure? No: stable', 'Tachy: Wide QRS (0.12 s or more)? Wide']);
  // anaphylaxis prompts
  const an = A.session(0, 'anaphylaxis', 'adult');
  eq(A.prompts(an, d, 0).map((p) => p.id), ['start']);
  A.add(an, 1000, 'ana-help', 'Help called');
  A.add(an, 2000, 'ana-epi-3', A.entryText(d.actions['ana-epi-3'], an, 0));
  eq(an.log.at(-1).text, 'Epinephrine IV · grade III 50 mcg IV');
  ps = A.prompts(an, d, 123000);
  eq(ps.map((p) => p.id), ['epi3-due']);
  eq(ps[0].text, 'Two minutes: if the response is inadequate, repeat epinephrine 200 mcg IV · 2 mL of 100 mcg/mL.');
  for (const t0 of [130000, 260000, 390000]) A.add(an, t0, 'ana-epi-3', 'Epinephrine');
  eq(A.prompts(an, d, 391000).map((p) => p.id), ['infusion']);
  eq(A.prompts(an, d, 700000).map((p) => p.id), ['epi3-due', 'infusion', 'refractory']);
  eq(A.prompts(an, d, 3400000).map((p) => p.id), ['epi3-due', 'infusion', 'refractory', 'tryptase']);
  // boluses of both grades count together towards the infusion
  const mix = A.session(0, 'anaphylaxis', 'adult');
  for (const [t0, id] of [[1000, 'ana-help'], [2000, 'ana-epi-2'], [60000, 'ana-epi-2'], [120000, 'ana-epi-3'], [180000, 'ana-epi-3']]) A.add(mix, t0, id, id);
  eq(A.prompts(mix, d, 181000).map((p) => p.id), ['infusion']);
  // a child sees the ANZAAG escalation
  const ch = A.session(0, 'anaphylaxis', 'child'); ch.weight = 18;
  A.add(ch, 1000, 'ana-help', 'Help called'); A.add(ch, 2000, 'ana-epi-3', 'Epinephrine');
  ps = A.prompts(ch, d, 123000);
  eq(ps.map((p) => p.id), ['child-doses', 'epi3-due-child'], 'the age limit for the child doses stays on screen');
  eq(ps[1].text, 'Two minutes: if the response is inadequate, increase the dose: 180 mcg IV · 9 mL of 20 mcg/mL (10 mcg/kg) (ANZAAG: 4–10 mcg/kg).');
});

// ---------- ABG: acid–base and compensation ----------
// A fixture with the textbook rules; the shipped coefficients are checked against reference.json below.
const ABG = {
  normal: { ph: [7.35, 7.45], paco2: [35, 45], hco3: [22, 26] }, mid: { ph: 7.4, paco2: 40, hco3: 24 },
  check: { pk: 6.1, solubility: 0.0307, tol: 0.03 }, plausible: { ph: [6.8, 7.8], paco2: [10, 150], hco3: [3, 60] },
  rules: {
    metAcid: { slope: 1.5, intercept: 8, tol: 2, label: 'Winters’ formula' }, metAlk: { slope: 0.7, intercept: 23.2, tol: 2 },
    respAcidAcute: { slope: 0.1, intercept: 20, tol: 2 }, respAcidChronic: { slope: 0.35, intercept: 10, tol: 2 },
    respAlkAcute: { slope: 0.2, intercept: 16, tol: 2 }, respAlkChronic: { slope: 0.5, intercept: 4, tol: 2 },
  },
};
const abg = (ph, paco2, hco3) => R.abg.read({ ph, paco2, hco3 }, ABG);
test('abg: primary disorder, compensation and mixed disorders', () => {
  let r = abg(7.28, 30, 14);
  eq([r.headline, r.primary, r.second, r.check.ok], ['Metabolic Acidosis', 'metAcid', null, true]);
  eq(r.visual.bands.map((b) => [R.abg.f1(b.lo), R.abg.f1(b.hi)]), [['27', '31']], 'Winters’ formula: 1.5 × 14 + 8 ± 2');
  eq(r.explanation, 'pH 7.28: acidemia. HCO₃ 14 mEq/L (below 22) makes it metabolic. Winters’ formula expects PaCO₂ 27–31 mmHg; 30 sits in it: the respiratory compensation is appropriate.');
  r = abg(7.19, 40, 15);
  eq([r.headline, r.second], ['Metabolic and Respiratory Acidosis', 'respAcid'], 'PaCO₂ above Winters’ band');
  r = abg(7.38, 30, 17.5);
  eq([r.status, r.headline], ['normal', 'Metabolic Acidosis and Respiratory Alkalosis'], 'normal pH, mixed');
  r = abg(7.25, 60, 26);
  eq([r.headline, r.phase], ['Acute Respiratory Acidosis', 'acute']);
  r = abg(7.33, 60, 31.5);
  eq(r.headline, 'Chronic Respiratory Acidosis');
  r = abg(7.29, 60, 28.5);
  eq([r.headline, r.phase], ['Respiratory Acidosis, Partly Compensated', 'between']);
  r = abg(7.39, 60, 36);
  eq(r.headline, 'Respiratory Acidosis and Metabolic Alkalosis', 'HCO₃ above the chronic band');
  r = abg(7.4, 60, 36);
  eq(r.headline, 'Respiratory Acidosis and Metabolic Alkalosis', 'pH at 7.40 with both abnormal');
  r = abg(7.49, 48, 36);
  eq([r.headline, r.second], ['Metabolic Alkalosis', null]);
  r = abg(7.55, 25, 21.5);
  eq(r.headline, 'Acute Respiratory Alkalosis');
  r = abg(7.1, 55, 17);
  eq([r.headline, r.disorders], ['Respiratory and Metabolic Acidosis', ['respAcid', 'metAcid']]);
  r = abg(7.4, 40, 24);
  eq(r.headline, 'Normal Acid–Base Status');
  // two values: the third from Henderson–Hasselbalch
  r = abg(7.28, 30, null);
  eq([r.derived, R.abg.f1(r.values.hco3), r.headline], ['hco3', '13.9', 'Metabolic Acidosis']);
  eq(abg(null, 30, 14).derived, 'ph');
  eq(R.abg.fph(abg(null, 30, 14).values.ph), '7.28');
  eq(abg(7.28, null, 14).derived, 'paco2');
  eq(abg(7.28, null, null).state, 'empty');
  // values that do not agree
  r = abg(7.4, 30, 14);
  eq(r.check.ok, false);
  assert.ok(r.cautions.some((c) => c.includes('do not agree')));
  // copy text
  assert.ok(R.abg.summary(abg(7.28, 30, 14)).startsWith('ABG: pH 7.28, PaCO₂ 30 mmHg, HCO₃ 14 mEq/L. Metabolic Acidosis.'));
});

test('abg: the shipped rules (reference.json)', () => {
  const d = bundle.abg;
  assert.ok(d, 'abg section present');
  const r = (ph, pc, hc) => R.abg.read({ ph, paco2: pc, hco3: hc }, d);
  // Winters' formula at HCO3 14: 29 ± 2
  let x = r(7.28, 30, 14);
  eq([x.headline, R.abg.band(x.visual.bands[0] && { lo: x.visual.bands[0].lo, hi: x.visual.bands[0].hi })], ['Metabolic Acidosis', '27–31']);
  // metabolic alkalosis: 40 + 0.7 × 10 = 47 ± 5
  x = r(7.5, 47, 34);
  eq([x.headline, R.abg.band(x.visual.bands[0])], ['Metabolic Alkalosis', '42–52']);
  // chronic respiratory acidosis, 2018 rule: PaCO2 60 → 34 ± 2; acute 26 ± 3
  x = r(7.37, 60, 34);
  eq([x.headline, x.visual.bands.map((b) => R.abg.band(b))], ['Chronic Respiratory Acidosis', ['23–29', '32–36']]);
  eq(x.status, 'normal', 'a normal pH in compensated chronic hypercapnia is not called mixed');
  x = r(7.27, 60, 27);
  eq(x.headline, 'Acute Respiratory Acidosis');
  x = r(7.31, 60, 30.5);
  eq(x.headline, 'Respiratory Acidosis, Partly Compensated');
  assert.ok(r(7.2, 80, 32).cautions.some((c) => c.includes('derived up to PaCO₂ 70')), 'above the chronic rule\'s range');
  // respiratory alkalosis: PaCO2 30 → acute 22 ± 3, chronic 20 ± 3 (bands overlap: either)
  x = r(7.47, 30, 21.5);
  eq([x.phase, x.headline], ['either', 'Respiratory Alkalosis']);
  x = r(7.55, 25, 21.5);
  eq(x.headline, 'Acute Respiratory Alkalosis');
  // a normal third-trimester gas reads as a compensated respiratory alkalosis
  x = r(7.44, 30, 20);
  eq([x.headline, x.second], ['Respiratory Alkalosis', null]);
  // agreement within 0.05
  eq([r(7.3, 30, 14).check.ok, r(7.36, 30, 14).check.ok], [true, false]);
  // every rule passes through 24/40 except Winters' formula (44 at 24)
  for (const [k, rule] of Object.entries(d.rules)) {
    const at = k.startsWith('resp') ? rule.slope * 40 + rule.intercept : rule.slope * 24 + rule.intercept;
    if (k === 'metAcid') eq(at, 44); else eq(Math.round(at * 1000) / 1000, k.startsWith('resp') ? 24 : 40, k);
  }
});

// ---------- Regional technique finder ----------
const RG = {
  figure: { regions: [{ id: 'chest', name: 'Anterior chest and breast' }, { id: 'lower-abdomen', name: 'Lower abdomen' }, { id: 'hip', name: 'Hip' }, { id: 'knee', name: 'Knee' }] },
  blocks: [{ id: 'acb', name: 'Adductor canal' }, { id: 'ipack', name: 'IPACK' }, { id: 'peng', name: 'PENG' }, { id: 'tap', name: 'TAP' }],
  map: {
    knee: { neuraxial: { level: 'T10', technique: 'spinal' }, blocks: [{ id: 'acb' }, { id: 'ipack' }, { id: 'missing' }] },
    hip: { neuraxial: { level: 'T10', technique: 'spinal' }, blocks: [{ id: 'peng' }] },
    'lower-abdomen': { neuraxial: { level: 'T6', technique: 'spinal or epidural' }, blocks: [{ id: 'tap', role: 'alternative' }] },
    chest: { neuraxial: null, blocks: [] },
  },
};
test('regional: sides, labels, levels and the recommendation', () => {
  const G = R.regional;
  eq([G.side('front', 0, 2), G.side('front', 1, 2), G.side('back', 0, 2), G.side('back', 1, 2), G.side('front', 0, 1)], ['R', 'L', 'L', 'R', 'M']);
  eq([G.rank('T4'), G.rank('T10'), G.rank('S2–S5'), G.rank('x')], [10, 16, 25, -1]);
  eq([G.label('Knee', ['R']), G.label('Hip', ['L', 'R']), G.label('Perineum and anus', ['M'])], ['Right knee', 'Both sides: hip', 'Perineum and anus']);
  const r = G.recommend(['knee:R', 'hip:L', 'lower-abdomen:M', 'knee:R', 'nowhere:M'], RG);
  eq(r.items.map((x) => [x.id, x.label]), [['lower-abdomen', 'Lower abdomen'], ['hip', 'Left hip'], ['knee', 'Right knee']], 'head to foot, duplicates merged');
  eq(r.items[2].blocks.map((b) => b.id), ['acb', 'ipack'], 'unknown blocks dropped');
  eq(r.items[0].blocks[0].role, 'alternative');
  eq(r.top, { level: 'T6', region: 'Lower abdomen' });
  eq(G.recommend(['chest:M'], RG).top, null);
});

test('regional content: the shipped figure, map, blocks and guide', () => {
  const G = R.regional, d = bundle.regional;
  const ids = new Set(d.blocks.map((x) => x.id));
  eq(ids.size, d.blocks.length, 'block ids are unique');
  for (const r of d.figure.regions) assert.ok(d.map[r.id], r.id + ' has options');
  for (const [rid, m] of Object.entries(d.map)) for (const x of m.blocks || []) assert.ok(ids.has(x.id), rid + ' → ' + x.id);
  let r = G.recommend(['knee:R'], d);
  eq(r.items[0].blocks.map((x) => x.id), ['adductor-canal', 'ipack', 'femoral']);
  eq(r.items[0].neuraxial.level, 'T10');
  r = G.recommend(['foot:L', 'knee:R', 'lower-abdomen:M'], d);
  eq(r.items.map((x) => x.label), ['Lower abdomen', 'Right knee', 'Left ankle and foot']);
  eq(r.top, { level: 'T6', region: 'Lower abdomen' }, 'the highest level wins');
  eq(G.recommend(['shoulder:R', 'chest:M'], d).top, null, 'no lumbar-type level above the waist');
  eq(G.recommend(['perineum:M'], d).items[0].neuraxial.level, 'S2–S5');
  for (const p of d.neuraxial.procedures) assert.ok(G.rank(p.level) >= 0, p.id + ' level');
  for (const b of d.blocks) assert.ok(/^https:\/\/(www\.)?nysora\.com\//.test(b.url), b.id + ' links to NYSORA');
});

test('OB emergencies: shipped checklists, clock and doses', () => {
  const d = bundle.obEmergency, src = new Set(d.sources.map((x) => x.id));
  eq(d.events.length, 13);
  eq(d.events[0].id, 'arrest', 'the arrest opens first');
  eq(d.events[0].timer.marks.map((m) => m.sec), [240, 300], 'hysterotomy by 4, delivery by 5 minutes');
  for (const e of d.events) {
    assert.ok(e.sections.some((s) => s.kind === 'steps' && s.items.length), e.id + ' has a checklist');
    for (const id of e.sources) assert.ok(src.has(id), e.id + ' → ' + id);
  }
  const ev = (id) => d.events.find((e) => e.id === id), dose = (id, label) => ev(id).weightDoses.find((x) => x.label.startsWith(label));
  const nb = ev('newborn');
  eq(nb.weightFor.key, 'newborn', 'the newborn has its own weight');
  assert.ok(nb.weightFor.maxKg > 0 && nb.weightFor.maxKg <= 10, 'an adult weight is refused');
  for (const e of d.events) if (e.id !== 'newborn') assert.ok(!e.weightFor, e.id + ' uses the mother\'s weight');
  const epi = dose('newborn', 'Epinephrine IV');
  eq(R.peds.doseText(epi.perKg, epi.perKgHigh, epi.unit, 3, null, null).text, '0.03–0.09 mg');
  const bolus = dose('last', 'Lipid 20% bolus');
  eq(R.peds.doseText(bolus.perKg, null, bolus.unit, 60, null, null).text, '90 mL');
  eq([bolus.aboveKg, bolus.aboveText], [70, 'About 100 mL (over 70 kg)']);
  const lev = dose('hypertension', 'Levetiracetam');
  eq(R.peds.doseText(lev.perKg, null, lev.unit, 90, null, lev.max).text, '4500 mg', 'held at the maximum');
  assert.ok(d.manual && /^https:\/\//.test(d.manual.url), 'the Stanford manual is linked');
});

console.log(`${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
