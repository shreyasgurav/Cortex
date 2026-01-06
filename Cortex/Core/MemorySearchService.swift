//
//  MemorySearchService.swift
//  Cortex
//
//  Uses embeddings + ExtractedMemoryStore for semantic search.
//

import Foundation

actor MemorySearchService {
    
    private let embeddingService: EmbeddingService
    private let extractedStore: ExtractedMemoryStore
    
    init(embeddingService: EmbeddingService, extractedStore: ExtractedMemoryStore) {
        self.embeddingService = embeddingService
        self.extractedStore = extractedStore
    }
    
    /// Semantic search for memories related to given text.
    /// Tries embeddings first; if that fails or returns nothing, falls back to
    /// simple content-based search.
    func searchRelatedMemories(for text: String, topK: Int = 5) async throws -> [ExtractedMemory] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        
        // Try embedding-based search
        var anyResults: [ExtractedMemory] = []
        do {
            let (vec, _) = try await embeddingService.embed(text: trimmed)
            let results = try await extractedStore.searchByEmbedding(queryEmbedding: vec, topK: topK)
            if !results.isEmpty {
                print("[MemorySearch] Embedding search found \(results.count) memories")
                return results
            }
        } catch {
            // Log and fall back
            print("[MemorySearch] Embedding search failed, falling back to content search: \(error)")
        }
        
        // Fallback: LIKE-based content search (no semantic vectors required)
        let byContent = try await extractedStore.searchMemories(query: trimmed)
        if !byContent.isEmpty {
            print("[MemorySearch] Content search found \(byContent.count) memories")
            return Array(byContent.prefix(topK))
        } else {
            print("[MemorySearch] Content search found 0 memories for query: \"\(trimmed)\"")
        }
        
        // Final fallback: if there are any extracted memories at all, just return most recent ones
        let all = try await extractedStore.fetchAllMemories()
        if !all.isEmpty {
            print("[MemorySearch] Fallback: returning \(min(topK, all.count)) most recent memories")
            return Array(all.prefix(topK))
        }
        
        return []
    }
}


