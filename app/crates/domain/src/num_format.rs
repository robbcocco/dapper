/// Dart `double.toStringAsFixed`: exact binary ties round away from zero,
/// where Rust's formatter rounds them to even.
pub fn to_string_as_fixed(x: f64, digits: usize) -> String {
    let scale = 10f64.powi(digits as i32);
    let scaled = x * scale;
    if scaled.is_finite() && (scaled - scaled.trunc()).abs() == 0.5 && scaled / scale == x {
        let rounded = scaled.round() / scale;
        return format!("{rounded:.digits$}");
    }
    format!("{x:.digits$}")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ties_round_away_from_zero() {
        assert_eq!(to_string_as_fixed(2.5, 0), "3");
        assert_eq!(to_string_as_fixed(0.25, 1), "0.3");
        assert_eq!(to_string_as_fixed(1.234, 1), "1.2");
        assert_eq!(to_string_as_fixed(100.0, 1), "100.0");
    }
}
