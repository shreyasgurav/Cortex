//
//  MenuBarView.swift
//  Cortex
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
            // Title
            Text("Cortex")
                .font(.headline)
                .fontWeight(.semibold)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            
            Divider()
            
            // Capture toggle
            Toggle(isOn: $appState.captureEnabled) {
                Text("Capture Enabled")
            }
            .toggleStyle(.switch)
            .disabled(!permissionsManager.accessibilityGranted)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            
            Divider()
            
            // Open Memory
            MenuButton(
                title: "Open Memory",
                icon: "tray.full",
                action: onOpenMemory
            )
            
            Divider()
            
            // Quit
            MenuButton(
                title: "Quit Cortex",
                icon: "power",
                action: onQuit
            )
        }
        .padding(.vertical, 8)
        .frame(width: 220)
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

