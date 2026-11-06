import { mount, unmount, type Component, type ComponentProps } from 'svelte';
import type { Album, ConnectedDevice, Song } from '../../lib/types';
import AddToPlaylistDialog from './AddToPlaylistDialog.svelte';
import AlbumInfoDialog from './AlbumInfoDialog.svelte';
import DevicePickerDialog from './DevicePickerDialog.svelte';
import SongMetadataDialog from './SongMetadataDialog.svelte';

/** Mounts a dialog on <body>; resolves with what it reports via `onresult`, then unmounts it. */
function show<P extends { onresult: (r: R) => void }, R>(component: Component<P>, props: Omit<P, 'onresult'>): Promise<R> {
  return new Promise((resolve) => {
    const target = document.createElement('div');
    document.body.appendChild(target);
    const app = mount(component, {
      target,
      props: {
        ...props,
        onresult: (r: R) => {
          void unmount(app).then(() => target.remove());
          resolve(r);
        },
      } as P,
    });
  });
}

export function showAddToPlaylistDialog(songIds: string[]): void {
  if (songIds.length === 0) return;
  void show<ComponentProps<typeof AddToPlaylistDialog>, null>(AddToPlaylistDialog, { songIds });
}

export function showSongMetadataDialog(song: Song): void {
  void show<ComponentProps<typeof SongMetadataDialog>, null>(SongMetadataDialog, { song });
}

export function showAlbumInfoDialog(album: Album): void {
  void show<ComponentProps<typeof AlbumInfoDialog>, null>(AlbumInfoDialog, { album });
}

/** `_pickDevicePath`: none → null, one → it, several → "Choose device" dialog. */
export function pickDevicePath(devices: ConnectedDevice[]): Promise<string | null> {
  if (devices.length === 0) return Promise.resolve(null);
  if (devices.length === 1) return Promise.resolve(devices[0]!.path);
  return show<ComponentProps<typeof DevicePickerDialog>, string | null>(DevicePickerDialog, { devices });
}
