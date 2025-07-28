import Foundation
import FirebaseFirestore
import FirebaseCore

struct Memory: Identifiable, Codable, Equatable {
    let id: String
    var text: String
    var timestamp: Date
    var tags: [String]
    
    init(id: String = UUID().uuidString, text: String, timestamp: Date = Date(), tags: [String] = []) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.tags = tags
    }
}

class MemoryManager: ObservableObject {
    @Published var memories: [Memory] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let db = Firestore.firestore()
    private let collectionName = "memory"
    
    init() {
        print("🔍 [MemoryManager] Initialized")
    }
    
    // MARK: - Load Memories
    func loadMemories() {
        guard FirebaseApp.app() != nil else {
            print("❌ [MemoryManager] Firebase not configured")
            errorMessage = "Firebase not configured"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        db.collection(collectionName)
            .order(by: "timestamp", descending: true)
            .getDocuments { [weak self] snapshot, error in
                DispatchQueue.main.async {
                    self?.isLoading = false
                    
                    if let error = error {
                        print("❌ [MemoryManager] Error loading memories: \(error.localizedDescription)")
                        self?.errorMessage = "Failed to load memories: \(error.localizedDescription)"
                        return
                    }
                    
                    guard let documents = snapshot?.documents else {
                        print("❌ [MemoryManager] No documents found")
                        return
                    }
                    
                    self?.memories = documents.compactMap { document in
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
                    }
                    
                    print("✅ [MemoryManager] Loaded \(self?.memories.count ?? 0) memories")
                }
            }
    }
    
    // MARK: - Add Memory
    func addMemory(_ text: String, tags: [String] = []) {
        guard FirebaseApp.app() != nil else {
            print("❌ [MemoryManager] Firebase not configured")
            errorMessage = "Firebase not configured"
            return
        }
        
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("❌ [MemoryManager] Cannot add empty memory")
            errorMessage = "Cannot add empty memory"
            return
        }
        
        let memory = Memory(text: text.trimmingCharacters(in: .whitespacesAndNewlines), tags: tags)
        
        let data: [String: Any] = [
            "text": memory.text,
            "timestamp": Timestamp(date: memory.timestamp),
            "tags": memory.tags
        ]
        
        db.collection(collectionName).addDocument(data: data) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ [MemoryManager] Error adding memory: \(error.localizedDescription)")
                    self?.errorMessage = "Failed to add memory: \(error.localizedDescription)"
                } else {
                    print("✅ [MemoryManager] Memory added successfully")
                    self?.loadMemories() // Reload to get the updated list
                }
            }
        }
    }
    
    // MARK: - Update Memory
    func updateMemory(_ memory: Memory) {
        guard FirebaseApp.app() != nil else {
            print("❌ [MemoryManager] Firebase not configured")
            errorMessage = "Firebase not configured"
            return
        }
        
        guard !memory.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("❌ [MemoryManager] Cannot update with empty text")
            errorMessage = "Cannot update with empty text"
            return
        }
        
        let data: [String: Any] = [
            "text": memory.text.trimmingCharacters(in: .whitespacesAndNewlines),
            "timestamp": Timestamp(date: memory.timestamp),
            "tags": memory.tags
        ]
        
        db.collection(collectionName).document(memory.id).updateData(data) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ [MemoryManager] Error updating memory: \(error.localizedDescription)")
                    self?.errorMessage = "Failed to update memory: \(error.localizedDescription)"
                } else {
                    print("✅ [MemoryManager] Memory updated successfully")
                    self?.loadMemories() // Reload to get the updated list
                }
            }
        }
    }
    
    // MARK: - Delete Memory
    func deleteMemory(_ memory: Memory) {
        guard FirebaseApp.app() != nil else {
            print("❌ [MemoryManager] Firebase not configured")
            errorMessage = "Firebase not configured"
            return
        }
        
        db.collection(collectionName).document(memory.id).delete { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ [MemoryManager] Error deleting memory: \(error.localizedDescription)")
                    self?.errorMessage = "Failed to delete memory: \(error.localizedDescription)"
                } else {
                    print("✅ [MemoryManager] Memory deleted successfully")
                    self?.loadMemories() // Reload to get the updated list
                }
            }
        }
    }
    
    // MARK: - Search Memories
    func searchMemories(query: String) -> [Memory] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return memories
        }
        
        let searchTerm = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        return memories.filter { memory in
            memory.text.lowercased().contains(searchTerm) ||
            memory.tags.contains { tag in
                tag.lowercased().contains(searchTerm)
            }
        }
    }
    
    // MARK: - Get Memory by ID
    func getMemory(by id: String) -> Memory? {
        return memories.first { $0.id == id }
    }
} 