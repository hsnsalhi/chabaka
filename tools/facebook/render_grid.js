// Rend une grille exportée (test/tools/export_grid_test.dart) en deux images
// carrées 1080×1080 pour Facebook : la grille vide et la solution.
//
//   NODE_PATH=$(npm root -g) node tools/facebook/render_grid.js grid.json out_dir [titre]
//
// Dépend de Playwright (chromium à /opt/pw-browsers/chromium dans le cloud).
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const [,, jsonPath, outDir, title = 'شبكة اليوم'] = process.argv;
if (!jsonPath || !outDir) {
  console.error('usage: render_grid.js grid.json out_dir [titre]');
  process.exit(1);
}
const grid = JSON.parse(fs.readFileSync(jsonPath, 'utf8'));
fs.mkdirSync(outDir, { recursive: true });

// Ordre d'affichage des indices dans une case (même règle que l'app) :
// flèches sortant à gauche, puis à droite, puis en bas.
const exitOf = { hSameRow: 'left', vColRight: 'left', vColLeft: 'right', vSameCol: 'bottom', hRowBelow: 'bottom' };
const rank = { left: 0, right: 1, bottom: 2 };
function orderedClues(cell) {
  return cell.clues.map((c, i) => [c, i]).sort((a, b) => (rank[exitOf[a[0].arrowType]] - rank[exitOf[b[0].arrowType]]) || (a[1] - b[1])).map(x => x[0]);
}

// Flèches : repère écran RTL. La colonne c+1 est à GAUCHE de la case.
function arrowPath(x, y, size, cy, type) {
  const inset = size * 0.11, over = size * 0.18, head = size * 0.07;
  const l = x, r = x + size, b = y + size;
  let pts, dir;
  switch (type) {
    case 'hSameRow': pts = [[l + inset, cy], [l - over, cy]]; dir = 'left'; break;
    case 'vColRight': pts = [[l + inset, cy], [l - over, cy], [l - over, cy + over]]; dir = 'down'; break;
    case 'vColLeft': pts = [[r - inset, cy], [r + over, cy], [r + over, cy + over]]; dir = 'down'; break;
    case 'vSameCol': { const cx = x + size / 2; pts = [[cx, b - inset], [cx, b + over]]; dir = 'down'; break; }
    case 'hRowBelow': { const cx = l + size * 0.28; pts = [[cx, b - inset], [cx, b + over], [cx - over, b + over]]; dir = 'left'; break; }
    default: return '';
  }
  const [tx, ty] = pts[pts.length - 1];
  const headPts = dir === 'down'
    ? `${tx},${ty + head} ${tx - head},${ty - head * 0.6} ${tx + head},${ty - head * 0.6}`
    : `${tx - head},${ty} ${tx + head * 0.6},${ty - head} ${tx + head * 0.6},${ty + head}`;
  return `<polyline points="${pts.map(p => p.join(',')).join(' ')}" fill="none" stroke="#7A1D1D" stroke-width="${size * 0.045}" stroke-linecap="round" stroke-linejoin="round"/><polygon points="${headPts}" fill="#7A1D1D"/>`;
}

