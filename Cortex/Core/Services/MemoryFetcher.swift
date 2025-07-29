import Foundation
import FirebaseFirestore
import FirebaseCore

class MemoryFetcher: ObservableObject {
    @Published var memories: [MemoryItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private var db: Firestore?
    private var listenerRegistration: ListenerRegistration?
    private var retryCount = 0
    private let maxRetries = 3
    
    init() {
        setupFirestore()
    }
    
    private func setupFirestore() {
        // Ensure Firebase is configured
        guard FirebaseApp.app() != nil else {
            print("❌ Firebase not configured")
            DispatchQueue.main.async {
                self.errorMessage = "Firebase not configured. Please restart the app."
            }
            return
        }
        
        // Initialize Firestore with settings to prevent database locks
        let settings = FirestoreSettings()
        settings.isPersistenceEnabled = false // Prevent database locks
        settings.cacheSizeBytes = FirestoreCacheSizeUnlimited
        
        db = Firestore.firestore()
        db?.settings = settings
        
        print("✅ Firestore initialized")
    }
    
    func fetchMemories() {
        guard let db = db else {
            print("❌ Firestore not initialized")
            DispatchQueue.main.async {
                self.errorMessage = "Firestore not initialized"
            }
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        // Remove existing listener
        listenerRegistration?.remove()
        
        // Add real-time listener
        listenerRegistration = db.collection("memory")
            .order(by: "timestamp", descending: true)
            .limit(to: 50)
            .addSnapshotListener { [weak self] querySnapshot, error in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    
                    self.isLoading = false
                    
                    if let error = error {
                        print("❌ Firestore error: \(error.localizedDescription)")
                        
                        // Check if it's a database lock error and retry
                        if self.shouldRetryForError(error) {
                            self.handleRetry()
                            return
                        }
                        
                        self.errorMessage = "Error loading memories: \(error.localizedDescription)"
                        return
                    }
                    
                    guard let documents = querySnapshot?.documents else {
                        self.memories = []
                        return
                    }
                    
                    self.memories = documents.compactMap { MemoryItem(document: $0) }
                    self.retryCount = 0 // Reset retry count on success
                    
                    print("✅ Loaded \(self.memories.count) memories")
                }
            }
    }
    
    private func shouldRetryForError(_ error: Error) -> Bool {
        let errorDescription = error.localizedDescription.lowercased()
        return errorDescription.contains("lock") ||
               errorDescription.contains("resource temporarily unavailable") ||
               errorDescription.contains("failed to open db") ||
               errorDescription.contains("leveldb error")
    }
    
    private func handleRetry() {
        retryCount += 1
        if retryCount <= maxRetries {
            let delay = Double(retryCount) * 2.0 // Exponential backoff
            print("🔄 Retrying in \(delay) seconds (attempt \(retryCount)/\(maxRetries))")
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.fetchMemories()
            }
        } else {
            print("❌ Max retries reached")
            DispatchQueue.main.async {
                self.errorMessage = "Failed to load memories after multiple attempts"
            }
        }
    }
    
    func cleanup() {
        listenerRegistration?.remove()
        listenerRegistration = nil
    }
    
    deinit {
        cleanup()
    }
}