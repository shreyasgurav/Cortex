//
//  SectorClassifier.swift
//  Cortex
//
//  Fast regex-based memory classification
//  Ported from OpenMemory's classify_content() in hsg.py
//
//  Classifies text into sectors WITHOUT using LLM (instant, free)
//

import Foundation

/// Memory sectors (categories) based on cognitive science
enum MemorySector: String, CaseIterable, Codable {
    case semantic     // Facts, knowledge, definitions
    case episodic     // Events, experiences, personal history
    case procedural   // How-to, processes, instructions
    case emotional    // Feelings, reactions, sentiments
    case reflective   // Insights, beliefs, self-reflection
    
    var displayName: String {
        switch self {
        case .semantic: return "Fact"
        case .episodic: return "Event"
        case .procedural: return "How-To"
        case .emotional: return "Feeling"
        case .reflective: return "Insight"
        }
    }
    
    var icon: String {
        switch self {
        case .semantic: return "brain.head.profile"
        case .episodic: return "calendar"
        case .procedural: return "list.number"
        case .emotional: return "heart.fill"
        case .reflective: return "lightbulb"
        }
    }
    
    /// Decay rate (lambda) - how fast memories of this type fade
    var decayLambda: Double {
        switch self {
        case .semantic: return 0.01      // Facts decay slowly
        case .episodic: return 0.03      // Events decay moderately
        case .procedural: return 0.02    // Procedures decay slowly
        case .emotional: return 0.05     // Emotions fade faster
        case .reflective: return 0.015   // Insights persist
        }
    }
    
    /// Base weight for scoring
    var weight: Double {
        switch self {
        case .semantic: return 1.0
        case .episodic: return 1.2
        case .procedural: return 1.1
        case .emotional: return 0.9
        case .reflective: return 1.0
        }
    }
}

/// Configuration for each sector's classification patterns
struct SectorConfig {
    let sector: MemorySector
    let patterns: [NSRegularExpression]
    let weight: Double
    let decayLambda: Double
}

/// Result of classification
struct ClassificationResult {
    let primary: MemorySector
    let additional: [MemorySector]
    let confidence: Double
    let scores: [MemorySector: Double]
}

/// Fast regex-based classifier (no LLM needed)
final class SectorClassifier {
    
    // MARK: - Singleton (for convenience)
    
    @MainActor static let shared = SectorClassifier()
    
    // MARK: - Patterns
    
    private let sectorConfigs: [SectorConfig]
    
    init() {
        self.sectorConfigs = Self.buildSectorConfigs()
    }
    
    // MARK: - Classification
    
    /// Classify content into sectors using regex patterns
    /// Returns primary sector + additional related sectors
    func classify(_ content: String, metadata: [String: Any]? = nil) -> ClassificationResult {
        // Check if sector is explicitly provided in metadata
        if let metaSector = metadata?["sector"] as? String,
           let sector = MemorySector(rawValue: metaSector) {
            return ClassificationResult(
                primary: sector,
                additional: [],
                confidence: 1.0,
                scores: [sector: 1.0]
            )
        }
        
        // Score each sector based on pattern matches
        var scores: [MemorySector: Double] = [:]
        
        for config in sectorConfigs {
            var score: Double = 0
            
            for pattern in config.patterns {
                let range = NSRange(content.startIndex..., in: content)
                let matches = pattern.numberOfMatches(in: content, options: [], range: range)
                if matches > 0 {
                    score += Double(matches) * config.weight
                }
            }
            
            scores[config.sector] = score
        }
        
        // Sort by score descending
        let sorted = scores.sorted { $0.value > $1.value }
        
        guard let (primarySector, primaryScore) = sorted.first, primaryScore > 0 else {
            // Default to semantic if no patterns match
            return ClassificationResult(
                primary: .semantic,
                additional: [],
                confidence: 0.2,
                scores: scores
            )
        }
        
        // Find additional sectors that score above threshold
        let threshold = max(1.0, primaryScore * 0.3)
        let additional = sorted.dropFirst()
            .filter { $0.value > 0 && $0.value >= threshold }
            .map { $0.key }
        
        // Calculate confidence based on score difference
        let secondScore = sorted.dropFirst().first?.value ?? 0
        let confidence = min(1.0, primaryScore / (primaryScore + secondScore + 1))
        
        return ClassificationResult(
            primary: primarySector,
            additional: additional,
            confidence: confidence,
            scores: scores
        )
    }
    
