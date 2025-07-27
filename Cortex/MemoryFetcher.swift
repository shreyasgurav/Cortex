import Foundation
import FirebaseFirestore
import FirebaseCore
import Combine

class MemoryFetcher: ObservableObject {
    @Published var memories: [MemoryItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private var db: Firestore?
    private var listenerRegistration: ListenerRegistration?
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        print("🔍 MemoryFetcher initialized")
        setupFirestore()
    }
    
    private func setupFirestore() {
        // Wait a bit for Firebase to be configured
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.initializeFirestore()
        }
    }
    
    private func initializeFirestore() {
        // Check if Firebase is configured
        if FirebaseApp.app() == nil {
            print("❌ Firebase not configured - attempting to configure")
            FirebaseApp.configure()
            print("✅ Firebase configured successfully")
        } else {
            print("✅ Firebase already configured")
        }
        
        print("✅ Firebase configured, setting up Firestore")
        db = Firestore.firestore()
    }
    
    func startListening() {
        print("🔍 Starting to listen for memories...")
        
        // Ensure Firestore is initialized
        if db == nil {
            print("🔍 Firestore not initialized, setting up...")
            setupFirestore()
            
            // Wait a bit and try again
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.startListening()
            }
            return
        }
        
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
        
        print("🔍 Setting up Firestore listener for 'memory' collection")
        
        // Test the connection first
        db.collection("memory").getDocuments { [weak self] querySnapshot, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Test query failed: \(error.localizedDescription)")
                    self?.errorMessage = "Connection test failed: \(error.localizedDescription)"
                    self?.isLoading = false
                    return
                }
                
                print("✅ Test query successful, found \(querySnapshot?.documents.count ?? 0) documents")
                
                // Now start the real-time listener
                self?.startRealTimeListener()
            }
        }
    }
    
    private func startRealTimeListener() {
        guard let db = db else { return }
        
        print("🔍 Starting real-time listener")
        listenerRegistration = db.collection("memory")
            .order(by: "timestamp", descending: true)
            .limit(to: 50)
            .addSnapshotListener { [weak self] querySnapshot, error in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    
                    self.isLoading = false
                    
                    if let error = error {
                        print("❌ Firestore error: \(error.localizedDescription)")
                        self.errorMessage = "Error loading memories: \(error.localizedDescription)"
                        return
                    }
                    
                    guard let documents = querySnapshot?.documents else {
                        print("❌ No documents found in memory collection")
                        self.errorMessage = "No memories found"
                        return
                    }
                    
                    print("✅ Found \(documents.count) memories in Firestore")
                    self.memories = documents.map { MemoryItem(document: $0) }
                    
                    // Print first few memories for debugging
                    for (index, memory) in self.memories.prefix(3).enumerated() {
                        print("🔍 Memory \(index + 1): \(memory.text)")
                    }
                }
            }
    }
    
    func stopListening() {
        print("🔍 Stopping memory listener")
        listenerRegistration?.remove()
        listenerRegistration = nil
    }
    
    func refreshMemories() {
        print("🔍 Refreshing memories")
        startListening()
    }
    
    deinit {
        print("🔍 MemoryFetcher deinit")
        stopListening()
    }
} 