//
//  MemoryGraphView.swift
//  Cortex
//
//  Interactive force-directed graph visualization of memory connections
//  Memories are nodes, waypoints are edges linking similar memories
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
    
    // Color based on sector
    var color: Color {
        switch sector?.lowercased() {
        case "semantic": return .blue
        case "episodic": return .purple
        case "procedural": return .green
        case "emotional": return .pink
        case "reflective": return .orange
        default: return .gray
        }
    }
    
    // Node size based on salience (importance)
    var radius: CGFloat {
        CGFloat(12 + salience * 18) // 12-30 range
    }
    
    // Preview text (first 40 chars)
    var preview: String {
        content.count > 40 ? String(content.prefix(40)) + "..." : content
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
    
    // Line width based on connection strength
    var strokeWidth: CGFloat {
        CGFloat(1 + weight * 3) // 1-4 range
    }
    
    // Opacity based on weight
    var opacity: Double {
        0.2 + weight * 0.6 // 0.2-0.8 range
    }
}

// MARK: - Force-Directed Graph Simulation

@MainActor
class GraphSimulation: ObservableObject {
    @Published var nodes: [GraphNode] = []
    @Published var edges: [GraphEdge] = []
    @Published var selectedNode: GraphNode?
    @Published var isSimulating: Bool = true
    
    private var displayLink: Timer?
    private let canvasSize: CGSize
    
    // Physics parameters
    private let repulsionStrength: CGFloat = 5000
    private let attractionStrength: CGFloat = 0.01
    private let centerPull: CGFloat = 0.01
    private let damping: CGFloat = 0.9
    private let minDistance: CGFloat = 50
    
    init(canvasSize: CGSize = CGSize(width: 800, height: 600)) {
        self.canvasSize = canvasSize
    }
    
    func loadData(memories: [ExtractedMemory], waypoints: [Waypoint]) {
        // Create nodes from memories
        nodes = memories.map { memory in
            GraphNode(
                id: memory.id,
                content: memory.content,
                sector: memory.sector,
                salience: memory.salience,
                position: randomPosition()
            )
        }
        
        // Create edges from waypoints
        edges = waypoints.compactMap { waypoint in
            // Only create edge if both nodes exist
            guard nodes.contains(where: { $0.id == waypoint.sourceId }),
                  nodes.contains(where: { $0.id == waypoint.targetId }),
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
        
        startSimulation()
    }
    
    private func randomPosition() -> CGPoint {
        CGPoint(
            x: CGFloat.random(in: 100...(canvasSize.width - 100)),
            y: CGFloat.random(in: 100...(canvasSize.height - 100))
        )
    }
    
    func startSimulation() {
        isSimulating = true
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
        
        var forces: [String: CGPoint] = [:]
        
        // Initialize forces
        for node in nodes {
            forces[node.id] = .zero
        }
        
        // Repulsion between all nodes (Coulomb's law)
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
        
        // Attraction along edges (Hooke's law)
        for edge in edges {
            guard let sourceIdx = nodes.firstIndex(where: { $0.id == edge.sourceId }),
                  let targetIdx = nodes.firstIndex(where: { $0.id == edge.targetId }) else {
                continue
            }
            
            let source = nodes[sourceIdx]
            let target = nodes[targetIdx]
            
            let dx = target.position.x - source.position.x
            let dy = target.position.y - source.position.y
            let distance = sqrt(dx * dx + dy * dy)
            
            let strength = attractionStrength * CGFloat(edge.weight) * distance
            let fx = strength * dx / max(distance, 1)
            let fy = strength * dy / max(distance, 1)
            
            forces[source.id]!.x += fx
            forces[source.id]!.y += fy
            forces[target.id]!.x -= fx
            forces[target.id]!.y -= fy
        }
        
        // Center pull (keep graph centered)
        let centerX = canvasSize.width / 2
        let centerY = canvasSize.height / 2
        
        for node in nodes {
            let dx = centerX - node.position.x
            let dy = centerY - node.position.y
            forces[node.id]!.x += dx * centerPull
            forces[node.id]!.y += dy * centerPull
        }
        
        // Apply forces and update positions
        var maxVelocity: CGFloat = 0
        
        for i in 0..<nodes.count {
            guard let force = forces[nodes[i].id] else { continue }
            
            // Update velocity
            nodes[i].velocity.x = (nodes[i].velocity.x + force.x) * damping
            nodes[i].velocity.y = (nodes[i].velocity.y + force.y) * damping
            
            // Limit velocity
            let velocity = sqrt(nodes[i].velocity.x * nodes[i].velocity.x + nodes[i].velocity.y * nodes[i].velocity.y)
            maxVelocity = max(maxVelocity, velocity)
            
            if velocity > 50 {
                nodes[i].velocity.x = nodes[i].velocity.x / velocity * 50
                nodes[i].velocity.y = nodes[i].velocity.y / velocity * 50
            }
            
            // Update position
            nodes[i].position.x += nodes[i].velocity.x
            nodes[i].position.y += nodes[i].velocity.y
            
            // Keep within bounds
            let margin: CGFloat = 30
            nodes[i].position.x = max(margin, min(canvasSize.width - margin, nodes[i].position.x))
            nodes[i].position.y = max(margin, min(canvasSize.height - margin, nodes[i].position.y))
        }
        
        // Stop simulation when settled
        if maxVelocity < 0.5 {
            stopSimulation()
        }
    }
    
    func dragNode(_ nodeId: String, to position: CGPoint) {
        guard let index = nodes.firstIndex(where: { $0.id == nodeId }) else { return }
        nodes[index].position = position
        nodes[index].velocity = .zero
    }
    
    func selectNode(_ nodeId: String?) {
        selectedNode = nodeId.flatMap { id in nodes.first(where: { $0.id == id }) }
    }
}

// MARK: - Memory Graph View

struct MemoryGraphView: View {
    @ObservedObject var appState: AppState
    @StateObject private var simulation = GraphSimulation()
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var draggedNode: String?
    @State private var hoveredNode: String?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color(nsColor: .textBackgroundColor)
                
