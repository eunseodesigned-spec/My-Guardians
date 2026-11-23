import Foundation
import CoreGraphics

/// Destination-based ambient motion in the house SVG's fixed 396 × 649 coordinate space.
/// Render the house, positions, and artwork with the same scale so resizing never resets a walk.
struct HomeWandering {
    static let canvasSize = CGSize(width: 396, height: 649)

    let artworkSize: CGSize
    private let boundary: HomeMotionBoundary
    private var actors: [UUID: HomeMotionActor] = [:]
    private var previousTime: TimeInterval?
    private var elapsed: TimeInterval = 0

    /// The polygon must be convex and sit just inside the illustrated house silhouette.
    init(artworkSize: CGSize, housePolygon: [CGPoint], clearance: CGFloat = 4) {
        self.artworkSize = artworkSize
        boundary = HomeMotionBoundary(polygon: housePolygon, artworkSize: artworkSize, clearance: clearance)
    }

    var positions: [UUID: CGPoint] { actors.mapValues(\.position) }

    func position(for id: UUID) -> CGPoint? { actors[id]?.position }

    /// Also useful for verifying that the entire artwork rectangle stays inside the house.
    func containsArtwork(at center: CGPoint, tolerance: CGFloat = 0.001) -> Bool {
        boundary.contains(center, tolerance: tolerance)
    }

    /// Call from a timeline update, outside view rendering. Random choices happen only when
    /// a guardian arrives or finishes a segment, never while sampling a moving segment.
    mutating func update(ids: [UUID], at time: TimeInterval) {
        if let previousTime {
            // Resume gently after backgrounding or a paused timeline rather than jumping ahead.
            elapsed += min(0.25, max(0, time - previousTime))
        }
        previousTime = time

        let orderedIDs = Array(Set(ids)).sorted { $0.uuidString < $1.uuidString }
        let retainedIDs = Set(orderedIDs)
        actors = actors.filter { retainedIDs.contains($0.key) }

        for id in orderedIDs where actors[id] == nil {
            var random = HomeMotionRandom(id: id)
            let point = initialPosition(using: &random)
            let delay = random.value(in: 0...0.8)
            actors[id] = HomeMotionActor(random: random, position: point, readyAt: elapsed + delay)
        }

        for id in orderedIDs {
            guard var actor = actors[id] else { continue }
            if let segment = actor.segment, elapsed >= segment.endTime {
                actor.position = segment.end
                actor.segment = nil
                let pause = actor.random.value(in: 0...1) < 0.32
                    ? actor.random.value(in: 0.6...2.0) : 0
                actor.readyAt = segment.endTime + pause
            }
            if actor.segment == nil, elapsed >= actor.readyAt {
                let segment = nextSegment(for: id, actor: &actor, startingAt: actor.readyAt)
                actor.segment = segment
            }
            if let segment = actor.segment {
                actor.position = segment.position(at: elapsed)
            }
            actors[id] = actor
        }
    }

    private func initialPosition(using random: inout HomeMotionRandom) -> CGPoint {
        var best = boundary.randomPoint(using: &random)
        var bestScore: CGFloat = -1
        for _ in 0..<32 {
            let candidate = boundary.randomPoint(using: &random)
            let score = actors.values.map { clearance(from: candidate, to: $0.position) }.min() ?? 2
            if score > bestScore {
                best = candidate
                bestScore = score
            }
        }
        return best
    }

