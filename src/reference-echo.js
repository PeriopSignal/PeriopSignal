/* Periop Signal echo tools for the website's Reference tab: ASE chamber quantification and ASE diastolic
   function. Values come from reference.json ("echo"); the grading lives in src/reference-logic.js. Height,
   weight and measurements stay in the open tool and are never stored. */
(function () {
  'use strict';
  const GRADE_COLOR = { '-1': 'var(--fg-3)', 0: 'var(--new)', 1: 'var(--amber)', 2: 'var(--orange)', 3: 'var(--accent)', 4: 'var(--accent)' };
  const BAR_COLOR = { '-1': 'var(--surface-3)', 0: 'var(--new)', 1: 'var(--amber)', 2: 'var(--orange)', 3: 'var(--accent)', 4: 'var(--accent)' };

  // ---------- ASE chamber quantification ----------
  function mountChamber(host, c) {
    const { R, esc, eyebrow, seg, numIn, resultCard, footnote, I } = c;
    const E = R.echo, f = E.fmt;
    const st = { sex: 'male', height: '', weight: '', age: '', group: null, vals: {}, raw: {}, ivc: '', collapse: null, vent: false };
    const data = () => (c.bundle() && c.bundle().echo) || null;
    const bsaOf = (d) => R.bsa(R.num(st.height), R.num(st.weight), d && d.bsaFormula);
    const ctxOf = (d) => ({ age: R.num(st.age), bsa: bsaOf(d) });

    function strip(m, v, ctx) {
      const bands = E.bands(m, st.sex, ctx);
      if (!bands.length) return '';
      const from = bands[0].from, to = bands[bands.length - 1].to, span = to - from || 1;
      const pct = (x) => Math.max(0, Math.min(100, ((x - from) / span) * 100));
      const ticks = [];
      for (let i = 0; i < bands.length - 1; i++) ticks.push(bands[i].to);
      let h = `<div class="e-strip" aria-hidden="true"><div class="e-bar">${bands.map((b) => `<i style="width:${(((b.to - b.from) / span) * 100).toFixed(2)}%;background:${BAR_COLOR[b.grade]}"></i>`).join('')}</div>`;
      h += `<div class="e-ticks">${ticks.map((t) => `<span style="left:${pct(t).toFixed(2)}%">${esc(f(t))}</span>`).join('')}</div>`;
      if (v !== null && v !== undefined) h += `<span class="e-mark" style="left:${pct(v).toFixed(2)}%"></span>`;
      return h + '</div>';
    }
    const rangeLine = (m, ctx, unit) => `${esc(E.ranges(m, st.sex, ctx).map((x) => x.text).join(' · '))}${unit ? ' ' + esc(unit) : ''}`;
    /** Everything a row shows: the value graded, and the indexed grade when the row has indexed cutoffs. */
    function reading(m, d) {
      const ctx = ctxOf(d), raw = !!st.raw[m.id];
      const v = E.value(m, st.vals[m.id], raw, ctx.bsa);
      const gr = E.grade(m, st.sex, v, ctx);
      const ix = E.indexed(m);
      const iv = ix && v !== null && ctx.bsa ? v / ctx.bsa : null;
      const ig = iv !== null ? E.grade(ix, st.sex, iv) : null;
      return { ctx, raw, v, gr, ix, iv, ig };
    }

    const update = c.view(host, () => {
      const d = data();
      if (!d) return `<p class="r-muted">${c.bundle() ? 'The echo reference values are not in this copy of the reference file yet; reload in a minute.' : 'Loading the reference values…'}</p>`;
      const bsa = bsaOf(d);
      const groups = d.groups;
      const cur = groups.find((g) => g.id === st.group) || groups[0];
      let h = `<div class="r-stack">`;
      // patient
      h += `<section class="r-card"><div class="r-inline"><span class="lab">Sex</span>${seg('sex', [['male', 'Male'], ['female', 'Female']], st.sex, 'Sex')}</div>
        <div class="r-pair"><label class="r-field" for="ch-height"><span>Height (cm)</span>${numIn('ch-height', st.height, 'height', { label: 'Height in centimetres', wide: true })}</label><label class="r-field" for="ch-weight"><span>Weight (kg)</span>${numIn('ch-weight', st.weight, 'weight', { label: 'Weight in kilograms', wide: true })}</label></div>
        <p class="r-small">${bsa ? `Body surface area <strong>${f(bsa)} m²</strong> (${d.bsaFormula === 'mosteller' ? 'Mosteller' : 'DuBois'}). Indexed rows accept the raw value too, and rows with indexed cutoffs grade both.` : 'Height and weight give the body surface area for indexed values (volumes, mass, the indexed RV and annulus cutoffs); they clear when you leave.'}</p></section>`;
      // summary of what has been entered
      const entered = [];
      for (const g of groups) for (const m of g.measures) {
        const x = reading(m, d);
        if (x.gr !== null) entered.push({ m, x });
      }
      const worstOf = (x) => Math.max(x.gr, x.ig === null ? -1 : x.ig);
      const toneOf = (gr) => GRADE_COLOR[gr];
      if (entered.length) {
        // outside = abnormal, or outside the range on the harmless side (an LVEF above 72%)
        const outside = entered.filter((e) => worstOf(e.x) !== 0);
        const worst = entered.reduce((a, e) => Math.max(a, worstOf(e.x)), -1);
        const headline = !outside.length ? (entered.length === 1 ? 'Within the normal range' : 'All entered values within the normal range') : `${outside.length} of ${entered.length} outside the normal range`;
        h += resultCard(worst > 0 ? toneOf(worst) : (outside.length ? toneOf(-1) : 'var(--new)'), `${eyebrow(st.sex === 'female' ? 'Female reference values' : 'Male reference values')}<p class="r-headline big">${esc(headline)}</p>
          <div class="e-sum">${entered.map(({ m, x }) => {
            const unit = m.unit;
            const lab = E.label(m, x.gr) + (x.ig !== null && x.ig !== x.gr ? ` · indexed ${E.label(x.ix, x.ig).toLowerCase()}` : '');
            return `<div class="e-sr"><i style="background:${toneOf(worstOf(x))}"></i><span class="n">${esc(m.short || m.name)}</span><span class="v">${esc(f(x.v))}${unit ? ' ' + esc(unit) : ''}</span><span class="l" style="color:${toneOf(worstOf(x))}">${esc(lab)}</span></div>`;
          }).join('')}</div>`);
      }
      // group tabs
      h += `<div class="r-tabs" role="tablist" aria-label="Structure">${groups.map((g) => `<button type="button" role="tab" data-a="group" data-v="${esc(g.id)}" aria-selected="${g.id === cur.id}">${esc(g.short || g.name)}</button>`).join('')}</div>`;
      h += `<section class="r-sec">${eyebrow(cur.name)}<div class="r-card flush">`;
      if (cur.measures.some((m) => m.byAge)) {
        h += `<div class="e-row"><div class="e-top"><label class="e-name" for="ch-age"><strong>Age</strong><small>The aortic root limits are set by age and sex, then BSA</small></label><span class="e-in">${numIn('ch-age', st.age, 'age', { label: 'Age in years' })}<span class="e-u">years</span></span></div></div>`;
      }
      for (const m of cur.measures) {
        const x = reading(m, d);
        const ref = E.ref(m, st.sex, x.ctx);
        const unit = m.index === 'bsa' && x.raw ? (m.rawUnit || m.unit.replace('/m²', '')) : m.unit;
        h += `<div class="e-row"><div class="e-top"><label class="e-name" for="ch-${esc(m.id)}"><strong>${esc(m.name)}</strong>${m.method ? `<small>${esc(m.method)}</small>` : ''}</label>
          <span class="e-in">${numIn('ch-' + m.id, st.vals[m.id], 'val', { k: m.id, label: m.name })}${m.index === 'bsa' ? `<button type="button" class="e-unit" data-a="unit" data-k="${esc(m.id)}" aria-label="Switch between the indexed and the raw value">${esc(unit)}</button>` : `<span class="e-u">${esc(unit)}</span>`}</span></div>`;
        if (m.byAge && !ref) h += `<p class="r-small">${R.num(st.age) && R.num(st.age) < 15 ? 'The adult tables start at 15 years.' : 'Enter the age for the upper limit.'}</p>`;
        else if (!ref) h += `<p class="r-small">No reference value for this sex.</p>`;
        else {
          h += strip(m, x.v, x.ctx);
          h += `<p class="e-range">${rangeLine(m, x.ctx, m.unit)}${m.ref ? ` <span>· ${esc(m.ref)}</span>` : ''}</p>`;
          if (m.byAge) {
            const lim = E.ageLimit(m, st.sex, x.ctx);
            const band = lim.row.to !== undefined && lim.row.to !== null ? `${lim.row.from}–${lim.row.to}` : `${lim.row.from} and over`;
            h += `<p class="r-small">${st.sex === 'female' ? 'Women' : 'Men'} ${esc(band)}: upper limit ${esc(f(lim.base))} cm at BSA ${esc(f(lim.refBsa))} m²${lim.adjusted ? `, ${esc(f(lim.value))} cm at this patient's ${esc(f(x.ctx.bsa))} m²` : '; add height and weight to adjust it for BSA'}.</p>`;
          }
        }
        if (m.index === 'bsa' && x.raw && st.vals[m.id] && !x.ctx.bsa) h += `<p class="e-res" style="color:var(--accent)">Enter height and weight to index this value.</p>`;
        else if (x.gr !== null) h += `<p class="e-res" style="color:${toneOf(x.gr)}">${esc(E.label(m, x.gr))}${m.index === 'bsa' && x.raw ? ` · ${esc(f(x.v))} ${esc(m.unit)}` : ''}</p>`;
        if (x.ix) {
          if (x.ig !== null) h += `<p class="e-res sub" style="color:${toneOf(x.ig)}">Indexed ${esc(f(x.iv))} ${esc(x.ix.unit)}: ${esc(E.label(x.ix, x.ig).toLowerCase())}</p>`;
          h += `<p class="e-range">Indexed: ${rangeLine(x.ix, null, x.ix.unit)}${x.ctx.bsa ? '' : ' <span>· needs height and weight</span>'}</p>`;
        }
        if (m.note) h += `<p class="r-small">${esc(m.note)}</p>`;
        h += `</div>`;
      }
      h += `</div>${cur.note ? footnote(cur.note) : ''}</section>`;
      // right-atrial pressure from the IVC
      if (d.ivc && cur.id === d.ivc.group) {
        const rap = E.rap(R.num(st.ivc), st.collapse, d.ivc.cut, st.vent, d.ivc.ventCut);
        h += `<section class="r-sec">${eyebrow('Right-atrial pressure from the IVC')}<div class="r-card">
          <div class="r-inline wide"><span class="lab">Breathing</span>${seg('vent', [['no', 'Spontaneous'], ['yes', 'Ventilated']], st.vent ? 'yes' : 'no', 'Breathing')}</div>
          <div class="e-top"><label class="e-name" for="ch-ivc"><strong>IVC diameter</strong><small>${esc(d.ivc.method || 'Subcostal, just proximal to the hepatic veins')}</small></label><span class="e-in">${numIn('ch-ivc', st.ivc, 'ivc', { label: 'IVC diameter in centimetres' })}<span class="e-u">cm</span></span></div>
          ${st.vent ? '' : `<div class="r-inline"><span class="lab">Collapses 50% or more with a sniff</span>${seg('collapse', [['yes', 'Yes'], ['no', 'No']], st.collapse === null ? '' : (st.collapse ? 'yes' : 'no'), 'Collapse')}</div>`}
          ${rap ? `<p class="r-answer">${rap.value !== null ? `${rap.value} mmHg <span class="e-rap">${esc(rap.label)}, ${esc(rap.range)}</span>` : esc(rap.label)}</p>${rap.detail ? `<p class="r-small">${esc(rap.detail)}</p>` : ''}` : `<p class="r-small">${st.vent ? 'Enter the diameter.' : 'Enter the diameter and the collapse.'}</p>`}
          ${(d.ivc.notes || []).map((n) => `<p class="r-small">${esc(n)}</p>`).join('')}</div></section>`;
      }
      h += `<footer class="r-footer">${eyebrow('Sources')}${d.sources.map((s) => `<div class="r-src"><p>${esc(s.citation)}</p>${s.url ? `<a href="${esc(s.url)}" target="_blank" rel="noopener">Open ${I.ext}</a>` : ''}</div>`).join('')}${(d.notes || []).map((n) => footnote(n)).join('')}${footnote('Reviewed ' + (d.reviewed || '') + '. A reference, not a report: measure the way the guideline describes, and read borderline values with the whole study.')}</footer>`;
      return h + `</div>`;
    }, {
      sex(el) { st.sex = el.dataset.v; },
      height(el) { st.height = el.value; },
      weight(el) { st.weight = el.value; },
      age(el) { st.age = el.value; },
      group(el) { st.group = el.dataset.v; },
      val(el) { st.vals[el.dataset.k] = el.value; },
      unit(el) { st.raw[el.dataset.k] = !st.raw[el.dataset.k]; },
      ivc(el) { st.ivc = el.value; },
      collapse(el) { st.collapse = el.dataset.v === 'yes'; },
      vent(el) { st.vent = el.dataset.v === 'yes'; },
    });
    if (!data()) c.loadBundle().then(update);
  }

  // ---------- ASE 2025 diastolic function ----------
  const MAIN = [
    ['E', 'Mitral E velocity', 'cm/s', 'Pulsed Doppler at the leaflet tips'],
    ['A', 'Mitral A velocity', 'cm/s', null],
    ['eSeptal', 'Septal e′', 'cm/s', 'Tissue Doppler'],
    ['eLateral', 'Lateral e′', 'cm/s', 'Tissue Doppler'],
    ['pasp', 'PA systolic pressure', 'mmHg', 'From TR velocity plus RAP; preferred when RAP can be estimated'],
    ['tr', 'Peak TR velocity', 'm/s', 'Used when RAP cannot be estimated'],
  ];
  const SUPP = [
    ['lvef', 'LVEF', '%', 'Below 50%: a pulmonary vein S/D above 0.67 counts as normal'],
    ['pvsd', 'Pulmonary vein S/D', '', 'Abnormal ≤ 0.67; above 0.67 settles nothing unless LVEF is reduced'],
    ['lars', 'LA reservoir strain', '%', 'Abnormal ≤ 18%; not with AF, significant MR, transplant, normal EF with GLS > 18%, or LA stunning'],
    ['lavi', 'LA volume index', 'mL/m²', 'Abnormal > 34; not from athletes, anemia, AF or mitral disease'],
    ['ivrt', 'IVRT', 'ms', 'Abnormal ≤ 70 ms; rate dependent'],
  ];
  const MORE = [
    ['prEdv', 'PR end-diastolic velocity', 'm/s', 'Abnormal ≥ 2 m/s'],
    ['padp', 'PA diastolic pressure', 'mmHg', 'Abnormal ≥ 16 mmHg'],
    ['lwave', 'Mitral L-wave', 'cm/s', 'Abnormal ≥ 50 cm/s'],
    ['ara', 'Ar − A duration', 'ms', 'Abnormal > 30 ms with pulmonary vein Ar above 35 cm/s; reflects LVEDP'],
    ['valsalva', 'Fall in E/A with Valsalva', '%', 'Abnormal ≥ 50%; 0 or negative if E/A does not fall'],
  ];
  function mountDiastolic(host, c) {
    const { R, esc, eyebrow, seg, numIn, resultCard, footnote, I } = c;
    const st = { pop: 'standard', sex: 'male', age: '', lung: false, v: {}, more: false };
    const SIGNED = ['ara', 'valsalva']; // can be zero or negative
    const num = (k) => (SIGNED.includes(k) ? R.numSigned(st.v[k]) : R.num(st.v[k]));
    const data = () => (c.bundle() && c.bundle().diastolic) || null;
    const input = () => ({ E: num('E'), A: num('A'), eSeptal: num('eSeptal'), eLateral: num('eLateral'), pasp: num('pasp'), tr: num('tr'), lungDisease: st.lung, ageBand: st.age || null,
      pvsd: num('pvsd'), lars: num('lars'), lavi: num('lavi'), ivrt: num('ivrt'), prEdv: num('prEdv'), padp: num('padp'), lwave: num('lwave'), ara: num('ara'), valsalva: num('valsalva'),
      esr: num('esr'), lvmi: num('lvmi'), lvef: num('lvef'), sex: st.sex });
    const rows = (list, flags) => `<div class="r-card flush">${list.map(([k, label, unit, hint]) => {
      const fl = flags ? flags[k] : null;
      return `<div class="r-meas"><label class="mt" for="dd-${k}"><span>${esc(label)}</span>${hint ? `<small>${esc(hint)}</small>` : ''}</label>${fl === true ? '<i class="gd" style="background:var(--accent)" title="Abnormal"></i>' : (fl === false ? '<i class="gd" style="background:var(--new)" title="Normal"></i>' : '<i class="gd"></i>')}${numIn('dd-' + k, st.v[k], 'val', { k, label, signed: SIGNED.includes(k) })}<span class="mu">${esc(unit)}</span></div>`;
    }).join('')}</div>`;
    const warnLine = (d) => (d && d.readingWarning ? c.caution(d.readingWarning) : '');
    const toneFor = (r) => r.lap === 'increased' ? 'var(--accent)' : (r.lap === 'lvedp' ? 'var(--orange)' : (r.lap === 'normal' ? (r.grade === 1 ? 'var(--amber)' : 'var(--new)') : 'var(--fg-3)'));
    function summaryText(r) {
      const p = r.primaries || R.diastolicPrimaries(input());
      const parts = [];
      if (p.E !== null) parts.push('E ' + R.fmt(p.E) + ' cm/s'); if (p.A !== null) parts.push('A ' + R.fmt(p.A) + ' cm/s'); if (p.EA !== null) parts.push('E/A ' + R.fmt(p.EA));
      if (p.es !== null) parts.push('septal e′ ' + R.fmt(p.es)); if (p.el !== null) parts.push('lateral e′ ' + R.fmt(p.el)); if (p.eea !== null) parts.push('average E/e′ ' + R.fmt(p.eea));
      if (num('pasp') !== null) parts.push('PASP ' + R.fmt(num('pasp')) + ' mmHg'); if (num('tr') !== null) parts.push('TR ' + R.fmt(num('tr')) + ' m/s');
      for (const [k, label, unit] of SUPP.concat(MORE)) if (num(k) !== null) parts.push(label + ' ' + R.fmt(num(k)) + (unit ? ' ' + unit : ''));
      const d = data();
      return `LV diastolic function (ASE 2025): ${r.headline}. ${r.explanation}\n${parts.join('; ')}${d && d.readingWarning ? '\n' + d.readingWarning : ''}`;
    }
    const update = c.view(host, () => {
      const d = data();
      if (!d) return `<p class="r-muted">${c.bundle() ? 'The diastolic content is not in this copy of the reference file yet; reload in a minute.' : 'Loading the algorithm…'}</p>`;
      const pop = d.populations.find((x) => x.id === st.pop) || d.populations[0];
      const i = input();
      let h = `<div class="r-stack"><section class="r-warnbox">${c.caution(d.scope)}</section>`;
      h += `<section class="r-card"><label class="r-lesion plain r-pick" for="dd-pop"><span class="r-eyebrow">Patient</span><span class="r-picked"><span>${esc(pop.name)}</span>${I.updown}</span><select id="dd-pop" data-a="pop" aria-label="Patient group">${d.populations.map((x) => `<option value="${esc(x.id)}"${x.id === pop.id ? ' selected' : ''}>${esc(x.name)}</option>`).join('')}</select></label>`;
      if (pop.mode === 'main') {
        h += `<div class="r-inline"><span class="lab">e′ cutoffs</span><select id="dd-age" data-a="age" aria-label="e′ cutoffs"><option value=""${st.age ? '' : ' selected'}>Figure 3 (any age)</option><option value="20-39"${st.age === '20-39' ? ' selected' : ''}>Age 20–39 (Table 6)</option><option value="40-65"${st.age === '40-65' ? ' selected' : ''}>Age 40–65 (Table 6)</option><option value=">65"${st.age === '>65' ? ' selected' : ''}>Age over 65 (Table 6)</option></select></div>`;
        h += c.switchRow('lung', st.lung, 'Lung or pulmonary vascular disease', 'TR velocity and PASP then stop standing in for LAP');
      }
      h += `</section>`;
      // result
      if (pop.mode === 'main') {
        const r = R.diastolic(i), tone = toneFor(r);
        const pr = r.dysfunction;
        let inner = `<div class="r-rowtop">${eyebrow('ASE 2025 · Figure 3', tone)}<button type="button" class="r-ghost sm" data-a="copy">${I.copy}Copy</button></div><p class="r-headline big${r.lap === 'unknown' ? ' muted' : ''}">${esc(r.headline)}</p><p class="r-detail">${esc(r.explanation)}</p>`;
        inner += `<div class="dd-steps">${r.steps.map((s) => `<div class="dd-step"><i style="background:${s.state === true ? 'var(--accent)' : (s.state === false ? 'var(--new)' : 'var(--fg-3)')}"></i><span><strong>${esc(s.label)}</strong> ${esc(s.text)}</span></div>`).join('')}</div>`;
        if (pr && pr.state !== null) inner += `<p class="r-note2">${I.info}<span>Diastolic dysfunction (Figure 2): ${esc(pr.text)}${pr.supportive ? '; LV mass index supports it' : ''}.</span></p>`;
        inner += r.cautions.map(c.caution).join('') + warnLine(d);
        h += resultCard(tone, inner);
        // §13A: test symptomatic patients with grade 1, normal LAP without a grade, or an undetermined reading; not grade 0
        const anyMain = [r.primaries.v1, r.primaries.v2, r.primaries.v3].some((x) => x !== null);
        if (anyMain && (r.grade === 1 || (r.lap === 'normal' && r.grade === null) || r.lap === 'unknown') && d.exercise) h += `<section class="r-sec">${eyebrow('If symptomatic: diastolic exercise echo')}${c.factTable(d.exercise)}</section>`;
        if (pop.indicators && pop.indicators.length) h += `<section class="r-sec">${eyebrow(pop.name + ': also look for')}${c.takeList(pop.indicators)}${(pop.notes || []).map((n) => footnote(n)).join('')}</section>`;
        const p = r.primaries;
        h += `<section class="r-sec">${eyebrow('Main variables')}${rows(MAIN, { E: null, A: null, eSeptal: p.eFlags[0], eLateral: p.eFlags[1], pasp: p.v3by === 'pasp' ? p.v3 : null, tr: p.v3by === 'tr' ? p.v3 : null })}`;
        const derived = [p.EA !== null ? 'E/A ' + R.fmt(p.EA) : null, p.ea !== null ? 'average e′ ' + R.fmt(p.ea) + ' cm/s' : null, p.ees !== null ? 'septal E/e′ ' + R.fmt(p.ees) : null, p.eel !== null ? 'lateral E/e′ ' + R.fmt(p.eel) : null, p.eea !== null ? 'average E/e′ ' + R.fmt(p.eea) : null].filter(Boolean);
        if (derived.length) h += `<p class="r-small">${esc(derived.join(' · '))}</p>`;
        h += `</section><section class="r-sec">${eyebrow('Supplemental, when the main three disagree')}${rows(SUPP, { pvsd: num('pvsd') === null ? null : (num('pvsd') <= 0.67 ? true : (R.diastolicReducedEF(i) === true ? false : null)), lars: num('lars') === null ? null : num('lars') <= 18, lavi: num('lavi') === null ? null : num('lavi') > 34, ivrt: num('ivrt') === null ? null : num('ivrt') <= 70 })}</section>`;
        h += `<section class="r-sec"><button type="button" class="r-disclose" data-a="more" aria-expanded="${st.more}">${eyebrow('If those are not available or reliable')}<span>${st.more ? '−' : '+'}</span></button>${st.more ? rows(MORE, { prEdv: num('prEdv') === null ? null : num('prEdv') >= 2, padp: num('padp') === null ? null : num('padp') >= 16, lwave: num('lwave') === null ? null : num('lwave') >= 50, ara: num('ara') === null ? null : num('ara') > 30, valsalva: num('valsalva') === null ? null : num('valsalva') >= 50 }) : ''}</section>`;
        h += `<section class="r-sec">${eyebrow('Supportive')}<div class="r-inline"><span class="lab">Sex, for LV mass</span>${seg('sex', [['male', 'Male'], ['female', 'Female']], st.sex, 'Sex')}</div>${rows([['lvmi', 'LV mass index', 'g/m²', 'Supports diastolic dysfunction above 95 (women) or 115 (men), not in athletes']], { lvmi: num('lvmi') === null ? null : (st.sex === 'female' ? num('lvmi') > 95 : num('lvmi') > 115) })}</section>`;
      } else if (pop.mode === 'mac' || pop.mode === 'transplant') {
        const r = pop.mode === 'mac' ? R.diastolicMAC(i) : R.diastolicTransplant(i);
        const tone = r.lap === 'increased' ? 'var(--accent)' : (r.lap === 'normal' ? 'var(--new)' : 'var(--fg-3)');
        h += resultCard(tone, `${eyebrow(pop.mode === 'mac' ? 'ASE 2025 · Figure 4' : 'ASE 2025 · Section 15B', tone)}<p class="r-headline big${r.lap === 'unknown' ? ' muted' : ''}">${esc(r.headline)}</p><p class="r-detail">${esc(r.explanation)}</p>${warnLine(d)}`);
        const list = pop.mode === 'mac' ? [['E', 'Mitral E velocity', 'cm/s', null], ['A', 'Mitral A velocity', 'cm/s', null], ['ivrt', 'IVRT', 'ms', 'Decides when E/A is 0.8–1.8']]
          : [['E', 'Mitral E velocity', 'cm/s', null], ['eSeptal', 'Septal e′', 'cm/s', null], ['eLateral', 'Lateral e′', 'cm/s', null], ['esr', 'E/SRIVR', 'cm', 'Decides when average E/e′ is 7–14'], ['tr', 'Peak TR velocity', 'm/s', 'When SRIVR cannot be measured']];
        h += `<section class="r-sec">${eyebrow('Measurements')}${rows(list, null)}</section>`;
        if (pop.notes) h += `<section class="r-sec">${pop.notes.map((n) => footnote(n)).join('')}</section>`;
      } else {
        h += resultCard('var(--accent-2)', `${eyebrow('Main algorithm does not apply', 'var(--accent-2)')}<p class="r-headline big">${esc(pop.name)}</p><p class="r-detail">The 2025 document reads filling pressure in this group from its own signs, listed below; enter them in the report rather than a grade.</p>${warnLine(d)}`);
        if (pop.indicators && pop.indicators.length) h += `<section class="r-sec">${eyebrow('Signs of increased filling pressure')}${c.takeList(pop.indicators)}</section>`;
        if (pop.notes) h += `<section class="r-sec">${pop.notes.map((n) => footnote(n)).join('')}</section>`;
      }
      h += `<footer class="r-footer">${eyebrow('Source')}<div class="r-src"><p>${esc(d.source.citation)}</p><a href="${esc(d.source.url)}" target="_blank" rel="noopener">Open ${I.ext}</a></div>${footnote(d.supersedes)}${footnote(d.validation)}${(d.notes || []).map((n) => footnote(n)).join('')}</footer>`;
      return h + `</div>`;
    }, {
      pop(el) { st.pop = el.value; },
      age(el) { st.age = el.value; },
      lung() { st.lung = !st.lung; },
      sex(el) { st.sex = el.dataset.v; },
      val(el) { st.v[el.dataset.k] = el.value; },
      more() { st.more = !st.more; },
      copy() { const r = R.diastolic(input()); c.F.copyText(summaryText(r), 'Reading copied'); return false; },
    });
    if (!data()) c.loadBundle().then(update);
  }

  window.PSEcho = { mountChamber, mountDiastolic };
})();
