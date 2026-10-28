// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright 2026 Zack Bleach. See LICENSE.md.

import SwiftUI
import TwelveStepKit

struct DeviceView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let session = model.session

        List {
            Section {
                StatusCard(status: session.status)
            }

            Section {
                NavigationLink { MonitorView() } label: { Label("MIDI monitor", systemImage: "waveform.path.ecg") }
                #if DEBUG
                // Developer tool (identity, CV calibration and legacy firmware queries); not in release builds.
                NavigationLink { QueryView() } label: { Label("Diagnostic queries", systemImage: "arrow.left.arrow.right") }
                #endif
                NavigationLink { AboutView() } label: { Label("About", systemImage: "info.circle") }
            }

            Section {
                if session.twelveStepMatches.isEmpty {
                    Text("No endpoints with “12 Step” in their name.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(session.twelveStepMatches, id: \.endpoint) { match in
                        NavigationLink(value: match.endpoint) {
                            EndpointRow(endpoint: match.endpoint, role: match.role)
                        }
                    }
                }
            } header: {
                Text("12 Step ports")
            } footer: {
                Text("Configuration traffic uses the Control Surface port. The Expander / TRS port is not used for configuration.")
            }

            Section("All MIDI sources (\(session.endpoints.sources.count))") {
                ForEach(session.endpoints.sources) { endpoint in
                    NavigationLink(value: endpoint) { EndpointRow(endpoint: endpoint) }
                }
            }

            Section("All MIDI destinations (\(session.endpoints.destinations.count))") {
                ForEach(session.endpoints.destinations) { endpoint in
                    NavigationLink(value: endpoint) { EndpointRow(endpoint: endpoint) }
                }
            }

            Section {
                Toggle("Demo mode (simulated 12 Step)", isOn: $model.useSimulator)
            } header: {
                Text("Demo")
            } footer: {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Try the app without a 12 Step. The simulated device accepts sends and answers queries with invented placeholder replies; nothing it shows is real 12 Step behaviour.")
                    Text("12 Step Editor \(model.shortVersion)")
                        .accessibilityLabel("App version \(model.shortVersion)")
                }
            }
        }
        .navigationTitle("Device")
        .navigationDestination(for: EndpointInfo.self) { EndpointDetailView(endpoint: $0) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    session.refreshEndpoints()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .refreshable { session.refreshEndpoints() }
    }
}

struct EndpointRow: View {
    let endpoint: EndpointInfo
    var role: TwelveStepPortRole? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: endpoint.direction == .source ? "arrow.down.circle" : "arrow.up.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(endpoint.direction == .source ? "Source" : "Destination")
                Text(endpoint.displayName).font(.body)
                if endpoint.isOffline {
                    Text("offline").font(.caption).foregroundStyle(.red)
                }
            }
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var subtitle: String {
        var parts = [endpoint.direction == .source ? "Source (12 Step → \(deviceName))" : "Destination (\(deviceName) → 12 Step)"]
        if let role { parts.append("role: \(role.rawValue)") }
        if let manufacturer = endpoint.manufacturer { parts.append(manufacturer) }
        return parts.joined(separator: " · ")
    }
}

struct EndpointDetailView: View {
    let endpoint: EndpointInfo

    var body: some View {
        List {
            Section("Endpoint") {
                LabeledContent("Display name", value: endpoint.displayName)
                LabeledContent("Name", value: endpoint.name)
                LabeledContent("Direction", value: endpoint.direction.rawValue)
                LabeledContent("Unique ID", value: String(endpoint.id))
                LabeledContent("Entity", value: endpoint.entityName ?? "—")
                LabeledContent("Device", value: endpoint.deviceName ?? "—")
                LabeledContent("Manufacturer", value: endpoint.manufacturer ?? "—")
                LabeledContent("Model", value: endpoint.model ?? "—")
                LabeledContent("Driver", value: endpoint.driverOwner ?? "—")
                LabeledContent("Offline", value: endpoint.isOffline ? "Yes" : "No")
                if let match = DeviceDiscovery.match(endpoint) {
                    LabeledContent("12 Step role", value: match.role.rawValue)
                }
            }
            Section("All Core MIDI properties") {
                Text(endpoint.propertyDump.isEmpty ? "—" : endpoint.propertyDump)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .navigationTitle(endpoint.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button {
                UIPasteboard.general.string = endpoint.propertyDump
            } label: {
                Label("Copy properties", systemImage: "doc.on.doc")
            }
        }
    }
}
