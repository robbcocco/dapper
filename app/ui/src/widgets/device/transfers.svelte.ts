// App-lifetime mirror of the backend transfer queue (transferQueueProvider,
// transferProgressProvider, isAnyDevicePaused). Byte progress lives apart from the
// task list so ~5 Hz ticks only touch rows that read it.
import * as api from '../../lib/api';
import type { TransferProgress, TransferTask } from '../../lib/types';

class TransfersStore {
  tasks = $state.raw<TransferTask[]>([]);
  progress = $state.raw<TransferProgress>({});
  anyPaused = $state(false);

  /** queue.activeCount: queued + inProgress. */
  activeCount = $derived(this.tasks.reduce((n, t) => (t.status === 'queued' || t.status === 'inProgress' ? n + 1 : n), 0));

  constructor() {
    // Events win over the initial snapshot if they arrive first.
    let tasksSeen = false;
    let pausedSeen = false;
    void api.onTransferTasks((tasks) => {
      tasksSeen = true;
      this.tasks = tasks;
    });
    void api.onTransferProgress((p) => (this.progress = p));
    void api.onTransferPaused((p) => {
      pausedSeen = true;
      this.anyPaused = p.anyPaused;
    });
    void api.transferTasks().then((tasks) => {
      if (!tasksSeen) this.tasks = tasks;
    });
    void api.transferPaused().then((p) => {
      if (!pausedSeen) this.anyPaused = p.anyPaused;
    });
  }
}

export const transfers = new TransfersStore();
