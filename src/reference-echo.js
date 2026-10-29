/* Periop Signal echo tools for the website's Reference tab: ASE chamber quantification and ASE diastolic
   function. Values come from reference.json ("echo"); the grading lives in src/reference-logic.js. Height,
   weight and measurements stay in the open tool and are never stored. */
(function () {
  'use strict';
  const GRADE_COLOR = { '-1': 'var(--fg-3)', 0: 'var(--new)', 1: 'var(--amber)', 2: 'var(--orange)', 3: 'var(--accent)', 4: 'var(--accent)' };
  const BAR_COLOR = { '-1': 'var(--surface-3)', 0: 'var(--new)', 1: 'var(--amber)', 2: 'var(--orange)', 3: 'var(--accent)', 4: 'var(--accent)' };

  // ---------- ASE chamber quantification ----------
  function mountChamber(host, c) {
    const { R, esc, eyebrow, seg, numIn, resultCard, footnote, ghostLink, I } = c;
    const st = { sex: 'male', height: '', weight: '', group: null, vals: {}, raw: {}, ivc: '', collapse: null };
    const data = () => (c.bundle() && c.bundle().echo) || null;
    const bsaOf = (d) => R.bsa(R.num(st.height), R.num(st.weight), d && d.bsaFormula);

    function strip(m, v) {
      const bands = R.echo.bands(m, st.sex);
      if (!bands.length) return '';
      const from = bands[0].from, to = bands[bands.length - 1].to, span = to - from || 1;
      const pct = (x) => Math.max(0, Math.min(100, ((x - from) / span) * 100));
      const ticks = [];
      for (let i = 0; i < bands.length - 1; i++) ticks.push(bands[i].to);
      let h = `<div class="e-strip" aria-hidden="true"><div class="e-bar">${bands.map((b) => `<i style="width:${(((b.to - b.from) / span) * 100).toFixed(2)}%;background:${BAR_COLOR[b.grade]}"></i>`).join('')}</div>`;
      h += `<div class="e-ticks">${ticks.map((t) => `<span style="left:${pct(t).toFixed(2)}%">${esc(R.fmt(t))}</span>`).join('')}</div>`;
      if (v !== null && v !== undefined) h += `<span class="e-mark" style="left:${pct(v).toFixed(2)}%"></span>`;
      return h + '</div>';
    }
    function rangeText(m) {
      const r = R.echo.ref(m, st.sex); if (!r) return '';
      const cuts = (r.cuts || []).slice().sort((a, b) => a - b), f = R.fmt, ge = m.edge === 'inclusive';
      if (m.dir === 'low') {
        if (cuts.length >= 3) return `Normal ${r.normal ? f(r.normal[0]) + '–' + f(r.normal[1]) : '≥ ' + f(cuts[2])} · mild ${f(cuts[1])}–${f(cuts[2])} · moderate ${f(cuts[0])}–${f(cuts[1])} · severe < ${f(cuts[0])}`;
        return `Normal ${r.normal ? f(r.normal[0]) + '–' + f(r.normal[1]) : (ge ? '> ' : '≥ ') + f(cuts[0])} · abnormal ${ge ? '≤' : '<'} ${f(cuts[0])}`;
      }
      if (cuts.length >= 3) return `Normal ${r.normal ? f(r.normal[0]) + '–' + f(r.normal[1]) : '≤ ' + f(cuts[0])} · mild ${f(cuts[0])}–${f(cuts[1])} · moderate ${f(cuts[1])}–${f(cuts[2])} · severe > ${f(cuts[2])}`;
      return `Normal ${r.normal ? f(r.normal[0]) + '–' + f(r.normal[1]) : (ge ? '< ' : '≤ ') + f(cuts[0])} · ${esc(m.word || 'abnormal')} ${ge ? '≥' : '>'} ${f(cuts[0])}`;
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
        <p class="r-small">${bsa ? `Body surface area <strong>${R.fmt(bsa)} m²</strong> (${d.bsaFormula === 'mosteller' ? 'Mosteller' : 'DuBois'}). Indexed rows accept the raw value too.` : 'Height and weight give the body surface area for the indexed rows (volumes, mass, the indexed annulus); they clear when you leave.'}</p></section>`;
      // summary of what has been entered
      const entered = [];
      for (const g of groups) for (const m of g.measures) {
        const v = R.echo.value(m, st.vals[m.id], st.raw[m.id], bsa);
        const gr = R.echo.grade(m, st.sex, v);
        if (gr !== null) entered.push({ g, m, v, gr });
      }
      const worst = entered.reduce((a, e) => (e.gr > (a ? a.gr : -2) && e.gr !== -1 ? e : a), null);
      const toneOf = (gr) => GRADE_COLOR[gr];
      if (entered.length) {
        const abnormal = entered.filter((e) => e.gr > 0);
        const headline = !abnormal.length ? (entered.length === 1 ? 'Within the normal range' : 'All entered values within the normal range') : `${abnormal.length} of ${entered.length} outside the normal range`;
        h += resultCard(worst && worst.gr > 0 ? toneOf(worst.gr) : 'var(--new)', `${eyebrow(st.sex === 'female' ? 'Female reference values' : 'Male reference values')}<p class="r-headline big">${esc(headline)}</p>
          <div class="e-sum">${entered.map((e) => `<div class="e-sr"><i style="background:${toneOf(e.gr)}"></i><span class="n">${esc(e.m.short || e.m.name)}</span><span class="v">${esc(R.fmt(e.v))} ${esc(e.m.unit)}</span><span class="l" style="color:${toneOf(e.gr)}">${esc(R.echo.label(e.m, e.gr))}</span></div>`).join('')}</div>`);
      }
      // group tabs
      h += `<div class="r-tabs" role="tablist" aria-label="Structure">${groups.map((g) => `<button type="button" role="tab" data-a="group" data-v="${esc(g.id)}" aria-selected="${g.id === cur.id}">${esc(g.short || g.name)}</button>`).join('')}</div>`;
      h += `<section class="r-sec">${eyebrow(cur.name)}<div class="r-card flush">`;
      for (const m of cur.measures) {
        const raw = !!st.raw[m.id];
        const v = R.echo.value(m, st.vals[m.id], raw, bsa);
        const gr = R.echo.grade(m, st.sex, v);
        const ref = R.echo.ref(m, st.sex);
        const unit = m.index === 'bsa' && raw ? (m.rawUnit || m.unit.replace('/m²', '')) : m.unit;
        h += `<div class="e-row"><div class="e-top"><label class="e-name" for="ch-${esc(m.id)}"><strong>${esc(m.name)}</strong>${m.method ? `<small>${esc(m.method)}</small>` : ''}</label>
          <span class="e-in">${numIn('ch-' + m.id, st.vals[m.id], 'val', { k: m.id, label: m.name })}${m.index === 'bsa' ? `<button type="button" class="e-unit" data-a="unit" data-k="${esc(m.id)}" aria-label="Switch between the indexed and the raw value">${esc(unit)}</button>` : `<span class="e-u">${esc(unit)}</span>`}</span></div>`;
        if (!ref) h += `<p class="r-small">No reference value for this sex.</p>`;
        else {
          h += strip(m, v);
          h += `<p class="e-range">${rangeText(m)} ${esc(m.unit)}${m.ref ? ` <span>· ${esc(m.ref)}</span>` : ''}</p>`;
        }
        if (m.index === 'bsa' && raw && st.vals[m.id] && !bsa) h += `<p class="e-res" style="color:var(--accent)">Enter height and weight to index this value.</p>`;
        else if (gr !== null) h += `<p class="e-res" style="color:${toneOf(gr)}">${esc(R.echo.label(m, gr))}${m.index === 'bsa' && raw ? ` · ${esc(R.fmt(v))} ${esc(m.unit)}` : ''}</p>`;
        if (m.note) h += `<p class="r-small">${esc(m.note)}</p>`;
        h += `</div>`;
      }
      h += `</div>${cur.note ? footnote(cur.note) : ''}</section>`;
      // right-atrial pressure from the IVC
      if (cur.id === (d.ivc && d.ivc.group) && d.ivc) {
        const rap = R.echo.rap(R.num(st.ivc), st.collapse, d.ivc.cut);
        h += `<section class="r-sec">${eyebrow('Right-atrial pressure from the IVC')}<div class="r-card">
          <div class="e-top"><label class="e-name" for="ch-ivc"><strong>IVC diameter</strong><small>${esc(d.ivc.method || 'Subcostal, just proximal to the hepatic veins')}</small></label><span class="e-in">${numIn('ch-ivc', st.ivc, 'ivc', { label: 'IVC diameter in centimetres' })}<span class="e-u">cm</span></span></div>
          <div class="r-inline"><span class="lab">Collapses more than 50% with a sniff</span>${seg('collapse', [['yes', 'Yes'], ['no', 'No']], st.collapse === null ? '' : (st.collapse ? 'yes' : 'no'), 'Collapse')}</div>
          ${rap ? `<p class="r-answer">${rap.value} mmHg <span class="e-rap">${esc(rap.label)}, ${esc(rap.range)}</span></p>` : '<p class="r-small">Enter the diameter and the collapse.</p>'}
          ${(d.ivc.notes || []).map((n) => `<p class="r-small">${esc(n)}</p>`).join('')}</div></section>`;
      }
      h += `<footer class="r-footer">${eyebrow('Sources')}${d.sources.map((s) => `<div class="r-src"><p>${esc(s.citation)}</p>${s.url ? `<a href="${esc(s.url)}" target="_blank" rel="noopener">Open ${I.ext}</a>` : ''}</div>`).join('')}${(d.notes || []).map((n) => footnote(n)).join('')}${footnote('Reviewed ' + (d.reviewed || '') + '. A reference, not a report: measure the way the guideline describes, and read borderline values with the whole study.')}</footer>`;
      return h + `</div>`;
    }, {
      sex(el) { st.sex = el.dataset.v; },
      height(el) { st.height = el.value; },
      weight(el) { st.weight = el.value; },
      group(el) { st.group = el.dataset.v; },
      val(el) { st.vals[el.dataset.k] = el.value; },
      unit(el) { st.raw[el.dataset.k] = !st.raw[el.dataset.k]; },
      ivc(el) { st.ivc = el.value; },
      collapse(el) { st.collapse = el.dataset.v === 'yes'; },
    });
    if (!data()) c.loadBundle().then(update);
  }

  // ---------- ASE diastolic function (filled in from the guideline research) ----------
  function mountDiastolic(host, c) {
    if (window.PSDiastolic) return window.PSDiastolic(host, c);
    host.innerHTML = '<p class="r-muted">Loading…</p>';
  }

  window.PSEcho = { mountChamber, mountDiastolic };
})();
