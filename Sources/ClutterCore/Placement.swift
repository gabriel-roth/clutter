import CoreGraphics

public enum Placement {
    /// A random origin that keeps a `size`-by-`size` cover entirely inside `visible`.
    /// If `visible` is too small, the cover is pinned to its top-left corner instead.
    public static func randomOrigin(size: CGFloat, in visible: CGRect, using rng: inout some RandomNumberGenerator) -> CGPoint {
        let maxX = visible.maxX - size
        let maxY = visible.maxY - size
        let x = maxX > visible.minX ? CGFloat.random(in: visible.minX...maxX, using: &rng) : visible.minX
        let y = maxY > visible.minY ? CGFloat.random(in: visible.minY...maxY, using: &rng) : maxY
        return CGPoint(x: x, y: y)
    }

    /// Whether any part of `frame` is on one of the `screens` (visible frames).
    public static func isVisible(_ frame: CGRect, on screens: [CGRect]) -> Bool {
        screens.contains { $0.intersects(frame) }
    }
}

extension Placement {
    /// Where each cover in `origins` should go to line up in an evenly spread grid, in the same order.
    /// Each cover goes to the screen it's nearest; the covers on a screen get a grid just big enough for
    /// them (shaped to the screen, with equal gaps between covers and equal margins around them), and
    /// are assigned to its cells so that together they move as little as possible. If a screen can't
    /// hold its covers without overlap, the grid's cells overlap instead.
    public static func tidyOrigins(of origins: [CGPoint], size: CGFloat, on screens: [CGRect]) -> [CGPoint] {
        guard !origins.isEmpty, !screens.isEmpty else { return origins }
        var groups = [[Int]](repeating: [], count: screens.count)
        for (index, origin) in origins.enumerated() {
            let center = CGPoint(x: origin.x + size / 2, y: origin.y + size / 2)
            let nearest = screens.indices.min { distance(from: center, to: screens[$0]) < distance(from: center, to: screens[$1]) }!
            groups[nearest].append(index)
        }
        var result = origins
        for (screen, indices) in zip(screens, groups) where !indices.isEmpty {
            let cells = gridCells(count: indices.count, size: size, in: screen)
            let cost = indices.map { index in
                cells.map { cell in
                    let dx = Double(origins[index].x - cell.x), dy = Double(origins[index].y - cell.y)
                    return dx * dx + dy * dy
                }
            }
            for (index, cell) in zip(indices, assignment(minimizing: cost)) {
                result[index] = cells[cell]
            }
        }
        return result
    }

    /// A cover's place on the desktop: the origin of its square and how far it's turned.
    public struct Spot: Equatable, Sendable {
        public var origin: CGPoint
        /// Degrees counterclockwise about the cover's center.
        public var rotation: CGFloat
    }

    /// Covers turn by up to this many degrees either way when placed at random.
    public static let maxRotation: CGFloat = 15

    /// The chance that a cover placed at random stays straight.
    public static let straightChance = 0.4

    /// A random turn, in tenths of a degree. Most often none (`straightChance`); otherwise 1 to
    /// `maxRotation` degrees either way, with small turns likelier than large ones.
    public static func randomRotation(using rng: inout some RandomNumberGenerator) -> CGFloat {
        guard Double.random(in: 0..<1, using: &rng) >= straightChance else { return 0 }
        let fraction = CGFloat.random(in: 0...1, using: &rng)
        let degrees = 1 + (maxRotation - 1) * fraction * fraction
        let turn = (degrees * 10).rounded() / 10
        return Bool.random(using: &rng) ? turn : -turn
    }

    /// How far a `size` cover turned by `rotation` degrees reaches beyond its square on each side, in
    /// whole points: the room the cover's window needs around the square.
    public static func rotationMargin(size: CGFloat, rotation: CGFloat) -> CGFloat {
        let radians = Double(rotation) * .pi / 180
        let reach = Double(size) * (abs(cos(radians)) + abs(sin(radians)) - 1) / 2
        return CGFloat(max(0, reach - 1e-9).rounded(.up))
    }

