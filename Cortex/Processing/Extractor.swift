//
//  EssenceExtractor.swift
//  Cortex
//
//  Extracts important content from text WITHOUT using LLM
//  Ported from OpenMemory's extract_essence() in hsg.py
//
//  Uses sentence scoring heuristics to pick the most important parts
//

import Foundation

/// Extracts the "essence" of text using sentence scoring (no LLM)
final class EssenceExtractor {
    
    // MARK: - Singleton
    
    static let shared = EssenceExtractor()
    
    // MARK: - Configuration
    
    /// Maximum length for extracted essence
    var maxLength: Int = 500
    
    private init() {}
    
    // MARK: - Extraction
    
    /// Extract essence from raw text
    /// Returns the most important sentences up to maxLength
    func extractEssence(_ raw: String, sector: MemorySector? = nil, maxLen: Int? = nil) -> String {
        let limit = maxLen ?? maxLength
        
        // If already short enough, return as-is
        if raw.count <= limit {
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Split into sentences
        let sentences = splitIntoSentences(raw)
            .filter { $0.count > 10 } // Skip very short fragments
        
        guard !sentences.isEmpty else {
            return String(raw.prefix(limit))
        }
        
        // Score each sentence
        var scored: [(text: String, score: Int, index: Int)] = []
        
        for (index, sentence) in sentences.enumerated() {
            let score = scoreSentence(sentence, index: index, sector: sector)
            scored.append((text: sentence, score: score, index: index))
        }
        
        // Sort by score descending
        scored.sort { $0.score > $1.score }
        
        // Select sentences that fit within limit
        var selected: [(text: String, score: Int, index: Int)] = []
        var currentLength = 0
        
        // Always include first sentence if it fits
        if let first = scored.first(where: { $0.index == 0 }), first.text.count < limit {
            selected.append(first)
            currentLength = first.text.count
        }
        
        // Add high-scoring sentences
        for item in scored {
            if item.index == 0 { continue } // Already added
            
            if currentLength + item.text.count + 2 <= limit {
                selected.append(item)
                currentLength += item.text.count + 2
            }
        }
        
        // Sort by original position for readability
        selected.sort { $0.index < $1.index }
        
        return selected.map { $0.text }.joined(separator: " ")
    }
    
    /// Extract atomic memories from text (one per fact)
    /// Returns array of extracted memory strings
    func extractAtomicMemories(_ raw: String) -> [ExtractedContent] {
        var results: [ExtractedContent] = []
        
        let sentences = splitIntoSentences(raw)
        let classifier = SectorClassifier.shared
        
        for sentence in sentences {
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count > 10 else { continue }
            
            // Classify this sentence
            let classification = classifier.classify(trimmed)
            
            // Check if it's worth keeping
            let (worth, _) = classifier.isWorthRemembering(trimmed)
            guard worth else { continue }
            
            // Convert to third person
            let thirdPerson = convertToThirdPerson(trimmed)
            
            // Calculate confidence based on pattern strength
            let confidence = calculateConfidence(trimmed, classification: classification)
            
            // Extract tags
            let tags = extractTags(trimmed)
            
            results.append(ExtractedContent(
                content: thirdPerson,
                sector: classification.primary,
                confidence: confidence,
                tags: tags
            ))
        }
        
        return results
    }
    
    // MARK: - Sentence Scoring
    
    private func scoreSentence(_ sentence: String, index: Int, sector: MemorySector?) -> Int {
        var score = 0
        let lowercased = sentence.lowercased()
        
        // Position bonuses
        if index == 0 { score += 10 } // First sentence
        if index == 1 { score += 5 }  // Second sentence
        
        // Header patterns
        if sentence.hasPrefix("#") || matchesPattern(sentence, "^[A-Z][A-Z\\s]+:") {
            score += 8
        }
        if matchesPattern(sentence, "^[A-Z][a-z]+:") {
            score += 6
        }
        
        // Date patterns (high value for episodic)
        if matchesPattern(sentence, "\\d{4}-\\d{2}-\\d{2}") {
            score += 7
        }
        let months = "january|february|march|april|may|june|july|august|september|october|november|december"
        if matchesPattern(lowercased, "\\b(\(months))\\s+\\d+") {
            score += 5
        }
        
        // Quantitative data
        if matchesPattern(sentence, "\\$\\d+|\\d+\\s*(miles|dollars|years|months|km|days|hours)") {
            score += 4
        }
        
        // Named entities (capitalized multi-word)
        if matchesPattern(sentence, "\\b[A-Z][a-z]+(?:\\s+[A-Z][a-z]+)+") {
            score += 3
        }
        
        // Action verbs (events, changes)
        let actionVerbs = "bought|purchased|serviced|visited|went|got|received|paid|earned|learned|discovered|found|saw|met|completed|finished|fixed|implemented|created|updated|added|removed|resolved|built|started|launched"
        if matchesPattern(lowercased, "\\b(\(actionVerbs))\\b") {
            score += 4
        }
        
        // Question patterns
        if matchesPattern(lowercased, "\\b(who|what|when|where|why|how)\\b") {
            score += 2
        }
        
        // Prefer concise sentences
        if sentence.count < 80 {
            score += 2
        }
        
        // First person (personal relevance)
        if matchesPattern(lowercased, "\\b(i|my|me)\\b") {
            score += 1
        }
        
        // Sector-specific bonuses
        if let sector = sector {
            switch sector {
            case .semantic:
                if matchesPattern(lowercased, "\\b(is|are|means|defined)\\b") { score += 3 }
            case .episodic:
                if matchesPattern(lowercased, "\\b(yesterday|today|happened|went)\\b") { score += 3 }
            case .procedural:
                if matchesPattern(lowercased, "\\b(step|first|then|next|how to)\\b") { score += 3 }
            case .emotional:
                if matchesPattern(lowercased, "\\b(feel|felt|love|hate|like)\\b") { score += 3 }
            case .reflective:
                if matchesPattern(lowercased, "\\b(think|believe|realize|learned)\\b") { score += 3 }
            }
        }
        
        return score
    }
    
    // MARK: - Third Person Conversion
    
    /// Convert first-person text to third person ("I like X" → "User likes X")
    private func convertToThirdPerson(_ text: String) -> String {
        var result = text
        
        // Common first-person to third-person replacements
        let replacements: [(pattern: String, replacement: String)] = [
            ("\\bI am\\b", "User is"),
            ("\\bI'm\\b", "User is"),
            ("\\bI have\\b", "User has"),
            ("\\bI've\\b", "User has"),
            ("\\bI will\\b", "User will"),
            ("\\bI'll\\b", "User will"),
            ("\\bI would\\b", "User would"),
            ("\\bI'd\\b", "User would"),
            ("\\bI can\\b", "User can"),
            ("\\bI could\\b", "User could"),
            ("\\bI was\\b", "User was"),
            ("\\bI like\\b", "User likes"),
            ("\\bI love\\b", "User loves"),
            ("\\bI hate\\b", "User hates"),
            ("\\bI prefer\\b", "User prefers"),
            ("\\bI want\\b", "User wants"),
            ("\\bI need\\b", "User needs"),
            ("\\bI think\\b", "User thinks"),
            ("\\bI believe\\b", "User believes"),
            ("\\bI feel\\b", "User feels"),
            ("\\bI work\\b", "User works"),
            ("\\bI live\\b", "User lives"),
            ("\\bI know\\b", "User knows"),
            ("\\bmy\\b", "User's"),
            ("\\bMy\\b", "User's"),
            ("\\bme\\b", "User"),
            ("\\bI\\b", "User"),
        ]
        
        for (pattern, replacement) in replacements {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: replacement)
            }
        }
        
