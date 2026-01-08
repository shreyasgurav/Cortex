//
//  MemoryConsolidator.swift
//  Cortex
//
//  Merges similar memories and strengthens recurring patterns
//

import Foundation
import Combine

@MainActor
final class MemoryConsolidator: ObservableObject {
    
    private let embeddingService: EmbeddingService
    private let llmService: LLMService
    private let extractedMemoryStore: ExtractedMemoryStore
    
    init(
        embeddingService: EmbeddingService,
        llmService: LLMService,
        extractedMemoryStore: ExtractedMemoryStore
    ) {
        self.embeddingService = embeddingService
        self.llmService = llmService
        self.extractedMemoryStore = extractedMemoryStore
    }
    
    // MARK: - Deduplication & Merging
    
    /// Decision after comparing two memories
    struct MergeDecision: Codable {
        let decision: String  // duplicate, update, enrich, strengthen, separate
        let reason: String
        let mergedContent: String?
        let newConfidence: Double
    }

    enum ConsolidationAction {
        case merge(ExtractedMemory)
        case strengthen(ExtractedMemory)
        case keepBoth
    }
    
    /// Determine the relationship between a new memory and an existing one
    func decideMergeStrategy(new: ExtractedMemoryData, existing: ExtractedMemory) async throws -> MergeDecision {
        let prompt = """
        Compare these two memories about the same user:
        
        EXISTING MEMORY:
        Content: \(existing.content)
        Type: \(existing.type.rawValue)
        Confidence: \(existing.confidence)
        
        NEW MEMORY:
        Content: \(new.content)
        Type: \(new.type.rawValue)
        Confidence: \(new.confidence)
        
        TASK: Determine the relationship.
        
        OPTIONS:
        1. duplicate: Same info, rephrased
        2. update: New info is more current/accurate
        3. enrich: Combine details naturally. ALWAYS use third person (e.g., "User...") even if inputs use "I".
        4. strengthen: Same info, boosts confidence
        5. separate: Different enough to keep both
        
        Respond with JSON:
        {
            "decision": "duplicate|update|enrich|strengthen|separate",
            "reason": "Brief explanation",
            "mergedContent": "Natural combination in third person (starting with 'User...') if enrich",
            "newConfidence": 0.0-1.0
        }
        """
        
        let systemPrompt = "You are a memory consolidation system. Deduplicate while preserving details in the third person (e.g., 'User...')."
        
        return try await llmService.completeJSON(
            prompt: prompt,
            systemPrompt: systemPrompt,
            responseType: MergeDecision.self
        )
    }
    
    /// Find potential semantic duplicates in the store
    func findSimilarMemories(for embedding: [Double], topK: Int = 5) async throws -> [ExtractedMemory] {
        return try await extractedMemoryStore.searchByEmbedding(
            queryEmbedding: embedding,
            topK: topK,
            minScore: 0.8  // Threshold for semantic similarity
        )
    }

    /// Consolidate a new memory by checking against existing ones
    func consolidate(_ newMemoryData: ExtractedMemoryData, embedding: [Double], sourceMemory: Memory) async throws -> Bool {
        let similar = try await findSimilarMemories(for: embedding)
        
        for existing in similar {
            let decision = try await decideMergeStrategy(new: newMemoryData, existing: existing)
            
            switch decision.decision {
            case "duplicate":
                print("[MemoryConsolidator] Duplicate found, skipping: \(newMemoryData.content)")
                return true // Already "saved" (as a duplicate)
                
            case "update":
                print("[MemoryConsolidator] Updating existing memory: \(existing.id)")
                try await extractedMemoryStore.deleteMemory(id: existing.id)
                // The caller will save the "new" one as the replacement
                return false 
                
            case "enrich":
                print("[MemoryConsolidator] Enriching memory: \(existing.id)")
                try await extractedMemoryStore.deleteMemory(id: existing.id)
                let enriched = ExtractedMemory(
                    id: existing.id,
                    createdAt: existing.createdAt,
                    content: decision.mergedContent ?? newMemoryData.content,
                    type: newMemoryData.type,
                    confidence: decision.newConfidence,
                    tags: Array(Set(existing.tags + newMemoryData.tags)),
                    sourceMemoryId: sourceMemory.id,
                    sourceApp: sourceMemory.appName,
                    isActive: true,
                    expiresAt: newMemoryData.expiresAt,
                    relatedMemoryIds: existing.relatedMemoryIds + [existing.id],
                    embedding: embedding,
                    embeddingModel: existing.embeddingModel
                )
                try await extractedMemoryStore.saveMemory(enriched, embedding: embedding, embeddingModel: existing.embeddingModel)
                return true
                
            case "strengthen":
                print("[MemoryConsolidator] Strengthening confidence for: \(existing.id)")
                var updated = existing
                updated.confidence = decision.newConfidence
                try await extractedMemoryStore.deleteMemory(id: existing.id)
                try await extractedMemoryStore.saveMemory(updated, embedding: existing.embedding, embeddingModel: existing.embeddingModel)
                return true
                
            default:
                continue // Keep both
            }
        }
        
        return false // No consolidation took place, save normally
    }
}
