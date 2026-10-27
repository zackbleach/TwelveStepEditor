# Licence

This project is **source-available**. You may use, study and change it for **noncommercial** purposes. Commercial use needs permission.

Required Notice: Copyright 2026 Zack Bleach (https://github.com/zackbleach/TwelveStepEditor)

## Two licences

**1. Most of the project uses the PolyForm Noncommercial License 1.0.0.** The full text is in [`LICENSES/PolyForm-Noncommercial-1.0.0.md`](LICENSES/PolyForm-Noncommercial-1.0.0.md) and at <https://polyformproject.org/licenses/noncommercial/1.0.0>. This covers every file whose header says `SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0`, which includes:
- the iOS app;
- most of TwelveStepKit;
- 12 Step Sync (`Tools/sync-setup`);
- the scripts in `Tools/mac-sync`;
- the tests.

The licence allows personal, hobby, educational and other noncommercial use, and sharing changes for those purposes. For commercial use, contact the copyright holder.

**2. Files derived from the official 12 Step Editor use the Mozilla Public License 2.0.** These are files from, or translated from, Muse Kinetics' (Keith McMillen Instruments') [12 Step Editor](https://github.com/Muse-Kinetics/12-step-editor-qt6), which is MPL-2.0. They stay MPL-2.0. That licence allows commercial use, and their source must stay available. The text is in [`LICENSES/MPL-2.0.txt`](LICENSES/MPL-2.0.txt). The files are:
- `TwelveStepKit/Sources/TwelveStepKit/Protocol/KMIFraming.swift`: translation of the editor's SysEx framing.
- `TwelveStepKit/Sources/TwelveStepKit/Protocol/PresetImageFormatter.swift`: translation of its preset and settings formatter.
- `TwelveStepKit/Sources/TwelveStepKit/Resources/FactoryPresets/`: the editor's factory presets, copied unmodified (see `NOTICE.txt` there).
- `Tools/golden-harness/`: a test tool that builds the editor's unmodified formatter.

Each file's header says which licence applies.

## The App Store app

The app distributed on the App Store is provided under Apple's standard licence terms for App Store apps. The licences above govern the source code in this repository.

## Contributions

By contributing to this repository, you agree that your contribution can be distributed under these terms, and that the copyright holder may also license it under other terms, including commercially.

## Trademarks

12 Step is a trademark of Muse Kinetics (Keith McMillen Instruments), used here with their permission. This is an independent project, not made by Muse Kinetics.
