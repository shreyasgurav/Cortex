//
//  HybridMemorySearch.swift
//  Cortex
//
//  OpenMemory-style hybrid memory search
//  Ported from hsg_query() in hsg.py
//
//  Search flow:
//  1. Classify query into sectors
//  2. Create embeddings for query
//  3. Vector search (cosine similarity)
//  4. Hybrid scoring: similarity + keywords + waypoints + recency + tags
//  5. Waypoint expansion for low-confidence results
//  6. Retrieval reinforcement (boost salience of retrieved memories)
//

import Foundation

// MARK: - Search Result

/// Scored memory result with debug info
struct HybridSearchResult {
    let memory: ExtractedMemory
    let score: Double
    let path: [String]  // Waypoint path
    
    // Debug info
    var debugInfo: SearchDebugInfo?
}

struct SearchDebugInfo {
    let similarityAdjusted: Double
    let tokenOverlap: Double
    let recencyScore: Double
    let waypointWeight: Double
    let tagMatch: Double
    let sectorPenalty: Double
    let keywordBoost: Double
}

// MARK: - Search Filters

struct SearchFilters {
    var sectors: [MemorySector]?
    var minSalience: Double?
    var startTime: Date?
    var endTime: Date?
    var debug: Bool = false
}

// MARK: - HybridMemorySearch

/// OpenMemory-style hybrid search combining multiple signals
@MainActor
final class HybridMemorySearch {
    
    // MARK: - Dependencies
    
    private let embeddingService: EmbeddingService
    private let extractedStore: ExtractedMemoryStore
    private let classifier: SectorClassifier
    private let salienceManager: SalienceManager
    private let waypointManager: WaypointManager
    
    // MARK: - Cache
    
    private var cache: [String: (results: [HybridSearchResult], timestamp: Date)] = [:]
    private let cacheTTL: TimeInterval = 60 // 60 seconds
    
    // MARK: - Scoring Weights (from OpenMemory)
    
    private let weights = ScoringWeights.default
    
    init(
        embeddingService: EmbeddingService,
        extractedStore: ExtractedMemoryStore
    ) {
        self.embeddingService = embeddingService
        self.extractedStore = extractedStore
        self.classifier = SectorClassifier()
        self.salienceManager = SalienceManager()
        self.waypointManager = WaypointManager()
    }
    
    // MARK: - Main Search API
    
