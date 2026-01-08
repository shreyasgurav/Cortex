//
//  PermissionsManager.swift
//  Cortex
//
//  Manages Accessibility and Input Monitoring permissions
//

import Foundation
import AppKit
import ApplicationServices
import Combine

/// Manages system permissions required for Cortex to function
/// - Accessibility: Required to read text from any application
/// - Input Monitoring: Optional, enables Enter key detection for better capture timing
@MainActor
final class PermissionsManager: ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var accessibilityGranted: Bool = false
    @Published private(set) var inputMonitoringGranted: Bool = false
    
    // MARK: - Private
    
    private var checkTimer: Timer?
    
    // MARK: - Initialization
    
    init() {
        refreshPermissions()
        startPermissionMonitoring()
    }
    
    deinit {
        checkTimer?.invalidate()
    }
    
    // MARK: - Permission Checking
    
    /// Refresh current permission states
    func refreshPermissions() {
        accessibilityGranted = checkAccessibilityPermission()
        inputMonitoringGranted = checkInputMonitoringPermission()
        
        // Update app state
        AppState.shared.hasAccessibilityPermission = accessibilityGranted
        AppState.shared.hasInputMonitoringPermission = inputMonitoringGranted
    }
    
    /// Check if Accessibility permission is granted
    /// This is REQUIRED for the app to function
    private func checkAccessibilityPermission() -> Bool {
        // AXIsProcessTrusted() returns true if accessibility is enabled
        // This is the standard way to check accessibility permission on macOS
        return AXIsProcessTrusted()
    }
    
    /// Check if Input Monitoring permission is granted
    /// This is OPTIONAL but enables better capture timing via key events
    private func checkInputMonitoringPermission() -> Bool {
        // Input monitoring is harder to check directly
        // We attempt to create a global event tap as a test
        // If it fails, we assume permission is not granted
        
        // Note: This is a best-effort check. The actual event tap
        // in KeyEventListener will handle the case where permission
        // is denied at runtime.
        
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { _, _, event, _ in
                return Unmanaged.passUnretained(event)
            },
            userInfo: nil
        ) else {
            return false
        }
        
        // Successfully created tap, clean up and return true
        CFMachPortInvalidate(tap)
        return true
    }
    
    // MARK: - Permission Requests
    
    /// Request Accessibility permission
    /// Opens System Settings to the Accessibility pane
    func requestAccessibilityPermission() {
        // First, trigger the system prompt by calling AXIsProcessTrustedWithOptions
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        
        // Also open System Settings for clarity
        openAccessibilitySettings()
    }
    
    /// Request Input Monitoring permission
    /// Opens System Settings to the Input Monitoring pane
    func requestInputMonitoringPermission() {
        openInputMonitoringSettings()
    }
    
    // MARK: - Open System Settings
    
    /// Open Accessibility settings in System Settings
    func openAccessibilitySettings() {
        // macOS Ventura+ uses different URL scheme
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Open Input Monitoring settings in System Settings
    func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - Continuous Monitoring
    
    /// Start monitoring for permission changes
    /// The system doesn't notify us when permissions change, so we poll
    private func startPermissionMonitoring() {
        checkTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                self?.refreshPermissions()
            }
        }
    }
    
    /// Stop monitoring (called when app terminates)
    func stopMonitoring() {
        checkTimer?.invalidate()
        checkTimer = nil
    }
}

// MARK: - Permission Status

extension PermissionsManager {
    
    /// Overall permission status
    var permissionStatus: PermissionStatus {
        if !accessibilityGranted {
            return .accessibilityRequired
        } else if !inputMonitoringGranted {
            return .inputMonitoringOptional
        } else {
            return .allGranted
        }
    }
    
    enum PermissionStatus {
        case accessibilityRequired
        case inputMonitoringOptional
        case allGranted
        
        var title: String {
            switch self {
            case .accessibilityRequired:
                return "Accessibility Access Required"
            case .inputMonitoringOptional:
                return "Input Monitoring (Optional)"
            case .allGranted:
                return "All Permissions Granted"
            }
        }
        
        var description: String {
            switch self {
            case .accessibilityRequired:
                return "Cortex needs Accessibility access to detect and read text from any application. This is required for the app to function."
            case .inputMonitoringOptional:
                return "Input Monitoring allows Cortex to detect when you press Enter to send messages. This improves capture accuracy but is optional."
            case .allGranted:
                return "Cortex has all the permissions it needs to capture your memories."
            }
        }
    }
}

