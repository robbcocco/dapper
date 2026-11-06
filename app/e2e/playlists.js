// Playlists: create, add songs (selection + context menu), rename, remove a song, delete.
const main = 'main.main';
const name = `E2E ${Date.now().toString(36)}`;
const renamed = `${name} renamed`;
const sidebarItem = (n) => find('nav.sidebar button.tile.playlist', { text: n });
const songRows = () => all(`${main} .detail [role=row]`);

await step('connect', connectDemo);

await step('create playlist from sidebar', async () => {
  await click('nav.sidebar button[aria-label="New Playlist"]');
  await type('[role=dialog] input', name);
  await shot('01-new-playlist-dialog');
  await click('[role=dialog] button', { text: 'Create' });
  await waitFor('[role=dialog]', { gone: true });
  await until(() => sidebarItem(name), 'playlist in sidebar', 15000);
});

const tableRows = () => all(`${main} [role=row]:not(.cols)`).filter((r) => r.querySelector('.title'));

await step('add selected songs from Songs', async () => {
  await click('nav.sidebar button.tile', { text: 'Songs', settle: 600 });
  await waitFor(`${main} [role=row] .title`, { timeout: 15000 });
  // Re-query each time: rows re-render on selection changes.
  for (const i of [0, 1, 2]) {
    const row = tableRows()[i];
    await click(row, { mouse: { metaKey: true }, settle: 400 });
    log(`after meta-click ${i} (${textOf(row.querySelector('.title'))}): ${all(`${main} [role=row].selected`).map((r) => textOf(r.querySelector('.title'))).join(' | ')}`);
  }
  await until(() => all(`${main} [role=row].selected`).length === 3, '3 rows selected');
  await waitFor(`${main} .bar`, { text: '3 selected' });
  await shot('02-songs-selected');
  const menu = await contextMenu(tableRows()[0], 'Add 3 selected songs to Playlist');
  log(`menu: ${menu.filter((m) => m.label).map((m) => m.label).join(' | ')}`);
  await click('[role=dialog] button.item', { text: name, timeout: 10000 });
  await waitFor('[role=dialog]', { gone: true, timeout: 10000 });
  await until(() => all(`${main} [role=row].selected`).length === 0, 'selection cleared');
});

await step('add single song via context menu', async () => {
  await contextMenu(tableRows()[5], 'Add to Playlist');
  await click('[role=dialog] button.item', { text: name, timeout: 10000 });
  await waitFor('[role=dialog]', { gone: true, timeout: 10000 });
});

await step('playlist detail shows 4 songs', async () => {
  await click(sidebarItem(name), { settle: 800 });
  await waitFor(`${main} .detail h1`, { text: name });
  await until(() => songRows().length === 4, `4 songs (have ${songRows().length})`, 15000);
  log(`meta: ${textOf(find(`${main} .detail .meta`))}`);
  await shot('03-playlist-detail');
});

await step('remove song', async () => {
  const first = textOf(songRows()[0].querySelector('.title'));
  await contextMenu(songRows()[0], 'Remove from Playlist');
  await until(() => songRows().length === 3, 'one fewer song', 15000);
  assert(textOf(songRows()[0].querySelector('.title')) !== first, 'first song removed');
  const pl = (await invoke('playlists_list')).find((p) => p.name === name);
  assert(pl && pl.songCount === 3, `server count 3 (got ${pl?.songCount})`);
});

await step('rename', async () => {
  await click(`${main} button[aria-label=Back]`, { settle: 600 });
  const row = await scrollFind(`${main} .vl`, `${main} button.row`, { text: name });
  await contextMenu(row, 'Rename');
  const input = await waitFor('[role=dialog] input');
  assert(input.value === name, 'prefilled name');
  await type(input, renamed);
  await click('[role=dialog] button', { text: /^Rename$/ });
  await until(() => sidebarItem(renamed), 'renamed in sidebar', 15000);
  await scrollFind(`${main} .vl`, `${main} button.row`, { text: renamed });
  await shot('04-renamed');
});

await step('delete', async () => {
  const row = await scrollFind(`${main} .vl`, `${main} button.row`, { text: renamed });
  await contextMenu(row, 'Delete');
  await waitFor('[role=dialog]', { text: 'cannot be undone' });
  await shot('05-delete-confirm');
  await click('[role=dialog] button', { text: /^Delete$/ });
  await until(() => !sidebarItem(renamed), 'gone from sidebar', 15000);
  const left = (await invoke('playlists_list')).filter((p) => p.name.startsWith(name));
  assert(left.length === 0, 'deleted on server');
});
