import AppKit
import CryptoKit
import Foundation

@MainActor
final class PackagerModel: ObservableObject {
    static let startupWorkflowKey = "startupWorkflow"
    static let lastUsedModeKey = "lastUsedPackagingMode"
    static let collectionPathKey = "traktorCollectionPath"
    static let stemsDirectoryPathKey = "traktorStemsDirectoryPath"
    static let openTraktorAfterAACKey = "openTraktorAfterAACExport"
    static let audioFolderBehaviorKey = "audioFolderBehavior"
    static let lastAudioFolderPathKey = "lastAudioFolderPath"
    static let fixedAudioFolderPathKey = "fixedAudioFolderPath"
    static let lastInstalledFingerprintKey = "lastInstalledPackageFingerprint"
    static let lastInstalledDestinationKey = "lastInstalledDestinationPath"

    enum State: Equatable {
        case waiting
        case validating
        case ready
        case packaging
        case complete(URL)
        case failed(String)
    }

    enum WorkflowPhase: Equatable {
        case addMaster
        case chooseTraktorLocations
        case checkingTraktor
        case prepareMasterInTraktor
        case saveTraktorAndRefresh
        case addStems
        case reviewAssignments
        case validating
        case readyToCreateAAC
        case readyToInstallLossless
        case working
        case installed
        case actionNeeded
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
    @Published var assignmentsNeedReview = false
    @Published private(set) var validationAccepted = false
    @Published var waitingForManualTraktorQuit = false
    @Published private(set) var resetGeneration = 0
    @Published var audioFolderBehavior: AudioFolderBehavior = .rememberLastUsed
    @Published var lastAudioFolderURL: URL?
    @Published var fixedAudioFolderURL: URL?
    @Published private(set) var traktorAuditText: String?
    @Published private(set) var traktorSavedStateMayBeStale = false
    @Published private(set) var traktorAuditHasProblem = false
    @Published private(set) var traktorRefreshRequiresSave = false
    private var extractedArtworkURL: URL?
    private var readinessTask: Task<Void, Never>?
    private var validationTask: Task<Void, Never>?
    private var metadataTask: Task<Void, Never>?
    private var workflowGeneration = 0
    private var metadataGeneration = 0
    private var observedCollectionModificationDate: Date?
    private var observedStemsModificationDate: Date?

