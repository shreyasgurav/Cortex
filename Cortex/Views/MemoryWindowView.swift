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
                if appState.filterBeforeSaving {
                    // Show extracted memories
                    List(filteredExtractedMemories, selection: $selectedMemory) { memory in
                        ExtractedMemoryRowView(memory: memory)
                            .tag(Memory(
                                id: memory.id,
                                createdAt: memory.createdAt,
                                appBundleId: "",
                                appName: memory.sourceApp,
                                windowTitle: "",
                                source: .enterKey,
                                text: memory.content,
                                textHash: ""
                            ))
                    }
                    .listStyle(.sidebar)
                } else {
                    // Show raw memories
                    List(filteredRawMemories, selection: $selectedMemory) { memory in
                        MemoryRowView(memory: memory, isSelected: selectedMemory?.id == memory.id)
                            .tag(memory)
                    }
                    .listStyle(.sidebar)
                }
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
    
    private var filteredRawMemories: [Memory] {
        if searchText.isEmpty {
            return appState.memories
        }
        
        let lowercasedSearch = searchText.lowercased()
        return appState.memories.filter { memory in
            memory.text.lowercased().contains(lowercasedSearch) ||
            memory.appName.lowercased().contains(lowercasedSearch)
        }
    }
    
    private var filteredExtractedMemories: [ExtractedMemory] {
        if searchText.isEmpty {
            return appState.extractedMemories
        }
        
        let lowercasedSearch = searchText.lowercased()
        return appState.extractedMemories.filter { memory in
            memory.content.lowercased().contains(lowercasedSearch) ||
            memory.sourceApp.lowercased().contains(lowercasedSearch) ||
            memory.type.displayName.lowercased().contains(lowercasedSearch) ||
            memory.tags.contains(where: { $0.lowercased().contains(lowercasedSearch) })
        }
    }
    
    private var filteredMemories: [Any] {
        appState.filterBeforeSaving ? filteredExtractedMemories : filteredRawMemories
    }
    
    private var listFooter: some View {
        let memoryCount = appState.filterBeforeSaving ? appState.extractedMemories.count : appState.memories.count
        
        return HStack {
            Text("\(memoryCount) memories")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button(action: { showDeleteConfirmation = true }) {
                Label("Clear All", systemImage: "trash")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundColor(.red)
            .disabled(memoryCount == 0)
        }
        .padding(12)
        .alert("Clear All Memories?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                appState.clearAllMemories()
                selectedMemory = nil
            }
        } message: {
            Text("This action cannot be undone. All \(memoryCount) memories will be permanently deleted.")
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
        Text(memory.text)
            .font(.subheadline)
            .lineLimit(3)
            .foregroundColor(.primary)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
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
                Text(memory.appName)
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

// MARK: - Extracted Memory Row

struct ExtractedMemoryRowView: View {
    let memory: ExtractedMemory
    
    var body: some View {
        Text(memory.content)
            .font(.subheadline)
            .lineLimit(3)
            .foregroundColor(.primary)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
    }
}

