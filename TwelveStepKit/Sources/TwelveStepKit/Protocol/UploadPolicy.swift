import Foundation

/// The only *writes* the app may send: a full-setlist upload or a global-settings upload,
/// shaped exactly as the desktop editor's legacy encoder produces them. Anything else
/// (bootloader, mode switches, calibration resets, unknown packets) is refused.
public enum UploadPolicy {
    public enum Kind: Equatable, Sendable {
        case setlist(presetCount: Int)
        case settings

        public var title: String {
            switch self {
            case .setlist(let count): "Setlist upload (\(count) preset\(count == 1 ? "" : "s"))"
            case .settings: "Settings upload"
            }
        }
    }

    /// Returns what the message is, or nil if it isn't an allowed upload.
    public static func classify(_ message: [UInt8]) -> Kind? {
        guard message.count > 18,
              Array(message[0...6]) == [0xF0] + kmiManufacturerID + [0x00, PresetImageFormatter.legacyPID, 0x00],
              let packet = try? KMIFraming.decode(message),
              packet.packetType == PresetImageFormatter.standalonePacketType,
              let info = packet.blocks.first, info.count == 6, info[0] == 0 else { return nil }
        let data = packet.blocks.dropFirst()
        switch info[1] {
        case PresetImageFormatter.presetImageType:
            let count = Int(info[5])
            guard info[2] == PresetImageFormatter.presetInfoFormatVersion,
                  (1...Setlist.slotCount).contains(count), data.count == count,
                  data.allSatisfy({ $0.count == PresetImageFormatter.imageSize }) else { return nil }
            return .setlist(presetCount: count)
        case PresetImageFormatter.settingsType:
            guard data.count == 1, data.first?.count == PresetImageFormatter.settingsSize else { return nil }
            return .settings
        default:
            return nil
        }
    }
}
