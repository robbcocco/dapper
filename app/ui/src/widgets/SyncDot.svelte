<script lang="ts" module>
  /** Colours used with SyncDot across album/song views (Colors.* at 0.85 alpha). */
  export const syncColors = {
    queued: 'rgba(33, 150, 243, 0.85)',
    full: 'rgba(76, 175, 80, 0.85)',
    partial: 'rgba(255, 152, 0, 0.85)',
    absent: 'transparent',
  } as const;
  export type SyncState = keyof typeof syncColors;
</script>

<script lang="ts">
  /** Pass `state` (queued/full/partial/absent) or an explicit `color`; `pulse` for in-progress. */
  let { state, color, size = 7, pulse = false }: { state?: SyncState; color?: string; size?: number; pulse?: boolean } = $props();
</script>

{#if state !== 'absent'}
  <span class="dot" class:pulse style:width="{size}px" style:height="{size}px" style:background={color ?? syncColors[state ?? 'full']}></span>
{/if}

<style>
  .dot {
    display: inline-block;
    flex: none;
    border-radius: 50%;
  }
  .pulse {
    animation: pulse 0.9s ease-in-out infinite alternate;
  }
  @keyframes pulse {
    from {
      opacity: 0.35;
    }
    to {
      opacity: 1;
    }
  }
</style>
