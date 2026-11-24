import Foundation

/// Thin wrapper over POSIX/NSFileManager used by the browser.
///
/// After the exploit has escaped the sandbox and set uid 0, plain POSIX calls
/// are enough to walk the whole filesystem, so no vnode reimplementation is
/// needed here.
final class FileSystemService {
    static let shared = FileSystemService()

    private let fm = FileManager.default

    struct Entry: Identifiable, Hashable {
        let path: String
        let name: String
        let isDirectory: Bool
        let isSymlink: Bool
        let size: Int64
        let mode: UInt16
        let modified: Date?

        var id: String { path }
    }

    enum FSError: LocalizedError {
        case posix(String, Int32)

        var errorDescription: String? {
            switch self {
            case let .posix(op, code):
                return "\(op) failed: \(String(cString: strerror(code)))"
            }
        }
    }

    func list(_ path: String) throws -> [Entry] {
        let names: [String]
        do {
            names = try fm.contentsOfDirectory(atPath: path)
        } catch {
            throw FSError.posix("list", (error as NSError).code == 0 ? EACCES : Int32((error as NSError).code))
        }

        var entries: [Entry] = []
        entries.reserveCapacity(names.count)
        for name in names {
            let full = path == "/" ? "/" + name : path + "/" + name
            var st = stat()
            guard lstat(full, &st) == 0 else { continue }
            let kind = st.st_mode & S_IFMT
            entries.append(Entry(
                path: full,
                name: name,
                isDirectory: kind == S_IFDIR,
                isSymlink: kind == S_IFLNK,
                size: Int64(st.st_size),
                mode: UInt16(st.st_mode & 0o7777),
                modified: Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))
            ))
        }
        entries.sort {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory && !$1.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return entries
    }

    func read(_ path: String, maxBytes: Int = 1 << 20) throws -> Data {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        return try handle.read(upToCount: maxBytes) ?? Data()
    }

    func write(_ data: Data, to path: String) throws {
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    func createFolder(named name: String, in parent: String) throws {
        let full = parent == "/" ? "/" + name : parent + "/" + name
        try fm.createDirectory(atPath: full, withIntermediateDirectories: false)
    }

    func delete(_ path: String) throws {
        try fm.removeItem(atPath: path)
    }

    func move(from: String, to: String) throws {
        try fm.moveItem(atPath: from, toPath: to)
    }

    func copy(from: String, to: String) throws {
        try fm.copyItem(atPath: from, toPath: to)
    }

    func isDirectory(_ path: String) -> Bool {
        var st = stat()
        guard lstat(path, &st) == 0 else { return false }
        return (st.st_mode & S_IFMT) == S_IFDIR
    }

    func attributes(_ path: String) -> String {
        var st = stat()
        guard lstat(path, &st) == 0 else { return "unavailable" }
        return String(format: "mode %o  uid %u  gid %u  size %lld",
                      st.st_mode & 0o7777, st.st_uid, st.st_gid, Int64(st.st_size))
    }

    /// Renders unprintable bytes as a hex dump.
    static func hexDump(_ data: Data) -> String {
        var out = ""
        out.reserveCapacity(data.count * 4)
        let bytes = [UInt8](data)
        for offset in stride(from: 0, to: bytes.count, by: 16) {
            let slice = bytes[offset ..< min(offset + 16, bytes.count)]
            out += String(format: "%08x  ", offset)
            out += slice.map { String(format: "%02x ", $0) }.joined()
            out += " "
            out += slice.map { b in
                (b >= 0x20 && b < 0x7f) ? String(UnicodeScalar(b)) : "."
            }.joined()
            out += "\n"
        }
        return out
    }
}
