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
    
    // MARK: - Queue for processing
    
    private var processingQueue: [Memory] = []
    private var isProcessingQueue: Bool = false
    
    // MARK: - Initialization
    
    init(config: LLMConfig = .default) {
        self.config = config
        self.llmService = LLMService(config: config)
    }
    
    // MARK: - Configuration
    
    func configure(provider: LLMProvider, apiKey: String, model: String? = nil) {
        var newConfig = config
        newConfig.provider = provider
        newConfig.apiKey = apiKey
        if let model = model {
            newConfig.model = model
        }
        self.config = newConfig
        
        Task {
            await llmService.updateConfig(newConfig)
        }
        
        isEnabled = !apiKey.isEmpty
        print("[MemoryProcessor] Configured with \(provider.displayName)")
    }
    
    // MARK: - Main Processing Methods
    
    /// Add a raw memory to the processing queue
    func queueForProcessing(_ memory: Memory) {
        guard isEnabled else {
            print("[MemoryProcessor] Not enabled, skipping: \(memory.preview)")
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
                    
                    // TODO: Save extracted memories to storage
                    // This will be wired up to ExtractedMemoryStore
                    
                } else {
                    print("[MemoryProcessor] Skipped (not worth remembering): \(memory.preview)")
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
        let worthiness = try await checkWorthiness(memory)
        
        if !worthiness.isWorthRemembering {
            return MemoryExtractionResult(
                memories: [],
                wasProcessed: false,
                processingNote: worthiness.reason
            )
        }
        
        // Stage 2: Extract structured memories
        let extractedMemories = try await extractMemories(memory, suggestedTypes: worthiness.suggestedTypes)
        
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

