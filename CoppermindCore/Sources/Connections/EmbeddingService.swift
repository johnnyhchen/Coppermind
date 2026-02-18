// EmbeddingService.swift — On-device text embedding via NaturalLanguage framework
// CoppermindCore

import Foundation
import NaturalLanguage

/// Provides text-to-vector embeddings using Apple's NaturalLanguage framework.
/// Uses TF-IDF-weighted word vector averaging when sentence embedding is unavailable.
/// Used by ConnectionDiscovery and NoteClusterer for semantic similarity.
public actor EmbeddingService {

    // MARK: - Configuration

    public struct Configuration: Sendable {
        public let language: NLLanguage
        public let maxCacheSize: Int

        public init(
            language: NLLanguage = .english,
            maxCacheSize: Int = 500
        ) {
            self.language = language
            self.maxCacheSize = maxCacheSize
        }
    }

    // MARK: - LRU Cache Entry

    private struct CacheEntry {
        let embedding: [Float]
        var lastAccess: UInt64
    }

    // MARK: - Properties

    private let configuration: Configuration
    /// LRU cache: key -> (embedding, access-order counter)
    private var cache: [String: CacheEntry] = [:]
    /// Monotonically increasing counter for LRU ordering.
    private var accessCounter: UInt64 = 0

    // MARK: - Init

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    // MARK: - Primary API

    /// Generate an embedding vector for the given text.
    ///
    /// Strategy:
    /// 1. Try NLEmbedding.sentenceEmbedding if available.
    /// 2. Fall back to TF-IDF-weighted average of NLEmbedding.wordEmbedding vectors.
    ///
    /// Results are cached with LRU eviction at `maxCacheSize` (default 500).
    ///
    /// - Parameter text: The input text to embed.
    /// - Returns: A float array representing the text in vector space.
    /// - Throws: `EmbeddingError` if no embedding method is available.
    public func embed(_ text: String) throws -> [Float] {
        let key = text

        // -- Cache hit --
        if var entry = cache[key] {
            accessCounter += 1
            entry.lastAccess = accessCounter
            cache[key] = entry
            return entry.embedding
        }

        // -- Try sentence-level embedding first --
        if let sentenceEmbedding = NLEmbedding.sentenceEmbedding(for: configuration.language),
           let vector = sentenceEmbedding.vector(for: text) {
            let result = vector.map { Float($0) }
            insertIntoCache(key: key, embedding: result)
            return result
        }

        // -- Fall back to TF-IDF-weighted word-vector average --
        guard let wordEmbedding = NLEmbedding.wordEmbedding(for: configuration.language) else {
            throw EmbeddingError.embeddingUnavailable(configuration.language)
        }

        let result = try tfidfWeightedAverage(text: text, wordEmbedding: wordEmbedding)
        insertIntoCache(key: key, embedding: result)
        return result
    }

    /// Cosine similarity between two text embeddings.
    ///
    /// - Parameters:
    ///   - a: First embedding vector.
    ///   - b: Second embedding vector.
    /// - Returns: Cosine similarity in the range [-1.0, 1.0]. Returns 0.0 for
    ///   mismatched or empty vectors.
    public func similarity(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0.0 }

        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }

        let denominator = sqrtf(normA) * sqrtf(normB)
        guard denominator > 0 else { return 0.0 }

        return Double(dotProduct / denominator)
    }

    /// Batch-embed multiple texts. Returns embeddings in the same order as input.
    public func embedBatch(texts: [String]) throws -> [[Float]] {
        var results: [[Float]] = []
        results.reserveCapacity(texts.count)
        for text in texts {
            let embedding = try embed(text)
            results.append(embedding)
        }
        return results
    }

    /// Clear the embedding cache.
    public func clearCache() {
        cache.removeAll()
        accessCounter = 0
    }

    /// Current cache size.
    public var cacheSize: Int {
        cache.count
    }

    // MARK: - TF-IDF Weighted Average

    /// Compute a document embedding by averaging word vectors weighted by TF-IDF scores.
    private func tfidfWeightedAverage(text: String, wordEmbedding: NLEmbedding) throws -> [Float] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text

        var tokens: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            tokens.append(String(text[range]).lowercased())
            return true
        }

        guard !tokens.isEmpty else {
            throw EmbeddingError.vectorGenerationFailed(String(text.prefix(50)))
        }

        // -- Term frequency (TF) --
        var termFrequency: [String: Int] = [:]
        for token in tokens {
            termFrequency[token, default: 0] += 1
        }

        // -- IDF approximation --
        // Without a corpus, use sub-linear TF as weight: 1 + log(tf).
        // Words that appear many times get dampened; single-occurrence words
        // (likely topical) keep weight ~ 1.
        var dimension: Int?
        var weightedSum: [Float]?
        var totalWeight: Float = 0

        for (token, count) in termFrequency {
            guard let wordVector = wordEmbedding.vector(for: token) else { continue }

            let floatVec = wordVector.map { Float($0) }

            if dimension == nil {
                dimension = floatVec.count
                weightedSum = [Float](repeating: 0, count: floatVec.count)
            }

            guard floatVec.count == dimension else { continue }

            let weight = Float(1.0 + log(Double(count)))
            totalWeight += weight

            for d in 0..<floatVec.count {
                weightedSum![d] += floatVec[d] * weight
            }
        }

        guard var sum = weightedSum, totalWeight > 0 else {
            throw EmbeddingError.vectorGenerationFailed(String(text.prefix(50)))
        }

        // Normalize to unit vector
        for d in 0..<sum.count {
            sum[d] /= totalWeight
        }

        return sum
    }

    // MARK: - LRU Cache Management

    /// Insert an entry, evicting the least-recently-used item if at capacity.
    private func insertIntoCache(key: String, embedding: [Float]) {
        if cache.count >= configuration.maxCacheSize {
            evictLRU()
        }
        accessCounter += 1
        cache[key] = CacheEntry(embedding: embedding, lastAccess: accessCounter)
    }

    /// Evict the least-recently-used entry from the cache.
    private func evictLRU() {
        guard let lruKey = cache.min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key else {
            return
        }
        cache.removeValue(forKey: lruKey)
    }
}

