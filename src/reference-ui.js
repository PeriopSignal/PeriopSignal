/* Periop Signal reference tab for the website: folders, search, favorites and every calculator and
   guided tool of the app, built on src/reference-logic.js (PSRef) and the feed's PSFeed helpers.
   Patient details (weight, age, times) live only in the open tool's memory and are never stored. */
(function () {
  'use strict';
  const R = window.PSRef, F = window.PSFeed;
  if (!R || !F) return;
  const esc = F.esc, LS = F.LS;
  const $ = (s, el) => (el || document).querySelector(s);
  const pad = (n) => String(n).padStart(2, '0');

  // ---------- icons ----------
  const svg = (inner, sw) => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="${sw || 1.9}" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${inner}</svg>`;
  const I = {
    search: svg('<circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/>', 2.2),
    chevR: svg('<path d="M9 5l7 7-7 7"/>', 2.2),
    chevL: svg('<path d="M15 5l-7 7 7 7"/>', 2.4),
    updown: svg('<path d="M8 9.5l4-4 4 4M8 14.5l4 4 4-4"/>', 2.2),
    star: svg('<path d="M12 3.5l2.6 5.3 5.9.9-4.3 4.1 1 5.8L12 16.9l-5.2 2.7 1-5.8-4.3-4.1 5.9-.9z"/>'),
    starFill: '<svg viewBox="0 0 24 24" fill="currentColor" stroke="currentColor" stroke-width="1.9" stroke-linejoin="round" aria-hidden="true"><path d="M12 3.5l2.6 5.3 5.9.9-4.3 4.1 1 5.8L12 16.9l-5.2 2.7 1-5.8-4.3-4.1 5.9-.9z"/></svg>',
    reset: svg('<path d="M4 12a8 8 0 1 0 2.4-5.7"/><path d="M4 4v4h4"/>', 2.1),
    ext: svg('<path d="M14 4h6v6M20 4l-9 9M19 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1h5"/>', 2.1),
    table: svg('<rect x="3.5" y="4.5" width="17" height="15" rx="2"/><path d="M3.5 9.5h17M3.5 14.5h17M9.5 9.5v10"/>'),
    doc: svg('<path d="M6 3h8l4 4v14H6z"/><path d="M14 3v4h4M9 12h6M9 16h6"/>'),
    copy: svg('<rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15V5a1 1 0 0 1 1-1h10"/>'),
    warn: '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 3L1.8 20.5h20.4z"/><path d="M12 9.5v5M12 17.5v.5" stroke="var(--surface)" stroke-width="2" stroke-linecap="round"/></svg>',
    info: svg('<circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 8h.01"/>', 2.1),
    check: svg('<path d="M5 12.5l4.5 4.5L19 7.5"/>', 3),
    plus: svg('<path d="M12 5v14M5 12h14"/>', 2.3),
    x: svg('<path d="M6 6l12 12M18 6L6 18"/>', 2.2),
    drop: svg('<path d="M12 3.5s6 6.4 6 10.9a6 6 0 0 1-12 0C6 9.9 12 3.5 12 3.5z"/>'),
    scale: svg('<path d="M5.5 20h13l-1.8-10.5H7.3z"/><circle cx="12" cy="6" r="2.4"/>'),
    // folders
    bolt: svg('<path d="M13 2.5L4.5 13.5h6l-1 8 8.5-11h-6z"/>'),
    clipboard: svg('<rect x="5" y="4.5" width="14" height="16.5" rx="2"/><path d="M9 3h6v3H9zM8.8 13l2.2 2.2 4.4-4.4"/>'),
    lungs: svg('<path d="M12 3v8.5M12 11.5l-2.2 2M12 11.5l2.2 2"/><path d="M8.8 7.5C5.8 7.8 3.5 12.6 3.5 17.6c0 1.4 1.2 2.2 2.5 1.7l3.1-1.2c.6-.3 1-.9 1-1.6V9.2c0-.9-.5-1.7-1.3-1.7z"/><path d="M15.2 7.5c3 .3 5.3 5.1 5.3 10.1 0 1.4-1.2 2.2-2.5 1.7l-3.1-1.2c-.6-.3-1-.9-1-1.6V9.2c0-.9.5-1.7 1.3-1.7z"/>'),
    syringe: svg('<path d="M17.5 2.5l4 4M19.5 4.5l-3 3M14 5l5 5M15.5 6.5L6 16l-1 3 3-1 9.5-9.5M2.5 21.5l3-3M9 10l2 2M11.5 7.5l2 2"/>'),
    heart: svg('<path d="M12 20s-7.5-4.6-7.5-10.4A4.2 4.2 0 0 1 12 7a4.2 4.2 0 0 1 7.5 2.6C19.5 15.4 12 20 12 20z"/>'),
    ivbag: svg('<path d="M9 3h6M8 5h8a2 2 0 0 1 2 2v7.5a4.5 4.5 0 0 1-4.5 4.5h-3A4.5 4.5 0 0 1 6 14.5V7a2 2 0 0 1 2-2z"/><path d="M12 19v3M9.5 10h3M9.5 13.5h3"/>'),
    child: svg('<circle cx="12" cy="5" r="2.4"/><path d="M7.5 10h9M12 10v5M12 15l-3 6M12 15l3 6"/>'),
    // tools
    vial: svg('<path d="M9 3h6M10 3v6.3L5.2 18A2 2 0 0 0 7 21h10a2 2 0 0 0 1.8-3L14 9.3V3"/><path d="M7.4 14.5h9.2"/>'),
    thermo: svg('<path d="M14 14.6V5a2 2 0 0 0-4 0v9.6a4 4 0 1 0 4 0z"/><path d="M12 9v7"/>'),
    wind: svg('<path d="M3 8.5h10.5A3 3 0 1 0 10.5 5.5M3 12.5h15a3 3 0 1 1-3 3M3 16.5h7"/>'),
    heartPulse: svg('<path d="M12 20s-7.5-4.6-7.5-10.4A4.2 4.2 0 0 1 12 7a4.2 4.2 0 0 1 7.5 2.6C19.5 15.4 12 20 12 20z"/><path d="M6.5 12.5h3l1.2-2.5 2 5 1.3-2.5h3.5"/>'),
    zzz: svg('<path d="M4 6.5h5L4 12.5h5M13 4h4l-4 5h4M14 13.5h6.5L14 20.5h6.5"/>'),
    cup: svg('<path d="M4.5 9h11v4.5a5 5 0 0 1-5 5h-1a5 5 0 0 1-5-5zM15.5 10h1.5a2.5 2.5 0 0 1 0 5h-1.5M8 3.5v2.5M12 3.5v2.5"/>'),
    pills: svg('<path d="M10.6 20a4.6 4.6 0 0 1-6.6-6.6l6-6a4.6 4.6 0 0 1 6.6 6.6z"/><path d="M7 10.4l6.6 6.6"/><circle cx="18.5" cy="18.5" r="2.6"/>'),
    bed: svg('<path d="M3 6.5v13M3 15h18v4.5M21 15v-2.5a3 3 0 0 0-3-3h-7.5V15"/><circle cx="6.8" cy="11.2" r="1.9"/>'),
    valve: svg('<rect x="3" y="4" width="18" height="16" rx="3"/><path d="M6 14h2.2l1.4-4.5 2.2 8 1.6-5.5 1.4 2H18"/>'),
    heartCircle: svg('<circle cx="12" cy="12" r="9"/><path d="M12 16.6s-4.2-2.5-4.2-5.6A2.3 2.3 0 0 1 12 9.7a2.3 2.3 0 0 1 4.2 1.3c0 3.1-4.2 5.6-4.2 5.6z"/>'),
    ruler: svg('<path d="M3.5 16.5L16.5 3.5l4 4-13 13z"/><path d="M7.5 12.5l1.8 1.8M10 10l1.8 1.8M12.5 7.5l1.8 1.8"/>'),
    inflow: svg('<path d="M3 18.5h3l2.2-11 3 11h2l2-6.5 2 6.5H21"/>'),
  };

  // ---------- reference.json ----------
  let bundle = null, bundlePromise = null, bundleFailed = false;
  function loadBundle() {
    if (!bundlePromise) {
      bundlePromise = fetch('reference.json', { cache: 'no-cache' })
        .then((r) => { if (!r.ok) throw new Error(r.status); return r.json(); })
        .then((b) => { bundle = b; bundleFailed = false; return b; })
        .catch(() => { bundleFailed = true; bundlePromise = null; return null; });
    }
    return bundlePromise;
  }
  const quickref = (id) => (bundle && bundle.quickrefs || []).find((q) => q.id === id) || null;

  // ---------- catalog: folders and tools ----------
  const FOLDERS = [
    { id: 'emergency', title: 'Emergency', icon: 'bolt', tint: 'var(--accent)', items: ['tool-acls', 'card-asra-last', 'card-mhaus-mh', 'tool-airway'],
      note: 'ACLS starts its code clock when it opens. The checklists take the patient’s weight at the top and work out the doses; the weight clears when you leave.' },
    { id: 'preoperative', title: 'Preoperative', icon: 'clipboard', tint: 'var(--accent-2)', items: ['tool-rcri', 'tool-ariscat', 'tool-stopbang', 'tool-fasting'] },
    { id: 'general-anesthesia', title: 'General Anesthesia', icon: 'lungs', tint: 'var(--t-thoracic-fg)', items: ['tool-ponv', 'tool-aldrete'] },
    { id: 'regional', title: 'Regional', icon: 'syringe', tint: 'var(--t-regional-fg)', items: ['tool-neuraxial', 'tool-local'] },
    { id: 'cardiothoracic', title: 'Cardiothoracic', icon: 'heart', tint: 'var(--t-cardiacSurgery-fg)', items: ['tool-valves', 'tool-intervention', 'tool-chamber', 'tool-diastolic'] },
    { id: 'medications', title: 'Medications & Hematology', icon: 'ivbag', tint: 'var(--new)', items: ['tool-infusions'] },
    { id: 'pediatrics', title: 'Pediatrics', icon: 'child', tint: 'var(--t-pediatric-fg)', items: ['tool-peds'] },
  ];
  const T = (title, blurb, icon, keywords, mount, extra) => Object.assign({ title, blurb, icon, keywords: keywords || [], mount }, extra || {});
  const TOOLS = {
    'tool-acls': T('ACLS', 'Code clock, checklists and doses as it runs', 'heartPulse', ['acls', 'pals', 'code', 'code blue', 'cardiac arrest', 'arrest', 'cpr', 'resuscitation', 'defibrillation', 'defibrillator', 'shock', 'vf', 'vt', 'pea', 'asystole', 'epinephrine', 'adrenaline', 'amiodarone', 'lidocaine', 'bradycardia', 'tachycardia', 'atropine', 'adenosine', 'cardioversion', 'pacing', 'rosc', 'post-arrest', 'cals', 'resternotomy', 'cardiac surgery arrest', 'anaphylaxis', 'allergic reaction', 'timer'], (h) => window.PSAcls ? window.PSAcls.mount(h, ctxFor('tool-acls')) : notReady(h)),
    'card-asra-last': T('Local Anesthetic Toxicity', 'Checklist with lipid doses for the weight', 'vial', ['last', 'lipid', 'toxicity', 'local anesthetic'], (h) => mountQuickref(h, 'asra-last'), { quickref: 'asra-last' }),
    'card-mhaus-mh': T('Malignant Hyperthermia', 'Checklist with dantrolene for the weight', 'thermo', ['mh', 'dantrolene', 'hyperthermia', 'ryanodex'], (h) => mountQuickref(h, 'mhaus-mh'), { quickref: 'mhaus-mh' }),
    'tool-airway': T('Difficult Airway', 'Assessment in, plan and checklists out', 'wind', ['airway', 'intubat', 'laryngoscop', 'cricothyr', 'cannot ventilate', 'cicv', 'awake', 'videolaryngoscope', 'supraglottic', 'lma'], mountAirway),
    'tool-rcri': T('RCRI', 'Cardiac risk for non-cardiac surgery', 'heartPulse', [], (h) => mountScore(h, 'rcri'), { score: 'rcri' }),
    'tool-ariscat': T('ARISCAT', 'Postoperative pulmonary complications', 'lungs', [], (h) => mountScore(h, 'ariscat'), { score: 'ariscat' }),
    'tool-stopbang': T('STOP-Bang', 'Sleep apnea screening', 'zzz', [], (h) => mountScore(h, 'stopbang'), { score: 'stopbang' }),
    'tool-fasting': T('Fasting', 'Last intake in, earliest start out', 'cup', ['npo', 'fasting', 'fast', 'clear liquid', 'breast milk', 'formula', 'meal', 'gum', 'aspiration'], mountFasting),
    'tool-ponv': T('PONV', 'Apfel score, how many agents, rescue', 'pills', ['ponv', 'nausea', 'vomiting', 'antiemetic', 'apfel', 'ondansetron', 'dexamethasone', 'droperidol', 'amisulpride', 'aprepitant', 'scopolamine', 'palonosetron', 'granisetron', 'promethazine', 'rescue', 'prophylaxis'], mountPONV),
    'tool-aldrete': T('Modified Aldrete', 'Ready to leave recovery?', 'bed', [], (h) => mountScore(h, 'aldrete'), { score: 'aldrete' }),
    'tool-neuraxial': T('Blocks on Anticoagulants', 'Drug and last dose in, earliest block out', 'drop', ['anticoag', 'neuraxial', 'epidural', 'spinal', 'block', 'heparin', 'enoxaparin', 'lmwh', 'warfarin', 'apixaban', 'rivaroxaban', 'edoxaban', 'dabigatran', 'doac', 'fondaparinux', 'clopidogrel', 'prasugrel', 'ticagrelor', 'aspirin', 'thrombolytic', 'asra'], mountNeuraxial),
    'tool-local': T('Local Anesthetic Doses', 'One agent or a mixture, with Exparel', 'syringe', ['local anesthetic', 'local anaesthetic', 'max dose', 'maximum dose', 'exparel', 'liposomal', 'mixture', 'toxicity', 'mg/kg'], mountLocal),
    'tool-valves': T('ASE Valve Severity Grading', 'Echo numbers in, ASE grade out', 'valve', ['cardiothoracic', 'cardiac', 'valve', 'valvular', 'echo', 'tee', 'stenosis', 'regurgitation', 'aortic', 'mitral', 'tricuspid', 'vena contracta', 'eroa', 'pisa', 'gradient', 'ase'], mountValves),
    'tool-intervention': T('AHA/ACC Valve Intervention', 'Repair or replace? Prompted questions', 'heartCircle', ['cardiothoracic', 'cardiac', 'valve', 'valvular', 'stenosis', 'regurgitation', 'aortic', 'mitral', 'tricuspid', 'tavi', 'tavr', 'savr', 'avr', 'teer', 'mitraclip', 'pmbc', 'commissurotomy', 'repair', 'replacement', 'prosthesis', 'mechanical', 'bioprosthe', 'acc', 'aha'], mountIntervention),
    'tool-chamber': T('ASE Chamber Quantification', 'Sizes and function against the ASE cutoffs', 'ruler', ['cardiothoracic', 'cardiac', 'echo', 'tee', 'ase', 'chamber', 'quantification', 'dilated', 'dilation', 'lvidd', 'lvedd', 'lvesd', 'lv size', 'lv mass', 'hypertrophy', 'wall thickness', 'rwt', 'ejection fraction', 'lvef', 'la volume', 'lavi', 'atrial', 'rv', 'right ventricle', 'tapse', 'fac', 'basal', 'tricuspid annulus', 'annulus', 'aorta', 'aortic root', 'sinus', 'sinuses of valsalva', 'ivc', 'ra pressure', 'right atrium', 'rvot', 'strain', 'rimp', 'tei', 's prime'], (h) => window.PSEcho ? window.PSEcho.mountChamber(h, ctxFor('tool-chamber')) : notReady(h)),
    'tool-diastolic': T('ASE Diastolic Function', 'Grade and filling pressure, step by step', 'inflow', ['cardiothoracic', 'cardiac', 'echo', 'tee', 'ase', 'diastolic', 'diastology', 'dysfunction', 'filling pressure', 'lap', 'e/e', 'e/a', 'tr velocity', 'la strain', 'lars', 'pulmonary vein', 'hfpef', 'relaxation', 'restrictive'], (h) => window.PSEcho ? window.PSEcho.mountDiastolic(h, ctxFor('tool-diastolic')) : notReady(h)),
    'tool-infusions': T('Medications & Hematology', 'Drips, single doses, blood products and factors', 'ivbag', ['infusion', 'drip', 'pressor', 'vasopressor', 'inotrope', 'vasodilator', 'hemodynamic', 'bolus', 'mcg/kg/min', 'hematolog', 'coagulation', 'factor', 'pcc', 'antifibrinolytic', 'transfus', 'blood product', 'red cell', 'rbc', 'prbc', 'ffp', 'plasma', 'platelet', 'cryo', 'sedation', 'antiarrhythmic'], mountInfusions),
    'tool-peds': T('Pediatric Doses', 'Doses, tube sizes, fluids and blood volume', 'scale', ['pediatric', 'peds', 'child', 'weight', 'dose', 'dosing', 'ett', 'tube', 'lma', 'fluid', 'blood volume', 'mabl'], mountPeds),
  };
  // Quick references opened from a tool (not in a folder of their own).
  const CARD_TITLES = { 'asra-anticoagulation': 'ASRA Anticoagulation Table', 'asa-fasting': 'ASA Fasting', 'asa-difficult-airway': 'ASA Difficult Airway', 'ase-valve-severity': 'ASE Grading Tables', 'acc-aha-valve-intervention': 'ACC/AHA Valve Tables', 'ponv-consensus': 'PONV Consensus' };
  const folderOf = (id) => FOLDERS.find((f) => f.items.includes(id)) || null;
  const toolMeta = (id) => {
    if (TOOLS[id]) return TOOLS[id];
    if (id.startsWith('card-')) {
      const q = id.slice(5), ref = quickref(q);
      return T(ref ? R.titleCase(ref.title) : (CARD_TITLES[q] || 'Quick reference'), ref ? (ref.short || ref.society) : '', 'table', [], (h) => mountQuickref(h, q), { quickref: q });
    }
    return null;
  };
  // Hash names: only plain #names survive the artifact viewer, so routes are "reference", "folder-<id>", "tool-<id>", "card-<quickref id>".
  const isRefRoute = (h) => h === 'reference' || /^(folder|tool|card)-[a-z0-9-]+$/.test(h);

  // ---------- favorites (ids only; on this device) ----------
  const favs = {
    list: (() => { const v = LS.get('ps.ref.favorites', []); return Array.isArray(v) ? v.filter((x) => typeof x === 'string') : []; })(),
    has(id) { return this.list.includes(id); },
    toggle(id) {
      if (this.has(id)) this.list = this.list.filter((x) => x !== id); else this.list.push(id);
      LS.set('ps.ref.favorites', this.list);
      F.toast(this.has(id) ? 'Added to favorites' : 'Removed from favorites');
    },
  };

  // ---------- DOM patching: re-render a tool without replacing the field being typed in ----------
  function morphNode(from, to) {
    if (from.nodeType !== to.nodeType || from.nodeName !== to.nodeName) { from.replaceWith(to); return; }
    if (from.nodeType === 3 || from.nodeType === 8) { if (from.nodeValue !== to.nodeValue) from.nodeValue = to.nodeValue; return; }
    if (from.nodeType !== 1) return;
    for (let i = from.attributes.length - 1; i >= 0; i--) { const n = from.attributes[i].name; if (!to.hasAttribute(n)) from.removeAttribute(n); }
    for (let i = 0; i < to.attributes.length; i++) { const a = to.attributes[i]; if (from.getAttribute(a.name) !== a.value) from.setAttribute(a.name, a.value); }
    morphChildren(from, to);
    if (from.tagName === 'INPUT' || from.tagName === 'TEXTAREA') {
      const v = to.getAttribute('value') || '';
      if (from !== document.activeElement && from.value !== v) from.value = v;
    } else if (from.tagName === 'SELECT') {
      const opt = to.querySelector('option[selected]');
      const v = opt ? opt.getAttribute('value') : null;
      if (v !== null && from.value !== v) from.value = v;
    }
  }
  // Children match by key where they have one (their id, a data-key, or the first id inside them), so a section
  // appearing above a field never turns the field being typed in into a different one; the rest match by
  // position. Unwanted nodes are removed rather than the kept one moved, since moving a node blurs its field.
  const keyOf = (n) => {
    if (n.nodeType !== 1) return null;
    if (n.id) return '#' + n.id;
    if (n.dataset && n.dataset.key) return 'k:' + n.dataset.key;
    const d = n.querySelector('[id]');
    return d ? '>' + d.id : null;
  };
  function morphChildren(from, to) {
    const tc = Array.from(to.childNodes), tk = tc.map(keyOf);
    const keyed = new Map();
    for (let n = from.firstChild; n; n = n.nextSibling) { const k = keyOf(n); if (k && !keyed.has(k)) keyed.set(k, n); }
    let cur = from.firstChild;
    for (let i = 0; i < tc.length; i++) {
      const t = tc[i], k = tk[i];
      let match = null;
      if (k) { match = keyed.get(k) || null; keyed.delete(k); }
      else if (cur && cur.nodeType === t.nodeType && cur.nodeName === t.nodeName && !keyOf(cur)) match = cur;
      if (!match) { from.insertBefore(t, cur); continue; }
      if (match === cur) cur = cur.nextSibling;
      else {
        const later = new Set(tk.slice(i + 1).filter(Boolean));
        let reorder = false;
        for (let n = cur; n && n !== match; n = n.nextSibling) { const nk = keyOf(n); if (nk && later.has(nk)) { reorder = true; break; } }
        if (reorder) from.insertBefore(match, cur);
        else { while (cur && cur !== match) { const nx = cur.nextSibling; from.removeChild(cur); cur = nx; } cur = match.nextSibling; }
      }
      morphNode(match, t);
    }
    while (cur) { const nx = cur.nextSibling; from.removeChild(cur); cur = nx; }
  }
  function patch(host, html) { const t = document.createElement('template'); t.innerHTML = html; morphChildren(host, t.content); }

  /** A tool view: render() → HTML; actions keyed by data-a on clicked/changed elements. Returns update(). */
  function view(host, render, actions) {
    const update = () => patch(host, render());
    const run = (ev, kind) => {
      const el = ev.target.closest('[data-a]');
      if (!el || !host.contains(el)) return;
      const tag = el.tagName;
      const isField = tag === 'INPUT' || tag === 'SELECT' || tag === 'TEXTAREA';
      if (kind === 'click' && isField) return;
      if (kind === 'input' && !(tag === 'INPUT' && el.type !== 'datetime-local')) return;
      if (kind === 'change' && !(tag === 'SELECT' || el.type === 'datetime-local')) return;
      const fn = actions[el.dataset.a];
      if (!fn) return;
      if (kind === 'click' && (tag === 'A' && !el.getAttribute('href'))) ev.preventDefault();
      if (fn(el, ev) !== false) update();
    };
    host.addEventListener('click', (e) => run(e, 'click'));
    host.addEventListener('input', (e) => run(e, 'input'));
    host.addEventListener('change', (e) => run(e, 'change'));
    update();
    return update;
  }

  // ---------- shared pieces ----------
  const eyebrow = (text, color) => `<p class="r-eyebrow"${color ? ` style="color:${color}"` : ''}>${esc(text)}</p>`;
  const TONE = { low: 'var(--new)', moderate: 'var(--accent-2)', high: 'var(--accent)' };
  const GRADE_COLOR = { 1: 'var(--new)', 2: 'var(--accent-2)', 3: 'var(--accent)' };
  const numIn = (id, value, a, opts) => `<input class="r-in${opts && opts.wide ? ' wide' : ''}" id="${id}" data-a="${a}"${opts && opts.k ? ` data-k="${esc(opts.k)}"` : ''} type="text" inputmode="${opts && opts.signed ? 'text' : 'decimal'}" autocomplete="off" placeholder="${(opts && opts.ph) || '—'}" value="${esc(value || '')}" aria-label="${esc((opts && opts.label) || 'Value')}">`;
  function weightField(id, text, prompt) {
    const empty = R.num(text) === null;
    return `<div class="r-weight${empty ? '' : ' ok'}">
      <div class="wl">${I.scale}<span>Patient Weight</span>${empty ? '<span class="r-badge">Required</span>' : '<span class="r-cleared">Cleared when you leave</span>'}</div>
      <label class="wbox" for="${id}"><input id="${id}" data-a="weight" type="text" inputmode="decimal" autocomplete="off" placeholder="Enter weight" value="${esc(text)}" aria-label="Patient weight in kilograms"><span class="unit">kg</span></label>
      ${empty ? `<p class="wp">${esc(prompt || 'Enter the weight to calculate the doses.')}</p>` : ''}
    </div>`;
  }
  function compactWeight(id, text) {
    const empty = R.num(text) === null;
    return `<label class="r-cweight${empty ? '' : ' ok'}" for="${id}">${I.scale}<span class="cwl">Weight</span><input id="${id}" data-a="weight" type="text" inputmode="decimal" autocomplete="off" placeholder="—" value="${esc(text)}" aria-label="Patient weight in kilograms"><span class="unit">kg</span>${empty ? '<span class="r-badge">For totals</span>' : '<span class="r-cleared">Clears when you leave</span>'}</label>`;
  }
  const seg = (a, options, value, label) => `<div class="r-seg" role="group" aria-label="${esc(label || '')}">${options.map(([v, l]) => `<button type="button" data-a="${a}" data-v="${esc(v)}" aria-pressed="${String(v) === String(value)}">${esc(l)}</button>`).join('')}</div>`;
  const switchRow = (a, on, title, detail, opts) => `<button type="button" class="r-switchrow" role="switch" aria-checked="${!!on}" data-a="${a}"${opts && opts.k ? ` data-k="${esc(opts.k)}"` : ''}${opts && opts.tint ? ` style="--tint:${opts.tint}"` : ''}><span class="st"><span class="sl">${esc(title)}${opts && opts.points ? ` <span class="pts">+${opts.points}</span>` : ''}</span>${detail ? `<span class="sd">${esc(detail)}</span>` : ''}</span><span class="r-switch" aria-hidden="true"></span></button>`;
  const radioRow = (a, k, v, on, label, right) => `<button type="button" class="r-radio" data-a="${a}" data-k="${esc(k)}" data-v="${esc(v)}" aria-pressed="${!!on}"><span class="dot" aria-hidden="true"></span><span class="rl">${esc(label)}</span>${right ? `<span class="rr">${esc(right)}</span>` : ''}</button>`;
  const pills = (a, k, options, selected) => `<div class="r-pills">${options.map((o) => `<button type="button" class="r-pill" data-a="${a}" data-k="${esc(k)}" data-v="${esc(o)}" aria-pressed="${selected === o}">${esc(o)}</button>`).join('')}</div>`;
  function progress(done, total, tint, title, doneWord, resetAct) {
    const complete = total > 0 && done === total;
    return `<div class="r-prog" style="--tint:${tint}">
      <div class="ph"><span class="pi">${complete ? I.check : I.clipboard}</span><strong>${esc(title)}</strong><span class="pn${complete ? ' ok' : ''}">${done} of ${total} ${esc(doneWord || 'done')}</span>${resetAct && done > 0 ? `<button type="button" class="r-link" data-a="${resetAct}">${I.reset} Reset</button>` : ''}</div>
      <div class="bar"><i style="width:${total ? (100 * done / total).toFixed(1) : 0}%;${complete ? 'background:var(--new)' : ''}"></i></div>
    </div>`;
  }
  const checkRow = (a, k, n, text, done, tint) => `<button type="button" class="r-check" role="checkbox" aria-checked="${!!done}" data-a="${a}" data-k="${esc(k)}" style="--tint:${tint}"><span class="box" aria-hidden="true">${done ? I.check : n}</span><span class="tx">${esc(text)}</span></button>`;
  const takeList = (items) => `<ul class="r-take">${items.map((t) => `<li>${esc(t)}</li>`).join('')}</ul>`;
  const factTable = (rows) => `<div class="r-facts">${rows.map((r) => `<div class="fr"><span class="fl">${esc(r[0] || '')}</span><span class="fv">${esc(r.length > 1 ? r[1] : '')}</span></div>`).join('')}</div>`;
  function refTable(columns, rows) {
    return `<div class="r-table">${rows.map((r) => `<div class="tr"><p class="th">${esc(r[0] || '')}</p>${r.slice(1).map((c, j) => c ? `<div class="tc"><span class="tl">${esc(columns[j + 1] || '')}</span><span class="tv${c === '—' ? ' muted' : ''}">${esc(c)}</span></div>` : '').join('')}</div>`).join('')}</div>`;
  }
  const resultCard = (tone, inner) => `<section class="r-card r-result" style="--tone:${tone}">${inner}</section>`;
  const caution = (t) => `<p class="r-caution"><span>${I.warn}</span><span>${esc(t)}</span></p>`;
  const sourceLine = (s) => `<div class="r-src"><p>${esc(s.citation || s.title)}</p>${s.url ? `<a href="${esc(s.url)}" target="_blank" rel="noopener">Open ${I.ext}</a>` : ''}</div>`;
  const ghostLink = (href, icon, label, external) => `<a class="r-ghost" href="${esc(href)}"${external ? ' target="_blank" rel="noopener"' : ''}>${icon}${esc(label)}</a>`;
  const footnote = (t) => `<p class="r-foot">${esc(t)}</p>`;
  const monthYear = (s) => { if (!s) return ''; const [y, m] = s.split('-').map(Number); return ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'][(m || 1) - 1] + ' ' + y; };
  const WD = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'], MO = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const fmtWhen = (ms) => { const d = new Date(ms); return `${WD[d.getDay()]} ${d.getDate()} ${MO[d.getMonth()]}, ${pad(d.getHours())}:${pad(d.getMinutes())}`; };
  const fmtClock = (ms) => { const d = new Date(ms); return `${pad(d.getHours())}:${pad(d.getMinutes())}`; };
  const toLocalInput = (ms) => { const d = new Date(ms); return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`; };
  const fromLocalInput = (s) => { if (!s) return null; const d = new Date(s); return isNaN(d.getTime()) ? null : d.getTime(); };
  const roleColor = (role) => { const r = role.toLowerCase(); if (r.includes('pressor') && !r.includes('ino')) return 'var(--accent)'; if (r.includes('ino') || r.includes('chrono')) return 'var(--new)'; if (r.includes('dilator')) return 'var(--accent-2)'; return 'var(--fg-3)'; };
  const roleTag = (role) => `<span class="r-role" style="--c:${roleColor(role)}">${esc(role)}</span>`;
  const lowerFirst = (s) => (!s ? s : (s.length > 1 && /\p{Lu}/u.test(s[1]) ? s : s[0].toLowerCase() + s.slice(1)));
  const loading = (what) => `<p class="r-muted">${bundleFailed ? 'The reference file did not load. Check the connection and reload.' : 'Loading ' + esc(what) + '…'}</p>`;
  function notReady(host) { host.innerHTML = `<p class="r-muted">This tool is still loading. Reload the page if it does not appear.</p>`; }
  /** Re-render once the bundle arrives (tools that need reference.json). */
  function whenBundle(update) { if (!bundle) loadBundle().then(() => update()); }
  // Context handed to tools that live in other files (the echo tools).
  function ctxFor(id) { return { R, F, I, esc, view, eyebrow, numIn, seg, switchRow, radioRow, pills, resultCard, caution, footnote, ghostLink, takeList, factTable, refTable, sourceLine, weightField, checkRow, bundle: () => bundle, loadBundle, toolId: id }; }

  // ---------- quick reference card ----------
  function mountQuickref(host, id) {
    const st = { weight: '', done: {} };
    const update = view(host, () => {
      const ref = quickref(id);
      if (!ref) return loading('the reference');
      const tint = ref.emergency ? 'var(--accent)' : `var(--t-${ref.topic || 'general'}-fg)`;
      const w = R.num(st.weight);
      const steps = ref.emergency ? ref.sections.map((s, i) => s.kind === 'steps' ? i : -1).filter((i) => i >= 0) : [];
      const total = steps.reduce((t, i) => t + (ref.sections[i].items || []).length, 0);
      const doneN = Object.values(st.done).reduce((t, s) => t + s.size, 0);
      let h = `<div class="r-stack">`;
      h += `<header class="r-qhead"><div class="r-eyes">${ref.emergency ? eyebrow('Emergency checklist', 'var(--accent)') : ''}${eyebrow([ref.society, ref.year].filter(Boolean).join(' · '), ref.emergency ? null : tint)}</div><p class="r-lede">${esc(ref.summary)}</p></header>`;
      if (ref.weightDoses && ref.weightDoses.length) {
        h += `<section class="r-card" style="border-color:color-mix(in srgb, ${tint} 40%, var(--line))">${eyebrow('Doses for this patient', tint)}${weightField('qr-weight', st.weight, 'Enter the weight: the doses below are per kilogram until you do.')}<div class="r-doses">`;
        for (const d of ref.weightDoses) {
          let text;
          if (w === null) text = R.fmt(d.perKg) + (d.perKgHigh ? '–' + R.fmt(d.perKgHigh) : '') + ' ' + d.unit + '/kg';
          else if (d.aboveKg && w > d.aboveKg && d.aboveText) text = d.aboveText;
          else text = R.peds.doseText(d.perKg, d.perKgHigh ?? null, d.unit, w, null, d.max ?? null).text;
          let vials = '';
          if (w !== null && d.vialSize) { let mg = d.perKg * w; if (d.max) mg = Math.min(mg, d.max); vials = Math.ceil(mg / d.vialSize) + ' × ' + (d.vialName || 'vial'); }
          h += `<div class="dr"><div class="dl"><span>${esc(d.label)}</span>${d.note ? `<small>${esc(d.note)}</small>` : ''}</div><div class="dv"><span class="${w === null ? 'muted' : ''}">${esc(text)}</span>${vials ? `<small style="color:${tint}">${esc(vials)}</small>` : ''}</div></div>`;
        }
        h += `</div></section>`;
      }
      if (total > 0) h += `<section class="r-card" style="border-color:color-mix(in srgb, ${tint} 40%, var(--line))">${progress(doneN, total, tint, 'Emergency Checklist', 'done', 'resetAll')}</section>`;
      ref.sections.forEach((s, i) => {
        const isCheck = steps.includes(i), done = st.done[i] || new Set();
        h += `<section class="r-sec">`;
        if (s.heading) h += `<div class="r-sechead"><h3>${esc(R.titleCase(s.heading))}</h3>${isCheck ? `<span class="${done.size === (s.items || []).length ? 'ok' : ''}">${done.size}/${(s.items || []).length}</span>` : ''}</div>`;
        if (s.kind === 'text') h += `<p class="r-text">${esc(s.text || '')}</p>`;
        else if (s.kind === 'list') h += takeList(s.items || []);
        else if (s.kind === 'steps') {
          if (isCheck) h += `<div class="r-card flush r-checks" style="border-color:color-mix(in srgb, ${tint} 30%, var(--line))">${(s.items || []).map((t, j) => checkRow('step', i + ':' + j, j + 1, t, done.has(j), tint)).join('')}</div>`;
          else h += `<ol class="r-steps" style="--tint:${tint}">${(s.items || []).map((t) => `<li>${esc(t)}</li>`).join('')}</ol>`;
        } else if (s.kind === 'facts') h += factTable(s.rows || []);
        else if (s.kind === 'table') h += refTable(s.columns || [], s.rows || []);
        if (s.note) h += `<p class="r-note">${esc(s.note)}</p>`;
        h += `</section>`;
      });
      h += `<footer class="r-footer">${eyebrow('Source')}<p class="r-cite">${esc(ref.source.citation || ref.source.title)}</p><div class="r-btns">${ref.source.url ? ghostLink(ref.source.url, I.ext, 'Open the source document', true) : ''}<button type="button" class="r-ghost" data-a="cite">${I.copy}Copy citation</button></div>${footnote('Condensed by Periop Signal' + (ref.reviewed ? ', reviewed ' + monthYear(ref.reviewed) : '') + '. A quick reference, not the guideline: confirm against the source document and your own judgement before acting on it.')}</footer>`;
      return h + `</div>`;
    }, {
      weight(el) { st.weight = el.value; },
      step(el) { const [i, j] = el.dataset.k.split(':').map(Number); const s = st.done[i] || (st.done[i] = new Set()); if (s.has(j)) s.delete(j); else s.add(j); },
      resetAll() { st.done = {}; },
      cite() { const ref = quickref(id); if (ref) F.copyText(ref.source.citation || ref.source.title, 'Citation copied'); return false; },
    });
    whenBundle(update);
  }

  // ---------- score calculators ----------
  function mountScore(host, id) {
    const def = R.score(id);
    const sel = { on: new Set(), choices: {} };
    view(host, () => {
      const score = R.scoreTotal(def, sel), band = R.scoreBand(def, score), max = R.scoreMax(def);
      const tone = band ? TONE[band.tone] : 'var(--fg-3)';
      const empty = !sel.on.size && !Object.keys(sel.choices).length;
      let h = `<div class="r-stack">`;
      h += resultCard(tone, `<div class="r-rowtop">${eyebrow(def.name)}${empty ? '' : `<button type="button" class="r-link" data-a="reset">${I.reset} Reset</button>`}</div>
        <div class="r-big"><span class="n">${score}</span><span class="of">of ${max}</span><button type="button" class="r-ghost sm" data-a="copy">${I.copy}Copy</button></div>
        ${band ? `<div class="r-band"><span class="dot" style="background:${tone}"></span><strong>${esc(band.label)}</strong></div><p class="r-detail">${esc(band.detail)}</p>` : ''}
        <p class="r-small">${esc(def.readout)}</p>`);
      h += `<section class="r-card flush">${def.items.map((it) => scoreItem(it, sel)).join('')}</section>`;
      h += `<section class="r-sec">${eyebrow('Interpretation')}<div class="r-card flush">${def.bands.map((b) => {
        const on = score >= b.lo && score <= b.hi;
        return `<div class="r-bandrow${on ? ' on' : ''}"><span class="dot" style="background:${TONE[b.tone]}"></span><span class="bt"><span>${esc(b.label)}</span><small>${esc(b.detail)}</small></span>${on ? `<span class="here">${I.chevL}</span>` : ''}</div>`;
      }).join('')}</div></section>`;
      if (def.notes.length) h += `<section class="r-sec">${eyebrow('Notes')}${takeList(def.notes)}</section>`;
      h += `<footer class="r-footer">${eyebrow('Sources')}${sourceLine(def.source)}${def.rateSource ? sourceLine(def.rateSource) : ''}${footnote('A calculator, not a consultation: the score informs, your assessment decides.')}</footer>`;
      return h + `</div>`;
    }, {
      tog(el) { const k = el.dataset.k; if (sel.on.has(k)) sel.on.delete(k); else sel.on.add(k); },
      opt(el) { sel.choices[el.dataset.k] = el.dataset.v; },
      reset() { sel.on.clear(); sel.choices = {}; },
      copy() {
        const score = R.scoreTotal(def, sel), band = R.scoreBand(def, score);
        let s = `${def.name}: ${score}/${R.scoreMax(def)}` + (band ? ` — ${band.label}; ${band.detail}` : '');
        const yes = def.items.map((it) => it.kind === 'toggle' ? (sel.on.has(it.id) ? it.label : null) : `${it.label}: ${sel.choices[it.id] || it.options[0].label}`).filter(Boolean);
        if (yes.length) s += '\n' + yes.join('; ');
        F.copyText(s + '\n(' + (def.source.citation || def.source.title) + ')', 'Score copied');
        return false;
      },
    });
  }
  function scoreItem(it, sel) {
    if (it.kind === 'toggle') return switchRow('tog', sel.on.has(it.id), it.label, it.detail, { k: it.id, points: it.points !== 1 ? it.points : 0 });
    const chosen = sel.choices[it.id] ?? it.options[0].label;
    return `<div class="r-choice"><p class="cl">${esc(it.label)}${it.detail ? `<small>${esc(it.detail)}</small>` : ''}</p>${it.options.map((o) => radioRow('opt', it.id, o.label, chosen === o.label, o.label, o.points === 0 ? '0' : '+' + o.points)).join('')}</div>`;
  }

  // ---------- PONV ----------
  function mountPONV(host) {
    const def = R.score('apfel');
    const sel = { on: new Set(), choices: {} }, chosen = new Set();
    const update = view(host, () => {
      const data = bundle && bundle.ponv;
      const factors = R.scoreTotal(def, sel), band = R.scoreBand(def, factors);
      const toneC = band ? TONE[band.tone] : 'var(--fg-3)';
      let h = `<div class="r-stack">`;
      h += `<section class="r-sec"><div class="r-sechead"><h3>Risk Factors (Apfel)</h3>${sel.on.size || chosen.size ? `<button type="button" class="r-link" data-a="reset">${I.reset} Reset</button>` : ''}</div><div class="r-card flush">${def.items.map((it) => scoreItem(it, sel)).join('')}</div></section>`;
      if (!data) return h + loading('the agents') + `</div>`;
      const target = R.ponv.target(factors, data.counts), classes = R.ponv.classes(chosen, data.agents), need = target ? target.agents : 2;
      const wanted = target ? (target.agentsHigh && target.agentsHigh > target.agents ? `${target.agents}–${target.agentsHigh}` : String(target.agents)) : '2';
      h += resultCard(toneC, `<div class="r-big"><span class="n">${factors}</span><span class="of">${factors === 1 ? 'risk factor' : 'risk factors'}${band ? `<strong style="color:${toneC}">${esc(band.label)}</strong>` : ''}</span></div>
        <p class="r-headline">${I.pills.replace('<svg', `<svg style="color:${toneC}"`)}Give ${wanted} antiemetics from different classes</p>
        ${target ? `<p class="r-detail">${esc(target.text)} (Fifth consensus).</p>` : ''}
        ${progress(Math.min(classes.length, need), need, toneC, 'Classes Chosen', 'chosen', 'clearAgents')}
        ${factors >= 3 ? `<div class="r-sub"><strong>Reduce the Baseline Risk</strong><div class="r-chips">${data.riskReduction.map((r) => `<span>${esc(r)}</span>`).join('')}</div></div>` : ''}`);
      const agents = data.agents.filter((a) => a.prophylaxis !== false);
      h += `<section class="r-sec"><div class="r-sechead"><h3>Antiemetic Agents</h3></div><p class="r-small">Tick what you give; two agents of one class count once.</p><div class="r-card flush">${agents.map((a) => {
        const on = chosen.has(a.id);
        const same = on ? data.agents.filter((x) => x.id !== a.id && chosen.has(x.id) && x.class === a.class).map((x) => x.name) : [];
        return `<button type="button" class="r-agent" role="checkbox" aria-checked="${on}" data-a="agent" data-k="${esc(a.id)}"><span class="box" aria-hidden="true">${on ? I.check : ''}</span><span class="at"><span class="an">${esc(a.name)} ${roleTag(a.class)}${a.longActing ? '<span class="r-tag">Long-acting</span>' : ''}</span><span class="ad">${esc(a.dose + (a.timing ? ' · ' + lowerFirst(a.timing) : ''))}</span>${same.length ? `<span class="aw">Same class as ${esc(same.join(', '))}: counts once</span>` : ''}</span></button>`;
      }).join('')}</div></section>`;
      const given = R.ponv.classes(chosen, data.agents), options = R.ponv.rescueOptions(chosen, data.agents), longActing = R.ponv.longActingGiven(chosen, data.agents);
      h += `<section class="r-sec"><div class="r-sechead"><h3>PONV Rescue</h3></div><div class="r-card">`;
      if (given.length) h += `<p class="r-flag">${I.x}<span>Not again within 6 h: ${esc(given.join(', '))}</span></p>`;
      if (longActing.length) h += `<p class="r-flag">${I.x}<span>Do not redose ${esc(longActing.map((a) => a.name).join(' or '))} in recovery.</span></p>`;
      h += `<p class="r-small strong">${given.length ? 'From a class not yet given' : 'Rescue options (tick the prophylaxis above to narrow them to classes not yet given)'}</p>`;
      h += `<div class="r-list">${options.map((a) => `<div class="li"><span class="lt"><strong>${esc(a.name)}</strong>${roleTag(a.class)}</span><span class="lv">${esc(a.rescueDose || a.dose)}</span></div>`).join('')}</div>`;
      if (!options.length) h += `<p class="r-detail">Every rescue class has been used: after 6 hours a second 5-HT₃ antagonist or butyrophenone dose may be considered.</p>`;
      h += `<ul class="r-bullets">${data.rescueRules.map((r) => `<li>${esc(r)}</li>`).join('')}</ul></div></section>`;
      h += `<footer class="r-footer"><div class="r-btns">${ghostLink('#card-ponv-consensus', I.table, 'Full card, with children')}${data.sourceURL ? ghostLink(data.sourceURL, I.doc, 'Guideline', true) : ''}</div>${footnote(def.readout)}${data.source ? footnote(data.source) : ''}</footer>`;
      return h + `</div>`;
    }, {
      tog(el) { const k = el.dataset.k; if (sel.on.has(k)) sel.on.delete(k); else sel.on.add(k); },
      agent(el) { const k = el.dataset.k; if (chosen.has(k)) chosen.delete(k); else chosen.add(k); },
      clearAgents() { chosen.clear(); },
      reset() { sel.on.clear(); chosen.clear(); },
    });
    whenBundle(update);
  }

  // ---------- pediatric doses ----------
  function mountPeds(host) {
    const st = { weight: '', years: 0, months: 0, tab: 0, hs: '', hm: '', open: null };
    const update = view(host, () => {
      const peds = bundle && bundle.peds;
      const w = R.num(st.weight), est = R.peds.estimatedWeight(st.years, st.months), ageMonths = st.years * 12 + st.months;
      let h = `<div class="r-stack"><section class="r-card">`;
      h += weightField('peds-weight', st.weight, est === null ? 'Enter the weight: doses, tube and mask sizes and fluids fill in as you type.' : 'Enter the weight, or use the estimate for this age below.');
      h += `<div class="r-age"><span>Age</span><select id="peds-years" data-a="years" aria-label="Years">${Array.from({ length: 18 }, (_, y) => `<option value="${y}"${y === st.years ? ' selected' : ''}>${y} y</option>`).join('')}</select><select id="peds-months" data-a="months" aria-label="Months">${Array.from({ length: 12 }, (_, m) => `<option value="${m}"${m === st.months ? ' selected' : ''}>${m} mo</option>`).join('')}</select></div>`;
      if (w === null && est !== null) h += `<button type="button" class="r-link accent" data-a="useEst">Use the APLS estimate for this age: ${R.fmt(est)} kg</button>`;
      h += `</section>${seg('tab', [[0, 'Drugs'], [1, 'Airway'], [2, 'Fluids & Blood']], st.tab, 'Section')}`;
      if (!peds) return h + loading('the dosing table') + `</div>`;
      if (st.tab === 0) {
        const groups = [];
        for (const d of peds.drugs) { let g = groups.find((x) => x.group === d.group); if (!g) groups.push(g = { group: d.group, drugs: [] }); g.drugs.push(d); }
        for (const g of groups) {
          h += `<section class="r-sec">${eyebrow(g.group)}<div class="r-card flush">`;
          for (const d of g.drugs) {
            const perKg = R.fmt(d.low) + (d.high ? '–' + R.fmt(d.high) : '') + ' ' + d.unit + '/kg';
            const c = w === null ? null : R.peds.doseText(d.low, d.high ?? null, d.unit, w, d.min ?? null, d.max ?? null);
            const open = st.open === d.id;
            h += `<button type="button" class="r-drug" data-a="open" data-k="${esc(d.id)}" aria-expanded="${open}"><span class="dt"><strong>${esc(d.name)}</strong><small>${esc(d.use)} · ${esc(d.route)}</small></span><span class="dv">${c ? `<span class="mono">${esc(c.text)}</span>` : '<span class="need">Needs weight</span>'}<small>${c && c.capped ? '<em>limit</em> ' : ''}${esc(perKg)}</small></span>`;
            if (open) {
              const lim = [d.min ? 'minimum ' + R.fmt(d.min) + ' ' + d.unit : null, d.max ? 'maximum ' + R.fmt(d.max) + ' ' + d.unit : null].filter(Boolean).join(' · ');
              h += `<span class="dx">${lim ? `<span>${esc(lim[0].toUpperCase() + lim.slice(1))}</span>` : ''}${d.conc ? `<span>${esc(d.conc)}</span>` : ''}${d.note ? `<span>${esc(d.note)}</span>` : ''}${d.source ? `<small>${esc(d.source)}</small>` : ''}</span>`;
            }
            h += `</button>`;
          }
          h += `</div></section>`;
        }
      } else if (st.tab === 1) {
        const sizes = R.peds.ettSizes(st.years, st.months), unc = parseFloat(sizes.uncuffed.split('–')[0]);
        const nasal = R.peds.ettDepthNasal(st.years, st.months);
        h += `<section class="r-sec">${eyebrow(ageMonths < 1 ? 'Set the age for tube sizes' : `For ${st.years} y ${st.months} mo`)}${factTable([
          ['ETT uncuffed', sizes.uncuffed + ' mm ID'], ['ETT cuffed', sizes.cuffed + ' mm ID'],
          ['Depth, oral', R.peds.ettDepthOral(st.years, st.months, isNaN(unc) ? null : unc) + ' cm at the lip'],
          ['Depth, nasal', nasal + (nasal === '—' ? '' : ' cm at the naris')],
          ['Laryngeal mask', w === null ? '— (needs weight)' : 'Size ' + R.peds.lmaSize(w)]])}
          ${footnote('Uncuffed: age/4 + 4 (Cole); cuffed: age/4 + 3.5 (Khine), from 2 years; fixed sizes below that. Oral depth: age/2 + 12 cm from 2 years, 3 × tube ID before; nasal: age/2 + 15 cm. Laryngeal mask sizes follow the manufacturers’ weight bands. Have the half-size above and below ready; confirm with a leak test and the chest radiograph when indicated.')}</section>`;
      } else {
        const ebv = w === null ? null : R.peds.bloodVolume(w, ageMonths, peds.bloodVolume);
        const hs = R.num(st.hs), hm = R.num(st.hm);
        let mabl = null;
        if (ebv && hs && hm) { const lo = R.peds.mabl(ebv.low, hs, hm), hi = R.peds.mabl(ebv.high, hs, hm); if (lo !== null && hi !== null) mabl = [lo, hi]; }
        h += `<section class="r-sec">${factTable([
          ['Maintenance', w === null ? '—' : R.fmt(R.peds.maintenance(w)) + ' mL/h (4-2-1)'],
          ['Blood volume', ebv ? `${R.range(ebv.low, ebv.high)} mL · ${ebv.row.group}, ${R.range(ebv.row.mlPerKgLow, ebv.row.mlPerKgHigh)} mL/kg` : '—'],
          ['Allowable loss', mabl ? R.range(mabl[0], mabl[1]) + ' mL' : '— (enter hematocrits)']])}
          <div class="r-pair"><label class="r-field" for="peds-hs"><span>Starting Hct %</span>${numIn('peds-hs', st.hs, 'hs', { label: 'Starting hematocrit percent', wide: true })}</label><label class="r-field" for="peds-hm"><span>Lowest acceptable Hct %</span>${numIn('peds-hm', st.hm, 'hm', { label: 'Lowest acceptable hematocrit percent', wide: true })}</label></div>
          ${footnote('Maintenance by Holliday–Segar (4 mL/kg/h for the first 10 kg, 2 for the next 10, 1 beyond). Blood volume uses the age band in the table. Allowable blood loss = EBV × (Hct₀ − Hct_min) ÷ Hct₀; a guide for planning, not a transfusion trigger.')}
          ${eyebrow('Blood volume by age')}${factTable(peds.bloodVolume.map((r) => [r.group, R.range(r.mlPerKgLow, r.mlPerKgHigh) + ' mL/kg']))}</section>`;
      }
      h += `<button type="button" class="r-quiet" data-a="toLocal"><span class="qi">${I.syringe}</span><span class="qt"><small>Local anesthetic</small><span>Maximum doses for a child of this weight, single agent or mixture</span></span>${I.chevR}</button>`;
      h += `<footer class="r-footer">${peds.note ? `<p class="r-detail">${esc(peds.note)}</p>` : ''}${footnote('Doses are starting points from the sources shown on each line' + (peds.reviewed ? ', reviewed ' + monthYear(peds.reviewed) : '') + '. Check the concentration in your hand and your institution’s references before giving a drug.')}</footer>`;
      return h + `</div>`;
    }, {
      weight(el) { st.weight = el.value; },
      years(el) { st.years = Number(el.value) || 0; },
      months(el) { st.months = Number(el.value) || 0; },
      useEst() { const e = R.peds.estimatedWeight(st.years, st.months); if (e !== null) st.weight = R.fmt(e); },
      tab(el) { st.tab = Number(el.dataset.v); },
      open(el) { st.open = st.open === el.dataset.k ? null : el.dataset.k; },
      hs(el) { st.hs = el.value; },
      hm(el) { st.hm = el.value; },
      toLocal() { handoff = { weightKg: R.num(st.weight), ageYears: st.years }; go('tool-local'); return false; },
    });
    whenBundle(update);
  }
  /** Weight and age passed once from the pediatric calculator to the local anesthetic one (memory only). */
  let handoff = null;

  // ---------- local anesthetic doses ----------
  function mountLocal(host) {
    const passed = handoff; handoff = null;
    const st = { weight: '', pediatric: false, years: 8, epi: false, entries: [], seq: 0 };
    if (passed && passed.weightKg) { st.weight = R.fmt(passed.weightKg); st.pediatric = true; if (passed.ageYears !== null && passed.ageYears !== undefined) st.years = passed.ageYears; }
    const agents = () => (bundle && bundle.peds && bundle.peds.localAnesthetics) || [];
    const add = (a) => st.entries.push({ id: 'e' + (++st.seq), agentID: a.id, percent: a.concentrations[0] || 0.5, mLText: '' });
    const evaluate = () => R.la.evaluate(st.entries.map((e) => ({ id: e.id, agentID: e.agentID, percent: e.percent, mL: R.num(e.mLText) || 0 })), agents(), R.num(st.weight) || 0, st.pediatric, st.epi, st.pediatric ? st.years : null);
    const status = (r, w) => {
      if (w === null) return 'Enter the weight';
      const dosed = r.agents.filter((a) => a.mg > 0);
      if (!dosed.length) return 'Type the volumes';
      if (dosed.length === 1 && dosed[0].maxMg !== null) return r.combined > 1 ? `Above the maximum of ${R.fmt(dosed[0].maxMg)} mg` : `Under the maximum of ${R.fmt(dosed[0].maxMg)} mg (${r.percentUsed}%)`;
      return r.combined > 1 ? `Above the combined maximum (${r.percentUsed}%)` : `Under the combined maximum (${r.percentUsed}% used)`;
    };
    const basis = (a) => {
      if (st.pediatric) {
        let s = R.fmt(a.maxMgPerKg) + ' mg/kg single injection';
        const cap = a.pedsMaxMg ?? a.adultPlainMaxMg; if (cap) s += ', at most ' + R.fmt(cap) + ' mg';
        if (a.pedsMinYears) s += '; labeled from ' + a.pedsMinYears + ' years';
        return s;
      }
      const perKg = st.epi ? (a.adultEpiMgPerKg ?? a.adultPlainMgPerKg) : a.adultPlainMgPerKg;
      const cap = st.epi ? (a.adultEpiMaxMg ?? a.adultPlainMaxMg) : a.adultPlainMaxMg;
      const parts = []; if (perKg) parts.push(R.fmt(perKg) + ' mg/kg'); if (cap) parts.push('at most ' + R.fmt(cap) + ' mg');
      let s = parts.length ? parts.join(', ') : 'no adult maximum on file';
      if (st.epi && !a.adultEpiMaxMg && !a.adultEpiMgPerKg) s += ' (epinephrine does not change it)';
      if (a.per24hMaxMg) s += '; ' + R.fmt(a.per24hMaxMg) + ' mg in 24 h';
      return s;
    };
    const update = view(host, () => {
      const list = agents();
      if (!list.length) return `<div class="r-stack">${loading('the agents')}</div>`;
      if (!st.entries.length) add(list[0]);
      const w = R.num(st.weight), r = evaluate();
      const over = r.combined > 1, tone = w === null ? 'var(--fg-3)' : (over ? 'var(--accent)' : 'var(--new)');
      const totalMg = r.agents.reduce((t, a) => t + a.mg, 0);
      let h = `<div class="r-stack"><section class="r-card">`;
      h += weightField('la-weight', st.weight, 'Enter the weight: the maximum for each agent, and whether the total is under it, depend on it.');
      h += `<div class="r-inline"><span class="lab">Patient</span>${seg('ped', [['0', 'Adult'], ['1', 'Child']], st.pediatric ? '1' : '0', 'Patient')}${st.pediatric ? `<select id="la-years" data-a="years" aria-label="Age in years">${Array.from({ length: 18 }, (_, y) => `<option value="${y}"${y === st.years ? ' selected' : ''}>${y} y</option>`).join('')}</select>` : ''}</div>`;
      h += switchRow('epi', st.epi, 'With epinephrine', 'Raises the label maximum for lidocaine, bupivacaine, mepivacaine and chloroprocaine; not for Exparel.');
      h += `</section><section class="r-sec"><div class="r-sechead">${eyebrow('Doses')}<select id="la-add" class="r-addsel" data-a="add" aria-label="Add an agent"><option value="" selected>+ Add agent</option>${list.map((a) => `<option value="${esc(a.id)}">${esc(a.name)}</option>`).join('')}</select></div>`;
      h += `<div class="r-card flush r-latable" style="border-color:${w === null ? 'var(--line)' : `color-mix(in srgb, ${tone} 60%, var(--line))`}"><div class="lh"><span>Agent</span><span>Conc</span><span class="rt">mL</span><span class="rt">mg</span><span></span></div>`;
      for (const e of st.entries) {
        const a = list.find((x) => x.id === e.agentID), res = r.agents.find((x) => x.id === e.id);
        const overRow = res && res.fraction > 1;
        h += `<div class="lr"><select id="la-agent-${e.id}" data-a="agentSel" data-k="${e.id}" aria-label="Agent">${list.map((x) => `<option value="${esc(x.id)}"${x.id === e.agentID ? ' selected' : ''}>${esc(x.name)}</option>`).join('')}</select>
          <select id="la-conc-${e.id}" data-a="conc" data-k="${e.id}" aria-label="Concentration">${(a ? a.concentrations : []).map((c) => `<option value="${c}"${c === e.percent ? ' selected' : ''}>${R.fmt(c)}%</option>`).join('')}</select>
          ${numIn('la-ml-' + e.id, e.mLText, 'ml', { k: e.id, ph: '0', label: 'Volume in mL' })}
          <span class="mg${overRow ? ' over' : ''}">${res ? R.fmt(res.mg) : '0'}</span>
          ${st.entries.length > 1 ? `<button type="button" class="rm" data-a="remove" data-k="${e.id}" aria-label="Remove">${I.x}</button>` : '<span></span>'}
          ${res && w !== null ? `<small class="ld${overRow ? ' over' : ''}">${esc(rowDetail(res))}</small>` : ''}</div>`;
      }
      h += `<div class="lt" style="background:${w === null ? 'transparent' : `color-mix(in srgb, ${tone} 10%, transparent)`}"><span class="tl"><strong>Total</strong><small style="color:${tone}">${esc(status(r, w))}</small></span><span class="tv" style="color:${tone}">${w === null ? '—' : R.fmt(totalMg) + ' mg'}</span></div></div>`;
      h += `<div class="r-legend"><p>Green: under the maximum for this weight. Red: above it. With more than one agent, each counts as a fraction of its own maximum and the fractions add up.</p><button type="button" class="r-ghost sm" data-a="copy"${w === null ? ' disabled' : ''}>${I.copy}Copy</button></div></section>`;
      if (r.warnings.length) h += `<section class="r-warnbox">${r.warnings.map((x) => caution(x)).join('')}</section>`;
      h += `<section class="r-sec">${eyebrow(w === null ? 'Maximum doses' : 'Maximum doses at ' + st.weight + ' kg')}<div class="r-card flush">${list.map((a) => {
        const m = w === null ? null : R.la.maxMg(a, w, st.pediatric, st.epi, st.pediatric ? st.years : null);
        return `<div class="r-max"><div class="mt"><strong>${esc(a.name)}</strong><span class="${m === null ? 'muted' : ''}">${m === null ? '—' : R.fmt(m) + ' mg'}</span></div><small>${esc(basis(a))}</small>${m !== null && a.concentrations.length ? `<small class="mv">${esc(a.concentrations.map((c) => R.fmt(m / (c * 10)) + ' mL of ' + R.fmt(c) + '%').join(' · '))}</small>` : ''}${a.note ? `<small>${esc(a.note)}</small>` : ''}</div>`;
      }).join('')}</div></section>`;
      const sources = Array.from(new Set(list.map((a) => a.source).filter(Boolean))).sort();
      h += `<footer class="r-footer">${footnote('Adult maxima are the FDA labels’ figures (with a conventional per-kilogram ceiling where the label gives only milligrams); pediatric per-kilogram maxima follow the ASRA/ESRA 2018 recommendations. The additive rule for mixtures (each agent as a fraction of its own maximum, summed) is the convention described in ASRA’s 2026 Pro-Con on mixing local anesthetics; no label or guideline codifies it. Label maxima are conservative conventions, not pharmacological thresholds: site, vascularity, age, hepatic and cardiac function change the risk. Exparel’s rules come from its label. The LAST checklist is in the Emergency folder.')}${sources.map((s) => footnote(s)).join('')}</footer>`;
      return h + `</div>`;
      function rowDetail(res) {
        if (res.maxMg === null) return st.pediatric && res.agent.pedsMinYears ? `Not labeled under ${res.agent.pedsMinYears} years` : 'No maximum on file for this patient';
        let s = `Max ${R.fmt(res.maxMg)} mg = ${R.fmt(res.maxMg / (res.percent * 10))} mL of ${R.fmt(res.percent)}% alone`;
        if (res.mg > 0 && res.remainingML !== null) s += ' · ' + (res.remainingML < 0.05 ? 'nothing' : R.fmt(res.remainingML) + ' mL') + ' more fits in this mix';
        return s;
      }
    }, {
      weight(el) { st.weight = el.value; },
      ped(el) { st.pediatric = el.dataset.v === '1'; },
      years(el) { st.years = Number(el.value) || 0; },
      epi() { st.epi = !st.epi; },
      add(el) { const a = agents().find((x) => x.id === el.value); if (a) add(a); el.value = ''; },
      agentSel(el) { const e = st.entries.find((x) => x.id === el.dataset.k), a = agents().find((x) => x.id === el.value); if (e && a) { e.agentID = a.id; e.percent = a.concentrations[0] || 0.5; } },
      conc(el) { const e = st.entries.find((x) => x.id === el.dataset.k); if (e) e.percent = parseFloat(el.value); },
      ml(el) { const e = st.entries.find((x) => x.id === el.dataset.k); if (e) e.mLText = el.value; },
      remove(el) { st.entries = st.entries.filter((x) => x.id !== el.dataset.k); },
      copy() {
        const r = evaluate(), w = R.num(st.weight); if (w === null) return false;
        let s = `Local anesthetic for ${st.weight} kg ${st.pediatric ? 'child' : 'adult'}${st.epi ? ' with epinephrine' : ''}: ${status(r, w)}.`;
        for (const a of r.agents) if (a.mL > 0) s += `\n• ${a.agent.name} ${R.fmt(a.percent)}% × ${R.fmt(a.mL)} mL = ${R.fmt(a.mg)} mg` + (a.maxMg !== null ? ` (max ${R.fmt(a.maxMg)} mg)` : '');
        for (const x of r.warnings) s += '\n! ' + x;
        F.copyText(s, 'Doses copied');
        return false;
      },
    });
    whenBundle(update);
  }

  // ---------- medications & hematology ----------
  function mountInfusions(host) {
    const st = { weight: '', tab: null, open: null, q: '' };
    const update = view(host, () => {
      const groups = (bundle && bundle.infusions && bundle.infusions.groups) || [];
      const w = R.num(st.weight);
      let h = `<div class="r-stack tight">${compactWeight('inf-weight', st.weight)}<label class="r-find" for="inf-q">${I.search}<input id="inf-q" data-a="q" type="search" autocomplete="off" placeholder="Find a drug" value="${esc(st.q)}" aria-label="Find a drug"></label>`;
      if (!groups.length) return h + loading('the table') + `</div>`;
      const tabs = []; for (const g of groups) { const t = g.tab || g.name; if (!tabs.includes(t)) tabs.push(t); }
      const cur = tabs.includes(st.tab) ? st.tab : tabs[0];
      const q = st.q.trim().toLowerCase();
      const row = (d) => {
        const lines = R.infusionLines(d, w), parts = R.nameParts(d.name), open = st.open === d.id;
        let r = `<button type="button" class="r-inf" data-a="open" data-k="${esc(d.id)}" aria-expanded="${open}"><span class="it"><span class="nm">${esc(parts.main)}${d.offLabel ? '<sup title="Off-label">†</sup>' : ''}</span>${parts.alias ? `<small>${esc(parts.alias)}</small>` : ''}</span><span class="iv"><span class="mono">${esc(d.display || lines.dose)}</span>${lines.equivalent ? `<small>${esc(lines.equivalent)}</small>` : ''}</span>`;
        if (d.threshold) r += `<span class="thr">${I.drop}<span>${esc(d.threshold)}</span></span>`;
        if (open) {
          const det = (l, t) => `<span class="dd"><span>${esc(l)}</span><span>${esc(t)}</span></span>`;
          r += `<span class="ix">${det('Use', d.use + (d.role ? ' · ' + d.role : ''))}${d.offLabel ? det('Label', 'Off-label use: see the source') : ''}${d.titration ? det('Titration', d.titration) : ''}${d.range ? det('Range', d.range) : ''}${d.max ? det('Maximum', d.max) : ''}${d.bolus ? det('Bolus', d.bolus) : ''}${d.preparation ? det('Preparation', d.preparation) : ''}${d.caution ? det('Caution', d.caution) : ''}${d.source ? `<small>${esc(d.source)}</small>` : ''}</span>`;
        }
        return r + `</button>`;
      };
      const section = (g, title) => `<section class="r-sec">${title ? eyebrow(title) : ''}<div class="r-card flush">${g.drugs.map(row).join('')}</div></section>`;
      if (!q) {
        h += `<div class="r-tabs" role="tablist" aria-label="Sections">${tabs.map((t) => `<button type="button" role="tab" data-a="tab" data-v="${esc(t)}" aria-selected="${t === cur}">${esc(t)}</button>`).join('')}</div>`;
        const tg = groups.filter((g) => (g.tab || g.name) === cur);
        h += tg.map((g) => section(g, tg.length > 1 ? g.name : null)).join('');
      } else {
        const hits = groups.map((g) => ({ name: g.name, tab: g.tab, drugs: g.drugs.filter((d) => (d.name + ' ' + d.use + ' ' + (d.role || '')).toLowerCase().includes(q)) })).filter((g) => g.drugs.length);
        if (!hits.length) h += `<p class="r-muted">No drug matches “${esc(st.q)}”.</p>`;
        else h += hits.map((g) => section(g, [g.tab, g.tab === g.name ? null : g.name].filter(Boolean).join(' · '))).join('');
      }
      const rev = bundle.infusions.reviewed;
      h += `<footer class="r-footer">${footnote('† Off-label use. Starting points from the FDA labels and the cited guidelines' + (rev ? ', reviewed ' + monthYear(rev) : '') + '; norepinephrine, epinephrine and phenylephrine show the usual operating-room start. Titrate to the patient and check your pump’s concentration before programming a rate.')}</footer>`;
      return h + `</div>`;
    }, {
      weight(el) { st.weight = el.value; },
      q(el) { st.q = el.value; },
      tab(el) { st.tab = el.dataset.v; st.open = null; },
      open(el) { st.open = st.open === el.dataset.k ? null : el.dataset.k; },
    });
    whenBundle(update);
  }

  // ---------- blocks on anticoagulants ----------
  function mountNeuraxial(host) {
    const st = { drug: '', tier: null, renal: 0, elderly: false, last: Date.now(), general: false };
    const step = (n, title, inner) => `<section class="r-card"><div class="r-step"><span class="sn">${n}</span><h3>${esc(title)}</h3></div>${inner}</section>`;
    const update = view(host, () => {
      const data = bundle && bundle.neuraxial;
      let h = `<div class="r-stack">`;
      if (!data) return h + step(1, 'Which drug?', loading('the rules')) + `</div>`;
      const all = data.groups.flatMap((g) => g.drugs), drug = all.find((d) => d.id === st.drug) || null;
      const tier = drug ? (drug.tiers.find((t) => t.id === st.tier) || drug.tiers[0]) : null;
      h += step(1, 'Which drug?', `<select id="nx-drug" class="r-bigsel${drug ? '' : ' empty'}" data-a="drug" aria-label="Antithrombotic drug"><option value=""${drug ? '' : ' selected'}>Choose the antithrombotic</option>${data.groups.map((g) => `<optgroup label="${esc(g.name)}">${g.drugs.map((d) => `<option value="${esc(d.id)}"${d.id === st.drug ? ' selected' : ''}>${esc(d.name)}</option>`).join('')}</optgroup>`).join('')}</select>`);
      if (drug) {
        let n = 2;
        if (drug.tiers.length > 1) h += step(n++, 'Which dose?', `<div class="r-radios">${drug.tiers.map((t) => radioRow('tier', 'tier', t.id, tier && tier.id === t.id, t.label)).join('')}</div>`);
        if (tier && tier.renal && tier.renal.length) {
          h += step(n++, 'Kidney function?', `<div class="r-radios">${tier.renal.map((r, i) => radioRow('renal', 'renal', String(i), st.renal === i, r.label, r.hours !== null && r.hours !== undefined ? R.fmtHours(r.hours) : '')).join('')}</div>${tier.renal.some((r) => r.elderlyHours) ? switchRow('elderly', st.elderly, 'Elderly patient') : ''}`);
        }
        h += step(n, 'Last dose was at', `<input class="r-when" id="nx-last" type="datetime-local" data-a="last" value="${toLocalInput(st.last)}" max="${toLocalInput(Date.now() + 3600000)}" aria-label="Time of the last dose">${tier && tier.inrRule ? `<p class="r-small">Warfarin counts in days: the block needs a normal INR on the day, whatever the calendar says.</p>` : ''}`);
        if (tier) {
          const a = R.neuraxialAnswer(tier, st.renal, st.elderly, st.last), now = Date.now();
          const passed = a.earliest !== null && a.earliest <= now;
          const tone = a.avoid ? 'var(--accent)' : (passed ? 'var(--new)' : 'var(--accent-2)');
          let big;
          if (a.avoid) big = `<p class="r-answer" style="color:var(--accent)">Avoid</p>`;
          else if (a.earliest !== null && a.hours > 0) big = `<div class="r-answer-row"><p class="r-answer">${esc(fmtWhen(a.earliest))}</p><span style="color:${tone}">${passed ? 'now' : esc(R.countdown(a.earliest, now))}</span></div>`;
          else if (a.hours === 0) big = `<p class="r-answer" style="color:var(--new)">Now</p>`;
          else big = `<p class="r-answer">No Interval</p>`;
          h += resultCard(tone, `${eyebrow('Earliest neuraxial or deep block', tone)}${big}<p class="r-detail">${esc(a.rule)}</p>${tier.level ? `<p class="r-detail">${esc(tier.level)}</p>` : ''}${tier.renalNote ? `<p class="r-detail">${esc(tier.renalNote)}</p>` : ''}`);
          const rows = [];
          if (tier.catheter) rows.push(['Catheter in place', tier.catheter]);
          rows.push(['Next dose', tier.restartText || (tier.restartHours !== null && tier.restartHours !== undefined ? (tier.restartHours === 0 ? 'No interval after the block or catheter removal' : R.fmtHours(tier.restartHours) + ' after needle placement or catheter removal') : 'Not specified')]);
          if (drug.notes && drug.notes.length) rows.push(['Also', drug.notes.join(' ')]);
          h += factTable(rows);
        }
      }
      h += `<section class="r-sec"><button type="button" class="r-disclose" data-a="general" aria-expanded="${st.general}">${eyebrow('Ground rules that apply to every drug')}<span>${st.general ? '−' : '+'}</span></button>${st.general ? takeList(data.general) : ''}</section>`;
      h += `<footer class="r-footer"><div class="r-btns">${ghostLink('#card-asra-anticoagulation', I.table, 'Full ASRA table')}${data.sourceURL ? ghostLink(data.sourceURL, I.doc, 'Guideline', true) : ''}</div>${footnote('ASRA Pain Medicine, fifth edition (2025)' + (data.reviewed ? '; reviewed ' + monthYear(data.reviewed) : '') + '. The interval is the guideline’s minimum for a patient on this drug alone; combinations, kidney function and age push it out, and a bloody tap or a catheter changes the plan. The guideline and your judgement decide.')}</footer>`;
      return h + `</div>`;
    }, {
      drug(el) { st.drug = el.value; const d = (bundle.neuraxial.groups.flatMap((g) => g.drugs)).find((x) => x.id === el.value); st.tier = d ? d.tiers[0].id : null; st.renal = 0; },
      tier(el) { st.tier = el.dataset.v; st.renal = 0; },
      renal(el) { st.renal = Number(el.dataset.v); },
      elderly() { st.elderly = !st.elderly; },
      last(el) { const t = fromLocalInput(el.value); if (t !== null) st.last = t; },
      general() { st.general = !st.general; },
    });
    whenBundle(update);
    const timer = setInterval(update, 60000);
    return () => clearInterval(timer);
  }

  // ---------- fasting ----------
  function mountFasting(host) {
    const st = { taken: {}, flags: new Set() };
    const update = view(host, () => {
      const e = R.fasting.earliest(st.taken), now = Date.now();
      const ready = e ? e.date <= now : false;
      const tone = st.flags.size ? 'var(--accent)' : (!e ? 'var(--fg-3)' : (ready ? 'var(--new)' : 'var(--accent-2)'));
      let inner = `<div class="r-rowtop">${eyebrow('Earliest elective start', tone)}${Object.keys(st.taken).length || st.flags.size ? `<button type="button" class="r-link" data-a="reset">${I.reset} Reset</button>` : ''}</div>`;
      if (e) {
        inner += `<div class="r-answer-row"><p class="r-answer">${esc(fmtWhen(e.date))}</p><span style="color:${tone}">${ready ? 'now' : esc(R.countdown(e.date, now))}</span></div>`;
        inner += `<p class="r-detail">${e.because.hours === 0 ? 'Gum does not set a time; remove it before any sedative.' : `${esc(R.fmtHours(e.because.hours))} after the ${esc(e.because.label.toLowerCase())} at ${esc(fmtClock(st.taken[e.because.id]))}.`}</p>`;
        if (!ready && e.date - 2 * 3600000 > now) inner += `<p class="r-detail">Clear liquids are fine until ${esc(fmtClock(e.date - 2 * 3600000))}.</p>`;
      } else inner += `<p class="r-answer muted">Enter What Was Taken</p>`;
      if (st.flags.size) inner += `<p class="r-detail" style="color:var(--accent)">The guideline is written for healthy patients: with ${st.flags.size === 1 ? 'this condition' : 'these conditions'} its times do not apply as written. Plan for delayed emptying.</p>`;
      let h = `<div class="r-stack">${resultCard(tone, inner)}`;
      h += `<section class="r-sec">${eyebrow('What was taken, and when')}<div class="r-card flush">${R.fasting.intakes.map((i) => {
        const on = st.taken[i.id] !== undefined;
        return `<div class="r-intake"><button type="button" class="r-intakebtn" role="checkbox" aria-checked="${on}" data-a="take" data-k="${i.id}"><span class="box" aria-hidden="true">${on ? I.check : ''}</span><span class="tt"><span>${esc(i.label)}</span>${i.detail ? `<small>${esc(i.detail)}</small>` : ''}</span><span class="hrs">${i.hours === 0 ? '—' : esc(R.fmtHours(i.hours))}</span></button>${on ? `<input class="r-when" id="fast-${i.id}" type="datetime-local" data-a="time" data-k="${i.id}" value="${toLocalInput(st.taken[i.id])}" max="${toLocalInput(Date.now())}" aria-label="When: ${esc(i.label)}">` : ''}</div>`;
      }).join('')}</div></section>`;
      h += `<section class="r-sec">${eyebrow('Anything that slows emptying?')}<div class="r-pills">${R.fasting.conditions.map((c) => `<button type="button" class="r-pill" data-a="flag" data-v="${esc(c)}" aria-pressed="${st.flags.has(c)}">${esc(c)}</button>`).join('')}</div></section>`;
      h += `<footer class="r-footer"><div class="r-btns">${ghostLink('#card-asa-fasting', I.table, 'Guideline card')}${ghostLink('https://doi.org/10.1097/ALN.0000000000004381', I.doc, 'Guideline', true)}</div>${footnote('ASA practice guidelines for preoperative fasting (2017, updated 2023): minimum times for healthy patients of all ages having elective procedures under general anesthesia, regional anesthesia or procedural sedation; not for labor. Meeting the times does not guarantee an empty stomach. Children’s clear liquids: as close to 2 h before as possible.')}</footer>`;
      return h + `</div>`;
    }, {
      take(el) { const k = el.dataset.k; if (st.taken[k] !== undefined) delete st.taken[k]; else st.taken[k] = Date.now() - 3600000; },
      time(el) { const t = fromLocalInput(el.value); if (t !== null) st.taken[el.dataset.k] = t; },
      flag(el) { const v = el.dataset.v; if (st.flags.has(v)) st.flags.delete(v); else st.flags.add(v); },
      reset() { st.taken = {}; st.flags.clear(); },
    });
    const timer = setInterval(update, 60000);
    return () => clearInterval(timer);
  }

  // ---------- difficult airway ----------
  function mountAirway(host) {
    const fresh = () => ({ suspected: false, ventilation: false, aspiration: false, apnea: false, invasive: false, uncooperative: false, attempts: 0, maskOK: true, cicv: false, done: new Set() });
    let st = fresh();
    const block = (items, key, title, tint, size) => {
      const ids = items.map((_, i) => key + '-' + i), n = ids.filter((x) => st.done.has(x)).length;
      return `<div class="r-block">${progress(n, items.length, tint, title, 'done', 'clr-' + key)}<div class="r-checks">${items.map((t, i) => checkRow('chk', ids[i], i + 1, t, st.done.has(ids[i]), tint)).join('')}</div></div>`;
    };
    const actions = {
      q(el) { const k = el.dataset.k; st[k] = !st[k]; },
      fail() { st.attempts += 1; },
      undo() { st.attempts = Math.max(0, st.attempts - 1); },
      mask() { st.maskOK = !st.maskOK; },
      cicv() { st.cicv = true; },
      chk(el) { const k = el.dataset.k; if (st.done.has(k)) st.done.delete(k); else st.done.add(k); },
      reset() { st = fresh(); },
    };
    for (const key of ['plan', 'room', 'cicv']) actions['clr-' + key] = () => { for (const x of Array.from(st.done)) if (x.startsWith(key + '-')) st.done.delete(x); };
    view(host, () => {
      const predictors = st.ventilation || st.aspiration || st.apnea || st.invasive;
      const plan = !st.suspected ? 'routine' : (predictors && !st.uncooperative ? 'awake' : 'prepared');
      let title, tone, steps;
      if (plan === 'awake') {
        title = 'Awake Intubation'; tone = 'var(--accent)';
        steps = ['Explain the plan and the risks; antisialagogue; topicalize well, sedation light enough to keep breathing and cooperation.',
          'Oxygen throughout: high-flow nasal or a nasal cannula under the mask.',
          'Choose the device you know best (flexible scope, videolaryngoscope, or both); a second skilled clinician present.',
          'Double set-up: surgical or invasive airway ready' + (st.invasive ? '. The invasive route is itself expected to be difficult, so have the surgeon in the room.' : '.'),
          'If the awake attempt fails and the case cannot wait or the patient is unstable: post-induction pathway with the invasive airway prepared.'];
      } else if (plan === 'prepared') {
        title = 'Intubate After Induction, Prepared for Failure'; tone = 'var(--accent-2)';
        steps = [st.uncooperative ? 'Awake technique not feasible: induce with spontaneous ventilation maintained where possible (inhalational in children).' : 'No independent predictor of failed rescue: induction is reasonable with rescue devices open.',
          'Position, preoxygenate, apneic oxygenation; videolaryngoscope, supraglottic airway and flexible scope in the room; bougie and stylet ready.',
          'Time-out: name the primary and backup airway managers; an observer calls time, attempts and saturation.',
          'Plan the wake-up: short-acting drugs or rocuronium with sugammadex drawn up (16 mg/kg for immediate reversal).',
          'Invasive airway kit opened, not just available.'];
      } else {
        title = 'Routine Airway, Cart Available'; tone = 'var(--new)';
        steps = ['Standard equipment in the room; the difficult-airway cart immediately available.',
          'Preoxygenate and keep oxygen flowing; capnography to confirm ventilation.',
          'Reassess if the first laryngoscopy surprises you: the attempt counter below applies to every patient.'];
      }
      const reasons = [st.ventilation && 'difficult ventilation', st.aspiration && 'aspiration risk', st.apnea && 'intolerance of apnea', st.invasive && 'a difficult invasive airway'].filter(Boolean).join(', ');
      const qs = [['suspected', 'Difficult laryngoscopy or intubation suspected?', 'Several features together: mouth opening, upper-lip bite, Mallampati, thyromental distance, neck mobility, history'],
        ['ventilation', 'Difficult mask or supraglottic ventilation?', null], ['aspiration', 'Increased aspiration risk?', null],
        ['apnea', 'Rapid desaturation or intolerance of apnea?', 'Obesity, pregnancy, children, critical illness, low reserve'],
        ['invasive', 'Emergency invasive airway would be difficult?', 'Neck anatomy, prior surgery or radiation, obesity'],
        ['uncooperative', 'Awake technique not feasible?', 'Uncooperative patient, small child']];
      let h = `<div class="r-stack"><section class="r-sec"><div class="r-sechead">${eyebrow('Before you start')}<button type="button" class="r-link" data-a="reset">${I.reset} Reset</button></div><div class="r-card flush">${qs.map(([k, t, d]) => switchRow('q', st[k], t, d, { k })).join('')}</div></section>`;
      h += resultCard(tone, `${eyebrow('The plan', tone)}<p class="r-headline big">${esc(title)}</p>${plan === 'awake' ? `<p class="r-detail">Difficult intubation is suspected together with ${esc(reasons)}.</p>` : ''}${block(steps, 'plan', 'Plan Checklist', tone)}`);
      const at = st.attempts;
      const aTitle = at === 0 ? 'No attempts yet' : (at <= 2 ? `Attempt ${at} failed` : (at === 3 ? 'Three attempts: one more, by the most skilled person present' : 'Stop attempting: rescue, wake, or invasive airway'));
      const aDetail = at === 0 ? 'Count every laryngoscopy, supraglottic placement and mask rescue; the limit is three of any class, plus one by a more skilled clinician (3 + 1).' : (at <= 2 ? 'Call for help now if you have not; the observer tracks time and saturation.' : (at === 3 ? 'Only a clinician with greater skill makes the fourth; otherwise wake the patient or move to rescue.' : 'Further attempts cause injury and swelling. Oxygenate by whatever works; wake the patient if feasible, or proceed to the invasive airway.'));
      h += `<section class="r-sec">${eyebrow('In the room: attempt by attempt')}<div class="r-card"><div class="r-attempts"><span class="at"><strong${at >= 4 ? ' style="color:var(--accent)"' : ''}>${esc(aTitle)}</strong><small>${esc(aDetail)}</small></span><span class="an"${at >= 3 ? ' style="color:var(--accent)"' : ''}>${at}</span></div>
        <div class="r-btns"><button type="button" class="r-cta" data-a="fail">Attempt failed</button><button type="button" class="r-ghost" data-a="undo"${at === 0 ? ' disabled' : ''}>Undo</button></div>
        ${switchRow('mask', st.maskOK, 'Mask or supraglottic ventilation adequate after the last attempt', null, { tint: 'var(--new)' })}
        ${block(['Change something before trying again: position, relaxation, blade or device, a bougie, an adjunct. Not the same move twice.',
          'Combine devices when one struggles: videolaryngoscope with a flexible scope, or intubate through the supraglottic airway.',
          'Provide and test mask ventilation after every attempt; keep oxygen on throughout.',
          'Each attempt, decide: wake the patient and restore breathing, or carry on? Non-invasive next, or invasive?'], 'room', 'Before Every Attempt', 'var(--accent-2)')}
        ${!st.maskOK ? `<button type="button" class="r-cta danger" data-a="cicv">${I.warn} Cannot ventilate: open the emergency pathway</button>` : ''}</div></section>`;
      if (st.cicv) {
        h += `<section class="r-card r-alarm"><p class="r-headline" style="color:var(--accent)">Cannot Intubate, Cannot Ventilate</p>${block([
          'Call for help: a second anesthesiologist, a surgeon, the invasive airway kit opened now; start the clock.',
          'Optimize oxygenation: two-hand mask with an oral and nasal airway, a supraglottic airway (a different size or type), and a final look with the videolaryngoscope only if it does not cost oxygenation.',
          'Functional obstruction (laryngospasm, light anesthesia)? Deepen and relax. Anatomic? Devices.',
          'When non-invasive options have failed or are failing: emergency invasive airway without further delay (surgical cricothyrotomy, or needle cricothyrotomy with a pressure-regulated jet device, or large-bore cannula) by the most experienced person present, with an alternative ready if it fails.',
          'Start ECMO when appropriate and available; rigid bronchoscopy in adults where a team exists.',
          'Afterwards: document the difficulty, tell the patient, registry or letter and alert bracelet.'], 'cicv', 'Emergency Checklist', 'var(--accent)')}</section>`;
      }
      h += `<footer class="r-footer"><div class="r-btns">${ghostLink('#card-asa-difficult-airway', I.table, 'Full algorithm')}${ghostLink('https://doi.org/10.1097/ALN.0000000000004002', I.doc, 'Guideline', true)}</div>${footnote('A guide through the 2022 ASA practice guideline’s decision points, in Periop Signal’s words; the ASA infographics are the algorithm. Children: awake intubation is uncommon, inhalational induction with spontaneous breathing is usual, and the attempt limit is the primary manager’s attempts plus one by the backup.')}</footer>`;
      return h + `</div>`;
    }, actions);
  }

  // ---------- ASE valve severity ----------
  function mountValves(host) {
    const st = { lesion: 'as', texts: {}, signs: new Set() };
    view(host, () => {
      const lesion = R.valveLesions.find((l) => l.id === st.lesion), params = R.valveParams(st.lesion);
      const numbers = {}; for (const [k, v] of Object.entries(st.texts)) { const n = R.num(v); if (n !== null) numbers[k] = n; }
      const input = { numbers, signs: st.signs }, empty = !Object.keys(numbers).length && !st.signs.size;
      const r = R.valveRead(st.lesion, input);
      const tone = r.overall ? GRADE_COLOR[r.overall] : (empty ? 'var(--fg-3)' : 'var(--accent-2)');
      let h = `<div class="r-stack"><div class="r-pickrow">${seg('lesion', R.valveLesions.map((l) => [l.id, l.short]), st.lesion, 'Lesion')}${empty ? '' : `<button type="button" class="r-iconbtn" data-a="clear" aria-label="Clear the measurements">${I.reset}</button>`}</div>`;
      h += resultCard(tone, `${eyebrow(lesion.name, tone)}<p class="r-headline big${empty ? ' muted' : ''}">${esc(R.titleCase(r.headline))}</p><p class="r-detail">${esc(r.explanation)}</p>
        ${r.lines.length ? `<div class="r-chips">${r.lines.map((l) => `<span>${l.grade ? `<i style="background:${GRADE_COLOR[l.grade]}"></i>` : ''}${esc(l.label)}: ${esc(l.text)}</span>`).join('')}</div>` : ''}
        ${r.cautions.map(caution).join('')}`);
      h += `<section class="r-sec">${eyebrow('Measurements')}<div class="r-card flush">${params.filter((p) => p.kind !== 'sign').map((p) => {
        const v = R.num(st.texts[p.id]), g = v === null ? null : R.valveGrade(p, v);
        return `<div class="r-meas"><label class="mt" for="v-${st.lesion}-${p.id}"><span>${esc(p.label)}</span>${p.hint ? `<small>${esc(p.hint)}</small>` : ''}</label>${g ? `<i class="gd" style="background:${GRADE_COLOR[g]}" title="${R.gradeLabel(g)}"></i>` : '<i class="gd"></i>'}${numIn('v-' + st.lesion + '-' + p.id, st.texts[p.id], 'num', { k: p.id, label: p.label })}<span class="mu">${esc(p.unit)}</span></div>`;
      }).join('')}</div></section>`;
      const signs = params.filter((p) => p.kind === 'sign');
      if (signs.length) h += `<section class="r-sec">${eyebrow('Signs')}<div class="r-card flush">${signs.map((p) => {
        const on = st.signs.has(p.id);
        return `<button type="button" class="r-sign" role="checkbox" aria-checked="${on}" data-a="sign" data-k="${p.id}"><span class="box" aria-hidden="true">${on ? I.check : ''}</span><span class="st"><span>${esc(p.label)}</span>${p.hint ? `<small>${esc(p.hint)}</small>` : ''}</span>${p.grade !== 2 ? `<span class="sg" style="color:${GRADE_COLOR[p.grade]}">${R.gradeLabel(p.grade)}</span>` : ''}</button>`;
      }).join('')}</div></section>`;
      h += `<footer class="r-footer"><div class="r-btns">${ghostLink('#card-ase-valve-severity', I.table, 'Grading tables')}${ghostLink('https://www.asecho.org/guideline/native-valvular-regurgitation-by-echo', I.doc, 'ASE', true)}</div>${footnote('Source: ' + lesion.source + '. The reading integrates the signs the way the documents describe and sets aside what you leave blank; it is a second pair of eyes on the numbers, not a report. Loading conditions in the operating room usually under-read regurgitation.')}</footer>`;
      return h + `</div>`;
    }, {
      lesion(el) { st.lesion = el.dataset.v; st.texts = {}; st.signs = new Set(); },
      clear() { st.texts = {}; st.signs = new Set(); },
      num(el) { st.texts[el.dataset.k] = el.value; },
      sign(el) { const k = el.dataset.k; if (st.signs.has(k)) st.signs.delete(k); else st.signs.add(k); },
    });
  }

  // ---------- AHA/ACC valve intervention ----------
  function mountIntervention(host) {
    const st = { lesion: 'as', answers: {} };
    const classColor = { '1': 'var(--new)', '2a': 'var(--accent-2)', '2b': 'var(--fg-2)', '3': 'var(--accent)' };
    view(host, () => {
      const lesion = R.viLesions.find((l) => l.id === st.lesion), qs = R.viQuestions(st.lesion), r = R.viEvaluate(st.lesion, st.answers);
      const top = r.matched.find((x) => x.group === 'Intervention') || null, empty = !Object.keys(st.answers).length;
      const tone = top ? classColor[top.cls] : (empty ? 'var(--fg-3)' : (r.fallback ? 'var(--new)' : 'var(--accent-2)'));
      let h = `<div class="r-stack"><div class="r-pickrow"><label class="r-lesion" for="vi-lesion"><span class="r-eyebrow">Lesion</span><select id="vi-lesion" data-a="lesion">${R.viLesions.map((l) => `<option value="${l.id}"${l.id === st.lesion ? ' selected' : ''}>${esc(l.name)}</option>`).join('')}</select></label>${empty ? '' : `<button type="button" class="r-iconbtn big" data-a="clear" aria-label="Clear the answers">${I.reset}</button>`}</div>`;
      let inner = eyebrow(top ? `${R.viClassWord(top.cls)} · class ${top.cls}` : (r.fallback ? 'Surveillance' : 'Answer the questions'), tone);
      if (top) inner += `<p class="r-headline big">${esc(top.recommendation)}</p><p class="r-detail">${esc(top.situation)}</p>${top.note ? `<p class="r-note2">${I.info}<span>${esc(top.note)}</span></p>` : ''}`;
      else if (r.fallback) inner += `<p class="r-lede">${esc(r.fallback)}</p>`;
      else inner += `<p class="r-headline big muted">${empty ? 'Severity and Symptoms First' : 'Nothing Settled Yet'}</p><p class="r-detail">${empty ? 'The recommendations appear as the answers come in; the dots mark the questions that would decide.' : 'Keep going: the marked questions decide.'}</p>`;
      const rest = r.matched.filter((x) => !top || x.id !== top.id);
      if (rest.length) {
        inner += `<div class="r-recs">`;
        rest.forEach((x, i) => {
          if (i === 0 || rest[i - 1].group !== x.group) inner += eyebrow(x.group);
          inner += `<div class="rec"><span class="cls" style="color:${classColor[x.cls]}">${x.cls}</span><span class="rt"><span>${esc(x.recommendation)}</span><small>${esc(x.situation)} · ${esc(x.level)}</small>${x.note ? `<small class="nt">${esc(x.note)}</small>` : ''}</span></div>`;
        });
        inner += `</div>`;
      }
      if (r.needed.length) {
        const labels = r.needed.map((id) => (qs.find((q) => q.id === id) || {}).label).filter(Boolean);
        inner += `<p class="r-next">${I.chevR}<span>${r.matched.length ? 'Could add: ' : 'Decides: '}${esc(labels.slice(0, 3).join(' · ') + (labels.length > 3 ? ' · …' : ''))}</span></p>`;
      }
      h += resultCard(tone, inner);
      const needed = new Set(r.needed);
      h += `<section class="r-sec">${eyebrow('What is known')}<div class="r-card flush">${qs.map((q) => `<div class="r-q"><p class="ql"><i class="${needed.has(q.id) ? 'on' : ''}"></i><span>${esc(q.label)}${q.hint ? `<small>${esc(q.hint)}</small>` : ''}</span></p>${pills('ans', q.id, q.options, st.answers[q.id])}</div>`).join('')}</div>${footnote(lesion.severity)}</section>`;
      h += `<footer class="r-footer"><div class="r-btns">${ghostLink('#card-acc-aha-valve-intervention', I.table, 'Full tables')}${ghostLink('https://doi.org/10.1161/CIR.0000000000000923', I.doc, 'Guideline', true)}</div>${footnote('2020 ACC/AHA guideline for valvular heart disease (Otto et al, Circulation 2021;143:e72–e227), the current edition; the next is scheduled for 2027. Classes: 1 recommended, 2a reasonable, 2b may be considered, 3 no benefit or harm. Severe valve disease is evaluated by a multidisciplinary Heart Valve Team when intervention is considered (class 1); the full tables carry prosthesis anticoagulation, bridging and endocarditis prophylaxis.')}</footer>`;
      return h + `</div>`;
    }, {
      lesion(el) { st.lesion = el.value; st.answers = {}; },
      clear() { st.answers = {}; },
      ans(el) { const k = el.dataset.k, v = el.dataset.v; if (st.answers[k] === v) delete st.answers[k]; else st.answers[k] = v; },
    });
  }

  // ---------- search ----------
  function searchHTML(q) {
    const s = q.toLowerCase();
    const tools = [];
    for (const f of FOLDERS) for (const id of f.items) {
      const t = toolMeta(id);
      if (!t) continue;
      let hit = (t.title + ' ' + t.blurb).toLowerCase().includes(s) || t.keywords.some((k) => k.includes(s) || s.includes(k));
      if (!hit && t.score) hit = R.scoreSearchText(R.score(t.score)).includes(s);
      if (!hit && bundle) {
        if (id === 'tool-peds' && bundle.peds) hit = bundle.peds.drugs.some((d) => d.name.toLowerCase().includes(s));
        if (id === 'tool-local' && bundle.peds) hit = bundle.peds.localAnesthetics.some((d) => d.name.toLowerCase().includes(s));
        if (id === 'tool-infusions' && bundle.infusions) hit = bundle.infusions.groups.some((g) => g.drugs.some((d) => (d.name + ' ' + d.use + ' ' + (d.role || '')).toLowerCase().includes(s)));
      }
      if (hit) tools.push(id);
    }
    const refs = (bundle ? bundle.quickrefs : []).filter((r) => refSearchText(r).includes(s));
    const posts = F.posts().filter((p) => (p.headline + ' ' + p.summary + ' ' + p.trialName + ' ' + p.journal + ' ' + p.kind + ' ' + p.takeHome.join(' ')).toLowerCase().includes(s));
    if (!tools.length && !refs.length && !posts.length) return `<div class="r-empty"><strong>Nothing matches “${esc(q)}”</strong><span>Try a drug, a score, a society or a procedure.</span></div>`;
    let h = '';
    if (tools.length) h += `<section class="r-sec">${eyebrow('Calculators and guides')}<div class="r-tiles">${tools.map((id) => tile(id)).join('')}</div></section>`;
    if (refs.length) h += `<section class="r-sec">${eyebrow('Quick references')}<div class="r-card flush">${refs.map((r) => `<a class="r-rowlink" href="#card-${esc(r.id)}"><span class="rt"><strong>${esc(R.titleCase(r.title))}</strong><small>${r.emergency ? '<em>Emergency</em>' : `<i style="background:var(--t-${esc(r.topic || 'general')}-fg)"></i>`}${esc(r.short || r.society)}${r.year ? ' · ' + r.year : ''}</small></span>${I.chevR}</a>`).join('')}</div></section>`;
    if (posts.length) h += `<section class="r-sec"><div class="r-sechead">${eyebrow('In the feed')}<span class="r-count">${posts.length}</span></div><div class="r-card flush">${posts.slice(0, 25).map((p) => `<button type="button" class="r-rowlink" data-post="${esc(p.id)}"><span class="rt"><strong>${esc(p.headline)}</strong><small><i style="background:var(--t-${esc(p.topics[0] || 'general')}-fg)"></i>${esc(p.journal)} · ${esc(p.kind)} · ${esc(F.fmtDate(p.date, true))}${p.impact === 3 ? ' <em>Landmark</em>' : ''}</small></span>${I.chevR}</button>`).join('')}</div></section>`;
    return h;
  }
  function refSearchText(r) {
    const parts = [r.title, r.society, r.short || '', r.summary].concat(r.keywords || []);
    for (const s of r.sections) { if (s.heading) parts.push(s.heading); parts.push(...(s.items || [])); if (s.text) parts.push(s.text); for (const row of s.rows || []) parts.push(...row); }
    return parts.join(' ').toLowerCase();
  }

  // ---------- home, folders, tiles ----------
  function tile(id) {
    const t = toolMeta(id); if (!t) return '';
    const on = favs.has(id);
    return `<div class="r-tile"><a class="r-tilelink" href="#${id}"><span class="ti">${I[t.icon] || I.table}</span><span class="tt">${esc(t.title)}</span><span class="tb">${esc(t.blurb)}</span></a><button type="button" class="r-star" data-fav="${id}" aria-pressed="${on}" aria-label="${on ? 'Remove from favorites' : 'Add to favorites'}">${on ? I.starFill : I.star}</button></div>`;
  }
  let homeQuery = '';
  function homeHTML() {
    let h = `<div class="r-stack"><label class="r-searchbox" for="ref-q">${I.search}<input id="ref-q" type="search" autocomplete="off" placeholder="Drug, score, society, procedure" value="${esc(homeQuery)}" aria-label="Search the reference"></label><div id="ref-home-body">${homeBody()}</div></div>`;
    return h;
  }
  function homeBody() {
    if (homeQuery.trim()) return searchHTML(homeQuery.trim());
    let h = '';
    const favList = favs.list.filter((id) => toolMeta(id));
    if (favList.length) h += `<section class="r-sec">${eyebrow('Favorites')}<div class="r-tiles">${favList.map(tile).join('')}</div></section>`;
    h += `<section class="r-sec"><nav class="r-card flush r-folders" aria-label="Reference folders">${FOLDERS.map((f) => {
      const one = f.items.length === 1, t1 = one ? toolMeta(f.items[0]) : null;
      const summary = one ? t1.blurb : f.items.map((id) => (toolMeta(id) || {}).title).join(' · ');
      return `<a class="r-folder" href="#${one ? f.items[0] : 'folder-' + f.id}" style="--tint:${f.tint}"><span class="fi">${I[f.icon]}</span><span class="ft"><span class="fn">${esc(f.title)}</span><span class="fs">${esc(summary)}</span></span>${one ? '' : `<span class="fc">${f.items.length}</span>`}${I.chevR}</a>`;
    }).join('')}</nav>`;
    h += footnote('Calculators ask for what they need and give the answer; the condensed references cite their society document and link to it. Confirm against the source before acting. Favorites are kept on this device.');
    if (bundle && bundle.updated) h += `<p class="r-eyebrow small">Content reviewed ${esc(monthYear(bundle.updated))}</p>`;
    return h + `</section>`;
  }
  function folderHTML(f) {
    return `<div class="r-stack"><div class="r-tiles">${f.items.map(tile).join('')}</div>${footnote('Tap the star on a tool to keep it in your favorites at the top of Reference.')}${f.note ? footnote(f.note) : ''}</div>`;
  }

  // ---------- router and page chrome ----------
  const refEl = $('#ref');
  let current = null, cleanup = null, navStack = [], lastRef = 'reference';
  const scrollMem = {};
  function go(hash) { if (location.hash.slice(1) === hash) route(); else location.hash = hash; }
  function parentOf(h) {
    if (h === 'reference') return null;
    if (h.startsWith('folder-')) return { hash: 'reference', label: 'Reference' };
    const f = folderOf(h);
    if (f && f.items.length > 1) return { hash: 'folder-' + f.id, label: f.title };
    return { hash: 'reference', label: 'Reference' };
  }
  function headHTML(h, title, opts) {
    const back = navStack.length > 1 ? { label: labelFor(navStack[navStack.length - 2]), stack: true } : parentOf(h);
    const fav = opts && opts.fav;
    return `<header class="r-head">${back ? `<a class="r-back" href="#${back.stack ? navStack[navStack.length - 2] : back.hash}" data-back="${back.stack ? '1' : ''}">${I.chevL}<span>${esc(back.label)}</span></a>` : ''}<div class="r-titlebar"><h2 class="r-title" id="ref-title">${esc(title)}</h2>${fav ? `<button type="button" class="r-fav" data-fav="${h}" aria-pressed="${favs.has(h)}">${favs.has(h) ? I.starFill : I.star}<span>${favs.has(h) ? 'Favorite' : 'Add to favorites'}</span></button>` : ''}</div></header>`;
  }
  function labelFor(h) {
    if (h === 'reference') return 'Reference';
    if (h.startsWith('folder-')) { const f = FOLDERS.find((x) => 'folder-' + x.id === h); return f ? f.title : 'Back'; }
    const t = toolMeta(h); return t ? t.title : 'Back';
  }
  function show(view) {
    const ref = view === 'ref';
    document.body.classList.toggle('view-ref', ref);
    document.querySelectorAll('[data-tab]').forEach((b) => b.setAttribute('aria-selected', String(b.dataset.tab === view)));
  }
  let feedScroll = 0;
  function route() {
    const h = decodeURIComponent((location.hash || '').slice(1));
    if (!isRefRoute(h)) {
      if (current !== null) {
        if (cleanup) { cleanup(); cleanup = null; }
        current = null; navStack = [];
        show('feed');
        requestAnimationFrame(() => window.scrollTo(0, feedScroll));
      }
      return;
    }
    if (current === null) { feedScroll = window.scrollY; show('ref'); }
    if (current !== null) scrollMem[current] = window.scrollY;
    if (cleanup) { cleanup(); cleanup = null; }
    // Navigation stack: a return to the previous page pops it.
    if (navStack.length > 1 && navStack[navStack.length - 2] === h) navStack.pop();
    else if (navStack[navStack.length - 1] !== h) navStack.push(h);
    if (h === 'reference') navStack = ['reference'];
    current = h; lastRef = h;
    if (!bundle) loadBundle().then(() => { if (current === h && (h === 'reference' || h.startsWith('folder-'))) renderStatic(h); });
    if (h === 'reference' || h.startsWith('folder-')) renderStatic(h);
    else renderTool(h);
    const y = (h === 'reference' || h.startsWith('folder-')) ? scrollMem[h] : undefined;
    const top = Math.max(0, refEl.getBoundingClientRect().top + window.scrollY - mastHeight() - 8);
    requestAnimationFrame(() => window.scrollTo(0, y !== undefined ? y : (window.scrollY > top ? top : window.scrollY)));
  }
  const mastHeight = () => { const m = $('.masthead'); return m ? m.getBoundingClientRect().height : 0; };
  function renderStatic(h) {
    if (h === 'reference') {
      const q = $('#ref-q');
      if (q && current === 'reference' && refEl.querySelector('#ref-home-body')) { $('#ref-home-body').innerHTML = homeBody(); return; }
      refEl.innerHTML = `<div class="r-page">${headHTML(h, 'Reference')}${homeHTML()}</div>`;
      return;
    }
    const f = FOLDERS.find((x) => 'folder-' + x.id === h);
    if (!f) { refEl.innerHTML = `<div class="r-page">${headHTML(h, 'Not found')}<p class="r-muted">That folder does not exist.</p></div>`; return; }
    refEl.innerHTML = `<div class="r-page" style="--tint:${f.tint}">${headHTML(h, f.title)}${folderHTML(f)}</div>`;
  }
  function renderTool(h) {
    const t = toolMeta(h);
    if (!t) {
      refEl.innerHTML = `<div class="r-page">${headHTML(h, 'Not found')}<p class="r-muted">That tool is not in the reference. Go back to the folders.</p></div>`;
      return;
    }
    refEl.innerHTML = `<div class="r-page">${headHTML(h, t.title, { fav: true })}<div class="r-tool" id="ref-tool"></div></div>`;
    try { cleanup = t.mount($('#ref-tool')) || null; }
    catch (e) { $('#ref-tool').innerHTML = `<p class="r-muted">This tool hit an error: ${esc(e && e.message)}. Reload the page to try again.</p>`; }
    // A quick reference's title arrives with the bundle.
    if (h.startsWith('card-') && !bundle) loadBundle().then(() => { if (current === h) { const tt = toolMeta(h); const el = $('#ref-title'); if (el && tt) el.textContent = tt.title; } });
  }

  // Page-level events: tabs, back links, favorites, search, post rows.
  document.addEventListener('click', (e) => {
    const tab = e.target.closest('[data-tab]');
    if (tab) {
      e.preventDefault();
      if (tab.dataset.tab === 'ref') { if (current === null) go(lastRef || 'reference'); else if (current !== 'reference') { navStack = []; go('reference'); } }
      else if (current !== null) { try { history.pushState(null, '', location.pathname + location.search); } catch (err) { location.hash = ''; } route(); }
      return;
    }
    const back = e.target.closest('.r-back');
    if (back && back.dataset.back === '1') { e.preventDefault(); history.back(); return; }
    const fav = e.target.closest('[data-fav]');
    if (fav && refEl.contains(fav)) {
      e.preventDefault(); const id = fav.dataset.fav; favs.toggle(id);
      const on = favs.has(id);
      document.querySelectorAll(`[data-fav="${CSS.escape(id)}"]`).forEach((b) => {
        b.setAttribute('aria-pressed', String(on));
        if (b.classList.contains('r-fav')) b.innerHTML = (on ? I.starFill : I.star) + `<span>${on ? 'Favorite' : 'Add to favorites'}</span>`;
        else { b.innerHTML = on ? I.starFill : I.star; b.setAttribute('aria-label', on ? 'Remove from favorites' : 'Add to favorites'); }
      });
      if (current === 'reference' && !homeQuery.trim()) $('#ref-home-body').innerHTML = homeBody();
      return;
    }
    const post = e.target.closest('[data-post]');
    if (post && refEl.contains(post)) { const p = F.posts().find((x) => x.id === post.dataset.post); if (p) F.openPost(p); }
  });
  let qTimer;
  document.addEventListener('input', (e) => {
    if (e.target.id !== 'ref-q') return;
    clearTimeout(qTimer);
    qTimer = setTimeout(() => { homeQuery = e.target.value; const b = $('#ref-home-body'); if (b) b.innerHTML = homeBody(); }, 120);
  });
  window.addEventListener('hashchange', route);
  window.addEventListener('popstate', route);
  F.onPosts(() => { if (current === 'reference' && homeQuery.trim()) { const b = $('#ref-home-body'); if (b) b.innerHTML = homeBody(); } });
  window.PSRefUI = { go, toolMeta, ctxFor };
  route();
  // Warm the cache once the feed has painted, so the tab opens instantly.
  setTimeout(loadBundle, 1500);
})();
