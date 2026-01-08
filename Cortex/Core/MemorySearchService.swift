//
//  MemorySearchService.swift
//  Cortex
//
//  Slot-aware memory retrieval using
//  entity + attribute extraction, embeddings,
//  scoring, and fallback search.
//

import Foundation

// MARK: - Public Types

struct MemoryEntitySlot: Decodable {
    let name: String
    let attributes: [String]
}

struct MemorySlotExtraction: Decodable {
    let entities: [MemoryEntitySlot]
}

enum SearchQueryType {
    case entity
    case attribute
    case fallback
}

struct SearchQuery {
    let text: String
    let weight: Double
    let type: SearchQueryType
}

struct ScoredMemory {
    let memory: ExtractedMemory
    var score: Double
}

// MARK: - MemorySearchService

actor MemorySearchService {

    private let embeddingService: EmbeddingService
    private let extractedStore: ExtractedMemoryStore
    private let llmService: LLMService

    init(
        embeddingService: EmbeddingService,
        extractedStore: ExtractedMemoryStore,
        llmService: LLMService
    ) {
        self.embeddingService = embeddingService
        self.extractedStore = extractedStore
        self.llmService = llmService
    }

    // MARK: - Public API

    func searchRelatedMemories(
        for inputText: String,
        topK: Int = 5
    ) async throws -> [ExtractedMemory] {

        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // 1️⃣ Strip task / intent language
        let coreText = stripIntent(from: trimmed)
        guard !coreText.isEmpty else { return [] }

        // 2️⃣ Extract entity + attribute slots
        let slotExtraction = await extractSlots(from: coreText)

        // 3️⃣ Build weighted search queries
        let queries = buildSearchQueries(
            from: slotExtraction,
            fallbackText: coreText
        )

        // 4️⃣ Execute searches and score results
        let scored = try await performSearches(queries)

        // 5️⃣ Rank + return
        let sorted = scored
            .sorted { $0.score > $1.score }
            .prefix(topK)
            .map { $0.memory }

        return Array(sorted)
    }

    // MARK: - Step 1: Intent Stripping

    private func stripIntent(from text: String) -> String {
        let stopPhrases = [
            "write a mail to",
            "send a mail to",
            "send an email to",
            "write an email to",
            "tell me about",
            "can you find",
            "help me with",
            "i need to",
            "i want to",
            "please"
        ]

        var result = text.lowercased()
        for phrase in stopPhrases {
            result = result.replacingOccurrences(of: phrase, with: "")
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Step 2: Slot Extraction (LLM)

    private func extractSlots(from text: String) async -> MemorySlotExtraction {
        let systemPrompt = """
        You extract memory lookup slots from user input.

        Rules:
        1. Identify ENTITIES (people, organizations, places, projects).
        2. For each entity, infer ATTRIBUTES the user may need.
        3. Ignore action verbs (write, send, tell, help).
        4. Be conservative. Do not hallucinate entities.

        Return JSON in this format:
        {
          "entities": [
            {
              "name": "college",
              "attributes": ["name", "email"]
            }
          ]
        }

        Only return JSON.
        """

        do {
            let result = try await llmService.completeJSON(
                prompt: "INPUT: \"\(text)\"",
                systemPrompt: systemPrompt,
                responseType: MemorySlotExtraction.self
            )
            return result
        } catch {
            print("[MemorySearch] Slot extraction failed: \(error)")
            return MemorySlotExtraction(entities: [])
        }
    }

    // MARK: - Step 3: Query Construction

    private func buildSearchQueries(
        from extraction: MemorySlotExtraction,
        fallbackText: String
    ) -> [SearchQuery] {

        var queries: [SearchQuery] = []

        if extraction.entities.isEmpty {
            // No entities found? Use fallback text with higher weight to capture intent
            queries.append(
                SearchQuery(
                    text: fallbackText,
                    weight: 0.4,
                    type: .fallback
                )
            )
        } else {
            for entity in extraction.entities {
                // Entity name (highest weight)
                queries.append(
                    SearchQuery(
                        text: entity.name,
                        weight: 1.0,
                        type: .entity
                    )
                )

                // Entity attributes
                for attribute in entity.attributes {
                    queries.append(
                        SearchQuery(
                            text: "\(entity.name) \(attribute)",
                            weight: 0.9,
                            type: .attribute
                        )
                    )
                }
            }

            // Fallback semantic query (lowest priority when we HAVE slots)
            queries.append(
                SearchQuery(
                    text: fallbackText,
                    weight: 0.15,
                    type: .fallback
                )
            )
        }

        return queries
    }

    // MARK: - Step 4: Search Execution + Scoring

    private func performSearches(
        _ queries: [SearchQuery]
    ) async throws -> [ScoredMemory] {

        var memoryScores: [String: ScoredMemory] = [:]

        // Associating results with the specific query that found them to avoid over-scoring
        await withTaskGroup(of: (SearchQuery, [ExtractedMemory]).self) { group in
            for query in queries {
                group.addTask {
                    let results = (try? await self.searchSingleQuery(query.text)) ?? []
                    return (query, results)
                }
            }

            for await (query, results) in group {
                for memory in results {
                    let baseScore = memoryScores[memory.id]?.score ?? 0
                    let addedScore = scoreContribution(
                        for: memory,
                        query: query
                    )

                    memoryScores[memory.id] = ScoredMemory(
                        memory: memory,
                        score: baseScore + addedScore
                    )
                }
            }
        }

        return Array(memoryScores.values)
    }

    // MARK: - Step 5: Single Query Search

    private func searchSingleQuery(
        _ text: String
    ) async throws -> [ExtractedMemory] {

        // Primary: Embedding search
        do {
            let (vec, _) = try await embeddingService.embed(text: text)
            let results = try await extractedStore.searchByEmbedding(
                queryEmbedding: vec,
                topK: 8
            )
            if !results.isEmpty {
                return results
            }
        } catch {
            if error is CancellationError { throw error }
            print("[MemorySearch] Embedding search failed for '\(text)': \(error)")
        }

        // Fallback: Keyword/content search
        let byContent = try await extractedStore.searchMemories(query: text)
        return Array(byContent.prefix(5))
    }

    // MARK: - Step 6: Scoring

    private func scoreContribution(
        for memory: ExtractedMemory,
        query: SearchQuery
    ) -> Double {

        let content = memory.content.lowercased()
        let queryText = query.text.lowercased()

        // Match check: ensure this memory relates to THIS query
        // Checks both content and tags for consistency with storage layer
        guard content.contains(queryText) || memory.tags.contains(where: { $0.lowercased() == queryText }) else {
            // Found via embedding but no keyword match? Give reduced weight
            return query.weight * 0.5
        }

        var score = query.weight

        // Small boost for attribute queries as they are more specific
        if query.type == .attribute {
            score += 0.2
        }

        // Age decay
        score -= memoryAgePenalty(memory)

        return score
    }

    private func memoryAgePenalty(_ memory: ExtractedMemory) -> Double {
        let daysOld = abs(memory.createdAt.timeIntervalSinceNow) / 86_400
        if daysOld > 365 { return 0.4 }
        if daysOld > 180 { return 0.2 }
        return 0
    }
}
