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
            .accessibilityLabel("Display \(text)")
    }
}

/// A stepper whose lowest value reads "Off" (the desktop's -1 / 0 "off" spin boxes).
struct OffStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var offValue: Int? = nil

    var body: some View {
        Stepper(value: $value, in: range) {
            LabeledContent(title, value: value == offValue ? "Off" : String(value))
        }
    }
}

/// Picker over string options with the same spellings as the desktop's menus.
struct OptionPicker: View {
    let title: String
    @Binding var selection: String
    let options: [String]

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(options, id: \.self) { Text($0).tag($0) }
            if !options.contains(selection) { Text(selection).tag(selection) }
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