    private func nextSegment(for id: UUID, actor: inout HomeMotionActor, startingAt startTime: TimeInterval) -> HomeMotionSegment {
        var best: HomeMotionSegment?
        var bestScore: CGFloat = -.greatestFiniteMagnitude
        let others = actors.filter { $0.key != id }.map(\.value)

        for _ in 0..<28 {
            let destination = boundary.randomPoint(using: &actor.random)
            let dx = destination.x - actor.position.x
            let dy = destination.y - actor.position.y
            let length = hypot(dx, dy)
            let bend = CGFloat(actor.random.value(in: -1...1)) * min(36, length * 0.24)
            let normal = CGPoint(x: -dy / max(length, 1), y: dx / max(length, 1))
            let first = boundary.clamp(CGPoint(
                x: actor.position.x + dx / 3 + normal.x * bend,
                y: actor.position.y + dy / 3 + normal.y * bend
            ))
            let second = boundary.clamp(CGPoint(
                x: actor.position.x + dx * 2 / 3 + normal.x * bend * 0.7,
                y: actor.position.y + dy * 2 / 3 + normal.y * bend * 0.7
            ))
            var candidate = HomeMotionSegment(
                start: actor.position, first: first, second: second, end: destination,
                startTime: startTime, duration: 1
            )
            let speed = actor.random.value(in: 12...25)
            candidate.duration = max(2.4, Double(candidate.approximateLength) / speed)

            var destinationClearance: CGFloat = 2
            var pathClearance: CGFloat = 2
            for other in others {
                destinationClearance = min(destinationClearance, clearance(
                    from: destination, to: other.position(at: candidate.endTime)
                ))
                for fraction in [0.25, 0.5, 0.75] {
                    let sampleTime = startTime + candidate.duration * fraction
                    pathClearance = min(pathClearance, clearance(
                        from: candidate.position(at: sampleTime), to: other.position(at: sampleTime)
                    ))
                }
            }
            // Prefer room around both the destination and its approach; overcrowded homes
            // can still overlap, but guardians do not repeatedly converge on one point.
            let shortTripPenalty: CGFloat = length < max(artworkSize.width, artworkSize.height) * 0.7 ? 1.2 : 0
            let score = destinationClearance * 2 + pathClearance - shortTripPenalty
                + CGFloat(actor.random.value(in: 0...0.12))
            if score > bestScore {
                best = candidate
                bestScore = score
            }
        }
        // Every candidate is valid, including in a small usable polygon.
        return best!
    }

    private func clearance(from point: CGPoint, to other: CGPoint) -> CGFloat {
        let x = (point.x - other.x) / max(1, artworkSize.width + 10)
        let y = (point.y - other.y) / max(1, artworkSize.height + 10)
        return min(2, hypot(x, y))
    }
}

private struct HomeMotionActor {
    var random: HomeMotionRandom
    var position: CGPoint
    var readyAt: TimeInterval
    var segment: HomeMotionSegment?

    func position(at time: TimeInterval) -> CGPoint {
        segment?.position(at: time) ?? position
    }
}

private struct HomeMotionSegment {
    let start: CGPoint
    let first: CGPoint
    let second: CGPoint
    let end: CGPoint
    let startTime: TimeInterval
    var duration: TimeInterval

    var endTime: TimeInterval { startTime + duration }

    func position(at time: TimeInterval) -> CGPoint {
        let progress = CGFloat(min(1, max(0, (time - startTime) / duration)))
        // Zero velocity at joins makes direction changes and occasional rests gentle.
        let t = progress * progress * (3 - 2 * progress)
        let u = 1 - t
        return CGPoint(
            x: u * u * u * start.x + 3 * u * u * t * first.x + 3 * u * t * t * second.x + t * t * t * end.x,
            y: u * u * u * start.y + 3 * u * u * t * first.y + 3 * u * t * t * second.y + t * t * t * end.y
        )
    }

    var approximateLength: CGFloat {
        var total: CGFloat = 0
        var previous = start
        for step in 1...12 {
            let point = position(at: startTime + duration * Double(step) / 12)
            total += hypot(point.x - previous.x, point.y - previous.y)
            previous = point
        }
        return total
    }
}

private struct HomeMotionBoundary {
    private struct Edge {
        let normal: CGPoint
        let minimum: CGFloat

        func distance(to point: CGPoint) -> CGFloat {
            normal.x * point.x + normal.y * point.y - minimum
        }
    }

    private let edges: [Edge]
    private let polygon: [CGPoint]
    private let triangleAreas: [CGFloat]

