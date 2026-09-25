# Version 0.6.0-beta.20

- Added continuous monitoring of the saved Traktor collection and Stems folder while the app is open, plus a manual Refresh Traktor Status control.
- The status distinguishes verified saved state from potentially unsaved changes while Traktor is open.
- Detects the collection’s linked-stems flag separately from whether a Stem file merely exists, including a master that was unpaired inside Traktor.
- Stem labels are now plain text until the user explicitly chooses the pencil control, permanently preventing DRUMS from opening in edit mode.
- Audio pickers remember the last-used folder by default; Preferences can instead set a fixed starting audio folder.
- Removed irrelevant Traktor-closing information from Mac Security setup and clarified that users must scroll to Security after macOS opens Privacy & Security.
- The main window is explicitly reactivated after closing How to Use so the orange next action is immediately visible.

# Version 0.6.0-beta.19

- Replaced numbered workflow jumps with clear states: Add Audio, Prepare Master in Traktor, Review Assignments, and Ready to Create or Install.
- Orange now marks the single next action: Add Master, Add Remaining Stems, Accept Assignments, or Create/Install.
- Added multi-file selection for remaining stems while keeping drag-and-drop reassignment and explicit acceptance.
- Added Start New Package with Command-N. It clears all transient package state, cancels stale background work, and preserves workflow and folder preferences.
- Security instructions now include live buttons beside the matching Privacy & Security and App Management steps.
- Removed the duplicate AAC footer Open Traktor button and prevented an editable stem label from taking focus on launch.

# Version 0.6.0-beta.18

- Manual file entry and folder import now use the same explicit Review Assignments → Accept Assignments → orange next-action sequence.
- The persistent Traktor control is now a distinct black button with an icon, separate from the secondary How to Use control.
- Removed inaccurate Automation-permission instructions. Traktor Stem Packager does not require Automation permission to request a normal quit.
- App Management guidance now explains that Terminal appears only after macOS blocks an installation attempt.
- If Traktor remains open, the app brings it forward and gives a direct Command-Q fallback while continuing to monitor for closure.

# Version 0.4.0

Initial public beta release for Apple Silicon Macs running macOS 14 or newer.

## Highlights

- Native SwiftUI drag-and-drop interface
- Traktor-compatible five-track Stem MP4 packaging
- Metadata and artwork import from the stereo master
- Editable title, artist, album, date, producer, label, genre, and stem names
- Bundled Node.js, FFmpeg, and FFprobe runtimes
- Guided installer with a documented Terminal fallback for non-notarized distribution

## Important installation note

This free build is ad-hoc signed rather than Apple-notarized. Follow the included README. Some Macs require the one-time Terminal installation method.
