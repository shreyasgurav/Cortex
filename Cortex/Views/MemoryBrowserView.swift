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
    @State private var navigationSelection: NavigationItem? = .memories
    @State private var searchText: String = ""
    
    enum NavigationItem {
        case memories
        case apps
    }
    
    var body: some View {
        NavigationSplitView {
            // SIDEBAR
            List(selection: $navigationSelection) {
                Label("Memories", systemImage: "clock")
                    .tag(NavigationItem.memories)
                Label("Allowed Apps", systemImage: "checkmark.shield")
                    .tag(NavigationItem.apps)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 250)
        } detail: {
            // MAIN CONTENT (Right Side)
            if let selection = navigationSelection {
                switch selection {
                case .memories:
                    MemoriesContentView(appState: appState, searchText: $searchText)
                case .apps:
                    AppsView(appState: appState)
                }
            } else {
                Text("Select an item")
                    .foregroundColor(.secondary)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .navigationTitle("Cortex")
    }
}

// MARK: - Memories Content View (Right Side)

struct MemoriesContentView: View {
    @ObservedObject var appState: AppState
    @Binding var searchText: String
    @State private var hoveredMemoryId: String?
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header / Search
            HStack {
                Text(appState.filterBeforeSaving ? "AI Memories" : "Raw Captures")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                // Search Bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search memories...", text: $searchText)
                        .textFieldStyle(.plain)
                        .frame(width: 250)
                }
                .padding(8)
                .padding(.horizontal, 4)
                .background(Color(nsColor: .quaternaryLabelColor).opacity(0.4))
                .cornerRadius(8)
                
                Spacer()
                
                // Delete All Button
                Button(action: { showDeleteConfirmation = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("Delete All")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.red.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("Delete All")
                .disabled(appState.filterBeforeSaving ? appState.extractedMemories.isEmpty : appState.memories.isEmpty)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Content
            ScrollView {
                LazyVStack(spacing: 6) {
                    if appState.filterBeforeSaving {
                        // DISPLAY EXTRACTED MEMORIES
                        if filteredExtractedMemories.isEmpty {
                            emptyState
                        } else {
                            ForEach(filteredExtractedMemories) { memory in
                                ExtractedMemoryCardView(
                                    memory: memory,
                                    isHovered: hoveredMemoryId == memory.id,
                                    onDelete: {
                                        appState.deleteExtractedMemory(memory)
                                    }
                                )
                                .onHover { isHovering in
                                    hoveredMemoryId = isHovering ? memory.id : nil
                                }
                            }
                        }
                    } else {
                        // DISPLAY RAW MEMORIES
                        if filteredMemories.isEmpty {
                            emptyState
                        } else {
                            ForEach(filteredMemories) { memory in
                                MemoryCardView(
                                    memory: memory,
                                    isHovered: hoveredMemoryId == memory.id,
                                    onDelete: {
                                        appState.deleteMemory(memory)
                                    }
                                )
                                .onHover { isHovering in
                                    hoveredMemoryId = isHovering ? memory.id : nil
                                }
                            }
                        }
                    }
                }
                .padding(12)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .alert("Clear All Memories?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                appState.clearAllMemories()
            }
        } message: {
            Text("This action cannot be undone. All memories will be permanently deleted.")
        }
    }
    
    // Helpers
    private var filteredMemories: [Memory] {
        if searchText.isEmpty { return appState.memories }
        return appState.memories.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
    }
    
    private var filteredExtractedMemories: [ExtractedMemory] {
        if searchText.isEmpty { return appState.extractedMemories }
        return appState.extractedMemories.filter { $0.content.localizedCaseInsensitiveContains(searchText) }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 100)
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.3))
            Text(searchText.isEmpty ? "No memories captured yet" : "No matches found")
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Extracted Memory Card

struct ExtractedMemoryCardView: View {
    let memory: ExtractedMemory
    let isHovered: Bool
    let onDelete: () -> Void
    @State private var isTrashHovered = false
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Memory Text Only (User requested to hide type, date, icon)
            Text(memory.content)
                .font(.system(size: 14))
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 24)
            
            // Delete Button Area
            ZStack {
                if isHovered {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                            .font(.system(size: 15))
                            .opacity(isTrashHovered ? 1.0 : 0.6)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.1)) {
                            isTrashHovered = hovering
                        }
                    }
                    .transition(.opacity)
                }
            }
            .frame(width: 24, height: 24)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isHovered ? Color.secondary.opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Memory Card

struct MemoryCardView: View {
    let memory: Memory
    let isHovered: Bool
    let onDelete: () -> Void
    @State private var isTrashHovered = false
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Memory Text
            Text(memory.text)
                .font(.system(size: 14))
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 24) // reserve space for the delete button
            
            // Delete Button Area (Fixed width to prevent text shift)
            ZStack {
                if isHovered {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                            .font(.system(size: 15))
                            .opacity(isTrashHovered ? 1.0 : 0.6)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.1)) {
                            isTrashHovered = hovering
                        }
                    }
                    .transition(.opacity)
                }
            }
            .frame(width: 24, height: 24) // Fixed size container
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isHovered ? Color.secondary.opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle()) 
    }
}


