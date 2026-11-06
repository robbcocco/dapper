use std::collections::HashMap;
use std::path::Path;

use dapper_domain::{AppError, Result};

use super::SecretBackend;

pub(super) fn native(_service: &str) -> Box<dyn SecretBackend> {
    Box::new(Unsupported)
}

struct Unsupported;

fn unsupported<T>() -> Result<T> {
    Err(AppError::Storage(
        "Secure storage is not supported on this platform".into(),
    ))
}

impl SecretBackend for Unsupported {
    fn get(&self, _key: &str) -> Result<Option<String>> {
        unsupported()
    }

    fn set(&self, _key: &str, _value: &str) -> Result<()> {
        unsupported()
    }

    fn delete(&self, _key: &str) -> Result<()> {
        unsupported()
    }
}

pub(super) fn read_legacy(_legacy_support_dir: &Path) -> Result<HashMap<String, String>> {
    Ok(HashMap::new())
}
