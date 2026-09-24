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
