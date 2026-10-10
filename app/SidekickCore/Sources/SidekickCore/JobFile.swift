import Foundation

/// jobs.json next to `Garage/`. A writer exists only when this process may replace the file.
enum JobFile {
    static let currentVersion = 1
    static let fileName = "jobs.json"

    /// Missing file writes nothing. A newer version stays put and returns no writer.
    static func open(
        _ location: JobFileLocation,
        now: Date,
        fileManager: FileManager = .default
    ) -> JobFileOpening {
        if case let .temporary(mode) = location, mode == .fresh {
            let root = temporaryRoot(fileManager: fileManager)
            if fileManager.fileExists(atPath: root.path) {
                do {
                    try fileManager.removeItem(at: root)
                } catch {
                    return .blocked(.couldNotRead)
                }
            }
        }
        guard let url = fileURL(for: location, fileManager: fileManager) else {
            return .blocked(.couldNotRead)
        }
        guard fileManager.fileExists(atPath: url.path) else {
            return .ready([], JobFileWriter(url: url))
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return .blocked(.couldNotRead)
        }
        switch JobFileVerdict.classify(data) {
        case let .jobs(jobs):
            return .ready(jobs, JobFileWriter(url: url))
        case let .newerVersion(version):
            // Leave the bytes at jobs.json. No writer, so a later save cannot replace them.
            return .blocked(.newerVersion(found: version))
        case .unreadable:
            let name = asideName(now: now)
            let destination = url.deletingLastPathComponent().appendingPathComponent(name)
            do {
                try fileManager.moveItem(at: url, to: destination)
            } catch {
                return .blocked(.couldNotSetAside)
            }
            return .setAside(fileName: name, JobFileWriter(url: url))
        }
    }

    private static func fileURL(for location: JobFileLocation, fileManager: FileManager) -> URL? {
        switch location {
        case .applicationSupport:
            guard let base = try? fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            ) else {
                return nil
            }
            return base
                .appendingPathComponent("SidekickMechanic", isDirectory: true)
                .appendingPathComponent(fileName)
        case .temporary:
            return temporaryRoot(fileManager: fileManager).appendingPathComponent(fileName)
        case let .directory(directory):
            return directory.appendingPathComponent(fileName)
        }
    }

    private static func temporaryRoot(fileManager: FileManager) -> URL {
        fileManager.temporaryDirectory
            .appendingPathComponent(JobsLaunch.temporaryFolderName, isDirectory: true)
    }

    private static func asideName(now: Date) -> String {
        let stamp = String(Int(now.timeIntervalSince1970))
        let token = UUID().uuidString.prefix(8)
        return "jobs.unreadable-\(stamp)-\(token).json"
    }
}

enum JobFileOpening {
    case ready([JobSheetState], JobFileWriter)
    case setAside(fileName: String, JobFileWriter)
    case blocked(JobStorageProblem)
}

/// Proof that jobs.json is ours to overwrite. Only `JobFile.open` can mint one.
struct JobFileWriter: Sendable {
    let url: URL

    fileprivate init(url: URL) {
        self.url = url
    }

    func save(_ jobs: [JobSheetState]) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(JobFileEnvelope(version: JobFile.currentVersion, jobs: jobs))
        try data.write(to: url, options: .atomic)
    }
}

enum JobFileVerdict: Equatable {
    case jobs([JobSheetState])
    case newerVersion(Int)
    /// Not JSON, no `version`, version < 1, or a current-version file that does not decode.
    case unreadable

    static func classify(_ data: Data) -> JobFileVerdict {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let probe = try? decoder.decode(VersionProbe.self, from: data) else {
            return .unreadable
        }
        if probe.version > JobFile.currentVersion {
            return .newerVersion(probe.version)
        }
        guard probe.version == JobFile.currentVersion,
              let file = try? decoder.decode(JobFileEnvelope.self, from: data)
        else {
            return .unreadable
        }
        return .jobs(file.jobs)
    }

    private struct VersionProbe: Decodable {
        let version: Int
    }
}

struct JobFileEnvelope: Codable {
    let version: Int
    let jobs: [JobSheetState]
}
