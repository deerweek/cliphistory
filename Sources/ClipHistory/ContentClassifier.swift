import Foundation

/// Lightweight, dependency-free classifier used when recording text so the UI
/// can show category badges, smart archive tags, language detection, code formatting,
/// link hosts, and color swatches. Kept in the core library so it is unit-testable.
public enum ContentClassifier {
    public static func classify(_ text: String) -> ContentType {
        isLink(text) ? .link : .text
    }

    /// Classifies text into a semantic `SmartArchiveTag` for automatic archiving.
    public static func classifySmartTag(_ text: String, contentType: ContentType? = nil) -> SmartArchiveTag {
        let resolvedType = contentType ?? classify(text)
        if resolvedType != .text { return .general }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .general }

        if isCredentialOrCodeToken(trimmed) {
            return .credential
        }
        if isCodeLike(trimmed) {
            return .codeCommand
        }
        if isAddressOrContact(trimmed) {
            return .addressContact
        }
        if looksLikeForeignText(trimmed) {
            return .foreignText
        }
        if isWorkChatMessage(trimmed) {
            return .workChat
        }
        return .general
    }

    /// True when the string is a URL/domain or a share message containing an embedded URL.
    public static func isLink(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, s.count <= 2048 else { return false }

        // If the entire string has no spaces, check direct scheme or bare domain
        if !s.contains(where: { $0.isWhitespace || $0.isNewline }) {
            let lower = s.lowercased()
            for scheme in ["http://", "https://", "ftp://", "mailto:"] where lower.hasPrefix(scheme) {
                return true
            }
            if looksLikeBareDomain(s) {
                return true
            }
        }

        // If the text has prefix/suffix words (e.g. "【分享】https://example.com 点击查看"),
        // recognize it as a link as long as it is not source code / shell commands.
        let lineCount = s.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
        guard s.count <= 800, lineCount <= 8, !isCodeLike(s) else { return false }
        return extractURL(s) != nil
    }

    /// Extracts the first valid URL (or bare domain) from `raw`, even when surrounded by Chinese or English share text.
    public static func extractURL(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, s.count <= 2048 else { return nil }

        // 1. Fast path for pure single-token URL or bare domain
        if !s.contains(where: { $0.isWhitespace || $0.isNewline }) {
            let lower = s.lowercased()
            for scheme in ["http://", "https://", "ftp://", "mailto:"] where lower.hasPrefix(scheme) {
                return trimTrailingURLPunctuation(s)
            }
            if looksLikeBareDomain(s) {
                return s
            }
        }

        // 2. Match explicit scheme URL (`http://`, `https://`, `ftp://`, `mailto:`) embedded anywhere in text
        let schemePattern = #"(?i)(?:https?://|ftp://|mailto:)[A-Za-z0-9\-._~:/?#\[\]@!$&'()*+,;=%]+"#
        if let regex = try? NSRegularExpression(pattern: schemePattern),
           let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..<s.endIndex, in: s)),
           let range = Range(match.range, in: s) {
            let candidate = trimTrailingURLPunctuation(String(s[range]))
            if candidate.count > 8 {
                return candidate
            }
        }

        // 3. Match `www.` or common bare domain embedded in short share text
        let domainPattern = #"(?i)(?<![A-Za-z0-9@/])(?:www\.[A-Za-z0-9\-]+\.[A-Za-z]{2,}|[A-Za-z0-9\-]+\.(?:com|cn|net|org|io|dev|ai|app|me|co|tv|cc|uk|jp|hk|tw|edu|gov)(?:\.[A-Za-z]{2,})?)(?:/[A-Za-z0-9\-._~:/?#\[\]@!$&()*+,;=%]*)?"#
        if let regex = try? NSRegularExpression(pattern: domainPattern),
           let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..<s.endIndex, in: s)),
           let range = Range(match.range, in: s) {
            let candidate = trimTrailingURLPunctuation(String(s[range]))
            if looksLikeBareDomain(candidate) {
                return candidate
            }
        }

        return nil
    }

    private static func trimTrailingURLPunctuation(_ url: String) -> String {
        let trailingChars = Set(".,;:!?'\"’”)>】」》")
        var result = url
        while let last = result.last, trailingChars.contains(last) {
            if last == ")" {
                let openCount = result.filter { $0 == "(" }.count
                let closeCount = result.filter { $0 == ")" }.count
                if closeCount <= openCount { break }
            }
            result.removeLast()
        }
        return result
    }

    /// Extracts a readable domain/host from a link string for display badges.
    public static func extractHost(_ raw: String) -> String? {
        guard let s = extractURL(raw) else { return nil }
        let lower = s.lowercased()
        if lower.hasPrefix("mailto:") {
            return String(s.dropFirst("mailto:".count))
        }
        var remainder = s[...]
        for scheme in ["https://", "http://", "ftp://"] where lower.hasPrefix(scheme) {
            remainder = s.dropFirst(scheme.count)
            break
        }
        let host = remainder.split(whereSeparator: { $0 == "/" || $0 == "?" || $0 == "#" }).first.map(String.init)
        guard let host, !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Detects whether text looks like source code, JSON, shell commands, or structured markup.
    public static func isCodeLike(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 12 else { return false }

        if (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) ||
           (trimmed.hasPrefix("[") && trimmed.hasSuffix("]") && trimmed.contains(":")) ||
           trimmed.hasPrefix("#!/") ||
           (trimmed.hasPrefix("<") && trimmed.hasSuffix(">") && trimmed.contains("</")) {
            return true
        }

        let codeKeywords = [
            "func ", "import ", "struct ", "class ", "enum ", "protocol ",
            "let ", "var ", "const ", "function ", "return ", "export ",
            "def ", "async ", "await ", "public ", "private ", "SELECT ",
            "FROM ", "WHERE ", "INSERT INTO", "git ", "docker ", "npm ", "brew ",
            "cd ", "curl ", "python", "swiftc "
        ]
        var score = 0
        for kw in codeKeywords where trimmed.contains(kw) {
            score += 1
            if score >= 2 { return true }
        }

        let symbolMarkers = [" -> ", " => ", " != ", " == ", " && ", " || ", "::", "();", "};"]
        for marker in symbolMarkers where trimmed.contains(marker) {
            score += 1
            if score >= 2 { return true }
        }

        let lines = raw.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        if lines.count >= 3 {
            let indentedLines = lines.filter { $0.hasPrefix("  ") || $0.hasPrefix("\t") }.count
            if indentedLines >= 2 && (trimmed.contains("{") || trimmed.contains(":") || trimmed.contains(";")) {
                return true
            }
        }
        return false
    }

    /// Detects API keys, JWTs, verification SMS codes, or tracking numbers.
    public static func isCredentialOrCodeToken(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        let tokenPrefixes = ["sk-", "ghp_", "gho_", "ak_", "eyjh", "xoxb-", "xoxp-", "bearer "]
        if tokenPrefixes.contains(where: { lower.hasPrefix($0) }) && !raw.contains(" ") {
            return true
        }
        let otpMarkers = ["验证码", "校验码", "动态码", "取件码", "快递单号", "运单号", "verification code", "otp", "passcode"]
        if otpMarkers.contains(where: { lower.contains($0) }) && raw.contains(where: \.isNumber) {
            return true
        }
        // Pure 4-8 digit verification code
        if (4...8).contains(raw.count) && raw.allSatisfy(\.isNumber) {
            return true
        }
        return false
    }

    /// Detects Chinese/English addresses, phone numbers, tax IDs, or contact cards.
    public static func isAddressOrContact(_ raw: String) -> Bool {
        let addressKeywords = [
            "省", "市", "区", "街道", "路", "号楼", "室", "大厦", "园区",
            "收件人", "收货人", "联系电话", "手机号", "纳税人识别号", "统一社会信用代码",
            "开户行", "发票抬头", "邮箱："
        ]
        var hits = 0
        for kw in addressKeywords where raw.contains(kw) {
            hits += 1
            if hits >= 2 { return true }
        }
        // Check for mainland 11-digit mobile number pattern (1[3-9]\d{9})
        let digitsOnly = raw.filter(\.isNumber)
        if digitsOnly.count == 11, digitsOnly.hasPrefix("1") {
            return true
        }
        return false
    }

    /// Detects whether text is primarily English / foreign natural language suitable for Chinese translation.
    public static func looksLikeForeignText(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 6, !isLink(trimmed), !isCodeLike(trimmed) else { return false }
        guard !containsChinese(trimmed) else { return false }

        let letters = trimmed.filter(\.isLetter)
        guard letters.count >= 5 else { return false }
        let asciiLetters = letters.filter(\.isASCII)
        let ratio = Double(asciiLetters.count) / Double(max(1, trimmed.count))
        // Natural English sentences have spaces and mostly ASCII letters
        return trimmed.contains(" ") && ratio >= 0.60
    }

    /// True if the text contains any CJK Unified Ideographs (Chinese characters).
    public static func containsChinese(_ raw: String) -> Bool {
        for scalar in raw.unicodeScalars {
            if (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value) {
                return true
            }
        }
        return false
    }

    public static func isWorkChatMessage(_ raw: String) -> Bool {
        let chatMarkers = ["请问", "你好", "您好", "麻烦", "收到", "谢谢", "发一下", "可以吗", "什么时候", "？", "?"]
        return chatMarkers.contains { raw.contains($0) }
    }

    /// Parses a standalone Hex color code (`#RGB`, `#RRGGBB`, or `0xRRGGBB`) into normalized RGB (0...1).
    public static func extractHexColor(_ raw: String) -> (r: Double, g: Double, b: Double, hex: String)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let hexBody: Substring
        if trimmed.hasPrefix("#") {
            hexBody = trimmed.dropFirst()
        } else if trimmed.lowercased().hasPrefix("0x") {
            hexBody = trimmed.dropFirst(2)
        } else {
            return nil
        }

        let expanded: String
        switch hexBody.count {
        case 3:
            expanded = hexBody.map { "\($0)\($0)" }.joined()
        case 6:
            expanded = String(hexBody)
        default:
            return nil
        }

        guard expanded.allSatisfy({ $0.isHexDigit }),
              let value = UInt32(expanded, radix: 16) else {
            return nil
        }

        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return (r, g, b, "#" + expanded.uppercased())
    }

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