    init() {
        let manager = FileManager.default
        let defaults = UserDefaults.standard
        let home = manager.homeDirectoryForCurrentUser
        audioFolderBehavior = AudioFolderBehavior(
            rawValue: defaults.string(forKey: Self.audioFolderBehaviorKey) ?? ""
        ) ?? .rememberLastUsed
        if let path = defaults.string(forKey: Self.lastAudioFolderPathKey), !path.isEmpty {
            lastAudioFolderURL = URL(fileURLWithPath: path, isDirectory: true)
        }
        if let path = defaults.string(forKey: Self.fixedAudioFolderPathKey), !path.isEmpty {
            fixedAudioFolderURL = URL(fileURLWithPath: path, isDirectory: true)
        }
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
        primeObservedTraktorFiles()
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
    var audioSetValidated: Bool { hasAllFiles && validationAccepted && report != nil }
    var assignmentsLocked: Bool { audioSetValidated && !assignmentsNeedReview }
    var canStartNewPackage: Bool { state != .packaging && !waitingForManualTraktorQuit }
    var preferredAudioDirectoryURL: URL? {
        let candidate = audioFolderBehavior == .fixedFolder ? fixedAudioFolderURL : lastAudioFolderURL
        guard let candidate, locationExists(candidate) else { return nil }
        return candidate
    }
    var canCreate: Bool {
        state == .ready && audioSetValidated &&
            (mode == .portableAAC || (collectionURL != nil && stemsDirectoryURL != nil && nativeReadiness?.ready == true))
    }

    var canAddRemainingStems: Bool {
        guard files[.master] != nil,
              !hasAllFiles,
              !assignmentsNeedReview,
              state != .validating,
              state != .packaging else { return false }
        return mode == .portableAAC || nativeReadiness?.ready == true
    }

    var workflowPhase: WorkflowPhase {
        if state == .validating { return .validating }
        if state == .packaging { return .working }
        if case .failed = state { return .actionNeeded }
        if assignmentsNeedReview { return .reviewAssignments }
        if files[.master] == nil { return .addMaster }

        if mode == .portableAAC {
            if !hasAllFiles { return .addStems }
            if case .complete = state { return .installed }
            return .readyToCreateAAC
        }

        if collectionURL == nil || stemsDirectoryURL == nil { return .chooseTraktorLocations }
        if nativeReadiness == nil { return .checkingTraktor }
        if traktorRefreshRequiresSave && traktorRunning { return .saveTraktorAndRefresh }
        if case .complete = state,
           nativeReadiness?.collectionLinked == true,
           nativeReadiness?.linkedStemExists == true { return .installed }
        if nativeReadiness?.ready == false {
            return traktorRunning ? .saveTraktorAndRefresh : .prepareMasterInTraktor
        }
        if !hasAllFiles { return .addStems }
        if traktorRunning { return .saveTraktorAndRefresh }
        return .readyToInstallLossless
    }

    var canResolveUnsavedAnalysis: Bool {
        state == .ready && mode == .nativeLossless && hasAllFiles &&
            collectionURL != nil && stemsDirectoryURL != nil &&
            traktorRunning && nativeReadiness?.ready == false
    }

    var primaryActionTitle: String {
        if mode == .portableAAC { return "CREATE AAC STEM FILE" }
        if canResolveUnsavedAnalysis { return "CLOSE TRAKTOR & INSTALL" }
        if traktorRunning { return "CLOSE TRAKTOR & VERIFY / INSTALL" }
        return "VERIFY & INSTALL LOSSLESS STEMS"
    }

    func setMode(_ newMode: PackagingMode) {
        invalidatePendingWork()
        mode = newMode
        UserDefaults.standard.set(newMode.rawValue, forKey: Self.lastUsedModeKey)
        report = nil
        validationAccepted = false
        validationProblemRoles = []
        recoveryText = nil
        traktorRefreshRequiresSave = false
        state = .waiting
        assignmentsNeedReview = hasAllFiles
        statusText = hasAllFiles
            ? "Review the assignments, then choose Accept Assignments."
            : "Add your master and four stem files, or import a five-file folder."
        refreshNativeReadiness()
    }

    func setFile(_ url: URL, for role: AudioRole) {
        guard !assignmentsLocked else { return }
        invalidatePendingWork()
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
        validationAccepted = false
        validationProblemRoles = []
        recoveryText = nil
        traktorRefreshRequiresSave = false
        state = .waiting
        assignmentsNeedReview = hasAllFiles
        statusText = hasAllFiles
            ? "Review the assignments. Drag files between slots to reassign them, then choose Accept Assignments."
            : "Add your master and four stem files, or import a five-file folder."
        if files[.master] != previousMaster, let master = files[.master] {
            title = master.deletingPathExtension().lastPathComponent
            startMetadataLoad(from: master)
        }
        refreshNativeReadiness()
    }

    func addStemFiles(_ urls: [URL]) {
        guard !assignmentsLocked else { return }
        var remainingRoles = AudioRole.allCases.filter { $0 != .master && files[$0] == nil }
        for url in urls where !remainingRoles.isEmpty {
            let role: AudioRole
            if let suggested = suggestedRole(for: url), suggested != .master,
               let index = remainingRoles.firstIndex(of: suggested) {
                role = suggested
                remainingRoles.remove(at: index)
            } else {
                role = remainingRoles.removeFirst()
            }
            setFile(url, for: role)
        }
    }

    func importFolder(_ directory: URL) {
        invalidatePendingWork()
        let supported = Set(["wav", "wave", "aif", "aiff", "m4a", "aac", "mp3"])
        report = nil
        validationAccepted = false
        do {
            let audioFiles = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
                .filter { supported.contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

            guard audioFiles.count == 5 else {
                assignmentsNeedReview = false
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
            validationAccepted = false
            validationProblemRoles = []
            recoveryText = nil
            assignmentsNeedReview = true
            state = .waiting
            statusText = "Review the assignments. Drag files between slots to reassign them, then choose Accept Assignments."
            if let master = files[.master] {
                title = master.deletingPathExtension().lastPathComponent
                startMetadataLoad(from: master)
            }
            refreshNativeReadiness()
        } catch {
            assignmentsNeedReview = false
            state = .failed("The folder could not be read. Choose it again or add the files manually.")
            statusText = "The folder could not be read. Choose it again or add the files manually."
            recoveryText = "Check that the folder still exists and is readable, then choose it again or add the files individually."
        }
    }

    func confirmAssignments() {
        guard assignmentsNeedReview, hasAllFiles else { return }
        assignmentsNeedReview = false
        statusText = "Checking compatibility…"
        validationTask?.cancel()
        validationTask = Task { [weak self] in
            await self?.validate()
        }
    }

    func editAssignments() {
        guard hasAllFiles else { return }
        assignmentsNeedReview = true
        report = nil
        validationAccepted = false
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
        invalidatePendingWork()
        files[role] = nil
        report = nil
        validationAccepted = false
        validationProblemRoles = []
        recoveryText = nil
        traktorRefreshRequiresSave = false
        assignmentsNeedReview = false
        state = .waiting
        statusText = "Add your master and four stem files, or import a five-file folder."
        if role == .master {
            cancelMetadataLoad()
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
            traktorAuditText = mode == .nativeLossless ? "Add a master to check its saved Traktor state." : nil
            traktorAuditHasProblem = false
        } else {
            refreshNativeReadiness()
        }
    }

    func startNewPackage() {
        guard canStartNewPackage else { return }
        invalidatePendingWork()
        cancelMetadataLoad()
        files.removeAll()
        report = nil
        validationAccepted = false
        nativeReadiness = nil
        traktorAuditText = mode == .nativeLossless ? "Add a master to check its saved Traktor state." : nil
        traktorAuditHasProblem = false
        traktorRefreshRequiresSave = false
        validationProblemRoles = []
        assignmentsNeedReview = false
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
        resetGeneration += 1
        statusText = "Ready for a new package. Add your master and four stem files, or import a five-file folder."
        refreshTraktorStatus()
    }

    private func invalidatePendingWork() {
        workflowGeneration += 1
        validationTask?.cancel()
        validationTask = nil
        readinessTask?.cancel()
        readinessTask = nil
    }

    private func cancelMetadataLoad() {
        metadataGeneration += 1
        metadataTask?.cancel()
        metadataTask = nil
    }

    func setCollection(_ url: URL?) {
        collectionURL = url
        if let url {
            UserDefaults.standard.set(url.path, forKey: Self.collectionPathKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.collectionPathKey)
        }
        observedCollectionModificationDate = modificationDate(for: url)
        refreshNativeReadiness()
    }

    func setStemsDirectory(_ url: URL?) {
        stemsDirectoryURL = url
        if let url {
            UserDefaults.standard.set(url.path, forKey: Self.stemsDirectoryPathKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.stemsDirectoryPathKey)
        }
        observedStemsModificationDate = modificationDate(for: url)
        refreshNativeReadiness()
    }

    func setAudioFolderBehavior(_ behavior: AudioFolderBehavior) {
        audioFolderBehavior = behavior
        UserDefaults.standard.set(behavior.rawValue, forKey: Self.audioFolderBehaviorKey)
    }

    func setFixedAudioFolder(_ url: URL?) {
        fixedAudioFolderURL = url
        if let url {
            UserDefaults.standard.set(url.path, forKey: Self.fixedAudioFolderPathKey)
            setAudioFolderBehavior(.fixedFolder)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.fixedAudioFolderPathKey)
        }
    }

    func recordAudioSelection(_ url: URL) {
        let directory = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        lastAudioFolderURL = directory
        UserDefaults.standard.set(directory.path, forKey: Self.lastAudioFolderPathKey)
    }

    func resetDetectedLocations() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.collectionPathKey)
        defaults.removeObject(forKey: Self.stemsDirectoryPathKey)
        let manager = FileManager.default
        let home = manager.homeDirectoryForCurrentUser
        collectionURL = Self.detectCollection(home: home, manager: manager)
        stemsDirectoryURL = Self.detectStemsDirectory(home: home, manager: manager)
        primeObservedTraktorFiles()
        refreshNativeReadiness()
    }

