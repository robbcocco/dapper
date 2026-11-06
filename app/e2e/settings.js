// Settings: concurrency, clean cache, edit server with blank password, bogus second server,
// reset all data → setup screen.
const main = 'main.main';
const dialog = '[role=dialog]';
const toastText = () => textOf(find('.toast') ?? document.body);

await step('connect', connectDemo);

await step('open settings', async () => {
  await click('nav.sidebar button.tile', { text: 'Settings', settle: 600 });
  await waitFor(`${main} h3`, { text: 'Transfer' });
  await shot('01-general');
});

await step('transfer concurrency', async () => {
  await click(`${main} .row [role=tab]`, { text: '3', settle: 600 });
  await until(async () => (await invoke('app_settings_get')).transferConcurrency === 3, 'concurrency 3 persisted');
  assert(find(`${main} .row [role=tab][aria-selected=true]`, { text: '3' }), '3 selected');
  await click(`${main} .row [role=tab]`, { text: '2', settle: 600 });
  await until(async () => (await invoke('app_settings_get')).transferConcurrency === 2, 'concurrency 2 persisted');
});

await step('clean cache', async () => {
  await click(`${main} button`, { text: 'Clean cache' });
  await until(() => /cleared/i.test(toastText()), 'clean toast', 10000);
  log(`toast: ${toastText()}`);
  await shot('02-clean-cache');
});

await step('edit server with blank password', async () => {
  await click(`${main} [role=tab]`, { text: 'Navidrome', settle: 600 });
  await waitFor(`${main} .tile.active`, { text: 'demo.navidrome.org' });
  await click(`${main} .tile.active button[aria-label=Edit]`);
  await waitFor(dialog, { text: 'Edit Server' });
  const pw = await field('Password (leave blank to keep current)');
  assert(pw.value === '', 'password blank');
  await type(await field('Name'), 'Demo (edited)');
  await shot('03-edit-server');
  await click(`${dialog} button`, { text: 'Save' });
  await waitFor(dialog, { gone: true, timeout: 20000 });
  await waitFor(`${main} .tile.active`, { text: 'Demo (edited)' });
  await waitFor('nav.sidebar .switcher', { text: 'Demo (edited)', timeout: 10000 });
  const s = await invoke('library_sync_status');
  assert(!s.error, `session still valid (${s.error})`);
});

await step('bogus second server shows error', async () => {
  await click(`${main} button`, { text: 'Add Server' });
  await waitFor(dialog, { text: 'Add Server' });
  await type(await field('Name'), 'Bogus');
  await type(await field('Server URL'), 'http://127.0.0.1:9');
  await type(await field('Username'), 'nobody');
  await type(await field('Password'), 'nothing');
  await click(`${dialog} button`, { text: 'Test & Add' });
  const banner = await waitFor(`${dialog} [role=alert]`, { timeout: 20000 });
  log(`bogus server error: ${textOf(banner)}`);
  await shot('04-bogus-server');
  await click(`${dialog} button`, { text: 'Cancel' });
  await waitFor(dialog, { gone: true });
  assert(!find(`${main} .tile`, { text: 'Bogus' }), 'bogus not added');
});

await step('reset all data → setup', async () => {
  await click(`${main} [role=tab]`, { text: 'General', settle: 600 });
  await click(`${main} button.reset`);
  await waitFor(dialog, { text: 'This cannot be undone' });
  await shot('05-reset-confirm');
  await click(`${dialog} button`, { text: /^Reset$/ });
  await waitFor('form.card', { text: 'Connect to Navidrome', timeout: 20000 });
  const servers = await invoke('servers_list');
  assert(servers.servers.length === 0, 'no servers left');
  await shot('06-after-reset');
});
