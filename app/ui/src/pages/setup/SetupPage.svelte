<script lang="ts">
  import * as api from '../../lib/api';
  import Button from '../../widgets/Button.svelte';
  import Spinner from '../../widgets/Spinner.svelte';
  import TextField from '../../widgets/TextField.svelte';
  import ErrorBanner from '../../widgets/forms/ErrorBanner.svelte';
  import SecretField from '../../widgets/forms/SecretField.svelte';
  import { errorOf, friendlyServerError, normalizeUrl, validateUrl, withTimeout } from '../settings/connection';

  let url = $state('');
  let username = $state('');
  let password = $state('');
  let connecting = $state(false);
  let error = $state<string | null>(null);
  let errors = $state<{ url: string | null; username: string | null; password: string | null }>({
    url: null,
    username: null,
    password: null,
  });

  async function connect(e: SubmitEvent): Promise<void> {
    e.preventDefault();
    if (connecting) return;
    errors = {
      url: validateUrl(url),
      username: username.trim() === '' ? 'Required' : null,
      password: password === '' ? 'Required' : null,
    };
    if (errors.url || errors.username || errors.password) return;

    connecting = true;
    error = null;
    const u = normalizeUrl(url);
    const user = username.trim();
    try {
      await withTimeout(api.serverTest(u, user, password));
    } catch (err) {
      connecting = false;
      error = friendlyServerError(errorOf(err), '. ');
      return;
    }

    let host = '';
    try {
      host = new URL(u).hostname;
    } catch {
      host = '';
    }
    try {
      // The shell swaps to the library once `server-changed` lands. Reset the
      // spinner anyway so it can't get stuck if that stalls.
      await api.serverAdd(host || u, u, user, password);
      connecting = false;
    } catch (err) {
      connecting = false;
      error = `Could not save the server: ${errorOf(err).message}`;
    }
  }
</script>

<div class="setup">
  <div class="column">
    <h1>dapper</h1>
    <p class="tagline">Transfer music from Navidrome to your DAP</p>

    <form class="card" onsubmit={connect} novalidate>
      <h2>Connect to Navidrome</h2>

      {#if error}
        <ErrorBanner message={error} />
      {/if}

      <TextField
        bind:value={url}
        label="Server URL"
        placeholder="https://music.example.com"
        type="url"
        autocapitalize="off"
        error={errors.url}
      />
      <TextField bind:value={username} label="Username" autocapitalize="off" error={errors.username} />
      <SecretField bind:value={password} label="Password" error={errors.password} />

      <div class="connect">
        <Button type="submit" variant="primary" disabled={connecting}>
          {#if connecting}<Spinner size={16} />{:else}Connect{/if}
        </Button>
      </div>
    </form>

    <p class="footer">Lidarr and other options can be configured later in Settings.</p>
  </div>
</div>

<style>
  .setup {
    position: fixed;
    inset: 0;
    overflow: auto;
    display: flex;
    background: var(--color-background);
    /* Clears the transparent macOS titlebar. */
    padding: 28px 32px 0;
  }
  .column {
    width: 400px;
    margin: auto;
    padding: 48px 0;
    display: flex;
    flex-direction: column;
    align-items: stretch;
  }
  h1 {
    margin: 0;
    text-align: center;
    font-size: 36px;
    font-weight: 700;
    letter-spacing: -1.5px;
  }
  .tagline {
    margin: 6px 0 40px;
    text-align: center;
    font-size: 13px;
    color: var(--color-text-secondary);
  }
  .card {
    display: flex;
    flex-direction: column;
    gap: 12px;
    padding: 28px;
    background: var(--color-surface);
    border: 1px solid var(--color-glass-border);
    border-radius: 12px;
    box-shadow: 0 6px 20px rgba(0, 0, 0, 0.2);
  }
  h2 {
    margin: 0 0 8px;
    font-size: 15px;
    font-weight: 600;
  }
  .connect {
    display: flex;
    flex-direction: column;
    margin-top: 12px;
  }
  .connect :global(button) {
    height: 44px;
    font-size: 14px;
    font-weight: 600;
  }
  .connect :global(svg) {
    color: #fff;
  }
  .footer {
    margin: 20px 0 0;
    text-align: center;
    font-size: 11px;
    color: var(--color-text-secondary);
  }
</style>
