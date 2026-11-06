//! Per-device transfer engine: parallel downloads into local staging, FLAC
//! post-processing there, and one sequential writer per device.

mod engine;
mod fsops;
mod index;
mod service;

pub use service::{QueueItemStatus, TransferDeps, TransferService};

#[cfg(test)]
mod tests;
