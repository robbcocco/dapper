<script lang="ts">
  import Icon from '../../widgets/Icon.svelte';

  let { message, onretry, compact = false }: { message: string; onretry: () => void; compact?: boolean } = $props();
</script>

<div class="err" class:compact>
  <Icon name="cloud_off" size={compact ? 20 : 32} color="var(--color-text-secondary)" />
  <p>{message}</p>
  <button type="button" onclick={onretry}><Icon name="refresh" size={15} />Retry</button>
</div>

<style>
  .err {
    height: 100%;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    padding: 16px;
    text-align: center;
  }
  .compact {
    height: auto;
    align-items: flex-start;
    padding: 0;
    text-align: start;
  }
  p {
    margin: 8px 0 10px;
    font-size: 12px;
    color: var(--color-text-secondary);
  }
  button {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    padding: 4px 8px;
    border: none;
    border-radius: 6px;
    background: transparent;
    color: var(--color-accent);
    font: inherit;
    font-size: 12px;
  }
  button:hover {
    background: rgba(255, 255, 255, 0.06);
  }
</style>
