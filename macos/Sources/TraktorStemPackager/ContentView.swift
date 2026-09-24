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
               !model.assignmentsNeedReview,
               model.state != .packaging {
                VStack(alignment: .trailing, spacing: 6) {
                    if model.nativeReadiness?.ready == false {
                        if model.traktorRunning {
                            Button(model.canResolveUnsavedAnalysis ? "CLOSE TRAKTOR & INSTALL" : "CLOSE TRAKTOR & CHECK MASTER") {
                                if model.canResolveUnsavedAnalysis {
                                    Task { await model.create() }
                                } else {
                                    Task { await model.saveAndQuitAfterAnalysis() }
                                }
                            }
                            .font(.system(size: 9, weight: .semibold))
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                        } else {
                            Button("OPEN TRAKTOR & SHOW MASTER") { model.openTraktorAndRevealMaster() }
                                .font(.system(size: 9, weight: .semibold))
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)
                        }
                    }
                    Button("SHOW MASTER IN FINDER") { model.revealMasterInFinder() }
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
            return ("ACTION NEEDED", model.statusText, "exclamationmark.triangle.fill", .red)
        default:
            break
        }

        if model.assignmentsNeedReview {
            return ("REVIEW ASSIGNMENTS", "Check all five slots. Drag any file onto another slot to reassign it, then choose Accept Assignments.", "hand.draw.fill", .blue)
        }

        if model.mode == .portableAAC {
            if !model.hasAllFiles {
                return ("STEP 1", "Add your master and four stem files, or import a five-file folder.", "1.circle.fill", .blue)
            }
            return ("STEP 2", "Review the metadata, then create the AAC Stem file. Drag the finished .stem.mp4 directly into Traktor; all four stems will be present.", "2.circle.fill", .green)
        }

        if model.files[.master] == nil {
            return ("STEP 1", "Start by adding the stereo master in the Master slot. You may also add the four stems now—individually or with Import Folder—or add them later.", "1.circle.fill", .blue)
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
                    ? "Let Traktor finish analyzing the stereo master. Then choose Close Traktor & Install. The app will close Traktor, verify the saved analysis, install the stems, and reopen Traktor."
                    : "Let Traktor finish analyzing the stereo master. Then choose Close Traktor & Check Master. The app will close Traktor, verify the saved analysis, and reopen it.", "arrow.right.circle.fill", .blue)
            }
            return ("STEP 3", "Traktor must analyze the exact stereo master before lossless stems can be installed. Choose Open Traktor & Show Master, then drag the highlighted file into Track Collection—not onto a deck.", "3.circle.fill", .blue)
        }
        if model.traktorRunning && model.hasAllFiles {
            return ("READY TO VERIFY", "Traktor is open, so its current library state may not be saved yet. Choose Close Traktor & Verify / Install. The app will save and recheck the latest collection before changing anything.", "checkmark.circle.fill", .blue)
        }
        if !model.hasAllFiles {
            return ("STEP 4", "The analyzed master was found. Add the remaining four stems or import their five-file folder.", "4.circle.fill", .blue)
        }
        return ("READY TO INSTALL", "The analyzed master and all five files are ready. Choose Verify & Install Lossless Stems below.", "checkmark.circle.fill", .green)
    }

    private var workflowGuide: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Image(nsImage: NSApplication.shared.applicationIconImage)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 58, height: 58)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("HOW TO USE TRAKTOR STEM PACKAGER")
                                .font(.system(size: 16, weight: .bold))
                                .tracking(0.6)
                            Text("Choose one of the two workflows below.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.72))
                        }
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text("THIS APP PACKAGES EXISTING STEMS")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.7)
                        Text("It does not create or separate stems. Start with one stereo master and four matching stem files. Add them individually or use Import Folder.")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.65))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.035))
                    .overlay(Rectangle().stroke(Color.white.opacity(0.08)))

                    Text("CHOOSE ONE OF TWO WORKFLOWS")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.0)
                        .foregroundStyle(Color.white.opacity(0.76))

                    workflowGuideCard(
                        number: "1",
                        icon: "shippingbox.fill",
                        accent: .cyan,
                        title: "AAC STEM FILE",
                        bestFor: "Choose this for the simplest, shareable Stem file.",
                        result: "Creates one 320 kbps AAC .stem.mp4.",
                        steps: [
                            "Add the stereo master and four stems.",
                            "Review the embedded title, artist, album and artwork.",
                            "Create the file, then drag it directly into Traktor."
                        ],
                        note: "Traktor treats the finished file as a new track. Standard metadata is copied, but cues, beat grids, loops and play history from a separate master entry do not transfer automatically."
                    )

                    workflowGuideCard(
                        number: "2",
                        icon: "waveform.badge.checkmark",
                        accent: Color(red: 0.82, green: 0.20, blue: 0.96),
                        title: "LOSSLESS TRAKTOR INSTALLATION",
                        bestFor: "Choose this to preserve source PCM and keep the existing Traktor master entry.",
                        result: "Creates a linked lossless Stem file for the original master.",
                        steps: [
                            "Add the stereo master and four matching stems to this app.",
                            "Already in Traktor? Select the exact same master file that Traktor analyzed. The app links the four stems to that existing track and preserves its cues, beat grid, loops and other Traktor data.",
                            "Not in Traktor? The app walks you through importing and analyzing the master, then links the four stems to it as a new track.",
                            "Follow the single orange action. The app verifies Traktor’s saved collection, installs the stems and reopens Traktor."
                        ],
                        note: "In both cases, load the stereo master in Traktor to use the four linked lossless stems. A duplicate master stored in another folder may be treated as a different track."
                    )

                    HStack(spacing: 9) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.orange)
                            .frame(width: 18, height: 10)
                        Text("In the main window, orange always marks the one action to take next.")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.7))
                    }
                    .padding(.horizontal, 2)

                    VStack(alignment: .leading, spacing: 7) {
                        Text("ONE-TIME MAC SECURITY SETUP")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.6)
                        Text("This free build is not Apple-notarized. Only use a settings button after macOS displays the matching warning; opening a pane by itself does not create a permission entry.")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.white.opacity(0.62))
                            .fixedSize(horizontal: false, vertical: true)
                        securityStep("1", "If macOS blocks the first launch, open Privacy & Security, scroll to Security, choose Open Anyway, then confirm Open.")
                        securityStep("2", "If the installer says Terminal was prevented from modifying apps, open App Management and enable Terminal. Terminal may not appear until macOS has actually blocked an installation attempt.")
                        securityStep("3", "Closing Traktor does not require Automation permission. The app first asks Traktor to quit normally. If Traktor stays open, press Command-Q in Traktor; this app detects the closure and continues.")
                        HStack(spacing: 8) {
                            Button("GENERAL SECURITY") { model.openPrivacyAndSecurity() }
                            Button("APP MANAGEMENT — ONLY IF PROMPTED") { model.openAppManagementSettings() }
                        }
                        .font(.system(size: 9, weight: .semibold))
                        .buttonStyle(.bordered)
                    }
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.035))
                    .overlay(Rectangle().stroke(Color.white.opacity(0.08)))
                }
                .padding(22)
            }

            Divider().overlay(Color.white.opacity(0.08))
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
                    showWorkflowGuide = false
                    DispatchQueue.main.async {
                        NSApplication.shared.terminate(nil)
                    }
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
            .padding(.horizontal, 22)
            .frame(height: 58)
            .background(Color(red: 0.11, green: 0.115, blue: 0.13))
        }
        .frame(width: 640, height: 720)
        .background(background)
        .preferredColorScheme(.dark)
    }

    private func workflowGuideCard(
        number: String,
        icon: String,
        accent: Color,
        title: String,
        bestFor: String,
        result: String,
        steps: [String],
        note: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                Text(number)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.85))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(accent))
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundStyle(accent)
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .tracking(0.5)
                Spacer()
            }
            Text(bestFor)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.82))
            Text(result)
                .font(.system(size: 11))
                .foregroundStyle(accent.opacity(0.9))
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(accent)
                            .frame(width: 15, alignment: .trailing)
                        Text(step)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.white.opacity(0.66))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Divider().overlay(accent.opacity(0.18))
            Text(note)
                .font(.system(size: 9.5))
                .foregroundStyle(Color.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.055))
        .overlay(Rectangle().stroke(accent.opacity(0.28), lineWidth: 1))
    }

    private func securityStep(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.82))
                .frame(width: 17, height: 17)
                .background(Circle().fill(Color.orange.opacity(0.9)))
            Text(text)
                .font(.system(size: 9.5))
                .foregroundStyle(Color.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var modePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CHOOSE ONE WORKFLOW")
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
            VStack(alignment: .leading, spacing: 2) {
                Text(url?.path(percentEncoded: false) ?? emptyText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(url == nil ? Color.white.opacity(0.32) : Color.white.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if url != nil && !model.locationExists(url) {
                    Text("DRIVE OR FOLDER UNAVAILABLE")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(Color.red)
                }
            }
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
                Text("v0.6.0-beta.18")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.62))
                Text("AAC + VERIFIED LOSSLESS")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.35))
                HStack(spacing: 12) {
                    Button { model.openTraktor() } label: {
                        Label(
                            model.traktorRunning ? "BRING TRAKTOR FORWARD" : "OPEN TRAKTOR",
                            systemImage: "play.rectangle.fill"
                        )
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 10)
                        .frame(height: 25)
                        .background(Color.black)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color.white.opacity(0.32), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    Button("HOW TO USE") { showWorkflowGuide = true }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                .font(.system(size: 9, weight: .semibold))
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
                if model.assignmentsNeedReview {
                    Text("REVIEW • DRAG TO REASSIGN")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.blue)
                    Button("ACCEPT ASSIGNMENTS") { model.confirmAssignments() }
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
                if !model.assignmentsNeedReview {
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
                        .foregroundStyle(Color.blue.opacity(0.9))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("WHAT TO DO NEXT")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(Color.blue.opacity(0.9))
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
                if model.mode == .portableAAC {
                    Button("OPEN TRAKTOR") { model.openTraktor() }
                        .buttonStyle(.bordered)
                    Button("SHOW STEM FILE IN FINDER") { model.revealOutput() }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                } else {
                    Button("SHOW INSTALLED STEM IN FINDER") { model.revealOutput() }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                }
            } else if model.mode == .portableAAC || model.nativeReadiness?.ready == true {
                Button(model.primaryActionTitle) {
                    Task { await model.create() }
                }
                    .buttonStyle(.borderedProminent)
                    .tint(model.canCreate ? .orange : Color(red: 0.32, green: 0.34, blue: 0.37))
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
