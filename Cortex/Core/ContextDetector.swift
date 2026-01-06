//
//  ContextDetector.swift
//  Cortex
//
//  Lightweight helper to get current text + bounds for the focused element.
//  Uses AccessibilityWatcher as the primary source.
//

import Foundation
import AppKit
import ApplicationServices

@MainActor
final class ContextDetector {
    
    private let accessibilityWatcher: AccessibilityWatcher
    
    init(accessibilityWatcher: AccessibilityWatcher) {
        self.accessibilityWatcher = accessibilityWatcher
    }
    
    struct Context {
        let text: String
        let appName: String
        let bundleId: String
        let windowTitle: String
        let elementFrame: CGRect?
    }
    
    /// Best-effort: current text context + approximate bounds of focused element
    func currentContext() -> Context? {
        let text = accessibilityWatcher.getTrackedText()
        if text.isEmpty {
            return nil
        }
        
        let appName = accessibilityWatcher.currentAppName
        let bundleId = accessibilityWatcher.currentAppBundleId
        let windowTitle = accessibilityWatcher.windowTitle
        
        // Try to get element bounds via raw AX API
        var frame: CGRect? = nil
        if let element = accessibilityWatcher.currentAXElement() {
            var value: AnyObject?
            // Use AXFrame attribute via raw string to avoid symbol issues
            if AXUIElementCopyAttributeValue(element, "AXFrame" as CFString, &value) == .success,
               let rectValue = value {
                let axVal = rectValue as! AXValue
                if AXValueGetType(axVal) == .cgRect {
                    var cgRect = CGRect.zero
                    if AXValueGetValue(axVal, .cgRect, &cgRect) {
                        frame = cgRect
                    }
                }
            }
        }
        
        return Context(
            text: text,
            appName: appName,
            bundleId: bundleId,
            windowTitle: windowTitle,
            elementFrame: frame
        )
    }
}


