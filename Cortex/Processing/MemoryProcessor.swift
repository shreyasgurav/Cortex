//
//  MemoryProcessor.swift
//  Cortex
//
//  AI-powered service that processes raw captures and extracts meaningful memories
//  
//  NEW: OpenMemory-style processing with two paths:
//    1. Fast path: Regex classification + sentence scoring (no LLM, instant)
//    2. LLM path: Full AI extraction for complex cases
//
//  Features:
//    - SimHash deduplication (fuzzy matching)
//    - Salience with decay
//    - Waypoint creation (memory linking)
//

import Foundation
import Combine

/// Processes raw captured text and extracts structured memories
@MainActor
final class MemoryProcessor: ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var isProcessing: Bool = false
    @Published private(set) var processedCount: Int = 0
    @Published private(set) var lastError: String?
    @Published var isEnabled: Bool = false
    
    /// Use fast (regex-based) extraction instead of LLM
    /// Set to false to use LLM-based extraction (requires API key)
    @Published var useFastExtraction: Bool = false
    
    // MARK: - Dependencies
    
    private var llmService: LLMService
    private var config: LLMConfig
    internal var extractedMemoryStore: ExtractedMemoryStore?  // Internal so CaptureCoordinator can access
    private var embeddingService: EmbeddingService
    
    // MARK: - OpenMemory-style components
    
    private let classifier = SectorClassifier.shared
    private let essenceExtractor = EssenceExtractor.shared
    private let salienceManager = SalienceManager.shared
    private let waypointManager = WaypointManager()
    
    // MARK: - Queue for processing
    
    private var processingQueue: [Memory] = []
    private var isProcessingQueue: Bool = false
    
    /// Current segment for memory organization
    private var currentSegment: Int = 0
    private let segmentSize: Int = 100 // Memories per segment
    
    // MARK: - Initialization
    
    init(extractedMemoryStore: ExtractedMemoryStore? = nil, config: LLMConfig = .default) {
        self.config = config
        self.llmService = LLMService(config: config)
        self.extractedMemoryStore = extractedMemoryStore
        self.embeddingService = EmbeddingService()
    }
    
    func setExtractedMemoryStore(_ store: ExtractedMemoryStore?) {
        self.extractedMemoryStore = store
    }
    
    // MARK: - Configuration
    
    func configure(provider: LLMProvider, apiKey: String?, model: String? = nil, baseURL: String? = nil) {
        var newConfig = config
        newConfig.provider = provider
        newConfig.apiKey = apiKey
        if let model = model {
            newConfig.model = model
        }
        if let baseURL = baseURL {
            newConfig.baseURL = baseURL
        }
        self.config = newConfig
        
        Task {
            await llmService.updateConfig(newConfig)
        }
        
        // Ollama doesn't require a key; others do
        switch provider {
        case .ollama:
            isEnabled = true
        default:
            isEnabled = !(apiKey ?? "").isEmpty
        }
        
        print("[MemoryProcessor] Configured with \(provider.displayName) (enabled: \(isEnabled))")
    }
    
    /// Configure from environment variables (.env loaded into process env)
    /// Returns true if configuration succeeded (has key or using Ollama)
    @discardableResult
    func configureFromEnvironment() -> Bool {
        let env = ProcessInfo.processInfo.environment
        
        // Provider
        let providerString = env["CORTEX_LLM_PROVIDER"]?.lowercased() ?? "openai"
        let provider = LLMProvider(rawValue: providerString) ?? .openai
        
        // Model / base URL
        let model = env["CORTEX_LLM_MODEL"]
        let baseURL = env["CORTEX_LLM_BASE_URL"] ?? env["OLLAMA_BASE_URL"]
        
        // API key selection
        var apiKey: String?
        switch provider {
        case .openai:
            apiKey = env["OPENAI_API_KEY"]
        case .anthropic:
            apiKey = env["ANTHROPIC_API_KEY"]
        case .ollama:
            // Ollama doesn't require a key
            apiKey = nil
        }
        
        // For non-Ollama providers, require a key
        if provider != .ollama, (apiKey ?? "").isEmpty {
            print("[MemoryProcessor] No API key found for provider \(provider.displayName). Set OPENAI_API_KEY or ANTHROPIC_API_KEY.")
            isEnabled = false
            return false
        }
        
        // Configure embedding service (OpenAI embeddings)
        var embedConfig = EmbeddingConfig.default
        embedConfig.provider = provider == .openai ? .openai : .unsupported
        embedConfig.apiKey = apiKey
        embedConfig.model = env["CORTEX_EMBED_MODEL"] ?? embedConfig.model
        embedConfig.baseURL = baseURL ?? embedConfig.baseURL
        Task { await embeddingService.updateConfig(embedConfig) }
        
        configure(provider: provider, apiKey: apiKey, model: model, baseURL: baseURL)
        return isEnabled
    }
    
    // MARK: - Main Processing Methods
    
    /// Add a raw memory to the processing queue
    func queueForProcessing(_ memory: Memory) async {
        guard isEnabled else {
            print("[MemoryProcessor] Not enabled, skipping: \(memory.preview)")
            return
        }
        
        // Avoid re-processing the same raw memory if already processed
        if let store = extractedMemoryStore,
           (try? await store.hasBeenProcessed(rawMemoryId: memory.id)) == true {
            print("[MemoryProcessor] Already processed raw memory \(memory.id), skipping")
            return
        }
        
        processingQueue.append(memory)
        print("[MemoryProcessor] Queued memory for processing: \(memory.preview)")
        
        // Start processing if not already running
        if !isProcessingQueue {
            Task {
                await processQueue()
            }
        }
    }
    
    /// Save extracted memories directly with embeddings (used for AI-first filtering)
    /// NOW: Uses OpenMemory-style SimHash deduplication, salience, and waypoints
    func saveExtractedMemories(_ memoriesData: [ExtractedMemoryData], sourceMemory: Memory) async throws {
        guard let store = extractedMemoryStore else {
            print("[MemoryProcessor] No extracted memory store available")
            return
        }
        
        var enriched: [(memory: ExtractedMemory, embedding: [Double]?, embeddingModel: String?)] = []
        
        for data in memoriesData {
            // OpenMemory-style: SimHash deduplication (fuzzy matching)
            let simhash = SimHash.compute(data.content)
            
            if let existing = try? await store.findNearDuplicates(data.content) {
                // Near-duplicate found - boost salience instead of creating new
                print("[MemoryProcessor] 🔁 Near-duplicate found, boosting salience: \(data.content.prefix(40))...")
                try? await store.boostSalience(memoryId: existing.id, boost: 0.15)
                continue
            }
            
            // Check exact content match as fallback
            do {
                if try await store.hasMemory(withContent: data.content) {
                    print("[MemoryProcessor] Skipping exact duplicate: \(data.content.prefix(50))...")
                    continue
                }
            } catch {
                print("[MemoryProcessor] Failed to check for duplicate: \(error)")
            }
            
            // Generate embedding
            let embeddingResult: ([Double]?, String?)
            if isEnabled {
                do {
                    let (vec, model) = try await embeddingService.embed(text: data.content)
                    embeddingResult = (vec, model)
                    print("[MemoryProcessor] ✓ Generated embedding for: \(data.content.prefix(50))...")
                } catch {
                    print("[MemoryProcessor] Embedding failed: \(error)")
                    embeddingResult = (nil, nil)
                }
            } else {
                embeddingResult = (nil, nil)
            }
            
            // Classify into sector
            let classification = classifier.classify(data.content)
            
            // Calculate initial salience based on classification
            let initialSalience = salienceManager.calculateInitialSalience(classification: classification)
            
            let mem = ExtractedMemory(
                id: UUID().uuidString,
                createdAt: Date(),
                content: data.content,
                type: data.type,
                confidence: data.confidence,
                tags: data.tags,
                sourceMemoryId: sourceMemory.id,
                sourceApp: sourceMemory.appName,
                isActive: true,
                expiresAt: data.expiresAt,
                relatedMemoryIds: [],
                embedding: embeddingResult.0,
                embeddingModel: embeddingResult.1,
                // OpenMemory-style fields
                simhash: simhash,
                sector: classification.primary.rawValue,
                salience: initialSalience,
                lastSeenAt: Date(),
                decayLambda: classification.primary.decayLambda,
                segment: currentSegment
            )
            enriched.append((mem, embeddingResult.0, embeddingResult.1))
            
            // Create waypoint to most similar existing memory
            if let embedding = embeddingResult.0 {
                await createWaypointForNewMemory(memoryId: mem.id, embedding: embedding, store: store)
            }
        }
        
        try await store.saveMemories(enriched)
        try await store.logProcessing(
            rawMemoryId: sourceMemory.id,
            wasWorthRemembering: true,
            reason: nil,
            extractedCount: enriched.count
        )
        
        // Update segment if needed
        await updateSegmentIfNeeded(store: store)
        
        print("[MemoryProcessor] ✓ Saved \(enriched.count) extracted memories with OpenMemory features")
    }
    
    // MARK: - Fast Extraction (OpenMemory-style, no LLM)
    
    /// Process memory using fast regex-based extraction (no LLM needed)
    /// Returns extracted memories without making any API calls
    func processMemoryFast(_ memory: Memory) async -> MemoryExtractionResult {
        let text = memory.text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Quick worthiness check (no LLM)
        let (worth, reason) = classifier.isWorthRemembering(text)
        
        guard worth else {
            return MemoryExtractionResult(
                memories: [],
                wasProcessed: false,
                processingNote: reason
            )
        }
        
        // Extract atomic memories using sentence scoring
        let extracted = essenceExtractor.extractAtomicMemories(text)
        
        guard !extracted.isEmpty else {
            // Fallback: use whole text as single memory
            let classification = classifier.classify(text)
            let fallback = ExtractedMemoryData(
                content: EssenceExtractor.shared.extractEssence(text, sector: classification.primary),
                type: classification.primary.toMemoryType(),
                confidence: classification.confidence,
                tags: [],
                expiresAt: nil
            )
            return MemoryExtractionResult(
                memories: [fallback],
                wasProcessed: true,
                processingNote: "Fast extraction (fallback)"
            )
        }
        
        // Convert to ExtractedMemoryData
        let memories = extracted.map { $0.toExtractedMemoryData() }
        
        return MemoryExtractionResult(
            memories: memories,
            wasProcessed: true,
            processingNote: "Fast extraction (regex + scoring)"
        )
    }
    
    /// Quick worthiness check without LLM
    func checkWorthinessFast(_ memory: Memory) -> MemoryWorthinessResult {
        let text = memory.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let (worth, reason) = classifier.isWorthRemembering(text)
        
        if worth {
            let classification = classifier.classify(text)
            return MemoryWorthinessResult(
                isWorthRemembering: true,
                reason: reason,
                suggestedTypes: [classification.primary.toMemoryType()]
            )
        } else {
            return MemoryWorthinessResult(
                isWorthRemembering: false,
                reason: reason,
                suggestedTypes: []
            )
        }
    }
    
    // MARK: - Waypoint Creation
    
    private func createWaypointForNewMemory(memoryId: String, embedding: [Double], store: ExtractedMemoryStore) async {
        do {
            let existingMemories = try await store.fetchMemoriesWithEmbeddings()
            
            if let best = waypointManager.findBestWaypointTarget(
                newMemoryId: memoryId,
                newEmbedding: embedding,
                existingMemories: existingMemories
            ) {
                let waypoint = waypointManager.createWaypoint(
                    sourceId: memoryId,
                    targetId: best.targetId,
                    weight: best.similarity
                )
                try await store.saveWaypoint(waypoint)
                print("[MemoryProcessor] 🔗 Created waypoint: \(memoryId) → \(best.targetId) (sim: \(String(format: "%.2f", best.similarity)))")
            }
        } catch {
            print("[MemoryProcessor] Failed to create waypoint: \(error)")
        }
    }
    
    private func updateSegmentIfNeeded(store: ExtractedMemoryStore) async {
        do {
            let allMemories = try await store.fetchAllMemories()
            let currentSegmentCount = allMemories.filter { $0.segment == currentSegment }.count
            
            if currentSegmentCount >= segmentSize {
                currentSegment += 1
                print("[MemoryProcessor] 📦 Rotated to segment \(currentSegment)")
            }
        } catch {
            // Ignore segment rotation errors
        }
    }
    
    /// Process all queued memories
    private func processQueue() async {
        guard !isProcessingQueue else { return }
        isProcessingQueue = true
        isProcessing = true
        
        while !processingQueue.isEmpty {
            let memory = processingQueue.removeFirst()
            
            do {
                let result = try await processMemory(memory)
                if result.wasProcessed {
                    processedCount += 1
                    print("[MemoryProcessor] ✓ Extracted \(result.memories.count) memories from: \(memory.preview)")
                    
                    // Persist extracted memories
                    if let store = extractedMemoryStore {
                        // Generate embeddings per memory (best-effort)
                        var enriched: [(memory: ExtractedMemory, embedding: [Double]?, embeddingModel: String?)] = []
                        for data in result.memories {
                            let embeddingResult: ([Double]?, String?)
                            if isEnabled {
                                do {
                                    let (vec, model) = try await embeddingService.embed(text: data.content)
                                    embeddingResult = (vec, model)
                                } catch {
                                    embeddingResult = (nil, nil)
                                }
                            } else {
                                embeddingResult = (nil, nil)
                            }
                            
                            let mem = ExtractedMemory(
                                id: UUID().uuidString,
                                createdAt: Date(),
                                content: data.content,
                                type: data.type,
                                confidence: data.confidence,
                                tags: data.tags,
                                sourceMemoryId: memory.id,
                                sourceApp: memory.appName,
                                isActive: true,
                                expiresAt: data.expiresAt,
                                relatedMemoryIds: [],
                                embedding: embeddingResult.0,
                                embeddingModel: embeddingResult.1
                            )
                            enriched.append((mem, embeddingResult.0, embeddingResult.1))
                        }
                        
                        try await store.saveMemories(enriched)
                        try await store.logProcessing(
                            rawMemoryId: memory.id,
                            wasWorthRemembering: true,
                            reason: nil,
                            extractedCount: enriched.count
                        )
                    }
                    
                } else {
                    print("[MemoryProcessor] Skipped (not worth remembering): \(memory.preview)")
                    
                    if let store = extractedMemoryStore {
                        try await store.logProcessing(
                            rawMemoryId: memory.id,
                            wasWorthRemembering: false,
                            reason: result.processingNote,
                            extractedCount: 0
                        )
                    }
                }
            } catch {
                lastError = error.localizedDescription
                print("[MemoryProcessor] Error processing memory: \(error)")
            }
            
            // Small delay between processing to avoid rate limits
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        
        isProcessingQueue = false
        isProcessing = false
    }
    
    /// Process a single memory with context: filter + extract
    func processMemory(_ memory: Memory, context: String? = nil) async throws -> MemoryExtractionResult {
        // Stage 1: Check if worth remembering
        let worthiness: MemoryWorthinessResult
        do {
            worthiness = try await checkWorthiness(memory, context: context)
        } catch {
            let text = memory.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let isWorth = text.count >= 10
            print("[MemoryProcessor] Worthiness check failed, using heuristic (len=\(text.count), worth=\(isWorth)): \(error)") // Keep original print for more info
            if !isWorth {
                return MemoryExtractionResult(
                    memories: [],
                    wasProcessed: false,
                    processingNote: "Heuristic: text too short"
                )
            }
            worthiness = MemoryWorthinessResult(
                isWorthRemembering: true,
                reason: "Heuristic fallback",
                suggestedTypes: [.insight]
            )
        }
        
        if !worthiness.isWorthRemembering {
            return MemoryExtractionResult(
                memories: [],
                wasProcessed: false,
                processingNote: worthiness.reason
            )
        }
        
        // Stage 2: Extract structured memories
        var extractedMemories: [ExtractedMemoryData]
        do {
            extractedMemories = try await extractMemories(memory, suggestedTypes: worthiness.suggestedTypes, context: context)
        } catch {
            print("[MemoryProcessor] Extraction failed, using raw text as a single memory: \(error)") // Keep original print for more info
            let text = memory.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                return MemoryExtractionResult(
                    memories: [],
                    wasProcessed: false,
                    processingNote: "Extraction failed"
                )
            }
            let fallback = ExtractedMemoryData(
                content: text,
                type: .insight,
                confidence: 0.4,
                tags: [],
                expiresAt: nil
            )
            extractedMemories = [fallback]
        }
        
        // If LLM returned no memories at all, also fall back to a single generic one
        if extractedMemories.isEmpty {
            let text = memory.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                print("[MemoryProcessor] LLM returned 0 memories, falling back to generic memory for: \(memory.preview)")
                let fallback = ExtractedMemoryData(
                    content: text,
                    type: .insight,
                    confidence: 0.5,
                    tags: [],
                    expiresAt: nil
                )
                extractedMemories = [fallback]
            } else {
                return MemoryExtractionResult(
                    memories: [],
                    wasProcessed: false,
                    processingNote: "Empty text after extraction"
                )
            }
        }
        
        return MemoryExtractionResult(
            memories: extractedMemories,
            wasProcessed: true,
            processingNote: nil
        )
    }
    
    // MARK: - Stage 1: Worthiness Check
    
    /// Check if a memory is worth saving
    func checkWorthiness(_ memory: Memory, context: String? = nil) async throws -> MemoryWorthinessResult {
        let contextSection = context != nil ? "\nCONTEXT FROM PREVIOUS MESSAGES:\n\(context!)\n" : ""
        let prompt = """
        You are a memory extraction system analyzing user text from the app "\(memory.appName)".
        \(contextSection)
        Determine if the NEW TEXT below contains information worth remembering about the user. Use this hierarchy:

        ### TIER 1: Identity & Personal Facts (HI-PRIORITY)
        - Name, location, job, medical conditions/allergies.
        - Family structure, significant relationships.
        - *Example*: "My name is Alex", "I'm allergic to peanuts", "I live in SF".

        ### TIER 2: Preferences, Hobbies & Lifestyle (MED-PRIORITY)
        - Personal likes/dislikes, hobbies, interests, and recurring activities.
        - Tool preferences, work habits, and communication styles.
        - *Example*: "I love playing guitar", "I work best in the morning", "I enjoy hiking".

        ### TIER 3: Active Goals & Projects (MED-PRIORITY)
        - Current objectives, deadlines, key decisions made, blockers.
        - *Example*: "Building an app called Cortex", "Launch target is Q1".

        ### TIER 4: Domain Knowledge & Expertise (LOW-PRIORITY)
        - Specific technical knowledge or industry expertise.
        - *Example*: "I know SwiftUI and Core Data".

        ### DO NOT SAVE:
        - Greetings ("Hi", "Thanks"), simple commands ("Search for X"), placeholder text, very short generic responses ("Ok", "Done").
        - Random URLs or code snippets without context.

        NEW TEXT TO ANALYZE:
        ---
        \(memory.text)
        ---

        Respond with JSON:
        {
            "isWorthRemembering": true/false,
            "reason": "Brief explanation citing the Tier or reason for skip",
            "suggestedTypes": ["fact", "preference", "goal", "skill", "insight", "relationship", "medical"]
        }
        """
        
        let systemPrompt = "You are a selective memory filter. Your goal is to identify information that builds a personal profile of the user, including their identity, lifestyle, preferences, and goals."
        
        return try await llmService.completeJSON(
            prompt: prompt,
            systemPrompt: systemPrompt,
            responseType: MemoryWorthinessResult.self
        )
    }
    
    // MARK: - Stage 2: Memory Extraction
    
    /// Extract structured memories from text
    func extractMemories(_ memory: Memory, suggestedTypes: [MemoryType], context: String? = nil) async throws -> [ExtractedMemoryData] {
        let typesString = suggestedTypes.map { $0.rawValue }.joined(separator: ", ")
        let contextSection = context != nil ? "\n### CONTEXT FROM PREVIOUS MESSAGES:\n\(context!)\n" : ""
        
        let prompt = """
        Extract specific, factual memories from the NEW TEXT below, sent by a user in "\(memory.appName)".
        \(contextSection)
        ### NEW TEXT:
        ---
        \(memory.text)
        ---

        ### EXTRACTION RULES:
        1. **Atomic Facts**: Each memory must be a single, independent statement.
        2. **Third Person**: ALWAYS use the third person. Use "User" (e.g., "User likes playing guitar" instead of "I like playing guitar"). NEVER use "I" or "my".
        3. **Contextual**: Include critical context (e.g., "User prefers Python *for automation tasks*" rather than just "User likes Python").
        4. **Factual**: Do not speculate. Only extract what is clearly stated.
        5. **Confidence**: Assign 0.0-1.0 based on clarity.
        6. **Formatting**: Present tense, clear and concise.

        ### MEMORY TYPES:
        - fact: Identity/Location/Job
        - preference: Likes/Dislikes/Choices
        - goal: Objectives/Deadlines
        - skill: Expertise/Knowledge
        - medical: Health/Allergies
        - relationship: People/Connections
        - insight: Patterns/Observations

        ### EXAMPLES:
        - Input: "I'm allergic to peanuts." -> "User has a peanut allergy." (Type: medical)
        - Input: "I prefer SwiftUI over UIKit for new projects." -> "User prefers SwiftUI over UIKit for new projects." (Type: preference)
        - Input: "Building an app called Cortex." -> "User is building an application named Cortex." (Type: goal)

        Respond with JSON:
        {
            "memories": [
                {
                    "content": "The extracted memory",
                    "type": "fact|preference|goal|skill|medical|relationship|insight",
                    "confidence": 0.8,
                    "tags": ["relevant", "keywords"],
                    "expiresAt": null
                }
            ]
        }
        """
        
        let systemPrompt = "You are a memory extraction system. Extract clear, atomic, third-person facts from user messages. Be precise and factual."
        
        struct ExtractionResponse: Codable {
            let memories: [ExtractedMemoryData]
        }
        
        let response = try await llmService.completeJSON(
            prompt: prompt,
            systemPrompt: systemPrompt,
            responseType: ExtractionResponse.self
        )
        
        return response.memories
    }
    
    // MARK: - Batch Processing
    
    /// Process multiple memories at once (more efficient)
    func processBatch(_ memories: [Memory]) async throws -> [MemoryExtractionResult] {
        var results: [MemoryExtractionResult] = []
        
        for memory in memories {
            let result = try await processMemory(memory)
            results.append(result)
            
            // Rate limiting
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
        }
        
        return results
    }
}

// MARK: - Preview/Testing

extension MemoryProcessor {
    /// Create a preview instance for testing
    static var preview: MemoryProcessor {
        let processor = MemoryProcessor()
        // Don't enable for preview
        return processor
    }
}

