//
//  MemoryProcessor.swift
//  Cortex
//
//  AI-powered service that processes raw captures and extracts meaningful memories
//  Two-stage process:
//    1. Filter: Is this worth remembering?
//    2. Extract: What facts/insights can we extract?
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
    
    // MARK: - Dependencies
    
    private var llmService: LLMService
    private var config: LLMConfig
    private var extractedMemoryStore: ExtractedMemoryStore?
    private var embeddingService: EmbeddingService
    
    // MARK: - Queue for processing
    
    private var processingQueue: [Memory] = []
    private var isProcessingQueue: Bool = false
    
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
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }
        
        isProcessingQueue = false
        isProcessing = false
    }
    
    /// Process a single memory: filter + extract
    func processMemory(_ memory: Memory) async throws -> MemoryExtractionResult {
        // Stage 1: Check if worth remembering
        // Be resilient: if LLM fails, fall back to simple heuristic (length-based)
        let worthiness: MemoryWorthinessResult
        do {
            worthiness = try await checkWorthiness(memory)
        } catch {
            let text = memory.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let isWorth = text.count >= 10 // simple fallback: non-trivial messages
            print("[MemoryProcessor] Worthiness check failed, using heuristic (len=\(text.count), worth=\(isWorth)): \(error)")
            if !isWorth {
                return MemoryExtractionResult(
                    memories: [],
                    wasProcessed: false,
                    processingNote: "Heuristic: text too short or uninformative"
                )
            }
            worthiness = MemoryWorthinessResult(
                isWorthRemembering: true,
                reason: "Heuristic: long enough message, LLM unavailable",
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
            extractedMemories = try await extractMemories(memory, suggestedTypes: worthiness.suggestedTypes)
        } catch {
            // Fallback: if extraction fails (e.g. LLM/network), create a single generic memory
            print("[MemoryProcessor] Extraction failed, using raw text as a single memory: \(error)")
            let text = memory.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                return MemoryExtractionResult(
                    memories: [],
                    wasProcessed: false,
                    processingNote: "Extraction failed and text was empty"
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
    func checkWorthiness(_ memory: Memory) async throws -> MemoryWorthinessResult {
        let prompt = """
        Analyze this text that a user sent from the app "\(memory.appName)":
        
        ---
        \(memory.text)
        ---
        
        Determine if this contains information worth remembering about the user.
        
        Worth remembering:
        - Personal facts (name, location, job, etc.)
        - Preferences (likes, dislikes, how they want things done)
        - Goals and aspirations
        - Projects they're working on
        - Skills and expertise
        - Relationships and people they mention
        - Important events or deadlines
        - Beliefs and opinions
        - Questions they frequently ask
        
        NOT worth remembering:
        - Generic greetings ("hi", "hello", "thanks")
        - Simple commands ("search for X", "open file")
        - Code snippets without context
        - Random URLs without explanation
        - Placeholder text
        - Very short responses ("ok", "yes", "done")
        
        Respond with JSON:
        {
            "isWorthRemembering": true/false,
            "reason": "Brief explanation",
            "suggestedTypes": ["fact", "preference", "goal", etc.]
        }
        """
        
        let systemPrompt = """
        You are a memory filter. Your job is to determine if text contains memorable information about a user.
        Be selective - only flag things that reveal something meaningful about the person.
        """
        
        return try await llmService.completeJSON(
            prompt: prompt,
            systemPrompt: systemPrompt,
            responseType: MemoryWorthinessResult.self
        )
    }
    
    // MARK: - Stage 2: Memory Extraction
    
    /// Extract structured memories from text
    func extractMemories(_ memory: Memory, suggestedTypes: [MemoryType]) async throws -> [ExtractedMemoryData] {
        let typesString = suggestedTypes.map { $0.rawValue }.joined(separator: ", ")
        
        let prompt = """
        Extract specific, factual memories from this text sent by a user in "\(memory.appName)":
        
        ---
        \(memory.text)
        ---
        
        Suggested memory types to look for: \(typesString)
        
        Rules:
        1. Each memory should be a single, atomic fact
        2. Write memories in third person ("User prefers..." not "I prefer...")
        3. Be specific and concrete
        4. Include context when relevant
        5. Don't invent information not present in the text
        6. Assign confidence (0.0-1.0) based on how clear the information is
        7. Add relevant tags for categorization
        
        Memory types:
        - fact: Personal information (name, location, job)
        - preference: What they like/dislike
        - belief: Opinions and worldviews
        - goal: What they want to achieve
        - relationship: People they know
        - event: Upcoming/past events with dates
        - skill: Things they can do
        - project: Work they're doing
        - insight: General observations
        - question: Topics they're curious about
        - instruction: How they want things done
        
        Respond with JSON:
        {
            "memories": [
                {
                    "content": "The extracted memory as a clear statement",
                    "type": "fact/preference/goal/etc",
                    "confidence": 0.0-1.0,
                    "tags": ["relevant", "tags"],
                    "expiresAt": null or "2024-12-31T00:00:00Z" for time-sensitive info
                }
            ]
        }
        """
        
        let systemPrompt = """
        You are a memory extraction system. Extract clear, factual memories from user messages.
        Be precise and avoid speculation. Only extract what's clearly stated or strongly implied.
        """
        
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

