<script lang="ts">
  import { untrack } from 'svelte';
  import * as api from '../../lib/api';
  import type { NavidromeServer } from '../../lib/types';
  import Button from '../../widgets/Button.svelte';
  import Dialog from '../../widgets/Dialog.svelte';
  import Spinner from '../../widgets/Spinner.svelte';
  import TextField from '../../widgets/TextField.svelte';
  import ErrorBanner from '../../widgets/forms/ErrorBanner.svelte';
  import SecretField from '../../widgets/forms/SecretField.svelte';
  import { errorOf, friendlyServerError, isSaveError, normalizeUrl, validateUrl, withTimeout } from './connection';

  let { existing = null, onclose }: { existing?: NavidromeServer | null; onclose: (saved: boolean) => void } = $props();

  // The form edits a snapshot; the dialog is re-mounted per open.
  const initial = untrack(() => existing);
  const isEdit = initial !== null;
  let name = $state(initial?.name ?? '');
  let url = $state(initial?.url ?? '');
  let username = $state(initial?.username ?? '');
  let password = $state('');
  let saving = $state(false);
  let error = $state<string | null>(null);
  let errors = $state<{ url: string | null; username: string | null; password: string | null }>({
    url: null,
    username: null,
    password: null,
  });

  async function save(e?: SubmitEvent): Promise<void> {
    e?.preventDefault();
    if (saving) return;
    errors = {
      url: validateUrl(url),
      username: username.trim() === '' ? 'Required' : null,
      password: !isEdit && password === '' ? 'Required' : null,
    };
    if (errors.url || errors.username || errors.password) return;

    saving = true;
    error = null;
    const u = normalizeUrl(url);
    const user = username.trim();
    const n = name.trim();

    // With a blank password on edit the backend re-tests using the stored one.
    if (password !== '') {
      try {
        await withTimeout(api.serverTest(u, user, password));
      } catch (err) {
        saving = false;
        error = friendlyServerError(errorOf(err), ': ');
        return;
      }
    }

    try {
      if (existing) {
        await withTimeout(api.serverUpdate(existing.id, n, u, user, password === '' ? null : password));
      } else {
        await api.serverAdd(n === '' ? u : n, u, user, password);
      }
      onclose(true);
    } catch (err) {
      saving = false;
      const ae = errorOf(err);
      error =
        isSaveError(ae) || password !== ''
          ? `Could not save the server: ${ae.message}`
          : friendlyServerError(ae, ': ');
    }
  }
</script>

<Dialog title={isEdit ? 'Edit Server' : 'Add Server'} width={440} dismissible={false}>
  <form id="server-form" class="form" onsubmit={save} novalidate>
    {#if error}<ErrorBanner message={error} />{/if}
    <TextField bind:value={name} label="Name" placeholder="Home, Work…" />
    <TextField bind:value={url} label="Server URL" placeholder="https://music.example.com" autocapitalize="off" error={errors.url} />
    <TextField bind:value={username} label="Username" autocapitalize="off" error={errors.username} />
    <SecretField
      bind:value={password}
      label={isEdit ? 'Password (leave blank to keep current)' : 'Password'}
      error={errors.password}
    />
  </form>
  {#snippet footer()}
    <Button variant="text" disabled={saving} onclick={() => onclose(false)}>Cancel</Button>
    <Button type="submit" form="server-form" variant="primary" disabled={saving}>
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
