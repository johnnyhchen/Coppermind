// CategoryClassifier.swift — Tiered classification orchestrator
// CoppermindCore

import Foundation

// MARK: - Classification Tier

/// Which tier of the pipeline produced the classification.
public enum ClassificationTier: String, Sendable, Codable {
    case ruleBased = "rule_based"
    case ml        = "ml"
    case fallback  = "fallback"
    case userOverride = "user_override"
}

// MARK: - CategoryResult

/// Complete result from the classification pipeline, including provenance.
public struct CategoryResult: Sendable {
    /// The assigned category.
    public let category: NoteCategory
    /// Confidence in the classification (0.0 ... 1.0).
    public let confidence: Double
    /// Which tier of the pipeline produced this result.
    public let tier: ClassificationTier
    /// Human-readable explanation of why this category was chosen.
    public let reasoning: String

    public init(
        category: NoteCategory,
        confidence: Double,
        tier: ClassificationTier,
        reasoning: String
    ) {
        self.category = category
        self.confidence = min(max(confidence, 0.0), 1.0)
        self.tier = tier
        self.reasoning = reasoning
    }
}

// MARK: - CategoryClassifier

/// Orchestrates the tiered classification pipeline:
///   1. **Rule-based** (fast, deterministic, high-confidence patterns)
///   2. **ML** (NLModel or NLEmbedding heuristics)
///   3. **Fallback** (defaults to .idea with low confidence)
///
/// Also supports explicit user override, which always wins.
public struct CategoryClassifier: Sendable {

    // MARK: - Configuration

    /// Confidence threshold above which we accept a rule-based result
    /// without consulting the ML tier.
    public static let ruleAcceptanceThreshold: Double = 0.70

    /// Confidence threshold above which we accept an ML result.
    public static let mlAcceptanceThreshold: Double = 0.45

    // MARK: - Dependencies

    private let ruleClassifier: RuleBasedClassifier
    private let mlClassifier: MLClassifier

    // MARK: - Init

    public init(
        ruleClassifier: RuleBasedClassifier = RuleBasedClassifier(),
        mlClassifier: MLClassifier = MLClassifier()
    ) {
        self.ruleClassifier = ruleClassifier
        self.mlClassifier = mlClassifier
    }

    // MARK: - Primary API

    /// Classify the given text through the tiered pipeline.
    ///
    /// Pipeline order:
    /// 1. Rule-based: if confidence ≥ `ruleAcceptanceThreshold`, return immediately.
    /// 2. ML classifier: if confidence ≥ `mlAcceptanceThreshold`, return.
    /// 3. Fallback: return `.idea` with low confidence.
    public func classify(text: String) async -> CategoryResult {
        // ── Tier 1: Rule-based ──
        if let ruleMatch = ruleClassifier.classify(text: text),
           ruleMatch.confidence >= Self.ruleAcceptanceThreshold {
            return CategoryResult(
                category: ruleMatch.category,
                confidence: ruleMatch.confidence,
                tier: .ruleBased,
                reasoning: "Rule '\(ruleMatch.matchedRule)' matched with \(formatted(ruleMatch.confidence)) confidence"
            )
        }

        // ── Tier 2: ML classifier ──
        if let mlResult = await mlClassifier.classify(text: text),
           mlResult.confidence >= Self.mlAcceptanceThreshold {
            return CategoryResult(
                category: mlResult.category,
                confidence: mlResult.confidence,
                tier: .ml,
                reasoning: "ML classifier predicted '\(mlResult.category.displayName)' with \(formatted(mlResult.confidence)) confidence"
            )
        }

        // ── Tier 2.5: Low-confidence rule match ──
        // If rules fired but below threshold, still prefer them over pure fallback.
        if let ruleMatch = ruleClassifier.classify(text: text) {
            return CategoryResult(
                category: ruleMatch.category,
                confidence: ruleMatch.confidence,
                tier: .ruleBased,
                reasoning: "Rule '\(ruleMatch.matchedRule)' matched (low confidence: \(formatted(ruleMatch.confidence)))"
            )
        }

        // ── Tier 3: Fallback ──
        return CategoryResult(
            category: .idea,
            confidence: 0.10,
            tier: .fallback,
            reasoning: "No classifier matched; defaulting to Idea"
        )
    }

    /// Apply user override: always returns a result with tier `.userOverride`
    /// and confidence 1.0.
    public func userOverride(category: NoteCategory) -> CategoryResult {
        CategoryResult(
            category: category,
            confidence: 1.0,
            tier: .userOverride,
            reasoning: "User manually selected '\(category.displayName)'"
        )
    }

    /// Classify and apply the result to a Note.
    /// Returns the CategoryResult for display/logging purposes.
    @discardableResult
    public func classifyAndApply(to note: Note) async -> CategoryResult {
        let text = [note.title, note.body].filter { !$0.isEmpty }.joined(separator: ". ")
        let result = await classify(text: text)
        note.category = result.category
        return result
    }

    // MARK: - Helpers

    private func formatted(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }
}
