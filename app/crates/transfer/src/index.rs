use std::collections::{BTreeMap, HashMap, HashSet};

use dapper_domain::{TransferStatus, TransferTask};
use indexmap::IndexMap;

struct Entry {
    task: TransferTask,
    seq: u64,
}

/// Queue in display order with O(1) lookup by id plus secondary indexes the
/// engine needs on every pick: ready tasks per device in queue order, ids per
/// status, and members per zip group. Every mutation goes through
/// [`TaskIndex::update`] so the indexes never drift from the tasks.
#[derive(Default)]
pub(crate) struct TaskIndex {
    tasks: IndexMap<String, Entry>,
    next_seq: u64,
    ready: HashMap<String, BTreeMap<u64, String>>,
    by_status: HashMap<TransferStatus, HashSet<String>>,
    groups: HashMap<String, Vec<String>>,
}

/// Status before and after a mutation.
#[derive(Clone, Copy)]
pub(crate) struct Transition {
    pub from: TransferStatus,
    pub to: TransferStatus,
}

pub(crate) fn is_terminal(s: TransferStatus) -> bool {
    matches!(
        s,
        TransferStatus::Completed | TransferStatus::Failed | TransferStatus::Cancelled
    )
}

// Per-song tasks are always ready when queued; zip followers wait for their
// leader, which downloads the whole group.
fn is_ready(t: &TransferTask) -> bool {
    t.status == TransferStatus::Queued && (!t.is_zip_member() || t.is_zip_leader())
}

impl TaskIndex {
    pub fn from_tasks(tasks: Vec<TransferTask>) -> Self {
        let mut idx = Self::default();
        for t in tasks {
            idx.push(t);
        }
        idx
    }

    pub fn push(&mut self, task: TransferTask) {
        let seq = self.next_seq;
        self.next_seq += 1;
        let id = task.id.clone();
        self.index(&task, seq);
        self.tasks.insert(id, Entry { task, seq });
    }

    fn index(&mut self, t: &TransferTask, seq: u64) {
        if is_ready(t) {
            self.ready
                .entry(t.device_path.clone())
                .or_default()
                .insert(seq, t.id.clone());
        }
        self.by_status
            .entry(t.status)
            .or_default()
            .insert(t.id.clone());
        if let Some(g) = &t.zip_group_id {
            self.groups.entry(g.clone()).or_default().push(t.id.clone());
        }
    }

    fn unindex(&mut self, t: &TransferTask, seq: u64) {
        if is_ready(t)
            && let Some(m) = self.ready.get_mut(&t.device_path)
        {
            m.remove(&seq);
            if m.is_empty() {
                self.ready.remove(&t.device_path);
            }
        }
        if let Some(s) = self.by_status.get_mut(&t.status) {
            s.remove(&t.id);
        }
        if let Some(g) = &t.zip_group_id
            && let Some(members) = self.groups.get_mut(g)
        {
            members.retain(|m| m != &t.id);
            if members.is_empty() {
                self.groups.remove(g);
            }
        }
    }

    pub fn get(&self, id: &str) -> Option<&TransferTask> {
        self.tasks.get(id).map(|e| &e.task)
    }

    pub fn status(&self, id: &str) -> Option<TransferStatus> {
        self.get(id).map(|t| t.status)
    }

    /// Applies `f` to task `id`, keeping every index consistent.
    pub fn update(&mut self, id: &str, f: impl FnOnce(&mut TransferTask)) -> Option<Transition> {
        let entry = self.tasks.get(id)?;
        let seq = entry.seq;
        let old = entry.task.clone();
        self.unindex(&old, seq);
        let entry = self.tasks.get_mut(id)?;
        f(&mut entry.task);
        let new = entry.task.clone();
        self.index(&new, seq);
        Some(Transition {
            from: old.status,
            to: new.status,
        })
    }

    pub fn remove(&mut self, id: &str) -> Option<TransferTask> {
        let entry = self.tasks.shift_remove(id)?;
        self.unindex(&entry.task, entry.seq);
        Some(entry.task)
    }

    pub fn ids_with_status(&self, s: TransferStatus) -> Vec<String> {
        self.by_status
            .get(&s)
            .map(|set| set.iter().cloned().collect())
            .unwrap_or_default()
    }

    pub fn group_members(&self, group_id: &str) -> Vec<String> {
        self.groups.get(group_id).cloned().unwrap_or_default()
    }

    pub fn first_ready(&self, device: &str) -> Option<&str> {
        self.ready
            .get(device)
            .and_then(|m| m.values().next())
            .map(String::as_str)
    }

    pub fn has_ready(&self, device: &str) -> bool {
        self.ready.contains_key(device)
    }

    pub fn ready_devices(&self) -> Vec<String> {
        self.ready.keys().cloned().collect()
    }

    pub fn iter(&self) -> impl Iterator<Item = &TransferTask> {
        self.tasks.values().map(|e| &e.task)
    }

    pub fn snapshot(&self) -> Vec<TransferTask> {
        self.iter().cloned().collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use dapper_domain::Song;

    fn task(id: &str, dev: &str) -> TransferTask {
        TransferTask::new(
            id,
            Song {
                id: id.into(),
                ..Default::default()
            },
            dev,
        )
    }

    #[test]
    fn ready_follows_queue_order_and_status() {
        let mut idx = TaskIndex::default();
        idx.push(task("a", "d"));
        idx.push(task("b", "d"));
        let mut follower = task("c", "d");
        follower.zip_group_id = Some("g".into());
        idx.push(follower);
        assert_eq!(idx.first_ready("d"), Some("a"));
        idx.update("a", |t| t.status = TransferStatus::InProgress);
        assert_eq!(idx.first_ready("d"), Some("b"));
        idx.update("b", |t| t.status = TransferStatus::Failed);
        assert!(!idx.has_ready("d"));
        assert_eq!(idx.group_members("g"), vec!["c".to_string()]);
        idx.update("c", |t| t.zip_group_id = None);
        assert_eq!(idx.first_ready("d"), Some("c"));
        assert!(idx.group_members("g").is_empty());
        // Retried tasks keep their original queue position.
        idx.update("b", |t| t.status = TransferStatus::Queued);
        assert_eq!(idx.first_ready("d"), Some("b"));
        assert_eq!(
            idx.ids_with_status(TransferStatus::InProgress),
            vec!["a".to_string()]
        );
        idx.remove("b");
        assert_eq!(idx.first_ready("d"), Some("c"));
        assert_eq!(idx.snapshot().len(), 2);
    }
}
