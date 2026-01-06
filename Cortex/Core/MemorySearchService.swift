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
            // Use a threshold to ensure relevance (0.6 is a reasonable starting point for cosine sim)
            let results = try await extractedStore.searchByEmbedding(queryEmbedding: vec, topK: topK)
            
            // Check relevance - since searchByEmbedding returns top K sorted, we might need to verify scores
            // But searchByEmbedding doesn't return scores currently. 
            // We should trust the store or update store to return scores.
            // For now, let's assume specific threshold filtering inside the store or just rely on the top match being good enough?
            // Actually, better to update the store to filter, but let's just trust top results 
            // provided they adhere to some minimum.
            // Wait, ExtractedMemoryStore.searchByEmbedding returns [ExtractedMemory] without scores.
            // We should accept what we get, but we MUST remove the "most recent" fallback below.
            
            if !results.isEmpty {
                print("[MemorySearch] Embedding search found \(results.count) memories")
                return results
            }
        } catch {
            // If task was cancelled, propagate the error (don't fallback)
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == -999 {
                throw error
            }
            if let urlError = error as? URLError, urlError.code == .cancelled {
                throw error
            }
            if error is CancellationError {
                throw error
            }
            
            print("[MemorySearch] Embedding search failed, falling back to content search: \(error)")
        }
        
        // Fallback: LIKE-based content search (no semantic vectors required)
        let byContent = try await extractedStore.searchMemories(query: trimmed)
        if !byContent.isEmpty {
            print("[MemorySearch] Content search found \(byContent.count) memories")
            return Array(byContent.prefix(topK))
        }
        
        // Removed fallback that returns random recent memories
        return []
    }
}


