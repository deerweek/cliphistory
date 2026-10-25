import Foundation

/// Represents a calibrated decision returned by TypeSafe AI's Jev (System One) model
/// or the local fast-path fallback engine.
public struct JevDecisionResult: Sendable, Equatable {
    /// ID of the best matching snippet to reply with, if any.
    public var recommendedReplyID: Int64?
    /// Calibrated confidence (0.0 ... 1.0) for the recommended reply.
    public var replyConfidence: Double
    /// Recommended smart archive tag for the newly copied item.
    public var archiveTag: SmartArchiveTag
    /// Confidence in the archive classification.
    public var archiveConfidence: Double
    /// Suggested next action ID (e.g. "translate_zh", "format_json", "extract_code").
    public var suggestedActionID: String?
    /// Whether this decision came from the live Jev cloud model or the local engine.
    public var isFromJevModel: Bool

    public init(
        recommendedReplyID: Int64? = nil,
        replyConfidence: Double = 0,
        archiveTag: SmartArchiveTag = .general,
        archiveConfidence: Double = 0.8,
        suggestedActionID: String? = nil,
        isFromJevModel: Bool = false
    ) {
        self.recommendedReplyID = recommendedReplyID
        self.replyConfidence = replyConfidence
        self.archiveTag = archiveTag
        self.archiveConfidence = archiveConfidence
        self.suggestedActionID = suggestedActionID
        self.isFromJevModel = isFromJevModel
    }
}

/// Inspired by `metasequoiaime/chinese-ime-lm`:
/// 1. Exact-Match Guardrail: Exact matches on `triggerCode` or `title` are locked at the top
///    and never overridden by statistical or neural weights.
/// 2. Fast Path (<1ms): Character-level 1-gram & 2-gram overlap + logarithmic usage frequency
///    + context app affinity.
/// 3. Pause Path (~70ms): Calibrated Jev System-One probabilistic reranking.
public enum SmartRanker {

    /// Reranks items for a given search query and active target app.
    public static func rankItems(
        _ items: [ClipItem],
        query: String,
        targetAppBundleID: String? = nil,
        now: Date = Date()
    ) -> [ClipItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // When query is empty, preserve priority tiers (Pinned -> Snippets -> History),
        // and within each tier sort by updatedAt DESC, id DESC so newly copied items
        // are always immediately at the top of History.
        if trimmedQuery.isEmpty {
            return items.sorted { lhs, rhs in
                let tierL = priorityTier(lhs)
                let tierR = priorityTier(rhs)
                if tierL != tierR { return tierL < tierR }

                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.id > rhs.id
            }
        }

        // When query is non-empty: apply `chinese-ime-lm` Exact-Match Guardrail first,
        // followed by character N-gram + usage score.
        let queryBigrams = characterNGrams(trimmedQuery, n: 2)
        let queryUnigrams = Set(trimmedQuery)

        let scored: [(item: ClipItem, tier: Int, score: Double)] = items.map { item in
            let code = (item.triggerCode ?? "").lowercased()
            let title = (item.title ?? "").lowercased()
            let bodyLower = String(item.body.prefix(4000)).lowercased()

            // Tier 0: Exact trigger code match (e.g. ";dz", "dz", "//mail")
            if !code.isEmpty && (code == trimmedQuery || code == ";" + trimmedQuery || code == "//" + trimmedQuery) {
                return (item, 0, 1000.0 + Double(item.useCount))
            }
            // Tier 1: Exact title match or trigger code prefix match
            if !title.isEmpty && title == trimmedQuery {
                return (item, 1, 900.0 + Double(item.useCount))
            }
            if !code.isEmpty && (code.hasPrefix(trimmedQuery) || code.hasPrefix(";" + trimmedQuery)) {
                return (item, 1, 850.0 + Double(item.useCount))
            }
            // Tier 2: Title prefix / substring match
            if !title.isEmpty && title.contains(trimmedQuery) {
                let prefixBonus = title.hasPrefix(trimmedQuery) ? 100.0 : 0.0
                return (item, 2, 600.0 + prefixBonus + Double(item.useCount) * 2.0)
            }
            // Tier 3: Body match + character N-gram similarity + habit score
            var bodyBonus = 0.0
            if bodyLower == trimmedQuery {
                bodyBonus = 300.0
            } else if bodyLower.hasPrefix(trimmedQuery) {
                bodyBonus = 180.0
            } else if bodyLower.contains(trimmedQuery) {
                bodyBonus = 90.0
            }
            let ngramScore = ngramSimilarity(
                queryUnigrams: queryUnigrams,
                queryBigrams: queryBigrams,
                candidate: title + " " + bodyLower
            )
            let habit = adaptiveHabitScore(item, targetApp: targetAppBundleID, now: now)
            return (item, 3, bodyBonus + ngramScore * 100.0 + habit)
        }

        return scored.sorted { a, b in
            if a.tier != b.tier { return a.tier < b.tier }
            if abs(a.score - b.score) > 0.001 { return a.score > b.score }
            return a.item.updatedAt > b.item.updatedAt
        }.map(\.item)
    }

