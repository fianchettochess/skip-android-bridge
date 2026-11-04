// Copyright 2024–2026 Skip
// SPDX-License-Identifier: MPL-2.0
import Foundation

/// A bounded, sequential reader for one Android bundle asset.
public final class AssetInputStream: @unchecked Sendable {
    public enum ReadError: Error, Equatable {
        case invalidCount
        case closed
        case invalidRemainingLength
        case readFailed
    }

    /// The largest allocation a single read may request.
    public static let maximumReadSize = 1_048_576

    private let lock = NSLock()
    private let remaining: () -> Int64
    private let readChunk: (Int) -> Data?
    private let closeHandle: () -> Void
    private var closed = false

    // Internal seam also exercises the reader independently of the Android runtime.
    init(remaining: @escaping () -> Int64, read: @escaping (Int) -> Data?, close: @escaping () -> Void) {
        self.remaining = remaining
        self.readChunk = read
        self.closeHandle = close
    }

    /// Reads at most `count` bytes. An empty result means end of asset.
    /// `count` must be positive and no greater than `maximumReadSize`.
    public func read(upToCount count: Int) throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { throw ReadError.closed }
        guard count > 0, count <= Self.maximumReadSize else { throw ReadError.invalidCount }
        let available = remaining()
        guard available >= 0 else { throw ReadError.invalidRemainingLength }
        guard available > 0 else { return Data() }
        // AndroidAssetManager.Asset.read can retain zero padding if requested
        // past EOF. Never request more than the actual remaining asset length.
        let requested = Int(min(Int64(count), available))
        guard let result = readChunk(requested), !result.isEmpty, result.count <= requested else {
            throw ReadError.readFailed
        }
        return result
    }

    /// Close the asset. Repeated calls are harmless.
    public func close() {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return }
        closed = true
        closeHandle()
    }

    deinit { close() }
}