    /// Search for relevant memories using hybrid scoring
    /// Implements OpenMemory's hsg_query() logic
    func search(
        query: String,
        limit: Int = 10,
        filters: SearchFilters = SearchFilters()
    ) async throws -> [HybridSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        
        // Check cache
        let cacheKey = "\(trimmed):\(limit):\(String(describing: filters.sectors))"
        if let cached = cache[cacheKey], Date().timeIntervalSince(cached.timestamp) < cacheTTL {
            print("[HybridSearch] Cache hit for: \(trimmed.prefix(30))...")
            return cached.results
        }
        
        print("[HybridSearch] 🔍 Searching: '\(trimmed.prefix(50))...'")
        
        // Step 1: Classify query
        let queryClassification = classifier.classify(trimmed)
        let queryTokens = SimHash.tokenOverlap(query: trimmed, content: "").description // Get tokens
        
        print("[HybridSearch] Query sector: \(queryClassification.primary.rawValue)")
        
        // Step 2: Determine sectors to search
        let sectors = filters.sectors ?? MemorySector.allCases
        
        // Step 3: Create query embedding
        let queryEmbedding: [Double]
        do {
            let (vec, _) = try await embeddingService.embed(text: trimmed)
            queryEmbedding = vec
        } catch {
            print("[HybridSearch] Embedding failed, falling back to keyword search: \(error)")
            return try await fallbackKeywordSearch(query: trimmed, limit: limit)
        }
        
        // Step 4: Vector search
        let vectorResults = try await extractedStore.searchByEmbedding(
            queryEmbedding: queryEmbedding,
            topK: limit * 3,  // Get more candidates for scoring
            minScore: 0.3     // Lower threshold, we'll score properly later
        )
        
        var candidateIds = Set(vectorResults.map { $0.id })
        print("[HybridSearch] Vector search found \(candidateIds.count) candidates")
        
        // Step 5: Calculate average similarity for confidence check
        let allMemories = try await extractedStore.fetchAllMemories()
        let similarities = vectorResults.compactMap { mem -> Double? in
            guard let emb = mem.embedding else { return nil }
            return cosineSimilarity(queryEmbedding, emb)
        }
        let avgSimilarity = similarities.isEmpty ? 0 : similarities.reduce(0, +) / Double(similarities.count)
        let highConfidence = avgSimilarity >= 0.55
        
        print("[HybridSearch] Avg similarity: \(String(format: "%.3f", avgSimilarity)), high confidence: \(highConfidence)")
        
        // Step 6: Waypoint expansion (if low confidence)
        var waypointExpansion: [(id: String, weight: Double, path: [String])] = []
        if !highConfidence {
            let waypoints = try await extractedStore.fetchAllWaypoints()
            waypointExpansion = waypointManager.expandViaWaypoints(
                seedIds: Array(candidateIds),
                waypoints: waypoints,
                maxExpansion: limit * 2
            )
            for exp in waypointExpansion {
                candidateIds.insert(exp.id)
            }
            print("[HybridSearch] Expanded via waypoints: +\(waypointExpansion.count) candidates")
        }
        
        // Step 7: Score all candidates
        var scoredResults: [HybridSearchResult] = []
        
        for memoryId in candidateIds {
            guard let memory = allMemories.first(where: { $0.id == memoryId }) else { continue }
            
            // Apply filters
            if let minSalience = filters.minSalience, memory.currentSalience < minSalience { continue }
            if let startTime = filters.startTime, memory.createdAt < startTime { continue }
            if let endTime = filters.endTime, memory.createdAt > endTime { continue }
            
            // Calculate similarity
            var bestSimilarity: Double = 0
            if let memEmb = memory.embedding {
                bestSimilarity = cosineSimilarity(queryEmbedding, memEmb)
            }
            
            // Apply sector penalty
            let memorySector = memory.memorySector
            let querySector = queryClassification.primary
            let sectorPenalty = SectorRelationships.weight(from: querySector, to: memorySector)
            let adjustedSimilarity = bestSimilarity * sectorPenalty
            
            // Get waypoint weight
            let waypointEntry = waypointExpansion.first { $0.id == memoryId }
            let waypointWeight = waypointEntry?.weight ?? 0
            let path = waypointEntry?.path ?? [memoryId]
            
            // Calculate token overlap
            let tokenOverlap = SimHash.tokenOverlap(query: trimmed, content: memory.content)
            
            // Calculate keyword boost
            let keywordBoost = computeKeywordBoost(query: trimmed, content: memory.content)
            
            // Calculate recency score
            let recencyScore = memory.recencyScore
            
            // Calculate tag match
            let tagMatch = computeTagMatch(queryTokens: trimmed, tags: memory.tags)
            
            // Compute final hybrid score
            let finalScore = salienceManager.computeHybridScore(
                similarity: adjustedSimilarity,
                tokenOverlap: tokenOverlap,
                waypointWeight: waypointWeight,
                recencyScore: recencyScore,
                tagMatch: tagMatch,
                keywordScore: keywordBoost
            )
            
            var result = HybridSearchResult(
                memory: memory,
                score: finalScore,
                path: path
            )
            
            if filters.debug {
                result.debugInfo = SearchDebugInfo(
                    similarityAdjusted: adjustedSimilarity,
                    tokenOverlap: tokenOverlap,
                    recencyScore: recencyScore,
                    waypointWeight: waypointWeight,
                    tagMatch: tagMatch,
                    sectorPenalty: sectorPenalty,
                    keywordBoost: keywordBoost
                )
            }
            
            scoredResults.append(result)
        }
        
        // Step 8: Sort and limit
        let sorted = scoredResults.sorted { $0.score > $1.score }
        let topResults = Array(sorted.prefix(limit))
        
        print("[HybridSearch] ✓ Returning \(topResults.count) results (top score: \(String(format: "%.3f", topResults.first?.score ?? 0)))")
        
        // Step 9: Reinforce retrieved memories
        await reinforceRetrievedMemories(topResults)
        
        // Cache results
        cache[cacheKey] = (topResults, Date())
        
        return topResults
    }
    
