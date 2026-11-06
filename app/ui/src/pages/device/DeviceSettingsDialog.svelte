<script lang="ts">
  // device_settings_dialog.dart
  import { tick } from 'svelte';
  import * as api from '../../lib/api';
  import { toAppError } from '../../lib/ipc';
  import { toast } from '../../lib/stores/toast.svelte';
  import type { DeviceSettings, FilenameFormat, FolderStructure, TranscodeFormat } from '../../lib/types';
  import Button from '../../widgets/Button.svelte';
  import Dialog from '../../widgets/Dialog.svelte';
  import ErrorRetry from '../../widgets/ErrorRetry.svelte';
  import IconButton from '../../widgets/IconButton.svelte';
  import Select from '../../widgets/Select.svelte';
  import Spinner from '../../widgets/Spinner.svelte';
  import TextField from '../../widgets/TextField.svelte';
  import Toggle from '../../widgets/Toggle.svelte';
  import FolderPickerDialog from './FolderPickerDialog.svelte';
  import {
    filenamePreview,
    folderPreview,
    resolvedMusicRoot,
    transcodeLabels,
    validateFilenameTemplate,
    validateFolderTemplate,
    validateMusicRootPath,
  } from '../../widgets/device/preview';

  let {
    devicePath,
    onClose,
    onSaved,
  }: { devicePath: string; onClose: () => void; onSaved?: (settings: DeviceSettings) => void } = $props();

  // Bitrate choices; 0 stands in for "Unlimited" (null) because Select values are primitives.
  const bitRateChoices = [0, 96, 128, 192, 256, 320] as const;
  const bitRateOptions = bitRateChoices.map((br) => ({ value: br as number, label: br === 0 ? 'Unlimited' : `${br} kbps` }));
  const transcodeOptions = (Object.keys(transcodeLabels) as TranscodeFormat[]).map((f) => ({ value: f, label: transcodeLabels[f] }));

  const folderChoices: [FolderStructure, string][] = [
    ['artistAlbum', 'Artist / Album / track'],
    ['artistAlbumYear', 'Artist / Year - Album / track'],
    ['artistOnly', 'Artist / track'],
    ['flat', 'Flat (all files in music root)'],
    ['custom', 'Custom template'],
  ];
  const filenameChoices: [FilenameFormat, string][] = [
    ['discTrack', '1-01 - Title  (disc · track · title)'],
    ['track', '01 Title  (track · title)'],
    ['none', 'Title  (no prefix)'],
    ['custom', 'Custom template'],
  ];
  const tokens = ['{track}', '{track:02}', '{disc}', '{disc:02}', '{title}', '{artist}', '{albumArtist}', '{album}', '{year}'];

  let loadError = $state<unknown>(null);
  let loaded = $state(false);
  let saving = $state(false);
  let picking = $state(false);

  let root = $state('');
  let playlistFolder = $state('');
  let folderStructure = $state<FolderStructure>('artistAlbum');
  let filenameFormat = $state<FilenameFormat>('discTrack');
  let includeYear = $state(false);
  let overwriteExisting = $state(false);
  let transcodeFormat = $state<TranscodeFormat>('original');
  let bitRate = $state(0);
  let useZipDownload = $state(true);
  let autoCleanMetadata = $state(true);
  let autoShrinkCoverArt = $state(true);
  let customTemplate = $state('');
  let customFolder = $state('');
  let templateInput = $state<HTMLInputElement>();

  async function load(): Promise<void> {
    loadError = null;
    try {
      const s = await api.deviceSettingsGet(devicePath);
      root = s.musicRootFolder;
      playlistFolder = s.playlistFolder;
      folderStructure = s.folderStructure;
      filenameFormat = s.filenameFormat;
      includeYear = s.includeYear;
      overwriteExisting = s.overwriteExisting;
      transcodeFormat = s.transcodeFormat;
      bitRate = bitRateChoices.find((b) => b === s.transcodeMaxBitRate) ?? 0;
      useZipDownload = s.useZipDownload;
      autoCleanMetadata = s.autoCleanMetadata;
      autoShrinkCoverArt = s.autoShrinkCoverArt;
      customTemplate = s.customFilenameTemplate;
      customFolder = s.customFolderTemplate;
      loaded = true;
    } catch (e) {
      loadError = e;
    }
  }
  void load();

  const rootError = $derived(validateMusicRootPath(root.trim()));
  const rootPreview = $derived(rootError === null ? resolvedMusicRoot(devicePath, root.trim()) : null);
  const folderError = $derived(customFolder.trim() === '' ? 'Template cannot be empty' : validateFolderTemplate(customFolder));
  const filenameError = $derived(customTemplate.trim() === '' ? 'Template cannot be empty' : validateFilenameTemplate(customTemplate));
  const isOriginal = $derived(transcodeFormat === 'original');

  async function insertToken(t: string): Promise<void> {
    const el = templateInput;
    const start = el?.selectionStart ?? customTemplate.length;
    const end = el?.selectionEnd ?? start;
    const before = customTemplate.slice(0, start);
    customTemplate = `${before}${t}${customTemplate.slice(end)}`;
    await tick();
    el?.focus();
    el?.setSelectionRange(before.length + t.length, before.length + t.length);
  }

  async function save(): Promise<void> {
    const rootErr = validateMusicRootPath(root);
    if (rootErr !== null) {
      toast(`Music root: ${rootErr}`, { kind: 'error' });
      return;
    }
    if (filenameFormat === 'custom') {
      const err = validateFilenameTemplate(customTemplate);
      if (err !== null) {
        toast(`Filename template: ${err}`, { kind: 'error' });
        return;
      }
    }
    if (folderStructure === 'custom') {
      const err = validateFolderTemplate(customFolder);
      if (err !== null) {
        toast(`Folder template: ${err}`, { kind: 'error' });
        return;
      }
    }
    const settings: DeviceSettings = {
      devicePath,
      musicRootFolder: root.trim(),
      playlistFolder: playlistFolder.trim(),
      folderStructure,
      filenameFormat,
      includeYear,
      overwriteExisting,
      transcodeFormat,
      // Bit-rate is only meaningful when actually transcoding.
      transcodeMaxBitRate: isOriginal || bitRate === 0 ? null : bitRate,
      // Persisted even when transcoding so the choice survives a round-trip.
      useZipDownload,
      customFilenameTemplate: customTemplate.trim(),
      customFolderTemplate: customFolder.trim(),
      autoCleanMetadata,
      autoShrinkCoverArt,
    };
    saving = true;
    try {
      await api.deviceSettingsSave(settings);
      onSaved?.(settings);
      onClose();
    } catch (e) {
      toast(`Couldn't save device settings: ${toAppError(e).message}`, { kind: 'error' });
    } finally {
      saving = false;
    }
  }
