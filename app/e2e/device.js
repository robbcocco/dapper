// Device: own FAT32 image → sidebar + auto-select, settings dialog, album (zip) + playlist
// transfer, popup progress, sync dots, queue tab, scan (+ prune/clean), file browser, eject.
const main = 'main.main';
const VOL = '/Volumes/DAPE2E';
const IMG = '/tmp/dape2e.dmg';
const deviceTile = () => find('nav.sidebar .tile.device', { text: 'DAPE2E' });
let playlistId = null;

const run = async (cmd) => {
  const r = await sh(cmd);
  log(`$ ${cmd} → ${r.code}${r.out.trim() ? `\n${r.out.trim()}` : ''}`);
  return r;
};

await step('connect', connectDemo);

await step('attach FAT32 image → sidebar + auto-select', async () => {
  await run(`hdiutil detach ${VOL} -force >/dev/null 2>&1; rm -f ${IMG}`);
  assert((await run(`hdiutil create -size 200m -fs MS-DOS -volname DAPE2E ${IMG}`)).code === 0, 'hdiutil create');
  assert((await run(`hdiutil attach ${IMG}`)).code === 0, 'hdiutil attach');
  await until(() => deviceTile(), 'DAPE2E in sidebar', 20000);
  const list = await invoke('devices_list');
  log(`devices: ${list.map((d) => `${d.label}@${d.path}`).join(', ')}`);
  await click(deviceTile().querySelector('.device-main'), { settle: 1000 });
  await waitFor(`${main} .header .label`, { text: 'DAPE2E' });
  await waitFor(`${main} .capacity`, { text: 'available of' });
  await shot('01-device-page');
});

await step('device settings dialog preview', async () => {
  await click(`${main} button[aria-label="Device settings"]`);
  await waitFor('[role=dialog] .section', { text: 'FOLDER STRUCTURE', timeout: 10000 });
  const custom = all('[role=dialog] input[name=filename]').find((i) => i.value === 'custom');
  custom.click();
  await sleep(300);
  const tpl = await waitFor('[role=dialog] .custom input');
  await type(tpl, '{track:02} - {title}');
  const preview = await waitFor('[role=dialog] .custom .note');
  log(`filename preview: ${textOf(preview)}`);
  assert(/→ \d\d - /.test(textOf(preview)), 'filename preview rendered');
  await type(await waitFor('[role=dialog] input[placeholder="e.g. Music/FLAC"]'), 'Music');
  await waitFor('[role=dialog] .note', { text: '/Volumes/DAPE2E/Music', timeout: 3000 }).catch((e) => {
    const input = find('[role=dialog] input[placeholder="e.g. Music/FLAC"]');
    log(`root input value=${input?.value}; form head: ${find('[role=dialog] .form')?.innerHTML.slice(0, 1500)}`);
    throw e;
  });
  log(`previews: ${all('[role=dialog] .note').map(textOf).join(' | ')}`);
  await shot('02-device-settings');
  await click('[role=dialog] button', { text: 'Cancel' });
  await waitFor('[role=dialog]', { gone: true });
});

await step('transfer album (zip)', async () => {
  const input = await waitFor('nav.sidebar .search input');
  await type(input, 'Brighten');
  await click(`${main} button.item`, { text: 'Brighten', timeout: 10000, settle: 800 });
  await waitFor(`${main} .detail h1`, { text: 'Brighten' });
  await click(`${main} .detail button`, { text: /^Transfer$/ });
  await waitFor('.bottom-bar button[aria-label="Transfer queue"]', { timeout: 10000 });
  await click('.bottom-bar button[aria-label="Transfer queue"]');
  await waitFor('[role=dialog][aria-label="Transfer Queue"] .row', { timeout: 10000 });
  await shot('03-transfer-popup-active');
  const t0 = Date.now();
  await until(async () => {
    const tasks = await invoke('transfer_tasks');
    const failed = tasks.filter((t) => t.status === 'failed');
    if (failed.length) throw new Error(`failed: ${failed.map((t) => t.errorMessage).join('; ')}`);
    return tasks.length > 0 && tasks.every((t) => t.status === 'completed');
  }, 'album transfer completes', 180000);
  log(`album transferred in ${Date.now() - t0}ms; popup: ${textOf(find('[role=dialog][aria-label="Transfer Queue"]'))}`);
  await sleep(800);
  await shot('04-transfer-popup-done');
  await key('Escape');
  await until(async () => (await run(`find ${VOL} -name .dapper.json | head -3`)).out.includes('.dapper.json'), 'manifest on device', 10000);
});

