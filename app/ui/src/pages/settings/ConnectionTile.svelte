<script lang="ts">
  import Button from '../../widgets/Button.svelte';
  import IconButton from '../../widgets/IconButton.svelte';

  /** Server / Lidarr instance row (_ServerTile / _LidarrInstanceTile). */
  let {
    name,
    lines,
    active,
    onconnect,
    onedit,
    onremove,
  }: {
    name: string;
    lines: string[];
    active: boolean;
    onconnect: () => void;
    onedit: () => void;
    onremove: () => void;
  } = $props();
</script>

<div class="tile" class:active>
  <div class="text">
    <div class="title">
      <span class="name">{name}</span>
      {#if active}<span class="badge">Active</span>{/if}
    </div>
    {#each lines as line, i (i)}
      <div class="line">{line}</div>
    {/each}
  </div>
  {#if !active}
    <Button variant="text" small onclick={onconnect}>Connect</Button>
  {/if}
  <IconButton icon="edit" size={14} label="Edit" color="var(--color-text-secondary)" onclick={onedit} />
  <IconButton icon="delete" size={14} label="Remove" color="var(--color-text-secondary)" onclick={onremove} />
</div>

<style>
  .tile {
    display: flex;
    align-items: center;
    gap: 4px;
    margin-bottom: 8px;
    padding: 12px 12px 12px 16px;
    border-radius: 8px;
    background: var(--color-surface-variant);
    border: 1px solid var(--color-glass-border);
  }
  .active {
    background: rgba(10, 132, 255, 0.08);
    border-color: rgba(10, 132, 255, 0.3);
  }
  .text {
    flex: 1;
    min-width: 0;
    margin-right: 4px;
  }
  .title {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-bottom: 2px;
  }
  .name {
    font-size: 13px;
    font-weight: 500;
  }
  .badge {
    padding: 2px 6px;
    border-radius: 8px;
    background: rgba(76, 175, 80, 0.15);
    color: #4caf50;
    font-size: 10px;
  }
  .line {
    font-size: 11px;
    color: var(--color-text-secondary);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
</style>
