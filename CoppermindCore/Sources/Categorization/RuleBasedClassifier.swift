// RuleBasedClassifier.swift — Pattern-match note text → NoteCategory
// CoppermindCore

import Foundation

// MARK: - RuleBasedClassifier

/// Tier-1 deterministic classifier that matches note text against keyword and regex
/// patterns to propose a category with confidence.
///
/// Rules are evaluated in priority order. The first high-confidence match wins,
/// but all matches are returned so the orchestrator can reason about ambiguity.
public struct RuleBasedClassifier: Sendable {

    // MARK: - Types

    /// The result of a single rule-based classification attempt.
    public struct RuleMatch: Sendable {
        public let category: NoteCategory
        public let confidence: Double       // 0.0 ... 1.0
        public let matchedRule: String       // Human-readable rule name for debugging

        public init(category: NoteCategory, confidence: Double, matchedRule: String) {
            self.category = category
            self.confidence = min(max(confidence, 0.0), 1.0)
            self.matchedRule = matchedRule
        }
    }

    // MARK: - Public API

    public init() {}

    /// Classify the given text and return the best (category, confidence) match,
    /// or `nil` if no rule fires with sufficient confidence.
    public func classify(text: String) -> RuleMatch? {
        let matches = allMatches(text: text)
        return matches.first // Already sorted by confidence descending
    }

    /// Return all rule matches sorted by confidence descending.
    public func allMatches(text: String) -> [RuleMatch] {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        var results: [RuleMatch] = []

        // ── Rule 1: URL → Bucket (highest priority for URLs)
        if let match = matchURL(normalized) {
            results.append(match)
        }

        // ── Rule 2: Action verbs → Bucket (buy/get/order/visit/read/watch)
        if let match = matchBucketVerbs(normalized) {
            results.append(match)
        }

        // ── Rule 3: Task indicators → Task (TODO/need to/must/should)
        if let match = matchTask(normalized) {
            results.append(match)
        }

        // ── Rule 4: Project indicators → Project (build/create/make/project)
        if let match = matchProject(normalized) {
            results.append(match)
        }

        // Sort by confidence descending
        return results.sorted { $0.confidence > $1.confidence }
    }

    // MARK: - Individual Rule Matchers

    /// URLs → Bucket with high confidence.
    private func matchURL(_ text: String) -> RuleMatch? {
        let urlPattern = #"https?://[^\s]+"#
        let bareURLPattern = #"(?:www\.)[^\s]+"#

        let urlCount = regexMatchCount(text, pattern: urlPattern)
            + regexMatchCount(text, pattern: bareURLPattern)

        guard urlCount > 0 else { return nil }

        // Confidence scales with how URL-dominated the text is
        let wordCount = max(text.split(separator: " ").count, 1)
        let urlDominance = min(Double(urlCount) / Double(wordCount) * 3.0, 1.0)
        let confidence = 0.85 + 0.15 * urlDominance  // 0.85 – 1.0

        return RuleMatch(category: .bucket, confidence: confidence, matchedRule: "url_detected")
    }

    /// Action verbs that indicate a bucket-list item: buy, get, order, visit, read, watch.
    private func matchBucketVerbs(_ text: String) -> RuleMatch? {
        // Match verbs at word boundaries, typically at the start of a sentence/phrase
        let bucketVerbs: [(String, Double)] = [
            ("buy",   0.80),
            ("order", 0.80),
            ("get",   0.65),   // "get" is more ambiguous
            ("visit", 0.80),
            ("read",  0.75),
            ("watch", 0.75),
            ("listen to", 0.75),
            ("check out", 0.70),
            ("look into", 0.65),
        ]

        var bestConfidence = 0.0
        var matched = false

        for (verb, baseConfidence) in bucketVerbs {
            let pattern = #"(?:^|\.\s*|;\s*|!\s*|\n\s*)"# + NSRegularExpression.escapedPattern(for: verb) + #"\b"#
            let leadingMatch = regexMatchCount(text, pattern: pattern)

            let anywherePattern = #"\b"# + NSRegularExpression.escapedPattern(for: verb) + #"\b"#
            let anywhereMatch = regexMatchCount(text, pattern: anywherePattern)

            if leadingMatch > 0 {
                // Verb leads a clause → higher confidence
                bestConfidence = max(bestConfidence, baseConfidence)
                matched = true
            } else if anywhereMatch > 0 {
                // Verb appears somewhere → lower confidence
                bestConfidence = max(bestConfidence, baseConfidence * 0.7)
                matched = true
            }
        }

        guard matched else { return nil }
        return RuleMatch(category: .bucket, confidence: bestConfidence, matchedRule: "bucket_action_verb")
    }

    /// Task indicators: TODO, need to, must, should, have to, don't forget, remember to.
    private func matchTask(_ text: String) -> RuleMatch? {
        let strongIndicators: [(String, Double)] = [
            (#"\btodo\b"#,            0.90),
            (#"\bto-do\b"#,           0.90),
            (#"\bto do\b"#,           0.85),
            (#"\bneed to\b"#,         0.80),
            (#"\bmust\b"#,            0.80),
            (#"\bshould\b"#,          0.70),
            (#"\bhave to\b"#,         0.80),
            (#"\bdon'?t forget\b"#,   0.85),
            (#"\bremember to\b"#,     0.85),
            (#"\bdeadline\b"#,        0.75),
            (#"\bdue\b"#,             0.70),
            (#"\baction item\b"#,     0.85),
            (#"\bfollow up\b"#,       0.75),
            (#"- ?\[ ?\]"#,           0.90),   // Markdown checkbox
            (#"\breminder\b"#,        0.70),
        ]

        var bestConfidence = 0.0
        var matched = false

        for (pattern, confidence) in strongIndicators {
            if regexMatchCount(text, pattern: pattern) > 0 {
                bestConfidence = max(bestConfidence, confidence)
                matched = true
            }
        }

        guard matched else { return nil }
        return RuleMatch(category: .task, confidence: bestConfidence, matchedRule: "task_indicator")
    }

    /// Project indicators: build, create, make, project, design, develop, implement.
    private func matchProject(_ text: String) -> RuleMatch? {
        let projectIndicators: [(String, Double)] = [
            (#"\bbuild\b"#,     0.75),
            (#"\bcreate\b"#,    0.70),
            (#"\bmake\b"#,      0.65),
            (#"\bproject\b"#,   0.80),
            (#"\bdesign\b"#,    0.70),
            (#"\bdevelop\b"#,   0.75),
            (#"\bimplement\b"#, 0.75),
            (#"\bprototype\b"#, 0.80),
            (#"\bapp\b"#,       0.55),
            (#"\btool\b"#,      0.55),
        ]

        var bestConfidence = 0.0
        var totalMatches = 0

        for (pattern, confidence) in projectIndicators {
            let count = regexMatchCount(text, pattern: pattern)
            if count > 0 {
                bestConfidence = max(bestConfidence, confidence)
                totalMatches += count
            }
        }

        guard totalMatches > 0 else { return nil }

        // Multiple project-related words boost confidence
        let multiMatchBoost = min(Double(totalMatches - 1) * 0.05, 0.15)
        let finalConfidence = min(bestConfidence + multiMatchBoost, 0.95)

        return RuleMatch(category: .project, confidence: finalConfidence, matchedRule: "project_indicator")
    }

    // MARK: - Helpers

    private func regexMatchCount(_ text: String, pattern: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return 0
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.numberOfMatches(in: text, range: range)
    }
}
