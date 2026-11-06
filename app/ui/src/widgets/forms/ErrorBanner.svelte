<script lang="ts">
  import Icon from '../Icon.svelte';

  let { message }: { message: string } = $props();
</script>

<div class="banner" role="alert">
  <Icon name="error" size={14} />
  <span>{message}</span>
</div>

<style>
  .banner {
    display: flex;
    align-items: flex-start;
    gap: 8px;
    padding: 9px 12px;
    border-radius: 6px;
    background: rgba(255, 82, 82, 0.08);
    border: 1px solid rgba(255, 82, 82, 0.3);
    color: #ff5252;
    font-size: 12px;
    line-height: 1.4;
    user-select: text;
    -webkit-user-select: text;
  }
  .banner :global(svg) {
    margin-top: 1px;
  }
</style>
