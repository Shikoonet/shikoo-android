// شیکو — عکسِ همهٔ قاب‌ها، و چند سنجش خودکار روی همان صفحه‌ها.
// اجرا از ریشهٔ مخزن:   node design/export-shots.mjs
// نیاز: کروم نصب‌شده، و playwright-core: از متغیر PLAYWRIGHT_CORE، یا نصبِ معمولیِ npm،
//       یا تازه‌ترین نسخه در کشِ npx کاربرِ فعلی (همان که افزونهٔ Playwright گذاشته).
//
// خروجی:
//   design/shots/<صفحه>-<تم>.png                 کل صفحه، چگالی ۱
//   design/shots/frames/<قاب>-<تم>.png             هر قاب، چگالی ۲: گوشی ۸۲۴×۱۸۳۰، تلویزیون ۱۹۲۰×۱۰۸۰
//   design/shots/frames/<قاب>-1280dp-light.png     قاب‌های تلویزیون در ۱۲۸۰×۷۲۰ dp با چگالی ۱٫۵ (باکس ۲۴۰dpi)
//
// سنجش‌ها (اگر یکی رد شود، کد خروج ۱ است):
//   - فونت: برای هر وزن ۴۰۰، ۵۰۰، ۷۰۰ و ۸۰۰، تکهٔ عربیِ Vazirmatn باید status === 'loaded' باشد.
//   - متنِ بریده (از پهلو، یا یک‌خطیِ سه‌نقطه‌دار از بالا و پایین) یا جزئی که از قاب بیرون زده.
//   - متنِ تلویزیون کوچک‌تر از --text-caption (۱۲dp).
//   - جزئی از قاب تلویزیون، با حلقهٔ فوکوسش، بیرون از حاشیهٔ امن (--safe-x، --safe-y). ستونِ اسکرول‌شونده و پردهٔ پشت پنجره سنجیده نمی‌شوند.
//   - حرف لاتین در لایهٔ ارائه (سربرگ، زیرنویس، یادداشت).
//   - اندازهٔ هر عکسِ قاب.
import { createServer } from 'node:http';
import { existsSync, readdirSync, statSync } from 'node:fs';
import { mkdir, readFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { createRequire } from 'node:module';
import { dirname, extname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = dirname(fileURLToPath(import.meta.url));
const SHOTS = join(ROOT, 'shots');
const FRAMES = join(SHOTS, 'frames');
const require = createRequire(import.meta.url);
const { chromium } = require(findPlaywright());

function findPlaywright() {
  if (process.env.PLAYWRIGHT_CORE) return process.env.PLAYWRIGHT_CORE;
  try {
    return require.resolve('playwright-core');
  } catch {}
  const caches = [process.env.LOCALAPPDATA && join(process.env.LOCALAPPDATA, 'npm-cache', '_npx'), join(homedir(), '.npm', '_npx')];
  const found = [];
  for (const cache of caches.filter(Boolean)) {
    if (!existsSync(cache)) continue;
    for (const entry of readdirSync(cache)) {
      const pkg = join(cache, entry, 'node_modules', 'playwright-core');
      if (existsSync(join(pkg, 'package.json'))) found.push({ pkg, time: statSync(pkg).mtimeMs });
    }
  }
  if (!found.length) throw new Error('playwright-core پیدا نشد؛ مسیرش را در متغیر PLAYWRIGHT_CORE بگذار.');
  return found.sort((a, b) => b.time - a.time)[0].pkg;
}

// سرور کوچکِ همین پوشه، چون Playwright نشانی file:// را باز نمی‌کند.
const TYPES = { '.html': 'text/html; charset=utf-8', '.css': 'text/css', '.js': 'text/javascript' };
const server = createServer(async (req, res) => {
  const file = normalize(join(ROOT, decodeURIComponent(new URL(req.url, 'http://x').pathname)));
  try {
    if (!file.startsWith(ROOT)) throw new Error('بیرون از پوشه');
    const body = await readFile(file);
    res.writeHead(200, { 'content-type': TYPES[extname(file)] ?? 'application/octet-stream' }).end(body);
  } catch {
    res.writeHead(404).end();
  }
});
await new Promise((done) => server.listen(0, '127.0.0.1', done));
const BASE = `http://127.0.0.1:${server.address().port}/mockups/`;

const PAGES = [
  { name: 'phone', width: 2300 },
  { name: 'phone-states', width: 2300 },
  { name: 'phone-ping', width: 2300 },
  { name: 'tv', width: 2040 },
  { name: 'tv-states', width: 2040 },
  { name: 'tv-ping', width: 2040 },
];
const WEIGHTS = ['400', '500', '700', '800'];
const problems = [];
const written = [];
const tallFrames = new Set();
const browser = await chromium.launch({ channel: 'chrome' });
await mkdir(FRAMES, { recursive: true });

async function open(page, query, scale, width = page.width) {
  const context = await browser.newContext({ deviceScaleFactor: scale, viewport: { width, height: 1000 } });
  const tab = await context.newPage();
  await tab.goto(`${BASE}${page.name}.html?${query}`, { waitUntil: 'networkidle' });
  await tab.evaluate(() => document.fonts.ready);
  return { context, tab };
}

async function checkFonts(tab, label) {
  const faces = await tab.evaluate(() =>
    [...document.fonts]
      .filter((f) => f.family.replaceAll('"', '') === 'Vazirmatn')
      .map((f) => ({ weight: String(f.weight), arabic: /U\+0*6[0-9A-F]{2}\b/i.test(f.unicodeRange), status: f.status })),
  );
  const cells = WEIGHTS.map((w) => {
    const face = faces.find((f) => f.weight === w && f.arabic);
    if (face?.status !== 'loaded') problems.push(`${label}: تکهٔ عربیِ وزن ${w} بار نشده`);
    return `${w}=${face?.status ?? 'نیست'}`;
  });
  console.log(`فونت ${label}: ${cells.join(' ')} · ${faces.filter((f) => f.status === 'loaded').length} از ${faces.length} تکه بار شده`);
}

async function checkText(tab, label) {
  const found = await tab.evaluate(() => {
    const out = [];
    for (const frame of document.querySelectorAll('[data-frame]')) {
      const box = frame.getBoundingClientRect();
      for (const el of frame.querySelectorAll('*')) {
        if (el.closest('svg')) continue;
        const r = el.getBoundingClientRect();
        if (!r.width) continue;
        const style = getComputedStyle(el);
        const clipped = el.scrollWidth > el.clientWidth + 1 && style.overflowX !== 'visible';
        const cutTall = style.textOverflow === 'ellipsis' && el.scrollHeight > el.clientHeight;
        const outside = r.left < box.left - 1 || r.right > box.right + 1;
        const tiny = frame.dataset.device === 'tv' && el.childNodes[0]?.nodeType === 3 && el.textContent.trim() &&
          parseFloat(style.fontSize) < parseFloat(getComputedStyle(frame).getPropertyValue('--text-caption'));
        if (clipped || cutTall || outside || tiny)
          out.push(`${frame.dataset.frame}: «${el.textContent.trim().slice(0, 30)}» ${clipped ? 'بریده شده' : cutTall ? 'از بالا یا پایین بریده' : outside ? 'بیرون از قاب' : `متن ${style.fontSize} کوچک‌تر از ۱۲dp`}`);
        if (frame.dataset.device === 'tv' && !el.closest('.tv-col') && !el.classList.contains('scrim')) {
          const fs = getComputedStyle(frame);
          const sx = parseFloat(fs.paddingLeft), sy = parseFloat(fs.paddingTop);
          const ring = el.classList.contains('is-focused') ? parseFloat(style.outlineWidth) + parseFloat(style.outlineOffset) : 0;
          const over = Math.max(box.top + sy - (r.top - ring), (r.bottom + ring) - (box.bottom - sy), box.left + sx - (r.left - ring), (r.right + ring) - (box.right - sx));
          if (over > 0.5) out.push(`${frame.dataset.frame}: «${el.textContent.trim().slice(0, 30) || el.className}» ${over.toFixed(1)}dp بیرون از حاشیهٔ امن`);
        }
      }
    }
    for (const el of document.querySelectorAll('.sheet-head, figcaption, .note, .fold'))
      if (/[A-Za-z]/.test(el.textContent)) out.push(`حرف لاتین در لایهٔ ارائه: «${el.textContent.trim().slice(0, 40)}»`);
    return out;
  });
  for (const line of found) problems.push(`${label}: ${line}`);
}

async function tvTextSizes(tab) {
  return tab.evaluate(() => {
    const sizes = {};
    for (const el of document.querySelectorAll('[data-device="tv"] *')) {
      if (el.closest('svg') || !el.textContent.trim() || ![...el.childNodes].some((n) => n.nodeType === 3 && n.textContent.trim())) continue;
      const fs = getComputedStyle(el).fontSize;
      sizes[fs] = (sizes[fs] ?? 0) + 1;
    }
    return Object.entries(sizes).sort((a, b) => parseFloat(a[0]) - parseFloat(b[0]));
  });
}

async function shootFrames(tab, suffix) {
  for (const el of await tab.$$('[data-frame]')) {
    const file = join(FRAMES, `${await el.getAttribute('data-frame')}-${suffix}.png`);
    // قابی که جایش کسری است، عکسی یک پیکسل پهن‌تر می‌دهد.
    const tall = await el.evaluate((n) => {
      const r = n.getBoundingClientRect();
      n.style.translate = `${Math.round(r.x) - r.x}px ${Math.round(r.y) - r.y}px`;
      return n.classList.contains('tall');
    });
    if (tall) tallFrames.add(file);
    await el.screenshot({ path: file });
    written.push(file);
  }
}

for (const theme of ['light', 'dark']) {
  for (const page of PAGES) {
    const whole = await open(page, `theme=${theme}`, 1);
    await checkFonts(whole.tab, `${page.name}/${theme}`);
    await checkText(whole.tab, `${page.name}/${theme}`);
    await whole.tab.screenshot({ path: join(SHOTS, `${page.name}-${theme}.png`), fullPage: true });
    await whole.context.close();

    const frames = await open(page, `theme=${theme}`, 2);
    if (page.name === 'tv' && theme === 'light') {
      const ring = await frames.tab.evaluate(() => getComputedStyle(document.querySelector('.tv .is-focused')).outlineWidth);
      console.log(`حلقهٔ فوکوس تلویزیون: ${ring} در CSS (= dp)، یعنی ${parseFloat(ring) * 2} پیکسل در عکس با چگالی ۲`);
      const sizes = await tvTextSizes(frames.tab);
      console.log(`اندازه‌های متن تلویزیون (dp × تعداد): ${sizes.map(([s, n]) => `${s}×${n}`).join(' ')}`);
      console.log(`همان‌ها روی ۱۰۸۰p: با ۳۲۰dpi ${sizes.map(([s]) => parseFloat(s) * 2).join('، ')} پیکسل · با ۲۴۰dpi ${sizes.map(([s]) => parseFloat(s) * 1.5).join('، ')} پیکسل`);
    }
    await shootFrames(frames.tab, theme);
    await frames.context.close();
  }
}

// تلویزیون در ۱۲۸۰×۷۲۰ dp: چگالی ۱٫۵ تا عکس باز ۱۹۲۰×۱۰۸۰ شود. فقط تم روشن، چون چگالی به تم ربطی ندارد.
for (const page of PAGES.filter((p) => p.name.startsWith('tv'))) {
  const dense = await open(page, 'theme=light&tvdp=1280', 1.5, 2800);
  await checkText(dense.tab, `${page.name}/1280dp`);
  await shootFrames(dense.tab, '1280dp-light');
  await dense.context.close();
}

await browser.close();
server.close();

// اندازهٔ هر عکس از سربرگِ خودِ فایل PNG.
const sizes = {};
for (const file of written) {
  const head = await readFile(file);
  const size = `${head.readUInt32BE(16)}×${head.readUInt32BE(20)}`;
  const name = file.slice(FRAMES.length + 1);
  (sizes[size] ??= []).push(name);
  const fixed = name.startsWith('tv-') ? '1920×1080' : tallFrames.has(file) || name.startsWith('phone-cards') ? null : name.startsWith('phone-small') ? '686×1524' : '824×1830';
  if (fixed && size !== fixed) problems.push(`${name}: ${size} به‌جای ${fixed}`);
}
for (const [size, names] of Object.entries(sizes)) console.log(`${size}: ${names.length} عکس`);
console.log(`جمعاً ${written.length} عکسِ قاب و ${PAGES.length * 2} عکسِ کل صفحه.`);

if (problems.length) {
  console.log(`\nمشکل‌ها (${problems.length}):\n${problems.join('\n')}`);
  process.exitCode = 1;
} else {
  console.log('\nهیچ مشکلی پیدا نشد.');
}