    // MARK: - Fallback Search
    
    private func fallbackKeywordSearch(query: String, limit: Int) async throws -> [HybridSearchResult] {
        let results = try await extractedStore.searchMemories(query: query)
        return results.prefix(limit).map { memory in
            HybridSearchResult(
                memory: memory,
                score: 0.5, // Neutral score for keyword matches
                path: [memory.id]
            )
        }
    }
    
    // MARK: - Scoring Helpers
    
    private func computeKeywordBoost(query: String, content: String) -> Double {
        let queryWords = Set(query.lowercased().split(separator: " ").map { String($0) })
        let contentWords = Set(content.lowercased().split(separator: " ").map { String($0) })
        
        let overlap = queryWords.intersection(contentWords).count
        let boost = Double(overlap) / max(1, Double(queryWords.count))
        
        return boost * 0.15 // 15% max boost for keyword overlap
    }
    
    private func computeTagMatch(queryTokens: String, tags: [String]) -> Double {
        guard !tags.isEmpty else { return 0 }
        
        let queryWords = Set(queryTokens.lowercased().split(separator: " ").map { String($0) })
        var matches = 0
        
        for tag in tags {
            let tagLower = tag.lowercased()
            if queryWords.contains(tagLower) {
                matches += 2 // Exact match
            } else {
                for word in queryWords {
                    if tagLower.contains(word) || word.contains(tagLower) {
                        matches += 1 // Partial match
                    }
                }
            }
        }
        
        return min(1.0, Double(matches) / max(1, Double(tags.count * 2)))
    }
    
    private func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        
        var dot: Double = 0
        var normA: Double = 0
        var normB: Double = 0
        
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        
        let denom = sqrt(normA) * sqrt(normB)
        return denom == 0 ? 0 : dot / denom
    }
    
    // MARK: - Retrieval Reinforcement
    
    /// Boost salience of retrieved memories (OpenMemory-style)
    private func reinforceRetrievedMemories(_ results: [HybridSearchResult]) async {
        for result in results {
            // Boost salience
            let boostedSalience = salienceManager.reinforceOnRetrieval(currentSalience: result.memory.salience)
            
            // Update in store
            try? await extractedStore.boostSalience(
                memoryId: result.memory.id,
                boost: boostedSalience - result.memory.salience
            )
            
            // Propagate to linked memories via waypoints
            if result.path.count > 1 {
                await propagateReinforcementToLinked(result: result, newSalience: boostedSalience)
            }
        }
    }
    
    private func propagateReinforcementToLinked(result: HybridSearchResult, newSalience: Double) async {
        let waypoints = try? await extractedStore.fetchWaypoints(forSource: result.memory.id)
        guard let waypoints = waypoints, !waypoints.isEmpty else { return }
        
        let allMemories = (try? await extractedStore.fetchAllMemories()) ?? []
        var currentSaliences: [String: Double] = [:]
        for mem in allMemories {
            currentSaliences[mem.id] = mem.salience
        }
        
        let updates = waypointManager.propagateReinforcement(
            sourceId: result.memory.id,
            sourceSalience: newSalience,
            waypoints: waypoints,
            currentSaliences: currentSaliences
        )
        
        for update in updates {
            let boost = update.newSalience - (currentSaliences[update.memoryId] ?? 0)
            if boost > 0 {
                try? await extractedStore.boostSalience(memoryId: update.memoryId, boost: boost)
            }
        }
    }
    
    // MARK: - Quick Search (No LLM)
    
    /// Quick search without LLM slot extraction
    func quickSearch(
        query: String,
        limit: Int = 5
    ) async throws -> [ExtractedMemory] {
        let results = try await search(query: query, limit: limit)
        return results.map { $0.memory }
    }
    
    // MARK: - Context Injection
    
    /// Get memories formatted for injection into AI prompt
    func getContextForPrompt(
        query: String,
        limit: Int = 3
    ) async throws -> String? {
        let results = try await search(query: query, limit: limit)
        
        guard !results.isEmpty else { return nil }
        
        let contextLines = results.map { "- \($0.memory.content)" }
        return contextLines.joined(separator: "\n")
    }
}


