//
//  SimHash.swift
//  Cortex
//
//  SimHash implementation for fuzzy duplicate detection
//  Ported from OpenMemory's hsg.py
//

import Foundation

/// SimHash-based near-duplicate detection
/// Uses 64-bit hash with hamming distance comparison
struct SimHash {
    
    // MARK: - Constants
    
    /// Maximum hamming distance to consider as duplicate
    static let duplicateThreshold: Int = 3
    
    // MARK: - Public API
    
    /// Compute SimHash for text
    /// Returns a 16-character hex string (64 bits)
    static func compute(_ text: String) -> String {
        let tokens = canonicalTokenSet(text)
        var hashes: [Int32] = []
        
        for token in tokens {
            var h: Int32 = 0
            for char in token.unicodeScalars {
                // Simulate JavaScript's (h << 5) - h + charCode with 32-bit overflow
                let charCode = Int32(char.value)
                h = (h &<< 5) &- h &+ charCode
            }
            hashes.append(h)
        }
        
        // Build 64-bit SimHash vector
        var vec = [Int](repeating: 0, count: 64)
        
        for h in hashes {
            for i in 0..<64 {
                // JavaScript quirk: 1 << i wraps at 32 bits, so i % 32
                let bit: Int32 = 1 << (i % 32)
                if (h & bit) != 0 {
                    vec[i] += 1
                } else {
                    vec[i] -= 1
                }
            }
        }
        
        // Convert to hex string (4 bits per character = 16 hex chars)
        var result = ""
        for i in stride(from: 0, to: 64, by: 4) {
            var nibble = 0
            if vec[i] > 0 { nibble += 8 }
            if vec[i + 1] > 0 { nibble += 4 }
            if vec[i + 2] > 0 { nibble += 2 }
            if vec[i + 3] > 0 { nibble += 1 }
            result += String(format: "%x", nibble)
        }
        
        return result
    }
    
    /// Compute hamming distance between two SimHash strings
    static func hammingDistance(_ h1: String, _ h2: String) -> Int {
        guard h1.count == h2.count else { return Int.max }
        
        var distance = 0
        let chars1 = Array(h1)
        let chars2 = Array(h2)
        
        for i in 0..<chars1.count {
            guard let v1 = Int(String(chars1[i]), radix: 16),
                  let v2 = Int(String(chars2[i]), radix: 16) else {
                continue
            }
            
            let xor = v1 ^ v2
            // Count bits in XOR result
            if xor & 8 != 0 { distance += 1 }
            if xor & 4 != 0 { distance += 1 }
            if xor & 2 != 0 { distance += 1 }
            if xor & 1 != 0 { distance += 1 }
        }
        
        return distance
    }
    
    /// Check if two texts are near-duplicates
    static func isDuplicate(_ text1: String, _ text2: String) -> Bool {
        let h1 = compute(text1)
        let h2 = compute(text2)
        return hammingDistance(h1, h2) <= duplicateThreshold
    }
    
    /// Check if a hash is a duplicate of another hash
    static func isDuplicateHash(_ h1: String, _ h2: String) -> Bool {
        return hammingDistance(h1, h2) <= duplicateThreshold
    }
    
    // MARK: - Tokenization
    
    /// Extract canonical tokens from text (lowercase, alphanumeric, stopwords removed)
    private static func canonicalTokenSet(_ text: String) -> Set<String> {
        let lowercased = text.lowercased()
        
        // Split on non-alphanumeric characters
        let tokens = lowercased.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && $0.count > 2 }
        
        // Remove stopwords
        let stopwords: Set<String> = [
            "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for",
            "of", "with", "by", "from", "as", "is", "was", "are", "were", "been",
            "be", "have", "has", "had", "do", "does", "did", "will", "would",
            "could", "should", "may", "might", "must", "shall", "can", "need",
            "this", "that", "these", "those", "it", "its", "they", "them",
            "their", "we", "us", "our", "you", "your", "he", "him", "his",
            "she", "her", "hers", "who", "whom", "what", "which", "when",
            "where", "why", "how", "all", "each", "every", "both", "few",
            "more", "most", "other", "some", "such", "no", "not", "only",
            "same", "so", "than", "too", "very", "just", "also"
        ]
        
        return Set(tokens.filter { !stopwords.contains($0) })
    }
}

// MARK: - Token Overlap

extension SimHash {
    /// Compute token overlap score between query and memory content
    static func tokenOverlap(query: String, content: String) -> Double {
        let queryTokens = canonicalTokenSet(query)
        let contentTokens = canonicalTokenSet(content)
        
        guard !queryTokens.isEmpty else { return 0.0 }
        
        let overlap = queryTokens.intersection(contentTokens).count
        return Double(overlap) / Double(queryTokens.count)
    }
}

