import Foundation
import AppKit
import ApplicationServices

class TextInjectionService: ObservableObject {
    static let shared = TextInjectionService()
    
    private var permissionCache: (accessibility: Bool, automation: Bool)?
    private var lastPermissionCheck: Date = Date.distantPast
    private let permissionCacheTimeout: TimeInterval = 300 // Cache for 5 minutes
    private var hasShownPermissionAlert = false
    
    private init() {}
    
    // MARK: - Text Injection Methods
    
    func injectText(_ text: String) {
        print("🔍 [TextInjectionService] Attempting to inject text: \(text)")
        
        // Check permissions first (with caching)
        let permissions = checkAllPermissions()
        if !permissions.accessibility && !permissions.automation {
            print("❌ [TextInjectionService] No permissions available")
            // Only show alert once per session unless cache is cleared
            if !hasShownPermissionAlert {
                hasShownPermissionAlert = true
                showPermissionAlert()
            }
            return
        }
        
        print("✅ [TextInjectionService] Permissions confirmed - accessibility: \(permissions.accessibility), automation: \(permissions.automation)")
        
        // Method 1: Try Accessibility API first (if we have accessibility permissions)
        if permissions.accessibility && injectTextViaAccessibility(text) {
            print("✅ [TextInjectionService] Text injected via Accessibility API")
            return
        }
        
        // Method 2: Try AppleScript (if we have automation permissions)
        if permissions.automation && injectTextViaAppleScript(text) {
            print("✅ [TextInjectionService] Text injected via AppleScript")
            return
        }
        
        // Method 3: Try Pasteboard as fallback (if we have automation permissions)
        if permissions.automation && injectTextViaPasteboard(text) {
            print("✅ [TextInjectionService] Text injected via Pasteboard")
            return
        }
        
        print("❌ [TextInjectionService] All text injection methods failed")
        // Clear cache and try again, but don't show alert immediately
        clearPermissionCache()
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
        // First check if we have System Events permissions
        let checkScript = """
        tell application "System Events"
            return true
        end tell
        """
        
        let checkAppleScript = NSAppleScript(source: checkScript)
        var checkError: NSDictionary?
        _ = checkAppleScript?.executeAndReturnError(&checkError)
        
        if let checkError = checkError {
            print("❌ [TextInjectionService] System Events permission check failed: \(checkError)")
            return false
        }
        
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
        
        // Check System Events permissions first
        let checkScript = """
        tell application "System Events"
            return true
        end tell
        """
        
        let checkAppleScript = NSAppleScript(source: checkScript)
        var checkError: NSDictionary?
        _ = checkAppleScript?.executeAndReturnError(&checkError)
        
        if let checkError = checkError {
            print("❌ [TextInjectionService] System Events permission check failed for pasteboard: \(checkError)")
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
        
        let permissions = checkAllPermissions()
        print("🔍 [TextInjectionService] Permission test result - accessibility: \(permissions.accessibility), automation: \(permissions.automation)")
        
        if permissions.accessibility || permissions.automation {
            print("✅ [TextInjectionService] Permissions are working correctly")
        } else {
            print("❌ [TextInjectionService] Permissions are not working")
            showPermissionAlert()
        }
    }
    
    private func checkAllPermissions() -> (accessibility: Bool, automation: Bool) {
        // Check if we have cached permissions that are still valid
        if let cache = permissionCache, 
           Date().timeIntervalSince(lastPermissionCheck) < permissionCacheTimeout {
            return cache
        }
        
        let accessibility = checkAccessibilityPermissions()
        let automation = checkAutomationPermissions()
        
        permissionCache = (accessibility: accessibility, automation: automation)
        lastPermissionCheck = Date()
        
        return (accessibility: accessibility, automation: automation)
    }
    
    private func checkAutomationPermissions() -> Bool {
        let checkScript = """
        tell application "System Events"
            return true
        end tell
        """
        
        let appleScript = NSAppleScript(source: checkScript)
        var error: NSDictionary?
        let result = appleScript?.executeAndReturnError(&error)
        
        if let error = error {
            print("❌ [TextInjectionService] Automation permission check failed: \(error)")
            return false
        }
        
        print("✅ [TextInjectionService] Automation permissions confirmed")
        return result != nil
    }
    
    func clearPermissionCache() {
        permissionCache = nil
        lastPermissionCheck = Date.distantPast
        hasShownPermissionAlert = false
        print("🔍 [TextInjectionService] Permission cache cleared")
    }
    
    private func showPermissionAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Cortex needs permissions"
            alert.informativeText = "To insert text into other applications, Cortex needs two types of permissions:\n\n1. ACCESSIBILITY PERMISSIONS:\n- Go to System Preferences > Privacy & Security > Accessibility\n- Click the '+' button and add Cortex.app\n- Make sure the toggle is ON (blue)\n\n2. AUTOMATION PERMISSIONS:\n- Go to System Preferences > Privacy & Security > Automation\n- Find 'Cortex' in the list\n- Make sure 'System Events' is checked\n\nAfter granting permissions:\n- Restart Cortex\n- Try the text injection again\n\nIf you've already done this, try:\n- Removing Cortex from both permissions and adding it again\n- Restarting your Mac"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open Accessibility Settings")
            alert.addButton(withTitle: "Open Automation Settings")
            alert.addButton(withTitle: "Test Permissions")
            alert.addButton(withTitle: "Clear Cache & Retry")
            alert.addButton(withTitle: "Cancel")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            } else if response == .alertSecondButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
            } else if response == .alertThirdButtonReturn {
                self.testPermissions()
            } else if response.rawValue == NSApplication.ModalResponse.alertThirdButtonReturn.rawValue + 1 {
                self.clearPermissionCache()
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
            let result = AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &value)
            
            print("🔍 [TextInjectionService] AXUIElementCopyAttributeValue result: \(result)")
            
            if result == .success { // kAXErrorSuccess
                print("✅ [TextInjectionService] Accessibility permissions confirmed via AXUIElement")
                return true
            } else {
                print("❌ [TextInjectionService] AXUIElement failed with error: \(result)")
            }
        }
        
        // Method 3: Check if we can perform basic accessibility operations on our own app
        let testElement = AXUIElementCreateApplication(NSRunningApplication.current.processIdentifier)
        var testValue: CFTypeRef?
        let testResult = AXUIElementCopyAttributeValue(testElement, kAXFocusedUIElementAttribute as CFString, &testValue)
        
        print("🔍 [TextInjectionService] Self-accessibility test result: \(testResult)")
        
        if testResult == .success { // kAXErrorSuccess
            print("✅ [TextInjectionService] Self-accessibility test passed")
            return true
        }
        
        print("❌ [TextInjectionService] All accessibility permission checks failed")
        return accessibilityEnabled
    }
} 