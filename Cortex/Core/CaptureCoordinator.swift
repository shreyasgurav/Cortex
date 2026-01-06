//
//  CaptureCoordinator.swift
//  Cortex
//
//  Coordinates all capture logic and decides when to save memories
//  Uses THREE layers (like Grammarly):
//    1. Accessibility APIs (AXValue) - works for native apps
//    2. Selection-based (AXSelectedText) - partial Electron support
//    3. Shadow buffer (keystroke tracking) - robust Electron fallback
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
        // When AccessibilityWatcher detects text should be captured (focus lost, app switch)
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
        
        // When AccessibilityWatcher detects focus change - clear shadow buffer
        accessibilityWatcher.onFocusChanged = { [weak self] in
            self?.keyEventListener.clearBuffer()
        }
        
        // When AccessibilityWatcher detects app switch - clear shadow buffer
        accessibilityWatcher.onAppSwitched = { [weak self] in
            self?.keyEventListener.clearBuffer()
        }
        
        // When KeyEventListener detects Enter key - THIS IS THE MAIN CAPTURE POINT
        keyEventListener.onEnterKeyPressed = { [weak self] shadowBuffer in
            self?.handleEnterKeyWithShadowBuffer(shadowBuffer)
        }
    }
    
    // MARK: - Enter Key Handling (The Smart Part)
    
    /// Handle Enter key press - compare multiple sources and pick the best text
    private func handleEnterKeyWithShadowBuffer(_ shadowBuffer: String) {
        let appName = accessibilityWatcher.currentAppName
        let bundleId = accessibilityWatcher.currentAppBundleId
        let windowTitle = accessibilityWatcher.windowTitle
        
        print("[CaptureCoordinator] ========== ENTER KEY PRESSED ==========")
        print("[CaptureCoordinator] App: \(appName) (\(bundleId))")
        print("[CaptureCoordinator] Shadow buffer: '\(shadowBuffer.prefix(50))...' (\(shadowBuffer.count) chars)")
        
        // Layer 1: Try Accessibility API (works for native apps)
        let accessibilityText = accessibilityWatcher.getTrackedText()
        print("[CaptureCoordinator] Accessibility text: '\(accessibilityText.prefix(50))...' (\(accessibilityText.count) chars)")
        
        // Layer 2: Try to read directly from focused element
        let directText = accessibilityWatcher.tryReadCurrentElementText() ?? ""
        print("[CaptureCoordinator] Direct read text: '\(directText.prefix(50))...' (\(directText.count) chars)")
        
        // Layer 3: Shadow buffer (keystroke tracking)
        // Already have it as parameter
        
        // DECISION: Pick the best text source
        // Priority: Accessibility > Direct > Shadow Buffer (but validate each)
        let textToCapture = chooseBestText(
            accessibility: accessibilityText,
            direct: directText,
            shadow: shadowBuffer,
            appName: appName
        )
        
        guard let finalText = textToCapture, !finalText.isEmpty else {
            print("[CaptureCoordinator] ✗ No valid text found from any source")
            return
        }
        
        print("[CaptureCoordinator] ✓ Capturing: '\(finalText.prefix(50))...'")
        
        // Capture it
        Task { @MainActor in
            await captureText(
                text: finalText,
                source: .enterKey,
                appName: appName,
                appBundleId: bundleId,
                windowTitle: windowTitle
            )
        }
    }
    
    /// Choose the best text from multiple sources
    private func chooseBestText(
        accessibility: String,
        direct: String,
        shadow: String,
        appName: String
    ) -> String? {
        let trimmedAccessibility = accessibility.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDirect = direct.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedShadow = shadow.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Filter out placeholder/junk text
        let validAccessibility = isValidUserText(trimmedAccessibility) ? trimmedAccessibility : ""
        let validDirect = isValidUserText(trimmedDirect) ? trimmedDirect : ""
        let validShadow = isValidUserText(trimmedShadow) ? trimmedShadow : ""
        
        // For Electron apps (Cursor, VS Code, Slack), prefer shadow buffer
        let isElectronApp = isLikelyElectronApp(appName)
        
        if isElectronApp {
            print("[CaptureCoordinator] Electron app detected - prioritizing shadow buffer")
            // For Electron: Shadow > Accessibility > Direct
            if !validShadow.isEmpty {
                return validShadow
            }
            if !validAccessibility.isEmpty {
                return validAccessibility
            }
            if !validDirect.isEmpty {
                return validDirect
            }
        } else {
            // For native apps: Accessibility > Shadow > Direct
            if !validAccessibility.isEmpty {
                return validAccessibility
            }
            if !validShadow.isEmpty {
                return validShadow
            }
            if !validDirect.isEmpty {
                return validDirect
            }
        }
        
        return nil
    }
    
    /// Check if text looks like actual user content
    private func isValidUserText(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        
        // Too short might be accidental
        // But allow single chars like "y", "k", "!" for quick replies
        
        let lowercased = text.lowercased()
        
        // Filter out common placeholders
        let placeholders = [
            "ask anything", "type a message", "message", "search",
            "write a message", "type here", "enter text",
            "write something", "what's on your mind", "send a message",
            "ask me anything", "ask a question"
        ]
        
        for placeholder in placeholders {
            if lowercased == placeholder || lowercased.hasPrefix(placeholder) {
                return false
            }
        }
        
        // Filter out app names and window titles
        let appNames = [
            "google chrome", "safari", "firefox", "cursor", "xcode", "slack",
            "discord", "notion", "finder", "terminal", "messages", "mail",
            "spotify", "zoom", "teams", "cortex", "code", "visual studio"
        ]
        
        if appNames.contains(lowercased) {
            return false
        }
        
        // Filter out URLs without context
        if text.count < 50 && !text.contains(" ") {
            let urlPatterns = [".com", ".org", ".io", ".net", ".dev", "http://", "https://"]
            for pattern in urlPatterns {
                if text.contains(pattern) {
                    return false
                }
            }
        }
        
        return true
    }
    
    /// Check if app is likely an Electron app (where Accessibility is flaky)
    private func isLikelyElectronApp(_ appName: String) -> Bool {
        let electronApps = [
            "cursor", "visual studio code", "code", "slack", "discord",
            "notion", "figma", "postman", "insomnia", "atom", "teams",
            "whatsapp", "telegram desktop", "signal", "element", "obsidian"
        ]
        
        let lowercased = appName.lowercased()
        return electronApps.contains { lowercased.contains($0) }
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
        print("[CaptureCoordinator] Started capture coordinator (with shadow buffer support)")
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
            
            print("[CaptureCoordinator] ✓✓✓ Saved memory from \(appName) via \(source.rawValue)")
            
        } catch {
            print("[CaptureCoordinator] Failed to save memory: \(error)")
        }
    }
    
    // MARK: - State Updates
    
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
