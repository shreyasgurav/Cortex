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
    }
    
    private func showOverlay(near elementFrame: CGRect?) {
        // Button size we expect for the overlay window
        let buttonSize = CGSize(width: 32, height: 32)
        let margin: CGFloat = 6
        
        let position: CGPoint
        
        if let elementFrame = elementFrame {
            // Try to find the screen that contains this element
            let screen = NSScreen.screens.first { screen in
                screen.frame.intersects(elementFrame)
            } ?? NSScreen.main
            
            let screenFrame = screen?.frame ?? NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
            
            // Base position: just to the right of the element, vertically centered on it
            var x = elementFrame.maxX + margin
            var y = elementFrame.midY - buttonSize.height / 2
            
            // Clamp inside screen horizontally
            if x + buttonSize.width > screenFrame.maxX - margin {
                x = elementFrame.minX - buttonSize.width - margin
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
    
    func hideOverlay() {
        window?.orderOut(nil)
        isVisible = false
    }
    
    private func handleButtonTap() async {
        guard let context = contextDetector.currentContext() else { return }
        
        do {
            let memories = try await searchService.searchRelatedMemories(for: context.text, topK: 5)
            if memories.isEmpty {
                print("[MemoryOverlay] No related memories found for current context")
                return
            }
            
            print("[MemoryOverlay] Found \(memories.count) related memories, inserting...")
            
            // For V1: insert all results directly (no selection UI yet)
            insertService.insertMemories(memories)
        } catch {
            print("[MemoryOverlay] Search failed: \(error)")
        }
    }
}


