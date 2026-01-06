//
//  AccessibilityWatcher.swift
//  MemoryTap
//
//  Watches focused UI elements using macOS Accessibility APIs
//

import Foundation
import AppKit
import ApplicationServices
import Combine

/// Watches the system-wide focused UI element and tracks text in editable fields
/// Uses AXUIElement APIs to read text from any application
@MainActor
final class AccessibilityWatcher: ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var currentApp: NSRunningApplication?
    @Published private(set) var currentAppName: String = ""
    @Published private(set) var currentAppBundleId: String = ""
    @Published private(set) var windowTitle: String = ""
    @Published private(set) var isEditableFieldFocused: Bool = false
    @Published private(set) var currentText: String = ""
    
    // MARK: - State Tracking
    
    /// Text that was in the field when user first focused it (to detect actual typing)
    private var initialTextOnFocus: String = ""
    
    /// Last known text content (for change detection)
    private var lastKnownText: String = ""
    
    /// Whether user has actually typed something (text changed from initial)
    private var userHasTyped: Bool = false
    
    /// Timestamp of last text edit
    private var lastEditTime: Date?
    
    /// Hash of last saved text (for deduplication)
    private var lastSavedTextHash: String = ""
    
    /// The current focused element reference
    private var currentElement: AXUIElement?
    
    /// System-wide element for accessibility queries
    private let systemWide = AXUIElementCreateSystemWide()
    
    /// Timer for polling focused element
    private var pollTimer: Timer?
    
    /// Workspace notification observers
    private var observers: [Any] = []
    
    // MARK: - Callbacks
    
    /// Called when text should be captured (focus lost with recent edits)
    var onTextShouldCapture: (@MainActor (String, CaptureSource, String, String, String) -> Void)?
    
    // MARK: - Configuration
    
    /// How long after last edit to consider text as "recently edited"
    private let recentEditThreshold: TimeInterval = 5.0
    
    /// Common placeholder texts to ignore
    private let placeholderPatterns: [String] = [
        "ask anything",
        "type a message",
        "write a message",
        "search",
        "type here",
        "enter text",
        "type something",
        "message",
        "send a message",
        "write something",
        "ask me anything",
        "what's on your mind",
        "type to search",
        "search or type",
    ]
    
    // MARK: - Initialization
    
    init() {
        setupNotifications()
    }
    
    // MARK: - Start/Stop
    
    func start() {
        guard pollTimer == nil else { return }
        
        // Poll every 100ms for focused element changes
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollFocusedElement()
            }
        }
        
        // Initial poll
        pollFocusedElement()
        
        print("[AccessibilityWatcher] Started watching")
    }
    
    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        print("[AccessibilityWatcher] Stopped watching")
    }
    
    func cleanup() {
        pollTimer?.invalidate()
        pollTimer = nil
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
    }
    
    // MARK: - Notifications
    
    private func setupNotifications() {
        // Watch for app activation changes
        let activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Extract data we need synchronously
            guard let userInfo = notification.userInfo,
                  let newApp = userInfo[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            let appName = newApp.localizedName ?? "Unknown"
            let bundleId = newApp.bundleIdentifier ?? ""
            
            Task { @MainActor [weak self] in
                self?.handleAppSwitchWithData(newApp: newApp, appName: appName, bundleId: bundleId)
            }
        }
        
        observers.append(activationObserver)
    }
    
    private func handleAppSwitchWithData(newApp: NSRunningApplication, appName: String, bundleId: String) {
        // Only capture if user actually typed something (not just placeholder text)
        if isEditableFieldFocused,
           userHasTyped,  // KEY: User must have actually typed
           let lastEdit = lastEditTime,
           Date().timeIntervalSince(lastEdit) < recentEditThreshold,
           !lastKnownText.isEmpty,
           !isPlaceholderText(lastKnownText),  // Skip placeholder text
           MemoryStore.hashText(lastKnownText) != lastSavedTextHash {
            
            let textToCapture = lastKnownText
            let prevAppName = currentAppName
            let prevBundleId = currentAppBundleId
            let window = windowTitle
            
            onTextShouldCapture?(textToCapture, .appSwitch, prevAppName, prevBundleId, window)
            lastSavedTextHash = MemoryStore.hashText(textToCapture)
        }
        
        // Update current app
        currentApp = newApp
        currentAppName = appName
        currentAppBundleId = bundleId
        
        // Update app state
        AppState.shared.currentAppName = currentAppName
        AppState.shared.currentAppBundleId = currentAppBundleId
    }
    
    // MARK: - Placeholder Detection
    
    /// Check if text looks like a placeholder
    private func isPlaceholderText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // Empty or very short text
        if trimmed.isEmpty || trimmed.count < 3 {
            return true
        }
        
        // Check against known placeholder patterns
        for pattern in placeholderPatterns {
            if trimmed == pattern || trimmed.hasPrefix(pattern) {
                return true
            }
        }
        
        // Check if it looks like a log message (starts with brackets)
        if trimmed.hasPrefix("[") && trimmed.contains("]") {
            return true
        }
        
        return false
    }
    
    // MARK: - Focus Tracking
    
    private func pollFocusedElement() {
        guard AXIsProcessTrusted() else { return }
        
        // Get focused application
        var focusedApp: AnyObject?
        let appResult = AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp)
        
        guard appResult == .success, let appElement = focusedApp else {
            return
        }
        
        // Get focused UI element
        var focusedElement: AnyObject?
        let elementResult = AXUIElementCopyAttributeValue(appElement as! AXUIElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        guard elementResult == .success, let element = focusedElement else {
            handleFocusLost()
            return
        }
        
        let axElement = element as! AXUIElement
        
        // Check if this is a new element
        if !isSameElement(axElement, currentElement) {
            handleFocusChange(from: currentElement, to: axElement)
            currentElement = axElement
        }
        
        // Update current app info
        updateCurrentAppInfo()
        
        // If editable, track text changes
        if isEditableFieldFocused {
            trackTextChanges(in: axElement)
        }
    }
    
    private func handleFocusChange(from oldElement: AXUIElement?, to newElement: AXUIElement) {
        // Only capture if user actually typed something
        if let _ = oldElement,
           isEditableFieldFocused,
           userHasTyped,  // KEY: User must have actually typed
           let lastEdit = lastEditTime,
           Date().timeIntervalSince(lastEdit) < recentEditThreshold,
           !lastKnownText.isEmpty,
           !isPlaceholderText(lastKnownText),
           MemoryStore.hashText(lastKnownText) != lastSavedTextHash {
            
            let textToCapture = lastKnownText
            let appName = currentAppName
            let bundleId = currentAppBundleId
            let window = windowTitle
            
            onTextShouldCapture?(textToCapture, .focusLost, appName, bundleId, window)
            lastSavedTextHash = MemoryStore.hashText(textToCapture)
        }
        
        // Reset state for new element
        lastKnownText = ""
        initialTextOnFocus = ""
        userHasTyped = false
        lastEditTime = nil
        
        // Check if new element is editable
        isEditableFieldFocused = isElementEditable(newElement)
        
        if isEditableFieldFocused {
            // Read initial text - this is what was already in the field
            if let text = getElementText(newElement) {
                initialTextOnFocus = text
                lastKnownText = text
                print("[AccessibilityWatcher] Focused editable field in \(currentAppName), initial text: '\(text.prefix(30))...'")
            } else {
                print("[AccessibilityWatcher] Focused editable field in \(currentAppName) but couldn't read text")
            }
        } else {
            // Debug: log why field wasn't detected as editable
            var roleValue: AnyObject?
            let roleResult = AXUIElementCopyAttributeValue(newElement, kAXRoleAttribute as CFString, &roleValue)
            let role = (roleResult == .success) ? (roleValue as? String ?? "unknown") : "error"
            
            // Only log for Cursor/VS Code to avoid spam
            if currentAppBundleId.contains("cursor") || currentAppBundleId.contains("vscode") || currentAppBundleId.contains("Code") {
                print("[AccessibilityWatcher] Field in \(currentAppName) not detected as editable (role: \(role))")
            }
        }
    }
    
    private func handleFocusLost() {
        guard isEditableFieldFocused else { return }
        
        // Only capture if user actually typed something
        if userHasTyped,  // KEY: User must have actually typed
           let lastEdit = lastEditTime,
           Date().timeIntervalSince(lastEdit) < recentEditThreshold,
           !lastKnownText.isEmpty,
           !isPlaceholderText(lastKnownText),
           MemoryStore.hashText(lastKnownText) != lastSavedTextHash {
            
            let textToCapture = lastKnownText
            let appName = currentAppName
            let bundleId = currentAppBundleId
            let window = windowTitle
            
            onTextShouldCapture?(textToCapture, .focusLost, appName, bundleId, window)
            lastSavedTextHash = MemoryStore.hashText(textToCapture)
        }
        
        isEditableFieldFocused = false
        currentElement = nil
        lastKnownText = ""
        initialTextOnFocus = ""
        userHasTyped = false
        lastEditTime = nil
    }
    
    // MARK: - Text Tracking
    
    private func trackTextChanges(in element: AXUIElement) {
        guard let currentTextValue = getElementText(element) else { return }
        
        if currentTextValue != lastKnownText {
            lastKnownText = currentTextValue
            lastEditTime = Date()
            self.currentText = currentTextValue
            
            // Check if user has typed (text is different from initial)
            if currentTextValue != initialTextOnFocus {
                userHasTyped = true
            }
        }
    }
    
    // MARK: - Element Inspection
    
    private func isElementEditable(_ element: AXUIElement) -> Bool {
        // Check if this is a secure/password field - skip these entirely
        if isSecureField(element) {
            return false
        }
        
        // Check role
        var roleValue: AnyObject?
        let roleResult = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        
        guard roleResult == .success, let role = roleValue as? String else {
            return false
        }
        
        // Common editable roles
        let editableRoles = [
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            kAXComboBoxRole as String,
            "AXWebArea", // Web content
            "AXText", // Some editors use this
            "AXGroup", // Cursor/VS Code might use this for editor groups
        ]
        
        if editableRoles.contains(role) {
            return true
        }
        
        // Check subrole for additional editable types
        var subroleValue: AnyObject?
        let subroleResult = AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleValue)
        
        if subroleResult == .success, let subrole = subroleValue as? String {
            let editableSubroles = [
                "AXSearchField",
                "AXSecureTextField", // Note: We filter this out above in isSecureField
                "AXContentArea", // Some editors
            ]
            if editableSubroles.contains(subrole) {
                return true
            }
        }
        
        // Check if element has editable attribute (most important check)
        var editableValue: AnyObject?
        let editableResult = AXUIElementCopyAttributeValue(element, "AXEditable" as CFString, &editableValue)
        
        if editableResult == .success, let editable = editableValue as? Bool, editable {
            // Additional check: if it's editable, also verify we can read text from it
            if getElementText(element) != nil {
                return true
            }
        }
        
        // For Cursor/VS Code: check if parent or child has editable content
        // Sometimes the focused element is a container, but the actual text is in a child
        if role == "AXGroup" || role == "AXScrollArea" {
            // Check if we can get text from this element or its children
            if getElementText(element) != nil {
                return true
            }
        }
        
        return false
    }
    
    private func isSecureField(_ element: AXUIElement) -> Bool {
        // Check subrole for secure text field
        var subroleValue: AnyObject?
        let subroleResult = AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleValue)
        
        if subroleResult == .success, let subrole = subroleValue as? String {
            if subrole == "AXSecureTextField" {
                return true
            }
        }
        
        // Check role description
        var descValue: AnyObject?
        let descResult = AXUIElementCopyAttributeValue(element, kAXRoleDescriptionAttribute as CFString, &descValue)
        
        if descResult == .success, let desc = descValue as? String {
            let secureKeywords = ["password", "secure", "secret"]
            let lowerDesc = desc.lowercased()
            if secureKeywords.contains(where: { lowerDesc.contains($0) }) {
                return true
            }
        }
        
        return false
    }
    
    private func getElementText(_ element: AXUIElement) -> String? {
        // Try kAXValueAttribute first (most common)
        var valueResult: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueResult)
        
        if result == .success, let value = valueResult as? String {
            return value
        }
        
        // For some elements, try getting selected text
        var selectedResult: AnyObject?
        let selectedTextResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedResult)
        
        if selectedTextResult == .success, let selected = selectedResult as? String, !selected.isEmpty {
            return selected
        }
        
        // For editors like Cursor/VS Code, try getting text from children
        // Sometimes the focused element is a container
        var childrenValue: AnyObject?
        let childrenResult = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue)
        
        if childrenResult == .success, let children = childrenValue as? [AXUIElement] {
            // Try to get text from first child that has text
            for child in children.prefix(5) { // Limit to first 5 children
                if let childText = getElementText(child), !childText.isEmpty {
                    return childText
                }
            }
        }
        
        // Try getting the document text (for code editors)
        var documentValue: AnyObject?
        let documentResult = AXUIElementCopyAttributeValue(element, "AXDocument" as CFString, &documentValue)
        
        if documentResult == .success, let document = documentValue as? String {
            return document
        }
        
        return nil
    }
    
    private func isSameElement(_ a: AXUIElement?, _ b: AXUIElement?) -> Bool {
        guard let a = a, let b = b else { return false }
        return CFEqual(a, b)
    }
    
    private func updateCurrentAppInfo() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        
        if currentApp?.processIdentifier != frontApp.processIdentifier {
            currentApp = frontApp
            currentAppName = frontApp.localizedName ?? "Unknown"
            currentAppBundleId = frontApp.bundleIdentifier ?? ""
            
            AppState.shared.currentAppName = currentAppName
            AppState.shared.currentAppBundleId = currentAppBundleId
        }
        
        // Try to get window title
        updateWindowTitle()
    }
    
    private func updateWindowTitle() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        
        var windowsValue: AnyObject?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)
        
        guard result == .success, let windows = windowsValue as? [AXUIElement], let firstWindow = windows.first else {
            windowTitle = ""
            return
        }
        
        var titleValue: AnyObject?
        let titleResult = AXUIElementCopyAttributeValue(firstWindow, kAXTitleAttribute as CFString, &titleValue)
        
        if titleResult == .success, let title = titleValue as? String {
            windowTitle = title
        }
    }
    
    // MARK: - Manual Capture (called by KeyEventListener)
    
    /// Called when Enter key is detected - immediately capture current text
    func captureCurrentTextOnEnter() {
        // For Cursor/editors, we might not have detected the field as editable
        // So try to read text from current element even if not marked as editable
        var textToCapture: String? = nil
        
        if isEditableFieldFocused && userHasTyped && !lastKnownText.isEmpty {
            // Normal case: we're tracking an editable field
            textToCapture = lastKnownText
        } else if let currentElement = currentElement {
            // Fallback: try to read text directly from focused element
            // This helps with Cursor/VS Code where the field might not be detected as editable
            if let directText = getElementText(currentElement),
               !directText.isEmpty,
               !isPlaceholderText(directText),
               directText.count >= 2 {
                // Check if text changed (user typed something)
                if directText != initialTextOnFocus {
                    textToCapture = directText
                    // Update our tracking state
                    lastKnownText = directText
                    userHasTyped = true
                }
            }
        }
        
        guard let text = textToCapture,
              !isPlaceholderText(text) else {
            print("[AccessibilityWatcher] Enter pressed but no valid text to capture (editable: \(isEditableFieldFocused), typed: \(userHasTyped), text: '\(lastKnownText.prefix(20))...')")
            return
        }
        
        let appName = currentAppName
        let bundleId = currentAppBundleId
        let window = windowTitle
        
        // Small delay to let the app process the Enter key first
        // (the text might change or clear after Enter)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            
            guard let self = self else { return }
            
            // Re-read text after delay in case it changed
            let finalText: String
            if let currentElement = self.currentElement,
               let updatedText = self.getElementText(currentElement),
               !updatedText.isEmpty,
               !self.isPlaceholderText(updatedText) {
                finalText = updatedText
            } else {
                finalText = text
            }
            
            // Check for duplicates
            let hash = MemoryStore.hashText(finalText)
            guard hash != self.lastSavedTextHash else {
                print("[AccessibilityWatcher] Duplicate text, skipping")
                return
            }
            
            print("[AccessibilityWatcher] Capturing text on Enter: '\(finalText.prefix(50))...' from \(appName)")
            
            self.onTextShouldCapture?(
                finalText,
                .enterKey,
                appName,
                bundleId,
                window
            )
            
            self.lastSavedTextHash = hash
            
            // Reset state since text was "sent"
            self.lastKnownText = ""
            self.initialTextOnFocus = ""
            self.userHasTyped = false
            self.lastEditTime = nil
        }
    }
}