function buildHtml(solved) {
  const W = 1080, pad = 60, headerH = 150, footerH = 110;
  const gw = W - 2 * pad, gh = W - headerH - footerH - pad;
  const size = Math.floor(Math.min(gw / grid.cols, gh / grid.rows));
  const gx = (W - size * grid.cols) / 2, gy = headerH + (gh - size * grid.rows) / 2 + 10;
  let cells = '', arrows = '';
  for (let r = 0; r < grid.rows; r++) {
    for (let c = 0; c < grid.cols; c++) {
      const cell = grid.cells[r][c];
      const vc = grid.cols - 1 - c; // RTL
      const x = gx + vc * size, y = gy + r * size;
      if (cell.type === 'letter') {
        const letter = solved ? cell.solution : '';
        cells += `<div class="lc" style="left:${x}px;top:${y}px;width:${size}px;height:${size}px;font-size:${size * 0.58}px">${letter}</div>`;
      } else {
        const clues = orderedClues(cell);
        const n = Math.max(clues.length, 1);
        const lines = clues.map(cl => `<div class="cl" style="height:${(size - 10) / n}px;font-size:${clueFont(cl.text, size, n)}px">${cl.text}</div>`).join('');
        cells += `<div class="cc" style="left:${x}px;top:${y}px;width:${size}px;height:${size}px">${lines}</div>`;
        clues.forEach((cl, i) => {
          const cy = y + 5 + (i + 0.5) * ((size - 10) / n);
          arrows += arrowPath(x, y, size, cy, cl.arrowType);
        });
      }
    }
  }
  return `<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8">
<link href="https://fonts.googleapis.com/css2?family=Cairo:wght@500;600;700;800&family=Amiri:wght@700&display=swap" rel="stylesheet">
<style>
*{box-sizing:border-box;margin:0}
body{width:${W}px;height:${W}px;background:#F5E6D3;font-family:Cairo,sans-serif;color:#1C0E07;position:relative;overflow:hidden}
.bg{position:absolute;inset:0;background-image:radial-gradient(circle at 20% 10%,rgba(212,175,55,.18),transparent 45%),radial-gradient(circle at 85% 95%,rgba(122,29,29,.14),transparent 45%)}
.head{position:absolute;top:0;left:0;right:0;height:${headerH}px;display:flex;align-items:center;justify-content:space-between;padding:0 ${pad}px}
.title{font-family:Amiri,serif;font-size:62px;color:#7A1D1D;line-height:1.2}
.sub{font-size:24px;color:#8C6E58;font-weight:600;margin-top:-6px}
.logo{width:92px;height:92px;border-radius:24px;background:radial-gradient(circle at 30% 25%,#A83232,#7A1D1D 55%,#4F0E0E);color:#F5E6D3;font-family:Amiri,serif;font-size:64px;display:flex;align-items:center;justify-content:center;box-shadow:0 10px 30px -8px rgba(122,29,29,.6)}
.logo span{transform:translateY(-6px)}
.board{position:absolute;left:${gx - 6}px;top:${gy - 6}px;width:${size * grid.cols + 12}px;height:${size * grid.rows + 12}px;background:#7A1D1D;border-radius:10px;box-shadow:0 24px 50px -20px rgba(28,14,7,.45)}
.lc,.cc{position:absolute;border:1.5px solid #8C6E58;display:flex;flex-direction:column;align-items:center;justify-content:center}
.lc{background:#FDF6EE;font-weight:700;color:#7A1D1D}
.cc{background:#EAD6BE;padding:5px 4px}
.cl{display:flex;align-items:center;justify-content:center;text-align:center;font-weight:700;line-height:1.15;width:100%;color:#1C0E07;padding:0 3px}
.cl+.cl{border-top:1.5px solid #8C6E58}
.foot{position:absolute;bottom:0;left:0;right:0;height:${footerH}px;display:flex;align-items:center;justify-content:space-between;padding:0 ${pad}px;color:#8C6E58;font-size:26px;font-weight:600}
.foot b{color:#7A1D1D}
svg{position:absolute;left:0;top:0;pointer-events:none}
</style></head><body>
<div class="bg"></div>
<div class="head"><div><div class="title">${title}</div><div class="sub">${solved ? 'الحل' : 'كلمات مسهمة · حلّها في التعليقات'}</div></div><div class="logo"><span>ش</span></div></div>
<div class="board"></div>${cells}
<svg width="${W}" height="${W}">${arrows}</svg>
<div class="foot"><span>من تطبيق <b>شبكة</b> · شبكات لا نهائية بدون إنترنت</span><span dir="ltr">techlyb.com/chabaka</span></div>
</body></html>`;
}

function clueFont(text, size, n) {
  const len = text.length;
  let f = size * (n === 1 ? 0.2 : 0.17);
  if (len > 10) f *= 0.85;
  if (len > 16) f *= 0.8;
  if (len > 24) f *= 0.8;
  return Math.max(f, size * 0.11);
}

(async () => {
  const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || '/opt/pw-browsers/chromium' });
  for (const solved of [false, true]) {
    const page = await browser.newPage({ viewport: { width: 1080, height: 1080 }, deviceScaleFactor: 1 });
    await page.setContent(buildHtml(solved), { waitUntil: 'networkidle' });
    await page.evaluate(() => document.fonts.ready);
    const out = path.join(outDir, solved ? 'solution.png' : 'grille.png');
    await page.screenshot({ path: out });
    console.log('→', out);
    await page.close();
  }
  await browser.close();
})();
