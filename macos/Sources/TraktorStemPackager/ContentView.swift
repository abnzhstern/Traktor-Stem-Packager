import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: PackagerModel
    @EnvironmentObject private var updateChecker: UpdateChecker
    @State private var showDetails = false
    @State private var showWorkflowGuide = false
    @AppStorage("hideWorkflowGuideOnLaunch") private var hideWorkflowGuideOnLaunch = false

    private let panel = Color(red: 0.105, green: 0.11, blue: 0.125)
    private let background = Color(red: 0.065, green: 0.068, blue: 0.078)

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            ScrollView {
                VStack(spacing: 14) {
                    modePanel
                    workflowStepPanel
                    if model.mode == .portableAAC {
                        metadataPanel
                    } else {
                        nativeConfigPanel
                    }
                    tracksPanel
                    statusPanel
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(0)
            footer
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(10)
        }
        .frame(minWidth: 720, idealWidth: 780, minHeight: 520, idealHeight: 760)
        .background(background)
        .preferredColorScheme(.dark)
        .onAppear {
            if !hideWorkflowGuideOnLaunch { showWorkflowGuide = true }
        }
        .sheet(isPresented: $showWorkflowGuide) {
            workflowGuide
        }
        .task { await updateChecker.checkAutomatically() }
        .task {
            while !Task.isCancelled {
                await model.pollTraktorStatus()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
        .alert(item: $updateChecker.notice) { notice in
            if notice.offersDownload {
                return Alert(
                    title: Text(notice.title),
                    message: Text(notice.message),
                    primaryButton: .default(Text("Download Update")) { updateChecker.openLatestRelease() },
                    secondaryButton: .cancel(Text("Not Now"))
                )
            }
            return Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var workflowStepPanel: some View {
        let step = currentWorkflowStep
        return HStack(alignment: .center, spacing: 11) {
            Image(systemName: step.icon)
                .font(.system(size: 16))
                .foregroundStyle(step.color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(step.label)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.0)
                    .foregroundStyle(step.color.opacity(0.9))
                Text(step.message)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if model.mode == .nativeLossless,
               model.files[.master] != nil,
               model.nativeReadiness?.ready == false,
               model.state != .packaging {
                VStack(alignment: .trailing, spacing: 6) {
                    if model.traktorRunning {
                        Button(model.canResolveUnsavedAnalysis ? "SAVE, QUIT TRAKTOR & INSTALL" : "SAVE & QUIT TRAKTOR") {
                            if model.canResolveUnsavedAnalysis {
                                Task { await model.create() }
                            } else {
                                Task { await model.saveAndQuitAfterAnalysis() }
                            }
                        }
                        .font(.system(size: 9, weight: .semibold))
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        Button("SHOW MASTER IN FINDER") { model.revealMasterInFinder() }
                            .font(.system(size: 9, weight: .semibold))
                            .buttonStyle(.bordered)
                    } else {
                        Button("DRAG STEREO MASTER INTO TRAKTOR") { model.openTraktorAndRevealMaster() }
                            .font(.system(size: 9, weight: .semibold))
                            .buttonStyle(.borderedProminent)
                    }
                    Button("CHECK TRAKTOR AGAIN") {
                        Task { await model.checkTraktorForMaster() }
                    }
                    .font(.system(size: 9, weight: .semibold))
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(12)
        .background(step.color.opacity(0.07))
        .overlay(Rectangle().stroke(step.color.opacity(0.18)))
    }

    private var currentWorkflowStep: (label: String, message: String, icon: String, color: Color) {
        switch model.state {
        case .validating:
            return ("CHECKING FILES", "Verifying format, duration, synchronization and peak level…", "waveform", .blue)
        case .packaging:
            return ("WORKING", model.statusText, "gearshape.2.fill", .blue)
        case .complete:
            return ("COMPLETE", model.statusText, "checkmark.circle.fill", .green)
        case .failed:
            return ("ACTION NEEDED", model.statusText, "exclamationmark.triangle.fill", .orange)
        default:
            break
        }

        if model.folderImportNeedsReview {
            return ("REVIEW ASSIGNMENTS", "Check all five slots. Drag any file onto another slot to reassign it, then choose Accept Assignments.", "hand.draw.fill", .orange)
        }

        if model.mode == .portableAAC {
            if !model.hasAllFiles {
                return ("STEP 1", "Add your master and four stem files, or import a five-file folder.", "1.circle.fill", .blue)
            }
            return ("STEP 2", "Review the metadata, then create the AAC Stem file. Drag the finished .stem.mp4 directly into Traktor; all four stems will be present.", "2.circle.fill", .green)
        }

        if model.files[.master] == nil {
            return ("STEP 1", "Add the stereo master in the Master slot below, add all five files individually, or use Import Folder.", "1.circle.fill", .blue)
        }
        if model.collectionURL == nil || model.stemsDirectoryURL == nil {
            return ("STEP 2", "Confirm the Traktor Collection and Stems folder locations below.", "2.circle.fill", .blue)
        }
        if model.nativeReadiness == nil {
            return ("CHECKING TRAKTOR", "Checking the master against Traktor’s saved collection…", "magnifyingglass.circle.fill", .blue)
        }
        if model.nativeReadiness?.ready == false {
            if model.traktorRunning {
                return ("NEXT ACTION", model.canResolveUnsavedAnalysis
                    ? "Let Traktor finish analyzing the stereo master. Then choose Save, Quit Traktor & Install. Traktor may briefly say Updating Settings while it saves; that is normal."
                    : "Let Traktor finish analyzing the stereo master. Then choose Save & Quit Traktor. Traktor may briefly say Updating Settings while it saves; that is normal.", "arrow.right.circle.fill", .orange)
            }
            return ("STEP 3", "Before lossless stems can be installed, the exact stereo master must be analyzed. Choose Drag Stereo Master into Traktor, then drop it into the Track Collection—not onto a deck.", "3.circle.fill", .blue)
        }
        if !model.hasAllFiles {
            return ("STEP 4", "The analyzed master was found. Add the remaining four stems or import their five-file folder.", "4.circle.fill", .blue)
        }
        return ("READY TO INSTALL", "The analyzed master and all five files are ready. Choose Verify & Install Lossless Stems below.", "checkmark.circle.fill", .green)
    }

    private var workflowGuide: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 58, height: 58)
                VStack(alignment: .leading, spacing: 4) {
                    Text("BEFORE YOU BEGIN")
                        .font(.system(size: 16, weight: .bold))
                        .tracking(0.8)
                    Text("Choose the workflow that matches your goal.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("THIS APP PACKAGES EXISTING STEMS FOR TRAKTOR")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.6)
                Text("It does not separate a finished song or create stems. Use four stems you created yourself or received from a producer, composer, label, or stem-separation service, plus the matching stereo master. Add them individually or use Import Folder to auto-assign a five-file folder for review.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.blue.opacity(0.08))
            .overlay(Rectangle().stroke(Color.blue.opacity(0.22)))

            guideRow(
                icon: "shippingbox.fill",
                title: "AAC Stem File",
                detail: "The easiest workflow. No Traktor preparation is required. Create one shareable 320 kbps AAC .stem.mp4, then drag that finished file directly into Traktor. Its four stems are already packaged inside."
            )
            guideRow(
                icon: "waveform.badge.checkmark",
                title: "Lossless Traktor Installation",
                detail: "The exact stereo master must be in Traktor and analyzed before lossless stems can be installed. Add it here first so the app can check. If it is already analyzed, that step is skipped. Otherwise drag the highlighted master into Traktor’s Track Collection—not onto a deck—so Traktor adds and analyzes it. You may add the four stems before or after this step."
            )

            Text("Important: use the same master file in both Traktor and this app. A different copy may create a separate library entry and will not inherit the original track’s cues or beat grid.")
                .font(.system(size: 10))
                .foregroundStyle(Color.orange.opacity(0.9))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08))
                .overlay(Rectangle().stroke(Color.orange.opacity(0.22)))

            HStack {
                Button(hideWorkflowGuideOnLaunch ? "SHOW AT LAUNCH" : "DON’T SHOW AGAIN") {
                    if hideWorkflowGuideOnLaunch {
                        hideWorkflowGuideOnLaunch = false
                    } else {
                        hideWorkflowGuideOnLaunch = true
                        showWorkflowGuide = false
                    }
                }
                .buttonStyle(.bordered)
                Button("QUIT APP") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("CLOSE") {
                    showWorkflowGuide = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 590)
        .background(background)
        .preferredColorScheme(.dark)
    }

    private func guideRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(Color.white.opacity(0.8))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(panel)
    }

    private var modePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CHOOSE YOUR RESULT")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(Color.white.opacity(0.45))
            HStack(spacing: 10) {
                ForEach(PackagingMode.allCases) { mode in
                    Button { model.setMode(mode) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: mode == .portableAAC ? "shippingbox.fill" : "waveform.badge.checkmark")
                                .font(.system(size: 19))
                                .foregroundStyle(model.mode == mode ? Color.white : Color.white.opacity(0.42))
                                .frame(width: 26)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(mode.title)
                                    .font(.system(size: 12, weight: .semibold))
                                Text(mode.subtitle)
                                    .font(.system(size: 9))
                                    .foregroundStyle(Color.white.opacity(0.45))
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: model.mode == mode ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(model.mode == mode ? Color.green : Color.white.opacity(0.2))
                        }
                        .padding(11)
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .background(model.mode == mode ? Color.white.opacity(0.09) : Color.white.opacity(0.035))
                        .overlay(Rectangle().stroke(model.mode == mode ? Color.white.opacity(0.2) : Color.white.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(panel)
    }

    private var nativeConfigPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TRAKTOR LOCATIONS")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(Color.white.opacity(0.45))
            pathRow(
                label: "Collection",
                url: model.collectionURL,
                emptyText: "Choose collection.nml",
                action: chooseCollection
            )
            pathRow(
                label: "Stems folder",
                url: model.stemsDirectoryURL,
                emptyText: "Choose Traktor’s configured Stems folder",
                action: chooseStemsDirectory
            )
        }
        .padding(14)
        .background(panel)
    }

    private func pathRow(label: String, url: URL?, emptyText: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.4))
                .frame(width: 78, alignment: .trailing)
            Text(url?.path(percentEncoded: false) ?? emptyText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(url == nil ? Color.white.opacity(0.32) : Color.white.opacity(0.72))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("CHOOSE", action: action)
                .font(.system(size: 9, weight: .semibold))
        }
    }

    private var titleBar: some View {
        HStack {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 5) {
                Text("TRAKTOR STEM PACKAGER")
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(0.7)
                Text("LUCKYSTAR PRODUCTIONS")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(2.2)
                    .foregroundStyle(Color.white.opacity(0.46))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("v0.6.0-beta.11")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.62))
                Text("AAC + VERIFIED LOSSLESS")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.35))
                Button("HOW IT WORKS") { showWorkflowGuide = true }
                    .buttonStyle(.plain)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 72)
        .background(Color(red: 0.17, green: 0.18, blue: 0.20))
    }

    private var metadataPanel: some View {
        HStack(alignment: .top, spacing: 14) {
            Button(action: chooseArtwork) {
                ZStack {
                    Rectangle().fill(Color.white.opacity(0.055))
                    if let url = model.artworkURL, let image = NSImage(contentsOf: url) {
                        Image(nsImage: image).resizable().scaledToFill()
                    } else {
                        VStack(spacing: 5) {
                            Image(systemName: "photo.badge.plus").font(.system(size: 22))
                            Text("ARTWORK").font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(Color.white.opacity(0.35))
                    }
                }
                .frame(width: 112, height: 112)
                .clipped()
                .overlay(Rectangle().stroke(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help("Choose JPEG or PNG artwork")

            VStack(spacing: 9) {
                metadataRow("Track", text: $model.title, placeholder: "Track title")
                metadataRow("Artist", text: $model.artist, placeholder: "Artist")
                metadataRow("Album", text: $model.album, placeholder: "Album")
                HStack(spacing: 12) {
                    metadataRow("Producer", text: $model.producer, placeholder: "Producer", labelWidth: 56)
                    metadataRow("Label", text: $model.label, placeholder: "Label", labelWidth: 36)
                }
                HStack(spacing: 12) {
                    metadataRow("Genre", text: $model.genre, placeholder: "Genre", labelWidth: 56)
                    metadataRow("Released", text: $model.releaseDate, placeholder: "YYYY-MM-DD", labelWidth: 52)
                }
            }
        }
        .padding(14)
        .background(panel)
    }

    private func metadataRow(_ label: String, text: Binding<String>, placeholder: String, labelWidth: CGFloat = 48) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.38))
                .frame(width: labelWidth, alignment: .trailing)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 8)
                .frame(height: 25)
                .background(Color.white.opacity(0.055))
                .overlay(Rectangle().stroke(Color.white.opacity(0.08)))
        }
    }

    private var tracksPanel: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("ADD YOUR AUDIO FILES")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(Color.white.opacity(0.45))
                Spacer()
                if model.folderImportNeedsReview {
                    Text("REVIEW • DRAG TO REASSIGN")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.orange)
                    Button("ACCEPT ASSIGNMENTS") { model.confirmFolderAssignments() }
                        .font(.system(size: 9, weight: .semibold))
                        .buttonStyle(.borderedProminent)
                        .tint(Color.orange.opacity(0.8))
                } else if model.state == .validating {
                    ProgressView().controlSize(.small)
                    Text("CHECKING FILES")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.blue.opacity(0.9))
                } else if model.audioSetValidated {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.green)
                    Text("ACCEPTED • ASSIGNMENTS LOCKED")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.green)
                    Button("EDIT ASSIGNMENTS") { model.editAssignments() }
                        .font(.system(size: 9, weight: .semibold))
                        .buttonStyle(.bordered)
                } else if case .failed = model.state {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.red)
                    Text(model.validationProblemRoles.isEmpty ? "ACTION NEEDED" : "CHECK HIGHLIGHTED FILES")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.red)
                } else {
                    Text("MASTER + 4 STEMS")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.32))
                }
                if !model.folderImportNeedsReview {
                    Button("IMPORT FOLDER") { chooseAudioFolder() }
                        .font(.system(size: 9, weight: .semibold))
                        .buttonStyle(.bordered)
                }
                if !model.files.isEmpty {
                    Button("CLEAR ALL") { model.clearAll() }
                        .font(.system(size: 9, weight: .semibold))
                        .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 2)

            ForEach([AudioRole.master, .drums, .bass, .other, .vocals]) { role in
                FileDropRow(
                    role: role,
                    displayName: stemNameBinding(role),
                    url: model.files[role],
                    isValidated: model.audioSetValidated,
                    isLocked: model.assignmentsLocked,
                    hasProblem: model.validationProblemRoles.contains(role),
                    select: { model.setFile($0, for: role) },
                    clear: { model.clear(role) }
                )
            }
        }
        .padding(10)
        .background(model.audioSetValidated ? Color.green.opacity(0.035) : panel)
        .overlay(Rectangle().stroke(model.audioSetValidated ? Color.green.opacity(0.35) : Color.clear))
    }

    private var statusPanel: some View {
        VStack(spacing: 0) {
            Button { showDetails.toggle() } label: {
                HStack(spacing: 9) {
                    if model.state == .validating || model.state == .packaging {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: statusIcon).foregroundStyle(statusColor)
                    }
                    Text(model.statusText)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .lineLimit(2)
                    Spacer()
                    Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.35))
                }
                .contentShape(Rectangle())
                .padding(12)
            }
            .buttonStyle(.plain)

            if showDetails, let report = model.report {
                Divider().overlay(Color.white.opacity(0.08))
                Text("\(report.sampleRate) Hz  •  Stereo  •  \(duration(report.duration))  •  Stem sum \(report.stemSumTruePeakDbfs, specifier: "%.1f") dBFS  •  Peak protection \(report.limiterEnabled ? "enabled (−0.3 dBFS ceiling)" : "not needed")")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }

            if let recovery = model.recoveryText {
                Divider().overlay(Color.white.opacity(0.08))
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .foregroundStyle(Color.orange.opacity(0.9))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("WHAT TO DO NEXT")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(Color.orange.opacity(0.9))
                        Text(recovery)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.68))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
            }
        }
        .background(panel)
    }

    private var footer: some View {
        HStack {
            Text("Source files are never altered")
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.32))
            Spacer()
            if case .complete = model.state {
                Button("SHOW IN FINDER") { model.revealOutput() }
            }
            if model.mode == .portableAAC || model.nativeReadiness?.ready == true {
                Button(model.primaryActionTitle) {
                    Task { await model.create() }
                }
                    .buttonStyle(.borderedProminent)
                    .tint(model.mode == .nativeLossless && model.canCreate ? .orange : Color(red: 0.32, green: 0.34, blue: 0.37))
                    .disabled(!(model.canCreate || model.canResolveUnsavedAnalysis))
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 58)
        .background(Color(red: 0.14, green: 0.145, blue: 0.16))
    }

    private func stemNameBinding(_ role: AudioRole) -> Binding<String> {
        Binding(
            get: { model.stemNames[role] ?? role.rawValue },
            set: { model.stemNames[role] = $0 }
        )
    }

    private func chooseArtwork() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK { model.setArtwork(panel.url) }
    }

    private func chooseAudioFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.message = "Choose a folder containing one stereo master and four stems"
        if panel.runModal() == .OK, let directory = panel.url {
            model.importFolder(directory)
        }
    }

    private func chooseCollection() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.xml]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose Traktor Pro 4 collection.nml"
        if panel.runModal() == .OK { model.setCollection(panel.url) }
    }

    private func chooseStemsDirectory() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Choose the Stems folder configured in Traktor Pro 4"
        if panel.runModal() == .OK { model.setStemsDirectory(panel.url) }
    }

    private var statusIcon: String {
        switch model.state {
        case .ready, .complete: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        default: "info.circle.fill"
        }
    }

    private var statusColor: Color {
        switch model.state {
        case .ready, .complete: .green
        case .failed: .red
        default: Color.white.opacity(0.35)
        }
    }

    private func duration(_ seconds: Double) -> String {
        let whole = Int(seconds.rounded())
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}
