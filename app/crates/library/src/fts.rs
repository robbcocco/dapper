/// Turns free text into an FTS5 MATCH expression: every whitespace-separated
/// term must match (implicit AND, across any column) and each term is a
/// prefix. Terms are quoted so FTS5 operators and punctuation in user input
/// (`AC/DC`, `"`, `-`, `NOT`) are tokenised as plain text rather than parsed
/// as query syntax. Returns `None` when nothing searchable remains.
pub(crate) fn match_expr(query: &str) -> Option<String> {
    let terms: Vec<String> = query
        .split_whitespace()
        .filter(|t| t.chars().any(char::is_alphanumeric))
        .map(|t| format!("\"{}\"*", t.replace('"', "\"\"")))
        .collect();
    (!terms.is_empty()).then(|| terms.join(" "))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn builds_prefix_and_expression() {
        assert_eq!(match_expr("  abbey  road ").unwrap(), r#""abbey"* "road"*"#);
        assert_eq!(match_expr(r#"say "hi""#).unwrap(), r#""say"* """hi"""*"#);
        assert_eq!(match_expr("AC/DC").unwrap(), r#""AC/DC"*"#);
        assert_eq!(match_expr("NOT"), Some(r#""NOT"*"#.into()));
        assert_eq!(match_expr(" - * \" "), None);
        assert_eq!(match_expr(""), None);
    }
}
