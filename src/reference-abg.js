// ABG interpretation (Reference tab, General Anesthesia): pH, PaCO2 and HCO3 in; primary disorder, expected
// compensation and any second disorder out. Rules: R.abg in reference-logic.js; numbers: reference.json "abg".
// The iPhone app has the same tool (AbgView.swift).
(function () {
  'use strict';

  const FIELDS = [
    ['ph', 'pH', '', 'ph'],
    ['paco2', 'PaCO₂', 'mmHg', 'paco2'],
    ['hco3', 'HCO₃', 'mEq/L', 'hco3'],
  ];
  const TONE = { ok: 'var(--new)', bad: 'var(--accent)', info: 'var(--accent-2)' };

  function mount(host, c) {
    const { R, esc, eyebrow, numIn, resultCard, footnote, I } = c;
    const A = R.abg;
    const st = { v: {} };
    const num = (k) => R.num(st.v[k]);
    const data = () => (c.bundle() && c.bundle().abg) || null;
    const read = (d) => A.read({ ph: num('ph'), paco2: num('paco2'), hco3: num('hco3') }, d);
    const fmt = (k, x) => (k === 'ph' ? A.fph(x) : A.f1(x));
    const range = (k, r) => (k === 'ph' ? r.map((x) => x.toFixed(2)) : r.map((x) => A.f1(x))).join('–');

    /** The measured value against the band(s) the rule expects. */
    function strip(v) {
      const vals = v.bands.flatMap((b) => [b.lo, b.hi]).concat([v.measured]);
      let lo = Math.min(...vals), hi = Math.max(...vals);
      const pad = Math.max((hi - lo) * 0.2, 2);
      lo = Math.max(0, Math.floor(lo - pad)); hi = Math.ceil(hi + pad);
      const x = (n) => (((n - lo) / (hi - lo)) * 100).toFixed(2);
      const label = `${v.variable} ${A.f1(v.measured)} ${v.unit} against ` + v.bands.map((b) => `${b.label.toLowerCase()} ${A.f1(b.lo)} to ${A.f1(b.hi)}`).join(' and ');
      return `<div class="abg-strip" role="img" aria-label="${esc(label)}">
        <div class="abg-track">${v.bands.map((b) => `<span class="abg-band ${b.id}" style="left:${x(b.lo)}%;width:${(x(b.hi) - x(b.lo)).toFixed(2)}%"></span>`).join('')}<span class="abg-mark" style="left:${x(v.measured)}%"><b>${esc(A.f1(v.measured))}</b></span></div>
        <div class="abg-axis"><span>${lo}</span><span>${esc(v.variable)}, ${esc(v.unit)}</span><span>${hi}</span></div>
        <div class="abg-key">${v.bands.map((b) => `<span><i class="abg-sw ${b.id}"></i>${esc(b.label)} ${esc(A.f1(b.lo))}–${esc(A.f1(b.hi))}</span>`).join('')}<span><i class="abg-sw mark"></i>Measured ${esc(A.f1(v.measured))}</span></div>
      </div>`;
    }

    const update = c.view(host, () => {
      const d = data();
      if (!d) return `<p class="r-muted">${c.bundle() ? 'The ABG content is not in this copy of the reference file yet; reload in a minute.' : 'Loading the rules…'}</p>`;
      const r = read(d), N = d.normal;
      const tone = r.state !== 'read' ? 'var(--fg-3)' : r.headline === 'Check the Values' ? 'var(--amber)' : r.disorders.length ? 'var(--accent)' : 'var(--new)';
      let h = '<div class="r-stack">';
      // the gas
      h += `<section class="r-sec">${eyebrow('Arterial blood gas')}<div class="r-card flush">${FIELDS.map(([k, label, unit]) => {
        const typed = num(k), shown = typed !== null ? typed : (r.state === 'read' && r.derived === k ? r.values[k] : null);
        const fl = shown === null ? null : !(shown >= N[k][0] && shown <= N[k][1]);
        const ph = r.state === 'read' && r.derived === k ? '≈ ' + fmt(k, r.values[k]) : '—';
        const hint = `Normal ${range(k, N[k])}` + (r.state === 'read' && r.derived === k ? ' · calculated' : k === 'hco3' ? ' · leave blank to calculate' : '');
        return `<div class="r-meas"><label class="mt" for="abg-${k}"><span>${esc(label)}</span><small>${esc(hint)}</small></label>${fl === true ? '<i class="gd" style="background:var(--accent)" title="Outside the normal range"></i>' : (fl === false ? '<i class="gd" style="background:var(--new)" title="Normal"></i>' : '<i class="gd"></i>')}${numIn('abg-' + k, st.v[k], 'val', { k, label: label + (unit ? ' in ' + unit : ''), ph })}<span class="mu">${esc(unit)}</span></div>`;
      }).join('')}</div></section>`;
      // the reading
      let inner = `<div class="r-rowtop">${eyebrow('Acid–base', tone)}${r.state === 'read' ? `<button type="button" class="r-ghost sm" data-a="copy">${I.copy}Copy</button>` : ''}</div>`;
      inner += `<p class="r-headline big${r.state !== 'read' ? ' muted' : ''}">${esc(r.headline)}</p><p class="r-detail">${esc(r.explanation)}</p>`;
      if (r.visual) inner += strip(r.visual);
      if (r.steps.length) inner += `<div class="dd-steps">${r.steps.map((s) => `<div class="dd-step"><i style="background:${TONE[s.tone] || 'var(--fg-3)'}"></i><span><strong>${esc(s.label)}</strong> ${esc(s.text)}</span></div>`).join('')}</div>`;
      inner += r.cautions.map(c.caution).join('');
      h += resultCard(tone, inner);
      // the rules
      const order = [['metAcid', 'Metabolic acidosis'], ['metAlk', 'Metabolic alkalosis'], ['respAcidAcute', 'Acute respiratory acidosis'], ['respAcidChronic', 'Chronic respiratory acidosis'], ['respAlkAcute', 'Acute respiratory alkalosis'], ['respAlkChronic', 'Chronic respiratory alkalosis']];
      const rows = order.filter(([k]) => d.rules[k]).map(([k, name]) => [d.rules[k].name || name, d.rules[k].formula || '']);
      if (rows.length) h += `<section class="r-sec">${eyebrow('Expected compensation')}${c.factTable(rows)}</section>`;
      const srcs = d.sources || [];
      h += `<footer class="r-footer">${eyebrow(srcs.length > 1 ? 'Sources' : 'Source')}${srcs.map((s) => c.sourceLine(s)).join('')}${(d.notes || []).map((n) => footnote(n)).join('')}${footnote('Reviewed ' + (d.reviewed || '') + '. Interpret the gas with the history, the anion gap and the electrolytes; the rules give a range, not a diagnosis.')}</footer>`;
      return h + '</div>';
    }, {
      val(el) { st.v[el.dataset.k] = el.value; },
      copy() { const d = data(); if (d) c.F.copyText(A.summary(read(d)), 'Reading copied'); return false; },
    });
    if (!data()) c.loadBundle().then(update);
  }

  window.PSAbg = { mount };
})();
