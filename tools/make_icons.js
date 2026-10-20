// Generates the app icons and the social preview image from one SVG design.
// Usage: node tools/make_icons.js   (needs the `sharp` package; see README)
const fs = require('fs');
const path = require('path');
let sharp;
try { sharp = require('sharp'); } catch (e) { sharp = require('/opt/npm-tools/node_modules/sharp'); }

const root = path.join(__dirname, '..');
const out = path.join(root, 'icons');
fs.mkdirSync(out, { recursive: true });

const RED = '#F2634F';
const trace = (s) => `<path d="M${2 * s} ${12 * s}h${4 * s}l${2.5 * s}-${6 * s} ${3 * s} ${12 * s} ${2.5 * s}-${8 * s} ${1.5 * s} ${2 * s}H${22 * s}" fill="none" stroke="#fff" stroke-width="${2.2 * s}" stroke-linecap="round" stroke-linejoin="round"/>`;

// 512 canvas: rounded square with the trace (used for favicon, apple touch, 192/512)
function iconSvg(pad) {
  // pad = fraction of canvas kept clear around the artwork (maskable icons need ~0.1 extra)
  const size = 512, inner = size * (1 - 2 * pad), s = inner / 24, off = size * pad;
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${size} ${size}">
  <defs><linearGradient id="lg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FF7A66"/><stop offset="1" stop-color="#D9472F"/></linearGradient></defs>
  <rect width="${size}" height="${size}" rx="${pad > 0 ? 0 : 112}" fill="url(#lg)"/>
  <g transform="translate(${off} ${off})">${trace(s)}</g>
</svg>`;
}

const ogSvg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 630">
  <defs>
    <radialGradient id="g1" cx="50%" cy="-10%" r="70%"><stop offset="0" stop-color="#7AAAFF" stop-opacity=".28"/><stop offset="1" stop-color="#7AAAFF" stop-opacity="0"/></radialGradient>
    <radialGradient id="g2" cx="100%" cy="0%" r="55%"><stop offset="0" stop-color="${RED}" stop-opacity=".22"/><stop offset="1" stop-color="${RED}" stop-opacity="0"/></radialGradient>
    <linearGradient id="lg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FF7A66"/><stop offset="1" stop-color="#D9472F"/></linearGradient>
  </defs>
  <rect width="1200" height="630" fill="#0A0E14"/>
  <rect width="1200" height="630" fill="url(#g1)"/>
  <rect width="1200" height="630" fill="url(#g2)"/>
  <rect x="96" y="150" width="200" height="200" rx="52" fill="url(#lg)"/>
  <g transform="translate(112 166)">${trace(7.3)}</g>
  <text x="340" y="250" font-family="'Arial Black', 'DejaVu Sans', Arial, sans-serif" font-size="88" font-weight="900" letter-spacing="-3"><tspan fill="#ECF0F6">Periop</tspan><tspan fill="${RED}" dx="22">Signal</tspan></text>
  <text x="340" y="318" font-family="Helvetica, Arial, 'DejaVu Sans', sans-serif" font-size="34" fill="#A9B3C2">Cardiothoracic · critical care · trauma anesthesia</text>
  <text x="340" y="366" font-family="Helvetica, Arial, 'DejaVu Sans', sans-serif" font-size="34" fill="#A9B3C2">Curated research, updated daily</text>
  <rect x="96" y="470" width="1008" height="1" fill="#2C3748"/>
  <text x="96" y="528" font-family="Helvetica, Arial, 'DejaVu Sans', sans-serif" font-size="27" fill="#717D8F">Landmark trials · guidelines · FDA notices · take-home points · paper links</text>
</svg>`;

(async () => {
  fs.writeFileSync(path.join(out, 'icon.svg'), iconSvg(0));
  const base = Buffer.from(iconSvg(0));
  const maskable = Buffer.from(iconSvg(0.1));
  await sharp(base).resize(192, 192).png().toFile(path.join(out, 'icon-192.png'));
  await sharp(base).resize(512, 512).png().toFile(path.join(out, 'icon-512.png'));
  await sharp(maskable).resize(512, 512).png().toFile(path.join(out, 'icon-maskable-512.png'));
  await sharp(base).resize(180, 180).png().toFile(path.join(out, 'apple-touch-icon.png'));
  await sharp(Buffer.from(ogSvg)).resize(1200, 630).png().toFile(path.join(out, 'og.png'));
  console.log('icons written to', out);
})();
