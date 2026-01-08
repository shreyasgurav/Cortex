//
//  ContextWindow.swift
//  Cortex
//
//  Maintains a sliding window of recent messages for better context
//

import Foundation
import Combine

/// Holds recent messages to provide context for memory extraction
@MainActor
final class ContextWindow: ObservableObject {
    
    struct MessageContext {
        let text: String
        let appName: String
        let timestamp: Date
    }
    
    // MARK: - Properties
    
    private var messagesByApp: [String: [MessageContext]] = [:]
    private let maxMessagesPerApp: Int
    
    // MARK: - Initialization
    
    init(maxMessagesPerApp: Int = 10) {
        self.maxMessagesPerApp = maxMessagesPerApp
    }
    
    // MARK: - Methods
    
    /// Add a new message to the context window
    func addMessage(_ text: String, appName: String) {
        let context = MessageContext(text: text, appName: appName, timestamp: Date())
        
        var appMessages = messagesByApp[appName] ?? []
        appMessages.append(context)
        
        // Mantain sliding window
        if appMessages.count > maxMessagesPerApp {
            appMessages.removeFirst()
        }
        
        messagesByApp[appName] = appMessages
    }
    
    /// Get recent context for an app as a formatted string
    func getContext(for appName: String) -> String {
        guard let messages = messagesByApp[appName], !messages.isEmpty else {
            return ""
        }
        
        let formatted = messages.map { "- \($0.text)" }.joined(separator: "\n")
        return """
        Recent context from "\(appName)":
        \(formatted)
        """
    }
    
    /// Clear context for an app
    func clearContext(for appName: String) {
        messagesByApp.removeValue(forKey: appName)
    }
    
    /// Clear all context
    func clearAll() {
        messagesByApp.removeAll()
    }
}
