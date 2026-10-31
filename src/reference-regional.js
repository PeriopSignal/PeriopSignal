/* Periop Signal regional anesthesia tools for the website's Reference tab: the Regional Technique Finder (mark the
   operative area on a body figure, get neuraxial and block options), the Peripheral Nerve Blocks reference (one card
   per block with an original placement and ultrasound schematic, volumes and cautions, linked to NYSORA) and the
   Neuraxial Guide (level, technique and dosing by procedure, with the dermatome height drawn on the figure).
   Content: reference.json "regional"; rules: R.regional in reference-logic.js. The iPhone app has the same tools
   (RegionalViews.swift). */
(function () {
  'use strict';
  const ARMS = ['shoulder', 'upper-arm', 'forearm', 'hand'];
  let focusBlock = null;   // set by the finder before it opens the block reference

  /** Dermatome → height on the figure (front view), for the neuraxial shading. */
  const LEVEL_Y = { T2: 84, T4: 104, T5: 114, T6: 122, T7: 129, T8: 136, T9: 143, T10: 150, T11: 160, T12: 170, L1: 186, L2: 232, L3: 270, L4: 300, L5: 350, S1: 396 };
  function levelY(level) {
    const m = String(level || '').toUpperCase().match(/[CTLS]\d{1,2}/);
    return m && LEVEL_Y[m[0]] !== undefined ? LEVEL_Y[m[0]] : null;
  }

  const pts = (p) => p.map(([x, y]) => `${x},${y}`).join(' ');

  /** The body figure as SVG. opts: { id, selected (Set of "region:side"), interactive, probe {view,x,y,angle},
      shadeFrom (y on the figure: shade from there down, arms excluded), saddle (shade the perineum), labels }. */
  function figure(F, view, opts) {
    const o = opts || {}, id = o.id || 'rg';
    const sel = o.selected || new Set();
    const h = [`<svg class="rg-fig${o.interactive ? ' live' : ''}${o.small ? ' small' : ''}" id="${id}-svg" viewBox="0 0 200 420" role="${o.interactive ? 'group' : 'img'}" aria-label="${o.label || 'Body figure, ' + view + ' view'}">`];
    h.push(`<defs><clipPath id="${id}-clip-${view}"><path d="${F.outline}"/><ellipse cx="${F.head.cx}" cy="${F.head.cy}" rx="${F.head.rx}" ry="${F.head.ry}"/></clipPath></defs>`);
    h.push(`<path class="rg-body" d="${F.outline}"/><ellipse class="rg-body" cx="${F.head.cx}" cy="${F.head.cy}" rx="${F.head.rx}" ry="${F.head.ry}"/>`);
    h.push(`<g clip-path="url(#${id}-clip-${view})">`);
    if (o.shadeFrom !== undefined && o.shadeFrom !== null) {
      h.push(`<rect class="rg-shade" x="0" y="${o.shadeFrom}" width="200" height="${420 - o.shadeFrom}"/>`);
      for (const r of F.regions) if (ARMS.includes(r.id)) for (const p of (r.views[view] || [])) h.push(`<polygon class="rg-cover" points="${pts(p)}"/>`);
    }
    if (o.saddle) for (const r of F.regions) if (r.id === 'perineum') for (const p of (r.views[view] || [])) h.push(`<polygon class="rg-shade" points="${pts(p)}"/>`);
    for (const r of F.regions) {
      const polys = r.views[view] || [];
      polys.forEach((p, i) => {
        const key = r.id + ':' + window.PSRef.regional.side(view, i, polys.length);
        const on = sel.has(key);
        if (o.interactive || on) h.push(`<polygon class="rg-r${on ? ' on' : ''}" data-r="${key}" points="${pts(p)}"><title>${r.name}</title></polygon>`);
      });
    }
    h.push('</g>');
    h.push(`<path class="rg-line" d="${F.outline}"/><ellipse class="rg-line" cx="${F.head.cx}" cy="${F.head.cy}" rx="${F.head.rx}" ry="${F.head.ry}"/>`);
    for (const lm of (F.landmarks[view] || [])) {
      if (lm.kind === 'dot') h.push(`<circle class="rg-lmd" cx="${lm.x}" cy="${lm.y}" r="1.7"/>`);
      else h.push(`<polyline class="rg-lm" points="${pts(lm.pts)}"/>`);
    }
    if (o.probe && o.probe.view === view) {
      const p = o.probe, len = p.len || 26;
      h.push(`<g class="rg-probe" transform="translate(${p.x} ${p.y}) rotate(${p.angle || 0})"><rect x="${-len / 2}" y="-4" width="${len}" height="8" rx="3"/></g><circle class="rg-target" cx="${p.x}" cy="${p.y}" r="${(len / 2) + 7}"/>`);
    }
    if (o.levels) for (const [lv, y] of o.levels) h.push(`<line class="rg-lv" x1="62" x2="138" y1="${y}" y2="${y}"/><text class="rg-lvt" x="140" y="${y + 3}">${lv}</text>`);
    if (o.sides !== false) {
      const left = view === 'back' ? 'L' : 'R', right = view === 'back' ? 'R' : 'L';
      h.push(`<text class="rg-side" x="12" y="22">${left}</text><text class="rg-side" x="188" y="22" text-anchor="end">${right}</text>`);
    }
    h.push('</svg>');
    return h.join('');
  }

  /** An original ultrasound schematic (160 × 100): layers, structures, the needle path and the spread. */
  function sono(s, label) {
    const W = 160, H = 100, h = [`<svg class="rg-sono" viewBox="0 0 ${W} ${H}" role="img" aria-label="${label || 'Ultrasound schematic'}">`];
    const curved = s.kind === 'curved';
    h.push(`<defs><linearGradient id="rgsg" x1="0" x2="0" y1="0" y2="1"><stop offset="0" stop-color="#2b3036"/><stop offset="1" stop-color="#121417"/></linearGradient><clipPath id="rgsc"><path d="${curved ? `M30 0 L130 0 L160 100 L0 100 Z` : `M0 0 H${W} V${H} H0 Z`}"/></clipPath></defs>`);
    h.push(`<g clip-path="url(#rgsc)"><rect width="${W}" height="${H}" fill="url(#rgsg)"/>`);
    const labels = [];
    for (const it of s.items || []) {
      switch (it.t) {
        case 'band': h.push(`<rect x="-2" y="${it.y}" width="${W + 4}" height="${it.h || 10}" rx="3" fill="#4a5058" opacity="0.85"/>`); if (it.label) labels.push([4, it.y + (it.h || 10) / 2 + 3, it.label, 'start']); break;
        case 'muscle': h.push(`<ellipse cx="${it.x}" cy="${it.y}" rx="${it.rx}" ry="${it.ry}" fill="#4f565f" stroke="#7d858f" stroke-width="0.6"/>`); if (it.label) labels.push([it.x, it.y + 3, it.label, 'middle']); break;
        case 'fascia': h.push(`<polyline points="${pts(it.pts)}" fill="none" stroke="#c9ced4" stroke-width="1.4" stroke-linecap="round"/>`); if (it.label) labels.push([it.pts[it.pts.length - 1][0], it.pts[it.pts.length - 1][1] - 3, it.label, 'end']); break;
        case 'bone': h.push(`<rect x="${it.x1}" y="${it.y}" width="${it.x2 - it.x1}" height="${H - it.y}" fill="#08090a" opacity="0.9"/><line x1="${it.x1}" x2="${it.x2}" y1="${it.y}" y2="${it.y}" stroke="#f1f3f5" stroke-width="2.2" stroke-linecap="round"/>`); if (it.label) labels.push([(it.x1 + it.x2) / 2, it.y + 10, it.label, 'middle']); break;
        case 'pleura': h.push(`<line x1="${it.x1}" x2="${it.x2}" y1="${it.y}" y2="${it.y}" stroke="#e7ebef" stroke-width="1.6"/><rect x="${it.x1}" y="${it.y + 2}" width="${it.x2 - it.x1}" height="${H - it.y}" fill="#6b7280" opacity="0.25"/>`); if (it.label) labels.push([(it.x1 + it.x2) / 2, it.y + 10, it.label, 'middle']); break;
        case 'artery': h.push(`<circle cx="${it.x}" cy="${it.y}" r="${it.r || 6}" fill="#050506" stroke="#f2634f" stroke-width="1.3"/>`); if (it.label) labels.push([it.x, it.y + (it.r || 6) + 8, it.label, 'middle']); break;
        case 'vein': h.push(`<ellipse cx="${it.x}" cy="${it.y}" rx="${it.rx || it.r || 6}" ry="${it.ry || (it.r || 6) * 0.7}" fill="#050506" stroke="#8ab8ff" stroke-width="1.2"/>`); if (it.label) labels.push([it.x, it.y + (it.ry || 5) + 8, it.label, 'middle']); break;
        case 'nerve': {
          const r = it.r || 6;
          h.push(`<circle cx="${it.x}" cy="${it.y}" r="${r}" fill="#25282c" stroke="#ffd470" stroke-width="1.3"/>`);
          const dots = r > 5 ? [[-0.35, -0.3], [0.35, -0.3], [0, 0.35], [-0.42, 0.25], [0.42, 0.25]] : [[0, 0]];
          for (const [dx, dy] of dots) h.push(`<circle cx="${(it.x + dx * r).toFixed(1)}" cy="${(it.y + dy * r).toFixed(1)}" r="${Math.max(1, r * 0.22).toFixed(1)}" fill="#0b0c0e"/>`);
          if (it.label) labels.push([it.x, it.y - r - 3, it.label, 'middle']);
          break;
        }
        case 'la': h.push(`<ellipse cx="${it.x}" cy="${it.y}" rx="${it.rx}" ry="${it.ry}" fill="#43a7ff" opacity="0.32"/>`); break;
        case 'text': labels.push([it.x, it.y, it.label, it.anchor || 'middle']); break;
        default: break;
      }
    }
    if (s.needle) {
      const [x1, y1] = s.needle.from, [x2, y2] = s.needle.to, a = Math.atan2(y2 - y1, x2 - x1);
      const ax = (d, t) => [x2 - d * Math.cos(a + t), y2 - d * Math.sin(a + t)];
      const [lx, ly] = ax(6, 0.45), [rx, ry] = ax(6, -0.45);
      h.push(`<line x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}" stroke="#ffffff" stroke-width="1.6" stroke-linecap="round"/><path d="M${x2} ${y2} L${lx.toFixed(1)} ${ly.toFixed(1)} M${x2} ${y2} L${rx.toFixed(1)} ${ry.toFixed(1)}" stroke="#ffffff" stroke-width="1.4" stroke-linecap="round"/>`);
    }
    h.push('</g>');
    for (const [x, y, t, anchor] of labels) h.push(`<text class="rg-st" x="${x}" y="${y}" text-anchor="${anchor}">${String(t).replace(/&/g, '&amp;').replace(/</g, '&lt;')}</text>`);
    h.push(`<text class="rg-st dim" x="${W - 4}" y="${H - 4}" text-anchor="end">${curved ? 'Curvilinear' : 'Linear'} probe · schematic</text>`);
    h.push('</svg>');
    return h.join('');
  }

  // ---------- Regional Technique Finder ----------
  function mountFinder(host, c) {
    const { R, esc, eyebrow, seg, footnote, I } = c;
    const G = R.regional;
    const st = { view: 'front', sel: new Set() };
    const data = () => (c.bundle() && c.bundle().regional) || null;
    const update = c.view(host, () => {
      const d = data();
      if (!d) return `<p class="r-muted">${c.bundle() ? 'The regional content is not in this copy of the reference file yet; reload in a minute.' : 'Loading…'}</p>`;
      const rec = G.recommend([...st.sel], d);
      let h = '<div class="r-stack">';
      h += `<section class="r-card rg-pick"><p class="r-small">Tap or drag across the figure to mark the incision or operative area; tap again to clear it. Switch to the back view for the spine, buttocks and the backs of the limbs.</p>`;
      h += `<div class="r-inline">${seg('view', [['front', 'Front'], ['back', 'Back']], st.view, 'View')}${st.sel.size ? `<button type="button" class="r-ghost sm" data-a="clear">${I.reset}Clear</button>` : ''}</div>`;
      h += `<div class="rg-figwrap">${figure(d.figure, st.view, { id: 'rgf', selected: st.sel, interactive: true, label: 'Body figure: tap regions to mark them' })}</div>`;
      if (rec.items.length) h += `<div class="rg-chips">${rec.items.map((it) => `<span class="rg-chip">${esc(it.label)}<button type="button" data-a="drop" data-k="${esc(it.id)}" aria-label="Remove ${esc(it.label)}">${I.x}</button></span>`).join('')}</div>`;
      h += `</section>`;
      if (!rec.items.length) {
        h += `<section class="r-card"><p class="r-muted">Nothing marked yet. The options for each marked area appear here: neuraxial technique and level, and the peripheral blocks NYSORA describes for it.</p></section>`;
      } else {
        if (rec.items.length > 1 && rec.top) h += `<section class="r-card r-result" style="--tone:var(--accent-2)">${eyebrow('Neuraxial height for everything marked', 'var(--accent-2)')}<p class="r-headline big">${esc(rec.top.level)}</p><p class="r-detail">The highest level any marked area needs (${esc(rec.top.region.toLowerCase())}). A spinal or epidural planned for all of them has to reach it.</p></section>`;
        for (const it of rec.items) {
          const n = it.neuraxial;
          let inner = `${eyebrow(it.label)}`;
          if (n) {
            inner += `<div class="rg-nx"><span class="rg-nxl">${esc(n.technique || 'Neuraxial')}</span><span class="rg-nxv">${n.level ? 'to ' + esc(n.level) : ''}</span></div>`;
            if (n.text) inner += `<p class="r-detail">${esc(n.text)}</p>`;
          } else inner += `<p class="r-detail">No neuraxial technique: ${esc(it.blocks.length ? 'use the blocks below or general anesthesia.' : 'general anesthesia or local infiltration.')}</p>`;
          if (it.blocks.length) {
            const prim = it.blocks.filter((b) => b.role !== 'alternative'), alt = it.blocks.filter((b) => b.role === 'alternative');
            const row = (b) => `<a class="r-rowlink rg-blk" href="#tool-blocks" data-a="block" data-k="${esc(b.id)}"><span class="rt"><strong>${esc(b.name)}</strong>${b.note ? `<small>${esc(b.note)}</small>` : ''}</span>${I.chevR}</a>`;
            inner += `<p class="rg-sub">Peripheral blocks</p><div class="r-card flush">${prim.map(row).join('')}</div>`;
            if (alt.length) inner += `<p class="rg-sub">Alternatives</p><div class="r-card flush">${alt.map(row).join('')}</div>`;
          }
          if (it.note) inner += footnote(it.note);
          h += `<section class="r-card">${inner}</section>`;
        }
      }
      h += `<footer class="r-footer">${eyebrow('Sources')}${(d.sources || []).map((s) => c.sourceLine(s)).join('')}${(d.finderNotes || []).map((x) => footnote(x)).join('')}<div class="r-btns">${c.ghostLink('#tool-neuraxial', I.table, 'Blocks on anticoagulants')}${c.ghostLink('#tool-local', I.table, 'Local anesthetic doses')}</div></footer>`;
      return h + '</div>';
    }, {
      view(el) { st.view = el.dataset.v; },
      clear() { st.sel.clear(); },
      drop(el) { for (const k of [...st.sel]) if (k.split(':')[0] === el.dataset.k) st.sel.delete(k); },
      block(el) { focusBlock = el.dataset.k; return false; },
    });
    // Tap or drag to paint regions: the first region touched decides whether the drag marks or clears.
    let painting = null;
    const keyAt = (x, y) => { const el = document.elementFromPoint(x, y); const p = el && el.closest && el.closest('[data-r]'); return p && host.contains(p) ? p.getAttribute('data-r') : null; };
    const paint = (k) => {
      if (!k || !painting) return;
      if (painting === 'add' ? !st.sel.has(k) : st.sel.has(k)) { if (painting === 'add') st.sel.add(k); else st.sel.delete(k); update(); }
    };
    host.addEventListener('pointerdown', (e) => {
      const p = e.target.closest && e.target.closest('[data-r]');
      if (!p) return;
      e.preventDefault();
      const k = p.getAttribute('data-r');
      painting = st.sel.has(k) ? 'remove' : 'add';
      paint(k);
      const svg = host.querySelector('#rgf-svg');
      try { if (svg) svg.setPointerCapture(e.pointerId); } catch (err) { /* capture is a nicety */ }
    });
    host.addEventListener('pointermove', (e) => { if (painting) paint(keyAt(e.clientX, e.clientY)); });
    const stop = () => { painting = null; };
    host.addEventListener('pointerup', stop);
    host.addEventListener('pointercancel', stop);
    if (!data()) c.loadBundle().then(update);
  }

  // ---------- Peripheral Nerve Blocks ----------
  function mountBlocks(host, c) {
    const { esc, eyebrow, footnote, I } = c;
    const data = () => (c.bundle() && c.bundle().regional) || null;
    const st = { group: null, open: null };
    const fields = [
      ['indications', 'Indications'], ['coverage', 'Coverage'], ['position', 'Position'], ['equipment', 'Probe and needle'],
      ['target', 'Technique'], ['volume', 'Volume and dose'], ['onset', 'Onset and duration'], ['cautions', 'Cautions'], ['tips', 'Tips'],
    ];
    const text = (v) => (Array.isArray(v) ? v : [v]).filter(Boolean);
    const update = c.view(host, () => {
      const d = data();
      if (!d) return `<p class="r-muted">${c.bundle() ? 'The block content is not in this copy of the reference file yet; reload in a minute.' : 'Loading…'}</p>`;
      if (focusBlock) {
        const b = d.blocks.find((x) => x.id === focusBlock);
        if (b) { st.group = b.group; st.open = b.id; }
        focusBlock = null;
      }
      const groups = d.blockGroups || [];
      if (!st.group || !groups.some((g) => g.id === st.group)) st.group = groups.length ? groups[0].id : null;
      let h = '<div class="r-stack">';
      h += `<div class="r-tabs" role="tablist" aria-label="Region">${groups.map((g) => `<button type="button" role="tab" data-a="group" data-v="${esc(g.id)}" aria-selected="${g.id === st.group}">${esc(g.name)}</button>`).join('')}</div>`;
      const list = d.blocks.filter((b) => b.group === st.group);
      h += `<div class="r-card flush rg-blocks">`;
      for (const b of list) {
        const open = st.open === b.id;
        h += `<div class="rg-b${open ? ' open' : ''}" id="blk-${esc(b.id)}"><button type="button" class="rg-bh" data-a="open" data-k="${esc(b.id)}" aria-expanded="${open}"><span class="rt"><strong>${esc(b.name)}</strong><small>${esc(b.summary || '')}</small></span><span class="rg-chev">${open ? '−' : '+'}</span></button>`;
        if (open) {
          h += `<div class="rg-bd">`;
          if (b.art) {
            h += `<div class="rg-art">`;
            if (b.art.probe) h += `<div class="rg-artfig">${figure(d.figure, b.art.probe.view || 'front', { id: 'bf-' + b.id, probe: b.art.probe, small: true, sides: false, label: 'Probe position for the ' + b.name })}</div>`;
            if (b.art.sono) h += `<div class="rg-artsono">${sono(b.art.sono, 'Ultrasound schematic for the ' + b.name)}${b.art.caption ? `<p class="r-small">${esc(b.art.caption)}</p>` : ''}</div>`;
            h += `</div>`;
          }
          h += `<div class="r-facts">${fields.filter(([k]) => b[k] && text(b[k]).length).map(([k, label]) => `<div class="fr"><span class="fl">${esc(label)}</span><span class="fv">${text(b[k]).map((t) => `<span class="rg-li">${esc(t)}</span>`).join('')}</span></div>`).join('')}</div>`;
          if (b.source) h += `<div class="r-btns">${c.ghostLink(b.source.url, I.ext, b.source.label, true)}</div>`;
          else if (b.url) h += `<div class="r-btns">${c.ghostLink(b.url, I.ext, 'NYSORA technique page', true)}</div>`;
          h += `</div>`;
        }
        h += `</div>`;
      }
      h += `</div>`;
      h += `<footer class="r-footer">${eyebrow('Source')}${(d.sources || []).map((s) => c.sourceLine(s)).join('')}${(d.blockNotes || []).map((x) => footnote(x)).join('')}</footer>`;
      return h + '</div>';
    }, {
      group(el) { st.group = el.dataset.v; st.open = null; },
      open(el) { st.open = st.open === el.dataset.k ? null : el.dataset.k; },
    });
    if (!data()) c.loadBundle().then(update);
  }

  // ---------- Neuraxial Guide ----------
  function mountNeuraxial(host, c) {
    const { esc, eyebrow, footnote, I } = c;
    const data = () => (c.bundle() && c.bundle().regional) || null;
    const st = { proc: '' };
    const update = c.view(host, () => {
      const d = data();
      if (!d || !d.neuraxial) return `<p class="r-muted">${c.bundle() ? 'The neuraxial content is not in this copy of the reference file yet; reload in a minute.' : 'Loading…'}</p>`;
      const N = d.neuraxial, procs = N.procedures || [];
      if (!st.proc && procs.length) st.proc = procs[0].id;
      const p = procs.find((x) => x.id === st.proc) || procs[0];
      let h = '<div class="r-stack">';
      h += `<section class="r-card"><label class="r-lesion plain r-pick" for="nx-proc"><span class="r-eyebrow">Procedure</span><span class="r-picked"><span>${esc(p ? p.name : '')}</span>${I.updown}</span><select id="nx-proc" data-a="proc" aria-label="Procedure">${procs.map((x) => `<option value="${esc(x.id)}"${x.id === st.proc ? ' selected' : ''}>${esc(x.name)}</option>`).join('')}</select></label></section>`;
      if (p) {
        const y = levelY(p.level), saddle = /^S/i.test(String(p.level || ''));
        const marks = (N.dermatomes || []).filter((x) => levelY(x.level) !== null && x.level !== 'S1').map((x) => [x.level, levelY(x.level)]);
        let inner = `${eyebrow('Target sensory level', 'var(--accent-2)')}<p class="r-headline big">${esc(p.level || '—')}</p>${p.levelText ? `<p class="r-detail">${esc(p.levelText)}</p>` : ''}`;
        inner += `<div class="rg-nxfig">${figure(d.figure, 'front', { id: 'nxf', shadeFrom: saddle ? null : y, saddle, levels: marks, sides: false, label: 'Block height ' + (p.level || '') })}</div>`;
        const rows = [['Technique', p.technique], ['Insertion', p.insertion], ['Spinal', p.spinal], ['Epidural', p.epidural], ['Adjuvants', p.adjuvants], ['Notes', p.notes]].filter(([, v]) => v && (Array.isArray(v) ? v.length : true));
        inner += `<div class="r-facts">${rows.map(([k, v]) => `<div class="fr"><span class="fl">${esc(k)}</span><span class="fv">${(Array.isArray(v) ? v : [v]).map((t) => `<span class="rg-li">${esc(t)}</span>`).join('')}</span></div>`).join('')}</div>`;
        h += c.resultCard('var(--accent-2)', inner);
      }
      for (const t of N.tables || []) h += `<section class="r-sec">${eyebrow(t.title)}${c.refTable(t.columns, t.rows)}${(t.notes || []).map((x) => footnote(x)).join('')}</section>`;
      h += `<footer class="r-footer">${eyebrow('Sources')}${(N.sources || d.sources || []).map((s) => c.sourceLine(s)).join('')}${(N.notes || []).map((x) => footnote(x)).join('')}</footer>`;
      return h + '</div>';
    }, {
      proc(el) { st.proc = el.value; },
    });
    if (!data()) c.loadBundle().then(update);
  }

  window.PSRegional = { mountFinder, mountBlocks, mountNeuraxial, figure, sono };
})();
