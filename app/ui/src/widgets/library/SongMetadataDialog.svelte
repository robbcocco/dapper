<script lang="ts">
  import Dialog from '../Dialog.svelte';
  import Button from '../Button.svelte';
  import Icon from '../Icon.svelte';
  import RatingStars from '../RatingStars.svelte';
  import TextField from '../TextField.svelte';
  import * as api from '../../lib/api';
  import { toAppError } from '../../lib/ipc';
  import type { Song, SongUpdateFields } from '../../lib/types';
  import { toast } from '../../lib/stores/toast.svelte';
  import { fmtDuration } from './actions';
  import { ratings } from './ratings.svelte';

  /** Port of song_metadata_dialog.dart, plus tag editing through Navidrome's native API (`song_update`). */
  let { song, onresult }: { song: Song; onresult: (r: null) => void } = $props();

  const rows = $derived(
    [
      ['Title', song.title],
      ['Artist', song.artist],
      ['Album Artist', song.albumArtist],
      ['Album', song.album],
      ['Genre', song.genre || null],
      ['Year', song.year?.toString() ?? null],
      ['Track', song.track?.toString() ?? null],
      ['Disc', song.discNumber?.toString() ?? null],
      ['Duration', song.duration != null ? fmtDuration(song.duration) : null],
    ].filter((r): r is [string, string] => r[1] != null),
  );

  let editing = $state(false);
  let saving = $state(false);
  let error = $state<string | null>(null);
  const initial = () => ({
    title: song.title,
    artist: song.artist ?? '',
    album: song.album ?? '',
    albumArtist: song.albumArtist ?? '',
    track: song.track?.toString() ?? '',
    disc: song.discNumber?.toString() ?? '',
    year: song.year?.toString() ?? '',
    genre: song.genre ?? '',
  });
  let form = $state(initial());

  type NumKey = 'track' | 'disc' | 'year';
  const numKeys: NumKey[] = ['track', 'disc', 'year'];
  const invalid = $derived(numKeys.filter((k) => form[k].trim() !== '' && !/^\d+$/.test(form[k].trim())));

  function changedFields(): SongUpdateFields {
    const base = initial();
    const out: SongUpdateFields = {};
    for (const k of ['title', 'artist', 'album', 'albumArtist', 'genre'] as const) {
      if (form[k].trim() !== base[k]) out[k] = form[k].trim();
    }
    for (const k of numKeys) {
      const v = form[k].trim();
      if (v !== base[k] && v !== '') out[k] = Number(v);
    }
    return out;
  }

  async function save(): Promise<void> {
    if (invalid.length > 0 || saving) return;
    if (form.title.trim() === '') {
      error = 'Title cannot be empty.';
      return;
    }
    const fields = changedFields();
    if (Object.keys(fields).length === 0) {
      editing = false;
      return;
    }
    saving = true;
    error = null;
    try {
      await api.songUpdate(song.id, fields);
      toast('Song info updated', { kind: 'success' });
      onresult(null);
    } catch (e) {
      error = toAppError(e).message;
    } finally {
      saving = false;
    }
  }
</script>

<Dialog title="Song Info" width={editing ? 440 : 400} onclose={() => onresult(null)}>
  {#if editing}
    <form
      class="form"
      onsubmit={(e) => {
        e.preventDefault();
        void save();
      }}
    >
      <TextField label="Title" bind:value={form.title} />
      <TextField label="Artist" bind:value={form.artist} />
      <TextField label="Album Artist" bind:value={form.albumArtist} />
      <TextField label="Album" bind:value={form.album} />
      <TextField label="Genre" bind:value={form.genre} />
      <div class="nums">
        <TextField label="Year" bind:value={form.year} inputmode="numeric" error={invalid.includes('year') ? 'Number' : null} />
        <TextField label="Track" bind:value={form.track} inputmode="numeric" error={invalid.includes('track') ? 'Number' : null} />
        <TextField label="Disc" bind:value={form.disc} inputmode="numeric" error={invalid.includes('disc') ? 'Number' : null} />
      </div>
      {#if error}<p class="error">{error}</p>{/if}
      <button type="submit" hidden aria-hidden="true"></button>
    </form>
  {:else}
    {#each rows as [label, value] (label)}
      <div class="row">
        <span class="label">{label}</span>
        <span class="value">{value}</span>
      </div>
    {/each}
    <div class="row rating">
      <span class="label">Rating</span>
      <RatingStars rating={ratings.get(song.id, song.userRating)} size={16} onRate={(r) => void ratings.set(song.id, r)} />
    </div>
    <p class="note"><Icon name="info" size={12} /> Edits are written to the server's library via Navidrome.</p>
  {/if}
  {#snippet footer()}
    {#if editing}
      <Button
        variant="text"
        onclick={() => {
          form = initial();
          error = null;
          editing = false;
        }}>Cancel</Button
      >
      <Button variant="primary" disabled={saving || invalid.length > 0} onclick={() => void save()}>{saving ? 'Saving…' : 'Save'}</Button>
    {:else}
      <Button variant="text" icon="edit" onclick={() => (editing = true)}>Edit</Button>
      <Button variant="text" onclick={() => onresult(null)}>Close</Button>
    {/if}
  {/snippet}
</Dialog>

<style>
  .row {
    display: flex;
    align-items: flex-start;
    padding-bottom: 6px;
    font-size: 11px;
  }
  .rating {
    align-items: center;
    padding-top: 4px;
  }
  .label {
    width: 80px;
    flex: none;
    font-weight: 600;
    letter-spacing: 0.3px;
    color: var(--color-text-secondary);
  }
  .value {
    flex: 1;
    min-width: 0;
    color: var(--color-text-primary);
    overflow-wrap: anywhere;
  }
  .note {
    display: flex;
    align-items: center;
    gap: 6px;
    margin: 12px 0 0;
    font-size: 10px;
  }
  .form {
    display: flex;
    flex-direction: column;
    gap: 10px;
  }
  .nums {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 10px;
  }
  .error {
    margin: 0;
    color: #ff453a;
    font-size: 12px;
  }
</style>
