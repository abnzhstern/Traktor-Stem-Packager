TRAKTOR STEM PACKAGER — MAC INSTALLATION

This build is not Apple-notarized. Installation may require one brief Terminal step, depending on your Mac's security settings. Terminal is not needed for normal use after installation.

WHAT THIS APP IS

Traktor Stem Packager does not create or separate stems. It packages four stems you already created or received from a producer, composer, label, or stem-separation service, together with the matching stereo master.

AAC STEM FILE WORKFLOW

The AAC workflow creates one shareable .stem.mp4 file. Drag that finished .stem.mp4 directly into Traktor's Track Collection or a deck; the four packaged stems will be present automatically. No master-track analysis or linked-folder setup is required for this workflow.

Files can be added individually, or Import Folder can propose assignments from a folder containing exactly five supported audio files. Always review the proposed assignments before accepting them. Drag a file onto another slot to reassign it. Accepted assignments lock; choose Edit Assignments to change them. Clear All empties the queue without deleting source files.

IMPORTANT
Keep these two items together in this folder:
• Install Traktor Stem Packager.command
• Traktor Stem Packager.app

METHOD 1 — TRY THIS FIRST

1. Control-click or right-click “Install Traktor Stem Packager.command.”
2. Choose Open.
3. If macOS asks whether you are sure, choose Open again.
4. The installer will place the app in Applications and launch it.

If macOS says Terminal needs permission to modify apps, choose Allow. That permission is used only to place or replace Traktor Stem Packager in the Applications folder.

If an older version is already installed, you do not need to delete it first. The installer closes it, installs the new version in the same Applications location, and moves the previous copy to the Trash as a recoverable backup.

METHOD 2 — IF MACOS SAYS THE COMMAND CANNOT BE OPENED

1. Open Terminal from Applications > Utilities.
2. Type: zsh followed by one space. Do not press Return yet.
3. Drag “Install Traktor Stem Packager.command” from this folder into the Terminal window.
4. Press Return.
5. Wait for the message that Traktor Stem Packager was installed successfully.

The completed Terminal line will look similar to this:

zsh "/Users/yourname/Downloads/Traktor Stem Packager Installer/Install Traktor Stem Packager.command"

WHAT THE INSTALLER DOES

• Places Traktor Stem Packager.app in Applications.
• Clears quarantine attributes from this app only.
• Repairs executable permissions.
• Creates and verifies a local ad-hoc signature.
• Launches the installed app.
• Moves an older installed copy to the Trash as a recoverable backup.

Updates use the same app name and Applications location. The app does not install audio files, engines, or large support folders elsewhere on your Mac. Normal macOS preference data may remain between versions.

The installer does not disable Gatekeeper or change system-wide Mac security settings.

Because this free build is not signed and notarized through Apple's Developer Program, macOS behavior may vary by version or security software. If installation fails, copy the complete Terminal error message when asking for help.

LOSSLESS TRAKTOR HANDOFF

The lossless workflow checks Traktor's collection first. If the exact master is already analyzed, the import step is skipped.

If it is not present, choose Drag Stereo Master into Traktor. The app opens Traktor and brings Finder to the foreground with the exact master highlighted. Drag it into Traktor's Track Collection, not onto a deck, and let analysis finish. A Show Master in Finder button remains available if you need to reveal it again. Return to the app and choose Save, Quit Traktor & Install.

If linked stems already exist for that master, the app asks before replacing them. A timestamped .bak file is a safety backup of the previous linked Stem file, not a second active Stem set.

Traktor must close before the app edits collection.nml. Quit Traktor normally when prompted. The app detects the closure and continues automatically without requesting permission to close another app. Traktor may briefly say Updating Settings while saving its collection; that is expected.
