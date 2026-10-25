import AppKit
import Foundation
import Vision

/// Handles asynchronous calls to:
/// 1. TypeSafe AI's `Jev` System-One decision model (`jev-latest`) for ~70ms calibrated reply
///    recommendation, smart semantic archiving, and action routing.
/// 2. Multi-engine translation (zero-config instant translation + optional LLM translation).
/// 3. Custom AI prompt actions and local shell script actions.
@MainActor
final class SmartService {
    static let shared = SmartService()

    private let settings: AppSettings
    private let session: URLSession

    init(settings: AppSettings = .shared) {
        self.settings = settings
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6.0
        config.timeoutIntervalForResource = 10.0
        self.session = URLSession(configuration: config)
    }

    // MARK: - 1. Two-Tier Decision Engine (Local Fast Path + Jev 70ms System-One Model)

    /// Evaluates a newly copied item against the user's snippets and archive categories.
    /// First returns the <1ms local decision via `onLocalDecision`, then if `jevAPIKey` is configured,
    /// queries `jev-latest` in parallel and delivers the calibrated result via `onJevDecision`.
    func evaluateCopiedItem(
        _ item: ClipItem,
        snippets: [ClipItem],
        onLocalDecision: @escaping (JevDecisionResult) -> Void,
        onJevDecision: @escaping (JevDecisionResult) -> Void
    ) {
        guard item.contentType == .text else { return }

        // Tier 1: <1ms Local N-gram & Rule Engine
        let localTag = ContentClassifier.classifySmartTag(item.body, contentType: item.contentType)
        let localReply = settings.enableSmartReply
            ? SmartRanker.localRecommendReply(for: item.body, snippets: snippets)
            : nil
        let localAction = Self.suggestLocalAction(for: item, tag: localTag)

        let initialResult = JevDecisionResult(
            recommendedReplyID: localReply?.snippet.id,
            replyConfidence: localReply?.confidence ?? 0,
            archiveTag: localTag,
            archiveConfidence: 0.82,
            suggestedActionID: localAction,
            isFromJevModel: false
        )
        onLocalDecision(initialResult)

        // Tier 2: ~70ms TypeSafe Jev System-One Model (if API Key is configured)
        let apiKey = settings.jevAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else { return }

        let endpoint = settings.jevEndpoint
        let candidateSnippets = Array(snippets.prefix(32))

        Task {
            if let jevResult = await queryJevModel(
                item: item,
                snippets: candidateSnippets,
                endpoint: endpoint,
                apiKey: apiKey,
                fallback: initialResult
            ) {
                onJevDecision(jevResult)
            }
        }
    }

