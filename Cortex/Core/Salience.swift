//
//  Salience.swift
//  Cortex
//
//  Memory salience (importance) with decay and reinforcement
//  Ported from OpenMemory's decay.py and hsg.py
//
//  Memories fade over time unless reinforced by retrieval
//

import Foundation

/// Manages memory salience with time-based decay and reinforcement
final class SalienceManager {
    
    // MARK: - Singleton (for convenience)
    
    @MainActor static let shared = SalienceManager()
    
    // MARK: - Constants (from OpenMemory's HYBRID_PARAMS)
    
    /// Time constant for recency decay (days)
    private let tDays: Double = 7.0
    
    /// Maximum time for complete decay (days)
    private let tMaxDays: Double = 60.0
    
    /// Reinforcement boost on retrieval
    private let alphaReinforce: Double = 0.08
    
    /// Salience boost when retrieved
    private let salienceBoost: Double = 0.1
    
    /// Maximum salience value
    private let maxSalience: Double = 1.0
    
    /// Minimum salience before pruning consideration
    private let pruneThreshold: Double = 0.05
    
    init() {}
    
    // MARK: - Decay Calculation
    
    /// Calculate decayed salience based on time passed
    /// - Parameters:
    ///   - sector: Memory sector (affects decay rate)
    ///   - initialSalience: Original salience value
    ///   - lastSeenAt: When memory was last accessed
    ///   - segmentIndex: Optional segment position
    ///   - maxSegment: Optional total segments
    func calculateDecayedSalience(
        sector: MemorySector,
        initialSalience: Double,
        lastSeenAt: Date,
        segmentIndex: Int? = nil,
        maxSegment: Int? = nil
    ) -> Double {
        let daysSince = Date().timeIntervalSince(lastSeenAt) / 86400.0
        var lambda = sector.decayLambda
        
        // Adjust decay rate based on segment position (newer segments decay faster)
        if let segIdx = segmentIndex, let maxSeg = maxSegment, maxSeg > 0 {
            let segRatio = sqrt(Double(segIdx) / Double(maxSeg))
            lambda = lambda * (1.0 - segRatio)
        }
        
        // Exponential decay
        let decayed = initialSalience * exp(-lambda * daysSince)
        
        // Add reinforcement factor (prevents complete decay)
        let reinforcement = alphaReinforce * (1 - exp(-lambda * daysSince))
        
        return min(maxSalience, max(0.0, decayed + reinforcement))
    }
    
    /// Calculate recency score for ranking
    func calculateRecencyScore(lastSeenAt: Date) -> Double {
        let days = Date().timeIntervalSince(lastSeenAt) / 86400.0
        let recency = exp(-days / tDays)
        let timeFactor = 1 - min(1.0, days / tMaxDays)
        return recency * timeFactor
    }
    
    // MARK: - Reinforcement
    
    /// Boost salience when memory is retrieved
    func reinforceOnRetrieval(currentSalience: Double) -> Double {
        let boosted = currentSalience + salienceBoost
        return min(maxSalience, boosted)
    }
    
    /// Boost salience when near-duplicate is found (strengthens existing memory)
    func reinforceOnDuplicate(currentSalience: Double) -> Double {
        let boosted = currentSalience + 0.15
        return min(maxSalience, boosted)
    }
    
    /// Calculate initial salience for new memory
    func calculateInitialSalience(classification: ClassificationResult) -> Double {
        // Base salience + bonus for multi-sector relevance
        let base = 0.4
        let bonus = 0.1 * Double(classification.additional.count)
        return min(maxSalience, max(0.0, base + bonus))
    }
    
    // MARK: - Pruning
    
    /// Check if memory should be pruned (too old, low salience)
    func shouldPrune(salience: Double, lastSeenAt: Date) -> Bool {
        let daysSince = Date().timeIntervalSince(lastSeenAt) / 86400.0
        
        // Don't prune recent memories
        if daysSince < 7 { return false }
        
        // Prune if salience is below threshold and old
        return salience < pruneThreshold && daysSince > 30
    }
    
    // MARK: - Hybrid Scoring
    
    /// Boosted similarity using sigmoid-like transformation
    func boostedSimilarity(_ similarity: Double, tau: Double = 3.0) -> Double {
        return 1 - exp(-tau * similarity)
    }
    
    /// Compute hybrid score for retrieval ranking
    func computeHybridScore(
        similarity: Double,
        tokenOverlap: Double,
        waypointWeight: Double,
        recencyScore: Double,
        tagMatch: Double = 0,
        keywordScore: Double = 0
    ) -> Double {
        let weights = ScoringWeights.default
        
        let boosted = boostedSimilarity(similarity)
        
        let raw = weights.similarity * boosted +
                  weights.overlap * tokenOverlap +
                  weights.waypoint * waypointWeight +
                  weights.recency * recencyScore +
                  weights.tagMatch * tagMatch +
                  keywordScore
        
        // Sigmoid normalization
        return 1.0 / (1.0 + exp(-raw))
    }
}

// MARK: - Scoring Weights

struct ScoringWeights {
    let similarity: Double
    let overlap: Double
    let waypoint: Double
    let recency: Double
    let tagMatch: Double
    
    static let `default` = ScoringWeights(
        similarity: 0.35,
        overlap: 0.20,
        waypoint: 0.15,
        recency: 0.10,
        tagMatch: 0.20
    )
}

// MARK: - Sector Relationships

/// Cross-sector relationship weights for scoring
struct SectorRelationships {
    /// Get relationship weight between two sectors
    static func weight(from source: MemorySector, to target: MemorySector) -> Double {
        if source == target { return 1.0 }
        
        let relationships: [MemorySector: [MemorySector: Double]] = [
            .semantic: [.procedural: 0.8, .episodic: 0.6, .reflective: 0.7, .emotional: 0.4],
            .procedural: [.semantic: 0.8, .episodic: 0.6, .reflective: 0.6, .emotional: 0.3],
            .episodic: [.reflective: 0.8, .semantic: 0.6, .procedural: 0.6, .emotional: 0.7],
            .reflective: [.episodic: 0.8, .semantic: 0.7, .procedural: 0.6, .emotional: 0.6],
            .emotional: [.episodic: 0.7, .reflective: 0.6, .semantic: 0.4, .procedural: 0.3],
        ]
        
        return relationships[source]?[target] ?? 0.3
    }
}

