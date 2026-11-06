<script lang="ts">
  import NowPlaying from './bottom/NowPlaying.svelte';
  import PlayerControls from './bottom/PlayerControls.svelte';
  import RightPanel from './bottom/RightPanel.svelte';
</script>

<div class="bar">
  <div class="pane" style:flex="3"><NowPlaying /></div>
  <div class="rule"></div>
  <div class="pane" style:flex="5"><PlayerControls /></div>
  <div class="rule"></div>
  <div class="pane" style:flex="3"><RightPanel /></div>
</div>

<style>
  .bar {
    height: 100%;
    display: flex;
  }
  .pane {
    min-width: 0;
    flex-basis: 0;
  }
  .rule {
    flex: none;
    width: 1px;
    background: var(--color-glass-border);
  }
</style>
