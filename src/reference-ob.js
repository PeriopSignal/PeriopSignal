/* Periop Signal OB Emergencies for the website's Reference tab: one checklist per obstetric crisis (maternal
   cardiac arrest, hemorrhage, and the rest), with the doses for the patient's weight and, for the arrest, a clock
   for the 4- to 5-minute delivery decision. Built from the primary sources (AHA, SOAP, ACOG, SMFM, ASRA and others);
   the Stanford Obstetric Anesthesia Emergency Manual is linked, not reproduced. Content: reference.json
   "obEmergency"; the app has the same tool (ObEmergencyView.swift). Nothing is stored: the weight, the ticks and
   the clock live in this page's memory and clear when the page closes. */
(function () {
  'use strict';
  const mem = { ev: null, weights: {}, done: {}, clock: {} };   // kept while the page is open; weights by whose: '' the mother's, 'newborn'
  const cur = (d) => d.events.find((e) => e.id === mem.ev) || d.events[0];

  function mount(host, c) {
    const { R, I, esc, eyebrow, takeList, factTable, refTable, checkRow, weightField, caution, footnote, sourceLine, ghostLink, progress } = c;
    const tint = 'var(--accent)';
    const data = () => (c.bundle() && c.bundle().obEmergency) || null;
    const clock = (ms) => { const s = Math.max(0, Math.floor(ms / 1000)); return Math.floor(s / 60) + ':' + String(s % 60).padStart(2, '0'); };

    function doses(ev) {
      const wf = ev.weightFor || {}, key = wf.key || '';
      const entered = R.num(mem.weights[key] || ''), tooHigh = entered !== null && wf.maxKg && entered > wf.maxKg;
      const w = tooHigh ? null : entered;
      let h = `<section class="r-card" style="border-color:color-mix(in srgb, ${tint} 40%, var(--line))">${eyebrow(wf.eyebrow || 'Doses for this patient', tint)}${weightField('ob-weight' + (key ? '-' + key : ''), mem.weights[key] || '', wf.prompt || 'Enter the weight: the doses below are per kilogram until you do.', wf.title)}`;
      if (tooHigh) h += caution(wf.maxText || 'Check the weight.');
      h += `<div class="r-doses">`;
      for (const d of ev.weightDoses) {
        let text;
        if (w === null) text = R.fmt(d.perKg) + (d.perKgHigh ? '–' + R.fmt(d.perKgHigh) : '') + ' ' + d.unit + '/kg';
        else if (d.aboveKg && w > d.aboveKg && d.aboveText) text = d.aboveText;
        else text = R.peds.doseText(d.perKg, d.perKgHigh ?? null, d.unit, w, null, d.max ?? null).text;
        h += `<div class="dr"><div class="dl"><span>${esc(d.label)}</span>${d.note ? `<small>${esc(d.note)}</small>` : ''}</div><div class="dv"><span class="${w === null ? 'muted' : ''}">${esc(text)}</span></div></div>`;
      }
      return h + `</div></section>`;
    }

    function timer(ev) {
      const t0 = mem.clock[ev.id], tm = ev.timer;
      const el = t0 ? Date.now() - t0 : 0;
      let h = `<section class="r-card ob-clock${t0 ? ' on' : ''}"><div class="ob-row"><div>${eyebrow(tm.label || 'Clock', tint)}<span class="ob-big">${clock(el)}</span></div>`;
      h += t0 ? `<button type="button" class="r-ghost sm" data-a="clockReset">${I.reset}Reset</button>` : `<button type="button" class="r-cta" data-a="clockStart">${esc(tm.start || 'Start the clock')}</button>`;
      h += `</div><ol class="ob-marks">`;
      for (const m of tm.marks || []) {
        const st = !t0 ? '' : el >= m.sec * 1000 ? ' past' : el >= (m.sec - 60) * 1000 ? ' near' : '';
        h += `<li class="ob-mark${st}"><span class="ob-at">${clock(m.sec * 1000)}</span><span>${esc(m.text)}</span></li>`;
      }
      return h + `</ol>${tm.note ? `<p class="r-small">${esc(tm.note)}</p>` : ''}</section>`;
    }

    const update = c.view(host, () => {
      const d = data();
      if (!d) return `<p class="r-muted">${c.bundle() ? 'The OB emergency content is not in this copy of the reference file yet; reload in a minute.' : 'Loading the checklists…'}</p>`;
      const ev = d.events.find((e) => e.id === mem.ev) || d.events[0];
      const done = mem.done[ev.id] || (mem.done[ev.id] = {});
      const steps = (ev.sections || []).map((s, i) => (s.kind === 'steps' ? i : -1)).filter((i) => i >= 0);
      const total = steps.reduce((t, i) => t + (ev.sections[i].items || []).length, 0);
      const doneN = Object.values(done).reduce((t, s) => t + s.size, 0);
      let h = `<div class="r-stack ob">`;
      h += `<div class="r-tabs ob-tabs" role="tablist" aria-label="Emergency">${d.events.map((e) => `<button type="button" role="tab" data-a="ev" data-v="${esc(e.id)}" aria-selected="${e.id === ev.id}">${esc(e.short || e.title)}</button>`).join('')}</div>`;
      h += `<header class="r-qhead"><div class="r-eyes">${eyebrow('Emergency checklist', tint)}</div><h2 class="ob-title">${esc(R.titleCase(ev.title))}</h2><p class="r-lede">${esc(ev.summary || '')}</p></header>`;
      if (ev.timer) h += timer(ev);
      if (ev.weightDoses && ev.weightDoses.length) h += doses(ev);
      if (total > 0) h += `<section class="r-card" style="border-color:color-mix(in srgb, ${tint} 40%, var(--line))">${progress(doneN, total, tint, 'Emergency Checklist', 'done', 'resetChecks')}</section>`;
      (ev.sections || []).forEach((s, i) => {
        const isCheck = steps.includes(i), dn = done[i] || new Set();
        h += `<section class="r-sec">`;
        if (s.heading) h += `<div class="r-sechead"><h3>${esc(R.titleCase(s.heading))}</h3>${isCheck ? `<span class="${dn.size === (s.items || []).length ? 'ok' : ''}">${dn.size}/${(s.items || []).length}</span>` : ''}</div>`;
        if (s.kind === 'text') h += `<p class="r-text">${esc(s.text || '')}</p>`;
        else if (s.kind === 'list') h += takeList(s.items || []);
        else if (s.kind === 'steps') h += `<div class="r-card flush r-checks" style="border-color:color-mix(in srgb, ${tint} 30%, var(--line))">${(s.items || []).map((t, j) => checkRow('step', i + ':' + j, j + 1, t, dn.has(j), tint)).join('')}</div>`;
        else if (s.kind === 'facts') h += factTable(s.rows || []);
        else if (s.kind === 'table') h += refTable(s.columns || [], s.rows || []);
        if (s.note) h += `<p class="r-note">${esc(s.note)}</p>`;
        h += `</section>`;
      });
      const srcs = (ev.sources || []).map((id) => (d.sources || []).find((s) => s.id === id)).filter(Boolean);
      h += `<footer class="r-footer">${eyebrow(srcs.length > 1 ? 'Sources' : 'Source')}${srcs.map(sourceLine).join('')}`;
      if (d.manual) h += `<div class="ob-manual">${eyebrow('Stanford OB Emergency Manual')}<p class="r-small">${esc(d.manual.note || '')}</p>${d.manual.url ? `<div class="r-btns">${ghostLink(d.manual.url, I.ext, 'Open the manual', true)}</div>` : ''}</div>`;
      for (const n of d.notes || []) h += footnote(n);
      h += footnote('Condensed by Periop Signal' + (d.reviewed ? ', reviewed ' + d.reviewed : '') + '. A checklist to prompt, not a protocol: follow your institution’s obstetric emergency plan and confirm doses against the sources.');
      return h + `</footer></div>`;
    }, {
      ev(el) { mem.ev = el.dataset.v; window.scrollTo({ top: Math.max(0, host.getBoundingClientRect().top + window.scrollY - 90), behavior: 'smooth' }); },
      weight(el) { const d = data(); if (!d) return false; const k = (cur(d).weightFor || {}).key || ''; mem.weights[k] = el.value; },
      step(el) {
        const d = data(); if (!d) return false;
        const ev = d.events.find((e) => e.id === mem.ev) || d.events[0];
        const done = mem.done[ev.id] || (mem.done[ev.id] = {});
        const [i, j] = el.dataset.k.split(':').map(Number);
        const s = done[i] || (done[i] = new Set());
        if (s.has(j)) s.delete(j); else s.add(j);
      },
      resetChecks() { const d = data(); const ev = d && (d.events.find((e) => e.id === mem.ev) || d.events[0]); if (ev) mem.done[ev.id] = {}; },
      clockStart() { const d = data(); const ev = d && (d.events.find((e) => e.id === mem.ev) || d.events[0]); if (ev) mem.clock[ev.id] = Date.now(); },
      clockReset() { const d = data(); const ev = d && (d.events.find((e) => e.id === mem.ev) || d.events[0]); if (ev) delete mem.clock[ev.id]; },
    });
    const tick = setInterval(() => {
      if (!host.isConnected) return;
      const d = data(), ev = d && (d.events.find((e) => e.id === mem.ev) || d.events[0]);
      if (ev && ev.timer && mem.clock[ev.id]) update();
    }, 1000);
    if (!data()) c.loadBundle().then(update);
    return () => clearInterval(tick);
  }

  window.PSOb = { mount };
})();
