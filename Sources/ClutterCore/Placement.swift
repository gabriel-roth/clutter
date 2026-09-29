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
