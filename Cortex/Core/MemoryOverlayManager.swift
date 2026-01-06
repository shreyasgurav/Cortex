//
//  MemoryOverlayManager.swift
//  Cortex
//
//  Manages the floating \"memory\" button overlay and search+insert flow.
//

import Foundation
import AppKit
import SwiftUI

@MainActor
final class MemoryOverlayManager {
    
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
            hideOverlay()
            return
        }
        
        guard let context = contextDetector.currentContext(),
              !context.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            hideOverlay()
            return
        }
        
        showOverlay(with: context)
        triggerBackgroundSearch(for: context.text)
    }
    
    private func showOverlay(with context: ContextDetector.Context?) {
        // Button size we expect for the overlay window
        let buttonSize = CGSize(width: 32, height: 32)
        let margin: CGFloat = 6
        
        let position: CGPoint
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? NSScreen.main?.frame.height ?? 1080
        
        if let context = context {
            // Priority 1: Cursor Frame (Position ABOVE cursor)
            if let cursorFrame = context.cursorFrame, cursorFrame.width > 0 && cursorFrame.height > 0 {
                // Convert AX cursor frame (Top-Left) to Cocoa frame (Bottom-Left)
                let cocoaCursorY = primaryScreenHeight - cursorFrame.maxY
                let cocoaCursorFrame = CGRect(x: cursorFrame.origin.x, y: cocoaCursorY, width: cursorFrame.width, height: cursorFrame.height)
                
                // Find screen for cursor
                let screen = NSScreen.screens.first { screen in
                    screen.frame.intersects(cocoaCursorFrame)
                } ?? NSScreen.main
                let screenFrame = screen?.frame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
                
                // Position: Centered horizontally on cursor, floating ABOVE it
                // X: Cursor MidX - Half Button Width
                var x = cocoaCursorFrame.midX - (buttonSize.width / 2)
                // Y: Cursor MaxY (top in Cocoa) + margin
                var y = cocoaCursorFrame.maxY + margin
                
                // Clamp inside screen
                if x < screenFrame.minX + margin { x = screenFrame.minX + margin }
                if x + buttonSize.width > screenFrame.maxX - margin { x = screenFrame.maxX - buttonSize.width - margin }
                
                // If hitting top of screen, flip to below
                if y + buttonSize.height > screenFrame.maxY - margin {
                    y = cocoaCursorFrame.minY - buttonSize.height - margin
                    // Double check bottom clamp
                    if y < screenFrame.minY + margin { y = screenFrame.minY + margin }
                }
                
                position = CGPoint(x: x, y: y)
                
            } 
            // Priority 2: Element Frame (Position Bottom-Right INSIDE element)
            else if let elementFrame = context.elementFrame {
                // Convert AX element frame to Cocoa
                let cocoaY = primaryScreenHeight - elementFrame.maxY
                let cocoaElementFrame = CGRect(x: elementFrame.origin.x, y: cocoaY, width: elementFrame.width, height: elementFrame.height)
                
                // Find screen
                let screen = NSScreen.screens.first { screen in
                    screen.frame.intersects(cocoaElementFrame)
                } ?? NSScreen.main
                let screenFrame = screen?.frame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
                
                let innerMargin: CGFloat = 8
                var x = cocoaElementFrame.maxX - buttonSize.width - innerMargin
                var y = cocoaElementFrame.minY + innerMargin
                
                // Clamp
                if x + buttonSize.width > screenFrame.maxX - 8 { x = screenFrame.maxX - buttonSize.width - 8 }
                if x < screenFrame.minX + 8 { x = screenFrame.minX + 8 }
                if y + buttonSize.height > screenFrame.maxY - 8 { y = screenFrame.maxY - buttonSize.height - 8 }
                if y < screenFrame.minY + 8 { y = screenFrame.minY + 8 }
                
                position = CGPoint(x: x, y: y)
                
            } 
            // Fallback
            else {
                 position = CGPoint(x: 200, y: 200)
            }
        } else {
            position = CGPoint(x: 200, y: 200)
        }
        
        if window == nil {
            let hosting = NSHostingView(rootView: MemoryOverlayButtonView { [weak self] in
                Task { @MainActor in
                    await self?.insertRelatedMemories()
                }
            })
            
            let win = NSPanel(
                contentRect: NSRect(x: position.x, y: position.y, width: buttonSize.width, height: buttonSize.height),
                styleMask: [.nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            win.isOpaque = false
            win.backgroundColor = .clear
            win.level = .floating
            win.hasShadow = false
            win.ignoresMouseEvents = false
            win.hidesOnDeactivate = false
            win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            win.becomesKeyOnlyIfNeeded = false
            win.contentView = hosting
            
            window = win
            win.orderFrontRegardless()
        } else if let win = window {
            let frame = NSRect(x: position.x, y: position.y, width: win.frame.width, height: win.frame.height)
            win.setFrame(frame, display: true)
            win.orderFrontRegardless()
        }
        
        isVisible = true
    }
    
    private var searchTask: Task<Void, Never>?
    private var cachedMemories: [ExtractedMemory] = []
    
    func hideOverlay() {
        window?.orderOut(nil)
        isVisible = false
        // Cancel any pending search
        searchTask?.cancel()
        searchTask = nil
    }
    

    
    /// Triggered by updateOverlayVisibility when text is present
    private func triggerBackgroundSearch(for text: String) {
        // Cancel existing task to debounce
        searchTask?.cancel()
        
        searchTask = Task { @MainActor in
            // Debounce: wait 500ms for user to stop typing
            try? await Task.sleep(nanoseconds: 500 * 1_000_000)
            if Task.isCancelled { return }
            
            do {
                // Search for related memories
                let memories = try await searchService.searchRelatedMemories(for: text, topK: 5)
                if Task.isCancelled { return }
                
                self.cachedMemories = memories
                print("[MemoryOverlay] Background search found \(memories.count) related memories")
            } catch {
                if !Task.isCancelled {
                    print("[MemoryOverlay] Background search failed: \(error)")
                    self.cachedMemories = []
                }
            }
        }
    }
    
    
    /// Public method to trigger memory insertion (called by button or shortcut)
    public func insertRelatedMemories() async {
        guard let context = contextDetector.currentContext() else { return }
        
        // Use cached memories if available and context matches (roughly)
        // Or if not available, try immediate search? 
        // User said "keep loading... in background", and "as i click... add memories"
        // If we have cached results, use them. If not (maybe typed too fast), try searching now.
        
        var memoriesToInsert = cachedMemories
        
        if memoriesToInsert.isEmpty {
            // Try explicit search if cache is empty
            do {
                memoriesToInsert = try await searchService.searchRelatedMemories(for: context.text, topK: 5)
            } catch {
                print("[MemoryOverlay] Search failed: \(error)")
                return
            }
        }
        
        if memoriesToInsert.isEmpty {
            print("[MemoryOverlay] No related memories found to insert")
            return
        }
        
        print("[MemoryOverlay] Inserting \(memoriesToInsert.count) related memories")
        insertService.insertMemories(memoriesToInsert)
    }
}


