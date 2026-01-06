//
//  MenuBarView.swift
//  MemoryTap
//
//  Menu bar dropdown UI
//

import SwiftUI

/// The menu that appears when clicking the menu bar icon
struct MenuBarView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var permissionsManager: PermissionsManager
    
    var onOpenMemory: () -> Void
    var onQuit: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            headerSection
            
            Divider()
                .padding(.vertical, 8)
            
            // Status
            statusSection
            
            Divider()
                .padding(.vertical, 8)
            
            // Controls
            controlsSection
            
            Divider()
                .padding(.vertical, 8)
            
            // Actions
            actionsSection
        }
        .padding(12)
        .frame(width: 280)
    }
    
    // MARK: - Sections
    
    private var headerSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 24))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text("MemoryTap")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text("v1.0")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Status indicator
            statusBadge
        }
    }
    
    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            Text(appState.statusText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.15))
        .cornerRadius(12)
    }
    
    private var statusColor: Color {
        if appState.privacyModeEnabled {
            return .orange
        } else if !appState.hasAccessibilityPermission {
            return .red
        } else if appState.captureEnabled {
            return .green
        } else {
            return .gray
        }
    }
    
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Permission status
            if !permissionsManager.accessibilityGranted {
                permissionWarning
            } else {
                // Capture stats
                HStack {
                    Label("\(appState.captureCount) memories", systemImage: "tray.full")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if !appState.currentAppName.isEmpty {
                        Text(appState.currentAppName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                // Last capture preview
                if !appState.lastCapturedPreview.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "text.quote")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(appState.lastCapturedPreview)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
                }
            }
        }
    }
    
    private var permissionWarning: some View {
        Button(action: {
            permissionsManager.requestAccessibilityPermission()
        }) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Accessibility Required")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text("Click to grant permission")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
    
    private var controlsSection: some View {
        VStack(spacing: 6) {
            // Capture toggle
            Toggle(isOn: $appState.captureEnabled) {
                Label("Capture Enabled", systemImage: "record.circle")
            }
            .toggleStyle(.switch)
            .disabled(!permissionsManager.accessibilityGranted)
            
            // Privacy mode toggle
            Toggle(isOn: $appState.privacyModeEnabled) {
                Label("Privacy Mode", systemImage: "eye.slash")
            }
            .toggleStyle(.switch)
            
            if appState.privacyModeEnabled {
                Text("Nothing is being captured")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 28)
            }
        }
    }
    
    private var actionsSection: some View {
        VStack(spacing: 4) {
            // Open Memory
            MenuButton(
                title: "Open Memory",
                icon: "tray.full",
                action: onOpenMemory
            )
            
            // Clear All
            MenuButton(
                title: "Clear All Memories",
                icon: "trash",
                isDestructive: true,
                action: {
                    appState.clearAllMemories()
                }
            )
            
            Divider()
                .padding(.vertical, 4)
            
            // Quit
            MenuButton(
                title: "Quit MemoryTap",
                icon: "power",
                action: onQuit
            )
        }
    }
}

// MARK: - Menu Button

struct MenuButton: View {
    let title: String
    let icon: String
    var isDestructive: Bool = false
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: icon)
                    .foregroundColor(isDestructive ? .red : .primary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isHovered ? Color.primary.opacity(0.1) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

