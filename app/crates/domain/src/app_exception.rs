use serde::{Deserialize, Deserializer, Serialize, Serializer};

pub type Result<T> = std::result::Result<T, AppError>;

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum AppError {
    #[error("{0}")]
    Network(String),
    #[error("{message}")]
    Subsonic { message: String, code: i32 },
    #[error("Invalid credentials")]
    Auth,
    #[error("{0}")]
    NotFound(String),
    #[error("{0}")]
    Storage(String),
    #[error("{0}")]
    Io(String),
    #[error("Cancelled")]
    Cancelled,
    #[error("{0}")]
    Other(String),
}

impl AppError {
    pub fn kind(&self) -> &'static str {
        match self {
            Self::Network(_) => "network",
            Self::Subsonic { .. } => "subsonic",
            Self::Auth => "auth",
            Self::NotFound(_) => "notFound",
            Self::Storage(_) => "storage",
            Self::Io(_) => "io",
            Self::Cancelled => "cancelled",
            Self::Other(_) => "other",
        }
    }

    pub fn message(&self) -> String {
        self.to_string()
    }

    pub fn code(&self) -> Option<i32> {
        match self {
            Self::Subsonic { code, .. } => Some(*code),
            _ => None,
        }
    }
}

impl From<std::io::Error> for AppError {
    fn from(e: std::io::Error) -> Self {
        Self::Io(e.to_string())
    }
}

/// Wire shape for the UI: `{kind, message, code?}`.
#[derive(Serialize, Deserialize)]
struct Wire {
    kind: String,
    message: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    code: Option<i32>,
}

impl Serialize for AppError {
    fn serialize<S: Serializer>(&self, s: S) -> std::result::Result<S::Ok, S::Error> {
        Wire { kind: self.kind().into(), message: self.message(), code: self.code() }.serialize(s)
    }
}

impl<'de> Deserialize<'de> for AppError {
    fn deserialize<D: Deserializer<'de>>(d: D) -> std::result::Result<Self, D::Error> {
        let w = Wire::deserialize(d)?;
        Ok(match w.kind.as_str() {
            "network" => Self::Network(w.message),
            "subsonic" => Self::Subsonic { message: w.message, code: w.code.unwrap_or(0) },
            "auth" => Self::Auth,
            "notFound" => Self::NotFound(w.message),
            "storage" => Self::Storage(w.message),
            "io" => Self::Io(w.message),
            "cancelled" => Self::Cancelled,
            _ => Self::Other(w.message),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wire_roundtrip() {
        let e = AppError::Subsonic { message: "x".into(), code: 70 };
        let v = serde_json::to_value(&e).unwrap();
        assert_eq!(v, serde_json::json!({"kind": "subsonic", "message": "x", "code": 70}));
        assert_eq!(serde_json::from_value::<AppError>(v).unwrap(), e);
        assert_eq!(
            serde_json::to_value(AppError::Auth).unwrap(),
            serde_json::json!({"kind": "auth", "message": "Invalid credentials"})
        );
    }
}
