import SwiftUI
import AppKit

/// The whole brain as a living constellation: notes are nodes, [[wikilinks]] are
/// edges, colors are folders. Force-directed layout in a Canvas — drag to arrange,
/// hover to focus a neighborhood, click to open the note.
final class GraphModel {
    struct GNode {
        let id: String
        let title: String
        let group: Int
        var degree: Int = 0
        var pos: CGPoint
        var vel: CGVector = .zero
    }

    var nodes: [GNode] = []
    var edges: [(a: Int, b: Int)] = []
    var adjacency: [Set<Int>] = []
    var groups: [String] = []
    var settled = false
    private var calmFrames = 0
    private var builtFor: Int = -1

    func rebuild(notes: [Note]) {
        let hash = notes.count &* 31 &+ notes.reduce(0) { $0 &+ $1.id.hashValue }
        guard hash != builtFor else { return }
        builtFor = hash

        let old = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.pos) })
        let groupKeys = Set(notes.map { $0.topFolder.isEmpty ? $0.rootName : $0.topFolder })
        groups = groupKeys.sorted()
        let groupIndex = Dictionary(uniqueKeysWithValues: groups.enumerated().map { ($1, $0) })

        nodes = notes.enumerated().map { i, note in
            let angle = 2.399963 * Double(i)   // golden-angle spiral: stable, deterministic
            let radius = 0.85 * sqrt(Double(i + 1) / Double(max(notes.count, 1)))
            let start = CGPoint(x: radius * cos(angle), y: radius * sin(angle))
            return GNode(
                id: note.id,
                title: note.title,
                group: groupIndex[note.topFolder.isEmpty ? note.rootName : note.topFolder] ?? 0,
                pos: old[note.id] ?? start
            )
        }
        let indexByTitle = Dictionary(notes.enumerated().map { ($1.title.lowercased(), $0) },
                                      uniquingKeysWith: { a, _ in a })
        var seen = Set<Int>()
        edges = []
        for (i, note) in notes.enumerated() {
            for target in note.links {
                guard let j = indexByTitle[target.lowercased()], j != i else { continue }
                let key = i < j ? i * 100_000 + j : j * 100_000 + i
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                edges.append((i, j))
            }
        }
        adjacency = Array(repeating: Set<Int>(), count: nodes.count)
        for e in edges {
            adjacency[e.a].insert(e.b)
            adjacency[e.b].insert(e.a)
            nodes[e.a].degree += 1
            nodes[e.b].degree += 1
        }
        wake()
    }

    func wake() { settled = false; calmFrames = 0 }

    /// One physics tick. O(n²) repulsion is fine at vault scale.
    /// ponytail: switch to a Barnes-Hut quadtree if the brain ever passes ~1500 notes.
    func step(dragging: Int?) {
        guard !settled, !nodes.isEmpty else { return }
        let dt: CGFloat = 1.0 / 60.0
        let repulsion: CGFloat = 0.020
        let springRest: CGFloat = 0.16
        let springK: CGFloat = 2.6
        var forces = Array(repeating: CGVector.zero, count: nodes.count)

        for i in 0..<nodes.count {
            for j in (i + 1)..<nodes.count {
                let dx = nodes[i].pos.x - nodes[j].pos.x
                let dy = nodes[i].pos.y - nodes[j].pos.y
                let d2 = max(dx * dx + dy * dy, 0.0004)
                let f = repulsion / d2
                let d = sqrt(d2)
                let fx = f * dx / d, fy = f * dy / d
                forces[i].dx += fx; forces[i].dy += fy
                forces[j].dx -= fx; forces[j].dy -= fy
            }
        }
        for e in edges {
            let dx = nodes[e.b].pos.x - nodes[e.a].pos.x
            let dy = nodes[e.b].pos.y - nodes[e.a].pos.y
            let d = max(sqrt(dx * dx + dy * dy), 0.001)
            let f = springK * (d - springRest)
            let fx = f * dx / d, fy = f * dy / d
            forces[e.a].dx += fx; forces[e.a].dy += fy
            forces[e.b].dx -= fx; forces[e.b].dy -= fy
        }
        var energy: CGFloat = 0
        for i in 0..<nodes.count {
            if i == dragging { nodes[i].vel = .zero; continue }
            forces[i].dx -= nodes[i].pos.x * 0.9   // gravity toward center
            forces[i].dy -= nodes[i].pos.y * 0.9
            nodes[i].vel.dx = (nodes[i].vel.dx + forces[i].dx * dt) * 0.86
            nodes[i].vel.dy = (nodes[i].vel.dy + forces[i].dy * dt) * 0.86
            nodes[i].pos.x += nodes[i].vel.dx * dt
            nodes[i].pos.y += nodes[i].vel.dy * dt
            energy += nodes[i].vel.dx * nodes[i].vel.dx + nodes[i].vel.dy * nodes[i].vel.dy
        }
        if dragging == nil, energy < 0.00003 {
            calmFrames += 1
            if calmFrames > 20 { settled = true }
        } else {
            calmFrames = 0
        }
    }

    func layout(_ p: CGPoint, in size: CGSize) -> CGPoint {
        let scale = min(size.width, size.height) * 0.42
        return CGPoint(x: size.width / 2 + p.x * scale, y: size.height / 2 + p.y * scale)
    }

    func unproject(_ p: CGPoint, in size: CGSize) -> CGPoint {
        let scale = min(size.width, size.height) * 0.42
        return CGPoint(x: (p.x - size.width / 2) / scale, y: (p.y - size.height / 2) / scale)
    }

    func nearest(to point: CGPoint, in size: CGSize, within: CGFloat) -> Int? {
        var best: (Int, CGFloat)? = nil
        for (i, node) in nodes.enumerated() {
            let sp = layout(node.pos, in: size)
            let d = hypot(sp.x - point.x, sp.y - point.y)
            if d < within, d < (best?.1 ?? .infinity) { best = (i, d) }
        }
        return best?.0
    }

    static let palette: [Color] = [
        Color(red: 0.91, green: 0.66, blue: 0.31),  // amber (accent)
        Color(red: 0.27, green: 0.72, blue: 0.65),  // teal
        Color(red: 0.36, green: 0.55, blue: 0.93),  // blue
        Color(red: 0.88, green: 0.42, blue: 0.54),  // rose
        Color(red: 0.56, green: 0.75, blue: 0.44),  // sage
        Color(red: 0.65, green: 0.55, blue: 0.88),  // lavender
        Color(red: 0.91, green: 0.47, blue: 0.35),  // coral
        Color(red: 0.86, green: 0.82, blue: 0.66),  // cream
    ]
    static func color(for group: Int) -> Color { palette[group % palette.count] }
}

