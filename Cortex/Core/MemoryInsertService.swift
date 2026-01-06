//
//  MemoryInsertService.swift
//  Cortex
//
//  Handles clipboard-safe insertion of memories into the current input
//  by simulating a paste operation (Cmd+V).
//

import Foundation
import AppKit
import Carbon.HIToolbox

@MainActor
final class MemoryInsertService {
    
    /// Insert given memories into the current focused input, below existing text.
    /// Uses clipboard save/restore and Cmd+V.
    func insertMemories(_ memories: [ExtractedMemory]) {
        guard !memories.isEmpty else { return }
        
        let header = "\n\nThese are relatable memories:\n"
        let bulletLines = memories.map { "- \($0.content)" }.joined(separator: "\n")
        let block = header + bulletLines + "\n"
        
        let pasteboard = NSPasteboard.general
        
        // Save existing clipboard
        let existing = pasteboard.string(forType: .string)
        
        // Set our text
        pasteboard.clearContents()
        pasteboard.setString(block, forType: .string)
        
        // Send Cmd+V
        simulateCmdV()
        
        // Restore clipboard after short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let existing = existing {
                pasteboard.clearContents()
                pasteboard.setString(existing, forType: .string)
            } else {
                pasteboard.clearContents()
            }
        }
    }
    
    private func simulateCmdV() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        
        let keyV: CGKeyCode = CGKeyCode(kVK_ANSI_V)
        
        // Create events
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false) else {
            return
        }
        
        // Set flags
        keyDown.flags = [.maskCommand]
        keyUp.flags = [.maskCommand]
        
        // Post events with delay
        keyDown.post(tap: .cghidEventTap)
        
        // Small delay to ensure app registers the key down state
        usleep(10000) // 10ms
        
        keyUp.post(tap: .cghidEventTap)
    }
    
    // Increased delay for cleanup
    // Restore clipboard after short delay
    // DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) -> Increased to 0.5
    // Actually, in insertMemories:
    // DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) ...
}


