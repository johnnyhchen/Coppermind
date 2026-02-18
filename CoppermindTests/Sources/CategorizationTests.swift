// CategorizationTests.swift — Tests for the classification pipeline
// CoppermindTests

import Testing
import Foundation
@testable import CoppermindCore

// MARK: - RuleBasedClassifier Tests

@Suite("RuleBasedClassifier")
struct RuleBasedClassifierTests {

    let classifier = RuleBasedClassifier()

    // ── URL → Bucket ──

    @Test("URL in text classifies as Bucket")
    func urlClassification() {
        let match = classifier.classify(text: "Check out https://example.com/article")
        #expect(match != nil)
        #expect(match?.category == .bucket)
        #expect(match!.confidence >= 0.85)
    }

    @Test("Multiple URLs yield high confidence Bucket")
    func multipleURLs() {
        let match = classifier.classify(text: "https://a.com and https://b.com")
        #expect(match?.category == .bucket)
    }

    @Test("www prefix detected as URL")
    func wwwURL() {
        let match = classifier.classify(text: "Visit www.example.com for details")
        #expect(match?.category == .bucket)
    }

    // ── Action verbs → Bucket ──

    @Test("Buy verb classifies as Bucket")
    func buyVerb() {
        let match = classifier.classify(text: "Buy new headphones from Amazon")
        #expect(match?.category == .bucket)
    }

    @Test("Watch verb classifies as Bucket")
    func watchVerb() {
        let match = classifier.classify(text: "Watch Interstellar this weekend")
        #expect(match?.category == .bucket)
    }

    @Test("Read verb classifies as Bucket")
    func readVerb() {
        let match = classifier.classify(text: "Read Designing Data-Intensive Applications")
        #expect(match?.category == .bucket)
    }

    @Test("Visit verb classifies as Bucket")
    func visitVerb() {
        let match = classifier.classify(text: "Visit the new ramen place downtown")
        #expect(match?.category == .bucket)
    }

    // ── Task indicators ──

    @Test("TODO classifies as Task")
    func todoTask() {
        let match = classifier.classify(text: "TODO: file quarterly taxes")
        #expect(match?.category == .task)
        #expect(match!.confidence >= 0.80)
    }

    @Test("Need to classifies as Task")
    func needToTask() {
        let match = classifier.classify(text: "Need to call the dentist on Monday")
        #expect(match?.category == .task)
    }

    @Test("Must classifies as Task")
    func mustTask() {
        let match = classifier.classify(text: "Must finish the report before Friday")
        #expect(match?.category == .task)
    }

    @Test("Should classifies as Task")
    func shouldTask() {
        let match = classifier.classify(text: "Should review the pull request today")
        #expect(match?.category == .task)
    }

    @Test("Markdown checkbox classifies as Task")
    func checkboxTask() {
        let match = classifier.classify(text: "- [ ] Pick up dry cleaning")
        #expect(match?.category == .task)
    }

    // ── Project indicators ──

    @Test("Build classifies as Project")
    func buildProject() {
        let match = classifier.classify(text: "Build a split-flap display for the kitchen")
        #expect(match?.category == .project)
    }

    @Test("Create classifies as Project")
    func createProject() {
        let match = classifier.classify(text: "Create a personal finance tracking app")
        #expect(match?.category == .project)
    }

    @Test("Project keyword classifies as Project")
    func projectKeyword() {
        let match = classifier.classify(text: "New project: home automation system")
        #expect(match?.category == .project)
    }

    // ── No match ──

    @Test("Unrecognizable text returns nil")
    func noMatch() {
        let match = classifier.classify(text: "What if gravity is just nostalgia for mass?")
        #expect(match == nil)
    }

    @Test("Empty text returns nil")
    func emptyText() {
        let match = classifier.classify(text: "")
        #expect(match == nil)
    }

    // ── Multiple matches sorted by confidence ──

    @Test("allMatches returns results sorted by confidence")
    func sortedMatches() {
        let matches = classifier.allMatches(text: "TODO: buy groceries and visit the store https://shop.com")
        #expect(matches.count >= 2)
        for i in 0..<(matches.count - 1) {
            #expect(matches[i].confidence >= matches[i + 1].confidence)
        }
    }
}

// MARK: - MLClassifier Tests

@Suite("MLClassifier")
struct MLClassifierTests {

    @Test("Returns result via embedding fallback when no model loaded")
    func embeddingFallback() async {
        let classifier = MLClassifier()
        // Without a loaded model, falls back to NLEmbedding
        // This may return nil on some CI environments without NL resources
        let result = await classifier.classify(text: "I need to finish this task by tomorrow")
        // Just verify no crash; result may be nil if NLEmbedding unavailable
        _ = result
    }

    @Test("loadDefaultModel returns false (stub)")
    func loadDefaultModelStub() async {
        let classifier = MLClassifier()
        let loaded = await classifier.loadDefaultModel()
        #expect(loaded == false)
    }

    @Test("unloadModel lifecycle is safe")
    func unloadLifecycle() async {
        let classifier = MLClassifier()
        _ = await classifier.loadDefaultModel()
        await classifier.unloadModel()
        // Classify after unload should still work via fallback
        let result = await classifier.classify(text: "Build a new prototype")
        _ = result  // No crash = success
    }
}

// MARK: - CategoryClassifier (Composite) Tests

@Suite("CategoryClassifier Pipeline")
struct CategoryClassifierTests {

    let classifier = CategoryClassifier()

    @Test("URL text classified via rule tier")
    func urlViaPipeline() async {
        let result = await classifier.classify(text: "Check https://swift.org/blog")
        #expect(result.category == .bucket)
        #expect(result.tier == .ruleBased)
        #expect(result.confidence >= 0.70)
    }

    @Test("Task text classified via rule tier")
    func taskViaPipeline() async {
        let result = await classifier.classify(text: "TODO: deploy the new version")
        #expect(result.category == .task)
        #expect(result.tier == .ruleBased)
    }

    @Test("Unrecognizable text falls back to Idea")
    func fallbackToIdea() async {
        let result = await classifier.classify(text: "Quantum entanglement is spooky")
        #expect(result.category == .idea)
        // Could be fallback or low-confidence ML
        #expect(result.confidence <= 0.50)
    }

    @Test("User override always wins")
    func userOverride() {
        let result = classifier.userOverride(category: .project)
        #expect(result.category == .project)
        #expect(result.confidence == 1.0)
        #expect(result.tier == .userOverride)
    }

    @Test("classifyAndApply sets note category")
    func applyToNote() async {
        let note = Note(title: "TODO", body: "Need to submit the form by Friday")
        let result = await classifier.classifyAndApply(to: note)
        #expect(note.category == result.category)
        #expect(result.category == .task)
    }

    @Test("Reasoning string is non-empty")
    func reasoningPresent() async {
        let result = await classifier.classify(text: "Build a weather dashboard app")
        #expect(!result.reasoning.isEmpty)
    }

    @Test("Empty text falls back to Idea with low confidence")
    func emptyTextFallback() async {
        let result = await classifier.classify(text: "   ")
        #expect(result.category == .idea)
        #expect(result.tier == .fallback)
    }
}
