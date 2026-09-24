import AppKit
import Foundation

@MainActor
final class PackagerModel: ObservableObject {
    static let startupWorkflowKey = "startupWorkflow"
    static let lastUsedModeKey = "lastUsedPackagingMode"
    static let collectionPathKey = "traktorCollectionPath"
    static let stemsDirectoryPathKey = "traktorStemsDirectoryPath"
    static let openTraktorAfterAACKey = "openTraktorAfterAACExport"

    enum State: Equatable {
        case waiting
        case validating
        case ready
        case packaging
        case complete(URL)
        case failed(String)
    }

    @Published var files: [AudioRole: URL] = [:]
    @Published var mode: PackagingMode = .portableAAC
    @Published var collectionURL: URL?
    @Published var stemsDirectoryURL: URL?
    @Published var title = ""
    @Published var artist = ""
    @Published var album = ""
    @Published var genre = ""
    @Published var releaseDate = ""
    @Published var producer = ""
    @Published var label = ""
    @Published var artworkURL: URL?
    @Published var stemNames: [AudioRole: String] = [
        .drums: "Drums", .bass: "Bass", .other: "Other", .vocals: "Vocals"
    ]
    @Published var state: State = .waiting
    @Published var report: ValidationReport?
    @Published var nativeReadiness: NativeReadiness?
    @Published var traktorRunning = false
    @Published var statusText = "Add your master and four stem files, or import a five-file folder."
    @Published var recoveryText: String?
    @Published var validationProblemRoles: Set<AudioRole> = []
    @Published var folderImportNeedsReview = false
    @Published var waitingForManualTraktorQuit = false
    private var extractedArtworkURL: URL?
    private var readinessTask: Task<Void, Never>?

    init() {
        let manager = FileManager.default
        let defaults = UserDefaults.standard
        let home = manager.homeDirectoryForCurrentUser
        let startup = StartupWorkflow(rawValue: defaults.string(forKey: Self.startupWorkflowKey) ?? "") ?? .rememberLastUsed
        switch startup {
        case .rememberLastUsed:
            mode = PackagingMode(rawValue: defaults.string(forKey: Self.lastUsedModeKey) ?? "") ?? .portableAAC
        case .portableAAC:
            mode = .portableAAC
        case .nativeLossless:
            mode = .nativeLossless
        }

        if let savedCollection = defaults.string(forKey: Self.collectionPathKey), !savedCollection.isEmpty {
            collectionURL = URL(fileURLWithPath: savedCollection)
        } else {
            collectionURL = Self.detectCollection(home: home, manager: manager)
        }
        if let savedStems = defaults.string(forKey: Self.stemsDirectoryPathKey), !savedStems.isEmpty {
            stemsDirectoryURL = URL(fileURLWithPath: savedStems, isDirectory: true)
        } else {
            stemsDirectoryURL = Self.detectStemsDirectory(home: home, manager: manager)
        }
        refreshTraktorStatus()
    }

