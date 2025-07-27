import SwiftUI
import AppKit

struct FloatingModalView: View {
    @StateObject private var memoryFetcher = MemoryFetcher()
    @State private var isVisible = false
    @State private var searchText = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            // Content
            if isVisible {
                contentView
            }
        }
        .frame(minWidth: 280, maxWidth: 400, minHeight: 50, maxHeight: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
        .onAppear {
            print("🔍 FloatingModalView appeared")
            memoryFetcher.startListening()
        }
        .onDisappear {
            print("🔍 FloatingModalView disappeared")
            memoryFetcher.stopListening()
        }
    }
    
    private var headerView: some View {
        HStack {
            Image(systemName: "brain.head.profile")
                .foregroundColor(.blue)
                .font(.system(size: 16, weight: .medium))
            
            Text("Cortex Memories")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
            
            Spacer()
            
            Button(action: {
                print("🔍 Manual refresh triggered")
                memoryFetcher.refreshMemories()
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
            
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isVisible.toggle()
                    if isVisible {
                        print("🔍 Expanding modal, starting to listen for memories")
                        memoryFetcher.startListening()
                    } else {
                        print("🔍 Collapsing modal, stopping listener")
                        memoryFetcher.stopListening()
                    }
                }
            }) {
                Image(systemName: isVisible ? "chevron.down" : "chevron.up")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
            
            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private var contentView: some View {
        VStack(spacing: 0) {
            // Search bar
            searchBar
            
            // Memories list
            memoriesList
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 12))
            
            TextField("Search memories...", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 12))
            
            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 10))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(6)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    private var memoriesList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Debug info
                debugInfo
                
                if memoryFetcher.isLoading {
                    loadingView
                } else if let errorMessage = memoryFetcher.errorMessage {
                    errorView(message: errorMessage)
                } else if filteredMemories.isEmpty {
                    emptyView
                } else {
                    ForEach(filteredMemories) { memory in
                        MemoryRowView(memory: memory) {
                            addMemoryToInput(memory)
                        }
                    }
                }
            }
        }
        .frame(minHeight: 200, maxHeight: 400)
        .onAppear {
            print("🔍 Memories list appeared, memories count: \(memoryFetcher.memories.count)")
        }
        .onChange(of: memoryFetcher.memories) { _, newMemories in
            print("🔍 Memories changed: \(newMemories.count) memories")
        }
        .onChange(of: searchText) { _, newSearchText in
            print("🔍 Search text changed: '\(newSearchText)'")
        }
    }
    
    private var debugInfo: some View {
        VStack(spacing: 4) {
            Text("Debug: \(memoryFetcher.memories.count) memories, \(filteredMemories.count) filtered")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            Text("Search: '\(searchText)'")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            Text("Loading: \(memoryFetcher.isLoading ? "Yes" : "No")")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            if let error = memoryFetcher.errorMessage {
                Text("Error: \(error)")
                    .font(.system(size: 9))
                    .foregroundColor(.red)
            }
        }
        .padding(.vertical, 4)
        .background(Color.yellow.opacity(0.1))
    }
    
    private var loadingView: some View {
        HStack {
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading memories...")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 20)
    }
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 16))
            Text(message)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 20)
    }
    
    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.bubble")
                .foregroundColor(.secondary)
                .font(.system(size: 16))
            Text("No memories found")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 20)
    }
    
    private var filteredMemories: [MemoryItem] {
        let memories = memoryFetcher.memories
        print("🔍 Filtering \(memories.count) memories, search text: '\(searchText)'")
        
        if searchText.isEmpty {
            return memories
        } else {
            let filtered = memories.filter { memory in
                memory.text.localizedCaseInsensitiveContains(searchText) ||
                memory.appName.localizedCaseInsensitiveContains(searchText)
            }
            print("🔍 Filtered to \(filtered.count) memories")
            return filtered
        }
    }
    
    private func addMemoryToInput(_ memory: MemoryItem) {
        print("🔍 Adding memory to input: \(memory.text)")
        NotificationCenter.default.post(
            name: NSNotification.Name("AddMemoryToInput"),
            object: memory.text
        )
    }
}

struct MemoryRowView: View {
    let memory: MemoryItem
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                Text(memory.text)
                    .font(.system(size: 11))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                HStack {
                    Text(memory.appName)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(memory.timestamp, style: .relative)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.clear)
        }
        .buttonStyle(PlainButtonStyle())
        .contentShape(Rectangle())
        .background(Color.clear)
        
        Divider()
            .padding(.horizontal, 16)
    }
}

#Preview {
    FloatingModalView()
} 