// Rend les visuels d'identité de la page Facebook « الإعراب » :
// photo de profil (1024×1024) et photo de couverture (1640×624).
//
//   NODE_PATH=$(npm root -g) node tools/facebook/render_brand.js out_dir
//
// Palette claire : ivoire, or pâle, rose poudré, bordeaux (#7A1D1D) hérité des
// images de grilles (render_grid.js). Dépend de Playwright (chromium).
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const [,, outDir = 'build/fb/brand'] = process.argv;
fs.mkdirSync(outDir, { recursive: true });

const FONTS = '<link href="https://fonts.googleapis.com/css2?family=Cairo:wght@500;600;700;800&family=Amiri:wght@400;700&display=swap" rel="stylesheet">';
const BASE = `
*{box-sizing:border-box;margin:0}
body{font-family:Cairo,sans-serif;color:#1C0E07;position:relative;overflow:hidden;background:#FBF7F1}
.bg{position:absolute;inset:0;background:
  radial-gradient(circle at 15% 15%,rgba(226,196,120,.32),transparent 42%),
  radial-gradient(circle at 88% 85%,rgba(196,120,120,.22),transparent 45%),
  radial-gradient(circle at 80% 10%,rgba(255,255,255,.9),transparent 40%),
  linear-gradient(135deg,#FDFAF4,#F7EEE2)}
.pattern{position:absolute;inset:0;opacity:.35;background-image:
  linear-gradient(rgba(140,110,88,.18) 1px,transparent 1px),
  linear-gradient(90deg,rgba(140,110,88,.18) 1px,transparent 1px);
  -webkit-mask-image:radial-gradient(circle at 50% 50%,#000 20%,transparent 75%)}
.maroon{color:#7A1D1D}
`;

// ── Profil ────────────────────────────────────────────────────────────────────
function profileHtml() {
  const W = 1024;
  return `<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8">${FONTS}<style>${BASE}
body{width:${W}px;height:${W}px}
.pattern{background-size:64px 64px}
.ring{position:absolute;inset:54px;border-radius:50%;border:3px solid rgba(122,29,29,.14)}
.ring2{position:absolute;inset:78px;border-radius:50%;border:1.5px solid rgba(201,160,80,.45)}
.card{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:0}
.word{font-family:Amiri,serif;font-weight:700;font-size:256px;line-height:1.1;color:#7A1D1D;margin-top:-30px;
  text-shadow:0 6px 0 rgba(255,255,255,.9),0 16px 36px rgba(122,29,29,.14)}
.tag{display:flex;align-items:center;gap:18px;margin-top:22px;font-size:40px;font-weight:700;color:#8C6E58;letter-spacing:.5px}
.tag i{display:block;width:12px;height:12px;border-radius:50%;background:#C9A050}
.cells{position:absolute;bottom:118px;left:50%;transform:translateX(-50%);display:flex;gap:10px;direction:rtl}
.cells div{width:56px;height:56px;border:2px solid #8C6E58;border-radius:8px;background:#FFFDF9;display:flex;align-items:center;justify-content:center;font-family:Amiri,serif;font-weight:700;font-size:40px;color:#7A1D1D;box-shadow:0 6px 14px -8px rgba(28,14,7,.3)}
.cells div.e{background:#EAD6BE}
</style></head><body><div class="bg"></div><div class="pattern"></div><div class="ring"></div><div class="ring2"></div>
<div class="card"><div class="word">الإعراب</div>
<div class="tag"><span>نَحْو</span><i></i><span>كلمات مسهمة</span></div></div>
<div class="cells"><div>إ</div><div>ع</div><div>ر</div><div>ا</div><div>ب</div></div>
</body></html>`;
}

// ── Couverture ────────────────────────────────────────────────────────────────
function miniGrid() {
  // Petite grille décorative 6×4 (RTL), mélange de cases définition, lettres et vides.
  const rows = [
    ['c:نحو', 'ن', 'ح', 'و', 'c:لغة', 'c:كلمة'],
    ['ل', 'g', 'g', 'c:جملة', 'ك', 'ل'],
    ['غ', 'c:فعل', 'ف', 'ع', 'ل', 'g'],
    ['ة', 'g', 'c:حرف', 'g', 'م', 'ة'],
  ];
  const size = 84;
  let html = '';
  rows.forEach(r => r.forEach(cell => {
    if (cell.startsWith('c:')) html += `<div class="cc"><span>${cell.slice(2)}</span><b>←</b></div>`;
    else if (cell === 'g') html += '<div class="lc"></div>';
    else html += `<div class="lc f">${cell}</div>`;
  }));
  return { html, size, cols: 6, rows: 4 };
}

