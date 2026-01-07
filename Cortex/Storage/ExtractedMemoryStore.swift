//
//  ExtractedMemoryStore.swift
//  Cortex
//
//  SQLite storage for AI-extracted memories
//  Separate from MemoryStore which stores raw captures
//

import Foundation
import SQLite3
import CryptoKit

/// Storage layer for extracted/processed memories
final class ExtractedMemoryStore: @unchecked Sendable {
    
    // MARK: - Properties
    
    private var db: OpaquePointer?
    private let dbPath: String
    private let queue = DispatchQueue(label: "com.Cortex.extracted-store", qos: .userInitiated)
    
    // MARK: - Initialization
    
    init() throws {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("Cortex", isDirectory: true)
        
        try FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        
        dbPath = appFolder.appendingPathComponent("extracted_memories.db").path
        
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            throw ExtractedMemoryStoreError.databaseOpenFailed
        }
        
        try createTables()
    }
    
    deinit {
        sqlite3_close(db)
    }
    
    // MARK: - Schema
    
    private func createTables() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS extracted_memories (
            id TEXT PRIMARY KEY,
            created_at INTEGER NOT NULL,
            content TEXT NOT NULL,
            type TEXT NOT NULL,
            confidence REAL NOT NULL,
            tags TEXT NOT NULL,
            source_memory_id TEXT NOT NULL,
            source_app TEXT NOT NULL,
            is_active INTEGER NOT NULL DEFAULT 1,
            expires_at INTEGER,
            related_memory_ids TEXT NOT NULL DEFAULT '[]',
            embedding TEXT,
            embedding_model TEXT
        );
        
        CREATE INDEX IF NOT EXISTS idx_extracted_created_at ON extracted_memories(created_at DESC);
        CREATE INDEX IF NOT EXISTS idx_extracted_type ON extracted_memories(type);
        CREATE INDEX IF NOT EXISTS idx_extracted_active ON extracted_memories(is_active);
        CREATE INDEX IF NOT EXISTS idx_extracted_source ON extracted_memories(source_memory_id);
        
        CREATE TABLE IF NOT EXISTS processing_log (
            id TEXT PRIMARY KEY,
            raw_memory_id TEXT NOT NULL,
            processed_at INTEGER NOT NULL,
            was_worth_remembering INTEGER NOT NULL,
            reason TEXT,
            extracted_count INTEGER NOT NULL DEFAULT 0
        );
        """
        
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            throw ExtractedMemoryStoreError.tableCreationFailed
        }
    }
    
    // MARK: - Save Methods
    
    /// Save an extracted memory
    func saveMemory(_ memory: ExtractedMemory, embedding: [Double]? = nil, embeddingModel: String? = nil) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [weak self] in
                guard let self = self, let db = self.db else {
                    continuation.resume(throwing: ExtractedMemoryStoreError.databaseNotOpen)
                    return
                }
                
                let sql = """
                INSERT OR REPLACE INTO extracted_memories 
                (id, created_at, content, type, confidence, tags, source_memory_id, source_app, is_active, expires_at, related_memory_ids, embedding, embedding_model)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """
                
                var statement: OpaquePointer?
                
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                    continuation.resume(throwing: ExtractedMemoryStoreError.prepareFailed)
                    return
                }
                
                defer { sqlite3_finalize(statement) }
                
                let tagsJSON = (try? JSONEncoder().encode(memory.tags)) ?? Data()
                let relatedJSON = (try? JSONEncoder().encode(memory.relatedMemoryIds)) ?? Data()
                let embeddingJSON = embedding.flatMap { try? JSONEncoder().encode($0) }
                
                sqlite3_bind_text(statement, 1, (memory.id as NSString).utf8String, -1, nil)
                sqlite3_bind_int64(statement, 2, Int64(memory.createdAt.timeIntervalSince1970))
                sqlite3_bind_text(statement, 3, (memory.content as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 4, (memory.type.rawValue as NSString).utf8String, -1, nil)
                sqlite3_bind_double(statement, 5, memory.confidence)
                sqlite3_bind_text(statement, 6, (String(data: tagsJSON, encoding: .utf8)! as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 7, (memory.sourceMemoryId as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 8, (memory.sourceApp as NSString).utf8String, -1, nil)
                sqlite3_bind_int(statement, 9, memory.isActive ? 1 : 0)
                
                if let expiresAt = memory.expiresAt {
                    sqlite3_bind_int64(statement, 10, Int64(expiresAt.timeIntervalSince1970))
                } else {
                    sqlite3_bind_null(statement, 10)
                }
                
                sqlite3_bind_text(statement, 11, (String(data: relatedJSON, encoding: .utf8)! as NSString).utf8String, -1, nil)
                
                 if let embeddingJSON = embeddingJSON, let embString = String(data: embeddingJSON, encoding: .utf8) {
                    sqlite3_bind_text(statement, 12, (embString as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(statement, 12)
                }
                
                if let model = embeddingModel {
                    sqlite3_bind_text(statement, 13, (model as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(statement, 13)
                }
                
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    continuation.resume(throwing: ExtractedMemoryStoreError.insertFailed)
                    return
                }
                
                print("[ExtractedMemoryStore] Saved memory: \(memory.preview)")
                continuation.resume()
            }
        }
    }
    
    /// Save multiple extracted memories
    func saveMemories(_ memories: [(memory: ExtractedMemory, embedding: [Double]?, embeddingModel: String?)]) async throws {
        for entry in memories {
            try await saveMemory(entry.memory, embedding: entry.embedding, embeddingModel: entry.embeddingModel)
        }
    }
    
    /// Log that a raw memory was processed
    func logProcessing(rawMemoryId: String, wasWorthRemembering: Bool, reason: String?, extractedCount: Int) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [weak self] in
                guard let self = self, let db = self.db else {
                    continuation.resume(throwing: ExtractedMemoryStoreError.databaseNotOpen)
                    return
                }
                
                let sql = """
                INSERT INTO processing_log (id, raw_memory_id, processed_at, was_worth_remembering, reason, extracted_count)
                VALUES (?, ?, ?, ?, ?, ?)
                """
                
                var statement: OpaquePointer?
                
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                    continuation.resume(throwing: ExtractedMemoryStoreError.prepareFailed)
                    return
                }
                
                defer { sqlite3_finalize(statement) }
                
                let id = UUID().uuidString
                sqlite3_bind_text(statement, 1, (id as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 2, (rawMemoryId as NSString).utf8String, -1, nil)
                sqlite3_bind_int64(statement, 3, Int64(Date().timeIntervalSince1970))
                sqlite3_bind_int(statement, 4, wasWorthRemembering ? 1 : 0)
                
                if let reason = reason {
                    sqlite3_bind_text(statement, 5, (reason as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(statement, 5)
                }
                
                sqlite3_bind_int(statement, 6, Int32(extractedCount))
                
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    continuation.resume(throwing: ExtractedMemoryStoreError.insertFailed)
                    return
                }
                
                continuation.resume()
            }
        }
    }
    
    // MARK: - Query Methods
    
    /// Fetch all active extracted memories
    func fetchAllMemories() async throws -> [ExtractedMemory] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self, let db = self.db else {
                    continuation.resume(throwing: ExtractedMemoryStoreError.databaseNotOpen)
                    return
                }
                
                let sql = """
                SELECT id, created_at, content, type, confidence, tags, source_memory_id, source_app, is_active, expires_at, related_memory_ids
                FROM extracted_memories
                WHERE is_active = 1
                ORDER BY created_at DESC
                """
                
                var statement: OpaquePointer?
                
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                    continuation.resume(throwing: ExtractedMemoryStoreError.queryFailed)
                    return
                }
                
                defer { sqlite3_finalize(statement) }
                
                var memories: [ExtractedMemory] = []
                
                while sqlite3_step(statement) == SQLITE_ROW {
                    if let memory = self.extractMemoryFromRow(statement) {
                        memories.append(memory)
                    }
                }
                
                continuation.resume(returning: memories)
            }
        }
    }
    
    /// Fetch memories by type
    func fetchMemories(ofType type: MemoryType) async throws -> [ExtractedMemory] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self, let db = self.db else {
                    continuation.resume(throwing: ExtractedMemoryStoreError.databaseNotOpen)
                    return
                }
                
                let sql = """
                SELECT id, created_at, content, type, confidence, tags, source_memory_id, source_app, is_active, expires_at, related_memory_ids
                FROM extracted_memories
                WHERE type = ? AND is_active = 1
                ORDER BY created_at DESC
                """
                
                var statement: OpaquePointer?
                
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                    continuation.resume(throwing: ExtractedMemoryStoreError.queryFailed)
                    return
                }
                
                defer { sqlite3_finalize(statement) }
                
                sqlite3_bind_text(statement, 1, (type.rawValue as NSString).utf8String, -1, nil)
                
                var memories: [ExtractedMemory] = []
                
                while sqlite3_step(statement) == SQLITE_ROW {
                    if let memory = self.extractMemoryFromRow(statement) {
                        memories.append(memory)
                    }
                }
                
                continuation.resume(returning: memories)
            }
        }
    }
    
    /// Search memories by content (case-insensitive LIKE)
    func searchMemories(query: String) async throws -> [ExtractedMemory] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self, let db = self.db else {
                    continuation.resume(throwing: ExtractedMemoryStoreError.databaseNotOpen)
                    return
                }
                
                let sql = """
                SELECT id, created_at, content, type, confidence, tags, source_memory_id, source_app, is_active, expires_at, related_memory_ids, embedding, embedding_model
                FROM extracted_memories
                WHERE LOWER(content) LIKE LOWER(?) AND is_active = 1
                ORDER BY created_at DESC
                """
                
                var statement: OpaquePointer?
                
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                    continuation.resume(throwing: ExtractedMemoryStoreError.queryFailed)
                    return
                }
                
                defer { sqlite3_finalize(statement) }
                
                let searchPattern = "%\(query)%"
                sqlite3_bind_text(statement, 1, (searchPattern as NSString).utf8String, -1, nil)
                
                var memories: [ExtractedMemory] = []
                
                while sqlite3_step(statement) == SQLITE_ROW {
                    if let memory = self.extractMemoryFromRow(statement) {
                        memories.append(memory)
                    }
                }
                
                continuation.resume(returning: memories)
            }
        }
    }
    
    // MARK: - Semantic Search (Cosine on stored embeddings)
    
    /// Compute cosine similarity between two vectors
    private func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Double = 0
        var na: Double = 0
        var nb: Double = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        let denom = (na.squareRoot() * nb.squareRoot())
        return denom == 0 ? 0 : dot / denom
    }
    
    /// Semantic search using precomputed embeddings (in-memory scoring)
    func searchByEmbedding(queryEmbedding: [Double], topK: Int = 10, minScore: Double = 0.6) async throws -> [ExtractedMemory] {
        let all = try await fetchAllMemories()
        let scored: [(ExtractedMemory, Double)] = all.compactMap { mem in
            guard let emb = mem.embedding else { return nil }
            let score = cosine(queryEmbedding, emb)
            return (mem, score)
        }
        
        // Filter by minScore and sort by score descending
        let sorted = scored
            .filter { $0.1 >= minScore }
            .sorted { $0.1 > $1.1 }
            .prefix(topK)
            .map { $0.0 }
            
        return sorted
    }
    
    /// Check if a raw memory has been processed
    func hasBeenProcessed(rawMemoryId: String) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self, let db = self.db else {
                    continuation.resume(throwing: ExtractedMemoryStoreError.databaseNotOpen)
                    return
                }
                
                let sql = "SELECT COUNT(*) FROM processing_log WHERE raw_memory_id = ?"
                var statement: OpaquePointer?
                
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                    continuation.resume(returning: false)
                    return
                }
                
                defer { sqlite3_finalize(statement) }
                
                sqlite3_bind_text(statement, 1, (rawMemoryId as NSString).utf8String, -1, nil)
                
                if sqlite3_step(statement) == SQLITE_ROW {
                    let count = sqlite3_column_int(statement, 0)
                    continuation.resume(returning: count > 0)
                } else {
                    continuation.resume(returning: false)
                }
            }
        }
    }
    
    // MARK: - Delete Methods
    
    /// Mark a memory as forgotten (soft delete)
    func forgetMemory(id: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [weak self] in
                guard let self = self, let db = self.db else {
                    continuation.resume(throwing: ExtractedMemoryStoreError.databaseNotOpen)
                    return
                }
                
                let sql = "UPDATE extracted_memories SET is_active = 0 WHERE id = ?"
                var statement: OpaquePointer?
                
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                    continuation.resume(throwing: ExtractedMemoryStoreError.deleteFailed)
                    return
                }
                
                defer { sqlite3_finalize(statement) }
                
                sqlite3_bind_text(statement, 1, (id as NSString).utf8String, -1, nil)
                
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    continuation.resume(throwing: ExtractedMemoryStoreError.deleteFailed)
                    return
                }
                
                print("[ExtractedMemoryStore] Forgot memory: \(id)")
                continuation.resume()
            }
        }
    }
    
    /// Permanently delete a memory
    func deleteMemory(id: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [weak self] in
                guard let self = self, let db = self.db else {
                    continuation.resume(throwing: ExtractedMemoryStoreError.databaseNotOpen)
                    return
                }
                
                let sql = "DELETE FROM extracted_memories WHERE id = ?"
                var statement: OpaquePointer?
                
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                    continuation.resume(throwing: ExtractedMemoryStoreError.deleteFailed)
                    return
                }
                
                defer { sqlite3_finalize(statement) }
                
                sqlite3_bind_text(statement, 1, (id as NSString).utf8String, -1, nil)
                
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    continuation.resume(throwing: ExtractedMemoryStoreError.deleteFailed)
                    return
                }
                
                print("[ExtractedMemoryStore] Deleted memory: \(id)")
                continuation.resume()
            }
        }
    }
    
    /// Clear all extracted memories
    func clearAllMemories() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [weak self] in
                guard let self = self, let db = self.db else {
                    continuation.resume(throwing: ExtractedMemoryStoreError.databaseNotOpen)
                    return
                }
                
                let sql = "DELETE FROM extracted_memories"
                var statement: OpaquePointer?
                
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                    continuation.resume(throwing: ExtractedMemoryStoreError.deleteFailed)
                    return
                }
                
                defer { sqlite3_finalize(statement) }
                
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    continuation.resume(throwing: ExtractedMemoryStoreError.deleteFailed)
                    return
                }
                
                print("[ExtractedMemoryStore] Cleared all memories")
                continuation.resume()
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func extractMemoryFromRow(_ statement: OpaquePointer?) -> ExtractedMemory? {
        guard let statement = statement else { return nil }
        
        guard let idCStr = sqlite3_column_text(statement, 0),
              let contentCStr = sqlite3_column_text(statement, 2),
              let typeCStr = sqlite3_column_text(statement, 3),
              let tagsCStr = sqlite3_column_text(statement, 5),
              let sourceIdCStr = sqlite3_column_text(statement, 6),
              let sourceAppCStr = sqlite3_column_text(statement, 7),
              let relatedCStr = sqlite3_column_text(statement, 10) else {
            return nil
        }
        
        let id = String(cString: idCStr)
        let createdAt = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 1)))
        let content = String(cString: contentCStr)
        let typeString = String(cString: typeCStr)
        let type = MemoryType(rawValue: typeString) ?? .insight
        let confidence = sqlite3_column_double(statement, 4)
        let tagsJSON = String(cString: tagsCStr)
        let tags = (try? JSONDecoder().decode([String].self, from: tagsJSON.data(using: .utf8)!)) ?? []
        let sourceMemoryId = String(cString: sourceIdCStr)
        let sourceApp = String(cString: sourceAppCStr)
        let isActive = sqlite3_column_int(statement, 8) == 1
        
        var expiresAt: Date?
        if sqlite3_column_type(statement, 9) != SQLITE_NULL {
            expiresAt = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 9)))
        }
        
        let relatedJSON = String(cString: relatedCStr)
        let relatedMemoryIds = (try? JSONDecoder().decode([String].self, from: relatedJSON.data(using: .utf8)!)) ?? []
        
        var embedding: [Double]? = nil
        if sqlite3_column_type(statement, 11) != SQLITE_NULL,
           let embCStr = sqlite3_column_text(statement, 11) {
            let embJSON = String(cString: embCStr)
            embedding = try? JSONDecoder().decode([Double].self, from: Data(embJSON.utf8))
        }
        
        var embeddingModel: String? = nil
        if sqlite3_column_type(statement, 12) != SQLITE_NULL,
           let modelCStr = sqlite3_column_text(statement, 12) {
            embeddingModel = String(cString: modelCStr)
        }
        
        return ExtractedMemory(
            id: id,
            createdAt: createdAt,
            content: content,
            type: type,
            confidence: confidence,
            tags: tags,
            sourceMemoryId: sourceMemoryId,
            sourceApp: sourceApp,
            isActive: isActive,
            expiresAt: expiresAt,
            relatedMemoryIds: relatedMemoryIds,
            embedding: embedding,
            embeddingModel: embeddingModel
        )
    }


    /// Check if a memory with the exact same content already exists (case-insensitive)
    func hasMemory(withContent content: String) async throws -> Bool {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            queue.async { [weak self] in
                guard let self = self, let db = self.db else {
                    continuation.resume(throwing: ExtractedMemoryStoreError.databaseNotOpen)
                    return
                }
                
                // Use standard SQL LOWER()
                let sql = "SELECT COUNT(*) FROM extracted_memories WHERE LOWER(content) = LOWER(?)"
                
                var statement: OpaquePointer?
                
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                    continuation.resume(throwing: ExtractedMemoryStoreError.prepareFailed)
                    return
                }
                
                defer { sqlite3_finalize(statement) }
                
                sqlite3_bind_text(statement, 1, (content as NSString).utf8String, -1, nil)
                
                if sqlite3_step(statement) == SQLITE_ROW {
                    let count = sqlite3_column_int(statement, 0)
                    continuation.resume(returning: count > 0)
                } else {
                    continuation.resume(returning: false)
                }
            }
        }
    }
}

// MARK: - Errors

enum ExtractedMemoryStoreError: Error {
    case databaseOpenFailed
    case databaseNotOpen
    case tableCreationFailed
    case prepareFailed
    case insertFailed
    case queryFailed
    case deleteFailed
}

