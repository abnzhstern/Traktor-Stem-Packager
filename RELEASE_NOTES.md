# Version 1.0.1

- Renamed the launch-guide preference to “Show ‘How It Works’ when the app opens,” making its behavior match the visible How It Works button.
- No audio engine, packaging, metadata, Traktor-linking, or workflow behavior changed.

# Version 1.0.0

First stable public release of Traktor Stem Packager.

- Packages an existing stereo master and four matching stems for Traktor Pro 4; it does not create or separate stems.
- Offers two clear workflows: a standalone 320 kbps AAC `.stem.mp4`, or a lossless ALAC installation linked to the original analyzed Traktor master.
- Preserves existing cues, beat grids, loops, play history, and other Traktor metadata in the lossless linked workflow.
- Supports bit-identical lossless packaging for matched stereo PCM WAV/AIFF sources at 16-bit/44.1 kHz and 24-bit/48 kHz, with post-package PCM SHA-256 verification.
- Imports standard metadata and artwork from the stereo master for the AAC workflow.
- Validates file assignments, format compatibility, timing, and stem-sum headroom before packaging.
- Guides the user through Traktor analysis, saving, installation, verification, and recovery with one highlighted next action.
- Creates safety backups before changing Traktor's collection or replacing an existing linked Stem file.
- Includes update notifications, a permanent latest-release download link, and an installer that safely replaces an older version.
- Supports Apple Silicon Macs running macOS 14 or newer.

## Release-candidate fixes incorporated in 1.0.0

- Restored the proven beta 20 workflow and status presentation after beta 21’s global phase system hid important Traktor state and controls.
- A successful lossless installation now remains Complete while its saved Traktor link and Stem file are still present, preventing the reinstall loop.
- Refresh Traktor Status preserves the detailed saved-state result. When Traktor is open, the same status row exposes a visible orange Save & Quit Traktor, Then Refresh button.
- The app waits for Traktor to close, rereads the saved collection, and reports whether the exact master is analyzed, missing, linked, or ready for installation.
- Add Remaining Stems is orange whenever it is the valid next action, without depending on the old waiting-state gate.
- Main-window file pickers remain attached to the app window to prevent hidden modal dialogs and unexplained macOS beeps.

# Version 0.6.0-beta.21

- Rebuilt the visible workflow around one authoritative phase at a time, so the interface cannot simultaneously guide conflicting actions.
- A successful lossless install now remains Complete; automatic Traktor audits no longer reactivate the install button and invite a duplicate installation.
- The app remembers a verified package fingerprint and recognizes the same already-installed source set after reopening.
- Refresh Traktor Status now reports that an open Traktor session may contain unsaved changes and exposes one orange Save & Quit Traktor, Then Refresh action.
- After Traktor closes, the app waits for the saved collection, rereads the master/link/Stem state, and updates automatically. It reopens Traktor only when the master must be imported or analyzed again.
- Add Remaining Stems is driven by missing files rather than the previous fragile waiting-state check, so it appears consistently when it is the next action.
- Main-window file pickers are attached sheets instead of hidden blocking dialogs, eliminating the unexplained macOS beep when another window covered a picker.

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
