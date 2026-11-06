import { session } from './session.svelte';

/** selectedPlaylistIdProvider (sidebar_state.dart): the playlist whose detail the Playlists page shows. */
export const selectionNav = $state<{ selectedPlaylistId: string | null }>({ selectedPlaylistId: null });

// Playlist ids are server-scoped: a stale id from another server would only 404.
$effect.root(() => {
  let prev = session.serverId;
  $effect(() => {
    const id = session.serverId;
    if (id !== prev) {
      prev = id;
      selectionNav.selectedPlaylistId = null;
    }
  });
});
