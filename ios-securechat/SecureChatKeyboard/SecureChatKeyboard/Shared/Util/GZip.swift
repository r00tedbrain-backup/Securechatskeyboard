import Foundation
import Compression

/// GZIP compression/decompression utility using Apple's Compression framework.
/// Replaces Java's GZIPOutputStream/GZIPInputStream used in the Android version.
enum GZip {

    /// Compress data using ZLIB (deflate) algorithm.
    /// The Android version uses GZIPOutputStream with BEST_COMPRESSION.
    static func compress(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return data }

        var output = Data(count: data.count)
        let result = output.withUnsafeMutableBytes { outputBuffer in
            data.withUnsafeBytes { inputBuffer in
                compression_encode_buffer(
                    outputBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    data.count,
                    inputBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }

        guard result > 0 else {
            throw GZipError.compressionFailed
        }

        output.count = result
        return output
    }

    /// Decompress ZLIB-compressed data.
    static func decompress(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return data }

        // Allocate a generous output buffer (compressed data could expand significantly)
        let bufferSize = data.count * 10
        var output = Data(count: bufferSize)

        let result = output.withUnsafeMutableBytes { outputBuffer in
            data.withUnsafeBytes { inputBuffer in
                compression_decode_buffer(
                    outputBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    bufferSize,
                    inputBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }

        guard result > 0 else {
            throw GZipError.decompressionFailed
        }

        output.count = result
        return output
    }
}

enum GZipError: LocalizedError {
    case compressionFailed
    case decompressionFailed

    var errorDescription: String? {
        switch self {
        case .compressionFailed: return "GZIP compression failed"
        case .decompressionFailed: return "GZIP decompression failed"
        }
    }
}
