#!/bin/bash
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Copyright 2026 Zack Bleach. See LICENSE.md.
#
# Builds, signs, notarizes and staples "12 Step Sync.app", then zips it for a GitHub release.
#
#   ./release.sh 1.0
#
# Needs, once per Mac:
#   - a "Developer ID Application" certificate in the keychain (Xcode › Settings › Accounts ›
#     Manage Certificates › + › Developer ID Application);
#   - notarization credentials stored as the keychain profile "notarytool":
#     xcrun notarytool store-credentials notarytool --apple-id <apple id> --team-id <team id>
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:?usage: ./release.sh <version>}"
SIGN_ID="${SIGN_ID:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}"
[[ -n "$SIGN_ID" ]] || { echo "No Developer ID Application certificate found."; exit 1; }

swift test
VERSION="$VERSION" SIGN_ID="$SIGN_ID" ./build-app.sh

APP="dist/12 Step Sync.app"
ZIP="dist/12-Step-Sync-$VERSION.zip"
rm -f "$ZIP" dist/notarize.zip
ditto -c -k --keepParent "$APP" dist/notarize.zip
xcrun notarytool submit dist/notarize.zip --keychain-profile notarytool --wait
rm dist/notarize.zip
xcrun stapler staple "$APP"
spctl --assess --type execute --verbose=2 "$APP"
ditto -c -k --keepParent "$APP" "$ZIP"
shasum -a 256 "$ZIP"
echo "Ready: $ZIP"
