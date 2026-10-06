// مشترکِ همهٔ صفحه‌های ماکاپ: تم، چگالی تلویزیون، آیکون‌ها و QR ساختگی.
// ?theme=dark|light  تم را اجبار می‌کند (بدون آن، مثل سیستم).
// ?tvdp=1280          قاب تلویزیون را ۱۲۸۰×۷۲۰ dp می‌کند (باکس ۲۴۰dpi).

const query = new URLSearchParams(location.search);
const rootEl = document.documentElement;
if (['light', 'dark'].includes(query.get('theme'))) rootEl.dataset.theme = query.get('theme');
if (query.get('tvdp') === '1280') rootEl.dataset.tvdp = '1280';

function toggleTheme() {
  const dark = rootEl.dataset.theme ? rootEl.dataset.theme === 'dark' : matchMedia('(prefers-color-scheme: dark)').matches;
  rootEl.dataset.theme = dark ? 'light' : 'dark';
}

// آیکون‌ها با خط (stroke) کشیده شده‌اند و رنگ و ضخامت را از CSS می‌گیرند؛ پرچم‌ها رنگ خودشان را دارند.
const SPRITE = `<svg width="0" height="0" style="position:absolute" aria-hidden="true">
<symbol id="i-power" viewBox="0 0 24 24"><path d="M12 3.5v8"/><path d="M6.7 6.8a7.5 7.5 0 1 0 10.6 0"/></symbol>
<symbol id="i-gear" viewBox="0 0 24 24"><path d="M9.96 4.89L10.5 2.52h3l.54 2.37 1.55.64 2.05-1.3 2.13 2.13-1.3 2.05.64 1.55 2.37.54v3l-2.37.54-.64 1.55 1.3 2.05-2.13 2.13-2.05-1.3-1.55.64-.54 2.37h-3l-.54-2.37-1.55-.64-2.05 1.3-2.13-2.13 1.3-2.05-.64-1.55-2.37-.54v-3l2.37-.54.64-1.55-1.3-2.05 2.13-2.13 2.05 1.3z"/><circle cx="12" cy="12" r="3"/></symbol>
<symbol id="i-chevron-up" viewBox="0 0 24 24"><path d="M6 15l6-6 6 6"/></symbol>
<symbol id="i-chevron-down" viewBox="0 0 24 24"><path d="M6 9l6 6 6-6"/></symbol>
<symbol id="i-chevron-fwd" viewBox="0 0 24 24"><path d="M15 6l-6 6 6 6"/></symbol>
<symbol id="i-back" viewBox="0 0 24 24"><path d="M5 12h14"/><path d="M13 6l6 6-6 6"/></symbol>
<symbol id="i-check" viewBox="0 0 24 24"><path d="M5 12.5l4.5 4.5L19 7.5"/></symbol>
<symbol id="i-x" viewBox="0 0 24 24"><path d="M6.5 6.5l11 11"/><path d="M17.5 6.5l-11 11"/></symbol>
<symbol id="i-alert" viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="M12 7.5v5.5"/><path d="M12 16.4v.2"/></symbol>
<symbol id="i-refresh" viewBox="0 0 24 24"><path d="M19.5 12a7.5 7.5 0 1 1-2.2-5.3"/><path d="M19.5 4.5v4h-4"/></symbol>
<symbol id="i-gauge" viewBox="0 0 24 24"><path d="M5.99 19.01A8.5 8.5 0 1 1 18.01 19.01"/><path d="M12 13l4-4"/></symbol>
<symbol id="i-search" viewBox="0 0 24 24"><circle cx="10.5" cy="10.5" r="6.5"/><path d="M15.5 15.5l5 5"/></symbol>
<symbol id="i-spin" viewBox="0 0 24 24"><path d="M12 3.5a8.5 8.5 0 1 1-8.5 8.5"/></symbol>
<symbol id="i-plane"viewBox="0 0 24 24"><path d="M21 3.5L3 10.8l6.8 2.6L12.5 20.5z"/><path d="M9.8 13.4L21 3.5"/></symbol>
<symbol id="i-bell" viewBox="0 0 24 24"><path d="M6 16v-5a6 6 0 0 1 12 0v5l1.5 2h-15z"/><path d="M10 20.5a2 2 0 0 0 4 0"/></symbol>
<symbol id="i-logout" viewBox="0 0 24 24"><path d="M14 4h4a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2h-4"/><path d="M9 8l-4 4 4 4"/><path d="M5 12h10"/></symbol>
<symbol id="i-qr" viewBox="0 0 24 24"><rect x="3.5" y="3.5" width="6" height="6" rx="1"/><rect x="14.5" y="3.5" width="6" height="6" rx="1"/><rect x="3.5" y="14.5" width="6" height="6" rx="1"/><path d="M14.5 14.5h2.5v2.5"/><path d="M20.5 14.5v.5"/><path d="M14.5 20.5h6v-2"/></symbol>
<symbol id="i-download" viewBox="0 0 24 24"><path d="M12 4v11"/><path d="M7 10.5l5 5 5-5"/><path d="M5 20h14"/></symbol>
<symbol id="i-paste" viewBox="0 0 24 24"><rect x="5" y="4.5" width="14" height="17" rx="2"/><rect x="9" y="2.5" width="6" height="4" rx="1"/><path d="M9 12h6"/><path d="M9 16h4"/></symbol>
<symbol id="i-phone" viewBox="0 0 24 24"><rect x="7" y="2.5" width="10" height="19" rx="2.5"/><path d="M11 18.5h2"/></symbol>
<symbol id="f-de" viewBox="0 0 30 20"><rect width="30" height="20" fill="#FFCE00"/><rect width="30" height="13.34" fill="#DD0000"/><rect width="30" height="6.67" fill="#000"/></symbol>
<symbol id="f-nl" viewBox="0 0 30 20"><rect width="30" height="20" fill="#21468B"/><rect width="30" height="13.34" fill="#FFF"/><rect width="30" height="6.67" fill="#AE1C28"/></symbol>
<symbol id="f-fi" viewBox="0 0 30 20"><rect width="30" height="20" fill="#FFF"/><rect x="8" width="5.6" height="20" fill="#002F6C"/><rect y="7.2" width="30" height="5.6" fill="#002F6C"/></symbol>
<symbol id="f-us" viewBox="0 0 30 20"><rect width="30" height="20" fill="#B22234"/><path d="M0 2.31h30M0 5.38h30M0 8.46h30M0 11.54h30M0 14.62h30M0 17.69h30" stroke="#FFF" stroke-width="1.54"/><rect width="13" height="10.77" fill="#3C3B6E"/><g fill="#FFF"><circle cx="2" cy="2" r=".7"/><circle cx="5" cy="2" r=".7"/><circle cx="8" cy="2" r=".7"/><circle cx="11" cy="2" r=".7"/><circle cx="3.5" cy="5.4" r=".7"/><circle cx="6.5" cy="5.4" r=".7"/><circle cx="9.5" cy="5.4" r=".7"/><circle cx="2" cy="8.8" r=".7"/><circle cx="5" cy="8.8" r=".7"/><circle cx="8" cy="8.8" r=".7"/><circle cx="11" cy="8.8" r=".7"/></g></symbol>
<symbol id="f-gb" viewBox="0 0 30 20"><rect width="30" height="20" fill="#012169"/><path d="M0 0l30 20M30 0L0 20" stroke="#FFF" stroke-width="4"/><path d="M0 0l30 20M30 0L0 20" stroke="#C8102E" stroke-width="1.5"/><path d="M15 0v20M0 10h30" stroke="#FFF" stroke-width="6"/><path d="M15 0v20M0 10h30" stroke="#C8102E" stroke-width="3.5"/></symbol>
<symbol id="sb" viewBox="0 0 44 14"><path d="M1 13L13 1v12z"/><rect x="21" y="2" width="20" height="10" rx="2.5" fill="none" stroke="currentColor" stroke-width="1.4"/><rect x="23" y="4" width="13" height="6" rx="1"/><rect x="42" y="5" width="1.6" height="4" rx=".8"/></symbol>
</svg>`;

