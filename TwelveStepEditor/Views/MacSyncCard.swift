import SwiftUI
import TwelveStepKit

/// Shown on the Presets tab while presets are only on this device: asks whether to share presets
/// with the desktop 12 Step Editor. "Set Up Sync" opens `SyncWizard`; "Not Now" hides the card
/// (Settings › Preset Files still offers the wizard).
struct MacSyncCard: View {
    let onSetUp: () -> Void
    @AppStorage("macSyncCardDismissed") private var dismissed = false

    var body: some View {
        if !dismissed {
            Section {
                VStack(spacing: 16) {
                    SyncDevicesGraphic(size: .compact)
                    VStack(spacing: 6) {
                        Text("Sync presets with your Mac?")
                            .font(.title3.weight(.bold))
                        Text("Edit the same presets in the desktop 12 Step Editor and on this \(deviceName), kept in step by iCloud Drive.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        FreeBadge(text: "Free · takes about a minute")
                            .padding(.top, 4)
                    }
                    .multilineTextAlignment(.center)

                    HStack(spacing: 12) {
                        Button {
                            withAnimation { dismissed = true }
                        } label: {
                            Text("Not Now").font(.body.weight(.semibold)).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        Button(action: onSetUp) {
                            Text("Set Up Sync").font(.body.weight(.semibold)).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .controlSize(.large)
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .listRowBackground(
                    LinearGradient(colors: [Color.accentColor.opacity(0.18), Color.accentColor.opacity(0.03)],
                                   startPoint: .top, endPoint: .bottom)
                        .background(Color(.secondarySystemGroupedBackground))
                )
            }
        }
    }
}

/// "Free" in a green capsule.
struct FreeBadge: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "gift.fill")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.green)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.green.opacity(0.14), in: Capsule())
    }
}

/// Mac, iCloud and iPhone joined by dashed lines.
struct SyncDevicesGraphic: View {
    enum Size { case compact, large }
    let size: Size

    var body: some View {
        let scale: CGFloat = size == .large ? 1.25 : 1
        HStack(spacing: 0) {
            badge("laptopcomputer", diameter: 48 * scale)
            connector(width: 30 * scale)
            badge("icloud.fill", diameter: 64 * scale, filled: true)
            connector(width: 30 * scale)
            badge("iphone", diameter: 48 * scale)
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private func badge(_ symbol: String, diameter: CGFloat, filled: Bool = false) -> some View {
        Image(systemName: symbol)
            .font(.system(size: diameter * (filled ? 0.42 : 0.4), weight: filled ? .semibold : .regular))
            .foregroundStyle(filled ? Color.white : Color.accentColor)
            .frame(width: diameter, height: diameter)
            .background(filled ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color.accentColor.opacity(0.15)), in: Circle())
    }

    private func connector(width: CGFloat) -> some View {
        DashLine()
            .stroke(Color.accentColor.opacity(0.5), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 5]))
            .frame(width: width, height: 2)
            .padding(.horizontal, 6)
    }
}

/// A straight horizontal line, for dashed connectors.
private struct DashLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}
