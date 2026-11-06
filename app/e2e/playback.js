// Playback: album track → bottom bar, transport, seek, volume, shuffle/repeat, lyrics.
const main = 'main.main';
const bar = '.bottom-bar';
const title = () => textOf(find(`${bar} .now-playing .title`) ?? document.body);
const times = () => all(`${bar} .seek .time`).map(textOf);
const secs = (s) => s.split(':').reduce((a, b) => a * 60 + Number(b), 0);
const state = async () => (await invoke('player_state')).state;

await step('connect', connectDemo);

await step('quiet volume', async () => {
  await type(`${bar} input[aria-label=Volume]`, '0.05');
  await until(async () => Math.abs((await state()).volume - 0.05) < 0.01, 'volume 0.05');
});

await step('play album track', async () => {
  await click('nav.sidebar button.tile', { text: 'Albums', settle: 600 });
  await click(`${main} button.card`, { text: 'Ghosts VI: Locusts', timeout: 15000, settle: 800 });
  await waitFor(`${main} .detail h1`, { text: 'Ghosts VI' });
  await click(`${main} .detail button`, { text: /^Play$/ });
  await until(() => title() !== 'Not Playing' && title() !== '', 'now playing title', 15000);
  await until(() => find(`${bar} .now-playing img`)?.naturalWidth > 0, 'now playing cover', 10000).catch((e) => {
    const img = document.querySelector(`${bar} .now-playing img`);
    log(`cover: ${document.querySelector(`${bar} .now-playing .cover`)?.outerHTML} complete=${img?.complete} nw=${img?.naturalWidth}`);
    throw e;
  });
  await until(() => secs(times()[0]) >= 3, 'position advances', 20000);
  log(`now playing: ${title()} @ ${times().join(' / ')}`);
  await waitFor(`${main} .detail .row.playing`);
  await shot('01-playing');
});

await step('pause + resume', async () => {
  await click(`${bar} button.play[aria-label=Pause]`, { settle: 800 });
  await waitFor(`${bar} button.play[aria-label=Play]`);
  const t = times()[0];
  await sleep(2000);
  assert(times()[0] === t, `paused position steady (${t} vs ${times()[0]})`);
  await shot('02-paused');
  await click(`${bar} button.play[aria-label=Play]`);
  await waitFor(`${bar} button.play[aria-label=Pause]`, { timeout: 10000 });
  await until(() => times()[0] !== t, 'resumed', 10000);
});

await step('next + previous', async () => {
  const first = title();
  await click(`${bar} button[aria-label=Next]`);
  await until(() => title() !== first, 'next track title', 15000);
  const second = title();
  log(`next: ${first} → ${second}`);
  await until(() => secs(times()[0]) >= 1, 'next playing', 20000);
  // Previous within the first seconds goes to the previous track (restarts otherwise).
  await click(`${bar} button[aria-label=Previous]`);
  await until(() => title() === first || secs(times()[0]) === 0, 'previous', 15000);
  log(`previous: ${title()} @ ${times()[0]}`);
});

await step('seek', async () => {
  await until(() => secs(times()[1]) > 0, 'duration known', 15000);
  const dur = secs(times()[1]);
  await type(`${bar} input[aria-label=Seek]`, '0.5');
  await until(() => Math.abs(secs(times()[0]) - dur / 2) <= 6, `seek to ~${dur / 2}s (at ${times()[0]})`, 20000);
  log(`seeked: ${times().join(' / ')}`);
  await shot('03-seeked');
});

await step('volume', async () => {
  await type(`${bar} input[aria-label=Volume]`, '0.1');
  await until(async () => Math.abs((await state()).volume - 0.1) < 0.01, 'volume 0.1');
});

await step('shuffle + repeat', async () => {
  const before = (await state()).isShuffled;
  await click(`${bar} button[aria-label=Shuffle]`, { settle: 500 });
  await until(async () => (await state()).isShuffled !== before, 'shuffle toggled');
  assert(find(`${bar} button[aria-label=Shuffle]`).classList.contains('active') === !before, 'shuffle accent');
  await click(`${bar} button[aria-label=Shuffle]`, { settle: 500 });
  await waitFor(`${bar} button[aria-label="Repeat off"]`);
  await click(`${bar} button[aria-label="Repeat off"]`);
  await waitFor(`${bar} button[aria-label="Repeat all"]`);
  await click(`${bar} button[aria-label="Repeat all"]`);
  await waitFor(`${bar} button[aria-label="Repeat one"]`);
  assert((await state()).repeatMode === 'one', 'repeat one in backend');
  await shot('04-repeat-one');
  await click(`${bar} button[aria-label="Repeat one"]`);
  await waitFor(`${bar} button[aria-label="Repeat off"]`);
});

await step('lyrics dialog', async () => {
  await click(`${bar} .now-playing button.lyrics`);
  const dlg = await waitFor('[role=dialog] .lyrics');
  await until(() => !find('[role=dialog] .lyrics .center .spinner, [role=dialog] .lyrics [class*=spin]'), 'lyrics loaded', 15000);
  await sleep(500);
  log(`lyrics: ${textOf(dlg).slice(0, 160)}`);
  await shot('05-lyrics');
  await click('[role=dialog] button', { text: 'Close' });
  await waitFor('[role=dialog]', { gone: true });
});

await step('space toggles playback', async () => {
  document.activeElement?.blur?.();
  await key(' ', { target: document.body, code: 'Space' });
  await waitFor(`${bar} button.play[aria-label=Play]`, { timeout: 5000 });
  await shot('06-final-paused');
});
