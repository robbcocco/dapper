<script lang="ts">
  import { untrack } from 'svelte';
  import * as api from '../../lib/api';
  import type { LidarrInstance } from '../../lib/types';
  import Button from '../../widgets/Button.svelte';
  import Dialog from '../../widgets/Dialog.svelte';
  import Spinner from '../../widgets/Spinner.svelte';
  import TextField from '../../widgets/TextField.svelte';
  import ErrorBanner from '../../widgets/forms/ErrorBanner.svelte';
  import SecretField from '../../widgets/forms/SecretField.svelte';
  import { errorOf, friendlyLidarrError, isSaveError, normalizeUrl, validateUrl, withTimeout } from './connection';

  let { existing = null, onclose }: { existing?: LidarrInstance | null; onclose: (saved: boolean) => void } = $props();

  // The form edits a snapshot; the dialog is re-mounted per open.
  const initial = untrack(() => existing);
  const isEdit = initial !== null;
  let name = $state(initial?.name ?? '');
  let url = $state(initial?.url ?? '');
  let apiKey = $state('');
  let saving = $state(false);
  let error = $state<string | null>(null);
  let errors = $state<{ url: string | null; apiKey: string | null }>({ url: null, apiKey: null });

  async function save(e: SubmitEvent): Promise<void> {
    e.preventDefault();
    if (saving) return;
    const key = apiKey.trim();
    errors = {
      url: validateUrl(url),
      apiKey: !isEdit && key === '' ? 'Required' : null,
    };
    if (errors.url || errors.apiKey) return;

    saving = true;
    error = null;
    const u = normalizeUrl(url);
    const n = name.trim();

    // With a blank key on edit the backend re-tests using the stored one.
    if (key !== '') {
      try {
        await withTimeout(api.lidarrTest(u, key));
      } catch (err) {
        saving = false;
        error = friendlyLidarrError(errorOf(err));
        return;
      }
    }

    try {
      if (existing) {
        await withTimeout(api.lidarrUpdate({ ...existing, name: n, url: u }, key === '' ? null : key));
      } else {
        await api.lidarrAdd(n === '' ? u : n, u, key);
      }
      onclose(true);
    } catch (err) {
      saving = false;
      const ae = errorOf(err);
      error = isSaveError(ae) || key !== '' ? `Could not save the instance: ${ae.message}` : friendlyLidarrError(ae);
    }
  }
</script>

<Dialog title={isEdit ? 'Edit Lidarr Instance' : 'Add Lidarr Instance'} width={440} dismissible={false}>
  <form id="lidarr-form" class="form" onsubmit={save} novalidate>
    {#if error}<ErrorBanner message={error} />{/if}
    <TextField bind:value={name} label="Name" placeholder="Main, Podcasts…" />
    <TextField bind:value={url} label="Lidarr URL" placeholder="http://localhost:8686" autocapitalize="off" error={errors.url} />
    <SecretField
      bind:value={apiKey}
      label={isEdit ? 'API Key (leave blank to keep current)' : 'API Key'}
      error={errors.apiKey}
    />
  </form>
  {#snippet footer()}
    <Button variant="text" disabled={saving} onclick={() => onclose(false)}>Cancel</Button>
    <Button type="submit" form="lidarr-form" variant="primary" disabled={saving}>
      {#if saving}<Spinner size={14} />{:else}{isEdit ? 'Save' : 'Test & Add'}{/if}
    </Button>
  {/snippet}
</Dialog>

<style>
  .form {
    display: flex;
    flex-direction: column;
    gap: 12px;
    padding: 2px;
  }
</style>