    private static func detectCollection(home: URL, manager: FileManager) -> URL? {
        let nativeInstruments = home.appending(path: "Documents/Native Instruments")
        guard let folders = try? manager.contentsOfDirectory(
            at: nativeInstruments,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        return folders
            .filter { $0.lastPathComponent.hasPrefix("Traktor ") }
            .map { $0.appending(path: "collection.nml") }
            .filter { manager.fileExists(atPath: $0.path) }
            .sorted { $0.deletingLastPathComponent().lastPathComponent > $1.deletingLastPathComponent().lastPathComponent }
            .first
    }

    private static func detectStemsDirectory(home: URL, manager: FileManager) -> URL? {
        let defaultStems = home.appending(path: "Music/Traktor/Stems", directoryHint: .isDirectory)
        return manager.fileExists(atPath: defaultStems.path) ? defaultStems : nil
    }

    var hasAllFiles: Bool { AudioRole.allCases.allSatisfy { files[$0] != nil } }
    var audioSetValidated: Bool {
        guard hasAllFiles, report != nil else { return false }
        switch state {
        case .ready, .packaging, .complete: return true
        case .waiting, .validating, .failed: return false
        }
    }
    var assignmentsLocked: Bool { audioSetValidated && !folderImportNeedsReview }
    var canCreate: Bool {
        state == .ready && hasAllFiles &&
            (mode == .portableAAC || (collectionURL != nil && stemsDirectoryURL != nil && nativeReadiness?.ready == true))
    }

    var canResolveUnsavedAnalysis: Bool {
        state == .ready && mode == .nativeLossless && hasAllFiles &&
            collectionURL != nil && stemsDirectoryURL != nil &&
            traktorRunning && nativeReadiness?.ready == false
    }

    var primaryActionTitle: String {
        if mode == .portableAAC { return "CREATE AAC STEM FILE" }
        if canResolveUnsavedAnalysis { return "CLOSE TRAKTOR & INSTALL" }
        return "VERIFY & INSTALL LOSSLESS STEMS"
    }

    func setMode(_ newMode: PackagingMode) {
        mode = newMode
        UserDefaults.standard.set(newMode.rawValue, forKey: Self.lastUsedModeKey)
        report = nil
        validationProblemRoles = []
        recoveryText = nil
        state = .waiting
        statusText = hasAllFiles ? "Checking compatibility…" : "Add your master and four stem files, or import a five-file folder."
        refreshNativeReadiness()
        if hasAllFiles && !folderImportNeedsReview { Task { await validate() } }
    }

    func setFile(_ url: URL, for role: AudioRole) {
        guard !assignmentsLocked else { return }
        let previousMaster = files[.master]
        if let sourceRole = files.first(where: { $0.value.standardizedFileURL == url.standardizedFileURL })?.key,
           sourceRole != role {
            let displaced = files[role]
            files[role] = url
            files[sourceRole] = displaced
        } else {
            files[role] = url
        }
        report = nil
        validationProblemRoles = []
        recoveryText = nil
        state = .waiting
        statusText = folderImportNeedsReview
            ? "Review the assignments. Drag files between slots to reassign them, then choose Accept Assignments."
            : hasAllFiles ? "Checking compatibility…" : "Add your master and four stem files, or import a five-file folder."
        if files[.master] != previousMaster, let master = files[.master] {
            title = master.deletingPathExtension().lastPathComponent
            Task { await loadMasterMetadata(from: master) }
            refreshNativeReadiness()
        }
        if hasAllFiles && !folderImportNeedsReview { Task { await validate() } }
    }

    func importFolder(_ directory: URL) {
        let supported = Set(["wav", "wave", "aif", "aiff", "m4a", "aac", "mp3"])
        do {
            let audioFiles = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
                .filter { supported.contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

            guard audioFiles.count == 5 else {
                folderImportNeedsReview = false
                validationProblemRoles = []
                state = .failed("This folder contains \(audioFiles.count) supported audio files. Choose a folder containing exactly one master and four stems, or add the files manually.")
                statusText = "This folder contains \(audioFiles.count) supported audio files. Choose a folder containing exactly one master and four stems, or add the files manually."
                recoveryText = "Choose a folder containing exactly five supported audio files, or add the master and stems individually."
                return
            }

            var assignments: [AudioRole: URL] = [:]
            var unassigned: [URL] = []
            for file in audioFiles {
                if let role = suggestedRole(for: file), assignments[role] == nil {
                    assignments[role] = file
                } else {
                    unassigned.append(file)
                }
            }
            for role in AudioRole.allCases where assignments[role] == nil {
                if let next = unassigned.first {
                    assignments[role] = next
                    unassigned.removeFirst()
                }
            }

            files = assignments
            report = nil
            validationProblemRoles = []
            recoveryText = nil
            folderImportNeedsReview = true
            state = .waiting
            statusText = "Review the assignments. Drag files between slots to reassign them, then choose Accept Assignments."
            if let master = files[.master] {
                title = master.deletingPathExtension().lastPathComponent
                Task { await loadMasterMetadata(from: master) }
            }
            refreshNativeReadiness()
        } catch {
            folderImportNeedsReview = false
            state = .failed("The folder could not be read. Choose it again or add the files manually.")
            statusText = "The folder could not be read. Choose it again or add the files manually."
            recoveryText = "Check that the folder still exists and is readable, then choose it again or add the files individually."
        }
    }

    func confirmFolderAssignments() {
        guard folderImportNeedsReview, hasAllFiles else { return }
        folderImportNeedsReview = false
        statusText = "Checking compatibility…"
        Task { await validate() }
    }

    func editAssignments() {
        guard hasAllFiles else { return }
        folderImportNeedsReview = true
        report = nil
        validationProblemRoles = []
        recoveryText = nil
        state = .waiting
        statusText = "Assignments unlocked. Move or replace files, then choose Accept Assignments."
    }

    private func suggestedRole(for file: URL) -> AudioRole? {
        let base = file.deletingPathExtension().lastPathComponent.lowercased()
        let tokens = base.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let boundaryTokens = Set([tokens.first, tokens.last].compactMap { $0 })
        if !boundaryTokens.isDisjoint(with: ["drum", "drums", "percussion"]) { return .drums }
        if boundaryTokens.contains("bass") { return .bass }
        if !boundaryTokens.isDisjoint(with: ["vocal", "vocals", "vox", "acapella", "acappella"]) { return .vocals }
        if !boundaryTokens.isDisjoint(with: ["other", "music", "instrumental", "instruments"]) { return .other }
        if boundaryTokens.contains("master") || base.contains("full mix") || base.contains("mixdown") || base.contains("stereo mix") {
            return .master
        }
        return nil
    }

    func clear(_ role: AudioRole) {
        files[role] = nil
        report = nil
        validationProblemRoles = []
        recoveryText = nil
        folderImportNeedsReview = false
        state = .waiting
        statusText = "Add your master and four stem files, or import a five-file folder."
        if role == .master {
            title = ""
            artist = ""
            album = ""
            genre = ""
            releaseDate = ""
            producer = ""
            label = ""
            discardExtractedArtwork()
            artworkURL = nil
            nativeReadiness = nil
        }
    }

    func clearAll() {
        readinessTask?.cancel()
        files.removeAll()
        report = nil
        nativeReadiness = nil
        validationProblemRoles = []
        folderImportNeedsReview = false
        waitingForManualTraktorQuit = false
        recoveryText = nil
        state = .waiting
        title = ""
        artist = ""
        album = ""
        genre = ""
        releaseDate = ""
        producer = ""
        label = ""
        stemNames = [.drums: "Drums", .bass: "Bass", .other: "Other", .vocals: "Vocals"]
        discardExtractedArtwork()
        artworkURL = nil
        statusText = "Queue cleared. Add your master and four stem files, or import a five-file folder."
    }

    func setCollection(_ url: URL?) {
        collectionURL = url
        if let url {
            UserDefaults.standard.set(url.path, forKey: Self.collectionPathKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.collectionPathKey)
        }
        refreshNativeReadiness()
    }

    func setStemsDirectory(_ url: URL?) {
        stemsDirectoryURL = url
        if let url {
            UserDefaults.standard.set(url.path, forKey: Self.stemsDirectoryPathKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.stemsDirectoryPathKey)
        }
        refreshNativeReadiness()
    }

    func resetDetectedLocations() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.collectionPathKey)
        defaults.removeObject(forKey: Self.stemsDirectoryPathKey)
        let manager = FileManager.default
        let home = manager.homeDirectoryForCurrentUser
        collectionURL = Self.detectCollection(home: home, manager: manager)
        stemsDirectoryURL = Self.detectStemsDirectory(home: home, manager: manager)
        refreshNativeReadiness()
    }

