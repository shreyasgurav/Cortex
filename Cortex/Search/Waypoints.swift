//
//  Waypoints.swift
//  Cortex
//
//  Memory linking system - creates connections between related memories
//  Ported from OpenMemory's waypoint logic in hsg.py
//
//  Waypoints enable:
//  - Graph traversal for memory retrieval
//  - Associative memory (related memories surface together)
//  - Context expansion during search
//

import Foundation

/// A connection between two memories
struct Waypoint: Codable, Identifiable {
    let id: String
    let sourceId: String      // Source memory ID
    let targetId: String      // Target memory ID
    let weight: Double        // Connection strength (0-1)
    let createdAt: Date
    var updatedAt: Date
    
    init(sourceId: String, targetId: String, weight: Double) {
        self.id = UUID().uuidString
        self.sourceId = sourceId
        self.targetId = targetId
        self.weight = min(1.0, max(0.0, weight))
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

/// Manages memory connections (waypoints)
final class WaypointManager {
    
    // MARK: - Constants
    
    /// Minimum similarity to create a waypoint
    private let minSimilarityThreshold: Double = 0.5
    
    /// Maximum waypoints per memory
    private let maxWaypointsPerMemory: Int = 10
    
    /// Weight decay for graph expansion
    private let expansionDecay: Double = 0.8
    
    /// Minimum weight for expansion
    private let minExpansionWeight: Double = 0.1
    
    // MARK: - Waypoint Creation
    
    /// Find the best waypoint target for a new memory
    /// Returns (targetId, similarity) or nil if no good match
    func findBestWaypointTarget(
        newMemoryId: String,
        newEmbedding: [Double],
        existingMemories: [(id: String, embedding: [Double])]
    ) -> (targetId: String, similarity: Double)? {
        var bestTarget: String?
        var bestSimilarity: Double = -1.0
        
        for (memId, embedding) in existingMemories {
            guard memId != newMemoryId else { continue }
            
            let similarity = cosineSimilarity(newEmbedding, embedding)
            if similarity > bestSimilarity {
                bestSimilarity = similarity
                bestTarget = memId
            }
        }
        
        guard let target = bestTarget, bestSimilarity >= minSimilarityThreshold else {
            return nil
        }
        
        return (target, bestSimilarity)
    }
    
    /// Create a waypoint between two memories
    func createWaypoint(sourceId: String, targetId: String, weight: Double) -> Waypoint {
        return Waypoint(sourceId: sourceId, targetId: targetId, weight: weight)
    }
    
    // MARK: - Graph Expansion
    
    /// Expand search results via waypoints (associative retrieval)
    /// Returns additional memory IDs with their expansion weights
    func expandViaWaypoints(
        seedIds: [String],
        waypoints: [Waypoint],
        maxExpansion: Int = 10
    ) -> [(id: String, weight: Double, path: [String])] {
        var expanded: [(id: String, weight: Double, path: [String])] = []
        var visited = Set(seedIds)
        var queue: [(id: String, weight: Double, path: [String])] = seedIds.map { (id: $0, weight: 1.0, path: [$0]) }
        var count = 0
        
        while !queue.isEmpty && count < maxExpansion {
            let current = queue.removeFirst()
            
            // Find neighbors via waypoints
            let neighbors = waypoints.filter { $0.sourceId == current.id }
            
            for waypoint in neighbors {
                let targetId = waypoint.targetId
                
                // Skip already visited
                guard !visited.contains(targetId) else { continue }
                
                // Calculate expanded weight
                let expandedWeight = current.weight * waypoint.weight * expansionDecay
                
                // Skip if weight too low
                guard expandedWeight >= minExpansionWeight else { continue }
                
                let newPath = current.path + [targetId]
                let item = (id: targetId, weight: expandedWeight, path: newPath)
                
                expanded.append(item)
                visited.insert(targetId)
                queue.append(item)
                count += 1
            }
        }
        
        return expanded
    }
    
    // MARK: - Reinforcement
    
    /// Reinforce waypoints when memories are retrieved together
    func reinforceWaypoint(_ waypoint: inout Waypoint, boost: Double = 0.05) {
        let newWeight = min(1.0, waypoint.weight + boost)
        waypoint = Waypoint(
            sourceId: waypoint.sourceId,
            targetId: waypoint.targetId,
            weight: newWeight
        )
    }
    
    /// Propagate reinforcement to linked memories
    func propagateReinforcement(
        sourceId: String,
        sourceSalience: Double,
        waypoints: [Waypoint],
        currentSaliences: [String: Double]
    ) -> [(memoryId: String, newSalience: Double)] {
        var updates: [(memoryId: String, newSalience: Double)] = []
        
        let linkedWaypoints = waypoints.filter { $0.sourceId == sourceId }
        
        for waypoint in linkedWaypoints {
            guard let currentSalience = currentSaliences[waypoint.targetId] else { continue }
            
            // Calculate context boost based on source salience difference
            let gamma: Double = 0.2
            let boost = gamma * (sourceSalience - currentSalience) * waypoint.weight
            let newSalience = min(1.0, max(0.0, currentSalience + boost))
            
            updates.append((memoryId: waypoint.targetId, newSalience: newSalience))
        }
        
        return updates
    }
    
    // MARK: - Helpers
    
    private func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        
        var dot: Double = 0
        var normA: Double = 0
        var normB: Double = 0
        
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        
        let denom = sqrt(normA) * sqrt(normB)
        return denom == 0 ? 0 : dot / denom
    }
}

