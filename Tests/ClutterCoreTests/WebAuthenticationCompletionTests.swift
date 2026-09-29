import Foundation
import Testing
@testable import ClutterCore

private struct SampleError: Error, Equatable {}

@MainActor
private func complete(with url: URL?, _ error: Error?) async throws -> URL {
    try await withCheckedThrowingContinuation { continuation in
        let handler = webAuthenticationCompletion(resuming: continuation)
        DispatchQueue.global().async { handler(url, error) }
    }
}

@Test @MainActor func completionReturnsTheCallbackURLFromAnotherQueue() async throws {
    let callback = URL(string: "clutter://callback?code=X")!
    #expect(try await complete(with: callback, nil) == callback)
}

@Test @MainActor func completionThrowsTheErrorFromAnotherQueue() async {
    await #expect(throws: SampleError()) { try await complete(with: nil, SampleError()) }
}

@Test @MainActor func completionWithNothingThrowsMissingCode() async {
    await #expect(throws: SpotifyAuthError.missingCode) { try await complete(with: nil, nil) }
}

@Test @MainActor func completionIgnoresASecondCall() async throws {
    let first = URL(string: "clutter://callback?code=A")!
    let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
        let handler = webAuthenticationCompletion(resuming: continuation)
        handler(first, nil)
        handler(nil, SampleError())
    }
    #expect(result == first)
}
