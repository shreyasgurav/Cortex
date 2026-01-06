//
//  Memory.swift
//  Cortex
//
//  Core data model for captured memories
//

import Foundation

/// Represents a captured memory entry
/// Each memory is a snapshot of text that the user "sent" or finalized from any application
struct Memory: Identifiable, Hashable {
    let id: String
    let createdAt: Date
    let appBundleId: String
    let appName: String
    let windowTitle: String
    let source: CaptureSource
    let text: String
    let textHash: String
    
    /// Preview text for list display (first line, truncated)
    var preview: String {
        let firstLine = text.components(separatedBy: .newlines).first ?? text
        if firstLine.count > 100 {
            return String(firstLine.prefix(100)) + "..."
        }
        return firstLine
    }
    
    /// Formatted timestamp for display
    var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }
    
    /// Full formatted timestamp
    var fullFormattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }
}

/// Source of capture - how we detected the "send" action
enum CaptureSource: String, Codable {
    case enterKey = "enter_key"        // User pressed Enter or Cmd+Enter
    case focusLost = "focus_lost"      // Focus moved away from editable field
    case appSwitch = "app_switch"      // User switched to another application
    
    var displayName: String {
        switch self {
        case .enterKey: return "Enter Key"
        case .focusLost: return "Focus Lost"
        case .appSwitch: return "App Switch"
        }
    }
}

