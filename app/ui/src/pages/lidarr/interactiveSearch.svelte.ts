import { mount, unmount } from 'svelte';
import InteractiveSearchSheet from './InteractiveSearchSheet.svelte';

/** showInteractiveSearchSheet port: mounts the release-search sheet on <body> until closed. */
export function showInteractiveSearch(albumId: number, albumTitle: string): void {
  const target = document.createElement('div');
  document.body.appendChild(target);
  const sheet = mount(InteractiveSearchSheet, {
    target,
    props: {
      albumId,
      albumTitle,
      onclose: () => void unmount(sheet).then(() => target.remove()),
    },
  });
}
