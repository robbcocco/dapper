<script lang="ts">
  // device_page.dart `_ScrobbleImportBanner`: result of the auto scrobble-log import for
  // this device; dismissible, replaced by the next device-plug import.
  import { devices } from '../../lib/stores/devices.svelte';
  import type { ScrobbleImportResult } from '../../lib/types';
  import Icon from '../../widgets/Icon.svelte';

  let { devicePath }: { devicePath: string } = $props();

  const result = $derived(
    devices.scrobbleImport !== null && devices.scrobbleImport.devicePath === devicePath && devices.scrobbleImport.parsed > 0
      ? devices.scrobbleImport
      : null,
  );

  function summarise(r: ScrobbleImportResult): string {
    if (r.matched === 0) {
      return `Found ${r.parsed} scrobble log entr${r.parsed === 1 ? 'y' : 'ies'} but none matched library songs.`;
    }
    const base = `Imported ${r.submitted} of ${r.parsed} offline play${r.parsed === 1 ? '' : 's'} from device.`;
    const errs = `${r.errors} server error${r.errors === 1 ? '' : 's'}`;
    if (r.unmatched > 0 && r.errors > 0) return `${base} ${r.unmatched} unmatched, ${errs}.`;
    if (r.unmatched > 0) return `${base} ${r.unmatched} unmatched.`;
    if (r.errors > 0) return `${base} ${errs}.`;
    return base;
  }
</script>

{#if result}
  {@const color = result.errors > 0 ? '#ff9800' : result.matched === 0 ? 'var(--color-text-secondary)' : 'var(--color-accent)'}
  <div class="wrap">
    <div class="banner" style:--tone={color}>
      <!-- Material cloud_upload_outlined -->
      <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true" style="flex:none">
        <path
          d="M19.35 10.04C18.67 6.59 15.64 4 12 4 9.11 4 6.6 5.64 5.35 8.04 2.34 8.36 0 10.91 0 14c0 3.31 2.69 6 6 6h13c2.76 0 5-2.24 5-5 0-2.64-2.05-4.78-4.65-4.96zM19 18H6c-2.21 0-4-1.79-4-4 0-2.05 1.53-3.76 3.56-3.97l1.07-.11.5-.95C8.08 7.14 9.94 6 12 6c2.62 0 4.88 1.86 5.39 4.43l.3 1.5 1.53.11c1.56.1 2.78 1.41 2.78 2.96 0 1.65-1.35 3-3 3zM8 13h2.55v3h2.9v-3H16l-4-4z"
        />
      </svg>
      <span class="msg">{summarise(result)}</span>
      <button type="button" aria-label="Dismiss" onclick={() => devices.dismissScrobbleImport()}>
        <Icon name="close" size={13} />
      </button>
    </div>
  </div>
{/if}

<style>
  .wrap {
    padding: 8px 24px 0;
  }
  .banner {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 8px 12px;
    border-radius: 8px;
    border: 1px solid color-mix(in srgb, var(--tone) 35%, transparent);
    background: color-mix(in srgb, var(--tone) 8%, transparent);
    color: var(--tone);
  }
  .msg {
    flex: 1;
    font-size: 11px;
  }
  button {
    display: grid;
    place-items: center;
    padding: 0;
    border: none;
    background: none;
    color: inherit;
  }
</style>
