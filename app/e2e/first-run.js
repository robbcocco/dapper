// First run: setup → demo server → library browsing, search, star + rating.
const main = 'main.main';
const nav = (label) => click('nav.sidebar button.tile', { text: label, settle: 600 });
const imgsLoaded = (root) => all(`${root} .cover img`).filter((i) => i.complete && i.naturalWidth > 0).length;

await step('setup screen', async () => {
  await waitFor('form.card', { text: 'Connect to Navidrome', timeout: 20000 });
  await click('button[type=submit]', { text: 'Connect' });
  await waitFor('form.card .error', { text: 'Required' });
  await shot('00-setup-validation');
});

await step('bad password shows error', async () => {
  // Scheme-less input is rejected client-side (Flutter `Uri.hasScheme` validator).
  await type(await field('Server URL'), 'demo.navidrome.org');
  await click('button[type=submit]', { text: 'Connect' });
  await waitFor('form.card .error', { text: 'Enter a valid URL' });
  await type(await field('Server URL'), 'https://demo.navidrome.org');
  await type(await field('Username'), 'demo');
  await type(await field('Password'), 'wrong');
  await click('button[type=submit]', { text: 'Connect' });
  const banner = await waitFor('form.card [role=alert], form.card .banner', { timeout: 20000 });
  log(`error banner: ${textOf(banner)}`);
  await shot('01-setup-error');
});

await step('connect demo server', async () => {
  await type(await field('Password'), 'demo');
  await click('button[type=submit]', { text: 'Connect' });
  await waitFor('nav.sidebar', { timeout: 30000 });
  await shot('02-shell-syncing');
  const s = await waitForSync();
  log(`sync: ${JSON.stringify(s)}`);
});

await step('sync status visible', async () => {
  const el = await waitFor('nav.sidebar .sync-status');
  log(`sync status: ${textOf(el)}`);
  assert(/synced/i.test(textOf(el)), 'idle sync status says Synced');
});

await step('recently added covers', async () => {
  await nav('Recently Added');
  await waitFor(`${main} button.card`, { timeout: 20000 });
  await until(() => imgsLoaded(main) >= 8, 'cover images loaded', 20000);
  log(`recent cards=${all(`${main} button.card`).length} covers=${imgsLoaded(main)}`);
  await shot('03-recently-added');
});

await step('albums grid scroll + sort', async () => {
  await nav('Albums');
  const head = await waitFor(`${main} .head .count`, { timeout: 15000 });
  log(`albums: ${textOf(head)}`);
  assert(/\d+ albums/.test(textOf(head)), 'album count');
  const first = textOf(await waitFor(`${main} button.card .name`));
  await choose(`${main} .sort select`, 'Year');
  await until(() => textOf(find(`${main} button.card .name`) ?? document.body) !== first, 'sort changed first album', 10000);
  log(`first by name=${first}, by year=${textOf(find(`${main} button.card .name`))}`);
  const vg = find(`${main} .vg`);
  vg.scrollTop = vg.scrollHeight;
  await sleep(1200);
  await until(() => imgsLoaded(main) >= 4, 'covers after scroll');
  await shot('04-albums-scrolled');
  await choose(`${main} .sort select`, 'Name');
  vg.scrollTop = 0;
  await sleep(500);
});

await step('album detail', async () => {
  await click(`${main} button.card`, { settle: 800 });
  await waitFor(`${main} .detail h1`);
  const rows = await until(() => all(`${main} .detail .row`).length || null, 'album songs');
  log(`album ${textOf(find(`${main} .detail h1`))}: ${rows} rows`);
  await shot('05-album-detail');
  await click(`${main} button[aria-label=Back]`);
  await waitFor(`${main} .detail h1`, { gone: true });
});

await step('artists list + detail', async () => {
  await nav('Artists');
  await waitFor(`${main} .list button.tile`, { timeout: 15000 });
  await click(`${main} .list button.tile`, { text: 'Nine Inch Nails', settle: 800 });
  await waitFor(`${main} .panel h1`, { text: 'Nine Inch Nails', timeout: 15000 });
  await until(() => all(`${main} .panel .album`).length || null, 'artist albums');
  log(`artist albums: ${all(`${main} .panel .album`).map(textOf).join(' | ')}`);
  await shot('06-artist-detail');
  await click(`${main} .panel .album`, { settle: 800 });
  await waitFor(`${main} .detail h1`);
  await click(`${main} button[aria-label=Back]`);
});