// MARK: - TF-IDF Utility (exposed for NoteClusterer label generation)

/// Lightweight TF-IDF calculator for keyword extraction.
public struct TFIDFCalculator: Sendable {

    /// Tokenize text into lowercased words.
    public static func tokenize(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var tokens: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            tokens.append(String(text[range]).lowercased())
            return true
        }
        return tokens
    }

    /// Extract top-N keywords from a set of documents by TF-IDF score.
    ///
    /// - Parameters:
    ///   - documents: Array of texts (each is one "document").
    ///   - topN: Number of keywords to return.
    /// - Returns: Keywords sorted descending by aggregate TF-IDF score.
    public static func topKeywords(from documents: [String], topN: Int = 3) -> [String] {
        let totalDocs = Double(documents.count)
        guard totalDocs > 0 else { return [] }

        // Tokenize all documents
        let tokenizedDocs = documents.map { tokenize($0) }

        // Document frequency: how many docs contain each term
        var docFrequency: [String: Int] = [:]
        for tokens in tokenizedDocs {
            let unique = Set(tokens)
            for token in unique {
                docFrequency[token, default: 0] += 1
            }
        }

        // Stop words (minimal set)
        let stopWords: Set<String> = [
            "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
            "have", "has", "had", "do", "does", "did", "will", "would", "shall",
            "should", "may", "might", "must", "can", "could", "of", "in", "to",
            "for", "with", "on", "at", "from", "by", "about", "as", "into",
            "through", "during", "before", "after", "above", "below", "between",
            "and", "but", "or", "nor", "not", "so", "yet", "both", "either",
            "neither", "each", "every", "all", "any", "few", "more", "most",
            "other", "some", "such", "no", "only", "own", "same", "than",
            "too", "very", "just", "because", "if", "when", "where", "how",
            "what", "which", "who", "whom", "this", "that", "these", "those",
            "i", "me", "my", "we", "our", "you", "your", "he", "him", "his",
            "she", "her", "it", "its", "they", "them", "their",
        ]

        // Aggregate TF-IDF per term across all documents
        var tfidfScores: [String: Double] = [:]

        for tokens in tokenizedDocs {
            var tf: [String: Int] = [:]
            for t in tokens { tf[t, default: 0] += 1 }

            for (term, count) in tf {
                guard term.count > 2, !stopWords.contains(term) else { continue }
                let termTF = 1.0 + log(Double(count))
                let idf = log(totalDocs / Double(docFrequency[term, default: 1]))
                tfidfScores[term, default: 0] += termTF * idf
            }
        }

        return tfidfScores
            .sorted { $0.value > $1.value }
            .prefix(topN)
            .map(\.key)
    }
}

// MARK: - EmbeddingError

/// Errors that can occur during embedding generation.
public enum EmbeddingError: Error, Sendable, LocalizedError {
    case embeddingUnavailable(NLLanguage)
    case vectorGenerationFailed(String)
    case dimensionMismatch(expected: Int, actual: Int)

    public var errorDescription: String? {
        switch self {
        case .embeddingUnavailable(let language):
            return "No embedding (sentence or word) available for language: \(language.rawValue)"
        case .vectorGenerationFailed(let preview):
            return "Failed to generate vector for text: \"\(preview)...\""
        case .dimensionMismatch(let expected, let actual):
            return "Embedding dimension mismatch: expected \(expected), got \(actual)"
        }
    }
}