function coverHtml() {
  const W = 1640, H = 624;
  const g = miniGrid();
  return `<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8">${FONTS}<style>${BASE}
body{width:${W}px;height:${H}px}
.pattern{background-size:52px 52px;-webkit-mask-image:radial-gradient(ellipse at 50% 50%,#000 30%,transparent 80%)}
.wrap{position:absolute;inset:0}
.text{position:absolute;right:210px;top:50%;transform:translateY(-50%);display:flex;flex-direction:column;align-items:flex-start;gap:4px;white-space:nowrap}
.title{font-family:Amiri,serif;font-weight:700;font-size:150px;line-height:1.15;color:#7A1D1D;text-shadow:0 4px 0 rgba(255,255,255,.9),0 14px 30px rgba(122,29,29,.12)}
.sub{font-size:38px;font-weight:700;color:#5C3F30;margin-top:-6px}
.sub2{font-size:27px;font-weight:600;color:#8C6E58}
.pill{display:inline-flex;align-items:center;gap:14px;margin-top:18px;padding:10px 26px;border-radius:999px;background:#FFFFFF;border:1.5px solid rgba(122,29,29,.18);box-shadow:0 10px 24px -14px rgba(28,14,7,.35);font-size:28px;font-weight:700;color:#7A1D1D}
.pill i{width:40px;height:40px;border-radius:11px;background:radial-gradient(circle at 30% 25%,#A83232,#7A1D1D 55%,#4F0E0E);color:#F5E6D3;font-family:Amiri,serif;font-size:28px;display:flex;align-items:center;justify-content:center}
.pill i span{transform:translateY(-2px)}
.board{position:absolute;left:250px;top:50%;transform:translateY(-50%) rotate(-3deg);padding:8px;background:#7A1D1D;border-radius:14px;box-shadow:0 30px 50px -24px rgba(28,14,7,.5)}
.grid{display:grid;grid-template-columns:repeat(${g.cols},${g.size}px);grid-auto-rows:${g.size}px;gap:0;direction:rtl}
.lc,.cc{border:1.5px solid #8C6E58;display:flex;align-items:center;justify-content:center;position:relative}
.lc{background:#FFFDF9;font-family:Amiri,serif;font-weight:700;font-size:48px;color:#7A1D1D}
.cc{background:#EAD6BE;flex-direction:column;padding-bottom:14px;font-size:24px;font-weight:700;color:#1C0E07;line-height:1.1}
.cc b{position:absolute;left:2px;bottom:2px;color:#7A1D1D;font-size:22px;font-weight:800;line-height:1}
.lc.f{animation:none}
.deco{position:absolute;width:420px;height:420px;border-radius:50%;border:2px solid rgba(201,160,80,.35)}
.deco.a{right:-140px;top:-200px}.deco.b{left:-160px;bottom:-230px;border-color:rgba(122,29,29,.12)}
</style></head><body><div class="bg"></div><div class="pattern"></div><div class="deco a"></div><div class="deco b"></div>
<div class="wrap">
  <div class="text">
    <div class="title">الإعراب</div>
    <div class="sub">قواعد اللغة العربية بأسلوب مبسّط</div>
    <div class="sub2">وكلمات مسهمة جديدة كل يوم · حلّوها في التعليقات</div>
    <div class="pill"><i><span>ش</span></i><span>من تطبيق شبكة</span></div>
  </div>
  <div class="board"><div class="grid">${g.html}</div></div>
</div>
</body></html>`;
}

(async () => {
  const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || '/opt/pw-browsers/chromium' });
  const jobs = [['profile.png', profileHtml(), 1024, 1024], ['cover.png', coverHtml(), 1640, 624]];
  for (const [name, html, w, h] of jobs) {
    const page = await browser.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: 1 });
    await page.setContent(html, { waitUntil: 'networkidle' });
    await page.evaluate(() => document.fonts.ready);
    const out = path.join(outDir, name);
    await page.screenshot({ path: out });
    console.log('→', out);
    await page.close();
  }
  await browser.close();
})();