                // Graph Canvas
                Canvas { context, size in
                    let transform = CGAffineTransform(translationX: offset.width, y: offset.height)
                        .scaledBy(x: scale, y: scale)
                    
                    // Draw edges
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
                        
                        let isHighlighted = hoveredNode == source.id || hoveredNode == target.id
                        let edgeColor = isHighlighted ? Color.accentColor : Color.secondary
                        
                        context.stroke(
                            path,
                            with: .color(edgeColor.opacity(edge.opacity)),
                            lineWidth: edge.strokeWidth * scale
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
                        
                        // Node background
                        let isSelected = simulation.selectedNode?.id == node.id
                        let isHovered = hoveredNode == node.id
                        
                        var nodeColor = node.color
                        if isSelected {
                            nodeColor = .accentColor
                        } else if isHovered {
                            nodeColor = node.color.opacity(0.8)
                        }
                        
                        context.fill(
                            Path(ellipseIn: rect),
                            with: .color(nodeColor)
                        )
                        
                        // Node border
                        if isSelected || isHovered {
                            context.stroke(
                                Path(ellipseIn: rect),
                                with: .color(.white),
                                lineWidth: 2 * scale
                            )
                        }
                    }
                }
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = max(0.3, min(3.0, value))
                        }
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if draggedNode == nil {
                                // Pan the view
                                offset = CGSize(
                                    width: offset.width + value.translation.width,
                                    height: offset.height + value.translation.height
                                )
                            }
                        }
                )
                
                // Interactive node overlays
                ForEach(simulation.nodes) { node in
                    NodeOverlay(
                        node: node,
                        scale: scale,
                        offset: offset,
                        isHovered: hoveredNode == node.id,
                        isSelected: simulation.selectedNode?.id == node.id,
                        onHover: { isHovering in
                            hoveredNode = isHovering ? node.id : nil
                        },
                        onTap: {
                            simulation.selectNode(node.id)
                        },
                        onDrag: { newPosition in
                            simulation.dragNode(node.id, to: newPosition)
                        }
                    )
                }
                
                // Controls overlay
                VStack {
                    HStack {
                        // Legend
                        LegendView()
                        
                        Spacer()
                        
                        // Zoom controls
                        HStack(spacing: 8) {
                            Button(action: { scale = max(0.3, scale - 0.2) }) {
                                Image(systemName: "minus.magnifyingglass")
                            }
                            .buttonStyle(.bordered)
                            
                            Text("\(Int(scale * 100))%")
                                .font(.caption)
                                .frame(width: 50)
                            
                            Button(action: { scale = min(3.0, scale + 0.2) }) {
                                Image(systemName: "plus.magnifyingglass")
                            }
                            .buttonStyle(.bordered)
                            
                            Button(action: { resetView() }) {
                                Image(systemName: "arrow.counterclockwise")
                            }
                            .buttonStyle(.bordered)
                            .help("Reset View")
                            
                            Button(action: { simulation.startSimulation() }) {
                                Image(systemName: simulation.isSimulating ? "pause.fill" : "play.fill")
                            }
                            .buttonStyle(.bordered)
                            .help(simulation.isSimulating ? "Pause" : "Simulate")
                        }
                    }
                    .padding()
                    
                    Spacer()
                    
                    // Selected node info
                    if let selectedNode = simulation.selectedNode {
                        SelectedNodeInfoView(node: selectedNode, onClose: {
                            simulation.selectNode(nil)
                        })
                        .padding()
                    }
                }
                
                // Empty state
                if simulation.nodes.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "circle.grid.cross")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary.opacity(0.3))
                        Text("No memories to visualize")
                            .foregroundColor(.secondary)
                        Text("Memories will appear here as connected nodes")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
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
    
    private func loadGraphData(size: CGSize) {
        Task {
            // Load waypoints from store
            let waypoints = await loadWaypoints()
            
            // Update simulation canvas size
            let simulation = GraphSimulation(canvasSize: size)
            simulation.loadData(memories: appState.extractedMemories, waypoints: waypoints)
            
            await MainActor.run {
                self.simulation.nodes = simulation.nodes
                self.simulation.edges = simulation.edges
                self.simulation.startSimulation()
            }
        }
    }
    
    private func loadWaypoints() async -> [Waypoint] {
        // Try to load from store
        do {
            let store = try ExtractedMemoryStore()
            return try await store.fetchAllWaypoints()
        } catch {
            print("[MemoryGraph] Failed to load waypoints: \(error)")
            return []
        }
    }
    
    private func resetView() {
        withAnimation {
            scale = 1.0
            offset = .zero
        }
        simulation.startSimulation()
    }
}