    /// Places for `count` covers that are scattered across `visible` but not evenly: the covers are dealt
    /// at random into the cells of the same grid Tidy uses, then each is knocked off its cell by up to
    /// most of its size and turned a little, so they crowd and overlap in places while still covering
    /// the whole screen. Every cover, turned, stays entirely on screen.
    public static func scrambledSpots(count: Int, size: CGFloat, in visible: CGRect, using rng: inout some RandomNumberGenerator) -> [Spot] {
        guard count > 0 else { return [] }
        let reach = size * 0.75
        return gridCells(count: count, size: size, in: visible).shuffled(using: &rng).prefix(count).map { cell in
            let rotation = randomRotation(using: &rng)
            let margin = rotationMargin(size: size, rotation: rotation)
            // A different reach for each cover, so some sit nearly in place and others wander far.
            let wander = reach * CGFloat.random(in: 0.3...1, using: &rng)
            let x = cell.x + CGFloat.random(in: -wander...wander, using: &rng)
            let y = cell.y + CGFloat.random(in: -wander...wander, using: &rng)
            let minX = visible.minX + margin
            let maxX = max(minX, visible.maxX - size - margin)
            let maxY = visible.maxY - size - margin
            let minY = min(maxY, visible.minY + margin)
            return Spot(origin: CGPoint(x: min(max(x, minX), maxX).rounded(.down), y: min(max(y, minY), maxY).rounded(.down)), rotation: rotation)
        }
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }

    /// The origins of the cells of a grid for `count` covers on `screen`. The grid has the fewest empty
    /// cells, then cells closest to square, among those that fit without overlap (or, if none do, among
    /// all). Covers are spread evenly, with the same gap between them as around the edge.
    private static func gridCells(count: Int, size: CGFloat, in screen: CGRect) -> [CGPoint] {
        let maxColumns = max(1, Int((screen.width / size).rounded(.down)))
        let maxRows = max(1, Int((screen.height / size).rounded(.down)))
        var shapes = (1...maxColumns).flatMap { columns in
            (1...maxRows).map { (columns: columns, rows: $0) }
        }.filter { $0.columns * $0.rows >= count }
        if shapes.isEmpty {
            shapes = (1...count).map { (columns: $0, rows: (count + $0 - 1) / $0) }
        }
        func badness(_ shape: (columns: Int, rows: Int)) -> (Int, Double) {
            let squareness = ((screen.width / CGFloat(shape.columns)) / (screen.height / CGFloat(shape.rows)))
            return (shape.columns * shape.rows - count, abs(log(Double(squareness))))
        }
        let shape = shapes.min { badness($0) < badness($1) }!
        let xs = offsets(count: shape.columns, size: size, length: screen.width).map { screen.minX + $0 }
        // Rows count down from the top edge, since origins are at a cover's bottom-left.
        let ys = offsets(count: shape.rows, size: size, length: screen.height).map { screen.maxY - size - $0 }
        return ys.flatMap { y in xs.map { CGPoint(x: $0.rounded(.down), y: y.rounded(.down)) } }
    }

    /// Where `count` covers of `size` start along a `length`-long edge: evenly spread with equal gaps
    /// between and around them, or, if they don't fit, overlapping from one end to the other. A cover on
    /// an edge shorter than itself starts at 0.
    private static func offsets(count: Int, size: CGFloat, length: CGFloat) -> [CGFloat] {
        let span = max(0, length - size)
        if count == 1 { return [span / 2] }
        let gap = (length - CGFloat(count) * size) / CGFloat(count + 1)
        if gap >= 0 {
            return (0..<count).map { gap + CGFloat($0) * (size + gap) }
        }
        return (0..<count).map { CGFloat($0) * span / CGFloat(count - 1) }
    }

    /// For each row of `cost`, the column it's assigned so that no two rows share a column and the total
    /// cost is least (the Hungarian algorithm). Needs at least as many columns as rows.
    private static func assignment(minimizing cost: [[Double]]) -> [Int] {
        let n = cost.count, m = cost[0].count
        var u = [Double](repeating: 0, count: n + 1)
        var v = [Double](repeating: 0, count: m + 1)
        var owner = [Int](repeating: 0, count: m + 1) // owner[j]: the 1-based row holding column j
        var previous = [Int](repeating: 0, count: m + 1)
        for i in 1...n {
            owner[0] = i
            var j0 = 0
            var minima = [Double](repeating: .infinity, count: m + 1)
            var used = [Bool](repeating: false, count: m + 1)
            repeat {
                used[j0] = true
                let i0 = owner[j0]
                var delta = Double.infinity
                var j1 = 0
                for j in 1...m where !used[j] {
                    let current = cost[i0 - 1][j - 1] - u[i0] - v[j]
                    if current < minima[j] {
                        minima[j] = current
                        previous[j] = j0
                    }
                    if minima[j] < delta {
                        delta = minima[j]
                        j1 = j
                    }
                }
                for j in 0...m {
                    if used[j] {
                        u[owner[j]] += delta
                        v[j] -= delta
                    } else {
                        minima[j] -= delta
                    }
                }
                j0 = j1
            } while owner[j0] != 0
            repeat {
                let j1 = previous[j0]
                owner[j0] = owner[j1]
                j0 = j1
            } while j0 != 0
        }
        var columns = [Int](repeating: 0, count: n)
        for j in 1...m where owner[j] != 0 {
            columns[owner[j] - 1] = j - 1
        }
        return columns
    }
}
