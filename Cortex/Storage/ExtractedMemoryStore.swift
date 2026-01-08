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
        // Step 1: Create tables (without new columns for backward compatibility)
        let tableSQL = """
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
        
        CREATE TABLE IF NOT EXISTS processing_log (
            id TEXT PRIMARY KEY,
            raw_memory_id TEXT NOT NULL,
            processed_at INTEGER NOT NULL,
            was_worth_remembering INTEGER NOT NULL,
            reason TEXT,
            extracted_count INTEGER NOT NULL DEFAULT 0
        );
        
        CREATE TABLE IF NOT EXISTS waypoints (
            id TEXT PRIMARY KEY,
            src_id TEXT NOT NULL,
            dst_id TEXT NOT NULL,
            weight REAL NOT NULL DEFAULT 0.5,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            UNIQUE(src_id, dst_id)
        );
        """
        
        if sqlite3_exec(db, tableSQL, nil, nil, nil) != SQLITE_OK {
            throw ExtractedMemoryStoreError.tableCreationFailed
        }
        
        // Step 2: Run migrations to add new columns if needed
        try runMigrations()
        
        // Step 3: Create indexes (after ensuring all columns exist)
        let indexSQL = """
        CREATE INDEX IF NOT EXISTS idx_extracted_created_at ON extracted_memories(created_at DESC);
        CREATE INDEX IF NOT EXISTS idx_extracted_type ON extracted_memories(type);
        CREATE INDEX IF NOT EXISTS idx_extracted_active ON extracted_memories(is_active);
        CREATE INDEX IF NOT EXISTS idx_extracted_source ON extracted_memories(source_memory_id);
        CREATE INDEX IF NOT EXISTS idx_waypoints_src ON waypoints(src_id);
        CREATE INDEX IF NOT EXISTS idx_waypoints_dst ON waypoints(dst_id);
        """
        
        // Only create indexes on new columns if they exist
        if sqlite3_exec(db, indexSQL, nil, nil, nil) != SQLITE_OK {
            // Non-fatal: indexes might fail if columns don't exist yet
            print("[ExtractedMemoryStore] Warning: Some indexes failed to create")
        }
        
        // Create indexes on new columns conditionally
        try createNewColumnIndexes()
    }
    
    /// Check if a column exists in extracted_memories table
    private func checkColumnExists(_ columnName: String) -> Bool {
        let checkSQL = "PRAGMA table_info(extracted_memories)"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, checkSQL, -1, &statement, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(statement) }
        
        while sqlite3_step(statement) == SQLITE_ROW {
            if let nameCStr = sqlite3_column_text(statement, 1) {
                let name = String(cString: nameCStr)
                if name == columnName { return true }
            }
        }
        return false
    }
    
    /// Create indexes on new OpenMemory-style columns (only if columns exist)
    private func createNewColumnIndexes() throws {
        // Check which columns exist
        let checkSQL = "PRAGMA table_info(extracted_memories)"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, checkSQL, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        
        var hasSimhash = false
        var hasSector = false
        var hasSalience = false
        
        while sqlite3_step(statement) == SQLITE_ROW {
            if let nameCStr = sqlite3_column_text(statement, 1) {
                let name = String(cString: nameCStr)
                if name == "simhash" { hasSimhash = true }
                if name == "sector" { hasSector = true }
                if name == "salience" { hasSalience = true }
            }
        }
        
        // Create indexes only for columns that exist
        var indexSQL = ""
        if hasSimhash {
            indexSQL += "CREATE INDEX IF NOT EXISTS idx_extracted_simhash ON extracted_memories(simhash);\n"
        }
        if hasSalience {
            indexSQL += "CREATE INDEX IF NOT EXISTS idx_extracted_salience ON extracted_memories(salience DESC);\n"
        }
        if hasSector {
            indexSQL += "CREATE INDEX IF NOT EXISTS idx_extracted_sector ON extracted_memories(sector);\n"
        }
        
        if !indexSQL.isEmpty {
            sqlite3_exec(db, indexSQL, nil, nil, nil) // Ignore errors
        }
    }
    
    /// Add new columns to existing databases
    private func runMigrations() throws {
        // Check if simhash column exists, if not add new columns
        let checkSQL = "PRAGMA table_info(extracted_memories)"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, checkSQL, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        
        var hasSimhash = false
        while sqlite3_step(statement) == SQLITE_ROW {
            if let nameCStr = sqlite3_column_text(statement, 1) {
                let name = String(cString: nameCStr)
                if name == "simhash" { hasSimhash = true }
            }
        }
        
        if !hasSimhash {
            let migrations = [
                "ALTER TABLE extracted_memories ADD COLUMN simhash TEXT",
                "ALTER TABLE extracted_memories ADD COLUMN sector TEXT",
                "ALTER TABLE extracted_memories ADD COLUMN salience REAL NOT NULL DEFAULT 0.5",
                "ALTER TABLE extracted_memories ADD COLUMN last_seen_at INTEGER",
                "ALTER TABLE extracted_memories ADD COLUMN decay_lambda REAL NOT NULL DEFAULT 0.02",
                "ALTER TABLE extracted_memories ADD COLUMN segment INTEGER NOT NULL DEFAULT 0",
            ]
            
            for sql in migrations {
                sqlite3_exec(db, sql, nil, nil, nil) // Ignore errors for already-existing columns
            }
            
            print("[ExtractedMemoryStore] Applied OpenMemory-style schema migrations")
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
                
                // Build SQL dynamically based on which columns exist
                let hasNewColumns = self.checkColumnExists("simhash")
                
                let sql: String
                if hasNewColumns {
                    sql = """
                    INSERT OR REPLACE INTO extracted_memories 
                    (id, created_at, content, type, confidence, tags, source_memory_id, source_app, is_active, expires_at, related_memory_ids, embedding, embedding_model, simhash, sector, salience, last_seen_at, decay_lambda, segment)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """
                } else {
                    sql = """
                    INSERT OR REPLACE INTO extracted_memories 
                    (id, created_at, content, type, confidence, tags, source_memory_id, source_app, is_active, expires_at, related_memory_ids, embedding, embedding_model)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """
                }
                
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
                
                // Bind new OpenMemory-style fields if they exist
                if hasNewColumns {
                    var paramIndex = 14
                    
                    // simhash
                    if let simhash = memory.simhash {
                        sqlite3_bind_text(statement, Int32(paramIndex), (simhash as NSString).utf8String, -1, nil)
                    } else {
                        sqlite3_bind_null(statement, Int32(paramIndex))
                    }
                    paramIndex += 1
                    
                    // sector (use sector field if available, otherwise type)
                    if let sector = memory.sector {
                        sqlite3_bind_text(statement, Int32(paramIndex), (sector as NSString).utf8String, -1, nil)
                    } else {
                        sqlite3_bind_text(statement, Int32(paramIndex), (memory.type.rawValue as NSString).utf8String, -1, nil)
                    }
                    paramIndex += 1
                    
                    // salience
                    sqlite3_bind_double(statement, Int32(paramIndex), memory.salience)
                    paramIndex += 1
                    
                    // last_seen_at
                    if let lastSeen = memory.lastSeenAt {
                        sqlite3_bind_int64(statement, Int32(paramIndex), Int64(lastSeen.timeIntervalSince1970))
                    } else {
                        sqlite3_bind_int64(statement, Int32(paramIndex), Int64(memory.createdAt.timeIntervalSince1970))
                    }
                    paramIndex += 1
                    
                    // decay_lambda
                    sqlite3_bind_double(statement, Int32(paramIndex), memory.decayLambda)
                    paramIndex += 1
                    
                    // segment
                    sqlite3_bind_int(statement, Int32(paramIndex), Int32(memory.segment))
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
                WHERE (LOWER(content) LIKE LOWER(?) OR LOWER(tags) LIKE LOWER(?)) AND is_active = 1
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
                sqlite3_bind_text(statement, 2, (searchPattern as NSString).utf8String, -1, nil)
                
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
    
    // MARK: - SimHash Deduplication (OpenMemory-style)
    
    /// Find existing memory by SimHash (fuzzy duplicate detection)
    /// Returns existing memory if hamming distance ≤ 3
    func findBySimHash(_ simhash: String) async throws -> ExtractedMemory? {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self, let db = self.db else {
                    continuation.resume(throwing: ExtractedMemoryStoreError.databaseNotOpen)
                    return
                }
                
                let sql = """
                SELECT id, created_at, content, type, confidence, tags, source_memory_id, source_app, 
                       is_active, expires_at, related_memory_ids, embedding, embedding_model,
                       simhash, sector, salience, last_seen_at, decay_lambda, segment
                FROM extracted_memories
                WHERE simhash = ? AND is_active = 1
                ORDER BY salience DESC
                LIMIT 1
                """
                
                var statement: OpaquePointer?
                
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                    continuation.resume(returning: nil)
                    return
                }
                
                defer { sqlite3_finalize(statement) }
                
                sqlite3_bind_text(statement, 1, (simhash as NSString).utf8String, -1, nil)
                
                if sqlite3_step(statement) == SQLITE_ROW {
                    let memory = self.extractMemoryFromRowExtended(statement)
                    continuation.resume(returning: memory)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    /// Find near-duplicates by SimHash (hamming distance check in code)
    func findNearDuplicates(_ content: String) async throws -> ExtractedMemory? {
        let newSimHash = SimHash.compute(content)
        
        // First try exact match
        if let exact = try await findBySimHash(newSimHash) {
            return exact
        }
        
        // Then check all memories for hamming distance ≤ 3
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self, let db = self.db else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let sql = """
                SELECT id, simhash, salience
                FROM extracted_memories
                WHERE simhash IS NOT NULL AND is_active = 1
                ORDER BY salience DESC
                """
                
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                    continuation.resume(returning: nil)
                    return
                }
                defer { sqlite3_finalize(statement) }
                
                var bestMatch: (id: String, distance: Int)? = nil
                
                while sqlite3_step(statement) == SQLITE_ROW {
                    guard let idCStr = sqlite3_column_text(statement, 0),
                          let hashCStr = sqlite3_column_text(statement, 1) else { continue }
                    
                    let existingId = String(cString: idCStr)
                    let existingHash = String(cString: hashCStr)
                    let distance = SimHash.hammingDistance(newSimHash, existingHash)
                    
                    if distance <= SimHash.duplicateThreshold {
                        if bestMatch == nil || distance < bestMatch!.distance {
                            bestMatch = (existingId, distance)
                        }
                    }
                }
                
                if let match = bestMatch {
                    // Fetch full memory
                    Task {
                        let memory = try? await self.fetchMemory(byId: match.id)
                        continuation.resume(returning: memory)
                    }
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    /// Fetch a single memory by ID
    func fetchMemory(byId id: String) async throws -> ExtractedMemory? {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self, let db = self.db else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let sql = """
                SELECT id, created_at, content, type, confidence, tags, source_memory_id, source_app, 
                       is_active, expires_at, related_memory_ids, embedding, embedding_model,
                       simhash, sector, salience, last_seen_at, decay_lambda, segment
                FROM extracted_memories
                WHERE id = ?
                """
                
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                    continuation.resume(returning: nil)
                    return
                }
                defer { sqlite3_finalize(statement) }
                
                sqlite3_bind_text(statement, 1, (id as NSString).utf8String, -1, nil)
                
                if sqlite3_step(statement) == SQLITE_ROW {
                    continuation.resume(returning: self.extractMemoryFromRowExtended(statement))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    // MARK: - Salience Updates
    
    /// Boost salience when memory is retrieved or duplicate found
    func boostSalience(memoryId: String, boost: Double = 0.15) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [weak self] in
                guard let self = self, let db = self.db else {
                    continuation.resume(throwing: ExtractedMemoryStoreError.databaseNotOpen)
                    return
                }
                
                let now = Int64(Date().timeIntervalSince1970)
                let sql = """
                UPDATE extracted_memories 
                SET salience = MIN(1.0, salience + ?), last_seen_at = ?
                WHERE id = ?
                """
                
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                    continuation.resume(throwing: ExtractedMemoryStoreError.prepareFailed)
                    return
                }
                defer { sqlite3_finalize(statement) }
                
                sqlite3_bind_double(statement, 1, boost)
                sqlite3_bind_int64(statement, 2, now)
                sqlite3_bind_text(statement, 3, (memoryId as NSString).utf8String, -1, nil)
                
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    continuation.resume(throwing: ExtractedMemoryStoreError.insertFailed)
                    return
                }
                
                print("[ExtractedMemoryStore] Boosted salience for: \(memoryId)")
                continuation.resume()
            }
        }
    }
    
    /// Update last_seen_at timestamp (for recency scoring)
    func touchMemory(memoryId: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [weak self] in
                guard let self = self, let db = self.db else {
                    continuation.resume(throwing: ExtractedMemoryStoreError.databaseNotOpen)
                    return
                }
                
                let now = Int64(Date().timeIntervalSince1970)
                let sql = "UPDATE extracted_memories SET last_seen_at = ? WHERE id = ?"
                
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                    continuation.resume(throwing: ExtractedMemoryStoreError.prepareFailed)
                    return
                }
                defer { sqlite3_finalize(statement) }
                
                sqlite3_bind_int64(statement, 1, now)
                sqlite3_bind_text(statement, 2, (memoryId as NSString).utf8String, -1, nil)
                
                sqlite3_step(statement)
                continuation.resume()
            }
        }
    }
    
    // MARK: - Waypoint Operations
    
    /// Save a waypoint (memory link)
    func saveWaypoint(_ waypoint: Waypoint) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [weak self] in
                guard let self = self, let db = self.db else {
                    continuation.resume(throwing: ExtractedMemoryStoreError.databaseNotOpen)
                    return
                }
                
                let sql = """
                INSERT OR REPLACE INTO waypoints (id, src_id, dst_id, weight, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """
                
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                    continuation.resume(throwing: ExtractedMemoryStoreError.prepareFailed)
                    return
                }
                defer { sqlite3_finalize(statement) }
                
                sqlite3_bind_text(statement, 1, (waypoint.id as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 2, (waypoint.sourceId as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 3, (waypoint.targetId as NSString).utf8String, -1, nil)
                sqlite3_bind_double(statement, 4, waypoint.weight)
                sqlite3_bind_int64(statement, 5, Int64(waypoint.createdAt.timeIntervalSince1970))
                sqlite3_bind_int64(statement, 6, Int64(waypoint.updatedAt.timeIntervalSince1970))
                
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    continuation.resume(throwing: ExtractedMemoryStoreError.insertFailed)
                    return
                }
                
                continuation.resume()
            }
        }
    }
    
    /// Fetch all waypoints for a source memory
    func fetchWaypoints(forSource sourceId: String) async throws -> [Waypoint] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self, let db = self.db else {
                    continuation.resume(returning: [])
                    return
                }
                
                let sql = "SELECT id, src_id, dst_id, weight, created_at, updated_at FROM waypoints WHERE src_id = ?"
                
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                    continuation.resume(returning: [])
                    return
                }
                defer { sqlite3_finalize(statement) }
                
                sqlite3_bind_text(statement, 1, (sourceId as NSString).utf8String, -1, nil)
                
                var waypoints: [Waypoint] = []
                while sqlite3_step(statement) == SQLITE_ROW {
                    guard let idCStr = sqlite3_column_text(statement, 0),
                          let srcCStr = sqlite3_column_text(statement, 1),
                          let dstCStr = sqlite3_column_text(statement, 2) else { continue }
                    
                    var wp = Waypoint(
                        sourceId: String(cString: srcCStr),
                        targetId: String(cString: dstCStr),
                        weight: sqlite3_column_double(statement, 3)
                    )
                    // Note: We're creating new waypoints here, timestamps will be current
                    waypoints.append(wp)
                }
                
                continuation.resume(returning: waypoints)
            }
        }
    }
    
    /// Fetch all waypoints
    func fetchAllWaypoints() async throws -> [Waypoint] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self, let db = self.db else {
                    continuation.resume(returning: [])
                    return
                }
                
                let sql = "SELECT id, src_id, dst_id, weight, created_at, updated_at FROM waypoints"
                
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                    continuation.resume(returning: [])
                    return
                }
                defer { sqlite3_finalize(statement) }
                
                var waypoints: [Waypoint] = []
                while sqlite3_step(statement) == SQLITE_ROW {
                    guard let srcCStr = sqlite3_column_text(statement, 1),
                          let dstCStr = sqlite3_column_text(statement, 2) else { continue }
                    
                    let wp = Waypoint(
                        sourceId: String(cString: srcCStr),
                        targetId: String(cString: dstCStr),
                        weight: sqlite3_column_double(statement, 3)
                    )
                    waypoints.append(wp)
                }
                
                continuation.resume(returning: waypoints)
            }
        }
    }
    
    /// Fetch all memories with embeddings (for waypoint creation)
    func fetchMemoriesWithEmbeddings() async throws -> [(id: String, embedding: [Double])] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self, let db = self.db else {
                    continuation.resume(returning: [])
                    return
                }
                
                let sql = """
                SELECT id, embedding FROM extracted_memories 
                WHERE embedding IS NOT NULL AND is_active = 1
                """
                
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                    continuation.resume(returning: [])
                    return
                }
                defer { sqlite3_finalize(statement) }
                
                var results: [(id: String, embedding: [Double])] = []
                
                while sqlite3_step(statement) == SQLITE_ROW {
                    guard let idCStr = sqlite3_column_text(statement, 0),
                          let embCStr = sqlite3_column_text(statement, 1) else { continue }
                    
                    let id = String(cString: idCStr)
                    let embJSON = String(cString: embCStr)
                    
                    if let embedding = try? JSONDecoder().decode([Double].self, from: Data(embJSON.utf8)) {
                        results.append((id, embedding))
                    }
                }
                
                continuation.resume(returning: results)
            }
        }
    }
    
    // MARK: - Extended Row Extraction
    
    private func extractMemoryFromRowExtended(_ statement: OpaquePointer?) -> ExtractedMemory? {
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
        
        // Extended fields (columns 13-18)
        var simhash: String? = nil
        if sqlite3_column_type(statement, 13) != SQLITE_NULL,
           let hashCStr = sqlite3_column_text(statement, 13) {
            simhash = String(cString: hashCStr)
        }
        
        var sector: String? = nil
        if sqlite3_column_type(statement, 14) != SQLITE_NULL,
           let sectorCStr = sqlite3_column_text(statement, 14) {
            sector = String(cString: sectorCStr)
        }
        
        let salience = sqlite3_column_double(statement, 15)
        
        var lastSeenAt: Date? = nil
        if sqlite3_column_type(statement, 16) != SQLITE_NULL {
            lastSeenAt = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 16)))
        }
        
        let decayLambda = sqlite3_column_double(statement, 17)
        let segment = Int(sqlite3_column_int(statement, 18))
        
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
            embeddingModel: embeddingModel,
            simhash: simhash,
            sector: sector,
            salience: salience,
            lastSeenAt: lastSeenAt,
            decayLambda: decayLambda,
            segment: segment
        )
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