</script>

<Dialog title="Device Settings" width={480} onclose={onClose}>
  {#if loadError}
    <div class="state"><ErrorRetry error={loadError} onRetry={load} compact /></div>
  {:else if !loaded}
    <div class="state"><Spinner /></div>
  {:else}
    <div class="form">
      <div class="section">FOLDERS</div>
      <div class="setting">
        <div class="label">
          <div>Music root path</div>
          <div class="hint">Relative to device root. Leave empty for root.</div>
        </div>
        <div class="field wide">
          <TextField bind:value={root} placeholder="e.g. Music/FLAC" />
          <IconButton icon="folder" size={16} label="Browse" color="var(--color-text-secondary)" onclick={() => (picking = true)} />
        </div>
      </div>
      {#if rootError !== null}
        <div class="note err">{rootError}</div>
      {:else if rootPreview !== null && root.trim() !== ''}
        <div class="note ellipsis">→ {rootPreview}</div>
      {/if}
      <div class="setting gap">
        <div class="label">
          <div>Playlist folder</div>
          <div class="hint">Relative to device root (not music root)</div>
        </div>
        <div class="field"><TextField bind:value={playlistFolder} placeholder="e.g. Playlists" /></div>
      </div>

      <div class="section top">FOLDER STRUCTURE</div>
      <div role="radiogroup" aria-label="Folder structure">
        {#each folderChoices as [value, label] (value)}
          <label class="radio"><input type="radio" name="folder" {value} bind:group={folderStructure} />{label}</label>
        {/each}
      </div>
      {#if folderStructure === 'custom'}
        <div class="custom">
          <TextField bind:value={customFolder} placeholder={'{albumArtist}/{year} - {album}'} />
          {#if folderError !== null}
            <div class="note err">{folderError}</div>
          {:else}
            <div class="note ellipsis">→ {folderPreview(customFolder)}</div>
          {/if}
          <div class="tiny">Use / to separate path components. {'{title}'} not allowed.</div>
        </div>
      {/if}

      <div class="section top">FILENAME FORMAT</div>
      <div role="radiogroup" aria-label="Filename format">
        {#each filenameChoices as [value, label] (value)}
          <label class="radio"><input type="radio" name="filename" {value} bind:group={filenameFormat} />{label}</label>
        {/each}
      </div>
      {#if filenameFormat === 'custom'}
        <div class="custom">
          <TextField bind:value={customTemplate} bind:input={templateInput} placeholder={'{track:02} - {title}'} />
          {#if filenameError !== null}
            <div class="note err">{filenameError}</div>
          {:else}
            <div class="note ellipsis">→ {filenamePreview(customTemplate)}</div>
          {/if}
          <div class="chips">
            {#each tokens as t (t)}
              <button type="button" class="chip" onmousedown={(e) => e.preventDefault()} onclick={() => void insertToken(t)}>{t}</button>
            {/each}
          </div>
        </div>
      {/if}

      <div class="section top">TRANSCODING</div>
      <div class="setting">
        <div class="label">
          <div>Format</div>
          <div class="hint">Re-encode on the server before transfer</div>
        </div>
        <div class="field"><Select bind:value={transcodeFormat} options={transcodeOptions} /></div>
      </div>
      {#if !isOriginal}
        <div class="setting gap">
          <div class="label">
            <div>Max bitrate</div>
            <div class="hint">Server caps re-encoded streams</div>
          </div>
          <div class="field"><Select bind:value={bitRate} options={bitRateOptions} /></div>
        </div>
      {/if}

      <div class="section top">FILE OPTIONS</div>
      {@render toggle('Include year in album folder name', includeYear, (v) => (includeYear = v))}
      {@render toggle('Overwrite existing files', overwriteExisting, (v) => (overwriteExisting = v))}
      {@render toggle('Bulk album download (zip, faster)', useZipDownload, (v) => (useZipDownload = v), !isOriginal)}
      {#if !isOriginal}
        <div class="explain">Bulk zip is only available in Original format.</div>
      {/if}

      <div class="section top small-gap">DAP COMPATIBILITY</div>
      {@render toggle('Automatically clean metadata', autoCleanMetadata, (v) => (autoCleanMetadata = v))}
      <div class="explain">
        Strips multi-line LYRICS and duplicate GENRE that break embedded DAP tag parsers (e.g. Shanling M-series).
      </div>
      {@render toggle('Automatically shrink album art', autoShrinkCoverArt, (v) => (autoShrinkCoverArt = v))}
      <div class="explain">
        Resizes embedded cover art to 320 px (DAP screen size). Lossless audio is untouched; saves several MB per album.
      </div>
    </div>
  {/if}
  {#snippet footer()}
    <Button variant="text" onclick={onClose}>Cancel</Button>
    <Button variant="primary" disabled={!loaded || saving} onclick={() => void save()}>Save</Button>
  {/snippet}
</Dialog>

{#if picking}
  <FolderPickerDialog
    {devicePath}
    initialRelative={root.trim()}
    onResult={(rel) => {
      picking = false;
      if (rel !== null) root = rel;
    }}
  />
{/if}

{#snippet toggle(label: string, checked: boolean, set: (v: boolean) => void, disabled = false)}
  <div class="toggle-row">
    <span>{label}</span>
    <Toggle {checked} {disabled} onchange={set} />
  </div>
{/snippet}

<style>
  .state {
    min-height: 160px;
    display: grid;
    place-items: center;
  }
  .form {
    max-height: 560px;
    display: flex;
    flex-direction: column;
    padding-right: 4px;
    font-size: 13px;
    color: var(--color-text-primary);
  }
  /* The column is height-capped: without this, overflow:hidden notes shrink to zero height. */
  .form > * {
    flex-shrink: 0;
  }
  .section {
    margin-bottom: 8px;
    font-size: 10px;
    font-weight: 600;
    letter-spacing: 0.8px;
    color: var(--color-text-secondary);
  }
  .top {
    margin-top: 20px;
  }
  .small-gap {
    margin-top: 12px;
  }
  .setting {
    display: flex;
    align-items: center;
    gap: 16px;
  }
  .gap {
    margin-top: 12px;
  }
  .label {
    flex: 1;
    min-width: 0;
  }
  .hint,
  .explain {
    font-size: 11px;
    color: var(--color-text-secondary);
  }
  .explain {
    padding: 0 0 4px 4px;
  }
  .field {
    width: 160px;
    flex: none;
  }
  .field.wide {
    width: 200px;
    display: flex;
    align-items: center;
    gap: 4px;
  }
  .field.wide :global(.tf) {
    flex: 1;
  }
  .note {
    margin: 6px 0 0 2px;
    font-size: 11px;
    color: var(--color-text-secondary);
  }
  .ellipsis {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .err {
    color: #ff5252;
  }
  .radio {
    display: flex;
    align-items: center;
    gap: 10px;
    height: 32px;
  }
  .radio input {
    margin: 0;
    accent-color: var(--color-accent);
  }
  .custom {
    display: flex;
    flex-direction: column;
    padding: 6px 0 0 16px;
  }
  .tiny {
    margin-top: 6px;
    font-size: 10px;
    color: var(--color-text-secondary);
  }
  .chips {
    display: flex;
    flex-wrap: wrap;
    gap: 4px 6px;
    margin-top: 6px;
  }
  .chip {
    padding: 2px 6px;
    border: none;
    border-radius: 4px;
    background: var(--color-surface-variant);
    font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
    font-size: 10px;
    color: var(--color-text-secondary);
  }
  .chip:hover {
    color: var(--color-text-primary);
  }
  .toggle-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    min-height: 40px;
  }
</style>
