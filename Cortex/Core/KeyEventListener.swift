//
//  KeyEventListener.swift
//  Cortex
//
//  Global key event listener with shadow buffer for Electron apps
//  This is the "secret sauce" - track keystrokes to build text internally
//

import Foundation
import AppKit
import Carbon.HIToolbox
import Combine

/// Global storage for the listener reference (needed for C callback)
private var globalKeyEventListener: KeyEventListener?

/// Listens for global key events to detect "send" actions
/// Uses a shadow buffer to track typed text for Electron apps (Cursor, VS Code, Slack)
/// that don't expose text reliably via Accessibility APIs
@MainActor
final class KeyEventListener: ObservableObject {
    
    // MARK: - State
    
    @Published private(set) var isListening: Bool = false
    
    /// Shadow buffer - tracks what user types character by character
    /// This is critical for Electron apps where AXValue doesn't work
    @Published private(set) var shadowBuffer: String = ""
    
    /// Event tap for global key monitoring
    private var eventTap: CFMachPort?
    
    /// Run loop source for the event tap
    private var runLoopSource: CFRunLoopSource?
    
    /// Timestamp of last keystroke (for detecting pauses)
    private var lastKeystrokeTime: Date?
    
    /// Maximum time between keystrokes before buffer is considered "stale"
    private let keystrokeTimeout: TimeInterval = 30.0 // 30 seconds
    
    // MARK: - Callbacks
    
    /// Called when Enter or Cmd+Enter is detected
    /// Passes the shadow buffer content
    var onEnterKeyPressed: ((String) -> Void)?
    
    /// Called when user types (for debugging)
    var onKeystroke: ((String) -> Void)?
    
    // MARK: - Key Codes
    
    private let returnKeyCode: Int64 = Int64(kVK_Return)
    private let enterKeyCode: Int64 = Int64(kVK_ANSI_KeypadEnter)
    private let deleteKeyCode: Int64 = Int64(kVK_Delete)         // Backspace
    private let forwardDeleteKeyCode: Int64 = Int64(kVK_ForwardDelete)
    private let tabKeyCode: Int64 = Int64(kVK_Tab)
    private let escapeKeyCode: Int64 = Int64(kVK_Escape)
    
    // MARK: - Initialization
    
    init() {
        globalKeyEventListener = self
    }
    
    // MARK: - Start/Stop
    
