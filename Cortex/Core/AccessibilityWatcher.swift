//
//  AccessibilityWatcher.swift
//  Cortex
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
    
    /// Called when focus changes to a new element
    /// Parameters: (oldElementWasEditable, newElementIsEditable, sameApp)
    var onFocusChanged: ((Bool, Bool, Bool) -> Void)?
    
    /// Called when app switches (for shadow buffer clearing)
    var onAppSwitched: (() -> Void)?
    
    /// Track previous app to detect app switches
    private var previousAppBundleId: String = ""
    
    /// Expose current AX element for overlay positioning
    func currentAXElement() -> AXUIElement? {
        return currentElement
    }
    
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
    
    // MARK: - Public Methods for CaptureCoordinator
    
    /// Get the text we've been tracking via Accessibility APIs
    func getTrackedText() -> String {
        return lastKnownText
    }
    
    /// Try to read text directly from the current focused element
    func tryReadCurrentElementText() -> String? {
        guard let element = currentElement else { return nil }
        return getElementText(element)
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
        
        // Track previous app before updating
        previousAppBundleId = currentAppBundleId
        
        // Update current app
        currentApp = newApp
        currentAppName = appName
        currentAppBundleId = bundleId
        
        // Update app state
        AppState.shared.currentAppName = currentAppName
        AppState.shared.currentAppBundleId = currentAppBundleId
        
        // Notify that app switched (for shadow buffer clearing)
        onAppSwitched?()
        
        // Reset tracking state for new app
        lastKnownText = ""
        initialTextOnFocus = ""
        userHasTyped = false
        lastEditTime = nil
    }
    
    // MARK: - Placeholder Detection
    
    /// Check if text looks like a placeholder or non-user-input
    private func isPlaceholderText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // Empty text only
        if trimmed.isEmpty {
            return true
        }
        
        // Check against known placeholder patterns (exact match or prefix)
        for pattern in placeholderPatterns {
            if trimmed == pattern || trimmed.hasPrefix(pattern) {
                return true
            }
        }
        
        // Check if it looks like a log message (starts with brackets)
        if trimmed.hasPrefix("[") && trimmed.contains("]") {
            return true
        }
        
        // Check if it's likely a window title or app name (not user input)
        // These are typically short and match app names or URLs without user context
        if isLikelyWindowTitleOrURL(trimmed) {
            return true
        }
        
        return false
    }
    
    /// Check if text looks like a window title, app name, or URL (not user-typed content)
    private func isLikelyWindowTitleOrURL(_ text: String) -> Bool {
        let appNames = [
            "google chrome", "safari", "firefox", "cursor", "xcode", "slack",
            "discord", "notion", "finder", "terminal", "messages", "mail",
            "spotify", "zoom", "teams", "Cortex", "code", "visual studio"
        ]
        
        // Exact match with app name
        if appNames.contains(text) {
            return true
        }
        
        // Looks like just a domain/URL without other content
        let urlPatterns = [".com", ".org", ".io", ".net", ".dev", "http://", "https://", "www."]
        if text.count < 50 { // Short text that's just a URL
            for pattern in urlPatterns {
                if text.contains(pattern) && !text.contains(" ") {
                    // It's a URL without spaces - probably not a user message
                    return true
                }
            }
        }
        
        // Just "github.com" or similar - not a message
        if text.hasSuffix(".com") || text.hasSuffix(".io") || text.hasSuffix(".org") {
            if !text.contains(" ") && text.count < 30 {
                return true
            }
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
        } else {
            // For Cursor/Electron apps: try to track even if not detected as editable
            // Sometimes the field isn't properly marked as editable but still has text
            if currentAppBundleId.contains("cursor") || currentAppBundleId.contains("Cursor") {
                if let text = getElementText(axElement), !text.isEmpty, !isPlaceholderText(text) {
                    // If we're getting text but field isn't marked editable, track it anyway
                    if lastKnownText != text {
                        let previousText = lastKnownText
                        lastKnownText = text
                        lastEditTime = Date()
                        self.currentText = text
                        
                        // Mark as typed if text changed
                        if text != initialTextOnFocus && (text.count > initialTextOnFocus.count || text != previousText) {
                            userHasTyped = true
                            print("[AccessibilityWatcher] Cursor: Tracking text even though not marked editable: '\(text.prefix(30))...'")
                        }
                    }
                }
            }
        }
        
        // Notify overlay manager candidate to update (via observers in AppDelegate)
        // We'll use AppState notifications indirectly, so nothing to do here directly.
    }
    
    private func handleFocusChange(from oldElement: AXUIElement?, to newElement: AXUIElement) {
        let oldWasEditable = isEditableFieldFocused
        let sameApp = (previousAppBundleId == currentAppBundleId)
        
        // Only capture if user actually typed something
        if let _ = oldElement,
           oldWasEditable,
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
        
        // Check if new element is editable BEFORE resetting state
        let newIsEditable = isElementEditable(newElement)
        
        // For Cursor: be more lenient - if we can read text, treat as editable
        var actuallyEditable = newIsEditable
        if !newIsEditable && (currentAppBundleId.contains("cursor") || currentAppBundleId.contains("Cursor")) {
            if let text = getElementText(newElement), !text.isEmpty, !isPlaceholderText(text) {
                actuallyEditable = true
                print("[AccessibilityWatcher] Cursor: Treating field as editable (can read text)")
            }
        }
        
        // Only reset state if we're leaving an editable field AND not entering another editable field
        // OR if we're switching apps
        if !sameApp || (oldWasEditable && !actuallyEditable) {
            // Reset state for new element
            lastKnownText = ""
            initialTextOnFocus = ""
            userHasTyped = false
            lastEditTime = nil
        }
        
        // Notify that focus changed (with context for smart buffer clearing)
        onFocusChanged?(oldWasEditable, actuallyEditable, sameApp)
        
        // Update editable state
        isEditableFieldFocused = actuallyEditable
        
        // For Cursor: be more lenient - if we can read text, treat as editable
        if !isEditableFieldFocused && (currentAppBundleId.contains("cursor") || currentAppBundleId.contains("Cursor")) {
            if let text = getElementText(newElement), !text.isEmpty, !isPlaceholderText(text) {
                isEditableFieldFocused = true
                print("[AccessibilityWatcher] Cursor: Treating field as editable (can read text)")
            }
        }
        
        if isEditableFieldFocused {
            // Read initial text - this is what was already in the field
            if let text = getElementText(newElement) {
                // Only track as initial if it's not a window title/app name
                if !isLikelyWindowTitleOrURL(text.lowercased()) {
                    initialTextOnFocus = text
                    lastKnownText = text
                    print("[AccessibilityWatcher] Focused editable field in \(currentAppName), initial: '\(text.prefix(30))...'")
                } else {
                    // Start with empty - the text we got is probably a window title
                    initialTextOnFocus = ""
                    lastKnownText = ""
                    print("[AccessibilityWatcher] Focused field in \(currentAppName), ignoring initial (looks like title): '\(text.prefix(30))...'")
                }
            } else {
                initialTextOnFocus = ""
                lastKnownText = ""
                print("[AccessibilityWatcher] Focused editable field in \(currentAppName) - empty or unreadable")
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
        
        // Skip if text looks like a window title or app name (not user input)
        // This prevents capturing "Google Chrome" etc. as user input
        if isLikelyWindowTitleOrURL(currentTextValue.lowercased()) {
            return
        }
        
        if currentTextValue != lastKnownText {
            let previousText = lastKnownText
            lastKnownText = currentTextValue
            lastEditTime = Date()
            self.currentText = currentTextValue
            
            // Check if user has typed (text is different from initial AND it grew or changed meaningfully)
            if currentTextValue != initialTextOnFocus {
                // Additional check: if text grew, user is definitely typing
                if currentTextValue.count > initialTextOnFocus.count ||
                   currentTextValue.count > previousText.count ||
                   !currentTextValue.hasPrefix(initialTextOnFocus) {
                    userHasTyped = true
                    print("[AccessibilityWatcher] Text changed: '\(currentTextValue.prefix(30))...' (typed: true)")
                }
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
        var textToCapture: String? = nil
        
        // Primary: use tracked text if user typed something
        if userHasTyped && !lastKnownText.isEmpty {
            textToCapture = lastKnownText
        }
        
        // Fallback for Cursor/Electron apps: try to read text directly from focused element
        // Even if we didn't detect it as editable or track it properly
        if textToCapture == nil, let currentElement = currentElement {
            print("[AccessibilityWatcher] Enter pressed but no tracked text, trying direct read from element...")
            
            // Try multiple methods to get text
            if let directText = getElementTextAggressive(currentElement),
               !directText.isEmpty,
               !isPlaceholderText(directText),
               directText.count >= 2 {
                textToCapture = directText
                print("[AccessibilityWatcher] ✓ Found text via direct read: '\(directText.prefix(50))...'")
            }
        }
        
        // Last resort for Cursor: try reading from parent or window
        if textToCapture == nil && (currentAppBundleId.contains("cursor") || currentAppBundleId.contains("Cursor")) {
            print("[AccessibilityWatcher] Cursor detected - trying aggressive text search...")
            if let windowText = tryGetTextFromCursorWindow() {
                textToCapture = windowText
                print("[AccessibilityWatcher] ✓ Found text from Cursor window: '\(windowText.prefix(50))...'")
            }
        }
        
        // Validate the text is actually user content
        guard let text = textToCapture,
              !text.isEmpty,
              !isPlaceholderText(text) else {
            // Debug log to help troubleshoot
            print("[AccessibilityWatcher] ✗ Enter pressed - no valid text found")
            print("  - Editable detected: \(isEditableFieldFocused)")
            print("  - User typed flag: \(userHasTyped)")
            print("  - Tracked text: '\(lastKnownText.prefix(50))...'")
            print("  - Initial text: '\(initialTextOnFocus.prefix(30))...'")
            print("  - App: \(currentAppName) (\(currentAppBundleId))")
            return
        }
        
        // Capture immediately - don't wait, as the text might be cleared
        let appName = currentAppName
        let bundleId = currentAppBundleId
        let window = windowTitle
        
        // Check for duplicates
        let hash = MemoryStore.hashText(text)
        guard hash != lastSavedTextHash else {
            print("[AccessibilityWatcher] Duplicate text, skipping")
            return
        }
        
        print("[AccessibilityWatcher] ✓✓✓ Capturing on Enter: '\(text.prefix(50))...' from \(appName)")
        
        onTextShouldCapture?(
            text,
            .enterKey,
            appName,
            bundleId,
            window
        )
        
        lastSavedTextHash = hash
        
        // Reset state since text was "sent"
        lastKnownText = ""
        initialTextOnFocus = ""
        userHasTyped = false
        lastEditTime = nil
    }
    
    /// Aggressive text reading - tries multiple methods
    private func getElementTextAggressive(_ element: AXUIElement) -> String? {
        // Method 1: Standard value attribute
        if let text = getElementText(element), !text.isEmpty {
            return text
        }
        
        // Method 2: Try parent element
        var parentValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parentValue) == .success,
           let parent = parentValue {
            let parentElement = parent as! AXUIElement
            if let parentText = getElementText(parentElement), !parentText.isEmpty {
                return parentText
            }
        }
        
        // Method 3: Try siblings
        var parent: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parent) == .success,
           let parentObj = parent {
            let parentElement = parentObj as! AXUIElement
            var childrenValue: AnyObject?
            if AXUIElementCopyAttributeValue(parentElement, kAXChildrenAttribute as CFString, &childrenValue) == .success,
               let children = childrenValue as? [AXUIElement] {
                // Check all siblings
                for sibling in children {
                    if let siblingText = getElementText(sibling), !siblingText.isEmpty, siblingText.count > 10 {
                        return siblingText
                    }
                }
            }
        }
        
        return nil
    }
    
    /// Try to get text from Cursor's window when Enter is pressed
    private func tryGetTextFromCursorWindow() -> String? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        
        // Get all windows
        var windowsValue: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement] else {
            return nil
        }
        
        // Try to find text in the frontmost window
        for window in windows.prefix(3) { // Check first 3 windows
            if let text = searchForTextInElement(window, maxDepth: 3) {
                return text
            }
        }
        
        return nil
    }
    
    /// Recursively search for text in an element and its children
    private func searchForTextInElement(_ element: AXUIElement, maxDepth: Int) -> String? {
        guard maxDepth > 0 else { return nil }
        
        // Try to get text from this element
        if let text = getElementText(element), !text.isEmpty, text.count > 5 {
            // Check if it looks like user input (not just UI labels)
            if !isPlaceholderText(text) && !isLikelyWindowTitleOrURL(text.lowercased()) {
                return text
            }
        }
        
        // Check children
        var childrenValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
           let children = childrenValue as? [AXUIElement] {
            for child in children.prefix(10) { // Limit search
                if let text = searchForTextInElement(child, maxDepth: maxDepth - 1) {
                    return text
                }
            }
        }
        
        return nil
    }
}
