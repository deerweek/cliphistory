import Foundation

/// Lightweight, dependency-free classifier used when recording text so the UI
/// can show a "链接" category/badge and filter by it. Kept in the core library
/// so it is unit-testable on any platform.
public enum ContentClassifier {
    public static func classify(_ text: String) -> ContentType {
        isLink(text) ? .link : .text
    }

    /// True when the whole string is a single URL / bare domain (no spaces).
    public static func isLink(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, s.count <= 2048 else { return false }
        guard !s.contains(where: { $0.isWhitespace || $0.isNewline }) else { return false }

        let lower = s.lowercased()
        for scheme in ["http://", "https://", "ftp://", "mailto:"] where lower.hasPrefix(scheme) {
            return true
        }
        return looksLikeBareDomain(s)
    }

    /// e.g. `github.com`, `example.co.uk/path?q=1` — a host with a dot and a
    /// letters-only TLD, followed optionally by a path.
    private static func looksLikeBareDomain(_ s: String) -> Bool {
        let host = s.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? s
        guard host.contains("."), !host.hasPrefix("."), !host.hasSuffix(".") else { return false }
        guard let lastDot = host.lastIndex(of: ".") else { return false }

        let tld = host[host.index(after: lastDot)...]
        guard tld.count >= 2, tld.allSatisfy({ $0.isLetter }) else { return false }

        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-:")
        return host.allSatisfy { allowed.contains($0) }
    }
}
