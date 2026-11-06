import type { UnlistenFn } from '@tauri-apps/api/event';
import * as api from '../api';
import type { ConnectedDevice, ScrobbleImportResult } from '../types';
import { selectedSection, SidebarSection } from './navigation.svelte';

/**
 * Connected removable drives (connectedDevicesProvider), the selected device
 * (selectedDeviceProvider) and the latest auto scrobble-log import result
 * (scrobbleImportResultProvider; the device page banner dismisses it).
 */
class DevicesStore {
  list = $state<ConnectedDevice[]>([]);
  selected = $state<ConnectedDevice | null>(null);
  scrobbleImport = $state<ScrobbleImportResult | null>(null);
  /** False until the first drive list arrives (StreamProvider loading). */
  loaded = $state(false);

  dismissScrobbleImport(): void {
    this.scrobbleImport = null;
  }
}

export const devices = new DevicesStore();

export function selectDevice(path: string | null): void {
  devices.selected = path === null ? null : (devices.list.find((d) => d.path === path) ?? null);
}

/** Port of app_shell.dart's connectedDevicesProvider listener. */
function applyDevices(list: ConnectedDevice[]): void {
  devices.list = list;
  devices.loaded = true;
  const selected = devices.selected;
  if (selected !== null) {
    const fresh = list.find((d) => d.path === selected.path);
    if (fresh === undefined) {
      devices.selected = null;
      // Navigate away so the sidebar doesn't orphan its selection highlight.
      if (selectedSection.value === SidebarSection.device) selectedSection.value = SidebarSection.recentlyAdded;
    } else if (
      // Refresh the stored object so availableBytes etc. stay current.
      fresh.label !== selected.label ||
      fresh.totalBytes !== selected.totalBytes ||
      fresh.availableBytes !== selected.availableBytes
    ) {
      devices.selected = fresh;
    }
  } else if (list.length === 1) {
    devices.selected = list[0]!;
  }
}

/** Loads the current drives and subscribes to device events; returns the unsubscriber. */
export function startDevicesSync(): () => void {
  let disposed = false;
  let pushed = false;
  const subs: Promise<UnlistenFn>[] = [
    api.onDevices((list) => {
      pushed = true;
      applyDevices(list);
    }),
    api.onScrobbleImport((r) => {
      devices.scrobbleImport = r;
    }),
  ];
  api
    .devicesList()
    .then((list) => {
      // An event that raced the initial fetch is newer; keep it.
      if (!disposed && !pushed) applyDevices(list);
    })
    .catch((e: unknown) => console.warn('devices: initial list failed', e));
  return () => {
    disposed = true;
    subs.forEach((s) => void s.then((un) => un()));
  };
}