await step('songs table scroll + sort', async () => {
  await nav('Songs');
  await waitFor(`${main} .row .title`, { timeout: 15000 });
  const vl = find(`${main} .body [class*=vl], ${main} .body > div > div`);
  const scroller = [...document.querySelectorAll(`${main} .body *`)].find((e) => e.scrollHeight > e.clientHeight + 100);
  assert(scroller, 'songs scroller');
  scroller.scrollTop = scroller.scrollHeight;
  await sleep(1500);
  await until(() => all(`${main} .row .title`).length > 5 && !find(`${main} .row .skeleton`), 'last rows loaded');
  const lastNums = all(`${main} .row`).slice(-3).map(textOf);
  log(`bottom rows: ${lastNums.join(' || ')} vl=${!!vl}`);
  await shot('07-songs-bottom');
  scroller.scrollTop = 0;
  await sleep(500);
  await click(`${main} .cols button.col`, { text: 'Time' });
  await click(`${main} .cols button.col`, { text: 'Time', settle: 1200 });
  await until(() => find(`${main} .row .time`), 'rows after sort');
  const t = all(`${main} .row .time`).slice(0, 3).map(textOf);
  log(`longest first: ${t.join(', ')}`);
  const secs = (s) => s.split(':').reduce((a, b) => a * 60 + Number(b), 0);
  assert(secs(t[0]) >= secs(t[1]) && secs(t[1]) >= secs(t[2]), 'duration desc');
  await shot('08-songs-sorted-time-desc');
});

await step('star + rating', async () => {
  const row = await waitFor(`${main} .row`, { text: /\d/ });
  const title = textOf(row.querySelector('.title'));
  const before = row.querySelector('button.star').getAttribute('aria-label');
  const ids0 = new Set(await invoke('starred_ids'));
  await click(row.querySelector('button.star'), { settle: 1000 });
  const ids1 = new Set(await invoke('starred_ids'));
  const added = [...ids1].filter((i) => !ids0.has(i));
  const removed = [...ids0].filter((i) => !ids1.has(i));
  log(`toggled star on ${title} (${before}) → added=${added} removed=${removed}`);
  assert((before === 'Star' ? added : removed).length === 1, 'star persisted in library cache');
  const after = (await waitFor(`${main} .row`, { text: title })).querySelector('button.star').getAttribute('aria-label');
  assert(after !== before, 'star icon flipped');
  const current = () => Number(/Rating (\d)/.exec((find(`${main} [role=row]`, { text: title }) ?? document.body).querySelector('.rs')?.getAttribute('aria-label') ?? '')?.[1]);
  const was = current();
  const target = was === 3 ? 4 : 3;
  await click((await waitFor(`${main} [role=row]`, { text: title })).querySelector(`button[aria-label="${target} stars"]`), { settle: 1200 });
  log(`rating ${was} → ${current()}`);
  assert(current() === target, `rating ${target}`);
  const starNow = (await waitFor(`${main} [role=row]`, { text: title })).querySelector('button.star').getAttribute('aria-label');
  log(`star label after rating: ${starNow}`);
  assert(starNow === after, 'star state survives the rating change');
  await shot('09-star-rating');
  // Restore so the shared demo server stays tidy.
  await click((await waitFor(`${main} [role=row]`, { text: title })).querySelector('button.star'), { settle: 800 });
  await click((await waitFor(`${main} [role=row]`, { text: title })).querySelector(`button[aria-label="${was || target} star${(was || target) > 1 ? 's' : ''}"]`), { settle: 800 });
  log(`restored rating → ${current()}`);
});

await step('genres', async () => {
  await nav('Genres');
  await waitFor(`${main} button.genre`, { timeout: 15000 });
  log(`genres: ${all(`${main} button.genre .name`).slice(0, 5).map(textOf).join(', ')}`);
  await click(`${main} button.genre`, { settle: 800 });
  await waitFor(`${main} .panel h1`);
  await until(() => imgsLoaded(main) > 0, 'genre album covers');
  await shot('10-genre-albums');
  await click(`${main} button[aria-label="All Genres"]`);
  await waitFor(`${main} button.genre`);
});

await step('search + Esc clears', async () => {
  const input = await waitFor('nav.sidebar .search input');
  await type(input, 'nine');
  await waitFor(`${main} .section`, { timeout: 10000 });
  log(`search sections: ${all(`${main} .section`).map(textOf).join(', ')}; items=${all(`${main} .item, ${main} .row`).length}`);
  await shot('11-search');
  await key('Escape', { target: input });
  await until(() => input.value === '' && !find(`${main} .section`), 'search cleared');
  await waitFor(`${main} button.genre`);
});
