//
//  MemoryGraphView.swift
//  Cortex
//
//  Clean, stable memory graph visualization
//  Follows Supermemory principles: calm, informational, minimal motion
//

import SwiftUI
import Combine

// MARK: - Graph Node

struct GraphNode: Identifiable, Equatable {
    let id: String
    let content: String
    let sector: String?
    let salience: Double
    var position: CGPoint
    var velocity: CGPoint = .zero
    
    var color: Color {
        switch sector?.lowercased() {
        case "semantic": return Color(red: 0.36, green: 0.52, blue: 0.85)
        case "episodic": return Color(red: 0.65, green: 0.45, blue: 0.78)
        case "procedural": return Color(red: 0.42, green: 0.72, blue: 0.55)
        case "emotional": return Color(red: 0.85, green: 0.52, blue: 0.60)
        case "reflective": return Color(red: 0.90, green: 0.65, blue: 0.40)
        default: return Color(red: 0.55, green: 0.55, blue: 0.60)
        }
    }
    
    // Reduced size variance: 10-20 range
    var radius: CGFloat {
        CGFloat(10 + salience * 10)
    }
    
    var preview: String {
        content.count > 50 ? String(content.prefix(50)) + "..." : content
    }
    
    static func == (lhs: GraphNode, rhs: GraphNode) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Graph Edge

struct GraphEdge: Identifiable {
    let id: String
    let sourceId: String
    let targetId: String
    let weight: Double
}

// MARK: - Sector Centers (for clustering)

struct SectorLayout {
    static func centerFor(sector: String?, in size: CGSize) -> CGPoint {
        let cx = size.width / 2
        let cy = size.height / 2
        let radius = min(size.width, size.height) * 0.25
        
        switch sector?.lowercased() {
        case "semantic":   return CGPoint(x: cx, y: cy - radius)
        case "episodic":   return CGPoint(x: cx + radius * 0.95, y: cy - radius * 0.31)
        case "procedural": return CGPoint(x: cx + radius * 0.59, y: cy + radius * 0.81)
        case "emotional":  return CGPoint(x: cx - radius * 0.59, y: cy + radius * 0.81)
        case "reflective": return CGPoint(x: cx - radius * 0.95, y: cy - radius * 0.31)
        default:           return CGPoint(x: cx, y: cy)
        }
    }
}

// MARK: - Graph Simulation (Calmer Physics)

@MainActor
class GraphSimulation: ObservableObject {
    @Published var nodes: [GraphNode] = []
    @Published var edges: [GraphEdge] = []
    @Published var selectedNodeId: String?
    @Published var isSimulating: Bool = false
    
    private var displayLink: Timer?
    private var canvasSize: CGSize = CGSize(width: 800, height: 600)
    private var iterationCount = 0
    private let maxIterations = 150
    
    // Calmer physics parameters
    private let repulsionStrength: CGFloat = 2500
    private let attractionStrength: CGFloat = 0.03
    private let sectorPull: CGFloat = 0.04
    private let damping: CGFloat = 0.8
    private let minDistance: CGFloat = 60
    
    var selectedNode: GraphNode? {
        nodes.first { $0.id == selectedNodeId }
    }
    
    func loadData(memories: [ExtractedMemory], waypoints: [Waypoint], size: CGSize) {
        self.canvasSize = size
        
        // CRITICAL: Only show top 25 by salience
        let topMemories = memories
            .sorted { $0.salience > $1.salience }
            .prefix(25)
        
        let memoryIds = Set(topMemories.map { $0.id })
        
        // Create nodes with sector-based initial positions
        nodes = topMemories.map { memory in
            let sectorCenter = SectorLayout.centerFor(sector: memory.sector, in: size)
            let jitter = CGPoint(
                x: CGFloat.random(in: -40...40),
                y: CGFloat.random(in: -40...40)
            )
            return GraphNode(
                id: memory.id,
                content: memory.content,
                sector: memory.sector,
                salience: memory.salience,
                position: CGPoint(x: sectorCenter.x + jitter.x, y: sectorCenter.y + jitter.y)
            )
        }
        
        // Only create edges between visible nodes
        edges = waypoints.compactMap { waypoint in
            guard memoryIds.contains(waypoint.sourceId),
                  memoryIds.contains(waypoint.targetId),
                  waypoint.sourceId != waypoint.targetId else {
                return nil
            }
            return GraphEdge(
                id: waypoint.id,
                sourceId: waypoint.sourceId,
                targetId: waypoint.targetId,
                weight: waypoint.weight
            )
        }
        
        // Run simulation briefly then stop
        iterationCount = 0
        startSimulation()
    }
    
