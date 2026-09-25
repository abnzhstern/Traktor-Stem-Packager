import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PreferencesView: View {
    @EnvironmentObject private var model: PackagerModel
    @AppStorage(PackagerModel.startupWorkflowKey) private var startupWorkflow = StartupWorkflow.rememberLastUsed.rawValue
    @AppStorage(PackagerModel.openTraktorAfterAACKey) private var openTraktorAfterAAC = false
    @AppStorage("hideWorkflowGuideOnLaunch") private var hideWorkflowGuideOnLaunch = false

    var body: some View {
        Form {
            Picker("Open with", selection: $startupWorkflow) {
                ForEach(StartupWorkflow.allCases) { workflow in
                    Text(workflow.title).tag(workflow.rawValue)
                }
            }

            Toggle("Open Traktor automatically after AAC export", isOn: $openTraktorAfterAAC)
            Toggle("Show Before You Begin at launch", isOn: showGuideBinding)

            Section("Audio Files") {
                Picker("Starting folder", selection: audioFolderBehaviorBinding) {
                    ForEach(AudioFolderBehavior.allCases) { behavior in
                        Text(behavior.title).tag(behavior)
                    }
                }
                if model.audioFolderBehavior == .fixedFolder {
                    locationRow("Audio folder", url: model.fixedAudioFolderURL, choose: chooseFixedAudioFolder)
                } else {
                    Text(model.lastAudioFolderURL.map {
                        "Next picker: \($0.path(percentEncoded: false))"
                    } ?? "The first picker uses macOS’s current location, then remembers your selection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                }
            }

            Section("Traktor Locations") {
                locationRow("Collection", url: model.collectionURL, choose: chooseCollection)
                locationRow("Stems folder", url: model.stemsDirectoryURL, choose: chooseStemsDirectory)
                Button("Reset to Detected Defaults") { model.resetDetectedLocations() }
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .frame(width: 560, height: 430)
    }

    private var showGuideBinding: Binding<Bool> {
        Binding(get: { !hideWorkflowGuideOnLaunch }, set: { hideWorkflowGuideOnLaunch = !$0 })
    }

    private var audioFolderBehaviorBinding: Binding<AudioFolderBehavior> {
        Binding(
            get: { model.audioFolderBehavior },
            set: { model.setAudioFolderBehavior($0) }
        )
    }

    private func locationRow(_ label: String, url: URL?, choose: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                Text(url?.path(percentEncoded: false) ?? "Not selected")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if url != nil && !model.locationExists(url) {
                    Text("Drive or folder unavailable — reconnect it or choose another location.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Spacer()
            Button("Choose…", action: choose)
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

    private func chooseFixedAudioFolder() {
        let panel = NSOpenPanel()
        panel.directoryURL = model.fixedAudioFolderURL ?? model.lastAudioFolderURL
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Choose where audio file pickers should begin"
        if panel.runModal() == .OK { model.setFixedAudioFolder(panel.url) }
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
}
