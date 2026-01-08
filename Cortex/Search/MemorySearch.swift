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
        
        // Step 0: Strip intent phrases and extract core content
        let coreQuery = stripIntentPhrases(trimmed)
        let queryKeywords = extractKeywords(coreQuery)
        
        print("[HybridSearch] Core query: '\(coreQuery)', keywords: \(queryKeywords)")
        
        // Step 1: Classify query
        let queryClassification = classifier.classify(coreQuery)
        
        print("[HybridSearch] Query sector: \(queryClassification.primary.rawValue)")
        
        // Step 2: Determine sectors to search
        let sectors = filters.sectors ?? MemorySector.allCases
        
        // Step 3: Create query embedding (use core query for better matching)
        let queryEmbedding: [Double]
        do {
            let (vec, _) = try await embeddingService.embed(text: coreQuery)
            queryEmbedding = vec
        } catch {
            print("[HybridSearch] Embedding failed, falling back to keyword search: \(error)")
            return try await fallbackKeywordSearch(query: coreQuery, keywords: queryKeywords, limit: limit)
        }
        
        // Step 4: Vector search with lower threshold
        let vectorResults = try await extractedStore.searchByEmbedding(
            queryEmbedding: queryEmbedding,
            topK: limit * 4,  // Get more candidates
            minScore: 0.2     // Lower threshold to catch more
        )
        
        var candidateIds = Set(vectorResults.map { $0.id })
        print("[HybridSearch] Vector search found \(candidateIds.count) candidates")
        
        // Step 4b: Also do keyword search for each extracted keyword
        let keywordMatches = try await keywordSearch(keywords: queryKeywords, limit: limit * 2)
        for mem in keywordMatches {
            candidateIds.insert(mem.id)
        }
        print("[HybridSearch] +\(keywordMatches.count) keyword matches, total: \(candidateIds.count)")
        
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
            
            // Calculate token overlap using extracted keywords
            let tokenOverlap = computeTokenOverlap(keywords: queryKeywords, content: memory.content)
            
            // Calculate keyword boost
            let keywordBoost = computeKeywordBoost(keywords: queryKeywords, content: memory.content, tags: memory.tags)
            
            // Calculate recency score
            let recencyScore = memory.recencyScore
            
            // Calculate tag match
            let tagMatch = computeTagMatch(keywords: queryKeywords, tags: memory.tags)
            
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
    
    // MARK: - Query Processing
    
    /// Strip intent phrases like "write a mail to", "help me with", etc.
    private func stripIntentPhrases(_ text: String) -> String {
        let intentPhrases = [
            "write a mail to",
            "send a mail to",
            "write an email to",
            "send an email to",
            "write mail to",
            "send mail to",
            "tell me about",
            "can you find",
            "help me with",
            "i need to",
            "i want to",
            "please help me",
            "please",
            "can you",
            "could you",
            "what do i know about",
            "what is",
            "who is",
            "where is",
            "remind me about",
            "find information about",
            "search for"
        ]
        
        var result = text.lowercased()
        for phrase in intentPhrases {
            result = result.replacingOccurrences(of: phrase, with: " ")
        }
        
        // Clean up extra spaces
        result = result.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Extract important keywords from query (nouns, names, topics)
    private func extractKeywords(_ text: String) -> [String] {
        // Common stop words to filter out
        let stopWords: Set<String> = [
            "a", "an", "the", "is", "are", "was", "were", "be", "been", "being",
            "have", "has", "had", "do", "does", "did", "will", "would", "could",
            "should", "may", "might", "must", "shall", "can", "need", "dare",
            "ought", "used", "to", "of", "in", "for", "on", "with", "at", "by",
            "from", "as", "into", "through", "during", "before", "after", "above",
            "below", "between", "under", "again", "further", "then", "once", "here",
            "there", "when", "where", "why", "how", "all", "each", "few", "more",
            "most", "other", "some", "such", "no", "nor", "not", "only", "own",
            "same", "so", "than", "too", "very", "just", "and", "but", "if", "or",
            "because", "as", "until", "while", "about", "against", "between",
            "into", "through", "during", "before", "after", "above", "below",
            "this", "that", "these", "those", "i", "me", "my", "myself", "we",
            "our", "ours", "ourselves", "you", "your", "yours", "yourself",
            "yourselves", "he", "him", "his", "himself", "she", "her", "hers",
            "herself", "it", "its", "itself", "they", "them", "their", "theirs",
            "themselves", "what", "which", "who", "whom", "this", "that", "these",
            "those", "am", "is", "are", "was", "were", "be", "been", "being"
        ]
        
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { word in
                word.count >= 2 &&
                !stopWords.contains(word)
            }
        
        // Return unique keywords, preserving order
        var seen = Set<String>()
        return words.filter { seen.insert($0).inserted }
    }
    
    // MARK: - Keyword Search
    
    /// Search by individual keywords
    private func keywordSearch(keywords: [String], limit: Int) async throws -> [ExtractedMemory] {
        var results: [ExtractedMemory] = []
        
        for keyword in keywords.prefix(5) { // Limit to top 5 keywords
            let matches = try await extractedStore.searchMemories(query: keyword)
            for mem in matches.prefix(limit / 2) {
                if !results.contains(where: { $0.id == mem.id }) {
                    results.append(mem)
                }
            }
        }
        
        return results
    }
    
    // MARK: - Fallback Search
    
    private func fallbackKeywordSearch(query: String, keywords: [String], limit: Int) async throws -> [HybridSearchResult] {
        var results: [ExtractedMemory] = []
        
        // Search by full query
        let fullQueryResults = try await extractedStore.searchMemories(query: query)
        results.append(contentsOf: fullQueryResults)
        
        // Search by each keyword
        for keyword in keywords.prefix(3) {
            let keywordResults = try await extractedStore.searchMemories(query: keyword)
            for mem in keywordResults {
                if !results.contains(where: { $0.id == mem.id }) {
                    results.append(mem)
                }
            }
        }
        
        return results.prefix(limit).map { memory in
            HybridSearchResult(
                memory: memory,
                score: 0.5, // Neutral score for keyword matches
                path: [memory.id]
            )
        }
    }
    
    // MARK: - Scoring Helpers
    
    /// Compute token overlap between keywords and memory content
    private func computeTokenOverlap(keywords: [String], content: String) -> Double {
        guard !keywords.isEmpty else { return 0 }
        
        let contentLower = content.lowercased()
        var matchCount = 0
        
        for keyword in keywords {
            if contentLower.contains(keyword) {
                matchCount += 1
            }
        }
        
        return Double(matchCount) / Double(keywords.count)
    }
    
    /// Compute keyword boost (higher for more keyword matches)
    private func computeKeywordBoost(keywords: [String], content: String, tags: [String]) -> Double {
        guard !keywords.isEmpty else { return 0 }
        
        let contentLower = content.lowercased()
        let tagsLower = tags.map { $0.lowercased() }
        var boost: Double = 0
        
        for keyword in keywords {
            // Content match
            if contentLower.contains(keyword) {
                boost += 0.1
            }
            
            // Exact tag match (higher value)
            if tagsLower.contains(keyword) {
                boost += 0.15
            }
            
            // Partial tag match
            for tag in tagsLower {
                if tag.contains(keyword) || keyword.contains(tag) {
                    boost += 0.05
                }
            }
        }
        
        return min(0.3, boost) // Cap at 30% boost
    }
    
    /// Compute tag match score
    private func computeTagMatch(keywords: [String], tags: [String]) -> Double {
        guard !tags.isEmpty, !keywords.isEmpty else { return 0 }
        
        let keywordSet = Set(keywords)
        var matches = 0
        
        for tag in tags {
            let tagLower = tag.lowercased()
            if keywordSet.contains(tagLower) {
                matches += 2 // Exact match
            } else {
                for keyword in keywords {
                    if tagLower.contains(keyword) || keyword.contains(tagLower) {
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


