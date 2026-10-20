// Rasterizes the app icons and social preview from the SVGs written by tools/logo.py
// Usage: python3 -I tools/logo.py square > icons/icon.svg; python3 -I tools/logo.py square 0.1 > icons/icon-maskable.svg; node tools/make_icons.js
const fs = require('fs');
const path = require('path');
let sharp;
try { sharp = require('sharp'); } catch (e) { sharp = require('/opt/npm-tools/node_modules/sharp'); }
const root = path.join(__dirname, '..');
const out = path.join(root, 'icons');
const RED = '#F2634F';
const base = fs.readFileSync(path.join(out, 'icon.svg'));
const maskable = fs.readFileSync(path.join(out, 'icon-maskable.svg'));
const wide = fs.readFileSync(path.join(out, 'mark-wide.svg'), 'utf8').replace(/<\?xml[^>]*>/, '').replace(/ aria-hidden="true"/, '');
const wideInner = wide.replace(/^<svg[^>]*>/, '').replace(/<\/svg>\s*$/, '');
const ogSvg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 630">
  <defs>
    <radialGradient id="g1" cx="50%" cy="-10%" r="70%"><stop offset="0" stop-color="#7AAAFF" stop-opacity=".28"/><stop offset="1" stop-color="#7AAAFF" stop-opacity="0"/></radialGradient>
    <radialGradient id="g2" cx="100%" cy="0%" r="55%"><stop offset="0" stop-color="${RED}" stop-opacity=".22"/><stop offset="1" stop-color="${RED}" stop-opacity="0"/></radialGradient>
    <linearGradient id="lg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FF7A66"/><stop offset="1" stop-color="#D9472F"/></linearGradient>
  </defs>
  <rect width="1200" height="630" fill="#0A0E14"/>
  <rect width="1200" height="630" fill="url(#g1)"/>
  <rect width="1200" height="630" fill="url(#g2)"/>
  <rect x="96" y="160" width="340" height="136" rx="34" fill="url(#lg)"/>
  <g transform="translate(106 166) scale(2.667)">${wideInner}</g>
  <text x="480" y="250" font-family="'Arial Black', 'DejaVu Sans', Arial, sans-serif" font-size="84" font-weight="900" letter-spacing="-3"><tspan fill="#ECF0F6">Periop</tspan><tspan fill="${RED}" dx="20">Signal</tspan></text>
  <text x="480" y="318" font-family="Helvetica, Arial, 'DejaVu Sans', sans-serif" font-size="32" fill="#A9B3C2">Cardiothoracic · critical care · trauma anesthesia</text>
  <text x="480" y="364" font-family="Helvetica, Arial, 'DejaVu Sans', sans-serif" font-size="32" fill="#A9B3C2">Curated research, updated daily</text>
  <rect x="96" y="470" width="1008" height="1" fill="#2C3748"/>
  <text x="96" y="528" font-family="Helvetica, Arial, 'DejaVu Sans', sans-serif" font-size="27" fill="#717D8F">Landmark trials · guidelines · FDA notices · take-home points · paper links</text>
</svg>`;
(async () => {
  await sharp(base).resize(192, 192).png().toFile(path.join(out, 'icon-192.png'));
  await sharp(base).resize(512, 512).png().toFile(path.join(out, 'icon-512.png'));
  await sharp(maskable).resize(512, 512).png().toFile(path.join(out, 'icon-maskable-512.png'));
  await sharp(base).resize(180, 180).png().toFile(path.join(out, 'apple-touch-icon.png'));
  await sharp(Buffer.from(ogSvg)).resize(1200, 630).png().toFile(path.join(out, 'og.png'));
  console.log('icons written to', out);
})();
