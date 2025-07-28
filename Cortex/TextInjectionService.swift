import Foundation
import AppKit
import ApplicationServices

class TextInjectionService: ObservableObject {
    static let shared = TextInjectionService()
    
    private init() {}
    
    // MARK: - Text Injection Methods
    
    func injectText(_ text: String) {
        print("🔍 [TextInjectionService] Attempting to inject text: \(text)")
        
        // Check permissions first
        if !checkAccessibilityPermissions() {
            print("❌ [TextInjectionService] No accessibility permissions - showing alert")
            showPermissionAlert()
            return
        }
        
        print("✅ [TextInjectionService] Accessibility permissions confirmed")
        
        // Method 1: Try Accessibility API first
        if injectTextViaAccessibility(text) {
            print("✅ [TextInjectionService] Text injected via Accessibility API")
            return
        }
        
        // Method 2: Try AppleScript with proper permissions
        if injectTextViaAppleScript(text) {
            print("✅ [TextInjectionService] Text injected via AppleScript")
            return
        }
        
        // Method 3: Try Pasteboard as fallback
        if injectTextViaPasteboard(text) {
            print("✅ [TextInjectionService] Text injected via Pasteboard")
            return
        }
        
        print("❌ [TextInjectionService] All text injection methods failed")
        showPermissionAlert()
    }
    
    // MARK: - Accessibility API Method
    
    private func injectTextViaAccessibility(_ text: String) -> Bool {
        print("🔍 [TextInjectionService] Attempting Accessibility API injection")
        
        // Get the frontmost application
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            print("❌ [TextInjectionService] No frontmost application found")
            return false
        }
        
        print("🔍 [TextInjectionService] Frontmost app: \(frontmostApp.localizedName ?? "Unknown")")
        
        // Create accessibility element for the frontmost app
        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        
        // Find the focused element (text field, text area, etc.)
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        if result != .success || focusedElement == nil {
            print("❌ [TextInjectionService] Could not find focused element")
            return false
        }
        
        print("✅ [TextInjectionService] Found focused element")
        
        // Try to get the current value to see if it's a text field
        var currentValue: CFTypeRef?
        let valueResult = AXUIElementCopyAttributeValue(focusedElement as! AXUIElement, kAXValueAttribute as CFString, &currentValue)
        
        if valueResult != .success {
            print("❌ [TextInjectionService] Could not get current value")
            return false
        }
        
        print("✅ [TextInjectionService] Current value retrieved")
        
        // Get current text
        let currentText = (currentValue as? String) ?? ""
        let newText = currentText + text
        
        // Set the new value
        let newValue = newText as CFString
        let setResult = AXUIElementSetAttributeValue(focusedElement as! AXUIElement, kAXValueAttribute as CFString, newValue)
        
