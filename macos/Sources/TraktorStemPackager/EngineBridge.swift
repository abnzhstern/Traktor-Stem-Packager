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

    private func requireComponents() throws {
        let manager = FileManager.default
        for (url, name) in [(node, "Node runtime"), (ffmpeg, "encoder"), (ffprobe, "media inspector"), (engine, "packaging engine")] {
            guard manager.isExecutableFile(atPath: url.path) || (name == "packaging engine" && manager.fileExists(atPath: url.path)) else {
                throw EngineError.missingComponent(name)
            }
        }
    }

    func validate(files: [AudioRole: URL]) async throws -> ValidationReport {
        let result = try await run(files: files, output: nil, validateOnly: true, progress: nil)
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
        year: String,
        artwork: URL?,
        stemNames: [AudioRole: String],
        progress: @escaping @Sendable (String) -> Void
    ) async throws {
        _ = try await run(
            files: files, output: output, validateOnly: false,
            metadata: ["title": title, "artist": artist, "album": album, "genre": genre, "year": year],
            stemNames: stemNames, artwork: artwork, progress: progress
        )
    }

    private func run(
        files: [AudioRole: URL],
        output: URL?,
        validateOnly: Bool,
        metadata: [String: String] = [:],
        stemNames: [AudioRole: String] = [:],
        artwork: URL? = nil,
        progress: (@Sendable (String) -> Void)?
    ) async throws -> String {
        try requireComponents()
        var arguments = [engine.path]
        for role in AudioRole.allCases {
            guard let url = files[role] else { throw EngineError.failed("Missing \(role.rawValue) file.") }
            arguments += ["--\(role.commandName)", url.path]
        }
        if validateOnly {
            arguments += ["--validate-only", "true"]
        } else if let output {
            arguments += ["--output", output.path]
        }
        for key in ["title", "artist", "album", "genre", "year"] {
            if let value = metadata[key], !value.isEmpty { arguments += ["--\(key)", value] }
        }
        for role in [AudioRole.drums, .bass, .other, .vocals] {
            if let value = stemNames[role], !value.isEmpty {
                arguments += ["--\(role.commandName)-name", value]
            }
        }
        if let artwork { arguments += ["--artwork", artwork.path] }

        return try await withCheckedThrowingContinuation { continuation in
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
                    continuation.resume(throwing: EngineError.failed(text.isEmpty ? "Packaging failed." : text))
                }
            }
            do { try process.run() }
            catch { continuation.resume(throwing: error) }
        }
    }
}
