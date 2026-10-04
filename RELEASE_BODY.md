# Traktor Stem Packager 1.0.3

This update makes the Lossless Linked Stems handoff explicit from beginning to end:

- Add and verify the stereo master and four stems before beginning the Traktor handoff.
- Add remaining stems manually, select several at once, or import a folder containing only the missing stems.
- Explicit prompts distinguish importing the master, analyzing it, closing Traktor, verifying the saved collection, and installing the linked stems.
- The guide now explains how to play the original master with **Load as Track** and the linked stems with **Load as Stem**, without importing a duplicate master.
- The README, installer guide, and in-app User Guide now include clear backup and recovery guidance.
- The AAC preference now reads “Open Traktor after creating an AAC Stem file.”

No audio encoding, lossless PCM verification, or Traktor collection-mutation logic changed.

## Requirements

- Apple Silicon Mac
- macOS 14 or newer
- Traktor Pro 4

## Installation

Download `Traktor-Stem-Packager-1.0.3-macOS.zip`, unzip it, and follow the included README. Installing the update replaces the existing app and moves the previous copy to the Trash as a recoverable backup.

This free build is ad-hoc signed rather than Apple-notarized. Some Macs require the documented one-time Terminal installation method. The installer does not disable Gatekeeper or change system-wide security settings.

TRAKTOR is a trademark of Native Instruments GmbH. This independent project is not affiliated with, sponsored by, or endorsed by Native Instruments.