    func locationExists(_ url: URL?) -> Bool {
        guard let url else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    func refreshTraktorStatus() {
        traktorRunning = runningTraktorApplication() != nil
    }

    func pollTraktorStatus() async {
        let wasRunning = traktorRunning
        refreshTraktorStatus()
        if wasRunning,
           !traktorRunning,
           mode == .nativeLossless,
           files[.master] != nil,
           collectionURL != nil,
           nativeReadiness?.ready != true,
           state != .packaging {
            await checkTraktorForMaster()
        }
    }

    func refreshNativeReadiness() {
        readinessTask?.cancel()
        nativeReadiness = nil
        guard mode == .nativeLossless,
              let master = files[.master],
              let collection = collectionURL else { return }
        readinessTask = Task { [weak self] in
            do {
                let result = try await EngineBridge().checkNativeReadiness(
                    master: master, collection: collection, stemsDirectory: self?.stemsDirectoryURL
                )
                guard !Task.isCancelled,
                      self?.files[.master] == master,
                      self?.collectionURL == collection else { return }
                self?.nativeReadiness = result
            } catch {
                guard !Task.isCancelled else { return }
                self?.nativeReadiness = NativeReadiness(
                    ready: false, found: false, hasAudioId: false, linkedStemExists: false,
                    message: error.localizedDescription
                )
            }
        }
    }

    func checkTraktorForMaster() async {
        guard mode == .nativeLossless else { return }
        guard let master = files[.master] else {
            statusText = "Add the stereo master first."
            recoveryText = "Drop or choose the exact master file you want to use in Traktor."
            return
        }
        guard let collectionURL else {
            statusText = "Choose Traktor’s collection.nml before checking for the master."
            recoveryText = "Use Choose beside Collection, then select the collection.nml used by this Traktor installation."
            return
        }
        statusText = "Checking Traktor’s saved collection for this exact master…"
        recoveryText = nil
        do {
            let result = try await EngineBridge().checkNativeReadiness(
                master: master, collection: collectionURL, stemsDirectory: stemsDirectoryURL
            )
            nativeReadiness = result
            refreshTraktorStatus()
            if result.ready {
                statusText = "Analyzed master found. Add or confirm the four stems, then continue."
            } else if traktorRunning {
                statusText = "The analyzed master is not in Traktor’s saved collection yet. Finish analysis, then save or close Traktor."
                recoveryText = "Traktor writes the new track ID when it saves its collection. Use the orange Close Traktor button; the app will verify the saved ID and continue automatically."
            } else {
                statusText = result.message
                recoveryText = "Choose Drag Stereo Master into Traktor below. Drop that exact file into Traktor’s Track Collection—not onto a deck—and let analysis finish."
            }
        } catch {
            nativeReadiness = NativeReadiness(ready: false, found: false, hasAudioId: false, linkedStemExists: false, message: error.localizedDescription)
            statusText = "Traktor’s collection could not be checked."
            recoveryText = "Confirm the Collection path points to collection.nml. The app will check again automatically."
        }
    }

    func saveAndQuitAfterAnalysis() async {
        refreshTraktorStatus()
        guard let traktor = runningTraktorApplication(), let collectionURL else {
            await checkTraktorForMaster()
            return
        }

        let traktorURL = traktor.bundleURL

        state = .packaging
        guard await closeTraktorAndWait(traktor) else { return }
        statusText = "Checking Traktor’s saved track ID…"
        let readiness = await recheckNativeReadinessAfterTraktorQuit(master: files[.master], collection: collectionURL)
        state = report != nil && hasAllFiles ? .ready : .waiting
        if readiness?.ready == true {
            statusText = hasAllFiles
                ? "Analyzed master found. All five files are ready for installation."
                : "Analyzed master found. Add the remaining stems to continue."
            recoveryText = hasAllFiles
                ? "Choose Verify & Install Lossless Stems below."
                : "Add the remaining four stem files individually or use Import Folder."
        } else {
            statusText = readiness?.message ?? "The saved Traktor track ID was not found."
            recoveryText = "Confirm the exact master appears in Traktor’s Track Collection and has finished analysis, then follow the orange next-action button."
        }
        if let traktorURL { _ = NSWorkspace.shared.open(traktorURL) }
        refreshTraktorStatus()
    }

    func openTraktorAndRevealMaster() {
        guard let master = files[.master] else {
            statusText = "Add the stereo master first."
            recoveryText = "Drop or choose the exact master file, then use one of the Traktor import options."
            return
        }
        guard let traktorURL = traktorApplicationURL() else {
            state = .failed("Traktor Pro 4 could not be found in Applications.")
            statusText = "Traktor Pro 4 could not be found in Applications."
            recoveryText = "Open Traktor manually and drag this exact stereo master into its Track Collection, or move Traktor Pro 4.app into the Applications folder."
            return
        }
        statusText = "Opening Traktor and highlighting the exact master in Finder…"
        recoveryText = "Drag the highlighted file from Finder into Traktor’s Track Collection—not onto a deck. Dismiss any Traktor startup window first, then let analysis finish."
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: traktorURL, configuration: configuration) { [weak self] _, error in
            Task { @MainActor in
                guard let self else { return }
                self.refreshTraktorStatus()
                if let error {
                    self.state = .failed("Traktor could not be opened: \(error.localizedDescription)")
                    self.statusText = "Traktor could not be opened."
                    self.recoveryText = "Open Traktor manually, drag this exact stereo master into its Track Collection, analyze it, then return to this app."
                } else {
                    self.statusText = "Your master is highlighted in Finder. Drag it into Traktor’s Track Collection now."
                    self.recoveryText = "Let Traktor finish analyzing it. Then return here and follow the orange Close Traktor button—the app will save, verify, and continue automatically."
                    self.revealMasterInFinder()
                }
            }
        }
    }

