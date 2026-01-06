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
    private let llmService: LLMService
    
    init(embeddingService: EmbeddingService, extractedStore: ExtractedMemoryStore, llmService: LLMService) {
        self.embeddingService = embeddingService
        self.extractedStore = extractedStore
        self.llmService = llmService
    }
    
    /// Semantic search for memories related to given text.
    /// Uses LLM to extract key search queries for better accuracy.
    func searchRelatedMemories(for text: String, topK: Int = 5) async throws -> [ExtractedMemory] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        
        var searchQueries = [trimmed]
        
        // If text is long enough, generate specific search queries
        // Simple heuristic: > 5 words
        if trimmed.split(separator: " ").count > 5 {
            let extracted = await generateSearchQueries(from: trimmed)
            if !extracted.isEmpty {
                print("[MemorySearch] Extracted queries: \(extracted)")
                searchQueries.append(contentsOf: extracted)
            }
        }
        
        // Use a set to track unique memory IDs
        var uniqueMemories: [String: ExtractedMemory] = [:]
        
        // Perform searches in parallel
        // We use a task group
        await withTaskGroup(of: [ExtractedMemory].self) { group in
            for query in searchQueries {
                group.addTask {
                    do {
                        return try await self.searchSingleQuery(query, topK: topK)
                    } catch {
                        print("[MemorySearch] Query failed for '\(query)': \(error)")
                        return []
                    }
                }
            }
            
            for await results in group {
                for memory in results {
                    uniqueMemories[memory.id] = memory
                }
            }
        }
        
        // Convert to array and maybe sort by relevance?
        // Since we don't have unified scores easily, let's just return unique ones
        // If we had scores, we could re-rank.
        // For now, simple de-duplication is a big step up.
        
        let finalResults = Array(uniqueMemories.values)
        print("[MemorySearch] Total unique memories found: \(finalResults.count)")
        return finalResults
    }
    
    private func searchSingleQuery(_ text: String, topK: Int) async throws -> [ExtractedMemory] {
        // Try embedding-based search
        do {
            let (vec, _) = try await embeddingService.embed(text: text)
            let results = try await extractedStore.searchByEmbedding(queryEmbedding: vec, topK: topK)
            
            if !results.isEmpty {
                 // print("[MemorySearch] Found \(results.count) results via embedding for '\(text)'")
                return results
            } else {
                 print("[MemorySearch] Minimal/No results via embedding for '\(text)'")
            }
        } catch {
            // Check cancellation
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == -999 { throw error }
            if let urlError = error as? URLError, urlError.code == .cancelled { throw error }
            if error is CancellationError { throw error }
            
            print("[MemorySearch] Embedding search failed for '\(text)': \(error)")
        }
        
        // Fallback: Content search
        let byContent = try await extractedStore.searchMemories(query: text)
        if !byContent.isEmpty {
             print("[MemorySearch] Found \(byContent.count) results via content search for '\(text)'")
        } else {
             print("[MemorySearch] No results via content search for '\(text)'")
        }
        return Array(byContent.prefix(topK))
    }
    
    private func generateSearchQueries(from text: String) async -> [String] {
        let systemPrompt = """
        You are a search query generator. Given a user's input, extract 1-3 specific keywords or short phrases to search their memory database for relevant facts.
        Return ONLY a JSON array of strings. Example: ["john email", "budget report"]
        """
        
        do {
            let queries = try await llmService.completeJSON(
                prompt: text,
                systemPrompt: systemPrompt,
                responseType: [String].self
            )
            return queries
        } catch {
            print("[MemorySearch] Failed to generate queries: \(error)")
            return []
        }
    }
}


