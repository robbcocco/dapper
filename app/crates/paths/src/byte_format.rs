/// Human-readable byte size: B / KB / MB / GB with adaptive precision.
pub fn format_bytes(bytes: i64) -> String {
    const K: i64 = 1024;
    if bytes < K {
        format!("{bytes} B")
    } else if bytes < K * K {
        format!("{} KB", to_fixed(bytes, 10, 1))
    } else if bytes < K * K * K {
        format!("{} MB", to_fixed(bytes, 20, 1))
    } else {
        format!("{} GB", to_fixed(bytes, 30, 2))
    }
}

/// Dart `(bytes / 2^shift).toStringAsFixed(digits)` for positive `bytes`.
/// Dart rounds exact ties away from zero (Rust's formatter rounds them to
/// even), so this works on the exact value of the double.
fn to_fixed(bytes: i64, shift: u32, digits: u32) -> String {
    // The int → double conversion is the only rounding Dart performs before
    // the (exact) power-of-two division.
    let num = bytes as f64 as u128 * 10u128.pow(digits);
    let den = 1u128 << shift;
    let n = (2 * num + den) / (2 * den);
    let scale = 10u128.pow(digits);
    format!("{}.{:0width$}", n / scale, n % scale, width = digits as usize)
}

#[cfg(test)]
mod tests {
    use super::format_bytes;

    #[test]
    fn bytes() {
        assert_eq!(format_bytes(0), "0 B");
        assert_eq!(format_bytes(512), "512 B");
        assert_eq!(format_bytes(1023), "1023 B");
    }

    #[test]
    fn kb() {
        assert_eq!(format_bytes(1024), "1.0 KB");
        assert_eq!(format_bytes(1536), "1.5 KB");
        // 1.25 exactly: Dart rounds the tie up.
        assert_eq!(format_bytes(1280), "1.3 KB");
    }

    #[test]
    fn mb() {
        assert_eq!(format_bytes(1024 * 1024), "1.0 MB");
        assert_eq!(format_bytes(5 * 1024 * 1024 + 512 * 1024), "5.5 MB");
    }

    #[test]
    fn gb() {
        assert_eq!(format_bytes(1024 * 1024 * 1024), "1.00 GB");
        assert_eq!(format_bytes(3 * 1024 * 1024 * 1024), "3.00 GB");
    }

    #[test]
    fn boundaries() {
        assert!(format_bytes(1024 * 1024 - 1).ends_with("KB"));
        assert!(format_bytes(1024 * 1024).ends_with("MB"));
    }
}
