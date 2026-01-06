//
//  CaptureCoordinator.swift
//  MemoryTap
//
//  Coordinates all capture logic and decides when to save memories
//

import Foundation
import Combine

/// Orchestrates the capture pipeline
/// Connects AccessibilityWatcher, KeyEventListener, and MemoryStore
@MainActor
final class CaptureCoordinator: ObservableObject {
    
    // MARK: - Dependencies
    
    private let accessibilityWatcher: AccessibilityWatcher
    private let keyEventListener: KeyEventListener
    private let memoryStore: MemoryStore
    private let permissionsManager: PermissionsManager
    
    // MARK: - State
    
    @Published private(set) var isCapturing: Bool = false
    @Published private(set) var lastCapturedText: String = ""
    @Published private(set) var captureCount: Int = 0
    
    // MARK: - Initialization
    
    init(
        accessibilityWatcher: AccessibilityWatcher,
        keyEventListener: KeyEventListener,
        memoryStore: MemoryStore,
        permissionsManager: PermissionsManager
    ) {
        self.accessibilityWatcher = accessibilityWatcher
        self.keyEventListener = keyEventListener
        self.memoryStore = memoryStore
        self.permissionsManager = permissionsManager
        
        setupCallbacks()
    }
    
    // MARK: - Setup
    
    private func setupCallbacks() {
        // When AccessibilityWatcher detects text should be captured
        accessibilityWatcher.onTextShouldCapture = { [weak self] text, source, appName, bundleId, windowTitle in
            Task { @MainActor in
                await self?.captureText(
                    text: text,
                    source: source,
                    appName: appName,
                    appBundleId: bundleId,
                    windowTitle: windowTitle
                )
            }
        }
        
        // When KeyEventListener detects Enter key
        keyEventListener.onEnterKeyPressed = { [weak self] in
            self?.accessibilityWatcher.captureCurrentTextOnEnter()
        }
    }
    
    // MARK: - Start/Stop
    
    func start() {
        guard AppState.shared.shouldCapture else {
            print("[CaptureCoordinator] Cannot start - conditions not met")
            return
        }
        
        // Start accessibility watcher
        accessibilityWatcher.start()
        
        // Start key event listener if we have permission
        if permissionsManager.inputMonitoringGranted {
            keyEventListener.start()
        }
        
        isCapturing = true
        print("[CaptureCoordinator] Started capture coordinator")
    }
    
    func stop() {
        accessibilityWatcher.stop()
        keyEventListener.stop()
        isCapturing = false
        print("[CaptureCoordinator] Stopped capture coordinator")
    }
    
    /// Restart capturing (e.g., when permissions change)
    func restart() {
        stop()
        
        // Small delay to ensure clean restart
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.start()
        }
    }
    
    // MARK: - Capture Logic
    
    private func captureText(
        text: String,
        source: CaptureSource,
        appName: String,
        appBundleId: String,
        windowTitle: String
    ) async {
        // Check if we should capture
        guard AppState.shared.shouldCapture else {
            print("[CaptureCoordinator] Capture disabled, skipping")
            return
        }
        
        // Validate text
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedText.isEmpty else {
            return
        }
        
        // Note: We allow single-character messages like "k", "y", etc.
        // Filtering is done in AccessibilityWatcher to avoid capturing junk
        
        // Create memory
        let memory = Memory(
            id: UUID().uuidString,
            createdAt: Date(),
            appBundleId: appBundleId,
            appName: appName,
            windowTitle: windowTitle,
            source: source,
            text: trimmedText,
            textHash: MemoryStore.hashText(trimmedText)
        )
        
        // Save to database
        do {
            try await memoryStore.saveMemory(memory)
            
            // Update UI state
            await MainActor.run {
                lastCapturedText = memory.preview
                captureCount += 1
                AppState.shared.addMemory(memory)
            }
            
            print("[CaptureCoordinator] Captured memory from \(appName) via \(source.rawValue)")
            
        } catch {
            print("[CaptureCoordinator] Failed to save memory: \(error)")
        }
    }
    
    // MARK: - State Updates
    
    /// Called when capture settings change
    func updateCaptureState() {
        if AppState.shared.shouldCapture && !isCapturing {
            start()
        } else if !AppState.shared.shouldCapture && isCapturing {
            stop()
        }
        
        // Update key listener based on permission
        if isCapturing {
            if permissionsManager.inputMonitoringGranted && !keyEventListener.isListening {
                keyEventListener.start()
            } else if !permissionsManager.inputMonitoringGranted && keyEventListener.isListening {
                keyEventListener.stop()
            }
        }
    }
}