    private static func suggestLocalAction(for item: ClipItem, tag: SmartArchiveTag) -> String? {
        if tag == .foreignText || item.isForeignLanguage {
            return "translate_auto"
        }
        let trimmed = item.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) {
            return "format_json"
        }
        if tag == .credential && item.body.count > 12 {
            return "extract_digits"
        }
        return nil
    }

    private func queryJevModel(
        item: ClipItem,
        snippets: [ClipItem],
        endpoint: String,
        apiKey: String,
        fallback: JevDecisionResult
    ) async -> JevDecisionResult? {
        guard let url = URL(string: endpoint) else { return nil }

        var replyCriteria: [String: String] = [
            "none": "Not an incoming question/request, or no snippet in the pool is relevant"
        ]
        for snippet in snippets {
            let label = [snippet.title, String(snippet.body.prefix(80))]
                .compactMap { $0 }
                .joined(separator: " — ")
            replyCriteria["id_\(snippet.id)"] = label
        }

        let archiveCriteria: [String: String] = [
            SmartArchiveTag.addressContact.rawValue: "Address, phone number, tax/invoice info, contact card",
            SmartArchiveTag.codeCommand.rawValue: "Source code, terminal command, JSON/XML, SQL, log",
            SmartArchiveTag.credential.rawValue: "Verification code, OTP, tracking number, API key, secret token",
            SmartArchiveTag.foreignText.rawValue: "Foreign language paragraph or sentence that may need Chinese translation",
            SmartArchiveTag.workChat.rawValue: "Work chat message, customer inquiry, colleague question",
            SmartArchiveTag.general.rawValue: "General plain text or notes"
        ]

        let actionCriteria: [String: String] = [
            "none": "Paste directly as-is",
            "translate_auto": "Translate between English/foreign language and Chinese",
            "format_json": "Pretty-print or format JSON",
            "clean_newlines": "Clean up broken PDF line wraps",
            "extract_digits": "Extract verification code or tracking number"
        ]

        let stateText = """
        Source App: \(item.sourceApp ?? "Unknown")
        Copied Text:
        \(String(item.body.prefix(1200)))
        """

        let payload: [String: Any] = [
            "model": "jev-latest",
            "state": stateText,
            "questions": [
                "best_reply_id": [
                    "type": "choice",
                    "instructions": "If the copied text is a question or message from someone else, pick the best matching quick-reply snippet to respond with.",
                    "criteria": replyCriteria
                ],
                "archive_tag": [
                    "type": "choice",
                    "instructions": "Classify the copied text into the most fitting semantic archive category.",
                    "criteria": archiveCriteria
                ],
                "suggested_action": [
                    "type": "choice",
                    "instructions": "Which transformation action is most helpful for this copied text?",
                    "criteria": actionCriteria
                ]
            ]
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            let answers = (json["answers"] as? [String: Any]) ?? json

            var result = fallback
            result.isFromJevModel = true

            if let replyObj = answers["best_reply_id"] as? [String: Any],
               let choice = replyObj["choice"] as? String {
                let conf = (replyObj["confidence"] as? Double)
                    ?? ((replyObj["probabilities"] as? [String: Double])?[choice])
                    ?? 0.85
                if choice.hasPrefix("id_"), let id = Int64(choice.dropFirst(3)), conf >= 0.50 {
                    result.recommendedReplyID = id
                    result.replyConfidence = conf
                } else if choice == "none" {
                    result.recommendedReplyID = nil
                    result.replyConfidence = 0
                }
            }

            if let tagObj = answers["archive_tag"] as? [String: Any],
               let choice = tagObj["choice"] as? String,
               let tag = SmartArchiveTag(rawValue: choice) {
                result.archiveTag = tag
                result.archiveConfidence = (tagObj["confidence"] as? Double) ?? 0.90
            }

            if let actObj = answers["suggested_action"] as? [String: Any],
               let choice = actObj["choice"] as? String {
                result.suggestedActionID = (choice == "none") ? nil : choice
            }

            return result
        } catch {
            return nil
        }
    }

    // MARK: - 2. Instant Translation (Zero-Config GTX + Optional LLM)

    /// Translates `text` to Chinese (if foreign) or to English (if already Chinese).
    func translate(_ text: String, forceTargetLanguage: String? = nil) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }

        let targetLang: String
        if let forceTargetLanguage {
            targetLang = forceTargetLanguage
        } else {
            targetLang = ContentClassifier.containsChinese(trimmed) ? "en" : "zh-CN"
        }

        // 1. If the user configured an AI API Key, use LLM for high-fluency contextual translation
        let aiKey = settings.aiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !aiKey.isEmpty {
            let prompt = targetLang.hasPrefix("zh")
                ? "请将以下内容准确、自然地翻译为简体中文，只输出译文，不要任何解释："
                : "Translate the following text into natural, idiomatic English. Output only the translation without explanation:"
            if let llmOut = try? await runAIPrompt(prompt: prompt, input: trimmed) {
                return llmOut
            }
        }

        // 2. Zero-config fast translation via public GTX endpoint (with MyMemory fallback)
        if let gtx = try? await translateViaGTX(trimmed, targetLang: targetLang) {
            return gtx
        }
        if let fallback = try? await translateViaMyMemory(trimmed, targetLang: targetLang) {
            return fallback
        }
        throw NSError(domain: "SmartService", code: -2, userInfo: [NSLocalizedDescriptionKey: "翻译请求超时或网络不可用，也可在设置中配置 AI API Key"])
    }

    private func translateViaGTX(_ text: String, targetLang: String) async throws -> String {
        var components = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
        components.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: "auto"),
            URLQueryItem(name: "tl", value: targetLang),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: String(text.prefix(4000)))
        ]
        guard let url = components.url else {
            throw NSError(domain: "SmartService", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的翻译请求"])
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3.5

        let (data, _) = try await session.data(for: request)
        if let root = try JSONSerialization.jsonObject(with: data) as? [Any],
           let sentences = root.first as? [[Any]] {
            let joined = sentences.compactMap { $0.first as? String }.joined()
            if !joined.isEmpty {
                return joined
            }
        }
        throw NSError(domain: "SmartService", code: -2, userInfo: [NSLocalizedDescriptionKey: "翻译解析失败"])
    }

    private func translateViaMyMemory(_ text: String, targetLang: String) async throws -> String {
        let sourceLang = ContentClassifier.containsChinese(text) ? "zh-CN" : "en"
        var components = URLComponents(string: "https://api.mymemory.translated.net/get")!
        components.queryItems = [
            URLQueryItem(name: "q", value: String(text.prefix(500))),
            URLQueryItem(name: "langpair", value: "\(sourceLang)|\(targetLang)")
        ]
        guard let url = components.url else {
            throw NSError(domain: "SmartService", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的翻译请求"])
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4.0
        let (data, _) = try await session.data(for: request)
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let responseData = json["responseData"] as? [String: Any],
           let translated = responseData["translatedText"] as? String,
           !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return translated.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        throw NSError(domain: "SmartService", code: -2, userInfo: [NSLocalizedDescriptionKey: "备用翻译解析失败"])
    }

    // MARK: - 3. Pluggable Action Execution (Built-in + AI Prompt + Shell Script)

    func executeAction(_ action: ClipActionDescriptor, on text: String) async throws -> String {
        switch action.kind {
        case .builtIn:
            if action.id == "translate_auto" {
                return try await translate(text)
            }
            if let out = ClipActionEngine.runBuiltIn(id: action.id, on: text) {
                return out
            }
            throw NSError(
                domain: "SmartService",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "当前内容不满足“\(action.title)”的格式要求"]
            )

        case .aiPrompt:
            return try await runAIPrompt(prompt: action.payload, input: text)

        case .shellCommand:
            return try await runShellCommand(command: action.payload, stdinText: text)
        }
    }

    private func runAIPrompt(prompt: String, input: String) async throws -> String {
        let apiKey = settings.aiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw NSError(
                domain: "SmartService",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: "请先在“设置 → 智能与模型”中配置 AI API Key"]
            )
        }
        guard let url = URL(string: settings.aiEndpoint) else {
            throw NSError(domain: "SmartService", code: -5, userInfo: [NSLocalizedDescriptionKey: "AI 接口地址无效"])
        }

        let body: [String: Any] = [
            "model": settings.aiModelName,
            "messages": [
                ["role": "system", "content": prompt],
                ["role": "user", "content": input]
            ],
            "temperature": 0.3
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw NSError(domain: "SmartService", code: -6, userInfo: [NSLocalizedDescriptionKey: "AI 模型调用失败"])
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runShellCommand(command: String, stdinText: String) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command]

            let inPipe = Pipe()
            let outPipe = Pipe()
            process.standardInput = inPipe
            process.standardOutput = outPipe
            process.standardError = outPipe

            try process.run()
            DispatchQueue.global(qos: .userInitiated).async {
                if let data = stdinText.data(using: .utf8) {
                    try? inPipe.fileHandleForWriting.write(contentsOf: data)
                }
                try? inPipe.fileHandleForWriting.close()
            }

            // Terminate runaway commands after 8 seconds
            let watchdog = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 8.0, execute: watchdog)

            // Read stdout/stderr BEFORE waitUntilExit to prevent >64KB pipe deadlock
            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            watchdog.cancel()

            let output = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .newlines) ?? ""
            guard process.terminationStatus == 0, !output.isEmpty else {
                throw NSError(
                    domain: "SmartService",
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: output.isEmpty ? "脚本执行未返回内容" : output]
                )
            }
            return output
        }.value
    }

    // MARK: - 4. Native macOS Vision OCR for Copied Screenshots & Images

    /// Extracts Chinese and English text from PNG/TIFF image data using Apple's native Vision framework.
    nonisolated func recognizeTextInImage(_ imageData: Data) async throws -> String {
        try await Task.detached(priority: .utility) {
            let handler = VNImageRequestHandler(data: imageData, options: [:])
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]

            try handler.perform([request])
            let observations = request.results ?? []
            let lines = observations.compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return lines.joined(separator: "\n")
        }.value
    }
}
