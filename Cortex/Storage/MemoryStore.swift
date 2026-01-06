//
//  MemoryStore.swift
//  MemoryTap
//
//  SQLite-based local storage for captured memories
//

import Foundation
import SQLite3
import CryptoKit

/// Lightweight SQLite storage layer for memories
/// Uses a serial dispatch queue for thread safety
final class MemoryStore: @unchecked Sendable {
    
    // MARK: - Properties
    
    private var db: OpaquePointer?
    private let dbPath: String
    private let queue = DispatchQueue(label: "com.memorytap.store", qos: .userInitiated)
    
    /// Cache of recent text hashes for deduplication
    /// Maps (hash, appBundleId) -> timestamp
    private var recentHashes: [(hash: String, appId: String, time: Date)] = []
    
    // MARK: - Initialization
    
    init() throws {
        // Store database in Application Support directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("MemoryTap", isDirectory: true)
        
        // Create directory if needed
        try FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        
        dbPath = appFolder.appendingPathComponent("memories.db").path
        
        // Open database
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            throw MemoryStoreError.databaseOpenFailed
        }
        
        // Create tables
        try createTables()
    }
    
    deinit {
        sqlite3_close(db)
    }
    
    // MARK: - Schema
    
    private func createTables() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS memories (
            id TEXT PRIMARY KEY,
            created_at INTEGER NOT NULL,
            app_bundle_id TEXT NOT NULL,
            app_name TEXT NOT NULL,
            window_title TEXT NOT NULL,
            source TEXT NOT NULL,
            text TEXT NOT NULL,
            text_hash TEXT NOT NULL
        );
        
        CREATE INDEX IF NOT EXISTS idx_memories_created_at ON memories(created_at DESC);
        CREATE INDEX IF NOT EXISTS idx_memories_hash ON memories(text_hash, app_bundle_id);
        """
        
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            throw MemoryStoreError.tableCreationFailed
        }
    }
    
    // MARK: - Hashing
    
    /// Generate SHA256 hash of trimmed text
    static func hashText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = Data(trimmed.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - Deduplication
    
    /// Check if we should skip saving this text (duplicate detection)
    /// Returns true if same hash was saved from same app within last 10 seconds
    private func shouldSkipDuplicate(hash: String, appBundleId: String) -> Bool {
        let now = Date()
        let threshold: TimeInterval = 10 // 10 seconds
        
        // Clean old entries
        recentHashes.removeAll { now.timeIntervalSince($0.time) > threshold }
        
        // Check for duplicate
        return recentHashes.contains { $0.hash == hash && $0.appId == appBundleId }
    }
    
    private func recordHash(_ hash: String, appBundleId: String) {
        recentHashes.append((hash: hash, appId: appBundleId, time: Date()))
    }
    
    // MARK: - CRUD Operations
    
    /// Save a new memory to the database
    func saveMemory(_ memory: Memory) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: MemoryStoreError.databaseOpenFailed)
                    return
                }
                
                do {
                    // Check for duplicates
                    if self.shouldSkipDuplicate(hash: memory.textHash, appBundleId: memory.appBundleId) {
                        print("[MemoryStore] Skipping duplicate: \(memory.preview.prefix(30))...")
                        continuation.resume()
                        return
                    }
                    
                    let sql = """
                    INSERT INTO memories (id, created_at, app_bundle_id, app_name, window_title, source, text, text_hash)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?);
                    """
                    
                    var statement: OpaquePointer?
                    
                    guard sqlite3_prepare_v2(self.db, sql, -1, &statement, nil) == SQLITE_OK else {
                        throw MemoryStoreError.prepareFailed
                    }
                    
                    defer { sqlite3_finalize(statement) }
                    
                    let timestamp = Int64(memory.createdAt.timeIntervalSince1970)
                    
                    sqlite3_bind_text(statement, 1, memory.id, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_int64(statement, 2, timestamp)
                    sqlite3_bind_text(statement, 3, memory.appBundleId, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(statement, 4, memory.appName, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(statement, 5, memory.windowTitle, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(statement, 6, memory.source.rawValue, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(statement, 7, memory.text, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(statement, 8, memory.textHash, -1, SQLITE_TRANSIENT)
                    
                    if sqlite3_step(statement) != SQLITE_DONE {
                        throw MemoryStoreError.insertFailed
                    }
                    
                    self.recordHash(memory.textHash, appBundleId: memory.appBundleId)
                    print("[MemoryStore] Saved memory from \(memory.appName): \(memory.preview.prefix(50))...")
                    
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Fetch all memories, sorted by creation date (newest first)
    func fetchAllMemories() async throws -> [Memory] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[Memory], Error>) in
            queue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: MemoryStoreError.databaseOpenFailed)
                    return
                }
                
                let sql = "SELECT id, created_at, app_bundle_id, app_name, window_title, source, text, text_hash FROM memories ORDER BY created_at DESC;"
                
                var statement: OpaquePointer?
                
                guard sqlite3_prepare_v2(self.db, sql, -1, &statement, nil) == SQLITE_OK else {
                    continuation.resume(throwing: MemoryStoreError.prepareFailed)
                    return
                }
                
                defer { sqlite3_finalize(statement) }
                
                var memories: [Memory] = []
                
                while sqlite3_step(statement) == SQLITE_ROW {
                    let id = String(cString: sqlite3_column_text(statement, 0))
                    let timestamp = sqlite3_column_int64(statement, 1)
                    let appBundleId = String(cString: sqlite3_column_text(statement, 2))
                    let appName = String(cString: sqlite3_column_text(statement, 3))
                    let windowTitle = String(cString: sqlite3_column_text(statement, 4))
                    let sourceRaw = String(cString: sqlite3_column_text(statement, 5))
                    let text = String(cString: sqlite3_column_text(statement, 6))
                    let textHash = String(cString: sqlite3_column_text(statement, 7))
                    
                    let source = CaptureSource(rawValue: sourceRaw) ?? .focusLost
                    let createdAt = Date(timeIntervalSince1970: TimeInterval(timestamp))
                    
                    let memory = Memory(
                        id: id,
                        createdAt: createdAt,
                        appBundleId: appBundleId,
                        appName: appName,
                        windowTitle: windowTitle,
                        source: source,
                        text: text,
                        textHash: textHash
                    )
                    
                    memories.append(memory)
                }
                
                continuation.resume(returning: memories)
            }
        }
    }
    
    /// Delete a specific memory by ID
    func deleteMemory(id: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: MemoryStoreError.databaseOpenFailed)
                    return
                }
                
                let sql = "DELETE FROM memories WHERE id = ?;"
                
                var statement: OpaquePointer?
                
                guard sqlite3_prepare_v2(self.db, sql, -1, &statement, nil) == SQLITE_OK else {
                    continuation.resume(throwing: MemoryStoreError.prepareFailed)
                    return
                }
                
                defer { sqlite3_finalize(statement) }
                
                sqlite3_bind_text(statement, 1, id, -1, SQLITE_TRANSIENT)
                
                if sqlite3_step(statement) != SQLITE_DONE {
                    continuation.resume(throwing: MemoryStoreError.deleteFailed)
                    return
                }
                
                continuation.resume()
            }
        }
    }
    
    /// Clear all memories from the database
    func clearAllMemories() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: MemoryStoreError.databaseOpenFailed)
                    return
                }
                
                let sql = "DELETE FROM memories;"
                
                if sqlite3_exec(self.db, sql, nil, nil, nil) != SQLITE_OK {
                    continuation.resume(throwing: MemoryStoreError.deleteFailed)
                    return
                }
                
                self.recentHashes.removeAll()
                continuation.resume()
            }
        }
    }
    
    /// Get total count of memories
    func getMemoryCount() async throws -> Int {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
            queue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: MemoryStoreError.databaseOpenFailed)
                    return
                }
                
                let sql = "SELECT COUNT(*) FROM memories;"
                
                var statement: OpaquePointer?
                
                guard sqlite3_prepare_v2(self.db, sql, -1, &statement, nil) == SQLITE_OK else {
                    continuation.resume(throwing: MemoryStoreError.prepareFailed)
                    return
                }
                
                defer { sqlite3_finalize(statement) }
                
                if sqlite3_step(statement) == SQLITE_ROW {
                    continuation.resume(returning: Int(sqlite3_column_int(statement, 0)))
                } else {
                    continuation.resume(returning: 0)
                }
            }
        }
    }
}

// MARK: - SQLITE_TRANSIENT helper

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// MARK: - Errors

enum MemoryStoreError: Error, LocalizedError {
    case databaseOpenFailed
    case tableCreationFailed
    case prepareFailed
    case insertFailed
    case deleteFailed
    
    var errorDescription: String? {
        switch self {
        case .databaseOpenFailed: return "Failed to open database"
        case .tableCreationFailed: return "Failed to create tables"
        case .prepareFailed: return "Failed to prepare SQL statement"
        case .insertFailed: return "Failed to insert memory"
        case .deleteFailed: return "Failed to delete memory"
        }
    }
}
