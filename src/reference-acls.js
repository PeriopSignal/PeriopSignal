/* Periop Signal ACLS tool for the website's Reference tab: a code clock that starts when the tool opens, the
   2-minute CPR cycle, drug and shock prompts with doses for the patient, checklists and a timestamped log to
   copy into the record. The rules live in src/reference-logic.js (R.acls); the content in reference.json
   ("acls"). The code stays in this page's memory while it is open (leaving the tool and coming back resumes
   it) and is never stored; "End code" clears it. */
(function () {
  'use strict';
  let live = null;            // the running code, kept across visits to the tool until it is ended
  let audio = null;           // WebAudio context, opened on the first tap (browsers allow sound only after one)

  function chime() {
    try {
      if (!audio) return;
      if (audio.state === 'suspended') audio.resume();
      const t0 = audio.currentTime;
      [[880, 0], [660, 0.22]].forEach(([f, d]) => {
        const o = audio.createOscillator(), g = audio.createGain();
        o.type = 'sine'; o.frequency.value = f;
        g.gain.setValueAtTime(0.0001, t0 + d);
        g.gain.exponentialRampToValueAtTime(0.35, t0 + d + 0.02);
        g.gain.exponentialRampToValueAtTime(0.0001, t0 + d + 0.18);
        o.connect(g).connect(audio.destination);
        o.start(t0 + d); o.stop(t0 + d + 0.2);
      });
    } catch (e) { /* sound is a courtesy; the prompt on screen is the alert */ }
  }
  function buzz() { try { if (navigator.vibrate) navigator.vibrate([180, 90, 180]); } catch (e) { /* not on iOS */ } }

  function mount(host, c) {
    const { R, F, esc, eyebrow, seg, numIn, footnote, I, checkRow } = c;
    const A = R.acls;
    const data = () => (c.bundle() && c.bundle().acls) || null;
    const ui = { joules: '', confirmEnd: false, ended: null, fired: new Set(), lastCycleAlert: -1 };
    const now = () => Date.now() - (live ? live.startedAt : Date.now());
    const wall = (ms) => { const d = new Date(ms); const p = (n) => String(n).padStart(2, '0'); return `${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`; };
    const modeOf = (d) => d.modes.find((m) => m.id === live.mode) || d.modes[0];

    function start(d) {
      live = A.session(Date.now(), 'arrest', 'adult');
      A.add(live, 0, 'start', 'Code clock started');
      ui.fired = new Set(); ui.lastCycleAlert = -1;
      return live;
    }

    function actionButton(id, a, d, t) {
      const n = A.count(live, id), max = A.maxDoses(a, live), full = n >= max;
      let detail = '';
      if (a.kind === 'drug') { const ds = A.dose(a, live, n); detail = ds ? ds.text : ''; }
      else if (a.kind === 'shock') { const e = A.energy(a, live, n); detail = e ? e.text : ''; }
      else detail = a.detail || '';
      const tm = A.timer(a, live, id, t);
      let status = '';
      if (full) status = `<span class="a-st">Max doses given</span>`;
      else if (tm && tm.state === 'wait') status = `<span class="a-st">Next in ${A.clock(tm.remaining * 1000)}</span>`;
      else if (tm && tm.state === 'due') status = `<span class="a-st due">Due now</span>`;
      else if (tm && tm.state === 'overdue') status = `<span class="a-st over">Overdue ${A.clock((tm.since - a.repeat.max) * 1000)}</span>`;
      const tone = a.kind === 'rhythm' ? ` a-${esc(a.rhythm || 'r')}` : a.kind === 'shock' ? ' a-shock' : a.kind === 'drug' ? ' a-drug' : '';
      return `<button type="button" class="a-act${tone}" data-a="act" data-k="${esc(id)}"${full ? ' disabled' : ''}><span class="at"><strong>${esc(a.label)}</strong>${n ? `<span class="a-n">×${n}</span>` : ''}</span>${detail ? `<span class="ad">${esc(detail)}</span>` : ''}${status}</button>`;
    }

    const update = c.view(host, () => {
      const d = data();
      if (!d) return `<p class="r-muted">${c.bundle() ? 'The ACLS content is not in this copy of the reference file yet; reload in a minute.' : 'Loading the reference values…'}</p>`;
      if (ui.ended) {
        return `<div class="r-stack"><section class="r-card a-ended">${eyebrow('Code ended')}<p class="r-headline big">Ended at ${esc(ui.ended.wall)} after ${esc(ui.ended.dur)}</p><p class="r-small">The clock is stopped and the log was cleared.</p><div class="r-btns"><button type="button" class="r-ghost" data-a="newCode">Start a new code</button></div></section></div>`;
      }
      if (!live) start(d);
      const t = now(), mode = modeOf(d), child = live.patient === 'child';
      let h = `<div class="r-stack a-code">`;
      // clock bar
      const cyc = mode.cycle ? A.cycle(live, d, t) : null;
      const left = cyc ? d.cycleSec - cyc.elapsed : 0;
      h += `<section class="a-clock${cyc && left <= 0 ? ' alarm' : ''}"><div class="a-row"><div class="a-time"><span class="a-big">${A.clock(t)}</span><span class="a-sub">Code time · started ${esc(wall(live.startedAt))}</span></div>`;
      if (cyc) h += `<div class="a-cyc"><span class="a-sub">${left > 0 ? 'Rhythm check in' : 'Rhythm check'}</span><span class="a-mid">${left > 0 ? A.clock(left * 1000) : 'Now'}</span></div>`;
      h += `</div>${cyc ? `<div class="a-bar"><i style="width:${Math.max(0, Math.min(100, (cyc.elapsed / d.cycleSec) * 100)).toFixed(1)}%"></i></div>` : ''}`;
      h += `<div class="a-row a-ctl">${seg('patient', [['adult', 'Adult'], ['child', 'Child']], live.patient, 'Patient')}<button type="button" class="r-ghost sm" data-a="endAsk">End code</button></div></section>`;
      if (ui.confirmEnd) h += `<section class="r-card a-confirm"><p><strong>End this code?</strong> The clock stops and the log is cleared; copy it first if you need it.</p><div class="r-btns"><button type="button" class="r-ghost" data-a="copyLog">${I.copy}Copy log</button><button type="button" class="r-ghost danger" data-a="endYes">End code</button><button type="button" class="r-ghost" data-a="endNo">Keep going</button></div></section>`;
      if (child) h += c.weightField('acls-weight', live.weightText || '', 'Enter the weight for the child doses and energies; it clears when the code ends.');
      // modes
      h += `<div class="r-tabs" role="tablist" aria-label="Algorithm">${d.modes.map((m) => `<button type="button" role="tab" data-a="mode" data-v="${esc(m.id)}" aria-selected="${m.id === mode.id}">${esc(m.short || m.name)}</button>`).join('')}</div>`;
      if (mode.patients && !mode.patients.includes(live.patient)) h += c.caution(mode.patientNote || `This protocol is written for ${mode.patients.join(' and ')} patients.`);
      if (mode.note) h += `<p class="r-small a-note">${esc(mode.note)}</p>`;
      // deadlines
      const dl = A.deadlines(live, d, t);
      if (dl.length) h += `<div class="a-dls">${dl.map((x) => `<div class="a-dl${x.remaining <= 0 ? ' over' : x.remaining <= 60 ? ' near' : ''}"><span>${esc(x.label)}</span><strong>${x.remaining > 0 ? A.clock(x.remaining * 1000) + ' left' : A.clock(-x.remaining * 1000) + ' over'}</strong></div>`).join('')}</div>`;
      // prompts
      const ps = A.prompts(live, d, t);
      if (cyc && left <= 0) ps.unshift({ id: 'cycle', level: 'now', text: mode.cycleText || 'Rhythm check: pause compressions under 10 seconds, switch compressors, then log the rhythm.', action: null, alert: true });
      if (ps.length) {
        h += `<section class="a-prompts" aria-live="polite">${ps.map((p) => {
          const a = p.action ? d.actions[p.action] : null;
          return `<div class="a-p ${esc(p.level)}"><p>${esc(p.text)}</p>${a ? `<button type="button" class="a-give" data-a="act" data-k="${esc(p.action)}">${a.kind === 'shock' ? 'Shock given' : a.kind === 'drug' ? 'Given' : 'Done'}</button>` : ''}</div>`;
        }).join('')}</section>`;
      }
      // action groups
      for (const g of mode.groups || []) {
        const ids = g.actions.filter((id) => d.actions[id] && (!d.actions[id].patients || d.actions[id].patients.includes(live.patient)));
        if (!ids.length) continue;
        h += `<section class="r-sec">${eyebrow(g.title)}`;
        const shockId = ids.find((id) => d.actions[id].kind === 'shock');
        if (shockId) {
          const e = A.energy(d.actions[shockId], live, A.count(live, shockId));
          h += `<div class="r-inline a-j"><span class="lab">Energy used for the next shock (J)</span>${numIn('acls-j', ui.joules, 'joules', { label: 'Shock energy in joules', ph: e && e.joules ? String(e.joules) : 'J' })}</div>`;
        }
        h += `<div class="a-grid">${ids.map((id) => actionButton(id, d.actions[id], d, t)).join('')}</div>`;
        if (g.note) h += footnote(g.note);
        h += `</section>`;
      }
      // decision tree
      const tr = A.tree(live, d);
      if (tr) {
        h += `<section class="r-sec">${eyebrow(tr.tree.title || 'Algorithm')}<div class="r-card a-tree">`;
        if (tr.path.length) h += `<div class="a-path">${tr.path.map((id) => `<span>${esc(tr.tree.nodes[id].crumb || tr.tree.nodes[id].q || tr.tree.nodes[id].title || '')}</span>`).join('')}<button type="button" class="r-link" data-a="back">${I.reset} Back</button></div>`;
        const node = tr.node;
        if (node.title) h += `<p class="a-ttl">${esc(node.title)}</p>`;
        if (node.text) h += `<p class="a-tx">${esc(node.text)}</p>`;
        if (node.items) h += c.takeList(node.items);
        if (node.q) h += `<p class="a-q">${esc(node.q)}</p><div class="a-opts">${node.options.map((o, i) => `<button type="button" class="a-opt" data-a="choose" data-k="${i}">${esc(o.label)}</button>`).join('')}</div>`;
        if (node.actions && node.actions.length) h += `<div class="a-grid">${node.actions.filter((id) => d.actions[id]).map((id) => actionButton(id, d.actions[id], d, t)).join('')}</div>`;
        h += `</div></section>`;
      }
      // checklists
      for (const l of mode.lists || []) {
        if (l.patient && l.patient !== live.patient) continue;
        const done = l.items.filter((x) => A.count(live, 'chk:' + l.id + ':' + x.id) > 0).length;
        h += `<section class="r-sec"><div class="r-sechead"><h3>${esc(l.title)}</h3><span class="${done === l.items.length ? 'ok' : ''}">${done}/${l.items.length}</span></div>`;
        h += `<div class="r-card flush r-checks">${l.items.map((x, i) => checkRow('chk', l.id + ':' + x.id, i + 1, x.label + (x.detail ? ' — ' + x.detail : ''), A.count(live, 'chk:' + l.id + ':' + x.id) > 0, 'var(--accent)')).join('')}</div>`;
        if (l.note) h += footnote(l.note);
        h += `</section>`;
      }
      // log
      h += `<section class="r-sec a-logsec"><div class="r-rowtop">${eyebrow(`Log · ${live.log.length} ${live.log.length === 1 ? 'entry' : 'entries'}`)}<button type="button" class="r-ghost sm" data-a="copyLog">${I.copy}Copy log</button></div><div class="r-card flush a-log">`;
      const rows = live.log.slice().reverse();
      h += rows.map((e) => `<div class="a-le"><span class="lt">${esc(wall(live.startedAt + e.t))}</span><span class="lc">+${A.clock(e.t)}</span><span class="lx">${esc(e.text)}</span>${e.id === 'start' ? '' : `<button type="button" class="a-x" data-a="unlog" data-k="${live.log.indexOf(e)}" aria-label="Remove this entry">${I.x}</button>`}</div>`).join('');
      h += `</div><p class="r-small">Clock times are this device's; the log stays on this page and clears when the code ends.</p></section>`;
      // sources
      const src = (mode.sources || []).map((id) => d.sources.find((s) => s.id === id)).filter(Boolean);
      h += `<footer class="r-footer">${eyebrow('Sources')}${src.map((s) => `<div class="r-src"><p>${esc(s.citation)}</p>${s.url ? `<a href="${esc(s.url)}" target="_blank" rel="noopener">Open ${I.ext}</a>` : ''}</div>`).join('')}${(d.notes || []).map((n) => footnote(n)).join('')}${footnote('Reviewed ' + (d.reviewed || '') + '. Prompts follow the guideline sequence; the team leader decides.')}</footer>`;
      return h + `</div>`;
    }, {
      patient(el) { live.patient = el.dataset.v === 'child' ? 'child' : 'adult'; A.add(live, now(), null, `Patient: ${live.patient}`, { kind: 'note' }); },
      weight(el) { live.weightText = el.value; live.weight = R.num(el.value); },
      joules(el) { ui.joules = el.value; },
      mode(el) {
        const d = data(), m = d.modes.find((x) => x.id === el.dataset.v);
        if (!m || m.id === live.mode) return false;
        live.mode = m.id; A.add(live, now(), null, `Switched to ${m.name}`, { kind: 'note' });
      },
      act(el) {
        const d = data(), id = el.dataset.k, a = d.actions[id];
        if (!a) return false;
        const n = A.count(live, id);
        if (n >= A.maxDoses(a, live)) return false;
        A.add(live, now(), id, A.entryText(a, live, n, R.num(ui.joules)));
        if (a.goto && d.modes.some((m) => m.id === a.goto)) { live.mode = a.goto; A.add(live, now(), null, `Switched to ${d.modes.find((m) => m.id === a.goto).name}`, { kind: 'note' }); }
      },
      chk(el) {
        const d = data(), [lid, iid] = el.dataset.k.split(':'), id = 'chk:' + lid + ':' + iid;
        const mode = modeOf(d), l = (mode.lists || []).find((x) => x.id === lid), item = l && l.items.find((x) => x.id === iid);
        if (!item) return false;
        if (A.count(live, id) > 0) { const e = live.log.slice().reverse().find((x) => x.id === id); A.remove(live, e); }
        else A.add(live, now(), id, `${l.verb || 'Done'}: ${item.label}`);
      },
      choose(el) {
        const d = data(), tr = A.tree(live, d), o = tr && tr.node.options[Number(el.dataset.k)];
        if (!o) return false;
        A.choose(live, d, now(), o.next, o.label);
      },
      back() { A.back(live, data()); },
      unlog(el) { const e = live.log[Number(el.dataset.k)]; if (e && e.id !== 'start') A.remove(live, e); },
      copyLog() { F.copyText(A.logText(live, wall), 'Log copied'); return false; },
      endAsk() { ui.confirmEnd = !ui.confirmEnd; },
      endNo() { ui.confirmEnd = false; },
      endYes() { ui.ended = { wall: wall(Date.now()), dur: A.clock(now()) }; live = null; ui.confirmEnd = false; ui.joules = ''; release(); },
      newCode() { ui.ended = null; start(data()); requestWake(); },
    });

    // Alerts: a prompt marked alert, or the end of a cycle, chimes and vibrates once when it appears.
    function tick() {
      const d = data();
      if (!d || !live || ui.ended) return;
      update();
      const t = now(), mode = modeOf(d);
      const active = new Set(A.prompts(live, d, t).filter((p) => p.alert).map((p) => p.id));
      let fire = [...active].some((id) => !ui.fired.has(id));
      ui.fired = active;
      if (mode.cycle) {
        const cyc = A.cycle(live, d, t);
        if (cyc.elapsed >= d.cycleSec && ui.lastCycleAlert !== cyc.from) { ui.lastCycleAlert = cyc.from; fire = true; }
      }
      if (fire) { chime(); buzz(); }
    }
    // Sound needs a tap first: open the audio context on the first one inside the tool.
    host.addEventListener('pointerdown', () => {
      try { if (!audio) audio = new (window.AudioContext || window.webkitAudioContext)(); if (audio.state === 'suspended') audio.resume(); } catch (e) { audio = null; }
    });
    // Keep the screen awake while the code runs (where the browser allows it).
    let lock = null;
    async function requestWake() { try { if ('wakeLock' in navigator && document.visibilityState === 'visible') lock = await navigator.wakeLock.request('screen'); } catch (e) { lock = null; } }
    function release() { try { if (lock) lock.release(); } catch (e) { /* already released */ } lock = null; }
    const onVis = () => { if (document.visibilityState === 'visible' && live) requestWake(); };
    document.addEventListener('visibilitychange', onVis);
    requestWake();
    // Sticky clock below the site header.
    const mast = document.querySelector('.masthead');
    if (mast) host.style.setProperty('--mast-h', mast.getBoundingClientRect().height + 'px');
    const timer = setInterval(tick, 500);
    if (!data()) c.loadBundle().then(update);
    return () => { clearInterval(timer); document.removeEventListener('visibilitychange', onVis); release(); };
  }

  window.PSAcls = { mount, running: () => !!live, elapsed: () => (live ? Date.now() - live.startedAt : 0) };
})();
