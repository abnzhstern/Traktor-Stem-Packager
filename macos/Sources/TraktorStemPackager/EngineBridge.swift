import Foundation

enum EngineError: LocalizedError {
    case missingComponent(String)
    case failed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingComponent(let name): "The app is missing its bundled \(name) component."
        case .failed(let message): message
        case .invalidResponse: "The packaging engine returned an invalid response."
        }
    }
}

struct EngineBridge {
    private let resources: URL

    init(resources: URL? = Bundle.main.resourceURL) throws {
        guard let resources else { throw EngineError.missingComponent("resources") }
        self.resources = resources
    }

    private var node: URL { resources.appending(path: "Runtime/node") }
    private var ffmpeg: URL { resources.appending(path: "Runtime/ffmpeg") }
    private var ffprobe: URL { resources.appending(path: "Runtime/ffprobe") }
    private var engine: URL { resources.appending(path: "Engine/src/pack.mjs") }
    private var metadataEngine: URL { resources.appending(path: "Engine/src/read-metadata.mjs") }
    private var nativeCheckEngine: URL { resources.appending(path: "Engine/src/check-native.mjs") }

    private func requireComponents() throws {
        let manager = FileManager.default
        for (url, name) in [(node, "Node runtime"), (ffmpeg, "encoder"), (ffprobe, "media inspector"), (engine, "packaging engine"), (metadataEngine, "metadata reader"), (nativeCheckEngine, "Traktor collection checker")] {
            let isScript = name == "packaging engine" || name == "metadata reader" || name == "Traktor collection checker"
            guard manager.isExecutableFile(atPath: url.path) || (isScript && manager.fileExists(atPath: url.path)) else {
                throw EngineError.missingComponent(name)
            }
        }
    }

    func checkNativeReadiness(master: URL, collection: URL) async throws -> NativeReadiness {
        try requireComponents()
        let result = try await execute(
            arguments: [nativeCheckEngine.path, "--master", master.path, "--collection", collection.path],
            progress: nil
        )
        guard let marker = result.split(separator: "\n").first(where: { $0.hasPrefix("NATIVE_READINESS_RESULT ") }) else {
            throw EngineError.invalidResponse
        }
        let json = marker.dropFirst("NATIVE_READINESS_RESULT ".count)
        return try JSONDecoder().decode(NativeReadiness.self, from: Data(json.utf8))
    }

    func readMasterMetadata(master: URL) async throws -> MasterMetadata {
        try requireComponents()
        let result = try await execute(
            arguments: [metadataEngine.path, "--master", master.path],
            progress: nil
        )
        guard let marker = result.split(separator: "\n").first(where: { $0.hasPrefix("MASTER_METADATA ") }) else {
            throw EngineError.invalidResponse
        }
        let json = marker.dropFirst("MASTER_METADATA ".count)
        return try JSONDecoder().decode(MasterMetadata.self, from: Data(json.utf8))
    }

    func validate(files: [AudioRole: URL], mode: PackagingMode = .portableAAC) async throws -> ValidationReport {
        let result = try await run(files: files, output: nil, validateOnly: true, mode: mode, progress: nil)
        guard let marker = result.split(separator: "\n").first(where: { $0.hasPrefix("VALIDATION_RESULT ") }) else {
            throw EngineError.invalidResponse
        }
        let json = marker.dropFirst("VALIDATION_RESULT ".count)
        return try JSONDecoder().decode(ValidationReport.self, from: Data(json.utf8))
    }

    func package(
        files: [AudioRole: URL],
        output: URL,
        title: String,
        artist: String,
        album: String,
        genre: String,
        releaseDate: String,
        producer: String,
        label: String,
        artwork: URL?,
        stemNames: [AudioRole: String],
        progress: @escaping @Sendable (String) -> Void
    ) async throws {
        _ = try await run(
            files: files, output: output, validateOnly: false, mode: .portableAAC,
            metadata: [
                "title": title, "artist": artist, "album": album, "genre": genre,
                "release-date": releaseDate, "producer": producer, "label": label
            ],
            stemNames: stemNames, artwork: artwork, progress: progress
        )
    }

