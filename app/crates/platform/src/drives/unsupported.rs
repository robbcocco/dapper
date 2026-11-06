use dapper_domain::{AppError, ConnectedDevice, EjectResult, Result};
use tokio::sync::watch;

const UNSUPPORTED: &str = "Drive detection not supported on this platform";

pub(super) enum Detector {}

impl Detector {
    pub fn new() -> Result<Self> {
        Err(AppError::Other(UNSUPPORTED.into()))
    }

    pub fn list(&self) -> Vec<ConnectedDevice> {
        match *self {}
    }

    pub fn watch(&self) -> watch::Receiver<Vec<ConnectedDevice>> {
        match *self {}
    }
}

pub(super) async fn eject(_: &str) -> EjectResult {
    EjectResult::failed(UNSUPPORTED)
}
