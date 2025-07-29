import Foundation
import FirebaseFirestore

struct MemoryItem: Identifiable, Hashable {
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
    
    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: MemoryItem, rhs: MemoryItem) -> Bool {
        lhs.id == rhs.id
    }
} 