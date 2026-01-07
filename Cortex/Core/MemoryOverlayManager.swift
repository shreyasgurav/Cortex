//
//  MemoryOverlayManager.swift
//  Cortex
//
//  Manages the floating \"memory\" button overlay and search+insert flow.
//

import Foundation
import AppKit
import SwiftUI
import Combine

@MainActor
final class MemoryOverlayManager: ObservableObject {
    
    enum MemoryOverlayState: Equatable {
        case idle
        case loading
        case available(count: Int)
        case empty
        case inserting
    }
    
    @Published private(set) var overlayState: MemoryOverlayState = .idle {
        didSet {
            print("[MemoryOverlay] State changed to: \(overlayState)")
        }
    }
    
    private var lastSearchedText: String?
    
    // Task to handle debounced hiding of the overlay
    private var hideDebounceTask: Task<Void, Error>?
    // Task to handle auto-hide after empty results
    private var autoHideTask: Task<Void, Error>?
    
    private let contextDetector: ContextDetector
    private let searchService: MemorySearchService
    private let insertService: MemoryInsertService
    
    private var window: NSWindow?
    private var isVisible: Bool = false
    
    init(contextDetector: ContextDetector,
         searchService: MemorySearchService,
         insertService: MemoryInsertService) {
        self.contextDetector = contextDetector
        self.searchService = searchService
        self.insertService = insertService
    }
    
    /// Show or update the overlay near the current context, if any.
    func updateOverlayVisibility() {
        guard AppState.shared.captureEnabled,
              !AppState.shared.privacyModeEnabled else {
            hideOverlay() // Immediate hide for strict conditions
            return
        }
        
        
        
        guard let context = contextDetector.currentContext() else {
            // No focused element at all. Debounce the hide to prevent flickering.
            scheduleDebouncedHide()
            return
        }
        
        // WHITELIST CHECK: Only show working overlay if app is enabled
        if !AppState.shared.isAppEnabled(context.bundleId) {
            hideOverlay()
            return
        }
        
        // Context is VALID (focused on an app). Cancel any pending hide.
        hideDebounceTask?.cancel()
        hideDebounceTask = nil
        autoHideTask?.cancel()
        autoHideTask = nil
        
        // Ensure visible immediately
        isVisible = true
        
        showOverlay(with: context)
        
        // Only trigger search if text is not empty and has changed
        let trimmedText = context.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedText.isEmpty {
            if trimmedText != lastSearchedText {
                print("[MemoryOverlay] Triggering search. Text changed: '\(lastSearchedText ?? "nil")' -> '\(trimmedText)'")
                lastSearchedText = trimmedText
                triggerBackgroundSearch(for: context.text)
            }
        } else {
            // Text is empty or whitespace - stay in idle/plus mode
            overlayState = .idle
            lastSearchedText = nil
            searchTask?.cancel()
        }
    }
    
