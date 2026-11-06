// Port of lib/ui/widgets/device_eject.dart `ejectConnectedDevice`.
import * as api from '../../lib/api';
import { toAppError } from '../../lib/ipc';
import { toast } from '../../lib/stores/toast.svelte';
import { confirm } from '../dialogs';
import { isActive } from './grouping';
import { transfers } from './transfers.svelte';

/** Unmounts `path`, first offering to cancel its queued/in-flight transfers; reports via toast. */
export async function ejectDevice(path: string): Promise<void> {
  if (transfers.tasks.some((t) => t.devicePath === path && isActive(t))) {
    const ok = await confirm({
      title: 'Eject anyway?',
      message: 'Transfers are still queued or in progress for this device. Ejecting now will cancel them.',
      confirmLabel: 'Cancel & eject',
      destructive: true,
    });
    if (!ok) return;
    try {
      await api.transferCancelAll(path);
    } catch (e) {
      toast(`Eject failed: ${toAppError(e).message}`, { kind: 'error', duration: 3000 });
      return;
    }
  }
  try {
    const result = await api.deviceEject(path);
    toast(result.success ? `Ejected ${path}` : `Eject failed: ${result.error ?? 'unknown error'}`, {
      kind: result.success ? 'info' : 'error',
      duration: 3000,
    });
  } catch (e) {
    toast(`Eject failed: ${toAppError(e).message}`, { kind: 'error', duration: 3000 });
  }
}