// QR ساختگی: الگوی ثابت با سه مربع گوشه. هیچ چیزی رمز نمی‌کند. data-seed الگوها را از هم جدا می‌کند.
function drawQr(svg) {
  const n = 29;
  let seed = Number(svg.dataset.seed || 20261002);
  const rand = () => (seed = (seed * 48271) % 2147483647) / 2147483647;
  const nearFinder = (x, y) => (x < 8 && y < 8) || (x > n - 9 && y < 8) || (x < 8 && y > n - 9);
  let d = '';
  for (let y = 0; y < n; y++)
    for (let x = 0; x < n; x++)
      if (!nearFinder(x, y) && rand() < 0.48) d += `M${x} ${y}h1v1h-1z`;
  const finder = (x, y) => `M${x} ${y}h7v7h-7zM${x + 1} ${y + 1}v5h5v-5zM${x + 2} ${y + 2}h3v3h-3z`;
  d += finder(0, 0) + finder(n - 7, 0) + finder(0, n - 7);
  svg.setAttribute('viewBox', `0 0 ${n} ${n}`);
  svg.innerHTML = `<path fill-rule="evenodd" d="${d}"/>`;
}

// قاب اسکرول‌شده: data-scroll-to روی ظرفِ اسکرول جزئی را نام می‌برد که باید بالای دید بیاید
// (با scroll-margin-top خودش)، ولی نه جلوتر از ته محتوا. بعد از رسیدن فونت دوباره حساب می‌شود.
function mockScroll(view) {
  const content = view.firstElementChild;
  const target = content.querySelector(view.dataset.scrollTo);
  const pad = parseFloat(getComputedStyle(view).paddingTop) + parseFloat(getComputedStyle(view).paddingBottom);
  const seen = view.clientHeight - pad;
  const want = target.getBoundingClientRect().top - content.getBoundingClientRect().top - parseFloat(getComputedStyle(target).scrollMarginTop);
  const y = Math.max(0, Math.min(want, content.offsetHeight - seen));
  content.style.setProperty('--scroll', `${y}px`);
  view.classList.toggle('is-scrolled', y > 0);
  const thumb = view.querySelector('.scroll-thumb');
  if (thumb) Object.assign(thumb.style, { top: `${pad / 2 + (y * seen) / content.offsetHeight}px`, blockSize: `${(seen * seen) / content.offsetHeight}px` });
}
const scrollAll = () => document.querySelectorAll('[data-scroll-to]').forEach(mockScroll);

document.addEventListener('DOMContentLoaded', () => {
  document.body.insertAdjacentHTML('afterbegin', SPRITE);
  document.querySelectorAll('svg.qr').forEach(drawQr);
});
window.addEventListener('load', () => document.fonts.ready.then(scrollAll));
document.fonts.addEventListener('loadingdone', scrollAll);