await step('album + song sync dots full', async () => {
  await until(() => all(`${main} .detail .row .slot .dot`).length > 0, 'song dots in album detail', 15000);
  const rows = all(`${main} .detail [role=row]`).length;
  const dots = all(`${main} .detail [role=row] .slot .dot`).length;
  log(`album rows=${rows} full dots=${dots}`);
  assert(dots === rows, 'every song shows on-device dot');
  await shot('05-album-song-dots');
  await key('Escape', { target: find('nav.sidebar .search input') });
  await click('nav.sidebar button.tile', { text: 'Albums', settle: 800 });
  await choose(`${main} .sort select`, 'Artist');
  const card = await waitFor(`${main} button.card`, { text: 'Brighten', timeout: 10000 });
  await until(() => card.querySelector('.dot span, .dot .dot, .dot'), 'album card dot', 10000);
  log(`album card dot: ${card.querySelector('.dot')?.outerHTML.slice(0, 200)}`);
  await shot('06-album-card-dot');
});

await step('transfer playlist', async () => {
  const songs = (await invoke('songs_window', { offset: 0, limit: 2, sort: 'title', desc: false })).items;
  const pl = await invoke('playlist_create', { name: `E2E device ${Date.now().toString(36)}`, songIds: songs.map((s) => s.id) });
  playlistId = pl.id;
  await until(() => find('nav.sidebar button.tile.playlist', { text: pl.name }), 'playlist in sidebar', 10000);
  await click(find('nav.sidebar button.tile.playlist', { text: pl.name }), { settle: 800 });
  await click(`${main} .detail button`, { text: 'Sync Playlist', timeout: 10000 });
  await until(async () => {
    const tasks = await invoke('transfer_tasks');
    return tasks.length > 0 && tasks.every((t) => t.status === 'completed' || t.status === 'failed');
  }, 'playlist transfer completes', 120000);
  await waitFor(`${main} .on-device`, { text: 'Playlist on device', timeout: 15000 });
  const m3u = await run(`find ${VOL} -iname '*.m3u*' -print -exec cat {} \\;`);
  assert(m3u.out.includes('.m3u'), 'M3U written');
  await shot('07-playlist-on-device');
});

await step('device page queue tab', async () => {
  await click(deviceTile().querySelector('.device-main'), { settle: 800 });
  await click(`${main} .tabs button`, { text: 'Transfer Queue' });
  await waitFor(`${main} .queue .row`, { timeout: 10000 });
  log(`queue rows: ${all(`${main} .queue .row`).length}`);
  await shot('08-queue-tab');
  await click(`${main} .queue button`, { text: 'Clear finished' });
  await waitFor(`${main} .queue .row`, { gone: true, timeout: 10000 });
  await click(`${main} .tabs button`, { text: 'On Device' });
});

await step('file browser', async () => {
  await waitFor(`${main} .browser .dir`, { timeout: 10000 });
  log(`top level: ${all(`${main} .browser .dir .dir-name`).map(textOf).join(', ')}`);
  await click(`${main} .browser .dir`, { text: 'Back On Earth', settle: 800 });
  await click(`${main} .browser .dir`, { text: 'Brighten', settle: 800 });
  await waitFor(`${main} .browser .file`, { timeout: 10000 });
  log(`files: ${all(`${main} .browser .file`).map(textOf).join(' | ')}`);
  await shot('09-file-browser');
});

await step('scan + prune + clean', async () => {
  await click(`${main} button[aria-label="Scan device library"]`);
  await waitFor('[role=dialog] .stat', { text: 'Albums scanned', timeout: 60000 });
  log(`scan: ${all('[role=dialog] .stat').map(textOf).join(' | ')}`);
  await shot('10-scan-result');
  await click('[role=dialog] button.link', { text: 'Prune' });
  await waitFor('[role=dialog] .stat', { text: 'Orphan songs removed', timeout: 60000 });
  const clean = find('[role=dialog] button.link', { text: /Clean/ });
  if (clean) {
    await click(clean);
    await waitFor('[role=dialog] .stat', { text: 'FLAC files scanned', timeout: 120000 });
  }
  log(`after: ${all('[role=dialog] .stat').map(textOf).join(' | ')}`);
  await shot('11-scan-prune-clean');
  await click('[role=dialog] button', { text: 'Done' });
  await waitFor('[role=dialog]', { gone: true });
});

await step('eject', async () => {
  await click(`${main} button[aria-label="Eject device"]`);
  await until(() => !deviceTile(), 'device gone from sidebar', 30000);
  const info = await run(`hdiutil info | grep -c DAPE2E || true`);
  assert(info.out.trim() === '0', 'image detached');
  await shot('12-ejected');
});

if (playlistId) await invoke('playlist_delete', { id: playlistId }).catch((e) => log(`cleanup playlist: ${e}`));
await run(`hdiutil detach ${VOL} -force >/dev/null 2>&1; rm -f ${IMG}`);
