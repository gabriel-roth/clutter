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
