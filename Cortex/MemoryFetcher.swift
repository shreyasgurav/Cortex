import Foundation
import FirebaseFirestore

class MemoryFetcher: NSObject {
    private let db = Firestore.firestore()
    private(set) var memories: [MemoryItem] = []
    var onUpdate: (() -> Void)?

    func fetchMemories() {
        db.collection("memory")
            .order(by: "timestamp", descending: true)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }
                if let docs = snapshot?.documents {
                    self.memories = docs.compactMap { MemoryItem(document: $0) }
                    self.onUpdate?()
                }
            }
    }
}