    func start() {
        guard !isListening else { return }
        
        // Create event tap - listen to ALL key events, not just Enter
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        
        let callback: CGEventTapCallBack = { proxy, type, event, userInfo in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                DispatchQueue.main.async {
                    globalKeyEventListener?.reEnableTap()
                }
                return Unmanaged.passUnretained(event)
            }
            
            if type == .keyDown {
                DispatchQueue.main.async {
                    globalKeyEventListener?.processKeyEvent(event)
                }
            }
            
            return Unmanaged.passUnretained(event)
        }
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: nil
        ) else {
            print("[KeyEventListener] Failed to create event tap - Input Monitoring permission may be required")
            return
        }
        
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        
        isListening = true
        print("[KeyEventListener] Started listening for key events (with shadow buffer)")
    }
    
    func stop() {
        guard isListening else { return }
        
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        
        eventTap = nil
        runLoopSource = nil
        isListening = false
        shadowBuffer = ""
        
        print("[KeyEventListener] Stopped listening for key events")
    }
    
    func reEnableTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }
    
    // MARK: - Shadow Buffer Management
    
    /// Clear the shadow buffer (called on focus change, app switch, etc.)
    func clearBuffer() {
        if !shadowBuffer.isEmpty {
            print("[KeyEventListener] Clearing shadow buffer (was: '\(shadowBuffer.prefix(30))...')")
        }
        shadowBuffer = ""
        lastKeystrokeTime = nil
    }
    
    /// Get and clear the buffer (for capture)
    func consumeBuffer() -> String {
        let text = shadowBuffer
        shadowBuffer = ""
        lastKeystrokeTime = nil
        return text
    }
    
    // MARK: - Key Processing
    
    func processKeyEvent(_ event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        
        // Check if buffer is stale (no typing for a while)
        if let lastTime = lastKeystrokeTime,
           Date().timeIntervalSince(lastTime) > keystrokeTimeout {
            clearBuffer()
        }
        
        // Handle special keys
        if keyCode == deleteKeyCode {
            // Backspace - remove last character
            handleBackspace(withCommand: flags.contains(.maskCommand))
            return
        }
        
        if keyCode == forwardDeleteKeyCode {
            // Forward delete - for now just ignore (complex to handle properly)
            return
        }
        
        if keyCode == escapeKeyCode {
            // Escape - clear buffer (user likely cancelled)
            clearBuffer()
            return
        }
        
        if keyCode == tabKeyCode {
            // Tab - might be autocomplete, ignore
            return
        }
        
        // Check if it's Enter
        if keyCode == returnKeyCode || keyCode == enterKeyCode {
            handleEnterKey(flags: flags)
            return
        }
        
        // For Cmd+A, Cmd+V, Cmd+C, Cmd+X - handle specially
        if flags.contains(.maskCommand) {
            handleCommandShortcut(keyCode: keyCode, event: event)
            return
        }
        
        // Regular character - add to buffer
        if let characters = event.keyboardEventCharacters, !characters.isEmpty {
            // Don't add control characters
            if !characters.unicodeScalars.allSatisfy({ CharacterSet.controlCharacters.contains($0) }) {
                shadowBuffer += characters
                lastKeystrokeTime = Date()
                
                // Debug log (only if buffer is short, to avoid spam)
                if shadowBuffer.count <= 50 {
                    print("[KeyEventListener] Buffer: '\(shadowBuffer)'")
                } else if shadowBuffer.count % 20 == 0 {
                    print("[KeyEventListener] Buffer length: \(shadowBuffer.count)")
                }
            }
        }
    }
    
    private func handleBackspace(withCommand: Bool) {
        if withCommand {
            // Cmd+Delete = delete word or line, just clear buffer to be safe
            clearBuffer()
        } else if !shadowBuffer.isEmpty {
            shadowBuffer.removeLast()
            lastKeystrokeTime = Date()
        }
    }
    
    private func handleCommandShortcut(keyCode: Int64, event: CGEvent) {
        // Get the character for the key
        guard let characters = event.keyboardEventCharacters?.lowercased() else { return }
        
        switch characters {
        case "a":
            // Cmd+A (Select All) - user might be replacing text
            // Don't clear, but note it happened
            print("[KeyEventListener] Cmd+A detected (select all)")
            
        case "v":
            // Cmd+V (Paste) - we can't know what was pasted
            // Clear buffer since pasted content won't be tracked
            print("[KeyEventListener] Cmd+V detected (paste) - buffer may be incomplete")
            // Don't clear - let the paste add to whatever they typed
            // The Accessibility layer should capture the final result
            
        case "c", "x":
            // Cmd+C/X (Copy/Cut) - doesn't affect what we're tracking
            break
            
        case "z":
            // Cmd+Z (Undo) - buffer is now unreliable
            print("[KeyEventListener] Cmd+Z detected (undo) - clearing buffer")
            clearBuffer()
            
        default:
            break
        }
    }
    
    private func handleEnterKey(flags: CGEventFlags) {
        let hasShift = flags.contains(.maskShift)
        let hasCmd = flags.contains(.maskCommand)
        let hasCtrl = flags.contains(.maskControl)
        let hasAlt = flags.contains(.maskAlternate)
        
        // Shift+Enter = new line in most apps
        if hasShift && !hasCmd && !hasCtrl {
            // Add newline to buffer instead of triggering capture
            shadowBuffer += "\n"
            lastKeystrokeTime = Date()
            print("[KeyEventListener] Shift+Enter - added newline to buffer")
            return
        }
        
        // Alt+Enter might have special meanings
        if hasAlt && !hasCmd && !hasCtrl {
            return
        }
        
        // Plain Enter, Cmd+Enter, or Ctrl+Enter = "send"
        print("[KeyEventListener] Enter/Send detected (cmd: \(hasCmd), ctrl: \(hasCtrl))")
        print("[KeyEventListener] Shadow buffer has \(shadowBuffer.count) characters: '\(shadowBuffer.prefix(50))...'")
        
        // Pass the buffer content to the callback
        let bufferContent = shadowBuffer
        
        // Call the callback with the buffer
        onEnterKeyPressed?(bufferContent)
        
        // Clear buffer after "send"
        clearBuffer()
    }
}

// MARK: - CGEvent extension for getting typed characters

extension CGEvent {
    /// Get the characters typed for this key event
    var keyboardEventCharacters: String? {
        // Try to get the Unicode string for this event
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        
        // Use keyboardEventAutorepeat to check if it's a repeat
        // We want to capture repeats too
        
        self.keyboardGetUnicodeString(
            maxStringLength: 4,
            actualStringLength: &length,
            unicodeString: &chars
        )
        
        guard length > 0 else { return nil }
        
        return String(utf16CodeUnits: chars, count: length)
    }
}
