<script lang="ts">
  let { size = 20, stroke = 2 }: { size?: number; stroke?: number } = $props();
</script>

<svg class="sp" width={size} height={size} viewBox="0 0 24 24" role="progressbar" aria-label="Loading">
  <circle cx="12" cy="12" r={12 - stroke} fill="none" stroke="currentColor" stroke-width={(stroke * 24) / size} stroke-linecap="round" stroke-dasharray="45 100" />
</svg>

<style>
  .sp {
    flex: none;
    color: var(--color-text-secondary);
    animation: spin 0.9s linear infinite;
  }
  @keyframes spin {
    to {
      transform: rotate(360deg);
    }
  }
</style>