    private func showOverlay(with context: ContextDetector.Context?) {
        // We always show overlay now (even for 0 results), unless explicitly hidden by other logic.
        
        // Fixed square size for perfect circle
        let buttonSize = CGSize(width: 28, height: 28)
        let margin: CGFloat = 8 // Space between cursor and button
        
        let position: CGPoint
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? NSScreen.main?.frame.height ?? 1080
        
        if let context = context {
            // Priority 1: Cursor-Right (User Request)
            // We check for valid cursor frame first.
            if let cursorFrame = context.cursorFrame, cursorFrame.height > 0 {
                // Convert AX cursor frame (Top-Left) to Cocoa frame (Bottom-Left)
                let cocoaCursorY = primaryScreenHeight - cursorFrame.maxY
                let cocoaCursorFrame = CGRect(x: cursorFrame.origin.x, y: cocoaCursorY, width: cursorFrame.width, height: cursorFrame.height)
                
                let screen = NSScreen.screens.first { screen in
                    screen.frame.intersects(cocoaCursorFrame)
                } ?? NSScreen.main
                
                let screenFrame = screen?.frame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
                
                // Position: Right of cursor, vertically centered
                var x = cocoaCursorFrame.maxX + margin
                // Center vertically relative to cursor height: CursorMidY - ButtonHalfHeight
                var y = cocoaCursorFrame.midY - (buttonSize.height / 2)
                
                // Clamp inside screen
                // Ensure it doesn't go off right edge
                if x + buttonSize.width > screenFrame.maxX - margin {
                    // If no space on right, flip to left? 
                    // Or keep sticky? Let's just clamp to max edge
                    x = screenFrame.maxX - buttonSize.width - margin
                }
                
                // Clamp vertically
                if y < screenFrame.minY + margin { y = screenFrame.minY + margin }
                if y + buttonSize.height > screenFrame.maxY - margin { y = screenFrame.maxY - buttonSize.height - margin }
                
                position = CGPoint(x: x, y: y)
            }
            // Priority 2: Element Frame (Fallback) - Bottom-Right inside input
            else if let elementFrame = context.elementFrame {
                // Convert AX (top-left) -> Cocoa (bottom-left)
                let cocoaY = primaryScreenHeight - elementFrame.maxY
                let cocoaElementFrame = CGRect(
                    x: elementFrame.origin.x,
                    y: cocoaY,
                    width: elementFrame.width,
                    height: elementFrame.height
                )
                
                let innerPadding: CGFloat = 8
                
                // Bottom-right INSIDE the input
                var x = cocoaElementFrame.maxX - buttonSize.width - innerPadding
                var y = cocoaElementFrame.minY + innerPadding
                
                position = CGPoint(x: x, y: y)
            }
            else {
                 // No context? Use last or default
                 position = window?.frame.origin ?? CGPoint(x: 100, y: 100)
            }
        } else {
            // Default/Fallback
            position = CGPoint(x: 100, y: 100)
        }
        
        if window == nil {
            let win = NSPanel(contentRect: NSRect(x: position.x, y: position.y, width: buttonSize.width, height: buttonSize.height),
                              styleMask: [.nonactivatingPanel, .borderless], // Borderless for custom shape
                              backing: .buffered,
                              defer: false)
            
            win.level = .floating
            win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            win.backgroundColor = .clear // IMPORTANT: Clear background for the capsule shape
            win.isOpaque = false
            win.hasShadow = false // View has shadow
            
            // Create the hosting view with the manager
            let hosting = NSHostingView(rootView: MemoryOverlayButtonView(manager: self))
            win.contentView = hosting
            
            self.window = win
        }
        
        // Ensure window size is correct (in case we changed it or it didn't update)
        if window?.frame.size != buttonSize {
             window?.setContentSize(buttonSize)
        }
        
        // Update position (always)
        window?.setFrameOrigin(position)
        
        if !isVisible {
            window?.orderFrontRegardless()
            isVisible = true
        }
    }
    
    private var searchTask: Task<Void, Never>?
    private var cachedMemories: [ExtractedMemory] = []
    
    private func scheduleDebouncedHide() {
        // If already scheduled, let it run
        guard hideDebounceTask == nil else { return }
        
        hideDebounceTask = Task { @MainActor in
            // Wait 500ms grace period. If context reappears, this task is cancelled.
            try? await Task.sleep(nanoseconds: 500 * 1_000_000)
            if Task.isCancelled { return }
            
            print("[MemoryOverlay] Grace period over. Hiding overlay.")
            self.hideOverlay()
            self.hideDebounceTask = nil
        }
    }
    
