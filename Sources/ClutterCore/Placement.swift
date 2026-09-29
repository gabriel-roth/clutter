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
    /// Where each cover in `origins` should go to line up in a grid, in the same order: covers are
    /// assigned to distinct cells of a grid of `size`-point cells filling the `screens`, so that
    /// together they move as little as possible. If the screens have fewer cells than there are
    /// covers, the grid tightens (its cells overlap) until there are enough.
    public static func tidyOrigins(of origins: [CGPoint], size: CGFloat, on screens: [CGRect]) -> [CGPoint] {
        guard !origins.isEmpty, !screens.isEmpty else { return origins }
        var extra = 0
        var cells = gridCells(size: size, on: screens, extra: extra)
        while cells.count < origins.count {
            extra += 1
            cells = gridCells(size: size, on: screens, extra: extra)
        }
        let cost = origins.map { origin in
            cells.map { cell in
                let dx = Double(origin.x - cell.x), dy = Double(origin.y - cell.y)
                return dx * dx + dy * dy
            }
        }
        return assignment(minimizing: cost).map { cells[$0] }
    }

    /// The origins of a grid on each screen, top row first: as many `size`-point columns and rows as
    /// fit plus `extra`, centered on the screen when they don't overlap, and pinned to its top-left
    /// corner when the screen is smaller than a cover.
    private static func gridCells(size: CGFloat, on screens: [CGRect], extra: Int) -> [CGPoint] {
        screens.flatMap { screen -> [CGPoint] in
            let columns = max(1, Int((screen.width / size).rounded(.down))) + extra
            let rows = max(1, Int((screen.height / size).rounded(.down))) + extra
            let spanX = screen.width - size, spanY = screen.height - size
            let pitchX = columns > 1 ? min(size, spanX / CGFloat(columns - 1)) : 0
            let pitchY = rows > 1 ? min(size, spanY / CGFloat(rows - 1)) : 0
            let marginX = max(0, spanX - pitchX * CGFloat(columns - 1)) / 2
            let marginY = max(0, spanY - pitchY * CGFloat(rows - 1)) / 2
            return (0..<rows).flatMap { row in
                (0..<columns).map { column in
                    // Whole points, rounded down, as for random origins.
                    CGPoint(
                        x: (screen.minX + marginX + CGFloat(column) * pitchX).rounded(.down),
                        y: (screen.maxY - marginY - size - CGFloat(row) * pitchY).rounded(.down)
                    )
                }
            }
        }
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
