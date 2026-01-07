//
//  AppState.swift
//  Cortex
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
    
    /// Smart filtering - when ON, only AI-approved memories are saved
    @Published var filterBeforeSaving: Bool = true {
        didSet {
            UserDefaults.standard.set(filterBeforeSaving, forKey: "filterBeforeSaving")
        }
    }
    
    /// Current accessibility permission status
    @Published var hasAccessibilityPermission: Bool = false
    
    /// Current input monitoring permission status
    @Published var hasInputMonitoringPermission: Bool = false
    
    /// All captured memories (loaded from database)
    @Published var memories: [Memory] = []
    
    /// AI-extracted memories (structured, filtered)
    @Published var extractedMemories: [ExtractedMemory] = []
    
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
    
    // MARK: - App Whitelist (Strict Mode)
    
    /// Set of bundle IDs that are allowed to use Cortex
    @Published var enabledBundleIds: Set<String> = [] {
        didSet {
            let array = Array(enabledBundleIds)
            UserDefaults.standard.set(array, forKey: "Cortex_enabled_apps")
        }
    }
    
    // MARK: - Dependencies
    private var memoryStore: MemoryStore?
    private var extractedMemoryStore: ExtractedMemoryStore?
    
    // MARK: - App Permission Helpers
    
    func isAppEnabled(_ bundleId: String) -> Bool {
        return enabledBundleIds.contains(bundleId)
    }
    
    func toggleAppResult(_ bundleId: String) {
        if enabledBundleIds.contains(bundleId) {
            enabledBundleIds.remove(bundleId)
        } else {
            enabledBundleIds.insert(bundleId)
        }
    }
    
    func setAppEnabled(_ bundleId: String, enabled: Bool) {
        if enabled {
            enabledBundleIds.insert(bundleId)
        } else {
            enabledBundleIds.remove(bundleId)
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        // Load persisted preferences
        captureEnabled = UserDefaults.standard.bool(forKey: "captureEnabled")
        if !UserDefaults.standard.bool(forKey: "hasLaunchedBefore") {
            captureEnabled = true
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
        }
        privacyModeEnabled = UserDefaults.standard.bool(forKey: "privacyModeEnabled")
        
        // Load filter preference (default to true for smart filtering)
        if UserDefaults.standard.object(forKey: "filterBeforeSaving") == nil {
            filterBeforeSaving = true
            UserDefaults.standard.set(true, forKey: "filterBeforeSaving")
        } else {
            filterBeforeSaving = UserDefaults.standard.bool(forKey: "filterBeforeSaving")
        }
        
        // Load enabled apps
        if let savedApps = UserDefaults.standard.array(forKey: "Cortex_enabled_apps") as? [String] {
            enabledBundleIds = Set(savedApps)
        } else {
            enabledBundleIds = []
        }
    }
    
    // MARK: - Setup
    
    func setup(memoryStore: MemoryStore) {
        self.memoryStore = memoryStore
        loadMemories()
    }
    
    func setupExtractedStore(_ store: ExtractedMemoryStore) {
        self.extractedMemoryStore = store
        loadExtractedMemories()
    }
    
    // MARK: - Memory Operations
    
    func loadMemories() {
        guard let store = memoryStore else { return }
        Task {
            do {
                let loaded = try await store.fetchAllMemories()
                await MainActor.run {
                    self.memories = loaded
                    // Only update count from raw memories if filtering is OFF
                    if !filterBeforeSaving {
                        self.captureCount = loaded.count
                    }
                }
            } catch {
                print("Failed to load memories: \(error)")
            }
        }
    }
    
    func loadExtractedMemories() {
        guard let store = extractedMemoryStore else { return }
        Task {
            do {
                let loaded = try await store.fetchAllMemories()
                await MainActor.run {
                    self.extractedMemories = loaded
                    // Update count from extracted memories if filtering is ON
                    if filterBeforeSaving {
                        self.captureCount = loaded.count
                    }
                }
            } catch {
                print("Failed to load extracted memories: \(error)")
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
        if filterBeforeSaving {
            // Clear extracted memories when filtering is ON
            guard let store = extractedMemoryStore else { return }
            Task {
                do {
                    try await store.clearAllMemories()
                    await MainActor.run {
                        extractedMemories.removeAll()
                        captureCount = 0
                        lastCapturedPreview = ""
                    }
                } catch {
                    print("Failed to clear extracted memories: \(error)")
                }
            }
        } else {
            // Clear raw memories when filtering is OFF
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

