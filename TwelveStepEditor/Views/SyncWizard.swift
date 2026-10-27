// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright 2026 Zack Bleach. See LICENSE.md.

import SwiftUI
import TwelveStepKit

/// Walks through sharing presets with the desktop 12 Step Editor:
/// 1. get the free 12 Step Sync app on the Mac and turn sync on there;
/// 2. connect this device to iCloud Drive › 12 Step Editor (a one-time folder pick);
/// 3. done.
/// iOS can't see that folder until it's picked once, which is why step 2 exists.
struct SyncWizard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var page = SyncWizard.initialPage
    @State private var choosingFolder = false
    @State private var problem: String?

    /// Where 12 Step Sync is downloaded from (GitHub releases).
    static let downloadURL = URL(string: "https://github.com/zackbleach/TwelveStepEditor/releases/latest")!

    enum Page: Int, CaseIterable { case mac, connect, done }

    /// DEBUG: `-syncPage connect|done` opens the wizard on that page (for screenshots).
    private static var initialPage: Page {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-syncPage"), arguments.indices.contains(index + 1) {
            return ["connect": .connect, "done": .done][arguments[index + 1]] ?? .mac
        }
        #endif
        return .mac
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if page != .done {
                    StepDots(current: page.rawValue, count: 2)
                        .padding(.top, 8)
                }
                ScrollView {
                    Group {
                        switch page {
                        case .mac: macPage
                        case .connect: connectPage
                        case .done: donePage
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .frame(maxWidth: 520)
                    .frame(maxWidth: .infinity)
                }
                footer
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                    .frame(maxWidth: 520)
            }
            .animation(.default, value: page)
            .toolbar {
                if page != .done {
                    ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() } }
                }
                if page == .connect {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { page = .mac } label: {
                            HStack(spacing: 4) { Image(systemName: "chevron.backward").fontWeight(.semibold); Text("Back") }
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            #if DEBUG
            // -syncPick: press Connect iCloud Folder on open (checks the picker presents from the sheet).
            .onAppear { if ProcessInfo.processInfo.arguments.contains("-syncPick") { choosingFolder = true } }
            #endif
            .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
                if case .success(let folder) = result { connect(folder) }
            }
        }
        .interactiveDismissDisabled(page == .connect && problem != nil)
    }

    // MARK: Pages

    private var macPage: some View {
        VStack(spacing: 20) {
            SyncAppIcon().frame(width: 96, height: 96)
            pageTitle("Get 12 Step Sync on your Mac",
                      "A small, free Mac app that moves the desktop 12 Step Editor's presets into iCloud Drive, so this \(deviceName) can use them too.")
            FreeBadge(text: "Free · no account needed")
            InstructionList(items: [
                "Tap **Send Download Link to Mac** and AirDrop, message or email it to yourself.",
                "On your Mac, open the link and download **12 Step Sync**.",
                "Quit the 12 Step Editor, open 12 Step Sync and click **Turn On iCloud Sync**.",
            ])
        }
    }

    private var connectPage: some View {
        VStack(spacing: 20) {
            SyncDevicesGraphic(size: .large)
                .padding(.vertical, 8)
            pageTitle("Connect this \(deviceName)",
                      "Choose the folder your Mac now shares. You only need to do this once.")
            InstructionList(items: [
                "Tap **Connect iCloud Folder**.",
                "Go to **Browse › iCloud Drive**.",
                "Select **12 Step Editor**, then tap **Open**.",
            ])
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var donePage: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: page)
                .padding(.top, 24)
            pageTitle("You're in sync",
                      "This \(deviceName) and your Mac now share the same presets, setlist and settings.")
            InstructionList(symbol: "lightbulb", items: [
                "Quit the desktop 12 Step Editor while editing here. It doesn't notice changes made elsewhere.",
                "If the desktop editor ever says a file is missing, choose **Exit Application**, never **Factory Default**.",
            ])
        }
    }

    // MARK: Footer buttons

    @ViewBuilder private var footer: some View {
        VStack(spacing: 10) {
            switch page {
            case .mac:
                ShareLink(item: Self.downloadURL,
                          subject: Text("12 Step Sync for Mac"),
                          message: Text("Download 12 Step Sync (free) on your Mac to share presets with the 12 Step app:")) {
                    wideLabel("Send Download Link to Mac", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                Button { page = .connect } label: { wideLabel("I've Turned On Sync") }
                    .buttonStyle(.borderedProminent)
            case .connect:
                Button { problem = nil; choosingFolder = true } label: {
                    wideLabel("Connect iCloud Folder", systemImage: "icloud.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
            case .done:
                Button { dismiss() } label: { wideLabel("Done") }
                    .buttonStyle(.borderedProminent)
            }
        }
        .controlSize(.large)
    }

    private func wideLabel(_ title: String, systemImage: String? = nil) -> some View {
        HStack(spacing: 8) {
            if let systemImage { Image(systemName: systemImage) }
            Text(title).lineLimit(1).minimumScaleFactor(0.8)
        }
        .font(.body.weight(.semibold))
        .frame(maxWidth: .infinity)
    }

    private func pageTitle(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.title2.weight(.bold))
            Text(subtitle).font(.body).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Connecting

    /// Switches to the picked folder. If it isn't a 12 Step Editor folder, goes back to the
    /// on-device presets and explains on the page.
    private func connect(_ folder: URL) {
        let store = model.presets
        store.useFolder(folder)
        if store.contents == nil {
            let reason = store.loadError ?? "It doesn't contain the 12 Step Editor's files."
            store.useOnDeviceFolder()
            problem = "“\(folder.lastPathComponent)” can't be used: \(reason) Check sync is on in 12 Step Sync, then pick iCloud Drive › 12 Step Editor."
        } else {
            problem = nil
            page = .done
        }
    }
}

// MARK: - Pieces

private struct StepDots: View {
    let current: Int
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: index == current ? 22 : 8, height: 8)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}

/// Numbered instructions in a rounded panel.
private struct InstructionList: View {
    var symbol: String? = nil
    let items: [LocalizedStringKey]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Group {
                        if let symbol {
                            Image(systemName: symbol).foregroundStyle(Color.accentColor)
                        } else {
                            Text("\(index + 1)")
                                .font(.footnote.weight(.bold).monospacedDigit())
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Color.accentColor, in: Circle())
                        }
                    }
                    .accessibilityHidden(true)
                    Text(item).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .font(.subheadline)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// The 12 Step Sync Mac app's icon (same drawing as Tools/sync-setup's AppIconView).
struct SyncAppIcon: View {
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size.width
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.05, green: 0.12, blue: 0.2), Color(red: 0.0, green: 0.36, blue: 0.55)],
                                         startPoint: .top, endPoint: .bottom))
                Image(systemName: "icloud.fill")
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(.white)
                    .offset(y: -size * 0.1)
                HStack(spacing: size * 0.025) {
                    ForEach(0..<5) { index in
                        RoundedRectangle(cornerRadius: size * 0.02)
                            .fill(index == 2 ? Color(red: 0, green: 0.682, blue: 0.929) : .white.opacity(0.85))
                            .frame(width: size * 0.1, height: size * 0.16)
                    }
                }
                .offset(y: size * 0.27)
            }
            .shadow(color: .black.opacity(0.15), radius: size * 0.06, y: size * 0.03)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
