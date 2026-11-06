// Lidarr: hidden without an instance; a bogus instance shows a connection error.
const main = 'main.main';
const dialog = '[role=dialog]';

await step('connect', connectDemo);

await step('no instance → Lidarr section hidden', async () => {
  const s = await invoke('lidarr_instances');
  assert(s.instances.length === 0, 'no instances');
  assert(!find('nav.sidebar .header', { text: 'LIDARR' }), 'no LIDARR header');
  await click('nav.sidebar button.tile', { text: 'Artists', settle: 600 });
  await click(`${main} .list button.tile`, { text: 'Nine Inch Nails', timeout: 15000, settle: 800 });
  await waitFor(`${main} .panel h1`, { text: 'Nine Inch Nails' });
  assert(!find(`${main} .panel button`, { text: 'Add to Lidarr' }), 'no Add to Lidarr without instance');
  await shot('01-no-lidarr');
});

await step('bogus instance → connection error', async () => {
  await click('nav.sidebar button.tile', { text: 'Settings', settle: 600 });
  await click(`${main} [role=tab]`, { text: 'Lidarr', settle: 600 });
  await waitFor(`${main} h3`, { text: 'Lidarr Instances' });
  await click(`${main} button`, { text: 'Add Instance' });
  await waitFor(dialog, { text: 'Add Lidarr Instance' });
  await type(await field('Name'), 'Bogus');
  await type(await field('Lidarr URL'), 'http://127.0.0.1:9');
  await type(await field('API Key'), '0123456789abcdef');
  await click(`${dialog} button`, { text: 'Test & Add' });
  const banner = await waitFor(`${dialog} [role=alert]`, { timeout: 20000 });
  log(`lidarr error: ${textOf(banner)}`);
  await shot('02-lidarr-bogus');
  await click(`${dialog} button`, { text: 'Cancel' });
  await waitFor(dialog, { gone: true });
  assert(!find('nav.sidebar .header', { text: 'LIDARR' }), 'still hidden');
  assert((await invoke('lidarr_instances')).instances.length === 0, 'not saved');
});
