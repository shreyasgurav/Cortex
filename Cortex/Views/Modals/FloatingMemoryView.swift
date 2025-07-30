import SwiftUI
import FirebaseFirestore
import FirebaseCore

class FloatingMemoryViewModel: ObservableObject {
    @Published var memories: [Memory] = []
    @Published var filteredMemories: [Memory] = []
    @Published var isLoading = false
    @Published var errorMessage = ""
    @Published var currentContext = ""
    
    private var db: Firestore?
    @Published var allMemories: [Memory] = []
    private var debounceTimer: Timer?
    
    func loadMemories() {
        print("🔍 [FloatingMemoryViewModel] loadMemories() called")
        
        // Ensure Firebase is configured
        guard FirebaseApp.app() != nil else {
            print("❌ [FloatingMemoryViewModel] Firebase not configured")
            DispatchQueue.main.async {
                self.isLoading = false
                self.errorMessage = "Firebase not configured. Please restart the app."
            }
            return
        }
        print("✅ [FloatingMemoryViewModel] Firebase is configured")
        
        // Initialize Firestore if needed
        if db == nil {
            db = Firestore.firestore()
            print("🔍 [FloatingMemoryViewModel] Firestore initialized")
        }
        
        guard let db = db else {
            print("❌ [FloatingMemoryViewModel] Firestore not initialized")
            DispatchQueue.main.async {
                self.isLoading = false
                self.errorMessage = "Firestore not initialized"
            }
            return
        }
        
        print("🔍 [FloatingMemoryViewModel] Starting to load memories from Firestore...")
        isLoading = true
        errorMessage = ""
        
        db.collection("memory")
            .order(by: "timestamp", descending: true)
            .limit(to: 100) // Increased for better semantic search coverage
            .getDocuments { [weak self] querySnapshot, error in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    
                    self.isLoading = false
                    
                    if let error = error {
                        print("❌ [FloatingMemoryViewModel] Firestore error: \(error.localizedDescription)")
                        self.errorMessage = "Error loading memories: \(error.localizedDescription)"
                        return
                    }
                    
                    guard let documents = querySnapshot?.documents else {
                        print("❌ [FloatingMemoryViewModel] No documents in query result")
                        self.errorMessage = "No memories found"
                        return
                    }
                    
                    print("🔍 [FloatingMemoryViewModel] Found \(documents.count) documents in Firestore")
                    
                    let loadedMemories = documents.compactMap { document in
                        do {
                            let data = document.data()
                            let text = data["text"] as? String ?? ""
                            let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() ?? Date()
                            let tags = data["tags"] as? [String] ?? []
                            
                            let memory = Memory(
                                id: document.documentID,
                                text: text,
                                timestamp: timestamp,
                                tags: tags
                            )
                            print("✅ [FloatingMemoryViewModel] Loaded memory: '\(text.prefix(50))...'")
                            return memory
                        } catch {
                            print("❌ [FloatingMemoryViewModel] Error parsing document: \(error)")
                            return nil
                        }
                    }
                    
                    print("🔍 [FloatingMemoryViewModel] Successfully loaded \(loadedMemories.count) memories")
                    
                    // If no memories exist, create some test memories for immediate functionality
                    if loadedMemories.isEmpty {
                        print("🔍 [FloatingMemoryViewModel] No memories found, creating test memories...")
                        self.createTestMemories()
                        return
                    }
                    
                    self.allMemories = loadedMemories
                    self.memories = loadedMemories
                    self.filterMemoriesByContext()
                    
                    print("🔍 [FloatingMemoryViewModel] Filtered memories: \(self.filteredMemories.count)")
                    if !self.filteredMemories.isEmpty {
                        print("  First filtered memory: '\(self.filteredMemories[0].text.prefix(30))...'")
                    }
                }
            }
    }
    
    func createTestMemories() {
        print("🔍 [FloatingMemoryViewModel] Creating test memories for immediate functionality")
        
        let testMemories = [
            Memory(text: "Remember to check email every morning", tags: ["productivity", "email"]),
            Memory(text: "Swift programming tips and tricks", tags: ["programming", "swift"]),
            Memory(text: "Meeting notes from client discussion about app features", tags: ["meetings", "clients"]),
            Memory(text: "Grocery list: milk, bread, eggs, cheese", tags: ["shopping", "groceries"]),
            Memory(text: "Important: Submit project proposal by Friday", tags: ["deadlines", "work"]),
            Memory(text: "Call mom about weekend plans", tags: ["family", "personal"]),
            Memory(text: "Debug the authentication issue in the login flow", tags: ["programming", "bugs"]),
            Memory(text: "Book doctor appointment for next week", tags: ["health", "appointments"])
        ]
        
        // Add test memories to both local storage and show them immediately
        self.allMemories = testMemories
        self.memories = testMemories
        self.filteredMemories = Array(testMemories.prefix(5)) // Show first 5
        
        print("✅ [FloatingMemoryViewModel] Created \(testMemories.count) test memories")
        print("✅ [FloatingMemoryViewModel] Showing \(self.filteredMemories.count) filtered memories")
        
        // Optionally add to Firestore for persistence
        guard let db = db else { return }
        
        for memory in testMemories {
            let data: [String: Any] = [
                "text": memory.text,
                "timestamp": Timestamp(date: memory.timestamp),
                "tags": memory.tags
            ]
            
            db.collection("memory").addDocument(data: data) { error in
                if let error = error {
                    print("❌ [FloatingMemoryViewModel] Error adding test memory: \(error)")
                } else {
                    print("✅ [FloatingMemoryViewModel] Test memory added to Firestore")
                }
            }
        }
    }
    
    func updateContext(_ context: String) {
        currentContext = context
        print("🔍 [FloatingMemoryViewModel] Context updated to: '\(context)'")
        
        // Debounce the filtering to prevent excessive computation
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.filterMemoriesByContext()
            }
        }
    }
    
    private func filterMemoriesByContext() {
        if currentContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // If no context, show recent memories
            filteredMemories = Array(allMemories.prefix(5))
            print("🔍 [FloatingMemoryView] No context, showing \(filteredMemories.count) recent memories")
            return
        }
        
        // Enhanced semantic filtering with better NLP
        let contextWords = preprocessText(currentContext)
        
        if contextWords.isEmpty {
            filteredMemories = Array(allMemories.prefix(5))
            return
        }
        
        print("🔍 [FloatingMemoryView] Context words: \(contextWords)")
        
        // Score memories based on enhanced relevance
        let scoredMemories = allMemories.map { memory -> (memory: Memory, score: Double) in
            let memoryWords = preprocessText(memory.text)
            var score = 0.0
            
            // 1. Exact word matches (highest priority)
            for contextWord in contextWords {
                if memoryWords.contains(contextWord) {
                    score += 5.0
                    print("  ✅ Exact match: '\(contextWord)' in '\(memory.text.prefix(50))...'")
                }
            }
            
            // 2. Substring matches
            for contextWord in contextWords where contextWord.count > 3 {
                for memoryWord in memoryWords {
                    if memoryWord.contains(contextWord) || contextWord.contains(memoryWord) {
                        let similarity = Double(min(contextWord.count, memoryWord.count)) / Double(max(contextWord.count, memoryWord.count))
                        score += 2.0 * similarity
                    }
                }
            }
            
            // 3. Word similarity (Levenshtein-like)
            for contextWord in contextWords where contextWord.count > 2 {
                for memoryWord in memoryWords where memoryWord.count > 2 {
                    let similarity = calculateWordSimilarity(contextWord, memoryWord)
                    if similarity > 0.7 {
                        score += 3.0 * similarity
                    }
                }
            }
            
            // 4. Tag matches (very important)
            for tag in memory.tags {
                let tagWords = preprocessText(tag)
                for contextWord in contextWords {
                    if tagWords.contains(contextWord) {
                        score += 4.0
                        print("  🏷️ Tag match: '\(contextWord)' in tag '\(tag)'")
                    }
                }
            }
            
            // 5. Phrase similarity
            let contextPhrase = currentContext.lowercased()
            let memoryPhrase = memory.text.lowercased()
            if memoryPhrase.contains(contextPhrase) || contextPhrase.contains(memoryPhrase) {
                score += 3.0
            }
            
            // 6. Recency boost
            let daysSinceCreation = Date().timeIntervalSince(memory.timestamp) / (24 * 60 * 60)
            if daysSinceCreation < 1 {
                score += 1.0 // Recent memories get higher priority
            } else if daysSinceCreation < 7 {
                score += 0.5
            }
            
            // 7. Length penalty for very short memories
            if memory.text.count < 10 {
                score *= 0.5
            }
            
            return (memory, score)
        }
        
        // Filter and sort by relevance score
        filteredMemories = scoredMemories
            .filter { $0.score > 0.5 } // Higher threshold for better quality
            .sorted { $0.score > $1.score }
            .map { $0.memory }
        
        // Limit to top 8 most relevant for better UI
        if filteredMemories.count > 8 {
            filteredMemories = Array(filteredMemories.prefix(8))
        }
        
        // Show some results even if no perfect matches
        if filteredMemories.isEmpty && !allMemories.isEmpty {
            filteredMemories = Array(allMemories.prefix(3))
            print("🔍 [FloatingMemoryView] No good matches, showing 3 recent memories as fallback")
        }
        
        print("🔍 [FloatingMemoryView] Context: '\(currentContext)' -> \(filteredMemories.count) relevant memories")
        if !filteredMemories.isEmpty {
            print("  Top match: '\(filteredMemories[0].text.prefix(50))...'")
        }
    }
    
    private func preprocessText(_ text: String) -> [String] {
        return text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && $0.count > 1 }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    
    private func calculateWordSimilarity(_ word1: String, _ word2: String) -> Double {
        let len1 = word1.count
        let len2 = word2.count
        
        if len1 == 0 || len2 == 0 { return 0.0 }
        if word1 == word2 { return 1.0 }
        
        // Simple similarity based on common characters
        let chars1 = Set(word1)
        let chars2 = Set(word2)
        let intersection = chars1.intersection(chars2)
        let union = chars1.union(chars2)
        
        return Double(intersection.count) / Double(union.count)
    }
    
    func addMemoryToInput(_ memory: Memory) {
        // Send notification to add memory to current input
        NotificationCenter.default.post(
            name: NSNotification.Name("AddMemoryToInput"),
            object: memory.text
        )
    }
    
    deinit {
        debounceTimer?.invalidate()
    }
}

