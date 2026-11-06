<script lang="ts">
  import { icons, type IconName } from './icons';

  let { name, size = 16, color = 'currentColor', title }: { name: IconName; size?: number; color?: string; title?: string } = $props();
</script>

<svg
  width={size}
  height={size}
  viewBox="0 0 24 24"
  fill={color}
  role={title ? 'img' : undefined}
  aria-hidden={title ? undefined : true}
  aria-label={title}
  style="flex:none;display:block"><path d={icons[name]} /></svg>
