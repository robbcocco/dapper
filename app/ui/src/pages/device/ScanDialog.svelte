<script lang="ts">
  import * as api from '../../lib/api';
  import { toAppError } from '../../lib/ipc';
  import type { FileDuplicate, PruneResult, ScanProgress, ScanReport, TagSanitizeResult } from '../../lib/types';
  import Button from '../../widgets/Button.svelte';
  import Dialog from '../../widgets/Dialog.svelte';
  import Icon from '../../widgets/Icon.svelte';
  import Spinner from '../../widgets/Spinner.svelte';
  import { formatBytes } from '../../widgets/device/format';
  import { joinPath } from '../../widgets/device/preview';

  let { devicePath, onClose }: { devicePath: string; onClose: () => void } = $props();

  let status = $state('Starting scan…');
  let result = $state<ScanReport | null>(null);

  let pruning = $state(false);
  let pruneStatus = $state('');
  let pruneResult = $state<PruneResult | null>(null);

  let sanitizing = $state(false);
  let sanitizeStatus = $state('');
  let sanitizeResult = $state<TagSanitizeResult | null>(null);

  let deleteError = $state<string | null>(null);

  function describe(p: ScanProgress): string {
    if (p.total !== null) return `${p.phase} (${p.done}/${p.total})`;
    return p.done > 0 ? `${p.phase} (${p.done})` : p.phase;
  }

  const plural = (n: number, word: string): string => `${n} ${word}${n === 1 ? '' : 's'}`;

  $effect(() => {
    const path = devicePath;
    api
      .deviceScan(path, false, false, (p) => (status = describe(p)))
      .then((r) => (result = r))
      .catch((e: unknown) => (status = `Error: ${toAppError(e).message}`));
  });

  // Prune and tag-clean ride on the scan command; the refreshed scan stats replace
  // the previous ones (with any file duplicates already resolved here dropped).
  async function runPrune(): Promise<void> {
    pruning = true;
    pruneStatus = 'Starting prune…';
    try {
      const r = await api.deviceScan(devicePath, true, false, (p) => (pruneStatus = describe(p)));
      result = r;
      pruneResult = r.prune;
    } catch (e) {
      pruneStatus = `Error: ${toAppError(e).message}`;
    } finally {
      pruning = false;
    }
  }

  async function runSanitize(): Promise<void> {
    sanitizing = true;
    sanitizeStatus = 'Starting…';
    try {
      const r = await api.deviceScan(devicePath, false, true, (p) => (sanitizeStatus = describe(p)));
      result = r;
      sanitizeResult = r.clean;
    } catch (e) {
      sanitizeStatus = `Error: ${toAppError(e).message}`;
    } finally {
      sanitizing = false;
    }
  }

  const deletable = (dup: FileDuplicate): string[] =>
    dup.correctFilename === null ? [] : dup.filenames.filter((f) => f !== dup.correctFilename);

  async function resolve(dup: FileDuplicate): Promise<void> {
    deleteError = null;
    try {
      await api.deviceDeleteFiles(
        devicePath,
        deletable(dup).map((f) => joinPath(dup.folderPath, f)),
      );
      if (result) result = { ...result, fileDuplicates: result.fileDuplicates.filter((d) => d !== dup) };
    } catch (e) {
      deleteError = toAppError(e).message;
    }
  }

  /** Correct file first, then the deletable ones. */
  const ordered = (dup: FileDuplicate): string[] => [
    ...(dup.correctFilename !== null ? [dup.correctFilename] : []),
    ...dup.filenames.filter((f) => f !== dup.correctFilename),
  ];

  const hasDuplicates = $derived(!!result && (result.manifestDuplicates.length > 0 || result.fileDuplicates.length > 0));
</script>

