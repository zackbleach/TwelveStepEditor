#!/bin/bash
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Copyright 2026 Zack Bleach. See LICENSE.md.
# Moves the 12 Step Editor's working folder to iCloud Drive so the iOS app can share it.
#
# What it does (nothing inside the editor app is modified):
#   1. Checks the 12 Step Editor is not running.
#   2. Backs up the editor's current preset folder to ~/Documents/12 Step Editor Backups/<date>/.
#   3. Copies 12Step.json, setlist.json, settings.json and Blank.twelvesteppreset to
#      iCloud Drive/12 Step Editor/ (never overwriting files already there).
#   4. Points the editor's PRESET_DIR preference at that folder.
# Undo with "Disable iCloud Sync.command".
#
# Test overrides: TWELVESTEP_PREFS_DOMAIN, TWELVESTEP_ICLOUD_DIR, TWELVESTEP_BACKUP_ROOT,
# TWELVESTEP_SKIP_RUNNING_CHECK=1.
set -euo pipefail

DOMAIN="${TWELVESTEP_PREFS_DOMAIN:-com.keithmcmillen.12 Step Editor}"
ICLOUD_ROOT="${TWELVESTEP_ICLOUD_DIR:-$HOME/Library/Mobile Documents/com~apple~CloudDocs}"
DEST="$ICLOUD_ROOT/12 Step Editor"
BACKUP_ROOT="${TWELVESTEP_BACKUP_ROOT:-$HOME/Documents/12 Step Editor Backups}"
DEFAULT_DIR="$HOME/Library/Application Support/KeithMcMillenInstruments/12 Step Editor"
FILES=("12Step.json" "setlist.json" "settings.json" "Blank.twelvesteppreset")

fail() { echo; echo "✗ $*"; echo "Nothing was changed."; exit 1; }

echo "12 Step Editor → iCloud Drive sync setup"
echo

if [[ "${TWELVESTEP_SKIP_RUNNING_CHECK:-0}" != 1 ]] && pgrep -f "12 Step Editor.app/Contents/MacOS/12 Step Editor" >/dev/null; then
    fail "The 12 Step Editor is running. Quit it (⌘Q) and run this again."
fi
[[ -d "$ICLOUD_ROOT" ]] || fail "iCloud Drive isn't available at $ICLOUD_ROOT. Turn on iCloud Drive in System Settings → Apple Account → iCloud."

CURRENT="$(defaults read "$DOMAIN" PRESET_DIR 2>/dev/null || true)"
SOURCE="${CURRENT:-$DEFAULT_DIR}"
if [[ "$SOURCE" == "$DEST" ]]; then
    echo "✓ Already set up: the editor uses $DEST"
    exit 0
fi
for f in "${FILES[@]}"; do
    [[ -f "$SOURCE/$f" ]] || fail "The editor's folder ($SOURCE) is missing $f. Open the editor once so it creates its files, quit it, then run this again."
done

existing=0
for f in "${FILES[@]}"; do [[ -e "$DEST/$f" ]] && existing=$((existing + 1)); done
if (( existing == ${#FILES[@]} )); then
    echo "iCloud Drive/12 Step Editor already has a full set of files (perhaps from another Mac)."
    read -r -p "Use those files and leave this Mac's current files in the backup? [y/N] " answer
    [[ "$answer" =~ ^[Yy]$ ]] || fail "Cancelled."
    copy=0
elif (( existing > 0 )); then
    fail "iCloud Drive/12 Step Editor has only some of the editor's files. Move that folder aside and run this again."
else
    copy=1
fi

stamp="$(date +%Y%m%d-%H%M%S)"
backup="$BACKUP_ROOT/$stamp"
mkdir -p "$backup"
ditto "$SOURCE" "$backup/presets"
printf '%s\n' "$CURRENT" > "$backup/previous-PRESET_DIR.txt"
echo "✓ Backed up $SOURCE"
echo "  to $backup/presets"

if (( copy )); then
    mkdir -p "$DEST"
    for f in "${FILES[@]}"; do
        cp -p "$SOURCE/$f" "$DEST/$f"
        cmp -s "$SOURCE/$f" "$DEST/$f" || fail "Copy of $f didn't verify."
    done
    echo "✓ Copied the presets to $DEST"
fi

defaults write "$DOMAIN" PRESET_DIR -string "$DEST"
[[ "$(defaults read "$DOMAIN" PRESET_DIR)" == "$DEST" ]] || fail "Couldn't update the editor's preference."
echo "✓ The 12 Step Editor now uses iCloud Drive/12 Step Editor"
echo
echo "Next:"
echo "  1. In Finder, open iCloud Drive, right-click the \"12 Step Editor\" folder and choose"
echo "     \"Keep Downloaded\", so the files are always on this Mac."
echo "  2. Open the 12 Step Editor and check your presets and setlist look right."
echo "  3. In the iOS app: Library → Choose folder… → iCloud Drive → 12 Step Editor."
echo
echo "Rules: quit the desktop editor while editing on the phone. If the editor ever says a"
echo "file is missing, choose \"Exit Application\", never \"Factory Default\" (that deletes the folder)."
