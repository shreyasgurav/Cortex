import SwiftUI
import FirebaseFirestore
import FirebaseCore

class FloatingMemoryViewModel: ObservableObject {
    @Published var memories: [Memory] = []
    @Published var isLoading = false
    @Published var errorMessage = ""
    
    private var db: Firestore?
    
    func loadMemories() {
        // Ensure Firebase is configured
        guard FirebaseApp.app() != nil else {
            DispatchQueue.main.async {
                self.isLoading = false
                self.errorMessage = "Firebase not configured. Please restart the app."
            }
            return
        }
        
        // Initialize Firestore if needed
        if db == nil {
            db = Firestore.firestore()
        }
        
        guard let db = db else {
            DispatchQueue.main.async {
                self.isLoading = false
                self.errorMessage = "Firestore not initialized"
            }
            return
        }
        
        isLoading = true
        errorMessage = ""
        
        db.collection("memories")
            .order(by: "timestamp", descending: true)
            .limit(to: 20)
            .getDocuments { [weak self] querySnapshot, error in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    
                    self.isLoading = false
                    
                    if let error = error {
                        self.errorMessage = "Error loading memories: \(error.localizedDescription)"
                        return
                    }
                    
                    guard let documents = querySnapshot?.documents else {
                        self.errorMessage = "No memories found"
                        return
                    }
                    
                    self.memories = documents.compactMap { document in
                        do {
                            let data = document.data()
                            let text = data["text"] as? String ?? ""
                            let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() ?? Date()
                            let tags = data["tags"] as? [String] ?? []
                            
                            return Memory(
                                id: document.documentID,
                                text: text,
                                timestamp: timestamp,
                                tags: tags
                            )
                        } catch {
                            print("❌ [FloatingMemoryView] Error parsing document: \(error)")
                            return nil
                        }
                    }
                }
            }
    }
    
    func addMemoryToInput(_ memory: Memory) {
        // Send notification to add memory to current input
        NotificationCenter.default.post(
            name: NSNotification.Name("AddMemoryToInput"),
            object: memory.text
        )
    }
}

struct FloatingMemoryView: View {
    @StateObject private var viewModel = FloatingMemoryViewModel()
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header - always visible and draggable
            HStack {
                Image("Image")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                    .foregroundColor(.blue)
                
                Text("Memories")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Toggle button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isExpanded.toggle()
                    }
                    if isExpanded {
                        viewModel.loadMemories()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
            
            // Expandable content
            if isExpanded {
                VStack(spacing: 0) {
                    if viewModel.isLoading {
                        loadingView
                    } else if !viewModel.errorMessage.isEmpty {
                        errorView
                    } else if viewModel.memories.isEmpty {
                        emptyView
                    } else {
                        memoriesList
                    }
                }
                .padding(.top, 8)
            }
        }
        .frame(width: 300)
        .padding(12)
    }
    
    private var loadingView: some View {
        HStack {
            ProgressView()
                .scaleEffect(0.8)
                .progressViewStyle(CircularProgressViewStyle(tint: .blue))
            
            Text("Loading memories...")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 20)
    }
    
    private var errorView: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 16))
            
            Text("Error")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.orange)
            
            Text(viewModel.errorMessage)
                .font(.system(size: 10, weight: .medium))
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
            
            Text("No memories yet")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            
            Text("Start typing to save memories")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 20)
    }
    
    private var memoriesList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.memories) { memory in
                    MemoryRowView(memory: memory) {
                        viewModel.addMemoryToInput(memory)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                }
            }
            .padding(.vertical, 8)
        }
        .frame(maxHeight: 300)
    }
}

struct MemoryRowView: View {
    let memory: Memory
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
                    // Tags
                    if !memory.tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(memory.tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.system(size: 8, weight: .medium))
                                        .foregroundColor(.blue)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(Color.blue.opacity(0.2))
                                        )
                                }
                            }
                        }
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
    FloatingMemoryView()
} 