    func hideOverlay() {
        if isVisible {
            print("[MemoryOverlay] Hiding overlay (resetting state)")
        }
        window?.orderOut(nil)
        isVisible = false
        lastSearchedText = nil
        searchTask?.cancel()
        overlayState = .idle
        searchTask = nil
    }
    

    
    /// Triggered by updateOverlayVisibility when text is present
    private func triggerBackgroundSearch(for text: String) {
        // Cancel existing task to debounce
        searchTask?.cancel()
        
        // Use a slight delay before showing loading state to avoid flickering? 
        // Or strictly strictly follow user: "Wait 700-1000ms... Only show if cachedMemories.count > 0"
        // Actually user said: "Wait 700-1000ms after last keystroke... Only show if cachedMemories.count > 0"
        // But also said: State 1 - Idle/Scanning... meaning "Checking memory..."
        
        searchTask = Task { @MainActor in
            // Debounce: wait 400ms for user to stop typing (reduce noise)
            try? await Task.sleep(nanoseconds: 400 * 1_000_000)
            if Task.isCancelled {
                print("[MemoryOverlay] Search task cancelled during debounce")
                return
            }
            
            print("[MemoryOverlay] Debounce finished, setting .loading")
            self.overlayState = .loading
            
            do {
                // Search for related memories
                let memories = try await searchService.searchRelatedMemories(for: text, topK: 5)
                if Task.isCancelled { return }
                
                self.cachedMemories = memories
                print("[MemoryOverlay] Background search found \(memories.count) related memories")
                
                // Show count even if 0, to be explicit
                self.overlayState = .available(count: memories.count)
                
                // Helper to manage auto-hide
                self.autoHideTask?.cancel() 
                if memories.isEmpty {
                   self.scheduleAutoHide()
                }
                
                // Ensure window is visible
                // Note: We removed the .empty logic, so we don't hide it anymore.
                if self.isVisible {
                    self.window?.orderFrontRegardless()
                }
            } catch {
                if !Task.isCancelled {
                    print("[MemoryOverlay] Background search failed: \(error)")
                    self.cachedMemories = []
                    // Show error state? Or just 0?
                    self.overlayState = .available(count: 0)
                    // Auto-hide on error too
                    self.scheduleAutoHide()
                }
            }
        }
    }
    
    private func scheduleAutoHide() {
        autoHideTask = Task { @MainActor in
            // Wait 3 seconds then hide if still empty
            try? await Task.sleep(nanoseconds: 3 * 1_000_000_000)
            if Task.isCancelled { return }
            print("[MemoryOverlay] Auto-hiding empty overlay")
            self.hideOverlay()
        }
    }
    
    
    /// Public method to trigger memory insertion (called by button or shortcut)
    public func insertRelatedMemories() async {
        guard let context = contextDetector.currentContext() else { return }
        
        // If we have search results, insert them
        if !cachedMemories.isEmpty {
            overlayState = .inserting
            print("[MemoryOverlay] Inserting \(cachedMemories.count) related memories")
            insertService.insertMemories(cachedMemories)
            try? await Task.sleep(nanoseconds: 500 * 1_000_000)
            overlayState = .idle
            return
        }
        
        // If no search results but text exists, treat as "Manual Capture"?
        // Or if the user just wants to add a memory manually.
        await manualAddMemory()
    }
    
    /// Explicitly save the current text as a memory
    public func manualAddMemory() async {
        guard let context = contextDetector.currentContext() else { return }
        let text = context.text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !text.isEmpty else {
            print("[MemoryOverlay] Cannot add empty memory")
            return
        }
        
        overlayState = .loading
        print("[MemoryOverlay] Manually adding memory: \(text.prefix(50))...")
        
        // We use the same capture logic as CaptureCoordinator but triggered manually
        // We'll notify the AppState directly to show immediate feedback
        let memory = Memory(
            id: UUID().uuidString,
            createdAt: Date(),
            appBundleId: context.bundleId,
            appName: context.appName,
            windowTitle: context.windowTitle,
            source: .enterKey, // Manual add is treated as explicit intent
            text: text,
            textHash: MemoryStore.hashText(text)
        )
        
        AppState.shared.addMemory(memory)
        // Also trigger extraction/save in background
        // For now, just show success
        try? await Task.sleep(nanoseconds: 500 * 1_000_000)
        overlayState = .idle
    }
}