        return result
    }
    
    // MARK: - Confidence Calculation
    
    private func calculateConfidence(_ text: String, classification: ClassificationResult) -> Double {
        var confidence = classification.confidence
        
        // Boost confidence for clear personal statements
        let personalPatterns = [
            "\\b(my name is|i am called)\\b",
            "\\b(i live in|i'm from)\\b",
            "\\b(i work (at|as|for))\\b",
            "\\b(allergic to)\\b",
        ]
        
        for pattern in personalPatterns {
            if matchesPattern(text.lowercased(), pattern) {
                confidence = min(1.0, confidence + 0.2)
                break
            }
        }
        
        // Penalize very short or very long
        if text.count < 20 {
            confidence *= 0.7
        } else if text.count > 500 {
            confidence *= 0.8
        }
        
        return confidence
    }
    
    // MARK: - Tag Extraction
    
    private func extractTags(_ text: String) -> [String] {
        var tags: [String] = []
        let lowercased = text.lowercased()
        
        // Category tags
        if matchesPattern(lowercased, "\\b(name|called|named)\\b") { tags.append("identity") }
        if matchesPattern(lowercased, "\\b(live|from|location|city|country)\\b") { tags.append("location") }
        if matchesPattern(lowercased, "\\b(work|job|profession|career)\\b") { tags.append("work") }
        if matchesPattern(lowercased, "\\b(like|love|prefer|enjoy)\\b") { tags.append("preference") }
        if matchesPattern(lowercased, "\\b(allergic|allergy|medical|health)\\b") { tags.append("health") }
        if matchesPattern(lowercased, "\\b(goal|want to|planning|building)\\b") { tags.append("goals") }
        if matchesPattern(lowercased, "\\b(learn|know|skill|expert)\\b") { tags.append("skills") }
        
        return tags
    }
    
    // MARK: - Helpers
    
    private func splitIntoSentences(_ text: String) -> [String] {
        // Split on sentence-ending punctuation
        let pattern = "(?<=[.!?])\\s+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [text]
        }
        
        let range = NSRange(text.startIndex..., in: text)
        var sentences: [String] = []
        var lastEnd = text.startIndex
        
        regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let matchRange = match?.range,
                  let range = Range(matchRange, in: text) else { return }
            
            let sentence = String(text[lastEnd..<range.lowerBound])
            if !sentence.isEmpty {
                sentences.append(sentence.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            lastEnd = range.upperBound
        }
        
        // Add remaining text
        let remaining = String(text[lastEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !remaining.isEmpty {
            sentences.append(remaining)
        }
        
        return sentences
    }
    
    private func matchesPattern(_ text: String, _ pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return false
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }
}

// MARK: - Extracted Content

struct ExtractedContent {
    let content: String
    let sector: MemorySector
    let confidence: Double
    let tags: [String]
    
    /// Convert to ExtractedMemoryData for compatibility
    func toExtractedMemoryData() -> ExtractedMemoryData {
        ExtractedMemoryData(
            content: content,
            type: sector.toMemoryType(),
            confidence: confidence,
            tags: tags,
            expiresAt: nil
        )
    }
}

