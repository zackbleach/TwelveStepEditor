// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright 2026 Zack Bleach. See LICENSE.md.

import SwiftUI
import TwelveStepKit

struct MonitorView: View {
    @Environment(AppModel.self) private var model
    @State private var filter: Filter = .all
    @State private var follow = true
    @State private var shareFile: ShareableFile?
    @State private var exportError: String?

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case configuration = "Config"
        case performance = "Performance"
        case problems = "Problems"
        var id: String { rawValue }
    }

    var body: some View {
        @Bindable var session = model.session
        let entries = filtered(session.log.entries)

        VStack(spacing: 0) {
            Picker("Filter", selection: $filter) {
                ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            ScrollViewReader { proxy in
                List(entries) { entry in
                    NavigationLink(value: entry.id) {
                        LogRow(entry: entry)
                    }
                    .id(entry.id)
                }
                .listStyle(.plain)
                .overlay {
                    if entries.isEmpty {
                        ContentUnavailableView("No messages", systemImage: "waveform",
                                               description: Text("Press a key or run a query to see traffic."))
                    }
                }
                .onChange(of: entries.last?.id) { _, last in
                    guard follow, let last else { return }
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }

            if session.log.droppedCount > 0 {
                Text("\(session.log.droppedCount) older entries dropped")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(4)
            }
        }
        .navigationTitle("Monitor")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Int.self) { id in
            if let entry = session.log.entries.first(where: { $0.id == id }) {
                LogEntryDetailView(entry: entry)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                Button {
                    session.isMonitorPaused.toggle()
                } label: {
                    Label(session.isMonitorPaused ? "Resume" : "Pause",
                          systemImage: session.isMonitorPaused ? "play.fill" : "pause.fill")
                }
                Toggle(isOn: $follow) {
                    Label("Follow", systemImage: "arrow.down.to.line")
                }
                .toggleStyle(.button)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button {
                        do {
                            shareFile = ShareableFile(url: try model.writeReportFile())
                        } catch {
                            exportError = error.localizedDescription
                        }
                    } label: {
                        Label("Share diagnostic report…", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        UIPasteboard.general.string = model.makeReport()
                    } label: {
                        Label("Copy diagnostic report", systemImage: "doc.on.doc")
                    }
                    Button {
                        model.printReport()
                    } label: {
                        Label("Print report to Xcode console", systemImage: "terminal")
                    }
                    Button {
                        UIPasteboard.general.string = session.log.exportText()
                    } label: {
                        Label("Copy log only", systemImage: "list.bullet.clipboard")
                    }
                    Divider()
                    Button(role: .destructive) {
                        session.log.clear()
                    } label: {
                        Label("Clear log", systemImage: "trash")
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
            }
        }
        .sheet(item: $shareFile) { file in
            ActivityView(items: [file.url])
        }
        .alert("Export failed", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
    }

    private func filtered(_ entries: [LogEntry]) -> [LogEntry] {
        switch filter {
        case .all: entries
        case .configuration: entries.filter { $0.kind == .configuration }
        case .performance: entries.filter { $0.kind == .performance }
        case .problems: entries.filter { $0.direction == .warning || $0.direction == .error }
        }
    }
}

struct LogRow: View {
    let entry: LogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(DiagnosticLog.timestampFormatter.string(from: entry.timestamp))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(entry.direction.rawValue)
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .foregroundStyle(directionColor)
                KindBadge(kind: entry.kind)
                if let endpoint = entry.endpointName {
                    Text(endpoint).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Text(entry.summary).font(.callout)
            if !entry.bytes.isEmpty {
                HexText(bytes: entry.bytes, lineLimit: 2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var directionColor: Color {
        switch entry.direction {
        case .received: .blue
        case .sent: .purple
        case .info: .secondary
        case .warning: .orange
        case .error: .red
        }
    }
}

struct LogEntryDetailView: View {
    let entry: LogEntry

    var body: some View {
        List {
            Section("Message") {
                LabeledContent("Time", value: DiagnosticLog.timestampFormatter.string(from: entry.timestamp))
                LabeledContent("Direction", value: entry.direction.rawValue)
                LabeledContent("Kind", value: entry.kind.label)
                LabeledContent("Endpoint", value: entry.endpointName ?? "—")
                LabeledContent("Length", value: "\(entry.bytes.count) bytes")
                Text(entry.summary).textSelection(.enabled)
            }
            if !entry.bytes.isEmpty {
                Section("Hex") {
                    HexText(bytes: entry.bytes)
                }
                if entry.bytes.first == 0xF0 {
                    Section("Decoded") {
                        Text(DiagnosticsSession.decode(entry.bytes)).textSelection(.enabled)
                    }
                }
            }
        }
        .navigationTitle("Message")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button {
                UIPasteboard.general.string = DiagnosticLog.format(entry)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
    }
}
