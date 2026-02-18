// MLClassifier.swift — On-device NLModel classification with embedding fallback
// CoppermindCore

import Foundation
import NaturalLanguage

// MARK: - CategoryClassifying Protocol

/// Common protocol for any classifier that can assign a NoteCategory to text.
public protocol CategoryClassifying: Sendable {
    func classify(text: String) async -> CategoryClassifyingResult?
}

/// Result from any classifier conforming to CategoryClassifying.
public struct CategoryClassifyingResult: Sendable {
    public let category: NoteCategory
    public let confidence: Double   // 0.0 ... 1.0

    public init(category: NoteCategory, confidence: Double) {
        self.category = category
        self.confidence = min(max(confidence, 0.0), 1.0)
    }
}

// MARK: - MLClassifier

/// Tier-2 classifier that wraps NLModel for on-device text classification.
/// When no trained model is available, falls back to NLEmbedding similarity
/// heuristics against category exemplar phrases.
public actor MLClassifier: CategoryClassifying {

    // MARK: - Configuration

    public struct Configuration: Sendable {
        /// Minimum confidence threshold to return a result.
        public let minimumConfidence: Double
        /// Language for NLEmbedding fallback.
        public let language: NLLanguage

        public init(
            minimumConfidence: Double = 0.30,
            language: NLLanguage = .english
        ) {
            self.minimumConfidence = minimumConfidence
            self.language = language
        }
    }

    // MARK: - Properties

    private let configuration: Configuration
    private var nlModel: NLModel?
    private var isModelLoaded: Bool { nlModel != nil }

    /// Category exemplar phrases for embedding-based fallback classification.
    /// Each category maps to representative phrases whose embeddings we compare against.
    private static let categoryExemplars: [NoteCategory: [String]] = [
        .task: [
            "I need to do this task",
            "Remember to finish the work",
            "TODO action item deadline",
            "Must complete this by tomorrow",
            "Follow up on the meeting",
            "Should call the doctor",
        ],
        .bucket: [
            "Buy this product online",
            "Watch this movie later",
            "Read this book article",
            "Visit this restaurant place",
            "Check out this link website",
            "Order something from the store",
        ],
        .project: [
            "Build an app for tracking",
            "Create a new design project",
            "Develop a tool for automation",
            "Make a prototype of the idea",
            "Implement the feature system",
            "Design and build something new",
        ],
        .idea: [
            "What if we could do this differently",
            "Interesting thought about the future",
            "Random shower thought observation",
            "I wonder if this would work",
            "Concept for a new approach",
            "Brainstorm creative possibility",
        ],
    ]

    // MARK: - Init

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    // MARK: - Model Lifecycle

    /// Attempt to load a compiled NLModel from the given URL.
    /// Call once at app launch. Returns false if loading fails.
    @discardableResult
    public func loadModel(from url: URL) -> Bool {
        do {
            nlModel = try NLModel(contentsOf: url)
            return true
        } catch {
            nlModel = nil
            return false
        }
    }

    /// Stub: attempt to load from the app bundle's default location.
    /// Returns false if no model is found (expected during cold start).
    @discardableResult
    public func loadDefaultModel() -> Bool {
        // TODO: In production, locate the compiled .mlmodelc in the bundle:
        // guard let modelURL = Bundle.main.url(
        //     forResource: "CoppermindTextClassifier",
        //     withExtension: "mlmodelc"
        // ) else { return false }
        // return loadModel(from: modelURL)
        return false
    }

    /// Release the loaded model to free memory.
    public func unloadModel() {
        nlModel = nil
    }

    // MARK: - CategoryClassifying

    public func classify(text: String) async -> CategoryClassifyingResult? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Tier 2a: Use the trained NLModel if available
        if let nlModel {
            return classifyWithNLModel(nlModel, text: trimmed)
        }

        // Tier 2b: Fall back to NLEmbedding similarity heuristics
        return classifyWithEmbeddings(text: trimmed)
    }

    // MARK: - NLModel Classification

    private func classifyWithNLModel(_ model: NLModel, text: String) -> CategoryClassifyingResult? {
        // NLModel.predictedLabel returns the top label as a String
        guard let predictedLabel = model.predictedLabel(for: text) else { return nil }

        // NLModel.predictedLabelHypotheses returns confidence distribution
        let hypotheses = model.predictedLabelHypotheses(for: text, maximumCount: 4)
        let confidence = hypotheses[predictedLabel] ?? 0.0

        guard confidence >= configuration.minimumConfidence,
              let category = NoteCategory(rawValue: predictedLabel) else {
            return nil
        }

        return CategoryClassifyingResult(category: category, confidence: confidence)
    }

    // MARK: - Embedding Fallback

    /// Classify text by computing NLEmbedding distance to category exemplar phrases.
    /// Uses sentence-level embeddings and averages distances to each category's exemplars.
    private func classifyWithEmbeddings(text: String) -> CategoryClassifyingResult? {
        guard let embedding = NLEmbedding.sentenceEmbedding(for: configuration.language) else {
            return nil
        }

        var bestCategory: NoteCategory?
        var bestSimilarity = -Double.infinity

        for (category, exemplars) in Self.categoryExemplars {
            var totalDistance = 0.0
            var validCount = 0

            for exemplar in exemplars {
                let distance = embedding.distance(between: text, and: exemplar)
                // NLEmbedding.distance returns cosine distance (0 = identical, 2 = opposite)
                // Convert to similarity: 1.0 - (distance / 2.0)
                if distance.isFinite {
                    totalDistance += distance
                    validCount += 1
                }
            }

            guard validCount > 0 else { continue }

            let avgDistance = totalDistance / Double(validCount)
            let similarity = 1.0 - (avgDistance / 2.0)  // Map [0,2] → [1,0]

            if similarity > bestSimilarity {
                bestSimilarity = similarity
                bestCategory = category
            }
        }

        guard let category = bestCategory,
              bestSimilarity >= configuration.minimumConfidence else {
            return nil
        }

        // Scale confidence: embedding similarities tend to cluster in 0.4–0.7 range
        // Remap to a more useful spread
        let scaledConfidence = min(max((bestSimilarity - 0.3) / 0.5, 0.0), 1.0) * 0.75

        return CategoryClassifyingResult(category: category, confidence: scaledConfidence)
    }
}
