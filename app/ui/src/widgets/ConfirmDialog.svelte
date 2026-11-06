<script lang="ts">
  import Dialog from './Dialog.svelte';
  import Button from './Button.svelte';

  let {
    title,
    message,
    confirmLabel = 'Confirm',
    cancelLabel = 'Cancel',
    destructive = false,
    onresult,
  }: {
    title: string;
    message: string;
    confirmLabel?: string;
    cancelLabel?: string;
    destructive?: boolean;
    onresult: (ok: boolean) => void;
  } = $props();
</script>

<Dialog {title} onclose={() => onresult(false)}>
  <p>{message}</p>
  {#snippet footer()}
    <Button onclick={() => onresult(false)}>{cancelLabel}</Button>
    <Button variant={destructive ? 'destructive' : 'primary'} autofocus onclick={() => onresult(true)}>{confirmLabel}</Button>
  {/snippet}
</Dialog>

<style>
  p {
    margin: 0;
    white-space: pre-wrap;
  }
</style>