struct GraphView: View {
    @EnvironmentObject var state: AppState
    @State private var model = GraphModel()
    @State private var hoverIndex: Int? = nil
    @State private var dragIndex: Int? = nil
    @State private var dragMoved: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { _ in
                Canvas { ctx, size in
                    model.step(dragging: dragIndex)
                    draw(ctx: ctx, size: size)
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(in: geo.size))
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    hoverIndex = model.nearest(to: point, in: geo.size, within: 22)
                case .ended:
                    hoverIndex = nil
                }
            }
        }
        .background(Theme.bg)
        .overlay(alignment: .topLeading) { legend }
        .overlay(alignment: .bottomTrailing) { stats }
        .navigationTitle("")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    state.selection = .dashboard
                } label: {
                    Label("Dashboard", systemImage: "sparkle")
                }
                CaptureButton()
            }
        }
        .onAppear { model.rebuild(notes: state.notes) }
        .onChange(of: state.notes) { model.rebuild(notes: state.notes) }
    }

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragIndex == nil {
                    dragIndex = model.nearest(to: value.startLocation, in: size, within: 22)
                    dragMoved = 0
                    model.wake()
                }
                if let i = dragIndex {
                    model.nodes[i].pos = model.unproject(value.location, in: size)
                    dragMoved = max(dragMoved, abs(value.translation.width) + abs(value.translation.height))
                }
            }
            .onEnded { _ in
                defer { dragIndex = nil }
                guard let i = dragIndex else { return }
                model.wake()
                if dragMoved < 4 {   // a click, not a drag: open the note
                    let id = model.nodes[i].id
                    if let note = state.notes.first(where: { $0.id == id }) {
                        state.open(note)
                    }
                }
            }
    }

    private func draw(ctx: GraphicsContext, size: CGSize) {
        let focus = hoverIndex ?? dragIndex
        let neighbors = focus.map { model.adjacency[$0] } ?? []

        var quiet = Path()
        var hot = Path()
        for e in model.edges {
            let a = model.layout(model.nodes[e.a].pos, in: size)
            let b = model.layout(model.nodes[e.b].pos, in: size)
            let touchesFocus = focus != nil && (e.a == focus || e.b == focus)
            if touchesFocus {
                hot.move(to: a); hot.addLine(to: b)
            } else {
                quiet.move(to: a); quiet.addLine(to: b)
            }
        }
        ctx.stroke(quiet, with: .color(.white.opacity(focus == nil ? 0.10 : 0.05)), lineWidth: 1)
        if focus != nil {
            ctx.stroke(hot, with: .color(Theme.accent.opacity(0.6)), lineWidth: 1.4)
        }

        for (i, node) in model.nodes.enumerated() {
            let p = model.layout(node.pos, in: size)
            let radius = 3.0 + min(CGFloat(node.degree), 8) * 0.7
            let isFocus = i == focus
            let isNeighbor = neighbors.contains(i)
            let dimmed = focus != nil && !isFocus && !isNeighbor
            let rect = CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)
            ctx.fill(Path(ellipseIn: rect),
                     with: .color(GraphModel.color(for: node.group).opacity(dimmed ? 0.22 : 1)))
            if isFocus {
                let ring = rect.insetBy(dx: -3.5, dy: -3.5)
                ctx.stroke(Path(ellipseIn: ring), with: .color(Theme.accent), lineWidth: 1.4)
            }
            if isFocus || (isNeighbor && model.nodes.count < 160) {
                ctx.draw(
                    Text(node.title)
                        .font(.system(size: isFocus ? 11.5 : 9.5, weight: isFocus ? .semibold : .regular))
                        .foregroundStyle(isFocus ? Theme.textPrimary : Theme.textSecondary),
                    at: CGPoint(x: p.x, y: p.y - radius - 10)
                )
            }
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(model.groups.enumerated().prefix(9)), id: \.offset) { i, name in
                HStack(spacing: 6) {
                    Circle().fill(GraphModel.color(for: i)).frame(width: 7, height: 7)
                    Text(name)
                        .font(Theme.monoSmall)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(12)
    }

    private var stats: some View {
        Text("\(model.nodes.count) notes · \(model.edges.count) links")
            .font(Theme.monoSmall)
            .foregroundStyle(Theme.textSecondary)
            .padding(12)
    }
}
