import SwiftUI
import TwelveStepKit

struct QueryView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingProbe: SafeCommand?

    var body: some View {
        let session = model.session

        List {
            Section {
                Picker("Send to", selection: Binding(
                    get: { session.selectedDestinationID },
                    set: { session.selectDestination($0) }
                )) {
                    Text("None").tag(EndpointID?.none)
                    ForEach(session.endpoints.destinations) { endpoint in
                        Text(label(for: endpoint)).tag(EndpointID?.some(endpoint.id))
                    }
                }
            } header: {
                Text("Destination")
            } footer: {
                Text("Picked automatically when a 12 Step Control Surface port appears.")
            }

            Section {
                ForEach(SafeCommand.allCases.filter { !$0.isExperimental }) { command in
                    Button {
                        Task { await session.run(command) }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(command.title).font(.headline)
                            Text(command.explanation).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .disabled(session.isQuerying || session.selectedDestinationID == nil)
                }
            } header: {
                HStack {
                    Text("Read-only queries")
                    if session.isQuerying { ProgressView().padding(.leading, 6) }
                }
            } footer: {
                Text("Read-only messages the official editor sends routinely. Apart from the experimental probe below, nothing else can be sent; that is enforced in code. Run the identity request first.")
            }

            Section {
                ForEach(SafeCommand.allCases.filter(\.isExperimental)) { command in
                    Button {
                        confirmingProbe = command
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(command.title, systemImage: "exclamationmark.triangle.fill")
                                .font(.headline)
                                .foregroundStyle(.orange)
                            Text(command.explanation).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .disabled(session.isQuerying || session.selectedDestinationID == nil)
                }
            } header: {
                Text("Experimental probe")
            } footer: {
                Text("Not used by the official editor. Back up your presets in the desktop editor before sending. Send it once, then export the report from the Monitor tab.")
            }

            if let result = session.lastResult {
                QueryResultSection(result: result)
            }
        }
        .navigationTitle("Query")
        .confirmationDialog("Send experimental message?", isPresented: Binding(
            get: { confirmingProbe != nil },
            set: { if !$0 { confirmingProbe = nil } }
        ), titleVisibility: .visible, presenting: confirmingProbe) { command in
            Button("Send \(command.title)", role: .destructive) {
                Task { await session.run(command) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The official editor never sends this message, so its effect on the 12 Step is unknown. It might be ignored, answered, or do something unexpected. Only continue if your presets are backed up in the desktop editor.")
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { VersionBadge() }
        }
    }

    private func label(for endpoint: EndpointInfo) -> String {
        if let match = DeviceDiscovery.match(endpoint) {
            return "\(endpoint.displayName) (12 Step \(match.role.rawValue))"
        }
        return endpoint.displayName
    }
}

struct QueryResultSection: View {
    let result: QueryResult

    var body: some View {
        Section {
            LabeledContent("Query", value: result.command.title)
            LabeledContent("Destination", value: result.destinationName)
            VStack(alignment: .leading, spacing: 4) {
                Text("Sent (\(result.sentBytes.count) bytes)").font(.caption).foregroundStyle(.secondary)
                HexText(bytes: result.sentBytes)
            }
            outcome
            ForEach(Array(result.otherSysExDuringWait.enumerated()), id: \.offset) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text("Other SysEx received while waiting").font(.caption).foregroundStyle(.secondary)
                    HexText(bytes: item.element)
                }
            }
        } header: {
            Text("Last result")
        }
    }

    @ViewBuilder private var outcome: some View {
        switch result.outcome {
        case .reply(let bytes, let latency, let decoded):
            Label("Reply in \(Int(latency * 1000)) ms", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 4) {
                Text("Received (\(bytes.count) bytes)").font(.caption).foregroundStyle(.secondary)
                HexText(bytes: bytes)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Decoded").font(.caption).foregroundStyle(.secondary)
                Text(decoded).textSelection(.enabled)
            }
        case .timeout(let seconds):
            Label("No reply within \(seconds.formatted()) s", systemImage: "clock.badge.exclamationmark")
                .foregroundStyle(.orange)
            Text("Check the Monitor tab for any traffic, confirm the destination is the Control Surface port, and try once more. A missing reply on one query is not proof of incompatibility.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
        }
    }
}
