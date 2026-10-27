// SPDX-License-Identifier: MPL-2.0
// Golden-byte harness: runs the official 12 Step Editor's own preset formatter (imageformatter.cpp)
// and legacy SysEx encoder (sysex.cpp, download.c), unmodified, on a flattened preset folder and
// prints the exact setlist and settings SysEx messages the desktop editor would send.
//
// Input (stdin, produced by flatten.py), tab-separated:
//   P <presetKey> <field> <i|d|s> <value>    one preset field from 12Step.json
//   S <slot> <name>                          one setlist slot from setlist.json
//   G <field> <i|d|s> <value>                one global setting from settings.json
// Output: "SETLIST <hex>" and "SETTINGS <hex>".
#include "imageformatter.h"
#include <cstdio>
#include <iostream>
#include <string>

static QVariant parseValue(const std::string &type, const std::string &value) {
    if (type == "i") return QVariant(std::stoi(value));
    if (type == "d") return QVariant(std::stod(value));
    return QVariant(QString(value));
}

static std::vector<std::string> split(const std::string &line) {
    std::vector<std::string> parts; std::string part; std::istringstream in(line);
    while (std::getline(in, part, '\t')) parts.push_back(part);
    if (!line.empty() && line.back() == '\t') parts.push_back("");
    return parts;
}

static void printHex(const char *label, const std::vector<unsigned char> &bytes) {
    std::printf("%s", label);
    for (unsigned char b : bytes) std::printf(" %02X", b);
    std::printf("\n");
}

int main() {
    std::map<std::string, QVariantMap> presets;
    QVariantMap setlist, global;
    std::string line;
    while (std::getline(std::cin, line)) {
        auto f = split(line);
        if (f.size() == 5 && f[0] == "P") presets[f[1]].insert(QString(f[2]), parseValue(f[3], f[4]));
        else if (f.size() == 3 && f[0] == "S") setlist.insert(QString(f[1]), QVariant(QString(f[2])));
        else if (f.size() == 4 && f[0] == "G") global.insert(QString(f[1]), parseValue(f[2], f[3]));
    }
    QVariantMap jsonMasterMap;
    for (auto &entry : presets) jsonMasterMap.insert(QString(entry.first), QVariant(entry.second));

    // Same glue as MainWindow::slotSendPresets (mainwindow.cpp:1553-1598) and
    // PresetInterface::slotGetNumPresetsInJson / slotGetPresetStringFromInt.
    int numPresetsInJson = 0;
    for (auto &entry : jsonMasterMap.m) if (entry.first.s.find("Preset") != std::string::npos) numPresetsInJson++;
    auto presetKey = [](int i) { char buf[16]; std::snprintf(buf, sizeof buf, "Preset_%03d", i); return QString(buf); };

    QVariantMap reduceSetlist;
    for (auto &slot : setlist.m) {
        QString name = slot.second.toString();
        if (name != QString("[EMPTY]")) {
            for (int j = 0; j < numPresetsInJson; j++) {
                if (jsonMasterMap.value(presetKey(j)).toMap().value("preset_name").toString() == name)
                    reduceSetlist.insert(slot.first, jsonMasterMap.value(presetKey(j)));
            }
        }
    }

    // Settings are sent first, as on connect; standalone_info is still zeroed at that point.
    ImageFormatter formatter;
    formatter.formatSettings(global);
    std::vector<unsigned char> settings = formatter.deviceManager.lastMessage;

    if (reduceSetlist.size() > 0) {
        formatter.formatImage(reduceSetlist);
        printHex("SETLIST", formatter.deviceManager.lastMessage);
    } else {
        std::printf("SETLIST\n"); // the editor sends nothing for an empty setlist
    }
    printHex("SETTINGS", settings);
    return 0;
}