    func startSimulation() {
        guard !nodes.isEmpty else { return }
        isSimulating = true
        iterationCount = 0
        
        displayLink?.invalidate()
        displayLink = Timer.scheduledTimer(withTimeInterval: 1/60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.step()
            }
        }
    }
    
    func stopSimulation() {
        isSimulating = false
        displayLink?.invalidate()
        displayLink = nil
    }
    
    private func step() {
        guard isSimulating, !nodes.isEmpty else { return }
        
        iterationCount += 1
        
        var forces: [String: CGPoint] = [:]
        for node in nodes {
            forces[node.id] = .zero
        }
        
        // Repulsion between nodes
        for i in 0..<nodes.count {
            for j in (i+1)..<nodes.count {
                let nodeA = nodes[i]
                let nodeB = nodes[j]
                
                let dx = nodeB.position.x - nodeA.position.x
                let dy = nodeB.position.y - nodeA.position.y
                let distance = max(sqrt(dx * dx + dy * dy), minDistance)
                
                let force = repulsionStrength / (distance * distance)
                let fx = force * dx / distance
                let fy = force * dy / distance
                
                forces[nodeA.id]!.x -= fx
                forces[nodeA.id]!.y -= fy
                forces[nodeB.id]!.x += fx
                forces[nodeB.id]!.y += fy
            }
        }
        
        // Attraction along edges
        for edge in edges {
            guard let sourceIdx = nodes.firstIndex(where: { $0.id == edge.sourceId }),
                  let targetIdx = nodes.firstIndex(where: { $0.id == edge.targetId }) else {
                continue
            }
            
            let source = nodes[sourceIdx]
            let target = nodes[targetIdx]
            
            let dx = target.position.x - source.position.x
            let dy = target.position.y - source.position.y
            let distance = max(sqrt(dx * dx + dy * dy), 1)
            
            let strength = attractionStrength * CGFloat(edge.weight) * distance
            let fx = strength * dx / distance
            let fy = strength * dy / distance
            
            forces[source.id]!.x += fx
            forces[source.id]!.y += fy
            forces[target.id]!.x -= fx
            forces[target.id]!.y -= fy
        }
        
        // Pull toward sector centers
        for node in nodes {
            let sectorCenter = SectorLayout.centerFor(sector: node.sector, in: canvasSize)
            let dx = sectorCenter.x - node.position.x
            let dy = sectorCenter.y - node.position.y
            forces[node.id]!.x += dx * sectorPull
            forces[node.id]!.y += dy * sectorPull
        }
        
        // Apply forces
        var maxVelocity: CGFloat = 0
        
        for i in 0..<nodes.count {
            guard let force = forces[nodes[i].id] else { continue }
            
            nodes[i].velocity.x = (nodes[i].velocity.x + force.x) * damping
            nodes[i].velocity.y = (nodes[i].velocity.y + force.y) * damping
            
            let velocity = sqrt(nodes[i].velocity.x * nodes[i].velocity.x + nodes[i].velocity.y * nodes[i].velocity.y)
            maxVelocity = max(maxVelocity, velocity)
            
            // Limit velocity
            if velocity > 30 {
                nodes[i].velocity.x = nodes[i].velocity.x / velocity * 30
                nodes[i].velocity.y = nodes[i].velocity.y / velocity * 30
            }
            
            nodes[i].position.x += nodes[i].velocity.x
            nodes[i].position.y += nodes[i].velocity.y
            
            // Keep within bounds
            let margin: CGFloat = 40
            nodes[i].position.x = max(margin, min(canvasSize.width - margin, nodes[i].position.x))
            nodes[i].position.y = max(margin, min(canvasSize.height - margin, nodes[i].position.y))
        }
        
        // Stop early: velocity < 2 OR max iterations reached
        if maxVelocity < 2 || iterationCount > maxIterations {
            stopSimulation()
        }
    }
    
