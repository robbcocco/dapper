<script lang="ts">
  let { label, color = 'var(--color-text-secondary)' }: { label: string; color?: string } = $props();
</script>

<span class="chip" style:color style:--chip={color}>{label}</span>

<style>
  .chip {
    flex: none;
    padding: 2px 6px;
    border-radius: 4px;
    font-size: 10px;
    white-space: nowrap;
    background: color-mix(in srgb, var(--chip) 12%, transparent);
  }
</style>
