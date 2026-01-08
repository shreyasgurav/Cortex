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
        let cursorFrame: CGRect?
    }
    
    /// Best-effort: current text context + approximate bounds of focused element
    func currentContext() -> Context? {
        // Primary check: do we have a focused element?
        guard let element = accessibilityWatcher.currentAXElement() else {
            return nil
        }
        
        let text = accessibilityWatcher.getTrackedText()
        // We no longer return nil for empty text, because we want the overlay 
        // to stay visible (as a 'plus' button) even in fresh fields.
        
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
        
        // Try to get actual cursor/caret selection bounds
        var cursorFrame: CGRect? = nil
        if let element = accessibilityWatcher.currentAXElement() {
            var rangeValue: AnyObject?
            // 1. Get SelectedTextRange
            if AXUIElementCopyAttributeValue(element, "AXSelectedTextRange" as CFString, &rangeValue) == .success {
                // 2. Use that range to get BoundsForRange
                var boundsValue: AnyObject?
                if AXUIElementCopyParameterizedAttributeValue(element, "AXBoundsForRange" as CFString, rangeValue!, &boundsValue) == .success,
                   let rectValue = boundsValue {
                    let axVal = rectValue as! AXValue
                    if AXValueGetType(axVal) == .cgRect {
                        var cgRect = CGRect.zero
                        if AXValueGetValue(axVal, .cgRect, &cgRect) {
                            cursorFrame = cgRect
                        }
                    }
                }
            }
            
            // Fallback: AXSelectedTextMarkerRange (for WebKit/Electron)
            if cursorFrame == nil {
                var markerRangeValue: AnyObject?
                if AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &markerRangeValue) == .success {
                    var boundsValue: AnyObject?
                    if AXUIElementCopyParameterizedAttributeValue(element, "AXBoundsForRange" as CFString, markerRangeValue!, &boundsValue) == .success,
                       let rectValue = boundsValue {
                        let axVal = rectValue as! AXValue
                        if AXValueGetType(axVal) == .cgRect {
                            var cgRect = CGRect.zero
                            if AXValueGetValue(axVal, .cgRect, &cgRect) {
                                cursorFrame = cgRect
                            }
                        }
                    }
                }
            }
        }
        
        return Context(
            text: text,
            appName: appName,
            bundleId: bundleId,
            windowTitle: windowTitle,
            elementFrame: frame,
            cursorFrame: cursorFrame
        )
    }
}


