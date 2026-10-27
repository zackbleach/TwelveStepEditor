// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright 2026 Zack Bleach. See LICENSE.md.

import SwiftUI
import TwelveStepKit

extension View {
    /// A simple OK alert driven by an optional message.
    func messageAlert(_ title: String, message: Binding<String?>) -> some View {
        alert(title, isPresented: Binding(get: { message.wrappedValue != nil }, set: { if !$0 { message.wrappedValue = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}

/// The 4-character display as the 12 Step shows it.
struct DisplayPreview: View {
    let text: String
    var font: Font = .system(.title3, design: .monospaced).weight(.semibold)

    var body: some View {
        Text(text.replacingOccurrences(of: " ", with: "\u{2007}"))
            .font(font)
            .foregroundStyle(.red)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.black, in: RoundedRectangle(cornerRadius: 5))
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .accessibilityLabel("Display \(text)")
    }
}

/// A stepper whose lowest value reads "Off" (the desktop's -1 / 0 "off" spin boxes).
struct OffStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var offValue: Int? = nil
    var help: String? = nil

    var body: some View {
        Stepper(value: $value, in: range) {
            LabeledContent { Text(value == offValue ? "Off" : String(value)) } label: { HelpTitle(title, help) }
        }
    }
}

/// A setting's name; with help text, touch and hold it for an explanation.
struct HelpTitle: View {
    let title: String
    let help: String?

    init(_ title: String, _ help: String? = nil) {
        self.title = title
        self.help = help
    }

    var body: some View {
        if let help { Text(title).holdForHelp(title, help) } else { Text(title) }
    }
}

/// Picker over string options with the same spellings as the desktop's menus.
struct OptionPicker: View {
    let title: String
    @Binding var selection: String
    let options: [String]
    var help: String? = nil

    var body: some View {
        // The name sits outside the menu so touch and hold reaches it rather than opening the menu.
        HStack {
            HelpTitle(title, help)
            Spacer(minLength: 8)
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { Text($0).tag($0) }
                if !options.contains(selection) { Text(selection).tag(selection) }
            }
            .labelsHidden()
        }
    }
}

extension Preset {
    var voiceSummary: String {
        Preset.Voice.allCases.compactMap { voice -> String? in
            let settings = self.voice(voice)
            if voice == .b && settings.channel == 0 { return nil }
            let pc = settings.programChange < 0 ? "" : " · PC \(settings.programChange)"
            return "\(voice.rawValue.uppercased()): ch \(settings.channel)\(pc)"
        }.joined(separator: "   ")
    }
}

// MARK: - Touch and hold for help

extension View {
    /// Touch and hold this view to show `text` in a small popover. VoiceOver reads it as a hint.
    /// Attach it to a label, not to a control, so it never competes with the control's own gestures.
    func holdForHelp(_ title: String, _ text: String) -> some View {
        modifier(HoldForHelp(title: title, text: text))
    }
}

private struct HoldForHelp: ViewModifier {
    let title: String
    let text: String
    @State private var showing = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.4) { showing = true }
            .sensoryFeedback(.impact(weight: .light), trigger: showing) { _, new in new }
            .popover(isPresented: $showing, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.headline)
                    Text(text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                }
                .padding()
                .frame(idealWidth: 300, maxWidth: 320)
                .presentationCompactAdaptation(.popover)
            }
            .accessibilityHint(text)
            #if DEBUG
            // -showHelp "<title>": open this help popover on launch (for screenshots).
            .onAppear {
                let arguments = ProcessInfo.processInfo.arguments
                if let index = arguments.firstIndex(of: "-showHelp"), arguments.indices.contains(index + 1), arguments[index + 1] == title {
                    Task { try? await Task.sleep(for: .seconds(1)); showing = true }
                }
            }
            #endif
    }
}
