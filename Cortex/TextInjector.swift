import AppKit

class TextInjector {
    static func insert(_ text: String) {
        guard AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString: true] as CFDictionary) else {
            showAccessibilityAlert()
            return
        }
        // Copy to clipboard
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        // Simulate Cmd+V using CGEvent (more robust than AppleScript)
        let src = CGEventSource(stateID: .combinedSessionState)
        let vDown = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true) // 'v'
        let vUp = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
        vDown?.flags = .maskCommand
        vDown?.post(tap: .cghidEventTap)
        vUp?.flags = .maskCommand
        vUp?.post(tap: .cghidEventTap)
    }

    private static func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Enable Accessibility"
        alert.informativeText = "Cortex needs Accessibility permissions to insert text. Go to System Preferences > Privacy & Security > Accessibility and enable Cortex."
        alert.alertStyle = .critical
        alert.runModal()
    }
}
