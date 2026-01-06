//
//  KeyEventListener.swift
//  MemoryTap
//
//  Global key event listener for detecting Enter/Cmd+Enter
//

import Foundation
import AppKit
import Carbon.HIToolbox
import Combine

/// Global storage for the listener reference (needed for C callback)
private var globalKeyEventListener: KeyEventListener?

/// Listens for global key events to detect "send" actions
/// Primarily watches for Enter and Cmd+Enter key combinations
@MainActor
final class KeyEventListener: ObservableObject {
    
    // MARK: - State
    
    @Published private(set) var isListening: Bool = false
    
    /// Event tap for global key monitoring
    private var eventTap: CFMachPort?
    
    /// Run loop source for the event tap
    private var runLoopSource: CFRunLoopSource?
    
    // MARK: - Callbacks
    
    /// Called when Enter or Cmd+Enter is detected
    var onEnterKeyPressed: (() -> Void)?
    
    // MARK: - Key Codes
    
    /// Return/Enter key code
    private let returnKeyCode: Int64 = Int64(kVK_Return)
    
    /// Keypad Enter key code
    private let enterKeyCode: Int64 = Int64(kVK_ANSI_KeypadEnter)
    
    // MARK: - Initialization
    
    init() {
        globalKeyEventListener = self
    }
    
    // MARK: - Start/Stop
    
    func start() {
        guard !isListening else { return }
        
        // Create event tap
        // We want to listen for key down events
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        
        // Create the callback as a literal closure
        let callback: CGEventTapCallBack = { proxy, type, event, userInfo in
            // Handle tap disabled events
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                DispatchQueue.main.async {
                    globalKeyEventListener?.reEnableTap()
                }
                return Unmanaged.passUnretained(event)
            }
            
            // Process key events
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
            options: .listenOnly,  // We only listen, don't modify events
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: nil
        ) else {
            print("[KeyEventListener] Failed to create event tap - Input Monitoring permission may be required")
            return
        }
        
        eventTap = tap
        
        // Create run loop source
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        
        // Add to run loop
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        
        // Enable the tap
        CGEvent.tapEnable(tap: tap, enable: true)
        
        isListening = true
        print("[KeyEventListener] Started listening for key events")
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
        
        print("[KeyEventListener] Stopped listening for key events")
    }
    
    /// Re-enable tap if it was disabled
    func reEnableTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }
    
    // MARK: - Key Processing
    
    /// Process a key event and check if it's Enter/Cmd+Enter
    func processKeyEvent(_ event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        
        // Check if it's Enter or Return
        guard keyCode == returnKeyCode || keyCode == enterKeyCode else {
            return
        }
        
        // Get modifier flags
        let flags = event.flags
        
        // We care about:
        // - Plain Enter (for single-line inputs like chat)
        // - Cmd+Enter (common "send" shortcut)
        // - Ctrl+Enter (another common send shortcut)
        
        // Check for common "send" modifiers or no modifiers
        let hasShift = flags.contains(.maskShift)
        let hasCmd = flags.contains(.maskCommand)
        let hasCtrl = flags.contains(.maskControl)
        let hasAlt = flags.contains(.maskAlternate)
        
        // Shift+Enter typically means "new line" in most apps, so skip
        if hasShift && !hasCmd && !hasCtrl {
            return
        }
        
        // Alt+Enter might have special meanings, skip for safety
        if hasAlt && !hasCmd && !hasCtrl {
            return
        }
        
        // Plain Enter, Cmd+Enter, or Ctrl+Enter - treat as "send"
        print("[KeyEventListener] Enter/Send key detected (cmd: \(hasCmd), ctrl: \(hasCtrl))")
        
        // Already on main actor, just call the callback
        onEnterKeyPressed?()
    }
}

