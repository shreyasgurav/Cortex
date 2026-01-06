//
//  MemoryWindowView.swift
//  Cortex
//
//  Main window for viewing and managing memories
//

import SwiftUI

/// Main window that displays all captured memories
struct MemoryWindowView: View {
    @ObservedObject var appState: AppState
    @State private var selectedMemory: Memory?
    @State private var searchText: String = ""
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        NavigationSplitView {
            // Sidebar - Memory list
            memoryList
                .frame(minWidth: 280)
        } detail: {
            // Detail view
            if let memory = selectedMemory {
                MemoryDetailView(memory: memory, onDelete: {
                    appState.deleteMemory(memory)
                    selectedMemory = nil
                })
            } else {
                emptyDetailView
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .navigationTitle("Cortex")
    }
    
    // MARK: - Memory List
    
    private var memoryList: some View {
        VStack(spacing: 0) {
            // Search bar
            searchBar
                .padding()
            
            Divider()
            
            // List
            if filteredMemories.isEmpty {
                emptyListView
            } else {
                List(filteredMemories, selection: $selectedMemory) { memory in
                    MemoryRowView(memory: memory, isSelected: selectedMemory?.id == memory.id)
                        .tag(memory)
                }
                .listStyle(.sidebar)
            }
            
            Divider()
            
            // Footer
            listFooter
        }
    }
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search memories...", text: $searchText)
                .textFieldStyle(.plain)
            
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
    
    private var filteredMemories: [Memory] {
        if searchText.isEmpty {
            return appState.memories
        }
        
        let lowercasedSearch = searchText.lowercased()
        return appState.memories.filter { memory in
            memory.text.lowercased().contains(lowercasedSearch) ||
            memory.appName.lowercased().contains(lowercasedSearch)
        }
    }
    
    private var listFooter: some View {
        HStack {
            Text("\(appState.memories.count) memories")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button(action: { showDeleteConfirmation = true }) {
                Label("Clear All", systemImage: "trash")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundColor(.red)
            .disabled(appState.memories.isEmpty)
        }
        .padding(12)
        .alert("Clear All Memories?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                appState.clearAllMemories()
                selectedMemory = nil
            }
        } message: {
            Text("This action cannot be undone. All \(appState.memories.count) memories will be permanently deleted.")
        }
    }
    
    // MARK: - Empty States
    
    private var emptyListView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: searchText.isEmpty ? "tray" : "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text(searchText.isEmpty ? "No memories yet" : "No matches found")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text(searchText.isEmpty ? 
                 "Start typing in any app and your text will be captured here." :
                 "Try a different search term.")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyDetailView: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.alignleft")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text("Select a memory")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Choose a memory from the list to view its full content")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Memory Row

struct MemoryRowView: View {
    let memory: Memory
    let isSelected: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // App name and time
            HStack {
                Label(memory.appName, systemImage: appIcon)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(memory.formattedDate)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            // Preview text
            Text(memory.preview)
                .font(.subheadline)
                .lineLimit(2)
                .foregroundColor(.primary)
            
            // Source badge
            HStack {
                sourceLabel
                Spacer()
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
    
    private var appIcon: String {
        // Map common apps to icons
        switch memory.appBundleId {
        case let id where id.contains("slack"):
            return "bubble.left.and.bubble.right"
        case let id where id.contains("discord"):
            return "bubble.left"
        case let id where id.contains("messages"):
            return "message"
        case let id where id.contains("mail"):
            return "envelope"
        case let id where id.contains("cursor"), let id where id.contains("vscode"):
            return "chevron.left.forwardslash.chevron.right"
        case let id where id.contains("notion"):
            return "doc.text"
        case let id where id.contains("safari"), let id where id.contains("chrome"), let id where id.contains("firefox"):
            return "globe"
        default:
            return "app"
        }
    }
    
    private var sourceLabel: some View {
        let (icon, color): (String, Color) = {
            switch memory.source {
            case .enterKey:
                return ("return", .green)
            case .focusLost:
                return ("arrow.right.circle", .blue)
            case .appSwitch:
                return ("arrow.triangle.2.circlepath", .purple)
            }
        }()
        
        return Label(memory.source.displayName, systemImage: icon)
            .font(.caption2)
            .foregroundColor(color.opacity(0.8))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.1))
            .cornerRadius(4)
    }
}

// MARK: - Memory Detail

struct MemoryDetailView: View {
    let memory: Memory
    let onDelete: () -> Void
    
    @State private var showCopied = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            detailHeader
                .padding()
            
            Divider()
            
            // Content
            ScrollView {
                Text(memory.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            
            Divider()
            
            // Actions
            detailActions
                .padding()
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
    
    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(memory.appName, systemImage: "app")
                    .font(.headline)
                
                Spacer()
                
                Text(memory.fullFormattedDate)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            if !memory.windowTitle.isEmpty {
                Text(memory.windowTitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            HStack(spacing: 12) {
                Label(memory.source.displayName, systemImage: sourceIcon)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("•")
                    .foregroundColor(.secondary)
                
                Text("\(memory.text.count) characters")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var sourceIcon: String {
        switch memory.source {
        case .enterKey: return "return"
        case .focusLost: return "arrow.right.circle"
        case .appSwitch: return "arrow.triangle.2.circlepath"
        }
    }
    
    private var detailActions: some View {
        HStack {
            // Copy button
            Button(action: copyToClipboard) {
                Label(showCopied ? "Copied!" : "Copy", systemImage: showCopied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.borderedProminent)
            .tint(showCopied ? .green : .accentColor)
            
            Spacer()
            
            // Delete button
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(.bordered)
        }
    }
    
    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(memory.text, forType: .string)
        
        withAnimation {
            showCopied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopied = false
            }
        }
    }
}

