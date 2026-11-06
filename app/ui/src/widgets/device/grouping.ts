// Port of lib/ui/widgets/transfer_queue_grouping.dart plus the per-row display
// helpers shared by the device page queue and the bottom-bar transfer popup.
import type { TransferProgress, TransferStatus, TransferTask } from '../../lib/types';

/** One queue row: a stand-alone task or the tasks sharing a `zipGroupId` (one album). */
export type QueueRow = { kind: 'single'; task: TransferTask } | { kind: 'group'; tasks: TransferTask[] };

/** Buckets by `zipGroupId`, ordered by first occurrence. */
export function buildQueueRows(queue: readonly TransferTask[]): QueueRow[] {
  const groups = new Map<string, TransferTask[]>();
  for (const t of queue) {
    if (t.zipGroupId === null) continue;
    const members = groups.get(t.zipGroupId);
    if (members) members.push(t);
    else groups.set(t.zipGroupId, [t]);
  }
  const rows: QueueRow[] = [];
  const seen = new Set<string>();
  for (const t of queue) {
    const gid = t.zipGroupId;
    if (gid === null) {
      rows.push({ kind: 'single', task: t });
      continue;
    }
    if (seen.has(gid)) continue;
    seen.add(gid);
    rows.push({ kind: 'group', tasks: groups.get(gid) ?? [t] });
  }
  return rows;
}

/** Reduces zip-group member statuses to one display status. */
export function aggregateStatus(tasks: Iterable<TransferTask>): TransferStatus {
  let hasFailed = false;
  let hasInProgress = false;
  let hasQueued = false;
  let hasCancelled = false;
  let allCompleted = true;
  for (const t of tasks) {
    if (t.status !== 'completed') allCompleted = false;
    if (t.status === 'failed') hasFailed = true;
    else if (t.status === 'inProgress') hasInProgress = true;
    else if (t.status === 'queued') hasQueued = true;
    else if (t.status === 'cancelled') hasCancelled = true;
  }
  if (hasFailed) return 'failed';
  if (hasInProgress) return 'inProgress';
  if (hasQueued) return 'queued';
  if (allCompleted) return 'completed';
  if (hasCancelled) return 'cancelled';
  return 'completed';
}

export interface GroupSummary {
  leader: TransferTask;
  artist: string;
  album: string;
  total: number;
  completed: number;
  status: TransferStatus;
  /** Task whose byte progress drives the bar (the zip leader mirrors onto members). */
  inProgressId: string | null;
  firstError: string | null;
}

export function summarizeGroup(group: readonly TransferTask[]): GroupSummary {
  const first = group[0];
  if (!first) throw new Error('empty transfer group');
  const leader = group.find((t) => t.zipSourceId !== null) ?? first;
  const song = leader.song;
  return {
    leader,
    artist: song.albumArtist ?? song.artist ?? 'Unknown artist',
    album: song.album ?? 'Unknown album',
    total: group.length,
    completed: group.filter((t) => t.status === 'completed').length,
    status: aggregateStatus(group),
    inProgressId: group.find((t) => t.status === 'inProgress')?.id ?? null,
    firstError: (group.find((t) => t.status === 'failed') ?? leader).errorMessage,
  };
}

const clamp01 = (v: number): number => Math.min(1, Math.max(0, v));

/** Group bar value; null = indeterminate. Combines finished songs with the in-flight bytes. */
export function groupProgress(g: GroupSummary, progress: TransferProgress): number | null {
  if (g.status === 'completed') return 1;
  if (g.status !== 'inProgress') return null;
  const bytes = g.inProgressId !== null ? progress[g.inProgressId] : undefined;
  if (bytes && bytes[1] > 0) return clamp01((g.completed + clamp01(bytes[0] / bytes[1])) / g.total);
  return g.total === 0 ? null : g.completed / g.total;
}

export function statusLabel(s: TransferStatus, error: string | null): string {
  switch (s) {
    case 'queued':
      return 'Waiting…';
    case 'inProgress':
      return '';
    case 'completed':
      return 'Done';
    case 'failed':
      return error === 'permission_denied' ? 'Permission denied' : (error ?? 'Failed');
    case 'cancelled':
      return 'Cancelled';
  }
}

export const isActive = (t: TransferTask): boolean => t.status === 'queued' || t.status === 'inProgress';
export const isFinished = (t: TransferTask): boolean =>
  t.status === 'completed' || t.status === 'cancelled' || t.status === 'failed';
