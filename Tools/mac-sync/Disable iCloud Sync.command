#!/bin/bash
# Points the 12 Step Editor back at its own folder, bringing the latest presets from iCloud Drive.
#
#   1. Checks the 12 Step Editor is not running.
#   2. Backs up the local folder, then copies the four preset files from iCloud Drive into it.
#   3. Restores the editor's PRESET_DIR preference to the local folder.
# The iCloud Drive copy is left in place (delete it yourself if you no longer need it).
set -euo pipefail

DOMAIN="${TWELVESTEP_PREFS_DOMAIN:-com.keithmcmillen.12 Step Editor}"
ICLOUD_ROOT="${TWELVESTEP_ICLOUD_DIR:-$HOME/Library/Mobile Documents/com~apple~CloudDocs}"
SYNCED="$ICLOUD_ROOT/12 Step Editor"
BACKUP_ROOT="${TWELVESTEP_BACKUP_ROOT:-$HOME/Documents/12 Step Editor Backups}"
LOCAL="${TWELVESTEP_LOCAL_DIR:-$HOME/Library/Application Support/KeithMcMillenInstruments/12 Step Editor}"
FILES=("12Step.json" "setlist.json" "settings.json" "Blank.twelvesteppreset")

fail() { echo; echo "✗ $*"; echo "Nothing was changed."; exit 1; }

if [[ "${TWELVESTEP_SKIP_RUNNING_CHECK:-0}" != 1 ]] && pgrep -f "12 Step Editor.app/Contents/MacOS/12 Step Editor" >/dev/null; then
    fail "The 12 Step Editor is running. Quit it (⌘Q) and run this again."
fi
CURRENT="$(defaults read "$DOMAIN" PRESET_DIR 2>/dev/null || true)"
[[ "$CURRENT" == "$SYNCED" ]] || fail "iCloud sync isn't enabled (the editor uses ${CURRENT:-its default folder})."
for f in "${FILES[@]}"; do
    [[ -f "$SYNCED/$f" ]] || fail "$SYNCED is missing $f. Make sure iCloud has finished downloading it."
done

stamp="$(date +%Y%m%d-%H%M%S)"
backup="$BACKUP_ROOT/$stamp-before-disable"
mkdir -p "$LOCAL" "$backup"
[[ -n "$(ls -A "$LOCAL" 2>/dev/null)" ]] && ditto "$LOCAL" "$backup/local-presets"
for f in "${FILES[@]}"; do
    cp -p "$SYNCED/$f" "$LOCAL/$f"
    cmp -s "$SYNCED/$f" "$LOCAL/$f" || fail "Copy of $f didn't verify."
done
defaults write "$DOMAIN" PRESET_DIR -string "$LOCAL"
echo "✓ The 12 Step Editor uses $LOCAL again, with the latest presets from iCloud Drive."
echo "  Previous local files were backed up to $backup"
