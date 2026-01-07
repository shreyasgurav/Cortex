//
//  ExtractedMemory.swift
//  Cortex
//
//  Structured memory extracted from raw captures using AI
//  This is what Supermemory calls "memories" - facts, insights, preferences
//

import Foundation

/// A structured memory extracted from raw captured text
/// Unlike the raw Memory (which stores what user typed), this stores
/// meaningful facts and insights extracted by AI
struct ExtractedMemory: Identifiable, Codable, Hashable {
    let id: String
    let createdAt: Date
    
    /// The extracted fact/insight/preference
    var content: String
    
    /// Type of memory
    var type: MemoryType
    
    /// Confidence score (0.0 - 1.0)
    var confidence: Double
    
    /// Tags for categorization
    var tags: [String]
    
    /// Source raw memory ID (links back to the original capture)
    let sourceMemoryId: String
    
    /// Source app where this was captured from
    let sourceApp: String
    
    /// Whether this memory is still relevant (can be "forgotten")
    var isActive: Bool
    
    /// Optional expiry date (some memories are time-sensitive)
    var expiresAt: Date?
    
    /// Relationships to other memories
    var relatedMemoryIds: [String]
    
    /// Optional embedding vector for semantic search
    let embedding: [Double]?
    
    /// Model used to generate embedding
    let embeddingModel: String?
    
    /// Convenience: does this memory have an embedding
    var hasEmbedding: Bool {
        embedding != nil && !(embedding?.isEmpty ?? true)
    }
    
    // MARK: - Display Helpers
    
    var preview: String {
        if content.count > 100 {
            return String(content.prefix(100)) + "..."
        }
        return content
    }
    
    var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }
    
    var typeIcon: String {
        type.icon
    }
}

/// Types of memories that can be extracted
enum MemoryType: String, Codable, CaseIterable {
    case fact = "fact"                      // "User's name is John"
    case preference = "preference"          // "User prefers dark mode"
    case belief = "belief"                  // "User believes AI will change everything"
    case goal = "goal"                      // "User wants to learn Swift"
    case relationship = "relationship"      // "User works with Sarah on Project X"
    case event = "event"                    // "User has a meeting tomorrow at 3pm"
    case skill = "skill"                    // "User knows Python and Swift"
    case project = "project"                // "User is building an app called Cortex"
    case insight = "insight"                // General insight about user
    case question = "question"              // Questions user frequently asks
    case instruction = "instruction"        // How user wants things done
    
    var displayName: String {
        switch self {
        case .fact: return "Fact"
        case .preference: return "Preference"
        case .belief: return "Belief"
        case .goal: return "Goal"
        case .relationship: return "Relationship"
        case .event: return "Event"
        case .skill: return "Skill"
        case .project: return "Project"
        case .insight: return "Insight"
        case .question: return "Question"
        case .instruction: return "Instruction"
        }
    }
    
    var icon: String {
        switch self {
        case .fact: return "info.circle"
        case .preference: return "heart"
        case .belief: return "brain.head.profile"
        case .goal: return "target"
        case .relationship: return "person.2"
        case .event: return "calendar"
        case .skill: return "hammer"
        case .project: return "folder"
        case .insight: return "lightbulb"
        case .question: return "questionmark.circle"
        case .instruction: return "list.bullet"
        }
    }
}

/// Result of memory worthiness check
struct MemoryWorthinessResult: Codable {
    let isWorthRemembering: Bool
    let reason: String
    let suggestedTypes: [MemoryType]
}

/// Result of memory extraction
struct MemoryExtractionResult: Codable {
    let memories: [ExtractedMemoryData]
    let wasProcessed: Bool
    let processingNote: String?
}

/// Data structure for extracted memory (before creating ExtractedMemory)
struct ExtractedMemoryData: Codable {
    let content: String
    let type: MemoryType
    let confidence: Double
    let tags: [String]
    let expiresAt: Date?
}