<Dialog title="Scan Device Library" width={488} dismissible={false} onclose={onClose}>
  <div class="scan">
    {#if result === null}
      <div class="progress">
        <Spinner size={32} stroke={3} />
        <span>{status}</span>
      </div>
    {:else}
      {@render stat('Albums scanned', String(result.albumsScanned))}
      {@render stat('Albums with audio files', String(result.albumsMatched))}
      {@render stat('Songs on device', String(result.songsTotal))}
      {@render stat('Songs matched & added to manifests', String(result.songsMatched))}

      {#if hasDuplicates}
        <hr />
        {#if result.fileDuplicates.length > 0}
          <div class="warn-title">
            {result.fileDuplicates.length} folder{result.fileDuplicates.length === 1 ? '' : 's'} with same-track duplicates
          </div>
          <div class="list" style:max-height="260px">
            {#each result.fileDuplicates as dup (dup)}
              {@const del = deletable(dup)}
              <div class="dup">
                <div class="folder" title={dup.folderPath}>{dup.folderPath}</div>
                {#each ordered(dup) as name (name)}
                  {@const correct = name === dup.correctFilename}
                  <div class="file" class:correct>
                    <Icon name={correct ? 'check_circle' : 'cancel'} size={12} color={correct ? '#4caf50' : '#ff5252'} />
                    <span>{name}</span>
                  </div>
                {/each}
                {#if dup.correctFilename !== null}
                  <button type="button" class="delete" onclick={() => resolve(dup)}>
                    <Icon name="delete" size={13} />
                    Delete {plural(del.length, 'duplicate')}
                  </button>
                {:else}
                  <div class="note">Cannot determine which file to keep — delete manually.</div>
                {/if}
              </div>
            {/each}
          </div>
          {#if deleteError}<div class="small warn">{deleteError}</div>{/if}
        {/if}
        {#if result.manifestDuplicates.length > 0}
          <div class="warn-title">
            {result.manifestDuplicates.length} song{result.manifestDuplicates.length === 1 ? '' : 's'} in multiple folders
          </div>
          <div class="list" style:max-height="160px">
            {#each result.manifestDuplicates as dup (dup.songId)}
              <div class="mdup">
                <div class="title">{dup.title}</div>
                {#each dup.folderPaths as path (path)}
                  <div class="folder" title={path}>&nbsp;&nbsp;{path}</div>
                {/each}
              </div>
            {/each}
          </div>
        {/if}
      {:else}
        <p class="muted">No duplicates found.</p>
      {/if}
      {#if result.albumsScanned === 0 && result.fileDuplicates.length === 0}
        <p class="muted">Scan is only supported for Artist/Album folder structures.</p>
      {/if}

      <hr />
      {#if pruneResult}
        {@render stat('Orphan songs removed', String(pruneResult.songsRemoved))}
        {@render stat('Space freed', formatBytes(pruneResult.bytesFreed))}
        {#if pruneResult.errors.length > 0}
          <div class="small warn">{pruneResult.errors.length} file(s) could not be deleted</div>
        {/if}
      {:else if pruning}
        {@render running(pruneStatus)}
      {:else}
        {@render action('Prune orphan files', 'Remove songs no longer in the library', 'Prune', 'orange', runPrune)}
        {#if pruneStatus}<div class="small muted">{pruneStatus}</div>{/if}
      {/if}

      <hr />
      {#if sanitizeResult}
        {@render stat('FLAC files scanned', String(sanitizeResult.filesScanned))}
        {@render stat('Already clean (skipped)', String(sanitizeResult.filesSkipped))}
        {@render stat('Files cleaned', String(sanitizeResult.filesModified))}
        {@render stat('Album covers shrunk', String(sanitizeResult.coversShrunk))}
        {@render stat('Space freed', formatBytes(sanitizeResult.bytesFreed))}
        {#if sanitizeResult.errors.length > 0}
          <div class="small warn">{sanitizeResult.errors.length} file(s) failed</div>
        {/if}
      {:else if sanitizing}
        {@render running(sanitizeStatus)}
      {:else}
        {@render action(
          'Clean FLAC tags & shrink covers',
          'Strip bad tags + shrink embedded cover art to 320 px',
          'Clean',
          'accent',
          runSanitize,
        )}
        {#if sanitizeStatus}<div class="small muted">{sanitizeStatus}</div>{/if}
      {/if}
    {/if}
  </div>

  {#snippet footer()}
    {#if result !== null}
      <Button variant="text" onclick={onClose}>Done</Button>
    {/if}
  {/snippet}
</Dialog>

{#snippet stat(label: string, value: string)}
  <div class="stat"><span>{label}</span><b>{value}</b></div>
{/snippet}

{#snippet running(text: string)}
  <div class="running"><Spinner size={14} /><span>{text}</span></div>
{/snippet}

{#snippet action(title: string, hint: string, label: string, tone: 'orange' | 'accent', run: () => void)}
  <div class="action">
    <div class="action-text">
      <div class="action-title">{title}</div>
      <div class="small muted">{hint}</div>
    </div>
    <button type="button" class="link {tone}" disabled={pruning || sanitizing} onclick={run}>{label}</button>
  </div>
{/snippet}

<style>
  .scan {
    display: flex;
    flex-direction: column;
    font-size: 12px;
  }
  .progress {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 16px;
    padding: 8px 0;
  }
  .progress :global(.sp) {
    color: var(--color-accent);
  }
  .stat {
    display: flex;
    justify-content: space-between;
    padding: 3px 0;
  }
  .stat b {
    font-weight: 600;
    color: var(--color-text-primary);
  }
  hr {
    width: 100%;
    border: none;
    border-top: 1px solid var(--color-divider);
    margin: 8px 0;
  }
  .warn-title {
    margin: 4px 0 6px;
    font-size: 13px;
    font-weight: 600;
    color: #ff9800;
  }
  .list {
    overflow-y: auto;
  }
  .dup,
  .mdup {
    padding: 6px 0;
    border-bottom: 1px solid var(--color-divider);
  }
  .dup:last-child,
  .mdup:last-child {
    border-bottom: none;
  }
  .folder {
    font-size: 10px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .title {
    color: var(--color-text-primary);
  }
  .file {
    display: flex;
    align-items: center;
    gap: 5px;
    margin-top: 2px;
    font-size: 11px;
    text-decoration: line-through;
  }
  .file span {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .file.correct {
    color: var(--color-text-primary);
    text-decoration: none;
  }
  .delete {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    margin-top: 6px;
    padding: 4px 8px;
    border: none;
    border-radius: 6px;
    background: transparent;
    font: inherit;
    font-size: 11px;
    color: #ff5252;
  }
  .delete:hover {
    background: rgba(255, 82, 82, 0.1);
  }
  .note {
    margin-top: 6px;
    font-size: 10px;
  }
  .muted {
    color: var(--color-text-secondary);
  }
  p.muted {
    margin: 8px 0 0;
  }
  .small {
    font-size: 11px;
  }
  .warn {
    margin-top: 4px;
    color: #ff9800;
  }
  .running {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 11px;
  }
  .action {
    display: flex;
    align-items: center;
    gap: 8px;
  }
  .action-text {
    flex: 1;
  }
  .action-title {
    font-weight: 600;
    color: var(--color-text-primary);
  }
  .link {
    padding: 4px 10px;
    border: none;
    border-radius: 6px;
    background: transparent;
    font: inherit;
    font-size: 12px;
  }
  .link:not(:disabled):hover {
    background: rgba(255, 255, 255, 0.06);
  }
  .link:disabled {
    opacity: 0.4;
  }
  .orange {
    color: #ff9800;
  }
  .accent {
    color: var(--color-accent);
  }
</style>
