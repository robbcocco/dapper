<script lang="ts" module>
  // Material glyphs the shared icon set lacks (play/pause circle, volume_down).
  const paths = {
    play_circle: 'M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 14.5v-9l6 4.5-6 4.5z',
    pause_circle: 'M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-1 14H9V8h2v8zm4 0h-2V8h2v8z',
    volume_down: 'M18.5 12c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02zM5 9v6h4l5 5V4L9 9H5z',
  } as const;
  export type GlyphName = keyof typeof paths;
</script>

<script lang="ts">
  let { name, size = 16 }: { name: GlyphName; size?: number } = $props();
</script>

<svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor" aria-hidden="true" style="flex:none;display:block"
  ><path d={paths[name]} /></svg
>
