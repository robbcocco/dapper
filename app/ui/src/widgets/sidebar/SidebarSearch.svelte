<script lang="ts">
  import { untrack } from 'svelte';
  import TextField from '../TextField.svelte';
  import { search } from '../../lib/stores/search.svelte';

  // Debounce the shared query so each keystroke doesn't run a search; only the
  // last keystroke in a ~300 ms window actually searches.
  let text = $state(untrack(() => search.query));
  let timer: ReturnType<typeof setTimeout> | undefined;

  function oninput(e: Event & { currentTarget: HTMLInputElement }): void {
    clearTimeout(timer);
    const v = e.currentTarget.value;
    timer = setTimeout(() => (search.query = v), 300);
  }

  function onclear(): void {
    clearTimeout(timer);
    search.query = '';
  }

  // Mirror external clears (Esc, sidebar navigation) into the field.
  let prev = untrack(() => search.query);
  $effect(() => {
    const q = search.query;
    if (q === prev) return;
    prev = q;
    if (q === '') {
      untrack(() => {
        if (text !== '') {
          clearTimeout(timer);
          text = '';
        }
      });
    }
  });

  let inputEl = $state<HTMLInputElement>();
  $effect(() => {
    search.input = inputEl ?? null;
    return () => (search.input = null);
  });

  $effect(() => () => clearTimeout(timer));
</script>

<div class="search">
  <TextField search bind:value={text} bind:input={inputEl} placeholder="Search…" {oninput} {onclear} />
</div>

<style>
  .search {
    padding: 8px 10px 4px;
    font-size: 12px;
  }
</style>