    func revealMasterInFinder() {
        guard let master = files[.master] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            NSWorkspace.shared.activateFileViewerSelecting([master])
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder")
                .first?.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        }
        if nativeReadiness?.ready == true {
            statusText = "The analyzed stereo master is highlighted in Finder."
            recoveryText = hasAllFiles
                ? "Return here and follow the orange install button."
                : "Add the four matching stems to continue."
        } else {
            statusText = "The stereo master is highlighted in Finder. Drag it into Traktor’s Track Collection."
            recoveryText = "After Traktor finishes analyzing it, return here and follow the orange next-action button."
        }
    }

    func setArtwork(_ url: URL?) {
        discardExtractedArtwork()
        artworkURL = url
    }

    private func loadMasterMetadata(from url: URL) async {
        do {
            let bridge = try EngineBridge()
            let metadata = try await bridge.readMasterMetadata(master: url)
            guard files[.master] == url else { return }
            title = metadata.title
            artist = metadata.artist
            album = metadata.album
            genre = metadata.genre
            releaseDate = metadata.releaseDate
            producer = metadata.producer
            label = metadata.label
            discardExtractedArtwork()
            if let encoded = metadata.artworkBase64,
               let data = Data(base64Encoded: encoded), !data.isEmpty {
                let fileExtension = metadata.artworkMimeType == "image/png" ? "png" : "jpg"
                let artwork = FileManager.default.temporaryDirectory
                    .appending(path: "traktor-master-artwork-\(UUID().uuidString).\(fileExtension)")
                try data.write(to: artwork, options: .atomic)
                extractedArtworkURL = artwork
                artworkURL = artwork
            }
        } catch {
            // Keep filename fallback and allow packaging when the source has no readable tags.
        }
    }

    private func discardExtractedArtwork() {
        guard let extractedArtworkURL else { return }
        if artworkURL == extractedArtworkURL { artworkURL = nil }
        try? FileManager.default.removeItem(at: extractedArtworkURL)
        self.extractedArtworkURL = nil
    }

    func validate() async {
        guard hasAllFiles else { return }
        state = .validating
        statusText = "Checking sample rate, channels, duration and stem-sum peak…"
        recoveryText = nil
        do {
            let bridge = try EngineBridge()
            let result = try await bridge.validate(files: files, mode: mode)
            report = result
            validationProblemRoles = []
            state = .ready
            statusText = result.limiterEnabled
                ? String(format: "Accepted. All five files match. Peak protection is enabled at a −0.3 dBFS ceiling because the combined peak is %.1f dBFS.", result.stemSumTruePeakDbfs)
                : String(format: "Accepted. All five files match. Peak protection is not needed; the combined peak is %.1f dBFS.", result.stemSumTruePeakDbfs)
        } catch {
            validationProblemRoles = problemRoles(from: error.localizedDescription)
            state = .failed(error.localizedDescription)
            statusText = error.localizedDescription
            recoveryText = recoverySuggestion(for: error.localizedDescription)
        }
    }

    private func recoverySuggestion(for message: String) -> String {
        let text = message.lowercased()
        if text.contains("sample") || text.contains("khz") || text.contains("hz") {
            return "Re-export or replace the highlighted files so all five use the same supported sample rate and bit-depth profile."
        }
        if text.contains("mono") || text.contains("stereo") || text.contains("channel") {
            return "Replace or re-export the highlighted file as stereo audio, then add it again."
        }
        if text.contains("length") || text.contains("duration") || text.contains("seconds different") {
            return "Re-export all five files from exactly the same start and end points, then try again."
        }
        if text.contains("audio_id") || text.contains("analy") || text.contains("collection") {
            return "Analyze the exact master in Traktor and allow Traktor to save its collection. The app will check again automatically."
        }
        return "Review the highlighted file slots and the message above. Replace the affected file, then try again. Your source files have not been changed."
    }

    private func problemRoles(from message: String) -> Set<AudioRole> {
        let lowercased = message.lowercased()
        let matched = AudioRole.allCases.filter { role in
            guard let url = files[role] else { return false }
            return lowercased.contains(role.commandName.lowercased()) ||
                lowercased.contains(url.path.lowercased())
        }
        return matched.isEmpty ? Set(AudioRole.allCases) : Set(matched)
    }

    func create() async {
        guard canCreate || canResolveUnsavedAnalysis else { return }
        if mode == .nativeLossless {
            await createNativeLossless()
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = sanitizedOutputName()
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        state = .packaging
        statusText = "Preparing audio…"
        do {
            let bridge = try EngineBridge()
            try await bridge.package(
                files: files,
                output: destination,
                title: title,
                artist: artist,
                album: album,
                genre: genre,
                releaseDate: releaseDate,
                producer: producer,
                label: label,
                artwork: artworkURL,
                stemNames: stemNames
            ) { message in
                Task { @MainActor in
                    if !message.isEmpty { self.statusText = message }
                }
            }
            state = .complete(destination)
            statusText = "AAC Stem file created. Drag the finished .stem.mp4 directly into Traktor; all four stems are already inside."
            recoveryText = "Choose Show Stem File in Finder, then drag the .stem.mp4 into Traktor’s Track Collection or a deck. This new file does not automatically inherit cues or beat grids from a separate master entry."
            if UserDefaults.standard.bool(forKey: Self.openTraktorAfterAACKey) {
                openTraktor()
            }
        } catch {
            state = .failed(error.localizedDescription)
            statusText = error.localizedDescription
            recoveryText = recoverySuggestion(for: error.localizedDescription)
        }
    }

    private func createNativeLossless() async {
        guard let collectionURL, let stemsDirectoryURL else { return }
        refreshTraktorStatus()
        let traktor = runningTraktorApplication()
        let shouldRelaunch = traktor != nil
        let traktorURL = traktor?.bundleURL
        let needsSavedAnalysisRefresh = nativeReadiness?.ready != true

        if nativeReadiness?.linkedStemExists == true {
            let replacement = NSAlert()
            replacement.messageText = "Replace the existing linked stems?"
            replacement.informativeText = "This master already has a linked Stem file. Replace Existing will install this set and keep the previous file as a timestamped .bak safety backup. The .bak file is not a second active Stem set."
            replacement.alertStyle = .warning
            replacement.addButton(withTitle: "Replace Existing")
            replacement.addButton(withTitle: "Cancel")
            guard replacement.runModal() == .alertFirstButtonReturn else {
                statusText = "Installation cancelled. The existing linked stems were not changed."
                recoveryText = nil
                return
            }
        }

        let warning = NSAlert()
        warning.messageText = needsSavedAnalysisRefresh && traktor != nil
            ? "Close Traktor, save its analysis, and continue?"
            : traktor == nil
            ? "Verify and install lossless stems?"
            : "Close Traktor and install lossless stems?"
        warning.informativeText = needsSavedAnalysisRefresh && traktor != nil
            ? "The app will ask Traktor to close so it saves its collection, verify the track ID, install the lossless stems, and then reopen Traktor. Traktor may briefly display Updating Settings while saving; that is expected."
            : traktor == nil
            ? "The app will verify all five decoded PCM streams, back up collection.nml, install the lossless sidecar, and link it to the exact master track."
            : "Traktor must close before installation. The app will ask it to close, install the lossless stems, and then reopen it. If macOS blocks that request, the app will show the exact manual fallback."
        warning.alertStyle = .warning
        if traktor != nil {
            warning.addButton(withTitle: "Close Traktor & Continue")
            warning.addButton(withTitle: "Cancel")
        } else {
            warning.addButton(withTitle: "Verify & Install")
            warning.addButton(withTitle: "Cancel")
        }
        let handoffChoice = warning.runModal()
        if traktor != nil {
            guard handoffChoice == .alertFirstButtonReturn else { return }
        } else {
            guard handoffChoice == .alertFirstButtonReturn else { return }
        }

        state = .packaging
        recoveryText = nil
        if let traktor {
            guard await closeTraktorAndWait(traktor) else { return }
        }
        if needsSavedAnalysisRefresh {
            statusText = "Rechecking Traktor’s saved track analysis…"
            let readiness = await recheckNativeReadinessAfterTraktorQuit(
                master: files[.master],
                collection: collectionURL
            )
            guard readiness?.ready == true else {
                state = .ready
                statusText = readiness?.message ?? "Could not recheck the saved Traktor collection."
                recoveryText = "Open Traktor and confirm the exact master has finished analysis. Then return here and follow the orange next-action button."
                if shouldRelaunch, let traktorURL { _ = NSWorkspace.shared.open(traktorURL) }
                refreshTraktorStatus()
                return
            }
        }
        statusText = "Creating and verifying lossless ALAC streams…"
        do {
            let bridge = try EngineBridge()
            let result = try await bridge.packageNativeLossless(
                files: files,
                collection: collectionURL,
                stemsDirectory: stemsDirectoryURL,
                stemNames: stemNames
            ) { message in
                Task { @MainActor in
                    if !message.isEmpty { self.statusText = message }
                }
            }
            let destination = URL(fileURLWithPath: result.destination)
            state = .complete(destination)
            statusText = "Installed and verified: all five decoded PCM streams match their sources exactly."
            recoveryText = result.stemBackup == nil
                ? "Load the original master in Traktor; it should now open as a Stem Deck."
                : "The existing linked Stem file was replaced. Its timestamped .bak file is a safety backup, not another active Stem set."
            refreshNativeReadiness()
            if shouldRelaunch, let traktorURL {
                _ = NSWorkspace.shared.open(traktorURL)
            }
            refreshTraktorStatus()
        } catch {
            state = .failed(error.localizedDescription)
            statusText = error.localizedDescription
            recoveryText = recoverySuggestion(for: error.localizedDescription)
        }
    }

    private func recheckNativeReadinessAfterTraktorQuit(
        master: URL?,
        collection: URL
    ) async -> NativeReadiness? {
        guard let master else { return nil }
        for attempt in 0..<8 {
            do {
                let result = try await EngineBridge().checkNativeReadiness(
                    master: master, collection: collection, stemsDirectory: stemsDirectoryURL
                )
                nativeReadiness = result
                if result.ready { return result }
                if attempt < 7 { try await Task.sleep(nanoseconds: 250_000_000) }
            } catch {
                nativeReadiness = NativeReadiness(
                    ready: false, found: false, hasAudioId: false, linkedStemExists: false,
                    message: error.localizedDescription
                )
                if attempt < 7 { try? await Task.sleep(nanoseconds: 250_000_000) }
            }
        }
        return nativeReadiness
    }

    private func runningTraktorApplication() -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { application in
            application.localizedName == "Traktor Pro 4" ||
                application.bundleURL?.lastPathComponent == "Traktor Pro 4.app"
        }
    }

    private func closeTraktorAndWait(_ application: NSRunningApplication) async -> Bool {
        waitingForManualTraktorQuit = true
        statusText = "Closing Traktor so it can save its collection…"
        recoveryText = "If Traktor says Updating Settings, let it finish. The app will continue automatically when Traktor closes."
        _ = application.terminate()

        for _ in 0..<48 {
            if application.isTerminated || runningTraktorApplication() == nil {
                waitingForManualTraktorQuit = false
                recoveryText = nil
                refreshTraktorStatus()
                statusText = "Traktor closed. Rechecking the saved analysis…"
                return true
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        let prompt = NSAlert()
        prompt.messageText = "macOS did not allow Traktor to close automatically"
        prompt.informativeText = "You can allow Traktor Stem Packager under System Settings > Privacy & Security > Automation if it appears there. Or quit Traktor normally now; the app will detect it and continue automatically."
        prompt.alertStyle = .warning
        prompt.addButton(withTitle: "Open Privacy & Security")
        prompt.addButton(withTitle: "I’ll Quit Traktor")
        prompt.addButton(withTitle: "Cancel")
        let choice = prompt.runModal()
        if choice == .alertFirstButtonReturn {
            openPrivacyAndSecurity()
        } else if choice == .alertThirdButtonReturn {
            waitingForManualTraktorQuit = false
            state = .ready
            statusText = "Installation paused. Traktor is still open."
            recoveryText = "Use the orange action again when you are ready. No files were changed."
            return false
        }

        statusText = "Waiting for Traktor to close…"
        recoveryText = "Quit Traktor normally if it remains open. The app will detect the closure and continue automatically."
        _ = application.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])

        for _ in 0..<2400 {
            if application.isTerminated || runningTraktorApplication() == nil {
                waitingForManualTraktorQuit = false
                recoveryText = nil
                refreshTraktorStatus()
                statusText = "Traktor closed. Rechecking the saved analysis…"
                return true
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        waitingForManualTraktorQuit = false
        state = .ready
        statusText = "Traktor is still open, so installation has paused."
        recoveryText = "Quit Traktor normally, then choose Verify & Install Lossless Stems again. No files were changed."
        return false
    }

    func openPrivacyAndSecurity() {
        let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!
        NSWorkspace.shared.open(settingsURL)
    }

    func openTraktor() {
        guard let traktorURL = traktorApplicationURL() else {
            let alert = NSAlert()
            alert.messageText = "Traktor Pro 4 could not be found"
            alert.informativeText = "Open Traktor manually, or place Traktor Pro 4.app in Applications or an Applications subfolder."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: traktorURL, configuration: configuration) { _, _ in }
    }

    private func traktorApplicationURL() -> URL? {
        if let runningURL = runningTraktorApplication()?.bundleURL { return runningURL }
        let manager = FileManager.default
        let applicationFolders = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            manager.homeDirectoryForCurrentUser.appending(path: "Applications", directoryHint: .isDirectory)
        ]
        let directCandidates = [
            URL(fileURLWithPath: "/Applications/Traktor Pro 4.app"),
            URL(fileURLWithPath: "/Applications/Native Instruments/Traktor Pro 4.app"),
            manager.homeDirectoryForCurrentUser.appending(path: "Applications/Traktor Pro 4.app")
        ]
        if let direct = directCandidates.first(where: { manager.fileExists(atPath: $0.path) }) {
            return direct
        }
        for folder in applicationFolders where manager.fileExists(atPath: folder.path) {
            guard let enumerator = manager.enumerator(
                at: folder,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let candidate as URL in enumerator {
                if candidate.lastPathComponent.caseInsensitiveCompare("Traktor Pro 4.app") == .orderedSame {
                    return candidate
                }
            }
        }
        return nil
    }

    func revealOutput() {
        if case .complete(let url) = state {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private func sanitizedOutputName() -> String {
        let base = title.isEmpty ? "Untitled" : title
        let invalid = CharacterSet(charactersIn: "/:")
        let safe = base.components(separatedBy: invalid).joined(separator: "-")
        return safe.hasSuffix(".stem.mp4") ? safe : "\(safe).stem.mp4"
    }
}
