<script lang="ts">
  /** Thin 2px-track slider (bottom-bar seek/volume). onChange fires while dragging, onChangeEnd on release. */
  let {
    value,
    min = 0,
    max = 1,
    step = 0.001,
    disabled = false,
    label,
    onChange,
    onChangeEnd,
  }: {
    value: number;
    min?: number;
    max?: number;
    step?: number;
    disabled?: boolean;
    label?: string;
    onChange?: (v: number) => void;
    onChangeEnd?: (v: number) => void;
  } = $props();

  const pct = $derived(max > min ? ((Math.min(Math.max(value, min), max) - min) / (max - min)) * 100 : 0);
</script>

<input
  type="range"
  class="sl"
  {min}
  {max}
  {step}
  {value}
  {disabled}
  aria-label={label}
  style:--pct="{pct}%"
  oninput={(e) => onChange?.(e.currentTarget.valueAsNumber)}
  onchange={(e) => onChangeEnd?.(e.currentTarget.valueAsNumber)}
/>

<style>
  .sl {
    appearance: none;
    -webkit-appearance: none;
    width: 100%;
    height: 14px;
    margin: 0;
    background: transparent;
  }
  .sl::-webkit-slider-runnable-track {
    height: 2px;
    border-radius: 1px;
    background: linear-gradient(to right, var(--color-text-primary) var(--pct), rgba(255, 255, 255, 0.2) var(--pct));
  }
  .sl::-webkit-slider-thumb {
    -webkit-appearance: none;
    width: 10px;
    height: 10px;
    margin-top: -4px;
    border-radius: 50%;
    background: #fff;
    opacity: 0;
    transition: opacity 0.1s;
  }
  .sl:hover::-webkit-slider-thumb,
  .sl:active::-webkit-slider-thumb,
  .sl:focus-visible::-webkit-slider-thumb {
    opacity: 1;
  }
  .sl:disabled {
    opacity: 0.4;
  }
  .sl:focus {
    outline: none;
  }
</style>
