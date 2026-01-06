//
//  AppState.swift
//  MemoryTap
//
//  Global application state management
//

import Foundation
import SwiftUI
@preconcurrency import Combine

/// Observable app state that drives the entire application
@MainActor
final class AppState: ObservableObject {
    // MARK: - Singleton
    static let shared = AppState()
    
    // MARK: - Published State
    
    /// Whether text capture is currently enabled
    @Published var captureEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(captureEnabled, forKey: "captureEnabled")
        }
    }
    
    /// Privacy mode - when ON, absolutely nothing is captured
    @Published var privacyModeEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(privacyModeEnabled, forKey: "privacyModeEnabled")
        }
    }
    
    /// Current accessibility permission status
    @Published var hasAccessibilityPermission: Bool = false
    
    /// Current input monitoring permission status
    @Published var hasInputMonitoringPermission: Bool = false
    
    /// All captured memories (loaded from database)
    @Published var memories: [Memory] = []
    
    /// Whether the main memory window is shown
    @Published var showMemoryWindow: Bool = false
    
    /// Whether onboarding/permissions window is shown
    @Published var showOnboarding: Bool = false
    
    /// Currently focused app info
    @Published var currentAppName: String = ""
    @Published var currentAppBundleId: String = ""
    
    /// Last captured text preview (for status display)
    @Published var lastCapturedPreview: String = ""
    
    /// Capture statistics
    @Published var captureCount: Int = 0
    
    // MARK: - Dependencies
    private var memoryStore: MemoryStore?
    
    // MARK: - Initialization
    
    private init() {
        // Load persisted preferences
        captureEnabled = UserDefaults.standard.bool(forKey: "captureEnabled")
        if !UserDefaults.standard.bool(forKey: "hasLaunchedBefore") {
            captureEnabled = true
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
        }
        privacyModeEnabled = UserDefaults.standard.bool(forKey: "privacyModeEnabled")
    }
    
    // MARK: - Setup
    
    func setup(memoryStore: MemoryStore) {
        self.memoryStore = memoryStore
        loadMemories()
    }
    
    // MARK: - Memory Operations
    
    func loadMemories() {
        guard let store = memoryStore else { return }
        Task {
            do {
                let loaded = try await store.fetchAllMemories()
                await MainActor.run {
                    self.memories = loaded
                    self.captureCount = loaded.count
                }
            } catch {
                print("Failed to load memories: \(error)")
            }
        }
    }
    
    func addMemory(_ memory: Memory) {
        memories.insert(memory, at: 0)
        captureCount = memories.count
        lastCapturedPreview = memory.preview
    }
    
    func deleteMemory(_ memory: Memory) {
        guard let store = memoryStore else { return }
        Task {
            do {
                try await store.deleteMemory(id: memory.id)
                await MainActor.run {
                    memories.removeAll { $0.id == memory.id }
                    captureCount = memories.count
                }
            } catch {
                print("Failed to delete memory: \(error)")
            }
        }
    }
    
    func clearAllMemories() {
        guard let store = memoryStore else { return }
        Task {
            do {
                try await store.clearAllMemories()
                await MainActor.run {
                    memories.removeAll()
                    captureCount = 0
                    lastCapturedPreview = ""
                }
            } catch {
                print("Failed to clear memories: \(error)")
            }
        }
    }
    
    // MARK: - Computed Properties
    
    /// Whether capture should currently happen
    var shouldCapture: Bool {
        captureEnabled && !privacyModeEnabled && hasAccessibilityPermission
    }
    
    /// Status text for menu bar
    var statusText: String {
        if privacyModeEnabled {
            return "Privacy Mode"
        } else if !hasAccessibilityPermission {
            return "Needs Permission"
        } else if captureEnabled {
            return "Capturing"
        } else {
            return "Paused"
        }
    }
}

