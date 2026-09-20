#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
SOURCE_APP="$SCRIPT_DIR/Traktor Stem Packager.app"
DEST_APP="/Applications/Traktor Stem Packager.app"
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_APP=""
FAILED_APP="$HOME/.Trash/Traktor Stem Packager failed install $STAMP.app"

show_error() {
  print -u2 -- "$1"
  osascript -e "display dialog \"$1\" with title \"Traktor Stem Packager Installer\" buttons {\"OK\"} default button \"OK\" with icon stop" >/dev/null 2>&1 || true
  exit 1
}

restore_previous() {
  if [[ -e "$DEST_APP" ]]; then
    mv "$DEST_APP" "$FAILED_APP" 2>/dev/null || true
  fi
  if [[ -n "$BACKUP_APP" && -e "$BACKUP_APP" ]]; then
    mv "$BACKUP_APP" "$DEST_APP" 2>/dev/null || true
  fi
}

[[ -d "$SOURCE_APP" ]] || show_error "The app must remain beside this installer."
[[ -f "$SOURCE_APP/Contents/MacOS/TraktorStemPackager" ]] || show_error "The app package is incomplete. Download and extract it again."
[[ -w "/Applications" ]] || show_error "Your account cannot write to Applications. Copy the app there manually, then run the installer again."

if [[ -e "$DEST_APP" ]]; then
  osascript -e 'tell application "Traktor Stem Packager" to quit' >/dev/null 2>&1 || true
  for _ in {1..20}; do
    pgrep -x TraktorStemPackager >/dev/null 2>&1 || break
    sleep 0.25
  done
  if pgrep -x TraktorStemPackager >/dev/null 2>&1; then
    pkill -TERM -x TraktorStemPackager >/dev/null 2>&1 || true
    sleep 1
  fi
  BACKUP_APP="$HOME/.Trash/Traktor Stem Packager previous $STAMP.app"
  mv "$DEST_APP" "$BACKUP_APP" || show_error "Could not preserve the existing app in the Trash."
fi

if ! ditto "$SOURCE_APP" "$DEST_APP"; then
  restore_previous
  show_error "The app could not be copied into Applications."
fi

if ! xattr -cr "$DEST_APP"; then
  restore_previous
  show_error "macOS quarantine attributes could not be cleared."
fi

chmod +x "$DEST_APP/Contents/MacOS/TraktorStemPackager" "$DEST_APP/Contents/Resources/Runtime/"* 2>/dev/null || true

if ! codesign --force --deep --sign - "$DEST_APP"; then
  restore_previous
  show_error "The local app signature could not be created."
fi

if ! codesign --verify --deep --strict "$DEST_APP"; then
  restore_previous
  show_error "The installed app did not pass signature verification."
fi

open "$DEST_APP"
if [[ -n "$BACKUP_APP" ]]; then
  osascript -e 'display notification "Updated successfully. The previous version was moved to the Trash." with title "Traktor Stem Packager"' >/dev/null 2>&1 || true
  print -- "Traktor Stem Packager was updated successfully. The previous version is in the Trash."
else
  osascript -e 'display notification "Installed successfully in Applications." with title "Traktor Stem Packager"' >/dev/null 2>&1 || true
  print -- "Traktor Stem Packager was installed successfully."
fi
