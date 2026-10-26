#!/bin/sh
# Builds the golden harness from the official editor's sources (default: ../../../12step-reference).
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
ref="${1:-$here/../../../12step-reference}/QT"
out="$here/.build"
mkdir -p "$out"
inc="-I$here/qtshim -I$ref/presetimageformatting -I$ref/presetimageformatting/DeviceManager -I$ref/inc/KMI_KMDM"
clang -x c -fcommon -w -c $inc "$ref/presetimageformatting/DeviceManager/download.c" -o "$out/download.o"
clang++ -std=c++17 -w -c $inc "$ref/presetimageformatting/DeviceManager/sysex.cpp" -o "$out/sysex.o"
clang++ -std=c++17 -w -c $inc "$ref/presetimageformatting/DeviceManager/sysexcmds.cpp" -o "$out/sysexcmds.o"
clang++ -std=c++17 -w -c $inc "$ref/presetimageformatting/imageformatter.cpp" -o "$out/imageformatter.o"
clang++ -std=c++17 -w -c $inc "$here/main.cpp" -o "$out/main.o"
clang++ "$out"/*.o -o "$out/golden-harness"
echo "$out/golden-harness"
