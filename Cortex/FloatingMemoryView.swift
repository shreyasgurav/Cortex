import SwiftUI
import FirebaseFirestore
import FirebaseCore

struct Memory: Identifiable {
    let id: String
    let text: String
    let timestamp: Date
    let appName: String
    
    init(document: QueryDocumentSnapshot) {
        self.id = document.documentID
        self.text = document.data()["text"] as? String ?? ""
        self.appName = document.data()["appName"] as? String ?? "Unknown"
        
        if let timestamp = document.data()["timestamp"] as? Timestamp {
            self.timestamp = timestamp.dateValue()
        } else {
            self.timestamp = Date()
        }
    }
}

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
        
        db.collection("memory")
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
                    
                    self.memories = documents.map { Memory(document: $0) }
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
                Image(systemName: "brain.head.profile")
                    .foregroundColor(.blue)
                    .font(.system(size: 16, weight: .medium))
                
                Text("Cortex Memories")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isExpanded.toggle()
                        if isExpanded {
                            viewModel.loadMemories()
                        }
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            
            // Expandable content
            if isExpanded {
                VStack(spacing: 0) {
                    // Memories list
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            if viewModel.isLoading {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Loading memories...")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 20)
                            } else if !viewModel.errorMessage.isEmpty {
                                VStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                        .font(.system(size: 16))
                                    Text(viewModel.errorMessage)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .padding(.vertical, 20)
                            } else if viewModel.memories.isEmpty {
                                VStack(spacing: 8) {
                                    Image(systemName: "text.bubble")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 16))
                                    Text("No memories yet")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 20)
                            } else {
                                ForEach(viewModel.memories) { memory in
                                    MemoryRow(memory: memory) {
                                        viewModel.addMemoryToInput(memory)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 250)
                }
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
            }
        }
        .frame(width: 300)
        .background(Color.clear)
    }
}

struct MemoryRow: View {
    let memory: Memory
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
        
        if memory.id != "last" {
            Divider()
                .padding(.horizontal, 16)
        }
    }
}

#Preview {
    FloatingMemoryView()
} 