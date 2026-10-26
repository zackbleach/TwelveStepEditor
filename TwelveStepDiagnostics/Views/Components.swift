import SwiftUI
import TwelveStepKit
import UIKit

extension ConnectionStatus {
    var color: Color {
        switch self {
        case .transportUnavailable: .red
        case .noDevice: .secondary
        case .detected: .orange
        case .identified: .green
        }
    }

    var symbol: String {
        switch self {
        case .transportUnavailable: "exclamationmark.triangle.fill"
        case .noDevice: "cable.connector.slash"
        case .detected: "cable.connector"
        case .identified: "checkmark.seal.fill"
        }
    }

    var detail: String {
        switch self {
        case .transportUnavailable(let message): message
        case .noDevice: "Connect the 12 Step to the iPhone's USB-C port."
        case .detected(let name): "\(name) is present. Identifying… (or run an identity request under Diagnostic queries)."
        case .identified(let name, let reply): "\(name) · \(reply.summary)"
        }
    }
}

struct StatusCard: View {
    let status: ConnectionStatus

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: status.symbol)
                .font(.title)
                .foregroundStyle(status.color)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(status.title).font(.headline)
                Text(status.detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

/// Monospaced, selectable hex dump.
struct HexText: View {
    let bytes: [UInt8]
    var lineLimit: Int? = nil

    var body: some View {
        Text(bytes.isEmpty ? "—" : Hex.string(bytes))
            .font(.system(.caption, design: .monospaced))
            .lineLimit(lineLimit)
            .textSelection(.enabled)
    }
}

struct KindBadge: View {
    let kind: TrafficKind

    var body: some View {
        Text(kind.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch kind {
        case .performance: .blue
        case .configuration: .purple
        case .realtime: .gray
        case .sysex: .teal
        case .other: .secondary
        }
    }
}

/// System share sheet for a file URL.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct ShareableFile: Identifiable {
    let url: URL
    var id: URL { url }
}

/// Small "v0.1.1 (2)" label so testers can confirm which build is installed.
struct VersionBadge: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Text("v\(model.shortVersion)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .accessibilityLabel("App version \(model.shortVersion)")
    }
}