    init(polygon original: [CGPoint], artworkSize: CGSize, clearance: CGFloat) {
        precondition(original.count >= 3, "The house motion boundary needs a convex polygon.")
        let signedArea = zip(original, original.dropFirst() + [original[0]]).reduce(CGFloat.zero) {
            $0 + $1.0.x * $1.1.y - $1.1.x * $1.0.y
        }
        let outline = signedArea >= 0 ? original : Array(original.reversed())
        let halfWidth = artworkSize.width / 2 + clearance
        let halfHeight = artworkSize.height / 2 + clearance
        edges = outline.indices.map { index in
            let start = outline[index]
            let end = outline[(index + 1) % outline.count]
            let length = max(0.001, hypot(end.x - start.x, end.y - start.y))
            let normal = CGPoint(x: (start.y - end.y) / length, y: (end.x - start.x) / length)
            return Edge(normal: normal, minimum: normal.x * start.x + normal.y * start.y
                        + abs(normal.x) * halfWidth + abs(normal.y) * halfHeight)
        }

        // Erode each edge by the complete axis-aligned artwork box. All Bezier control
        // points live in this convex region, so every point on each curve does too.
        var usable = outline
        for edge in edges {
            var clipped: [CGPoint] = []
            for index in usable.indices {
                let start = usable[index]
                let end = usable[(index + 1) % usable.count]
                let a = edge.distance(to: start)
                let b = edge.distance(to: end)
                if a >= 0 { clipped.append(start) }
                if (a >= 0) != (b >= 0) {
                    let t = a / (a - b)
                    clipped.append(CGPoint(x: start.x + (end.x - start.x) * t,
                                           y: start.y + (end.y - start.y) * t))
                }
            }
            usable = clipped
        }
        precondition(usable.count >= 3, "Guardian artwork must fit inside the house motion boundary.")
        polygon = usable
        triangleAreas = (1..<(usable.count - 1)).map { index in
            let a = usable[index], b = usable[index + 1], origin = usable[0]
            return abs((a.x - origin.x) * (b.y - origin.y) - (a.y - origin.y) * (b.x - origin.x)) / 2
        }
    }

    func contains(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        edges.allSatisfy { $0.distance(to: point) >= -tolerance }
    }

    func randomPoint(using random: inout HomeMotionRandom) -> CGPoint {
        var target = CGFloat(random.value(in: 0...1)) * triangleAreas.reduce(0, +)
        var triangle = triangleAreas.count - 1
        for index in triangleAreas.indices {
            target -= triangleAreas[index]
            if target <= 0 { triangle = index; break }
        }
        let a = polygon[0], b = polygon[triangle + 1], c = polygon[triangle + 2]
        let u = CGFloat(sqrt(random.value(in: 0...1)))
        let v = CGFloat(random.value(in: 0...1))
        return CGPoint(x: a.x * (1 - u) + b.x * u * (1 - v) + c.x * u * v,
                       y: a.y * (1 - u) + b.y * u * (1 - v) + c.y * u * v)
    }

    func clamp(_ point: CGPoint) -> CGPoint {
        if contains(point, tolerance: 0) { return point }
        var closest = polygon[0]
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for index in polygon.indices {
            let a = polygon[index], b = polygon[(index + 1) % polygon.count]
            let dx = b.x - a.x, dy = b.y - a.y
            let squaredLength = max(0.001, dx * dx + dy * dy)
            let t = min(1, max(0, ((point.x - a.x) * dx + (point.y - a.y) * dy) / squaredLength))
            let candidate = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
            let distance = hypot(point.x - candidate.x, point.y - candidate.y)
            if distance < bestDistance { closest = candidate; bestDistance = distance }
        }
        return closest
    }
}

/// Stable per guardian across launches; Swift's randomized Hasher is deliberately avoided.
private struct HomeMotionRandom {
    private var state: UInt64

    init(id: UUID) {
        state = id.uuidString.utf8.reduce(UInt64(14_695_981_039_346_656_037)) {
            ($0 ^ UInt64($1)) &* 1_099_511_628_211
        }
    }

    mutating func value(in range: ClosedRange<Double>) -> Double {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        value ^= value >> 31
        let unit = Double(value >> 11) / 9_007_199_254_740_992
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }
}