        if setResult == .success {
            print("✅ [TextInjectionService] Successfully set text via Accessibility API")
            return true
        } else {
            print("❌ [TextInjectionService] Failed to set text via Accessibility API: \(setResult)")
            return false
        }
    }
    
    private func getFocusedWindow() -> AXUIElement? {
        guard let focusedApp = NSWorkspace.shared.frontmostApplication else { return nil }
        
        let appRef = AXUIElementCreateApplication(focusedApp.processIdentifier)
        var focusedWindow: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &focusedWindow)
        
        if result == .success, let window = focusedWindow {
            return (window as! AXUIElement)
        }
        
        return nil
    }
    
    private func getFocusedTextField(in window: AXUIElement) -> AXUIElement? {
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        if result == .success, let element = focusedElement {
            return (element as! AXUIElement)
        }
        
        return nil
    }
    
    private func insertTextAtCursor(_ text: String, in textField: AXUIElement) -> Bool {
        // Get current selection range
        var selectionRange: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(textField, kAXSelectedTextRangeAttribute as CFString, &selectionRange)
        
        if rangeResult != .success {
            print("❌ [TextInjectionService] Could not get selection range")
            return false
        }
        
        // Insert text at current position
        let insertResult = AXUIElementSetAttributeValue(textField, kAXSelectedTextRangeAttribute as CFString, text as CFString)
        
        return insertResult == .success
    }
    
    // MARK: - AppleScript Method
    
    private func injectTextViaAppleScript(_ text: String) -> Bool {
        let escapedText = text.replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\\", with: "\\\\")
        
        let script = """
        tell application "System Events"
            set theText to "\(escapedText)"
            keystroke theText
        end tell
        """
        
        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        let result = appleScript?.executeAndReturnError(&error)
        
        if let error = error {
            print("❌ [TextInjectionService] AppleScript error: \(error)")
            return false
        }
        
        return result != nil
    }
    
    // MARK: - Pasteboard Method
    
    private func injectTextViaPasteboard(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        guard pasteboard.setString(text, forType: .string) else {
            print("❌ [TextInjectionService] Failed to set pasteboard content")
            return false
        }
        
        // Simulate Cmd+V
        let script = """
        tell application "System Events"
            key code 9 using {command down}
        end tell
        """
        
        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        let result = appleScript?.executeAndReturnError(&error)
        
        if let error = error {
            print("❌ [TextInjectionService] Pasteboard script error: \(error)")
            return false
        }
        
        return result != nil
    }
    
    // MARK: - Testing Methods
    
    func testPermissions() {
        print("🔍 [TextInjectionService] Testing permissions...")
        
        let hasPermissions = checkAccessibilityPermissions()
        print("🔍 [TextInjectionService] Permission test result: \(hasPermissions)")
        
        if hasPermissions {
            print("✅ [TextInjectionService] Permissions are working correctly")
        } else {
            print("❌ [TextInjectionService] Permissions are not working")
            showPermissionAlert()
        }
    }
    
    private func showPermissionAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Cortex needs Accessibility permissions"
            alert.informativeText = "To insert text into other applications, Cortex needs Accessibility permissions.\n\nPlease follow these steps:\n1. Go to System Preferences > Privacy & Security > Accessibility\n2. Click the '+' button\n3. Navigate to this exact path:\n/Users/shreyasgurav/Library/Developer/Xcode/DerivedData/Cortex-cqzmqlkfnwttsfaydnatslwiazpy/Build/Products/Debug/Cortex.app\n4. Select 'Cortex.app' and click 'Open'\n5. Make sure the toggle is ON (blue)\n6. Restart Cortex\n\nIf you've already done this, try:\n- Removing Cortex from Accessibility and adding it again\n- Restarting your Mac"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Preferences")
            alert.addButton(withTitle: "Copy Path")
            alert.addButton(withTitle: "Test Permissions")
            alert.addButton(withTitle: "Cancel")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            } else if response == .alertSecondButtonReturn {
                let path = "/Users/shreyasgurav/Library/Developer/Xcode/DerivedData/Cortex-cqzmqlkfnwttsfaydnatslwiazpy/Build/Products/Debug/Cortex.app"
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(path, forType: .string)
                print("✅ Path copied to clipboard: \(path)")
            } else if response == .alertThirdButtonReturn {
                self.testPermissions()
            }
        }
    }
    
    private func checkAccessibilityPermissions() -> Bool {
        print("🔍 [TextInjectionService] Checking accessibility permissions...")
        
        // Method 1: Check if we can access accessibility APIs
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString: false]
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(options)
        
        print("🔍 [TextInjectionService] AXIsProcessTrustedWithOptions result: \(accessibilityEnabled)")
        
        // Method 2: Try to get accessibility elements (this will fail if no permissions)
        let app = NSWorkspace.shared.frontmostApplication
        if let app = app {
            print("🔍 [TextInjectionService] Frontmost app: \(app.localizedName ?? "Unknown")")
            
            // Try to get accessibility elements for the frontmost app
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(axApp, "AXTrusted" as CFString, &value)
            
            print("🔍 [TextInjectionService] AXUIElementCopyAttributeValue result: \(result)")
            
            if result == .success { // kAXErrorSuccess
                print("✅ [TextInjectionService] Accessibility permissions confirmed via AXUIElement")
                return true
            } else {
                print("❌ [TextInjectionService] AXUIElement failed with error: \(result)")
            }
        }
        
        // Method 3: Check if we can perform basic accessibility operations
        let testElement = AXUIElementCreateApplication(NSRunningApplication.current.processIdentifier)
        var testValue: CFTypeRef?
        let testResult = AXUIElementCopyAttributeValue(testElement, "AXTrusted" as CFString, &testValue)
        
        print("🔍 [TextInjectionService] Self-accessibility test result: \(testResult)")
        
        if testResult == .success { // kAXErrorSuccess
            print("✅ [TextInjectionService] Self-accessibility test passed")
            return true
        }
        
        print("❌ [TextInjectionService] All accessibility permission checks failed")
        return accessibilityEnabled
    }
} 