// MARK: - Node Overlay (for interaction)

struct NodeOverlay: View {
    let node: GraphNode
    let scale: CGFloat
    let offset: CGSize
    let isHovered: Bool
    let isSelected: Bool
    let onHover: (Bool) -> Void
    let onTap: () -> Void
    let onDrag: (CGPoint) -> Void
    
    var body: some View {
        let position = CGPoint(
            x: node.position.x * scale + offset.width,
            y: node.position.y * scale + offset.height
        )
        let radius = node.radius * scale
        
        Circle()
            .fill(Color.clear)
            .frame(width: radius * 2, height: radius * 2)
            .position(position)
            .onHover { onHover($0) }
            .onTapGesture { onTap() }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let newPosition = CGPoint(
                            x: (value.location.x - offset.width) / scale,
                            y: (value.location.y - offset.height) / scale
                        )
                        onDrag(newPosition)
                    }
            )
            .overlay(
                // Tooltip on hover
                Group {
                    if isHovered && !isSelected {
                        Text(node.preview)
                            .font(.caption)
                            .padding(6)
                            .background(Color(nsColor: .windowBackgroundColor))
                            .cornerRadius(6)
                            .shadow(radius: 2)
                            .offset(y: -radius - 20)
                    }
                }
                .position(position)
            )
    }
}

// MARK: - Legend View

struct LegendView: View {
    var body: some View {
        HStack(spacing: 12) {
            ForEach(sectorItems, id: \.0) { item in
                HStack(spacing: 4) {
                    Circle()
                        .fill(item.1)
                        .frame(width: 10, height: 10)
                    Text(item.0)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(8)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.9))
        .cornerRadius(8)
    }
    
    private var sectorItems: [(String, Color)] {
        [
            ("Semantic", .blue),
            ("Episodic", .purple),
            ("Procedural", .green),
            ("Emotional", .pink),
            ("Reflective", .orange)
        ]
    }
}

// MARK: - Selected Node Info View

struct SelectedNodeInfoView: View {
    let node: GraphNode
    let onClose: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(node.color)
                .frame(width: 20, height: 20)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(node.content)
                    .font(.system(size: 13))
                    .lineLimit(3)
                
                HStack(spacing: 12) {
                    if let sector = node.sector {
                        Label(sector.capitalized, systemImage: "tag")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Label(String(format: "%.0f%% importance", node.salience * 100), systemImage: "star")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .frame(maxWidth: 400)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 4)
    }
}


