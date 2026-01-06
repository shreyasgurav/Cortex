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
        
        showOverlay(near: context.elementFrame)
        triggerBackgroundSearch(for: context.text)
    }
    
    private func showOverlay(near elementFrame: CGRect?) {
        // Button size we expect for the overlay window
        let buttonSize = CGSize(width: 32, height: 32)
        let margin: CGFloat = 6
        
        let position: CGPoint
        
        if let elementFrame = elementFrame {
            // AX coordinates are Top-Left relative to main screen
            // Cocoa coordinates are Bottom-Left relative to main screen
            // We need to flip Y using the primary screen height
            
            // Get the primary screen (index 0 usually contains the origin)
            // Or just use the union of all screens height? 
            // Standard approach: use NSScreen.screens[0].frame.height if assuming global coords.
            // But easier: `NSScreen.main` usually works for single screen contexts.
            // Let's use NSScreen.main?.frame.height for the flip reference.
            
            let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? NSScreen.main?.frame.height ?? 1080
            
            // Convert AX element frame (Top-Left) to Cocoa frame (Bottom-Left)
            // AX Y is distance from top.
            // Cocoa Y = Height - AX Y - HeightElement aka Height - (AX Y + HeightElement) = Height - AX MaxY
            let cocoaY = primaryScreenHeight - elementFrame.maxY
            let cocoaElementFrame = CGRect(x: elementFrame.origin.x, y: cocoaY, width: elementFrame.width, height: elementFrame.height)
            
            // Now find which screen this cocoa frame is on
            let screen = NSScreen.screens.first { screen in
                screen.frame.intersects(cocoaElementFrame)
            } ?? NSScreen.main
            
            let screenFrame = screen?.frame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
            
            // Position: Bottom-Right corner inside the element (Grammarly style)
            let innerMargin: CGFloat = 8
            
            // X: Right edge of element (same in both systems) - button width - margin
            var x = cocoaElementFrame.maxX - buttonSize.width - innerMargin
            
            // Y: Bottom edge of element (cocoaY) + margin (move up)
            var y = cocoaElementFrame.minY + innerMargin
            
            // Clamp inside screen horizontally
            if x + buttonSize.width > screenFrame.maxX - margin {
                x = screenFrame.maxX - buttonSize.width - margin
            }
            if x < screenFrame.minX + margin {
                x = screenFrame.minX + margin
            }
            
            // Clamp inside screen vertically
            if y + buttonSize.height > screenFrame.maxY - margin {
                y = screenFrame.maxY - buttonSize.height - margin
            }
            if y < screenFrame.minY + margin {
                y = screenFrame.minY + margin
            }
            
            position = CGPoint(x: x, y: y)
        } else if let screenFrame = NSScreen.main?.frame {
            // Fallback: center of main screen
            position = CGPoint(x: screenFrame.midX - buttonSize.width / 2,
                               y: screenFrame.midY - buttonSize.height / 2)
        } else {
            position = CGPoint(x: 200, y: 200)
        }
        
        if window == nil {
            let hosting = NSHostingView(rootView: MemoryOverlayButtonView { [weak self] in
                Task { @MainActor in
                    await self?.handleButtonTap()
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
    
    private func handleButtonTap() async {
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