    func locationExists(_ url: URL?) -> Bool {
        guard let url else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    func refreshTraktorStatus() {
        traktorRunning = runningTraktorApplication() != nil
        traktorSavedStateMayBeStale = traktorRunning && mode == .nativeLossless && files[.master] != nil
        if !traktorRunning { traktorRefreshRequiresSave = false }
    }

    func pollTraktorStatus() async {
        let wasRunning = traktorRunning
        refreshTraktorStatus()
        let collectionDate = modificationDate(for: collectionURL)
        let stemsDate = modificationDate(for: stemsDirectoryURL)
        let collectionChanged = observedCollectionModificationDate != nil &&
            collectionDate != observedCollectionModificationDate
        let stemsChanged = observedStemsModificationDate != nil &&
            stemsDate != observedStemsModificationDate
        observedCollectionModificationDate = collectionDate
        observedStemsModificationDate = stemsDate

        guard mode == .nativeLossless,
              files[.master] != nil,
              collectionURL != nil,
              state != .packaging else { return }

        if (wasRunning && !traktorRunning) || collectionChanged || stemsChanged {
            await auditTraktorState(explainChange: true)
        }
    }

    func auditTraktorState(explainChange: Bool = false) async {
        refreshTraktorStatus()
        guard mode == .nativeLossless else {
            traktorAuditText = nil
            traktorAuditHasProblem = false
            return
        }
        guard let master = files[.master], let collectionURL else {
            traktorAuditText = files[.master] == nil
                ? "Add a master to check its saved Traktor state."
                : "Choose Traktor’s collection.nml to check the master."
            traktorAuditHasProblem = false
            return
        }

        let previous = nativeReadiness
        do {
            let result = try await EngineBridge().checkNativeReadiness(
                master: master, collection: collectionURL, stemsDirectory: stemsDirectoryURL
            )
            guard files[.master] == master, self.collectionURL == collectionURL else { return }
            nativeReadiness = result
            updateTraktorAuditSummary(result)
            let installedStateIsStillValid = isVerifiedInstalledState(result)

            if traktorRunning && result.collectionLinked && !result.linkedStemExists {
                traktorRefreshRequiresSave = true
                traktorAuditText = "SAVED STATE: Traktor’s saved collection still links this master, but the Stem file is missing. If you changed or removed the track in open Traktor, save and close Traktor so the app can read the current state."
            }

            guard explainChange, !assignmentsNeedReview, state != .validating else { return }
            if installedStateIsStillValid {
                return
            } else if case .complete = state {
                state = audioSetValidated ? .ready : .waiting
                statusText = result.found
                    ? "The previously installed Stem link is no longer complete in Traktor’s saved state."
                    : "The selected master is no longer present in Traktor’s saved collection."
                recoveryText = result.found
                    ? "Review the saved-state message and follow the orange next action to repair or replace the link."
                    : "Import and analyze this exact master in Traktor, then save and close Traktor so the app can verify it."
            } else if previous?.collectionLinked == true && !result.collectionLinked {
                state = audioSetValidated ? .ready : .waiting
                statusText = "Traktor’s saved collection no longer links this master to its Stem file."
                recoveryText = audioSetValidated
                    ? "The current package is ready to install again. Follow the orange install action."
                    : "Add or confirm the updated stems, then follow the orange install action."
            } else if previous?.ready == true && !result.ready {
                state = audioSetValidated ? .ready : .waiting
                statusText = "The selected master is no longer analyzed in Traktor’s saved collection."
                recoveryText = "Import and analyze this exact master in Traktor, then save or close Traktor so the app can verify it."
            } else if !traktorRunning && result.ready && audioSetValidated,
                      !isVerifiedInstalledState(result) {
                state = .ready
                statusText = result.collectionLinked
                    ? "Saved Traktor state verified. This master is analyzed and linked to a Stem file."
                    : "Saved Traktor state verified. This master is analyzed and ready for Stem installation."
            }
        } catch {
            traktorAuditText = "Traktor’s saved collection could not be checked: \(error.localizedDescription)"
            traktorAuditHasProblem = true
        }
    }

    private func updateTraktorAuditSummary(_ result: NativeReadiness) {
        let prefix = traktorRunning ? "SAVED STATE" : "VERIFIED"
        let suffix = traktorRunning ? " Recent changes in open Traktor may not be saved yet." : ""
        if !result.found {
            traktorAuditText = "\(prefix): This exact master is not in Traktor’s saved collection.\(suffix)"
            traktorAuditHasProblem = true
        } else if !result.hasAudioId {
            traktorAuditText = "\(prefix): The master is present but has not been analyzed.\(suffix)"
            traktorAuditHasProblem = true
        } else if result.collectionLinked && result.linkedStemExists {
            traktorAuditText = "\(prefix): The master is analyzed and its linked Stem file is present.\(suffix)"
            traktorAuditHasProblem = false
        } else if result.collectionLinked {
            traktorAuditText = "\(prefix): The master is linked, but its Stem file is missing.\(suffix)"
            traktorAuditHasProblem = true
        } else if result.linkedStemExists {
            traktorAuditText = "\(prefix): The master is analyzed. A Stem file exists but is not linked in Traktor.\(suffix)"
            traktorAuditHasProblem = false
        } else {
            traktorAuditText = "\(prefix): The master is analyzed and has no linked stems.\(suffix)"
            traktorAuditHasProblem = false
        }
    }

    private func modificationDate(for url: URL?) -> Date? {
        guard let url else { return nil }
        return try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private func packageFingerprint() -> String? {
        guard hasAllFiles else { return nil }
        var components: [String] = []
        for role in AudioRole.allCases {
            guard let url = files[role] else { return nil }
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            components.append([
                role.rawValue,
                url.standardizedFileURL.path,
                String(values?.fileSize ?? -1),
                String(values?.contentModificationDate?.timeIntervalSince1970 ?? -1)
            ].joined(separator: "|"))
        }
        for role in [AudioRole.drums, .bass, .other, .vocals] {
            components.append("\(role.rawValue)|\(stemNames[role] ?? role.rawValue)")
        }
        let digest = SHA256.hash(data: Data(components.joined(separator: "\n").utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func rememberInstalledPackage(destination: URL) {
        guard let fingerprint = packageFingerprint() else { return }
        let defaults = UserDefaults.standard
        defaults.set(fingerprint, forKey: Self.lastInstalledFingerprintKey)
        defaults.set(destination.path, forKey: Self.lastInstalledDestinationKey)
    }

    private func isVerifiedInstalledState(_ readiness: NativeReadiness) -> Bool {
        guard readiness.collectionLinked, readiness.linkedStemExists else { return false }
        if case .complete = state { return true }
        guard let current = packageFingerprint(),
              current == UserDefaults.standard.string(forKey: Self.lastInstalledFingerprintKey),
              let path = UserDefaults.standard.string(forKey: Self.lastInstalledDestinationKey),
              FileManager.default.fileExists(atPath: path) else { return false }
        state = .complete(URL(fileURLWithPath: path))
        statusText = "Installed and verified. This exact package is already linked to the selected Traktor master."
        recoveryText = "Load the original master in Traktor; it should open as a Stem Deck. Choose Edit Assignments or Start New Package before installing a different set."
        return true
    }

    private func primeObservedTraktorFiles() {
        observedCollectionModificationDate = modificationDate(for: collectionURL)
        observedStemsModificationDate = modificationDate(for: stemsDirectoryURL)
    }

    func refreshNativeReadiness() {
        readinessTask?.cancel()
        nativeReadiness = nil
        guard mode == .nativeLossless else {
            traktorAuditText = nil
            traktorAuditHasProblem = false
            return
        }
        guard
              let master = files[.master],
              let collection = collectionURL else {
            traktorAuditText = files[.master] == nil
                ? "Add a master to check its saved Traktor state."
                : "Choose Traktor’s collection.nml to check the master."
            traktorAuditHasProblem = false
            return
        }
        readinessTask = Task { [weak self] in
            do {
                let result = try await EngineBridge().checkNativeReadiness(
                    master: master, collection: collection, stemsDirectory: self?.stemsDirectoryURL
                )
                guard !Task.isCancelled,
                      self?.files[.master] == master,
                      self?.collectionURL == collection else { return }
                guard let self else { return }
                self.nativeReadiness = result
                self.updateTraktorAuditSummary(result)
                _ = self.isVerifiedInstalledState(result)
            } catch {
                guard !Task.isCancelled else { return }
                self?.nativeReadiness = NativeReadiness(
                    ready: false, found: false, hasAudioId: false, linkedStemExists: false,
                    collectionLinked: false,
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
            updateTraktorAuditSummary(result)
            if result.ready {
                statusText = traktorRunning
                    ? "The saved collection contains this master. Because Traktor is open, the app will close it and verify the current saved state before installation."
                    : "Analyzed master found. Add or confirm the four stems, then continue."
            } else if traktorRunning {
                statusText = "The analyzed master is not in Traktor’s saved collection yet. Finish analysis, then save or close Traktor."
                recoveryText = "Traktor writes the new track ID when it saves its collection. Use the orange Close Traktor button; the app will verify the saved ID and continue automatically."
            } else {
                statusText = result.message
                recoveryText = "Choose Drag Stereo Master into Traktor below. Drop that exact file into Traktor’s Track Collection—not onto a deck—and let analysis finish."
            }
        } catch {
            nativeReadiness = NativeReadiness(
                ready: false, found: false, hasAudioId: false, linkedStemExists: false,
                collectionLinked: false, message: error.localizedDescription
            )
            traktorAuditText = "Traktor’s saved collection could not be checked: \(error.localizedDescription)"
            traktorAuditHasProblem = true
            statusText = "Traktor’s collection could not be checked."
            recoveryText = "Confirm the Collection path points to collection.nml. The app will check again automatically."
        }
    }

    func refreshTraktorStateFromUser() async {
        await auditTraktorState(explainChange: true)
        guard mode == .nativeLossless, files[.master] != nil else { return }
        if traktorRunning {
            traktorRefreshRequiresSave = true
            let savedSummary = traktorAuditText ?? "Traktor’s saved collection was checked."
            traktorAuditText = "\(savedSummary) Traktor is still open, so unsaved changes cannot be read yet."
            statusText = "The saved Traktor collection was refreshed. Open Traktor may still contain unsaved changes."
            recoveryText = "Choose Save & Quit Traktor, Then Refresh to save the current Traktor state and update this app automatically."
        } else {
            traktorRefreshRequiresSave = false
            statusText = "Traktor’s saved collection and Stem folder were refreshed."
            recoveryText = nil
        }
    }

    func saveQuitTraktorAndRefresh() async {
        refreshTraktorStatus()
        guard let traktor = runningTraktorApplication(), let collectionURL else {
            traktorRefreshRequiresSave = false
            await auditTraktorState(explainChange: true)
            return
        }

        let traktorURL = traktor.bundleURL
        state = .packaging
        recoveryText = nil
        guard await closeTraktorAndWait(traktor) else { return }

        statusText = "Traktor closed. Reading its newly saved collection…"
        let readiness = await recheckNativeReadinessAfterTraktorQuit(
            master: files[.master], collection: collectionURL
        )
        traktorRefreshRequiresSave = false

        guard let readiness else {
            state = audioSetValidated ? .ready : .waiting
            statusText = "Traktor closed, but its saved collection could not be read."
            recoveryText = "Confirm the Collection path below, then choose Refresh Traktor Status."
            return
        }

        if readiness.ready {
            if isVerifiedInstalledState(readiness) {
                statusText = "Saved Traktor state refreshed. This exact package remains installed and linked."
                recoveryText = "Load the original master in Traktor; it should open as a Stem Deck."
            } else {
                state = audioSetValidated ? .ready : .waiting
                statusText = audioSetValidated
                    ? "Saved Traktor state refreshed. The analyzed master is ready for lossless Stem installation."
                    : "Saved Traktor state refreshed. The analyzed master was found. Add the remaining stems."
                recoveryText = audioSetValidated
                    ? "Choose Verify & Install Lossless Stems."
                    : "Add the remaining four stem files individually or use Import Folder."
            }
            return
        }

        state = audioSetValidated ? .ready : .waiting
        statusText = readiness.found
            ? "The master is saved in Traktor but has not finished analysis."
            : "The exact stereo master is missing from Traktor’s newly saved collection."
        recoveryText = "Traktor will reopen and Finder will highlight the exact master. Drag it into Traktor’s Track Collection—not onto a deck—and let analysis finish."
        if let traktorURL {
            _ = NSWorkspace.shared.open(traktorURL)
            try? await Task.sleep(nanoseconds: 700_000_000)
            refreshTraktorStatus()
            revealMasterInFinder()
        }
    }

    func saveAndQuitAfterAnalysis() async {
        await saveQuitTraktorAndRefresh()
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
            if traktorRunning {
                statusText = "The stereo master is highlighted in Finder. Confirm that this exact file is still in Traktor’s Track Collection."
                recoveryText = "If it is missing, drag the highlighted file into Track Collection—not onto a deck—and let analysis finish. The app will verify Traktor’s saved state before installation."
            } else {
                statusText = "The analyzed stereo master is highlighted in Finder."
                recoveryText = hasAllFiles
                    ? "Return here and follow the orange install button."
                    : "Add the four matching stems to continue."
            }
        } else {
            statusText = "The master is not currently in Traktor’s saved collection. Import the highlighted stereo master to continue."
            recoveryText = "Drag the highlighted file into Traktor’s Track Collection—not onto a deck—and let Traktor finish analyzing it. Then return here and follow the orange next-action button."
        }
    }

    func setArtwork(_ url: URL?) {
        discardExtractedArtwork()
        artworkURL = url
    }

    private func startMetadataLoad(from url: URL) {
        cancelMetadataLoad()
        let generation = metadataGeneration
        metadataTask = Task { [weak self] in
            await self?.loadMasterMetadata(from: url, generation: generation)
        }
    }

    private func loadMasterMetadata(from url: URL, generation: Int) async {
        do {
            let bridge = try EngineBridge()
            let metadata = try await bridge.readMasterMetadata(master: url)
            guard !Task.isCancelled,
                  metadataGeneration == generation,
                  files[.master] == url else { return }
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
        let generation = workflowGeneration
        let validationFiles = files
        let validationMode = mode
        validationAccepted = false
        state = .validating
        statusText = "Checking sample rate, channels, duration and stem-sum peak…"
        recoveryText = nil
        do {
            let bridge = try EngineBridge()
            let result = try await bridge.validate(files: validationFiles, mode: validationMode)
            guard !Task.isCancelled,
                  workflowGeneration == generation,
                  files == validationFiles,
                  mode == validationMode else { return }
            report = result
            validationProblemRoles = []
            validationAccepted = true
            state = .ready
            statusText = result.limiterEnabled
                ? String(format: "Accepted. All five files match. Peak protection is enabled at a −0.3 dBFS ceiling because the combined peak is %.1f dBFS.", result.stemSumTruePeakDbfs)
                : String(format: "Accepted. All five files match. Peak protection is not needed; the combined peak is %.1f dBFS.", result.stemSumTruePeakDbfs)
            if mode == .nativeLossless, let readiness = nativeReadiness {
                _ = isVerifiedInstalledState(readiness)
            }
        } catch {
            guard !Task.isCancelled,
                  workflowGeneration == generation,
                  files == validationFiles,
                  mode == validationMode else { return }
            validationAccepted = false
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

        let warning = NSAlert()
        if traktor != nil {
            warning.messageText = "Close Traktor, verify its saved collection, and continue?"
            warning.informativeText = "The app will ask Traktor to close so its latest library state is saved. It will confirm that this exact master still exists and is analyzed before installing anything, then reopen Traktor."
        } else {
            warning.messageText = "Verify and install lossless stems?"
            warning.informativeText = "The app will recheck the saved collection, verify all five decoded PCM streams, back up collection.nml, install the lossless sidecar, and link it to the exact master track."
        }
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
        statusText = "Verifying Traktor’s latest saved collection…"
        let readiness = await recheckNativeReadinessAfterTraktorQuit(
            master: files[.master],
            collection: collectionURL
        )
        guard readiness?.ready == true else {
            state = .ready
            statusText = "The stereo master is not in Traktor’s latest saved collection. Import and analyze it before installing the lossless stems."
            recoveryText = "Open Traktor and drag the exact master selected in this app into Track Collection—not onto a deck. Let analysis finish, then return here and follow the orange next-action button. No collection or Stem files were changed."
            if shouldRelaunch, let traktorURL {
                _ = NSWorkspace.shared.open(traktorURL)
                try? await Task.sleep(nanoseconds: 700_000_000)
                refreshTraktorStatus()
                revealMasterInFinder()
            }
            return
        }

        if readiness?.linkedStemExists == true {
            let replacement = NSAlert()
            replacement.messageText = "Replace the existing linked stems?"
            replacement.informativeText = "The latest saved Traktor collection already links this master to a Stem file. Replace Existing will install this set and keep the previous file as a timestamped .bak safety backup. The .bak file is not a second active Stem set."
            replacement.alertStyle = .warning
            replacement.addButton(withTitle: "Replace Existing")
            replacement.addButton(withTitle: "Cancel")
            guard replacement.runModal() == .alertFirstButtonReturn else {
                state = .ready
                statusText = "Installation cancelled. The existing linked stems were not changed."
                recoveryText = nil
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
            rememberInstalledPackage(destination: destination)
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
                updateTraktorAuditSummary(result)
                if result.ready { return result }
                if attempt < 7 { try await Task.sleep(nanoseconds: 250_000_000) }
            } catch {
                nativeReadiness = NativeReadiness(
                    ready: false, found: false, hasAudioId: false, linkedStemExists: false,
                    collectionLinked: false,
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
        prompt.messageText = "Traktor is still open"
        prompt.informativeText = "No macOS Automation permission is required. Choose Bring Traktor Forward, then quit Traktor normally with Traktor Pro > Quit Traktor Pro 4 or Command-Q. Leave Traktor Stem Packager open; it will detect the closure and continue automatically. No files have been changed."
        prompt.alertStyle = .warning
        prompt.addButton(withTitle: "Bring Traktor Forward")
        prompt.addButton(withTitle: "I’ll Quit It Now")
        prompt.addButton(withTitle: "Cancel Installation")
        let choice = prompt.runModal()
        if choice == .alertFirstButtonReturn {
            _ = application.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
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

    func openAppManagementSettings() {
        openPrivacyPane(anchor: "Privacy_AppBundles")
    }

    private func openPrivacyPane(anchor: String) {
        guard let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"),
              NSWorkspace.shared.open(settingsURL) else {
            openPrivacyAndSecurity()
            return
        }
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
