<script lang="ts">
  /** `value` in 0..1; null → indeterminate (LinearProgressIndicator). */
  let { value = null, height = 3, color = 'var(--color-accent)' }: { value?: number | null; height?: number; color?: string } = $props();
</script>

<div class="pb" style:height="{height}px" role="progressbar" aria-valuemin={0} aria-valuemax={1} aria-valuenow={value ?? undefined}>
  {#if value == null}
    <div class="ind" style:background={color}></div>
  {:else}
    <div class="fill" style:background={color} style:width="{Math.min(Math.max(value, 0), 1) * 100}%"></div>
  {/if}
</div>

<style>
  .pb {
    position: relative;
    width: 100%;
    overflow: hidden;
    border-radius: 2px;
    background: rgba(255, 255, 255, 0.1);
  }
  .fill {
    height: 100%;
    transition: width 0.2s linear;
  }
  .ind {
    position: absolute;
    top: 0;
    bottom: 0;
    width: 35%;
    animation: slide 1.2s ease-in-out infinite;
  }
  @keyframes slide {
    from {
      left: -35%;
    }
    to {
      left: 100%;
    }
  }
</style>