struct FloatingMemoryView: View {
    @StateObject private var viewModel = FloatingMemoryViewModel()
    @State private var isExpanded = false
    @ObservedObject var contextManager: FloatingModalManager
    
    init(contextManager: FloatingModalManager) {
        self.contextManager = contextManager
    }
    
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
                    // Memories are now auto-loaded on appear, no need to load here
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
                ZStack {
                    // Solid background for readability
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.85))
                    
                    // Subtle gradient overlay
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.blue.opacity(0.1),
                                    Color.purple.opacity(0.05),
                                    Color.clear
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    // Border
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                }
            )
            
            // Expandable content
            if isExpanded {
                VStack(spacing: 0) {
                    if viewModel.isLoading {
                        loadingView
                    } else if !viewModel.errorMessage.isEmpty {
                        errorView
                    } else if viewModel.filteredMemories.isEmpty {
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
        .background(
            ZStack {
                // Main background
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.88))
                
                // Subtle glassmorphism effect
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.05),
                                Color.blue.opacity(0.02),
                                Color.clear
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // Border with glow
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.blue.opacity(0.6),
                                Color.purple.opacity(0.3),
                                Color.blue.opacity(0.2)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            }
        )
        .shadow(color: Color.blue.opacity(0.2), radius: 10, x: 0, y: 5)
        .shadow(color: Color.black.opacity(0.3), radius: 15, x: 0, y: 8)
        .onAppear {
            print("🔍 [FloatingMemoryView] View appeared, loading memories and context")
            print("🔍 [FloatingMemoryView] Current context: '\(contextManager.currentContext)'")
            viewModel.loadMemories()
            viewModel.updateContext(contextManager.currentContext)
            
            // Force expand for immediate visibility during testing
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if !isExpanded {
                    print("🔍 [FloatingMemoryView] Auto-expanding for testing")
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isExpanded = true
                    }
                }
            }
        }
        .onChange(of: contextManager.currentContext) { oldContext, newContext in
            print("🔍 [FloatingMemoryView] Context changed: '\(oldContext)' -> '\(newContext)'")
            viewModel.updateContext(newContext)
            
            // Auto-expand when user starts typing
            if !newContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isExpanded {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isExpanded = true
                }
                print("✅ [FloatingMemoryView] Auto-expanded due to typing activity")
            }
        }
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
        VStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .foregroundColor(.blue)
                .font(.system(size: 24))
            
            Text("No Relevant Memories")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
            
            Text("Try different keywords or add memories first")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            if viewModel.allMemories.isEmpty {
                Button("Create Test Memories") {
                    viewModel.createTestMemories()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.2))
                .foregroundColor(.blue)
                .cornerRadius(8)
                .font(.system(size: 12, weight: .medium))
            }
        }
        .padding(.vertical, 20)
    }
    
    private var memoriesList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.filteredMemories) { memory in
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
    let memoryManager = MemoryManager()
    let contextManager = FloatingModalManager(memoryManager: memoryManager)
    return FloatingMemoryView(contextManager: contextManager)
} 