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
    @StateObject private var memoryFetcher = MemoryFetcher()
    @State private var isVisible = false
    @State private var searchText = ""
    @State private var showAddedFeedback = false
    @State private var addedMemoryText = ""
    @State private var isHovering = false
    
    var body: some View {
        mainContent
    }
    
    private var mainContent: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            // Content
            if isVisible {
                contentView
            }
        }
        .frame(minWidth: 340, maxWidth: 480, minHeight: 80, maxHeight: 680)
        .background(
            ZStack {
                // Glassmorphism background
                BlurView(style: .hudWindow)
                
                // Subtle gradient overlay
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0.1),
                        Color.white.opacity(0.05),
                        Color.clear
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .cornerRadius(20)
        .overlay(
            // Border with glow effect
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.3),
                            Color.white.opacity(0.1),
                            Color.clear
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 10)
        .overlay(
            // Success feedback overlay
            Group {
                if showAddedFeedback {
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.green.opacity(0.2))
                                .frame(width: 60, height: 60)
                            
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 32, weight: .bold))
                        }
                        
                        Text("Added to active text field!")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.green)
                    }
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.green.opacity(0.15))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.green.opacity(0.3), lineWidth: 1)
                            )
                    )
                    .shadow(color: .green.opacity(0.2), radius: 12, x: 0, y: 4)
                    .transition(.scale.combined(with: .opacity))
                }
            }
        )
        .padding(12)
        .onAppear {
            print("🔍 FloatingModalView appeared")
        }
        .onDisappear {
            print("🔍 FloatingModalView disappeared")
            memoryFetcher.cleanup()
        }
    }
    
    private var headerView: some View {
        HStack(spacing: 12) {
            // Animated logo
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        gradient: Gradient(colors: [Color.blue, Color.purple]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 32, height: 32)
                    .shadow(color: .blue.opacity(0.3), radius: 6, x: 0, y: 3)
                
                Image("Image")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                    .foregroundColor(.white)
                    .fontWeight(.semibold)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Cortex Memories")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(LinearGradient(
                        gradient: Gradient(colors: [Color.white, Color.blue.opacity(0.8)]),
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                
                Text("\(memoryFetcher.memories.count) memories")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Control buttons
            HStack(spacing: 8) {
                Button(action: { memoryFetcher.fetchMemories() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isVisible.toggle()
                        if isVisible {
                            memoryFetcher.fetchMemories()
                        }
                    }
                }) {
                    Image(systemName: isVisible ? "chevron.down" : "chevron.up")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: { NSApplication.shared.terminate(nil) }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.red)
                        .frame(width: 24, height: 24)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    private var contentView: some View {
        VStack(spacing: 0) {
            // Search bar
            searchBar
            
            // Memories list
            memoriesList
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
    
    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 12, weight: .medium))
            
            TextField("Search memories...", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 13, weight: .medium))
                .padding(.vertical, 8)
            
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
    
    private var memoriesList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
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
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .frame(minHeight: 240, maxHeight: 480)
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
    
    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
                .progressViewStyle(CircularProgressViewStyle(tint: .blue))
            
            Text("Loading memories...")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 40)
    }
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 20))
            
            Text("Error")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.orange)
            
            Text(message)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
    }
    
    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.bubble")
                .foregroundColor(.secondary)
                .font(.system(size: 20))
            
            Text("No memories found")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)
            
            Text("Start typing and press Enter to save memories")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
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
        print("🔍 [FloatingModalView] Adding memory to input: \(memory.text)")
        
        // Hide the floating modal first
        NotificationCenter.default.post(name: NSNotification.Name("HideFloatingModal"), object: nil)
        print("🔍 [FloatingModalView] Sent HideFloatingModal notification")
        
        // Send notification to add memory to current input
        NotificationCenter.default.post(
            name: NSNotification.Name("AddMemoryToInput"),
            object: memory.text
        )
        print("🔍 [FloatingModalView] Sent AddMemoryToInput notification with text: \(memory.text)")
        
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
        
        print("✅ [FloatingModalView] Memory sent to active text field")
    }
}

struct MemoryRowView: View {
    let memory: MemoryItem
    let onTap: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                Text(memory.text)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "app.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.blue)
                        
                        Text(memory.appName)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Text(memory.timestamp, style: .relative)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovering ? Color.blue.opacity(0.1) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isHovering ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
                    )
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovering = hovering
                }
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .contentShape(Rectangle())
        
        Divider()
            .padding(.horizontal, 16)
            .opacity(0.3)
    }
}

#Preview {
    FloatingModalView()
} 