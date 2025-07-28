import SwiftUI
import AppKit

// MARK: - BlurView for macOS (wraps NSVisualEffectView)
struct BlurView: NSViewRepresentable {
    var style: NSVisualEffectView.Material = .contentBackground
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = style
        view.blendingMode = .withinWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = style
    }
}


struct FloatingModalView: View {
    private var memoryFetcher = MemoryFetcher()
    @State private var isVisible = false
    @State private var searchText = ""
    @State private var showAddedFeedback = false
    @State private var addedMemoryText = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            // Content
            if isVisible {
                contentView
            }
        }
        .frame(minWidth: 320, maxWidth: 440, minHeight: 70, maxHeight: 650)
        .background(BlurView(style: .contentBackground))
        .cornerRadius(18)
        .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 8)
        .overlay(
            // Success feedback overlay
            Group {
                if showAddedFeedback {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 32, weight: .bold))
                        Text("Added to active text field!")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.green)
                    }
                    .padding(20)
                    .background(Color.green.opacity(0.18))
                    .cornerRadius(12)
                    .shadow(color: .green.opacity(0.12), radius: 12, x: 0, y: 4)
                    .transition(.opacity)
                }
            }
        )
        .padding(8)
        .onAppear {
            print("🔍 FloatingModalView appeared")
            memoryFetcher.startListening()
        }
        .onDisappear {
            print("🔍 FloatingModalView disappeared")
            memoryFetcher.cleanup()
        }
    }
    
    private var headerView: some View {
        HStack(spacing: 10) {
            Image(systemName: "brain.head.profile")
                .resizable()
                .frame(width: 22, height: 22)
                .foregroundColor(.blue)
                .shadow(color: .blue.opacity(0.16), radius: 4, x: 0, y: 2)
            Text("Cortex Memories")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            Spacer()
            Button(action: { memoryFetcher.refreshMemories() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isVisible.toggle()
                    if isVisible {
                        memoryFetcher.startListening()
                    } else {
                        memoryFetcher.stopListening()
                    }
                }
            }) {
                Image(systemName: isVisible ? "chevron.down" : "chevron.up")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
            Button(action: { NSApplication.shared.terminate(nil) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(BlurView(style: .sidebar))
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.03), radius: 4, x: 0, y: 2)
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
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 14, weight: .medium))
            TextField("Search memories...", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 13))
                .padding(.vertical, 6)
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(BlurView(style: .menu))
        .cornerRadius(8)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
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
                            // Hide the floating modal before inserting
                            NotificationCenter.default.post(name: NSNotification.Name("HideFloatingModal"), object: nil)
                            // Give time for focus to return to previous app
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                                addMemoryToInput(memory)
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.primary.opacity(0.03))
                                .opacity(0)
                                .onHover { hovering in
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        if hovering {
                                            NSCursor.pointingHand.push()
                                        } else {
                                            NSCursor.pop()
                                        }
                                    }
                                }
                        )
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .frame(minHeight: 220, maxHeight: 440)
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
        
        // Send notification to add memory to current input
        NotificationCenter.default.post(
            name: NSNotification.Name("AddMemoryToInput"),
            object: memory.text
        )
        
        // Show visual feedback
        withAnimation(.easeInOut(duration: 0.3)) {
            showAddedFeedback = true
            addedMemoryText = memory.text
        }
        
        // Hide feedback after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.3)) {
                showAddedFeedback = false
            }
        }
        
        print("✅ Memory sent to active text field")
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