    /// Quick check if content is worth remembering (heuristic)
    func isWorthRemembering(_ content: String) -> (worth: Bool, reason: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Too short
        if trimmed.count < 10 {
            return (false, "Text too short")
        }
        
        // Check for garbage patterns
        let lowercased = trimmed.lowercased()
        
        let skipPatterns = [
            "^(hi|hello|hey|thanks|thank you|ok|okay|sure|yes|no|bye|goodbye)$",
            "^(search for|find|look up|google)\\s",
            "^\\s*$",
            "^[a-z0-9._%+-]+@[a-z0-9.-]+\\.[a-z]{2,}$",  // Email only
        ]
        
        for pattern in skipPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(lowercased.startIndex..., in: lowercased)
                if regex.firstMatch(in: lowercased, options: [], range: range) != nil {
                    return (false, "Common phrase or command")
                }
            }
        }
        
        // Check for personal information patterns (HIGH VALUE)
        let highValuePatterns = [
            "\\b(my name is|i am|i'm)\\b",
            "\\b(i live in|i'm from|i work at|i work as)\\b",
            "\\b(i like|i love|i prefer|i hate|i dislike)\\b",
            "\\b(i'm building|i'm working on|my project)\\b",
            "\\b(allergic to|allergy|medical|health)\\b",
            "\\b(goal|want to|planning to|trying to)\\b",
        ]
        
        for pattern in highValuePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(lowercased.startIndex..., in: lowercased)
                if regex.firstMatch(in: lowercased, options: [], range: range) != nil {
                    return (true, "Contains personal information")
                }
            }
        }
        
        // Default: worth remembering if reasonably long
        if trimmed.count >= 20 {
            return (true, "Sufficient content length")
        }
        
        return (false, "No significant content detected")
    }
    
    // MARK: - Pattern Building
    
    private static func buildSectorConfigs() -> [SectorConfig] {
        return [
            // SEMANTIC: Facts, knowledge, definitions
            SectorConfig(
                sector: .semantic,
                patterns: buildPatterns([
                    "\\b(is|are|was|were)\\s+(a|an|the)\\b",
                    "\\b(means|refers to|defined as|known as)\\b",
                    "\\b(fact|information|data|knowledge)\\b",
                    "\\b(name is|called|named)\\b",
                    "\\b(location|address|lives? in|from)\\b",
                    "\\b(works? (at|as|for)|job|profession|occupation)\\b",
                    "\\b(age|born|birthday)\\b",
                    "\\b(email|phone|contact)\\b",
                ]),
                weight: 1.0,
                decayLambda: 0.01
            ),
            
            // EPISODIC: Events, experiences, personal history
            SectorConfig(
                sector: .episodic,
                patterns: buildPatterns([
                    "\\b(yesterday|today|tomorrow|last week|this week)\\b",
                    "\\b(went to|visited|met|saw|attended)\\b",
                    "\\b(happened|occurred|event|experience)\\b",
                    "\\b(remember when|recall|the time when)\\b",
                    "\\b(meeting|appointment|scheduled|calendar)\\b",
                    "\\b(bought|purchased|ordered|received)\\b",
                    "\\b(trip|travel|vacation|visited)\\b",
                    "\\d{4}[-/]\\d{2}[-/]\\d{2}",  // Dates
                    "\\b(january|february|march|april|may|june|july|august|september|october|november|december)\\s+\\d+",
                ]),
                weight: 1.2,
                decayLambda: 0.03
            ),
            
            // PROCEDURAL: How-to, processes, instructions
            SectorConfig(
                sector: .procedural,
                patterns: buildPatterns([
                    "\\b(how to|steps to|guide|tutorial)\\b",
                    "\\b(first|then|next|finally|step \\d+)\\b",
                    "\\b(process|procedure|method|approach)\\b",
                    "\\b(install|setup|configure|implement)\\b",
                    "\\b(use|using|usage|run|execute)\\b",
                    "\\b(command|code|script|function)\\b",
                    "\\b(click|press|select|choose|enter)\\b",
                ]),
                weight: 1.1,
                decayLambda: 0.02
            ),
            
            // EMOTIONAL: Feelings, reactions, sentiments
            SectorConfig(
                sector: .emotional,
                patterns: buildPatterns([
                    "\\b(feel|feeling|felt|emotion)\\b",
                    "\\b(happy|sad|angry|frustrated|excited|anxious|worried)\\b",
                    "\\b(love|hate|like|dislike|prefer)\\b",
                    "\\b(amazing|terrible|awful|wonderful|great)\\b",
                    "\\b(stressed|relieved|overwhelmed|calm)\\b",
                    "\\b(miss|regret|appreciate|grateful)\\b",
                ]),
                weight: 0.9,
                decayLambda: 0.05
            ),
            
            // REFLECTIVE: Insights, beliefs, self-reflection
            SectorConfig(
                sector: .reflective,
                patterns: buildPatterns([
                    "\\b(believe|think|opinion|view)\\b",
                    "\\b(realize|realized|insight|learned)\\b",
                    "\\b(should|could|would|might)\\b",
                    "\\b(goal|aspiration|dream|vision)\\b",
                    "\\b(value|important|priority|matter)\\b",
                    "\\b(reflect|consider|ponder|wonder)\\b",
                    "\\b(decision|choice|chose|decided)\\b",
                ]),
                weight: 1.0,
                decayLambda: 0.015
            ),
        ]
    }
    
    private static func buildPatterns(_ patterns: [String]) -> [NSRegularExpression] {
        return patterns.compactMap { pattern in
            try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        }
    }
}

// MARK: - Mapping to existing MemoryType

extension MemorySector {
    /// Map sector to existing MemoryType for compatibility
    func toMemoryType() -> MemoryType {
        switch self {
        case .semantic: return .fact
        case .episodic: return .event
        case .procedural: return .instruction
        case .emotional: return .preference
        case .reflective: return .insight
        }
    }
}

extension MemoryType {
    /// Map existing MemoryType to sector
    var sector: MemorySector {
        switch self {
        case .fact: return .semantic
        case .event: return .episodic
        case .instruction: return .procedural
        case .preference, .belief: return .emotional
        case .insight, .goal, .project: return .reflective
        case .skill: return .procedural
        case .relationship: return .episodic
        case .question: return .semantic
        }
    }
}