    func packageNativeLossless(
        files: [AudioRole: URL],
        collection: URL,
        stemsDirectory: URL,
        stemNames: [AudioRole: String],
        progress: @escaping @Sendable (String) -> Void
    ) async throws -> NativePackageResult {
        let result = try await run(
            files: files,
            output: nil,
            validateOnly: false,
            mode: .nativeLossless,
            stemNames: stemNames,
            collection: collection,
            stemsDirectory: stemsDirectory,
            progress: progress
        )
        guard let marker = result.split(separator: "\n").first(where: { $0.hasPrefix("NATIVE_RESULT ") }) else {
            throw EngineError.invalidResponse
        }
        let json = marker.dropFirst("NATIVE_RESULT ".count)
        return try JSONDecoder().decode(NativePackageResult.self, from: Data(json.utf8))
    }

    private func run(
        files: [AudioRole: URL],
        output: URL?,
        validateOnly: Bool,
        mode: PackagingMode = .portableAAC,
        metadata: [String: String] = [:],
        stemNames: [AudioRole: String] = [:],
        artwork: URL? = nil,
        collection: URL? = nil,
        stemsDirectory: URL? = nil,
        progress: (@Sendable (String) -> Void)?
    ) async throws -> String {
        try requireComponents()
        var arguments = [engine.path]
        for role in AudioRole.allCases {
            guard let url = files[role] else { throw EngineError.failed("Missing \(role.rawValue) file.") }
            arguments += ["--\(role.commandName)", url.path]
        }
        arguments += ["--mode", mode.commandName]
        if validateOnly {
            arguments += ["--validate-only", "true"]
        } else if let output {
            arguments += ["--output", output.path]
        }
        if let collection { arguments += ["--collection", collection.path] }
        if let stemsDirectory { arguments += ["--stems-dir", stemsDirectory.path] }
        for key in ["title", "artist", "album", "genre", "release-date", "producer", "label"] {
            if let value = metadata[key], !value.isEmpty { arguments += ["--\(key)", value] }
        }
        for role in [AudioRole.drums, .bass, .other, .vocals] {
            if let value = stemNames[role], !value.isEmpty {
                arguments += ["--\(role.commandName)-name", value]
            }
        }
        if let artwork { arguments += ["--artwork", artwork.path] }

        return try await execute(arguments: arguments, progress: progress)
    }

    private func execute(
        arguments: [String],
        progress: (@Sendable (String) -> Void)?
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = node
            process.arguments = arguments
            process.currentDirectoryURL = resources.appending(path: "Engine")
            process.standardOutput = pipe
            process.standardError = pipe
            process.environment = [
                "PATH": resources.appending(path: "Runtime").path,
                "STEM_PACKAGER_FFMPEG": ffmpeg.path,
                "STEM_PACKAGER_FFPROBE": ffprobe.path,
            ]

            var collected = Data()
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                collected.append(data)
                if let line = String(data: data, encoding: .utf8) {
                    progress?(line.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
            process.terminationHandler = { completed in
                pipe.fileHandleForReading.readabilityHandler = nil
                let remaining = pipe.fileHandleForReading.readDataToEndOfFile()
                collected.append(remaining)
                let text = String(data: collected, encoding: .utf8) ?? ""
                if completed.terminationStatus == 0 {
                    continuation.resume(returning: text)
                } else {
                    continuation.resume(throwing: EngineError.failed(Self.failureMessage(from: text)))
                }
            }
            do { try process.run() }
            catch { continuation.resume(throwing: error) }
        }
    }

    private static func failureMessage(from output: String) -> String {
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Packaging failed. Check the selected files and try again."
        }
        let lines = output.components(separatedBy: .newlines)
        if let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("Error:") }) {
            var useful: [String] = []
            for line in lines[start...] {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("at ") || trimmed.hasPrefix("Node.js ") { break }
                if useful.isEmpty {
                    useful.append(trimmed.replacingOccurrences(of: "Error:", with: "", options: .anchored).trimmingCharacters(in: .whitespaces))
                } else if !trimmed.isEmpty {
                    useful.append(trimmed)
                }
            }
            let message = useful.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !message.isEmpty { return message }
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct MasterMetadata: Decodable {
    let title: String
    let artist: String
    let album: String
    let releaseDate: String
    let producer: String
    let label: String
    let genre: String
    let artworkBase64: String?
    let artworkMimeType: String?
}

struct NativePackageResult: Decodable {
    let destination: String
    let collectionBackup: String
    let stemBackup: String?
    let relativePath: String
    let verification: String
    let verifiedStreams: Int
    let sampleRate: Int
    let bitsPerSample: Int
}
