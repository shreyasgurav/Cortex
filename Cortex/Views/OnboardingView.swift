//
//  OnboardingView.swift
//  Cortex
//
//  Onboarding and permissions setup screen
//

import SwiftUI

/// Onboarding view that guides users through permission setup
struct OnboardingView: View {
    @ObservedObject var permissionsManager: PermissionsManager
    var onComplete: () -> Void
    
    @State private var currentStep: Int = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Content
            ScrollView {
                VStack(spacing: 32) {
                    welcomeSection
                    
                    permissionsSection
                    
                    privacySection
                }
                .padding(32)
            }
            
            Divider()
            
            // Footer
            footerView
        }
        .frame(width: 560, height: 640)
        .background(backgroundGradient)
    }
    
    // MARK: - Background
    
    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color(nsColor: .windowBackgroundColor).opacity(0.95)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 32))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Cortex")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Your personal memory assistant")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(24)
    }
    
    // MARK: - Sections
    
    private var welcomeSection: some View {
        VStack(spacing: 16) {
            Text("Welcome to Cortex")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Cortex captures text you send from any application on your Mac. Messages, AI prompts, emails, notes—everything is saved locally as your personal memory.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
    }
    
    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Required Permissions")
                .font(.headline)
            
            // Accessibility Permission
            PermissionCard(
                title: "Accessibility",
                description: "Required to detect and read text from any application. This is how Cortex can work across all your apps.",
                icon: "hand.raised.fill",
                iconColor: .purple,
                isGranted: permissionsManager.accessibilityGranted,
                isRequired: true,
                action: {
                    permissionsManager.requestAccessibilityPermission()
                }
            )
            
            // Input Monitoring Permission
            PermissionCard(
                title: "Input Monitoring",
                description: "Optional but recommended. Allows detection of Enter key presses for better capture timing.",
                icon: "keyboard.fill",
                iconColor: .blue,
                isGranted: permissionsManager.inputMonitoringGranted,
                isRequired: false,
                action: {
                    permissionsManager.requestInputMonitoringPermission()
                }
            )
        }
    }
    
    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Privacy First", systemImage: "lock.shield.fill")
                .font(.headline)
                .foregroundColor(.green)
            
            VStack(alignment: .leading, spacing: 8) {
                privacyPoint(icon: "internaldrive", text: "All data stored locally on your Mac")
                privacyPoint(icon: "icloud.slash", text: "No cloud sync, no external servers")
                privacyPoint(icon: "eye.slash", text: "Privacy mode to pause capture anytime")
                privacyPoint(icon: "key.slash", text: "Password fields are never captured")
            }
        }
        .padding(20)
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
    }
    
    private func privacyPoint(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.green)
                .frame(width: 20)
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Footer
    
    private var footerView: some View {
        HStack {
            // Status summary
            VStack(alignment: .leading, spacing: 4) {
                if permissionsManager.accessibilityGranted {
                    Label("Ready to capture", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundColor(.green)
                } else {
                    Label("Grant Accessibility to continue", systemImage: "exclamationmark.circle.fill")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                }
            }
            
            Spacer()
            
            // Continue button
            Button(action: onComplete) {
                Text(permissionsManager.accessibilityGranted ? "Get Started" : "Continue Anyway")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 24)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(24)
    }
}

// MARK: - Permission Card

struct PermissionCard: View {
    let title: String
    let description: String
    let icon: String
    let iconColor: Color
    let isGranted: Bool
    let isRequired: Bool
    let action: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 48, height: 48)
                
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(iconColor)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.headline)
                    
                    if isRequired {
                        Text("Required")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.red)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(4)
                    } else {
                        Text("Optional")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            // Status/Action
            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.green)
            } else {
                Button(action: action) {
                    Text("Grant")
                        .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
                .tint(isRequired ? iconColor : .secondary)
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isGranted ? Color.green.opacity(0.3) : Color.clear, lineWidth: 2)
        )
    }
}

// MARK: - Preview

#Preview {
    OnboardingView(
        permissionsManager: PermissionsManager(),
        onComplete: {}
    )
}

