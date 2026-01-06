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
    private let memoryProcessor: MemoryProcessor?
    
    // MARK: - State
    
    @Published private(set) var isCapturing: Bool = false
    @Published private(set) var lastCapturedText: String = ""
    @Published private(set) var captureCount: Int = 0
    
    // MARK: - Initialization
    
    init(
        accessibilityWatcher: AccessibilityWatcher,
        keyEventListener: KeyEventListener,
        memoryStore: MemoryStore,
        permissionsManager: PermissionsManager,
        memoryProcessor: MemoryProcessor? = nil
    ) {
        self.accessibilityWatcher = accessibilityWatcher
        self.keyEventListener = keyEventListener
        self.memoryStore = memoryStore
        self.permissionsManager = permissionsManager
        self.memoryProcessor = memoryProcessor
        
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
        
        // When AccessibilityWatcher detects focus change - smart buffer clearing
        accessibilityWatcher.onFocusChanged = { [weak self] oldWasEditable, newIsEditable, sameApp in
            // Only clear buffer if:
            // 1. We're switching apps (not same app), OR
            // 2. We're leaving an editable field AND not entering another editable field
            // The clearBuffer() method itself will check if user typed recently and skip if so
            if !sameApp || (oldWasEditable && !newIsEditable) {
                print("[CaptureCoordinator] Requesting buffer clear (app switch: \(!sameApp), left editable: \(oldWasEditable && !newIsEditable))")
                self?.keyEventListener.clearBuffer()
            } else {
                print("[CaptureCoordinator] Keeping shadow buffer (same app, still in editable field)")
            }
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
        
        // Create memory object (may or may not be saved depending on filtering)
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
        
        // NEW: Check if we should filter before saving
        if AppState.shared.filterBeforeSaving {
            // AI-first approach: filter, extract, then save only worthy memories
            await captureWithAIFiltering(memory: memory)
        } else {
            // Old behavior: save everything to raw database
            await saveRawMemory(memory)
        }
    }
    
    /// AI-first filtering: Check worthiness, extract memories, save only if worthy
    private func captureWithAIFiltering(memory: Memory) async {
        guard let processor = memoryProcessor, processor.isEnabled else {
            // No AI available, fall back to heuristic
            print("[CaptureCoordinator] AI not available, using fallback heuristic")
            await fallbackHeuristicCapture(memory)
            return
        }
        
        do {
            print("[CaptureCoordinator] 🧠 Checking if worth remembering: '\(memory.preview)'")
            
            // Stage 1: Check worthiness
            let worthiness = try await processor.checkWorthiness(memory)
            
            if !worthiness.isWorthRemembering {
                print("[CaptureCoordinator] ✗ Skipped (not worth remembering): \(worthiness.reason)")
                
                // Log that we skipped this
                if let store = processor.extractedMemoryStore {
                    try? await store.logProcessing(
                        rawMemoryId: memory.id,
                        wasWorthRemembering: false,
                        reason: worthiness.reason,
                        extractedCount: 0
                    )
                }
                return
            }
            
            print("[CaptureCoordinator] ✓ Worth remembering! Extracting memories...")
            
            // Stage 2: Extract structured memories
            let extracted = try await processor.extractMemories(memory, suggestedTypes: worthiness.suggestedTypes)
            
            if extracted.isEmpty {
                print("[CaptureCoordinator] ✗ No memories extracted")
                return
            }
            
            print("[CaptureCoordinator] ✓ Extracted \(extracted.count) memories")
            
            // Stage 3: Save extracted memories with embeddings
            try await processor.saveExtractedMemories(extracted, sourceMemory: memory)
            
            // Reload extracted memories to update UI
            AppState.shared.loadExtractedMemories()
            
            // Update UI state (but don't add to raw memories list)
            await MainActor.run {
                lastCapturedText = memory.preview
                captureCount += 1
                // Note: We don't add to AppState.shared.memories since we're not saving raw
            }
            
            print("[CaptureCoordinator] ✓✓✓ Saved \(extracted.count) extracted memories from \(memory.appName)")
            
        } catch {
            print("[CaptureCoordinator] AI filtering failed: \(error)")
            // Fallback to heuristic
            await fallbackHeuristicCapture(memory)
        }
    }
    
    /// Fallback heuristic when AI is unavailable: save if text is long enough
    private func fallbackHeuristicCapture(_ memory: Memory) async {
        let minLength = 15 // Minimum characters for a meaningful message
        
        if memory.text.count >= minLength {
            print("[CaptureCoordinator] Fallback: Text long enough (\(memory.text.count) chars), saving")
            await saveRawMemory(memory)
        } else {
            print("[CaptureCoordinator] Fallback: Text too short (\(memory.text.count) chars), skipping")
        }
    }
    
    /// Save raw memory to database (old behavior, used when filtering is disabled)
    private func saveRawMemory(_ memory: Memory) async {
        do {
            try await memoryStore.saveMemory(memory)
            
            // Update UI state
            await MainActor.run {
                lastCapturedText = memory.preview
                captureCount += 1
                AppState.shared.addMemory(memory)
            }
            
            print("[CaptureCoordinator] ✓✓✓ Saved raw memory from \(memory.appName) via \(memory.source.rawValue)")
            
            // Queue for AI processing (async, happens later)
            if let processor = memoryProcessor, processor.isEnabled {
                Task { @MainActor in
                    await processor.queueForProcessing(memory)
                }
            }
            
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
