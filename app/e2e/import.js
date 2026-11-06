// Spotify/Tidal import page: invalid URL → error state; real public playlist → review (or the
// scraper's error message, recorded).
const main = 'main.main';
const page = `${main} section.page`;

await step('connect', connectDemo);

await step('open import page', async () => {
  await click('nav.sidebar button[aria-label="Import from Spotify"]', { settle: 600 });
  await waitFor(`${page} h1`, { text: 'Import from a playlist' });
  assert(find(`${page} button`, { text: 'Import' }).disabled, 'Import disabled while empty');
  await shot('01-import-idle');
});

await step('invalid URL → error state', async () => {
  await type(`${page} form.url input`, 'https://example.com/not-a-playlist');
  await click(`${page} button`, { text: 'Import' });
  const err = await waitFor(`${page} .error`, { timeout: 20000 });
  log(`invalid URL error: ${textOf(err)}`);
  await shot('02-import-invalid');
  await click(`${page} button`, { text: 'Start over' });
  await waitFor(`${page} h1`, { text: 'Import from a playlist' });
});

await step('real Spotify playlist', async () => {
  await type(`${page} form.url input`, 'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M');
  await click(`${page} button`, { text: 'Import' });
  await sleep(300);
  await shot('03-import-scraping');
  const end = await until(() => find(`${page} .error`) ?? find(`${page} .review, ${page} [class*=review]`), 'review or error', 120000);
  if (end.classList.contains('error')) {
    log(`spotify import error: ${textOf(end)}`);
  } else {
    log(`review: ${textOf(end).slice(0, 300)}`);
  }
  await shot('04-import-result');
  const state = await invoke('import_state');
  log(`import state: ${state.kind}${state.matches ? ` matches=${state.matches.length}` : ''}${state.message ? ` message=${state.message}` : ''}`);
  await invoke('import_reset');
  await waitFor(`${page} h1`, { text: 'Import from a playlist', timeout: 10000 });
});
