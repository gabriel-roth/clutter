import AppKit

/// A fresh, empty directory path that doesn't exist yet.
func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "ClutterTests-\(UUID().uuidString)", directoryHint: .isDirectory)
}

/// A small valid JPEG.
func jpegData() -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 3,
        hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    return rep.representation(using: .jpeg, properties: [:])!
}

/// Deterministic generator (SplitMix64) so random placement is repeatable in tests.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
