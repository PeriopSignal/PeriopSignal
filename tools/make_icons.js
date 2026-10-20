// Generates the app icons and the social preview image from one SVG design.
// Usage: node tools/make_icons.js   (needs the `sharp` package; see README)
const fs = require('fs');
const path = require('path');
let sharp;
try { sharp = require('sharp'); } catch (e) { sharp = require('/opt/npm-tools/node_modules/sharp'); }

const root = path.join(__dirname, '..');
const out = path.join(root, 'icons');
fs.mkdirSync(out, { recursive: true });

const RED = '#D43A3C';
const trace = (s) => `<path d="M${2 * s} ${12 * s}h${4 * s}l${2.5 * s}-${6 * s} ${3 * s} ${12 * s} ${2.5 * s}-${8 * s} ${1.5 * s} ${2 * s}H${22 * s}" fill="none" stroke="#fff" stroke-width="${2.2 * s}" stroke-linecap="round" stroke-linejoin="round"/>`;

// 512 canvas: rounded square with the trace (used for favicon, apple touch, 192/512)
function iconSvg(pad) {
  // pad = fraction of canvas kept clear around the artwork (maskable icons need ~0.1 extra)
  const size = 512, inner = size * (1 - 2 * pad), s = inner / 24, off = size * pad;
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${size} ${size}">
  <rect width="${size}" height="${size}" rx="${pad > 0 ? 0 : 112}" fill="${RED}"/>
  <g transform="translate(${off} ${off})">${trace(s)}</g>
</svg>`;
}

const ogSvg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 630">
  <rect width="1200" height="630" fill="#F3F5F8"/>
  <rect x="96" y="150" width="200" height="200" rx="48" fill="${RED}"/>
  <g transform="translate(112 166)">${trace(7.3)}</g>
  <text x="340" y="250" font-family="Helvetica, Arial, sans-serif" font-size="92" font-weight="700" fill="#141B25" letter-spacing="-2">Periop Signal</text>
  <text x="340" y="320" font-family="Helvetica, Arial, sans-serif" font-size="36" fill="#4A5667">Cardiothoracic · critical care · trauma anesthesia</text>
  <text x="340" y="370" font-family="Helvetica, Arial, sans-serif" font-size="36" fill="#4A5667">Curated research, updated daily</text>
  <rect x="96" y="470" width="1008" height="2" fill="#CBD3DD"/>
  <text x="96" y="530" font-family="Helvetica, Arial, sans-serif" font-size="28" fill="#7A8697">Landmark trials · guidelines · FDA notices · take-home points · paper links</text>
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
