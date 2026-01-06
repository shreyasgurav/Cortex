//
//  LLMService.swift
//  Cortex
//
//  Abstraction layer for LLM providers (OpenAI, Claude, Ollama)
//  Handles API calls for memory extraction
//

import Foundation

/// LLM provider options
enum LLMProvider: String, Codable, CaseIterable {
    case openai = "openai"
    case anthropic = "anthropic"  // Claude
    case ollama = "ollama"        // Local LLM
    
    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .anthropic: return "Claude"
        case .ollama: return "Ollama (Local)"
        }
    }
    
    var defaultModel: String {
        switch self {
        case .openai: return "gpt-4o-mini"
        case .anthropic: return "claude-3-haiku-20240307"
        case .ollama: return "llama3.2"
        }
    }
    
    var baseURL: String {
        switch self {
        case .openai: return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .ollama: return "http://localhost:11434/api"
        }
    }
}

/// Configuration for LLM service
struct LLMConfig: Codable {
    var provider: LLMProvider
    var apiKey: String?
    var model: String?
    var baseURL: String?
    var maxTokens: Int
    var temperature: Double
    
    static var `default`: LLMConfig {
        LLMConfig(
            provider: .openai,
            apiKey: nil,
            model: nil,
            baseURL: nil,
            maxTokens: 1000,
            temperature: 0.3
        )
    }
    
    var effectiveModel: String {
        model ?? provider.defaultModel
    }
    
    var effectiveBaseURL: String {
        baseURL ?? provider.baseURL
    }
}

/// Error types for LLM service
enum LLMError: Error {
    case noAPIKey
    case invalidResponse
    case networkError(Error)
    case rateLimited
    case serverError(String)
    case parsingError(String)
}

/// Main LLM service class
actor LLMService {
    
    private var config: LLMConfig
    
    init(config: LLMConfig = .default) {
        self.config = config
    }
    
    // MARK: - Configuration
    
    func updateConfig(_ config: LLMConfig) {
        self.config = config
    }
    
    func setAPIKey(_ key: String) {
        self.config.apiKey = key
    }
    
    // MARK: - Core Methods
    
    /// Send a completion request to the LLM
    func complete(prompt: String, systemPrompt: String? = nil) async throws -> String {
        switch config.provider {
        case .openai:
            return try await completeOpenAI(prompt: prompt, systemPrompt: systemPrompt)
        case .anthropic:
            return try await completeAnthropic(prompt: prompt, systemPrompt: systemPrompt)
        case .ollama:
            return try await completeOllama(prompt: prompt, systemPrompt: systemPrompt)
        }
    }
    
    /// Send a structured completion request (expects JSON response)
    func completeJSON<T: Decodable>(
        prompt: String,
        systemPrompt: String? = nil,
        responseType: T.Type
    ) async throws -> T {
        let jsonSystemPrompt = (systemPrompt ?? "") + "\n\nRespond ONLY with valid JSON, no markdown or explanation."
        let response = try await complete(prompt: prompt, systemPrompt: jsonSystemPrompt)
        
        // Clean up response (remove markdown code blocks if present)
        let cleanedResponse = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let data = cleanedResponse.data(using: .utf8) else {
            throw LLMError.parsingError("Failed to convert response to data")
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            print("[LLMService] JSON parsing error: \(error)")
            print("[LLMService] Response was: \(cleanedResponse)")
            throw LLMError.parsingError("Failed to parse JSON: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Provider-Specific Implementations
    
    private func completeOpenAI(prompt: String, systemPrompt: String?) async throws -> String {
        guard let apiKey = config.apiKey, !apiKey.isEmpty else {
            throw LLMError.noAPIKey
        }
        
        let url = URL(string: "\(config.effectiveBaseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var messages: [[String: String]] = []
        if let systemPrompt = systemPrompt {
            messages.append(["role": "system", "content": systemPrompt])
        }
        messages.append(["role": "user", "content": prompt])
        
        let body: [String: Any] = [
            "model": config.effectiveModel,
            "messages": messages,
            "max_tokens": config.maxTokens,
            "temperature": config.temperature
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }
        
        if httpResponse.statusCode == 429 {
            throw LLMError.rateLimited
        }
        
        if httpResponse.statusCode != 200 {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMError.serverError(errorText)
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.invalidResponse
        }
        
        return content
    }
    
    private func completeAnthropic(prompt: String, systemPrompt: String?) async throws -> String {
        guard let apiKey = config.apiKey, !apiKey.isEmpty else {
            throw LLMError.noAPIKey
        }
        
        let url = URL(string: "\(config.effectiveBaseURL)/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        var body: [String: Any] = [
            "model": config.effectiveModel,
            "max_tokens": config.maxTokens,
            "messages": [["role": "user", "content": prompt]]
        ]
        
        if let systemPrompt = systemPrompt {
            body["system"] = systemPrompt
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }
        
        if httpResponse.statusCode == 429 {
            throw LLMError.rateLimited
        }
        
        if httpResponse.statusCode != 200 {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMError.serverError(errorText)
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = json?["content"] as? [[String: Any]],
              let firstContent = content.first,
              let text = firstContent["text"] as? String else {
            throw LLMError.invalidResponse
        }
        
        return text
    }
    
    private func completeOllama(prompt: String, systemPrompt: String?) async throws -> String {
        let url = URL(string: "\(config.effectiveBaseURL)/generate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var fullPrompt = prompt
        if let systemPrompt = systemPrompt {
            fullPrompt = "System: \(systemPrompt)\n\nUser: \(prompt)"
        }
        
        let body: [String: Any] = [
            "model": config.effectiveModel,
            "prompt": fullPrompt,
            "stream": false,
            "options": [
                "temperature": config.temperature,
                "num_predict": config.maxTokens
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMError.serverError(errorText)
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let responseText = json?["response"] as? String else {
            throw LLMError.invalidResponse
        }
        
        return responseText
    }
}