    func moveNode(_ nodeId: String, to position: CGPoint) {
        guard let index = nodes.firstIndex(where: { $0.id == nodeId }) else { return }
        nodes[index].position = position
        nodes[index].velocity = .zero
    }
    
    func selectNode(_ nodeId: String?) {
        selectedNodeId = nodeId
    }
}

// MARK: - Memory Graph View

struct MemoryGraphView: View {
    @ObservedObject var appState: AppState
    @StateObject private var simulation = GraphSimulation()
    @State private var hoveredNodeId: String?
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var isDraggingNode = false
    @State private var optionKeyPressed = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color(nsColor: .textBackgroundColor)
                    .onTapGesture {
                        simulation.selectNode(nil)
                    }
                
                if simulation.nodes.isEmpty {
                    emptyState
                } else {
                    graphContent(size: geometry.size)
                    controlsOverlay
                }
            }
            .onAppear {
                loadGraphData(size: geometry.size)
            }
            .onChange(of: appState.extractedMemories) { _, _ in
                loadGraphData(size: geometry.size)
            }
        }
    }
    
    // MARK: - Graph Content
    
    @ViewBuilder
    private func graphContent(size: CGSize) -> some View {
        // Canvas for edges and nodes
        Canvas { context, canvasSize in
            let transform = CGAffineTransform(translationX: offset.width, y: offset.height)
                .scaledBy(x: scale, y: scale)
            
            // Draw edges (very faint by default)
            for edge in simulation.edges {
                guard let source = simulation.nodes.first(where: { $0.id == edge.sourceId }),
                      let target = simulation.nodes.first(where: { $0.id == edge.targetId }) else {
                    continue
                }
                
                let sourcePoint = source.position.applying(transform)
                let targetPoint = target.position.applying(transform)
                
                var path = Path()
                path.move(to: sourcePoint)
                path.addLine(to: targetPoint)
                
                // Edges only visible when hovering/selecting connected nodes
                let isHighlighted = hoveredNodeId == source.id || hoveredNodeId == target.id ||
                                   simulation.selectedNodeId == source.id || simulation.selectedNodeId == target.id
                
                let opacity = isHighlighted ? 0.5 : 0.08
                
                context.stroke(
                    path,
                    with: .color(Color.secondary.opacity(opacity)),
                    lineWidth: 1.5
                )
            }
            
            // Draw nodes
            for node in simulation.nodes {
                let position = node.position.applying(transform)
                let radius = node.radius * scale
                
                let rect = CGRect(
                    x: position.x - radius,
                    y: position.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
                
                let isSelected = simulation.selectedNodeId == node.id
                let isHovered = hoveredNodeId == node.id
                
                // Node fill
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(node.color.opacity(isSelected ? 1.0 : 0.85))
                )
                
                // Selection ring
                if isSelected {
                    context.stroke(
                        Path(ellipseIn: rect.insetBy(dx: -3, dy: -3)),
                        with: .color(.white),
                        lineWidth: 2
                    )
                } else if isHovered {
                    context.stroke(
                        Path(ellipseIn: rect.insetBy(dx: -2, dy: -2)),
                        with: .color(.white.opacity(0.6)),
                        lineWidth: 1.5
                    )
                }
            }
        }
        .gesture(panGesture)
        .gesture(zoomGesture)
        
        // Invisible hit targets for nodes
        ForEach(simulation.nodes) { node in
            nodeHitTarget(for: node)
        }
        
        // Selected node detail panel
        if let selected = simulation.selectedNode {
            selectedNodePanel(node: selected)
        }
    }
    
    // MARK: - Node Hit Target
    
    @ViewBuilder
    private func nodeHitTarget(for node: GraphNode) -> some View {
        let position = CGPoint(
            x: node.position.x * scale + offset.width,
            y: node.position.y * scale + offset.height
        )
        let hitSize = max(node.radius * scale * 2, 30)
        
        Circle()
            .fill(Color.clear)
            .frame(width: hitSize, height: hitSize)
            .position(position)
            .contentShape(Circle())
            .onHover { isHovering in
                hoveredNodeId = isHovering ? node.id : nil
            }
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.15)) {
                    simulation.selectNode(simulation.selectedNodeId == node.id ? nil : node.id)
                }
            }
            .gesture(nodeDragGesture(for: node))
    }
    
    // MARK: - Gestures
    
    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard !isDraggingNode else { return }
                offset = CGSize(
                    width: offset.width + value.translation.width * 0.3,
                    height: offset.height + value.translation.height * 0.3
                )
            }
    }
    
    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = max(0.5, min(2.0, value))
            }
    }
    
    private func nodeDragGesture(for node: GraphNode) -> some Gesture {
        DragGesture()
            .onChanged { value in
                isDraggingNode = true
                let newPosition = CGPoint(
                    x: (value.location.x - offset.width) / scale,
                    y: (value.location.y - offset.height) / scale
                )
                simulation.moveNode(node.id, to: newPosition)
            }
            .onEnded { _ in
                isDraggingNode = false
            }
    }
    
    // MARK: - Selected Node Panel
    
    @ViewBuilder
    private func selectedNodePanel(node: GraphNode) -> some View {
        VStack {
            Spacer()
            
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(node.color)
                    .frame(width: 14, height: 14)
                    .padding(.top, 3)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(node.content)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    HStack(spacing: 16) {
                        if let sector = node.sector {
                            Label(sector.capitalized, systemImage: "tag.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Label("\(Int(node.salience * 100))%", systemImage: "star.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Button {
                    withAnimation { simulation.selectNode(nil) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .frame(maxWidth: 380)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    
    // MARK: - Controls Overlay
    
    private var controlsOverlay: some View {
        VStack {
            HStack(alignment: .top) {
                // Legend
                legendView
                
                Spacer()
                
                // Stats & controls
                HStack(spacing: 12) {
                    Text("\(simulation.nodes.count) nodes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Divider().frame(height: 12)
                    
                    Button {
                        withAnimation { resetView() }
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Reset view")
                }
                .padding(8)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.9))
                .cornerRadius(8)
            }
            .padding(16)
            
            Spacer()
        }
    }
    
    // MARK: - Legend
    
    private var legendView: some View {
        HStack(spacing: 10) {
            ForEach(sectorColors, id: \.0) { sector, color in
                HStack(spacing: 4) {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                    Text(sector)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.9))
        .cornerRadius(6)
    }
    
    private var sectorColors: [(String, Color)] {
        [
            ("Semantic", Color(red: 0.36, green: 0.52, blue: 0.85)),
            ("Episodic", Color(red: 0.65, green: 0.45, blue: 0.78)),
            ("Procedural", Color(red: 0.42, green: 0.72, blue: 0.55)),
            ("Emotional", Color(red: 0.85, green: 0.52, blue: 0.60)),
            ("Reflective", Color(red: 0.90, green: 0.65, blue: 0.40))
        ]
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "circle.grid.cross")
                .font(.system(size: 36))
                .foregroundColor(.secondary.opacity(0.3))
            Text("No memories yet")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
            Text("Your memory graph will appear here")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
        }
    }
    
    // MARK: - Helpers
    
    private func loadGraphData(size: CGSize) {
        Task {
            let waypoints = await loadWaypoints()
            await MainActor.run {
                simulation.loadData(
                    memories: appState.extractedMemories,
                    waypoints: waypoints,
                    size: size
                )
            }
        }
    }
    
    private func loadWaypoints() async -> [Waypoint] {
        do {
            let store = try ExtractedMemoryStore()
            return try await store.fetchAllWaypoints()
        } catch {
            return []
        }
    }
    
    private func resetView() {
        scale = 1.0
        offset = .zero
        simulation.startSimulation()
    }
}
