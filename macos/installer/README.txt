TRAKTOR STEM PACKAGER — MAC INSTALLATION

This build is not Apple-notarized. Installation may require one brief Terminal step, depending on your Mac's security settings. Terminal is not needed for normal use after installation.

WHAT THIS APP IS

Traktor Stem Packager does not create or separate stems. It packages four stems you already created or received from a producer, composer, label, or stem-separation service, together with the matching stereo master.

CHOOSE ONE OF TWO WORKFLOWS

1. AAC Stem File creates one simple, shareable 320 kbps AAC .stem.mp4.
2. Lossless Traktor Installation preserves the source PCM and links the stems to the existing Traktor master entry.

In the app, orange always marks the one action to take next. Blue explains the current step, green means ready or complete, and red identifies a problem that must be corrected.

AAC STEM FILE WORKFLOW

The AAC workflow creates one shareable .stem.mp4 file. Drag that finished .stem.mp4 directly into Traktor's Track Collection or a deck; the four packaged stems will be present automatically. No master-track analysis or linked-folder setup is required for this workflow. Traktor treats the finished .stem.mp4 as a new track, so cues, beat grids, loops, and play history from a separate stereo-master entry do not transfer automatically.

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

The lossless workflow checks Traktor's collection first. If the exact master file at that saved location is already analyzed, the import step is skipped. The stems are linked to the existing collection entry without replacing the master or removing its cues, beat grid, loops, or other Traktor data.

If the master is already analyzed in Traktor, add that exact same master file and the four matching stems to the app. The app links the four lossless stems to the existing track and preserves its Traktor data.

If the master is not in Traktor, add the master and four stems to the app. The app walks you through importing and analyzing the master, then links the four lossless stems to it as a new track.

Traktor saves additions and deletions to collection.nml when it closes. If Traktor is open, the app treats the on-disk collection as potentially out of date. Before every lossless installation, the app closes Traktor when necessary and rechecks the newly saved collection. It will not install anything unless the selected master is still present and analyzed. If the master is missing, the app highlights it in Finder and tells you to import it into Traktor's Track Collection.

Start by adding the exact stereo master to the app. You may add the four stems at the same time, individually or with Import Folder, or add them later. If the master is not already analyzed, choose Open Traktor & Show Master. The app opens Traktor and brings Finder to the foreground with the exact master highlighted. Drag it into Traktor's Track Collection, not onto a deck, and let analysis finish. Show Master in Finder remains available whenever a master is loaded.

If linked stems already exist for that master, the app asks before replacing them. A timestamped .bak file is a safety backup of the previous linked Stem file, not a second active Stem set.

Traktor must close before the app edits collection.nml. Follow the orange next-action button. The app asks Traktor to close, verifies the latest saved collection, installs the stems only if the master is present and analyzed, and reopens Traktor. Traktor may briefly say Updating Settings while saving its collection; that is expected.

MAC PRIVACY & SECURITY

This free build is not Apple-notarized. If macOS blocks the app from closing Traktor, open System Settings > Privacy & Security and allow Traktor Stem Packager under Automation if it appears. The app's How It Works page includes a button that opens Privacy & Security. If permission remains unavailable, the app pauses and walks you through quitting Traktor manually, then continues automatically.

App Management permission for Terminal or the installer is separate. It is needed only when installing or replacing Traktor Stem Packager in the Applications folder. Manually closing Traktor does not affect that installation notice.

PREFERENCES

Choose Traktor Stem Packager > Settings to control which workflow appears at launch, whether Traktor opens automatically after an AAC export, and whether Before You Begin appears at launch. "Remember Last Used" is the default startup choice.

The selected Traktor Collection and Stems folder are remembered between launches. You can change either location for another Traktor installation or an external drive. If a saved drive is disconnected, the app marks it unavailable and keeps the selection instead of silently switching to another folder. Use Reset to Detected Defaults to return to the automatically detected locations.
