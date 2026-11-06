<script lang="ts">
  import Dialog from './Dialog.svelte';
  import Button from './Button.svelte';
  import TextField from './TextField.svelte';

  let {
    title,
    message,
    label,
    placeholder,
    initial = '',
    confirmLabel = 'OK',
    cancelLabel = 'Cancel',
    onresult,
  }: {
    title: string;
    message?: string;
    label?: string;
    placeholder?: string;
    initial?: string;
    confirmLabel?: string;
    cancelLabel?: string;
    onresult: (value: string | null) => void;
  } = $props();

  // svelte-ignore state_referenced_locally
  let value = $state(initial);
  const valid = $derived(value.trim().length > 0);
  const submit = (): void => {
    if (valid) onresult(value.trim());
  };
</script>

<Dialog {title} onclose={() => onresult(null)}>
  {#if message}<p>{message}</p>{/if}
  <form
    onsubmit={(e) => {
      e.preventDefault();
      submit();
    }}
  >
    <TextField bind:value {label} {placeholder} autofocus />
  </form>
  {#snippet footer()}
    <Button onclick={() => onresult(null)}>{cancelLabel}</Button>
    <Button variant="primary" disabled={!valid} onclick={submit}>{confirmLabel}</Button>
  {/snippet}
</Dialog>

<style>
  p {
    margin: 0 0 10px;
  }
  form {
    padding: 2px;
  }
</style>
