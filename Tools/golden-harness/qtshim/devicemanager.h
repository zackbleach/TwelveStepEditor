// SPDX-License-Identifier: MPL-2.0
#ifndef DEVICEMANAGER_H
#define DEVICEMANAGER_H
#include "qtshim.h"
#include "sysex.h"
#include "StandalonePreset.h"
#include <vector>
extern "C" void send_standalone_image(unsigned char *image, int count);
extern "C" void send_standalone_settings(unsigned char *settings, int len);
class DeviceManager {
public:
    void slot_sendPresets(unsigned char *image, int count) { send_standalone_image(image, count); capture(); }
    void slot_sendSettings(unsigned char *settings) { send_standalone_settings(settings, sizeof(SETTINGS)); capture(); }
    std::vector<unsigned char> lastMessage;
private:
    void capture() { lastMessage.assign(midi_sysex_data(), midi_sysex_data() + midi_sysex_len()); }
};
#endif
