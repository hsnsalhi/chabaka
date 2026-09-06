// Rendu de l'icône et du logo de lancement avec Chromium (Playwright).
// Usage : NODE_PATH=$(npm root -g) node tools/branding/render.js
const { chromium } = require('playwright');
const path = require('path');
(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ deviceScaleFactor: 1 });
  const out = path.join(__dirname, 'out');
  require('fs').mkdirSync(out, { recursive: true });

  await page.setViewportSize({ width: 1024, height: 1024 });
  await page.goto('file://' + path.join(__dirname, 'icon.html'));
  await page.evaluate(() => document.fonts.ready);
  await page.locator('#icon').screenshot({ path: path.join(out, 'icon_1024.png') });

  await page.setViewportSize({ width: 480, height: 480 });
  await page.goto('file://' + path.join(__dirname, 'logo.html'));
  await page.evaluate(() => document.fonts.ready);
  await page.locator('#logo').screenshot({ path: path.join(out, 'logo_480.png'), omitBackground: true });
  await page.setViewportSize({ width: 1024, height: 1024 });
  await page.goto('file://' + path.join(__dirname, 'adaptive_fg.html'));
  await page.evaluate(() => document.fonts.ready);
  await page.locator('#fg').screenshot({ path: path.join(out, 'adaptive_fg_1024.png'), omitBackground: true });
  await browser.close();
  console.log('ok');
})();
