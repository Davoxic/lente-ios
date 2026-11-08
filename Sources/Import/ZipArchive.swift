import Foundation
import Compression

/// Minimal, dependency-free ZIP reader.
/// Supports stored (method 0) and deflate (method 8) entries, plus ZIP64 archives.
/// Instagram data exports are large, so the file is memory-mapped and entries are
/// inflated on demand rather than all at once.
enum ZipError: LocalizedError {
    case notAnArchive
    case corruptDirectory
    case unsupportedCompression(UInt16)
    case inflateFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAnArchive:
            return "Il file non sembra un archivio ZIP valido."
        case .corruptDirectory:
            return "L'indice dell'archivio è danneggiato o illeggibile."
        case .unsupportedCompression(let method):
            return "Metodo di compressione non supportato (\(method)). Riscarica l'export in formato standard."
        case .inflateFailed(let name):
            return "Impossibile decomprimere \(name)."
        }
    }
}

struct ZipEntry {
    let path: String
    let method: UInt16
    let compressedSize: Int
    let uncompressedSize: Int
    let headerOffset: Int

    var isDirectory: Bool { path.hasSuffix("/") }

    /// Last path component, lowercased - used for tolerant lookups.
    var fileName: String {
        (path as NSString).lastPathComponent.lowercased()
    }
}

final class ZipArchive {
    private let bytes: Data
    let entries: [ZipEntry]

    init(url: URL) throws {
        self.bytes = try Data(contentsOf: url, options: .mappedIfSafe)
        self.entries = try ZipArchive.readCentralDirectory(bytes)
    }

    // MARK: - Reading entries

    func data(for entry: ZipEntry) throws -> Data {
        guard entry.uncompressedSize > 0 else { return Data() }

        // Walk past the local file header to find where the payload starts.
        let base = entry.headerOffset
        guard bytes.u32(base) == 0x0403_4b50 else { throw ZipError.corruptDirectory }
        let nameLength = Int(bytes.u16(base + 26))
        let extraLength = Int(bytes.u16(base + 28))
        let start = base + 30 + nameLength + extraLength
        let end = start + entry.compressedSize
        guard start >= 0, end <= bytes.count else { throw ZipError.corruptDirectory }

        let payload = bytes.subdata(in: start..<end)

        switch entry.method {
        case 0:
            return payload
        case 8:
            return try ZipArchive.inflate(payload,
                                          expectedSize: entry.uncompressedSize,
                                          name: entry.path)
        default:
            throw ZipError.unsupportedCompression(entry.method)
        }
    }

    func utf8String(for entry: ZipEntry) throws -> String {
        let raw = try data(for: entry)
        if let text = String(data: raw, encoding: .utf8) { return text }
        return String(decoding: raw, as: UTF8.self)
    }

    // MARK: - Inflate

    private static func inflate(_ source: Data, expectedSize: Int, name: String) throws -> Data {
        // COMPRESSION_ZLIB in Apple's Compression framework is raw DEFLATE,
        // which is exactly what a ZIP member stores.
        var destination = Data(count: expectedSize)
        let written: Int = destination.withUnsafeMutableBytes { dst -> Int in
            guard let dstBase = dst.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return source.withUnsafeBytes { src -> Int in
                guard let srcBase = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(dstBase, expectedSize,
                                                 srcBase, source.count,
                                                 nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { throw ZipError.inflateFailed(name) }
        if written < expectedSize {
            return Data(destination.prefix(written))
        }
        return destination
    }

    // MARK: - Central directory

    private static func readCentralDirectory(_ data: Data) throws -> [ZipEntry] {
        guard data.count > 22 else { throw ZipError.notAnArchive }

        // End of central directory record, searched from the tail.
        let maxComment = 65_557
        let searchStart = max(0, data.count - maxComment)
        var eocd = -1
        var cursor = data.count - 22
        while cursor >= searchStart {
            if data.u32(cursor) == 0x0605_4b50 { eocd = cursor; break }
            cursor -= 1
        }
        guard eocd >= 0 else { throw ZipError.notAnArchive }

        var entryCount = Int(data.u16(eocd + 10))
        var directoryOffset = Int(data.u32(eocd + 16))

        // ZIP64: the 32-bit fields saturate and the real values live in a separate record.
        if entryCount == 0xFFFF || directoryOffset == 0xFFFF_FFFF {
            let locator = eocd - 20
            if locator >= 0, data.u32(locator) == 0x0706_4b50 {
                let zip64 = Int(data.u64(locator + 8))
                if zip64 >= 0, zip64 + 56 <= data.count, data.u32(zip64) == 0x0606_4b50 {
                    entryCount = Int(data.u64(zip64 + 32))
                    directoryOffset = Int(data.u64(zip64 + 48))
                }
            }
        }

        guard directoryOffset >= 0, directoryOffset < data.count else { throw ZipError.corruptDirectory }

        var result: [ZipEntry] = []
        result.reserveCapacity(min(entryCount, 100_000))

        var offset = directoryOffset
        var read = 0
        while read < entryCount, offset + 46 <= data.count {
            guard data.u32(offset) == 0x0201_4b50 else { break }

            let method = data.u16(offset + 10)
            var compressed = Int(data.u32(offset + 20))
            var uncompressed = Int(data.u32(offset + 24))
            let nameLength = Int(data.u16(offset + 28))
            let extraLength = Int(data.u16(offset + 30))
            let commentLength = Int(data.u16(offset + 32))
            var headerOffset = Int(data.u32(offset + 42))

            let nameStart = offset + 46
            guard nameStart + nameLength <= data.count else { break }
            let nameData = data.subdata(in: nameStart..<(nameStart + nameLength))
            let path = String(decoding: nameData, as: UTF8.self)

            // ZIP64 extended information extra field.
            if uncompressed == 0xFFFF_FFFF || compressed == 0xFFFF_FFFF || headerOffset == 0xFFFF_FFFF {
                var extra = nameStart + nameLength
                let extraEnd = extra + extraLength
                while extra + 4 <= extraEnd, extra + 4 <= data.count {
                    let fieldID = data.u16(extra)
                    let fieldSize = Int(data.u16(extra + 2))
                    if fieldID == 0x0001 {
                        var field = extra + 4
                        if uncompressed == 0xFFFF_FFFF, field + 8 <= data.count {
                            uncompressed = Int(data.u64(field)); field += 8
                        }
                        if compressed == 0xFFFF_FFFF, field + 8 <= data.count {
                            compressed = Int(data.u64(field)); field += 8
                        }
                        if headerOffset == 0xFFFF_FFFF, field + 8 <= data.count {
                            headerOffset = Int(data.u64(field))
                        }
                        break
                    }
                    extra += 4 + fieldSize
                }
            }

            result.append(ZipEntry(path: path,
                                   method: method,
                                   compressedSize: compressed,
                                   uncompressedSize: uncompressed,
                                   headerOffset: headerOffset))

            offset = nameStart + nameLength + extraLength + commentLength
            read += 1
        }

        guard !result.isEmpty else { throw ZipError.corruptDirectory }
        return result
    }
}

// MARK: - Little-endian reads

private extension Data {
    func u16(_ offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= count else { return 0 }
        return withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self).littleEndian }
    }

    func u32(_ offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { return 0 }
        return withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian }
    }

    func u64(_ offset: Int) -> UInt64 {
        guard offset >= 0, offset + 8 <= count else { return 0 }
        return withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self).littleEndian }
    }
}