    /// Recommends the best snippet reply for a newly copied incoming message using fast local
    /// character N-gram & semantic keyword overlap (used immediately before Jev returns or offline).
    public static func localRecommendReply(
        for incomingText: String,
        snippets: [ClipItem]
    ) -> (snippet: ClipItem, confidence: Double)? {
        let trimmed = incomingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, trimmed.count <= 600, !snippets.isEmpty else { return nil }

        // Avoid recommending a snippet if the user just copied that exact snippet itself
        if snippets.contains(where: { $0.body == trimmed }) {
            return nil
        }

        let intentKeywords: [(triggers: [String], replyHints: [String])] = [
            (["发票", "税号", "抬头", "开票", "专票", "普票"], ["发票", "税号", "抬头", "纳税人", "统一社会信用代码"]),
            (["地址", "收货", "寄到", "快递", "收件", "寄件", "哪里"], ["地址", "路", "号", "省", "市", "区", "收", "电话", "手机"]),
            (["邮箱", "邮件", "email", "mail", "发我"], ["@", "邮箱", ".com", ".cn", "mail"]),
            (["微信", "联系方式", "电话", "手机", "号码", "加你"], ["电话", "手机", "微信", "联系", "13", "15", "18", "17"]),
            (["账号", "卡号", "收款", "打款", "银行", "开户行"], ["银行", "卡号", "开户", "支行", "账号"]),
            (["会议", "链接", "腾讯会议", "zoom", "几点"], ["会议", "http", "链接", "号"]),
            (["谢谢", "感谢", "辛苦", "收到"], ["不客气", "没事", "应该的", "随时联系", "收到"])
        ]

        let lowerIncoming = trimmed.lowercased()
        let incomingBigrams = characterNGrams(lowerIncoming, n: 2)
        let incomingUnigrams = Set(lowerIncoming)

        var bestMatch: (ClipItem, Double)?

        for snippet in snippets {
            let target = ((snippet.title ?? "") + " " + snippet.body).lowercased()
            var score = 0.0

            // 1. Intent pair matching
            for pair in intentKeywords {
                let matchesTrigger = pair.triggers.contains { lowerIncoming.contains($0) }
                let matchesReply = pair.replyHints.contains { target.contains($0) }
                if matchesTrigger && matchesReply {
                    score += 0.68
                }
            }

            // 2. Direct title keyword hit in incoming question
            if let title = snippet.title?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
               title.count >= 2 {
                let titleBigrams = characterNGrams(title, n: 2)
                if !titleBigrams.isEmpty {
                    let overlap = Double(titleBigrams.intersection(incomingBigrams).count) / Double(titleBigrams.count)
                    score += overlap * 0.55
                }
            }

            // 3. General character N-gram overlap
            let generalOverlap = ngramSimilarity(
                queryUnigrams: incomingUnigrams,
                queryBigrams: incomingBigrams,
                candidate: target
            )
            score += generalOverlap * 0.35

            // 4. Small boost for frequently used snippets
            score += min(0.08, log2(Double(max(1, snippet.useCount + 1))) * 0.02)

            let calibrated = min(0.96, score)
            if calibrated >= 0.52 {
                if bestMatch == nil || calibrated > bestMatch!.1 {
                    bestMatch = (snippet, calibrated)
                }
            }
        }

        return bestMatch
    }

    // MARK: - Helpers

    private static func priorityTier(_ item: ClipItem) -> Int {
        if item.isPinned { return 0 }
        if item.kind == .snippet { return 1 }
        return 2
    }

    private static func adaptiveHabitScore(_ item: ClipItem, targetApp: String?, now: Date) -> Double {
        // Base score is recency in days so recent items stay fresh, plus logarithmic boost from useCount
        let ageSeconds = max(0, now.timeIntervalSince(item.updatedAt))
        let recencyScore = max(0, 100.0 - (ageSeconds / 3600.0))
        let frequencyBoost = log2(Double(max(1, item.useCount + 1))) * 4.5
        let appAffinityBoost: Double
        if let targetApp, !targetApp.isEmpty, item.sourceApp == targetApp {
            appAffinityBoost = 3.0
        } else {
            appAffinityBoost = 0.0
        }
        return recencyScore + frequencyBoost + appAffinityBoost
    }

    public static func characterNGrams(_ text: String, n: Int) -> Set<String> {
        let chars = Array(text.filter { !$0.isWhitespace && !$0.isNewline })
        guard chars.count >= n, n > 0 else {
            return chars.isEmpty ? [] : [String(chars)]
        }
        var set = Set<String>()
        for i in 0...(chars.count - n) {
            set.insert(String(chars[i..<(i + n)]))
        }
        return set
    }

    private static func ngramSimilarity(
        queryUnigrams: Set<Character>,
        queryBigrams: Set<String>,
        candidate: String
    ) -> Double {
        guard !queryUnigrams.isEmpty else { return 0 }
        let candUnigrams = Set(candidate)
        let uniOverlap = Double(queryUnigrams.intersection(candUnigrams).count) / Double(queryUnigrams.count)
        guard !queryBigrams.isEmpty else { return uniOverlap }
        let candBigrams = characterNGrams(candidate, n: 2)
        let biOverlap = Double(queryBigrams.intersection(candBigrams).count) / Double(queryBigrams.count)
        return uniOverlap * 0.4 + biOverlap * 0.6
    }
}
