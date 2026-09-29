import CoreGraphics

/// Places square windows in rows starting at the top-left of the visible screen area.
public enum WindowLayout {
    public static let margin: CGFloat = 40
    public static let gap: CGFloat = 20

    public static func frames(count: Int, size: CGFloat, in visible: CGRect) -> [CGRect] {
        let perRow = max(1, Int((visible.width - 2 * margin + gap) / (size + gap)))
        return (0..<count).map { index in
            let row = CGFloat(index / perRow)
            let column = CGFloat(index % perRow)
            return CGRect(
                x: visible.minX + margin + column * (size + gap),
                y: visible.maxY - margin - size - row * (size + gap),
                width: size,
                height: size
            )
        }
    }
}
