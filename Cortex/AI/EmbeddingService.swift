//
//  EmbeddingService.swift
//  Cortex
//
//  Generates vector embeddings for semantic search
//

import Foundation

enum EmbeddingProvider: String {
    case openai
    case unsupported
}

struct EmbeddingConfig {
    var provider: EmbeddingProvider
    var apiKey: String?
    var model: String
    var baseURL: String
    
    static var `default`: EmbeddingConfig {
        EmbeddingConfig(
            provider: .openai,
            apiKey: nil,
            model: "text-embedding-3-small",
            baseURL: "https://api.openai.com/v1"
        )
    }
}

enum EmbeddingError: Error {
    case noAPIKey
    case providerNotSupported
    case invalidResponse
    case serverError(String)
}

actor EmbeddingService {
    
    private var config: EmbeddingConfig
    
    init(config: EmbeddingConfig = .default) {
        self.config = config
    }
    
    func updateConfig(_ config: EmbeddingConfig) {
        self.config = config
    }
    
    func configureFromEnv(llmProvider: LLMProvider) {
        let env = ProcessInfo.processInfo.environment
        var newConfig = config
        
        switch llmProvider {
        case .openai:
            newConfig.provider = .openai
            newConfig.apiKey = env["OPENAI_API_KEY"]
            newConfig.model = env["CORTEX_EMBED_MODEL"] ?? "text-embedding-3-small"
            newConfig.baseURL = env["CORTEX_LLM_BASE_URL"] ?? "https://api.openai.com/v1"
        case .anthropic, .ollama:
            newConfig.provider = .unsupported
        }
        
        self.config = newConfig
    }
    
    func embed(text: String) async throws -> (vector: [Double], model: String) {
        switch config.provider {
        case .openai:
            return try await embedOpenAI(text: text)
        case .unsupported:
            throw EmbeddingError.providerNotSupported
        }
    }
    
    private func embedOpenAI(text: String) async throws -> (vector: [Double], model: String) {
        guard let apiKey = config.apiKey, !apiKey.isEmpty else {
            throw EmbeddingError.noAPIKey
        }
        
        let url = URL(string: "\(config.baseURL)/embeddings")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": config.model,
            "input": text
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw EmbeddingError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw EmbeddingError.serverError(errorText)
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard
            let dataArr = json?["data"] as? [[String: Any]],
            let first = dataArr.first,
            let embedding = first["embedding"] as? [Double],
            let model = json?["model"] as? String
        else {
            throw EmbeddingError.invalidResponse
        }
        
        return (embedding, model)
    }
}

